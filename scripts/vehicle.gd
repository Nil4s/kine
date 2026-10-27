class_name Vehicle
extends RefCounted
## VEHICLE (B3): a car is a Part body (PartTemplates "car": a box) and four wheels (PartTemplates "wheel": a revolve of a tyre
## profile about the axle). The axle runs along world X (side to side), the car drives along +Z, the body's +Y is up, the ground is y = 0.
## A wheel turns with the distance it travels on the ground: angle = distance / radius (rolling, no slip). drive() puts the car
## on a walk path (PathWalk.curve: the arc length s, turned to the path's tangent) and turns each wheel by s / radius.
## The scene: a root (position = the car on the ground, yaw = the heading), a body mesh lifted CLEAR above the ground, and four pivots
## at the axle centres; a pivot turns about X, so the wheel rolls with the body.
## NUMBERS (template defaults, 73229623): body 4000 x 1750 x 1450 mm (a small hatchback), wheel radius 320 mm, width 200 mm; the body
## stands on the ground and its sills sit at the wheel centre's height; each wheel's centre is on the body's side plane (its tyre sits in
## the arch, which is the radius + 40 mm); the axles are the wheelbase (2500 mm) apart, half fore and aft of the centre.
## EASY (scripts/easy_vehicle.gd, a screen of its own): the car's numbers (length, width, height, wheelbase) and the wheel's radius are
## the template's sliders; "Drive it" runs drive() on drive_path(); "Use in a scene" puts the car in the set as a prop (prop_solids).
## The car body is the BUILD Part record (scene "part"), the wheel is scene "vehicle".wheel; Expert opens the body as a Part.
## Not here: the wheel as its own Expert Part (it has no tab yet), a car that follows a path in STAGE.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const AXLE_Z := 0.33   # the axles sit this share of the body length fore and aft of the centre (when a car has no wheelbase)


## a new car: {"car": body record, "wheel": wheel record} from the template numbers (car_p, wheel_p: mm, missing = the defaults)
static func make_set(car_p := {}, wheel_p := {}) -> Dictionary:
	var cp := car_p.duplicate()
	cp["wheel_r"] = float(wheel_p.get("radius", PartTemplates.defaults("wheel")["radius"]))   # the arches follow the wheel
	return {"car": PartTemplates.make("car", cp), "wheel": PartTemplates.make("wheel", wheel_p)}


## a file's vehicle: {"wheel": the wheel's Part record} (when there is one), {"package": the hard points} (the Package step, carpkg:
## scripts/package_screen.gd) and {"chassis": the chassis record} (step 2, carchassis: scripts/car_chassis.gd, only with a package);
## {} when there is none. The car body is the Part record
static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var out := {}
	if (d as Dictionary).has("wheel"):
		var w := Part.from_file((d as Dictionary)["wheel"])
		if w.has("easy") and String(w["easy"].get("t", "")) == "wheel":
			out["wheel"] = w
	if (d as Dictionary).get("package") is Dictionary and not ((d as Dictionary)["package"] as Dictionary).is_empty():
		out["package"] = ((d as Dictionary)["package"] as Dictionary).duplicate(true)
	if (d as Dictionary).get("chassis") is Dictionary and out.has("package"):   # the chassis (carchassis) belongs to a package
		out["chassis"] = CarChassis.norm((d as Dictionary)["chassis"])
	if (d as Dictionary).get("susp") is Dictionary and out.has("package"):     # the suspension (carsusp) belongs to a package
		out["susp"] = CarSusp.norm((d as Dictionary)["susp"])
	return out


## the file form of a vehicle (the inverse of from_file): what undo and the scene file keep
static func to_file(v: Dictionary) -> Dictionary:
	var out := {}
	if v.has("wheel"):
		out["wheel"] = (v["wheel"] as Dictionary).duplicate(true)
	if v.get("package") is Dictionary and not (v["package"] as Dictionary).is_empty():
		out["package"] = (v["package"] as Dictionary).duplicate(true)
	if v.get("chassis") is Dictionary and out.has("package"):
		out["chassis"] = CarChassis.norm(v["chassis"])
	if v.get("susp") is Dictionary and out.has("package"):
		out["susp"] = CarSusp.norm(v["susp"])
	return out


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
	var solids := [[Vector3(0.0, (r + H) * 0.5, 0.0), Vector3(W, H - r, L)]]   # the body box from the sills (the wheel centre's height) to the roof
	for p in lay["wheels"]:
		solids.append([p, Vector3(w, 2.0 * r, 2.0 * r)])
	return {"solids": solids, "supports": [[H, Vector2.ZERO, Vector2(W, L)]]}   # supports: [height, centre, size] like Props.register


## the distance a wheel of radius r (m) turns through when the car covers dist (m): radians
static func spin(dist: float, r: float) -> float:
	return dist / r


## where the body and the four axles are, from the template numbers (mm in, m out): {"body": Vector3, "wheels": [Vector3 x 4], "r": float}
## the body stands on the ground (its origin). wheels: front left, front right, back left, back right (front = +Z). Each wheel's centre is
## on its axle, at height r (touching the ground), on the body's side plane: the tyre sits in the arch
static func layout(car_p: Dictionary, wheel_p: Dictionary) -> Dictionary:
	var L := float(car_p["body_length"]) * MM
	var W := float(car_p["body_width"]) * MM
	var r := float(wheel_p["radius"]) * MM
	var x := W * 0.5
	var z := float(car_p["wheelbase"]) * MM * 0.5 if car_p.has("wheelbase") else L * AXLE_Z   # the axles: wheelbase / 2 fore and aft
	return {"body": Vector3.ZERO, "r": r, "wheels": [Vector3(-x, r, z), Vector3(x, r, z), Vector3(-x, r, -z), Vector3(x, r, -z)]}


