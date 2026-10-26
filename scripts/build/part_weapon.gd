class_name PartWeapon
extends RefCounted
## A PART AS A WEAPON ("Give it to the fighter", Easy Part and Expert Part). register() turns a Part record into a weapon kind "part:<name>"
## in Body.KINDS, so the fighter holds it (Body.weapon_to_hand), the judges read its real numbers (WeaponTorque.profile, WeightFeel,
## WeaponRebound) and WeaponMesh draws its tessellation (node()).
##
## FRAME  The Part's long axis (X: a sword's pommel -> tip) is the weapon's +Y, its butt (knob) at the lowest X of the solid. The Part's Y
##   (a blade's width) lies along the weapon's -X, its Z (the thickness) stays Z: a blade is broad toward +Z, as WeaponMesh draws them.
## MASS  volume x density of ONE material per Part (rec["material"], default steel; words: steel, aluminium, wood, plastic).
##   Centre of mass = the volume centroid. k (radius of gyration about the centre of mass, fraction of the length) from the inertia about
##   the two axes across the length: k = sqrt(I_perp / m) / L (a uniform rod gives 0.289). Mass properties come from KCad (kernel, density 1).
## GRIP  the template's handle centre (PartTemplates.handle_of) or the Part's origin; "grip_u" = its distance from the butt (m).
##   WeightFeel.grip_of / grip_u_of read it, so the judges swing the weapon about the same point the hand holds.
## HOLD  parts for the grip book: [name, from, to, hold] from the butt (sword: pommel, grip, guard, blade; axe: haft, head; else one body).
## A Part record changes -> register() again: the kind's numbers and its mesh are made anew, and "rev" counts them (main re-draws the shape).

const PREFIX := "part:"
const DEFAULT := "steel"
const DENSITY := {"steel": 7850.0, "aluminium": 2700.0, "wood": 600.0, "plastic": 1050.0}   # kg/m3 (steel, aluminium 6061, pine ~600, ABS ~1050)
const WORDS := {"steel": "steel", "aluminium": "aluminium", "aluminum": "aluminium", "wood": "wood", "plastic": "plastic"}
const R_HANDLE := 0.015
static var meshes := {}   # kind -> ArrayMesh in the Part's frame (metres); node() places it
static var looks := {}    # kind -> the WeaponMesh material name ("steel", "wood", "metal", "tape")
static var revs := {}     # kind -> how many times it was registered (the drawn shape is rebuilt when it changes)


static func is_part(kind: String) -> bool:
	return kind.begins_with(PREFIX)


## the kind of a record: "part:" + its name in lower case, spaces as underscores
static func key_of(rec: Dictionary) -> String:
	return PREFIX + String(rec.get("name", "Part")).strip_edges().to_lower().replace(" ", "_")


## a material from plain words ("Steel", "wood"...): a DENSITY key, or "" when none fits
static func material_of(word: String) -> String:
	return WORDS.get(word.strip_edges().to_lower(), "")


## the record's material (a DENSITY key; steel when unset or unknown)
static func material_at(rec: Dictionary) -> String:
	var m := String(rec.get("material", DEFAULT))
	return m if DENSITY.has(m) else DEFAULT


