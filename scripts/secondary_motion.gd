## secondary_motion.gd - ROADMAP item 26: SECONDARY MOTION baked to keys (hair, cloth, a flexible weapon).
##
## Two kinds of item hang from a joint (the attach) and follow its motion with lag and overshoot:
##   "chain": N rigid segments, a point mass at each segment's end, hanging from the attach (a ponytail, a cloth strip
##            hung from the belt): the planar N-pendulum with the attach's sway acceleration a as its base. Coordinates
##            are the segments' absolute angles from the rest direction (down), W_i = mass below segment i:
##              sum_j M_ij th_j'' = -a W_i l_i cos th_i - g W_i l_i sin th_i - sum_j P_ij th_j'^2 - alpha sum_j M_ij th_j'
##            with M_ij = W_max(i,j) l_i l_j cos(th_i - th_j), P_ij = W_max(i,j) l_i l_j sin(th_i - th_j) (Lagrange; checked
##            against the textbook double pendulum). Damping is viscous and proportional to the mass (alpha = 2 zeta w1):
##            the FIRST mode of the small-swing chain has damping ratio zeta exactly, w1 being its frequency (power
##            iteration on the rest matrices, once). Swings of 60 deg and more are followed, not linearised.
##   "rod":   a flexible shaft clamped at the attach (an oak bo, a spear shaft). ONE bending mode, from the
##            Euler-Bernoulli cantilever: f1 = (beta1 L)^2 / (2 pi L^2) * sqrt(E I / (rho A)), beta1 L = 1.8751
##            (Blevins, Formulas for Natural Frequency and Mode Shape). The modal equation is
##            q'' + 2 zeta w q' + w^2 q = -Gamma a, Gamma = int(phi) / int(phi^2) with phi the mode normalised to 1 at
##            the free end. The shaft's nodes sit on the mode shape: the angle at node i is phi'(s_i) q.
##
## THE SIM (one integrator for both): semi-implicit Euler at SUB_HZ = 240 fixed substeps a second. The attach path is
## sampled at the scene's frames and interpolated (Catmull-Rom) to the substeps; its acceleration is the second
## difference on that grid, projected on the item's sway axis. The file never sees the frame rate in the sim.
##
## WHAT IS BAKED: each segment's angle RELATIVE to the segment before it (the first relative to the attach frame), in
## degrees, about the axis dir x sway (right-hand: positive takes the rest direction toward the sway), one key every
## 1 / BAKE_HZ s (a Catmull-Rom spline between keys on replay), written as "keys": {"<name>_<i>": [[t, deg], ...]} with "fps" (the scene's
## frame rate the attach path was sampled at). Those joints are not on Body's skeleton: the view draws them
## (main.gd _sec_draw) and the file carries them; no glTF/engine export writes them yet.
##
## WHAT IS NOT MODELLED: gravity is the rest of the world, not the attach's rotating frame (a vertical attach motion
## does not change the restoring force); the sway is one world axis (x or z), so a chain swings in one plane; the rod is
## the one-mode linear beam (its deflection is small by construction: a bo bends a few degrees at its tip).
##
## IN THE FILE: "secondary": {"items": [...], "keys": {...}, "fps": n}, written only when there is an item (Scene.to_dict).
class_name SecondaryMotion
extends RefCounted

const SUB_HZ := 240            # fixed substeps a second (the sim never reads the scene's frame rate)
const BAKE_HZ := 120           # keys a second: four times the scene's 30 fps (a 4 Hz staff mode is not aliased); the spline between them is within 0.1 deg of the sim (test 4)
const BETA1_L := 1.8751        # cantilever, first bending mode: beta1 * L
const GRAV := 9.81
const KINDS := ["chain", "rod"]
## PRESETS (ours, labelled). ponytail: a 0.38 m tail, 4 segments, 12 g a node, zeta 0.2 (hair in a tie: ours, not measured).
## cloth: a 0.5 m strip hung from the belt, 5 segments, zeta 0.3 (ours). bo: an oak bo, 1.8 m, 25 mm solid round, E 12 GPa
## along the grain and 750 kg/m3 dry (order of magnitude from the Forest Products Laboratory Wood Handbook, FPL-GTR-190;
## verify the number before quoting it), zeta 0.02 (wood is lightly damped; ours).
const PRESETS := {
	"ponytail": {"name": "ponytail", "kind": "chain", "attach": "head", "off": [0.0, 0.10, -0.08], "sway": "x",
		"n": 4, "len": 0.38, "mass": 0.012, "zeta": 0.2},
	"cloth": {"name": "strip", "kind": "chain", "attach": "pelvis", "off": [0.0, 0.0, -0.10], "sway": "z",
		"n": 5, "len": 0.5, "mass": 0.02, "zeta": 0.3},
	"bo": {"name": "bo", "kind": "rod", "attach": "hand_r", "off": [0.0, 0.0, 0.0], "sway": "x",
		"n": 6, "len": 1.8, "E": 12.0e9, "d": 0.025, "rho": 750.0, "zeta": 0.02},
}