## the car as a scene: {root (Node3D), wheels (Array of pivots)}; meshes come from the Part records (KCad). Without KCad: meshless nodes
static func build_node(car: Dictionary, wheel: Dictionary) -> Node3D:
	var lay := layout(car["easy"]["p"], wheel["easy"]["p"])
	var root := Node3D.new()
	root.name = "vehicle"
	var body := MeshInstance3D.new()
	body.name = "body"
	body.mesh = Part.replay(car)["mesh"]
	body.material_override = body_material(car["easy"]["p"])
	body.position = lay["body"]
	root.add_child(body)
	var pivots := []
	for i in 4:
		var pv := Node3D.new()
		pv.name = "wheel%d" % i
		pv.position = lay["wheels"][i]
		var m := MeshInstance3D.new()
		m.mesh = Part.replay(wheel)["mesh"]
		m.material_override = wheel_material(wheel["easy"]["p"])
		pv.add_child(m)
		root.add_child(pv)
		pivots.append(pv)
	root.set_meta("wheels", pivots)
	root.set_meta("r", lay["r"])
	return root


## MATERIALS (shaders, so the Part's single mesh per body keeps its one solid): the body is amber paint; the glass (by region, above the
## belt line): the side windows (the side faces between the hatch and the windscreen), the windscreen and the rear hatch (the sloped faces).
## The tyre is black with a silver hub (the side faces inside 60 % of the radius).
## The floor is a grid on the ground. The shaders read the mesh's own positions, so they follow every slider.
const BODY_SHADER := "shader_type spatial;
uniform vec4 body_color : source_color = vec4(0.92, 0.55, 0.12, 1.0);
uniform vec4 glass_color : source_color = vec4(0.03, 0.05, 0.07, 1.0);
uniform float belt = 0.8;
uniform float roof = 1.45;
uniform float win_z0 = -1.7;
uniform float win_z1 = 1.0;
varying vec3 lpos;
varying vec3 lnrm;
void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}
void fragment() {
	bool above = lpos.y > belt + 0.03 && lpos.y < roof - 0.05;
	bool side = abs(lnrm.x) > 0.7 && lpos.z > win_z0 && lpos.z < win_z1;
	bool slope = lnrm.y > 0.3 && abs(lnrm.z) > 0.3;
	bool glass = above && (side || slope);
	ALBEDO = glass ? glass_color.rgb : body_color.rgb;
	METALLIC = glass ? 0.0 : 0.5;
	ROUGHNESS = glass ? 0.05 : 0.35;
	SPECULAR = glass ? 0.9 : 0.5;
}
"

const WHEEL_SHADER := "shader_type spatial;
uniform vec4 tyre_color : source_color = vec4(0.05, 0.05, 0.06, 1.0);
uniform vec4 hub_color : source_color = vec4(0.72, 0.74, 0.78, 1.0);
uniform float hub_r = 0.18;
varying vec3 lpos;
varying vec3 lnrm;
void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}
void fragment() {
	bool hub = abs(lnrm.x) > 0.7 && length(lpos.yz) < hub_r;
	ALBEDO = hub ? hub_color.rgb : tyre_color.rgb;
	METALLIC = hub ? 0.9 : 0.0;
	ROUGHNESS = hub ? 0.3 : 0.9;
}
"

const FLOOR_SHADER := "shader_type spatial;
uniform vec4 floor_color : source_color = vec4(0.32, 0.34, 0.38, 1.0);
uniform vec4 line_color : source_color = vec4(0.5, 0.6, 0.75, 1.0);
uniform float cell = 0.5;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 g = wpos.xz / cell;
	vec2 l = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(1e-4));
	float line = 1.0 - clamp(min(l.x, l.y), 0.0, 1.0);
	ALBEDO = mix(floor_color.rgb, line_color.rgb, line * 0.5);
	ROUGHNESS = 0.9;
}
"


static func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## the car body's paint and glass: the belt line, the roof and the glass's z range (m, body frame) from the profile's numbers
static func body_material(cp: Dictionary) -> ShaderMaterial:
	var g := PartTemplates.car_geom(cp)
	var m := _shader_mat(BODY_SHADER)
	m.set_shader_parameter("body_color", Color(0.92, 0.55, 0.12))
	m.set_shader_parameter("belt", float(g["yb"]) * MM)
	m.set_shader_parameter("roof", float(g["H"]) * MM)
	m.set_shader_parameter("win_z0", (float(g["zrh"]) + 100.0) * MM)
	m.set_shader_parameter("win_z1", (float(g["zwb"]) - 100.0) * MM)
	return m


## the tyre (black) with its hub (silver): the hub is 60 % of the wheel's radius
static func wheel_material(wp: Dictionary) -> ShaderMaterial:
	var m := _shader_mat(WHEEL_SHADER)
	m.set_shader_parameter("hub_r", float(wp["radius"]) * Part.MM * 0.6)
	return m


## the ground: a grid of 0.5 m cells
static func floor_material() -> ShaderMaterial:
	return _shader_mat(FLOOR_SHADER)


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
