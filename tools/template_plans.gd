## The five template plans (ROADMAP 44), read by tools/make_templates.gd. Angles: [bend, side, twist] in degrees, the meaning
## in data/body_limits.json "say". Each plan says where its numbers come from; tests/templates_test.gd measures them again on
## the baked scene and holds each one inside the cited range.
extends RefCounted


static func get_plan(nm: String) -> Dictionary:
	match nm:
		"walk": return plan_walk()
		"run": return plan_run()
		"jump": return plan_jump()
		"punch": return plan_punch()
		"sword_swing": return plan_sword_swing()
		"sit_down": return plan_sit_down()
		"wave": return plan_wave()
		"fall": return plan_fall()
		"dance": return plan_dance()
		"turn_around": return plan_turn(180.0)
		"turn_left": return plan_turn(90.0)
		"turn_right": return plan_turn(-90.0)
	return {}


## the standing legs and relaxed arms every template starts from (feet hip-width: thigh side 7, a slight knee soften)
static func stand_set() -> Dictionary:
	return {"spine_02": [4, 0, 0], "upperarm_l": [4, -65, 0], "upperarm_r": [4, -65, 0], "lowerarm_l": [18, 0, 0], "lowerarm_r": [18, 0, 0],
		"thigh_l": [6, 7, 0], "thigh_r": [6, 7, 0], "calf_l": [12, 0, 0], "calf_r": [12, 0, 0]}


## WALK. REAL WALKERS: step 0.415 +- 0.038 of body height at 1.33 m/s, 21 young adults (Gait Posture 2009, PMID 19502061), so a
## stride (two steps) is 0.83 of height (0.75-0.85 is the usual band); cadence 105.5 +- 5.2 steps/min (PMID 29775941) and 108 +- 7
## (PMID 41879248); arms swing against the legs, ~25-33 deg peak to peak at 4 km/h (PMID 40291287, PMID 23236504; Kubo 2004,
## PMID 15351887). The legs are scenes/walk_bat's double-support cards (Fukuchi 2018: lead hip 30 / knee 12, trailing hip -7 /
## knee 23; docs/research/TOES.md for the toe joint): a half step, five 0.70 m steps of 0.57 s (105 steps/min), feet together.
static func plan_walk() -> Dictionary:
	var clips := [{"name": "stand", "move": -1, "hold": 0.4, "set": stand_set(), "relaxed": ["l", "r"], "hips": [0, 0, -3.85]}]
	var foot := ["_l", "_r"]
	var seq := [["_l", 0.35, 0.5], ["_r", 1.05, 0.57], ["_l", 1.4, 0.57], ["_r", 1.4, 0.57], ["_l", 1.4, 0.57], ["_r", 1.4, 0.57]]
	var at := {"_l": 0.0, "_r": 0.0}
	for s in seq:
		var sd: String = s[0]
		var other: String = "_r" if sd == "_l" else "_l"
		at[sd] = float(at[sd]) + float(s[1])
		var lead := sd == "_l"   # the foot that just landed is the leading leg
		var sw := 1.0 if lead else -1.0
		var half: bool = s[1] < 0.5
		var arm_l := -16.0 * sw      # the left arm goes back when the left leg leads
		var c := {"name": "step " + ("L" if lead else "R"), "move": s[2], "hold": 0.0, "walk": true, "lift": 0.06, "heel_up": [other],
			"heel_deg": 8 if half else 10, "steps": {sd: [0, 0, s[1]]}, "hips": [0, 0, -3.85 + (float(at["_l"]) + float(at["_r"])) / 2.0]}
		if half:
			c["name"] = "half step L"
		c["set"] = {"pelvis": [2, 0, -6.0 * sw], "spine_02": [4, 0, 3.6 * sw], "spine_03": [1, 0, 2.4 * sw],
			"upperarm_l": [4.0 + arm_l, -65, 0], "upperarm_r": [4.0 - arm_l, -65, 0],
			"lowerarm_l": [18 + (8 if arm_l > 0 else 0), 0, 0], "lowerarm_r": [18 + (8 if arm_l < 0 else 0), 0, 0],
			"thigh" + sd: [30 if not half else 14, 7, 0], "calf" + sd: [12 if not half else 5, 0, 0],
			"thigh" + other: [-7 if not half else -8, 7, 0], "calf" + other: [23 if not half else 8, 0, 0]}
		clips.append(c)
	clips.append({"name": "stop: feet together", "move": 0.6, "hold": 0.6, "walk": true, "lift": 0.06, "steps": {"_l": [0, 0, 0.7]},
		"hips": [0, 0, 0.0], "set": stand_set()})
	return {"name": "walk", "base": "poses/stand.json", "clips": clips,
		"note": "WALK template: half step, five 0.70 m steps at 0.57 s (105 steps/min), feet together; arms swing against the legs. Real walkers: step 0.415 of height (PMID 19502061), cadence 105 +- 5 (PMID 29775941), arm swing 25-33 deg peak to peak (PMID 40291287)."}


## RUN. A run cycle at a jogger's pace. REAL RUNNERS: preferred step rate ~170-172 steps/min in recreational runners, 180 the usual
## coaching target (Heiderscheit et al. 2011, Med Sci Sports Exerc 43:296: preferred step rate; Daniels' 180), so 0.353 s a step; a
## step of 1.165 m at 3.3 m/s (12 km/h; step length = speed / step rate, the identity); stance ~0.25 s and a FLIGHT of ~0.11 s with
## both feet off the floor (running has a flight phase, walking does not: Novacheck 1998, Gait Posture 7:77; flight is ~0.05-0.15 s at
## jogging speeds); the body is lowest at mid-stance (knee ~40 deg: Novacheck) and the centre of mass rises ~ g T^2 / 8 = 1.2 cm in
## the flight; elbows ~90 deg, arms against the legs. The numbers are the template's design and tests/templates_test.gd measures them.
const RUN_ARM_MID := -5.0       # upper arm bend (deg, + = forward) at mid-stance; the shoulder's back stop is -45 (body_limits)
const RUN_ARM_SWING := 40.0     # the swing either side of mid: back -45 (the stop), forward +35
const RUN_ARM_SIDE := -55.0   # the shoulder's side angle (-65 relaxed, -55 a little more to the body): the swing is about the same at any of these
const RUN_ELBOW := 90.0         # mean elbow bend
const RUN_ELBOW_SPLIT := 32.0   # back arm 58, forward arm 122: the back forearm must point back for the hand to reach behind the hip (the shoulder's back stop is -45)

