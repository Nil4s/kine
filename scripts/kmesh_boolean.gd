class_name KMeshBoolean
extends RefCounted
## B10 (docs/ROADMAP_400.md): BOOLEANS on closed meshes, union / difference / intersect. Own implementation:
##  1 both meshes are triangulated (KMeshTopo.face_tris; every triangle remembers its face and corners) and their
##    points go into one pool in float64. Points within the SNAP tolerance of each other become one point (a grid hash),
##    so a vertex of B lying on a vertex of A is shared, not doubled.
##  2 broad phase: only triangles whose box meets the overlap of the two boxes; B's go in a uniform grid.
##  3 triangle / triangle: the signed distances of each triangle's corners to the other's plane (float64, |d| < SNAP
##    counts as 0, so "on the plane" is decided once per vertex and the same everywhere). Non-coplanar: each triangle
##    cut by the other's plane gives a segment on the common line, their overlap is the intersection segment; an edge's
##    crossing point is always computed from the lower vertex id, so the two triangles of that edge get the same point.
##    Coplanar (every corner of one within SNAP of the other's plane): the edges of each, clipped to the other, become
##    cut lines in it, and the pair is remembered for the classification.
##  4 every triangle with points or cut lines is re-triangulated in its own plane: points inserted one by one (a point
##    within SNAP of an edge splits the edge, of a corner IS the corner), then each cut line forced in by edge flips
##    (Sloan). A point on a triangle's edge is also put in the triangle across that edge, so there is no T-junction.
##  5 classify: a piece inside a coplanar partner is "on" B (same or opposite facing); the rest are flood-filled into
##    patches that never cross a cut line, and one point per patch (the centroid of its biggest piece) is tested with the
##    generalised winding number (sum of solid angles of the other mesh's triangles; > 0.5 = inside).
##  6 keep: union = A out + B out; intersect = A in + B in; difference = A out + B in (flipped). The coplanar region is
##    kept once, from A: union / intersect when both face the same way, difference when they face apart; never from B.
##    So two cubes touching face to face union into one box with no wall between them.
##  7 rebuild: a face that was not cut comes back as it was (same corners, same order). The pieces of a cut face are
##    joined back into one n-gon where that is clean (one border loop, a disc, and a fan from one of its corners covers it
##    without folding, so to_array_mesh and the face-fan volume stay right); else they stay triangles.
## Attributes (A09) of the target A: face channels copied from the source face; corner channels (UV ...) interpolated
## barycentrically in the source triangle (exact on a face that was not cut); vert channels kept on old verts and
## interpolated on new ones; LABEL channels (KMesh.LABEL_ATTRS) take the nearest corner's value, never a blend; edge
## channels (crease) restart at their default. The operand B's pieces take B's channel of the same name if it has one.
## ROBUST: generic positions; vertices / edges / faces of B lying exactly on A's (shared corners, edges in a face, faces
## in one plane, same or opposite facing), up to SNAP = 1e-6 x the scene diagonal, at least 1e-5 m (KMeshValidate.WELD:
## closer points would be reported as doubled); nested and disjoint operands.
## NOT ROBUST: features smaller than SNAP (they are welded); two surfaces crossing at a grazing angle below ~SNAP / size
## (treated as coplanar); open or self-intersecting inputs (refused when open; self-intersection is not checked: the
## winding number then counts the overlap twice). A cut line that cannot be forced in (crossing another cut, only from
## numerical trouble) is counted in last["unresolved"]; the result may then not be closed.
## Two parts that touch only along an edge or at a point give a non-manifold union: that is the shape, not a bug.
## Speed: GDScript; 2 x 5120 triangles overlapping in ~1-2 s. A triangle crossed by a very long cut (hundreds of points)
## re-triangulates in O(n^2) and is the slow case.

const OPS := ["union", "difference", "intersect"]
const NAMES := {"union": "Union", "difference": "Difference", "intersect": "Intersect"}
const SNAP_REL := 1e-6    # the snapping tolerance, relative to the diagonal of both meshes' box ...
const SNAP_MIN := KMeshValidate.WELD   # ... and never under the distance at which validate calls two verts doubled (m)

## message of the last refused call (empty after a success); each names a next step
static var last_error := ""
## what the last run did: pairs tested, segments, split triangles, pieces, patches, unresolved cut lines, ms ...
static var last := {}


