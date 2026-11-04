## parkour_plan.gd - CH7: the course and the choreography of the 8 s chained run (see parkour.gd for the engine).
## The route, every number MINE (taste fitted to the bars in tests/ch7_test.gd, not data); the reference numbers it is held to
## are in docs/CH7_REFERENCE.md. He runs +z at about 4.2 m/s on the roofs (Y0 over the street):
##   0.0-0.9  run-in            0.9-1.5  SPEED VAULT over the 80 cm box (right hand on the near edge, legs to his left)
##   1.5-2.1  run               2.1-2.85 KONG over the 100 cm box (both hands on the near edge, legs between the arms)
##   2.85-3.4 run               3.4-4.3  WALL RUN along the wall across the 3.7 m gap (feet on the wall face, no roof under)
##   4.3-4.9  run               4.9-6.05 CAT LEAP onto the 1.7 m ledge (hands on the edge, feet on the face), mantle, step off
##   6.05-6.6 the 1.7 m DROP    6.6-7.2  ROLL     7.2-8.0 SLIDE under the low bar
## Contacts: a limb key {"t", "v", "c"}: two keys with c = true at the same point are one CONTACT (held, flat foot / flat palm).
class_name ParkourPlan
extends RefCounted

const Y0 := Parkour.Y0
const BALL := 0.0152          # a flat foot's toe base above the surface (Body p0 ball y)
const WRIST := 0.098          # a hand plant's wrist above the surface: the palm cannot lie flat (the wrist stops at 50 deg, measured: ContactIK gap -0.04 at 0.054), so the wrist rides 4 cm higher
const HIP := 0.80             # pelvis height over the roof in a run's stance (m)
const DEPTH_SOLE := 0.104     # ankle to sole (m): a foot on a wall has its ankle this far off it


static func obstacles() -> Array:
	return [
		{"name": "roofA", "lo": Vector3(-3, 0, -8), "hi": Vector3(3, Y0, 14.3)},
		{"name": "boxSpeed", "lo": Vector3(-1.5, Y0, 5.0), "hi": Vector3(1.5, Y0 + 0.8, 5.6)},
		{"name": "boxKong", "lo": Vector3(-1.5, Y0, 10.0), "hi": Vector3(1.5, Y0 + 1.0, 10.6)},
		{"name": "wall", "lo": Vector3(0.8, 0, 13.0), "hi": Vector3(0.95, Y0 + 2.6, 19.0)},
		{"name": "roofB", "lo": Vector3(-3, 0, 18.0), "hi": Vector3(3, Y0, 40)},
		{"name": "ledge", "lo": Vector3(-1.5, Y0, 22.7), "hi": Vector3(1.5, Y0 + 1.7, 24.4)},
		{"name": "barPostL", "lo": Vector3(1.15, Y0, 29.8), "hi": Vector3(1.25, Y0 + 0.75, 29.9)},
		{"name": "barPostR", "lo": Vector3(-1.25, Y0, 29.8), "hi": Vector3(-1.15, Y0 + 0.75, 29.9)},
		{"name": "bar", "lo": Vector3(-1.25, Y0 + 0.65, 29.8), "hi": Vector3(1.25, Y0 + 0.75, 29.9)},
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


static func _rows(P: Dictionary, chn: String, rows: Array) -> void:
	for r in rows:
		(P["root"][chn] as Array).append({"t": float(r[0]), "v": Vector3(float(r[1]), 0, 0)})


static func _sort(a: Array) -> void:
	a.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))


## a contact: two keys at one point. mode "" = flat sole / flat palm, "wall" = sole on a wall at x, "face" = sole on a wall facing -z
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


## a free key at an offset from the pelvis's own place at t (the root must be complete)
static func _rel(P: Dictionary, grp: String, tip: String, t: float, off: Vector3) -> void:
	var r := Parkour.root_at(P, t)
	_free(P, grp, tip, t, Vector3(float(r["x"]), float(r["y"]), float(r["z"])) + off)


static func _stance(P: Dictionary, sd: String, t0: float, t1: float, zoff := 0.0, y := 0.0, xoff := 0.0, mode := "") -> void:
	var r := Parkour.root_at(P, (t0 + t1) * 0.5)
	var x := (0.09 if sd == "_l" else -0.09) + xoff
	_hold(P, "feet", "foot" + sd, t0, t1, Vector3(x, Y0 + BALL + y, float(r["z"]) + zoff), mode)


