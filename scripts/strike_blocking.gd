## strike_blocking.gd - THE STRIKES NICK NEVER SAVED, for text-to-blocking (ROADMAP 22; TextBlocking.build routes here).
## TextBlocking retrieves and adapts Nick's saved scenes; scenes/ holds no punch and no kick, so "fast jab" came out as a
## bat thrust with the bat taken away (the arm never extended) and "front kick" was refused. A move with no saved source is
## GENERATED here instead, the way an animator blocks it: KEY POSES (a guard, the load, the strike, the re-chamber, the
## guard again) as joint angles on the body, both feet put on their stance spots by the app's own leg solve (Body.plant),
## the hips moved over the standing foot when one leg is in the air (Balance.read: the centre of mass back inside the
## support), the cards played by the app's own player (Scene: NATURAL easing, hips first and the hands/feet last).
## THE BIOMECHANICS (the textbook descriptions MoveRecognizer cites for its FORM, opened 10-23; the angles are mine,
## HEURISTIC, read back by the recognizer and the Check, never asserted):
##   jab / cross  the fist goes STRAIGHT to the target at shoulder height (the arm reaches it by Body.reach, aimed down the
##                centre line), the hips and shoulders turning into it; the cross's rear hip drives (the rear heel turns
##                out, the hips turn ~50 deg) (Boxing News 2015: "jab and cross ... thrown straight utilising elbow extension")
##   hook         a level arc: the elbow bent ~90 and level with the shoulder, the hips rotating into it, the lead foot
##                pivoting (Peloton, "How to throw a hook": "front arm bent at about 90 degrees ... fist and elbow level
##                with your shoulder", "rotate your hips into the hook")
##   uppercut     the knees DIP first (the fist drops by the hip), then the legs and hips drive it up, the arm bent ~90
##   front kick   chamber the knee to hip height, extend the shin straight forward, re-chamber, put the foot down
##   roundhouse   the support foot pivots (heel toward the target), the hips turn over (~130 deg in the cited kicks:
##                Gavagan & Sayers 2017, PLoS ONE 12:e0182645), the shin sweeps a level arc to the target
##   side kick    chamber, the hips turned side-on, the leg extends along the hip line, heel first (Wasik 2011, J Hum
##                Kinet, PMC3588635: the foot moves "in the direction of the intended impact")
## NOT MADE HERE: the two-hand staff / spear thrust (it stays retrieved: a dagger's thrust with the staff swapped in,
## which the recognizer reads as a swing). Tried 10-23 with Body.hold_bat on every key (the butt wrist placed, the shaft
## aimed along one line, the lead hand sliding on the haft): the keys held the line (0-2 deg) but the played frames
## between them swung the shaft 15-55 deg off it (keys interpolate joint angles), or the lead hand missed the haft by
## up to 11 cm; cut, not shipped.
## THE TIMING: the strike card's move is set so the striking point PEAKS at the cited human speed (I47 table, human_facts.gd),
## measured on the played frames and retimed (Scene.retime) until it does: the jab and cross at the straight punch's 8.4 m/s
## (Sensors 2025, 25(11):3270), the hook at 10.1 m/s (the lead hook's 11.95 +- 1.84 m/s, Stanley et al. 2018, one SD under
## the mean: under the Check's FIST SPEED bar), the uppercut at the straight punch's 8.4 (no uppercut number: HEURISTIC),
## the kicks at the foot's 14.66 m/s (Gavagan & Sayers 2017: taekwondo roundhouse; the front and side kick have no number
## of their own: HEURISTIC), then slowed further while any joint turns past HumanLimits' bars (knee 1874, trunk 1120 deg/s).
## The wind-up and the recovery: the "knife" row of docs/ATTACK_RULES.md for a fist (a hand's speed, as TextBlocking uses
## for a fist); a kick has no row there: its chamber and recovery are HEURISTIC (below).
class_name StrikeBlocking
extends RefCounted

const AT := preload("res://tools/attack_timing.gd")

## the moves made here, and their class in MoveRecognizer's words (the test's bar)
const MOVES := ["jab", "cross", "hook", "uppercut", "front kick", "roundhouse", "side kick"]
const CLASS := {"jab": "jab", "cross": "cross", "hook": "hook", "uppercut": "uppercut", "front kick": "front kick",
	"roundhouse": "roundhouse", "side kick": "side kick"}
## the striking point's target PEAK (m/s) and where it comes from (HumanFacts ids: the served fact names its paper)
const PEAK := {"jab": [8.4, "jab_speed"], "cross": [8.4, "jab_speed"], "hook": [10.11, "hook_speed (mean - 1 SD)"],
	"uppercut": [8.4, "jab_speed (no uppercut number: HEURISTIC)"], "front kick": [14.66, "kick_foot_speed (a roundhouse's: HEURISTIC for this kick)"],
	"roundhouse": [14.66, "kick_foot_speed"], "side kick": [14.66, "kick_foot_speed (a roundhouse's: HEURISTIC for this kick)"]}
const PEAK_TOL := 0.06       # the measured peak within 6 % of the target is on it (the retime is a % of the move: HEURISTIC)
const KICK_CHAMBER := 0.22   # s, HEURISTIC: the move into the chamber (no kick row in docs/ATTACK_RULES.md)
const KICK_BACK := 0.30      # s, HEURISTIC: re-chamber to the foot down again
const KICK_LOAD := 0.20      # s, HEURISTIC: the guard to the load (_load); inside the anticipation's retime with the chamber
const KICK_LAND := 0.15      # s, HEURISTIC: the re-chamber to the foot down (the load pose again); inside the recovery's retime
## the orthodox stance (left foot forward), the test's guard: the balls of the feet and their headings (rad)
const STANCE := {"_l": [Vector3(0.12, 0.0152, 0.28), 0.0], "_r": [Vector3(-0.14, 0.0152, -0.18), -0.35]}   # rear toes ~20 deg out
## to his right, with the bladed hips (at +0.5, the recognizer test's, the rear thigh sat on its twist stop)
const DROP := -0.08          # m: the hips this far down in the guard: both knees bent (at -0.04 the rear leg stood
                             # straight, and its knee solve flipped between cards: 2000+ deg/s on the knee)