static func plan_run() -> Dictionary:
	var step := 0.78
	var x := {"_r": -0.10, "_l": 0.10}
	# the arms against the legs: at a landing the arm of the stance side is back and the other forward, at mid-stance both hang
	# near the body, at take-off they have swapped (swing 52 deg peak to peak at the shoulder, elbows 50-65 deg flexed)
	# PUMPING ARMS (the run's look: the upper arms swing front to back from the shoulder, the back hand gets behind the hip and the
	# front hand reaches the chest). The shoulder's back stop is -45 (body_limits), so the upper arm alone cannot reach behind the
	# hip: the forearm must point back, which takes the back elbow to ~58 deg and the front one to ~122 (mean 90). Before this the
	# elbows were all ~90 and the forearm swung the hand forward every frame (both hands >= 17 cm in front of the pelvis).
	var arm := func(F: String, ph: String, k := 1.0) -> Dictionary:   # k: the swing's size (a shorter step swings the arms less)
		var O := "_l" if F == "_r" else "_r"
		var sw: float = {"land": -0.6, "mid": 0.0, "off": 0.6, "air": 1.0}[ph] as float   # F's arm: -1 back, +1 forward (O's is the mirror); the extreme only in the flight, so the arm turns there and does not dwell across the take-off and landing cards (a dwell reads as a HITCH)
		var bF: float = RUN_ARM_MID + RUN_ARM_SWING * sw * k
		var bO: float = RUN_ARM_MID - RUN_ARM_SWING * sw * k
		var eF: float = RUN_ELBOW + RUN_ELBOW_SPLIT * sw   # the back arm bends less (its forearm then points back), the forward arm more
		var eO: float = RUN_ELBOW - RUN_ELBOW_SPLIT * sw
		return {"upperarm" + F: [bF, RUN_ARM_SIDE, 0], "upperarm" + O: [bO, RUN_ARM_SIDE, 0], "lowerarm" + F: [eF, 0, 0], "lowerarm" + O: [eO, 0, 0]}
	# the whole body leans forward from the ankles about 7 deg (the head steady: the neck takes back part of it)
	var lean := {"pelvis": [3, 0, 0], "spine_01": [1, 0, 0], "spine_02": [2, 0, 0], "spine_03": [2, 0, 0], "neck_01": [-2, 0, 0]}
	var clips := []
	var feet := ["_r", "_l"]
	# N031 BODY ACCEL: the steps BUILD the speed and give it back. A run from a standstill takes several steps to reach its pace
	# and several to stop (step length grows at a steady cadence: the cadence is the same in every step here, only the length
	# changes); written at full length from the first card, the centre of mass went 0 -> 2.2 m/s in ~0.12 s (11 m/s^2, over
	# BodyCaps' 10 start cap) and back to 0 in ~0.1 s (24 m/s^2). The ramp below is the template's design (HEURISTIC), not data.
	var lens := [0.30, 0.48, 0.64, 0.78, 0.78, 0.78, 0.66, 0.50, 0.32]   # the step leaving each stance (m); n - 1 of them
	var n := lens.size() + 1   # stances
	var zs := [0.0]
	for L in lens:
		zs.append(float(zs[-1]) + float(L))
	for i in n:
		var F: String = feet[i % 2]
		var O: String = feet[(i + 1) % 2]
		var zf: float = zs[i]
		var s_in: float = (float(lens[i - 1]) if i > 0 else step) / step     # the hips' lead and lag scale with the step they belong to
		var s_out: float = (float(lens[i]) if i < n - 1 else step) / step
		var mark := [x[F], zf, 0.0]
		# the swing leg O in each phase (thigh, calf, foot): trailing after the landing, under the body, forward
		var sets := {
			"land": {"t": [-14, 3, 0], "c": [75, 0, 0], "f": [10, 0, 0], "y": -0.108, "z": -0.28},
			"mid": {"t": [6, 3, 0], "c": [100, 0, 0], "f": [0, 0, 0], "y": -0.115, "z": 0.0},
			"off": {"t": [38, 3, 0], "c": [88, 0, 0], "f": [-5, 0, 0], "y": -0.09, "z": 0.22}}
		for ph in ["land", "mid", "off"]:
			if (i == 0 and ph == "land") or (i == n - 1 and ph == "off"):
				continue
			var q: Dictionary = sets[ph]
			var st := lean.duplicate()
			st.merge(arm.call(F, ph, pow(s_in if ph == "land" else s_out, 2.0)), true)
			st["thigh" + O] = [q["t"][0], q["t"][1], 0]
			st["calf" + O] = q["c"]
			st["foot" + O] = q["f"]
			var zq: float = float(q["z"]) * (s_in if ph == "land" else s_out)
			var c := {"name": "%s %s%d" % [ph, "R" if F == "_r" else "L", i], "set": st, "hips": [0, 0, zf + zq], "y": q["y"],
				"plant": {F: mark}, "free_feet": [O], "move": 0.11 if ph == "mid" else (0.13 if ph == "off" else 0.05), "hold": 0.0}
			if ph == "off":
				c["heel_up"] = [F]
				c["heel_deg"] = 0
			if i == 0 and ph == "mid":
				c["move"] = -1
			clips.append(c)
		if i < n - 1:
			var a := lean.duplicate()
			a.merge(arm.call(F, "air", pow(s_out, 2.0)), true)
			a["thigh" + O] = [52, 3, 0]
			a["calf" + O] = [maxf(42.0 - 50.0 * (1.0 - s_out), 0.0), 0, 0]   # a shorter step: the leading knee opens sooner (its foot clear of the floor in the flight)
			a["foot" + O] = [-5, 0, 0]
			a["thigh" + F] = [-12, 3, 0]
			a["calf" + F] = [90, 0, 0]   # heel recovery: the leaving heel comes up high behind, toward the glute (not a kick out in front)
			a["foot" + F] = [-8, 0, 0]
			clips.append({"name": "air %d" % i, "set": a, "hips": [0, 0, zf + (0.22 + 0.14) * s_out], "y": -0.09, "free_feet": ["_l", "_r"], "air": true,
				"move": 0.06, "hold": 0.0})
	clips[0]["hold"] = 0.1   # the lead ramps in over the first 75 ms less this hold: every joint reads on time from the first frame
	clips[-1]["hold"] = 0.0
	# A spline scene reads the hips' curve Scene.LEAD * 5 (75 ms) AHEAD of the legs, so a hip value written on a card shows up 75 ms
	# early at runtime and a planted leg overreaches in the last 75 ms of its stance (locked straight, 3000 deg/s). Written here
	# as the path wanted AT each card's time, each card gets the path as it stood 75 ms BEFORE, which the spline reads back on time.
	var keys := []
	var tc := 0.0
	for c in clips:
		tc += maxf(float(c.get("move", 0.0)), 0.0)
		c["_t"] = tc
		keys.append([tc, float(c["hips"][2]), float(c.get("y", 0.0))])
		if float(c.get("hold", 0.0)) > 0.0:
			tc += float(c["hold"])
			keys.append([tc, float(c["hips"][2]), float(c.get("y", 0.0))])
	for c in clips:
		var tt: float = maxf(float(c["_t"]) - Scene.LEAD * 5.0, 0.0)
		var z: float = keys[0][1]
		var y: float = keys[0][2]
		for q in range(1, keys.size()):
			if tt <= float(keys[q][0]):
				var u: float = (tt - float(keys[q - 1][0])) / maxf(float(keys[q][0]) - float(keys[q - 1][0]), 1e-6)
				z = lerpf(keys[q - 1][1], keys[q][1], u)
				y = lerpf(keys[q - 1][2], keys[q][2], u)
				break
			z = keys[q][1]
			y = keys[q][2]
		c["store"] = [z, y]   # the card WRITES this offset; its legs are solved for the hips it will really have: "hips" and "y"
		c.erase("_t")
	return {"name": "run", "base": "poses/stand.json", "clips": clips, "spline": true, "no_pin": true,
		"note": "RUN template: a run cycle, 170 steps/min (0.353 s a step), 0.78 m a step (2.2 m/s, a slow jog) after three steps building up from a standstill (0.30, 0.48, 0.64 m) and before three slowing to a stop, a 0.10 s flight between footfalls; arms against the legs. Real runners: preferred step rate ~170-172, coaching 180; flight ~0.05-0.15 s."}


