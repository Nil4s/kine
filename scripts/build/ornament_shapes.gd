class_name OrnShapes
extends RefCounted
## s227 ORNAMENT SHAPES: organic shapes made in code (ridge beasts, corner beasts, finials, a lion, a dragon head, scrolls, a lotus base, domes).
## A shape is a list of SOFT PRIMITIVES (round cones, ellipsoids, rounded boxes) blended by a polynomial smooth-min, the way Blender's metaballs
## and Skin modifier blend, so a beast reads as one animal and not as touching balls. The blend is a signed field that is sampled on a grid,
## SURFACE NETS turns the zero level into a closed quad mesh (KMesh), ONE level of Catmull-Clark subdivision (KMeshSubdiv) smooths it, and its
## vertices are pulled back onto the field (a Newton step) so thin horns and tails keep their size. The result is a closed manifold KMesh, so
## meshsolid (PartMeshSolid) sews it into one solid. Everything is seeded: the same kind, seed and size give the same vertices, bit for bit.
## Design space: x along the ridge (the beast looks toward +x), y up, z across. build() scales the mesh to the asked box (mm) exactly, its
## bottom-centre at the origin, so the size you ask is the size you get.

const BIG := 1e6
const T_CONE := 0      # round cone from a to b, radius ra -> rb (a sphere when a == b); zf stretches z (a plate when > 1, a fat tube when < 1)
const T_ELL := 1       # ellipsoid: centre a, radii b, turned by basis
const T_BOX := 2       # rounded box: centre a, half sizes b, corner radius ra
const T_BELOW := 3     # the half space below the plane y = a.y (only used to cut a flat base)

var kind: PackedInt32Array = PackedInt32Array()
var A := PackedVector3Array()
var B := PackedVector3Array()
var RA := PackedFloat32Array()
var RB := PackedFloat32Array()
var ZF := PackedFloat32Array()
var K := PackedFloat32Array()
var INV: Array = []        # Basis per primitive (the inverse of its turn, for the ellipsoid)
var LO := PackedVector3Array()   # the box each primitive influences (its size + the blend + a margin)
var HI := PackedVector3Array()
var sub_from := 0          # primitives from this index on are SUBTRACTED from the union of the ones before
var rng := RandomNumberGenerator.new()
var _sub_mode := false
var base_cut := true


func _add(t: int, a: Vector3, b: Vector3, ra: float, rb: float, zf: float, k: float, inv: Basis, ext: Vector3) -> void:
	if _sub_mode and sub_from == 0:
		sub_from = kind.size()
	kind.append(t)
	A.append(a)
	B.append(b)
	RA.append(ra)
	RB.append(rb)
	ZF.append(zf)
	K.append(k)
	INV.append(inv)
	var m := ext + Vector3.ONE * (k + 0.02)
	LO.append(a - m)
	HI.append(a + m)


## a round cone from a to b (radius ra at a, rb at b); a == b is a sphere
func cone(a: Vector3, b: Vector3, ra: float, rb: float, k := 0.05, zf := 1.0) -> void:
	var lo := a.min(b)
	var hi := a.max(b)
	_add(T_CONE, a, b, ra, rb, zf, k, Basis(), Vector3.ZERO)
	var r := maxf(ra, rb) * maxf(1.0, 1.0 / maxf(zf, 0.05))
	var i := kind.size() - 1
	LO[i] = lo - Vector3.ONE * (r + k + 0.02)
	HI[i] = hi + Vector3.ONE * (r + k + 0.02)


func sph(c: Vector3, r: float, k := 0.05) -> void:
	cone(c, c, r, r, k)


## an ellipsoid with radii r, turned by euler angles (radians)
func ell(c: Vector3, r: Vector3, turn := Vector3.ZERO, k := 0.05) -> void:
	var bs := Basis.from_euler(turn)
	_add(T_ELL, c, r, 0.0, 0.0, 1.0, k, bs.inverse(), Vector3.ONE * maxf(r.x, maxf(r.y, r.z)))


## an ellipsoid whose long axis (y of its own) points along dir; wide and thick are its other two radii
func ell_dir(c: Vector3, dir: Vector3, long_r: float, wide: float, thick: float, k := 0.05) -> void:
	var y := dir.normalized()
	var x := y.cross(Vector3(0.0, 0.0, 1.0))
	if x.length() < 0.01:
		x = y.cross(Vector3(1.0, 0.0, 0.0))
	x = x.normalized()
	var z := x.cross(y).normalized()
	var bs := Basis(x, y, z)
	_add(T_ELL, c, Vector3(wide, long_r, thick), 0.0, 0.0, 1.0, k, bs.inverse(), Vector3.ONE * maxf(long_r, maxf(wide, thick)))