const REACH := 0.97          # a straight punch lands with the arm at this share of its length (the elbow not locked)
const BAL_IN := 0.02         # m: on one foot, the centre of mass put this far inside the standing foot


## the words -> the move made here, or "" (TextBlocking keeps retrieving): every unarmed strike and kick (a staff /
## spear thrust stays retrieved: a generated two-hand thrust is NOT made here yet)
static func move_of(P: Dictionary) -> String:
	var a: String = P["attack"]
	var kind: String = P["kind"]
	if a in ["front kick", "roundhouse", "side kick"]:
		return a
	if kind == "":
		if a in ["jab", "cross", "hook", "uppercut"]:
			return a
		if a == "thrust":
			return "jab"   # "punch", "straight": a straight punch
		return ""
	return ""


## the striking side and the stance: orthodox (left lead) unless the words put a lead / rear hand on the other side.
## -> [the striking side "_l"/"_r" in the ORTHODOX build, mirror (southpaw), the words]
static func side_of(move: String, side: String, lead: String) -> Array:
	var rear_default := move in ["cross", "uppercut", "front kick", "roundhouse", "side kick"]
	var want := ""   # "lead" / "rear"
	if lead != "":
		want = lead
	elif move == "jab":
		want = "lead"
	elif move == "cross":
		want = "rear"
	var sd := "_r" if rear_default else "_l"
	if want == "lead":
		sd = "_l"
	elif want == "rear":
		sd = "_r"
	var mirror := false
	if side != "":
		var hand := "_l" if side == "left" else "_r"
		if hand != sd:
			if (move == "jab" or move == "cross" or lead != "" or move in ["front kick", "roundhouse", "side kick"]):
				mirror = true   # a right jab is a southpaw's lead hand; a left kick a southpaw's rear leg
			else:
				sd = hand        # a right hook / a left uppercut: the other hand of the same orthodox stance
	var switched := false
	if sd == "_l" and move in ["front kick", "roundhouse", "side kick"]:
		# a lead-leg kick is built as a SWITCH kick: the feet change places and the (new) rear leg kicks, i.e. the rear-leg
		# template mirrored (the lead leg's short kick from the stance is not made here)
		sd = "_r"
		mirror = not mirror
		switched = true
	var role := "lead" if sd == "_l" else "rear"
	var hand_w := ("left" if sd == "_l" else "right") if not mirror else ("right" if sd == "_l" else "left")
	if switched:
		return [sd, mirror, "lead %s, a switch kick (built as the %s stance's rear leg)" % [hand_w, "southpaw" if mirror else "orthodox"]]
	return [sd, mirror, "%s %s (%s stance)" % [role, hand_w, "southpaw" if mirror else "orthodox"]]


static func _o(sd: String) -> String:
	return "_r" if sd == "_l" else "_l"


## the guard: knees soft, hips bladed 20 deg to his right (the lead side forward), both fists ~22 cm in front of the chin
## (an elbow folded to 125: at 135 the forearms sat 2.4 cm inside the chest, Body.contacts)
static func guard() -> Dictionary:
	return {"pelvis": Vector3(0, 0, -20), "spine_03": Vector3(0, 0, -5), "upperarm_l": Vector3(35, -55, 0), "lowerarm_l": Vector3(125, 0, 0),
		"upperarm_r": Vector3(35, -55, 0), "lowerarm_r": Vector3(125, 0, 0)}


## a pose on B: the guard, the angles on top, the listed feet planted [ball, heading, flat] (a missing foot hangs from the
## hips as the angles put it), the hips moved by off. Returns B.to_dict()
static func pose(B: Body, angs: Dictionary, feet: Dictionary, off := Vector3.ZERO, arm := []) -> Dictionary:
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.wep_on = false
	B.grip = false
	B.offset = Vector3(0, DROP, 0) + off
	var base := guard()
	base.merge({"thigh_l": Vector3(20, 0, 0), "calf_l": Vector3(15, 0, 0), "thigh_r": Vector3(-15, 0, 0), "calf_r": Vector3(10, 0, 0)})
	for j in base:
		B.ang[j] = B.clamp_ang(j, base[j])
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.hand_shape("l", "fist")
	B.hand_shape("r", "fist")
	B.fk()
	if not arm.is_empty():   # [side, upper arm dir, forearm dir] (_arm)
		_arm(B, arm[0], arm[1], arm[2])
	for sd in feet:
		var f: Array = feet[sd]
		B.plant(sd, f[0], f[1], f[2])
	return B.to_dict()


## both feet on the stance, the rear heel turned by `rear` rad and lifted (a cross / a rear uppercut), the lead foot by `lead`
static func stance(rear := 0.0, lead := 0.0) -> Dictionary:
	return {"_l": [STANCE["_l"][0], float(STANCE["_l"][1]) + lead, absf(lead) < 0.05], "_r": [STANCE["_r"][0], float(STANCE["_r"][1]) + rear, absf(rear) < 0.05]}