## JUMP. A countermovement jump of 0.40 m. REAL JUMPERS: the flight of T seconds is a jump of g T^2 / 8 (Bosco; Asmussen &
## Bonde-Petersen 1974), a recreational adult's countermovement jump is 0.40 +- 0.11 m on a force plate = 0.571 s in the air
## (Rulebook JUMP, docs/research); people dip to ~90 deg of knee bend before take-off (Rulebook.JUMP_DIP) with the trunk leaning
## forward and the arms swung back, leave the floor with the legs nearly straight (knee flexion at take-off under ~20 deg, ankle
## plantarflexed, arms swung up) and land soft: 77 deg of knee flexion is a stiff landing from 0.59 m, ~117 a soft one (DeVita &
## Skelly 1992, PMID 1548984). The flight is the "leave" and "air" cards between the take-off card and the touchdown card.
const PUSH_T := 0.28   # N031: the push, dip to take-off (s), and how far through it the "push" card has each part (HEURISTIC, tuned on BodyCaps)
const PUSH_F := 0.36   # ... the legs: an even push covers (0.6)^2 = 36% of the way at 60% of the time
const HIPS_F := 0.7    # ... the hips' travel forward (the body leaves going up, not lurching forward then caught)
const TRUNK_F := 0.7   # ... the trunk coming upright (late, it swings the centre of mass back just before the leave)
const TAKEOFF_Z := 0.04 # the hips over the feet at take-off (m; the straight leg reaches its mark from here)


