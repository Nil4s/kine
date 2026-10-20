## distance_keeper.gd - I18 FIGHT DISTANCE KEEPER. For a scene of two fighters (the attacker's strikes against the defender who stands at xf in
## the attacker's space) it measures, frame by frame, the GAP between the attacker's striking point and the defender's nearest body volume,
## classifies every strike and, per flagged strike, builds the defender's slide that puts it right.
##
## A STRIKE is a contact card of the attacker (BeatFight.contacts: the hit markers, else the strike-named cards); its SPAN runs from the
## start of the move into it to its arrival. The STRIKING POINT is the weapon tip when a weapon is held (Body.wep_point, the point the
## Hits / contact code of Dummy and FrameData use), else the hand or foot whose tip travels farthest from the root (FrameData.STRIKERS);
## the same choice as FrameData's key. The TARGET is the defender's body capsules (Body.cross_caps, the contact code's volumes; his
## weapon is not a target). GAP = distance from the point to the nearest capsule surface (negative inside).
##   REACH      the most the striking point gets from the attacker's root (pelvis) across the floor over the span, MEASURED on the clip.
##   JAMMED     the target is closer to the attacker's root than JAM (60 %) of the reach when the strike starts: the arm cannot extend.
##   OUT OF RANGE  the closest approach of the striking point to the target over the span misses by more than MISS (5 cm).
##   IN RANGE   neither.
## The 60 % and 5 cm are the brief's; the reach is the clip's own, not a table. A punch's reach is bounded by the arm (Winter 2009,
## Biomechanics and Motor Control of Human Movement: arm length is ~0.44 of body height, plus the shoulder's travel).
##
## SLIDE THE DEFENDER (fix): the defender's root moves along the floor line between the two by p metres (toward the attacker when p > 0), done
## before the strike starts: STEP cards are added where he stands still (the hold that contains the strike's start is split; his total time
## is unchanged, so every marker and beat stays where it is): the root eases in and out (smoothstep over the steps, and the cards' own
## ease), the feet take STEPS one at a time (Scene's "steps": the other foot is pinned where it stands, so a planted foot does not slide;
## the stepping foot lifts and lands), at most STEP_MAX (0.25 m, a half-stride: a walking step is 0.415 of body height = 0.7 m, Gait Posture
## 2009 PMID 19502061) of root travel per step. Cards after the slide are carried by the whole distance. With no hold to split (he is moving
## there), the cards in the window are carried by an eased share instead. The attacker is never touched.
class_name DistanceKeeper
extends RefCounted

const JAM := 0.6
const MISS := 0.05
const JAM_AIM := 0.8        # a jammed strike is given room to a gap of this share of its reach
const STEP_MAX := 0.25
const WINDOW := 1.2         # s before the strike the slide may use at most
const MIN_WIN := 0.2        # s: a slide needs at least this much hold to split
const STRIKERS := ["hand_r", "hand_l", "foot_r", "foot_l"]


static func new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## the gap from a point to the nearest body capsule surface (m), floor-plane only when flat
static func gap(p: Vector3, caps: Array, flat := false) -> float:
	var best := INF
	for c in caps:
		if Body.is_wep(String(c[0])):
			continue
		var a: Vector3 = c[1]
		var b: Vector3 = c[2]
		var q := p
		if flat:
			a = _flat(a)
			b = _flat(b)
			q = _flat(p)
		best = minf(best, _seg_dist(q, a, b) - float(c[3]))
	return best


## the strike points of the attacker's body as posed now: {"weapon" (if held), "hand_r", ...}
static func tips(BA: Body) -> Dictionary:
	var out := {}
	if BA.wep_on:
		out["weapon"] = BA.wep_point(BA.wep_len)
	for st in STRIKERS:
		out[st] = BA.E[st]
	return out


