## move_knobs.gd - MOVE KNOBS (docs/INNOVATIONS.md N025). Four numbers on a finished strike, read and set on its CONTACT
## card; Kine re-solves the limbs by IK and keeps the planted feet and the joint limits. Geometry, not style: the I6 style
## dial (style_dial.gd: heavier / tired / angry, timing and amplitude of the whole clip) is a different axis and is not used.
##
## THE KNOBS (measured on the card's pose as Scene.put lays it, the same as picking the card; all four are differences or
## lengths, so they do not depend on the floor grounding that playback adds):
##   strike_height_cm  the striking end's height above (+) / below (-) the striker's own CHIN height (N007's words: "3 cm
##                     above chin height"; the chin is SayIt.landmark, what I5 and body_frame.gd mean by it). The striking
##                     end = the weapon's tip when a weapon is in a hand, else the wrist (punch) or ankle (kick): the SAME
##                     points `measure`, `state` and body_frame.gd call hand_r / foot_r
##   reach_pct         the striking limb's root (shoulder / hip joint) to its wrist / ankle, as % of the limb's length
##                     (upper + lower segment): what_if.gd's "reach %" (100 = straight). A weapon: the arm that holds it
##   stance_cm         the horizontal distance between the two ankles. Not on a kick (one foot is the strike) and not on a
##                     card where a foot is off the floor
##   guard_cm          the guard hand's wrist above (+) / below (-) chin height. The guard hand = the hand that does not
##                     strike (on a kick: the one nearer the chin). Not with a two-hand grip (both hands hold the weapon)
##
## SETTING (one undo step). A knob asked within READ_TOL of its value is left alone, so "read, then set the same numbers"
## changes nothing. Else, on each AFFECTED card:
##   the contact card            the full change (weight 1)
##   the cards either side       FADE = 0.5 of it, applied to that card's own value (HEURISTIC: no paper says how a wind-up
##                               follows a changed contact; half keeps the path through the contact without a kink)
##   stance, every card where the moved foot stands on the SAME spot as at contact (down, its ball within SAME_SPOT)
##                               the full move, so a planted foot never slides between cards (the contact kept)
## Each change is ONE damped-least-squares solve of a limb's three joints (shoulder 3 axes + elbow + wrist, hip 3 + knee +
## ankle; THE LIMB SOLVES below) on the knob's rows, weighted over rows that keep the rest (the hand / foot's world turn: a
## fist keeps its line, a weapon its direction, a sole stays flat). The trunk and hips never move. What each knob asks:
##   striker   the end (weapon tip / wrist / ankle) at chin + height, the root-to-wrist distance at reach x length, the
##             wrist on its old horizontal bearing from the root
##   guard     the wrist straight up / down by the change, over the same spot
##   stance    the REAR foot (the one further back in the body's own forward, body_frame.gd) moved along the line from the
##             lead ankle to the rear ankle, its sole at the same height (so floor grounding moves nothing else); the lead
##             foot stays. A kick's foot standing on a neighbour card is planted there and is not moved
##   a two-hand grip: the second hand back on the shaft (Body.apply_grip), as playback does
## Every angle is written through Body.set_ang (clamped to data/body_limits.json), so no joint leaves its range.
## UNREACHED: a knob that misses its request by more than BAR (1 cm / 1 %) is reported with the joint that stops it: a reach
## past 100 % names the elbow / knee (longer than the limb); else the chain joint on a limit (within 0.5 deg) that the
## remaining error pushes further ("right hip bend at -25 (range -25 .. 120)" for a stance past the rear leg's reach), or
## "height and reach conflict" when no point is both that high and that far.
## LIMITS of this version: it re-solves the limbs only (no hips, no trunk), so a wider stance than a straight rear leg
## allows is reported, not made by lowering the hips; values are on the cards as made, not on the played (pinned, splined)
## frames between them.
class_name MoveKnobs
extends RefCounted

const KNOBS := ["strike_height_cm", "reach_pct", "stance_cm", "guard_cm"]
const UNIT := {"strike_height_cm": "cm", "reach_pct": "%", "stance_cm": "cm", "guard_cm": "cm"}
const FADE := 0.5          # HEURISTIC (above)
const READ_TOL := 0.05     # a knob is read to 0.1: asked within half a step = already there (+ 1e-6 for float noise)
const BAR := 1.0           # cm or %: the item's bar for "lands on the request"
const DOWN_M := 0.04       # m: a foot whose lowest sole point is this near the lower foot's is on the floor (style_dial.gd PLANT_Y)
const SAME_SPOT := 0.02    # m: a ball of the foot within this of its place at contact is the same plant (human_limits.gd TOUCH, 2 cm)
const LIMB := {"hand_r": ["upperarm_r", "lowerarm_r"], "hand_l": ["upperarm_l", "lowerarm_l"],
	"foot_r": ["thigh_r", "calf_r"], "foot_l": ["thigh_l", "calf_l"]}   # what_if.gd LIMBS
