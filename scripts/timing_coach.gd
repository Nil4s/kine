## timing_coach.gd - TIMING COACH (ROADMAP I4). For each strike in the scene it suggests a better move time and says WHY,
## from two kinds of evidence:
##   (1) REAL MOTION: the move database (MotionMatch.build: scenes/ and moves/, read only). For the pose pair the card
##       goes between, each clip is searched for the frame that looks like the first pose and the later frame that looks
##       like the second; the frames between them are how long that transition took there.
##   (2) PRINCIPLES with numbers:
##       STRIKE SIZE   a fist travelling d metres takes d / v_mean. Fist speeds recorded: 7.1 +- 0.5 m/s (MEAN fist speed over the
##                     last 10 ms before impact, MMA swing punch, 21 elite men, Sensors 2025, 25(11):3270, sec. 3.2) to PEAK 11.95 +- 1.84 m/s (lead hook, amateur boxers, Stanley et al. 2018, Int J Perf
##                     Anal Sport). A reaching movement's speed is a bell with peak = 1.875 x mean (minimum jerk, Flash & Hogan
##                     1985), so the mean speed is 3.8 .. 6.4 m/s: a 0.6 m punch takes 0.09 .. 0.16 s.
##       WEAPON        a held weapon slows the swing by (I / I_bat)^0.27 (Cross & Bower 2006; weight_feel.gd).
##       RATIO         the action is shorter than its anticipation: Thomas & Johnston, The Illusion of Life (1981), ch. "Anticipation"
##                     and Williams, The Animator's Survival Kit (2001), "Anticipation": a fast hit is a short action after a
##                     longer wind-up. ANTIC_RATIO = 2 is OURS (the books give the order, not a number).
##       FOLLOW-THROUGH  after the hit the limb settles more slowly than it struck (slow-out, the books' follow-through and overlap);
##                     SETTLE_RATIO = 1.5 is OURS.
## Read only: compute() returns suggestions; accept() writes ONE card field on the scene it is given.
class_name TimingCoach
extends RefCounted

const V_PEAK_LO := 7.1       # m/s: slowest recorded fist speed (MMA swing punch, a 10 ms pre-impact MEAN, not a peak: Sensors 2025 sec. 3.2)
const V_PEAK_HI := 11.95     # m/s: fastest (lead hook, Stanley 2018)
const PEAK_OVER_MEAN := 1.875   # minimum-jerk bell (Flash & Hogan 1985)
const ANTIC_RATIO := 2.0     # ours: the action is at most this fraction (1/2) of the wind-up that precedes it
const SETTLE_RATIO := 1.5    # ours: the follow-through move takes at least this many times the strike
const MIN_TRAVEL := 0.35     # m: a hand that moves less than this is not striking
const MIN_MOVE := 0.04       # s: no move shorter (Scene.retime)
const TOL := 0.005           # s: a time within this of the range counts as inside
const MATCH_TOL := 22.0      # deg RMS over the moving joints: how close a clip's pose must be to count as "the same pose"
const MOVERS := 8
const MOVER_MIN := 8.0       # deg: a joint that turns less between the two poses does not identify the move
const LOOK := 1.2            # s: the second pose is looked for this long after the first
const STRIKE_WORDS := ["strike", "hit", "contact", "punch", "jab", "cross", "hook", "uppercut", "kick", "slash", "swing", "thrust", "stab", "smash"]


static func peak_range(d: float, f := 1.0) -> Array:
	return [d / (V_PEAK_HI / PEAK_OVER_MEAN) * f, d / (V_PEAK_LO / PEAK_OVER_MEAN) * f]   # [fastest, slowest] seconds


static func is_strike(S: Scene, i: int) -> bool:
	if i < 1:
		return false
	var nm := String(S.cards[i]["name"]).to_lower()
	for w in STRIKE_WORDS:
		if nm.contains(w):
			return true
	var ts := S.times()
	for mk in S.markers:
		if String(mk["kind"]) == "hit" and absf(float(mk["t"]) - float(ts[i][1])) < 0.02:
			return true
	return false


static func _angles(B: Body) -> PackedVector3Array:
	var a := PackedVector3Array()
	for j in Body.ORDER:
		a.append(B.ang.get(j, Vector3.ZERO))
	return a


