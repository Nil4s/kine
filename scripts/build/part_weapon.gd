class_name PartWeapon
extends RefCounted
## A PART AS A WEAPON ("Give it to the fighter", Easy Part and Expert Part). register() turns a Part record into a weapon kind "part:<name>"
## in Body.KINDS, so the fighter holds it (Body.weapon_to_hand), the judges read its real numbers (WeaponTorque.profile, WeightFeel,
## WeaponRebound) and WeaponMesh draws its tessellation (node()).
##
## FRAME  The Part's long axis (X: a sword's pommel -> tip) is the weapon's +Y, its butt (knob) at the lowest X of the solid. The Part's Y
##   (a blade's width) lies along the weapon's -X, its Z (the thickness) stays Z: a blade is broad toward +Z, as WeaponMesh draws them.
## MASS  volume x density of the Part's material (rec["material"], default steel; words: steel, aluminium, wood, plastic); a body inside
##   PartTemplates.handle_mat's span (the sword's pommel and grip) takes that material instead (wood).
##   Centre of mass = the mass centroid. k (radius of gyration about the centre of mass, fraction of the length) from the inertia about
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
static var recs := {}     # kind -> the Part record it was made from (s132: a scene file keeps it, so a held Part comes back with its grip)


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


## WEIGHT READOUT (p057): the whole Part's weight if it were made of each material: volume (m3, the kernel's) x density (kg/m3).
## {"wood": kg, "steel": kg, "plastic": kg}, or {} when the Part has no solid. Only a readout: the record is not changed
static func weight_kg(rec: Dictionary) -> Dictionary:
	if not Part.available():
		return {}
	var res := Part.replay(rec, -1, {"props": true})
	var vol := float(res.get("volume", 0.0))
	if vol <= 0.0 or (res.get("props", []) as Array).is_empty():
		return {}
	var out := {}
	for k in ["wood", "steel", "plastic"]:
		out[k] = vol * float(DENSITY[k])
	return out


## registers rec as a weapon kind: Body.KINDS[kind] gets its numbers, meshes[kind] its shape. Returns the kind, or "" when the Part has no solid.
static func register(rec: Dictionary) -> String:
	var mat := material_at(rec)
	var res := Part.replay(rec, -1, {"props": true})
	var mesh: ArrayMesh = res["mesh"]
	var vol := float(res["volume"])
	if mesh == null or vol <= 0.0 or (res["props"] as Array).is_empty():
		return ""
	var hm := PartTemplates.handle_mat(rec)   # [material, last steel feature] of a handle in another material, or []
	var rho: float = DENSITY[mat]
	var bb: AABB = res["aabb"]
	var knob := bb.position.x
	var L := bb.size.x
	var gdir := grip_dir(rec, bb)   # s132: the way the hand's grip axis runs through the Part (X unless Hold here chose the long axis or a face)
	var rw := Basis(Vector3(0, 0, 1), PI * 0.5)   # the Part's frame -> the weapon's frame
	if gdir != Vector3.RIGHT:
		rw = rw * _arc_to_x(gdir)
		var lo := INF
		var hi := -INF
		for v in mesh.get_faces():
			var wy := (rw * v).y
			lo = minf(lo, wy)
			hi = maxf(hi, wy)
		knob = lo
		L = hi - lo
	# the mass centroid, then the inertia about it (summed over the bodies: parallel axis); each body has its own density
	var bodies := _bodies(rec, res, rho, hm)
	var c := Vector3.ZERO
	var m := 0.0
	for b in bodies:
		var w: float = float(b["v"]) * float(b["rho"])
		c += (b["c"] as Vector3) * w
		m += w
	c /= m
	var I := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for b in bodies:
		I = _mix(_mix(I, b["I"], float(b["rho"])), _parallel((b["c"] as Vector3) - c), float(b["v"]) * float(b["rho"]))
	var i_perp := (I.y.y + I.z.z) * 0.5   # the two axes across the length (Part Y and Z), kg m2
	if gdir != Vector3.RIGHT:   # the two axes across the grip axis: (trace - the moment about it) / 2
		i_perp = (I.x.x + I.y.y + I.z.z - gdir.dot(I * gdir)) * 0.5
	var grip := PartTemplates.handle_of(rec)
	var rg := rw * grip
	var picked: bool = (rec.get("grip", []) as Array).size() == 3
	var grip_u := rg.y - knob
	var c_w := rw * c
	var k := sqrt(i_perp / m) / L
	var key := key_of(rec)
	var r_barrel := clampf(0.25 * maxf(bb.size.y, bb.size.z), 0.008, 0.06)
	var mats := mat if hm.is_empty() else "%s, grip %s" % [mat, hm[0]]   # the status line: "steel, grip wood"
	Body.KINDS[key] = {"len": L, "handle": minf(L, grip_u + 0.06), "r_handle": R_HANDLE, "r_barrel": r_barrel, "head": [], "aim": true,
		"grip": "power", "mass": m, "com": (c_w.y - knob) / L, "k": k, "grip_u": grip_u, "parts": _parts(rec, L) if gdir == Vector3.RIGHT else [["body", 0.0, L, "hold"]],
		"knob": knob, "mesh_xf": Transform3D(rw, Vector3(-rg.x if picked else 0.0, -knob, -rg.z if picked else 0.0)), "grip_pick": picked, "material": mats, "com_part": c, "rev": int(revs.get(key, 0)) + 1,
		"src": "the Part %s: %.0f cm long, %.2f kg of %s, the grip %.0f cm from the butt" % [String(rec.get("name", "Part")), L * 100.0, m, mats, grip_u * 100.0]}
	revs[key] = int(Body.KINDS[key]["rev"])
	recs[key] = rec.duplicate(true)
	meshes[key] = mesh
	looks[key] = {"aluminium": "metal", "plastic": "tape", "wood": "wood"}.get(mat, "steel")
	return key


