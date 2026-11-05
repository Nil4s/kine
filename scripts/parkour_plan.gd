## parkour_plan.gd - CH7b: the 8 s chained run, planned CONTACTS FIRST (see parkour.gd for the engine that poses it).
##
## Order of work (docs/CH7b_FEEDBACK.md):
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
		{"name": "boxKong", "lo": Vector3(-1.5, Y0, 9.4), "hi": Vector3(1.5, Y0 + 1.0, 10.0)},
		{"name": "wall", "lo": Vector3(0.8, 0, 13.0), "hi": Vector3(0.95, Y0 + 2.6, 18.2)},
		{"name": "roofB", "lo": Vector3(-3, 0, 17.2), "hi": Vector3(3, Y0, 40)},
		{"name": "ledge", "lo": Vector3(-1.5, Y0, LEDGE_Z), "hi": Vector3(1.5, Y0 + 1.7, LEDGE_Z + 0.6)},
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

	## a support: the height is a function of t over the window (the pelvis held by the arms on planted palms)
	func fn(t1: float, f: Callable) -> void:
		segs.append({"k": "fn", "t0": t, "t1": t1, "f": f})
		t = t1
		y = float(f.call(t1))
		v = (y - float(f.call(t1 - 0.01))) / 0.01

	## the state, to try segments and take them back (the landing's depth is searched this way)
	func mark() -> Array:
		return [segs.size(), t, y, v]

	func back(m: Array) -> void:
		segs.resize(int(m[0]))
		t = m[1]
		y = m[2]
		v = m[3]

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
			"fn":
				return float((s["f"] as Callable).call(clampf(tt, float(s["t0"]), float(s["t1"]))))
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


static func _hand_palm(P: Dictionary, sd: String, t0: float, t1: float, pt: Vector3, surface: String, n0 := Vector3.ZERO, n1 := Vector3.ZERO, fdir := Vector3.ZERO) -> void:
	_hold(P, "hands", "hand" + sd, t0, t1, pt, "palm")
	if fdir != Vector3.ZERO:
		var kf: Array = P["hands"]["hand" + sd]
		kf[kf.size() - 2]["f"] = fdir
		kf[kf.size() - 1]["f"] = fdir
	if n0 != Vector3.ZERO:
		var ks: Array = P["hands"]["hand" + sd]
		ks[ks.size() - 2]["n"] = n0.normalized()
		ks[ks.size() - 1]["n"] = (n1 if n1 != Vector3.ZERO else n0).normalized()
	_log(P, "hand" + sd, t0, t1, pt, surface, "palm" if n0 == Vector3.ZERO else "palm hooked over the edge")


## the shoulder (the upperarm joint) of side sd from the pelvis joint, for the trunk as keyed at t: the engine's own Body posed by
## Parkour._set_trunk, so the plan and the pose agree exactly
static func sh_off(P: Dictionary, t: float, sd: String) -> Vector3:
	var B := Parkour.body()
	B.from_dict(Parkour._base)
	Parkour._set_trunk(B, Parkour.root_at(P, t))
	B.offset = Vector3.ZERO
	B.fk()
	return (B.P["upperarm" + sd] as Vector3) - (B.P["pelvis"] as Vector3)


## the wrist of a palm lying flat on a top face, fingers along +z
static func _wrist_of(palm: Vector3) -> Vector3:
	return palm + Vector3(0.0, 0.03, -PALM_WRIST)


## CONTACT FIRST, the support phase: the pelvis height that keeps every planted arm's shoulder A from its wrist (an inverted
## pendulum over the hands: the shoulder rides a sphere about the wrist while the pelvis runs on in z). [[side, palm], ...]
static func arm_y(P: Dictionary, t: float, palms: Array, A: float) -> float:
	var best := INF
	var zt := _zat(P, t)
	var xt: float = Parkour.ch(P, "x", t)
	for pp in palms:
		var so := sh_off(P, t, String(pp[0]))
		var w := _wrist_of(pp[1])
		var dh := Vector2(xt + so.x - w.x, zt + so.z - w.z).length()
		best = minf(best, w.y + sqrt(maxf(0.0, A * A - dh * dh)) - so.y)
	return best


## the knee flexion (deg) of a leg with the hip at `hip` and the ankle at `ankle` (law of cosines, thigh 0.400, calf 0.428)
static func knee_of(hip: Vector3, ankle: Vector3) -> float:
	var a := 0.400
	var b := 0.428
	var d := clampf(hip.distance_to(ankle), absf(a - b) + 1e-4, a + b - 1e-4)
	return 180.0 - rad_to_deg(acos(clampf((a * a + b * b - d * d) / (2.0 * a * b), -1.0, 1.0)))


