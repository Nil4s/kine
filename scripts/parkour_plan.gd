## parkour_plan.gd - CH7b: the 8 s chained run, planned CONTACTS FIRST (see parkour.gd for the engine that poses it).
##
## Order of work (docs/CH7B_CONTACTS.md):
##   1 the CONTACT SCHEDULE: which foot / palm touches which point of which obstacle, over which window (schedule() lists it)
##   2 the pelvis ROOT is solved from the contacts: z by anchors (a palm plant puts the shoulder over the palm, a landing puts the
##     ankle ahead of the hip), y by the leg and arm reach at each contact and by BALLISTIC FLIGHT between them (g = 9.81, a
##     parabola through the pelvis, which stands in for the centre of mass: the pelvis joint is the hip-level body centre)
##   3 the free limbs run between their contacts (swings and tucks, held clear of the obstacles)
## Every contact is a hard constraint in the engine: a stance foot is planted (the pelvis lowers, never the foot), a palm is
## placed on its point and the miss reported. Nothing is lifted to clear a penetration any more (P["lift"] = false).
##
## Units: metres, +y up, +z the way he runs, +x his left. Y0 = the roof's top over the street.
class_name ParkourPlan
extends RefCounted

const Y0 := Parkour.Y0
const G := 9.81
const BALL := 0.0152          # a flat foot's toe base above the surface (Body p0 ball y)
const ANKLE_H := 0.1037       # ankle height over the sole's surface when the foot is flat
const HIP_DZ := 0.0515        # the hip joint is this far ahead of the pelvis joint (rest pose)
const HIP_DY := 0.0155        # ... and this far above it
const HIP_DX := 0.089
const FOOT_DZ := 0.149        # ball ahead of the ankle on a flat foot
const LEG := 0.828            # thigh 0.400 + calf 0.428 (data/skeleton.json)
const LEG_USE := 0.97         # the longest hip-to-ankle distance a planned stance uses (a leg keeps a hair of bend)
const HIP_MID := 0.78         # pelvis height at mid-stance in a run (m over the roof)
const H_TD := 0.30            # a landing puts the ankle this far ahead of the hip at touchdown
const A_LAND := 4.0 * G       # mean pelvis deceleration in a landing's absorption (4 g, a parkour landing)
const WALL_X := 0.8
const DEPTH_SOLE := 0.104     # ankle to sole (m): a foot on a wall has its ankle this far off it
const TOE_STAND := 0.13       # the toe base this far off a wall face (ankle stops at 25 deg)
const PALM_Y := 0.017         # the palm point's height over a surface the hand lies flat on (axis 0.047 less the 0.03 palm drop)
const PALM_WRIST := 0.073     # wrist to palm point along the flat hand (0.6 of the hand bone)
const ARM_CH := 0.50          # shoulder-to-wrist distance of a slightly bent arm in support (arm 0.547)
const LEDGE_Z := 21.2
const SH := Vector3(0.19, 0.524, -0.015)   # shoulder from the pelvis joint in the rest pose


static func obstacles() -> Array:
	return [
		{"name": "roofA", "lo": Vector3(-3, 0, -8), "hi": Vector3(3, Y0, 14.3)},
		{"name": "boxSpeed", "lo": Vector3(-1.5, Y0, 5.0), "hi": Vector3(1.5, Y0 + 0.8, 5.6)},
		{"name": "boxKong", "lo": Vector3(-1.5, Y0, 10.0), "hi": Vector3(1.5, Y0 + 1.0, 10.6)},
		{"name": "wall", "lo": Vector3(0.8, 0, 13.0), "hi": Vector3(0.95, Y0 + 2.6, 18.2)},
		{"name": "roofB", "lo": Vector3(-3, 0, 17.2), "hi": Vector3(3, Y0, 40)},
		{"name": "ledge", "lo": Vector3(-1.5, Y0, LEDGE_Z), "hi": Vector3(1.5, Y0 + 1.7, LEDGE_Z + 1.7)},
		{"name": "barPostL", "lo": Vector3(1.15, Y0, 28.2), "hi": Vector3(1.25, Y0 + 0.75, 28.3)},
		{"name": "barPostR", "lo": Vector3(-1.25, Y0, 28.2), "hi": Vector3(-1.15, Y0 + 0.75, 28.3)},
		{"name": "bar", "lo": Vector3(-1.25, Y0 + 0.65, 28.2), "hi": Vector3(1.25, Y0 + 0.75, 28.3)},
	]


## the moves, for the test and the render: name, window, what is measured
static func moves() -> Array:
	return [
		{"name": "speed vault", "t0": 0.80, "t1": 1.64},
		{"name": "kong", "t0": 2.02, "t1": 3.00},
		{"name": "wall run", "t0": 3.26, "t1": 4.47},
		{"name": "cat leap", "t0": 4.82, "t1": 6.05},
		{"name": "roll", "t0": 6.58, "t1": 7.20},
		{"name": "slide", "t0": 7.20, "t1": 8.0},
	]


# ------------------------------------------------------------------ the pelvis path in y: ballistic flights between contacts

