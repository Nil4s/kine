## path_run.gd - RUN ALONG A PATH (ROADMAP 92, Nick: draw a path on the floor, pick walk or run and a speed).
## Same path machinery as PathWalk (curve / at / heading); the poses are made here, no donors: four cards per step
## (contact, mid-stance, toe-off, air), the stance foot PLANTED on its mark by Body.plant, the swing leg's knee and thigh
## read from a swing table, the arms opposite the legs, the trunk leaning forward. The air card is flagged "air" so the
## Scene gives the flight its ballistic parabola and no floor (Scene.flights).
##
## NUMBERS (measured on people at 3.5 m/s; only that speed is checked, see tests/pathrun_test.gd):
##   cadence 85.68 +- 5.27 strides/min = 171 steps/min; peak knee flexion 108.68 +- 10.65 deg (28 recreational runners on a
##     treadmill; Fukuchi, Fukuchi, Duarte 2017, PeerJ 5:e3298, Table 4 - "Cadence", "Max knee flx angle", read from the
##     Europe PMC full text of PMC5426356).
##   stance 38.34 % of the stride at 3.5 m/s, 32.11 % at 4.9 m/s (10 elite men, filmed at 60 Hz; Tsai, Wong, Wang, Lin 2008,
##     ISBS "Effect of different running speed on vertical oscillation and stride", as the abstract was returned by a search;
##     the Novacheck 1998 review (Gait Posture 7:77-95, PMID 10200378) could not be opened, its numbers are NOT used).
## From those: step period T = 60/171 = 0.351 s, a stance of 2 x 0.383 T = 0.269 s per foot, a flight of T - stance = 0.082 s
## after every stance. The step length is speed x T (3.5 m/s: 1.23 m). The cadence is held at 171 whatever the speed, so
## the speed range is clamped to 3.0-4.0 m/s, around the one speed measured.
## The swing table, the stance angles, the arm swing, the lean, the foot width are TASTE fitted to the knee bar, not data.
class_name PathRun
extends RefCounted

const CADENCE := 171.0        # steps/min (Fukuchi 2017: 85.68 strides/min)
const STANCE_FRAC := 0.383    # of the stride (Tsai 2008 at 3.5 m/s)
const SPEED_MIN := 3.0
const SPEED_MAX := 4.0
const MIN_RADIUS := 3.0       # m: v^2/r = 4 m/s^2 at 3.5 m/s; a tighter bend is refused
const LAT := 0.07             # m: a running foot lands this far either side of the path
const T_MID := 0.12           # s: contact to mid-stance
const BASE := "res://poses/stand.json"
# swing leg [time since toe-off (s), thigh bend, knee bend] (deg)
const SWING := [[0.0, -18.0, 15.0], [0.041, 5.0, 92.0], [0.082, 18.0, 102.0], [0.20, 48.0, 88.0], [0.30, 50.0, 55.0], [0.351, 42.0, 32.0], [0.392, 36.0, 18.0]]


static func timing() -> Dictionary:
	var T := 60.0 / CADENCE
	var Ts := 2.0 * STANCE_FRAC * T
	return {"T": T, "stance": Ts, "flight": T - Ts}


