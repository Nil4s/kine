## trunk_lean.gd - THE TRUNK-LEAN CHECK (Nick 10-23: "sometimes the back plus torso bend too much back or too much forward,
## something that doesn't feel natural; you can see it on kicks"). Each card's window of a clip is read for the trunk's lean
## against vertical; a frame past the range people are measured at for that move is a Check finding, "TRUNK LEAN" (WARN),
## and its Fix turns the spine back inside the range on the card nearest that frame, the strike's contact point and the
## feet kept where they were.
## WHY: a blind agent (or a hand drag, see below) can bend the back 50 deg behind a roundhouse and nothing said so. The
## numbers do now.
##
## WHAT IS READ (sources and reasoning: docs/research/TRUNK_LEAN.md):
##   the trunk     the line pelvis -> neck_01 (the base of the neck), per frame at 60 fps, said in the HIPS' frame (the hip
##                 line laid flat = his left; forward = left x up, body_frame.gd's rule on the hips alone): PITCH = its lean
##                 toward his front (+) or back (-), ROLL = toward his left (+) or right (-). The rest pose's own offset (the
##                 skeleton's neck sits 4 deg ahead of the pelvis standing straight) is taken off, so standing tall reads 0.
##   the move      N016's recognizer (MoveRecognizer.analyze) over each card's window (the move into card k and its hold), as
##                 weight_xfer.gd reads it: a named kick or punch gets its own range, anything else the general one.
##   lateral       for a kick, roll is said AWAY from the kicking leg (+ = away): the trunk leans off the kick to balance it.
## THE RANGES (deg; NORMS below, each with its source or HEURISTIC; the table: docs/research/TRUNK_LEAN.md)
## THE FIX (Fixer, the Check panel's Fix button, one Ctrl+Z): on the card nearest the worst frame, spine_01..03 are turned
## (in world space, a third each, their limits kept) by what the worst frame is past the range plus FIX_MARGIN; a punching
## hand is put back on the point it had on that card (Body.reach); the legs hang from the pelvis, which is not touched, so
## the feet and a kicking foot stay exactly where they were. Measured again as it plays, up to FIX_TRIES.
class_name TrunkLean
extends RefCounted

const FPS := 60.0
const SPINE := ["spine_01", "spine_02", "spine_03"]
const FIX_MARGIN := 3.0   # HEURISTIC: deg the fix aims inside the range (the move out of the card blends part of it away)
const FIX_TRIES := 4
const CONTACT_TOL := 0.005   # m: the pelvis fix re-aims the strike until the played contact is this close (test bar 3 cm)
const MEMO_MAX := 16

## per move: [back max, forward max, lateral max] (deg; back = -pitch, lateral = |roll|). See docs/research/TRUNK_LEAN.md
const NORMS := {
	"roundhouse": [40.0, 25.0, 45.0],
	"side kick": [40.0, 25.0, 55.0],
	"front kick": [30.0, 25.0, 25.0],
	"knee": [30.0, 30.0, 25.0],
	"jab": [10.0, 25.0, 20.0],
	"cross": [10.0, 30.0, 25.0],
	"hook": [10.0, 30.0, 30.0],
	"uppercut": [15.0, 30.0, 25.0],
}
const GENERAL := [25.0, 60.0, 30.0]   # HEURISTIC: no move named (walking, idling, a weapon swing, a bow)
const KICKS := ["front kick", "side kick", "roundhouse", "knee"]

static var _memo := {}


## the hips' own frame, yaw only: [left, fwd] (the hip line laid flat; fwd = left x up, body.gd: +z his front)
static func _frame(tl: Vector3, tr: Vector3) -> Array:
	var l := tl - tr
	l.y = 0.0
	if l.length() < 1e-4:
		l = Vector3(1, 0, 0)
	l = l.normalized()
	return [l, l.cross(Vector3.UP).normalized()]


## the skeleton's own standing offset (deg of pitch): the neck over the pelvis in the rest pose
static func rest_pitch(B: Body) -> float:
	var v: Vector3 = (B.p0["neck_01"] as Vector3) - (B.p0["pelvis"] as Vector3)
	return rad_to_deg(atan2(v.z, v.y))


