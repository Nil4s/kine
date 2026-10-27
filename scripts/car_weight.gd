class_name CarWeight
extends RefCounted
## VEHICLE, STEP 4 WEIGHT AND BALANCE: the car's mass list, its axle loads, its left / right split, its centre of gravity and the corner loads.
## Coordinates (mm, the same frame as the chassis and the package): x = LON, the distance rearward from the FRONT axle (the rear axle is at
## x = wheelbase; a point ahead of the front axle is negative); y = lateral, + to the LEFT of the centreline; z = height above the ground.
## The masses (data/car_parts.json: ESTIMATES, each with its note): the chassis members at their own centres (CarChassis.members); the
## suspension links, a solid steel round of the arm radius (CarSusp.ARM_R) x length, at each link midpoint (CarSusp.geo, link_list); the wheels
## and tyres (a per-tyre mass from the size, at each wheel centre); and the PLACEABLE parts: the engine (or the electric drive unit), the battery
## (12 V, or an EV pack on the electric skateboard), the fuel tank (shell + litres x 0.74 kg/L), the seats, the driver (75 kg, or the body's own
## mass when it has one), the passengers (0 to 4, each in a seat slot) and the cargo. Each placeable part has a default position per drive
## layout; a drag moves it (its place is kept in w["at"]).
## Readouts (analyse): W_front = sum(m (wheelbase - x)) / wheelbase and W_rear = sum(m x) / wheelbase (moments about the axles); the total = sum m;
## the left / right split by the lever on each axle's track; the centre of gravity height = sum(m z) / sum(m); the four corner loads (they add to the total).
## Compare (rows): the front axle share and the total mass against data/real_cars.json; red when a class car is more than 10 % off (CarPackage.RED).
## Stored in S.vehicle["weight"] = {"layout": one of LAYOUTS, "fuel_l": litres, "pax": 0 to 4, "cargo_kg": kg, "at": {part id: [x, y, z]}}.
## Pure functions (no nodes) except build_3d.

const LAYOUTS := ["Front engine FWD", "Front engine RWD", "Mid engine", "Rear engine", "Electric skateboard"]
const LAYOUT_TIPS := {
	"Front engine FWD": "Front-wheel drive: the engine sits ahead of the front axle, the fuel tank behind the rear axle",
	"Front engine RWD": "Rear-wheel drive: the engine sits ahead of the front axle, the fuel tank behind the rear axle",
	"Mid engine": "Mid-engine: the engine sits between the seats and the rear axle",
	"Rear engine": "Rear-engine: the engine sits behind the rear axle, the fuel tank at the front",
	"Electric skateboard": "Electric skateboard: a flat pack under the floor between the axles, a drive unit at the rear axle, no fuel tank",
}
const PLACE := ["engine", "battery", "fuel", "seats", "driver", "passengers", "cargo"]   # the placeable parts, in the list order
const PLACE_WORDS := {"engine": "Engine + gearbox", "battery": "Battery", "fuel": "Fuel tank", "seats": "Seats", "driver": "Driver",
	"passengers": "Passengers", "cargo": "Cargo"}
const PLACE_TIPS := {
	"engine": "Engine + gearbox: drag it on the side or top view. Its mass is an estimate",
	"battery": "Battery: a 12 V battery, or an EV pack under the floor on the electric skateboard. Drag it. Estimate",
	"fuel": "Fuel tank: its fill is litres x 0.74 kg. Drag it. Its mass is the tank shell plus the fuel",
	"seats": "Seats: the seat frames of the class, one block. Drag it. Estimate",
	"driver": "Driver: the fighter's own mass when the body has one, else 75 kg. Drag it",
	"passengers": "Passengers: 0 to 4 people, each in a seat position (they sit in the seats, they are not dragged)",
	"cargo": "Cargo: a load in the boot or the bed. Set its mass with the slider, drag it",
}
const BLOCK := {"engine": [600.0, 450.0], "battery": [500.0, 160.0], "fuel": [700.0, 260.0], "seats": [900.0, 420.0],
	"driver": [450.0, 520.0], "pax": [450.0, 520.0], "cargo": [800.0, 380.0]}   # the drawn block: length (lon) x height, mm