## A op B as a new KMesh (A and B are not changed); null with last_error set when an input is not closed or op is unknown.
static func run(a: KMesh, b: KMesh, op: String) -> KMesh:
	last_error = ""
	last = {}
	if not OPS.has(op):
		last_error = "no boolean called '%s'. Pick one of %s." % [op, ", ".join(OPS)]
		return null
	for m in [a, b]:
		if m.face_count() == 0 or not m.is_closed():
			last_error = "the %s is not closed (%d border edges): a boolean needs closed meshes. Fill its holes first (Repair, or F)." % ["target" if m == a else "operand", m.boundary_edge_count()]
			return null
	var t0 := Time.get_ticks_usec()
	var r := _Run.new()
	var res := r.go(a, b, op)
	last = r.stats
	last["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return res


# ---------------------------------------------------------------- one run

class _Run:
	var eps := 1e-6
	var cellsz := 2e-6
	var stats := {"pairs": 0, "segments": 0, "coplanar_pairs": 0, "split_tris": 0, "pieces": 0, "patches": 0,
		"unresolved": 0, "clamped": 0, "aliased": 0, "ngons": 0, "faces_as_were": 0, "tri_faces": 0}
	# the point pool (float64) and its union-find (points found to be one are joined)
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var pz := PackedFloat64Array()
	var uf := PackedInt32Array()
	var head := {}                       # Vector3i cell -> last point hashed into it
	var chain := PackedInt32Array()      # previous point of the same cell, -1
	var ob := PackedFloat64Array()       # the overlap box: lo x y z, hi x y z (grown by eps)
	# triangles of both meshes: A's first (0 .. na - 1), then B's
	var na := 0
	var tv := PackedInt32Array()         # 3 points each
	var tface := PackedInt32Array()      # source face
	var tcorner := PackedInt32Array()    # 3 source corners (face_he0 + i)
	var tsv := PackedInt32Array()        # 3 source verts
	var tn := PackedFloat64Array()       # unit normal x y z (0 0 0 = degenerate)
	var td := PackedFloat64Array()       # plane offset n . p
	var tax := PackedInt32Array()        # projection code: 2 * dominant axis + (1 when that component is negative)
	var pts := {}                        # tri -> PackedInt32Array of points inside it (cut ends)
	var segs := {}                       # tri -> PackedInt32Array, pairs: cut lines
	var copl := {}                       # tri -> PackedInt32Array of coplanar partners
	var epts := {}                       # edge key (min << 32 | max) -> PackedInt32Array of points on that edge
	var cut_list := PackedInt32Array()   # pairs: every forced cut line (global points)
	var gsrc_a := {}                     # point -> A vertex it came from
	var gsrc_b := {}
	var face_cut := [{}, {}]             # per side: face -> true when one of its triangles was split
	var face_ntri := [PackedInt32Array(), PackedInt32Array()]
	var _vg := [PackedInt32Array(), PackedInt32Array()]   # per side: vertex -> its point
	# pieces (the triangles after splitting)
	var pv := PackedInt32Array()
	var ptri := PackedInt32Array()
	# the local triangulation in progress
	var _u := 0.0
	var _v := 0.0
	var l_ids := PackedInt32Array()
	var l_u := PackedFloat64Array()
	var l_v := PackedFloat64Array()
	var l_al := PackedInt32Array()
	var l_tris := PackedInt32Array()
	var l_cons := {}

	func find(i: int) -> int:
		while uf[i] != i:
			uf[i] = uf[uf[i]]
			i = uf[i]
		return i

	func join(a: int, b: int) -> void:
		var ra := find(a)
		var rb := find(b)
		if ra != rb:
			uf[maxi(ra, rb)] = mini(ra, rb)
			stats["aliased"] += 1

	static func ekey(a: int, b: int) -> int:
		return (mini(a, b) << 32) | maxi(a, b)

	func _in_ob(x: float, y: float, z: float) -> bool:
		return x >= ob[0] and y >= ob[1] and z >= ob[2] and x <= ob[3] and y <= ob[4] and z <= ob[5]

	## a point of the pool: an existing one within eps (only points inside the overlap box are hashed and looked up)
	func add_point(x: float, y: float, z: float) -> int:
		var hashed := _in_ob(x, y, z)
		var c := Vector3i.ZERO
		if hashed:
			c = Vector3i(floori(x / cellsz), floori(y / cellsz), floori(z / cellsz))
			var e2 := eps * eps
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var q: int = head.get(c + Vector3i(dx, dy, dz), -1)
						while q != -1:
							var ddx := px[q] - x
							var ddy := py[q] - y
							var ddz := pz[q] - z
							if ddx * ddx + ddy * ddy + ddz * ddz <= e2:
								return find(q)
							q = chain[q]
		var id := px.size()
		px.append(x)
		py.append(y)
		pz.append(z)
		uf.append(id)
		chain.append(-1)
		if hashed:
			chain[id] = head.get(c, -1)
			head[c] = id
		return id

	# ------------------------------------------------------------ setup

	func go(a: KMesh, b: KMesh, op: String) -> KMesh:
		var lo := [INF, INF, INF, INF, INF, INF]   # a lo, b lo
		var hi := [-INF, -INF, -INF, -INF, -INF, -INF]
		for s in 2:
			var m: KMesh = a if s == 0 else b
			for p in m.verts:
				for k in 3:
					lo[s * 3 + k] = minf(lo[s * 3 + k], p[k])
					hi[s * 3 + k] = maxf(hi[s * 3 + k], p[k])
		var diag := 0.0
		for k in 3:
			var d := maxf(hi[k], hi[3 + k]) - minf(lo[k], lo[3 + k])
			diag += d * d
		eps = maxf(SNAP_MIN, SNAP_REL * sqrt(diag))
		cellsz = eps * 2.0
		ob.resize(6)
		for k in 3:
			ob[k] = maxf(lo[k], lo[3 + k]) - eps
			ob[3 + k] = minf(hi[k], hi[3 + k]) + eps
		_add_mesh(a, 0)
		na = tface.size()
		_add_mesh(b, 1)
		if ob[0] <= ob[3] and ob[1] <= ob[4] and ob[2] <= ob[5]:
			_broad()
		_split_all()
		var keep := _classify(op)
		return _build(a, b, op, keep)

	func _add_mesh(m: KMesh, side: int) -> void:
		var nv := m.verts.size()
		var gid := PackedInt32Array()
		gid.resize(nv)
		var src: Dictionary = gsrc_a if side == 0 else gsrc_b
		for v in nv:
			var p := m.verts[v]
			gid[v] = add_point(p.x, p.y, p.z)
			if not src.has(gid[v]):
				src[gid[v]] = v
		_vg[side] = gid
		var he0 := m.face_he0
		var cnt := PackedInt32Array()
		cnt.resize(m.faces.size())
		for fi in m.faces.size():
			var f: PackedInt32Array = m.faces[fi]
			var tr: Array = [[0, 1, 2]] if f.size() == 3 else KMeshTopo.face_tris(m, f)
			cnt[fi] = tr.size()
			for t in tr:
				var c0: int = t[0]
				var c1: int = t[1]
				var c2: int = t[2]
				_add_tri(gid[f[c0]], gid[f[c1]], gid[f[c2]], fi)
				tcorner.append(he0[fi] + c0)
				tcorner.append(he0[fi] + c1)
				tcorner.append(he0[fi] + c2)
				tsv.append(f[c0])
				tsv.append(f[c1])
				tsv.append(f[c2])
		face_ntri[side] = cnt

	func _add_tri(a: int, b: int, c: int, fi: int) -> void:
		tv.append(a)
		tv.append(b)
		tv.append(c)
		tface.append(fi)
		var ux := px[b] - px[a]
		var uy := py[b] - py[a]
		var uz := pz[b] - pz[a]
		var vx := px[c] - px[a]
		var vy := py[c] - py[a]
		var vz := pz[c] - pz[a]
		var nx := uy * vz - uz * vy
		var ny := uz * vx - ux * vz
		var nz := ux * vy - uy * vx
		var l := sqrt(nx * nx + ny * ny + nz * nz)
		if l > 1e-300:
			nx /= l
			ny /= l
			nz /= l
		else:
			nx = 0.0
			ny = 0.0
			nz = 0.0
		tn.append(nx)
		tn.append(ny)
		tn.append(nz)
		td.append(nx * px[a] + ny * py[a] + nz * pz[a])
		var ax := absf(nx)
		var ay := absf(ny)
		var az := absf(nz)
		var k := 0
		var comp := nx
		if ay > ax and ay >= az:
			k = 1
			comp = ny
		elif az > ax and az > ay:
			k = 2
			comp = nz
		tax.append(k * 2 + (1 if comp < 0.0 else 0))

	func _degen(t: int) -> bool:
		return tn[3 * t] == 0.0 and tn[3 * t + 1] == 0.0 and tn[3 * t + 2] == 0.0

	# ------------------------------------------------------------ broad phase

	func _box(t: int, out: PackedFloat64Array) -> void:
		var a := tv[3 * t]
		var b := tv[3 * t + 1]
		var c := tv[3 * t + 2]
		out[0] = minf(px[a], minf(px[b], px[c]))
		out[1] = minf(py[a], minf(py[b], py[c]))
		out[2] = minf(pz[a], minf(pz[b], pz[c]))
		out[3] = maxf(px[a], maxf(px[b], px[c]))
		out[4] = maxf(py[a], maxf(py[b], py[c]))
		out[5] = maxf(pz[a], maxf(pz[b], pz[c]))

	func _broad() -> void:
		var nt := tface.size()
		var bx := PackedFloat64Array()
		bx.resize(nt * 6)
		var tmp := PackedFloat64Array()
		tmp.resize(6)
		var ins := PackedInt32Array()   # B triangles meeting the overlap box
		var ina := PackedInt32Array()
		for t in nt:
			_box(t, tmp)
			for k in 6:
				bx[t * 6 + k] = tmp[k]
			if tmp[3] < ob[0] or tmp[4] < ob[1] or tmp[5] < ob[2] or tmp[0] > ob[3] or tmp[1] > ob[4] or tmp[2] > ob[5]:
				continue
			if t < na:
				ina.append(t)
			else:
				ins.append(t)
		if ins.is_empty() or ina.is_empty():
			return
		var res := clampi(int(ceil(pow(float(ins.size()), 1.0 / 3.0) * 1.5)), 1, 48)
		var csz := PackedFloat64Array([maxf((ob[3] - ob[0]) / res, 1e-12), maxf((ob[4] - ob[1]) / res, 1e-12), maxf((ob[5] - ob[2]) / res, 1e-12)])
		var ncell := res * res * res
		var start := PackedInt32Array()
		start.resize(ncell + 1)
		var rng := PackedInt32Array()
		rng.resize(6)
		# CSR: count, then fill
		for pass_i in 2:
			var fill := PackedInt32Array()
			if pass_i == 1:
				var acc := 0
				for ci in ncell:
					var n := start[ci]
					start[ci] = acc
					acc += n
				start[ncell] = acc
				fill = start.duplicate()
			var lst := PackedInt32Array()
			if pass_i == 1:
				lst.resize(start[ncell])
			for t in ins:
				_cells(bx, t, csz, res, rng)
				for ix in range(rng[0], rng[3] + 1):
					for iy in range(rng[1], rng[4] + 1):
						for iz in range(rng[2], rng[5] + 1):
							var ci := (ix * res + iy) * res + iz
							if pass_i == 0:
								start[ci] += 1
							else:
								lst[fill[ci]] = t
								fill[ci] += 1
			if pass_i == 1:
				_query(bx, ina, csz, res, start, lst)

	func _cells(bx: PackedFloat64Array, t: int, csz: PackedFloat64Array, res: int, rng: PackedInt32Array) -> void:
		for k in 3:
			rng[k] = clampi(floori((maxf(bx[t * 6 + k], ob[k]) - ob[k]) / csz[k]), 0, res - 1)
			rng[3 + k] = clampi(floori((minf(bx[t * 6 + 3 + k], ob[3 + k]) - ob[k]) / csz[k]), 0, res - 1)

	func _query(bx: PackedFloat64Array, ina: PackedInt32Array, csz: PackedFloat64Array, res: int, start: PackedInt32Array, lst: PackedInt32Array) -> void:
		var stamp := PackedInt32Array()
		stamp.resize(tface.size())
		stamp.fill(-1)
		var rng := PackedInt32Array()
		rng.resize(6)
		for ta in ina:
			_cells(bx, ta, csz, res, rng)
			for ix in range(rng[0], rng[3] + 1):
				for iy in range(rng[1], rng[4] + 1):
					for iz in range(rng[2], rng[5] + 1):
						var ci := (ix * res + iy) * res + iz
						for j in range(start[ci], start[ci + 1]):
							var tb := lst[j]
							if stamp[tb] == ta:
								continue
							stamp[tb] = ta
							if bx[ta * 6 + 3] < bx[tb * 6] - eps or bx[tb * 6 + 3] < bx[ta * 6] - eps or bx[ta * 6 + 4] < bx[tb * 6 + 1] - eps \
									or bx[tb * 6 + 4] < bx[ta * 6 + 1] - eps or bx[ta * 6 + 5] < bx[tb * 6 + 2] - eps or bx[tb * 6 + 5] < bx[ta * 6 + 2] - eps:
								continue
							_pair(ta, tb)

	# ------------------------------------------------------------ triangle / triangle

	## signed distance of point p to triangle t's plane, 0 within eps
	func _sd(t: int, p: int) -> float:
		var d := tn[3 * t] * px[p] + tn[3 * t + 1] * py[p] + tn[3 * t + 2] * pz[p] - td[t]
		return 0.0 if absf(d) < eps else d

	func _pair(ta: int, tb: int) -> void:
		stats["pairs"] += 1
		if _degen(ta) or _degen(tb):
			return
		var s0 := _sd(ta, tv[3 * tb])
		var s1 := _sd(ta, tv[3 * tb + 1])
		var s2 := _sd(ta, tv[3 * tb + 2])
		if (s0 > 0.0 and s1 > 0.0 and s2 > 0.0) or (s0 < 0.0 and s1 < 0.0 and s2 < 0.0):
			return
		var r0 := _sd(tb, tv[3 * ta])
		var r1 := _sd(tb, tv[3 * ta + 1])
		var r2 := _sd(tb, tv[3 * ta + 2])
		if (r0 > 0.0 and r1 > 0.0 and r2 > 0.0) or (r0 < 0.0 and r1 < 0.0 and r2 < 0.0):
			return
		if (s0 == 0.0 and s1 == 0.0 and s2 == 0.0) or (r0 == 0.0 and r1 == 0.0 and r2 == 0.0):
			_coplanar(ta, tb)
			return
		var ia := _cut(ta, r0, r1, r2)
		var ib := _cut(tb, s0, s1, s2)
		if ia.size() < 2 or ib.size() < 2:
			return   # a single touching point: nothing to cut
		var ax := tn[3 * ta]
		var ay := tn[3 * ta + 1]
		var az := tn[3 * ta + 2]
		var bxn := tn[3 * tb]
		var byn := tn[3 * tb + 1]
		var bzn := tn[3 * tb + 2]
		var dx := ay * bzn - az * byn
		var dy := az * bxn - ax * bzn
		var dz := ax * byn - ay * bxn
		var dl := sqrt(dx * dx + dy * dy + dz * dz)
		var fa0 := dx * px[ia[0]] + dy * py[ia[0]] + dz * pz[ia[0]]
		var fa1 := dx * px[ia[1]] + dy * py[ia[1]] + dz * pz[ia[1]]
		var fb0 := dx * px[ib[0]] + dy * py[ib[0]] + dz * pz[ib[0]]
		var fb1 := dx * px[ib[1]] + dy * py[ib[1]] + dz * pz[ib[1]]
		var alo := ia[0]
		var ahi := ia[1]
		if fa0 > fa1:
			alo = ia[1]
			ahi = ia[0]
			var tt := fa0
			fa0 = fa1
			fa1 = tt
		var blo := ib[0]
		var bhi := ib[1]
		if fb0 > fb1:
			blo = ib[1]
			bhi = ib[0]
			var tt2 := fb0
			fb0 = fb1
			fb1 = tt2
		var lo := fa0
		var lo_id := alo
		if fb0 > fa0:
			lo = fb0
			lo_id = blo
		var hi := fa1
		var hi_id := ahi
		if fb1 < fa1:
			hi = fb1
			hi_id = bhi
		if hi - lo <= eps * dl:
			return
		stats["segments"] += 1
		_add_seg(ta, lo_id, hi_id)
		_add_seg(tb, lo_id, hi_id)

	## the points of triangle t on the other plane (r = its corners' distances to it): corners on it, edge crossings
	func _cut(t: int, r0: float, r1: float, r2: float) -> PackedInt32Array:
		var out := PackedInt32Array()
		var c := [tv[3 * t], tv[3 * t + 1], tv[3 * t + 2]]
		var s := [r0, r1, r2]
		for i in 3:
			if s[i] == 0.0:
				out.append(c[i])
		for i in 3:
			var j := (i + 1) % 3
			if (s[i] > 0.0 and s[j] < 0.0) or (s[i] < 0.0 and s[j] > 0.0):
				out.append(_cross_pt(c[i], c[j], s[i], s[j]))
		return out

	## where the edge u-v crosses the plane (su, sv its ends' distances); from the lower id, so both triangles agree
	func _cross_pt(u: int, v: int, su: float, sv: float) -> int:
		if u > v:
			var t := u
			u = v
			v = t
			var ts := su
			su = sv
			sv = ts
		var f := su / (su - sv)
		return add_point(px[u] + (px[v] - px[u]) * f, py[u] + (py[v] - py[u]) * f, pz[u] + (pz[v] - pz[u]) * f)

	func _push(d: Dictionary, k: int, v: int) -> void:
		var a: PackedInt32Array = d.get(k, PackedInt32Array())
		a.append(v)
		d[k] = a

	func _add_seg(t: int, p: int, q: int) -> void:
		if find(p) == find(q):
			return
		_push(segs, t, p)
		_push(segs, t, q)
		_push(pts, t, p)
		_push(pts, t, q)

	func _coplanar(ta: int, tb: int) -> void:
		stats["coplanar_pairs"] += 1
		_push(copl, ta, tb)
		_push(copl, tb, ta)
		for pair_i in 2:
			var into := ta if pair_i == 0 else tb
			var from := tb if pair_i == 0 else ta
			for e in 3:
				var s := _clip(into, tv[3 * from + e], tv[3 * from + (e + 1) % 3])
				if s.is_empty():
					continue
				_add_seg(into, s[0], s[1])
				_push(pts, from, s[0])   # on from's own edge: put in it (and across that edge) too
				_push(pts, from, s[1])

	## the part of segment u-v inside triangle t (in t's plane), as two points; empty when it misses
	func _clip(t: int, u: int, v: int) -> PackedInt32Array:
		if u > v:
			var tt := u
			u = v
			v = tt
		var k := tax[t]
		var t0 := 0.0
		var t1 := 1.0
		for e in 3:
			var a := tv[3 * t + e]
			var b := tv[3 * t + (e + 1) % 3]
			var du := _d2(k, a, b, u)
			var dv := _d2(k, a, b, v)
			if du < -eps and dv < -eps:
				return PackedInt32Array()
			if du < -eps:
				t0 = maxf(t0, du / (du - dv))
			elif dv < -eps:
				t1 = minf(t1, du / (du - dv))
		var lx := px[v] - px[u]
		var ly := py[v] - py[u]
		var lz := pz[v] - pz[u]
		var ln := sqrt(lx * lx + ly * ly + lz * lz)
		if (t1 - t0) * ln <= eps:
			return PackedInt32Array()
		var p := u if t0 * ln <= eps else add_point(px[u] + lx * t0, py[u] + ly * t0, pz[u] + lz * t0)
		var q := v if (1.0 - t1) * ln <= eps else add_point(px[u] + lx * t1, py[u] + ly * t1, pz[u] + lz * t1)
		if find(p) == find(q):
			return PackedInt32Array()
		return PackedInt32Array([p, q])

	## point (x, y, z) in projection k -> _u, _v
	func _pr(k: int, x: float, y: float, z: float) -> void:
		match k:
			0:
				_u = y
				_v = z
			1:
				_u = z
				_v = y
			2:
				_u = z
				_v = x
			3:
				_u = x
				_v = z
			4:
				_u = x
				_v = y
			_:
				_u = y
				_v = x

	## signed distance (left = +) of point p from the line a -> b, in projection k
	func _d2(k: int, a: int, b: int, p: int) -> float:
		return _d2xyz(k, a, b, px[p], py[p], pz[p])

	func _d2xyz(k: int, a: int, b: int, x: float, y: float, z: float) -> float:
		_pr(k, px[a], py[a], pz[a])
		var au := _u
		var av := _v
		_pr(k, px[b], py[b], pz[b])
		var bu := _u - au
		var bv := _v - av
		_pr(k, x, y, z)
		var l := sqrt(bu * bu + bv * bv)
		if l <= 1e-300:
			return 0.0
		return (bu * (_v - av) - bv * (_u - au)) / l

	# ------------------------------------------------------------ splitting

	## is point p strictly inside the segment a-b (3D, within eps of it, more than eps from its ends)
	func _on_edge(p: int, a: int, b: int) -> bool:
		var ex := px[b] - px[a]
		var ey := py[b] - py[a]
		var ez := pz[b] - pz[a]
		var l2 := ex * ex + ey * ey + ez * ez
		if l2 <= 0.0:
			return false
		var wx := px[p] - px[a]
		var wy := py[p] - py[a]
		var wz := pz[p] - pz[a]
		var t := (wx * ex + wy * ey + wz * ez) / l2
		var l := sqrt(l2)
		if t * l <= eps or (1.0 - t) * l <= eps:
			return false
		var cx := wx - ex * t
		var cy := wy - ey * t
		var cz := wz - ez * t
		return cx * cx + cy * cy + cz * cz <= eps * eps

	func _split_all() -> void:
		# points on a triangle's edge are shared with the triangle across that edge
		for t in pts:
			var seen := {}
			for p0 in (pts[t] as PackedInt32Array):
				var p := find(p0)
				if seen.has(p):
					continue
				seen[p] = true
				for e in 3:
					var a := find(tv[3 * t + e])
					var b := find(tv[3 * t + (e + 1) % 3])
					if p != a and p != b and _on_edge(p, a, b):
						_push(epts, ekey(a, b), p)
		var nt := tface.size()
		for t in nt:
			var extra := PackedInt32Array()
			if pts.has(t):
				extra.append_array(pts[t])
			if not epts.is_empty():
				for e in 3:
					var k := ekey(find(tv[3 * t + e]), find(tv[3 * t + (e + 1) % 3]))
					if epts.has(k):
						extra.append_array(epts[k])
			if extra.is_empty() or _degen(t):
				pv.append(tv[3 * t])
				pv.append(tv[3 * t + 1])
				pv.append(tv[3 * t + 2])
				ptri.append(t)
				continue
			stats["split_tris"] += 1
			face_cut[0 if t < na else 1][tface[t]] = true
			_split(t, extra, segs.get(t, PackedInt32Array()))
		stats["pieces"] = ptri.size()

	func _ld(a: int, b: int, p: int) -> float:
		var bu := l_u[b] - l_u[a]
		var bv := l_v[b] - l_v[a]
		var l := sqrt(bu * bu + bv * bv)
		if l <= 1e-300:
			return 0.0
		return (bu * (l_v[p] - l_v[a]) - bv * (l_u[p] - l_u[a])) / l

	func _lres(i: int) -> int:
		while l_al[i] != i:
			i = l_al[i]
		return i

	## re-triangulate triangle t with its extra points and cut lines; the pieces go to pv / ptri
	func _split(t: int, extra: PackedInt32Array, sg: PackedInt32Array) -> void:
		var k := tax[t]
		l_ids = PackedInt32Array()
		l_u = PackedFloat64Array()
		l_v = PackedFloat64Array()
		var loc := {}
		for i in 3:
			var g := find(tv[3 * t + i])
			loc[g] = l_ids.size() if not loc.has(g) else loc[g]
			l_ids.append(g)
			_pr(k, px[g], py[g], pz[g])
			l_u.append(_u)
			l_v.append(_v)
		for p0 in extra:
			var g := find(p0)
			if loc.has(g):
				continue
			loc[g] = l_ids.size()
			l_ids.append(g)
			_pr(k, px[g], py[g], pz[g])
			l_u.append(_u)
			l_v.append(_v)
		l_al = PackedInt32Array()
		for i in l_ids.size():
			l_al.append(i)
		l_tris = PackedInt32Array([0, 1, 2])
		l_cons = {}
		for i in range(3, l_ids.size()):
			_ins(i)
		for j in range(0, sg.size() - 1, 2):
			var p: int = loc.get(find(sg[j]), -1)
			var q: int = loc.get(find(sg[j + 1]), -1)
			if p < 0 or q < 0:
				continue
			_force(_lres(p), _lres(q))
		for j in range(0, l_tris.size(), 3):
			var a := l_ids[_lres(l_tris[j])]
			var b := l_ids[_lres(l_tris[j + 1])]
			var c := l_ids[_lres(l_tris[j + 2])]
			if a == b or b == c or c == a:
				continue
			pv.append(a)
			pv.append(b)
			pv.append(c)
			ptri.append(t)
		for key in l_cons:
			cut_list.append(l_ids[key >> 32])
			cut_list.append(l_ids[key & 0xFFFFFFFF])

	## insert local point i: into the sub-triangle holding it (on an edge: split both sides; on a corner: it IS the corner)
	func _ins(i: int) -> void:
		var nt := l_tris.size() / 3
		var best := 0
		var bm := -INF
		var b0 := 0.0
		var b1 := 0.0
		var b2 := 0.0
		for k in nt:
			var a := l_tris[3 * k]
			var b := l_tris[3 * k + 1]
			var c := l_tris[3 * k + 2]
			var d0 := _ld(a, b, i)
			var d1 := _ld(b, c, i)
			var d2 := _ld(c, a, i)
			var m := minf(d0, minf(d1, d2))
			if m > bm:
				bm = m
				best = k
				b0 = d0
				b1 = d1
				b2 = d2
			if m > eps:
				break
		var a := l_tris[3 * best]
		var b := l_tris[3 * best + 1]
		var c := l_tris[3 * best + 2]
		var n0 := b0 <= eps
		var n1 := b1 <= eps
		var n2 := b2 <= eps
		if bm < -eps:   # outside every piece (numerical): onto the nearest edge
			stats["clamped"] += 1
			n0 = b0 == bm
			n1 = (not n0) and b1 == bm
			n2 = (not n0) and (not n1)
		var cnt := int(n0) + int(n1) + int(n2)
		if cnt >= 2:
			var v := b if (n0 and n1) else (c if (n1 and n2) else a)
			if cnt == 3:   # a sliver: the nearest corner
				var dv := INF
				for w in [a, b, c]:
					var dd: float = (l_u[w] - l_u[i]) ** 2 + (l_v[w] - l_v[i]) ** 2
					if dd < dv:
						dv = dd
						v = w
			l_al[i] = v
			join(l_ids[i], l_ids[v])
			return
		if cnt == 1:
			var u := a
			var w := b
			var o := c
			if n1:
				u = b
				w = c
				o = a
			elif n2:
				u = c
				w = a
				o = b
			_set_tri(best, u, i, o)
			_add_ltri(i, w, o)
			var j := _find_ltri(w, u)
			if j >= 0:
				var z := _third(j, w, u)
				_set_tri(j, w, i, z)
				_add_ltri(i, u, z)
			return
		_set_tri(best, a, b, i)
		_add_ltri(b, c, i)
		_add_ltri(c, a, i)

	func _set_tri(k: int, a: int, b: int, c: int) -> void:
		l_tris[3 * k] = a
		l_tris[3 * k + 1] = b
		l_tris[3 * k + 2] = c

	func _add_ltri(a: int, b: int, c: int) -> void:
		l_tris.append(a)
		l_tris.append(b)
		l_tris.append(c)

	## the sub-triangle with the directed edge a -> b, or -1
	func _find_ltri(a: int, b: int) -> int:
		for k in l_tris.size() / 3:
			for e in 3:
				if l_tris[3 * k + e] == a and l_tris[3 * k + (e + 1) % 3] == b:
					return k
		return -1

	func _third(k: int, a: int, b: int) -> int:
		for e in 3:
			var x := l_tris[3 * k + e]
			if x != a and x != b:
				return x
		return -1

	## force the cut line p-q to be an edge: split it at points lying on it, then flip the edges crossing it
	func _force(p: int, q: int) -> void:
		var stack := PackedInt32Array([p, q])
		while stack.size() >= 2:
			var b := stack[stack.size() - 1]
			var a := stack[stack.size() - 2]
			stack.resize(stack.size() - 2)
			if a == b:
				continue
			var lu := l_u[b] - l_u[a]
			var lv := l_v[b] - l_v[a]
			var l2 := lu * lu + lv * lv
			var l := sqrt(l2)
			var mid := -1
			for v in l_ids.size():
				if v == a or v == b or l_al[v] != v:
					continue
				if absf(_ld(a, b, v)) > eps:
					continue
				var tt := ((l_u[v] - l_u[a]) * lu + (l_v[v] - l_v[a]) * lv) / maxf(l2, 1e-300)
				if tt * l > eps and (1.0 - tt) * l > eps:
					mid = v
					break
			if mid >= 0:
				stack.append_array(PackedInt32Array([a, mid, mid, b]))
				continue
			if _find_ltri(a, b) < 0 and _find_ltri(b, a) < 0:
				_flip_to(a, b)
				if _find_ltri(a, b) < 0 and _find_ltri(b, a) < 0:
					stats["unresolved"] += 1
					continue
			l_cons[(mini(a, b) << 32) | maxi(a, b)] = true

	## does segment p-q properly cross u-v (exact signs; points on p-q were split off before)
	func _xing(p: int, q: int, u: int, v: int) -> bool:
		var du := _ld(p, q, u)
		var dv := _ld(p, q, v)
		if not ((du > 0.0 and dv < 0.0) or (du < 0.0 and dv > 0.0)):
			return false
		var dp := _ld(u, v, p)
		var dq := _ld(u, v, q)
		return (dp > 0.0 and dq < 0.0) or (dp < 0.0 and dq > 0.0)

	func _flip_to(p: int, q: int) -> void:
		var nt := l_tris.size() / 3
		var cap := 64 + 4 * nt * nt
		for guard in cap:
			var crossing := false
			var done := false
			for k in nt:
				for e in 3:
					var u := l_tris[3 * k + e]
					var v := l_tris[3 * k + (e + 1) % 3]
					var w := l_tris[3 * k + (e + 2) % 3]
					if u == p or u == q or v == p or v == q or not _xing(p, q, u, v):
						continue
					crossing = true
					if l_cons.has((mini(u, v) << 32) | maxi(u, v)):
						continue
					var j := _find_ltri(v, u)
					if j < 0:
						continue
					var z := _third(j, v, u)
					if _ld(u, z, w) <= 0.0 or _ld(z, v, w) <= 0.0:
						continue   # the quad is not convex: flipping would fold
					_set_tri(k, u, z, w)
					_set_tri(j, z, v, w)
					done = true
					break
				if done:
					break
			if not crossing or not done:
				return

	# ------------------------------------------------------------ classification

	## 0 = outside, 1 = inside, 2 = on, facing the same way, 3 = on, facing the other way; per piece
	func _classify(op: String) -> PackedByteArray:
		var np := ptri.size()
		for i in pv.size():
			pv[i] = find(pv[i])
		var cuts := {}
		for i in range(0, cut_list.size(), 2):
			cuts[ekey(find(cut_list[i]), find(cut_list[i + 1]))] = true
		var state := PackedInt32Array()
		state.resize(np)
		state.fill(-1)
		var e1 := {}
		var e2 := {}
		for pc in np:
			var a := pv[3 * pc]
			var b := pv[3 * pc + 1]
			var c := pv[3 * pc + 2]
			if a == b or b == c or c == a:
				state[pc] = 9   # degenerate: dropped
				continue
			var side := 0 if ptri[pc] < na else 1
			for e in 3:
				var k := ekey(pv[3 * pc + e], pv[3 * pc + (e + 1) % 3]) * 2 + side
				if e1.has(k):
					e2[k] = pc
				else:
					e1[k] = pc
			var t := ptri[pc]
			if copl.has(t):
				var cx := (px[a] + px[b] + px[c]) / 3.0
				var cy := (py[a] + py[b] + py[c]) / 3.0
				var cz := (pz[a] + pz[b] + pz[c]) / 3.0
				for o in (copl[t] as PackedInt32Array):
					var ko := tax[o]
					var inside := true
					for e in 3:
						if _d2xyz(ko, tv[3 * o + e], tv[3 * o + (e + 1) % 3], cx, cy, cz) <= eps:
							inside = false
							break
					if inside:
						var dot := tn[3 * t] * tn[3 * o] + tn[3 * t + 1] * tn[3 * o + 1] + tn[3 * t + 2] * tn[3 * o + 2]
						state[pc] = 2 if dot > 0.0 else 3
						break
		# patches of the rest
		var queue := PackedInt32Array()
		for s in np:
			if state[s] != -1:
				continue
			var side := 0 if ptri[s] < na else 1
			queue.resize(0)
			queue.append(s)
			state[s] = -2
			var qi := 0
			var best := s
			var barea := -1.0
			while qi < queue.size():
				var pc := queue[qi]
				qi += 1
				var ar := _area(pc)
				if ar > barea:
					barea = ar
					best = pc
				for e in 3:
					var a := pv[3 * pc + e]
					var b := pv[3 * pc + (e + 1) % 3]
					var ek := ekey(a, b)
					if cuts.has(ek):
						continue
					var k := ek * 2 + side
					for nb in [e1.get(k, -1), e2.get(k, -1)]:
						if nb >= 0 and nb != pc and state[nb] == -1:
							state[nb] = -2
							queue.append(nb)
			stats["patches"] += 1
			var a0 := pv[3 * best]
			var b0 := pv[3 * best + 1]
			var c0 := pv[3 * best + 2]
			var w := _winding((px[a0] + px[b0] + px[c0]) / 3.0, (py[a0] + py[b0] + py[c0]) / 3.0, (pz[a0] + pz[b0] + pz[c0]) / 3.0, 1 - side)
			var st := 1 if w > 0.5 else 0
			for pc in queue:
				state[pc] = st
		var keep := PackedByteArray()   # 0 drop, 1 keep, 2 keep flipped
		keep.resize(np)
		for pc in np:
			var st := state[pc]
			var side := 0 if ptri[pc] < na else 1
			var k := 0
			if st == 9:
				k = 0
			elif st >= 2:
				if side == 0:
					var same := st == 2
					k = 1 if (same if op != "difference" else not same) else 0
			elif op == "union":
				k = 1 if st == 0 else 0
			elif op == "intersect":
				k = 1 if st == 1 else 0
			else:
				k = (1 if st == 0 else 0) if side == 0 else (2 if st == 1 else 0)
			keep[pc] = k
		return keep

	func _area(pc: int) -> float:
		var a := pv[3 * pc]
		var b := pv[3 * pc + 1]
		var c := pv[3 * pc + 2]
		var ux := px[b] - px[a]
		var uy := py[b] - py[a]
		var uz := pz[b] - pz[a]
		var vx := px[c] - px[a]
		var vy := py[c] - py[a]
		var vz := pz[c] - pz[a]
		var nx := uy * vz - uz * vy
		var ny := uz * vx - ux * vz
		var nz := ux * vy - uy * vx
		return sqrt(nx * nx + ny * ny + nz * nz) * 0.5

	## generalised winding number of the point about the ORIGINAL triangles of one side (Van Oosterom-Strackee solid
	## angles): 1 inside a closed outward mesh, 0 outside
	func _winding(x: float, y: float, z: float, side: int) -> float:
		var t0 := 0 if side == 0 else na
		var t1 := na if side == 0 else tface.size()
		var w := 0.0
		for t in range(t0, t1):
			var a := tv[3 * t]
			var b := tv[3 * t + 1]
			var c := tv[3 * t + 2]
			var ax := px[a] - x
			var ay := py[a] - y
			var az := pz[a] - z
			var bx := px[b] - x
			var by := py[b] - y
			var bz := pz[b] - z
			var cx := px[c] - x
			var cy := py[c] - y
			var cz := pz[c] - z
			var la := sqrt(ax * ax + ay * ay + az * az)
			var lb := sqrt(bx * bx + by * by + bz * bz)
			var lc := sqrt(cx * cx + cy * cy + cz * cz)
			var det := ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx)
			var div := la * lb * lc + (ax * bx + ay * by + az * bz) * lc + (bx * cx + by * cy + bz * cz) * la + (cx * ax + cy * ay + cz * az) * lb
			w += atan2(det, div)
		return w / TAU

	# ------------------------------------------------------------ rebuild

	func _build(ma: KMesh, mb: KMesh, _op: String, keep: PackedByteArray) -> KMesh:
		for s in 2:   # points joined since _add_mesh: key the vertex sources by the joined point
			var old: Dictionary = gsrc_a if s == 0 else gsrc_b
			var nw := {}
			for g in old:
				var r := find(g)
				if not nw.has(r):
					nw[r] = old[g]
			if s == 0:
				gsrc_a = nw
			else:
				gsrc_b = nw
		var groups := {}   # side << 40 | face -> PackedInt32Array of kept pieces
		var order := []
		for pc in ptri.size():
			if keep[pc] == 0:
				continue
			var t := ptri[pc]
			var side := 0 if t < na else 1
			var gk := (side << 40) | tface[t]
			if not groups.has(gk):
				order.append(gk)
			_push(groups, gk, pc)
		# output faces: points, and per corner where its attributes come from
		var of_pts: Array = []           # PackedInt32Array per face (global points)
		var of_side := PackedInt32Array()
		var of_face := PackedInt32Array()
		var oc_tri: Array = []           # PackedInt32Array per face: source triangle per corner (-1 = exact corner)
		var oc_corner: Array = []        # PackedInt32Array per face: the exact source corner (when oc_tri is -1)
		for gk in order:
			var g: PackedInt32Array = groups[gk]
			var side: int = gk >> 40
			var fi: int = gk & 0xFFFFFFFFFF
			var flip: bool = keep[g[0]] == 2
			var m: KMesh = ma if side == 0 else mb
			var f: PackedInt32Array = m.faces[fi]
			var fp := PackedInt32Array()
			var ct := PackedInt32Array()
			var cc := PackedInt32Array()
			if not face_cut[side].has(fi) and g.size() == (face_ntri[side] as PackedInt32Array)[fi]:
				# not cut: the face as it was
				var he0: int = m.face_he0[fi]
				for i in f.size():
					var j := (f.size() - i) % f.size() if flip else i
					fp.append(_gid_of(side, f[j]))
					ct.append(-1)
					cc.append(he0 + j)
				of_pts.append(fp)
				of_side.append(side)
				of_face.append(fi)
				oc_tri.append(ct)
				oc_corner.append(cc)
				stats["faces_as_were"] += 1
				continue
			var loop := _merge(g)
			if loop.size() >= 3:
				stats["ngons"] += 1
				var n := loop.size() / 2
				for i in n:
					var j := (n - i) % n if flip else i
					fp.append(loop[2 * j])
					ct.append(loop[2 * j + 1])
					cc.append(-1)
				of_pts.append(fp)
				of_side.append(side)
				of_face.append(fi)
				oc_tri.append(ct)
				oc_corner.append(cc)
				continue
			for pc in g:
				stats["tri_faces"] += 1
				var tri := PackedInt32Array([pv[3 * pc], pv[3 * pc + 2], pv[3 * pc + 1]]) if flip else PackedInt32Array([pv[3 * pc], pv[3 * pc + 1], pv[3 * pc + 2]])
				of_pts.append(tri)
				of_side.append(side)
				of_face.append(fi)
				oc_tri.append(PackedInt32Array([ptri[pc], ptri[pc], ptri[pc]]))
				oc_corner.append(PackedInt32Array([-1, -1, -1]))
		# compact the points
		var newid := {}
		var V := PackedVector3Array()
		var vsrc_side := PackedInt32Array()   # first corner using each new vertex: its face side, tri, exact corner
		var vsrc_tri := PackedInt32Array()
		var vsrc_corner := PackedInt32Array()
		var vgid := PackedInt32Array()
		var F: Array = []
		for fo in of_pts.size():
			var fp: PackedInt32Array = of_pts[fo]
			var out := PackedInt32Array()
			out.resize(fp.size())
			for i in fp.size():
				var g := find(fp[i])
				var id: int = newid.get(g, -1)
				if id == -1:
					id = V.size()
					newid[g] = id
					V.append(Vector3(px[g], py[g], pz[g]))
					vsrc_side.append(of_side[fo])
					vsrc_tri.append((oc_tri[fo] as PackedInt32Array)[i])
					vsrc_corner.append((oc_corner[fo] as PackedInt32Array)[i])
					vgid.append(g)
				elif of_side[fo] == 0 and vsrc_side[id] == 1:   # A's values win on shared points
					vsrc_side[id] = 0
					vsrc_tri[id] = (oc_tri[fo] as PackedInt32Array)[i]
					vsrc_corner[id] = (oc_corner[fo] as PackedInt32Array)[i]
				out[i] = id
			F.append(out)
		var res := KMesh.new().from_arrays(V, F)
		res.normal_mode = ma.normal_mode
		res.auto_angle = ma.auto_angle
		res.modifiers = ma.modifiers.duplicate(true)
		res.materials = ma.materials.duplicate(true)
		if not ma.attrs.is_empty():
			_carry(ma, mb, res, of_pts, of_side, of_face, oc_tri, oc_corner, vsrc_side, vsrc_tri, vsrc_corner, vgid)
		return res

	## the point of vertex v of one side (welded points may have been joined since)
	func _gid_of(side: int, v: int) -> int:
		return find((_vg[side] as PackedInt32Array)[v])

	## the kept pieces of one source face as one n-gon: [point, tri, point, tri ...] (CCW like the pieces), or [] when
	## that is not clean (not one loop / not a disc / no corner whose fan covers it without folding)
	func _merge(g: PackedInt32Array) -> PackedInt32Array:
		if g.size() < 2:
			return PackedInt32Array()
		var dir := {}
		var und := {}
		var verts := {}
		for pc in g:
			for e in 3:
				var a := pv[3 * pc + e]
				var b := pv[3 * pc + (e + 1) % 3]
				dir[(a << 32) | b] = pc
				und[ekey(a, b)] = true
				verts[a] = true
		if verts.size() - und.size() + g.size() != 1:
			return PackedInt32Array()
		var nxt := {}
		var via := {}
		var nb := 0
		for k in dir:
			var a: int = k >> 32
			var b: int = k & 0xFFFFFFFF
			if dir.has((b << 32) | a):
				continue
			if nxt.has(a):
				return PackedInt32Array()   # touches itself at a vertex
			nxt[a] = b
			via[a] = dir[k]
			nb += 1
		if nb < 3:
			return PackedInt32Array()
		var start: int = nxt.keys()[0]
		var loop := PackedInt32Array()
		var tris := PackedInt32Array()
		var v := start
		while true:
			loop.append(v)
			tris.append(ptri[via[v]])
			v = nxt.get(v, -1)
			if v == start or v == -1 or loop.size() > nb:
				break
		if v != start or loop.size() != nb:
			return PackedInt32Array()
		# a corner whose fan does not fold (all fan triangles turn left, in the face's projection)
		var k := tax[ptri[g[0]]]
		var n := loop.size()
		var uu := PackedFloat64Array()
		var vv := PackedFloat64Array()
		for p in loop:
			_pr(k, px[p], py[p], pz[p])
			uu.append(_u)
			vv.append(_v)
		var best := -1
		var bscore := -INF
		for s in n:
			var worst := INF
			for i in range(1, n - 1):
				var a := s
				var b := (s + i) % n
				var c := (s + i + 1) % n
				var bu := uu[b] - uu[a]
				var bv := vv[b] - vv[a]
				var cu := uu[c] - uu[a]
				var cv := vv[c] - vv[a]
				var cr := bu * cv - bv * cu
				var lb := sqrt(cu * cu + cv * cv)
				worst = minf(worst, cr / maxf(lb, 1e-300))
				if worst < -eps:
					break
			if worst > bscore:
				bscore = worst
				best = s
		if best < 0 or bscore < -eps:
			return PackedInt32Array()
		var out := PackedInt32Array()
		for i in n:
			var j := (best + i) % n
			out.append(loop[j])
			out.append(tris[j])
		return out

	## barycentric weights of point g in triangle t (its projection) -> w (3 floats)
	func _bary(t: int, g: int, w: PackedFloat64Array) -> void:
		var k := tax[t]
		var a := tv[3 * t]
		var b := tv[3 * t + 1]
		var c := tv[3 * t + 2]
		_pr(k, px[a], py[a], pz[a])
		var au := _u
		var av := _v
		_pr(k, px[b], py[b], pz[b])
		var bu := _u
		var bv := _v
		_pr(k, px[c], py[c], pz[c])
		var cu := _u
		var cv := _v
		_pr(k, px[g], py[g], pz[g])
		var tot := (bu - au) * (cv - av) - (bv - av) * (cu - au)
		if absf(tot) <= 1e-300:
			w[0] = 1.0
			w[1] = 0.0
			w[2] = 0.0
			return
		w[0] = ((bu - _u) * (cv - _v) - (bv - _v) * (cu - _u)) / tot
		w[1] = ((cu - _u) * (av - _v) - (cv - _v) * (au - _u)) / tot
		w[2] = 1.0 - w[0] - w[1]

	## the value of channel data `d` (indexed by `idx`, 3 per tri) at point g of triangle t
	func _interp(d, t: int, g: int, idx: PackedInt32Array, label: bool, w: PackedFloat64Array):
		_bary(t, g, w)
		var i0 := idx[3 * t]
		var i1 := idx[3 * t + 1]
		var i2 := idx[3 * t + 2]
		if label:
			if w[0] >= w[1] and w[0] >= w[2]:
				return d[i0]
			return d[i1] if w[1] >= w[2] else d[i2]
		return d[i0] * w[0] + d[i1] * w[1] + d[i2] * w[2]

	func _carry(ma: KMesh, mb: KMesh, res: KMesh, of_pts: Array, of_side: PackedInt32Array, of_face: PackedInt32Array,
			oc_tri: Array, oc_corner: Array, vsrc_side: PackedInt32Array, vsrc_tri: PackedInt32Array,
			vsrc_corner: PackedInt32Array, vgid: PackedInt32Array) -> void:
		var w := PackedFloat64Array([0.0, 0.0, 0.0])
		for name in ma.attrs:
			var r: Dictionary = ma.attrs[name]
			var dom: String = r["domain"]
			var ty: int = r["type"]
			var rb = mb.attrs.get(name)
			if rb != null and (rb["domain"] != dom or rb["type"] != ty):
				rb = null
			var srcs := [r["data"], rb["data"] if rb != null else null]
			var label := KMesh.is_label(name)
			var data = KMesh._attr_make(ty, res.domain_count(dom), r["default"])
			match dom:
				KMesh.AD_FACE:
					for fo in of_pts.size():
						var sd = srcs[of_side[fo]]
						if sd != null:
							data[fo] = sd[of_face[fo]]
				KMesh.AD_CORNER:
					var ci := 0
					for fo in of_pts.size():
						var sd = srcs[of_side[fo]]
						var ct: PackedInt32Array = oc_tri[fo]
						var cc: PackedInt32Array = oc_corner[fo]
						var fp: PackedInt32Array = of_pts[fo]
						for i in fp.size():
							if sd != null:
								data[ci] = sd[cc[i]] if ct[i] < 0 else _interp(sd, ct[i], find(fp[i]), tcorner, label, w)
							ci += 1
				KMesh.AD_VERT:
					for v in vgid.size():
						var sd = srcs[vsrc_side[v]]
						if sd == null:
							continue
						var src: Dictionary = gsrc_a if vsrc_side[v] == 0 else gsrc_b
						if src.has(vgid[v]):
							data[v] = sd[src[vgid[v]]]
						elif vsrc_tri[v] >= 0:
							data[v] = _interp(sd, vsrc_tri[v], vgid[v], tsv, label, w)
			res.attrs[name] = {"domain": dom, "type": ty, "default": r["default"], "data": data}


