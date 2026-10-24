## spec_motion.gd - SPEC TO MOTION (docs/INNOVATIONS.md N004). A blind agent gives a move as a STRUCTURED SPEC and gets a
## clip that passes every assertion, or the list of the ones it could not meet, why, and how close it got:
##   {"kind": "jab", "side": "right", "target": "opponent's chin", "contact_t": 0.35,
##    "timing": {"anticipation": 0.15, "recovery": 0.3}, "contacts": ["both feet planted"],
##    "assertions": ["COM inside the feet all clip", "right fist touches the opponent's chin at 0.35 s +-1 f"]}
##   -> {"ok", "cards_added", "assertions": [{"line", "pass", "value", "unit"}], "unmet": [{"line", "why", "closest"}], ...}
## serve: spec {spec, apply?} (apply false = a DRY PLAN on a copy, nothing changes; true = the cards appended to the live scene as
## ONE undo step). CLI: spec <scene.json|-> <spec.json> [--dummy D] [--out <path>].
##
## THE PIPELINE (each step names the code it reuses):
##  1 BLOCKING from kind / side. A weapon move goes through ROADMAP 22's text-to-blocking (TextBlocking.build: one of Nick's
##    saved attack segments, retrieved and adapted; "bat swing left"). Fists and kicks do NOT: TEXT_TO_BLOCKING.md says no
##    saved punch or kick exists and "a bat chamber with a fist in it is not a boxer's jab", so they are blocked here from a
##    fighting stance (stand.json, the feet planted by Body.plant, the hands up by LimbIK.solve): READY (guard) ->
##    ANTICIPATION (the trunk loaded away / the knee chambered) -> STRIKE -> RECOVERY (guard). The words of the kind are read
##    by TextBlocking.parse's lexicon where it has them (jab / straight / hook / uppercut); the kicks are this file's.
##  2 TARGET: N007 words -> a point (BodyFrame.place, "opponent's chin" = "at the opponent's chin"), or [x, y, z] m. The
##    opponent is the live dummy (m.T: its body and placement) or the scene's second fighter.
##  3 TIMING: the strike card ARRIVES at contact_t. anticipation = the move into the anticipation card + its hold (3 : 1),
##    the strike move = the kind's budget (ATTACK_RULES.md: a fist 4 frames at 30 fps, the knife / light row TextBlocking
##    uses for fists; a kick 6 frames, the "<= 6 frames for any weapon" cap: no kick row exists, HEURISTIC; a weapon keeps
##    its row's strike from TextBlocking), the strike holds STRIKE_HOLD_F frames ("hold a key pose a few frames to sell
##    weight", ATTACK_RULES.md), recovery = from contact to the clip's end. The ready card holds what is left.
##  4 SOLVE: the strike END (a fist's knuckle face = the hand capsule's far end + its radius along it; a front kick's ball of
##    the foot = the toe base joint; a roundhouse's instep = the middle of the foot capsule's axis; a weapon's tip, as
##    measure's weapon_tip) put on the target point by LimbIK.solve on the wrist / ankle, iterated so the END (not the
##    wrist) lands, ON THE BODY AS IT PLAYS at contact_t (Scene.apply_true: on_floor's grounding and the pins act there)
##  5 CONTACTS: "both feet planted" / "left foot planted" keep that foot on its ready spot AND heading on every card (Body.plant;
##    flat, or on its ball with the heel up when the leg cannot reach flat; the hips sink when a straight leg leaves the ball
##    up) and become N002 lines ("left foot planted all clip") checked with the rest; a planted foot never steps or pivots
##    (Scene's pins hold a foot with the heading of its run's first card, so a card's pivot would never play).
##  6 CHECK: every line by BodyAssert.run (N002) on the clip, the dummy wired in as fighter 2 so "the opponent's chin" lines
##    read ("opponent's" / "dummy's" -> "fighter 2"), plus the implicit TARGET line: the end within tolerance_cm (default 3)
##    of the target at contact_t +-1 frame (the nearest frame in that window counts, N002's event rule).
##  7 REPAIR, bounded (ROUNDS rounds): target missed -> IK again on the played body, then the trunk leaned toward it inside the
##    lean interval N013's RangeSweep gives for "balance" (spine_02 bend), then (no planted contact on that foot) a STEP of the
##    lead foot for the shortfall, the hips 0.45 of it (TextBlocking.HIPS_PER_STEP); a foot not planted -> re-planted on every
##    card; COM past the feet -> the hips moved over them (TextBlocking's balance op: the card's offset, the feet re-planted);
##    a speed -> the strike move retimed (contact_t kept by the ready hold); an angle -> that joint clamped into the range on
##    the cards in the window. A weapon's tip short: the trunk turned (+-10..30 deg) on the strike card. A foot that leaves its
##    spot BETWEEN two cards that stand on it (two leg solutions blended across the move): a BREAKDOWN card at that time, the
##    pose as it plays there with the feet planted (at most 3; it takes its share of the move, so the strike still arrives at
##    contact_t). A line repaired twice without passing is not repaired again; the loop stops at TIME_CAP_MS. Then
##    everything is checked again.
##  8 UNMET: what still fails, with why ("reach: ... short") and the closest value it got (reach: the end's distance to the
##    target, cm). Nothing is hidden: the clip is returned (and applied, if asked) as made.
## The live scene, body and undo are not touched by a plan: the clip is built on its own Scene and Body.
class_name SpecMotion
extends RefCounted

const TOL_CM := 3.0           # cm: the strike end this close to the target counts as there (the item's bar)
const FIST_STRIKE := 4.0 / 30.0   # s: ATTACK_RULES.md knife / light row, 3-4 frames at 30 fps (TextBlocking's fist row)
const KICK_STRIKE := 6.0 / 30.0   # s: ATTACK_RULES.md "<= 6 frames at 30 fps (0.2 s) for any weapon"; no kick row: HEURISTIC
const STRIKE_MIN := 2.0 / 30.0    # s: the fastest a retime may make the strike (2 frames: one in-between)
const STRIKE_MAX := 0.3           # s: the slowest (HEURISTIC: past ATTACK_RULES' 0.2 s cap by half, the "too slow" side)
const STRIKE_HOLD_F := 2          # frames the strike pose holds (ATTACK_RULES.md: held 2-4 frames)
const STEP_MAX := 0.5             # m: the longest step for reach (HEURISTIC; TextBlocking's lunge is 0.4)
const ROUNDS := 6                 # repair rounds at most
const TIME_CAP_MS := 20000        # a spec's repair loop stops after this (reported as an unmet "timeout" line)
const BAL_IN := TextBlocking.BAL_IN   # m: the hips moved until the COM is this far inside the feet
const BLADE := 30.0               # deg: the stance's trunk turn away from the opponent (HEURISTIC: a bladed boxing stance)
const STANCE := {"lead_x": 0.11, "lead_z": 0.28, "rear_x": 0.15, "rear_z": -0.16, "lead_head": 0.25, "rear_head": 0.75}   # m / rad (HEURISTIC)

## kind -> the limb (hand / foot), whether the striking side is the LEAD side, the trunk turn into the strike (deg, + = the
## striking shoulder / hip goes forward), the pole (where the elbow / knee points), the strike end
const KINDS := {
	"jab": {"limb": "hand", "lead": true, "turn": 15.0, "pole": "down", "end": "fist", "load": -8.0},
	"cross": {"limb": "hand", "lead": false, "turn": 50.0, "pole": "down", "end": "fist", "load": -10.0},
	"hook": {"limb": "hand", "lead": true, "turn": 30.0, "pole": "out", "end": "fist", "load": -12.0},
	"uppercut": {"limb": "hand", "lead": false, "turn": 30.0, "pole": "under", "end": "fist", "load": -10.0},
	"front kick": {"limb": "foot", "lead": false, "turn": 30.0, "pole": "knee_up", "end": "ball", "load": 0.0},
	"roundhouse": {"limb": "foot", "lead": false, "turn": 60.0, "pole": "knee_side", "end": "instep", "load": 0.0}}
const ALIAS := {"straight": "cross", "rear straight": "cross", "punch": "jab", "lead hook": "hook", "front_kick": "front kick",
	"teep": "front kick", "push kick": "front kick", "roundhouse kick": "roundhouse", "round kick": "roundhouse",
	"round_kick": "roundhouse", "body kick": "roundhouse"}
