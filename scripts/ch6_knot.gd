## ch6_knot.gd - CH6: the bowline's layout, the hand's path, the crossing code of a rope, and the knot's loaded measures.
## Frame of the knot ("k"): x right, y up, viewer on +z (docs/CH6_REFERENCE.md). The rope is traced from the standing end S0
## (index 0) to the working end W (last index).
class_name Ch6Knot
extends RefCounted

const R_ROPE := 0.004
const DS := 0.008
const PEG := Vector3(0.07, -0.024, 0.0)   # peg axis along z through this point
const PEG_R := 0.018


# ---------------------------------------------------------------- the rope laid out, ready to be tied

static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


static func spline(c: Array, sub := 20) -> PackedVector3Array:
	var o := PackedVector3Array()
	var n := c.size()
	for i in n - 1:
		var p0: Vector3 = c[maxi(i - 1, 0)]
		var p1: Vector3 = c[i]
		var p2: Vector3 = c[i + 1]
		var p3: Vector3 = c[mini(i + 2, n - 1)]
		for k in sub:
			o.append(_cr(p0, p1, p2, p3, float(k) / sub))
	o.append(c[n - 1])
	return o


static func resample(c: PackedVector3Array, ds: float) -> PackedVector3Array:
	var o := PackedVector3Array([c[0]])
	var acc := 0.0
	var prev := c[0]
	for i in range(1, c.size()):
		var a := prev
		var b := c[i]
		var l := a.distance_to(b)
		while acc + l >= ds:
			var t := (ds - acc) / l
			a = a + (b - a) * t
			o.append(a)
			l = a.distance_to(b)
			acc = 0.0
		acc += l
		prev = c[i]
	return o


## the pre-laid rope: the standing part A rising along x = 0 (under at the crossing), the hole (a turn of A, counter-clockwise),
## the leg E leaving over A, the loop round the peg, and the long free end R that lies behind and ends behind the hole.
static func layout() -> PackedVector3Array:
	var c: Array = []
	for q in [[0, -0.35, 0], [0, -0.25, 0], [0, -0.16, 0], [0, -0.10, 0], [0, -0.075, -0.004], [0, -0.05, -0.007], [0, -0.02, -0.003]]:
		c.append(Vector3(q[0], q[1], q[2]))
	var d := 0
	while d <= 270:
		var a := deg_to_rad(d)
		var z := 0.0
		if d >= 247:
			z = 0.007 * (d - 247) / 23.0
		c.append(Vector3(-0.05 + 0.05 * cos(a), 0.05 * sin(a), z))
		d += 22
	for q in [[-0.05, -0.05, 0.004], [-0.02, -0.05, 0.007], [0.0, -0.05, 0.007], [0.03, -0.05, 0.004], [0.07, -0.05, 0.0]]:
		c.append(Vector3(q[0], q[1], q[2]))
	d = 285
	while d <= 450:
		var a2 := deg_to_rad(d)
		c.append(Vector3(PEG.x + 0.026 * cos(a2), PEG.y + 0.026 * sin(a2), 0.0))
		d += 15
	# CH6b: the free end's coil is laid 0.45 m longer (it was used up by frame 170 of the tie, then the hand pulled the peg loop
	# into the knot); same route and crossings (one curl behind, a Reidemeister I loop)
	for q in [[0.04, 0.03, -0.02], [0.06, 0.14, -0.05], [0.22, 0.30, -0.07], [0.42, 0.20, -0.07], [0.40, 0.02, -0.06], [0.20, 0.03, -0.055], [0.08, 0.035, -0.052], [0.0, 0.02, -0.05], [-0.06, 0.0, -0.05]]:
		c.append(Vector3(q[0], q[1], q[2]))
	return resample(spline(c), DS)