const COL := {"engine": Color(1.0, 0.45, 0.2), "battery": Color(0.4, 0.85, 1.0), "fuel": Color(1.0, 0.85, 0.3), "seats": Color(0.7, 0.6, 1.0),
	"driver": Color(0.95, 0.75, 0.55), "pax": Color(0.95, 0.6, 0.45), "cargo": Color(0.6, 0.9, 0.5),
	"chassis": Color(0.45, 0.9, 0.55), "susp": Color(1.0, 0.3, 0.9), "wheel": Color(0.8, 0.8, 0.85)}
const CG_COL := Color(1.0, 0.2, 0.2)
const DATA_PATH := "res://data/car_parts.json"
const REAR_SEAT := 800.0      # mm, the rear seat row behind the front seat H-point (the chassis step uses the same)
const SNAP := 5.0             # mm, a drag snaps to this
const KG_MAX := 300.0         # kg, the cargo slider's top
const PAX_MAX := 4
const BLOCK_ACROSS := 300.0   # mm, the 3D block's width across the car

static var _data: Dictionary = {}


## the data file (read once): {} when missing
static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(DATA_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if d is Dictionary:
			_data = d
	return _data


static func kg(id: String) -> float:
	return float((data().get("parts", {}) as Dictionary).get(id, {}).get("kg", 0.0))


static func part_name(id: String) -> String:
	return String((data().get("parts", {}) as Dictionary).get(id, {}).get("name", id))


static func class_row(cls: String) -> Dictionary:
	var cl: Dictionary = data().get("classes", {})
	return cl.get(cls, cl.get("Hatch", {}))


static func fuel_cap(cls: String) -> float:
	return float(class_row(cls).get("fuel_cap_l", 50.0))


static func seat_count(cls: String) -> int:
	return int(class_row(cls).get("seats", 5))


static func start(p: Dictionary) -> Dictionary:
	return {"layout": LAYOUTS[0], "fuel_l": roundf(fuel_cap(String(p.get("class", "Hatch"))) * 0.5), "pax": 0, "cargo_kg": 0.0, "at": {}}


## a weight record, filled in where a key is missing or junk (a file from before step 4)
static func norm(v: Variant, p: Dictionary) -> Dictionary:
	var out := start(p)
	if v is Dictionary:
		var d := v as Dictionary
		if LAYOUTS.has(String(d.get("layout", ""))):
			out["layout"] = String(d["layout"])
		out["fuel_l"] = clampf(float(d.get("fuel_l", out["fuel_l"])), 0.0, fuel_cap(String(p.get("class", "Hatch"))))
		out["pax"] = clampi(int(d.get("pax", 0)), 0, PAX_MAX)
		out["cargo_kg"] = clampf(float(d.get("cargo_kg", 0.0)), 0.0, KG_MAX)
		if d.get("at") is Dictionary:
			for k in (d["at"] as Dictionary).keys():
				var a: Variant = (d["at"] as Dictionary)[k]
				if a is Array and (a as Array).size() == 3 and PLACE.has(String(k)):
					out["at"][String(k)] = [float(a[0]), float(a[1]), float(a[2])]
	return out


static func is_ev(w: Dictionary) -> bool:
	return String(w.get("layout", "")) == "Electric skateboard"


## the tyre and wheel mass from the size (kg): a per-mm2 figure on width x diameter, plus the rim
static func tyre_kg(p: Dictionary) -> float:
	var d := CarPackage.derive(p)
	return float(data().get("tyre_kg_per_mm2", 0.000067)) * float(d["tyre_w"]) * float(d["tyre_d"]) + float(data().get("rim_kg", 6.0))


## the default position of a placeable part for the layout (x = lon, y = lateral, z = height; mm)
static func default_pos(p: Dictionary, w: Dictionary, id: String) -> Vector3:
	var wb := float(p["wheelbase"])
	var roh := float(p["rear_oh"])
	var clr := float(p["clearance"])
	var d := CarPackage.derive(p)
	var hip := float(d["hip_y"])
	var hg := float(d["hpt_ground"])
	var hx := float(p["hpt_x"])
	var lay := String(w.get("layout", LAYOUTS[0]))
	match id:
		"engine":
			if lay == "Electric skateboard":
				return Vector3(wb, 0.0, clr + 250.0)
			if lay == "Mid engine":
				return Vector3((hx + wb) * 0.5, 0.0, clr + 300.0)
			if lay == "Rear engine":
				return Vector3(wb + 350.0, 0.0, clr + 350.0)
			return Vector3(-400.0, 0.0, clr + 350.0)
		"battery":
			if lay == "Electric skateboard":
				return Vector3(wb * 0.5, 0.0, clr + 80.0)
			return Vector3(-600.0, -300.0, clr + 250.0)
		"fuel":
			if lay == "Rear engine":
				return Vector3(-400.0, 0.0, clr + 200.0)
			return Vector3(wb - 300.0, 0.0, clr + 200.0)
		"seats":
			var rows := 0.0 if seat_count(String(p.get("class", "Hatch"))) <= 2 else REAR_SEAT * 0.5
			return Vector3(hx + rows, 0.0, hg - 60.0)
		"driver":
			return Vector3(hx, hip, hg + 200.0)
		"cargo":
			return Vector3(wb + roh * 0.5, 0.0, clr + 350.0)
	return Vector3.ZERO


## the seat slot of passenger i (0 to 3): front passenger, rear left, rear centre, rear right
static func pax_slot(p: Dictionary, i: int) -> Vector3:
	var d := CarPackage.derive(p)
	var hip := float(d["hip_y"])
	var hx := float(p["hpt_x"])
	var hg := float(d["hpt_ground"])
	var slots := [Vector3(hx, -hip, hg + 200.0), Vector3(hx + REAR_SEAT, hip, hg + 200.0), Vector3(hx + REAR_SEAT, 0.0, hg + 200.0),
		Vector3(hx + REAR_SEAT, -hip, hg + 200.0)]
	return slots[clampi(i, 0, slots.size() - 1)]


## a placeable part's position: its dragged place, else the layout's default
static func pos_of(p: Dictionary, w: Dictionary, id: String) -> Vector3:
	var at: Dictionary = w.get("at", {})
	if at.has(id):
		var a: Array = at[id]
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return default_pos(p, w, id)


## a point kept inside the package box (x from the front axle, y across, z up), snapped to SNAP mm
static func clamp_pos(p: Dictionary, v: Vector3) -> Vector3:
	var d := CarPackage.derive(p)
	var foh := float(p["front_oh"])
	var L := float(d["length"])
	var W := float(d["width"])
	var H := float(d["height"])
	var x := clampf(snappedf(v.x, SNAP), -foh, L - foh)
	var y := clampf(snappedf(v.y, SNAP), -W * 0.5, W * 0.5)
	var z := clampf(snappedf(v.z, SNAP), 0.0, H)
	return Vector3(x, y, z)


## the mass list: [{id, name, kind (chassis, susp, wheel, part), kg, x, y, z, placeable, w, h}] (kg; mm)
static func items(p: Dictionary, c: Dictionary, susp: Dictionary, w: Dictionary) -> Array:
	var out := []
	var foh := float(p["front_oh"])
	var wb := float(p["wheelbase"])
	var d := CarPackage.derive(p)
	var r := float(d["r"])
	# the chassis: each member at its own centre (its z is from the nose, so x from the front axle = z - front overhang)
	for m in CarChassis.members(p, c):
		var lo: Vector3 = m["lo"]
		var hi: Vector3 = m["hi"]
		out.append({"id": String(m["id"]), "name": String(m["name"]), "kind": "chassis", "kg": float(m["mass"]),
			"x": (lo.z + hi.z) * 0.5 - foh, "y": (lo.x + hi.x) * 0.5, "z": (lo.y + hi.y) * 0.5, "placeable": false, "w": 0.0, "h": 0.0})
	# the suspension: each link (not a pivot) at its midpoint, a solid steel round of CarSusp.ARM_R radius x its length
	var g := CarSusp.geo(p, c, CarSusp.norm(susp))
	var rho := float(data().get("steel_density", 7850.0))
	var area := PI * pow(CarSusp.ARM_R * 1000.0, 2.0)
	for ax in ["front", "rear"]:
		var cn: Dictionary = g[ax]
		var po := CarSusp.pose(cn, 0.0)
		for sd in [1.0, -1.0]:
			for lk in CarSusp.link_list(cn, po, sd):
				if String(lk["type"]) == "pivot":
					continue
				var a: Vector3 = lk["a"]
				var b: Vector3 = lk["b"]
				var mid := (a + b) * 0.5
				out.append({"id": "%s_%s_%s" % [ax, "L" if sd > 0.0 else "R", String(lk["name"])], "name": "Suspension link", "kind": "susp",
					"kg": area * a.distance_to(b) * rho * 1e-9, "x": -mid.x, "y": mid.y, "z": mid.z, "placeable": false, "w": 0.0, "h": 0.0})
	# the wheels and tyres: one per corner, at the wheel centre
	var tf := float(p["track_f"])
	var tr := float(p["track_r"])
	var tk := tyre_kg(p)
	for sd in [1.0, -1.0]:
		var sn := "L" if sd > 0.0 else "R"
		out.append({"id": "wheel_F" + sn, "name": "Wheel and tyre", "kind": "wheel", "kg": tk, "x": 0.0, "y": sd * tf * 0.5, "z": r,
			"placeable": false, "w": 0.0, "h": 0.0})
		out.append({"id": "wheel_R" + sn, "name": "Wheel and tyre", "kind": "wheel", "kg": tk, "x": wb, "y": sd * tr * 0.5, "z": r,
			"placeable": false, "w": 0.0, "h": 0.0})
	# the placeable parts
	var cls := String(p.get("class", "Hatch"))
	var ev := is_ev(w)
	out.append(_part("engine", part_name("drive_unit" if ev else "engine"), kg("drive_unit" if ev else "engine"), w, p))
	if ev:
		out.append(_part("battery", part_name("ev_pack"), kg("ev_pack"), w, p))
	else:
		out.append(_part("battery", part_name("battery_12v"), kg("battery_12v"), w, p))
		out.append(_part("fuel", "Fuel tank", float(data().get("tank_shell_kg", 8.0)) + float(data().get("fuel_kg_per_l", 0.74)) * float(w["fuel_l"]), w, p))
	var nseats := seat_count(cls)
	out.append(_part("seats", "Seats (%d)" % nseats, kg("seat") * nseats, w, p))
	out.append(_part("driver", "Driver", float(data().get("driver_kg", 75.0)), w, p))
	for i in int(w["pax"]):
		var q := pax_slot(p, i)
		out.append({"id": "pax_%d" % (i + 1), "name": "Passenger %d" % (i + 1), "kind": "part", "kg": float(data().get("passenger_kg", 75.0)),
			"x": q.x, "y": q.y, "z": q.z, "placeable": false, "w": BLOCK["pax"][0], "h": BLOCK["pax"][1]})
	out.append(_part("cargo", "Cargo", float(w["cargo_kg"]), w, p))
	return out


static func _part(id: String, nm: String, m: float, w: Dictionary, p: Dictionary) -> Dictionary:
	var v := pos_of(p, w, id)
	var b: Array = BLOCK[id]
	return {"id": id, "name": nm, "kind": "part", "kg": m, "x": v.x, "y": v.y, "z": v.z, "placeable": true, "w": b[0], "h": b[1]}


## the readouts of a mass list (see the header): total, the axle loads, the left / right split, the centre of gravity, the corners
static func analyse(list: Array, p: Dictionary) -> Dictionary:
	var wb := float(p["wheelbase"])
	var tf := float(p["track_f"])
	var tr := float(p["track_r"])
	var tot := 0.0
	var front := 0.0
	var rear := 0.0
	var mx := 0.0
	var my := 0.0
	var mz := 0.0
	var c := {"fl": 0.0, "fr": 0.0, "rl": 0.0, "rr": 0.0}
	for it in list:
		var m := float(it["kg"])
		var x := float(it["x"])
		var y := float(it["y"])
		tot += m
		mx += m * x
		my += m * y
		mz += m * float(it["z"])
		var fw := m * (wb - x) / wb      # the front axle's share (moments about the rear axle)
		var rw := m * x / wb             # the rear axle's share
		front += fw
		rear += rw
		c["fl"] += fw * (tf * 0.5 + y) / tf
		c["fr"] += fw * (tf * 0.5 - y) / tf
		c["rl"] += rw * (tr * 0.5 + y) / tr
		c["rr"] += rw * (tr * 0.5 - y) / tr
	var left := float(c["fl"]) + float(c["rl"])
	var t := maxf(tot, 0.000001)
	return {"total": tot, "front": front, "rear": rear, "front_split": front / t, "left": left, "right": tot - left,
		"left_split": left / t, "cg_x": mx / t, "cg_y": my / t, "cg_z": mz / t, "corners": c, "count": list.size()}


## the step's readouts from the car: analyse(items(...))
static func summary(p: Dictionary, c: Dictionary, susp: Dictionary, w: Dictionary) -> Dictionary:
	return analyse(items(p, c, susp, w), p)


## the compare rows: [{key, label, yours, real, red, hint, n}] for the front axle share and the total mass against the class
## (red when a class car is more than CarPackage.RED off)
static func compare(p: Dictionary, s: Dictionary) -> Array:
	var cls := String(p.get("class", "Hatch"))
	var cc := CarPackage.class_cars(cls)
	var out := []
	for row in [["front_split", "Front axle share", float(s["front_split"])], ["mass", "Total mass", float(s["total"])]]:
		var key: String = row[0]
		var y: float = row[2]
		var red := false
		var avg := 0.0
		for car in cc:
			var cv := float(car[key])
			avg += cv
			if cv > 0.0 and absf(y - cv) / cv > CarPackage.RED:
				red = true
		avg = avg / float(maxi(1, cc.size()))
		var hint := ""
		if red and not cc.is_empty():
			var word := "high" if y > avg else "low"
			if key == "front_split":
				hint = "front axle share is %s for a %s" % [word, CarPackage.class_row(cls)[2]]
			else:
				hint = "total mass is %s for a %s%s" % [word, CarPackage.class_row(cls)[2], " (the body panels come in step 5 and are not in this total yet)" if y < avg else ""]
		out.append({"key": key, "label": row[1], "yours": y, "real": avg, "red": red, "hint": hint, "n": cc.size()})
	return out


## the 3D blocks: every placeable part as a box at its place, and the centre of gravity as a sphere. Built like CarChassis.build_3d:
## front +Z, the axles midpoint at the origin, metres. A block: across BLOCK_ACROSS, its height, its length along z
static func build_3d(p: Dictionary, c: Dictionary, susp: Dictionary, w: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "weight3d"
	var wb := float(p["wheelbase"])
	var list := items(p, c, susp, w)
	var s := analyse(list, p)
	for it in list:
		if not bool(it["placeable"]):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "part_" + String(it["id"])
		var bm := BoxMesh.new()
		bm.size = Vector3(BLOCK_ACROSS, float(it["h"]), float(it["w"])) * 0.001
		mi.mesh = bm
		mi.position = _to3(Vector3(float(it["x"]), float(it["y"]), float(it["z"])), wb)
		mi.material_override = CarPackage._mat(COL.get(String(it["id"]).split("_")[0], Color(0.8, 0.8, 0.8)))
		root.add_child(mi)
	var sph := MeshInstance3D.new()
	sph.name = "cg"
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	sph.mesh = sm
	sph.position = _to3(Vector3(float(s["cg_x"]), float(s["cg_y"]), float(s["cg_z"])), wb)
	sph.material_override = CarPackage._mat(CG_COL)
	root.add_child(sph)
	return root


## a point of the car (mm: x from the front axle, y left, z up) in the 3D frame (m)
static func _to3(v: Vector3, wb: float) -> Vector3:
	return Vector3(v.y, v.z, wb * 0.5 - v.x) * 0.001

