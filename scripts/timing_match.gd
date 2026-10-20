## MATCH THE REFERENCE'S TIMING (ROADMAP I29). Pure data, no UI: timing_match_ui.gd wraps it in a panel and one undo step.
## A reference (a tracked video clip, opened as a Scene) and the open clip are each reduced to a LIMB-SPEED CURVE: the sum of the
## speeds of the end effectors (both hands, both feet's balls), sampled at 60 Hz and smoothed with a 50 ms box (a strike's
## acceleration phase lasts 100-300 ms, so 50 ms keeps its peak and drops tracker jitter). Its EVENTS: peaks ("P": a
## strike, an action) and the lowest point between two peaks ("M": a hold or an extreme). The two event sequences are aligned
## by dynamic programming (monotone, like DTW but an event may be skipped on either side): kinds must agree, a match costs
## the time gap, a skip costs SKIP seconds. The cards are retimed on the piecewise-linear map clip time -> reference time through the
## matched events (a shift after the last). Poses are never touched: only move / hold change.
class_name TimingMatch
extends RefCounted

const HZ := 60.0
const SMOOTH := 0.05      # s: box filter width
const PROM := 0.12        # a peak must stand this fraction of the curve's maximum above its surrounding valleys
const SKIP := 0.45        # s: the price of leaving an event unmatched
const MIN_MOVE := 0.04
const EFFECTORS := ["hand_l", "hand_r", "ball_l", "ball_r"]


## {"t": PackedFloat32Array, "v": PackedFloat32Array (m/s)}
static func speed_curve(S: Scene, B: Body) -> Dictionary:
	var n := maxi(2, int(ceil(S.length() * HZ)) + 1)
	var pts: Array = []
	var keep := B.state()
	for i in n:
		S.apply(B, minf(float(i) / HZ, S.length()))
		B.fk()
		var row := PackedVector3Array()
		for j in EFFECTORS:
			row.append(B.P[j])
		pts.append(row)
	B.set_state(keep)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a: PackedVector3Array = pts[maxi(i - 1, 0)]
		var b: PackedVector3Array = pts[mini(i + 1, n - 1)]
		var dt := float(mini(i + 1, n - 1) - maxi(i - 1, 0)) / HZ
		var s := 0.0
		for k in a.size():
			s += a[k].distance_to(b[k]) / maxf(dt, 1e-6)
		raw[i] = s
	var w := maxi(1, roundi(SMOOTH * HZ))
	var v := PackedFloat32Array()
	var t := PackedFloat32Array()
	v.resize(n)
	t.resize(n)
	for i in n:
		var acc := 0.0
		var c := 0
		for k in range(i - w / 2, i - w / 2 + w + 1):
			if k >= 0 and k < n:
				acc += raw[k]
				c += 1
		v[i] = acc / float(maxi(c, 1))
		t[i] = float(i) / HZ
	return {"t": t, "v": v}


## [{"t", "kind": "P" | "M", "v"}] ascending. Peaks need PROM x max prominence; a valley is the lowest sample between two peaks
static func events(curve: Dictionary) -> Array:
	var v: PackedFloat32Array = curve["v"]
	var t: PackedFloat32Array = curve["t"]
	var n := v.size()
	var vmax := 0.0
	for x in v:
		vmax = maxf(vmax, x)
	var out := []
	if vmax <= 1e-6:
		return out
	var peaks := []
	for i in range(1, n - 1):
		if not (v[i] > v[i - 1] and v[i] >= v[i + 1]):
			continue
		# prominence: the drop to the higher of the two lowest points reached before a higher sample on each side
		var lo_l := v[i]
		var k := i - 1
		while k >= 0 and v[k] <= v[i]:
			lo_l = minf(lo_l, v[k])
			k -= 1
		var lo_r := v[i]
		k = i + 1
		while k < n and v[k] <= v[i]:
			lo_r = minf(lo_r, v[k])
			k += 1
		if v[i] - maxf(lo_l, lo_r) >= PROM * vmax:
			peaks.append(i)
	for pi in peaks.size():
		var i: int = peaks[pi]
		out.append({"t": float(t[i]), "kind": "P", "v": float(v[i])})
		if pi + 1 < peaks.size():
			var j: int = peaks[pi + 1]
			var lo := i
			for k in range(i, j + 1):
				if v[k] < v[lo]:
					lo = k
			out.append({"t": float(t[lo]), "kind": "M", "v": float(v[lo])})
	return out