class YPath extends RefCounted:
	var segs: Array = []
	var t := 0.0
	var y := 0.0
	var v := 0.0

	func start(t0: float, y0: float) -> void:
		t = t0
		y = y0
		v = 0.0

	## ballistic (g) from the cursor to (t1, y1): the parabola through both ends
	func par(t1: float, y1: float) -> void:
		var T := t1 - t
		if T <= 1e-6:
			y = y1
			return
		var v0 := (y1 - y) / T + 0.5 * ParkourPlan.G * T
		segs.append({"k": "par", "t0": t, "t1": t1, "y0": y, "v0": v0})
		v = v0 - ParkourPlan.G * T
		t = t1
		y = y1

	## the constant-deceleration stop of a landing: from the cursor (falling at v) to rest at a, then the cursor is the bottom
	func absorb(a: float) -> void:
		if v >= 0.0:
			return
		var Tb := -v / a
		segs.append({"k": "acc", "t0": t, "t1": t + Tb, "y0": y, "v0": v, "a": a})
		y += v * Tb + 0.5 * a * Tb * Tb
		t += Tb
		v = 0.0

	## a stance's spring: y1 at t1, passing ymid at the middle
	func dip(t1: float, y1: float, ymid: float) -> void:
		segs.append({"k": "dip", "t0": t, "t1": t1, "y0": y, "y1": y1, "ym": ymid})
		t = t1
		y = y1
		v = 0.0

	## a support's smooth change (hands on an edge): smoothstep to (t1, y1)
	func ease(t1: float, y1: float) -> void:
		segs.append({"k": "ease", "t0": t, "t1": t1, "y0": y, "y1": y1})
		t = t1
		y = y1
		v = 0.0

	func at(tt: float) -> float:
		if segs.is_empty():
			return y
		var s: Dictionary = segs[0]
		if tt >= float(segs[segs.size() - 1]["t1"]):
			return _eval(segs[segs.size() - 1], float(segs[segs.size() - 1]["t1"]), true)
		for q in segs:
			if tt < float(q["t1"]):
				s = q
				break
		return _eval(s, tt, false)

	func _eval(s: Dictionary, tt: float, end: bool) -> float:
		var tau: float = tt - float(s["t0"])
		var T: float = float(s["t1"]) - float(s["t0"])
		match String(s["k"]):
			"par":
				return float(s["y0"]) + float(s["v0"]) * tau - 0.5 * ParkourPlan.G * tau * tau
			"acc":
				return float(s["y0"]) + float(s["v0"]) * tau + 0.5 * float(s["a"]) * tau * tau
			"dip":
				var u := clampf(tau / T, 0.0, 1.0)
				var lin := lerpf(float(s["y0"]), float(s["y1"]), u)
				var dep := 0.5 * (float(s["y0"]) + float(s["y1"])) - float(s["ym"])
				return lin - dep * sin(PI * u)
			"ease":
				var u2 := smoothstep(0.0, 1.0, clampf(tau / T, 0.0, 1.0))
				return lerpf(float(s["y0"]), float(s["y1"]), u2)
		return float(s["y0"])


# ------------------------------------------------------------------ helpers on the root and the contact schedule

static func _zk(P: Dictionary, rows: Array) -> void:
	for r in rows:
		(P["root"]["z"] as Array).append({"t": float(r[0]), "v": Vector3(float(r[1]), 0, 0)})


static func _rows(P: Dictionary, chn: String, rows: Array) -> void:
	for r in rows:
		(P["root"][chn] as Array).append({"t": float(r[0]), "v": Vector3(float(r[1]), 0, 0)})


static func _sort(a: Array) -> void:
	a.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))


static func _zat(P: Dictionary, t: float) -> float:
	return Parkour.ch(P, "z", t)


## the longest pelvis height a stance can hold with the ankle at horizontal offset d (x, z) from the hip (m over the sole)
static func yext(dx: float, dz: float) -> float:
	var l := LEG * LEG_USE
	return sqrt(maxf(0.0, l * l - dx * dx - dz * dz)) + ANKLE_H - HIP_DY


## the pelvis height over a palm planted on a surface at height `top`, and its z behind the palm point, from the arm geometry of a
## support: the wrist rides PALM_Y + 0.03 over the surface, the shoulder is ARM_CH from it with the wrist `lean` ahead of the
## shoulder, the trunk leans p_eff degrees (the shoulder is SH rotated by it)
static func plant_pelvis(top: float, palm_z: float, p_eff: float, lean: float) -> Vector3:
	var a := deg_to_rad(p_eff)
	var sh_up := SH.y * cos(a)
	var sh_fwd := SH.y * sin(a)
	var wrist_y := top + 0.047
	var drop := sqrt(maxf(0.0, ARM_CH * ARM_CH - lean * lean))
	return Vector3(0.0, wrist_y + drop - sh_up - Y0 * 0.0 - 0.0, (palm_z - PALM_WRIST) - lean - sh_fwd)


## record a contact in the schedule
static func _log(P: Dictionary, limb: String, t0: float, t1: float, pt: Vector3, surface: String, kind: String) -> void:
	(P["schedule"] as Array).append({"limb": limb, "t0": t0, "t1": t1, "pt": pt, "surface": surface, "kind": kind})


## a contact: two keys at one point (the engine pins it for the window). mode: "" flat sole, "wall", "face" (sole on a face), "palm"
static func _hold(P: Dictionary, grp: String, tip: String, t0: float, t1: float, v: Vector3, mode := "") -> void:
	var a := {"t": t0, "v": v, "c": true}
	var b := {"t": t1, "v": v, "c": true}
	if mode != "":
		a["mode"] = mode
		b["mode"] = mode
	(P[grp][tip] as Array).append(a)
	(P[grp][tip] as Array).append(b)


