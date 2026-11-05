extends RefCounted
## CH15: the plant as Kine PARTS (feature lists of "prim" steps), block level, real scale. The builder takes METRES and writes the records in mm (Kine's unit).
## Every record builds ONE body (the overlap check of ch15_site.gd needs one solid per part). Local frames: y up from grade (+0 m), the reactor centre at the
## origin for the reactor building's parts; every other building is built round its own footprint centre and placed by its Assembly pose.
## Sizes and their sources: docs/CH15_REFERENCE.md sections 6 and 7.

const CONC := [0.72, 0.72, 0.70]
const CONC_D := [0.58, 0.58, 0.57]
const STEEL := [0.56, 0.62, 0.70]
const PRIM := [0.86, 0.12, 0.08]     # the primary circuit (the only red of the plant: the section bar counts it)
const DARK := [0.26, 0.27, 0.29]
const GROUND := [0.47, 0.52, 0.34]
const GRAVEL := [0.62, 0.60, 0.54]
const ROOF := [0.84, 0.85, 0.87]
const CRANE := [0.95, 0.78, 0.10]
const TURB := [0.30, 0.42, 0.55]
const GEN := [0.20, 0.50, 0.30]
const COND := [0.50, 0.55, 0.62]

# reactor building geometry (m)
const R_SPH := 28.0
const T_SPH := 0.03          # drawn at 30 mm, the Angra 2 wall (bar 5)
const Y_SPH := 22.0          # sphere centre above grade
const R_SHIELD := 35.75      # outer, 71.5 m measured
const T_SHIELD := 2.0
const Y_WALL_TOP := 24.25    # the dome springs here; its top at 24.25 + 35.75 = 60
const Y_MAT := -6.0          # mat top
const MAT_T := 3.0
const Y_PIT := -9.0          # the excavation floor
const Y_FILL := 2.0          # top of the concrete fill in the sphere's bowl: the equipment stands on it
const Y_DECK := 14.5
const LOOP_AZ := [45.0, 135.0, 225.0, 315.0]
const R_SG := 13.0
const R_RCP := 9.5
const RCP_DAZ := 22.0
const R_PZR := 12.0
const SG_R := 2.5
const RCP_R := 1.5
const PZR_R := 1.5
const RPV_R := 2.75
const PIPE_R := 0.45