# ---------------------------------------------------------------- the model preview (MeshTools ops)

## the connected parts of a mesh (faces sharing a vertex), each as its face list, in order of their first face
static func components(m: KMesh) -> Array:
	var nv := m.verts.size()
	var uf := PackedInt32Array()
	uf.resize(nv)
	for v in nv:
		uf[v] = v
	var fnd := func(i: int) -> int:
		while uf[i] != i:
			uf[i] = uf[uf[i]]
			i = uf[i]
		return i
	for f in m.faces:
		var fp: PackedInt32Array = f
		var r0: int = fnd.call(fp[0])
		for i in range(1, fp.size()):
			var r: int = fnd.call(fp[i])
			if r != r0:
				uf[maxi(r, r0)] = mini(r, r0)
				r0 = mini(r, r0)
	var by := {}
	var out: Array = []
	for fi in m.faces.size():
		var r: int = fnd.call((m.faces[fi] as PackedInt32Array)[0])
		if not by.has(r):
			by[r] = out.size()
			out.append(PackedInt32Array())
		var lst: PackedInt32Array = out[by[r]]
		lst.append(fi)
		out[by[r]] = lst
	return out


## the faces `flist` of m as a mesh of their own (verts renumbered); vert / face / corner channels carried, edge ones
## restart at their default
static func submesh(m: KMesh, flist: PackedInt32Array) -> KMesh:
	var map := {}
	var V := PackedVector3Array()
	var F: Array = []
	var src_v := PackedInt32Array()
	var src_c := PackedInt32Array()
	var he0 := m.face_he0
	for fi in flist:
		var f: PackedInt32Array = m.faces[fi]
		var g := PackedInt32Array()
		for i in f.size():
			var v := f[i]
			if not map.has(v):
				map[v] = V.size()
				V.append(m.verts[v])
				src_v.append(v)
			g.append(map[v])
			src_c.append(he0[fi] + i)
		F.append(g)
	var r := KMesh.new().from_arrays(V, F)
	if not m.attrs.is_empty():
		r.attrs = m.attr_snapshot()
		var src_e := PackedInt32Array()
		src_e.resize(r.edge_count())
		src_e.fill(-1)
		r.attr_remap(src_v, flist, src_c, src_e)
	r.normal_mode = m.normal_mode
	r.auto_angle = m.auto_angle
	r.modifiers = m.modifiers.duplicate(true)
	r.materials = m.materials.duplicate(true)
	return r


