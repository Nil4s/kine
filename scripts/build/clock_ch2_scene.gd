class_name ClockScene
extends RefCounted
## CH2: the clock as a 3D scene (metres; the model is in mm). Brass wheels, steel arbors / anchor / pendulum rod, a glass-fronted walnut case, a
## studio light rig. build(parent) makes everything; pose(model, wheel_ang, phi) turns the parts to a state of the run.

const MM := 0.001
const BRASS := Color(0.86, 0.62, 0.22)
const STEEL := Color(0.62, 0.64, 0.68)
const WOOD := Color(0.20, 0.10, 0.05)
var gear_nodes := {}     # gear id -> Node3D
var node_of := {}        # named parts
var model: ClockCH2


static func mat_brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = BRASS
	m.metallic = 1.0
	m.roughness = 0.28
	return m


static func mat_steel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = STEEL
	m.metallic = 1.0
	m.roughness = 0.18
	return m


static func mat_wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = WOOD
	m.metallic = 0.0
	m.roughness = 0.45
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	return m


static func mat_glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.07)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.0
	m.roughness = 0.02
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## a flat part: polygon (CCW, mm) extruded from z0 to z0 + th (mm); flat shaded; local origin at the polygon's origin, z0 at the node
static func extrude(poly: PackedVector2Array, th: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	var z1 := th * MM
	for i in range(0, idx.size(), 3):
		for k in [0, 1, 2]:   # bottom faces down, wound the other way
			pass
		var a := poly[idx[i]] * MM
		var b := poly[idx[i + 1]] * MM
		var c := poly[idx[i + 2]] * MM
		st.add_vertex(Vector3(a.x, a.y, z1))
		st.add_vertex(Vector3(b.x, b.y, z1))
		st.add_vertex(Vector3(c.x, c.y, z1))
		st.add_vertex(Vector3(c.x, c.y, 0))
		st.add_vertex(Vector3(b.x, b.y, 0))
		st.add_vertex(Vector3(a.x, a.y, 0))
	var n := poly.size()
	for i in n:
		var p := poly[i] * MM
		var q := poly[(i + 1) % n] * MM
		st.add_vertex(Vector3(p.x, p.y, 0))
		st.add_vertex(Vector3(q.x, q.y, 0))
		st.add_vertex(Vector3(q.x, q.y, z1))
		st.add_vertex(Vector3(p.x, p.y, 0))
		st.add_vertex(Vector3(q.x, q.y, z1))
		st.add_vertex(Vector3(p.x, p.y, z1))
	st.generate_normals()
	return st.commit()


static func circle(r: float, n := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(TAU * i / n) * r)
	return pts


static func ring(r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.from_angle(a0) * r0, Vector2.from_angle(a0) * r1, Vector2.from_angle(a1) * r1, Vector2.from_angle(a1) * r0])