static func plan_jump() -> Dictionary:
	var ball := {"_l": [0.0, 0.0], "_r": [0.0, 0.0]}   # filled by the tool: the feet's marks are the stand card's own
	var squat := {"spine_01": [3, 0, 0], "spine_02": [12, 0, 0], "spine_03": [12, 0, 0], "neck_01": [-12, 0, 0]}
	var clips := [{"name": "stand", "move": -1, "hold": 0.4, "set": stand_set(), "relaxed": ["l", "r"]}]
	var dip := squat.duplicate()
	dip.merge({"pelvis": [14, 0, 0], "thigh_l": [70, 7, 0], "thigh_r": [70, 7, 0], "calf_l": [95, 0, 0], "calf_r": [95, 0, 0],
		"upperarm_l": [-40, -65, 0], "upperarm_r": [-40, -65, 0], "lowerarm_l": [20, 0, 0], "lowerarm_r": [20, 0, 0]}, true)
	clips.append({"name": "dip", "move": 0.5, "hold": 0.05, "set": dip, "hips": [0, 0, -0.2], "keep_feet": true})
	var up := {"pelvis": [0, 0, 0], "spine_02": [0, 0, 0], "thigh_l": [-4, 7, 0], "thigh_r": [-4, 7, 0], "calf_l": [6, 0, 0], "calf_r": [6, 0, 0],
		"upperarm_l": [35, 50, 0], "upperarm_r": [35, 50, 0], "lowerarm_l": [10, 0, 0], "lowerarm_r": [10, 0, 0], "neck_01": [-8, 0, 0]}
	# N031 BODY ACCEL: the push SPEEDS UP all the way to the take-off (the flight leaves at g T / 2 = 2.8 m/s): a card part-way
	# up makes the curve accelerate into the leave instead of easing into it and being jerked onto the flight's speed (16.9
	# m/s^2 up, over BodyCaps' 14.7 rise cap). At an even push, 60% of the time covers 36% of the way (f^2): that card.
	var mid := {}
	for j in dip.keys() + up.keys():
		var a0: Array = dip.get(j, [0, 0, 0])
		var a1: Array = up.get(j, [0, 0, 0])
		var w: float = 0.6 if String(j).contains("arm") else (PUSH_F if String(j).begins_with("thigh") or String(j).begins_with("calf") else TRUNK_F)   # the arms swing through evenly
		mid[j] = [lerpf(a0[0], a1[0], w), lerpf(a0[1], a1[1], w), lerpf(a0[2], a1[2], w)]
	clips.append({"name": "push", "move": 0.6 * PUSH_T, "hold": 0.0, "set": mid, "keep_feet": true, "hips": [0, 0, lerpf(-0.2, TAKEOFF_Z, HIPS_F)]})
	clips.append({"name": "take-off", "move": 0.4 * PUSH_T, "hold": 0.0, "set": up, "heel_up": ["_l", "_r"], "heel_deg": 16, "keep_feet": true, "hips": [0, 0, TAKEOFF_Z]})
	var air := {"pelvis": [0, 0, 0], "thigh_l": [14, 7, 0], "thigh_r": [10, 7, 0], "calf_l": [22, 0, 0], "calf_r": [16, 0, 0],
		"upperarm_l": [50, 70, 0], "upperarm_r": [50, 70, 0], "lowerarm_l": [20, 0, 0], "lowerarm_r": [20, 0, 0]}
	# the legs stay long through the leave: the scene reads each joint up to 75 ms ahead (Scene.LEAD), so legs that bend for
	# the flight straight after the take-off card bent BEFORE it, on the floor, and the hips sank just as they should rise
	var leave := up.duplicate()
	for j in air:
		if String(j).contains("arm"):
			leave[j] = [lerpf(up[j][0], air[j][0], 0.5), lerpf(up[j][1], air[j][1], 0.5), lerpf(up[j][2], air[j][2], 0.5)]   # the arms keep swinging up
	clips.append({"name": "leave", "move": 0.10, "hold": 0.0, "set": leave, "air": true, "heel_up": ["_l", "_r"], "heel_deg": 30})
	clips.append({"name": "air", "move": 0.20, "hold": 0.0, "set": air, "air": true, "heel_up": ["_l", "_r"], "heel_deg": 30})
	var td := {"thigh_l": [10, 7, 0], "thigh_r": [10, 7, 0], "calf_l": [14, 0, 0], "calf_r": [14, 0, 0], "spine_02": [4, 0, 0],
		"upperarm_l": [80, -20, 0], "upperarm_r": [80, -20, 0], "lowerarm_l": [20, 0, 0], "lowerarm_r": [20, 0, 0]}
	clips.append({"name": "touch-down", "move": 0.271, "hold": 0.0, "set": td, "heel_up": ["_l", "_r"], "heel_deg": 0, "keep_feet": true, "hips": [0, 0, 0.04]})
	var cr := squat.duplicate()
	cr.merge({"pelvis": [14, 0, 0], "thigh_l": [75, 7, 0], "thigh_r": [75, 7, 0], "calf_l": [105, 0, 0], "calf_r": [105, 0, 0],
		"upperarm_l": [90, -5, 0], "upperarm_r": [90, -5, 0], "lowerarm_l": [15, 0, 0], "lowerarm_r": [15, 0, 0]}, true)
	clips.append({"name": "absorb", "move": 0.22, "hold": 0.1, "set": cr, "hips": [0, 0, -0.2], "keep_feet": true})
	clips.append({"name": "stand", "move": 0.6, "hold": 0.4, "set": stand_set(), "hips": [0, 0, 0], "keep_feet": true})
	return {"name": "jump", "base": "poses/stand.json", "clips": clips, "spline": true,
		"note": "JUMP template: a 0.40 m countermovement jump (0.571 s in the air, g T^2/8; recreational adults 0.40 +- 0.11 m): knee dip to ~90 deg with the arms back, a push that speeds up into the leave, legs nearly straight at take-off, soft landing to ~100 deg+."}