## waypoints of the working end (k frame). wrong=true plants the slip-knot control: both passes at A go OVER it (no turn round A).
static func tip_waypoints(start: Vector3, wrong := false) -> Array:
	var zb := -0.032   # behind A
	if wrong:
		zb = 0.036   # over A both times: the end never turns round the standing part
	var W: Array = [start]
	for q in [[-0.036, 0.0, -0.045], [-0.036, 0.0, -0.02], [-0.036, 0.0, 0.045], [-0.035, -0.05, 0.05], [-0.032, -0.10, 0.045], [-0.032, -0.10, 0.0],
			[-0.03, -0.10, zb], [0.0, -0.10, zb - 0.002], [0.028, -0.10, zb + 0.002], [0.032, -0.094, 0.0], [0.028, -0.088, 0.034],
			[0.0, -0.088, 0.036], [-0.02, -0.088, 0.036], [-0.022, -0.05, 0.045], [-0.022, 0.0, 0.045], [-0.022, 0.0, 0.0],
			[-0.022, 0.0, -0.05], [-0.022, 0.02, -0.10]]:
		W.append(Vector3(q[0], q[1], q[2]))
	return W


## the path sampled at `speed` m/s, one point per 1/30 s (CH6b: with the regrip dwells of tie_plan, where the end lies still)
static func tip_path(start: Vector3, speed := 0.08, wrong := false) -> PackedVector3Array:
	return tie_plan(start, speed, wrong)["path"]


## CH6b: waypoints where the hand lets go and takes the end again from the other side of the rope plane (it cannot follow the
## end through the hole or round the standing part without its fingers and palm going through the held rope). The hand goes
## to the side the end is on at that waypoint (sign of z): 3 = up through the hole (behind -> front), 7 = poked behind,
## left of the standing part (front -> behind), 11 = come forward right of it (behind -> front), 17 = down through the hole.
const REGRIP := [3, 7, 11, 17]
const REGRIP_X := -0.19   # the hand goes round outside the hole's left arc (x = -0.104)
const REGRIP_OUT := 0.07   # how far it backs off the rope plane


## the tie, frame by frame (30 fps): path = the end's keyed position (dwelling during a regrip), target = the pinch's target,
## mode = "hold" (the pinch carries the end), "open" (let go, 6 frames), "free" (the empty hand moves), "close" (take it, 6 frames)
static func tie_plan(start: Vector3, speed := 0.08, wrong := false) -> Dictionary:
	var W := tip_waypoints(start, wrong)
	var sub := 20
	var dense := spline(W, sub)
	var path := PackedVector3Array()
	var target := PackedVector3Array()
	var mode := PackedStringArray()
	var side := signf(W[0].z)
	var cuts: Array = [0]
	for k in REGRIP:
		if k < W.size() - 1:
			cuts.append(k)
	cuts.append(6)   # DOWN is a measured phase too: a dwell here, not a regrip
	cuts.sort()
	cuts.append(W.size() - 1)
	for ci in cuts.size() - 1:
		var a: int = cuts[ci] * sub
		var b: int = cuts[ci + 1] * sub
		var piece := resample(dense.slice(a, b + 1), speed / 30.0)
		if (piece[piece.size() - 1] as Vector3).distance_to(dense[b]) > 1e-6:
			piece.append(dense[b])
		for q in range(0 if ci == 0 else 1, piece.size()):
			# DOWN was already unthreaded at its keyed endpoint but recovered 0.7 s later. Settle just BEFORE the endpoint,
			# so the phase measurement still lands on the first exact waypoint rather than on a duplicate during the dwell.
			if cuts[ci + 1] == 6 and q == piece.size() - 2:
				for dwell in 24:
					path.append(piece[q])
					target.append(piece[q])
					mode.append("hold")
			path.append(piece[q])
			target.append(piece[q])
			mode.append("hold")
		var k: int = cuts[ci + 1]
		if ci == cuts.size() - 2:
			break
		if not REGRIP.has(k):
			continue
		var P: Vector3 = W[k]
		var sn := signf(P.z)
		if sn == side:
			continue
		# "seek": the hand comes back to where the end really lies (the planned P plus the end's drift since it was let go).
		# At ROUND's end the pinch has already come to the front with the end. Backing it toward the OLD side drove the palm
		# through the standing part and destroyed the collar. Back out to the FRONT and stay there for this regrip.
		var back_side := sn if k == 11 else side
		var slower := 2 if k == 11 else 1
		var out := 0.14 if k == 11 else REGRIP_OUT
		var transit_x := REGRIP_X   # +0.20 m was beyond the right arm's reach (T0: 176 mm miss)
		var legs: Array = [[P, 8 * slower, "open"], [P + Vector3(0, 0, out * back_side), 14 * slower, "free"], [Vector3(transit_x, P.y, out * back_side), 18 * slower, "free"],
			[Vector3(transit_x, P.y, out * sn), 14 * slower, "free"], [P + Vector3(0, 0, out * sn), 18 * slower, "seek"], [P, 12 * slower, "seek"], [P, 6 * slower, "close"]]
		var cur := P
		for L in legs:
			var to: Vector3 = L[0]
			var nf: int = L[1]
			for j in nf:
				var t := float(j + 1) / float(nf)
				t = t * t * (3.0 - 2.0 * t)
				path.append(P)
				target.append(cur.lerp(to, t))
				mode.append(L[2])
			cur = to
		side = sn
	return {"path": path, "target": target, "mode": mode}