## the straight punch's arm: the wrist put on the centre line ahead of the chin at shoulder height, REACH of the arm away
static func _straight(B: Body, sd: String) -> void:
	var sh: Vector3 = B.P["upperarm" + sd]
	var L: float = ((B.P["lowerarm" + sd] - sh) as Vector3).length() + ((B.P["hand" + sd] - B.P["lowerarm" + sd]) as Vector3).length()
	var aim := Vector3(0.0, sh.y + 0.02, sh.z + 1.5) - sh
	B.ang["upperarm" + sd] = B.clamp_ang("upperarm" + sd, Vector3(80, -10, 0))   # started out in front: from the chin the
	B.ang["lowerarm" + sd] = B.clamp_ang("lowerarm" + sd, Vector3(20, 0, 0))     # reach's turn runs the forearm into the chest
	B.fk()
	B.reach("hand" + sd, sh + aim.normalized() * L * REACH)
	B.ang["hand" + sd] = Vector3.ZERO
	B.fk()


## an arm put by DIRECTIONS in the chest's frame (the textbook words: "elbow level with the shoulder", "forearm upright"),
## not by raw angles: the upper arm along `up_dir`, the forearm along `fore_dir`, each [out (to the arm's own side), up,
## forward]; the app's own search (Body.search: coordinate descent inside the limits, the body's penetration costed)
static func _arm(B: Body, sd: String, up_dir: Vector3, fore_dir: Vector3) -> void:
	var ox := -1.0 if sd == "_r" else 1.0   # out to his right is -x
	var g: Quaternion = B.G["spine_03"]
	var wu: Vector3 = (g * Vector3(up_dir.x * ox, up_dir.y, up_dir.z)).normalized()
	var wf: Vector3 = (g * Vector3(fore_dir.x * ox, fore_dir.y, fore_dir.z)).normalized()
	var cost := func() -> float:
		var u: Vector3 = (B.P["lowerarm" + sd] - B.P["upperarm" + sd])
		var f: Vector3 = (B.P["hand" + sd] - B.P["lowerarm" + sd])
		return u.angle_to(wu) + f.angle_to(wf)
	B.search(["upperarm" + sd, "lowerarm" + sd], cost)
	B.fk()


## a kicking leg put by WORLD directions (x = his left, y up, z forward, the target straight ahead): the thigh along
## `th`, the shin along `sh`; Body.search over the hips (their tilt and lean: the hips' TURN held at its asked value,
## each degree off it costed) and the leg, inside the limits, the body's penetration costed
static func _leg(B: Body, sd: String, th: Vector3, sh: Vector3, lean := 35.0) -> float:
	var wt := th.normalized()
	var ws := sh.normalized()
	var tw0: float = B.ang["pelvis"].z
	var cost := func() -> float:
		var u: Vector3 = (B.P["calf" + sd] - B.P["thigh" + sd])
		var f: Vector3 = (B.P["foot" + sd] - B.P["calf" + sd])
		# the trunk may lean away from the kick up to `lean` deg off upright (HEURISTIC); past it, steeply costed
		var up: Vector3 = (B.P["neck_01"] - B.P["pelvis"]).normalized()
		var tilt := rad_to_deg(up.angle_to(Vector3.UP))
		return u.angle_to(wt) + f.angle_to(ws) + deg_to_rad(absf(float(B.ang["pelvis"].z) - tw0)) * 2.0 + deg_to_rad(maxf(0.0, tilt - lean)) * 4.0
	# several starts, the best kept (a coordinate descent is local: from the standing leg it stalled with the knee half
	# open on the side kick's chamber, cost 1.4 rad; seeded with the knee bent it stalled on the roundhouse's strike)
	var js := ["pelvis", "thigh" + sd, "calf" + sd]
	var start := {}
	for j in js:
		start[j] = B.ang[j]
	var kb := rad_to_deg(wt.angle_to(ws))
	var best := INF
	var keep := {}
	for seed in [Vector3(0, 0, -1), Vector3(60, 0, kb), Vector3(90, 40, kb), Vector3(100, 45, 120)]:
		for j in js:
			B.ang[j] = start[j]
		if seed.z >= 0.0:
			B.ang["thigh" + sd] = B.clamp_ang("thigh" + sd, Vector3(seed.x, seed.y, 0))
			B.ang["calf" + sd] = B.clamp_ang("calf" + sd, Vector3(seed.z, 0, 0))
		B.fk()
		var cc := B.search(js, cost)
		if cc < best:
			best = cc
			for j in js:
				keep[j] = B.ang[j]
	for j in js:
		B.ang[j] = keep[j]
	B.fk()
	var c := best
	return c


## the centre of mass over the standing foot: the hips moved (the offset) until it is BAL_IN inside it, the foot re-planted
static func _balance(B: Body, sd: String, f: Array) -> void:
	for it in 4:
		var bal := Balance.read(B)
		var poly: PackedVector2Array = bal["poly"]
		if poly.size() < 3:
			return
		var com: Vector3 = bal["com"]
		var q := Vector2(com.x, com.z)
		var ctr := Vector2.ZERO
		for v in poly:
			ctr += v
		ctr /= poly.size()
		if float(bal["margin"]) >= BAL_IN:
			return
		var d := (ctr - q)
		var need := d.normalized() * minf(d.length(), (BAL_IN - float(bal["margin"])) + 0.01)
		B.offset += Vector3(need.x, 0.0, need.y)
		B.fk()
		B.plant(sd, f[0], f[1], f[2])