## PUNCH (a rear-hand cross from an orthodox guard). REAL PUNCHERS: the fist of a straight punch peaks at 9.3 +- 2.1 m/s
## (Piorkowski et al. 2011, reported in Rulebook FIST SPEED), a lead hook 11.95 +- 1.84 m/s (Stanley et al. 2018); trained
## boxers' straight punches ~7-11 m/s, so the template is built to ~9. The power goes hips -> shoulders -> fist (the rear foot
## pivots on its ball, the hips and chest turn ~50 deg to square up: Rulebook SEQUENCE, hitters' pelvis peaks ~389 deg/s, ISBS
## 2015); the guard hand stays at the chin; the head stays still (Rulebook HEAD QUIET). The punch is 0.14 s from the load
## to the full reach, a held 0.06 s, then it comes back to the chin as fast as a person pulls the arm in (0.3 s).
static func plan_punch() -> Dictionary:
	var guard_arm_l := {"upperarm_l": [25, -56, 8], "lowerarm_l": [118, 0, 0], "clavicle_l": [0, 8, 0]}
	var guard_arm_r := {"upperarm_r": [25, -56, -8], "lowerarm_r": [118, 0, 0], "clavicle_r": [0, 8, 0]}
	var base := {"neck_01": [8, 0, 0], "spine_01": [4, 0, 0], "spine_02": [6, 0, 0], "spine_03": [6, 0, 0]}
	var lead := [0.14, 0.26, -0.15]    # left foot forward, toes a little in
	var rear := [-0.18, -0.2, -0.5]  # right foot back, toes out ~43 deg
	var g := base.duplicate()
	g.merge(guard_arm_l, true)
	g.merge(guard_arm_r, true)
	g.merge({"pelvis": [4, 0, -12], "spine_01": [4, 0, -3], "spine_02": [6, 0, -3], "spine_03": [6, 0, -3]}, true)
	# the whole stance sits 6 cm back over the rear foot on EVERY card (guard ~50 % rear, 49 % as the cross starts: WEIGHT
	# TRANSFER wants >= 45). The template plays hips-first, so a shift on the load card alone has already left by the time
	# the fist starts (10-23: load -0.12 m reached only 45 %); one offset on every card adds no motion and no HITCH.
	var clips := [{"name": "guard", "move": -1, "hold": 0.4, "set": g, "fist": ["l", "r"], "y": -0.10, "hips": [0, 0, -0.06],
		"plant": {"_l": lead, "_r": rear}}]
	var load := g.duplicate()
	load.merge({"pelvis": [5, 0, -17], "spine_01": [4, 0, -5], "spine_02": [6, 0, -5], "spine_03": [6, 0, -5],
		"upperarm_r": [8, -56, -8], "neck_01": [8, 0, 6]}, true)
	clips.append({"name": "load", "move": 0.25, "hold": 0.0, "set": load, "fist": ["l", "r"], "y": -0.11, "hips": [0, 0, -0.08], "keep_feet": true})
	var x := base.duplicate()
	x.merge(guard_arm_l, true)
	x.merge({"pelvis": [4, 0, 14], "spine_01": [4, 0, 5], "spine_02": [6, 0, 5], "spine_03": [6, 0, 5], "neck_01": [8, 0, -12],
		"clavicle_r": [0, 22, 0], "upperarm_r": [88, -6, 0], "lowerarm_r": [4, 0, 0], "hand_r": [0, 0, 0]}, true)
	clips.append({"name": "CROSS", "move": 0.11, "hold": 0.0, "set": x, "fist": ["l", "r"], "y": -0.05, "hips": [0, 0, -0.06],
		"heel_up": ["_r"], "heel_deg": 0, "keep_feet": true})
	clips.append({"name": "recover", "move": 0.3, "hold": 0.3, "set": g, "fist": ["l", "r"], "y": -0.10, "hips": [0, 0, -0.06], "keep_feet": true})
	return {"name": "punch", "base": "poses/stand.json", "clips": clips, "spline": true,
		"note": "PUNCH template: a rear-hand cross from an orthodox guard. Fist peak ~9 m/s (straight punch 9.3 +- 2.1, Piorkowski 2011; lead hook 11.95 +- 1.84, Stanley 2018); hips, then chest, then fist; the rear foot pivots on its ball."}


## SWORD SWING. No sword is in the library yet, so the BAT SWING DATA stands in: the hand paths, the blade aims and the timing of
## scenes/swing_fore.json (Nick's one-hand forehand: ready, wind-up, contact, follow-through, recover; plans/swing_fore.json), with a
## 1.0 m blade in the hand instead of the 0.84 m bat (an arming sword is about 1.0 m overall; the bat's 0.9 kg stands in for its
## mass), and BOTH FEET PLANTED (a rooted cut). REAL SWINGS: the power goes hips -> chest -> arm -> blade (hitters' peaks 389 / 601 /
## 1953 deg/s, ISBS 2015: Rulebook SEQUENCE), the head stays still (HEAD QUIET: hitters' heads drop ~9 cm), the blade's tip stays
## under a real weapon's cap (pro bat ~37-40 m/s) and the cut itself takes 6 frames at 30 fps or fewer (docs/ATTACK_RULES.md).
static func plan_sword_swing() -> Dictionary:
	var lead := [0.21, 0.16, 0.0]
	var rear := [-0.21, -0.17, -0.3]
	var base := {"thigh_l": [0, 0, 0], "neck_01": [0, 0, 0], "upperarm_l": [15, -55, 0], "lowerarm_l": [45, 0, 0]}
	var ready := base.duplicate()
	ready.merge({"pelvis": [2, 0, -2], "spine_02": [4, 0, 0]}, true)
	var wind := base.duplicate()
	wind.merge({"pelvis": [2, 0, -8], "spine_01": [2, 0, -8], "spine_02": [4, 0, -8], "spine_03": [2, 0, -8], "neck_01": [0, 0, 16],
		"upperarm_l": [30, -45, 0], "lowerarm_l": [60, 0, 0]}, true)
	var cut := base.duplicate()
	cut.merge({"pelvis": [5, 0, 22], "spine_01": [4, 0, 13], "spine_02": [4, 0, 13], "spine_03": [4, 0, 13], "neck_01": [4, 0, -35],
		"upperarm_l": [-10, -60, 0], "lowerarm_l": [40, 0, 0]}, true)
	var follow := base.duplicate()
	follow.merge({"pelvis": [5, 0, 26], "spine_01": [3, 0, 13], "spine_02": [3, 0, 13], "spine_03": [3, 0, 13], "neck_01": [2, 0, -26],
		"upperarm_l": [-20, -62, 0], "lowerarm_l": [35, 0, 0]}, true)
	var fl := {"fist": ["l"], "y": -0.07, "keep_feet": true}
	var clips := [
		{"name": "ready", "move": -1, "hold": 0.3, "set": ready, "hips": [0, 0, 0.0], "hand": [-0.3, -0.1, 0.16], "aim": [-0.1, 0.85, 0.4],
			"plant": {"_l": lead, "_r": rear}, "fist": ["l"], "y": -0.07},
		{"name": "wind-up", "move": 0.4, "hold": 0.06, "set": wind, "hips": [0, 0, -0.03], "hand": [-0.34, 0.1, 0.06], "aim": [-0.25, 0.85, -0.45]},
		{"name": "CUT", "move": 0.084, "hold": 0.0, "set": cut, "hips": [0, 0, 0.04], "hand": [-0.04, -0.02, 0.40], "aim": [0.3, 0.05, 0.95]},
		{"name": "follow-through", "move": 0.18, "hold": 0.3, "set": follow, "hips": [0, 0, 0.05], "hand": [0.2, 0.0, 0.3], "aim": [0.9, 0.1, -0.3]},
		{"name": "recover", "move": 0.6, "hold": 0.3, "set": ready, "hips": [0, 0, 0.0], "hand": [-0.3, -0.1, 0.16], "aim": [-0.1, 0.85, 0.4]}]
	for k in range(1, clips.size()):
		clips[k].merge(fl, true)
	return {"name": "sword_swing", "base": "poses/stand.json", "clips": clips, "spline": true, "aim_weight": 0.3,
		"weapon": {"kind": "metal_bat", "len": 1.0, "hand": "hand_r"},
		"note": "SWORD SWING template: a one-hand cut across the body with a 1.0 m blade, from the bat swing data (scenes/swing_fore.json): hips, then chest, then arm, then blade; ready, wind-up, cut, follow-through, recover. Feet planted."}


