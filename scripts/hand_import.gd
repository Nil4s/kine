## HAND CAPTURE FROM VIDEO (ROADMAP 90). The fingers of a tracked person, fitted to the app's own finger chain. tools/see_video.py
## runs MediaPipe's HandLandmarker (21 points per hand, the hand's world landmarks in metres) and matches each hand to the
## body's wrist it sits on; VideoImport.parse reads them as "hands": {"l": [21 Vector3], "r": [...]}, in OUR axes.
## THE FIT, per hand per frame, in the hand bone's own frame (so the arm's pose and the hand's place in the world do not matter):
##   palm    the frame of the wrist (MediaPipe 0), the index and pinky knuckles (5, 17) and the middle knuckle (9), built the
##           same way on the tracked hand and on the app's hand at rest. M turns the tracked palm onto the app's palm.
##   bones   each finger's three bones (MediaPipe 5->6, 6->7, 7->8; the thumb 1->2, 2->3, 3->4) as UNIT DIRECTIONS, so the
##           tracker's bone lengths are not the app's (the same rule as VideoImport's directions-only fit).
##   angles  per finger four numbers: the knuckle's bend and side, the middle joint's bend, the tip joint's bend (the thumb:
##           CMC bend and side, MCP bend, IP bend). They are found by Levenberg-Marquardt on the 9 direction residuals through
##           the app's own finger chain (Body's forward kinematics), each joint clamped to its limits (Body.clamp_ang) on every step.
## A hand whose residual is above RESID_MAX is refused (no hand for that frame). A hand missing in some frames: see fill().
## Numbers that are ours: RESID_MAX, LOST_HOLD, EASE, CUT, BETA (stated at each constant). The finger model and its limits are
## the app's (Body.FINGERS, data/body_limits.json); the rest pose is Varghese et al. 2020 through Body.RELAXED.
class_name HandImport
extends RefCounted

const FING := ["index", "middle", "ring", "pinky"]
## MediaPipe's 21 hand points by chain: the thumb's CMC, MCP, IP, tip (1-4); each finger's knuckle, middle, tip-side, tip
const CHAIN := {"thumb": [1, 2, 3, 4], "index": [5, 6, 7, 8], "middle": [9, 10, 11, 12], "ring": [13, 14, 15, 16], "pinky": [17, 18, 19, 20]}
const RESID_MAX := 0.3   # the RMS of the 9 direction residuals (unit vectors: 0.3 = 17 deg) above which a hand is refused (ours)
const LOST_HOLD := 0.5   # s: a hand that is not seen holds its last angles this long (ours)
const EASE := 0.5        # s: then eases to the relaxed hand over this long; a hand seen again eases in over this long too (ours)
const CUT := 2.0         # Hz: One Euro min cutoff for the finger angles (ours: a fist closes in about 0.3 s)
const BETA := 0.02       # One Euro speed term, per deg/s (ours)


## the three joint names of one finger (or the thumb) on one side: knuckle / middle / tip, the thumb's CMC / MCP / IP
static func joints(f: String, side: String) -> Array:
	var out := []
	for k in 3:
		out.append("thumb_0%d_%s" % [k + 1, side] if f == "thumb" else "%s_0%d_%s" % [f, k + 1, side])
	return out