func rbox(c: Vector3, half: Vector3, r: float, k := 0.03) -> void:
	_add(T_BOX, c, half, r, 0.0, 1.0, k, Basis(), half)


## the tube along a smooth curve through the control points (Catmull-Clark-free: a Catmull-Rom spline, 6 samples a span), radius r0 -> r1
func tube(ctrl: Array, r0: float, r1: float, k := 0.05, zf := 1.0, per := 6) -> PackedVector3Array:
	var pts := spline(ctrl, per)
	var n := pts.size()
	for i in range(n - 1):
		var f0 := float(i) / float(n - 1)
		var f1 := float(i + 1) / float(n - 1)
		cone(pts[i], pts[i + 1], lerpf(r0, r1, f0), lerpf(r0, r1, f1), k, zf)
	return pts


## a solid of revolution about the y axis, as a chain of cones through (radius, height) rows
func lathe(rows: Array, k := 0.02) -> void:
	for i in range(rows.size() - 1):
		var p: Array = rows[i]
		var q: Array = rows[i + 1]
		cone(Vector3(0.0, float(p[1]), 0.0), Vector3(0.0, float(q[1]), 0.0), float(p[0]), float(q[0]), k)


func begin_cut() -> void:
	_sub_mode = true


static func spline(ctrl: Array, per := 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	if n < 3:
		for c in ctrl:
			out.append(c)
		return out
	for i in range(n - 1):
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, n - 1)]
		for s in per:
			var t := float(s) / float(per)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out


# ---------------------------------------------------------------------------------------------- the field
func _d(i: int, p: Vector3) -> float:
	var q := p - A[i]
	match kind[i]:
		T_CONE:
			var ba := B[i] - A[i]
			var zf := ZF[i]
			q.z *= zf
			ba.z *= zf
			var l2 := ba.length_squared()
			var t := 0.0
			if l2 > 1e-12:
				t = clampf(q.dot(ba) / l2, 0.0, 1.0)
			return (q - ba * t).length() - lerpf(RA[i], RB[i], t)
		T_ELL:
			var s: Vector3 = (INV[i] as Basis) * q
			var r := B[i]
			var k0 := Vector3(s.x / r.x, s.y / r.y, s.z / r.z).length()
			return (k0 - 1.0) * minf(r.x, minf(r.y, r.z))
		T_BOX:
			var h := B[i] - Vector3.ONE * RA[i]
			var w := Vector3(absf(q.x), absf(q.y), absf(q.z)) - h
			return Vector3(maxf(w.x, 0.0), maxf(w.y, 0.0), maxf(w.z, 0.0)).length() + minf(maxf(w.x, maxf(w.y, w.z)), 0.0) - RA[i]
		_:
			return p.y - A[i].y
	return BIG


static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


## the field at one point (negative inside); the union of the first primitives, minus the cut ones
func field(p: Vector3) -> float:
	var f := BIG
	var n := sub_from if sub_from > 0 else kind.size()
	for i in n:
		var lo := LO[i]
		var hi := HI[i]
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue
		f = smin(f, _d(i, p), K[i]) if f < BIG else _d(i, p)
	if sub_from > 0:
		for i in range(sub_from, kind.size()):
			var lo := LO[i]
			var hi := HI[i]
			if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
				continue
			f = -smin(-f, _d(i, p), K[i])
	return f


func bounds() -> AABB:
	var n := sub_from if sub_from > 0 else kind.size()
	var lo := Vector3(BIG, BIG, BIG)
	var hi := Vector3(-BIG, -BIG, -BIG)
	for i in n:
		match kind[i]:
			T_CONE:
				var r := maxf(RA[i], RB[i]) * maxf(1.0, 1.0 / maxf(ZF[i], 0.05))
				lo = lo.min(A[i].min(B[i]) - Vector3.ONE * r)
				hi = hi.max(A[i].max(B[i]) + Vector3.ONE * r)
			T_ELL:
				var rr := maxf(B[i].x, maxf(B[i].y, B[i].z))
				lo = lo.min(A[i] - Vector3.ONE * rr)
				hi = hi.max(A[i] + Vector3.ONE * rr)
			T_BOX:
				lo = lo.min(A[i] - B[i])
				hi = hi.max(A[i] + B[i])
	return AABB(lo, hi - lo)