## THE LOAD (N031): the weight put over the support foot with BOTH feet still down, before the kicking foot leaves. A kicker's
## support leg loads before toe-off (Kinoshita & Fujii 2014, ISBS, taekwondo roundhouse: the support hip "generated the largest
## energy of all joints" in the READY phase before toe-off; docs/research/WEIGHT_TRANSFER.md). Built without it, the chamber
## carried the centre of mass ~0.2 m forward and 0.1 m across in one 0.22 s card (BODY ACCEL start 17.0 / stop 17.4 m/s^2 on
## the roundhouse, the cap 8.48 / 11.02), and the fix slowed the flowing chamber-and-strike until the foot came in at 7.1 m/s.
## Here the hips are moved (the offset) until the centre of mass stands where the chamber's will (`goal`, x and z), the
## support foot flat and turned `head`, the kicking foot on its stance spot with the heel up (the toes the last thing down);
## the hips sink (up to LOAD_SINK) while that back foot cannot reach its spot. The same pose is the landing after the kick:
## the foot down first, the weight still forward, THEN back to the guard (in the air the weight moved back over nothing: TIPPING).
const LOAD_SINK := 0.04      # m: the most the hips sink to keep the back toes down in the load (HEURISTIC: at 0.08, WeightXfer.SINK_MAX's
                             # figure, the chamber then RAISED the centre of mass 0.08-0.13 m in one card: RISE 25.5 m/s^2, cap 14.7)
const LOAD_SHARE := 0.5     # of the way from the guard's centre of mass to the chamber's, the load carries it (HEURISTIC: all the way,
                             # the back toes could not reach their spot without the hips sinking 0.08+)
static func _load(B: Body, sd: String, angs: Dictionary, head: float, chamber_com: Vector3, guard_com: Vector3) -> Dictionary:
	var o := _o(sd)
	var goal := guard_com.lerp(chamber_com, LOAD_SHARE)
	var feet := {o: [STANCE[o][0], float(STANCE[o][1]) + head, true], sd: [STANCE[sd][0], float(STANCE[sd][1]), true]}
	pose(B, angs, feet)
	for it in 12:
		var c := Balance.com(B)
		var d := Vector3(goal.x - c.x, 0.0, goal.z - c.z)
		var miss := 0.0
		B.offset += d
		B.fk()
		for k in feet:
			miss = maxf(miss, B.plant(k, feet[k][0], feet[k][1], feet[k][2]))
		if miss > 0.01 and B.offset.y > DROP - LOAD_SINK:
			B.offset.y -= 0.01
			B.fk()
			for k in feet:
				B.plant(k, feet[k][0], feet[k][1], feet[k][2])
		elif d.length() < 0.003 and miss <= 0.01:
			break
	# the back foot's toes flat on the floor: heel up, the foot pitched, the toe tip dug 5.6 cm under it (the floor pass
	# then lifted the whole body that much as the card played: a 0.06 m bob, BODY ACCEL rise 20.9 m/s^2); bent at the ball
	var toe := "ball" + sd
	var best := INF
	var keep: Vector3 = B.ang[toe]
	for x in range(-60, 61, 2):
		B.ang[toe] = B.clamp_ang(toe, Vector3(x, 0, 0))
		B.fk()
		var dy := absf((B.E[toe] as Vector3).y - (B.e0[toe] as Vector3).y)
		if dy < best:
			best = dy
			keep = B.ang[toe]
	B.ang[toe] = keep
	B.fk()
	return B.to_dict()


## a card: {name, pose, move, hold}
static func _c(nm: String, p: Dictionary, mv: float, hold: float) -> Dictionary:
	return {"name": nm, "pose": p, "move": mv, "hold": hold}