const PLANT_WORDS := {"both feet planted": ["_l", "_r"], "feet planted": ["_l", "_r"], "both feet on the floor": ["_l", "_r"],
	"left foot planted": ["_l"], "right foot planted": ["_r"], "left foot on the floor": ["_l"], "right foot on the floor": ["_r"]}


static func _sd(word: String) -> String:
	return "_l" if word.to_lower().begins_with("l") else "_r"


static func _word(sd: String) -> String:
	return "left" if sd == "_l" else "right"


static func _other(sd: String) -> String:
	return "_r" if sd == "_l" else "_l"


static func _body(props: Dictionary) -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	if not props.is_empty():
		B.set_proportions(props)
	B.fk()
	return B


# ------------------------------------------------------------------------------------------------ the spec
## the spec -> {"ok", ...normalised} or {"ok": false, "error"}
static func read(spec: Variant) -> Dictionary:
	if not (spec is Dictionary):
		return {"ok": false, "error": "spec must be an object: {\"kind\": \"jab\", \"side\": \"right\", \"target\": \"opponent's chin\", \"contact_t\": 0.35, \"timing\": {\"anticipation\": 0.15, \"recovery\": 0.3}, \"contacts\": [\"both feet planted\"], \"assertions\": [...]}"}
	var s: Dictionary = spec
	var kind := String(s.get("kind", "")).to_lower().strip_edges().replace("-", " ")
	kind = ALIAS.get(kind, kind)
	var weapon := String(s.get("weapon", "")).to_lower().strip_edges()
	var out := {"ok": true, "kind": kind, "weapon": weapon}
	if weapon == "" and not KINDS.has(kind):
		var tp := TextBlocking.parse(kind)   # "bat swing", "axe overhead": a weapon in the kind's own words
		if tp["ok"] and String(tp["kind"]) != "":
			weapon = String(tp["weapon"])
			out["weapon"] = weapon
		elif tp["ok"] and KINDS.has(String(tp["attack"])):
			kind = String(tp["attack"])
			out["kind"] = kind
		else:
			return {"ok": false, "error": "kind '%s': say one of %s, or a weapon move (kind \"swing\" / \"overhead\" / \"thrust\" with \"weapon\": \"bat\")" % [s.get("kind", ""), ", ".join(KINDS.keys())]}
	if weapon != "" and not TextBlocking.WEAPON.has(weapon):
		return {"ok": false, "error": "weapon '%s': say one of %s" % [weapon, ", ".join(TextBlocking.WEAPON.keys().filter(func(w): return TextBlocking.WEAPON[w] != ""))]}
	var side := String(s.get("side", "right")).to_lower()
	if not side in ["left", "right", "l", "r"]:
		return {"ok": false, "error": "side is \"left\" or \"right\" (the striking hand / foot; for a weapon, where the swing ends)"}
	out["side"] = "left" if side.begins_with("l") else "right"
	if not s.has("target"):
		return {"ok": false, "error": "target: N007 words (\"opponent's chin\", \"15 cm in front of the opponent's chin\") or a point [x, y, z] m"}
	out["target"] = s["target"]
	var ct: Variant = s.get("contact_t", 0.35)
	if not (ct is float or ct is int) or float(ct) <= 0.0:
		return {"ok": false, "error": "contact_t: the time (s, > 0) the strike end reaches the target, from the clip's first card"}
	out["contact_t"] = float(ct)
	var tm: Variant = s.get("timing", {})
	if not (tm is Dictionary):
		return {"ok": false, "error": "timing: {\"anticipation\": s, \"recovery\": s}"}
	out["anticipation"] = float(tm.get("anticipation", 0.15))
	out["recovery"] = float(tm.get("recovery", 0.3))
	if out["anticipation"] < 0.0 or out["recovery"] <= 0.0:
		return {"ok": false, "error": "timing: anticipation >= 0 and recovery > 0 seconds"}
	var plant := []
	var cs: Variant = s.get("contacts", [])
	if cs is String:
		cs = [cs]
	if not (cs is Array):
		return {"ok": false, "error": "contacts: a list like [\"both feet planted\"]"}
	for c in cs:
		var w := String(c).to_lower().strip_edges().trim_prefix("the ").rstrip(".")
		if not PLANT_WORDS.has(w):
			return {"ok": false, "error": "contact '%s': say one of %s" % [c, ", ".join(PLANT_WORDS.keys())]}
		for sd in PLANT_WORDS[w]:
			if not sd in plant:
				plant.append(sd)
	out["planted"] = plant
	var al: Variant = s.get("assertions", [])
	if not (al is Array) or not (al as Array).all(func(x): return x is String):
		return {"ok": false, "error": "assertions: a list of N002 lines", "grammar": BodyAssert.GRAMMAR}
	out["assertions"] = al
	out["tolerance_cm"] = float(s.get("tolerance_cm", TOL_CM))
	out["end"] = String(s.get("end", ""))
	out["name"] = String(s.get("name", (weapon + " " if weapon != "" else "") + kind))
	return out


## an N002 line with the opponent named the way BodyAssert reads him: fighter 2
static func opp_line(l: String) -> String:
	var s := l
	for w in ["the opponent's ", "opponent's ", "the opponent ", "the dummy's ", "dummy's ", "the dummy ", "the opponent’s ", "opponent’s "]:
		s = s.replace(w, "fighter 2 ").replace(w.capitalize(), "fighter 2 ")
	return s


# ------------------------------------------------------------------------------------------------ the opponent
## {"B": Body, "xf": Transform3D, "file_xf": {"pos", "yaw"} (Constraints.actor_xf's form), "name"} or {} (none)
static func opponent(m: Node) -> Dictionary:
	if m.S.actors.size() > 0:
		var a: Dictionary = m.S.actors[0]
		var bk := _body({})
		(a["scene"] as Scene).apply_true(bk, 0.0)
		return {"B": bk, "xf": Constraints.actor_xf(a["xf"]), "file_xf": (a["xf"] as Dictionary).duplicate(true), "name": String(a["name"]), "scene": a["scene"]}
	if m.dummy_on:
		var T: Dummy = m.T
		return {"B": T.D, "xf": T.xf, "file_xf": {"pos": [T.dist * sin(deg_to_rad(T.yaw)), T.dist * cos(deg_to_rad(T.yaw))], "yaw": T.yaw + 180.0},
			"name": "the dummy (%.2f m out)" % T.dist}
	return {}


## the target -> {"ok", "point": Vector3, "words"} (words read in the hero's frame on the ready pose F, the opponent's O)
static func target_point(t: Variant, F: Dictionary, O: Dictionary) -> Dictionary:
	if t is Array and (t as Array).size() == 3 and (t as Array).all(func(v): return v is float or v is int):
		var p := Vector3(float(t[0]), float(t[1]), float(t[2]))
		return {"ok": true, "point": p, "words": BodyFrame.describe(p, F)["words"]}
	if not (t is String):
		return {"ok": false, "error": "target: N007 words or [x, y, z] m"}
	var text := String(t).strip_edges()
	var r := BodyFrame.place(text, F, O)
	if not r["ok"]:
		var r2 := BodyFrame.place("at " + text, F, O)   # "opponent's chin" = the landmark itself
		if r2["ok"]:
			r = r2
	if not r["ok"]:
		return {"ok": false, "error": "target '%s': %s" % [text, r["error"]]}
	return {"ok": true, "point": r["point"], "words": text}


# ------------------------------------------------------------------------------------------------ the strike end
## the end's point on B: fist = the knuckle face, ball = the ball of the foot, instep = the foot's middle, tip = the weapon tip
static func end_point(B: Body, end: Dictionary) -> Vector3:
	var sd: String = end["sd"]
	match String(end["kind"]):
		"fist":
			var c: Array = B.cap("hand" + sd)
			var ax: Vector3 = ((c[1] as Vector3) - (c[0] as Vector3)).normalized()
			return (c[1] as Vector3) + ax * float(B.rad["hand" + sd])
		"ball":
			return B.P["ball" + sd]
		"instep":
			return ((B.P["foot" + sd] as Vector3) + (B.P["ball" + sd] as Vector3)) * 0.5
		"tip":
			return B.wep_point(B.wep_len) if B.wep_on else (B.E["hand" + sd] as Vector3)
		"thing":
			return BodyAssert.point(end["thing"], B, Transform3D.IDENTITY)
	return Vector3.ZERO