## a copy of a preset item
static func preset(key: String) -> Dictionary:
	return (PRESETS[key] as Dictionary).duplicate(true)


## the rest direction of an item's chain: down for hair and cloth, up for a rod
static func dir_of(item: Dictionary) -> Vector3:
	return Vector3.UP if String(item["kind"]) == "rod" else Vector3.DOWN


## the world axis the item sways along: x or z (the sway plane is dir x sway)
static func sway_of(item: Dictionary) -> Vector3:
	return Vector3.RIGHT if String(item["sway"]) == "x" else Vector3(0.0, 0.0, 1.0)


## the bending frequency of a rod (Hz) from E, I, L, rho, A (solid round of diameter d)
static func rod_hz(item: Dictionary) -> float:
	var d := float(item["d"])
	var L := float(item["len"])
	var I := PI * pow(d, 4.0) / 64.0
	var A := PI * d * d / 4.0
	var b := BETA1_L / L
	return (b * L) * (b * L) / (2.0 * PI * L * L) * sqrt(float(item["E"]) * I / (float(item["rho"]) * A))


## the simple-pendulum frequency of a one-segment chain (Hz): sqrt(g / l) / 2 pi, for the test to compare with
static func pendulum_hz(item: Dictionary) -> float:
	return sqrt(GRAV / float(item["len"])) / (2.0 * PI)


## the linear model of an item: {"dof", "M_inv", "K" (diagonal), "B", "alpha", "S" (node x dof), "w" (first mode, rad/s)}
static func build(item: Dictionary) -> Dictionary:
	var n := int(item["n"])
	var L := float(item["len"])
	var ell := L / float(n)
	if String(item["kind"]) == "rod":
		return _rod(item, n, L, ell)
	return _chain(item, n, ell)


static func _chain(item: Dictionary, n: int, ell: float) -> Dictionary:
	var m := float(item["mass"])
	var M := []
	var K := PackedFloat64Array()
	var B := PackedFloat64Array()
	var S := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		for j in n:
			row[j] = m * ell * ell * float(n - maxi(i, j))
		M.append(row)
		K.append(GRAV * m * ell * float(n - i))
		B.append(ell * m * float(n - i))
		var s := PackedFloat64Array()
		s.resize(n)
		s.fill(0.0)
		s[i] = 1.0
		S.append(s)
	var w1 := _first_mode(M, K)
	return {"dof": n, "M_inv": _invert(M), "K": K, "B": B, "alpha": 2.0 * float(item["zeta"]) * w1, "S": S, "w": w1}


## the first mode of K^-1 M (K diagonal): power iteration; w1 = 1 / sqrt(largest eigenvalue)
static func _first_mode(M: Array, K: PackedFloat64Array) -> float:
	var n := K.size()
	var x := PackedFloat64Array()
	x.resize(n)
	x.fill(1.0)
	var lam := 1.0
	for it in 2000:
		var y := PackedFloat64Array()
		y.resize(n)
		for i in n:
			var row: PackedFloat64Array = M[i]
			var acc := 0.0
			for j in n:
				acc += row[j] * x[j]
			y[i] = acc / K[i]
		var nx := 0.0
		var ny := 0.0
		for i in n:
			nx += x[i] * x[i]
			ny += y[i] * y[i]
		lam = sqrt(ny / maxf(nx, 1e-300))
		var s := 1.0 / sqrt(maxf(ny, 1e-300))
		for i in n:
			x[i] = y[i] * s
	return 1.0 / sqrt(lam)


