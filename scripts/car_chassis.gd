class_name CarChassis
extends RefCounted
## VEHICLE, STEP 2 CHASSIS: a steel unibody floor structure generated from the PACKAGE (CarPackage hard points). Taught layout: two side
## sills (rockers) along the wheelbase at the body sides; two front rails from the front crossmember to the firewall, inboard of the front
## wheels (rail centre y = front track / 2 - tyre width / 2 - 60 mm); two rear rails over the rear axle; crossmembers at the front bumper,
## the firewall (behind the front wheels), under the seats (the H-point x), the rear seat and the rear bumper; a floor pan between the sills
## (drawn, not weighed). Every member is a closed box section: w x h x wall (mm). Mass = density x perimeter-area x length, where the
## perimeter-area is 2 t (w + h - 2 t). Bending: I = (w h^3 - (w - 2t)(h - 2t)^3) / 12 (mm^4), E I for the stiffness (N m^2).
## Coordinates (mm): x = across the car (+ = left), y = up (ground = 0), z = from the NOSE (0) back to the tail (L). build_3d flips z
## to the 3D frame (front +Z, centred on the axles midpoint, like CarPackage.build_3d).
## Stored in S.vehicle["chassis"] = {"mat": material name, "g": {group: {"size": word or "Custom", "w", "h", "t"}}} (undo and the file keep it).
## Pure functions (no nodes) except build_3d.

const GROUPS := ["sills", "rails", "cross"]
const GROUP_NAMES := {"sills": "Sills (rockers)", "rails": "Front and rear rails", "cross": "Crossmembers"}
const GROUP_TIPS := {
	"sills": "Sill (rocker): the long side member under the doors, from the front axle to the rear axle",
	"rails": "Rails: the long members of the front (bumper to firewall, inboard of the front wheels) and the rear (over the rear axle)",
	"cross": "Crossmember: a box section across the floor: front bumper, firewall, under the seats, rear seat, rear bumper",
}
const GROUP_COL := {"sills": Color(0.45, 0.9, 0.55), "rails": Color(0.95, 0.55, 0.85), "cross": Color(0.55, 0.8, 1.0)}
const SIZE_WORDS := ["Light", "Normal", "Strong"]
const SIZES := {"Light": [60.0, 40.0, 1.2], "Normal": [80.0, 60.0, 1.5], "Strong": [100.0, 80.0, 2.0]}   # w, h, wall (mm)
## the materials: name, density (kg/m3), Young modulus E (GPa)
const MATS := [["Mild steel", 7850.0, 210.0], ["High-strength steel", 7850.0, 210.0], ["Aluminium", 2700.0, 70.0]]
const BIW_FACTOR := 1.6        # the body in white: the structure x 1.6 for the panels (doors, roof, wings, bonnet, boot)
const NOSE_CM := 40.0          # mm, the front bumper crossmember: behind the nose
const FIREWALL_GAP := 60.0     # mm, the firewall: this far behind the front wheel back edge (the wheel radius from the front axle)
const REAR_SEAT := 800.0       # mm, the rear seat H-point behind the front seat H-point
const RAIL_IN := 60.0          # mm, the front rail centre inboard of the tyre inner face (track / 2 - tyre width / 2 - 60)
const WALL_MIN := 0.8          # mm, the wall limits for typed sections
const WALL_MAX := 6.0
const SIZE_MIN := 20.0
const SIZE_MAX := 300.0


static func sec_of_word(word: String) -> Dictionary:
	var s: Array = SIZES.get(word, SIZES["Normal"])
	return {"size": word, "w": s[0], "h": s[1], "t": s[2]}


## the start: every group Normal, mild steel
static func start() -> Dictionary:
	var g := {}
	for k in GROUPS:
		g[k] = sec_of_word("Normal")
	return {"mat": "Mild steel", "g": g}


## a chassis record, filled in where a key is missing (a file from before the chassis)
static func norm(c: Variant) -> Dictionary:
	var out := start()
	if c is Dictionary:
		var d := c as Dictionary
		if d.get("g") is Dictionary:
			for k in GROUPS:
				if (d["g"] as Dictionary).get(k) is Dictionary:
					out["g"][k] = ((d["g"] as Dictionary)[k] as Dictionary).duplicate()
		if mat_row(String(d.get("mat", ""))).size() > 0:
			out["mat"] = String(d["mat"])
	return out


static func mat_row(name: String) -> Array:
	for r in MATS:
		if r[0] == name:
			return r
	return []


## a section can be built: sizes in range and the wall thinner than half the smaller side
static func valid(w: float, h: float, t: float) -> bool:
	return w >= SIZE_MIN and w <= SIZE_MAX and h >= SIZE_MIN and h <= SIZE_MAX and t >= WALL_MIN and t <= WALL_MAX and t * 2.0 < minf(w, h)


