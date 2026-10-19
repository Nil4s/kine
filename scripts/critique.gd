## critique.gd - ANIMATION-CRAFT notes that point at frames (ROADMAP 11). Every finding is sev "NOTE" (never MUST FIX), has the
## time it is about and a plain-words fix. Four rules, from the twelve principles (Thomas & Johnston, The Illusion of Life;
## Williams, The Animator's Survival Kit) with bars that are either measured or ours (docs/research/CRITIQUE.md):
##   ANTICIPATION   a fast move (the tip over FAST) with no small move the other way in the 0.1-0.4 s before it
##   FLOATY         both feet off the floor (the lower ankle over the scene's floor) for 0.1 s or more while the
##                  centre of mass falls well short of g
##   FOLLOW-THROUGH the speed drops from half its strike peak to a tenth in fewer than 2 frames: a dead stop
##   EVEN TIMING    the cards have the same length: no rhythm
## Opened only by "Check: critique the animation" (main.gd). The default Check (Rulebook.check) never calls this.
## Findings have the Rulebook shape ({"sev", "t", "card", "rule", "msg", "v"}), so the panel can jump to them.
class_name Critique
extends RefCounted

const FPS := 60.0
const FAST := 3.0          # m/s, ours: a tip this fast is a fast move (the same bar as Rulebook.STRIKE_MIN)
const ANTIC_FROM := 0.4    # s before the fast move: the counter-movement window opens ...
const ANTIC_TO := 0.1      # ... and closes this long before it (Nick's brief: "the 0.1-0.4 s before")
const ANTIC_BACK := 0.03   # m, ours: a part that goes this far the other way in the window counts as a pull-back
const ANTIC_DIR := 0.03    # m, ours: a part whose own move over the swing is shorter has no direction to judge
const FLOAT_AIR := 6       # frames (0.1 s, ours): both feet this long off the floor = in the air
const FLOAT_G := 0.5       # ours: in the air the centre of mass must fall at least half of g
const FLOAT_EASE := 9      # frames (0.15 s, ours): the start of a fall, judged on its own (an ease-in)
const STOP_FRAMES := 2     # frames, ours: half the strike speed down to a tenth in fewer than this = a dead stop
const STOP_LOOK := 30      # frames (0.5 s): how far after the strike the stop is looked for
const EVEN_MIN := 4        # cards after the first: fewer than this is no rhythm to judge
const EVEN_CV := 0.1       # ours: card lengths spread (std / mean) under this = even


## one finding, the Rulebook shape with the severity NOTE
static func _note(t: float, rule: String, msg: String, v := 0.0) -> Dictionary:
	return {"sev": "NOTE", "t": t, "card": -1, "rule": rule, "msg": msg, "v": v}


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()


## ANTICIPATION: for each fast move (Rulebook.strikes on the tip), the 0.1-0.4 s before its start must hold a small move
## the other way: the tip, the hips or the left hand goes back ANTIC_BACK along its own swing direction. None does = a note
## at the start of the move. Reads the raw frames (sm["_raw"]: positions per 60 fps frame)
static func rule_anticipation(sm: Dictionary) -> Array:
	var out := []
	var raw: Array = sm.get("_raw", [])
	if raw.is_empty():
		return out
	for st in Rulebook.strikes(sm["tip"]):
		var pk: int = st["pk"]
		var a: int = st["a"]
		var w0 := maxi(0, a - int(round(ANTIC_FROM * FPS)))
		var w1 := a - int(round(ANTIC_TO * FPS))
		if w1 < w0:
			continue   # the move starts too near the scene's first frame to have a before
		var best := 0.0
		var who := ""
		for part in ["tip", "hips", "hand_l"]:
			var d: Vector3 = (raw[pk][part] as Vector3) - (raw[w0][part] as Vector3)   # the swing's way: from the window's start to the peak (one frame's tangent turns on an arc)
			if d.length() < ANTIC_DIR:
				continue
			var dn := d.normalized()
			var back := 0.0
			for i in range(w0, w1 + 1):
				back = maxf(back, -((raw[i][part] as Vector3) - (raw[w0][part] as Vector3)).dot(dn))
			if back > best:
				best = back
				who = part
		if best < ANTIC_BACK:
			var t: float = a / FPS
			var what := "weapon tip" if raw[a]["wep"] else "hand"
			out.append(_note(t, "ANTICIPATION", "a fast move starts here (the %s at %.1f m/s) with nothing going the other way in the 0.1-0.4 s before it: the %s, the hips and the hand go straight into it. Add a small pull-back about 0.2 s before the swing: the %s goes back a few centimetres first, then swings." % [
				what, sm["tip"][pk], what, what], float(sm["tip"][pk])))
	return out