## the closed quad mesh of the zero level (surface nets) on a grid of about `cells` cells along the longest side; null when it is not one closed manifold
func nets(cells: int, iso := 0.0) -> KMesh:
	var bb := bounds()
	var big := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var h := big / float(cells)
	var org := bb.position - Vector3.ONE * (h * 3.0)
	var nx := int(ceilf(bb.size.x / h)) + 7
	var ny := int(ceilf(bb.size.y / h)) + 7
	var nz := int(ceilf(bb.size.z / h)) + 7
	var F := PackedFloat32Array()
	F.resize(nx * ny * nz)
	F.fill(BIG)
	var nu := sub_from if sub_from > 0 else kind.size()
	for i in kind.size():
		var lo := (LO[i] - org) / h
		var hi := (HI[i] - org) / h
		var x0 := maxi(int(floorf(lo.x)), 0)
		var y0 := maxi(int(floorf(lo.y)), 0)
		var z0 := maxi(int(floorf(lo.z)), 0)
		var x1 := mini(int(ceilf(hi.x)), nx - 1)
		var y1 := mini(int(ceilf(hi.y)), ny - 1)
		var z1 := mini(int(ceilf(hi.z)), nz - 1)
		var cut := i >= nu and sub_from > 0
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var row := (z * ny + y) * nx
				for x in range(x0, x1 + 1):
					var d := _d(i, org + Vector3(x, y, z) * h)
					var c := row + x
					if cut:
						F[c] = -smin(-F[c], d, K[i])
					elif F[c] >= BIG:
						F[c] = d
					else:
						F[c] = smin(F[c], d, K[i])
	for c in F.size():
		F[c] -= iso
	_make_manifold(F, nx, ny, nz, h * 0.02)
	var cx := nx - 1
	var cy := ny - 1
	var cz := nz - 1
	var cell := PackedInt32Array()
	cell.resize(cx * cy * cz)
	cell.fill(-1)
	var verts := PackedVector3Array()
	var corner := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var fv := PackedFloat32Array()
	fv.resize(8)
	for z in cz:
		for y in cy:
			for x in cx:
				var mask := 0
				for c in 8:
					var o: Vector3i = corner[c]
					var v := F[((z + o.z) * ny + (y + o.y)) * nx + x + o.x]
					fv[c] = v
					if v < 0.0:
						mask |= 1 << c
				if mask == 0 or mask == 255:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in edges:
					var ia: int = e[0]
					var ib: int = e[1]
					var fa := fv[ia]
					var fb := fv[ib]
					if (fa < 0.0) != (fb < 0.0):
						var t := fa / (fa - fb)
						var oa: Vector3i = corner[ia]
						var ob: Vector3i = corner[ib]
						acc += Vector3(oa).lerp(Vector3(ob), t)
						cnt += 1
				cell[(z * cy + y) * cx + x] = verts.size()
				verts.append(org + (Vector3(x, y, z) + acc / float(cnt)) * h)
	var faces: Array = []
	for z in range(1, cz):
		for y in range(1, cy):
			for x in range(1, cx):
				var f0 := F[(z * ny + y) * nx + x] < 0.0
				# the three edges leaving this node in +x, +y, +z
				for ax in 3:
					var nxt := Vector3i(x + (1 if ax == 0 else 0), y + (1 if ax == 1 else 0), z + (1 if ax == 2 else 0))
					if nxt.x >= nx or nxt.y >= ny or nxt.z >= nz:
						continue
					var f1 := F[(nxt.z * ny + nxt.y) * nx + nxt.x] < 0.0
					if f0 == f1:
						continue
					var u := (ax + 1) % 3
					var w := (ax + 2) % 3
					var q: Array = []
					for s in [[-1, -1], [0, -1], [0, 0], [-1, 0]]:
						var o := Vector3i(x, y, z)
						o[u] += int(s[0])
						o[w] += int(s[1])
						q.append(cell[(o.z * cy + o.y) * cx + o.x])
					if q.has(-1):
						return null
					if not f0:
						q.reverse()
					faces.append(PackedInt32Array([q[0], q[1], q[2], q[3]]))
	if faces.is_empty():
		return null
	var km := KMesh.new().from_arrays(verts, faces)
	if km.boundary_edge_count() > 0 or not km.is_manifold():
		return null
	if _signed_volume(km) < 0.0:
		for i in km.faces.size():
			var pf: PackedInt32Array = km.faces[i]
			pf.reverse()
			km.faces[i] = pf
		km.rebuild()
	return km


static func _signed_volume(km: KMesh) -> float:
	var v := 0.0
	for fc in km.faces:
		var f: PackedInt32Array = fc
		for k in range(1, f.size() - 1):
			v += km.verts[f[0]].dot(km.verts[f[k]].cross(km.verts[f[k + 1]])) / 6.0
	return v


## pull every vertex onto the zero level (one Newton step along the field's gradient)
func project(km: KMesh, eps: float, steps := 1) -> void:
	for s in steps:
		for i in km.verts.size():
			var p := km.verts[i]
			var f := field(p)
			var g := Vector3(field(p + Vector3(eps, 0, 0)) - field(p - Vector3(eps, 0, 0)), field(p + Vector3(0, eps, 0)) - field(p - Vector3(0, eps, 0)), field(p + Vector3(0, 0, eps)) - field(p - Vector3(0, 0, eps)))
			var gl := g.length_squared()
			if gl < 1e-12:
				continue
			var step := -f * g / gl * 2.0 * eps
			if step.length() > eps * 4.0:
				step = step.normalized() * eps * 4.0
			km.verts[i] = p + step
		km.rebuild()