static func end_words(end: Dictionary) -> String:
	match String(end["kind"]):
		"fist":
			return "%s fist" % _word(end["sd"])
		"ball":
			return "ball of the %s foot" % _word(end["sd"])
		"instep":
			return "%s instep" % _word(end["sd"])
		"tip":
			return "weapon tip"
	return String(end.get("name", "end"))


## the limb's pole point (where the elbow / knee points), in the hero's space; fwd / left: toward the target, flat
static func pole(B: Body, kind: String, limb_tip: String, target: Vector3) -> Vector3:
	var sd := limb_tip.right(2)
	var root: String = B.parent[B.parent[limb_tip]]
	var R: Vector3 = B.P[root]
	var fwd := Vector3(target.x - R.x, 0.0, target.z - R.z)
	fwd = fwd.normalized() if fwd.length() > 1e-6 else Vector3(0, 0, 1)
	var left := Vector3.UP.cross(fwd)
	var out := left * (1.0 if sd == "_l" else -1.0)   # away from the body's middle, on the limb's side
	match kind:
		"out":
			return R + out * 0.6 + Vector3.UP * 0.05 - fwd * 0.1
		"under":
			return R + fwd * 0.25 + Vector3.DOWN * 0.5
		"knee_up":
			return R + Vector3.UP * 0.6 + fwd * 0.5
		"knee_fwd":   # a close target: knee_up flexed the hip to its 120 deg limit and the ball stopped 15 cm short (measured)
			return R + fwd * 0.8 + Vector3.UP * 0.15
		"knee_side":   # up and out: the hip's side 45 / twist 40 deg limits stop a knee pointed square to the side (measured: 31 cm short at a 80 deg turn)
			return R + out * 0.3 + Vector3.UP * 0.6 + fwd * 0.2
	return R + Vector3.DOWN * 0.6 + out * 0.25   # "down": the elbow under the arm


## the poles tried after the kind's own when it misses by more than 5 mm (a limit clamped the limb on that side)
const POLE_FALLBACK := {"hand": ["down", "out", "under"], "foot": ["knee_up", "knee_fwd", "knee_side"]}


## put the END on the target with the kind's pole; missing, the other poles of the limb too: the best is kept. Returns the miss (m)
static func reach_end(B: Body, limb_tip: String, end: Dictionary, target: Vector3, pole_kind: String) -> float:
	var keep := B.state()
	var best := _reach_end(B, limb_tip, end, target, pole_kind)
	if best <= 0.005:
		return best
	var best_st := B.state()
	for pk in POLE_FALLBACK["hand" if limb_tip.begins_with("hand") else "foot"]:
		if pk == pole_kind:
			continue
		B.set_state(keep)
		B.fk()
		var mi := _reach_end(B, limb_tip, end, target, pk)
		if mi < best - 1e-4:
			best = mi
			best_st = B.state()
	B.set_state(best_st)
	B.fk()
	return best


static func _reach_end(B: Body, limb_tip: String, end: Dictionary, target: Vector3, pole_kind: String) -> float:
	var best := INF
	var keep := {}
	for it in 10:
		var e := end_point(B, end)
		var miss := e.distance_to(target)
		if miss < best - 1e-7:
			best = miss
			keep = B.state()
		if miss < 1e-4:
			break
		var w: Vector3 = (B.P[limb_tip] as Vector3) + (target - e)
		LimbIK.solve(B, limb_tip, w, pole(B, pole_kind, limb_tip, target))
		B.fk()
		if B.wep_on and B.grip:
			B.apply_grip()
	var last := end_point(B, end).distance_to(target)
	if last > best + 1e-7 and not keep.is_empty():
		B.set_state(keep)
		B.fk()
		return best
	return last


# ------------------------------------------------------------------------------------------------ the blocking
## turn the trunk by deg about the vertical (+ = toward his left): 0.6 at the pelvis, the rest over the three spine joints
static func turn(B: Body, deg: float) -> void:
	B.turn_world("pelvis", Quaternion(Vector3.UP, deg_to_rad(deg * 0.6)))
	var each := clampf(deg * 0.4 / 3.0, -17.0, 17.0)
	for j in ["spine_01", "spine_02", "spine_03"]:
		var v: Vector3 = B.ang[j]
		B.set_ang(j, Vector3(v.x, v.y, v.z + each))
	B.fk()


## a foot on its spot flat; a leg that cannot reach it flat pivots on the ball, the heel up (a cross's rear foot: flat, the
## toe base stayed 2.9 cm up as the hip turned forward, measured). Returns the miss (m)
static func plant_any(B: Body, sd: String, at: Vector3, head: float) -> float:
	var keep := B.state()
	var mi := B.plant(sd, at, head, true)
	if mi <= 0.005:
		return mi
	var flat_st := B.state()
	var m2 := B.plant(sd, at, head, false)
	if m2 < mi:
		return m2
	B.set_state(flat_st)
	B.fk()
	return mi


## the feet put back on their spots {sd: [ball, heading rad]} (flat), then the body grounded and planted again
static func plant_feet(B: Body, spots: Dictionary, which: Array) -> float:
	for sd in which:
		plant_any(B, sd, spots[sd][0], spots[sd][1])
	B.ground()
	var worst := 0.0
	for sd in which:
		worst = maxf(worst, plant_any(B, sd, spots[sd][0], spots[sd][1]))
	# a leg straight and still off its spot: the hips sink (the knees bend) by the miss, up to 4 times (a cross's turned
	# hips took the rear leg straight with its ball 2.1 cm up, the thigh at its 40 deg twist limit: measured)
	for it in 4:
		if worst <= 0.005:
			break
		var up := 0.0   # only a ball left ABOVE its spot is helped by sinking; a miss along the floor is not
		for sd in which:
			up = maxf(up, (B.P["ball" + sd] as Vector3).y - (spots[sd][0] as Vector3).y)
		if up < 0.6 * worst:
			break
		B.offset.y -= minf(up, 0.03)
		B.fk()
		worst = 0.0
		for sd in which:
			worst = maxf(worst, plant_any(B, sd, spots[sd][0], spots[sd][1]))
	return worst


## the hips moved over the feet until the COM is BAL_IN inside (the BALANCE rule's advice; TextBlocking's op), the feet that
## stand re-planted. Returns the margin (m) after
static func over_feet(B: Body, spots: Dictionary, stand: Array, want := BAL_IN) -> float:
	var r := Balance.read(B)
	for it in 6:
		r = Balance.read(B)
		var poly: PackedVector2Array = r["poly"]
		if float(r["margin"]) >= want or poly.size() == 0:
			break
		var com: Vector3 = r["com"]
		var q := Vector2(com.x, com.z)
		var to := TextBlocking._onto(poly, q) - q
		if float(r["margin"]) >= 0.0:   # inside but under BAL_IN: toward the polygon's middle
			var c := Vector2.ZERO
			for v in poly:
				c += v
			to = (c / poly.size() - q)
		var d: Vector2 = to.normalized() * minf(to.length() + want, 0.3) if to.length() > 1e-6 else Vector2.ZERO
		if d.length() < 1e-5:
			break
		B.offset += Vector3(d.x, 0.0, d.y)
		B.fk()
		for sd in stand:
			plant_any(B, sd, spots[sd][0], spots[sd][1])
	return float(Balance.read(B)["margin"])


## the fighting stance: lead foot forward, trunk bladed, knees soft, fists up at the chin
static func stance(B: Body, lead: String, target: Vector3) -> Dictionary:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var sg := 1.0 if lead == "_l" else -1.0
	var y0: float = (B.p0["ball_l"] as Vector3).y
	var spots := {lead: [Vector3(sg * float(STANCE["lead_x"]), y0, float(STANCE["lead_z"])), -sg * float(STANCE["lead_head"])],
		_other(lead): [Vector3(-sg * float(STANCE["rear_x"]), y0, float(STANCE["rear_z"])), -sg * float(STANCE["rear_head"])]}
	B.offset += Vector3(0.0, -0.05, 0.06)
	B.fk()
	turn(B, -sg * BLADE)
	plant_feet(B, spots, ["_l", "_r"])
	over_feet(B, spots, ["_l", "_r"])
	guard(B, lead, target)
	return spots