## the hand that travels furthest between two times: [metres, side]
static func _travel(S: Scene, B: Body, t0: float, t1: float) -> Array:
	S.apply(B, t0)
	B.fk()
	var l0: Vector3 = B.P["hand_l"]
	var r0: Vector3 = B.P["hand_r"]
	var a0 := _angles(B)
	S.apply(B, t1)
	B.fk()
	var dl := l0.distance_to(B.P["hand_l"])
	var dr := r0.distance_to(B.P["hand_r"])
	return [maxf(dl, dr), "l" if dl >= dr else "r", a0, _angles(B)]


## how long clips of `db` took to go from pose a to pose b (joint angles, Body.ORDER): {"n", "best": {clip, dur, cost}, "median"} or {}
static func real_time(db: Dictionary, a: PackedVector3Array, b: PackedVector3Array, exclude := "") -> Dictionary:
	if int(db.get("n", 0)) == 0:
		return {}
	var nj: int = Body.ORDER.size()
	var diffs := []
	for j in nj:
		var d := (b[j] - a[j]).abs()
		var m := maxf(d.x, maxf(d.y, d.z))
		if m >= MOVER_MIN and j < 22:   # the body's joints, not the fingers
			diffs.append([m, j])
	diffs.sort_custom(func(x, y): return x[0] > y[0])
	var mv := []
	for k in mini(MOVERS, diffs.size()):
		mv.append(diffs[k][1])
	if mv.is_empty():
		return {}
	var ang: PackedVector3Array = db["ang"]
	var found := []
	for ci in (db["clips"] as Array).size():
		var c: Dictionary = db["clips"][ci]
		if exclude != "" and String(c["name"]) == exclude:
			continue
		var n: int = c["n"]
		var first: int = c["first"]
		var ca := PackedFloat32Array()
		var cb := PackedFloat32Array()
		ca.resize(n)
		cb.resize(n)
		for f in n:
			var base := (first + f) * nj
			var sa := 0.0
			var sb := 0.0
			for j in mv:
				var v: Vector3 = ang[base + j]
				sa += (v - a[j]).length_squared()
				sb += (v - b[j]).length_squared()
			ca[f] = sqrt(sa / (3.0 * mv.size()))
			cb[f] = sqrt(sb / (3.0 * mv.size()))
		var fa := 0
		for f in n:
			if ca[f] < ca[fa]:
				fa = f
		if ca[fa] > MATCH_TOL:
			continue
		while fa + 1 < n and ca[fa + 1] <= ca[fa] + 1.5:
			fa += 1   # still in the first pose: the move starts where it is left
		var fps: float = c["fps"]
		var hi := mini(n - 1, fa + int(LOOK * fps))
		var fb := fa + 1
		for f in range(fa + 1, hi + 1):
			if cb[f] < cb[fb]:
				fb = f
		if fb >= n or cb[fb] > MATCH_TOL:
			continue
		for f in range(fa + 1, fb + 1):
			if cb[f] <= cb[fb] + 1.5:
				fb = f
				break
		if fb - fa < 2 or ca[fa] > cb[fb] * 3.0 + MATCH_TOL:
			continue
		found.append({"clip": String(c["name"]), "dur": float(fb - fa) / fps, "cost": ca[fa] + cb[fb]})
	if found.is_empty():
		return {}
	found.sort_custom(func(x, y): return x["cost"] < y["cost"])
	var durs := found.map(func(x): return x["dur"])
	durs.sort()
	return {"n": found.size(), "best": found[0], "median": durs[durs.size() / 2], "all": found}


static func _fmt(s: float) -> String:
	return "%.2f s" % s


## the suggestions for scene S (read only; B is posed on the way and left wherever the last sample put it).
## [{"card", "field": "move", "kind": "STRIKE" | "FOLLOW-THROUGH", "from", "to", "range": [lo, hi], "real": {...}, "reason"}]
static func compute(S: Scene, B: Body, db: Dictionary, exclude := "") -> Array:
	var keep := FrameMemo.suspend_slicing()   # a plain call never waits for a frame
	var r: Array = compute_co.call(S, B, db, exclude)
	FrameMemo.resume_slicing(keep)
	return r