## the key cards of a move (orthodox; sd = the striking side) and their roles. -> [cards, roles]
static func keys(B: Body, move: String, sd: String) -> Array:
	var o := _o(sd)
	var sg := 1.0 if sd == "_r" else -1.0   # + = the hips turn to his left: a right-hand / right-leg strike turns that way
	var cards := []
	var roles := []
	var g := stance()
	var ready := pose(B, {}, g)
	var g_com := Balance.com(B)
	cards.append(_c("ready: guard", ready, -1.0, 0.3))
	roles.append("ready")
	var add := func(nm: String, role: String, p: Dictionary, mv: float, hold: float) -> void:
		cards.append(_c(nm, p, mv, hold))
		roles.append(role)
	match move:
		"jab", "cross":
			var rear := sd == "_r"
			# the load: the weight settles, the hips open a touch away from the punch
			add.call("anticipation: load", "anticipation", pose(B, {"pelvis": Vector3(0, 0, -20 - 8.0 * sg), "spine_03": Vector3(0, 0, -5 - 4.0 * sg)}, g, Vector3(0, -0.01, -0.01)), 0.12, 0.0)
			# the strike: hips and shoulders turned into it, the rear heel out on a cross, the weight forward
			var turn := 50.0 if rear else -12.0
			var st := stance(0.6 if rear else 0.0, 0.0)
			var a := {"pelvis": Vector3(0, 0, -20 + turn), "spine_03": Vector3(0, 0, -5 + turn * 0.4), "neck_01": Vector3(0, 0, -turn * 0.35)}
			pose(B, a, st, Vector3(0, -0.015, 0.05 if rear else 0.04))
			_straight(B, sd)
			for sd2 in st:
				B.plant(sd2, st[sd2][0], st[sd2][1], st[sd2][2])
			add.call("STRIKE: %s" % move, "strike", B.to_dict(), 0.12, 0.06)
			add.call("recovery: guard", "recovery", ready.duplicate(true), 0.2, 0.3)
		"hook":
			var lead := sd == "_l"
			# the load: the hips turned away from the punch, the weight on the punching side, the elbow opening out from the
			# guard (the fist still by the chin)
			var ld := {"pelvis": Vector3(0, 0, -20 - 15.0 * sg), "spine_03": Vector3(0, 0, -5 - 10.0 * sg)}
			add.call("anticipation: load", "anticipation", pose(B, ld, g, Vector3(-0.02 * sg, -0.02, 0), [sd, Vector3(0.65, -0.3, 0.7), Vector3(-0.25, 0.8, 0.55)]), 0.15, 0.0)
			# the strike: the elbow out level with the shoulder, the forearm level across the front (bent ~90), the hips and
			# chest turned through into it, the punching side's foot pivoting
			var st := stance(0.5 if not lead else 0.0, -0.6 if lead else 0.0)
			var a := {"pelvis": Vector3(0, 0, -20 + 45.0 * sg), "spine_03": Vector3(0, 0, -5 + 8.0 * sg), "neck_01": Vector3(0, 0, -15.0 * sg)}
			add.call("STRIKE: hook", "strike", pose(B, a, st, Vector3(0, -0.02, 0.02), [sd, Vector3(0.7, 0.0, 0.72), Vector3(-0.75, 0.0, 0.66)]), 0.12, 0.06)
			add.call("recovery: guard", "recovery", ready.duplicate(true), 0.22, 0.3)
		"uppercut":
			var rear := sd == "_r"
			# the dip: knees bend, the hips load away, the fist drops by the ribs (upper arm hanging, forearm pointing ahead)
			var dip := {"pelvis": Vector3(0, 0, -20 - 6.0 * sg), "spine_03": Vector3(0, 0, -5 - 5.0 * sg), "spine_01": Vector3(10, 0, 0)}
			add.call("anticipation: dip", "anticipation", pose(B, dip, g, Vector3(0, -0.09, 0), [sd, Vector3(0.15, -0.97, 0.2), Vector3(-0.15, 0.35, 0.92)]), 0.2, 0.0)
			# the legs and hips drive first (a pass-through card: the move flows on into the strike): the hips are most of the
			# way round and up while the arm keeps its dip shape, so the hips peak before the arm turns (the Check's SEQUENCE)
			var drv := {"pelvis": Vector3(0, 0, -20 + 18.0 * sg), "spine_03": Vector3(0, 0, -5), "spine_01": Vector3(3, 0, 0)}
			add.call("anticipation: drive", "anticipation", pose(B, drv, stance(0.3 if rear else 0.0, 0.0 if rear else -0.2), Vector3(0, -0.05, 0.01), [sd, Vector3(0.15, -0.97, 0.2), Vector3(-0.15, 0.35, 0.92)]), 0.12, 0.0)
			cards[-1]["flow"] = true
			# the strike: the fist up in front of the chin, the forearm upright, the elbow bent ~90 and under it
			var st := stance(0.5 if rear else 0.0, 0.0 if rear else -0.3)
			var a := {"pelvis": Vector3(0, 0, -20 + 28.0 * sg), "spine_03": Vector3(0, 0, -5 + 5.0 * sg), "spine_01": Vector3(-5, 0, 0)}
			add.call("STRIKE: uppercut", "strike", pose(B, a, st, Vector3(0, 0.01, 0.02), [sd, Vector3(0.1, -0.6, 0.8), Vector3(-0.15, 0.95, 0.25)]), 0.14, 0.06)
			add.call("recovery: guard", "recovery", ready.duplicate(true), 0.22, 0.3)
		"front kick":
			var sup := {o: [STANCE[o][0], STANCE[o][1], true]}
			var ch := {"thigh" + sd: Vector3(90, 0, 0), "calf" + sd: Vector3(115, 0, 0), "foot" + sd: Vector3(-20, 0, 0), "pelvis": Vector3(-5, 0, -10), "spine_01": Vector3(-5, 0, 0)}
			B.offset = Vector3.ZERO
			pose(B, ch, sup)
			_balance(B, o, sup[o])
			var chamber := B.to_dict()
			var ld := _load(B, sd, {"pelvis": Vector3(-3, 0, -15)}, 0.0, Balance.com(B), g_com)
			add.call("anticipation: load", "anticipation", ld, KICK_LOAD, 0.0)
			add.call("anticipation: chamber", "anticipation", chamber, KICK_CHAMBER, 0.0)
			var ex := {"thigh" + sd: Vector3(85, 0, 0), "calf" + sd: Vector3(5, 0, 0), "foot" + sd: Vector3(-25, 0, 0), "ball" + sd: Vector3(-30, 0, 0),
				"pelvis": Vector3(-12, 0, -5), "spine_01": Vector3(-8, 0, 0)}
			pose(B, ex, sup, Body._v(chamber["offset"]) - Vector3(0, DROP, 0))
			_balance(B, o, sup[o])
			add.call("STRIKE: front kick", "strike", B.to_dict(), 0.12, 0.05)
			add.call("follow-through: re-chamber", "follow-through", chamber.duplicate(true), 0.14, 0.0)
			add.call("recovery: foot down", "recovery", ld.duplicate(true), KICK_LAND, 0.0)
			add.call("recovery: guard", "recovery", ready.duplicate(true), KICK_BACK, 0.3)
		"roundhouse":
			# directions in the world frame (x = his left; so a right leg's "out" is -x): mirrored for a left leg
			var X := -sg
			var sup1 := {o: [STANCE[o][0], float(STANCE[o][1]) + 1.0 * sg, true]}
			var sup2 := {o: [STANCE[o][0], float(STANCE[o][1]) + 2.0 * sg, true]}
			# the chamber: the support heel turns, the hips half over, the knee up level with the hip pointing ahead, the
			# shin folded back out to the kicking side and level (the plane the shin will sweep)
			pose(B, {"pelvis": Vector3(0, 0, -20 + 70.0 * sg), "spine_03": Vector3(0, 0, -5.0 * sg)}, {})
			_leg(B, sd, Vector3(0.05 * X, 0.0, 1.0), Vector3(0.85 * X, -0.3, -0.4))
			for k2 in sup1:
				B.plant(k2, sup1[k2][0], sup1[k2][1], sup1[k2][2])
			_balance(B, o, sup1[o])
			var chamber := B.to_dict()
			# the load: the support heel starting to turn, the hips a third of the way round, the weight already over the support
			var ld := _load(B, sd, {"pelvis": Vector3(0, 0, -20 + 30.0 * sg)}, 0.5 * sg, Balance.com(B), g_com)
			add.call("anticipation: load", "anticipation", ld, KICK_LOAD, 0.0)
			add.call("anticipation: pivot and chamber", "anticipation", chamber, KICK_CHAMBER, 0.0)
			cards[-1]["flow"] = true   # a roundhouse does not stop at the chamber: the hips turn on through it into the kick
			# the strike: the hips turned over (~120 deg from the guard; Gavagan & Sayers' pelvis ~130), the shin swept level
			# round to the front, the leg near straight at rib height, the body leaning away
			pose(B, {"pelvis": Vector3(0, 0, -20 + 120.0 * sg), "spine_03": Vector3(0, 0, -5.0 * sg), "neck_01": Vector3(0, 0, -30.0 * sg)}, {})
			_leg(B, sd, Vector3(-0.15 * X, 0.2, 0.97), Vector3(-0.1 * X, 0.25, 0.96))
			B.ang["foot" + sd] = B.clamp_ang("foot" + sd, Vector3(-30, 0, 0))   # the instep / shin leads: toes pointed
			B.fk()
			for k2 in sup2:
				B.plant(k2, sup2[k2][0], sup2[k2][1], sup2[k2][2])
			_balance(B, o, sup2[o])
			add.call("STRIKE: roundhouse", "strike", B.to_dict(), 0.14, 0.05)
			# the re-chamber: the shin folds back, the hips still over
			pose(B, {"pelvis": Vector3(0, 0, -20 + 100.0 * sg), "spine_03": Vector3(0, 0, -5.0 * sg), "neck_01": Vector3(0, 0, -25.0 * sg)}, {})
			_leg(B, sd, Vector3(-0.1 * X, 0.0, 1.0), Vector3(0.5 * X, -0.5, -0.7))
			for k2 in sup2:
				B.plant(k2, sup2[k2][0], sup2[k2][1], sup2[k2][2])
			_balance(B, o, sup2[o])
			add.call("follow-through: re-chamber", "follow-through", B.to_dict(), 0.18, 0.0)
			add.call("recovery: foot down", "recovery", ld.duplicate(true), KICK_LAND, 0.0)
			add.call("recovery: guard", "recovery", ready.duplicate(true), KICK_BACK + 0.1, 0.3)
		"side kick":
			var X := -sg
			var sup := {o: [STANCE[o][0], float(STANCE[o][1]) + 1.5 * sg, true]}
			# the chamber: the support foot turned, the hips side-on (the kicking hip toward the target), the knee drawn up
			# across the body and folded tight (~115 deg), the foot by the hip with the heel aimed at the target
			pose(B, {"pelvis": Vector3(0, 0, -20 + 90.0 * sg), "spine_03": Vector3(0, 0, -5.0 * sg), "neck_01": Vector3(0, 0, -30.0 * sg)}, {})
			_leg(B, sd, Vector3(-0.8 * X, 0.5, 0.25), Vector3(0.85 * X, -0.3, 0.4))
			for k2 in sup:
				B.plant(k2, sup[k2][0], sup[k2][1], sup[k2][2])
			_balance(B, o, sup[o])
			var chamber := B.to_dict()
			var ld := _load(B, sd, {"pelvis": Vector3(0, 0, -20 + 40.0 * sg)}, 0.75 * sg, Balance.com(B), g_com)
			add.call("anticipation: load", "anticipation", ld, KICK_LOAD, 0.0)
			add.call("anticipation: chamber", "anticipation", chamber, KICK_CHAMBER + 0.05, 0.0)
			# the strike: the leg driven straight out along the hip line at hip height, heel leading (toes pulled up)
			pose(B, {"pelvis": Vector3(0, 0, -20 + 95.0 * sg), "spine_03": Vector3(0, 0, -5.0 * sg), "neck_01": Vector3(0, 0, -30.0 * sg)}, {})
			_leg(B, sd, Vector3(0.0, 0.05, 1.0), Vector3(0.0, 0.05, 1.0))
			B.ang["foot" + sd] = B.clamp_ang("foot" + sd, Vector3(20, 0, 0))
			B.fk()
			for k2 in sup:
				B.plant(k2, sup[k2][0], sup[k2][1], sup[k2][2])
			_balance(B, o, sup[o])
			add.call("STRIKE: side kick", "strike", B.to_dict(), 0.12, 0.05)
			add.call("follow-through: re-chamber", "follow-through", chamber.duplicate(true), 0.15, 0.0)
			add.call("recovery: foot down", "recovery", ld.duplicate(true), KICK_LAND, 0.0)
			add.call("recovery: guard", "recovery", ready.duplicate(true), KICK_BACK + 0.05, 0.3)
	return [cards, roles]