## the fists at the chin: the lead 28 cm out, the rear 12 cm, elbows down (LimbIK.solve, wrist targets)
static func guard(B: Body, lead: String, target: Vector3) -> void:
	var chin := SayIt.landmark(B, "chin", "", "_r")
	var fwd := Vector3(target.x - chin.x, 0.0, target.z - chin.z)
	fwd = fwd.normalized() if fwd.length() > 1e-6 else Vector3(0, 0, 1)
	var left := Vector3.UP.cross(fwd)
	var sg := 1.0 if lead == "_l" else -1.0
	var rear := _other(lead)
	var aims := {lead: chin + fwd * 0.28 + left * (sg * 0.05) + Vector3.DOWN * 0.05,
		rear: chin + fwd * 0.12 + left * (-sg * 0.10) + Vector3.DOWN * 0.04}
	for sd in [lead, rear]:
		var s2 := 1.0 if sd == "_l" else -1.0
		LimbIK.solve(B, "hand" + sd, aims[sd], (aims[sd] as Vector3) + Vector3.DOWN * 0.5 + left * (s2 * 0.15))
		B.fk()
		B.hand_shape(sd.right(1), "fist")
	B.fk()


static func _card(name: String, B: Body, move: float, hold: float) -> Dictionary:
	return {"name": name, "pose": B.to_dict(), "move": move, "hold": hold}


## fists and kicks: READY, ANTICIPATION, STRIKE, RECOVERY from the stance (step 1 above)
static func block_body(P: Dictionary, target: Vector3, props: Dictionary) -> Dictionary:
	var K: Dictionary = KINDS[P["kind"]]
	var sd := _sd(P["side"])
	var lead := sd if bool(K["lead"]) else _other(sd)
	var limb := String(K["limb"]) + sd
	var B := _body(props)
	var spots := stance(B, lead, target)
	var g0 := B.state()
	var cards := []
	var label := String(P["kind"])
	cards.append(_card(label + " ready", B, -1.0, 0.0))
	var sgn := 1.0 if sd == "_r" else -1.0   # the striking side forward = the chest turns toward the other side
	var kick := String(K["limb"]) == "foot"
	var support := [_other(sd)] if kick else ["_l", "_r"]
	# anticipation: the trunk loaded away from the strike (a fist), the knee chambered (a kick)
	if not kick:
		turn(B, sgn * float(K["load"]))
		plant_feet(B, spots, ["_l", "_r"])
		guard(B, lead, target)
	else:
		turn(B, sgn * float(K["turn"]) * (0.2 if P["kind"] == "front kick" else 0.5))
		plant_feet(B, spots, support)
		var H: Vector3 = B.P["thigh" + sd]
		var fwd := Vector3(target.x - H.x, 0.0, target.z - H.z).normalized()
		var ch := H + fwd * 0.30 + Vector3.DOWN * 0.38 + Vector3.UP * (0.15 if P["kind"] == "roundhouse" else 0.0)
		LimbIK.solve(B, "foot" + sd, ch, pole(B, String(K["pole"]), "foot" + sd, target))
		B.fk()
		over_feet(B, spots, support)
		guard(B, lead, target)
	cards.append(_card(label + (" chamber" if kick else " anticipation"), B, 0.1, 0.0))
	# strike
	B.set_state(g0)
	B.fk()
	turn(B, sgn * float(K["turn"]))
	# the foot behind the turn pivots on its ball with the pelvis's share of it (a cross's rear foot, a roundhouse's support):
	# with the heading held, the thigh's 40 deg twist limit left a cross's rear toe base 3.9 cm up (measured)
	var sp := spots.duplicate(true)
	var piv: String = support[0] if kick else ("_r" if sgn > 0.0 else "_l")
	if P["kind"] != "front kick":
		sp[piv][1] = float(sp[piv][1]) + deg_to_rad(sgn * float(K["turn"]) * 0.6)
	plant_feet(B, sp, support)
	if kick:
		over_feet(B, sp, support)
	cards.append(_card(label + " strike", B, 0.1, 0.0))
	var after := [3]
	if kick:
		# re-chamber (the knee back up, the hips still over the support), then LAND (the foot down on its spot, the hips where
		# they were): from the strike straight to the guard, NATURAL's lead let the hips go home while the foot was still up
		# and the COM went 7 cm past the support foot (measured)
		var ch_pose: Dictionary = cards[1]["pose"]
		cards.append({"name": label + " re-chamber", "pose": ch_pose.duplicate(true), "move": 0.1, "hold": 0.0})
		B.set_state(g0)
		B.fk()
		var hips: Vector3 = Moves._flat(ch_pose)["offset"]
		B.offset = Vector3(hips.x, B.offset.y, hips.z)
		B.fk()
		plant_feet(B, spots, ["_l", "_r"])
		cards.append(_card(label + " land", B, 0.1, 0.0))
		after = [3, 4, 5]
	B.set_state(g0)
	B.fk()
	cards.append(_card(label + " recovery", B, 0.3, 0.0))
	var end := {"kind": String(K["end"]), "sd": sd}
	return {"ok": true, "cards": cards, "strike": 2, "antic": [1], "after": after, "limb": limb, "pole": String(K["pole"]),
		"end": end, "lead": lead, "spots": spots, "support": support, "from": "generated: a fighting stance (%s lead), %s %s" % [_word(lead), _word(sd), label],
		"strike_move": KICK_STRIKE if kick else FIST_STRIKE, "kick": kick}


## a weapon move: ROADMAP 22's text-to-blocking, its roles kept (ready, windup, strike, follow-through, recovery)
static func block_weapon(P: Dictionary, props: Dictionary) -> Dictionary:
	var phrase := "%s %s %s" % [P["weapon"], P["kind"] if not KINDS.has(P["kind"]) else "thrust", P["side"]]
	var B := _body(props)
	var r := TextBlocking.build(phrase, B)
	if not r["ok"]:
		return {"ok": false, "error": "text-to-blocking ('%s'): %s" % [phrase, r["error"]]}
	var S: Scene = r["scene"]
	var roles: Array = r["roles"]
	var s: int = r["strike_card"]
	var cards := S.cards.duplicate(true)
	B.from_dict(cards[s]["pose"])
	var h := B.wep_hand if B.wep_hand != "" else "hand_r"
	var antic := []
	var after := []
	for i in roles.size():
		if i > 0 and i < s:
			antic.append(i)
		elif i > s:
			after.append(i)
	# the lead foot: the one further forward on the ready card; spots = where the feet stand on it
	B.from_dict(cards[0]["pose"])
	var spots := {}
	B.ground()
	for sd in ["_l", "_r"]:
		# on the floor: the source's ready card stood its left toe base 6 cm up (a weight shift), so the spot was in the
		# air, no card's foot read as down and playback never pinned it (9 cm of slide: measured)
		var at: Vector3 = B.P["ball" + sd]
		spots[sd] = [Vector3(at.x, (B.p0["ball" + sd] as Vector3).y, at.z), B.foot_heading(sd)]
	var lead := "_l" if (B.P["ball_l"] as Vector3).z >= (B.P["ball_r"] as Vector3).z else "_r"
	return {"ok": true, "cards": cards, "strike": s, "antic": antic, "after": after, "limb": h, "pole": "down",
		"end": {"kind": "tip", "sd": h.right(2)}, "lead": lead, "spots": spots, "support": ["_l", "_r"],
		"from": "text-to-blocking '%s': %s (%s)" % [phrase, r["source"]["scene"], String(r["status"]).left(160)], "strike_move": S.move_time(s), "kick": false}


