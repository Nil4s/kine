## path_walk.gd - WALK ALONG A PATH (ROADMAP 92, Nick: draw a path on the floor, pick a walk and a speed, get the walk).
## THE PATH is the centre line the hips travel along (floor, x and z; y is up). Points are smoothed (Catmull-Rom) and
## measured by arc length s. Each card of the walk is one step, built from walk_bat's steady steps (the scene the walk
## tests already measure against people): the donors' poses are turned about the vertical so the body FACES THE PATH'S
## TANGENT, and every foot is planted on its mark (LAT either side of the path, toes along the tangent there); the
## "steps" offset is where the foot lands minus where it stood. A turn is made by stepping: the feet land on the curve,
## the heading changes card by card. The stance feet stay pinned where they stand (no slide).
##
## NUMBERS (walking; the gait check's own references, see rulebook.gd GAIT_STEP / GAIT_CAD):
##   step length 0.415 +- 0.038 of body height (Gait Posture 2009, PMID 19502061; 21 adults at 1.33 m/s)
##   cadence = 60 * speed / step length: 1.3 m/s at 1.70 m gives 0.705 m and 111 steps/min. People: 105.5 +- 5.2 at
##   1.21 m/s (PMID 29775941), 108 +- 7 at 1.4 m/s (PMID 41879248). Not a fit to those; the numbers fall inside them.
## SCOPE: walking only, and measured at 1.3 m/s only (tests/pathwalk_test.gd). The donors are walk_bat's step cards, so the
## other speeds the build accepts (0.6-1.6) are untested. A run needs its own donors (flight cards); not built here.
class_name PathWalk
extends RefCounted

const DONOR := "res://scenes/walk_bat.json"
const HEIGHT := 1.70          # m: walk_bat's body (its step 0.30 m is 0.176 of height, walk_legs_test)
const STEP_FRAC := 0.415      # step length / body height (PMID 19502061)
const LAT := 0.2003           # m: the donor's balls sit this far either side of the hips (walk_bat's stand)
const HIP_BACK := 0.115       # m: the hips sit this far behind the midpoint of the feet (walk_bat, every card)
const HOLD_START := 0.3       # s: the stand before the first step (walk_bat)
const HOLD_STOP := 0.4        # s: the stance after the last step (walk_bat's stop)
const SAMPLE := 0.002         # m: the smoothed path is sampled every 2 mm
const SWING := 0.7            # the share of a step period the stepping foot is in the air (its card's move); the rest is PIVOTS double-support cards
const PIVOTS := 3             # double-support cards before each step: the facing is keyed every 1/(PIVOTS+1) of a step, not once per step
const MIN_RADIUS := 0.8        # m: a tighter arc than this is refused (the walk steps can't turn it: the facing lags past 10 deg, the feet slide)
const YAW_LAG := 0.1          # m: a card's facing is the tangent this far BEHIND its hips (sweep on the 90 deg arc: 0 -> 15.6 deg, 0.05 -> 13.7, 0.10 -> 11.9, 0.15 -> 13.7)


## the walk's numbers at a speed: {"step" (m), "cadence" (steps/min), "time" (s per step)}
static func step_numbers(speed: float, height := HEIGHT) -> Dictionary:
	var L := STEP_FRAC * height
	return {"step": L, "cadence": 60.0 * speed / L, "time": L / speed}


## the smoothed path through the points (x, z used; y = 0): {"p": Array[Vector3], "s": arc length at each, "len"}
static func curve(pts: Array) -> Dictionary:
	var P: Array = []
	var n := pts.size()
	for i in range(n - 1):
		var p0: Vector3 = _flat(pts[maxi(i - 1, 0)])
		var p1: Vector3 = _flat(pts[i])
		var p2: Vector3 = _flat(pts[i + 1])
		var p3: Vector3 = _flat(pts[mini(i + 2, n - 1)])
		var m := maxi(1, int(ceil(p1.distance_to(p2) / SAMPLE)))
		for k in m:
			P.append(p1.cubic_interpolate(p2, p0, p3, float(k) / m))
	P.append(_flat(pts[n - 1]))
	var s := PackedFloat64Array()
	s.resize(P.size())
	for i in range(1, P.size()):
		s[i] = s[i - 1] + (P[i] as Vector3).distance_to(P[i - 1])
	return {"p": P, "s": s, "len": s[s.size() - 1] if s.size() > 0 else 0.0}