## the Part's bodies as [{"c" centre, "v" volume, "I" inertia about its own centre (density 1), "rho" density}]. A handle in another
## material (hm: [material, last steel feature]) is what the Part adds after that feature: the whole minus the steel part
static func _bodies(rec: Dictionary, res: Dictionary, rho: float, hm: Array) -> Array:
	var full: Array = res["props"]
	if hm.is_empty() or full.size() != 1:
		return full.map(func(p): return {"c": p["center"], "v": p["volume"], "I": p["inertia"], "rho": rho})
	var pre: Array = Part.replay(rec, int(hm[1]), {"props": true})["props"]
	if pre.size() != 1 or float(pre[0]["volume"]) <= 0.0:
		return full.map(func(p): return {"c": p["center"], "v": p["volume"], "I": p["inertia"], "rho": rho})
	var F: Dictionary = full[0]
	var A: Dictionary = pre[0]
	var vA := float(A["volume"])
	var vB := float(F["volume"]) - vA
	var cF: Vector3 = F["center"]
	var cA: Vector3 = A["center"]
	var cB := (cF * float(F["volume"]) - cA * vA) / vB
	# inertia about the whole's centre is additive: the handle's own = the whole's, less the steel's (moved to that centre), moved to its own
	var iA := _mix(A["inertia"], _parallel(cA - cF), vA)
	var iB := _mix(_mix(F["inertia"], iA, -1.0), _parallel(cB - cF), -vB)
	return [{"c": cA, "v": vA, "I": A["inertia"], "rho": rho}, {"c": cB, "v": vB, "I": iB, "rho": float(DENSITY[hm[0]])}]


## the weapon's name for the browser and the viewport: a Part's own name ("sword", "steel bar")
static func name_of(kind: String) -> String:
	return kind.trim_prefix(PREFIX).replace("_", " ")


## a plain-words line about a registered kind (the status line)
static func says(kind: String) -> String:
	if not is_part(kind) or not Body.KINDS.has(kind):   # (the drawing's status calls this for every kind: only a Part has a line here)
		return ""
	var k: Dictionary = Body.KINDS[kind]
	return "%s (%.0f cm, %.2f kg, %s): the grip %.0f cm from the butt" % [name_of(kind), float(k["len"]) * 100.0,
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
	mi.transform = Body.KINDS[kind].get("mesh_xf", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, -float(Body.KINDS[kind]["knob"]), 0)))
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


## s132 HOLD IT HERE: the way the hand's grip axis runs through the Part (its own frame, unit). A record with no "grip_axis" is X (as it
## always was); "long" is the longest side of the solid's box (X on a tie); "face" is the normal of the face Hold here was pressed on
static func grip_dir(rec: Dictionary, bb: AABB) -> Vector3:
	match String(rec.get("grip_axis", "")):
		"long":
			var s := bb.size
			if s.y > s.x + 1e-6 and s.y >= s.z:
				return Vector3.UP
			if s.z > s.x + 1e-6 and s.z > s.y:
				return Vector3.BACK
		"face":
			var n: Array = rec.get("grip_n", [])
			if n.size() == 3 and Vector3(float(n[0]), float(n[1]), float(n[2])).length() > 0.5:
				return Vector3(float(n[0]), float(n[1]), float(n[2])).normalized()
	return Vector3.RIGHT


## the turn that takes d to +X (the shortest way; a half turn about Z when d is -X)
static func _arc_to_x(d: Vector3) -> Basis:
	if d.dot(Vector3.RIGHT) < -0.9999:
		return Basis(Vector3(0, 0, 1), PI)
	return Basis(Quaternion(d, Vector3.RIGHT))


## the records of every Part kind a scene holds: the weapon in the hand now and in each card ({kind: record}); a scene file keeps them
static func held_recs(cards: Array, b: Body) -> Dictionary:
	var out := {}
	var kinds: Array = []
	if b != null and b.wep_on:
		kinds.append(b.wep_kind)
	for c in cards:
		var w: Dictionary = (c.get("pose", {}) as Dictionary).get("weapon", {})
		kinds.append(String(w.get("kind", "")))
	for k in kinds:
		if is_part(String(k)) and recs.has(k):
			out[k] = (recs[k] as Dictionary).duplicate(true)
	return out


## a scene file's held Parts made again from their records (so the kind exists before a card sets it in the hand)
static func restore(held: Dictionary) -> void:
	for k in held:
		if held[k] is Dictionary and not Body.KINDS.has(String(k)):
			register(held[k])