static func build() -> Dictionary:
	var P := {"obstacles": obstacles(), "length": 8.0, "lift": true,
		"root": {"z": [], "y": [], "x": [], "p": [], "r": [], "s": [], "tw": []},
		"feet": {"foot_l": [], "foot_r": []}, "hands": {"hand_l": [], "hand_r": []}, "fk": [], "poles": {}}
	# ---------------- the pelvis: z (the way he runs)
	_rows(P, "z", [[0, -0.2], [1.0, 4.0], [1.24, 5.0], [1.48, 6.0], [2.16, 8.86], [2.5, 10.28], [2.84, 11.7], [3.25, 13.42], [4.46, 18.5],
		[4.89, 20.4], [5.30, 22.2], [5.45, 22.25], [5.78, 23.15], [6.0, 24.0], [6.58, 25.8], [7.10, 27.4], [7.30, 28.1], [8.0, 30.6]])
	# ---------------- the pelvis: y. A run is low; a flight is a parabola (g = 9.81)
	var run_y := Y0 + HIP
	_rows(P, "y", [[0.0, run_y + 0.03], [0.09, run_y], [0.18, run_y + 0.06], [0.36, run_y + 0.10], [0.50, run_y + 0.06], [0.61, run_y], [0.75, run_y + 0.07], [0.90, run_y + 0.0],
		[1.00, run_y + 0.03], [1.12, Y0 + 1.08], [1.24, Y0 + 1.12], [1.36, Y0 + 1.08], [1.48, run_y + 0.0],
		[1.56, run_y], [1.70, run_y + 0.07], [1.86, run_y], [2.00, run_y + 0.07], [2.09, run_y], [2.16, run_y + 0.03],
		[2.30, Y0 + 1.35], [2.50, Y0 + 1.50], [2.70, Y0 + 1.25], [2.84, run_y], [2.92, run_y - 0.02], [3.05, run_y + 0.07], [3.18, run_y], [3.30, run_y + 0.05],
		[3.485, Y0 + 1.15], [3.63, Y0 + 1.22], [3.775, Y0 + 1.27], [3.93, Y0 + 1.27], [4.075, Y0 + 1.22], [4.20, Y0 + 1.08], [4.30, Y0 + 0.93], [4.385, run_y],
		[4.52, run_y + 0.06], [4.68, run_y], [4.82, run_y + 0.06], [4.89, run_y + 0.03], [5.0, Y0 + 0.95], [5.15, Y0 + 1.05], [5.30, Y0 + 0.90],
		[5.45, Y0 + 0.88], [5.62, Y0 + 1.7], [5.78, Y0 + 2.45], [5.92, Y0 + 2.50], [6.0, Y0 + 2.50], [6.2, Y0 + 2.62], [6.30, Y0 + 2.45], [6.40, Y0 + 1.95], [6.50, Y0 + 1.1],
		[6.58, Y0 + 0.62], [6.70, Y0 + 0.42], [6.85, Y0 + 0.36], [7.0, Y0 + 0.38], [7.12, Y0 + 0.62], [7.25, Y0 + 0.62], [7.38, Y0 + 0.30], [7.5, Y0 + 0.20], [8.0, Y0 + 0.19]])
	_rows(P, "x", [[0, 0], [3.0, 0], [3.4, 0.52], [4.15, 0.52], [4.46, 0.0], [8.0, 0.0]])
	# ---------------- the trunk's lean (p, degrees forward) and roll (r, to his left)
	_rows(P, "p", [[0, 10], [0.7, 12], [1.0, 30], [1.12, 70], [1.30, 75], [1.45, 25], [1.56, 12], [2.1, 12], [2.16, 30], [2.35, 80], [2.55, 85], [2.72, 40], [2.86, 12],
		[3.3, 12], [3.45, 8], [4.15, 8], [4.40, 12], [4.8, 12], [4.95, 25], [5.25, 5], [5.45, 0], [5.62, 25], [5.8, 20], [6.0, 12], [6.2, 5], [6.45, 25], [6.58, 40], [6.72, 70],
		[6.9, 200], [7.05, 330], [7.15, 360], [7.25, 372], [7.36, 340], [7.5, -80], [8.0, -82]])
	_rows(P, "r", [[0, 0], [3.2, 0], [3.45, -22], [4.2, -22], [4.45, 0], [8.0, 0]])
	_rows(P, "s", [[0, 6], [0.9, 6], [1.2, 15], [1.45, 5], [2.3, 6], [2.5, 12], [2.85, 6], [3.4, 8], [4.3, 6], [5.0, 8], [5.4, 0], [5.7, 10], [6.2, 6], [6.6, 20], [6.9, 30],
		[7.2, 10], [7.4, 5], [8.0, 0]])
	for k in P["root"]:
		_sort(P["root"][k])
	# ---------------- the feet: contacts (ball on the roof under the pelvis at mid-contact), swings between them
	var L := "_l"
	var R := "_r"
	_stance(P, R, 0.00, 0.18)
	_stance(P, L, 0.27, 0.45)
	_stance(P, R, 0.53, 0.70)
	_stance(P, L, 0.80, 1.00, 0.0, 0.0, 0.0)     # the speed vault's take-off
	_stance(P, R, 1.48, 1.64, 0.1)
	_stance(P, L, 1.78, 1.95)
	_stance(P, R, 2.02, 2.16)                  # the kong's take-off
	_stance(P, L, 2.84, 3.00, 0.1)
	_stance(P, R, 3.10, 3.26)
	# the wall run: soles on the wall face (x = 0.8), the pelvis well out from it
	_hold(P, "feet", "foot_l", 3.40, 3.57, Vector3(0.8 - DEPTH_SOLE, Y0 + 0.57, float(Parkour.root_at(P, 3.485)["z"])), "wall")
	_hold(P, "feet", "foot_r", 3.70, 3.85, Vector3(0.8 - DEPTH_SOLE, Y0 + 0.74, float(Parkour.root_at(P, 3.775)["z"])), "wall")
	_hold(P, "feet", "foot_l", 4.00, 4.15, Vector3(0.8 - DEPTH_SOLE, Y0 + 0.62, float(Parkour.root_at(P, 4.075)["z"])), "wall")
	_stance(P, R, 4.30, 4.47, 0.05)
	_stance(P, L, 4.60, 4.76)
	_stance(P, R, 4.82, 4.96)                  # the cat leap's take-off
	# the cat: soles on the ledge's face (z = 22.7) under the hands
	_hold(P, "feet", "foot_l", 5.32, 5.50, Vector3(0.12, Y0 + 0.78, 22.7 - DEPTH_SOLE), "face")
	_hold(P, "feet", "foot_r", 5.32, 5.50, Vector3(-0.12, Y0 + 0.55, 22.7 - DEPTH_SOLE), "face")
	_hold(P, "feet", "foot_r", 5.78, 5.92, Vector3(-0.09, Y0 + 1.7 + BALL, 23.25))   # up on the ledge
	_hold(P, "feet", "foot_l", 5.94, 6.04, Vector3(0.09, Y0 + 1.7 + BALL, 24.05))     # the step off its edge
	_hold(P, "feet", "foot_l", 6.58, 6.68, Vector3(0.12, Y0 + BALL, 25.65))            # the landing, both feet, into the roll
	_hold(P, "feet", "foot_r", 6.58, 6.68, Vector3(-0.12, Y0 + BALL, 25.65))
	# swings: a free foot passes through its mid-swing keys (relative to the pelvis)
	var sw := [
		["_r", 0.18, 0.27], ["_l", 0.45, 0.53], ["_r", 0.70, 0.80],
		["_r", 1.64, 1.78], ["_l", 1.95, 2.02], ["_l", 3.00, 3.10], ["_r", 3.26, 3.40],
		["_l", 3.57, 3.70], ["_r", 3.85, 4.00], ["_l", 4.15, 4.30], ["_r", 4.47, 4.60], ["_l", 4.76, 4.82]]
	for s in sw:
		_swing(P, String(s[0]), float(s[1]), float(s[2]))
	# the speed vault: after the left foot leaves (1.0) both legs fold up to his left over the box, the right comes through, land R then L
	_rel(P, "feet", "foot_l", 1.12, Vector3(0.45, -0.05, -0.30))
	_rel(P, "feet", "foot_l", 1.30, Vector3(0.50, 0.0, -0.15))
	_rel(P, "feet", "foot_l", 1.37, Vector3(0.30, -0.10, 0.10))
	_rel(P, "feet", "foot_l", 1.42, Vector3(0.15, -0.50, 0.30))
	_free(P, "feet", "foot_l", 1.45, Vector3(0.09, Y0 + 0.28, 5.95))
	_rel(P, "feet", "foot_r", 1.00, Vector3(-0.15, -0.55, -0.45))
	_rel(P, "feet", "foot_r", 1.15, Vector3(0.40, -0.02, -0.30))
	_rel(P, "feet", "foot_r", 1.32, Vector3(0.50, 0.0, -0.05))
	_rel(P, "feet", "foot_r", 1.36, Vector3(0.15, -0.08, 0.25))
	_rel(P, "feet", "foot_r", 1.40, Vector3(-0.09, -0.55, 0.35))
	# the kong: after 2.16 the legs tuck up between the arms, then reach for the roof
	_rel(P, "feet", "foot_l", 2.02, Vector3(0.09, -0.65, -0.35))
	_rel(P, "feet", "foot_l", 2.30, Vector3(0.12, -0.35, -0.30))
	_rel(P, "feet", "foot_l", 2.55, Vector3(0.12, -0.28, 0.25))
	_rel(P, "feet", "foot_l", 2.72, Vector3(0.10, -0.62, 0.35))
	_rel(P, "feet", "foot_r", 2.16, Vector3(-0.10, -0.55, -0.45))
	_rel(P, "feet", "foot_r", 2.32, Vector3(-0.12, -0.35, -0.28))
	_rel(P, "feet", "foot_r", 2.55, Vector3(-0.12, -0.30, 0.22))
	_rel(P, "feet", "foot_r", 2.72, Vector3(-0.10, -0.62, 0.45))
	# cat leap flight: knees up to the face
	_rel(P, "feet", "foot_l", 4.96, Vector3(0.10, -0.55, -0.40))
	_rel(P, "feet", "foot_l", 5.12, Vector3(0.12, -0.45, 0.10))
	_rel(P, "feet", "foot_l", 5.24, Vector3(0.12, -0.52, 0.30))
	_rel(P, "feet", "foot_r", 5.05, Vector3(-0.10, -0.50, -0.30))
	_rel(P, "feet", "foot_r", 5.20, Vector3(-0.12, -0.50, 0.20))
	# the mantle to the ledge's top and the step off, the drop
	_rel(P, "feet", "foot_l", 5.60, Vector3(0.12, -0.50, 0.05))
	_rel(P, "feet", "foot_l", 5.75, Vector3(0.10, -0.40, -0.25))
	_rel(P, "feet", "foot_r", 5.50, Vector3(-0.12, -0.55, 0.0))
	_rel(P, "feet", "foot_r", 5.64, Vector3(-0.12, -0.60, 0.10))
	_rel(P, "feet", "foot_r", 6.04, Vector3(-0.10, -0.55, -0.20))
	_rel(P, "feet", "foot_r", 6.25, Vector3(-0.10, -0.45, 0.25))
	_rel(P, "feet", "foot_r", 6.45, Vector3(-0.12, -0.60, 0.30))
	_rel(P, "feet", "foot_l", 6.04, Vector3(0.10, -0.40, 0.0))
	_rel(P, "feet", "foot_l", 6.30, Vector3(0.12, -0.52, 0.20))
	_rel(P, "feet", "foot_l", 6.50, Vector3(0.12, -0.62, 0.25))
	# roll then the slide: legs follow the trunk (FK tuck during the roll), then both reach forward on the slide
	_rel(P, "feet", "foot_l", 7.25, Vector3(0.09, -0.62, 0.15))
	_rel(P, "feet", "foot_r", 7.25, Vector3(-0.09, -0.62, -0.1))
	_rel(P, "feet", "foot_l", 7.40, Vector3(0.10, 0.10, 0.85))
	_rel(P, "feet", "foot_r", 7.40, Vector3(-0.10, 0.04, 0.80))
	_rel(P, "feet", "foot_l", 8.0, Vector3(0.10, 0.10, 0.85))
	_rel(P, "feet", "foot_r", 8.0, Vector3(-0.10, 0.04, 0.80))
	# ---------------- the hands
	_hand_run(P)
	var hz := 5.0     # the speed vault's right hand: on the box's near edge (z = 5.0), a hand's width from his centre line
	_hold(P, "hands", "hand_r", 1.10, 1.24, Vector3(-0.22, Y0 + 0.8 + WRIST, hz + 0.02))
	_rel(P, "hands", "hand_r", 0.95, Vector3(-0.30, 0.12, 0.40))
	_rel(P, "hands", "hand_r", 1.45, Vector3(-0.30, 0.00, 0.25))
	_rel(P, "hands", "hand_l", 1.0, Vector3(0.30, 0.20, 0.30))
	_rel(P, "hands", "hand_l", 1.2, Vector3(0.45, 0.10, 0.1))
	_rel(P, "hands", "hand_l", 1.40, Vector3(0.40, 0.10, 0.2))
	# the kong: both hands on the near edge (z = 10.0)
	_hold(P, "hands", "hand_l", 2.34, 2.48, Vector3(0.20, Y0 + 1.0 + WRIST, 10.03))
	_hold(P, "hands", "hand_r", 2.34, 2.48, Vector3(-0.20, Y0 + 1.0 + WRIST, 10.03))
	_rel(P, "hands", "hand_l", 2.16, Vector3(0.25, 0.1, 0.5))
	_rel(P, "hands", "hand_r", 2.16, Vector3(-0.25, 0.1, 0.5))
	_rel(P, "hands", "hand_l", 2.70, Vector3(0.30, 0.15, 0.2))
	_rel(P, "hands", "hand_r", 2.70, Vector3(-0.30, 0.15, 0.2))
	# the wall run: the hands stay clear, arms out for balance
	for tt in [3.40, 3.70, 4.00]:
		_rel(P, "hands", "hand_r", tt, Vector3(-0.40, 0.25, 0.35))
		_rel(P, "hands", "hand_l", tt, Vector3(-0.10, 0.15, -0.30))
	# the cat leap: reach for the edge (z = 22.7, top Y0 + 1.7), both hands on it, then push on the top
	_rel(P, "hands", "hand_l", 4.96, Vector3(0.20, 0.30, 0.45))
	_rel(P, "hands", "hand_r", 4.96, Vector3(-0.20, 0.30, 0.45))
	_hold(P, "hands", "hand_l", 5.30, 5.50, Vector3(0.20, Y0 + 1.7 + WRIST, 22.78))
	_hold(P, "hands", "hand_r", 5.30, 5.50, Vector3(-0.20, Y0 + 1.7 + WRIST, 22.78))
	_hold(P, "hands", "hand_l", 5.60, 5.80, Vector3(0.20, Y0 + 1.7 + WRIST, 23.35))
	_hold(P, "hands", "hand_r", 5.60, 5.80, Vector3(-0.20, Y0 + 1.7 + WRIST, 23.35))
	# up on the ledge, the drop: arms up and out
	for sd in ["_l", "_r"]:
		var sg := 1.0 if sd == "_l" else -1.0
		_rel(P, "hands", "hand" + sd, 6.0, Vector3(sg * 0.45, 0.30, 0.1))
		_rel(P, "hands", "hand" + sd, 6.3, Vector3(sg * 0.40, 0.55, 0.2))
		_rel(P, "hands", "hand" + sd, 6.5, Vector3(sg * 0.25, 0.20, 0.5))
	_hold(P, "hands", "hand_l", 6.62, 6.78, Vector3(0.18, Y0 + WRIST, 26.35))
	_hold(P, "hands", "hand_r", 6.62, 6.78, Vector3(-0.18, Y0 + WRIST, 26.35))
	# the slide: arms back / up, lying on his back
	for sd in ["_l", "_r"]:
		var sg := 1.0 if sd == "_l" else -1.0
		_rel(P, "hands", "hand" + sd, 7.25, Vector3(sg * 0.35, 0.1, 0.2))
		_rel(P, "hands", "hand" + sd, 7.45, Vector3(sg * 0.30, 0.0, -0.9))
		_rel(P, "hands", "hand" + sd, 8.0, Vector3(sg * 0.30, 0.0, -0.9))
	for g in ["feet", "hands"]:
		for k in P[g]:
			_sort(P[g][k])
	# the roll: the limbs are FK-tucked while the pelvis turns (angles in degrees, bend/side/twist)
	P["fk"].append({"t0": 6.78, "t1": 7.20, "ramp": 0.08, "ang": {
		"thigh_l": Vector3(115, 4, 0), "thigh_r": Vector3(115, -4, 0), "calf_l": Vector3(125, 0, 0), "calf_r": Vector3(125, 0, 0),
		"foot_l": Vector3(20, 0, 0), "foot_r": Vector3(20, 0, 0),
		"upperarm_l": Vector3(70, -30, 0), "upperarm_r": Vector3(70, -30, 0), "lowerarm_l": Vector3(95, 0, 0), "lowerarm_r": Vector3(95, 0, 0)}})
	return P


## the swing of a foot from its last contact (t0) to its next (t1): it trails, then passes the pelvis, then reaches
static func _swing(P: Dictionary, sd: String, t0: float, t1: float) -> void:
	var d := t1 - t0
	var x := 0.09 if sd == "_l" else -0.09
	_rel(P, "feet", "foot" + sd, t0 + d * 0.35, Vector3(x, -HIP + 0.38, -0.22))
	_rel(P, "feet", "foot" + sd, t0 + d * 0.72, Vector3(x, -HIP + 0.26, 0.38))


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