## compute() in slices: the strikes are read a few per frame while FrameMemo slicing is on (the Timing coach button), [] when cancelled
static func compute_co(S: Scene, B: Body, db: Dictionary, exclude := "") -> Array:
	var out := []
	var ts := S.times()
	var ref_i := float(WeightFeel.inertia(B, WeightFeel.REF_KIND)["i"])
	var strike_to := {}
	for i in range(1, S.cards.size()):
		if not await FrameMemo.pump(float(i) / float(S.cards.size())):
			return []
		if not is_strike(S, i):
			continue
		var cur := S.move_time(i)
		var tr := _travel(S, B, float(ts[i - 1][2]), float(ts[i][1]))
		var d: float = tr[0]
		if d < MIN_TRAVEL:
			continue
		var kind := WeightFeel.kind_at(S, i, B)
		var f := 1.0
		var wtxt := ""
		if kind != "":
			var inr := WeightFeel.inertia(B, kind)
			if not inr.is_empty():
				f = pow(float(inr["i"]) / ref_i, WeightFeel.N)
				wtxt = ", x%.2f for the %s (Cross & Bower 2006)" % [f, kind]
		var rng := peak_range(d, f)
		var lo: float = rng[0]
		var hi_cited: float = rng[1]
		var hi := hi_cited
		var ratio_txt := ""
		if i - 1 >= 1:
			var antic := S.move_time(i - 1)
			var cap := maxf(lo, antic / ANTIC_RATIO)
			if cap < hi:
				hi = cap
				ratio_txt = "; the wind-up before it takes %s and the action should be at most 1/%d of it (Thomas & Johnston; Williams)" % [_fmt(antic), int(ANTIC_RATIO)]
		var real := real_time(db, tr[2], tr[3], exclude)
		var to := cur
		var why := ""
		if cur > hi + TOL:
			to = hi
			if not real.is_empty() and float(real["best"]["dur"]) >= lo and float(real["best"]["dur"]) <= hi:
				to = float(real["best"]["dur"])
			why = "too slow for a %s strike" % Units.len(d)
		elif cur < lo - TOL:
			to = lo
			ratio_txt = ""
			why = "faster than any recorded punch of %s" % Units.len(d)
		else:
			strike_to[i] = cur
			continue
		to = snappedf(maxf(MIN_MOVE, to), 0.001)
		var rtxt := "no clip in your scenes goes between these two poses"
		if not real.is_empty():
			rtxt = "real clip '%s' does this in %s%s" % [real["best"]["clip"], _fmt(float(real["best"]["dur"])),
				"" if int(real["n"]) < 2 else " (%d clips, median %s)" % [real["n"], _fmt(float(real["median"]))]]
		strike_to[i] = to
		out.append({"card": i, "field": "move", "kind": "STRIKE", "from": snappedf(cur, 0.001), "to": to, "range": [lo, hi], "cited": [lo, hi_cited], "real": real,
			"reason": "card %d move %s -> %s: %s. %s; strikes this size take %.2f-%.2f s (fist %.1f-%.1f m/s peak, Sensors 2025 / Stanley 2018, bell profile x%.3f%s%s)" % [
				i + 1, _fmt(cur), _fmt(to), why, rtxt, lo, hi_cited, V_PEAK_LO, V_PEAK_HI, PEAK_OVER_MEAN, wtxt, ratio_txt]})
	for i in strike_to.keys():
		var k: int = i + 1
		if not await FrameMemo.pump(0.95):
			return []
		if k >= S.cards.size():
			continue
		var cur := S.move_time(k)
		var need := snappedf(SETTLE_RATIO * float(strike_to[i]), 0.001)
		if cur >= need - TOL:
			continue
		var tr := _travel(S, B, float(ts[k - 1][2]), float(ts[k][1]))
		var real := real_time(db, tr[2], tr[3], exclude)
		var rtxt := ""
		if not real.is_empty():
			rtxt = "real clip '%s' takes %s for this settle. " % [real["best"]["clip"], _fmt(float(real["best"]["dur"]))]
		out.append({"card": k, "field": "move", "kind": "FOLLOW-THROUGH", "from": snappedf(cur, 0.001), "to": need, "range": [need, need], "real": real,
			"reason": "card %d move %s -> %s: the settle after the hit is shorter than %.1fx the strike (%s). %sA limb eases out slower than it struck (follow-through: Thomas & Johnston; Williams; ratio ours)" % [
				k + 1, _fmt(cur), _fmt(need), SETTLE_RATIO, _fmt(float(strike_to[i])), rtxt]})
	out.sort_custom(func(x, y): return int(x["card"]) < int(y["card"]))
	return out


## write ONE suggestion on scene S (the caller makes the undo step). Returns the card index, or -1
static func accept(S: Scene, s: Dictionary) -> int:
	var i: int = s["card"]
	if i < 1 or i >= S.cards.size():
		return -1
	S.cards[i][String(s["field"])] = float(s["to"])
	return i


## a copy of S with the suggestions applied (the preview plays it; S is not touched)
static func with_applied(S: Scene, sugs: Array) -> Scene:
	var c := S.clone()
	for s in sugs:
		accept(c, s)
	return c