## monotone alignment of two event lists. A match is judged on the CHANGE of offset (ref time - clip time) from the previous match, so a
## clip that runs late by a steady amount, or a reference with an extra action that pushes everything after it, costs only the jump
## at that place; a left-out event on either side costs SKIP. Kinds must agree. The first match pays 0.3 x its offset (a lead-in is
## cheap but not free); a gap between two matches may leave out up to MAXRUN events on each side. O(n m MAXRUN^2).
## Returns {"pairs": [[ic, ir]...], "skip_clip": [ic...], "skip_ref": [ir...]}
const MAXRUN := 8
const LEAD := 0.3


static func align(ec: Array, er: Array) -> Dictionary:
	var n := ec.size()
	var m := er.size()
	var D := {}      # i * (m + 1) + j -> best cost of an alignment whose LAST match is (i, j)
	var P := {}      # ... and the previous match's key (-1 = none)
	var best_end := n + m + 0.0
	best_end *= SKIP
	var best_key := -1
	for i in n:
		for j in m:
			if ec[i]["kind"] != er[j]["kind"]:
				continue
			var off := float(er[j]["t"]) - float(ec[i]["t"])
			var key := i * (m + 1) + j
			var cost: float = SKIP * float(i + j) + LEAD * absf(off)
			var prev := -1
			for i2 in range(maxi(0, i - 1 - MAXRUN), i):
				for j2 in range(maxi(0, j - 1 - MAXRUN), j):
					var k2 := i2 * (m + 1) + j2
					if not D.has(k2):
						continue
					var off2 := float(er[j2]["t"]) - float(ec[i2]["t"])
					var c: float = float(D[k2]) + SKIP * float((i - i2 - 1) + (j - j2 - 1)) + absf(off - off2)
					if c < cost:
						cost = c
						prev = k2
			D[key] = cost
			P[key] = prev
			var tot: float = cost + SKIP * float((n - 1 - i) + (m - 1 - j))
			if tot < best_end:
				best_end = tot
				best_key = key
	var pairs := []
	var k := best_key
	while k >= 0:
		pairs.push_front([k / (m + 1), k % (m + 1)])
		k = int(P[k])
	var used_c := {}
	var used_r := {}
	for p in pairs:
		used_c[p[0]] = true
		used_r[p[1]] = true
	var sc := []
	var sr := []
	for i in n:
		if not used_c.has(i):
			sc.append(i)
	for j in m:
		if not used_r.has(j):
			sr.append(j)
	return {"pairs": pairs, "skip_clip": sc, "skip_ref": sr}


## the anchors [[clip t, ref t]...] of the matched pairs, strictly increasing on both sides
static func anchors(ec: Array, er: Array, al: Dictionary) -> Array:
	var out := []
	for p in al["pairs"]:
		var a := [float(ec[p[0]]["t"]), float(er[p[1]]["t"])]
		if out.is_empty() or (a[0] > out[-1][0] + 0.02 and a[1] > out[-1][1] + 0.02):
			out.append(a)
	return out


## clip time -> new time through the anchors: 0 stays 0, between anchors linear, after the last a shift
static func warp(t: float, anc: Array) -> float:
	if anc.is_empty():
		return t
	var prev := [0.0, 0.0]
	for a in anc:
		if t <= a[0]:
			var u: float = (t - float(prev[0])) / maxf(float(a[0]) - float(prev[0]), 1e-9)
			return float(prev[1]) + u * (float(a[1]) - float(prev[1]))
		prev = a
	return t + float(prev[1]) - float(prev[0])


## the retimed cards (a new array; poses are copies, untouched). Cumulative so rounding never drifts
static func retimed_cards(S: Scene, anc: Array) -> Array:
	var ts := S.times()
	var out := S.cards.duplicate(true)
	var prev_end := 0.0
	for i in out.size():
		var a := snappedf(warp(float(ts[i][1]), anc), 0.001)
		var e := snappedf(warp(float(ts[i][2]), anc), 0.001)
		var mv := 0.0
		if i > 0:
			mv = maxf(MIN_MOVE, snappedf(a - prev_end, 0.001))
		var hold := maxf(0.0, snappedf(e - (prev_end + mv), 0.001))
		out[i]["move"] = mv
		out[i]["hold"] = hold
		prev_end = prev_end + mv + hold
	return out