static func _rod(item: Dictionary, n: int, L: float, ell: float) -> Dictionary:
	var beta := BETA1_L / L
	var sig := (cosh(beta * L) + cos(beta * L)) / (sinh(beta * L) + sin(beta * L))
	var tip := _phi(L, beta, sig)
	# the modal participation: Gamma = int(phi) / int(phi^2) over the shaft (phi normalised to 1 at the free end)
	var num := 0.0
	var den := 0.0
	var N := 2000
	for k in N:
		var x := (float(k) + 0.5) * L / float(N)
		var p := _phi(x, beta, sig) / tip
		num += p
		den += p * p
	var gamma := num / den
	var w := 2.0 * PI * rod_hz(item)
	var S := []
	var h := L * 1e-6
	for i in n:
		var s := float(i + 1) * ell
		var slope := (_phi(s + h, beta, sig) - _phi(s - h, beta, sig)) / (2.0 * h) / tip
		var row := PackedFloat64Array()
		row.resize(1)
		row[0] = slope
		S.append(row)
	var M_inv := [PackedFloat64Array([1.0])]
	return {"dof": 1, "M_inv": M_inv, "K": PackedFloat64Array([w * w]), "B": PackedFloat64Array([gamma]),
		"alpha": 2.0 * float(item["zeta"]) * w, "S": S, "w": w}


static func _phi(x: float, beta: float, sig: float) -> float:
	return cosh(beta * x) - cos(beta * x) - sig * (sinh(beta * x) - sin(beta * x))


## Gauss-Jordan inverse of a small dense matrix (rows are PackedFloat64Array)
static func _invert(M: Array) -> Array:
	var n := M.size()
	var A := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(2 * n)
		for j in n:
			row[j] = (M[i] as PackedFloat64Array)[j]
		row[n + i] = 1.0
		A.append(row)
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf((A[r] as PackedFloat64Array)[c]) > absf((A[piv] as PackedFloat64Array)[c]):
				piv = r
		var tmp = A[c]
		A[c] = A[piv]
		A[piv] = tmp
		var pr: PackedFloat64Array = A[c]
		var d := pr[c]
		for j in 2 * n:
			pr[j] /= d
		for r in n:
			if r == c:
				continue
			var rr: PackedFloat64Array = A[r]
			var f := rr[c]
			if f == 0.0:
				continue
			for j in 2 * n:
				rr[j] -= f * pr[j]
	var out := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		var ar: PackedFloat64Array = A[i]
		for j in n:
			row[j] = ar[n + j]
		out.append(row)
	return out


## the base's sway acceleration at every substep: the second difference of the attach path on the SUB_HZ grid
static func base_accel(P: Array, axis: Vector3) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(P.size())
	a.fill(0.0)
	var f2 := float(SUB_HZ) * float(SUB_HZ)
	for s in range(1, P.size() - 1):
		a[s] = (P[s + 1] - 2.0 * P[s] + P[s - 1]).dot(axis) * f2
	return a


## the modal sim from rest: the state q after each substep (semi-implicit Euler at 1 / SUB_HZ)
static func simulate(st: Dictionary, a: PackedFloat64Array) -> Array:
	var dof: int = st["dof"]
	var M_inv: Array = st["M_inv"]
	var K: PackedFloat64Array = st["K"]
	var B: PackedFloat64Array = st["B"]
	var alpha: float = st["alpha"]
	var q := PackedFloat64Array()
	q.resize(dof)
	q.fill(0.0)
	var v := PackedFloat64Array()
	v.resize(dof)
	v.fill(0.0)
	var rhs := PackedFloat64Array()
	rhs.resize(dof)
	var dt := 1.0 / float(SUB_HZ)
	var out := []
	for s in a.size():
		for j in dof:
			rhs[j] = -K[j] * q[j] - B[j] * a[s]
		for i in dof:
			var acc := -alpha * v[i]
			var row: PackedFloat64Array = M_inv[i]
			for j in dof:
				acc += row[j] * rhs[j]
			v[i] += dt * acc
		for i in dof:
			q[i] += dt * v[i]
		out.append(q.duplicate())
	return out


## the node angles (rad from the rest direction) of a state q
static func angles(st: Dictionary, q: PackedFloat64Array) -> PackedFloat64Array:
	var S: Array = st["S"]
	var th := PackedFloat64Array()
	th.resize(S.size())
	for i in S.size():
		var row: PackedFloat64Array = S[i]
		var acc := 0.0
		for j in row.size():
			acc += row[j] * q[j]
		th[i] = acc
	return th