class PB extends RefCounted:
	var name := ""
	var feats: Array = []
	var nb := 0

	func _init(n: String) -> void:
		name = n

	func _add(f: Dictionary) -> void:
		f["id"] = "f%d" % (feats.size() + 1)
		f["name"] = "%s%d" % [String(f["t"]).capitalize(), feats.size() + 1]
		feats.append(f)

	func _mm(v: float) -> float:
		return snappedf(v * 1000.0, 0.001)

	func paint(col: Array) -> void:
		_add({"t": "appear", "body": 0.0, "color": col, "metal": 0.0, "rough": 0.8, "preset": "Custom"})

	func box(x: float, y: float, z: float, w: float, h: float, d: float, op := "new", into := 0) -> void:
		var f := {"t": "prim", "kind": "box", "op": op, "x": _mm(x), "y": _mm(y), "z": _mm(z), "w": _mm(w), "h": _mm(h), "d": _mm(d)}
		_op(f, op, into)

	func cyl(x: float, y: float, z: float, axis: String, r: float, ln: float, op := "new", into := 0) -> void:
		_op({"t": "prim", "kind": "cylinder", "op": op, "x": _mm(x), "y": _mm(y), "z": _mm(z), "axis": axis, "r": _mm(r), "len": _mm(ln)}, op, into)

	func tube(x: float, y: float, z: float, axis: String, r: float, r_in: float, ln: float, op := "new", into := 0) -> void:
		_op({"t": "prim", "kind": "tube", "op": op, "x": _mm(x), "y": _mm(y), "z": _mm(z), "axis": axis, "r": _mm(r), "r_in": _mm(r_in), "len": _mm(ln)}, op, into)

	func cone(x: float, y: float, z: float, axis: String, r: float, r2: float, ln: float, op := "new", into := 0) -> void:
		_op({"t": "prim", "kind": "cone", "op": op, "x": _mm(x), "y": _mm(y), "z": _mm(z), "axis": axis, "r": _mm(r), "r2": _mm(r2), "len": _mm(ln)}, op, into)

	func sphere(x: float, y: float, z: float, r: float, op := "new", into := 0) -> void:
		_op({"t": "prim", "kind": "sphere", "op": op, "x": _mm(x), "y": _mm(y), "z": _mm(z), "r": _mm(r)}, op, into)

	## a hemispherical shell about the y axis: centre height yc, radii ro > ri (m), up = the upper half; a Sketch (front plane) of the quarter annulus + a Revolve
	func hemi_shell(yc: float, ro: float, ri: float, up: bool, op := "new") -> void:
		var sg := 1.0 if up else -1.0
		var c45 := cos(PI / 4.0)
		var pt := func(x: float, y: float) -> Array: return [_mm(x), _mm(y)]
		var ents := [{"k": "line", "a": pt.call(ri, yc), "b": pt.call(ro, yc)},
			{"k": "arc", "a": pt.call(ro, yc), "m": pt.call(ro * c45, yc + sg * ro * c45), "b": pt.call(0.0, yc + sg * ro)},
			{"k": "line", "a": pt.call(0.0, yc + sg * ro), "b": pt.call(0.0, yc + sg * ri)},
			{"k": "arc", "a": pt.call(0.0, yc + sg * ri), "m": pt.call(ri * c45, yc + sg * ri * c45), "b": pt.call(ri, yc)}]
		var sid := "f%d" % (feats.size() + 1)
		feats.append({"t": "sketch", "id": sid, "name": "Sketch%d" % (feats.size() + 1), "plane": "front", "ents": ents, "dims": []})
		var f := {"t": "revolve", "sketch": sid, "axis": "y", "deg": 360.0, "op": op}
		if op == "new":
			nb += 1
		_add(f)

	## hollow body 0 with walls t m, the face towards open removed
	func shell(t: float, open: String) -> void:
		_add({"t": "shell", "body": 0, "thick": _mm(t), "open": open})

	func _op(f: Dictionary, op: String, into: int) -> void:
		if op == "new":
			nb += 1
		else:
			f["into"] = into
		_add(f)

	func rec(seq: int) -> Dictionary:
		return {"version": 1, "name": name, "seq": seq, "features": feats}


static func _done(p: PB, col: Array, seq: int) -> Dictionary:
	p.paint(col)
	return p.rec(seq)


## the azimuth position (x, z) at radius r, angle az degrees (from +x towards +z)
static func at_az(r: float, az: float) -> Vector2:
	return Vector2(r * cos(deg_to_rad(az)), r * sin(deg_to_rad(az)))


# ---------------------------------------------------------------- the site and the reactor building
static func ground() -> Dictionary:
	var p := PB.new("Site ground with the reactor pit")
	p.box(-220, -20, -360, 600, 20, 620)
	p.cyl(0, Y_PIT, 0, "y", 40.0, 10.0, "cut")
	return _done(p, GROUND, 1)


static func base_mat() -> Dictionary:
	var p := PB.new("Reactor building base mat (3 m)")
	p.cyl(0, Y_PIT, 0, "y", 37.0, MAT_T)
	return _done(p, CONC_D, 2)


## the steel containment sphere, 56 m, one half: lower (y < 22) or upper
static func sphere_half(upper: bool) -> Dictionary:
	var p := PB.new("Steel containment sphere 56 m, %s half (WStE 51, 30 mm)" % ("upper" if upper else "lower"))
	# a revolved quarter annulus: the prim route (sphere, cut a sphere, cut a box) replayed to the wrong body in Part for the lower half and the dome
	# (the kernel calls alone give the right volumes: docs/CH15_FEEDBACK.md)
	p.hemi_shell(Y_SPH, R_SPH, R_SPH - T_SPH, upper)
	return _done(p, STEEL, 3 if not upper else 4)