# ------------------------------------------------------------------------------------------------ timing
## the clip's times from the spec: the strike card arrives at contact_t. Returns notes on what could not be kept
static func set_times(C: Scene, bl: Dictionary, P: Dictionary, strike_move: float) -> Array:
	var notes := []
	var s: int = bl["strike"]
	var antic: Array = bl["antic"]
	var after: Array = bl["after"]
	var fps := float(C.fps)
	var a: float = P["anticipation"]
	if antic.is_empty():
		a = 0.0
	else:
		var each := a / antic.size()
		for i in antic:
			C.cards[i]["move"] = snappedf(maxf(0.04, each * 0.75), 0.001)
			C.cards[i]["hold"] = snappedf(each * 0.25, 0.001)
	C.cards[s]["move"] = snappedf(strike_move, 0.001)
	var sh := minf(STRIKE_HOLD_F / fps, float(P["recovery"]) * 0.5)
	C.cards[s]["hold"] = snappedf(sh, 0.001)
	var rest := maxf(float(P["recovery"]) - sh, 0.04 * after.size())
	for k in after.size():
		C.cards[after[k]]["move"] = snappedf(maxf(0.04, rest / after.size()), 0.001)
		C.cards[after[k]]["hold"] = 0.0
	var antic_t := 0.0
	for i in antic:
		antic_t += float(C.cards[i]["move"]) + float(C.cards[i]["hold"])
	var h0: float = float(P["contact_t"]) - antic_t - float(C.cards[s]["move"])
	if h0 < -1e-6:
		notes.append("contact_t %.3f s is shorter than the anticipation %.3f s + the strike move %.3f s: the contact comes at %.3f s" % [P["contact_t"], antic_t, C.cards[s]["move"], antic_t + float(C.cards[s]["move"])])
	C.cards[0]["hold"] = snappedf(maxf(0.0, h0), 0.0001)
	C.cards[0]["move"] = -1.0
	# a BREAKDOWN card (a planted-foot repair) takes its share "bd" of the next card's move: the two arrive when one did
	for i in range(C.cards.size() - 2, 0, -1):
		if C.cards[i].has("bd"):
			var full := float(C.cards[i + 1]["move"])
			C.cards[i]["move"] = snappedf(full * float(C.cards[i]["bd"]), 0.001)
			C.cards[i]["hold"] = 0.0
			C.cards[i + 1]["move"] = snappedf(full - float(C.cards[i]["move"]), 0.001)
	return notes


## a BREAKDOWN at time t inside card i's move: the pose as it plays there, the standing feet put on their spots, as a card
## that takes its share of the move (set_times keeps the share). The card indices after it shift by one. Returns i or -1
static func breakdown(C: Scene, bl: Dictionary, t: float, stand: Array, Bp: Body, Bs: Body) -> int:
	var i := C.span(t)
	if i <= 0 or C.cards[i].has("bd") or (i > 0 and C.cards[i - 1].has("bd")):
		return -1
	var ts := C.times()
	var mv := float(C.cards[i]["move"])
	var frac := clampf((t - float(ts[i][0])) / maxf(1e-6, mv), 0.2, 0.8)
	C.apply_true(Bp, t)
	Bs.from_dict(Bp.to_dict())
	Bs.fk()
	var sp := {}
	for sd in stand:
		sp[sd] = [bl["spots"][sd][0], bl["spots"][sd][1]]
	plant_feet(Bs, sp, stand)
	var card := {"name": "%s breakdown" % C.cards[i]["name"], "pose": Bs.to_dict(), "move": snappedf(mv * frac, 0.001), "hold": 0.0, "bd": frac}
	C.cards[i]["move"] = snappedf(mv - float(card["move"]), 0.001)
	C.cards.insert(i, card)
	bl["strike"] = int(bl["strike"]) + (1 if int(bl["strike"]) >= i else 0)
	for key in ["antic", "after"]:
		var a: Array = bl[key]
		for k in a.size():
			if int(a[k]) >= i:
				a[k] = int(a[k]) + 1
	return i


# ------------------------------------------------------------------------------------------------ checking
## the clip with the opponent wired in as fighter 2 (a 1-card scene of his pose), for the N002 lines
static func with_opp(C: Scene, O: Dictionary) -> Scene:
	if O.is_empty() or not C.actors.is_empty():
		return C
	var D := Scene.new()
	D.cards = [{"name": "stand", "pose": (O["B"] as Body).to_dict(), "move": -1.0, "hold": 0.0}]
	C.actors = [{"name": "opponent", "xf": O["file_xf"], "scene": D}]
	return C


## every line on the clip + the target line -> {"rows": [{"line", "pass", "value", "unit", "miss", ...}], "raw": BodyAssert results}
static func evaluate(C: Scene, bl: Dictionary, P: Dictionary, target: Vector3, lines: Array, Bp: Body) -> Dictionary:
	var rows := []
	# the TARGET line: the end within tolerance at contact_t +-1 frame (the nearest frame in the window)
	var fps := float(C.fps)
	var tc := float(C.times()[int(bl["strike"])][1])
	var c := roundi(float(P["contact_t"]) * fps)
	var best := INF
	var at := -1
	for f in range(c - 1, c + 2):
		if f < 0 or f / fps > C.length() + 1e-6:
			continue
		C.apply_true(Bp, f / fps)
		var d := end_point(Bp, bl["end"]).distance_to(target)
		if d < best:
			best = d
			at = f
	var tl := "%s within %s cm of the target at %s s +-1 f" % [end_words(bl["end"]), str(P["tolerance_cm"]), str(P["contact_t"])]
	rows.append({"line": tl, "pass": best * 100.0 <= float(P["tolerance_cm"]) + 1e-9, "value": snappedf(best * 100.0, 0.01), "unit": "cm",
		"frame": at, "kind": "target", "strike_arrives_s": snappedf(tc, 0.0001)})
	var r := BodyAssert.run(C, Bp, lines.map(func(l): return opp_line(String(l))))
	var res: Array = r["results"]
	for i in res.size():
		var x: Dictionary = res[i]
		var row := {"line": lines[i], "pass": bool(x.get("pass", false))}
		if not bool(x.get("ok", false)):
			row["error"] = x.get("error", "")
			row["kind"] = "unread"
		else:
			row["kind"] = x["kind"]
			row["value"] = x["worst"].get("value", x["worst"].get("miss"))
			row["unit"] = x["worst"]["unit"]
			if x["kind"] == "planted":
				row["value"] = {"lift_cm": x["worst"]["lift_cm"], "slide_cm": x["worst"]["slide_cm"]}
			if x.has("miss"):
				row["miss"] = x["miss"]["value"]
				row["miss_t"] = x["miss"]["t"]
			row["say"] = x["say"]
		rows.append(row)
	return {"rows": rows, "raw": res}


# ------------------------------------------------------------------------------------------------ solving + repairs
## the strike card solved on the body AS IT PLAYS at the strike card's arrival (step 4); writes the limb's angles back
static func solve_played(C: Scene, bl: Dictionary, target: Vector3, Bp: Body, Bs: Body) -> float:
	var s: int = bl["strike"]
	var limb: String = bl["limb"]
	var chain := LimbIK.chain(Bs, limb)
	var miss := INF
	for it in 4:
		var t := float(C.times()[s][1])
		C.apply_true(Bp, t)
		miss = end_point(Bp, bl["end"]).distance_to(target)
		if miss < 0.002:
			break
		reach_end(Bp, limb, bl["end"], target, bl["pole"])
		Bs.from_dict(C.cards[s]["pose"])
		for j in chain:
			Bs.ang[j] = Bp.ang[j]
		Bs.fk()
		if Bs.wep_on and Bs.grip:
			Bs.apply_grip()
		C.cards[s]["pose"] = Bs.to_dict()
	C.apply_true(Bp, float(C.times()[s][1]))
	return end_point(Bp, bl["end"]).distance_to(target)


