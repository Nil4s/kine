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
## EASY (scripts/easy_vehicle.gd, a screen of its own): the car's numbers (length, width, height, wheelbase) and the wheel's radius are
## the template's sliders; "Drive it" runs drive() on drive_path(); "Use in a scene" puts the car in the set as a prop (prop_solids).
## The car body is the BUILD Part record (scene "part"), the wheel is scene "vehicle".wheel; Expert opens the body as a Part.
## Not here: the wheel as its own Expert Part (it has no tab yet), a car that follows a path in STAGE.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const CLEAR := 0.15    # m: the body's underside above the ground
const GAP := 0.005     # m: a wheel's inner face to the body's side
const AXLE_Z := 0.33   # the axles sit this share of the body length fore and aft of the centre


## a new car: {"car": body record, "wheel": wheel record} from the template numbers (car_p, wheel_p: mm, missing = the defaults)
static func make_set(car_p := {}, wheel_p := {}) -> Dictionary:
	return {"car": PartTemplates.make("car", car_p), "wheel": PartTemplates.make("wheel", wheel_p)}


## a file's vehicle: {"wheel": the wheel's Part record} or {} when there is none (the car body is the Part record)
static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary) or not (d as Dictionary).has("wheel"):
		return {}
	var w := Part.from_file((d as Dictionary)["wheel"])
	return {"wheel": w} if w.has("easy") and String(w["easy"].get("t", "")) == "wheel" else {}


## the path the car drives on: a straight 10 m, then a curve to the right (metres, the ground is y = 0)
static func drive_path() -> Dictionary:
	return PathWalk.curve([Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, 12), Vector3(2.5, 0, 14.5), Vector3(7.0, 0, 15.5)])


## the car as a set prop (Props.register_solids): the body box and the four wheel boxes, in the prop's frame (m, centred on the floor)
static func prop_solids(car: Dictionary, wheel: Dictionary) -> Dictionary:
	var lay := layout(car["easy"]["p"], wheel["easy"]["p"])
	var cp: Dictionary = car["easy"]["p"]
	var wp: Dictionary = wheel["easy"]["p"]
	var W := float(cp["body_width"]) * MM
	var L := float(cp["body_length"]) * MM
	var H := float(cp["body_height"]) * MM
	var r := float(wp["radius"]) * MM
	var w := float(wp["width"]) * MM
	var solids := [[lay["body"] + Vector3(0.0, H * 0.5, 0.0), Vector3(W, H, L)]]
	for p in lay["wheels"]:
		solids.append([p, Vector3(w, 2.0 * r, 2.0 * r)])
	return {"solids": solids, "supports": [[CLEAR + H, Vector2.ZERO, Vector2(W, L)]]}   # supports: [height, centre, size] like Props.register


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
	var z := float(car_p["wheelbase"]) * MM * 0.5 if car_p.has("wheelbase") else L * AXLE_Z   # the axles: wheelbase / 2 fore and aft
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