## the knee flexion (deg) of a stance leg with the toe base pinned at `ball`: the foot lies flat until the shank leans past the
## ankle's dorsiflexion stop (25 deg, data/body_limits.json), then the heel rises about the ball (as the engine's stance does)
static func knee_heel(hip: Vector3, ball: Vector3) -> float:
	var a := 0.400
	var b := 0.428
	var foot := Vector2(-FOOT_DZ, ANKLE_H - BALL)      # (z, y) of the ankle from the ball, flat
	var th := 0.0
	var flex := 0.0
	for it in 6:
		var af := foot.rotated(-th)                      # heel up: the ankle turns up and forward about the ball
		var A := Vector2(ball.z + af.x, ball.y + af.y)
		var H := Vector2(hip.z, hip.y)
		var dv := A - H
		var d := clampf(dv.length(), absf(a - b) + 1e-4, a + b - 1e-4)
		var u := dv.normalized()
		var s := (a * a - b * b + d * d) / (2.0 * d)
		var h := sqrt(maxf(0.0, a * a - s * s))
		var n := Vector2(-u.y, u.x)
		if n.x < 0.0:
			n = -n                                       # the knee bends forward (+z)
		var K := H + u * s + n * h
		flex = 180.0 - rad_to_deg(acos(clampf((a * a + b * b - d * d) / (2.0 * a * b), -1.0, 1.0)))
		var shank := rad_to_deg(atan2(K.x - A.x, K.y - A.y))
		th = deg_to_rad(maxf(0.0, shank - 25.0))
	return flex


## the knee flexion (deg) the ENGINE's stance gives with the pelvis at height y and the toe base pinned at `ball`: the plan poses the
## engine's own Body (trunk, pelvis, Parkour._stance_foot) so the landing depth it plans is the knee the run will show
static func knee_solved(P: Dictionary, sd: String, t: float, y: float, ball: Vector3) -> float:
	var B := Parkour.body()
	B.from_dict(Parkour._base)
	var rt := Parkour.root_at(P, t)
	Parkour._set_trunk(B, rt)
	var p0: Vector3 = B.p0["pelvis"]
	B.offset = Vector3(float(rt["x"]), y - p0.y, float(rt["z"]))
	B.fk()
	Parkour._stance_foot(B, sd, ball)
	return float((B.ang["calf" + sd] as Vector3).x)


## A LANDING, contact first: the foot is pinned H_TD ahead of the hip at touchdown; the pelvis falls ballistically into it and
## stops in a constant deceleration whose depth is set so the knee's absorption peak is flex_at(fall), the fall being the pelvis
## drop from the flight's apex (knee-dominant landing, Zhang et al. 2025 PeerJ 13:e19490, docs/CH7_REFERENCE.md: 30.8 deg/m);
## then the leg extends to y_end by t1. Returns [t_end, fall (m), planned peak (deg)]
static func _land(P: Dictionary, Y: YPath, sd: String, t0: float, t1: float, surface: String, y_end: float, both := false) -> Array:
	var x := 0.09 if sd == "_l" else -0.09
	if both:
		x = 0.12 if sd == "_l" else -0.12
	var bz := _zat(P, t0) + HIP_DZ + H_TD + FOOT_DZ
	var ball := Vector3(x, Y0 + BALL, bz)
	var ankle := Vector3(x, Y0 + ANKLE_H, bz - FOOT_DZ)
	var y_td := Y0 + yext(0.0, H_TD)
	# the flight's apex, for the fall
	var apex := Y.y
	Y.par(t0, y_td)
	var seg: Dictionary = Y.segs[Y.segs.size() - 1]
	var tau := clampf(float(seg["v0"]) / G, 0.0, t0 - float(seg["t0"]))
	apex = maxf(apex, float(seg["y0"]) + float(seg["v0"]) * tau - 0.5 * G * tau * tau)
	var fall := apex - y_td
	var want := flex_at(fall)
	var din: Dictionary = P.get("drops_in", {})
	if din.has(t0):
		want = flex_drop(float(din[t0]))
	var v_td := Y.v
	var m1 := Y.mark()
	var lo := 0.01
	var hi := 0.60
	var peak := 0.0
	for k in 22:
		var D := 0.5 * (lo + hi)
		Y.back(m1)
		var vv := minf(v_td, -0.8)
		var a := vv * vv / (2.0 * D)
		Y.v = vv
		Y.absorb(a)
		if Y.t > t1 - 0.015:
			hi = D
			continue
		Y.ease(t1, y_end if y_end > 0.0 else Y.y - y_end)
		peak = 0.0
		var tt := t0
		while tt <= t0 + 0.2501:
			var hip := Vector3(Parkour.ch(P, "x", tt) + (HIP_DX if sd == "_l" else -HIP_DX), Y.at(tt) + HIP_DY, _zat(P, tt) + HIP_DZ)
			peak = maxf(peak, knee_solved(P, sd, tt, Y.at(tt), ball))
			tt += 1.0 / 30.0
		if peak > want:
			hi = D
		else:
			lo = D
	Y.back(m1)
	var vf := minf(v_td, -0.8)
	Y.v = vf
	Y.absorb(vf * vf / (2.0 * lo))
	Y.ease(maxf(t1, Y.t + 0.05), y_end if y_end > 0.0 else Y.y - y_end)
	_hold(P, "feet", "foot" + sd, t0, t1, ball)
	_log(P, "foot" + sd, t0, t1, ball, surface, "sole (landing, fall %.2f m, knee peak %.0f deg)" % [fall, peak])
	(P["landings"] as Array).append({"foot": sd, "t": t0, "fall": fall, "peak": peak})
	return [t1, fall, peak]


