class_name Vehicle
extends RefCounted
## VEHICLE (B3): a car is a Part body (PartTemplates "car": a box) and four wheels (PartTemplates "wheel": a revolve of a tyre
## profile about the axle). The axle runs along world X (side to side), the car drives along +Z, the body's +Y is up, the ground is y = 0.
## A wheel turns with the distance it travels on the ground: angle = distance / radius (rolling, no slip). drive() puts the car
## on a walk path (PathWalk.curve: the arc length s, turned to the path's tangent) and turns each wheel by s / radius.
## The scene: a root (position = the car on the ground, yaw = the heading), a body mesh lifted CLEAR above the ground, and four pivots
## at the axle centres; a pivot turns about X, so the wheel rolls with the body.
## NUMBERS (template defaults): body 2400 x 1200 x 500 mm, wheel radius 300 mm, width 200 mm; the body's underside 150 mm up;
## each wheel's inner face 5 mm outside the body's side; the axles 0.33 of the body length fore and aft of its centre.
## Not here: a card on BUILD (build_choose.gd keeps Vehicle greyed: tests/buildchoose_test.gd asserts it), Easy sliders, Expert loft.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const CLEAR := 0.15    # m: the body's underside above the ground
const GAP := 0.005     # m: a wheel's inner face to the body's side
const AXLE_Z := 0.33   # the axles sit this share of the body length fore and aft of the centre


## the distance a wheel of radius r (m) turns through when the car covers dist (m): radians
static func spin(dist: float, r: float) -> float:
	return dist / r


## where the body and the four axles are, from the template numbers (mm in, m out): {"body": Vector3, "wheels": [Vector3 x 4], "r": float}
## wheels: front left, front right, back left, back right (front = +Z). Each wheel's centre is on its axle, at height r (touching the ground)
static func layout(car_p: Dictionary, wheel_p: Dictionary) -> Dictionary:
	var L := float(car_p["body_length"]) * MM
	var W := float(car_p["body_width"]) * MM
	var r := float(wheel_p["radius"]) * MM
	var w := float(wheel_p["width"]) * MM
	var x := W * 0.5 + GAP + w * 0.5
	var z := L * AXLE_Z
	return {"body": Vector3(0.0, CLEAR, 0.0), "r": r, "wheels": [Vector3(-x, r, z), Vector3(x, r, z), Vector3(-x, r, -z), Vector3(x, r, -z)]}


## the car as a scene: {root (Node3D), wheels (Array of pivots)}; meshes come from the Part records (KCad). Without KCad: meshless nodes
static func build_node(car: Dictionary, wheel: Dictionary) -> Node3D:
	var lay := layout(car["easy"]["p"], wheel["easy"]["p"])
	var root := Node3D.new()
	root.name = "vehicle"
	var body := MeshInstance3D.new()
	body.name = "body"
	body.mesh = Part.replay(car)["mesh"]
	body.position = lay["body"]
	root.add_child(body)
	var pivots := []
	for i in 4:
		var pv := Node3D.new()
		pv.name = "wheel%d" % i
		pv.position = lay["wheels"][i]
		var m := MeshInstance3D.new()
		m.mesh = Part.replay(wheel)["mesh"]
		pv.add_child(m)
		root.add_child(pv)
		pivots.append(pv)
	root.set_meta("wheels", pivots)
	root.set_meta("r", lay["r"])
	return root


## the car on path c (PathWalk.curve) once it has covered s metres of it: the root sits on the path at s and faces the tangent;
## each wheel has turned by s / r. Rolling forward turns the wheel about -X (its top moves with the car)
static func drive(root: Node3D, c: Dictionary, s: float) -> float:
	root.position = PathWalk.at(c, s)
	root.rotation.y = PathWalk.heading(c, s)
	var a := spin(s, float(root.get_meta("r")))
	for pv in root.get_meta("wheels"):
		(pv as Node3D).rotation.x = -a
	return a


## KCad solid of a record's single solid (body or wheel), moved by `at` (m). The caller releases it. 0 when KCad is absent
static func solid_at(rec: Dictionary, at: Vector3) -> int:
	var ids: Array = Part.replay(rec, -1, {"keep": true})["ids"]
	if ids.size() != 1:
		for id in ids:
			KCad.release(id)
		return 0
	var moved := KCad.translate(ids[0], at)   # a new shape: the original is ours to release
	KCad.release(ids[0])
	return moved


## the volume (m3) two solids share, from KCad's boolean intersect; 0 when they touch or do not meet
static func overlap(a: int, b: int) -> float:
	var x := KCad.intersect(a, b)
	if x == 0:
		return 0.0
	var v := KCad.volume(x)
	KCad.release(x)
	return v