const JOINT_WORD := {"upperarm": "shoulder", "lowerarm": "elbow", "hand": "wrist", "thigh": "hip", "calf": "knee", "foot": "ankle"}
const AX := ["bend", "side", "twist"]
const EXTRA_STRIKE := ["cut", "chop"]   # names TimingCoach.STRIKE_WORDS misses (the sword template's "CUT")


# ---- the body ------------------------------------------------------------------------------------------------------

## a scratch body on the scene's proportions
static func scratch(S: Scene) -> Body:
	var B := DistanceKeeper.new_body()
	if not S.body.is_empty():
		B.set_proportions(S.body)
	return B


## the card's pose on B, as picking the card puts it
static func put(B: Body, card: Dictionary) -> void:
	Scene.put(B, Moves._flat(card["pose"]))


static func chin(B: Body) -> Vector3:
	return SayIt.landmark(B, "chin", "", "_r")


static func strike_cards(S: Scene) -> Array:
	var out: Array = FightRhythm.strike_cards(S)
	for i in range(1, S.cards.size()):
		var nm := String(S.cards[i]["name"]).to_lower()
		for w in EXTRA_STRIKE:
			if nm.contains(w) and not out.has(i):
				out.append(i)
	out.sort()
	return out


## who does what on contact card i: {"kind": punch / kick / weapon, "limb": the wrist / ankle whose reach is the knob,
## "end": "weapon" or that limb, "guard": hand or "", "foot": the stance foot moved ("_l" / "_r") or "", "na": {knob: why}}
static func roles(S: Scene, B: Body, i: int) -> Dictionary:
	var w: Dictionary = S.cards[i]["pose"].get("weapon", {})
	var R := {"na": {}}
	if not w.is_empty() and String(w.get("hand", "")) != "":
		R["kind"] = "weapon"
		R["limb"] = String(w["hand"])
		R["end"] = "weapon"
	else:
		var lm: String = FightRhythm._limb(S, B, i)[0]   # the limb that travels furthest into the card (fight_rhythm.gd)
		R["kind"] = "kick" if lm.begins_with("foot") else "punch"
		R["limb"] = lm
		R["end"] = lm
	put(B, S.cards[i])
	var c := chin(B)
	R["guard"] = ""
	if R["kind"] == "weapon" and bool(w.get("two_hand_grip", false)):
		R["na"]["guard_cm"] = "both hands hold the weapon: no guard hand"
	elif R["kind"] == "kick":
		R["guard"] = "hand_l" if (B.P["hand_l"] as Vector3).distance_to(c) <= (B.P["hand_r"] as Vector3).distance_to(c) else "hand_r"
	else:
		R["guard"] = "hand_l" if String(R["limb"]) == "hand_r" else "hand_r"
	R["foot"] = ""
	if R["kind"] == "kick":
		R["na"]["stance_cm"] = "a kick: one foot is the strike, there is no stance at contact"
	elif not (down(B, "_l") and down(B, "_r")):
		R["na"]["stance_cm"] = "a foot is off the floor on this card: no stance to measure"
	else:
		var fwd: Vector3 = BodyFrame.fighter(B)["fwd"]
		R["foot"] = "_l" if (B.P["foot_l"] as Vector3).dot(fwd) < (B.P["foot_r"] as Vector3).dot(fwd) else "_r"
	return R


static func down(B: Body, sd: String) -> bool:
	return B.foot_sole_low(sd) - minf(B.foot_sole_low("_l"), B.foot_sole_low("_r")) < DOWN_M


static func end_point(B: Body, R: Dictionary) -> Vector3:
	return B.wep_point(B.wep_len) if R["end"] == "weapon" and B.wep_on else B.P[R["limb"]]


static func limb_len(B: Body, tip: String) -> float:
	var rt: Vector3 = B.P[LIMB[tip][0]]
	var md: Vector3 = B.P[LIMB[tip][1]]
	return rt.distance_to(md) + md.distance_to(B.P[tip])