## the planned knee absorption peak for a pelvis fall (deg): 30.8 deg per m (the published knee-dominant slope) from 52 deg at 0.3 m
## the planned knee absorption peak for a drop of the feet (deg): the published knee-dominant slope, 30.8 deg per m, from 50 deg
static func flex_drop(drop: float) -> float:
	return 50.0 + 30.8 * drop


static func flex_at(fall: float) -> float:
	return 52.0 + 30.8 * (fall - 0.3)


## the landings as the feet see them: [foot, touchdown, the start of the flight the drop is read from]
const LANDS := [["_r", 1.48, 1.00], ["_l", 2.84, 2.16], ["_r", 4.30, 4.15], ["_l", 6.58, 6.04]]


## the plan, built twice: the first pass lays the feet's flight paths, the second sets each landing's absorption from the drop of
## the feet in that flight (the apex of the lower foot to the touchdown sole)
static func build() -> Dictionary:
	var P1 := _build({})
	var drops := {}
	for l in LANDS:
		drops[l[1]] = feet_drop(P1, float(l[1]), float(l[2]))
	var P := _build(drops)
	P["drops"] = drops
	return P


## the drop of the feet into a landing (m): the highest the lower foot's toe base gets after k0, less the sole on the roof
static func feet_drop(P: Dictionary, t0: float, k0: float) -> float:
	var apex := -INF
	var t := k0
	while t <= t0 + 1e-6:
		var yl: float = (PartKeys.at(P["feet"]["foot_l"], t) as Vector3).y
		var yr: float = (PartKeys.at(P["feet"]["foot_r"], t) as Vector3).y
		apex = maxf(apex, minf(yl, yr))
		t += 1.0 / 30.0
	return apex - (Y0 + BALL)