## the strike card's raw pose reached (reach_end) on Bs; lean (spine_02 bend) inside N013's balance interval when short.
## Returns {"miss", "lean": deg added, "lean_hi": the balance-safe top}
static func reach_card(C: Scene, bl: Dictionary, target: Vector3, Bs: Body) -> Dictionary:
	var s: int = bl["strike"]
	Bs.from_dict(C.cards[s]["pose"])
	Bs.fk()
	var miss := reach_end(Bs, bl["limb"], bl["end"], target, bl["pole"])
	if bool(bl["kick"]):
		# the leg out front moves the COM off the one foot; the hips back over it move the hip toward the target: alternate
		var sup: String = bl["support"][0]
		for k in 3:
			var fs := Bs.foot_state(sup)
			over_feet(Bs, {sup: [fs[0], fs[1]]}, [sup])
			miss = reach_end(Bs, bl["limb"], bl["end"], target, bl["pole"])
	var out := {"miss": miss, "lean": 0.0, "lean_hi": null, "turn": 0.0}
	if miss > 0.002 and String(bl["end"]["kind"]) == "tip":
		# a weapon's tip: the arm alone met its limits (a two-handed bat 8.8 cm short: measured); the trunk turns it on,
		# the feet re-planted, the arm re-reached: the best of a few turns is kept
		var k0 := Bs.state()
		var bt := 0.0
		var bst := k0
		for a in [-30.0, -20.0, -10.0, 10.0, 20.0, 30.0]:
			Bs.set_state(k0)
			Bs.fk()
			turn(Bs, a)
			var pm := plant_feet(Bs, bl["spots"], bl["support"])   # a turn the legs cannot stand on is not kept
			var mi := reach_end(Bs, bl["limb"], bl["end"], target, bl["pole"])
			if mi < miss - 1e-4 and pm <= 0.005 and float(Balance.read(Bs)["margin"]) >= 0.0:
				miss = mi
				bt = a
				bst = Bs.state()
		Bs.set_state(bst)
		Bs.fk()
		out["miss"] = miss
		out["turn"] = bt
	if miss <= 0.002:
		C.cards[s]["pose"] = Bs.to_dict()
		return out
	# N013: the spine_02 bends that keep the balance, on this pose
	var host := _Host.new()
	host.B = Bs
	var rs := RangeSweep.run(host, {"joint": "spine_02", "axis": "bend", "conditions": ["balance"], "step": 1.0})
	host.free()
	var now: float = (Bs.ang["spine_02"] as Vector3).x
	var hi := now
	for iv in rs.get("intervals", []):
		if float(iv["from"]) <= now + 1e-6 and float(iv["to"]) >= now - 1e-6:
			hi = float(iv["to"])
	out["lean_hi"] = snappedf(hi, 0.01)
	var keep := Bs.state()
	var best := miss
	var best_st := keep
	var best_lean := 0.0
	var n := 8
	for k in range(1, n + 1):
		var lean := now + (hi - now) * k / n
		Bs.set_state(keep)
		Bs.fk()
		var v: Vector3 = Bs.ang["spine_02"]
		Bs.set_ang("spine_02", Vector3(lean, v.y, v.z))
		Bs.fk()
		var mi := reach_end(Bs, bl["limb"], bl["end"], target, bl["pole"])
		var bal := Balance.read(Bs)
		if (bal["down"] as Array).size() > 0 and float(bal["margin"]) >= 0.0 and mi < best - 1e-5:
			best = mi
			best_st = Bs.state()
			best_lean = lean - now
	Bs.set_state(best_st)
	Bs.fk()
	C.cards[s]["pose"] = Bs.to_dict()
	out["miss"] = best
	out["lean"] = snappedf(best_lean, 0.01)
	return out


class _Host extends Node:
	var B: Body
	var S := Scene.new()
	var playhead := 0.0


## a step of the lead foot for the shortfall (the cards from the strike to the last before the recovery stand on it; the hips
## follow by HIPS_PER_STEP; the recovery steps back). Returns the step length (m) or 0
static func step_for(C: Scene, bl: Dictionary, target: Vector3, short: float, Bs: Body) -> float:
	var lead: String = bl["lead"]
	var s: int = bl["strike"]
	# the step lands on the ANTICIPATION card (a step-in, then the strike from both feet): on the 4-frame strike move the
	# foot was in the air at the hit and the COM 20 cm past the one foot left down (measured)
	var at := int(bl["antic"][0]) if not (bl["antic"] as Array).is_empty() else s
	var spots: Dictionary = bl["spots"]
	var base: Vector3 = spots[lead][0]
	var dir := Vector3(target.x - base.x, 0.0, target.z - base.z).normalized()
	# the shoulder travels with the hips, HIPS_PER_STEP of the step: the step is the shortfall over that (a 16 cm step
	# for a 14 cm shortfall closed 7 of it: measured)
	var d := clampf(short / TextBlocking.HIPS_PER_STEP + 0.02, 0.0, STEP_MAX)
	if d < 0.01:
		return 0.0
	var new_spot: Vector3 = base + dir * d
	var stand: Array = ["_l", "_r"] if not bool(bl["kick"]) else bl["support"]
	var last := C.cards.size() - 1
	# the fighter STAYS in the new stance through the recovery: stepping back on the recovery move had the foot in the air
	# with the COM 23 cm past the rear foot (measured)
	for i in range(at, last + 1):
		Bs.from_dict(C.cards[i]["pose"])
		Bs.fk()
		Bs.offset += dir * d * TextBlocking.HIPS_PER_STEP
		Bs.fk()
		var sp := spots.duplicate(true)
		sp[lead] = [new_spot, spots[lead][1]]
		for sd in stand:
			plant_any(Bs, sd, sp[sd][0], sp[sd][1])
		C.cards[i]["pose"] = Bs.to_dict()
	C.cards[at]["steps"] = {lead: [dir.x * d, 0.0, dir.z * d]}
	spots[lead] = [new_spot, spots[lead][1]]   # the lead foot's spot from here on (a later re-plant keeps the step)
	return d


## a foot put back on its ready spot on every card (a "planted" line or contact); its steps taken out
static func replant(C: Scene, bl: Dictionary, sd: String, Bs: Body) -> void:
	var spots: Dictionary = bl["spots"]
	for i in C.cards.size():
		Bs.from_dict(C.cards[i]["pose"])
		Bs.fk()
		# on its spot; with the other standing foot, so the hips may sink
		var which: Array = [sd]
		var sp := {}
		for o in bl["support"]:
			if o != sd and (not bool(bl["kick"]) or i == 0 or i == C.cards.size() - 1 or (o in bl["support"])):
				which.append(o)
		for w in which:   # the spot's heading on every card: playback pins a foot with the heading of the run's first card,
			sp[w] = [spots[w][0], spots[w][1]]   # so a card's pivot never plays (a cross pivoted on its strike slid 8.7 cm: measured)
		plant_feet(Bs, sp, which)
		C.cards[i]["pose"] = Bs.to_dict()
		var st: Variant = C.cards[i].get("steps", null)
		if st is Dictionary:
			(st as Dictionary).erase(sd)
			if (st as Dictionary).is_empty():
				C.cards[i].erase("steps")


## the card nearest time t
static func card_near(C: Scene, t: float) -> int:
	var ts := C.times()
	var best := 0
	for i in C.cards.size():
		if absf(float(ts[i][1]) - t) < absf(float(ts[best][1]) - t):
			best = i
	return best


