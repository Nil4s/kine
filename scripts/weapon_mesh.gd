class_name WeaponMesh
extends RefCounted
## THE WEAPON'S SHAPE: a low-poly mesh per kind, built in code from primitives (cylinders with 4-12 sides, spheres, boxes).
## One build draws the weapon in the hand (main.gd wep_model, wep2_model) and its library picture (LibraryThumbs.weapon_node).
##
## FRAME: the knob at the origin, +Y from the knob to the tip, so a node set to Body.wep_xform() (the knob's point and the
## weapon's rotation) puts each piece where the old cylinders stood. The grip (the hands), the hit capsules and the tip
## (Body.KINDS, Body.wep_point) are not drawn from here and are unchanged.
##
## Blades lie flat in the XY plane (broad face toward +Z), so seen from the front each blade shows its full width.
## A part's span comes from Body.KINDS "parts" (negative values count from the tip), so the shapes sit on the grip book's parts.

const SHARP := 0.22   # a blade's thickness against its width (the local Z scale of a flat blade)


## the weapon of kind (a Body.KINDS key, or "two_daggers"): one Node3D with the pieces as MeshInstance3D children
static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	if kind == "two_daggers":
		for x in [-0.05, 0.05]:
			var d := build("dagger")
			d.position = Vector3(x, 0.0, 0.0)
			root.add_child(d)
		return root
	var k: Dictionary = Body.KINDS[kind]
	var L := float(k["len"])
	var rh := float(k["r_handle"])
	var rb := float(k["r_barrel"])
	var hd := float(k["handle"])
	var wh := (L + hd) if hd < 0.0 else hd   # main's wep_handle: where the grip ends
	var mt := materials()
	match kind:
		"metal_bat":
			_tube(root, 0.0, 0.03, rh * 1.6, rh * 1.6, mt.tape, 10)   # the knob
			_tube(root, 0.03, wh, rh, rh, mt.tape, 10)                # the taped handle
			_tube(root, wh, L, rh, rb, mt.metal, 12)                  # the barrel swells to the end
			_ball(root, Vector3(0, L - rb, 0), rb, mt.metal)          # the rounded end, its top at the tip
		"staff":
			_tube(root, 0.0, L, rh, rh, mt.wood, 8)
			_tube(root, 0.0, 0.05, 0.02, rh, mt.metal, 8)             # the ferrule
			_tube(root, 0.25, 0.5, rh * 1.6, rh * 1.6, mt.tape, 8)    # the wrapped grip (visual: the hands close on the shaft)
			_tube(root, 0.25, 0.27, rh * 1.8, rh * 1.8, mt.metal, 8)  # the bands at its ends
			_tube(root, 0.48, 0.5, rh * 1.8, rh * 1.8, mt.metal, 8)
			_ball(root, Vector3(0, L - rh, 0), rh, mt.wood)
		"long_hammer":
			var hw := float(k["head"][0])
			var hr := float(k["head"][1])
			_tube(root, 0.0, 0.012, rh * 1.6, rh * 1.6, mt.tape, 8)
			_tube(root, 0.012, L - 0.02, rh, rh, mt.tape, 8)
			_box(root, Vector3(0, L - hr, 0), Vector3(2.0 * hw, 2.0 * hr, 0.07), mt.metal)   # the block across the tip
		"dagger":
			_sword(root, k, 0.07, 0.014, mt)
		"sword":
			_sword(root, k, 0.13, 0.03, mt)
		"longsword":
			_sword(root, k, 0.15, 0.032, mt)
		"katana":
			_katana(root, k, mt)
		"spear":
			_tube(root, 0.0, wh, rh, rh, mt.wood, 8)
			_tube(root, wh, wh + 0.02, 0.02, 0.02, mt.metal, 8)       # the socket collar
			_leaf(root, wh + 0.02, L, 0.05, mt.steel)                 # the leaf-shaped head
		"long_axe":
			var ahw := float(k["head"][0])
			_tube(root, 0.012, wh, rh, rh, mt.tape, 8)                # the haft
			_box(root, Vector3(0, wh + 0.04, 0), Vector3(0.05, 0.09, 0.05), mt.metal)
			_rod(root, Vector3(0, L - 0.08, 0), Vector3(0, L, 0), 0.02, 0.0, mt.metal, 4, 1.0)   # the spike at the top
			for s in [1.0, -1.0]:                                     # two crescent blades, one each side
				var px := [0.13, 0.6, 0.93, 1.0, 0.87, 0.53, 0.13]
				var py := [-0.06, -0.01, -0.02, -0.06, -0.11, -0.115, -0.10]
				for i in px.size() - 1:
					_rod(root, Vector3(s * ahw * px[i], L + py[i], 0), Vector3(s * ahw * px[i + 1], L + py[i + 1], 0),
						0.026, 0.026, mt.steel, 4, 0.35)
		_:
			_tube(root, 0.0, L, rh, rb, mt.metal, 8)                  # an unknown kind: a plain bar, never an empty weapon
	return root


## the span [from, to] of a Body.KINDS part, in metres from the knob (negative values count from the tip)
static func _span(k: Dictionary, part: String) -> Vector2:
	var L := float(k["len"])
	for p in k["parts"]:
		if String(p[0]) == part:
			var a := float(p[1])
			var b := float(p[2])
			return Vector2(a if a >= 0.0 else L + a, b if b >= 0.0 else L + b)
	return Vector2(0.0, 0.0)