static func fill() -> Dictionary:
	var p := PB.new("Concrete fill in the sphere's bowl")
	p.cyl(0, Y_MAT, 0, "y", R_SPH - T_SPH - 0.01, Y_FILL - Y_MAT)
	p.sphere(0, Y_SPH, 0, R_SPH - T_SPH - 0.01, "intersect")
	return _done(p, CONC, 5)


static func internals() -> Dictionary:
	var p := PB.new("Internal concrete: reactor cavity and operating deck")
	p.tube(0, Y_FILL, 0, "y", 6.0, 3.3, Y_DECK + 1.0 - Y_FILL)
	p.tube(0, Y_DECK, 0, "y", 24.0, 6.0, 1.0, "join")
	for az in LOOP_AZ:
		var c := at_az(R_SG, az)
		p.cyl(c.x, Y_DECK - 0.5, c.y, "y", SG_R + 0.3, 2.0, "cut")
	var pz := at_az(R_PZR, 0.0)
	p.cyl(pz.x, Y_DECK - 0.5, pz.y, "y", PZR_R + 0.3, 2.0, "cut")
	return _done(p, CONC, 6)


static func crane_runway() -> Dictionary:
	var p := PB.new("Polar crane ring runway (on brackets of the steel sphere)")
	p.tube(0, 29.0, 0, "y", 26.3, 25.5, 1.0)
	return _done(p, CRANE, 7)


static func polar_crane() -> Dictionary:
	var p := PB.new("Polar crane, 50 m bridge and trolley")
	p.box(-25, 30.0, -2, 50, 2.5, 4)
	p.box(-2, 32.5, -2, 4, 1.5, 4, "join")
	return _done(p, CRANE, 8)


static func vessel() -> Dictionary:
	var p := PB.new("Reactor pressure vessel (20 MnMoNi 5 5), 5.5 m OD, 12 m")
	p.cyl(0, Y_FILL, 0, "y", RPV_R, 9.25)
	p.sphere(0, Y_FILL + 9.25, 0, RPV_R, "join")
	return _done(p, PRIM, 9)


static func steam_generator(k: int) -> Dictionary:
	var c := at_az(R_SG, LOOP_AZ[k])
	var p := PB.new("Steam generator %d (vertical U-tube, Incoloy 800), 21.5 m" % (k + 1))
	p.cyl(c.x, Y_FILL, c.y, "y", 1.9, 12.0)
	p.cone(c.x, Y_FILL + 12.0, c.y, "y", 1.9, SG_R, 1.5, "join")
	p.cyl(c.x, Y_FILL + 13.5, c.y, "y", SG_R, 5.5, "join")
	p.sphere(c.x, Y_FILL + 19.0, c.y, SG_R, "join")
	return _done(p, PRIM, 10 + k)


static func coolant_pump(k: int) -> Dictionary:
	var c := at_az(R_RCP, LOOP_AZ[k] + RCP_DAZ)
	var p := PB.new("Reactor coolant pump %d, 1190 rpm" % (k + 1))
	p.cyl(c.x, Y_FILL, c.y, "y", RCP_R, 9.0)
	return _done(p, PRIM, 14 + k)


static func pressurizer() -> Dictionary:
	var c := at_az(R_PZR, 0.0)
	var p := PB.new("Pressurizer, 3 m x 14 m")
	p.cyl(c.x, Y_FILL, c.y, "y", PZR_R, 14.0)
	return _done(p, PRIM, 18)


## a straight pipe along local +x from 0 to ln at the local origin (posed by ch15_site.gd)
static func pipe(nm: String, ln: float, seq: int) -> Dictionary:
	var p := PB.new(nm)
	p.cyl(0, 0, 0, "x", PIPE_R, ln)
	return _done(p, PRIM, seq)


static func shield_wall() -> Dictionary:
	var p := PB.new("Concrete shield building, cylinder wall 2 m")
	p.tube(0, Y_MAT, 0, "y", R_SHIELD, R_SHIELD - T_SHIELD, Y_WALL_TOP - Y_MAT)
	return _done(p, CONC, 30)