static func _build(drops: Dictionary) -> Dictionary:
	var P := {"drops_in": drops, "obstacles": obstacles(), "length": 8.0, "lift": false, "two_pass": false,
		"root": {"z": [], "y": [], "x": [], "p": [], "r": [], "s": [], "tw": []},
		"feet": {"foot_l": [], "foot_r": []}, "hands": {"hand_l": [], "hand_r": []}, "fk": [], "poles": {}, "schedule": [], "snap": [],
		"landings": []}
	var L := "_l"
	var R := "_r"
	var zl := LEDGE_Z
	# ================= 0 the trunk (pitch, roll, spine bend): the shoulders' place over the pelvis depends on it, so it comes first
	_rows(P, "x", [[0, 0], [3.0, 0], [3.4, 0.52], [3.62, 0.52], [3.77, 0.55], [3.92, 0.52], [4.15, 0.52], [4.46, 0.0], [8.0, 0.0]])
	_rows(P, "p", [[0, 10], [0.7, 12], [0.97, 15], [1.10, 5], [1.24, 5], [1.45, 12], [1.56, 12], [2.1, 12], [2.2, 40], [2.35, 80], [2.44, 90], [2.56, 75], [2.66, 45], [2.78, 20], [2.86, 12],
		[3.3, 12], [3.45, 8], [4.15, 8], [4.40, 12], [4.8, 12], [4.95, 22], [5.30, 24], [5.50, 24], [5.64, 24], [5.74, 45], [5.84, 40], [5.96, 25], [6.06, 15],
		[6.30, 8], [6.45, 12], [6.58, 12], [6.70, 18], [6.80, 40], [6.95, 200], [7.08, 330], [7.15, 360], [7.25, 372], [7.36, 340], [7.5, -80], [8.0, -82]])
	# the speed vault tips the body toward the planted right hand ("tw" is the pelvis's side tilt, the body lies sideways over the box);
	# "r" is the pelvis's turn (the wall run faces off the wall)
	_rows(P, "tw", [[0, 0], [0.95, 0], [1.10, -45], [1.28, -45], [1.45, 0], [3.3, 0], [3.45, -10], [4.15, -10], [4.40, 0], [8.0, 0]])
	_rows(P, "r", [[0, 0], [3.2, 0], [3.45, -22], [4.2, -22], [4.45, 0], [8.0, 0]])
	_rows(P, "s", [[0, 6], [0.9, 6], [1.0, 10], [1.2, 10], [1.45, 5], [2.3, 6], [2.5, 12], [2.85, 6], [3.4, 8], [4.3, 6], [5.0, 8], [5.30, 5], [5.64, 5],
		[5.74, 15], [5.90, 10], [6.2, 6], [6.6, 20], [6.9, 30], [7.2, 10], [7.4, 5], [8.0, 0]])
	for k in ["x", "p", "r", "s", "tw"]:
		_sort(P["root"][k])
	# ================= 1 the contacts that fix the pelvis in z
	# speed vault: the right palm on the box's near edge; at mid-plant (1.17) the right shoulder is 5 cm past the wrist
	var hv := Vector3(-0.35, Y0 + 0.8 + PALM_Y, 5.0)
	var zv := _wrist_of(hv).z + 0.05 - sh_off(P, 1.17, R).z
	# kong: both palms on the box's FAR edge (a dive kong: the hands reach long, the body is already over the box); at 2.44 the
	# shoulders are over the wrists
	var kz := 10.0 - 0.01
	var hkl := Vector3(0.20, Y0 + 1.0 + PALM_Y, kz)
	var hkr := Vector3(-0.20, Y0 + 1.0 + PALM_Y, kz)
	var zk := _wrist_of(hkl).z - 0.5 * (sh_off(P, 2.44, L).z + sh_off(P, 2.44, R).z)
	# the cat leap and the climb-up: the palms hook the wall top's near edge; the SHOULDER path about the palms is the plan
	# (hang, sag, pull, over the edge, press), the pelvis follows from it through the trunk
	var palm_c := Vector3(0.0, Y0 + 1.7 + 0.022, zl - 0.005)
	# the shoulder goes AROUND the wrist (never nearer than a folded arm, 0.22 m): behind it through the pull, over it in the press
	var shk := [{"t": 5.30, "v": Vector3(0, -0.42, -0.30)}, {"t": 5.42, "v": Vector3(0, -0.44, -0.31)}, {"t": 5.50, "v": Vector3(0, -0.42, -0.30)},
		{"t": 5.64, "v": Vector3(0, -0.05, -0.30)}, {"t": 5.70, "v": Vector3(0, 0.15, -0.26)}, {"t": 5.76, "v": Vector3(0, 0.30, -0.12)}, {"t": 5.84, "v": Vector3(0, 0.46, 0.06)}]
	var pel_c := func(tt: float) -> Vector3:
		var so := 0.5 * (sh_off(P, tt, L) + sh_off(P, tt, R))
		return palm_c + (PartKeys.at(shk, tt) as Vector3) - so
	var rows := [[0.0, zv - 0.36 - 4.2 * 1.07], [1.07, zv - 0.36], [1.17, zv], [1.27, zv + 0.36], [1.48, zv + 1.20], [1.74, zv + 1.20 + 0.65],
		[2.34, zk - 0.34], [2.44, zk], [2.54, zk + 0.34], [2.84, zk + 1.42], [3.10, zk + 2.07], [4.30, 17.10], [4.56, 17.75], [4.89, 19.35]]
	var tc := 5.30
	while tc <= 5.8401:
		rows.append([tc, (pel_c.call(tc) as Vector3).z])
		tc += 1.0 / 30.0
	var z_off := zl + 0.38
	rows += [[5.96, zl + 0.08], [6.06, z_off], [6.58, z_off + 3.0 * 0.52], [6.82, z_off + 3.0 * 0.52 + 0.65], [7.2, z_off + 3.0 * 0.52 + 1.85],
		[7.6, z_off + 3.0 * 0.52 + 2.95], [8.0, z_off + 3.0 * 0.52 + 3.85]]
	_zk(P, rows)
	_sort(P["root"]["z"])
	# ================= 2 the contacts in time order: each fixes its limb's point and the pelvis height around it
	var Y := YPath.new()
	_stance(P, Y, R, 0.00, 0.18, "run")
	_stance(P, Y, L, 0.27, 0.45, "run")
	_stance(P, Y, R, 0.53, 0.70, "run")
	_stance(P, Y, L, 0.80, 0.97, "off", "roof")
	# the speed vault: the right palm 1.10-1.24; the pelvis rides the arm (inverted pendulum over the hand), ballistic either side
	var vpalm := [[R, hv]]
	Y.par(1.10, arm_y(P, 1.10, vpalm, ARM_CH))
	Y.fn(1.24, func(tt: float) -> float: return arm_y(P, tt, vpalm, ARM_CH))
	_hand_palm(P, R, 1.10, 1.24, hv, "boxSpeed")
	_land(P, Y, R, 1.48, 1.74, "roof", _y_run(P, R, 1.74, 1.48))
	_stance(P, Y, L, 1.78, 1.95, "run")
	_stance(P, Y, R, 2.02, 2.16, "off")
	# the kong: both palms 2.35-2.56 on the far edge
	var kpalm := [[L, hkl], [R, hkr]]
	Y.par(2.35, arm_y(P, 2.35, kpalm, ARM_CH))
	Y.fn(2.56, func(tt: float) -> float: return arm_y(P, tt, kpalm, ARM_CH))
	_hand_palm(P, L, 2.35, 2.56, hkl, "boxKong", Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1))
	_hand_palm(P, R, 2.35, 2.56, hkr, "boxKong", Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1))
	_land(P, Y, L, 2.84, 3.07, "roof", _y_run(P, L, 3.07, 2.84))
	_stance(P, Y, R, 3.12, 3.26, "run")
	# the wall run: the TOE BASE is pinned on the wall face (the foot pivots about it, the ankle's inversion stop allowing);
	# the pelvis rides the leg's reach above it
	var wall_steps := [[L, 3.40, 3.57, 0.57], [R, 3.70, 3.85, 0.74], [L, 4.00, 4.15, 0.62]]
	for w in wall_steps:
		var sd: String = w[0]
		var tm: float = 0.5 * (float(w[1]) + float(w[2]))
		var az := _zat(P, tm)
		var ankle := Vector3(WALL_X - DEPTH_SOLE, Y0 + float(w[3]), az)
		var ballw := Vector3(WALL_X - 0.06, Y0 + float(w[3]), az + 0.10)
		var o0 := _hip_off(P, sd, float(w[1]), ankle)
		var o1 := _hip_off(P, sd, float(w[2]), ankle)
		var om := _hip_off(P, sd, tm, ankle)
		Y.par(float(w[1]), Y0 + float(w[3]) - ANKLE_H + yext(o0.x, o0.y) - 0.05)
		var ym := Y0 + float(w[3]) - ANKLE_H + yext(om.x, om.y) - 0.09
		Y.dip(float(w[2]), Y0 + float(w[3]) - ANKLE_H + yext(o1.x, o1.y) - 0.05, ym)
		_hold(P, "feet", "foot" + sd, float(w[1]), float(w[2]), ballw, "wall")
		_log(P, "foot" + sd, float(w[1]), float(w[2]), ballw, "wall", "toe base on the wall")
	_land(P, Y, R, 4.30, 4.56, "roofB", _y_run(P, R, 4.56, 4.30))
	_stance(P, Y, L, 4.62, 4.76, "run", "roofB")
	_stance(P, Y, R, 4.82, 4.96, "off", "roofB")
	# the cat leap: flight to the wall top, palms hooked on its near edge 5.30-5.86 through the catch, the pull and the press
	Y.par(5.30, (pel_c.call(5.30) as Vector3).y)
	Y.fn(5.84, func(tt: float) -> float: return (pel_c.call(tt) as Vector3).y)
	var hook := Vector3(0, 1, -1)
	_hand_palm(P, L, 5.30, 5.86, palm_c + Vector3(0.20, 0, 0), "ledge", hook, Vector3.UP, Vector3(0, 0, 1))
	_hand_palm(P, R, 5.30, 5.86, palm_c + Vector3(-0.20, 0, 0), "ledge", hook, Vector3.UP, Vector3(0, 0, 1))
	# the feet hang free at the catch: on a 1.7 m wall the toes reach the face near its foot, and a knee bent to them runs into it
	# up: the right foot onto the wall top, the take-off from it over the far edge
	var top_r := Vector3(-0.10, Y0 + 1.7 + BALL, zl + 0.30)
	Y.ease(5.96, Y0 + 1.7 + 0.64)
	Y.ease(6.06, Y0 + 1.7 + 0.80)
	_hold(P, "feet", "foot_r", 5.98, 6.06, top_r)
	_log(P, "foot_r", 5.98, 6.06, top_r, "ledge top", "sole (take-off)")
	# the drop: ballistic from the take-off to the landing on both feet, then the hands, the shoulder, the back (the roll: "from the feet
	# to the hands and to the back", "Kinematic analyses of Parkour landings from as high as 2.7 m", J Hum Kinet 72 (2020),
	# doi 10.2478/hukin-2019-0123; shoulder to the opposite side, Puddle & Maulder 2013 J Sports Sci Med, PMC3761764)
	# the legs extend 15 cm out of the absorption as he dives onto the hands (y_end <= 0: that far over the bottom)
	_land(P, Y, L, 6.58, 6.82, "roofB", -0.15, true)
	var bz := _zat(P, 6.58) + HIP_DZ + H_TD + FOOT_DZ
	var land_ball_r := Vector3(-0.12, Y0 + BALL, bz)
	_hold(P, "feet", "foot_r", 6.58, 6.82, land_ball_r)
	_log(P, "foot_r", 6.58, 6.82, land_ball_r, "roofB", "sole (landing)")
	var tb := Y.t
	var hz := bz + 0.30
	_hand_palm(P, L, 6.76, 6.90, Vector3(0.18, Y0 + PALM_Y, hz), "roofB")
	_hand_palm(P, R, 6.76, 6.90, Vector3(-0.18, Y0 + PALM_Y, hz), "roofB")
	Y.ease(7.0, Y0 + 0.30)
	Y.ease(7.4, Y0 + 0.20)
	Y.ease(8.0, Y0 + 0.19)
	P["snap"].append([6.86, 8.0])      # the roll and the slide: the lowest body point is the contact with the roof
	_log(P, "shoulder_r", 6.84, 6.94, Vector3.ZERO, "roofB", "shoulder (diagonal)")
	_log(P, "back", 6.94, 7.10, Vector3.ZERO, "roofB", "upper back")
	_log(P, "hip_l", 7.10, 7.20, Vector3.ZERO, "roofB", "opposite hip")
	# ================= the pelvis y channel: dense samples of the path
	var t := -0.1
	while t <= 8.0001:
		(P["root"]["y"] as Array).append({"t": snappedf(t, 0.0001), "v": Vector3(Y.at(maxf(t, 0.0)), 0, 0)})
		t += 1.0 / 60.0
	P["ypath_bottom"] = tb
	# ================= 3 the free limbs
	_free_feet(P)
	_free_hands(P)
	for g in ["feet", "hands"]:
		for k in P[g]:
			_sort(P[g][k])
	# the roll: the limbs are FK-tucked while the pelvis turns (angles in degrees, bend/side/twist)
	P["fk"].append({"t0": 6.92, "t1": 7.20, "ramp": 0.08, "ang": {
		"thigh_l": Vector3(115, 4, 0), "thigh_r": Vector3(115, -4, 0), "calf_l": Vector3(125, 0, 0), "calf_r": Vector3(125, 0, 0),
		"foot_l": Vector3(20, 0, 0), "foot_r": Vector3(20, 0, 0),
		"upperarm_l": Vector3(70, -30, 0), "upperarm_r": Vector3(70, -30, 0), "lowerarm_l": Vector3(95, 0, 0), "lowerarm_r": Vector3(95, 0, 0)}})
	return P