## the striking point's world speed per frame (60 fps) as the scene plays: the fist (the hand's end, what FIST SPEED reads)
## or the ball of the foot (the recognizer's striking point for a kick)
static func point_speed(S: Scene, B: Body, pt: String, rel := false) -> Array:
	var n := int(ceil(S.length() * 60.0)) + 1
	var out := []
	var prev := Vector3.ZERO
	var prev_h := Vector3.ZERO
	for i in n:
		S.apply(B, minf(i / 60.0, S.length()))
		var p: Vector3 = B.E[pt] if pt.begins_with("hand") else B.P[pt]
		var h: Vector3 = B.P["pelvis"]
		var d := (p - prev) - ((h - prev_h) if rel else Vector3.ZERO)
		out.append(d.length() * 60.0 if i > 0 else 0.0)
		prev = p
		prev_h = h
	out[0] = out[1] if n > 1 else 0.0
	return out


## the strike card's move retimed until the striking point peaks at `target` m/s (within PEAK_TOL) inside the strike's
## move; then any other part where the point runs faster than that (the retraction, the foot going down) slowed until
## the strike holds the move's peak. -> [peak, t]
static func time_to_peak(S: Scene, B: Body, s: int, pt: String, target: float) -> Array:
	var pk := [0.0, 0.0]
	var s0 := first_of_strike(S, s)
	for it in 12:
		var sp := point_speed(S, B, pt)
		var ts := S.times()
		var a := int(floor(float(ts[s0][0]) * 60.0))
		var b := mini(int(ceil(float(ts[s][2]) * 60.0)), sp.size() - 1)
		var bi := a
		for i in range(a, b + 1):
			if float(sp[i]) > float(sp[bi]):
				bi = i
		pk = [float(sp[bi]), bi / 60.0]
		if absf(pk[0] / target - 1.0) > PEAK_TOL:
			S.retime(s0, s, clampf(pk[0] / target * 100.0, 50.0, 200.0))
			continue
		if _others_slower(S, B, s, pt, pk[0]):
			break
	return pk