## the same map on everything else the scene times (part keys, IK, layers, props, markers, plants), in place
static func warp_others(S: Scene, anc: Array, markers := true) -> void:
	for j in S.part_keys:
		for key in S.part_keys[j]:
			key["t"] = warp(float(key["t"]), anc)
	for j in S.ik:
		for key in S.ik[j]:
			key["t"] = warp(float(key["t"]), anc)
	for L in S.layers:
		for kv in L.get("wk", []):
			kv[0] = warp(float(kv[0]), anc)
	for pr in S.props:
		for key in pr.get("keys", []):
			key["t"] = warp(float(key["t"]), anc)
	if markers:   # main passes false: its Markers.remap rides them with the card times instead
		for d in S.markers:
			d["t"] = warp(float(d["t"]), anc)
	for pl in S.plants:
		pl["t0"] = warp(float(pl["t0"]), anc)
		pl["t1"] = warp(float(pl["t1"]), anc)


## where the reference has an EXTRA action between two matched events (it left events out and its stretch is longer), the clip should
## wait rather than slow its whole move down: the extra time goes into the hold of the card boundary (end of a hold) where the clip
## is slowest between the two. The cards are the only samples of the map, so the pause is an anchor pair on that boundary.
static func with_pauses(anc: Array, ec: Array, er: Array, al: Dictionary, S: Scene, cc: Dictionary) -> Array:
	if anc.size() < 2:
		return anc
	var ts := S.times()
	var v: PackedFloat32Array = cc["v"]
	var out := [anc[0]]
	for k in range(1, anc.size()):
		var a: Array = anc[k - 1]
		var b: Array = anc[k]
		var extra: float = (float(b[1]) - float(a[1])) - (float(b[0]) - float(a[0]))
		var skipped := false
		for j in al["skip_ref"]:
			if float(er[j]["t"]) > float(a[1]) and float(er[j]["t"]) < float(b[1]):
				skipped = true
		if skipped and extra > 0.1:
			var best_t := -1.0
			var best_v := INF
			for r in ts:
				var tb: float = r[2]
				if tb > float(a[0]) + 0.03 and tb < float(b[0]) - 0.03:
					var vi: float = v[clampi(roundi(tb * HZ), 0, v.size() - 1)]
					if vi < best_v:
						best_v = vi
						best_t = tb
			if best_t > 0.0:
				var nt: float = float(a[1]) + (best_t - float(a[0]))
				out.append([best_t - 0.001, nt - 0.001])   # the hold's END maps to the later anchor: the hold takes the extra time
				out.append([best_t, nt + extra])
		out.append(b)
	return out


## the map "first, then second" as one anchor list (breakpoints of both)
static func compose(first: Array, second: Array) -> Array:
	var inv := first.map(func(a): return [a[1], a[0]])
	var ts := []
	for a in first:
		ts.append(float(a[0]))
	for a in second:
		ts.append(warp(float(a[0]), inv))
	ts.sort()
	var out := []
	for t in ts:
		var n := warp(warp(t, first), second)
		if t > 0.0 and (out.is_empty() or (t > out[-1][0] + 0.0005 and n > out[-1][1] + 0.0005)):
			out.append([t, n])
	return out


## one pass: {"cc", "cr" (curves), "ec", "er" (events), "al" (alignment), "anc" (anchors)}
static func plan1(S: Scene, R: Scene, B: Body, cr: Dictionary, er: Array) -> Dictionary:
	var cc := speed_curve(S, B)
	var ec := events(cc)
	var al := align(ec, er)
	return {"cc": cc, "cr": cr, "ec": ec, "er": er, "al": al, "anc": with_pauses(anchors(ec, er, al), ec, er, al, S, cc)}


## the plan: pass 1 on the clip as it is; pass 2 re-detects on the once-retimed copy (a warp that is not linear inside a card moves a
## peak a little) and its anchors are composed with the first's. "ec" / "al" / "cc" are pass 1's (what the panel draws: before)
static func plan(S: Scene, R: Scene, B: Body) -> Dictionary:
	var cr := speed_curve(R, B)
	var er := events(cr)
	var p1 := plan1(S, R, B, cr, er)
	var anc: Array = p1["anc"]
	if anc.is_empty():
		return p1
	var C := S.clone()
	apply(C, anc)
	var p2 := plan1(C, R, B, cr, er)
	if not (p2["anc"] as Array).is_empty() and (p2["al"]["pairs"] as Array).size() >= (p1["al"]["pairs"] as Array).size():
		p1["anc"] = compose(anc, p2["anc"])
	return p1


## applies anchors to S in place (cards + the other timed things)
static func apply(S: Scene, anc: Array, markers := true) -> void:
	S.cards = retimed_cards(S, anc)
	warp_others(S, anc, markers)
