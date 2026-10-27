class_name CarPackage
extends RefCounted
## VEHICLE, STEP 1 PACKAGE + STEP 6 COMPARE (the course order: packaging first). The car is set by HARD POINTS (mm, or degrees for the
## angles): wheelbase, front and rear wheel spacing ("track"), tyre size ("225/45R17"), nose and tail length ("overhang"), ground
## clearance, the seat's H-point (hip point) height and its distance back from the front axle, the seat back angle, the roof height.
## Everything else is derived here: length, width, height, approach / departure / breakover angles, head room (the seated fighter's own
## size along the seat back). COMPARE: the nearest real car (data/real_cars.json, normalised length / width / height / wheelbase) and
## every metric side by side; a metric more than 10 % off ANY car of the chosen class is red, with plain words why.
## Pure functions (no nodes) except build_3d, which builds the 3D preview from the same numbers only.
## Stored in S.vehicle["package"] (a Dictionary of these keys; undo and the scene file carry it: Vehicle.to_file / from_file).

const TORSO := 560.0    # mm, the seated fighter: H-point up the seat back to the base of the neck (the body's spine)
const NECK := 120.0     # mm, base of the neck to the head's centre-line base
const HEAD := 230.0     # mm, head: chin to crown
const THIGH := 450.0    # mm, H-point to the knee (horizontal: the seat cushion)
const SHIN := 430.0     # mm, knee to the ankle
const PEDAL_H := 90.0   # mm, the ankle's height above the floor (where the foot rests)
const FLOOR := 150.0    # mm, the floor's thickness: the seat base sits on the floor, so H-point above ground = clearance + FLOOR + seat height
const FEET := 100.0     # mm, the heel point must be this far behind the front tyre's radius (the front axle + tyre radius + FEET)
const RED := 0.10       # a metric more than this share off any car of the class is red
const DEFAULT_TYRE := "225/45R17"
const TYRES := ["185/55R15", "205/45R17", "215/50R17", "225/40R18", "225/45R17", "225/60R18", "235/35R19"]
## the chooser: [name on the card, real cars' class (data/real_cars.json), the word for a car of that class in the hints, seat height above the floor (mm), H-point x: back from the front axle (mm)]
## (the H-point x is the driver's hip about 1000-1300 mm behind the front axle centre in C-segment cars: the heel sits behind the front tyre)
const CLASSES := [
	["City", "A city", "city car", 240.0, 1000.0],
	["Hatch", "C hatch", "hatchback", 260.0, 1150.0],
	["Sedan", "C sedan", "sedan", 260.0, 1200.0],
	["SUV", "C SUV", "SUV", 300.0, 1150.0],
	["Roadster", "roadster", "roadster", 200.0, 1250.0],
]
## the sliders and typed fields: [key, label (plain words), tooltip (the engineering term), unit, lo, hi, step]
const PARAMS := [
	["wheelbase", "Wheelbase", "Wheelbase: the distance between the front and rear axles", "mm", 1800.0, 3400.0, 5.0],
	["track_f", "Front wheel spacing", "Front track: the distance between the centres of the front wheels, side to side", "mm", 1200.0, 1900.0, 5.0],
	["track_r", "Rear wheel spacing", "Rear track: the distance between the centres of the rear wheels, side to side", "mm", 1200.0, 1900.0, 5.0],
	["front_oh", "Nose length", "Front overhang: from the front axle to the front bumper", "mm", 500.0, 1200.0, 5.0],
	["rear_oh", "Tail length", "Rear overhang: from the rear axle to the back bumper", "mm", 450.0, 1200.0, 5.0],
	["clearance", "Height off the ground", "Ground clearance: the lowest point under the car, above the ground", "mm", 60.0, 280.0, 5.0],
	["hpt_h", "Seat height above the floor", "Seat height: the H-point (hip point) of the seated fighter, above the car's floor", "mm", 150.0, 450.0, 5.0],
	["hpt_x", "Seat from the front wheel", "H-point x: the hip point's distance back from the front axle centre (the heel point must clear the front tyre)", "mm", 700.0, 1800.0, 5.0],
	["seat_a", "Seat back angle", "Seat back angle: the lean of the seat back from straight up (seat-back recline)", "deg", 10.0, 40.0, 1.0],
	["roof", "Roof height", "Overall height: the roof's height above the ground", "mm", 1100.0, 2000.0, 5.0],
]
## the compare table: [key, label]; the metrics are the real cars' fields (tyre_d is the tyre's diameter in mm)
const METRICS := [
	["length", "Length"], ["width", "Width"], ["height", "Height"], ["wheelbase", "Wheelbase"], ["track_f", "Front wheel spacing"],
	["track_r", "Rear wheel spacing"], ["ground_clearance", "Height off the ground"], ["tyre_d", "Tyre diameter"],
]
## the plain words for a metric under / over the class average: [low word, high word]
const WORDS := {
	"length": ["short", "long"], "width": ["narrow", "wide"], "height": ["low", "high"], "wheelbase": ["short", "long"],
	"track_f": ["narrow", "wide"], "track_r": ["narrow", "wide"], "ground_clearance": ["low", "high"], "tyre_d": ["small", "big"],
}