## the tightest turn of the path: the smallest radius over 0.2 m of arc (m); INF for a straight path
static func min_radius(c: Dictionary) -> float:
	var best := INF
	var L: float = c["len"]
	var s := 0.1
	while s < L - 0.1:
		var a := heading(c, s - 0.1)
		var b := heading(c, s + 0.1)
		var dth := absf(wrapf(b - a, -PI, PI))
		if dth > 1e-6:
			best = minf(best, 0.2 / dth)
		s += 0.05
	return best


static func _flat(v) -> Vector3:
	var w: Vector3 = v
	return Vector3(w.x, 0.0, w.z)


## the path point at arc length s (extended straight past either end, along the end's own segment)
static func at(c: Dictionary, s: float) -> Vector3:
	var P: Array = c["p"]
	var S: PackedFloat64Array = c["s"]
	if s <= 0.0:
		return (P[0] as Vector3) + _end_dir(P, true) * s
	if s >= float(c["len"]):
		return (P[-1] as Vector3) + _end_dir(P, false) * (s - float(c["len"]))
	var lo := 0
	var hi := S.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if S[mid] <= s:
			lo = mid
		else:
			hi = mid
	var f := (s - S[lo]) / maxf(1e-9, S[hi] - S[lo])
	return (P[lo] as Vector3).lerp(P[hi], f)


## the direction of the first (or last) segment of the path, flat
static func _end_dir(P: Array, first: bool) -> Vector3:
	var d: Vector3 = (P[1] - P[0]) if first else (P[-1] - P[-2])
	return Vector3(d.x, 0.0, d.z).normalized()


static func _dir(c: Dictionary, s: float) -> Vector3:
	var d := at(c, s + 0.01) - at(c, s - 0.01)
	return Vector3(d.x, 0.0, d.z).normalized()


## the direction of travel at s as a yaw: the body's forward (+z at yaw 0) turned to it, radians about +y
static func heading(c: Dictionary, s: float) -> float:
	var d := _dir(c, s)
	return atan2(d.x, d.z)


## where foot sd (_l / _r) stands when its mark is at s: on the path, LAT to its side (the body's +x is its left)
static func foot(c: Dictionary, sd: String, s: float) -> Vector3:
	var side := 1.0 if sd == "_l" else -1.0
	return at(c, s) + Quaternion(Vector3.UP, heading(c, s)) * Vector3(LAT * side, 0.0, 0.0)