static func _free(P: Dictionary, grp: String, tip: String, t: float, v: Vector3) -> void:
	(P[grp][tip] as Array).append({"t": t, "v": v, "c": false})


static func _rel(P: Dictionary, grp: String, tip: String, t: float, off: Vector3) -> void:
	var r := Parkour.root_at(P, t)
	_free(P, grp, tip, t, Vector3(float(r["x"]), float(r["y"]), float(r["z"])) + off)


## the pelvis's ankle-to-hip offsets at time t for a foot contact with the ankle at `ankle`: (dx, dz) horizontal
static func _hip_off(P: Dictionary, sd: String, t: float, ankle: Vector3) -> Vector2:
	var hx: float = float(Parkour.ch(P, "x", t)) + (HIP_DX if sd == "_l" else -HIP_DX)
	var hz: float = _zat(P, t) + HIP_DZ
	return Vector2(hx - ankle.x, hz - ankle.z)


## a flat-sole stance on the roof. kind: "run" (the ankle under the hip at mid-stance), "land" (the ankle H_TD ahead at touchdown, the
## pelvis falls into it and stops in a constant-deceleration absorption), "off" (take-off: the pelvis leaves it at its longest reach)
static func _stance(P: Dictionary, Y: YPath, sd: String, t0: float, t1: float, kind: String, surface := "roof", gx := NAN) -> float:
	var x := (0.09 if sd == "_l" else -0.09) if is_nan(gx) else gx
	var tm := 0.5 * (t0 + t1)
	var bz: float
	if kind == "land":
		bz = _zat(P, t0) + HIP_DZ + H_TD + FOOT_DZ
	else:
		bz = _zat(P, tm) + HIP_DZ + FOOT_DZ
	var ball := Vector3(x, Y0 + BALL, bz)
	var ankle := Vector3(x, Y0 + ANKLE_H, bz - FOOT_DZ)
	var o0 := _hip_off(P, sd, t0, ankle)
	var y_td := Y0 + yext(o0.x, o0.y)
	if kind == "land":
		y_td = Y0 + yext(0.0, H_TD)
	if Y.segs.is_empty() and Y.t == 0.0 and Y.y == 0.0:
		Y.start(t0, y_td)
	else:
		Y.par(t0, y_td)
	var t_end := t1
	if kind == "land":
		Y.absorb(A_LAND)
		var o1 := _hip_off(P, sd, t1, ankle)
		var y_lo := Y0 + yext(o1.x, o1.y)
		if Y.t > t1 - 0.04:
			t_end = Y.t + 0.05
			y_lo = Y0 + yext(_hip_off(P, sd, t_end, ankle).x, _hip_off(P, sd, t_end, ankle).y)
		Y.ease(t_end, y_lo)
	else:
		var o1b := _hip_off(P, sd, t1, ankle)
		var y_lo2 := Y0 + yext(o1b.x, o1b.y)
		Y.dip(t1, y_lo2, Y0 + HIP_MID)
	_hold(P, "feet", "foot" + sd, t0, t_end, ball)
	_log(P, "foot" + sd, t0, t_end, ball, surface, "sole")
	return t_end


static func _hand_palm(P: Dictionary, sd: String, t0: float, t1: float, pt: Vector3, surface: String) -> void:
	_hold(P, "hands", "hand" + sd, t0, t1, pt, "palm")
	_log(P, "hand" + sd, t0, t1, pt, surface, "palm")