static func shield_dome() -> Dictionary:
	var p := PB.new("Concrete shield building, hemispherical dome 2 m")
	p.hemi_shell(Y_WALL_TOP, R_SHIELD, R_SHIELD - T_SHIELD, true)
	return _done(p, ROOF, 31)


# ---------------------------------------------------------------- turbine hall (local frame: footprint centre; +x along the shaft, the generator at +x)
const TH_W := 93.0
const TH_D := 50.0
const TH_H := 45.0
const LP_X := [-12.0, 3.0, 18.0]


static func th_mat() -> Dictionary:
	var p := PB.new("Turbine hall foundation mat")
	p.box(-TH_W / 2, 0, -TH_D / 2, TH_W, 1.5, TH_D)
	return _done(p, CONC_D, 40)


static func th_shell() -> Dictionary:
	var p := PB.new("Turbine hall walls and roof, 93 x 50 x 45 m")
	p.box(-TH_W / 2, 1.5, -TH_D / 2, TH_W, TH_H - 1.5, TH_D)
	p.box(-TH_W / 2 + 0.5, 1.0, -TH_D / 2 + 0.5, TH_W - 1.0, TH_H - 1.5, TH_D - 1.0, "cut")
	return _done(p, ROOF, 41)


static func pedestal() -> Dictionary:
	var p := PB.new("Turbine table (pedestal) with the condenser pits")
	p.box(-38, 1.5, -8, 82, 9.5, 16)
	for x in LP_X:
		p.box(x - 5, 1.5, -7, 10, 8, 14, "cut")
	return _done(p, CONC, 42)


static func condenser(k: int) -> Dictionary:
	var p := PB.new("Condenser %d (titanium tubes, seawater)" % (k + 1))
	p.box(float(LP_X[k]) - 5, 1.5, -7, 10, 8, 14)
	return _done(p, COND, 43 + k)


static func hp_turbine() -> Dictionary:
	var p := PB.new("HP turbine (Siemens, 1800 rpm)")
	p.cyl(-35, 13.5, 0, "x", 2.5, 10)
	return _done(p, TURB, 46)


static func lp_turbine(k: int) -> Dictionary:
	var p := PB.new("LP turbine %d" % (k + 1))
	p.cyl(float(LP_X[k]) - 6, 16.0, 0, "x", 5.0, 12)
	return _done(p, TURB, 47 + k)


static func generator() -> Dictionary:
	var p := PB.new("Generator THFF 180/64-18, 1458 MVA, 25 kV, and exciter")
	p.cyl(27, 13.5, 0, "x", 2.5, 15)
	p.cyl(42.5, 13.5, 0, "x", 1.2, 2.0, "join")
	return _done(p, GEN, 50)


static func transformer_yard() -> Dictionary:
	var p := PB.new("Main step-up transformers 3 x 520 MVA and unit auxiliary transformers")
	p.box(-15, 0, -6, 30, 0.5, 12)
	for x in [-10.0, 0.0, 10.0]:
		p.box(x - 2.5, 0.5, -3, 5, 9.5, 6, "join")
	return _done(p, DARK, 51)


static func switchyard() -> Dictionary:
	var p := PB.new("500 kV switchyard (gravel field, portal gantries)")
	p.box(-140, 0, -95, 280, 0.3, 190)
	for x in [-120.0, -60.0, 0.0, 60.0, 120.0]:
		for z in [-90.0, 90.0]:
			p.box(x - 0.5, 0.3, z - 0.5, 1, 29.7, 1, "join")
		p.box(x - 0.5, 29.0, -90.5, 1, 1, 181, "join")
	return _done(p, GRAVEL, 52)


## a plain block building, w x h x d m round its footprint centre
static func block(nm: String, w: float, h: float, d: float, col: Array, seq: int) -> Dictionary:
	var p := PB.new(nm)
	p.box(-w / 2, 0, -d / 2, w, h, d)
	return _done(p, col, seq)