## the four numbers on the body as posed (null = not on this strike), unrounded
static func values(B: Body, R: Dictionary) -> Dictionary:
	var c := chin(B)
	var tip: String = R["limb"]
	var v := {"strike_height_cm": (end_point(B, R).y - c.y) * 100.0,
		"reach_pct": 100.0 * (B.P[LIMB[tip][0]] as Vector3).distance_to(B.P[tip]) / limb_len(B, tip),
		"stance_cm": null, "guard_cm": null}
	if R["foot"] != "":
		var d: Vector3 = (B.P["foot_l"] as Vector3) - (B.P["foot_r"] as Vector3)
		v["stance_cm"] = Vector2(d.x, d.z).length() * 100.0
	if R["guard"] != "":
		v["guard_cm"] = ((B.P[R["guard"]] as Vector3).y - c.y) * 100.0
	return v


static func rounded(v: Dictionary) -> Dictionary:
	var o := {}
	for k in KNOBS:
		o[k] = snappedf(float(v[k]), 0.1) if v[k] != null else null
	return o


# ---- the solver ----------------------------------------------------------------------------------------------------

## the free axes of a chain: [[joint, axis index]] whose range is wider than 0.5 deg (a hinge's side and twist are locked)
static func _vars(B: Body, js: Array) -> Array:
	var vs := []
	for j in js:
		for k in 3:
			var r: Vector2 = B.lim[j][AX[k]]
			if r.y - r.x > 0.5:
				vs.append([j, k])
	return vs


static func _ang_of(B: Body, v: Array) -> float:
	return (B.ang[v[0]] as Vector3)[v[1]]


static func _ang_to(B: Body, v: Array, x: float) -> void:
	var a: Vector3 = B.ang[v[0]]
	a[v[1]] = x
	B.set_ang(v[0], a)   # clamped to the joint's range


## the d(end)/d(angle) columns (m per radian), one-sided toward the inside of the range
static func _jac(B: Body, vs: Array, end: String) -> Array:
	var J := []
	var p0: Vector3 = B.P[end]
	for v in vs:
		var x := _ang_of(B, v)
		var r: Vector2 = B.lim[v[0]][AX[v[1]]]
		var h := 0.25 if x + 0.25 <= r.y else -0.25   # deg
		_ang_to(B, v, x + h)
		J.append(((B.P[end] as Vector3) - p0) / deg_to_rad(h))
		_ang_to(B, v, x)
	return J


## DAMPED LEAST SQUARES (Wampler 1986 / Buss 2004, "Introduction to inverse kinematics with Jacobian transpose, pseudoinverse
## and damped least squares methods"): dq = J^T (J J^T + l^2 I)^-1 e, l = 1 cm, each step capped at 0.2 rad, on any residual
## err() (m; rows of a turn are weighted by ROT_W). Each step, an axis on its stop that the step would push further out is
## left out and the step solved again without it (the active set is rebuilt every step: a straight knee that must bend is
## not shut out for good, the first version's bug). Stops when the error stops falling.
static func _dls(B: Body, vs: Array, err: Callable) -> void:
	var best := INF
	for it in 40:
		var e: PackedFloat64Array = err.call()
		var nrm := 0.0
		for x in e:
			nrm += x * x
		nrm = sqrt(nrm)
		if nrm < 1e-5 or nrm > best - 1e-9:
			break
		best = nrm
		var J := []
		for v in vs:
			var x := _ang_of(B, v)
			var r: Vector2 = B.lim[v[0]][AX[v[1]]]
			var h := 0.25 if x + 0.25 <= r.y else -0.25   # deg, toward the inside of the range
			_ang_to(B, v, x + h)
			var e1: PackedFloat64Array = err.call()
			_ang_to(B, v, x)
			var col := PackedFloat64Array()
			for k in e.size():
				col.append((e[k] - e1[k]) / deg_to_rad(h))   # the tip's change per radian (the error falls as it moves)
			J.append(col)
		var act := range(vs.size())
		var dq := _dls_step(J, act, e)
		var out := []
		for n in act:
			var v: Array = vs[n]
			var r: Vector2 = B.lim[v[0]][AX[v[1]]]
			var x := _ang_of(B, v)
			if (x >= r.y - 1e-3 and dq[n] > 0.0) or (x <= r.x + 1e-3 and dq[n] < 0.0):
				out.append(n)
		if not out.is_empty():
			act = act.filter(func(n): return not out.has(n))
			dq = _dls_step(J, act, e)
		# BACKTRACKING: a step that makes the error worse is taken back and halved (4 times at most). From a straight knee
		# the first full step bent it the wrong way round a rolled hip and the solve stopped there (the sword's rear foot
		# 14 cm off its target)
		var x0 := {}
		for n in act:
			x0[n] = _ang_of(B, vs[n])
		var f := 1.0
		var better := false
		for half in 5:
			for n in act:
				_ang_to(B, vs[n], float(x0[n]) + rad_to_deg(clampf(dq[n] * f, -0.2, 0.2)))
			var e2: PackedFloat64Array = err.call()
			var n2 := 0.0
			for x in e2:
				n2 += x * x
			if sqrt(n2) < nrm - 1e-9:
				better = true
				break
			f *= 0.5
		if not better:
			for n in act:
				_ang_to(B, vs[n], float(x0[n]))
			break