static func build() -> Dictionary:
	var P := {"obstacles": obstacles(), "length": 8.0, "lift": false, "two_pass": false,
		"root": {"z": [], "y": [], "x": [], "p": [], "r": [], "s": [], "tw": []},
		"feet": {"foot_l": [], "foot_r": []}, "hands": {"hand_l": [], "hand_r": []}, "fk": [], "poles": {}, "schedule": [], "snap": []}
	var L := "_l"
	var R := "_r"
	var obs := {}
	for o in P["obstacles"]:
		obs[o["name"]] = o
	# ================= 1 the anchors that fix the pelvis in z
	# a palm plant puts the shoulder over the palm: the pelvis z follows from the plant (speed vault p_eff 57, kong 70)
	var pv := plant_pelvis(Y0 + 0.8, 5.0 + 0.0, 57.0, 0.34)       # speed vault, right palm on the near edge (z = 5.0)
	var pk := plant_pelvis(Y0 + 1.0, 10.0, 70.0, 0.34)            # kong, both palms on the near edge (z = 10.0)
	var zv: float = pv.z
	var zk: float = pk.z
	var zl := LEDGE_Z
	var pc := plant_pelvis(Y0 + 1.7, zl, 10.0, 0.12)              # the hang from the ledge's edge: the shoulder 12 cm behind the palm
	# the pelvis z knots (t, z): ~4 m/s in a run, ~3.2 through a plant (the hands brake), the same ~3 m/s through the mantle and the drop
	_zk(P, [[0.0, zv - 4.2 * 1.07 - 0.32 * 3.2 * 0.0 - 0.0], [1.07, zv - 0.32], [1.17, zv], [1.27, zv + 0.32],
		[2.31, zk - 0.32], [2.41, zk], [2.51, zk + 0.32],
		[4.385, 17.45], [4.89, 19.35], [5.30, pc.z], [5.50, pc.z + 0.04], [5.74, zl + 0.30], [5.88, zl + 0.80], [6.04, zl + 1.30],
		[6.58, zl + 1.30 + 3.0 * 0.54], [6.78, zl + 1.30 + 3.0 * 0.54 + 0.55], [7.2, zl + 1.30 + 3.0 * 0.54 + 1.85], [7.6, zl + 1.30 + 3.0 * 0.54 + 2.95],
		[8.0, zl + 1.30 + 3.0 * 0.54 + 3.85]])
	# the first knot: constant speed from the start to the slow-down (the run-in is ~4.2 m/s)
	(P["root"]["z"] as Array)[0]["v"] = Vector3(zv - 0.32 - 4.2 * 1.07, 0, 0)
	_rows(P, "x", [[0, 0], [3.0, 0], [3.4, 0.52], [4.15, 0.52], [4.46, 0.0], [8.0, 0.0]])
	_rows(P, "p", [[0, 10], [0.7, 12], [0.97, 25], [1.12, 55], [1.22, 55], [1.45, 22], [1.56, 12], [2.1, 12], [2.2, 35], [2.41, 70], [2.55, 70], [2.72, 40], [2.86, 12],
		[3.3, 12], [3.45, 8], [4.15, 8], [4.40, 12], [4.8, 12], [4.95, 25], [5.25, 10], [5.5, 10], [5.74, 25], [5.9, 12], [6.2, 5], [6.45, 20], [6.58, 40], [6.72, 70],
		[6.9, 200], [7.05, 330], [7.15, 360], [7.25, 372], [7.36, 340], [7.5, -80], [8.0, -82]])
	_rows(P, "r", [[0, 0], [3.2, 0], [3.45, -22], [4.2, -22], [4.45, 0], [8.0, 0]])
	_rows(P, "s", [[0, 6], [0.9, 6], [1.0, 10], [1.2, 10], [1.45, 5], [2.3, 6], [2.5, 12], [2.85, 6], [3.4, 8], [4.3, 6], [5.0, 8], [5.4, 0], [5.7, 10], [6.2, 6], [6.6, 20], [6.9, 30],
		[7.2, 10], [7.4, 5], [8.0, 0]])
	for k in ["z", "x", "p", "r", "s"]:
		_sort(P["root"][k])
	# ================= 2 the stances, in time order: each one fixes its foot and the pelvis height around it
	var Y := YPath.new()
	_stance(P, Y, R, 0.00, 0.18, "run")
	_stance(P, Y, L, 0.27, 0.45, "run")
	_stance(P, Y, R, 0.53, 0.70, "run")
	_stance(P, Y, L, 0.80, 0.97, "off", "roof")
	# the speed vault: right palm on the box's near edge at 1.10-1.24 (the schedule), the pelvis flies through the plant's height
	var hv := Vector3(-0.22, Y0 + 0.8 + PALM_Y, 5.0)
	Y.par(1.17, pv.y)
	_hand_palm(P, R, 1.10, 1.24, hv, "boxSpeed")
	var t_v := _stance(P, Y, R, 1.48, 1.64, "land")
	_stance(P, Y, L, 1.78, 1.95, "run")
	_stance(P, Y, R, 2.02, 2.16, "off")
	# the kong: both palms on the near edge at 2.30-2.56
	Y.par(2.41, pk.y)
	_hand_palm(P, L, 2.30, 2.56, Vector3(0.20, Y0 + 1.0 + PALM_Y, 10.0), "boxKong")
	_hand_palm(P, R, 2.30, 2.56, Vector3(-0.20, Y0 + 1.0 + PALM_Y, 10.0), "boxKong")
	_stance(P, Y, L, 2.84, 3.00, "land")
	_stance(P, Y, R, 3.10, 3.26, "run")
	# the wall run: soles on the wall face. The ankle is the target; the pelvis rides the leg's reach above it.
	var wall_steps := [[L, 3.40, 3.57, 0.57], [R, 3.70, 3.85, 0.74], [L, 4.00, 4.15, 0.62]]
	for w in wall_steps:
		var sd: String = w[0]
		var tm: float = 0.5 * (float(w[1]) + float(w[2]))
		var az := _zat(P, tm)
		var ankle := Vector3(WALL_X - DEPTH_SOLE, Y0 + float(w[3]), az)
		var o0 := _hip_off(P, sd, float(w[1]), ankle)
		var o1 := _hip_off(P, sd, float(w[2]), ankle)
		var om := _hip_off(P, sd, tm, ankle)
		Y.par(float(w[1]), Y0 + float(w[3]) - ANKLE_H + yext(o0.x, o0.y) - 0.02)
		var ym := Y0 + float(w[3]) - ANKLE_H + yext(om.x, om.y) - 0.06
		Y.dip(float(w[2]), Y0 + float(w[3]) - ANKLE_H + yext(o1.x, o1.y) - 0.02, ym)
		_hold(P, "feet", "foot" + sd, float(w[1]), float(w[2]), ankle, "wall")
		_log(P, "foot" + sd, float(w[1]), float(w[2]), ankle, "wall", "sole on the wall")
	_stance(P, Y, R, 4.30, 4.47, "land", "roofB")
	_stance(P, Y, L, 4.60, 4.76, "run", "roofB")
	_stance(P, Y, R, 4.82, 4.96, "off", "roofB")
	# the cat leap: flight to the ledge, palms on its near edge (z = LEDGE_Z) 5.30-5.84 through the catch and the mantle, toe tips on the face
	var hang_y := Y0 + 1.7 + 0.047 - ARM_CH * 0.95 - SH.y * cos(deg_to_rad(10.0))
	Y.par(5.30, hang_y)
	var hl := Vector3(0.20, Y0 + 1.7 + PALM_Y, zl)
	_hand_palm(P, L, 5.30, 5.84, hl, "ledge")
	_hand_palm(P, R, 5.30, 5.84, Vector3(-0.20, Y0 + 1.7 + PALM_Y, zl), "ledge")
	Y.ease(5.50, hang_y - 0.06)         # the catch's sag
	Y.ease(5.74, Y0 + 1.7 + 0.27)       # the pull: the pelvis rises past the edge over the palms
	Y.ease(5.90, Y0 + 1.7 + 0.80)       # standing on the ledge
	Y.ease(6.04, Y0 + 1.7 + 0.80)
	_hold(P, "feet", "foot_l", 5.32, 5.50, Vector3(0.12, Y0 + 0.28, zl - TOE_STAND))
	_log(P, "foot_l", 5.32, 5.50, Vector3(0.12, Y0 + 0.28, zl - TOE_STAND), "ledge face", "toe tip")
	_hold(P, "feet", "foot_r", 5.32, 5.50, Vector3(-0.12, Y0 + 0.16, zl - TOE_STAND))
	_log(P, "foot_r", 5.32, 5.50, Vector3(-0.12, Y0 + 0.16, zl - TOE_STAND), "ledge face", "toe tip")
	_hold(P, "feet", "foot_r", 5.78, 5.92, Vector3(-0.09, Y0 + 1.7 + BALL, zl + 0.80))
	_log(P, "foot_r", 5.78, 5.92, Vector3(-0.09, Y0 + 1.7 + BALL, zl + 0.80), "ledge top", "sole")
	_hold(P, "feet", "foot_l", 5.94, 6.04, Vector3(0.09, Y0 + 1.7 + BALL, zl + 1.40))
	_log(P, "foot_l", 5.94, 6.04, Vector3(0.09, Y0 + 1.7 + BALL, zl + 1.40), "ledge top", "sole")
	# the drop: ballistic from the step-off to the landing, both feet, then the hands (Dai et al. 2020: feet, hands, back)
	var zl_td := _zat(P, 6.58)
	var bz := zl_td + HIP_DZ + H_TD + FOOT_DZ
	var y_td := Y0 + yext(0.0, H_TD)
	Y.par(6.58, y_td)
	Y.absorb(A_LAND * 2.0)              # the roll shares the landing with the hands: a firmer stop in the legs
	var tb := Y.t
	var land_ball_l := Vector3(0.12, Y0 + BALL, bz)
	var land_ball_r := Vector3(-0.12, Y0 + BALL, bz)
	_hold(P, "feet", "foot_l", 6.58, 6.68, land_ball_l)
	_hold(P, "feet", "foot_r", 6.58, 6.68, land_ball_r)
	_log(P, "foot_l", 6.58, 6.68, land_ball_l, "roofB", "sole")
	_log(P, "foot_r", 6.58, 6.68, land_ball_r, "roofB", "sole")
	var hz := bz + 0.30
	_hand_palm(P, L, 6.62, 6.78, Vector3(0.18, Y0 + PALM_Y, hz), "roofB")
	_hand_palm(P, R, 6.62, 6.78, Vector3(-0.18, Y0 + PALM_Y, hz), "roofB")
	Y.ease(6.82, Y0 + 0.50)
	Y.ease(7.0, Y0 + 0.30)
	Y.ease(7.4, Y0 + 0.20)
	Y.ease(8.0, Y0 + 0.19)
	P["snap"].append([6.86, 8.0])      # the roll and the slide: the lowest body point is the contact with the roof
	_log(P, "shoulder_r", 6.80, 6.92, Vector3.ZERO, "roofB", "shoulder (diagonal)")
	_log(P, "back", 6.92, 7.10, Vector3.ZERO, "roofB", "upper back")
	_log(P, "hip_l", 7.10, 7.20, Vector3.ZERO, "roofB", "opposite hip")
	# ================= the pelvis y channel: dense samples of the path
	var t := -0.1
	while t <= 8.0001:
		(P["root"]["y"] as Array).append({"t": snappedf(t, 0.0001), "v": Vector3(Y.at(maxf(t, 0.0)), 0, 0)})
		t += 1.0 / 60.0
	P["ypath_bottom"] = tb
	P["v_td_note"] = "absorb ends at %.3f" % tb
	# ================= 3 the free limbs
	_free_feet(P)
	_free_hands(P)
	for g in ["feet", "hands"]:
		for k in P[g]:
			_sort(P[g][k])
	# the roll: the limbs are FK-tucked while the pelvis turns (angles in degrees, bend/side/twist)
	P["fk"].append({"t0": 6.88, "t1": 7.20, "ramp": 0.08, "ang": {
		"thigh_l": Vector3(115, 4, 0), "thigh_r": Vector3(115, -4, 0), "calf_l": Vector3(125, 0, 0), "calf_r": Vector3(125, 0, 0),
		"foot_l": Vector3(20, 0, 0), "foot_r": Vector3(20, 0, 0),
		"upperarm_l": Vector3(70, -30, 0), "upperarm_r": Vector3(70, -30, 0), "lowerarm_l": Vector3(95, 0, 0), "lowerarm_r": Vector3(95, 0, 0)}})
	return P