## the pelvis height a run leaves a landing at: the leg's reach at t1, no higher than a run's mid-stance spring
static func _y_run(P: Dictionary, sd: String, t1: float, t0: float) -> float:
	var bz := _zat(P, t0) + HIP_DZ + H_TD + FOOT_DZ
	var ankle := Vector3(0.09 if sd == "_l" else -0.09, Y0 + ANKLE_H, bz - FOOT_DZ)
	var o := _hip_off(P, sd, t1, ankle)
	return Y0 + minf(yext(o.x, o.y), HIP_MID + 0.02)


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
		if pt.z < 14.3 or pt.z > 17.2:
			pt.y = maxf(pt.y, Y0 + 0.06)   # a free foot stays over the roof it runs on
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
		[0.97, Vector3(0.12, -0.60, -0.30)], [1.12, Vector3(0.20, -0.12, 0.45)], [1.25, Vector3(0.15, -0.10, 0.68)], [1.35, Vector3(0.15, -0.25, 0.65)], [1.44, Vector3(0.15, -0.55, 0.45)],
		[1.55, Vector3(0.12, -0.55, 0.40)], [1.78, Vector3(0.09, -0.62, 0.10)]])
	_flight(P, "feet", "foot_r", 0.70, pt.call(R, 0.70), 1.48, pt.call(R, 1.48), [
		[0.70, Vector3(-0.09, -0.50, -0.30)], [0.85, Vector3(-0.12, -0.45, 0.20)], [1.0, Vector3(-0.15, -0.35, -0.35)], [1.15, Vector3(0.0, -0.15, 0.45)],
		[1.25, Vector3(-0.02, -0.12, 0.68)], [1.35, Vector3(-0.05, -0.30, 0.62)], [1.42, Vector3(-0.08, -0.55, 0.50)], [1.48, Vector3(-0.09, -0.80, 0.50)]])
	# kong: legs tuck up between the arms, then reach for the roof
	_flight(P, "feet", "foot_l", 1.95, pt.call(L, 1.95), 2.84, pt.call(L, 2.84), [
		[1.95, Vector3(0.09, -0.60, -0.30)], [2.20, Vector3(0.12, -0.40, -0.30)], [2.45, Vector3(0.12, -0.15, 0.05)], [2.60, Vector3(0.12, -0.10, 0.30)],
		[2.72, Vector3(0.10, -0.32, 0.55)], [2.84, Vector3(0.09, -0.80, 0.55)]])
	_flight(P, "feet", "foot_r", 2.16, pt.call(R, 2.16), 3.12, pt.call(R, 3.12), [
		[2.16, Vector3(-0.10, -0.55, -0.40)], [2.30, Vector3(-0.12, -0.40, -0.28)], [2.45, Vector3(-0.12, -0.15, 0.05)], [2.62, Vector3(-0.12, -0.10, 0.30)],
		[2.75, Vector3(-0.10, -0.38, 0.55)], [2.95, Vector3(-0.09, -0.65, 0.20)], [3.12, Vector3(-0.09, -0.70, 0.45)]])
	# wall run: the swing between wall steps
	_flight(P, "feet", "foot_r", 3.26, pt.call(R, 3.26), 3.70, pt.call(R, 3.70), [
		[3.26, Vector3(-0.09, -0.70, 0.30)], [3.45, Vector3(-0.10, -0.55, 0.25)], [3.60, Vector3(0.10, -0.55, 0.30)]])
	_flight(P, "feet", "foot_l", 3.10, pt.call(L, 3.10), 3.40, pt.call(L, 3.40), [
		[3.10, Vector3(0.09, -0.65, -0.20)], [3.22, Vector3(0.12, -0.45, 0.25)], [3.30, Vector3(0.12, -0.45, 0.30)]])
	_flight(P, "feet", "foot_l", 3.57, pt.call(L, 3.57), 4.00, pt.call(L, 4.00), [
		[3.57, Vector3(0.20, -0.55, -0.10)], [3.80, Vector3(0.16, -0.50, 0.25)], [3.92, Vector3(0.16, -0.45, 0.20)]])
	_flight(P, "feet", "foot_r", 3.85, pt.call(R, 3.85), 4.30, pt.call(R, 4.30), [
		[3.85, Vector3(0.0, -0.55, -0.20)], [4.05, Vector3(-0.09, -0.50, 0.10)], [4.20, Vector3(-0.09, -0.62, 0.35)], [4.30, Vector3(-0.09, -0.80, 0.50)]])
	_flight(P, "feet", "foot_l", 4.15, pt.call(L, 4.15), 4.62, pt.call(L, 4.62), [
		[4.15, Vector3(0.10, -0.45, -0.15)], [4.30, Vector3(0.10, -0.55, -0.30)], [4.45, Vector3(0.09, -0.50, 0.10)], [4.62, Vector3(0.09, -0.70, 0.40)]])
	# cat leap and climb-up: knees up after the take-off, the legs hang under the pelvis through the catch and the pull (knees off
	# the face), the right foot steps onto the wall top, the left knee tucks over the edge; then both reach for the landing
	_flight(P, "feet", "foot_l", 4.76, pt.call(L, 4.76), 6.58, pt.call(L, 6.58), [
		[4.76, Vector3(0.09, -0.60, -0.15)], [4.96, Vector3(0.10, -0.55, -0.40)], [5.12, Vector3(0.12, -0.45, 0.10)], [5.25, Vector3(0.12, -0.55, 0.15)],
		[5.40, Vector3(0.12, -0.62, 0.10)], [5.66, Vector3(0.12, -0.75, -0.02)], [5.84, Vector3(0.12, -0.80, -0.05)], [5.96, Vector3(0.12, -0.45, 0.10)],
		[6.10, Vector3(0.12, -0.40, 0.10)], [6.30, Vector3(0.12, -0.52, 0.20)], [6.50, Vector3(0.12, -0.62, 0.25)], [6.58, Vector3(0.12, -0.80, 0.50)]], 0.12)
	_flight(P, "feet", "foot_r", 4.96, pt.call(R, 4.96), 5.98, pt.call(R, 5.98), [
		[4.96, Vector3(-0.09, -0.62, -0.20)], [5.05, Vector3(-0.10, -0.50, -0.30)], [5.20, Vector3(-0.12, -0.50, 0.20)], [5.40, Vector3(-0.12, -0.62, 0.10)],
		[5.66, Vector3(-0.12, -0.75, -0.02)], [5.84, Vector3(-0.12, -0.80, -0.05)], [5.88, Vector3(-0.11, -0.45, 0.0)], [5.93, Vector3(-0.11, -0.30, 0.30)]], 0.14)
	_flight(P, "feet", "foot_r", 6.06, pt.call(R, 6.06), 6.58, pt.call(R, 6.58), [
		[6.06, Vector3(-0.09, -0.75, -0.20)], [6.20, Vector3(-0.10, -0.50, 0.10)], [6.45, Vector3(-0.12, -0.60, 0.30)], [6.58, Vector3(-0.12, -0.80, 0.50)]], 0.12)
	# the roll then the slide: the legs follow the trunk (FK tuck), then both reach forward on the slide
	for sd in ["_l", "_r"]:
		var sg := 1.0 if sd == "_l" else -1.0
		_rel(P, "feet", "foot" + sd, 6.90, Vector3(sg * 0.12, -0.55, 0.45))
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
	# the kong: both palms reach long, over the box top, for its far edge
	_rel(P, "hands", "hand_l", 2.16, Vector3(0.25, 0.1, 0.5))
	_rel(P, "hands", "hand_r", 2.16, Vector3(-0.25, 0.1, 0.5))
	_free(P, "hands", "hand_l", 2.27, Vector3(0.20, Y0 + 1.22, 9.70))
	_free(P, "hands", "hand_r", 2.27, Vector3(-0.20, Y0 + 1.22, 9.70))
	_free(P, "hands", "hand_r", 1.28, Vector3(-0.40, Y0 + 0.98, 5.06))
	_free(P, "hands", "hand_l", 2.61, Vector3(0.22, Y0 + 1.16, 10.06))
	_free(P, "hands", "hand_r", 2.61, Vector3(-0.22, Y0 + 1.16, 10.06))
	_free(P, "hands", "hand_l", 5.91, Vector3(0.24, Y0 + 1.86, LEDGE_Z + 0.06))
	_free(P, "hands", "hand_r", 5.91, Vector3(-0.24, Y0 + 1.86, LEDGE_Z + 0.06))
	_rel(P, "hands", "hand_l", 2.72, Vector3(0.30, 0.15, 0.2))
	_rel(P, "hands", "hand_r", 2.72, Vector3(-0.30, 0.15, 0.2))
	# the wall run: the hands stay clear, arms out for balance
	for tt in [3.40, 3.70, 4.00]:
		_rel(P, "hands", "hand_r", tt, Vector3(-0.40, 0.25, 0.35))
		_rel(P, "hands", "hand_l", tt, Vector3(-0.10, 0.15, -0.30))
	# the cat leap: reach for the edge
	_rel(P, "hands", "hand_l", 4.96, Vector3(0.20, 0.30, 0.45))
	_rel(P, "hands", "hand_r", 4.96, Vector3(-0.20, 0.30, 0.45))
	_free(P, "hands", "hand_l", 5.22, Vector3(0.20, Y0 + 1.85, LEDGE_Z - 0.10))
	_free(P, "hands", "hand_r", 5.22, Vector3(-0.20, Y0 + 1.85, LEDGE_Z - 0.10))
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
