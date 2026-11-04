class_name KMeshRetopoFill
extends RefCounted
## I11: the PATCH FILL of stroke-guided retopology, the GDScript twin of native/src/kine_retopo_native.cpp (plan / fill).
## Same integer system, same vertex order, same operation order, plain floats (64-bit) in flat arrays, so the two agree to 1e-9
## (tests/i11_test.gd bar 7). The C++ is the fast path; this is the reference and the fallback.
##
## METHOD: Takayama, Panozzo, Sorkine-Hornung and Sorkine-Hornung, "Sketch-Based Generation and Editing of Quad Meshes",
## ACM Transactions on Graphics 32(4) (SIGGRAPH 2013), art. 97: strokes cut the surface into patches of 2 to 6 sides, each side
## has an edge count, and the patch is filled from a small dictionary of quad topologies chosen by those counts. Written
## here from the paper's idea; no QuadriFlow or AGPL code was read or used.
##
## THE DICTIONARY (sides counted ccw seen from outside, d_i edges on side i):
##   4 sides   one grid a x b; needs d0 = d2 and d1 = d3.                                    0 interior singularities
##   3,5,6     n sub-grids round ONE centre vertex of valence n, joined by n spokes to a vertex of each side. Side i is cut
##             at f_i from its start (g_i = d_i - f_i left). A sub-grid has opposite sides equal, which gives
##                 f_i + f_(i+2) = d_i,   spoke_i = f_(i+1) edges,
##             solved over the integers by f_i = 1/2 * sum_k (-1)^k d_(i+2k) (k over the cycle i, i+2, ...: n for odd n, n/2
##             for n = 6); it needs an even sum and 1 <= f_i < d_i.                          1 singularity (valence n)
##   2 sides   two valence-3 vertices X, Y: end grids alpha x beta at both ends and a band of width p between; a = 2 alpha + p,
##             b = 2 beta + p (same parity, both >= 3); p is enumerated for the most square end grid.   2 singularities
## Why these are the fewest: a quad disk obeys sum over interior (4 - valence) + sum over border (3 - valence) = 4. A side
## corner of valence 2 adds 1, so n corners leave 4 - n for the interior: +2 (two valence-3), +1 (valence 3), 0, -1 (valence 5),
## -2 (one valence-6 vertex) for n = 2, 3, 4, 5, 6.
const MIN_SING := {2: 2, 3: 1, 4: 0, 5: 1, 6: 1}   # interior singular vertices of the patch with n sides


## the integer plan for side counts d: {"ok", "kind", "reason", "n", "f", "p", "alpha", "beta", "singular" (their valences)}
static func plan(d: PackedInt32Array) -> Dictionary:
	var n := d.size()
	var pl := {"ok": false, "kind": "none", "reason": "", "n": n, "f": PackedInt32Array(), "p": 0, "alpha": 0, "beta": 0, "singular": PackedInt32Array()}
	for x in d:
		if x < 1:
			pl["reason"] = "a side has no edges"
			return pl
	if n == 4:
		pl["kind"] = "quad"
		if d[0] != d[2] or d[1] != d[3]:
			pl["reason"] = "opposite sides of a 4-sided patch need equal counts"
			return pl
		pl["ok"] = true
		return pl
	if n == 3 or n == 5 or n == 6:
		pl["kind"] = "tri" if n == 3 else ("pent" if n == 5 else "hex")
		var m := n if n % 2 == 1 else n / 2
		var f := PackedInt32Array()
		f.resize(n)
		for i in n:
			var s := 0
			var sign := 1
			for k in m:
				s += sign * d[(i + 2 * k) % n]
				sign = -sign
			if (s & 1) != 0:
				pl["reason"] = "the side counts need an even parity (the sum of alternate sides is odd)"
				return pl
			var fi := s / 2
			if fi < 1 or fi > d[i] - 1:
				pl["reason"] = "one side is too long for the others (the triangle inequality of the counts fails)"
				return pl
			f[i] = fi
		pl["f"] = f
		pl["singular"] = PackedInt32Array([n])
		pl["ok"] = true
		return pl
	if n == 2:
		pl["kind"] = "digon"
		var a := d[0]
		var b := d[1]
		if ((a + b) & 1) != 0:
			pl["reason"] = "the two sides of a 2-sided patch need counts of the same parity"
			return pl
		if a < 3 or b < 3:
			pl["reason"] = "a 2-sided patch needs at least 3 edges on each side"
			return pl
		var mn := mini(a, b)
		var best := -1
		var bscore := 1 << 30
		var p := mn - 2
		while p >= 1:
			if ((p - a) & 1) == 0:
				var al := (a - p) / 2
				var be := (b - p) / 2
				if al >= 1 and be >= 1:
					var sc := absi(al - be)
					if sc < bscore:
						bscore = sc
						best = p
			p -= 1
		if best < 0:
			pl["reason"] = "no 2-sided topology fits these counts"
			return pl
		pl["p"] = best
		pl["alpha"] = (a - best) / 2
		pl["beta"] = (b - best) / 2
		pl["singular"] = PackedInt32Array([3, 3])
		pl["ok"] = true
		return pl
	pl["reason"] = "only 2 to 6 sided patches are filled"
	return pl