## the contact schedule as text, for the report
static func schedule_text(P: Dictionary) -> String:
	var rows: Array = (P["schedule"] as Array).duplicate()
	rows.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	var s := ""
	for r in rows:
		var pt: Vector3 = r["pt"]
		s += "%.2f-%.2f  %-10s %-12s %-18s (%.2f, %.2f, %.2f)\n" % [r["t0"], r["t1"], r["limb"], r["surface"], r["kind"], pt.x, pt.y - Y0, pt.z]
	return s


# ------------------------------------------------------------------ free limbs

## a foot target held clear of every box above the roofs (the vault's box, the kong's box, the ledge, the wall): lifted to top + clear
## where it passes over one
static func _clear(P: Dictionary, p: Vector3, clear: float) -> Vector3:
	for o in P["obstacles"]:
		var nm: String = o["name"]
		if nm.begins_with("roof"):
			continue
		var lo: Vector3 = o["lo"]
		var hi: Vector3 = o["hi"]
		if p.x > lo.x - 0.08 and p.x < hi.x + 0.08 and p.z > lo.z - 0.22 and p.z < hi.z + 0.22 and p.y < hi.y + clear:
			if nm == "wall" or nm == "ledge" and p.z < lo.z:
				continue
			p.y = hi.y + clear
	return p