## FLOATY: a run of FLOAT_AIR frames or more with both feet off the floor. In the air the centre of mass can only fall at g,
## so its vertical acceleration is compared with -g over the whole run and over the first FLOAT_EASE frames (an ease-in
## at the start of a fall). Frames at each end are left out: the take-off and the landing are still on the floor
static func rule_floaty(sm: Dictionary) -> Array:
	var out := []
	var raw: Array = sm.get("_raw", [])
	var n := raw.size()
	var bar := -FLOAT_G * Scene.G
	var ground := INF
	for d in raw:
		ground = minf(ground, float(d["fy"]))   # the lower ankle's lowest point: the floor of this scene
	var i := 0
	while i < n:
		if not _air(raw[i], ground):
			i += 1
			continue
		var s := i
		while i < n and _air(raw[i], ground):
			i += 1
		var e := i - 1
		if e - s + 1 < FLOAT_AIR:
			continue
		var acc := []
		for k in range(s + 1, e):
			acc.append(_accel(raw, k))
		var whole := _mean(acc)
		var head := _mean(acc.slice(0, mini(FLOAT_EASE, acc.size())))
		if whole <= bar and head <= bar:
			continue
		var t: float = s / FPS
		var t1: float = e / FPS
		if whole > bar:
			out.append(_note(t, "FLOATY", "%.2f-%.2f s in the air: the centre of mass falls at only %.1f m/s^2 (gravity is 9.8 m/s^2; with nothing under him in the air he must fall at full pull). He floats. Shorten the air time, or bring the hips down faster." % [
				t, t1, absf(whole)], absf(whole)))
		else:
			out.append(_note(t, "FLOATY", "%.2f s in the air at the start of the fall: the centre of mass drops at only %.1f m/s^2 in its first 0.15 s (gravity is 9.8 m/s^2: a body in the air falls at full pull, so the fall eases in and reads as floating). Start the fall at full speed: move the hips down faster at the take-off, or give the first 0.15 s a fast ease in." % [
				t1 - t, absf(head)], absf(head)))
		out[-1]["t1"] = t1
	return out


## in the air: the lower of the two ankles is over the floor by Rulebook.AIR (the rulebook's own off-the-ground bar; a
## ball of the foot is not used: a body up on its heels with the toes raised is not in the air)
static func _air(d: Dictionary, ground: float) -> bool:
	return float(d["fy"]) > ground + Rulebook.AIR


## the centre of mass's vertical acceleration at frame k (m/s^2, the second difference at 60 fps; positive = up)
static func _accel(raw: Array, k: int) -> float:
	var y0: float = (raw[k]["bal"]["com"] as Vector3).y
	var ym: float = (raw[k - 1]["bal"]["com"] as Vector3).y
	var yp: float = (raw[k + 1]["bal"]["com"] as Vector3).y
	return (yp - 2.0 * y0 + ym) * FPS * FPS


## FOLLOW-THROUGH (a dead stop): after each strike the tip falls from half its peak (the strike's last frame over half)
## to under a tenth of its peak within STOP_FRAMES frames. A decelerating follow-through takes longer than that
static func rule_stop(sm: Dictionary) -> Array:
	var out := []
	var s: Array = sm["tip"]
	for st in Rulebook.strikes(s):
		var pk: int = st["pk"]
		var b: int = st["b"]
		var v: float = s[pk]
		var j := b + 1
		while j < s.size() and j <= b + STOP_LOOK and s[j] >= 0.1 * v:
			j += 1
		if j > b + STOP_LOOK or j >= s.size() or j - b > STOP_FRAMES:
			continue
		var what := "weapon tip" if sm.get("armed", false) else "hand"
		var t: float = b / FPS
		out.append(_note(t, "FOLLOW-THROUGH", "the %s stops dead after the hit: from %.1f m/s to under %.1f m/s in %.0f ms (a real arm carries on and slows over about 0.2 s). Give the strike a slower ease out, or add a follow-through card after the hit, so the %s keeps going and slows." % [
			what, s[b], 0.1 * v, (j - b) * 1000.0 / FPS, what], v))
	return out


## EVEN TIMING: the cards after the first, each card's length (move + hold). Spread under EVEN_CV of the mean = no rhythm
static func rule_even(S: Scene) -> Array:
	var out := []
	var ts := S.times()
	var lens := []
	for i in range(1, ts.size()):
		lens.append(float(ts[i][2]) - float(ts[i][0]))
	if lens.size() < EVEN_MIN:
		return out
	var m := _mean(lens)
	if m <= 0.0:
		return out
	var var_ := 0.0
	for L in lens:
		var_ += (float(L) - m) * (float(L) - m)
	var cv := sqrt(var_ / lens.size()) / m
	if cv >= EVEN_CV:
		return out
	var t: float = ts[1][0]
	out.append(_note(t, "EVEN TIMING", "cards %d-%d all take %.2f s (spread %.0f%%): every move has the same length, so the timing has no rhythm and reads as a machine. Vary it: a quick move into the hit, a slow settle after; change the holds too." % [
		2, ts.size(), m, cv * 100.0], cv))
	return out


## every rule over a scene, sorted by time. sm: a sample already taken (Rulebook.sample); taken here when absent
static func check(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = Rulebook.sample(S, B)
	var out := []
	out += rule_anticipation(sm)
	out += rule_floaty(sm)
	out += rule_stop(sm)
	out += rule_even(S)
	for f in out:
		f["card"] = Rulebook.card_at(S, f["t"])
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out