## split the preview's mesh into target and operand: the operand is every part holding a selected vertex / face (nothing
## selected: the part added last, i.e. the one with the highest face). {"target", "operand"} face lists, or {"why"}
static func pick(m: KMesh, sel) -> Dictionary:
	var comps := components(m)
	if comps.size() < 2:
		return {"why": "a boolean needs two parts: add a primitive (Add primitive), move it into the mesh, then run it again"}
	var hit := {}
	if sel != null:
		for v in sel.verts:
			hit[v] = true
		for fi in sel.faces:
			for v in (m.faces[fi] as PackedInt32Array):
				hit[v] = true
		for e in sel.edges:
			hit[(e as Vector2i).x] = true
	var tgt := PackedInt32Array()
	var opd := PackedInt32Array()
	var last_i := comps.size() - 1
	var hi := -1
	for ci in comps.size():   # the part added last holds the highest face index
		var c: PackedInt32Array = comps[ci]
		if c[c.size() - 1] > hi:
			hi = c[c.size() - 1]
			last_i = ci
	for ci in comps.size():
		var c: PackedInt32Array = comps[ci]
		var is_op := false
		if hit.is_empty():
			is_op = ci == last_i
		else:
			for fi in c:
				for v in (m.faces[fi] as PackedInt32Array):
					if hit.has(v):
						is_op = true
						break
				if is_op:
					break
		if is_op:
			opd.append_array(c)
		else:
			tgt.append_array(c)
	if tgt.is_empty():
		return {"why": "every part is selected: select only the operand (the part to cut / add / keep with), the rest is the target"}
	return {"target": tgt, "operand": opd}