## a free limb over [ta, tb] between two world points pa, pb (the neighbouring contacts), with waypoints rel [[t, offset from the pelvis]]
## in between; sampled every frame so the engine hits exactly the planned point
static func _flight(P: Dictionary, grp: String, tip: String, ta: float, pa: Vector3, tb: float, pb: Vector3, rel: Array, clear := 0.17) -> void:
	var keys: Array = []
	for r in rel:
		keys.append({"t": float(r[0]), "v": r[1]})
	var t: float = ceilf(ta * 30.0 + 0.001) / 30.0
	while t < tb - 0.001:
		var rt := Parkour.root_at(P, t)
		var base := Vector3(float(rt["x"]), float(rt["y"]), float(rt["z"]))
		var wp: Vector3 = base + (PartKeys.at(keys, t) as Vector3) if not keys.is_empty() else pa.lerp(pb, (t - ta) / (tb - ta))
		var wa := smoothstep(0.0, 0.10, t - ta)
		var wb := smoothstep(0.0, 0.10, tb - t)
		var pt: Vector3 = wp
		pt = pa.lerp(pt, wa) if wa < 1.0 else pt
		pt = pb.lerp(pt, wb) if wb < 1.0 else pt
		pt = _clear(P, pt, clear)
		(P[grp][tip] as Array).append({"t": snappedf(t, 0.0001), "v": pt, "c": false})
		t += 1.0 / 30.0


## the run swing of a foot between two stances: the ball travels from pa to pb with a lift
static func _swing(P: Dictionary, sd: String, ta: float, pa: Vector3, tb: float, pb: Vector3, lift := 0.26) -> void:
	var t: float = ceilf(ta * 30.0 + 0.001) / 30.0
	while t < tb - 0.001:
		var s := (t - ta) / (tb - ta)
		var e := smoothstep(0.0, 1.0, s)
		var pt := pa.lerp(pb, e)
		pt.y += lift * sin(PI * clampf(s, 0, 1)) + 0.0
		(P["feet"]["foot" + sd] as Array).append({"t": snappedf(t, 0.0001), "v": pt, "c": false})
		t += 1.0 / 30.0


static func _contacts_of(P: Dictionary, tip: String) -> Array:
	var out := []
	var keys: Array = P["feet"]["foot" + tip.substr(4)] if tip.begins_with("foot") else []
	return out


## the foot contacts of one foot as [t0, t1, point], time-ordered
static func _foot_holds(P: Dictionary, sd: String) -> Array:
	var ks: Array = P["feet"]["foot" + sd]
	var out := []
	for i in range(ks.size()):
		var a: Dictionary = ks[i]
		if bool(a.get("c", false)) and i + 1 < ks.size() and bool(ks[i + 1].get("c", false)) and (a["v"] as Vector3).is_equal_approx(ks[i + 1]["v"]):
			out.append([float(a["t"]), float(ks[i + 1]["t"]), a["v"], String(a.get("mode", ""))])
	out.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	return out


static func _free_feet(P: Dictionary) -> void:
	_flight_legs(P)
	for sd in ["_l", "_r"]:
		var hs := _foot_holds(P, sd)
		for i in range(hs.size() - 1):
			var a: Array = hs[i]
			var b: Array = hs[i + 1]
			var ta: float = a[1]
			var tb: float = b[0]
			var has := false
			for k in P["feet"]["foot" + sd]:
				if not bool(k.get("c", false)) and float(k["t"]) > ta + 0.001 and float(k["t"]) < tb - 0.001:
					has = true
			if has:
				continue
			if String(a[3]) == "" and String(b[3]) == "":
				_swing(P, sd, ta, a[2], tb, b[2])
			else:
				_flight(P, "feet", "foot" + sd, ta, a[2], tb, b[2], [])