## pitch / roll (deg) of the trunk line from four points, the rest offset taken off
static func lean_of(pel: Vector3, neck: Vector3, tl: Vector3, tr: Vector3, rest := 0.0) -> Vector2:
	var fr := _frame(tl, tr)
	var v := neck - pel
	var up := v.dot(Vector3.UP)
	return Vector2(rad_to_deg(atan2(v.dot(fr[1]), up)) - rest, rad_to_deg(atan2(v.dot(fr[0]), up)))


## the body now: {"pitch" (+ forward), "roll" (+ his left), "bend" (spine_01..03 bend summed, + forward), "side" (summed)}
## (pitch here is raw: the rest offset NOT taken off; the dev tools print it as it stands)
static func angles(B: Body) -> Dictionary:
	var l := lean_of(B.P["pelvis"], B.P["neck_01"], B.P["thigh_l"], B.P["thigh_r"])
	var bend := 0.0
	var side := 0.0
	for j in SPINE:
		bend += float((B.ang[j] as Vector3).x)
		side += float((B.ang[j] as Vector3).y)
	return {"pitch": l.x, "roll": l.y, "bend": bend, "side": side}


static func _pt(clip: Dictionary, f: int, nm: String) -> Vector3:
	return MoveRecognizer._p(clip, 0, f, nm)


## per card window k (1..): {"card", "class" ("" = none named), "norm", "f" (worst frame), "t", "pitch", "roll" (away from a
## kicking leg for a kick), "over" (deg past the range, > 0 = flagged), "what" ("back" / "forward" / "sideways"), "point"
## (the strike's contact point name, "" = none)}. Card 0's own hold is read with the general range.
static func windows(S: Scene, B: Body) -> Array:
	var out := []
	if S.cards.size() < 1:
		return out
	var keep := B.state()
	var was := S.stepped
	S.stepped = false   # graded as it really plays (Rulebook.sample's rule)
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	var key := ""
	if main:
		key = PoseBake.signature(S).hex_encode().sha256_text() + str(B.body.hash())
		if _memo.has(key):
			S.stepped = was
			return (_memo[key] as Array).duplicate(true)
	var clip := EventQuery.sample([{"S": S, "B": B, "xf": Transform3D.IDENTITY, "name": String(S.name)}], FPS, {"cross": false, "bal": false}, not main)
	var n: int = clip["n"]
	var rest := rest_pitch(B)
	var ts := S.times()
	var seen := {}
	for k in S.cards.size():
		var f0 := 0 if k == 0 else int(round(float(ts[k][0]) * FPS))
		var f1 := mini(int(round(float(ts[k][2]) * FPS)), n - 1)
		if f1 < f0:
			continue
		var cls := ""
		var sd := ""
		var point := ""
		if k > 0 and f1 > f0:
			var r := MoveRecognizer.analyze(clip, 0, f0, f1)
			if r.get("strike", false) and not r.get("unknown", true) and NORMS.has(String(r["class"])):
				cls = String(r["class"])
				sd = "_l" if String(r["side"]) == "left" else "_r"
				point = String(r.get("point", ""))
		var norm: Array = NORMS[cls] if cls != "" else GENERAL
		var worst := {"over": -INF}
		for f in range(f0, f1 + 1):
			var l := lean_of(_pt(clip, f, "pelvis"), _pt(clip, f, "neck_01"), _pt(clip, f, "thigh_l"), _pt(clip, f, "thigh_r"), rest)
			var roll := l.y
			if cls in KICKS:
				roll = l.y if sd == "_r" else -l.y   # + = away from the kicking leg (a right kick: toward his left)
			var o := {"back": -l.x - float(norm[0]), "forward": l.x - float(norm[1]), "sideways": absf(roll) - float(norm[2])}
			for w in o:
				if float(o[w]) > float(worst["over"]):
					worst = {"over": float(o[w]), "what": w, "f": f, "pitch": l.x, "roll": roll}
		if worst["over"] > 0.0 and seen.has(int(worst["f"])):
			continue   # the same frame already reported from the window before
		seen[int(worst["f"])] = true
		worst.merge({"card": k, "class": cls, "side": sd, "norm": norm, "t": int(worst["f"]) / FPS, "point": point})
		out.append(worst)
	S.stepped = was
	B.set_state(keep)
	B.fk()
	if main:
		if _memo.size() >= MEMO_MAX:
			_memo.clear()
		_memo[key] = out.duplicate(true)
	return out