## mass (kg) of a closed box section of w x h x wall (mm) of density rho (kg/m3) and length len (mm)
static func box_mass(w: float, h: float, t: float, rho: float, len_mm: float) -> float:
	var area := 2.0 * t * (w + h - 2.0 * t)   # mm2, the perimeter-area of the closed section
	return rho * area * len_mm * 1e-9


## second moment of area I (mm4) of a closed box section about its bending axis
static func inertia(w: float, h: float, t: float) -> float:
	return (w * pow(h, 3.0) - (w - 2.0 * t) * pow(h - 2.0 * t, 3.0)) / 12.0


## E I (N m2): E in GPa, I in mm4
static func ei(e_gpa: float, i_mm4: float) -> float:
	return e_gpa * i_mm4 * 1e-3


## every member of the structure from the package p and the chassis c: [{id, name, group, lo, hi (Vector3 mm), len (mm along the member),
## mass (kg), I (mm4), EI (N m2), w, h, t}]. Sills and rails run along z; crossmembers along x.
static func members(p: Dictionary, c: Dictionary) -> Array:
	var cc := norm(c)
	var d := CarPackage.derive(p)
	var W := float(d["width"])
	var foh := float(p["front_oh"])
	var wb := float(p["wheelbase"])
	var roh := float(p["rear_oh"])
	var L := foh + wb + roh
	var r := float(d["r"])
	var clr := float(p["clearance"])
	var fl := clr + CarPackage.FLOOR      # the floor top: the seat sits on it
	var tf := float(p["track_f"])
	var tr := float(p["track_r"])
	var tw := float(d["tyre_w"])
	var mat := mat_row(String(cc["mat"]))
	var rho: float = mat[1]
	var e_gpa: float = mat[2]
	var zb := NOSE_CM
	var zfw := foh + r + FIREWALL_GAP
	var zus := foh + float(p["hpt_x"])
	var zrs := zus + REAR_SEAT
	var zrb := L - NOSE_CM
	var out := []
	var sill := cc["g"]["sills"] as Dictionary
	var rail := cc["g"]["rails"] as Dictionary
	var cross := cc["g"]["cross"] as Dictionary
	for s in [1.0, -1.0]:
		var sd := "left" if s > 0.0 else "right"
		var w: float = sill["w"]
		var h: float = sill["h"]
		var t: float = sill["t"]
		var xc: float = s * (W * 0.5 - w * 0.5)
		out.append(_mem("sill_" + sd, "Sill (rocker) " + sd, "sills", Vector3(xc - w * 0.5, fl - h, foh), Vector3(xc + w * 0.5, fl, foh + wb), rho, e_gpa, w, h, t))
	for s in [1.0, -1.0]:
		var sd := "left" if s > 0.0 else "right"
		var w: float = rail["w"]
		var h: float = rail["h"]
		var t: float = rail["t"]
		var xf: float = s * (tf * 0.5 - tw * 0.5 - RAIL_IN)
		out.append(_mem("rail_front_" + sd, "Front rail " + sd, "rails", Vector3(xf - w * 0.5, fl - h, zb), Vector3(xf + w * 0.5, fl, zfw), rho, e_gpa, w, h, t))
		var xr: float = s * (tr * 0.5 - tw * 0.5 - RAIL_IN)
		out.append(_mem("rail_rear_" + sd, "Rear rail " + sd, "rails", Vector3(xr - w * 0.5, fl - h, zrs), Vector3(xr + w * 0.5, fl, zrb), rho, e_gpa, w, h, t))
	var cw: float = cross["w"]
	var ch_h: float = cross["h"]
	var ct: float = cross["t"]
	var span := W * 0.5 - float(sill["w"]) * 0.5    # between the sills centres
	var cms := [["bumper", "front bumper", zb], ["firewall", "firewall", zfw], ["under_seats", "under the seats", zus],
		["rear_seat", "rear seat", zrs], ["rear_bumper", "rear bumper", zrb]]
	for cm in cms:
		var zc: float = cm[2]
		out.append(_mem("cross_" + cm[0], "Crossmember " + cm[1], "cross", Vector3(-span, fl - ch_h, zc - cw * 0.5), Vector3(span, fl, zc + cw * 0.5), rho, e_gpa, cw, ch_h, ct))
	return out