## the walk for a path: {"ok": true, "scene": Dictionary (a scene file's shape), "step", "cadence", "covered"} or
## {"ok": false, "why"}. pts: Vector3 points on the floor (the path's order). speed in m/s.
static func build(pts: Array, speed: float, height := HEIGHT) -> Dictionary:
	if pts.size() < 2:
		return {"ok": false, "why": "a path needs at least two points on the floor"}
	if speed < 0.6 or speed > 1.6:
		return {"ok": false, "why": "walk speed %.2f m/s is outside what the walk's poses carry (0.6-1.6 m/s)" % speed}
	var c := curve(pts)
	var r_min := min_radius(c)
	if r_min < MIN_RADIUS:
		return {"ok": false, "why": "the path turns on a %.2f m radius; the walk needs at least %.1f m. Widen the bend (move the points out) or add points on the straight part before it" % [r_min, MIN_RADIUS]}
	var nums := step_numbers(speed, height)
	var L: float = nums["step"]
	var T: float = nums["time"]
	var D: float = c["len"]
	var N := int(floor((D - L * 0.5) / L)) + 1   # landings k = 1..N at s = L/2 + (k-1) L
	if N < 2:
		return {"ok": false, "why": "the path is %.2f m: a walk needs two steps (%.2f m) on it" % [D, 2.0 * L]}
	var donor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DONOR))
	var dc: Array = donor["cards"]
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var cards := []
	var arrive := 0.0   # when the current card's move arrives (s); the stand holds HOLD_START first
	var cur := {"_l": 0.0, "_r": 0.0}   # where each foot's mark is now (s along the path)
	# the stand: both feet at s = 0 (the path's start)
	cards.append(_card(B, c, dc[0], "stand", {}, -1.0, HOLD_START, cur, false, 0.0))
	arrive = HOLD_START
	var last := 0.0
	var prev_donor: Dictionary = dc[0]   # the pose the body is in when the period starts: the stand, then the card of the step before
	for k in range(1, N + 1):
		var sd := "_l" if k % 2 == 1 else "_r"
		var s_k := L * 0.5 + (k - 1) * L
		var donor_card: Dictionary
		if k == 1:
			donor_card = dc[1]
		elif k == 2:
			donor_card = dc[2]
		else:
			donor_card = dc[3] if sd == "_l" else dc[4]
		var off := foot(c, sd, s_k) - foot(c, sd, cur[sd])   # the foot's own mark now, to its new one
		off.y = 0.0
		# the period T: PIVOTS double-support cards (both feet on their marks, the body turning on them), then the step (move SWING T)
		var h0 := _hip_s(cur)
		var after := cur.duplicate()
		after[sd] = s_k
		var h1 := _hip_s(after)
		for j in PIVOTS:
			var f := float(j + 1) / (PIVOTS + 1)
			arrive += (1.0 - SWING) * T / PIVOTS
			cards.append(_card(B, c, prev_donor, "pivot %d.%d" % [k, j + 1], {}, (1.0 - SWING) * T / PIVOTS, 0.0, cur, true, arrive, h0, h0))
		var name := "step %s %d" % ["L" if sd == "_l" else "R", k]
		arrive += SWING * T
		cur[sd] = s_k
		cards.append(_card(B, c, donor_card, name, {sd: [off.x, off.y, off.z]}, SWING * T, 0.0, cur, true, arrive))
		last = s_k
		prev_donor = donor_card
	# the stop: the foot that stepped before the last one comes up to the last mark (feet together)
	var behind := "_r" if N % 2 == 1 else "_l"
	var stop_off := foot(c, behind, last) - foot(c, behind, cur[behind])
	stop_off.y = 0.0
	cur[behind] = last
	arrive += T
	cards.append(_card(B, c, dc[5], "stop: feet together", {behind: [stop_off.x, stop_off.y, stop_off.z]}, T, HOLD_STOP, cur, true, arrive))

	var out := {}
	for key in ["fps", "on_floor", "floor_body", "natural", "pin", "bad_frames", "note"]:
		if donor.has(key):
			out[key] = donor[key]
	out["scene"] = "path_walk"
	out["plan"] = "walk along a path: %.2f m/s, %.3f m steps, %.0f steps/min" % [speed, L, nums["cadence"]]
	out["cards"] = cards
	out["length_s"] = arrive + HOLD_STOP
	return {"ok": true, "scene": out, "step": L, "cadence": nums["cadence"], "covered": last, "steps": N + 1}


## one card: the donor's pose turned to face the path at its hips (HIP_BACK behind the feet's midpoint, yaw lagging
## YAW_LAG), then each foot PLANTED on its mark (ball on the path's point LAT to its side, toes along the tangent there).
## marks: {"_l": s, "_r": s} where each foot stands along the path. The donor's own legs put the stepping foot where its
## rigid turn leaves it, which is straight ahead on a curve, so the legs are re-solved to the marks.
## the hips' arc position for a set of marks: their midpoint, HIP_BACK behind
static func _hip_s(marks: Dictionary) -> float:
	var s_mid := 0.0
	for sd in marks:
		s_mid += float(marks[sd])
	return s_mid / maxf(1.0, float(marks.size())) - HIP_BACK


static func _card(B: Body, c: Dictionary, donor: Dictionary, name: String, steps: Dictionary, move: float, hold: float,
		marks: Dictionary, walk: bool, arrive: float, s_hip_in := NAN, s_yaw_in := NAN) -> Dictionary:
	var s_hip := _hip_s(marks) if is_nan(s_hip_in) else s_hip_in
	B.from_dict(donor["pose"])
	B.turn_world("pelvis", Quaternion(Vector3.UP, heading(c, (s_hip if is_nan(s_yaw_in) else s_yaw_in) - YAW_LAG)))
	var o: Vector3 = at(c, s_hip)
	B.offset = Vector3(o.x, B.offset.y, o.z)
	B.fk()
	for sd in ["_l", "_r"]:
		var s: float = marks[sd]
		var ball_at := foot(c, sd, s)
		ball_at.y = (B.p0["ball" + sd] as Vector3).y
		var flat := true   # the toe base on its mark on the floor; a heel-first step lands with the heel up, so the ball is the low point
		B.plant(sd, ball_at, heading(c, s), flat)
	B.fk()
	var card := {"name": name, "pose": B.to_dict(), "move": move, "hold": hold,
		"arrive_s": snappedf(arrive, 0.01), "leave_s": snappedf(arrive + hold, 0.01)}
	if not steps.is_empty():
		card["steps"] = steps
	if walk:
		card["walk"] = true
	return card