## registers rec as a weapon kind: Body.KINDS[kind] gets its numbers, meshes[kind] its shape. Returns the kind, or "" when the Part has no solid.
static func register(rec: Dictionary) -> String:
	var mat := material_at(rec)
	var res := Part.replay(rec, -1, {"props": true})
	var mesh: ArrayMesh = res["mesh"]
	var vol := float(res["volume"])
	if mesh == null or vol <= 0.0 or (res["props"] as Array).is_empty():
		return ""
	var rho: float = DENSITY[mat]
	var bb: AABB = res["aabb"]
	var knob := bb.position.x
	var L := bb.size.x
	# the centroid and the inertia about it (density 1, summed over the bodies: parallel axis)
	var c := Vector3.ZERO
	for p in res["props"]:
		c += (p["center"] as Vector3) * float(p["volume"])
	c /= vol
	var I := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for p in res["props"]:
		var d: Vector3 = (p["center"] as Vector3) - c
		I = _mix(_mix(I, p["inertia"], 1.0), _parallel(d), float(p["volume"]))
	var m := vol * rho
	var i_perp := (I.y.y + I.z.z) * 0.5 * rho   # the two axes across the length (Part Y and Z), kg m2
	var grip := PartTemplates.handle_of(rec)
	var grip_u := grip.x - knob
	var k := sqrt(i_perp / m) / L
	var key := key_of(rec)
	var r_barrel := clampf(0.25 * maxf(bb.size.y, bb.size.z), 0.008, 0.06)
	Body.KINDS[key] = {"len": L, "handle": minf(L, grip_u + 0.06), "r_handle": R_HANDLE, "r_barrel": r_barrel, "head": [], "aim": true,
		"grip": "power", "mass": m, "com": (c.x - knob) / L, "k": k, "grip_u": grip_u, "parts": _parts(rec, L),
		"knob": knob, "material": mat, "com_part": c, "rev": int(revs.get(key, 0)) + 1,
		"src": "the Part %s: %.0f cm long, %.2f kg of %s, the grip %.0f cm from the butt" % [String(rec.get("name", "Part")), L * 100.0, m, mat, grip_u * 100.0]}
	revs[key] = int(Body.KINDS[key]["rev"])
	meshes[key] = mesh
	looks[key] = {"aluminium": "metal", "plastic": "tape", "wood": "wood"}.get(mat, "steel")
	return key


## a plain-words line about a registered kind (the status line)
static func says(kind: String) -> String:
	if not is_part(kind) or not Body.KINDS.has(kind):   # (the drawing's status calls this for every kind: only a Part has a line here)
		return ""
	var k: Dictionary = Body.KINDS[kind]
	return "%s (%.0f cm, %.2f kg, %s): the grip %.0f cm from the butt" % [kind.trim_prefix(PREFIX).replace("_", " "), float(k["len"]) * 100.0,
		float(k["mass"]), String(k["material"]), float(k["grip_u"]) * 100.0]


## the drawn shape of a registered kind: the Part's mesh turned into the weapon's frame (a child of the weapon's node)
static func node(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var mi := MeshInstance3D.new()
	mi.name = "part"
	mi.mesh = meshes.get(kind)
	var mt := WeaponMesh.materials()
	mi.material_override = mt.get(String(looks.get(kind, "steel")), mt.steel)
	mi.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, -float(Body.KINDS[kind]["knob"]), 0))
	root.add_child(mi)
	return root


static func _outer(d: Vector3) -> Basis:
	return Basis(d * d.x, d * d.y, d * d.z)


## a + b * f, column by column (Godot's Basis has no + or - between two bases)
static func _mix(a: Basis, b: Basis, f: float) -> Basis:
	return Basis(a.x + b.x * f, a.y + b.y * f, a.z + b.z * f)


## the parallel-axis term of a point at d from the centre: |d|^2 E - d d^T (Godot's Basis has no minus, so it is written out)
static func _parallel(d: Vector3) -> Basis:
	var s := d.length_squared()
	var o := _outer(d)
	return Basis(Vector3(s - o.x.x, -o.x.y, -o.x.z), Vector3(-o.y.x, s - o.y.y, -o.y.z), Vector3(-o.z.x, -o.z.y, s - o.z.z))


## the parts along the weapon, from the butt (GripBook): the template's own parts, else the whole length as one holdable body
static func _parts(rec: Dictionary, L: float) -> Array:
	var e: Dictionary = rec.get("easy", {})
	match String(e.get("t", "")):
		"sword":   # the revolve pommel -124..-104 mm, the grip -106..-2, the guard -6..4, the blade 0..
			return [["pommel", 0.0, 0.02, "hold"], ["grip", 0.02, 0.118, "hold"], ["guard", 0.118, 0.128, "no"], ["blade", 0.128, L, "blade"]]
		"axe":     # the haft from the butt to where the head starts (H - 30 mm)
			var h := (float(e["p"]["handle_length"]) - 30.0) * PartTemplates.MM
			return [["haft", 0.0, h, "hold"], ["head", h, L, "no"]]
	return [["body", 0.0, L, "hold"]]