## sides: Array of PackedFloat64Array (xyz flat; side i has d_i + 1 points). -> {"ok", "reason", "kind", "verts" (PackedFloat64Array),
## "quads" (PackedInt32Array, 4 per), "nring", "singular" (ids of the interior singular verts)}
static func fill(sides: Array) -> Dictionary:
	var n := sides.size()
	var d := PackedInt32Array()
	d.resize(n)
	for i in n:
		var s: PackedFloat64Array = sides[i]
		if s.size() < 6 or s.size() % 3 != 0:
			return {"ok": false, "reason": "a side needs at least 2 points", "kind": "none"}
		d[i] = s.size() / 3 - 1
	var pl := plan(d)
	if not pl["ok"]:
		return {"ok": false, "reason": pl["reason"], "kind": pl["kind"]}
	var b := _B.new()
	b.n = n
	b.d = d
	b.off = PackedInt32Array()
	b.off.resize(n)
	var o := 0
	for i in n:
		b.off[i] = o
		o += d[i]
	b.nring = o
	for i in n:
		var s: PackedFloat64Array = sides[i]
		for k in d[i]:
			b.addv(s[k * 3], s[k * 3 + 1], s[k * 3 + 2])
	if n == 4:
		var a := d[0]
		var bb := d[1]
		var bottom := []
		var right := []
		var top := []
		var left := []
		for k in a + 1:
			bottom.append(b.ring(0, k))
		for k in bb + 1:
			right.append(b.ring(1, k))
		for i in a + 1:
			top.append(b.ring(2, a - i))
		for j in bb + 1:
			left.append(b.ring(3, bb - j))
		b.grid(bottom, right, top, left)
	elif n == 3 or n == 5 or n == 6:
		var f: PackedInt32Array = pl["f"]
		var sx := 0.0
		var sy := 0.0
		var sz := 0.0
		for r in b.nring:
			sx += b.P[r * 3]
			sy += b.P[r * 3 + 1]
			sz += b.P[r * 3 + 2]
		var c := b.addv(sx / b.nring, sy / b.nring, sz / b.nring)
		b.special.append(c)
		var spoke := []
		for k in n:
			spoke.append(b.line(c, b.ring(k, f[k]), f[(k + 1) % n]))
		for i in n:
			var A := f[(i + 1) % n]
			var Bg := d[i] - f[i]
			var bottom: Array = spoke[i]
			var right := []
			var top := []
			var left := []
			for j in Bg + 1:
				right.append(b.ring(i, f[i] + j))
			for iu in A + 1:
				top.append(b.ring((i + 1) % n, A - iu))
			var sp: Array = spoke[(i + 1) % n]
			for j in Bg + 1:
				left.append(sp[j])
			b.grid(bottom, right, top, left)
	else:
		var a := d[0]
		var bb := d[1]
		var p: int = pl["p"]
		var al: int = pl["alpha"]
		var be: int = pl["beta"]
		var pp := b.ring(0, 0)
		var qq := b.ring(0, a)
		var a1 := b.ring(0, al)
		var b1 := b.ring(1, bb - be)
		var x := b.addv(b.P[a1 * 3] + b.P[b1 * 3] - b.P[pp * 3], b.P[a1 * 3 + 1] + b.P[b1 * 3 + 1] - b.P[pp * 3 + 1], b.P[a1 * 3 + 2] + b.P[b1 * 3 + 2] - b.P[pp * 3 + 2])
		var a2 := b.ring(0, a - al)
		var b2 := b.ring(1, be)
		var y := b.addv(b.P[a2 * 3] + b.P[b2 * 3] - b.P[qq * 3], b.P[a2 * 3 + 1] + b.P[b2 * 3 + 1] - b.P[qq * 3 + 1], b.P[a2 * 3 + 2] + b.P[b2 * 3 + 2] - b.P[qq * 3 + 2])
		b.special.append(x)
		b.special.append(y)
		var sXA := b.line(a1, x, be)
		var sXB := b.line(x, b1, al)
		var path := b.line(x, y, p)
		var sYA := b.line(a2, y, be)
		var sYB := b.line(y, b2, al)
		var bottom := []
		var top := []
		var left := []
		for k in al + 1:
			bottom.append(b.ring(0, k))
		for i in al + 1:
			top.append(sXB[al - i])
		for j in be + 1:
			left.append(b.ring(1, bb - j))
		b.grid(bottom, sXA, top, left)
		bottom = []
		for k in p + 1:
			bottom.append(b.ring(0, al + k))
		b.grid(bottom, sYA, path, sXA)
		top = []
		for i in p + 1:
			top.append(b.ring(1, bb - be - i))
		b.grid(path, sYB, top, sXB)
		bottom = []
		var right := []
		for k in al + 1:
			bottom.append(b.ring(0, a - al + k))
		for k in be + 1:
			right.append(b.ring(1, k))
		b.grid(bottom, right, sYB, sYA)
	var pv := PackedFloat64Array(b.P)
	var qv := PackedInt32Array(b.Q)
	return {"ok": true, "reason": "", "kind": pl["kind"], "verts": pv, "quads": qv, "nring": b.nring, "singular": PackedInt32Array(b.special)}