static func _mem(id: String, nm: String, g: String, lo: Vector3, hi: Vector3, rho: float, e_gpa: float, w: float, h: float, t: float) -> Dictionary:
	var along := hi.z - lo.z if g != "cross" else hi.x - lo.x
	var i_mm := inertia(w, h, t)
	return {"id": id, "name": nm, "group": g, "lo": lo, "hi": hi, "len": along, "mass": box_mass(w, h, t, rho, along),
		"I": i_mm, "EI": ei(e_gpa, i_mm), "w": w, "h": h, "t": t}


## the totals: the structure mass, the mass per group, one sill I and E I (the pair E I is twice), the body in white (x 1.6)
static func totals(p: Dictionary, c: Dictionary) -> Dictionary:
	var mem := members(p, c)
	var by := {}
	var mass := 0.0
	var sill_i := 0.0
	var sill_ei := 0.0
	for g in GROUPS:
		by[g] = 0.0
	for m in mem:
		mass += float(m["mass"])
		by[m["group"]] = float(by[m["group"]]) + float(m["mass"])
		if String(m["group"]) == "sills" and sill_i == 0.0:
			sill_i = float(m["I"])
			sill_ei = float(m["EI"])
	return {"mass": mass, "by": by, "count": mem.size(), "sill_I": sill_i, "sill_EI": sill_ei, "sill_EI_pair": 2.0 * sill_ei,
		"biw": mass * BIW_FACTOR}


## the floor pan between the sills (mm): x0..x1 across, z0..z1 from the nose, at the floor top (drawn, not weighed)
static func floor_pan(p: Dictionary, c: Dictionary) -> Dictionary:
	var cc := norm(c)
	var d := CarPackage.derive(p)
	var W := float(d["width"])
	var sw := float((cc["g"]["sills"] as Dictionary)["w"])
	var L := float(p["front_oh"]) + float(p["wheelbase"]) + float(p["rear_oh"])
	return {"x0": -W * 0.5 + sw, "x1": W * 0.5 - sw, "z0": NOSE_CM, "z1": L - NOSE_CM, "y": float(p["clearance"]) + CarPackage.FLOOR}


## the body in white compare line: the real cars body-in-white mass where data/real_cars.json has one WITH a source; else the
## plain words that none is compared
static func biw_compare(p: Dictionary, c: Dictionary) -> String:
	var cls := String(p.get("class", ""))
	var have := []
	for car in CarPackage.class_cars(cls):
		if car.has("biw_mass") and car.has("source") and String(car["source"]) != "":
			have.append(float(car["biw_mass"]))
	var mine := float(totals(p, c)["biw"])
	if have.is_empty():
		return "Body in white %d kg. No real %s body-in-white mass with a source in the data yet: not compared" % [int(round(mine)), CarPackage.class_row(cls)[2]]
	var avg := 0.0
	for v in have:
		avg += v
	avg /= float(have.size())
	return "Body in white %d kg; real %s: %d kg (average of %d with a source)" % [int(round(mine)), CarPackage.class_row(cls)[2], int(round(avg)), have.size()]


## the 3D form (m): the package's own 3D view (CarPackage.build_3d), a box per member (coloured by group) and a thin floor pan
static func build_3d(p: Dictionary, c: Dictionary) -> Node3D:
	var root := CarPackage.build_3d(p)
	root.name = "chassis3d"
	var zc := float(p["front_oh"]) + float(p["wheelbase"]) * 0.5
	var box := Node3D.new()
	box.name = "chassis"
	root.add_child(box)
	for m in members(p, c):
		var lo: Vector3 = m["lo"]
		var hi: Vector3 = m["hi"]
		var mi := MeshInstance3D.new()
		mi.name = "member_" + String(m["id"])
		var bm := BoxMesh.new()
		bm.size = Vector3(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) * 0.001
		mi.mesh = bm
		var z3 := (zc - (lo.z + hi.z) * 0.5) * 0.001
		mi.position = Vector3((lo.x + hi.x) * 0.0005, (lo.y + hi.y) * 0.0005, z3)
		mi.material_override = CarPackage._mat(GROUP_COL[m["group"]])
		box.add_child(mi)
	var fp := floor_pan(p, c)
	var fi := MeshInstance3D.new()
	fi.name = "floor_pan"
	var fb := BoxMesh.new()
	fb.size = Vector3(float(fp["x1"]) - float(fp["x0"]), 0.004, float(fp["z1"]) - float(fp["z0"])) * 0.001
	fi.mesh = fb
	fi.position = Vector3((float(fp["x0"]) + float(fp["x1"])) * 0.0005, float(fp["y"]) * 0.001, (zc - (float(fp["z0"]) + float(fp["z1"])) * 0.5) * 0.001)
	fi.material_override = CarPackage._mat(Color(0.35, 0.37, 0.4), false)
	box.add_child(fi)
	return root