## for each of the 256 corner masks of a cube: the corners to flip so that its inside corners are one piece along the cube's edges and so are its
## outside corners (the cubes where naive surface nets makes a pinched, non-manifold skin). 0 = nothing to do
static var _fix: PackedInt32Array = PackedInt32Array()


static func _fix_table() -> PackedInt32Array:
	if _fix.size() == 256:
		return _fix
	var t := PackedInt32Array()
	t.resize(256)
	for mask in range(1, 255):
		var flip := 0
		for side in 2:
			var want := 1 if side == 0 else 0   # side 0: the inside corners, side 1: the outside ones
			var seen := 0
			var comps: Array = []
			for c0 in 8:
				if ((mask >> c0) & 1) != want or ((seen >> c0) & 1) == 1:
					continue
				var comp := 1 << c0
				var stack := [c0]
				seen |= 1 << c0
				while not stack.is_empty():
					var c: int = stack.pop_back()
					for b in 3:
						var n := c ^ (1 << b)
						if ((mask >> n) & 1) == want and ((seen >> n) & 1) == 0:
							seen |= 1 << n
							comp |= 1 << n
							stack.append(n)
				comps.append(comp)
			if comps.size() > 1:
				var keep := 0
				for i in comps.size():
					if _bits(comps[i]) > _bits(comps[keep]):
						keep = i
				for i in comps.size():
					if i != keep:
						flip |= comps[i]
				break   # one side per pass; the loop in _make_manifold comes back
		t[mask] = flip
	_fix = t
	return t


static func _bits(m: int) -> int:
	var n := 0
	while m != 0:
		n += m & 1
		m >>= 1
	return n


## flip the nodes of every cube whose inside (or outside) corners are cut in two, until none is left (a few passes)
static func _make_manifold(F: PackedFloat32Array, nx: int, ny: int, nz: int, eps: float) -> void:
	var tab := _fix_table()
	for pass_i in 12:
		var changed := 0
		for z in nz - 1:
			for y in ny - 1:
				for x in nx - 1:
					var i0 := (z * ny + y) * nx + x
					var mask := 0
					if F[i0] < 0.0: mask |= 1
					if F[i0 + 1] < 0.0: mask |= 2
					if F[i0 + nx] < 0.0: mask |= 4
					if F[i0 + nx + 1] < 0.0: mask |= 8
					var i1 := i0 + nx * ny
					if F[i1] < 0.0: mask |= 16
					if F[i1 + 1] < 0.0: mask |= 32
					if F[i1 + nx] < 0.0: mask |= 64
					if F[i1 + nx + 1] < 0.0: mask |= 128
					if mask == 0 or mask == 255:
						continue
					var fl := tab[mask]
					if fl == 0:
						continue
					for c in 8:
						if (fl >> c) & 1 == 1:
							var idx := ((z + ((c >> 2) & 1)) * ny + (y + ((c >> 1) & 1))) * nx + x + (c & 1)
							F[idx] = eps if F[idx] < 0.0 else -eps
					changed += 1
		if changed == 0:
			return


## only the biggest connected shell of `km` (the specks a thin feature leaves behind are dropped); `km` itself when it is one shell already
static func keep_largest(km: KMesh) -> KMesh:
	var par := PackedInt32Array()
	par.resize(km.verts.size())
	for i in par.size():
		par[i] = i
	for fc in km.faces:
		var f: PackedInt32Array = fc
		for k in range(1, f.size()):
			var a := _find(par, f[0])
			var b := _find(par, f[k])
			if a != b:
				par[a] = b
	var cnt := {}
	for fc in km.faces:
		var r := _find(par, (fc as PackedInt32Array)[0])
		cnt[r] = int(cnt.get(r, 0)) + 1
	if cnt.size() <= 1:
		return km
	var best := -1
	for r in cnt:
		if best < 0 or int(cnt[r]) > int(cnt[best]):
			best = r
	var remap := {}
	var vs := PackedVector3Array()
	var fs: Array = []
	for fc in km.faces:
		var f2: PackedInt32Array = fc
		if _find(par, f2[0]) != best:
			continue
		var nf := PackedInt32Array()
		for vi in f2:
			if not remap.has(vi):
				remap[vi] = vs.size()
				vs.append(km.verts[vi])
			nf.append(remap[vi])
		fs.append(nf)
	return KMesh.new().from_arrays(vs, fs)


static func _find(par: PackedInt32Array, i: int) -> int:
	while par[i] != i:
		par[i] = par[par[i]]
		i = par[i]
	return i
