## inbetween.gd - PUSH / RELAX / BLEND (round 41, GATES WW3, UPGRADES #279 + #280). Blender's Pose Mode in-betweens
## (manual: animation/in_betweens.rst): Push From Breakdown, Relax To Breakdown, Blend To Neighbour, Blend To Rest.
## The picked card's two neighbours give a "breakdown" pose (their halfway mix, the same Scene.mix_flat the tween
## slider uses). Per joint angle p, with m the breakdown angle and f the factor:
##   PUSH  p + f (p - m)   away from the breakdown (exaggerates the pose)
##   RELAX p + f (m - p)   toward it
##   BLEND TO REST  p + f (0 - p)           toward the straight pose
##   BLEND TO NEIGHBOUR  p + f (n - p)      toward the card before or after
## The hips' turn (pelvis twist) takes the short way round, as the tween does. Every result goes through the body's
## own set_ang (clamp_ang), so no angle is ever written past a joint's limit; a value the limit stopped is REPORTED.
## Logic only: main.gd checks, pushes the one undo step and refreshes. No window needed.
class_name Inbetween

const FACTOR := 0.25   # one press (Blender's default blend is 0.5; a quarter is a nudge you can repeat)
const OPS := ["push", "relax", "rest", "prev", "next"]
const AXES := ["bend", "side", "twist"]


## "" if op can run on card k of S, else why not (nothing is touched)
static func refuse(S: Scene, k: int, op: String) -> String:
	var n := S.cards.size()
	if k < 0 or k >= n:
		return "pick a card first"
	if op == "push" or op == "relax":
		if k <= 0 or k >= n - 1:
			return "%s needs a card with a card before it and after it (the first and last cards have no breakdown)" % op
	elif op == "prev" and k <= 0:
		return "there is no card before this one"
	elif op == "next" and k >= n - 1:
		return "there is no card after this one"
	return ""


## the joints an op works on: the group's body parts if more than one part is selected, else the whole body
static func joints_for(B: Body, group: Array) -> Array:
	if group.size() > 1:
		return group.filter(func(j): return B.ang.has(j))
	return B.ang.keys()


## run op on the body B (its current angles are p) for card k of S. joints = the parts to move ([] = all).
## Returns {"ok", "why", "n" joints moved, "max" biggest change in degrees, "stopped": [{joint, axis, wanted, got}]}
static func run(B: Body, S: Scene, k: int, op: String, f: float, joints: Array) -> Dictionary:
	var why := refuse(S, k, op)
	if why != "":
		return {"ok": false, "why": why, "n": 0, "max": 0.0, "stopped": []}
	var tgt := {}   # joint -> Vector3, where p is heading (push goes the other way, by the dir of f)
	var dir := 1.0
	match op:
		"push", "relax":
			var a := Moves._flat(S.cards[k - 1]["pose"])
			var b := Moves._flat(S.cards[k + 1]["pose"])
			tgt = Scene.mix_flat(a, b, 0.5)["ang"]
			if op == "push":
				dir = -1.0
		"prev":
			tgt = Moves._flat(S.cards[k - 1]["pose"])["ang"]
		"next":
			tgt = Moves._flat(S.cards[k + 1]["pose"])["ang"]
	var js := joints if not joints.is_empty() else B.ang.keys()
	var stopped := []
	var n := 0
	var worst := 0.0
	var before := {}
	for j in js:
		if B.ang.has(j):
			before[j] = B.ang[j]
	for j in before:
		var p: Vector3 = before[j]
		var m: Vector3 = Vector3.ZERO if op == "rest" else (tgt[j] if tgt.has(j) else p)
		var want: Vector3 = p + Scene._d(p, m, j) * (f * dir)
		if j == "pelvis":
			want.z = wrapf(want.z, -180.0, 180.0)
		B.set_ang(j, want)
		var got: Vector3 = B.ang[j]
		for c in 3:
			var r: Vector2 = B.lim[j][AXES[c]]
			if r.y - r.x > 0.5 and absf(got[c] - want[c]) > 0.5:   # a locked axis is not a stop
				stopped.append({"joint": j, "axis": AXES[c], "wanted": want[c], "got": got[c]})
		var d := (got - p).abs()
		worst = maxf(worst, maxf(d.x, maxf(d.y, d.z)))
		if d.length() > 1e-6:
			n += 1
	return {"ok": true, "why": "", "n": n, "max": worst, "stopped": stopped}


## one line for the say-bar
static func describe(op: String, f: float, r: Dictionary, scope: String) -> String:
	if not r["ok"]:
		return "%s: %s" % [op, r["why"]]
	var s := "%s %d%% on %s: %d joints moved, biggest change %.1f deg" % [op, round(f * 100.0), scope, r["n"], r["max"]]
	var st: Array = r["stopped"]
	if not st.is_empty():
		var e: Dictionary = st[0]
		s += ".  STOPPED at a limit: %d angle%s (%s %s wanted %.1f, stopped at %.1f)" % [st.size(), "" if st.size() == 1 else "s", e["joint"], e["axis"], e["wanted"], e["got"]]
	return s