func _mi(parent: Node, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(parent: Node, size_mm: Vector3, c_mm: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size_mm * MM
	return _mi(parent, b, mat, c_mm * MM)


## a steel cylinder along z from z0 to z1 mm at (x, y)
func _arbor(parent: Node, x: float, y: float, z0: float, z1: float, r: float, mat: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r * MM
	c.bottom_radius = r * MM
	c.height = (z1 - z0) * MM
	c.radial_segments = 16
	var mi := _mi(parent, c, mat, Vector3(x, y, (z0 + z1) * 0.5) * MM)
	mi.rotation.x = PI * 0.5


func build(parent: Node3D, m: ClockCH2) -> void:
	model = m
	var brass := mat_brass()
	var steel := mat_steel()
	var wood := mat_wood()
	var mv := Node3D.new()
	mv.name = "Movement"
	parent.add_child(mv)
	node_of["movement"] = mv
	# wheels
	for g in ClockCH2.GEARS:
		var p := ClockCH2.pos_of(g[1])
		var holder := Node3D.new()
		holder.position = Vector3(p.x, p.y, g[4]) * MM
		mv.add_child(holder)
		_mi(holder, extrude(ClockCH2.involute_outline(g[2], g[3]), g[5]), brass)
		gear_nodes[g[0]] = holder
	# escape wheel
	var eh := Node3D.new()
	var ep := ClockCH2.pos_of("E")
	eh.position = Vector3(ep.x, ep.y, ClockCH2.ESC_Z0) * MM
	mv.add_child(eh)
	_mi(eh, extrude(ClockCH2.escape_outline(), ClockCH2.ESC_TH), brass)
	gear_nodes["ESC"] = eh
	# arbors
	for s in ["C", "T", "E", "M"]:
		var p2 := ClockCH2.pos_of(s)
		_arbor(mv, p2.x, p2.y, -2.0, 26.0 if s != "C" and s != "E" else 56.0, 1.6, steel)
	# plates: a back and a front frame (rectangular bars) with a cross bar at each arbor, four pillars
	var frames := [[0.0, 3.0], [26.0, 3.0]]
	for f in frames:
		var z: float = f[0]
		var th: float = f[1]
		for sx in [-66.0, 66.0]:
			_box(mv, Vector3(9, 190, th), Vector3(sx, 35, z + th * 0.5), brass)
		for y in [-50.0, 120.0]:
			_box(mv, Vector3(141, 9, th), Vector3(0, y, z + th * 0.5), brass)
		for y in [0.0, 36.0, 70.0]:
			_box(mv, Vector3(132, 5, th), Vector3(0, y, z + th * 0.5), brass)
	for px in [-66.0, 66.0]:
		for py in [-50.0, 120.0]:
			_arbor(mv, px, py, 3.0, 26.0, 3.5, brass)
	# anchor: pivot arbor, hub and two arms to the blades; the blades are the model's pallet blades
	var ah := Node3D.new()
	var D: float = ClockCH2.anchor_dims()["D"]
	ah.position = Vector3(ep.x, ep.y + D, ClockCH2.ESC_Z0) * MM
	mv.add_child(ah)
	node_of["anchor"] = ah
	_mi(ah, extrude(circle(6.0), ClockCH2.ESC_TH), steel)
	var dd := ClockCH2.anchor_dims()
	var side := 0
	for b in ClockCH2.blade_polys():
		_mi(ah, extrude(b, ClockCH2.ESC_TH), steel)
		# an arm from the hub to the pallet's inner edge, along the middle of the pallet's polar span
		var mid := Vector2.ZERO
		for v in b:
			mid += v
		mid /= b.size()
		var dirv := mid.normalized()
		var perp := Vector2(-dirv.y, dirv.x) * 1.6
		var r1: float = mid.length() - (float(dd["thick"]) * 0.5 if side == 0 else float(dd["thick"]) * 0.5)
		_mi(ah, extrude(PackedVector2Array([dirv * 5.0 - perp, dirv * r1 - perp, dirv * r1 + perp, dirv * 5.0 + perp]), ClockCH2.ESC_TH), steel)
		side += 1
	_arbor(ah, 0.0, 0.0, -34.0, 3.0, 1.6, steel)
	# pendulum behind the back plate
	var pend := Node3D.new()
	pend.position = Vector3(ep.x, ep.y + D, -14.0) * MM
	mv.add_child(pend)
	node_of["pendulum"] = pend
	_box(pend, Vector3(5, ClockCH2.L_PEND, 2.4), Vector3(0, -ClockCH2.L_PEND * 0.5, 0), steel)
	var bob := CylinderMesh.new()
	bob.top_radius = 62.0 * MM
	bob.bottom_radius = 62.0 * MM
	bob.height = 14.0 * MM
	var bm := _mi(pend, bob, brass, Vector3(0, -ClockCH2.L_PEND, 0) * MM)
	bm.rotation.x = PI * 0.5
	_arbor(pend, 0.0, 0.0, -4.0, 3.0, 4.0, brass)
	# chapter rings (minute track round the centre, seconds track round the escape arbor) in front of the movement, hands
	_chapter(mv, Vector2.ZERO, 54.0, 60, 44.0, brass)
	_chapter(mv, Vector2(ep.x, ep.y), 46.0, 60, 40.0, brass)
	node_of["hour"] = _hand(mv, 36.0, 7.0, 47.0, brass)
	node_of["minute"] = _hand(mv, 50.0, 4.0, 50.0, steel)
	var sh := _hand(mv, 42.0, 1.4, 53.0, steel)
	sh.position = Vector3(ep.x, ep.y, 53.0) * MM
	node_of["second"] = sh
	node_of["hour"].position = Vector3(0, 0, 47.0 * MM)
	node_of["minute"].position = Vector3(0, 0, 50.0 * MM)
	# case: walnut trunk and hood, glass front, floor and back wall
	var cx0 := -118.0
	var cx1 := 118.0
	var cy0 := -985.0
	var cy1 := 215.0
	var cz0 := -70.0
	var cz1 := 62.0
	var t := 16.0
	_box(parent, Vector3(t, cy1 - cy0, cz1 - cz0), Vector3(cx0, (cy0 + cy1) * 0.5, (cz0 + cz1) * 0.5), wood)
	_box(parent, Vector3(t, cy1 - cy0, cz1 - cz0), Vector3(cx1, (cy0 + cy1) * 0.5, (cz0 + cz1) * 0.5), wood)
	_box(parent, Vector3(cx1 - cx0, t, cz1 - cz0), Vector3(0, cy1, (cz0 + cz1) * 0.5), wood)
	_box(parent, Vector3(cx1 - cx0, t, cz1 - cz0), Vector3(0, cy0, (cz0 + cz1) * 0.5), wood)
	_box(parent, Vector3(cx1 - cx0, cy1 - cy0, t), Vector3(0, (cy0 + cy1) * 0.5, cz0), wood)
	var frame := mat_wood()
	_box(parent, Vector3(cx1 - cx0, 20, 10), Vector3(0, cy1 - 10, cz1), frame)
	_box(parent, Vector3(cx1 - cx0, 20, 10), Vector3(0, cy0 + 10, cz1), frame)
	_box(parent, Vector3(cx1 - cx0, 20, 10), Vector3(0, -80, cz1), frame)   # the rail between hood and trunk
	_mi(parent, _quad(cx1 - cx0 - 2 * t, cy1 - cy0 - 2 * t), mat_glass(), Vector3(0, (cy0 + cy1) * 0.5, cz1 + 2.0) * MM)
	# floor
	var fl := PlaneMesh.new()
	fl.size = Vector2(6.0, 6.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.10, 0.09)
	fm.roughness = 0.35
	fm.metallic = 0.0
	_mi(parent, fl, fm, Vector3(0, cy0 * MM - 0.01, 0))
	var wall := PlaneMesh.new()
	wall.size = Vector2(6.0, 4.0)
	wall.orientation = PlaneMesh.FACE_Z
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.20, 0.23, 0.28)
	wm.roughness = 0.9
	_mi(parent, wall, wm, Vector3(0, 0.6, (cz0 - 60.0) * MM))


func _quad(w_mm: float, h_mm: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w_mm, h_mm) * MM
	return q


func _chapter(parent: Node, c: Vector2, r: float, n: int, z: float, mat: Material) -> void:
	var node := Node3D.new()
	node.position = Vector3(c.x, c.y, z) * MM
	parent.add_child(node)
	_mi(node, extrude(ring(r - 1.0, r + 0.0, 0.0, 0.0), 1.0) if false else extrude(_annulus(r, r + 1.2), 1.0), mat)
	for i in n:
		var a := TAU * i / n
		var big := (i % 5) == 0
		var l := 5.0 if big else 2.5
		var w := 1.2 if big else 0.6
		var d := Vector2.from_angle(a)
		var nrm := Vector2(-d.y, d.x) * w * 0.5
		var p0 := d * (r - l)
		var p1 := d * r
		_mi(node, extrude(PackedVector2Array([p0 - nrm, p1 - nrm, p1 + nrm, p0 + nrm]), 1.0), mat)


static func _annulus(r0: float, r1: float, n := 72) -> PackedVector2Array:
	# a simple polygon: the outer circle then a thin slit back to the inner circle (so Geometry2D can triangulate it)
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(Vector2.from_angle(TAU * i / n) * r1)
	for i in range(n, -1, -1):
		pts.append(Vector2.from_angle(TAU * i / n) * r0)
	return pts


## a hand pointing to +y at angle 0; the node turns about z
func _hand(parent: Node, length: float, width: float, z: float, mat: Material) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(0, 0, z * MM)
	parent.add_child(node)
	var pts := PackedVector2Array([Vector2(-width * 0.5, -length * 0.18), Vector2(width * 0.5, -length * 0.18), Vector2(width * 0.5, length * 0.6), Vector2(0, length), Vector2(-width * 0.5, length * 0.6)])
	_mi(node, extrude(pts, 1.5), mat)
	return node


## set the parts to a state: wheel_ang = the escape wheel (radians), phi = the pendulum (radians)
func pose(wheel_ang: float, phi: float) -> void:
	model.drive("E", wheel_ang)
	for g in ClockCH2.GEARS:
		(gear_nodes[g[0]] as Node3D).rotation.z = model.shaft_ang[g[1]]
	(gear_nodes["ESC"] as Node3D).rotation.z = wheel_ang
	(node_of["anchor"] as Node3D).rotation.z = phi * float(ClockCH2.anchor_dims()["k"])
	(node_of["pendulum"] as Node3D).rotation.z = phi
	# hands: a hand at angle 0 points to +y (12 o'clock); a clockwise hand turns by a negative angle. The seconds hand is the escape wheel,
	# the minute hand the centre shaft, the hour hand the H shaft, each from its own start (the clock reads 10:09:00 at wheel_ang = 0).
	(node_of["second"] as Node3D).rotation.z = wheel_ang - model.start_angle("E")
	(node_of["minute"] as Node3D).rotation.z = model.shaft_ang["C"] - model.start_angle("C") + deg_to_rad(-54.0)
	(node_of["hour"] as Node3D).rotation.z = model.shaft_ang["H"] - model.start_angle("H") + deg_to_rad(-304.5)
