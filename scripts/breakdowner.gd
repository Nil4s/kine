## breakdowner.gd - BREAKDOWNER and PASTE FLIPPED WITH OPTIONS (round 42, GATES XX4, UPGRADES #278 + #282).
## BREAKDOWNER (Blender's Pose Breakdowner, Shift+E): the picked card's pose becomes the per-joint SLERP between the
## card before (factor 0) and the card after (factor 1). Each joint's three angles are turned into the joint's
## rotation (Body.compose), the two rotations are slerped, and the result is split back (Body.decompose) and clamped
## by the body's own set_ang. Factors past the ends overshoot, from -0.5 to 1.5. With more than one part selected,
## only those parts move; every other joint is left bit for bit as it was.
## PASTE FLIPPED, with options: the copied pose reflected left <-> right (Body.pose_paste), on the selected parts only
## and/or at a factor 0..1 (current pose -> flipped pose, slerped per joint). Factor 1 on all parts is the old paste.
## A factor under 1 moves angles only (the hips' offset and the weapon come with a full-strength paste).
## Logic only: main.gd checks, pushes the one undo step and refreshes. No window needed.
class_name Breakdowner

const MIN_F := -0.5
const MAX_F := 1.5
const PRESETS := [0.25, 0.5, 0.75]
const AXES := ["bend", "side", "twist"]


## "" if card k of S can be broken down, else why not (nothing is touched)
static func refuse(S: Scene, k: int) -> String:
	var n := S.cards.size()
	if k < 0 or k >= n:
		return "pick a card first"
	if k <= 0 or k >= n - 1:
		return "the breakdowner needs a card with a card before it and after it"
	return ""


## the joint's angles after turning from a to b by fraction f of the way (slerp; f outside 0..1 overshoots)
static func slerp_ang(B: Body, j: String, a: Vector3, b: Vector3, f: float) -> Vector3:
	var qa := B.compose(j, a)
	var qb := B.compose(j, b)
	return B.decompose(j, qa.slerp(qb, f))


## set the picked card k's pose on body B to the slerp of its neighbours at factor f. joints = parts to move ([] = all).
## Returns {"ok", "why", "n", "max", "stopped": [{joint, axis, wanted, got}]}
static func run(B: Body, S: Scene, k: int, f: float, joints: Array) -> Dictionary:
	var why := refuse(S, k)
	if why != "":
		return {"ok": false, "why": why, "n": 0, "max": 0.0, "stopped": []}
	f = clampf(f, MIN_F, MAX_F)
	var a: Dictionary = Moves._flat(S.cards[k - 1]["pose"])["ang"]
	var b: Dictionary = Moves._flat(S.cards[k + 1]["pose"])["ang"]
	var js := joints if not joints.is_empty() else B.ang.keys()
	var stopped := []
	var n := 0
	var worst := 0.0
	for j in js:
		if not (B.ang.has(j) and a.has(j) and b.has(j)):
			continue
		var p: Vector3 = B.ang[j]
		var want := slerp_ang(B, j, a[j], b[j], f)
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


static func describe(f: float, r: Dictionary, scope: String) -> String:
	if not r["ok"]:
		return "breakdowner: %s" % r["why"]
	var s := "breakdowner %d%%%s on %s: %d joints moved, biggest change %.1f deg" % [round(f * 100.0), " (overshoot)" if f < 0.0 or f > 1.0 else "", scope, r["n"], r["max"]]
	var st: Array = r["stopped"]
	if not st.is_empty():
		var e: Dictionary = st[0]
		s += ".  STOPPED at a limit: %d angle%s (%s %s wanted %.1f, stopped at %.1f)" % [st.size(), "" if st.size() == 1 else "s", e["joint"], e["axis"], e["wanted"], e["got"]]
	return s


## paste the copied pose `clip` reflected (flipped) or not onto body B. joints = parts to paste on ([] = all).
## f = 1 and all parts is exactly Body.pose_paste; f < 1 slerps each joint from where it is now toward the pasted
## angle (angles only); f = 0 changes nothing. Returns the number of joints that moved.
static func paste(B: Body, clip: Dictionary, flipped: bool, joints: Array, f: float) -> int:
	f = clampf(f, 0.0, 1.0)
	if f <= 0.0:
		return 0
	var before := {}
	for j in B.ang:
		before[j] = B.ang[j]
	if f >= 1.0:
		B.pose_paste(clip, flipped, joints)
	else:
		var only: Array = joints if not joints.is_empty() else Body.ORDER.duplicate()
		B.pose_paste(clip, flipped, only)   # B now holds the target; blend back from where it was
		for j in only:
			B.ang[j] = B.clamp_ang(j, slerp_ang(B, j, before[j], B.ang[j], f))
		B.fk()
	var n := 0
	for j in B.ang:
		if (B.ang[j] - before[j]).length() > 1e-6:
			n += 1
	return n