class _B:
	extends RefCounted
	var n := 0
	var d := PackedInt32Array()
	var off := PackedInt32Array()
	var nring := 0
	var P: Array = []   # flat floats
	var Q: Array = []
	var special: Array = []

	func ring(i: int, k: int) -> int:
		return off[(i + 1) % n] if k == d[i] else off[i] + k

	func addv(x: float, y: float, z: float) -> int:
		P.append(x)
		P.append(y)
		P.append(z)
		return P.size() / 3 - 1

	func line(a: int, b: int, m: int) -> Array:
		var out := [a]
		for t in range(1, m):
			var w := float(t) / float(m)
			var x: float = P[a * 3] + (P[b * 3] - P[a * 3]) * w
			var y: float = P[a * 3 + 1] + (P[b * 3 + 1] - P[a * 3 + 1]) * w
			var z: float = P[a * 3 + 2] + (P[b * 3 + 2] - P[a * 3 + 2]) * w
			out.append(addv(x, y, z))
		out.append(b)
		return out

	func grid(bottom: Array, right: Array, top: Array, left: Array) -> void:
		var A := bottom.size() - 1
		var Bn := left.size() - 1
		var g := []
		for i in A + 1:
			var col := []
			col.resize(Bn + 1)
			col.fill(-1)
			g.append(col)
		for i in A + 1:
			g[i][0] = bottom[i]
			g[i][Bn] = top[i]
		for j in Bn + 1:
			g[0][j] = left[j]
			g[A][j] = right[j]
		var c00 := [P[bottom[0] * 3], P[bottom[0] * 3 + 1], P[bottom[0] * 3 + 2]]
		var c10 := [P[bottom[A] * 3], P[bottom[A] * 3 + 1], P[bottom[A] * 3 + 2]]
		var c01 := [P[top[0] * 3], P[top[0] * 3 + 1], P[top[0] * 3 + 2]]
		var c11 := [P[top[A] * 3], P[top[A] * 3 + 1], P[top[A] * 3 + 2]]
		for j in range(1, Bn):
			for i in range(1, A):
				var u := float(i) / float(A)
				var v := float(j) / float(Bn)
				var r := [0.0, 0.0, 0.0]
				for c in 3:
					r[c] = (1.0 - v) * P[bottom[i] * 3 + c] + v * P[top[i] * 3 + c] + (1.0 - u) * P[left[j] * 3 + c] + u * P[right[j] * 3 + c] \
							- ((1.0 - u) * (1.0 - v) * c00[c] + u * (1.0 - v) * c10[c] + (1.0 - u) * v * c01[c] + u * v * c11[c])
				g[i][j] = addv(r[0], r[1], r[2])
		for j in Bn:
			for i in A:
				Q.append(g[i][j])
				Q.append(g[i + 1][j])
				Q.append(g[i + 1][j + 1])
				Q.append(g[i][j + 1])