static func _flight_legs(P: Dictionary) -> void:
	var L := "_l"
	var R := "_r"
	var pt := func(sd: String, t: float) -> Vector3:
		for h in _foot_holds(P, sd):
			if absf(float(h[0]) - t) < 0.001 or absf(float(h[1]) - t) < 0.001:
				return h[2]
		return Vector3.ZERO
	# speed vault: after L leaves (0.97) both legs fold up to his left over the box; R was the last swinging, lands at 1.48
	_flight(P, "feet", "foot_l", 0.97, pt.call(L, 0.97), 1.78, pt.call(L, 1.78), [
		[0.97, Vector3(0.12, -0.60, -0.30)], [1.12, Vector3(0.45, -0.30, -0.20)], [1.30, Vector3(0.48, -0.25, 0.0)], [1.42, Vector3(0.20, -0.45, 0.35)],
		[1.55, Vector3(0.12, -0.55, 0.40)], [1.78, Vector3(0.09, -0.62, 0.10)]])
	_flight(P, "feet", "foot_r", 0.70, pt.call(R, 0.70), 1.48, pt.call(R, 1.48), [
		[0.70, Vector3(-0.09, -0.50, -0.30)], [0.85, Vector3(-0.12, -0.45, 0.20)], [1.0, Vector3(-0.15, -0.35, -0.35)], [1.15, Vector3(0.38, -0.20, -0.30)],
		[1.32, Vector3(0.45, -0.20, 0.0)], [1.40, Vector3(0.15, -0.45, 0.30)], [1.48, Vector3(-0.09, -0.80, 0.50)]])
	# kong: legs tuck up between the arms, then reach for the roof
	_flight(P, "feet", "foot_l", 1.95, pt.call(L, 1.95), 2.84, pt.call(L, 2.84), [
		[1.95, Vector3(0.09, -0.60, -0.30)], [2.20, Vector3(0.12, -0.40, -0.30)], [2.41, Vector3(0.12, -0.28, -0.05)], [2.60, Vector3(0.12, -0.30, 0.25)],
		[2.72, Vector3(0.10, -0.50, 0.40)], [2.84, Vector3(0.09, -0.80, 0.55)]])
	_flight(P, "feet", "foot_r", 2.16, pt.call(R, 2.16), 3.10, pt.call(R, 3.10), [
		[2.16, Vector3(-0.10, -0.55, -0.40)], [2.30, Vector3(-0.12, -0.40, -0.28)], [2.45, Vector3(-0.12, -0.30, 0.0)], [2.62, Vector3(-0.12, -0.30, 0.22)],
		[2.75, Vector3(-0.10, -0.55, 0.40)], [2.95, Vector3(-0.09, -0.65, 0.20)], [3.10, Vector3(-0.09, -0.70, 0.45)]])
	# wall run: the swing between wall steps
	for q in [[L, 3.26, 3.40], [R, 3.26, 3.40]]:
		pass
	_flight(P, "feet", "foot_r", 3.26, pt.call(R, 3.26), 3.70, pt.call(R, 3.70), [
		[3.26, Vector3(-0.09, -0.70, 0.30)], [3.45, Vector3(-0.10, -0.55, 0.25)], [3.60, Vector3(0.10, -0.55, 0.30)]])
	_flight(P, "feet", "foot_l", 3.00, pt.call(L, 3.00), 3.40, pt.call(L, 3.40), [
		[3.00, Vector3(0.09, -0.65, -0.20)], [3.20, Vector3(0.12, -0.45, 0.25)], [3.30, Vector3(0.12, -0.45, 0.30)]])
	_flight(P, "feet", "foot_l", 3.57, pt.call(L, 3.57), 4.00, pt.call(L, 4.00), [
		[3.57, Vector3(0.20, -0.55, -0.10)], [3.80, Vector3(0.16, -0.50, 0.25)], [3.92, Vector3(0.16, -0.45, 0.20)]])
	_flight(P, "feet", "foot_r", 3.85, pt.call(R, 3.85), 4.30, pt.call(R, 4.30), [
		[3.85, Vector3(0.0, -0.55, -0.20)], [4.05, Vector3(-0.09, -0.50, 0.10)], [4.20, Vector3(-0.09, -0.62, 0.35)], [4.30, Vector3(-0.09, -0.80, 0.50)]])
	_flight(P, "feet", "foot_l", 4.15, pt.call(L, 4.15), 4.60, pt.call(L, 4.60), [
		[4.15, Vector3(0.10, -0.45, -0.15)], [4.30, Vector3(0.10, -0.55, -0.30)], [4.45, Vector3(0.09, -0.50, 0.10)], [4.60, Vector3(0.09, -0.70, 0.40)]])
	# cat leap: knees up to the face after the take-off, the toe tips on the face (5.32), then up onto the ledge
	_flight(P, "feet", "foot_l", 4.76, pt.call(L, 4.76), 5.32, pt.call(L, 5.32), [
		[4.76, Vector3(0.09, -0.60, -0.15)], [4.96, Vector3(0.10, -0.55, -0.40)], [5.12, Vector3(0.12, -0.45, 0.10)], [5.25, Vector3(0.12, -0.50, 0.30)]])
	_flight(P, "feet", "foot_r", 4.96, pt.call(R, 4.96), 5.32, pt.call(R, 5.32), [
		[4.96, Vector3(-0.09, -0.62, -0.20)], [5.05, Vector3(-0.10, -0.50, -0.30)], [5.20, Vector3(-0.12, -0.50, 0.20)], [5.30, Vector3(-0.12, -0.55, 0.30)]])
	_flight(P, "feet", "foot_l", 5.50, pt.call(L, 5.50), 5.94, pt.call(L, 5.94), [
		[5.50, Vector3(0.12, -0.55, -0.40)], [5.60, Vector3(0.12, -0.50, -0.40)], [5.75, Vector3(0.10, -0.40, 0.0)], [5.90, Vector3(0.09, -0.60, 0.10)]], 0.10)
	_flight(P, "feet", "foot_r", 5.50, pt.call(R, 5.50), 5.78, pt.call(R, 5.78), [
		[5.50, Vector3(-0.12, -0.55, -0.45)], [5.64, Vector3(-0.12, -0.50, -0.30)], [5.72, Vector3(-0.12, -0.45, 0.10)]], 0.10)
	# the step off and the drop: legs open to reach for the roof
	_flight(P, "feet", "foot_r", 5.92, pt.call(R, 5.92), 6.58, pt.call(R, 6.58), [
		[5.92, Vector3(-0.09, -0.80, -0.20)], [6.15, Vector3(-0.10, -0.55, 0.25)], [6.45, Vector3(-0.12, -0.60, 0.30)], [6.58, Vector3(-0.12, -0.80, 0.50)]], 0.10)
	_flight(P, "feet", "foot_l", 6.04, pt.call(L, 6.04), 6.58, pt.call(L, 6.58), [
		[6.04, Vector3(0.09, -0.80, 0.0)], [6.30, Vector3(0.12, -0.52, 0.20)], [6.50, Vector3(0.12, -0.62, 0.25)], [6.58, Vector3(0.12, -0.80, 0.50)]], 0.10)
	# the roll then the slide: the legs follow the trunk (FK tuck), then both reach forward on the slide
	for sd in ["_l", "_r"]:
		var sg := 1.0 if sd == "_l" else -1.0
		_rel(P, "feet", "foot" + sd, 6.68, Vector3(sg * 0.12, -0.55, 0.45))
		_rel(P, "feet", "foot" + sd, 7.25, Vector3(sg * 0.09, -0.62, 0.15))
		_rel(P, "feet", "foot" + sd, 7.40, Vector3(sg * 0.10, 0.12, 0.88))
		_rel(P, "feet", "foot" + sd, 8.0, Vector3(sg * 0.10, 0.12, 0.88))