# ---------------------------------------------------------------- the crossing code (Gauss code of a projection)

static func _basis(d: Vector3) -> Array:
	d = d.normalized()
	var a := Vector3(0, 1, 0) if absf(d.y) < 0.9 else Vector3(1, 0, 0)
	var u := a.cross(d).normalized()
	var v := d.cross(u)
	return [u, v, d]


## the signed Gauss code seen from direction d (the viewer is at +d): Array of [crossing id, "O"|"U"] along the rope
static func gauss(P: PackedVector3Array, d := Vector3(0, 0, 1)) -> Array:
	var B := _basis(d)
	var u: Vector3 = B[0]
	var v: Vector3 = B[1]
	var w: Vector3 = B[2]
	var n := P.size()
	var X := PackedFloat64Array()
	var Y := PackedFloat64Array()
	var Z := PackedFloat64Array()
	for q in P:
		X.append(q.dot(u))
		Y.append(q.dot(v))
		Z.append(q.dot(w))
	var ev: Array = []   # [pos along rope, crossing, "O"/"U"]
	var cid := 0
	for i in n - 1:
		var ax := X[i]
		var ay := Y[i]
		var rx := X[i + 1] - ax
		var ry := Y[i + 1] - ay
		var xmin := minf(ax, ax + rx)
		var xmax := maxf(ax, ax + rx)
		var ymin := minf(ay, ay + ry)
		var ymax := maxf(ay, ay + ry)
		for j in range(i + 2, n - 1):
			var cx := X[j]
			var cy := Y[j]
			var sx := X[j + 1] - cx
			var sy := Y[j + 1] - cy
			if maxf(cx, cx + sx) < xmin or minf(cx, cx + sx) > xmax or maxf(cy, cy + sy) < ymin or minf(cy, cy + sy) > ymax:
				continue
			var den := rx * sy - ry * sx
			if absf(den) < 1e-14:
				continue
			var qx := cx - ax
			var qy := cy - ay
			var t := (qx * sy - qy * sx) / den
			var k := (qx * ry - qy * rx) / den
			if t >= 0.0 and t < 1.0 and k >= 0.0 and k < 1.0:
				var zi: float = Z[i] + t * (Z[i + 1] - Z[i])
				var zj: float = Z[j] + k * (Z[j + 1] - Z[j])
				ev.append([float(i) + t, cid, "O" if zi > zj else "U"])
				ev.append([float(j) + k, cid, "U" if zi > zj else "O"])
				cid += 1
	ev.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for e in ev:
		out.append([e[1], e[2]])
	return out


