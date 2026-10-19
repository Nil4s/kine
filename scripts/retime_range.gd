## retime_range.gd - ROADMAP 67: RETIME A RANGE AROUND THE PLAYHEAD. Pure data, no UI: main.gd wraps it in one undo step.
##
## The range [r0, r1] (seconds) holds the playhead p (r0 <= p <= r1). The warp W maps every time of the scene:
##   t <= r0          -> t                      (before the range: untouched, the boundary r0 stays where it is)
##   r0 < t <= r1     -> p + (t - p) * k        (inside: scaled about the playhead, k = pct / 100)
##   t > r1           -> t + (r1 - p) * (k - 1) (after: shifted by the change of the range's end, so nothing overlaps)
## A key at p + 0.4 at 150 % lands at p + 0.6. The range's start moves to p + (r0 - p) * k, so a stretch with the
## playhead inside the range and k > 1 would run back over the content before r0: check() refuses that rather than
## overlap it, and so does a stretch that would start the range before 0 s. Move the playhead to the range's start,
## or stretch less, to get it through.
##
## WHAT MOVES: the cards (each move and hold that intersects the range is rewritten from the warped boundaries, 1 ms,
## a move never under 0.04 s as Scene.retime does) and the part keys (their times, the handles' dt inside the range,
## and a modifier's range_start / range_end). WHAT DOES NOT: foot plants, layers, props, IK keys, drivers, audio: those
## keep their own times (named in the report, not hidden).
class_name RetimeRange
extends RefCounted

const MIN_MOVE := 0.04   # the same floor Scene.retime uses


## the warped time of t (see the header). k > 0
static func warp(t: float, r0: float, r1: float, p: float, k: float) -> float:
	if t <= r0:
		return t
	if t <= r1:
		return p + (t - p) * k
	return t + (r1 - p) * (k - 1.0)


## "" when the retime can be made, else what is wrong (the caller says it with the next step)
static func check(S: Scene, r0: float, r1: float, p: float, pct: float) -> String:
	if not (pct >= 10.0 and pct <= 1000.0):
		return "retime by 10 to 1000 %% (100 = as it is), not %s" % pct
	if r1 - r0 < 1.0 / float(maxi(S.fps, 1)):
		return "the range is shorter than a frame"
	if p < r0 - 1e-6 or p > r1 + 1e-6:
		return "the playhead (%.2f s) is outside the range %.2f-%.2f s" % [p, r0, r1]
	var k := pct / 100.0
	var n0 := p + (r0 - p) * k   # where the range starts after the stretch
	if n0 < 0.0:
		return "stretching %.2f-%.2f s about %.2f s would start it at %.2f s, before the scene starts" % [r0, r1, p, n0]
	if n0 < r0 - 1e-9:
		var xs := []
		for ts in S.times():
			xs.append_array([ts[0], ts[1], ts[2]])
		for j in S.part_keys:
			for key in S.part_keys[j]:
				xs.append(float(key["t"]))
		for x in xs:
			if float(x) > n0 + 1e-9 and float(x) <= r0 + 1e-9:
				return "stretching %.2f-%.2f s about %.2f s would run it back over the content at %.2f s before the range" % [r0, r1, p, float(x)]
	return ""


## applies the retime. Assumes check() passed. Returns the number of cards rewritten (0 at 100 %: nothing is touched)
static func apply(S: Scene, r0: float, r1: float, p: float, pct: float) -> int:
	if pct == 100.0:
		return 0
	var k := pct / 100.0
	var ts: Array = S.times().duplicate(true)
	var changed := 0
	for i in S.cards.size():
		var s: float = ts[i][0]
		var a: float = ts[i][1]
		var e: float = ts[i][2]
		if e <= r0 or s >= r1:
			continue   # wholly before the range (untouched) or after it (it shifts with the cumulative times)
		var c: Dictionary = S.cards[i]
		if i > 0:
			c["move"] = maxf(MIN_MOVE, snappedf(warp(a, r0, r1, p, k) - warp(s, r0, r1, p, k), 0.001))
		c["hold"] = maxf(0.0, snappedf(warp(e, r0, r1, p, k) - warp(a, r0, r1, p, k), 0.001))
		changed += 1
	for j in S.part_keys:
		for key in S.part_keys[j]:
			_warp_key(key, r0, r1, p, k)
	return changed


static func _warp_key(key: Dictionary, r0: float, r1: float, p: float, k: float) -> void:
	var t: float = key["t"]
	var inside := t > r0 and t <= r1
	key["t"] = warp(t, r0, r1, p, k)
	for h in ["hin", "hout"]:
		if inside and key.has(h):
			var hv: Array = key[h].duplicate()
			hv[0] = float(hv[0]) * k   # a handle's dt is a time: it scales with the stretch
			key[h] = hv
	for md in key.get("mods", []):
		if md.has("range_start"):
			var rs: float = md["range_start"]
			var mod_inside := rs > r0 and rs <= r1
			md["range_start"] = warp(rs, r0, r1, p, k)
			if md.has("range_end"):
				md["range_end"] = warp(float(md["range_end"]), r0, r1, p, k)
			if mod_inside:
				for b in ["blend_in", "blend_out"]:
					if md.has(b):
						md[b] = float(md[b]) * k