## the orthonormal frame of four palm points: y along the wrist -> middle knuckle, x across the knuckles, z the palm's normal
static func palm(a0: Vector3, a5: Vector3, a9: Vector3, a17: Vector3) -> Basis:
	var y := (a9 - a0).normalized()
	var a := a17 - a5
	var x := (a - y * a.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


## the app's relaxed hand (ROADMAP 73's RELAXED / THUMB_RELAXED), by joint name
static func rest_pose(side: String) -> Dictionary:
	var out := {}
	for f in FING:
		for k in 3:
			out[joints(f, side)[k]] = Vector3(float(Body.RELAXED[f][k]), 0.0, 0.0)
	for k in 3:
		out["thumb_0%d_%s" % [k + 1, side]] = Body.THUMB_RELAXED[k]
	return out


## one hand on one frame. B must hold this frame's arm (VideoImport's fit does that first). lm: MediaPipe's 21 points (our axes,
## metres). prev: the last fitted angles (the start of the search). Returns {"ang": {joint: Vector3 deg}, "rms": float} or {}
## when the hand is refused. Leaves B's fingers at the fitted pose.
static func fit_hand(B: Body, side: String, lm: Array, prev := {}) -> Dictionary:
	if lm.size() < 21:
		return {}
	var hand := "hand_" + side
	var Gh: Quaternion = B.G[hand]
	var Gi := Gh.inverse()
	var Ph: Vector3 = B.P[hand]
	var Fr := palm(Vector3.ZERO,
		Gi * ((B.P["index_01_" + side] as Vector3) - Ph),
		Gi * ((B.P["middle_01_" + side] as Vector3) - Ph),
		Gi * ((B.P["pinky_01_" + side] as Vector3) - Ph))
	var Fo := palm(lm[0], lm[5], lm[9], lm[17])
	var M := Fr * Fo.transposed()
	var was := B.fast
	B.fast = true
	var ang := {}
	var ss := 0.0
	var n := 0
	for f in ["thumb"] + FING:
		var js := joints(f, side)
		var tgt := []
		for k in 3:
			var a: int = CHAIN[f][k]
			var b: int = CHAIN[f][k + 1]
			tgt.append((M * ((lm[b] as Vector3) - (lm[a] as Vector3))).normalized())
		var p0 := [0.0, 0.0, 0.0, 0.0]
		if prev.has(js[0]) and prev.has(js[1]) and prev.has(js[2]):
			var v0: Vector3 = prev[js[0]]
			var v1: Vector3 = prev[js[1]]
			var v2: Vector3 = prev[js[2]]
			p0 = [v0.x, v0.y, v1.x, v2.x]
		var p := _lm(B, side, f, tgt, Gi, p0)
		var r := _resid(B, side, f, p, tgt, Gi)
		ss += _dot(r, r)
		n += r.size()
		ang[js[0]] = B.clamp_ang(js[0], Vector3(p[0], p[1], 0.0))
		ang[js[1]] = B.clamp_ang(js[1], Vector3(p[2], 0.0, 0.0))
		ang[js[2]] = B.clamp_ang(js[2], Vector3(p[3], 0.0, 0.0))
	B.fast = was
	for j in ang:
		B.ang[j] = ang[j]
	B.fk()
	var rms := sqrt(ss / maxf(float(n), 1.0))
	if rms > RESID_MAX:
		return {}
	return {"ang": ang, "rms": rms}


## the four parameters of one finger, clamped to its joints' limits: [knuckle bend, knuckle side, middle bend, tip bend]
static func _clampp(B: Body, side: String, f: String, p: Array) -> Array:
	var js := joints(f, side)
	var v0 := B.clamp_ang(js[0], Vector3(p[0], p[1], 0.0))
	var v1 := B.clamp_ang(js[1], Vector3(p[2], 0.0, 0.0))
	var v2 := B.clamp_ang(js[2], Vector3(p[3], 0.0, 0.0))
	return [v0.x, v0.y, v1.x, v2.x]


## the 9 residuals of one finger: each bone's direction through the app's chain (local to the hand) minus the target
static func _resid(B: Body, side: String, f: String, p: Array, tgt: Array, Gi: Quaternion) -> Array:
	var js := joints(f, side)
	var c := _clampp(B, side, f, p)
	B.ang[js[0]] = Vector3(c[0], c[1], 0.0)
	B.ang[js[1]] = Vector3(c[2], 0.0, 0.0)
	B.ang[js[2]] = Vector3(c[3], 0.0, 0.0)
	B.fk_sub(js[0])
	var pts := [B.P[js[0]], B.P[js[1]], B.P[js[2]], B.E[js[2]]]
	var out := []
	for k in 3:
		var d: Vector3 = (Gi * ((pts[k + 1] as Vector3) - (pts[k] as Vector3))).normalized()
		var t: Vector3 = tgt[k]
		out.append(d.x - t.x)
		out.append(d.y - t.y)
		out.append(d.z - t.z)
	return out


## Levenberg-Marquardt on one finger's four parameters from p0; the Jacobian by forward differences
static func _lm(B: Body, side: String, f: String, tgt: Array, Gi: Quaternion, p0: Array) -> Array:
	var p := _clampp(B, side, f, p0)
	var r := _resid(B, side, f, p, tgt, Gi)
	var cost := _dot(r, r)
	var lam := 1e-3
	for it in 40:
		var J := []
		for c in 4:
			var q := p.duplicate()
			q[c] += 0.05
			var rq := _resid(B, side, f, _clampp(B, side, f, q), tgt, Gi)
			var col := []
			for m in r.size():
				col.append((float(rq[m]) - float(r[m])) / 0.05)
			J.append(col)
		var A := []
		var g := []
		for a in 4:
			var row := []
			for b in 4:
				row.append(_dot(J[a], J[b]))
			A.append(row)
			g.append(_dot(J[a], r))
		var accepted := false
		for tries in 10:
			var Am := []
			for a in 4:
				var row: Array = (A[a] as Array).duplicate()
				row[a] = float(row[a]) * (1.0 + lam) + 1e-9
				Am.append(row)
			var dl := _solve(Am, g)
			var q2 := []
			for c in 4:
				q2.append(float(p[c]) - float(dl[c]))
			q2 = _clampp(B, side, f, q2)
			var r2 := _resid(B, side, f, q2, tgt, Gi)
			var c2 := _dot(r2, r2)
			if c2 < cost:
				var moved := 0.0
				for c in 4:
					moved = maxf(moved, absf(float(q2[c]) - float(p[c])))
				p = q2
				r = r2
				cost = c2
				lam = maxf(lam * 0.3, 1e-9)
				accepted = true
				if moved < 1e-4:
					return p
				break
			lam *= 10.0
		if not accepted:
			break
	return p


static func _dot(a: Array, b: Array) -> float:
	var s := 0.0
	for i in a.size():
		s += float(a[i]) * float(b[i])
	return s


## A x = b by Gauss-Jordan with partial pivoting (4 x 4 here)
static func _solve(A: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for i in n:
		var row: Array = (A[i] as Array).duplicate()
		row.append(float(b[i]))
		M.append(row)
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf(float(M[r][c])) > absf(float(M[piv][c])):
				piv = r
		var tmp = M[c]
		M[c] = M[piv]
		M[piv] = tmp
		var d := float(M[c][c])
		if absf(d) < 1e-15:
			var zero := []
			for i in n:
				zero.append(0.0)
			return zero
		for r in n:
			if r != c:
				var fct := float(M[r][c]) / d
				for k in range(c, n + 1):
					M[r][k] = float(M[r][k]) - fct * float(M[c][k])
	var x := []
	for i in n:
		x.append(float(M[i][n]) / float(M[i][i]))
	return x


static func _lerp(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	for j in a:
		out[j] = (a[j] as Vector3).lerp(b[j] as Vector3, u)
	return out


## one side's hand over the clip: raw[i] = fit_hand's angles, or null where the hand was not seen. A gap holds the last angles
## for LOST_HOLD seconds, then eases to the relaxed hand over EASE seconds (a gap at the start starts from the relaxed hand). A
## hand seen again eases in from where the gap left off, over EASE seconds, so nothing snaps. Every frame is complete on return.
static func fill(raw: Array, fps: float, side: String) -> Array:
	var n := raw.size()
	var rest := rest_pose(side)
	var hold_n := maxi(1, roundi(LOST_HOLD * fps))
	var ease_n := maxi(1, roundi(EASE * fps))
	var out := []
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	var i := 0
	while i < n:
		if out[i] != null:
			i += 1
			continue
		var j := i
		while j < n and out[j] == null:
			j += 1
		var a := i - 1
		var start: Dictionary = out[a] if a >= 0 else rest
		for k in range(i, j):
			var t := k - a
			if t <= hold_n:
				out[k] = start.duplicate()
			else:
				var u := smoothstep(0.0, 1.0, clampf(float(t - hold_n) / float(ease_n), 0.0, 1.0))
				out[k] = _lerp(start, rest, u)
		if j < n:
			var gap_end: Dictionary = out[j - 1]
			for k in range(j, n):
				if raw[k] == null or k >= j + ease_n:
					break
				out[k] = _lerp(gap_end, raw[k], smoothstep(0.0, 1.0, float(k - j) / float(ease_n)))
		i = j
	return out


## the clean path's One Euro filter (VideoCleanup.one_euro_zero_lag, forward and backward) on every joint's angles. Expects
## complete frames (fill's output). Returns the same form
static func smooth(series: Array, fps: float) -> Array:
	if series.is_empty():
		return series
	var out := []
	for i in series.size():
		out.append({})
	for j in (series[0] as Dictionary).keys():
		var xs := []
		for d in series:
			xs.append((d as Dictionary)[j])
		var ys := VideoCleanup.one_euro_zero_lag(xs, fps, CUT, BETA)
		for i in series.size():
			(out[i] as Dictionary)[j] = ys[i]
	return out