## Reidemeister I and II on an open code (a crossing next to itself; two crossings next to each other on both strands with
## one strand over at both), then relabelled in order of first appearance
static func reduce_code(code: Array) -> Array:
	var seq: Array = code.duplicate(true)
	var changed := true
	while changed:
		changed = false
		for i in seq.size() - 1:
			if seq[i][0] == seq[i + 1][0]:
				var c = seq[i][0]
				seq = seq.filter(func(s): return s[0] != c)
				changed = true
				break
		if changed:
			continue
		var pos := {}
		for i in seq.size():
			if not pos.has(seq[i][0]):
				pos[seq[i][0]] = []
			pos[seq[i][0]].append(i)
		for i in seq.size() - 1:
			var a = seq[i][0]
			var b = seq[i + 1][0]
			if a == b:
				continue
			var pa := -1
			for k in pos[a]:
				if k != i:
					pa = k
			var pb := -1
			for k in pos[b]:
				if k != i + 1:
					pb = k
			if absi(pa - pb) == 1 and seq[i][1] == seq[i + 1][1]:
				if seq[pa][1] == seq[pb][1] and seq[pa][1] != seq[i][1]:
					seq = seq.filter(func(s): return s[0] != a and s[0] != b)
					changed = true
					break
	var m := {}
	var out: Array = []
	for s in seq:
		if not m.has(s[0]):
			m[s[0]] = m.size() + 1
		out.append([m[s[0]], s[1]])
	return out


static func code_str(code: Array) -> String:
	var parts := PackedStringArray()
	for s in code:
		parts.append("%d%s" % [s[0], s[1]])
	return " ".join(parts)


static func mirror(code: Array) -> Array:
	var o: Array = []
	for s in code:
		o.append([s[0], "U" if s[1] == "O" else "O"])
	return o


## the shortest reduced code over a fixed set of view directions (6 axes + `nv` pseudo-random ones, seeded)
static func best_code(P: PackedVector3Array, nv := 40) -> Array:
	var dirs: Array = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in nv:
		dirs.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()))
	var best: Array = []
	var first := true
	for d in dirs:
		var s := reduce_code(gauss(P, d))
		if first or s.size() < best.size():
			best = s
			first = false
	return best


## same code up to the mirror image (the left-hand bowline is the same knot seen from behind)
static func same_code(a: Array, b: Array) -> bool:
	return code_str(a) == code_str(b) or code_str(a) == code_str(mirror(b))


# ---------------------------------------------------------------- measures of a loaded knot

## the knot: particles in self contact with a rope run at least 8 particles away (gap < 0.5 r); returns centre or null
static func knot_centre(P: PackedVector3Array) -> Variant:
	var n := P.size()
	var s := Vector3.ZERO
	var c := 0
	var lim := 2.0 * R_ROPE * 1.5
	for i in n:
		var hit := false
		for j in n:
			if absi(i - j) < 8:
				continue
			if P[i].distance_to(P[j]) < lim:
				hit = true
				break
		if hit:
			s += P[i]
			c += 1
	if c == 0:
		return null
	return s / float(c)


## core length (m): the rope inside radius `rk` of the knot centre, counted in particles
static func core_len(P: PackedVector3Array, ctr: Vector3, rk := 0.03) -> float:
	var c := 0
	for q in P:
		if q.distance_to(ctr) < rk:
			c += 1
	return c * DS


## loop circumference (m): the rope run that goes round the peg, between the first particles (walking out from the one nearest
## the peg axis) that are inside radius `rk` of the knot centre; the closing chord through the knot is added
static func loop_len(P: PackedVector3Array, ctr: Vector3, rk := 0.03) -> float:
	var m := 0
	var best := INF
	for i in P.size():
		var d := Vector2(P[i].x - PEG.x, P[i].y - PEG.y).length()
		if d < best:
			best = d
			m = i
	var a := m
	while a > 0 and P[a].distance_to(ctr) >= rk:
		a -= 1
	var b := m
	while b < P.size() - 1 and P[b].distance_to(ctr) >= rk:
		b += 1
	var l := 0.0
	for i in range(a, b):
		l += P[i].distance_to(P[i + 1])
	return l + P[a].distance_to(P[b])


## winding of the rope's loop about the peg axis (turns), from the run a..b of loop_len
static func peg_winding(P: PackedVector3Array) -> float:
	var tot := 0.0
	for i in P.size() - 1:
		var a := Vector2(P[i].x - PEG.x, P[i].y - PEG.y)
		var b := Vector2(P[i + 1].x - PEG.x, P[i + 1].y - PEG.y)
		if a.length() < 0.12 and b.length() < 0.12:
			tot += a.angle_to(b)
	return tot / TAU