## outside the strike: the fastest frame before it (the wind-up) and after it (the return), read as MoveRecognizer
## reads it too (the point's velocity less the hips': a kick's return outran the strike there while the hips carried
## the strike); a part running over 0.85 of the strike's peak slowed. -> true when nothing needed slowing
static func _others_slower(S: Scene, B: Body, s: int, pt: String, peak: float) -> bool:
	var s0 := first_of_strike(S, s)
	var sp := point_speed(S, B, pt)
	var ts := S.times()
	var a := int(floor(float(ts[s0][0]) * 60.0))
	var b := mini(int(ceil(float(ts[s][2]) * 60.0)), sp.size() - 1)
	var rs := point_speed(S, B, pt, true)
	var rtop := 0.0
	for i in range(a, b + 1):
		rtop = maxf(rtop, float(rs[i]))
	var done := true
	for part in [[0, a - 1, 1, s0 - 1], [b + 1, sp.size() - 1, s + 1, S.cards.size() - 1]]:
		if part[2] > part[3]:
			continue
		var top := 0.0
		var rt := 0.0
		for i in range(maxi(part[0], 0), mini(part[1], sp.size() - 1) + 1):
			top = maxf(top, float(sp[i]))
			rt = maxf(rt, float(rs[i]))
		var f := maxf(top / peak, rt / maxf(rtop, 0.1))
		if f > 0.85:
			S.retime(part[2], part[3], clampf(f / 0.8 * 100.0, 105.0, 200.0))
			done = false
	return done


static func _part(t: float, ts: Array, s: int, n: int, s0: int) -> String:
	if t < float(ts[s0][0]) - 1e-3 and s0 >= 2:
		return "anticipation"
	if t > float(ts[s][2]) + 1e-3 and n - 1 > s:
		return "after the strike"
	return "strike"


## the strike's first card: a pass-through ("flow") card before it is eased with it as one move (Scene's FLOW), so the
## strike's move starts there
static func first_of_strike(S: Scene, s: int) -> int:
	var k := s
	while k - 1 >= 1 and bool(S.cards[k - 1].get("flow", false)):
		k -= 1
	return k


## the striking point's name on the body: the fist (hand's end) or the ball of the foot
static func point_of(move: String, sd: String) -> String:
	return ("ball" if move in ["front kick", "roundhouse", "side kick"] else "hand") + sd