static func _sw(t: float) -> Vector2:
	for i in range(SWING.size() - 1):
		var a: Array = SWING[i]
		var b: Array = SWING[i + 1]
		if t <= float(b[0]):
			var f := clampf((t - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
			return Vector2(lerpf(a[1], b[1], f), lerpf(a[2], b[2], f))
	return Vector2(SWING[-1][1], SWING[-1][2])


static func _foot(c: Dictionary, sd: String, s: float) -> Vector3:
	var side := 1.0 if sd == "_l" else -1.0
	return PathWalk.at(c, s) + Quaternion(Vector3.UP, PathWalk.heading(c, s)) * Vector3(LAT * side, 0.0, 0.0)


static func build(pts: Array, speed: float) -> Dictionary:
	if pts.size() < 2:
		return {"ok": false, "why": "a path needs at least two points on the floor"}
	if speed < SPEED_MIN or speed > SPEED_MAX:
		return {"ok": false, "why": "run speed %.1f m/s is outside %.1f-%.1f m/s (the cadence and stance numbers were measured at 3.5 m/s). Pick a speed in that range" % [speed, SPEED_MIN, SPEED_MAX]}
	var c := PathWalk.curve(pts)
	var r_min := PathWalk.min_radius(c)
	if r_min < MIN_RADIUS:
		return {"ok": false, "why": "the path turns on a %.2f m radius; a run needs at least %.1f m. Widen the bend (move the points out)" % [r_min, MIN_RADIUS]}
	var tm := timing()
	var T: float = tm["T"]
	var Ts: float = tm["stance"]
	var F: float = tm["flight"]
	var L := speed * T
	var D: float = c["len"]
	var N := int(floor((D - 0.5 - L * 0.5) / L)) + 1
	if N < 3:
		return {"ok": false, "why": "the path is %.1f m: a run needs three strides (%.1f m) on it. Draw a longer path" % [D, 3.0 * L + 1.0]}
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE))
	var cards := []
	var arrive := 0.0
	var v := speed
	# the stand, in the first contact's place (both feet down), then the first contact
	var m1 := L * 0.5
	var sd1 := "_l"
	var other1 := "_r"
	var h_c1 := m1 - T_MID * v
	cards.append(_card(B, c, base, "stand", sd1, "stand", m1, other1, "stand", h_c1, 0.0, 0.0, 0.0, arrive, 0.0, 0.3, false))
	arrive = 0.3
	var sd := sd1
	var last_m := m1
	for k in range(1, N + 1):
		var m := L * 0.5 + (k - 1) * L
		var nsd := "_r" if sd == "_l" else "_l"
		last_m = m
		var rows := [["contact", 0.082, -0.40, (F * 0.5 if k > 1 else 0.5)], ["mid", 0.20, 0.0, T_MID], ["off", 0.351, 0.18, Ts - T_MID]]
		for i in 3:
			var row: Array = rows[i]
			arrive += float(row[3])
			cards.append(_card(B, c, base, "%s %s %d" % [row[0], "L" if sd == "_l" else "R", k], sd, row[0], m, nsd, "swing", m + float(row[2]), 0.0, row[1], 0.0, arrive, float(row[3]), 0.0, false))
		if k < N:
			arrive += F * 0.5
			cards.append(_card(B, c, base, "air %d" % k, sd, "air", m, nsd, "swing", m + 0.62, 0.04, 0.392, 0.041, arrive, F * 0.5, 0.0, true))
		sd = nsd
	# the stop: the last stance foot stays on its mark, the other lands ahead of it, both down
	var m_last := L * 0.5 + (N - 1) * L
	arrive += 0.55
	cards.append(_card(B, c, base, "stop", ("_r" if sd == "_l" else "_l"), "stop", m_last, sd, "stop", m_last + 0.2, 0.0, 0.0, 0.0, arrive, 0.55, 0.4, false))
	var out := {"fps": 30, "on_floor": true, "floor_body": false, "natural": true, "pin": true, "scene": "path_run"}
	out["plan"] = "run along a path: %.1f m/s, %.2f m steps, %.0f steps/min" % [speed, L, CADENCE]
	out["cards"] = cards
	out["length_s"] = arrive + 0.4
	return {"ok": true, "scene": out, "step": L, "cadence": CADENCE, "steps": N, "covered": last_m + 0.2}