static var _cars: Array = []


## the real cars (data/real_cars.json, read only): [] when the file is missing
static func cars() -> Array:
	if _cars.is_empty() and FileAccess.file_exists("res://data/real_cars.json"):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/real_cars.json"))
		if d is Dictionary:
			_cars = (d as Dictionary).get("cars", [])
	return _cars


## the class row of the chooser by its name on the card ("Hatch")
static func class_row(cls: String) -> Array:
	for c in CLASSES:
		if c[0] == cls:
			return c
	return CLASSES[1]


## the real cars of a chooser class
static func class_cars(cls: String) -> Array:
	var real: String = class_row(cls)[1]
	var out := []
	for c in cars():
		if String(c["class"]) == real:
			out.append(c)
	return out


## a tyre size "225/45R17" -> {ok, width (mm), aspect (%), rim (in), diameter (mm)}; diameter = rim x 25.4 + 2 x width x aspect / 100
static func tyre(s: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("(?i)^\\s*(\\d{3})\\s*/\\s*(\\d{2})\\s*R\\s*(\\d{2})\\s*$")
	var mt := re.search(s)
	if mt == null:
		return {"ok": false, "width": 0.0, "aspect": 0.0, "rim": 0.0, "diameter": 0.0}
	var w := float(mt.get_string(1))
	var a := float(mt.get_string(2))
	var rim := float(mt.get_string(3))
	return {"ok": true, "width": w, "aspect": a, "rim": rim, "diameter": rim * 25.4 + 2.0 * w * a / 100.0}


## the hard points a chooser class starts from: the averages of its real cars (wheelbase, tracks, clearance, height, length)
static func start(cls: String) -> Dictionary:
	var cc := class_cars(cls)
	if cc.is_empty():
		return {"wheelbase": 2640.0, "track_f": 1540.0, "track_r": 1540.0, "front_oh": 820.0, "rear_oh": 820.0, "clearance": 135.0,
			"hpt_h": 260.0, "hpt_x": 1150.0, "seat_a": 25.0, "roof": 1450.0, "tyre": DEFAULT_TYRE, "class": cls}
	var avg := func(k: String) -> float:
		var s := 0.0
		for c in cc:
			s += float(c[k])
		return s / float(cc.size())
	var L: float = avg.call("length")
	var wb: float = avg.call("wheelbase")
	var oh := roundf((L - wb) * 0.5 / 5.0) * 5.0
	return {"wheelbase": roundf(wb / 5.0) * 5.0, "track_f": roundf(avg.call("track_f") / 5.0) * 5.0,
		"track_r": roundf(avg.call("track_r") / 5.0) * 5.0, "front_oh": oh, "rear_oh": oh,
		"clearance": roundf(avg.call("ground_clearance") / 5.0) * 5.0, "hpt_h": float(class_row(cls)[3]), "hpt_x": float(class_row(cls)[4]),
		"seat_a": 25.0, "roof": roundf(avg.call("height") / 5.0) * 5.0, "tyre": String(cc[0]["tyre"]), "class": cls}


## is the tyre text a size we can read
static func tyre_ok(p: Dictionary) -> bool:
	return bool(tyre(String(p.get("tyre", ""))).get("ok", false))


## every readout from the hard points (mm, degrees): length, width, height, approach, departure, head, breakover, tyre_d, tyre_w, r
static func derive(p: Dictionary) -> Dictionary:
	var t := tyre(String(p.get("tyre", "")))
	if not bool(t["ok"]):
		t = tyre(DEFAULT_TYRE)
	var wb := float(p["wheelbase"])
	var clr := float(p["clearance"])
	var foh := float(p["front_oh"])
	var roh := float(p["rear_oh"])
	var head_stack := (TORSO + NECK + HEAD) * cos(deg_to_rad(float(p["seat_a"])))
	var hpt_h := float(p["hpt_h"])
	var reach := THIGH + sqrt(maxf(0.0, pow(SHIN, 2.0) - pow(hpt_h - PEDAL_H, 2.0)))   # the seated leg along the floor: thigh + shin
	var feet_min := float(t["diameter"]) * 0.5 + FEET
	var heel := float(p["hpt_x"]) - reach                                              # the heel point, back from the front axle
	return {
		"hpt_ground": float(p["clearance"]) + FLOOR + hpt_h,
		"reach": reach,
		"heel": heel,
		"feet_min": feet_min,
		"feet_ok": heel >= feet_min,
		"length": foh + wb + roh,
		"width": maxf(float(p["track_f"]), float(p["track_r"])) + float(t["width"]),
		"height": float(p["roof"]),
		"approach": rad_to_deg(atan(clr / foh)),
		"departure": rad_to_deg(atan(clr / roh)),
		"head": float(p["roof"]) - (clr + FLOOR + hpt_h + head_stack),   # the head above the GROUND (the roof is measured from the ground)
		"breakover": rad_to_deg(2.0 * atan(clr / (wb * 0.5))),
		"tyre_d": float(t["diameter"]),
		"tyre_w": float(t["width"]),
		"r": float(t["diameter"]) * 0.5,
	}


## one metric of yours (the hard points and readouts)
static func value(key: String, d: Dictionary, p: Dictionary) -> float:
	match key:
		"length", "width", "height", "tyre_d":
			return float(d[key])
		"wheelbase", "track_f", "track_r":
			return float(p[key])
		"ground_clearance":
			return float(p["clearance"])
	return 0.0


## one metric of a real car
static func real_value(car: Dictionary, key: String) -> float:
	if key == "tyre_d":
		return float(tyre(String(car["tyre"]))["diameter"])
	if key == "ground_clearance":
		return float(car["ground_clearance"])
	return float(car[key])


## the nearest real car: squared distance over length, width, height, wheelbase, each as a share of the car's own value
static func nearest(p: Dictionary, d: Dictionary) -> Dictionary:
	var best := {}
	var best_v := INF
	for c in cars():
		var s := 0.0
		for k in ["length", "width", "height", "wheelbase"]:
			s += pow(value(k, d, p) / float(c[k]) - 1.0, 2.0)
		if s < best_v:
			best_v = s
			best = c
	return best


## the compare rows: [{key, label, yours, real, diff, red, hint, near}] against the class. red = some class car is more than 10 % off
static func rows(p: Dictionary) -> Array:
	var d := derive(p)
	var cls := String(p.get("class", "Hatch"))
	var cc := class_cars(cls)
	var near := nearest(p, d)
	var out := []
	for mt in METRICS:
		var key: String = mt[0]
		var y := value(key, d, p)
		var rv := real_value(near, key) if not near.is_empty() else 0.0
		var red := false
		var avg := 0.0
		for c in cc:
			var cv := real_value(c, key)
			avg += cv
			if cv > 0.0 and absf(y - cv) / cv > RED:
				red = true
		avg = avg / float(maxi(1, cc.size()))
		var hint := ""
		if red:
			var word: String = WORDS[key][0] if y < avg else WORDS[key][1]
			hint = "%s is %s for a %s" % [String(mt[1]).to_lower(), word, class_row(cls)[2]]
		out.append({"key": key, "label": mt[1], "yours": y, "real": rv, "diff": y - rv, "red": red, "hint": hint,
			"near": String(near.get("name", ""))})
	return out


## the 3D preview from the same numbers (m): the wheels on their axle points, the ground line under them (its top is y = 0), the package
## box, the seated fighter at the H-point and its envelope. The car's front is +Z; the wheel centre is r above the ground (touching it).
## The fighter is one Node3D "fighter" at the hip (the H-point): its +Z is forward (the thighs and feet point to the front axle)
static func build_3d(p: Dictionary) -> Node3D:
	var d := derive(p)
	var s := 0.001
	var root := Node3D.new()
	root.name = "package3d"
	var wb := float(p["wheelbase"]) * s
	var tf := float(p["track_f"]) * s
	var tr := float(p["track_r"]) * s
	var r := float(d["r"]) * s
	var tw := float(d["tyre_w"]) * s
	var L := float(d["length"]) * s
	var W := float(d["width"]) * s
	var H := float(d["height"]) * s
	var zf := wb * 0.5
	var zr := -wb * 0.5
	var gr := MeshInstance3D.new()
	gr.name = "ground"
	var pl := PlaneMesh.new()
	pl.size = Vector2(12.0, 12.0)
	gr.mesh = pl
	gr.material_override = _mat(Color(0.3, 0.32, 0.36))
	root.add_child(gr)
	var gl := MeshInstance3D.new()
	gl.name = "ground_line"
	var gb := BoxMesh.new()
	gb.size = Vector3(0.04, 0.01, L + 2.0)
	gl.mesh = gb
	gl.position = Vector3(0.0, -0.005, 0.0)
	gl.material_override = _mat(Color(0.5, 0.75, 1.0))
	root.add_child(gl)
	var pts := {"fl": Vector3(-tf * 0.5, r, zf), "fr": Vector3(tf * 0.5, r, zf), "rl": Vector3(-tr * 0.5, r, zr), "rr": Vector3(tr * 0.5, r, zr)}
	for k in ["fl", "fr", "rl", "rr"]:
		var w := MeshInstance3D.new()
		w.name = "wheel_" + k
		var cy := CylinderMesh.new()
		cy.top_radius = r
		cy.bottom_radius = r
		cy.height = tw
		w.mesh = cy
		w.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		w.position = pts[k]
		w.material_override = _mat(Color(0.06, 0.06, 0.07))
		root.add_child(w)
	var box := MeshInstance3D.new()
	box.name = "package_box"
	box.mesh = _wire_box(Vector3(-W * 0.5, 0.0, zr - float(p["rear_oh"]) * s), Vector3(W * 0.5, H, zf + float(p["front_oh"]) * s))
	box.material_override = _mat(Color(1.0, 0.79, 0.2), true)
	root.add_child(box)
	# the fighter: one node at the hip (the H-point, above the floor: clearance + floor + seat height); its +Z is the car's forward
	var hpt := Vector3(0.0, float(d["hpt_ground"]) * s, zf - float(p["hpt_x"]) * s)
	var fi := Node3D.new()
	fi.name = "fighter"
	fi.position = hpt
	root.add_child(fi)
	var a := deg_to_rad(float(p["seat_a"]))
	var back := Vector3(0.0, cos(a), -sin(a))
	var torso := back * TORSO * s
	var neck := back * (TORSO + NECK) * s
	var head := back * (TORSO + NECK + HEAD * 0.5) * s
	var knee := Vector3(0.0, 0.0, THIGH * s)
	var dy := float(p["hpt_h"]) - PEDAL_H
	var foot := Vector3(0.0, -dy * s, knee.z + sqrt(maxf(0.0, pow(SHIN, 2.0) - pow(dy, 2.0))) * s)
	_stick(fi, Vector3.ZERO, torso, 0.16, "fighter_torso")
	_stick(fi, torso, neck, 0.05, "fighter_neck")
	_stick(fi, Vector3.ZERO, knee, 0.09, "fighter_thigh")
	_stick(fi, knee, foot, 0.07, "fighter_shin")
	var hd := MeshInstance3D.new()
	hd.name = "fighter_head"
	var sp := SphereMesh.new()
	sp.radius = 0.11
	sp.height = 0.22
	hd.mesh = sp
	hd.position = head
	hd.material_override = _mat(Color(0.85, 0.7, 0.55))
	fi.add_child(hd)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in [Vector3.ZERO, torso, neck, head, knee, foot]:
		lo = lo.min(hpt + v)
		hi = hi.max(hpt + v)
	lo -= Vector3(0.1, 0.1, 0.1)
	hi += Vector3(0.1, 0.1, 0.1)
	var env := MeshInstance3D.new()
	env.name = "occupant_envelope"
	var eb := BoxMesh.new()
	eb.size = hi - lo
	env.mesh = eb
	env.position = (lo + hi) * 0.5
	env.material_override = _mat(Color(0.3, 0.6, 1.0, 0.18), true)
	root.add_child(env)
	return root


static func _stick(parent: Node3D, a: Vector3, b: Vector3, rad: float, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cm := CapsuleMesh.new()
	cm.radius = rad
	cm.height = maxf(a.distance_to(b), 0.01) + 2.0 * rad
	mi.mesh = cm
	mi.position = (a + b) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	mi.material_override = _mat(Color(0.85, 0.7, 0.55))
	parent.add_child(mi)


static func _mat(c: Color, clear := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if clear:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _wire_box(lo: Vector3, hi: Vector3) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	return im