## SIT DOWN. Standing to a chair (Props "chair": seat top 0.45 m, back at -Z, so he faces +Z). The cards are Rise.sit_down's keys
## played backwards (scripts/rise.gd: the stand-up's keys, cited to Schenkman 1990 and Riley 1991: seat-off at 35-40 % of the rise,
## trunk flexion 40-50 deg; the knees bend, the trunk leans forward over the seat and comes back up to the seated pose); the feet
## never move (each key plants both feet). "rise": the bake takes the cards, "move" is the time between two cards: the hips reach
## the seat at 5 moves (1.1 s) and the seated pose is at 8 moves; the two moves after the seat contact take 0.30 s (at 0.18 the trunk coming
## back up pushed the centre of mass 16 m/s^2, past BODY ACCEL's caps: N031). REAL SIT-DOWNS: the hips reach the seat in ~1.0-1.4 s.
static func plan_sit_down() -> Dictionary:
	return {"name": "sit_down", "base": "poses/stand.json", "rise": true, "move": 0.18, "move_of": {6: 0.30, 7: 0.30}, "hold0": 0.2, "flow_from": 6, "no_pin": true, "clips": [],
		"note": "SIT DOWN template: from standing to a 45 cm chair, feet planted; the hips reach the seat at 1.1 s, the knees bend, the trunk leans forward and comes back up. Built from the stand-up keys of scripts/rise.gd (played backwards)."}


## WAVE. The right hand waves hello: the upper arm raised out to the side (side 88: nearly straight up), the forearm forward at
## 95 deg of elbow bend, and the upper arm's twist swings the forearm side to side, 2.5 swings in about 1.2 s (two full swings
## is the bar). The forearm itself has no twist bone (lowerarm side and twist are locked), so the swing is the upper arm's roll.
static func plan_wave() -> Dictionary:
	var rest := stand_set()
	var up := rest.duplicate()
	up.merge({"upperarm_r": [-15, 80, 0], "lowerarm_r": [40, 0, 0]}, true)
	var clips := [{"name": "stand", "move": -1, "hold": 0.4, "set": rest, "relaxed": ["l", "r"]},
		{"name": "Hand up", "move": 0.4, "hold": 0.0, "set": up}]   # Easy's card words: a beginner reads "Hand up", "Wave", "Hand down" (walk-through 10)
	var tw := [-45.0, 45.0, -45.0, 45.0, -45.0]
	var mv := [0.2, 0.25, 0.25, 0.25, 0.25]
	for i in tw.size():
		var w := up.duplicate()
		w["upperarm_r"] = [-15, 80, tw[i]]
		clips.append({"name": "Wave", "move": mv[i], "hold": 0.0, "set": w})
	clips.append({"name": "Hand down", "move": 0.45, "hold": 0.4, "set": rest, "relaxed": ["l", "r"]})
	return {"name": "wave", "base": "poses/stand.json", "clips": clips, "spline": false,
		"note": "WAVE template: the right hand raised, the forearm swung side to side 2.5 times (about 1.2 s), then lowered. Hand passes head height."}