## THE BLOCKING of a generated move, in TextBlocking.build's result shape (the test and the AI box read the same keys).
## P: TextBlocking.parse's words; move: move_of(P)
static func build(P: Dictionary, B: Body, move: String, text: String) -> Dictionary:
	var notes: Array = P["notes"].duplicate()
	var sm0 := side_of(move, String(P["side"]), String(P.get("lead", "")))
	var sd: String = sm0[0]
	var mirror: bool = sm0[1]
	var kick := move in ["front kick", "roundhouse", "side kick"]
	notes.append("no saved %s to start from: generated as key poses (%s; StrikeBlocking)" % [move, sm0[2]])
	var kr := keys(B, move, sd)
	var S := Scene.new()
	S.name = TextBlocking.slug(text)
	S.cards = kr[0]
	var roles: Array = kr[1]
	var n := S.cards.size()
	var s := roles.find("strike")
	if mirror:
		var M := Body.new()
		M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		for i in n:
			S.cards[i] = Scene.mirror_card(S.cards[i], M)
		sd = _o(sd)
		notes.append("mirrored (Mirror the scene, card by card): the words want the other side")
	var foot := String(P["foot"])
	if kick and foot in ["in", "back", "lunge"]:
		notes.append("%s: a kick stands on its other foot; the step is not added" % foot)
	elif foot != "":
		var fw := TextBlocking._footwork(S, roles, foot, mirror)
		if fw != "":
			notes.append(fw)
	S.pin_cards(B)
	# the wind-up and the recovery: the fist's row of ATTACK_RULES (knife: a hand's speed), a kick's HEURISTIC times
	var sp: Array = TextBlocking.SPEED_F.get(P["speed"], [1.0, 1.0])
	var rules: Array = AT.RULES["knife"]
	var ant: float = (KICK_CHAMBER if kick else TextBlocking._mid(rules[0])) * float(sp[0])
	var rec: float = (KICK_BACK if kick else TextBlocking._mid(rules[2])) * float(sp[1])
	var retimes := {}
	var s0 := first_of_strike(S, s)
	if s0 >= 2:
		retimes["anticipation"] = TextBlocking._retime_to(S, 1, s0 - 1, ant)
	if n - 1 > s:
		retimes["recovery"] = TextBlocking._retime_to(S, s + 1, n - 1, rec, true)
	if String(P["speed"]) == "heavy":
		S.cards[s]["ease"] = "in"
		notes.append("heavy: the strike's ease is \"in\" (it accelerates into the contact)")
	# the strike timed to the cited speed, then slowed wherever the Check or the human limits object
	var pt := point_of(move, sd)
	var target: float = PEAK[move][0]
	var cap: float = Rulebook.FIST_WARN
	var cap_name := "fist (Rulebook.FIST_WARN)"
	if kick:
		cap = 14.66 + 2.0 * 1.18
		cap_name = "foot (kick_foot_speed + 2 SD, 14.66 + 2 x 1.18)"
	var pk := time_to_peak(S, B, s, pt, target)
	notes.append("the strike timed so the %s peaks at the cited %.1f m/s (%s): %.1f m/s" % ["foot" if kick else "fist", target, PEAK[move][1], pk[0]])
	var slowed := {"anticipation": [], "strike": [], "after the strike": []}
	var fs := []
	var human := []
	for it in 10:
		fs = Rulebook.check(S, B)
		human = HumanLimits.findings(S, B)
		# SEQUENCE is the order of the joints' peaks, which no retime changes (every move scales alike): left to the poses
		var bad: Array = fs.filter(func(f): return f["sev"] == "FAIL" and f["rule"] != "SEQUENCE") + human
		var spx := point_speed(S, B, pt)
		var bx := 0
		for i in spx.size():
			if float(spx[i]) > float(spx[bx]):
				bx = i
		if float(spx[bx]) > TextBlocking.SAFE * cap:
			bad.push_front({"rule": "TIP SPEED", "t": bx / 60.0})
		if bad.is_empty():
			break
		var f: Dictionary = bad[0]
		var ts := S.times()
		var part := _part(float(f["peak_frame"]) / BodyCaps.FPS if f.has("peak_frame") else float(f["t"]), ts, s, n, s0)   # N031: BODY ACCEL: where it peaks
		var why := "%s%s" % [f["rule"], (" (" + String(f["joint"]).replace("_", " ") + ")") if f.has("joint") else ""]
		var pct := BodyCaps.stretch(f) if f["rule"] == "BODY ACCEL" else 115.0   # N031: a whole-body lurch slowed as much as it needs
		match part:
			"anticipation":
				S.retime(1, s0 - 1, pct)
			"strike":
				S.retime(s0, s, pct)
			_:
				S.retime(s + 1, n - 1, pct)
		(slowed[part] as Array).append(why)
	# the human-limit retimes slow the strike too: the wind-up and the return slowed again under it (the recognizer reads
	# the fastest moment as the strike), then the Check read once more
	var again := false
	for it in 6:
		var sp0 := point_speed(S, B, pt)
		var ts0 := S.times()
		var top0 := 0.0
		for i in range(int(floor(float(ts0[s0][0]) * 60.0)), mini(int(ceil(float(ts0[s][2]) * 60.0)), sp0.size() - 1) + 1):
			top0 = maxf(top0, float(sp0[i]))
		if _others_slower(S, B, s, pt, top0):
			break
		again = true
	if again:
		fs = Rulebook.check(S, B)
		human = HumanLimits.findings(S, B)
		notes.append("the wind-up / return slowed under the strike again")
	var slow_words := []
	for part in slowed:
		var ws: Array = slowed[part]
		if not ws.is_empty():
			slow_words.append("%s x%d (%s)" % [part, ws.size(), ws[-1]])
	if not slow_words.is_empty():
		notes.append("then slowed again (retime) " + "; ".join(slow_words))
	var spd := point_speed(S, B, pt)
	var ts2 := S.times()
	var best := 0
	for i in spd.size():
		if float(spd[i]) > float(spd[best]):
			best = i
	var peak_v := float(spd[best])
	var peak_t := best / 60.0
	var must := fs.filter(func(f): return f["sev"] == "FAIL")
	var words := func(a: Array) -> Array: return a.map(func(f): return "%s at %.2f s" % [f["rule"], f["t"]])
	var status := "%s. %s" % [notes[0] if not notes.is_empty() else "", "; ".join(notes.slice(1))]
	if not must.is_empty():
		status += ". MUST FIX: " + ", ".join(words.call(must))
	if not human.is_empty():
		status += ". Human-limit finding: " + ", ".join(words.call(human))
	var unk: Array = P["unknown"]
	if not unk.is_empty():
		status += ". Didn't understand: " + ", ".join(unk)
	var src := {"scene": "generated: %s" % move, "kind": "", "hand": "", "two": false, "ready": 0, "windup": range(1, s),
		"strike": s, "ft": range(s + 1, n - 1).filter(func(i): return roles[i] == "follow-through"), "recovery": n - 1, "dropped": [],
		"dir": move, "side": "left" if sd == "_l" else "right", "step": {}, "peak": peak_v, "cards": n, "feat": {}}
	var zeros := []
	zeros.resize(n)
	zeros.fill(0.0)

	return {"ok": true, "scene": S, "source": src, "mirror": mirror, "roles": roles, "kind": "", "shape": move,
		"asked_shape": TextBlocking._shape(P["attack"]), "row": "knife" if not kick else "", "cap": cap,
		"cap_name": cap_name,
		"findings": fs, "must_fix": must.size(), "must_fix_new": words.call(must), "src_must_fix": 0, "human": human,
		"human_new": words.call(human), "src_human": 0, "peak": peak_v, "peak_t": peak_t,
		"window": [float(ts2[s0][0]), float(ts2[s][2])], "strike_card": s, "grip": zeros, "worst_grip": 0.0, "palm": zeros, "worst_palm": 0.0,
		"aim": 0.0, "moved": 0.0, "two": false, "unknown": unk, "notes": notes, "status": status, "retimes": retimes, "slowed": slowed,
		"foot": P["foot"], "speed": P["speed"], "side": src["side"], "generated": move, "point": pt, "target_peak": target}