## the angle of each segment relative to the one before (the first relative to the attach frame)
static func rel(th: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(th.size())
	var prev := 0.0
	for i in th.size():
		out[i] = th[i] - prev
		prev = th[i]
	return out


## the segment angles (rad) at every substep for an attach path sampled at SUB_HZ (Array of Vector3)
static func run(item: Dictionary, P: Array) -> Array:
	var a := base_accel(P, sway_of(item))
	if String(item["kind"]) == "chain":
		return simulate_chain(item, a)
	var st := build(item)
	var qs := simulate(st, a)
	var out := []
	for q in qs:
		out.append(angles(st, q))
	return out


## THE CHAIN (the planar N-pendulum, see the header): the absolute segment angles after each substep, semi-implicit
## Euler at 1 / SUB_HZ. Each substep solves M(th) acc = rhs(th, om) for the accelerations (N x N, Gauss elimination)
static func simulate_chain(item: Dictionary, a: PackedFloat64Array) -> Array:
	var n := int(item["n"])
	var ell := float(item["len"]) / float(n)
	var m := float(item["mass"])
	var alpha := 2.0 * float(item["zeta"]) * float(build(item)["w"])
	var W := PackedFloat64Array()
	W.resize(n)
	for i in n:
		W[i] = m * float(n - i)   # the mass at and below segment i
	var th := PackedFloat64Array()
	th.resize(n)
	th.fill(0.0)
	var om := PackedFloat64Array()
	om.resize(n)
	om.fill(0.0)
	var dt := 1.0 / float(SUB_HZ)
	var out := []
	for s in a.size():
		var M := []
		var rhs := PackedFloat64Array()
		rhs.resize(n)
		for i in n:
			var row := PackedFloat64Array()
			row.resize(n)
			var r := -a[s] * W[i] * ell * cos(th[i]) - GRAV * W[i] * ell * sin(th[i])
			for j in n:
				var wm := W[maxi(i, j)] * ell * ell
				row[j] = wm * cos(th[i] - th[j])
				r -= wm * sin(th[i] - th[j]) * om[j] * om[j]
			M.append(row)
			rhs[i] = r
		var acc := _solve(M, rhs)
		for i in n:
			om[i] += dt * (acc[i] - alpha * om[i])
		for i in n:
			th[i] += dt * om[i]
		out.append(th.duplicate())
	return out


## x of A x = b (A dense rows, partial pivoting)
static func _solve(A: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := b.size()
	var M := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n + 1)
		var ar: PackedFloat64Array = A[i]
		for j in n:
			row[j] = ar[j]
		row[n] = b[i]
		M.append(row)
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf((M[r] as PackedFloat64Array)[c]) > absf((M[piv] as PackedFloat64Array)[c]):
				piv = r
		var tmp = M[c]
		M[c] = M[piv]
		M[piv] = tmp
		var pr: PackedFloat64Array = M[c]
		for r in range(c + 1, n):
			var rr: PackedFloat64Array = M[r]
			var f := rr[c] / pr[c]
			for j in range(c, n + 1):
				rr[j] -= f * pr[j]
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var row: PackedFloat64Array = M[i]
		var acc := row[n]
		for j in range(i + 1, n):
			acc -= row[j] * x[j]
		x[i] = acc / row[i]
	return x


## the attach path at the frames (one point a frame at fps) interpolated to the SUB_HZ grid (Catmull-Rom)
static func path240(frames: Array, fps: int) -> Array:
	var out := []
	var nf := frames.size()
	if nf < 2:
		return frames.duplicate()
	var n_sub := int(round(float(nf - 1) * float(SUB_HZ) / float(fps))) + 1
	for s in n_sub:
		var u := float(s) * float(fps) / float(SUB_HZ)
		var k := clampi(int(floor(u)), 0, nf - 2)
		var f := clampf(u - float(k), 0.0, 1.0)
		var p0: Vector3 = frames[maxi(k - 1, 0)]
		var p1: Vector3 = frames[k]
		var p2: Vector3 = frames[k + 1]
		var p3: Vector3 = frames[mini(k + 2, nf - 1)]
		out.append(0.5 * (2.0 * p1 + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f))
	return out


## the keys of one item: its segments' relative angles (deg) at every frame, from the attach path at those frames
static func keys_of(item: Dictionary, frames: Array, fps: int) -> Dictionary:
	var ths := run(item, path240(frames, fps))
	var name := String(item["name"])
	var n := int(item["n"])
	var out := {}
	for i in n:
		out["%s_%d" % [name, i + 1]] = []
	var span := float(frames.size() - 1) / float(fps)
	var nk := int(floor(span * float(BAKE_HZ) + 1e-6)) + 1
	for k in nk:
		var s := clampi(int(round(float(k) * float(SUB_HZ) / float(BAKE_HZ))), 0, ths.size() - 1)
		var r := rel(ths[s])
		for i in n:
			(out["%s_%d" % [name, i + 1]] as Array).append([snappedf(float(k) / float(BAKE_HZ), 0.0001), snappedf(rad_to_deg(r[i]), 0.001)])
	return out


## the world point the attach joint puts the item's root at this frame (the offset is in the joint's frame)
static func attach_point(B: Body, item: Dictionary) -> Vector3:
	var j := String(item["attach"])
	if not B.P.has(j):
		return Vector3.ZERO
	var o: Array = item["off"]
	return (B.P[j] as Vector3) + (B.G[j] as Quaternion) * Vector3(float(o[0]), float(o[1]), float(o[2]))


## BAKE (the scene): every item's attach point at the scene's frames (S.apply, the body put back as it was), the sim run on
## that path, the keys written. Returns the secondary block (items kept, keys and fps replaced)
static func bake_scene(S: Scene, B: Body, sec: Dictionary) -> Dictionary:
	var out := sec.duplicate(true)
	var items: Array = out.get("items", [])
	out.erase("keys")
	out.erase("fps")
	if items.is_empty():
		return out
	var fps := S.fps
	var L := S.length()
	var nf := maxi(int(ceil(L * float(fps) - 1e-6)), 1) + 1
	var keep := B.state()
	var frames := []
	for i in items.size():
		frames.append([])
	for k in nf:
		var t := minf(float(k) / float(fps), L)
		S.apply(B, t)
		for i in items.size():
			(frames[i] as Array).append(attach_point(B, items[i]))
	B.set_state(keep)
	var keys := {}
	for i in items.size():
		keys.merge(keys_of(items[i], frames[i], fps))
	out["keys"] = keys
	out["fps"] = fps
	return out


## the segment angles (rad) of an item at time t, from its baked keys (linear between keys)
static func replay(sec: Dictionary, item: Dictionary, t: float) -> PackedFloat64Array:
	var n := int(item["n"])
	var name := String(item["name"])
	var keys: Dictionary = sec.get("keys", {})
	var r := PackedFloat64Array()
	r.resize(n)
	for i in n:
		r[i] = deg_to_rad(_key_at(keys.get("%s_%d" % [name, i + 1], []), t))
	var th := PackedFloat64Array()
	th.resize(n)
	var acc := 0.0
	for i in n:
		acc += r[i]
		th[i] = acc
	return th


## the value at t: a Catmull-Rom spline through the keys around t (exact at the keys; the keys are sub-step apart)
static func _key_at(ks: Array, t: float) -> float:
	var n := ks.size()
	if n == 0:
		return 0.0
	if t <= float(ks[0][0]):
		return float(ks[0][1])
	if t >= float(ks[n - 1][0]):
		return float(ks[n - 1][1])
	for i in range(1, n):
		var t1 := float(ks[i][0])
		if t <= t1:
			var t0 := float(ks[i - 1][0])
			var u := (t - t0) / maxf(t1 - t0, 1e-9)
			var p0 := float(ks[maxi(i - 2, 0)][1])
			var p1 := float(ks[i - 1][1])
			var p2 := float(ks[i][1])
			var p3 := float(ks[mini(i + 1, n - 1)][1])
			return 0.5 * (2.0 * p1 + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)
	return float(ks[n - 1][1])


## the points of an item's chain: the root, then each node (its length n segments along dir cos + sway sin)
static func points(item: Dictionary, attach: Vector3, th: PackedFloat64Array) -> PackedVector3Array:
	var dir := dir_of(item)
	var sw := sway_of(item)
	var ell := float(item["len"]) / float(int(item["n"]))
	var out := PackedVector3Array()
	var p := attach
	out.append(p)
	for i in th.size():
		p += ell * (dir * cos(th[i]) + sw * sin(th[i]))
		out.append(p)
	return out


## the item list with this item in it (same name replaced, else appended). The keys are not touched: bake again
static func with_item(sec: Dictionary, item: Dictionary) -> Dictionary:
	var out := sec.duplicate(true)
	var items: Array = out.get("items", [])
	var done := false
	for i in items.size():
		if String(items[i]["name"]) == String(item["name"]):
			items[i] = item.duplicate(true)
			done = true
	if not done:
		items.append(item.duplicate(true))
	out["items"] = items
	return out


## the names the file gives an item that is not yet in the block: "ponytail", "ponytail2", ...
static func free_name(sec: Dictionary, base: String) -> String:
	var names := []
	for it in sec.get("items", []):
		names.append(String(it["name"]))
	if not base in names:
		return base
	var k := 2
	while (base + str(k)) in names:
		k += 1
	return base + str(k)


## IN THE FILE (from_file reads it back): the items as they are, the keys and fps when baked
static func to_file(sec: Dictionary) -> Dictionary:
	return sec.duplicate(true)


static func from_file(d: Variant) -> Dictionary:
	if not d is Dictionary:
		return {}
	var items := []
	for it in d.get("items", []):
		var c := clean_item(it)
		if not c.is_empty() and not _has_name(items, String(c["name"])):
			items.append(c)
	if items.is_empty():
		return {}
	var out := {"items": items}
	var keys: Variant = d.get("keys", {})
	if keys is Dictionary and d.has("fps"):
		var kept := {}
		for it in items:
			for i in int(it["n"]):
				var j := "%s_%d" % [String(it["name"]), i + 1]
				if keys.has(j) and keys[j] is Array:
					var ks := []
					for p in keys[j]:
						if p is Array and p.size() == 2:
							ks.append([float(p[0]), float(p[1])])
					kept[j] = ks
		out["keys"] = kept
		out["fps"] = int(d["fps"])
	return out


static func _has_name(items: Array, nm: String) -> bool:
	for it in items:
		if String(it["name"]) == nm:
			return true
	return false


## one item from the file, or {} when it is not one (a bad joint, a kind, a count, a size: dropped on load)
static func clean_item(d: Variant) -> Dictionary:
	if not d is Dictionary:
		return {}
	var nm := String(d.get("name", ""))
	var kind := String(d.get("kind", ""))
	var att := String(d.get("attach", ""))
	var off: Variant = d.get("off", [])
	var sway := String(d.get("sway", ""))
	if nm == "" or not kind in KINDS or not att in Body.ORDER or not off is Array or off.size() != 3:
		return {}
	if not sway in ["x", "z"]:
		return {}
	var n := int(d.get("n", 0))
	var L := float(d.get("len", 0.0))
	var z := float(d.get("zeta", -1.0))
	if n < 1 or n > 12 or L <= 0.0 or L > 5.0 or z < 0.0 or z > 1.0:
		return {}
	var out := {"name": nm, "kind": kind, "attach": att, "off": [float(off[0]), float(off[1]), float(off[2])],
		"sway": sway, "n": n, "len": L, "zeta": z}
	if kind == "chain":
		var m := float(d.get("mass", 0.0))
		if m <= 0.0:
			return {}
		out["mass"] = m
	else:
		var E := float(d.get("E", 0.0))
		var dd := float(d.get("d", 0.0))
		var rho := float(d.get("rho", 0.0))
		if E <= 0.0 or dd <= 0.0 or rho <= 0.0:
			return {}
		out["E"] = E
		out["d"] = dd
		out["rho"] = rho
	return out


## MIRROR (Scene.MIRROR_SCENE "secondary"): the attach joint to its twin, the offset's x negated; a chain that swings
## along x swings the other way (its keys' angles negated). A chain swinging along z keeps its angles.
static func mirror_file(sec: Dictionary) -> Dictionary:
	var out := sec.duplicate(true)
	var items: Array = out.get("items", [])
	var keys: Dictionary = out.get("keys", {})
	for it in items:
		var old := String(it["attach"])
		it["attach"] = Body.twin(old)
		var o: Array = it["off"]
		it["off"] = [-float(o[0]), float(o[1]), float(o[2])]
		if String(it["sway"]) == "x":
			for i in int(it["n"]):
				var j := "%s_%d" % [String(it["name"]), i + 1]
				if keys.has(j):
					var ks: Array = []
					for p in keys[j]:
						ks.append([p[0], -float(p[1])])
					keys[j] = ks
	if not keys.is_empty():
		out["keys"] = keys
	return out