static func _move_words(it: Dictionary) -> String:
	return ("the " + String(it["class"])) if it["class"] != "" else "this move"


## Check's findings: one WARN per card window whose worst frame is past its range. v = deg past it
static func findings(S: Scene, B: Body) -> Array:
	var out := []
	for it in windows(S, B):
		if float(it["over"]) <= 0.0:
			continue
		var nm: Array = it["norm"]
		var lean := "%.0f deg %s" % [absf(float(it["pitch"])) if it["what"] != "sideways" else absf(float(it["roll"])),
			{"back": "back", "forward": "forward", "sideways": "to the side" + (" away from the kick" if it["class"] in KICKS and float(it["roll"]) > 0.0 else "")}[it["what"]]]
		var bar := float(nm[{"back": 0, "forward": 1, "sideways": 2}[it["what"]]])
		var f := Rulebook._f("WARN", it["t"], "TRUNK LEAN", "%.2f s: in %s the trunk leans %s (pelvis to neck against vertical); people lean up to %.0f deg %s in %s, so it is %.0f deg past that." % [
			it["t"], _move_words(it), lean, bar, it["what"] if it["what"] != "sideways" else "sideways", _move_words(it) if it["class"] != "" else "an unnamed move (the general range)", it["over"]], float(it["over"]))
		f.merge({"what": it["what"], "class": it["class"], "window": it["card"], "point": it["point"]})
		out.append(f)
	return out


## the card nearest the time t (by its arrival)
static func _card_near(S: Scene, t: float) -> int:
	var ts := S.times()
	var best := -1
	for i in ts.size():
		if best < 0 or absf(float(ts[i][1]) - t) < absf(float(ts[best][1]) - t):
			best = i
	return best


## the same window again after an edit
static func _again(S: Scene, B: Body, f: Dictionary) -> Dictionary:
	for it in windows(S, B):
		if int(it["card"]) == int(f["window"]):
			return it
	return {}


## turn the trunk line of the pose in B by (dp, dr) deg (pitch toward his front, roll toward his left, the hips' frame),
## spread over spine_01..03 in world space (their limits kept); a hand on `keep_tip` is put back on `keep_at`
static func turn(B: Body, dp: float, dr: float, keep_tip := "", keep_at := Vector3.ZERO) -> void:
	var fr := _frame(B.P["thigh_l"], B.P["thigh_r"])
	# pitch forward = a turn about the hips' left axis (+z toward -y: about +x, right-handed, tips the top toward +fwd)
	var q := Quaternion(fr[0], deg_to_rad(dp)) * Quaternion(fr[1], deg_to_rad(-dr))
	var ax := q.get_axis()
	var a := q.get_angle()
	for j in SPINE:
		B.turn_world(j, Quaternion(ax, a / 3.0))
		B.fk()
	if keep_tip != "":
		B.reach(keep_tip, keep_at)