## one DLS step over the columns `act`: {column index: dq (rad)}
static func _dls_step(J: Array, act: Array, e: PackedFloat64Array) -> Dictionary:
	var m := e.size()
	var A := []
	for r in m:
		var row := []
		for c in m:
			var a := 1e-4 if r == c else 0.0
			for n in act:
				a += (J[n] as PackedFloat64Array)[r] * (J[n] as PackedFloat64Array)[c]
			row.append(a)
		A.append(row)
	var y := _gauss(A, Array(e))
	var dq := {}
	for n in act:
		var col: PackedFloat64Array = J[n]
		var d := 0.0
		for k in m:
			d += col[k] * float(y[k])
		dq[n] = d
	return dq


## THE LIMB SOLVES. Each is one damped-least-squares solve (_dls) of a limb's three joints on rows of two weights:
##   KNOB rows (x KNOB_W): what the knob asks (the end's height, the reach, the guard wrist's height, the stance ankle's
##     place along the floor, the stance sole's height). Weighted 10x so the knob is met whenever the limits allow it
##   KEEP rows (x 1, turns x ROT_W m per radian): what should not change (the hand / foot's world turn, the end's bearing
##     from the root, the guard wrist's place along the floor, the stance ankle's height)
## The first version moved the wrist / ankle onto a point and turned the hand / foot back afterwards: a solve on position
## alone rolls the thigh / upper arm for free, and the ankle's 25 deg could not turn the foot back (measured: the punch
## template's wider stance put the foot on all three ankle stops, its sole 1 cm off, and grounding moved the lead foot 1.7
## cm; the sword's tip, carried by the hand's turn, missed its height by 4 cm). With every row in one solve neither happens.
const KNOB_W := 10.0
const ROT_W := 0.1   # m per radian (6 deg weighs as 1 cm)
const CONTACT_W := 100.0   # the stance sole's height: a contact, above the knob (a stance out of reach must not lift the
                           # sole and so, through grounding, the lead foot: measured 1.4 cm at KNOB_W on the sword's +10 cm)


## a joint's world turn away from g0, as 3 rows (rotation vector x w)
static func _turn_rows(B: Body, j: String, g0: Quaternion, w: float) -> Array:
	var q: Quaternion = (g0 * (B.G[j] as Quaternion).inverse()).normalized()
	if q.w < 0.0:
		q = -q
	var a := q.get_angle()
	var rv: Vector3 = q.get_axis() * a * w if a > 1e-9 else Vector3.ZERO
	return [rv.x, rv.y, rv.z]


static func _chain(tip: String) -> Array:
	return LIMB[tip] + [tip]


## the striker: its end (weapon tip, wrist or ankle) at h cm over the chin, its root-to-wrist at r % of the limb, the
## wrist on its old bearing from the root, the hand / foot keeping its turn
static func _strike(B: Body, R: Dictionary, h: float, r: float) -> void:
	var tip: String = R["limb"]
	var root: String = LIMB[tip][0]
	var g0: Quaternion = B.G[tip]
	var cy := chin(B).y   # the trunk does not move: the chin stays
	var L := limb_len(B, tip)
	var az: Vector3 = (B.P[tip] as Vector3) - (B.P[root] as Vector3)
	az.y = 0.0
	var side: Vector3 = az.normalized().cross(Vector3.UP) if az.length() > 1e-4 else Vector3.ZERO
	_dls(B, _vars(B, _chain(tip)), func() -> PackedFloat64Array:
		var w: Vector3 = (B.P[tip] as Vector3) - (B.P[root] as Vector3)
		var rows := [KNOB_W * (cy + h * 0.01 - end_point(B, R).y), KNOB_W * (r * 0.01 * L - w.length()), -w.dot(side)]
		return PackedFloat64Array(rows + _turn_rows(B, tip, g0, ROT_W)))