## FALL. A backward fall, judo's ushiro ukemi (a back breakfall): stand, lean back with the arms forward, one step back and a deep crouch
## with the chin tucked, sit down onto the floor close to the heel, roll onto the back with the arms slapping the floor, lie still.
## The bars are in tests/templates_test.gd (the head stays 5 cm off the floor, the body ends lying). The pelvis drops no faster
## than free fall (BodyCaps FALL). Breakfall's rules (scripts/breakfall.gd) judge the landing: chin tucked, elbows bent, the
## slap at 30-45 deg from the body, the weight spread over arm and back.
static func plan_fall() -> Dictionary:
	# a controlled squat from standing (the centre of mass stays over the feet), then the sit back to the floor beside the heels
	var stand := stand_set()
	stand.merge({"pelvis": [4, 0, 0], "spine_01": [3, 0, 0]}, true)   # the weight a little forward: the centre of mass over the feet at rest
	var clips := [{"name": "stand", "move": -1, "hold": 0.3, "set": stand, "relaxed": ["l", "r"], "hips": [0, 0, 0.0]}]
	var arms_fwd := {"upperarm_l": [80, -15, 0], "upperarm_r": [80, -15, 0], "lowerarm_l": [30, 0, 0], "lowerarm_r": [30, 0, 0]}
	var sway := stand_set()
	sway.merge({"pelvis": [-2, 0, 0], "spine_01": [0, 0, 0], "spine_02": [0, 0, 0], "spine_03": [0, 0, 0]}, true)
	sway.merge(arms_fwd, true)
	clips.append({"name": "sway back", "move": 0.15, "hold": 0.0, "set": sway, "hips": [0, 0, -0.02]})
	var squat := {"pelvis": [10, 0, 0], "spine_01": [6, 0, 0], "spine_02": [6, 0, 0], "spine_03": [6, 0, 0],
		"neck_01": [24, 0, 0], "head": [14, 0, 0], "thigh_l": [112, 7, 0], "thigh_r": [112, 7, 0], "calf_l": [140, 0, 0], "calf_r": [140, 0, 0],
		"upperarm_l": [80, -15, 0], "upperarm_r": [80, -15, 0], "lowerarm_l": [40, 0, 0], "lowerarm_r": [40, 0, 0]}
	clips.append({"name": "squat", "move": 0.55, "hold": 0.0, "set": squat, "hips": [0, 0, 0.0], "keep_feet": true})
	var sit := {"pelvis": [-30, 0, 0], "spine_01": [-2, 0, 0], "spine_02": [-2, 0, 0], "spine_03": [-2, 0, 0],
		"neck_01": [26, 0, 0], "head": [14, 0, 0], "thigh_l": [100, 7, 0], "thigh_r": [100, 7, 0], "calf_l": [140, 0, 0], "calf_r": [140, 0, 0],
		"upperarm_l": [60, -40, 0], "upperarm_r": [60, -40, 0], "lowerarm_l": [40, 0, 0], "lowerarm_r": [40, 0, 0]}
	clips.append({"name": "sit back", "move": 0.36, "hold": 0.0, "set": sit, "hips": [0, 0, -0.22]})
	var roll := {"pelvis": [-75, 0, 0], "spine_01": [-1, 0, 0], "spine_02": [-1, 0, 0], "spine_03": [-1, 0, 0],
		"neck_01": [26, 0, 0], "head": [14, 0, 0], "thigh_l": [60, 7, 0], "thigh_r": [60, 7, 0], "calf_l": [95, 0, 0], "calf_r": [95, 0, 0],
		"upperarm_l": [0, 40, 0], "upperarm_r": [0, 40, 0], "lowerarm_l": [30, 0, 0], "lowerarm_r": [30, 0, 0]}
	clips.append({"name": "roll onto the back", "move": 0.2, "hold": 0.0, "set": roll, "hips": [0, 0, -0.28]})
	var lie := {"pelvis": [-90, 0, 0], "spine_01": [0, 0, 0], "spine_02": [0, 0, 0], "spine_03": [0, 0, 0],
		"neck_01": [26, 0, 0], "head": [14, 0, 0], "thigh_l": [85, 7, 0], "thigh_r": [85, 7, 0], "calf_l": [90, 0, 0], "calf_r": [90, 0, 0],
		"upperarm_l": [0, 45, 0], "upperarm_r": [0, 45, 0], "lowerarm_l": [30, 0, 0], "lowerarm_r": [30, 0, 0]}
	clips.append({"name": "lying, still", "move": 0.25, "hold": 0.16, "set": lie, "hips": [0, 0, -0.40]})
	return {"name": "fall", "base": "poses/stand.json", "clips": clips, "spline": true, "floor_body": true, "pin": false, "no_pin": true,
		"note": "FALL template: a backward breakfall (ushiro ukemi): stand, a small sway back, a controlled squat with the centre of mass over the feet and the chin tucked, sit back to the floor beside the heels, roll onto the back with the arms slapping the floor, lie still."}


## DANCE (beginner walk-through round 8: "dance", typed; not a picker card). A side-step, 3.5 s at 120 beats a minute (0.5 s a
## count): step right, close, step left, close, with the arms swinging in counter-phase to the hips' sway and a slight knee bounce.
## Feet are planted with "hold_feet" (the runtime holds a planted foot where it stood in the card before the run, Scene's PLANTED
## FEET) and the bake places each card's feet by its marks: [x, z] on the floor, [x, z, heading, lift] in the air. x is +his left.
## REAL SIDE-STEPS: a step of 0.25 m to the side is a short shuffle at this tempo; the weight shifts over the foot that stays
## before it lifts (the centre of mass goes over the stance foot first), so no card lifts a foot with the centre of mass outside it.
const DANCE_L := 0.10    # the left foot's mark when standing (m, +x his left); the right foot stands at -DANCE_L
const DANCE_OUT := -0.35 # the right foot stepped out to his right (m)
const DANCE_IN := -0.15  # the left foot closed beside the right (m)