## THE FIX (Fixer.apply / propose): {"did", "same" when nothing could be changed, "over0", "over1", "card"}
## Two levers, in this order. The SPINE first (spine_01..03, a third each): the spine turns the trunk line only about 0.4
## deg per deg (its joints sit low, the neck high), and its limits (bend -7..20 each) stop it at about 19 deg of trunk.
## Then the PELVIS for the rest: the trunk line starts at the pelvis, so a pelvis tilt turns the line 1 deg per deg. The
## pelvis moves the legs, so the kicking foot is reached back onto its contact point and each planted foot is put back on
## its ball (Body.plant), and a punching fist is re-reached (Body.reach).
static func fix(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var it := _again(S, B, f)
	if it.is_empty() or float(it["over"]) <= 0.0:
		return {"did": "the trunk is already inside its range", "same": true}
	var it0 := it.duplicate()
	var j := _card_near(S, float(it["t"]))
	if j < 0:
		return {"did": "no card to turn", "same": true}
	var orig: Dictionary = S.cards[j]["pose"].duplicate(true)
	var keep := B.state()
	var o0 := float(it["over"])
	var o1 := o0
	var best := {}
	var tip := ""
	var p: String = it.get("point", "")
	if p.begins_with("hand_"):
		tip = p   # a punch: the fist's wrist goes back where it was on this card; a kick's foot hangs off the untouched pelvis
	var acc := Vector2.ZERO
	for k in FIX_TRIES:
		var nm: Array = it["norm"]
		var want := Vector2.ZERO   # (pitch, roll) change at the worst frame
		match String(it["what"]):
			"back":
				want.x = (-float(nm[0]) + FIX_MARGIN) - float(it["pitch"])
			"forward":
				want.x = (float(nm[1]) - FIX_MARGIN) - float(it["pitch"])
			"sideways":
				var r := float(it["roll"])
				var lim := float(nm[2]) - FIX_MARGIN
				var dr := signf(r) * lim - r
				if it["class"] in KICKS and it["side"] == "_l":
					dr = -dr   # roll was said away from a left kick: back to his left / right
				want.y = dr
		acc += want
		Scene.put(B, Moves._flat(orig))
		B.fk()
		var at: Vector3 = B.P[tip] if tip != "" else Vector3.ZERO
		turn(B, acc.x, acc.y, tip, at)
		S.cards[j]["pose"] = B.to_dict()
		var it2 := _again(S, B, f)
		if it2.is_empty():
			break
		if float(it2["over"]) < o1:
			o1 = float(it2["over"])
			best = S.cards[j]["pose"]
		if float(it2["over"]) <= 0.0:
			break
		it = it2
	B.set_state(keep)
	B.fk()
	if not best.is_empty() and o1 <= 0.0:
		S.cards[j]["pose"] = best
		return {"did": "card %d '%s': the spine turned %.0f deg %s%s (spread over its three joints; %s, the feet untouched); now %s" % [
			j + 1, S.cards[j]["name"], acc.length(), "forward" if acc.x > 0.5 else ("back" if acc.x < -0.5 else "upright"),
			"" if absf(acc.y) < 0.5 else " and %.0f deg sideways" % absf(acc.y), "the fist kept on its point" if tip != "" else "the legs not touched",
			"inside the range"], "over0": o0, "over1": o1, "card": j}
	# the spine is not enough: the pelvis takes the rest (pitch only; a roll the spine could not give is not forced)
	var base: Dictionary = best if not best.is_empty() else orig
	var pr := _tilt(S, B, f, it0, orig, base, j) if String(it0["what"]) != "sideways" else {}
	B.set_state(keep)
	B.fk()
	if not pr.is_empty():
		S.cards[j]["pose"] = pr["pose"]
		var it3 := _again(S, B, f)
		if not it3.is_empty() and float(it3["over"]) <= 0.0:
			return {"did": "card %d '%s': the spine turned as far as its limits allow, then the pelvis tilted %.0f deg %s (the legs re-planted: the planted feet on their marks, the kicking foot or fist on its contact point); now inside the range" % [
				j + 1, S.cards[j]["name"], absf(float(pr["tilt"])), "forward" if float(pr["tilt"]) > 0.0 else "back"],
				"over0": o0, "over1": float(it3["over"]), "card": j}
	S.cards[j]["pose"] = orig
	return {"did": "card %d: the spine and the pelvis could not bring the trunk back (their limits; the feet and the contact kept)" % (j + 1), "same": true}


## the pelvis's share: the card `base` (the spine already turned) with the pelvis tilted so the trunk line reaches its
## goal; the planted feet put back on their balls of `orig`, a kicking foot reached back onto its contact point and a
## punching fist onto its point. Returns {"pose", "tilt"} (deg, + forward) or {} when the window is not a pitch one
static func _tilt(S: Scene, B: Body, f: Dictionary, w0: Dictionary, orig: Dictionary, base: Dictionary, j: int) -> Dictionary:
	var nm: Array = w0["norm"]
	var ksd: String = String(w0["side"]) if w0["class"] in KICKS else ""
	var pt: String = String(w0.get("point", ""))
	Scene.put(B, Moves._flat(orig))
	B.fk()
	var at: Vector3 = B.P[pt] if pt != "" else Vector3.ZERO
	var plant_at := {}
	for sd in ["_l", "_r"]:
		if sd == ksd:
			continue
		var ball: Vector3 = B.P["ball" + sd]
		if ball.y < 0.03:   # on the floor on this card
			var d: Vector3 = ball - (B.P["foot" + sd] as Vector3)
			plant_at[sd] = [ball, atan2(d.x, d.z)]
	S.cards[j]["pose"] = base
	var now := _again(S, B, f)
	if now.is_empty():
		return {}
	var want := 0.0
	match String(f["what"]):
		"back":
			want = (-float(nm[0]) + FIX_MARGIN) - float(now["pitch"])
		"forward":
			want = (float(nm[1]) - FIX_MARGIN) - float(now["pitch"])
		_:
			return {}
	# the contact as it PLAYS (the in-between frames carry the tilt too, so the card's own point is not enough): the strike's
	# point at the recognizer's contact frame, before; each pass below moves the reach target by what the played clip missed
	S.cards[j]["pose"] = orig
	var c0 := _contact(S, B, int(w0["card"]))
	var goal := at
	var pose := {}
	for pass_i in 3:
		Scene.put(B, Moves._flat(base))
		B.fk()
		var fr := _frame(B.P["thigh_l"], B.P["thigh_r"])
		B.turn_world("pelvis", Quaternion(fr[0], deg_to_rad(want)))   # the same sense as turn(): + tips the trunk forward
		B.fk()
		for k in 10:
			for sd in plant_at:
				B.plant(sd, plant_at[sd][0], plant_at[sd][1], true)
			if ksd != "":
				var d2: Vector3 = (B.P["ball" + ksd] as Vector3) - (B.P["foot" + ksd] as Vector3)
				B.reach("foot" + ksd, goal - d2)
			elif pt.begins_with("hand_"):
				B.reach(pt, goal)
			B.fk()
		pose = B.to_dict()
		if c0.is_empty() or (ksd == "" and not pt.begins_with("hand_")):
			break
		S.cards[j]["pose"] = pose
		var c1 := _contact(S, B, int(w0["card"]), int(c0["f"]), String(c0["pt"]))
		var miss: Vector3 = (c0["at"] as Vector3) - (c1["at"] as Vector3)
		if miss.length() < CONTACT_TOL:
			break
		goal += miss
	S.cards[j]["pose"] = base
	return {"pose": pose, "tilt": want}


## the strike's contact as it plays: {"f" (frame), "pt" (point name), "at" (world)} for card window k, or {} when the
## recognizer names no strike there. f / pt given: that same frame and point again (after an edit)
static func _contact(S: Scene, B: Body, k: int, f := -1, pt := "") -> Dictionary:
	var keep := B.state()
	var was := S.stepped
	S.stepped = false
	var clip := EventQuery.sample([{"S": S, "B": B, "xf": Transform3D.IDENTITY, "name": String(S.name)}], FPS, {"cross": false, "bal": false})
	S.stepped = was
	var out := {}
	if f < 0:
		var ts := S.times()
		var r := MoveRecognizer.analyze(clip, 0, int(round(float(ts[k][0]) * FPS)), mini(int(round(float(ts[k][2]) * FPS)), int(clip["n"]) - 1))
		if r.get("strike", false) and r.has("frames") and String(r.get("point", "")) != "":
			f = int(r["frames"]["contact"])
			pt = String(r["point"])
	if f >= 0 and pt != "":
		out = {"f": f, "pt": pt, "at": MoveRecognizer._p(clip, 0, f, pt)}
	B.set_state(keep)
	B.fk()
	return out