## one strike span of attacker card i. {"card", "t0", "t1", "tip", "reach", "root_gap", "miss", "t_min", "cls", "series": [[t, gap]]}
static func span(A: Scene, BA: Body, D: Scene, BD: Body, xf: Transform3D, i: int, fps: int) -> Dictionary:
	var ts := A.times()
	var t0: float = ts[i][0]
	var t1: float = ts[i][1]
	var n := maxi(2, int(ceil((t1 - t0) * fps)) + 1)
	var reach := {}
	var low := {}
	var low_t := {}
	var ser := {}
	var root_gap := 0.0
	for f in n:
		var t := lerpf(t0, t1, float(f) / float(n - 1))
		A.apply(BA, t)
		D.apply(BD, t)
		var caps := BD.cross_caps(xf)
		var root: Vector3 = BA.P["pelvis"]
		if f == 0:
			root_gap = gap(root, caps, true)
		var tp := tips(BA)
		for k in tp:
			var p: Vector3 = tp[k]
			var r := _flat(p - root).length()
			var g := gap(p, caps)
			reach[k] = maxf(float(reach.get(k, 0.0)), r)
			if not low.has(k) or g < float(low[k]):
				low[k] = g
				low_t[k] = t
			if not ser.has(k):
				ser[k] = []
			ser[k].append([t, g])
	var key := "hand_r"
	for k in reach:
		if float(reach[k]) > float(reach.get(key, 0.0)):
			key = k
	var R: float = reach[key]
	var cls := "in"
	if root_gap < JAM * R:
		cls = "jammed"
	elif float(low[key]) > MISS:
		cls = "out"
	return {"card": i, "t0": t0, "t1": t1, "tip": key, "reach": R, "root_gap": root_gap, "miss": float(low[key]), "t_min": float(low_t[key]),
		"cls": cls, "series": ser[key]}


## all the strikes of the attacker A against the defender D (placed at xf in A's space). Leaves nothing posed that matters (own bodies).
## {"ok", "msg", "spans", "flagged"}
static func analyze(A: Scene, D: Scene, xf: Transform3D, fps := 30) -> Dictionary:
	var a := A.clone()
	var d := D.clone()
	var BA := new_body()
	var BD := new_body()
	var spans := []
	var bad := 0
	for i in BeatFight.contacts(a):
		var s := span(a, BA, d, BD, xf, i, fps)
		spans.append(s)
		if s["cls"] != "in":
			bad += 1
	var msg := "no strikes in the attacker's scene" if spans.is_empty() else ("%d strike%s, all in range" % [spans.size(), "" if spans.size() == 1 else "s"] if bad == 0
		else "%d of %d strikes flagged" % [bad, spans.size()])
	return {"ok": not spans.is_empty(), "msg": msg, "spans": spans, "flagged": bad}


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _off(c: Dictionary) -> Vector3:
	var o: Array = c["pose"]["offset"]
	return Vector3(float(o[0]), float(o[1]), float(o[2]))


static func _set_off(c: Dictionary, v: Vector3) -> void:
	c["pose"]["offset"] = [v.x, v.y, v.z]