## one card. stance foot sd planted on its mark m (flat for contact / mid, heel up for off); the other leg: "swing" reads the
## table at swing time ts, "stand" plants it behind, "stop" plants it at hip s + 0.2
static func _card(B: Body, c: Dictionary, base: Dictionary, name: String, sd: String, phase: String, m: float, osd: String,
		omode: String, hip_s: float, air_t: float, sw_t: float, _unused: float, arrive: float, move: float, hold: float, air: bool) -> Dictionary:
	B.from_dict(base)
	var sgn := 1.0 if sd == "_l" else -1.0
	# stance leg start angles (the plant solves the rest)
	var st_thigh := 28.0
	var st_knee := 15.0
	var H := -0.05   # offset.y: the hips' drop from the standing height (m)
	if phase == "mid":
		st_thigh = 10.0
		st_knee = 40.0
		H = -0.09
	elif phase == "off":
		st_thigh = -18.0
		st_knee = 15.0
		H = -0.07
	elif phase == "air":
		H = -0.02
	elif phase == "stop" or phase == "stand":
		st_thigh = 6.0
		st_knee = 12.0
		H = 0.0
	var sw := Vector2(5.0, 92.0) if phase == "air" else _sw(sw_t)
	if phase == "air":
		# both legs swing: the card's stance leg (just left the floor) is at swing time 0.04, the other at 0.392
		B.ang["thigh" + sd] = Vector3(sw.x, 4.0 * sgn, 0.0)
		B.ang["calf" + sd] = Vector3(sw.y, 0.0, 0.0)
		B.ang["foot" + sd] = Vector3(sw.y - sw.x + 10.0, 0.0, 0.0)
		var s2 := _sw(0.30)   # the leading leg is still folded at mid-flight (knee ~55): at 0.392 it was straight and its foot hung 5 cm off the floor
		B.ang["thigh" + osd] = Vector3(s2.x, -4.0 * sgn, 0.0)
		B.ang["calf" + osd] = Vector3(s2.y, 0.0, 0.0)
		B.ang["foot" + osd] = Vector3(s2.y - s2.x + 5.0, 0.0, 0.0)
	else:
		B.ang["thigh" + sd] = Vector3(st_thigh, 4.0 * sgn, 0.0)
		B.ang["calf" + sd] = Vector3(st_knee, 0.0, 0.0)
		B.ang["foot" + sd] = Vector3(st_knee - st_thigh, 0.0, 0.0)
		if omode == "swing":
			B.ang["thigh" + osd] = Vector3(sw.x, -4.0 * sgn, 0.0)
			B.ang["calf" + osd] = Vector3(sw.y, 0.0, 0.0)
			B.ang["foot" + osd] = Vector3(sw.y - sw.x + 10.0, 0.0, 0.0)
		else:
			B.ang["thigh" + osd] = Vector3(6.0, -4.0 * sgn, 0.0)
			B.ang["calf" + osd] = Vector3(12.0, 0.0, 0.0)
			B.ang["foot" + osd] = Vector3(6.0, 0.0, 0.0)
	# arms opposite the legs (a leg forward, the same side's arm back), elbows bent, the trunk leaning on
	var tl: float = B.ang["thigh_l"].x
	var tr: float = B.ang["thigh_r"].x
	B.ang["upperarm_l"] = Vector3(clampf(-0.7 * tl, -35.0, 40.0), -30.0, 0.0)
	B.ang["upperarm_r"] = Vector3(clampf(-0.7 * tr, -35.0, 40.0), -30.0, 0.0)
	B.ang["lowerarm_l"] = Vector3(90.0, 0.0, 0.0)
	B.ang["lowerarm_r"] = Vector3(90.0, 0.0, 0.0)
	B.ang["spine_02"] = Vector3(6.0, 0.0, -4.0 * sgn)
	B.ang["spine_03"] = Vector3(4.0, 0.0, -2.0 * sgn)
	B.ang["pelvis"] = Vector3(0.0, 0.0, 5.0 * sgn)
	B.turn_world("pelvis", Quaternion(Vector3.UP, PathWalk.heading(c, hip_s - 0.1)))
	var o: Vector3 = PathWalk.at(c, hip_s)
	B.offset = Vector3(o.x, H, o.z)
	B.fk()
	if phase != "air":
		var ball_at := _foot(c, sd, m)
		ball_at.y = (B.p0["ball" + sd] as Vector3).y
		B.plant(sd, ball_at, PathWalk.heading(c, m), true)   # a flat foot: the toe-off heel-up plant left the toe tip 9 cm under the floor and lifted the body
		# the ankle stops at its limit (25 deg), so mid-stance / toe-off cannot lie flat: the heel comes up (plantarflexion) and
		# the toe tip dipped through the floor, which the floor step answered by lifting the whole body (the ball rode 2-4 cm up
		# and the foot stopped counting as down). The toes now bend at the ball (dorsiflexion, as in a real toe-off) until the
		# toe tip is as high as the ball: the toes lie on the floor, the ball stays within a centimetre of it
		_toes_flat(B, sd)
		if omode != "swing":
			var os_m := m - 0.3 if omode == "stand" else m + 0.2 + 0.0
			var ob := _foot(c, osd, os_m)
			ob.y = (B.p0["ball" + osd] as Vector3).y
			B.plant(osd, ob, PathWalk.heading(c, os_m), true)
			_toes_flat(B, osd)
		B.fk()
	var card := {"name": name, "pose": B.to_dict(), "move": move, "hold": hold,
		"arrive_s": snappedf(arrive, 0.01), "leave_s": snappedf(arrive + hold, 0.01), "walk": false}
	if air:
		card["air"] = true
	return card


## bend the toes at the ball joint until the toe tip is as high as the ball (a planted foot with its heel up keeps the toes on the floor)
static func _toes_flat(B: Body, sd: String) -> void:
	var best := 0.0
	var gap := INF
	for a in range(-70, 71, 2):
		B.ang["ball" + sd] = Vector3(float(a), 0.0, 0.0)
		B.fk()
		var g := absf((B.E["ball" + sd] as Vector3).y - (B.P["ball" + sd] as Vector3).y)
		if g < gap - 1e-6 or (absf(g - gap) <= 1e-6 and absf(a) < absf(best)):
			gap = g
			best = float(a)
	B.ang["ball" + sd] = Vector3(best, 0.0, 0.0)
	B.fk()