# ------------------------------------------------------------------------------------------------ the plan
## THE PLAN on its own Scene and Body: -> the result (see the head); "scene" = the clip (a Scene), "cards" its cards
static func plan(m: Node, spec: Variant) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var P := read(spec)
	if not P["ok"]:
		return P
	var O := opponent(m)
	var props: Dictionary = m.S.body
	var bl: Dictionary
	var Bs := _body(props)
	var Bp := _body(props)
	# a first target guess (the stance needs a direction): the words on the plain standing body
	Bs.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	Bs.ground()
	var OF: Dictionary = BodyFrame.fighter(O["B"], O["xf"]) if not O.is_empty() else {}
	var tg := target_point(P["target"], BodyFrame.fighter(Bs), OF)
	if not tg["ok"]:
		return tg
	var target: Vector3 = tg["point"]
	if String(P["weapon"]) != "":
		bl = block_weapon(P, props)
	else:
		bl = block_body(P, target, props)
	if not bl["ok"]:
		return bl
	# the target again, in the frame of the ready pose (the hero's own landmarks are where HE stands)
	Bs.from_dict(bl["cards"][0]["pose"])
	Bs.fk()
	tg = target_point(P["target"], BodyFrame.fighter(Bs), OF)
	target = tg["point"]
	if P["end"] != "":
		var th := BodyAssert.thing(BodyAssert.norm(String(P["end"])))
		if not th["ok"]:
			return {"ok": false, "error": "end: " + String(th["error"])}
		bl["end"] = {"kind": "thing", "thing": th, "sd": String(th.get("side", "_r")) if String(th.get("side", "")) != "" else "_r", "name": P["end"]}
	# the clip, with the live scene's settings
	var C := Scene.new()
	for k in ["natural", "on_floor", "floor_body", "pin", "fps", "body"]:
		C.set(k, m.S.get(k))
	C.name = "spec_" + TextBlocking.slug(String(P["name"]))
	C.cards = bl["cards"]
	var strike_move: float = bl["strike_move"]
	var notes := set_times(C, bl, P, strike_move)
	# the contacts: the planted feet as lines, and on their spots on every card
	var lines := []
	for sd in P["planted"]:
		lines.append("%s foot planted all clip" % _word(sd))
	lines += P["assertions"]
	for sd in P["planted"]:
		if bool(bl["kick"]) and sd == bl["end"]["sd"]:
			continue   # the kicking foot cannot stay planted: its line fails and says so
		replant(C, bl, sd, Bs)
	var repairs := []
	var rc := reach_card(C, bl, target, Bs)
	if float(rc["turn"]) != 0.0:
		repairs.append("trunk turned %+.0f deg on the strike card to bring the weapon's tip on (the feet re-planted)" % rc["turn"])
	if float(rc["lean"]) != 0.0:
		repairs.append("trunk leaned %.1f deg toward the target (spine_02; N013 balance range up to %s deg)" % [rc["lean"], rc["lean_hi"]])
	var stepped := 0.0
	var planted: Array = P["planted"]
	with_opp(C, O)
	var ev: Dictionary
	var stage := {"blocking_ms": 0, "rounds": 0}
	stage["blocking_ms"] = Time.get_ticks_msec() - t0
	var timed_out := false
	var tries := {}
	var t_loop := Time.get_ticks_msec()
	for round_i in ROUNDS + 1:
		stage["rounds"] = round_i + 1
		if Time.get_ticks_msec() - t_loop > TIME_CAP_MS and round_i > 0:   # the repairs' time (text-to-blocking's own is not)
			timed_out = true
			break
		solve_played(C, bl, target, Bp, Bs)
		ev = evaluate(C, bl, P, target, lines, Bp)
		var fails: Array = (ev["rows"] as Array).filter(func(r): return not r["pass"])
		if fails.is_empty() or round_i == ROUNDS:
			break
		var did := false
		for f in fails:
			# a repair already tried twice on this line without passing it is not tried again (it would repeat to ROUNDS)
			var key := String(f["line"])
			tries[key] = int(tries.get(key, 0)) + 1
			if int(tries[key]) > 2:
				continue
			match String(f.get("kind", "")):
				"target":
					var miss := float(f["value"]) / 100.0
					var lead: String = bl["lead"]
					if stepped == 0.0 and not lead in planted and miss > float(P["tolerance_cm"]) / 100.0:
						var d := step_for(C, bl, target, miss, Bs)
						if d > 0.0:
							stepped = d
							repairs.append("the %s foot steps %.0f cm toward the target on '%s' (the hips %.0f cm with it), and stays there" % [_word(lead), d * 100.0, C.cards[bl["antic"][0] if not (bl["antic"] as Array).is_empty() else bl["strike"]]["name"], d * TextBlocking.HIPS_PER_STEP * 100.0])
							var r2 := reach_card(C, bl, target, Bs)
							if float(r2["lean"]) != 0.0:
								repairs.append("trunk leaned %.1f deg after the step" % r2["lean"])
							did = true
				"planted":
					var sd := "_l" if String(f["line"]).to_lower().contains("left") else "_r"
					if not (bool(bl["kick"]) and sd == bl["end"]["sd"]):
						var tw := float(f.get("miss_t", -1.0))
						var stand: Array = []
						for o in ["_l", "_r"]:
							if o in planted and not (bool(bl["kick"]) and o == bl["end"]["sd"]):
								stand.append(o)
						if not sd in stand:
							stand.append(sd)
						var bi := -1
						if int(tries[key]) > 1 and C.span(tw) > 0 and int(bl.get("n_bd", 0)) < 3:
							# the cards stand on the spots already: the foot leaves them BETWEEN cards (two leg solutions
							# blended across a move): a breakdown card there, the feet planted on it
							bi = breakdown(C, bl, tw, stand, Bp, Bs)
						if bi > 0:
							bl["n_bd"] = int(bl.get("n_bd", 0)) + 1
							tries[key] = 1   # a new kind of repair on this line: it gets its own tries
							repairs.append("a breakdown card at %.3f s ('%s'): the %s foot planted between the cards" % [tw, C.cards[bi]["name"], _word(sd)])
						else:
							replant(C, bl, sd, Bs)
							repairs.append("the %s foot re-planted on its ready spot on every card" % _word(sd))
						if not sd in planted:
							planted.append(sd)
						reach_card(C, bl, target, Bs)
						did = true
				"inside":
					var k := card_near(C, float(f.get("miss_t", 0.0)))
					Bs.from_dict(C.cards[k]["pose"])
					Bs.fk()
					var stand: Array = ["_l", "_r"] if not (bool(bl["kick"]) and k > 0 and k < C.cards.size() - 1) else bl["support"]
					var sp: Dictionary = (bl["spots"] as Dictionary).duplicate(true)
					for sd in stand:   # on its ready spot (the card's own foot may stand off it)
						sp[sd] = [bl["spots"][sd][0], bl["spots"][sd][1]]
					Bs.ground()
					# the card is aimed past the bar by what the clip missed it by (+1 cm): the frames between cards and the
					# strike's re-solve on the played body move the COM again (a roundhouse card at +2.7 cm played -1.6 cm: measured)
					var short := absf(float(f["value"])) / 100.0 if f.get("value") is float and float(f["value"]) < 0.0 else 0.0
					var want := minf(0.06, BAL_IN + short * float(tries[key]) + 0.01)
					var mg := over_feet(Bs, sp, stand, want)
					C.cards[k]["pose"] = Bs.to_dict()
					repairs.append("hips moved over the feet on '%s' (COM margin now %.1f cm)" % [C.cards[k]["name"], mg * 100.0])
					if k == int(bl["strike"]):
						reach_card(C, bl, target, Bs)
					did = true
				"speed":
					var s: int = bl["strike"]
					var line := String(f["line"]).to_lower()
					var mv := float(C.cards[s]["move"])
					var slower := line.contains("under") or line.contains("below") or line.contains("at most") or line.contains("slower")
					var v := float(f["value"]) if f.get("value") != null else 0.0
					var x := float(f["miss"]) if f.get("miss") != null else 0.0
					var want := v - x if slower else v + x   # the line's bar (miss = v - X under, X - v over)
					# speed ~ 1 / move time: scale the move by v / X, 8 % past it so the bar is cleared, not grazed
					var nm := clampf(mv * (v / maxf(want, 0.01)) * (1.08 if slower else 0.92), STRIKE_MIN, STRIKE_MAX) if want > 0.0 else mv
					if absf(nm - mv) > 1e-4:
						strike_move = nm
						notes += set_times(C, bl, P, strike_move)
						repairs.append("strike move retimed %.3f -> %.3f s for '%s' (contact kept at %.3f s by the ready hold)" % [mv, nm, f["line"], P["contact_t"]])
						did = true
				"angle":
					var q := BodyAssert.parse(opp_line(String(f["line"])))
					if q["ok"]:
						var fr := BodyAssert.frames_of(q["window"], float(C.fps), int(floor(C.length() * C.fps + 1e-6)) + 1, [])
						var ts := C.times()
						var ai := int(WhatIf.AXI[q["axis"]])
						for i in C.cards.size():
							var ti := float(ts[i][1]) * C.fps
							if ti < float(fr[0]) - 1.0 or ti > float(fr[1]) + 1.0:
								continue
							Bs.from_dict(C.cards[i]["pose"])
							Bs.fk()
							var v3: Vector3 = Bs.ang[q["joint"]]
							var lo := float(q.get("lo", -INF)) if q["op"] == "between" else (float(q["x"]) if q["op"] == "gt" else -INF)
							var hi := float(q.get("hi", INF)) if q["op"] == "between" else (float(q["x"]) if q["op"] == "lt" else INF)
							var pad := 0.5
							v3[ai] = clampf(v3[ai], lo + pad, hi - pad)
							Bs.set_ang(q["joint"], v3)
							Bs.fk()
							C.cards[i]["pose"] = Bs.to_dict()
							repairs.append("%s %s clamped into the line's range on '%s'" % [q["joint"], q["axis"], C.cards[i]["name"]])
							did = true
		if not did:
			break
	# the result
	var rows: Array = ev["rows"]
	var unmet := []
	for r in rows:
		if r["pass"]:
			continue
		unmet.append(_why(r, bl, P, target, C, Bp, stepped))
	if timed_out:
		unmet.append({"line": "timeout", "why": "timeout: the repairs stopped after %d ms (TIME_CAP_MS) with lines still failing" % TIME_CAP_MS, "closest": null})
	stage["total_ms"] = Time.get_ticks_msec() - t0
	for c in C.cards:
		(c as Dictionary).erase("bd")   # set_times' breakdown share: the plan's own, not the clip's
	var ts2 := C.times()
	var cards_out := []
	for i in C.cards.size():
		cards_out.append({"n": i + 1, "name": C.cards[i]["name"], "arrive_s": snappedf(ts2[i][1], 0.001), "move_s": snappedf(C.move_time(i), 0.001),
			"hold_s": float(C.cards[i]["hold"])})
	C.actors = []   # the opponent was wired in only to read the lines
	return {"ok": unmet.is_empty(), "spec": P["name"], "cards_added": C.cards.size(), "cards": cards_out,
		"assertions": rows.map(func(r): return {"line": r["line"], "pass": r["pass"], "value": r.get("value"), "unit": r.get("unit", "")}),
		"unmet": unmet, "target": {"words": tg["words"], "point": [snappedf(target.x, 0.0001), snappedf(target.y, 0.0001), snappedf(target.z, 0.0001)],
			"opponent": O.get("name", "none")},
		"timing": {"contact_t": P["contact_t"], "strike_arrives_s": snappedf(float(ts2[int(bl["strike"])][1]), 0.0001), "strike_move_s": float(C.cards[bl["strike"]]["move"]),
			"anticipation_s": P["anticipation"], "recovery_s": P["recovery"], "length_s": snappedf(C.length(), 0.001)},
		"end": end_words(bl["end"]), "blocking_from": bl["from"], "repairs": repairs, "notes": notes, "ms": Time.get_ticks_msec() - t0, "stages": stage,
		"scene": C, "detail": rows}


