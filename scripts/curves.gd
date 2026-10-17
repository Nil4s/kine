class_name Curves
extends RefCounted
## CURVE TOOLS (round 41, gate WW2; UPGRADES_300 #244 #245). A pure library, no UI. A CHANNEL is an Array of
## [t, value] pairs, t in seconds rising, value a float or a Vector3 (degrees, one component per axis). Every tool
## returns {"track": Array, "report": {"keys_before", "keys_after", "worst_err"}}; worst_err is the largest
## per-component difference (degrees) between the result and the input, read at the keys of both.
##
## EULER FILTER (Maya Curves > Euler Filter; Blender Discontinuity Filter): per axis, every sample is moved by a
## multiple of 360 so no step to the next is more than 180. NOT DONE: the equivalent-Euler flip. Body.compose() is a
## swing-twist split (swing about b_ax*bend + a_ax*side, then twist), not three stacked axes, so the classic
## (a, b, c) = (a+180, 180-b, c+180) identity does not hold here; per-axis unwrap only.
##
## BUTTERWORTH: 2nd-order low-pass, H(s) = 1 / (s^2/wc^2 + sqrt(2) s/wc + 1) (analog prototype:
## https://en.wikipedia.org/wiki/Butterworth_filter, page read), turned digital by the bilinear transform with the
## cutoff pre-warped, K = tan(pi fc / fs). Run forward then backward (zero phase), so the total gain is
## |H|^2 = 1 / (1 + (f/fc)^4): -3 dB at fc. Ends are padded by odd reflection and the filter starts at steady state.
## Needs a uniform grid at fps (sample_scene_channel gives one).
##
## GAUSSIAN: weights exp(-dt^2 / 2 sigma^2) on the keys' real times, normalised; the ends are mirrored about the first
## and last key, so a constant is kept exactly and the mean nearly.
##
## DECIMATE (Blender Graph Editor > Key > Decimate (Allowed Change), Clean Keyframes:
## https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/editors/graph_editor/fcurves/editing.rst):
## Ramer-Douglas-Peucker in time. The result is read back with LINEAR interpolation between kept keys. The input is
## itself linear between its keys, so the two differ only at the input's keys: worst_err there is the true maximum.
## CLEAN: a greedy pass from the first key; a key goes when every key dropped with it lies within eps of the chord.
## Same bound, different choice of keys from decimate (local, left to right).


static func _dims(ch: Array) -> int:
	return 3 if not ch.is_empty() and ch[0][1] is Vector3 else 1


static func _comp(ch: Array, k: int) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	for p in ch:
		o.append(float(p[1][k]) if p[1] is Vector3 else float(p[1]))
	return o


static func _build(ch: Array, cols: Array) -> Array:
	var out := []
	for i in ch.size():
		if ch[i][1] is Vector3:
			out.append([ch[i][0], Vector3(cols[0][i], cols[1][i], cols[2][i])])
		else:
			out.append([ch[i][0], cols[0][i]])
	return out


static func _mag(d) -> float:
	if d is Vector3:
		return maxf(absf(d.x), maxf(absf(d.y), absf(d.z)))
	return absf(d)


## linear read of a channel at time t (clamped to the ends), as a float or a Vector3
static func eval(ch: Array, t: float):
	if ch.is_empty():
		return 0.0
	if t <= ch[0][0]:
		return ch[0][1]
	if t >= ch[-1][0]:
		return ch[-1][1]
	var lo := 0
	var hi := ch.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) >> 1
		if ch[m][0] <= t:
			lo = m
		else:
			hi = m
	var u: float = (t - float(ch[lo][0])) / maxf(1e-12, float(ch[hi][0]) - float(ch[lo][0]))
	return ch[lo][1] * (1.0 - u) + ch[hi][1] * u


## largest per-component |a(t) - b(t)| over the keys of a and of b (degrees)
static func max_diff(a: Array, b: Array) -> float:
	var w := 0.0
	for tr in [a, b]:
		for p in tr:
			w = maxf(w, _mag(eval(a, p[0]) - eval(b, p[0])))
	return w


static func _rep(before: Array, after: Array) -> Dictionary:
	return {"keys_before": before.size(), "keys_after": after.size(), "worst_err": max_diff(before, after)}


static func euler_filter(ch: Array) -> Dictionary:
	var cols := []
	for k in _dims(ch):
		var c := _comp(ch, k)
		for i in range(1, c.size()):
			c[i] += 360.0 * roundf((c[i - 1] - c[i]) / 360.0)
		cols.append(c)
	var out := _build(ch, cols)
	# for the filter, worst_err is the biggest shift it made (a multiple of 360 by design)
	var w := 0.0
	for i in ch.size():
		w = maxf(w, _mag(out[i][1] - ch[i][1]))
	return {"track": out, "report": {"keys_before": ch.size(), "keys_after": out.size(), "worst_err": w}}