## free arms in a run: the arm opposite each foot swings forward when that foot lands (elbows bent, hands near the ribs)
static func _hand_run(P: Dictionary) -> void:
	var runs := [[0.00, 0.18, "_r"], [0.27, 0.45, "_l"], [0.53, 0.70, "_r"], [1.64, 1.78, "_r"], [1.78, 1.95, "_l"],
		[3.00, 3.10, "_l"], [3.10, 3.26, "_r"], [4.30, 4.47, "_r"], [4.60, 4.76, "_l"]]
	for r in runs:
		var t := (float(r[0]) + float(r[1])) * 0.5
		var landing: String = r[2]
		var fwd := "_l" if landing == "_r" else "_r"
		var back := landing
		_rel(P, "hands", "hand" + fwd, t, Vector3((0.28 if fwd == "_l" else -0.28), 0.06, 0.34))
		_rel(P, "hands", "hand" + back, t, Vector3((0.30 if back == "_l" else -0.30), -0.04, -0.28))


static func _free_hands(P: Dictionary) -> void:
	_hand_run(P)
	# the speed vault: the right palm is on the edge; the left hand reaches out to the side
	_rel(P, "hands", "hand_r", 0.95, Vector3(-0.30, 0.12, 0.40))
	_rel(P, "hands", "hand_r", 1.45, Vector3(-0.30, 0.00, 0.25))
	_rel(P, "hands", "hand_l", 1.0, Vector3(0.30, 0.20, 0.30))
	_rel(P, "hands", "hand_l", 1.2, Vector3(0.45, 0.10, 0.1))
	_rel(P, "hands", "hand_l", 1.40, Vector3(0.40, 0.10, 0.2))
	# the kong: both palms on the near edge
	_rel(P, "hands", "hand_l", 2.16, Vector3(0.25, 0.1, 0.5))
	_rel(P, "hands", "hand_r", 2.16, Vector3(-0.25, 0.1, 0.5))
	_rel(P, "hands", "hand_l", 2.72, Vector3(0.30, 0.15, 0.2))
	_rel(P, "hands", "hand_r", 2.72, Vector3(-0.30, 0.15, 0.2))
	# the wall run: the hands stay clear, arms out for balance
	for tt in [3.40, 3.70, 4.00]:
		_rel(P, "hands", "hand_r", tt, Vector3(-0.40, 0.25, 0.35))
		_rel(P, "hands", "hand_l", tt, Vector3(-0.10, 0.15, -0.30))
	# the cat leap: reach for the edge
	_rel(P, "hands", "hand_l", 4.96, Vector3(0.20, 0.30, 0.45))
	_rel(P, "hands", "hand_r", 4.96, Vector3(-0.20, 0.30, 0.45))
	# up on the ledge, the drop: arms up and out
	for sd in ["_l", "_r"]:
		var sg := 1.0 if sd == "_l" else -1.0
		_rel(P, "hands", "hand" + sd, 6.0, Vector3(sg * 0.45, 0.30, 0.1))
		_rel(P, "hands", "hand" + sd, 6.3, Vector3(sg * 0.40, 0.55, 0.2))
		_rel(P, "hands", "hand" + sd, 6.5, Vector3(sg * 0.25, 0.20, 0.5))
	# the slide: arms back / up, lying on his back
	for sd in ["_l", "_r"]:
		var sg2 := 1.0 if sd == "_l" else -1.0
		_rel(P, "hands", "hand" + sd, 7.25, Vector3(sg2 * 0.35, 0.1, 0.2))
		_rel(P, "hands", "hand" + sd, 7.45, Vector3(sg2 * 0.30, 0.0, -0.9))
		_rel(P, "hands", "hand" + sd, 8.0, Vector3(sg2 * 0.30, 0.0, -0.9))