## the guard wrist dy metres up, staying over the same spot, the hand keeping its turn
static func _guard(B: Body, hand: String, dy: float) -> void:
	var T: Vector3 = (B.P[hand] as Vector3) + Vector3(0, dy, 0)
	var g0: Quaternion = B.G[hand]
	_dls(B, _vars(B, _chain(hand)), func() -> PackedFloat64Array:
		var e: Vector3 = T - (B.P[hand] as Vector3)
		return PackedFloat64Array([KNOB_W * e.y, e.x, e.z] + _turn_rows(B, hand, g0, ROT_W)))


## the stance foot (side sd) moved by D along the floor, its sole at the same height (so grounding moves nothing else),
## the ankle's height and the foot's turn kept
static func _stance(B: Body, sd: String, D: Vector3) -> void:
	var f := "foot" + sd
	var T: Vector3 = (B.P[f] as Vector3) + D
	var low0 := B.foot_sole_low(sd)
	var g0: Quaternion = B.G[f]
	_dls(B, _vars(B, _chain(f)), func() -> PackedFloat64Array:
		var e: Vector3 = T - (B.P[f] as Vector3)
		return PackedFloat64Array([KNOB_W * e.x, KNOB_W * e.z, CONTACT_W * (low0 - B.foot_sole_low(sd)), e.y] + _turn_rows(B, f, g0, ROT_W)))