## an unmet line -> {"line", "why", "closest"}
static func _why(r: Dictionary, bl: Dictionary, P: Dictionary, target: Vector3, C: Scene, Bp: Body, stepped: float) -> Dictionary:
	var k := String(r.get("kind", ""))
	if k == "target":
		var closest := float(r["value"])
		var limb: String = bl["limb"]
		var root: String = Bp.parent[Bp.parent[limb]]
		C.apply_true(Bp, float(C.times()[int(bl["strike"])][1]))
		var lead: String = bl["lead"]
		var no_step := "a step is not allowed ('%s foot planted')" % _word(lead) if lead in P["planted"] else ("after a %.0f cm step" % (stepped * 100.0) if stepped > 0.0 else "no step tried")
		var mid: String = Bp.parent[limb]
		var L: float = (Bp.P[mid] as Vector3).distance_to(Bp.P[root]) + (Bp.P[limb] as Vector3).distance_to(Bp.P[mid]) + end_point(Bp, bl["end"]).distance_to(Bp.P[limb])
		var far: float = (Bp.P[root] as Vector3).distance_to(target)
		var how := "the limb (%.2f m long) straight toward it" % L if far > 0.97 * L else "inside the limb's %.2f m length, but its joint limits stop it (a target this close needs a bend the limits refuse)" % L
		return {"line": r["line"], "why": "reach: the %s stops %.1f cm from the target (%s, from the %s %.2f m away; the trunk leaned inside the balance range; %s)" % [end_words(bl["end"]), closest, how, root.replace("_", " "), far, no_step],
			"closest": {"value": closest, "unit": "cm"}}
	if k == "unread":
		return {"line": r["line"], "why": "unread: " + String(r.get("error", "")), "closest": null}
	var why := String(r.get("say", "")).trim_prefix("FAIL  ")
	if k == "planted" and bool(bl["kick"]) and String(r["line"]).to_lower().contains(_word(bl["end"]["sd"])):
		why = "contact: the kicking foot leaves the floor, it cannot stay planted (%s)" % why
	return {"line": r["line"], "why": "%s: %s" % [k, why], "closest": {"value": r.get("miss", r.get("value")), "unit": r.get("unit", "")}}


# ------------------------------------------------------------------------------------------------ serve / CLI
## serve's `spec {spec, apply?}` -> {"ok": true, "result"} | {"ok": false, "error"} (a spec it cannot read). apply: the clip's
## cards appended to the live scene as ONE undo step (main._do); else nothing changes. result.ok = every line passed
static func serve(m: Node, p: Dictionary) -> Dictionary:
	if not p.has("spec"):
		return {"ok": false, "error": "spec needs {\"spec\": {\"kind\": \"jab\", \"side\": \"right\", \"target\": \"opponent's chin\", \"contact_t\": 0.35, \"timing\": {...}, \"contacts\": [...], \"assertions\": [...]}, \"apply\": false}"}
	var r := plan(m, p["spec"])
	if not r.has("scene"):
		return r
	var C: Scene = r["scene"]
	r.erase("scene")
	r.erase("detail")
	var ap := bool(p.get("apply", false))
	r["applied"] = ap
	if ap:
		var add: Array = C.cards.duplicate(true)
		var first: int = m.S.cards.size()
		m._do(func():
			for c in add:
				m.S.cards.append(c))
		m._rebuild_cards()
		r["first_card"] = first + 1
	return {"ok": true, "result": r}


## CLI (tools/poser_cli.gd: spec <scene.json|-> <spec.json> [--dummy D] [--out <path>]): the spec's cards appended to the scene
## (or a new one: "-"), each line printed, the scene written with --out. `cli` is poser_cli itself (its m, T, say, done, res)
static func cli(c: Object, a: Array) -> void:
	var m: Node = c.m
	var T: AgentTools = c.T
	var out := ""
	var i := a.find("--out")
	if i >= 0 and i + 1 < a.size():
		out = c.res(a[i + 1])
		a = a.slice(0, i) + a.slice(i + 2)
		var why := T.out_refused(out)
		if why != "":
			c.done({"ok": false, "error": why.replace("the output", "--out")})
			return
	var di := a.find("--dummy")
	if di >= 0 and di + 1 < a.size() and String(a[di + 1]).is_valid_float():
		m.T.place(float(a[di + 1]))
		a = a.slice(0, di) + a.slice(di + 2)
	if a.size() < 3 or not FileAccess.file_exists(c.res(a[2]) if not String(a[2]).is_absolute_path() else a[2]):
		c.done({"ok": false, "error": "spec <scene.json|-> <spec.json> [--dummy D] [--out <path>]  (N004; scripts/spec_motion.gd)"})
		return
	if a[1] == "-":
		m.S = Scene.new()
		m._rebuild_cards()
	elif not c.open_scene(a[1]):
		return
	var sp: Variant = JSON.parse_string(FileAccess.get_file_as_string(c.res(a[2]) if not String(a[2]).is_absolute_path() else a[2]))
	var sr := SpecMotion.serve(m, {"spec": sp, "apply": true})
	if not sr["ok"]:
		c.done(sr)
		return
	var r: Dictionary = sr["result"]
	for x in r["assertions"]:
		c.say("%s  %s  (%s %s)" % ["PASS" if x["pass"] else "FAIL", x["line"], str(x["value"]), x["unit"]])
	for u in r["unmet"]:
		c.say("UNMET %s: %s" % [u["line"], u["why"]])
	if out != "":
		T.write_scene(out, "poser_cli spec %s" % a[2])
		r["out"] = out
		c.say("wrote %s (%d cards)" % [out, m.S.cards.size()])
	c.done(r)