## MeshTools.op "boolean_union" / "boolean_difference" / "boolean_intersect" on the model preview's mesh: ONE undo step;
## returns what to say
static func op(name: String, m) -> String:
	var ui = m.kmed
	if ui == null or ui.mesh == null:
		return ""
	var kind := name.trim_prefix("boolean_")
	if not KMeshShapes.keys(ui.mesh).is_empty():
		return "Model: the mesh has shape keys: a boolean would break them. Remove the keys first"
	var pk := pick(ui.mesh, ui.sel)
	if pk.has("why"):
		return "Model: " + String(pk["why"])
	var a := submesh(ui.mesh, pk["target"])
	var b := submesh(ui.mesh, pk["operand"])
	var r := run(a, b, kind)
	if r == null:
		return "Model: " + last_error
	if r.face_count() == 0:
		return "Model: the %s would leave nothing (the parts do not overlap?). Nothing changed" % NAMES.get(kind, kind).to_lower()
	var f0: int = ui.mesh.face_count()
	ui.undo.begin(ui.mesh)
	ui.mesh.attrs = {}   # the new channels are sized for the new mesh: from_arrays must not fit the old ones
	ui.mesh.from_arrays(r.verts, r.faces)
	ui.mesh.attrs = r.attrs
	ui.undo.commit("Boolean " + NAMES.get(kind, kind).to_lower())
	ui.live = {}
	ui._after_topo()
	var warn := "" if int(last.get("unresolved", 0)) == 0 else " (%d cut lines could not be placed: check it with validate)" % int(last["unresolved"])
	return "Model: %s: %d faces -> %d, %s%s. One undo step (Ctrl+Z)" % [NAMES.get(kind, kind), f0, r.face_count(),
		"closed" if r.is_closed() else "NOT closed", warn]