## a one-hand or arming sword, a dagger: a pommel, a taped grip, a cross-guard of width gw, a double-edged blade of
## half-width bw to a point
static func _sword(root: Node3D, k: Dictionary, gw: float, bw: float, mt: Dictionary) -> void:
	var rh := float(k["r_handle"])
	var pom := _span(k, "pommel")
	var gr := _span(k, "grip")
	var cr := _span(k, "guard")   # a dagger's guard; a sword's is called "cross"
	if cr.y <= cr.x:
		cr = _span(k, "cross")
	var bl := _span(k, "blade")
	_ball(root, Vector3(0, pom.x + 0.02, 0), 0.022, mt.metal)
	_tube(root, gr.x, gr.y, rh, rh, mt.tape, 8)
	_box(root, Vector3(0, (cr.x + cr.y) * 0.5, 0), Vector3(gw, maxf(cr.y - cr.x, 0.02), 0.035), mt.metal)
	_blade(root, bl.x, bl.y, bw, mt.steel)


## a straight double-edged blade: wide at the guard, a point at the end
static func _blade(root: Node3D, y0: float, y1: float, w: float, mat: Material) -> void:
	var ym := y0 + (y1 - y0) * 0.7
	_rod(root, Vector3(0, y0, 0), Vector3(0, ym, 0), w, w * 0.95, mat, 4, SHARP)
	_rod(root, Vector3(0, ym, 0), Vector3(0, y1, 0), w * 0.95, 0.0, mat, 4, SHARP)


## a katana: a cord-wrapped tsuka, a round tsuba, and a blade that bows out and comes back to the tip on the axis
## (the bow is zero at the guard and at the tip, so the blade's end is where Body.wep_point(len) is)
static func _katana(root: Node3D, k: Dictionary, mt: Dictionary) -> void:
	var rh := float(k["r_handle"])
	var ks := _span(k, "kashira")
	var ts := _span(k, "tsuka")
	var tz := _span(k, "tsuba")
	var bl := _span(k, "blade")
	_tube(root, ks.x, ks.y, rh * 1.3, rh * 1.3, mt.metal, 8)
	_tube(root, ts.x, ts.y, rh, rh, mt.tape, 10)
	_tube(root, tz.x, tz.y, 0.055, 0.055, mt.metal, 14)               # the round tsuba: a disc across the blade
	var n := 6
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a := Vector3(_bow(t0), lerpf(bl.x, bl.y, t0), 0.0)
		var b := Vector3(_bow(t1), lerpf(bl.x, bl.y, t1), 0.0)
		_rod(root, a, b, 0.028 * (1.0 - t0), 0.028 * (1.0 - t1), mt.steel, 4, SHARP)


static func _bow(t: float) -> float:
	return 0.03 * sin(PI * t)


## a leaf-shaped head from y0 to y1: its widest a little past the middle, a point at the end
static func _leaf(root: Node3D, y0: float, y1: float, w: float, mat: Material) -> void:
	var ym := y0 + (y1 - y0) * 0.45
	_rod(root, Vector3(0, y0, 0), Vector3(0, ym, 0), w * 0.3, w, mat, 4, SHARP)
	_rod(root, Vector3(0, ym, 0), Vector3(0, y1, 0), w, 0.0, mat, 4, SHARP)


static func materials() -> Dictionary:
	# lit, not mirrors: a metal that is mostly metallic reflects the dark room and drops out of a picture on that room
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.2, 0.2, 0.22)
	tape.roughness = 0.9
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.8, 0.82, 0.86)
	metal.metallic = 0.35
	metal.roughness = 0.4
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.66, 0.68, 0.72)
	steel.metallic = 0.3
	steel.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.34, 0.2)
	wood.roughness = 0.75
	return {"tape": tape, "metal": metal, "steel": steel, "wood": wood}


## a piece as a MeshInstance3D child of root (named p<index>, so a listing can tell the pieces apart)
static func _put(root: Node3D, mesh: Mesh, mat: Material, t: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "p%d" % root.get_child_count()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = t
	root.add_child(mi)


## a rod from a to b: radius r0 at a, r1 at b, `sides` sides; flat scales its thickness across the blade's plane (1 = round)
static func _rod(root: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, sides := 6, flat := 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-6:
		return
	var y := d / len
	var z := Vector3.BACK - y * y.dot(Vector3.BACK)
	if z.length() < 1e-4:
		z = Vector3.RIGHT - y * y.dot(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z)
	var c := CylinderMesh.new()
	c.height = len
	c.top_radius = r1
	c.bottom_radius = r0
	c.radial_segments = sides
	c.rings = 1
	_put(root, c, mat, Transform3D(Basis(x, y, z * flat), (a + b) * 0.5))


## a tube along the weapon's axis from y0 to y1 (r0 at y0, r1 at y1)
static func _tube(root: Node3D, y0: float, y1: float, r0: float, r1: float, mat: Material, sides := 8) -> void:
	_rod(root, Vector3(0, y0, 0), Vector3(0, y1, 0), r0, r1, mat, sides, 1.0)


static func _ball(root: Node3D, c: Vector3, r: float, mat: Material) -> void:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = 2.0 * r
	sp.radial_segments = 8
	sp.rings = 4
	_put(root, sp, mat, Transform3D(Basis(), c))


static func _box(root: Node3D, c: Vector3, size: Vector3, mat: Material) -> void:
	var bx := BoxMesh.new()
	bx.size = size
	_put(root, bx, mat, Transform3D(Basis(), c))