static func plan_dance() -> Dictionary:
	var L := DANCE_L
	var R := -DANCE_L
	# [name, move, hold, hips x, knee bounce y, left mark, right mark, planted feet, the free foot]
	var rows := [
		["stand", -1.0, 0.3, 0.0, -0.014, [L, 0.0], [R, 0.0], ["_l", "_r"], []],
		["weight to left", 0.5, 0.0, 0.08, -0.034, [L, 0.0], [R, 0.0], ["_l", "_r"], []],
		["step right, lift", 0.25, 0.0, 0.08, -0.014, [L, 0.0], [-0.22, 0.0, 0.0, 0.05], ["_l"], ["_r"]],
		["step right, down", 0.25, 0.0, 0.08, -0.034, [L, 0.0], [DANCE_OUT, 0.0], ["_l"], []],
		["weight to right", 0.4, 0.0, -0.30, -0.014, [L, 0.0], [DANCE_OUT, 0.0], ["_l", "_r"], []],
		["close left, lift", 0.25, 0.0, -0.30, -0.014, [-0.02, 0.0, 0.0, 0.05], [DANCE_OUT, 0.0], ["_r"], ["_l"]],
		["close left, down", 0.25, 0.0, -0.25, -0.034, [DANCE_IN, 0.0], [DANCE_OUT, 0.0], ["_l", "_r"], []],
		["step left, lift", 0.25, 0.0, -0.33, -0.014, [-0.02, 0.0, 0.0, 0.05], [DANCE_OUT, 0.0], ["_r"], ["_l"]],
		["step left, down", 0.25, 0.0, -0.33, -0.034, [L, 0.0], [DANCE_OUT, 0.0], ["_r"], []],
		["weight to left again", 0.4, 0.0, 0.08, -0.014, [L, 0.0], [DANCE_OUT, 0.0], ["_l", "_r"], []],
		["close right, lift", 0.25, 0.0, 0.08, -0.014, [L, 0.0], [-0.22, 0.0, 0.0, 0.05], ["_l"], ["_r"]],
		["close right, down", 0.25, 0.3, 0.0, -0.014, [L, 0.0], [R, 0.0], ["_l", "_r"], []],
	]
	var clips := []
	for ri in rows.size():
		var row: Array = rows[ri]
		var hx: float = row[3]
		var s := 1.0 if hx > 0.0 else (-1.0 if hx < 0.0 else 0.0)   # the sway's side: the hips lean into it, the chest follows
		# THE PARTY READ (round 9): BOTH arms move on every count, in a clear rhythm of two counts each. Counts 1-2 (cards 0-1, 4-5,
		# 8-9): both hands up and pumping overhead, elbows bent (upper arm 75 = near straight up; the hands stay above the shoulders:
		# the elbow 60 on the first count, 95 on the second). Counts 3-4 (cards 2-3, 6-7, 10-11): a clap in front of the chest, the
		# hands apart on the first count (upper arm 45 forward, 60 out, elbow 70: the elbows out at chest height) and together on the second
		# (see the clap below).
		var phase := (ri / 2) % 2   # 0: the raise (counts 1-2), 1: the clap (counts 3-4)
		var odd := ri % 2 == 1
		var up_arm := [10.0, 75.0, 0.0]
		var set := stand_set()
		var arm_l: Array
		var arm_r: Array
		var low_l: int
		var low_r: int
		if phase == 0:
			arm_l = up_arm
			arm_r = up_arm
			low_l = 95 if odd else 60
			low_r = low_l
		elif odd:   # the clap: the hands together in front of the chest, the wrists about 37 cm apart (upper arm 50 forward, 25 in, elbow 80): tighter (wrists 28 cm, elbow 90, 52/28) leaves 19 forearm and palm contacts, so this is the 0-contact clap
			arm_l = [50.0, 25.0, 0.0]
			arm_r = [50.0, -25.0, 0.0]
			low_l = 80
			low_r = 80
		else:       # the clap opens: the hands apart in front of the chest, the elbows out
			arm_l = [45.0, 60.0, 0.0]
			arm_r = [45.0, -60.0, 0.0]
			low_l = 70
			low_r = 70
		set.merge({"pelvis": [2, 3.0 * s, -4.0 * s], "spine_01": [1, 0, 0], "spine_02": [4, 2.5 * s, 0], "head": [0, 3.0 * s, 8.0 * s],
			"upperarm_l": arm_l, "upperarm_r": arm_r,
			"lowerarm_l": [low_l, 0, 0], "lowerarm_r": [low_r, 0, 0]}, true)
		# THE KNEES BOUNCE ON EVERY COUNT: the body dips on the odd cards and rises on the even ones (the dip is the knee bend)
		var bounce: float = -0.012 if ri % 2 == 0 else -0.040
		clips.append({"name": row[0], "move": row[1], "hold": row[2], "set": set, "relaxed": ["l", "r"],
			"hips": [hx, 0, 0], "y": bounce, "plant": {"_l": row[5], "_r": row[6]}, "hold_feet": row[7], "free_feet": row[8]})
	return {"name": "dance", "base": "poses/stand.json", "clips": clips, "no_pin": true,
		"note": "DANCE: a side-step, 0.5 s a count: step right, close, step left, close (3.5 s); both arms raise and pump overhead on counts 1-2, clap in front of the chest on counts 3-4, the knees bounce on each count, the chest follows the hips. Typed, not a picker card (Templates.TYPED)."}


## TURN ON THE SPOT (round 10): "turn around" = 180 to his left, "turn left" = 90 to his left, "turn right" = 90 to his right (total_deg < 0).
## Four steps: each foot walks half of a circle round the centre of his stance (the left foot's start is at +x, his left side; for a left
## turn it goes round the FRONT, the right foot round the BACK), and each foot's heading turns with the body (the toes turn with the turn).
## The feet are planted at each card (the Scene holds them between cards). The turn is in the pelvis (the thighs turn with it, the feet's
## headings turn with the body). The radius is 0.10 m standing (the dance's stance) and 0.20 m at the middle of the turn.
const TURN_R0 := 0.10
const TURN_R1 := 0.20
const TURN_N := 4


static func plan_turn(total_deg: float) -> Dictionary:
	var clips := []
	var name := "turn_around" if absf(total_deg) > 120.0 else ("turn_left" if total_deg > 0.0 else "turn_right")
	for k in range(TURN_N + 1):
		var th_deg := total_deg * float(k) / float(TURN_N)
		var th := deg_to_rad(th_deg)
		var r := TURN_R0 + (TURN_R1 - TURN_R0) * sin(PI * float(k) / float(TURN_N))
		var lx := r * cos(th)
		var lz := r * sin(th)
		var set := stand_set()
		set.merge({"pelvis": [0, 0, th_deg]}, true)   # the hips turn the whole way (the hips' yaw is the pelvis's own; the spines stay square)
		var plant := {"_l": [lx, lz, th], "_r": [-lx, -lz, th]}
		if k == 0:
			clips.append({"name": "stand", "move": -1.0, "hold": 0.4, "set": set, "relaxed": ["l", "r"], "hips": [0, 0, 0],
				"plant": plant, "hold_feet": ["_l", "_r"]})
		else:
			clips.append({"name": "turn %d" % k, "move": 0.5, "hold": 0.4 if k == TURN_N else 0.0, "set": set, "relaxed": ["l", "r"],
				"hips": [0, 0, 0], "plant": plant, "hold_feet": ["_l", "_r"]})
	return {"name": name, "base": "poses/stand.json", "clips": clips, "no_pin": true,
		"note": "TURN (%s): %.0f deg on the spot in %d steps, each foot half a circle round the stance; hips and spine turn with it." % [name, total_deg, TURN_N]}