## the defender's scene with his root slid by p metres along u (the floor line attacker -> defender, in the attacker's space; p > 0 = toward
## the attacker), finished by t_end. A clone; D is not touched.
static func slide_scene(D: Scene, xf: Transform3D, u: Vector3, p: float, t_end: float) -> Scene:
	var S2 := D.clone()
	if absf(p) < 1e-5:
		return S2
	var v: Vector3 = xf.basis.inverse() * (-u * p)   # the defender's own space
	var ts := S2.times()
	var j := -1
	for c in S2.cards.size():
		if float(ts[c][1]) <= t_end + 1e-6 and t_end <= float(ts[c][2]) + 1e-6:
			j = c
	var tw0 := 0.0
	if j >= 0:
		tw0 = maxf(float(ts[j][1]), t_end - WINDOW)
	if j >= 0 and t_end - tw0 >= MIN_WIN:
		var W := t_end - tw0
		var n := maxi(1, int(ceil(absf(p) / STEP_MAX)))
		var m := W / float(n + 1)
		var base: Dictionary = (S2.cards[j] as Dictionary).duplicate(true)
		var base_off := _off(base)
		var rest := float(ts[j][2]) - t_end
		var news := []
		var foot := {"_l": Vector3.ZERO, "_r": Vector3.ZERO}
		var feet := ["_l", "_r"]
		var dk := Vector3.ZERO
		for k in range(1, n + 2):
			var c: Dictionary = base.duplicate(true)
			c.erase("arrive_s")
			c.erase("leave_s")
			var sd: String
			if k <= n:
				dk = v * _smooth(float(k) / float(n))
				sd = feet[(k - 1) % 2]
			else:
				sd = feet[n % 2]
			var step: Vector3 = dk - (foot[sd] as Vector3)
			foot[sd] = dk
			_set_off(c, base_off + dk)
			c["name"] = "slide %d" % k
			c["move"] = m
			c["hold"] = rest if k == n + 1 else 0.0
			c["steps"] = {sd: [step.x, step.y, step.z]}
			news.append(c)
		(S2.cards[j] as Dictionary)["hold"] = tw0 - float(ts[j][1])
		for c in range(S2.cards.size() - 1, j, -1):
			_set_off(S2.cards[c], _off(S2.cards[c]) + v)
		for k in news.size():
			S2.cards.insert(j + 1 + k, news[k])
		return S2
	# no hold to split: the cards in the window carry an eased share, the cards after it the whole
	var w0 := maxf(0.0, t_end - WINDOW)
	var Wd := maxf(0.1, t_end - w0)
	var prev := 0.0
	for c in range(1, S2.cards.size()):
		var wt := _smooth((float(ts[c][1]) - w0) / Wd)
		if wt <= 0.0:
			continue
		_set_off(S2.cards[c], _off(S2.cards[c]) + v * wt)
		if wt > prev and wt < 1.0:
			var sd2: Vector3 = v * (wt - prev)
			(S2.cards[c] as Dictionary)["steps"] = {"_l": [sd2.x, sd2.y, sd2.z]} if c % 2 == 0 else {"_r": [sd2.x, sd2.y, sd2.z]}
		prev = wt
	return S2


## the fix for strike k of A's report against D: {"ok", "why", "scene" (D with the slide), "p" (m, + toward the attacker), "k", "span", "after" (the span measured again), "msg"}
static func fix(A: Scene, D: Scene, xf: Transform3D, fps: int, k: int, rep: Dictionary = {}) -> Dictionary:
	if rep.is_empty():
		rep = analyze(A, D, xf, fps)
	var spans: Array = rep["spans"]
	if k < 0 or k >= spans.size():
		return {"ok": false, "why": "pick a flagged strike in the list first"}
	var sp: Dictionary = spans[k]
	if sp["cls"] == "in":
		return {"ok": false, "why": "that strike is in range already: nothing to slide"}
	var a := A.clone()
	var BA := new_body()
	var BD := new_body()
	var t0: float = sp["t0"]
	a.apply(BA, t0)
	D.clone().apply(BD, t0)
	var ra: Vector3 = _flat(BA.P["pelvis"])
	var rd: Vector3 = _flat(xf * (BD.P["pelvis"] as Vector3))
	var u := rd - ra
	if u.length() < 1e-4:
		return {"ok": false, "why": "the fighters stand on the same spot: move one of them first (Actor: place)"}
	u = u.normalized()
	var p := 0.0
	var res := {}
	if sp["cls"] == "jammed":
		p = float(sp["root_gap"]) - JAM_AIM * float(sp["reach"])
		res = span(a, BA, slide_scene(D, xf, u, p, t0), BD, xf, int(sp["card"]), fps)
	else:
		for it in 6:
			var sc := slide_scene(D, xf, u, p, t0)
			res = span(a, BA, sc, BD, xf, int(sp["card"]), fps)
			if absf(float(res["miss"])) < 0.004:
				break
			p += float(res["miss"])
	var sc2 := slide_scene(D, xf, u, p, t0)
	res = span(a, BA, sc2, BD, xf, int(sp["card"]), fps)
	return {"ok": true, "why": "", "scene": sc2, "p": p, "k": k, "span": sp, "after": res, "u": u,
		"msg": "slide the defender %.0f cm %s the attacker before %.2f s" % [absf(p) * 100.0, "toward" if p > 0.0 else "away from", t0]}