## n x n linear solve, Gaussian elimination with partial pivoting (doubles)
static func _gauss(A: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for r in n:
		M.append((A[r] as Array).duplicate() + [b[r]])
	for c in n:
		var p := c
		for r in range(c + 1, n):
			if absf(M[r][c]) > absf(M[p][c]):
				p = r
		var t = M[c]
		M[c] = M[p]
		M[p] = t
		if absf(M[c][c]) < 1e-18:
			continue
		for r in range(c + 1, n):
			var f: float = M[r][c] / M[c][c]
			for k in range(c, n + 1):
				M[r][k] -= f * M[c][k]
	var x := []
	x.resize(n)
	for r in range(n - 1, -1, -1):
		var s: float = M[r][n]
		for k in range(r + 1, n):
			s -= M[r][k] * x[k]
		x[r] = s / M[r][r] if absf(M[r][r]) > 1e-18 else 0.0
	return x


## the joint that stops a limb short of T: the chain axis on a limit (0.5 deg) that the error pushes past it, the
## hardest-pushed first. {} = none (the miss is not a limit's)
static func limiting(B: Body, tip: String, T: Vector3) -> Dictionary:
	var e: Vector3 = T - (B.P[tip] as Vector3)
	var vs := _vars(B, LIMB[tip] + [tip])
	var J := _jac(B, vs, tip)
	var best := {}
	var push := 1e-9
	for n in vs.size():
		var v: Array = vs[n]
		var x := _ang_of(B, v)
		var r: Vector2 = B.lim[v[0]][AX[v[1]]]
		var g: float = (J[n] as Vector3).dot(e)
		var out := (x >= r.y - 0.5 and g > 0.0) or (x <= r.x + 0.5 and g < 0.0)
		if out and absf(g) > push:
			push = absf(g)
			var jn: String = v[0]
			var sd := "right " if jn.ends_with("_r") else "left "
			best = {"joint": jn, "axis": AX[v[1]], "at_deg": snappedf(x, 0.1), "range": [r.x, r.y],
				"words": "%s%s %s at %s (range %s .. %s)" % [sd, JOINT_WORD.get(jn.left(jn.length() - 2), jn), AX[v[1]], snappedf(x, 0.1), r.x, r.y]}
	return best


# ---- reading -------------------------------------------------------------------------------------------------------

## the knobs of strike card i (0-based): {"ok", "card", "name", "kind", "striker", "values", "na", "guard_hand", "stance_foot",
## "end_words"} or {"ok": false, "error"}
static func read(S: Scene, i: int, B: Body = null) -> Dictionary:
	if B == null:
		B = scratch(S)
	var why := not_strike(S, i)
	if why != "":
		return {"ok": false, "error": why}
	var R := roles(S, B, i)
	put(B, S.cards[i])
	var v := values(B, R)
	var out := {"ok": true, "card": i + 1, "name": String(S.cards[i]["name"]), "kind": R["kind"],
		"striker": "weapon tip (%s)" % R["limb"] if R["kind"] == "weapon" else R["limb"], "values": rounded(v), "na": R["na"],
		"guard_hand": R["guard"], "stance_foot": ("foot" + String(R["foot"])) if R["foot"] != "" else "",
		"units": UNIT, "end_words": _words(B, R)}
	return out


## the striking end in the body's words (N007), its own wrist / ankle left out of the landmarks (a fist is not "level
## with the right hand")
static func _words(B: Body, R: Dictionary) -> String:
	var F := BodyFrame.fighter(B)
	if R["end"] != "weapon":
		var key: String = R["limb"]
		F["lm"][key] = Vector3(0, 1e6, 0)
	return BodyFrame.describe(end_point(B, R), F)["words"]


## "" = card i is a strike card; else why not, with the ones that are
static func not_strike(S: Scene, i: int) -> String:
	if S.cards.size() < 2:
		return "move knobs need a scene of 2+ cards with a strike: open one"
	if i < 0 or i >= S.cards.size():
		return "no card %d (the scene has %d)" % [i + 1, S.cards.size()]
	var sc := strike_cards(S)
	if not sc.has(i):
		var names := sc.map(func(k): return "%d '%s'" % [k + 1, S.cards[k]["name"]])
		return "card %d '%s' is not a strike card (a card named strike / punch / kick / swing / cut ..., or with a hit marker). %s" % [i + 1,
			S.cards[i]["name"], ("The strike cards: " + ", ".join(names)) if not names.is_empty() else "This scene has none: name the contact card (e.g. 'CROSS') or put a hit marker on it"]
	return ""


# ---- setting -------------------------------------------------------------------------------------------------------

## THE PLAN for setting knobs `ask` ({knob: number}) on strike card i: the new poses, nothing written.
## {"ok", "poses": {card index: pose}, "before", "after" (rounded values on the contact card), "asked", "unreached": [...],
##  "already": [knobs left alone], "feet_moved_cm" (planted feet other than the stance foot, worst over the cards),
##  "cards": [1-based affected cards]} or {"ok": false, "error"}
static func plan(S: Scene, i: int, ask: Dictionary) -> Dictionary:
	var B := scratch(S)
	var why := not_strike(S, i)
	if why != "":
		return {"ok": false, "error": why}
	for k in ask:
		if not k in KNOBS:
			return {"ok": false, "error": "no knob '%s': the knobs are %s" % [k, ", ".join(KNOBS)]}
		if not (ask[k] is float or ask[k] is int):
			return {"ok": false, "error": "%s must be a number (%s), got %s" % [k, UNIT[k], ask[k]]}
	var R := roles(S, B, i)
	for k in ask:
		if R["na"].has(k):
			return {"ok": false, "error": "%s is not on this strike: %s" % [k, R["na"][k]]}
	put(B, S.cards[i])
	var v0 := values(B, R)
	var want := {}
	var already := []
	for k in ask:
		if absf(float(ask[k]) - float(v0[k])) <= READ_TOL + 1e-6:
			already.append(k)
		else:
			want[k] = float(ask[k])
	var out := {"ok": true, "poses": {}, "before": rounded(v0), "asked": ask, "already": already, "unreached": [], "feet_moved_cm": 0.0, "cards": []}
	if want.is_empty():
		out["after"] = out["before"]
		return out
	# the weights: the contact card and its neighbours; for the stance, the moved foot's whole plant at contact
	var wt := {}   # card -> {"limb": w, "stance": w}
	var n := S.cards.size()
	for k in [i - 1, i, i + 1]:
		if k >= 0 and k < n:
			wt[k] = {"limb": 1.0 if k == i else FADE, "stance": 1.0 if k == i else FADE}
	var D := Vector3.ZERO   # the stance move at contact (m, horizontal)
	if want.has("stance_cm"):
		var sd: String = R["foot"]
		var o := "_l" if sd == "_r" else "_r"
		var dir: Vector3 = (B.P["foot" + sd] as Vector3) - (B.P["foot" + o] as Vector3)
		dir.y = 0.0
		D = dir.normalized() * (float(want["stance_cm"]) - float(v0["stance_cm"])) * 0.01
		var ball0: Vector3 = B.P["ball" + sd]
		for k in n:
			put(B, S.cards[k])
			var bk: Vector3 = B.P["ball" + sd]
			if down(B, sd) and Vector2(bk.x - ball0.x, bk.z - ball0.z).length() < SAME_SPOT:
				if not wt.has(k):
					wt[k] = {"limb": 0.0, "stance": 1.0}
				wt[k]["stance"] = 1.0
	var keys: Array = wt.keys()
	keys.sort()
	var feet := 0.0
	for k in keys:
		put(B, S.cards[k])
		var vk := values(B, R)
		var feet0 := _feet(B)
		var wl: float = wt[k]["limb"]
		var ws: float = wt[k]["stance"]
		var moved := false
		if want.has("stance_cm") and ws > 0.0:
			_stance(B, String(R["foot"]), D * ws)
			moved = true
		# a kick's foot standing on a neighbour card (the guard it starts from, the stance it lands in) is a planted foot there:
		# it is not the strike on that card and stays where it is (measured: the recover card's right foot moved 8.6 cm)
		var kick_down: bool = R["kind"] == "kick" and k != i and down(B, String(R["limb"]).right(2))
		if wl > 0.0 and not kick_down and (want.has("strike_height_cm") or want.has("reach_pct")):
			var h: float = float(vk["strike_height_cm"]) + (wl * (float(want["strike_height_cm"]) - float(v0["strike_height_cm"])) if want.has("strike_height_cm") else 0.0)
			var r: float = float(vk["reach_pct"]) + (wl * (float(want["reach_pct"]) - float(v0["reach_pct"])) if want.has("reach_pct") else 0.0)
			_strike(B, R, h, r)
			moved = true
		if wl > 0.0 and want.has("guard_cm"):
			var dg: float = wl * (float(want["guard_cm"]) - float(v0["guard_cm"])) * 0.01
			_guard(B, R["guard"], dg)
			moved = true
		if not moved:
			continue
		B.apply_grip()   # a two-hand grip: the second hand back on the shaft (playback does the same)
		var pose: Dictionary = (S.cards[k]["pose"] as Dictionary).duplicate(true)
		var td := B.to_dict()
		for key in ["joints", "weapon", "contacts"]:
			pose[key] = td[key]
		out["poses"][k] = pose
		out["cards"].append(k + 1)
		# the planted feet (not the one the stance knob moves), on the pose as written and grounded as playback grounds it
		put(B, {"pose": pose})
		feet = maxf(feet, _feet_moved(feet0, _feet(B), String(R["foot"]) if want.has("stance_cm") else ""))
	out["feet_moved_cm"] = snappedf(feet * 100.0, 0.01)
	# the contact card as written: what it reached, and what stopped what it did not
	put(B, {"pose": out["poses"].get(i, S.cards[i]["pose"])})
	var v1 := values(B, R)
	out["after"] = rounded(v1)
	for k in want:
		var miss := absf(float(v1[k]) - float(want[k]))
		if miss > BAR:
			out["unreached"].append(_why(B, R, k, float(want[k]), float(v1[k]), v0, want))
	return out


## the point at height y, distance d from the limb's root, on the wrist's present bearing from it (horizontal); a height
## further from the root than d is clamped to straight above / below it (the conflict is reported by _why)
static func _target(B: Body, tip: String, y: float, d: float) -> Vector3:
	var R0: Vector3 = B.P[LIMB[tip][0]]
	var az: Vector3 = (B.P[tip] as Vector3) - R0
	az.y = 0.0
	if az.length() < 1e-4:
		az = BodyFrame.fighter(B)["fwd"]
	az = az.normalized()
	var dy := clampf(y - R0.y, -d, d)
	return R0 + az * sqrt(maxf(d * d - dy * dy, 0.0)) + Vector3(0, dy, 0)


## a knob that missed: the limit that stopped it
static func _why(B: Body, R: Dictionary, k: String, asked: float, got: float, v0: Dictionary, want: Dictionary) -> Dictionary:
	var u := {"knob": k, "asked": asked, "got": snappedf(got, 0.1), "unit": UNIT[k]}
	var tip: String = R["limb"]
	var T := Vector3.ZERO
	var mid: String = LIMB[tip][1]
	if k == "reach_pct" and asked > 100.0:
		# past 100 % is longer than the limb: the elbow / knee straight is the stop, whatever else the solve leaned on
		var r0: Vector2 = B.lim[mid]["bend"]
		var sd := "right " if mid.ends_with("_r") else "left "
		u["limit"] = {"joint": mid, "axis": "bend", "at_deg": snappedf(float((B.ang[mid] as Vector3).x), 0.1), "range": [r0.x, r0.y],
			"words": "%s%s bend %s (straight at 0, range %s .. %s): %.1f %% is this limb's full reach from the %s" % [sd, JOINT_WORD[mid.left(mid.length() - 2)],
				snappedf(float((B.ang[mid] as Vector3).x), 0.1), r0.x, r0.y, got, JOINT_WORD[LIMB[tip][0].left(LIMB[tip][0].length() - 2)]]}
		u["joint"] = mid
		return u
	match k:
		"strike_height_cm", "reach_pct":
			var h: float = float(want.get("strike_height_cm", v0["strike_height_cm"]))
			var r: float = float(want.get("reach_pct", v0["reach_pct"]))
			var off_y: float = end_point(B, R).y - (B.P[tip] as Vector3).y
			var y := chin(B).y + h * 0.01 - off_y
			var d := r * 0.01 * limb_len(B, tip)
			if absf(y - (B.P[LIMB[tip][0]] as Vector3).y) > d + 0.005:
				u["limit"] = {"words": "height and reach conflict: at %.0f %% the %s reaches %.1f cm above / below its %s at most" % [r, tip, d * 100.0,
					JOINT_WORD[LIMB[tip][0].left(LIMB[tip][0].length() - 2)]]}
				return u
			T = _target(B, tip, y, d)
		"guard_cm":
			tip = R["guard"]
			T = B.P[tip] + Vector3(0, (asked - got) * 0.01, 0)
		"stance_cm":
			tip = "foot" + String(R["foot"])
			var o := "_l" if R["foot"] == "_r" else "_r"
			var dir: Vector3 = (B.P[tip] as Vector3) - (B.P["foot" + o] as Vector3)
			dir.y = 0.0
			T = B.P[tip] + dir.normalized() * (asked - got) * 0.01
	var lj := limiting(B, tip, T)
	u["limit"] = lj if not lj.is_empty() else {"words": "no joint on a limit: the solve stalled (a pose the two-segment IK cannot reach from here)"}
	u["joint"] = String(lj.get("joint", ""))
	return u


## where each foot on the floor is (ankle and ball), grounded as playback grounds it
static func _feet(B: Body) -> Dictionary:
	var keep := B.offset
	B.ground()
	var f := {}
	for sd in ["_l", "_r"]:
		if down(B, sd):
			f[sd] = [B.P["foot" + sd], B.P["ball" + sd]]
	B.offset = keep
	B.fk()
	return f


## the most a planted foot moved (m), the foot `skip` (the stance knob's own) aside
static func _feet_moved(a: Dictionary, b: Dictionary, skip: String) -> float:
	var worst := 0.0
	for sd in a:
		if sd == skip:
			continue
		if not b.has(sd):
			return INF   # it left the floor
		worst = maxf(worst, maxf((a[sd][0] as Vector3).distance_to(b[sd][0]), (a[sd][1] as Vector3).distance_to(b[sd][1])))
	return worst


# ---- the agent's call ----------------------------------------------------------------------------------------------

## serve's `knobs` on the live poser m: {card (1-based; default the picked card), read: true} -> the values;
## {card, set: {knob: number}} -> applied as ONE undo step; the new values, what was left alone and what was not reached
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var S: Scene = m.S
	var i := int(p.get("card", m.sel_card + 1)) - 1
	if not p.has("set"):
		return read(S, i)   # {read: true} or nothing to set
	var ask: Variant = p["set"]
	if not (ask is Dictionary) or (ask as Dictionary).is_empty():
		return {"ok": false, "error": "knobs set needs {\"card\": N, \"set\": {\"strike_height_cm\": -5, \"reach_pct\": 95, \"stance_cm\": 45, \"guard_cm\": -3}} (any of the four)"}
	var pl := plan(S, i, ask)
	if not pl["ok"]:
		return pl
	var poses: Dictionary = pl["poses"]
	pl.erase("poses")
	pl["card"] = i + 1
	pl["undo_steps"] = 0
	if not poses.is_empty():
		m._step_hint = "Move knobs: " + ", ".join((ask as Dictionary).keys().map(func(k): return "%s %s" % [k, ask[k]]))
		var u0: int = m.undo.size()
		m._push_undo()
		for k in poses:
			m.S.cards[k]["pose"] = poses[k]
		m._rebuild_cards()
		if m.sel_card >= 0 and m.sel_card < m.S.cards.size():
			Scene.put(m.B, Moves._flat(m.S.cards[m.sel_card]["pose"]))
			m.B.apply_grip()
		m._refresh()
		pl["undo_steps"] = m.undo.size() - u0
	pl["said"] = "card %d: %s%s" % [i + 1, ", ".join(KNOBS.filter(func(k): return pl["after"][k] != null).map(func(k): return "%s %s %s" % [k, pl["after"][k], UNIT[k]])),
		(" ; NOT REACHED: " + "; ".join(pl["unreached"].map(func(x): return "%s asked %s got %s (%s)" % [x["knob"], x["asked"], x["got"], x["limit"]["words"]]))) if not pl["unreached"].is_empty() else ""]
	return pl