static func smooth_gaussian(ch: Array, sigma_s: float) -> Dictionary:
	var n := ch.size()
	var cols := []
	var ts := PackedFloat64Array()
	for p in ch:
		ts.append(float(p[0]))
	for k in _dims(ch):
		var c := _comp(ch, k)
		var o := PackedFloat64Array()
		o.resize(n)
		for i in n:
			if sigma_s <= 1e-9 or n < 2:
				o[i] = c[i]
				continue
			var ws := 0.0
			var acc := 0.0
			var reach := 3.0 * sigma_s
			for j in n:
				var cands := [ts[j]]
				if j != 0:
					cands.append(2.0 * ts[0] - ts[j])
				if j != n - 1:
					cands.append(2.0 * ts[n - 1] - ts[j])
				for tj in cands:
					var dt: float = absf(ts[i] - tj)
					if dt > reach:
						continue
					var w := exp(-dt * dt / (2.0 * sigma_s * sigma_s))
					ws += w
					acc += w * c[j]
			o[i] = acc / ws
		cols.append(o)
	var out := _build(ch, cols)
	return {"track": out, "report": _rep(ch, out)}


## one biquad pass (direct form II transposed) with the state set so a constant input stays constant
static func _biquad(x: PackedFloat64Array, b: Array, a: Array) -> PackedFloat64Array:
	var y := PackedFloat64Array()
	y.resize(x.size())
	var z1: float = (1.0 - b[0]) * x[0]
	var z2: float = (b[2] - a[1]) * x[0]
	for i in x.size():
		var o: float = b[0] * x[i] + z1
		z1 = b[1] * x[i] - a[0] * o + z2
		z2 = b[2] * x[i] - a[1] * o
		y[i] = o
	return y


static func butterworth(ch: Array, cutoff_hz: float, fps: float) -> Dictionary:
	var n := ch.size()
	var cols := []
	var K := tan(PI * clampf(cutoff_hz / fps, 1e-6, 0.4999))
	var nrm := 1.0 / (1.0 + sqrt(2.0) * K + K * K)
	var b := [K * K * nrm, 2.0 * K * K * nrm, K * K * nrm]
	var a := [2.0 * (K * K - 1.0) * nrm, (1.0 - sqrt(2.0) * K + K * K) * nrm]
	for k in _dims(ch):
		var c := _comp(ch, k)
		if n < 3:
			cols.append(c)
			continue
		var pad := mini(n - 1, 30)
		var e := PackedFloat64Array()
		for i in range(pad, 0, -1):
			e.append(2.0 * c[0] - c[i])
		e.append_array(c)
		for i in range(1, pad + 1):
			e.append(2.0 * c[n - 1] - c[n - 1 - i])
		var f := _biquad(e, b, a)
		f.reverse()
		var g := _biquad(f, b, a)
		g.reverse()
		cols.append(g.slice(pad, pad + n))
	var out := _build(ch, cols)
	return {"track": out, "report": _rep(ch, out)}


static func _chord_err(ch: Array, i0: int, i1: int, i: int) -> float:
	var u: float = (float(ch[i][0]) - float(ch[i0][0])) / maxf(1e-12, float(ch[i1][0]) - float(ch[i0][0]))
	return _mag(ch[i][1] - (ch[i0][1] * (1.0 - u) + ch[i1][1] * u))


static func _rdp(ch: Array, i0: int, i1: int, eps: float, keep: PackedByteArray) -> void:
	var worst := -1.0
	var at := -1
	for i in range(i0 + 1, i1):
		var e := _chord_err(ch, i0, i1, i)
		if e > worst:
			worst = e
			at = i
	if at >= 0 and worst > eps:
		keep[at] = 1
		_rdp(ch, i0, at, eps, keep)
		_rdp(ch, at, i1, eps, keep)


static func decimate(ch: Array, max_err_deg: float) -> Dictionary:
	if ch.size() < 3:
		return {"track": ch.duplicate(true), "report": _rep(ch, ch)}
	var keep := PackedByteArray()
	keep.resize(ch.size())
	keep[0] = 1
	keep[ch.size() - 1] = 1
	_rdp(ch, 0, ch.size() - 1, max_err_deg, keep)
	var out := []
	for i in ch.size():
		if keep[i]:
			out.append(ch[i].duplicate())
	return {"track": out, "report": _rep(ch, out)}


static func clean(ch: Array, eps: float) -> Dictionary:
	if ch.size() < 3:
		return {"track": ch.duplicate(true), "report": _rep(ch, ch)}
	var out := [ch[0].duplicate()]
	var anchor := 0
	var last_ok := 1
	for j in range(2, ch.size()):
		var good := true
		for i in range(anchor + 1, j):
			if _chord_err(ch, anchor, j, i) > eps:
				good = false
				break
		if good:
			last_ok = j
		else:
			out.append(ch[last_ok].duplicate())
			anchor = last_ok
			last_ok = j
	out.append(ch[-1].duplicate())
	return {"track": out, "report": _rep(ch, out)}


## the scene's (bend, side, twist) for one joint, sampled at fps from 0 to its length: [[t, Vector3], ...]
static func sample_scene_channel(S: Scene, _B: Body, joint: String, fps: float) -> Array:
	var out := []
	var n := int(floor(S.length() * fps + 1e-6)) + 1
	for i in n:
		var t := float(i) / fps
		var s := S.sample(t)
		var v := Vector3.ZERO
		if s.has("ang") and s["ang"].has(joint):
			v = s["ang"][joint]
		out.append([t, v])
	return out
