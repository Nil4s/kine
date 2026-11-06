class_name KMeshHoles
extends RefCounted
## G16: the open edges of a mesh (a neck cut, an eye hole) for stroke retopology (KMeshRetopoNet).
## loops(): the simple boundary loops, each with its default MODE: a small hole (bbox diagonal <= SMALL_DIAM x the mesh's) is CLOSED,
## a big one (a neck or limb cut) is used as a SIDE of the patches. close(): fills chosen loops on a COPY of the mesh with a
## minimal-area triangulation (dynamic programming over the loop), refined by longest-edge splits + flips to the loop's own edge length, then faired:
## the interior vertices minimise sum |L x|^2 (uniform umbrella L, boundary fixed), solved with conjugate gradients (Liepa 2003 style).

const SMALL_DIAM := 0.12   # a hole whose bbox diagonal is at most this x the mesh's bbox diagonal is closed by default
const SMALL_N := 12        # ... or has at most this many boundary vertices (a puncture)
const MAX_DP := 90         # loops longer than this are filled by a fan round a centre vertex instead of the O(n^3) search
const MODE_SIDE := "side"
const MODE_CLOSE := "close"


## [{verts, key, n, len, diam, simple, mode}] the boundary loops, verts in the direction the faces use them (a -> b)
static func loops(m: KMesh) -> Array:
	var outs := {}
	for f in m.faces:
		var n: int = f.size()
		for c in n:
			var a: int = f[c]
			var b: int = f[(c + 1) % n]
			if m.find_half_edge(b, a) == -1:
				if not outs.has(a):
					outs[a] = []
				(outs[a] as Array).append(b)
	var bb := AABB(m.verts[0], Vector3.ZERO) if m.verts.size() > 0 else AABB()
	for v in m.verts:
		bb = bb.expand(v)
	var diag := bb.size.length()
	var used := {}   # "a>b" edges walked
	var starts := outs.keys()
	starts.sort()
	var res: Array = []
	for s in starts:
		for first in outs[s]:
			if used.has(Vector2i(s, first)):
				continue
			var lp := PackedInt32Array([s])
			var simple := true
			var seen := {s: true}
			var a: int = s
			var b: int = first
			var closed := false
			while true:
				used[Vector2i(a, b)] = true
				if (outs[a] as Array).size() != 1:
					simple = false
				if b == s:
					closed = true
					break
				if seen.has(b):
					simple = false
					break
				seen[b] = true
				lp.append(b)
				if not outs.has(b):
					break
				var nx := -1
				for c in outs[b]:
					if not used.has(Vector2i(b, c)):
						nx = c
						break
				if nx < 0:
					break
				a = b
				b = nx
			var lb := AABB(m.verts[lp[0]], Vector3.ZERO)
			var ln := 0.0
			var mn := lp[0]
			for i in lp.size():
				lb = lb.expand(m.verts[lp[i]])
				ln += m.verts[lp[i]].distance_to(m.verts[lp[(i + 1) % lp.size()]])
				mn = mini(mn, lp[i])
			var diam := lb.size.length()
			var ok := simple and closed and lp.size() >= 3
			res.append({"verts": lp, "key": mn, "n": lp.size(), "len": ln, "diam": diam, "simple": ok,
					"mode": MODE_CLOSE if (ok and (diam <= SMALL_DIAM * diag or lp.size() <= SMALL_N)) else MODE_SIDE})
	return res


## a copy of the mesh with the given loops (entries of loops()) filled; the fill faces are appended after the original faces
static func close(m: KMesh, which: Array, fair := true) -> KMesh:
	var outer := _outside_nbrs(m)
	var vs := m.verts.duplicate()
	var fs: Array = []
	for f in m.faces:
		fs.append(f)
	for lp in which:
		var r := fill(vs, lp["verts"], fair, outer)
		vs = r["verts"]
		for t in r["faces"]:
			fs.append(t)
	return KMesh.new().from_arrays(vs, fs)


## fill one loop (indices into vs, in face direction a -> b): {verts: all vertices (the old ones first), faces: triangles of vertex indices,
## "first": index of the first new vertex}. fair = false leaves the refinement vertices where the splits put them (the planted control)
static func _outside_nbrs(m: KMesh) -> Dictionary:
	var nb := {}
	for f in m.faces:
		for c in f.size():
			var a: int = f[c]
			var b: int = f[(c + 1) % f.size()]
			if not nb.has(a):
				nb[a] = {}
			if not nb.has(b):
				nb[b] = {}
			nb[a][b] = true
			nb[b][a] = true
	return nb


## outer = the mesh's vertex neighbours (from _outside_nbrs): the loop vertices' rows of the fairing then use them too, so the fill leaves the rim with
## the surface's own tangent (without them the fairing of fixed positions alone is the flat membrane's neighbour: a disc under a spherical rim)
static func fill(vs: PackedVector3Array, loop: PackedInt32Array, fair := true, outer := {}) -> Dictionary:
	var vp := vs.duplicate()
	var base := vp.size()
	var P := PackedInt32Array()
	for i in range(loop.size() - 1, -1, -1):
		P.append(loop[i])   # the fill runs b -> a on every source edge a -> b
	var n := P.size()
	var tris: Array = []
	var mean_e := 0.0
	for i in n:
		mean_e += vp[P[i]].distance_to(vp[P[(i + 1) % n]])
	mean_e /= float(n)
	if n <= MAX_DP:
		var cost := []
		var cut := []
		for i in n:
			var row := []
			row.resize(n)
			row.fill(0.0)
			cost.append(row)
			var row2 := []
			row2.resize(n)
			row2.fill(0)
			cut.append(row2)
		for span in range(2, n):
			for i in n - span:
				var j := i + span
				var best := INF
				var bk := i + 1
				for k in range(i + 1, j):
					var c: float = cost[i][k] + cost[k][j] + 0.5 * (vp[P[k]] - vp[P[i]]).cross(vp[P[j]] - vp[P[i]]).length()
					if c < best:
						best = c
						bk = k
				cost[i][j] = best
				cut[i][j] = bk
		var stack := [[0, n - 1]]
		while not stack.is_empty():
			var ij: Array = stack.pop_back()
			if ij[1] - ij[0] < 2:
				continue
			var k: int = cut[ij[0]][ij[1]]
			tris.append(PackedInt32Array([P[ij[0]], P[k], P[ij[1]]]))
			stack.append([ij[0], k])
			stack.append([k, ij[1]])
	else:
		var c := Vector3.ZERO
		for v in P:
			c += vp[v]
		vp.append(c / float(n))
		for i in n:
			tris.append(PackedInt32Array([P[i], P[(i + 1) % n], vp.size() - 1]))
	var st := _State.new()
	st.vp = vp
	st.loop_edges = {}
	for i in n:
		st.loop_edges[_key(P[i], P[(i + 1) % n])] = true
	for t in tris:
		st.add(t)
	# refine: split the longest interior edge of a triangle whose longest interior edge is > 1.5 x the loop's mean edge, flip towards Delaunay
	for pass_i in 8:
		var split := 0
		var ids := st.live()
		for ti in ids:
			if st.tris[ti] == null:
				continue
			var t: PackedInt32Array = st.tris[ti]
			var be := -1.0
			var ea := -1
			var eb := -1
			for k in 3:
				var a := t[k]
				var b := t[(k + 1) % 3]
				if st.loop_edges.has(_key(a, b)):
					continue
				var l: float = st.vp[a].distance_to(st.vp[b])
				if l > be:
					be = l
					ea = a
					eb = b
			if be > 1.5 * mean_e and ea >= 0 and st.emap.has(_key(ea, eb)) and (st.emap[_key(ea, eb)] as Array).size() == 2:
				st.split(ea, eb)
				split += 1
		st.flips()
		if split == 0:
			break
	var first := base if vp.size() == base else base
	if fair:
		_fair(st, P, outer, vs)
	var out_f: Array = []
	for t in st.tris:
		if t != null:
			out_f.append(t)
	return {"verts": st.vp, "faces": out_f, "first": first}


static func _key(a: int, b: int) -> int:
	return mini(a, b) * 4194304 + maxi(a, b)


class _State extends RefCounted:
	var vp := PackedVector3Array()
	var tris: Array = []
	var emap := {}   # edge key -> Array of triangle ids
	var loop_edges := {}

	func add(t: PackedInt32Array) -> int:
		tris.append(t)
		var ti := tris.size() - 1
		for k in 3:
			var key := KMeshHoles._key(t[k], t[(k + 1) % 3])
			if not emap.has(key):
				emap[key] = []
			(emap[key] as Array).append(ti)
		return ti

	func rem(ti: int) -> void:
		var t: PackedInt32Array = tris[ti]
		for k in 3:
			var key := KMeshHoles._key(t[k], t[(k + 1) % 3])
			(emap[key] as Array).erase(ti)
			if (emap[key] as Array).is_empty():
				emap.erase(key)
		tris[ti] = null

	func live() -> Array:
		var r := []
		for i in tris.size():
			if tris[i] != null:
				r.append(i)
		return r

	func split(a: int, b: int) -> void:
		var tl: Array = (emap[KMeshHoles._key(a, b)] as Array).duplicate()
		var m := vp.size()
		vp.append((vp[a] + vp[b]) * 0.5)
		for ti in tl:
			var t: PackedInt32Array = tris[ti]
			var i := 0
			for k in 3:
				if (t[k] == a and t[(k + 1) % 3] == b) or (t[k] == b and t[(k + 1) % 3] == a):
					i = k
			var p: int = t[i]
			var q: int = t[(i + 1) % 3]
			var c: int = t[(i + 2) % 3]
			rem(ti)
			add(PackedInt32Array([p, m, c]))
			add(PackedInt32Array([m, q, c]))

	func flips() -> void:
		for round_i in 6:
			var any := false
			for key in emap.keys():
				if not emap.has(key) or loop_edges.has(key):
					continue
				var tl: Array = (emap[key] as Array).duplicate()
				if tl.size() != 2:
					continue
				var t1: PackedInt32Array = tris[tl[0]]
				var t2: PackedInt32Array = tris[tl[1]]
				var a := -1
				var b := -1
				var c := -1
				for k in 3:
					var p: int = t1[k]
					var q: int = t1[(k + 1) % 3]
					if KMeshHoles._key(p, q) == key:
						a = p
						b = q
						c = t1[(k + 2) % 3]
				var d := -1
				for k in 3:
					if t2[k] != a and t2[k] != b:
						d = t2[k]
				if a < 0 or d < 0 or emap.has(KMeshHoles._key(c, d)):
					continue
				var ang_c := _angle(c, a, b)
				var ang_d := _angle(d, a, b)
				if ang_c + ang_d <= PI + 1e-9:
					continue
				var n_old := (vp[b] - vp[a]).cross(vp[c] - vp[a])
				var n1 := (vp[d] - vp[a]).cross(vp[c] - vp[d])
				var n2 := (vp[b] - vp[d]).cross(vp[c] - vp[d])
				if n1.dot(n_old) <= 0.0 or n2.dot(n_old) <= 0.0:
					continue
				rem(tl[0])
				rem(tl[1])
				add(PackedInt32Array([a, d, c]))
				add(PackedInt32Array([d, b, c]))
				any = true
			if not any:
				break

	func _angle(at: int, p: int, q: int) -> float:
		var u := vp[p] - vp[at]
		var w := vp[q] - vp[at]
		return acos(clampf(u.normalized().dot(w.normalized()), -1.0, 1.0))


## minimise sum over the fill's vertices of |x_v - mean(x_nbrs)|^2 with the loop fixed (the new vertices are the unknowns)
static func _fair(st: _State, P: PackedInt32Array, outer: Dictionary, vs: PackedVector3Array) -> void:
	var fixed := {}
	for v in P:
		fixed[v] = true
	var nb := {}
	for t in st.tris:
		if t == null:
			continue
		for k in 3:
			var a: int = t[k]
			var b: int = t[(k + 1) % 3]
			if not nb.has(a):
				nb[a] = {}
			if not nb.has(b):
				nb[b] = {}
			nb[a][b] = true
			nb[b][a] = true
	var unk := PackedInt32Array()
	for v in nb.keys():
		if not fixed.has(v):
			unk.append(v)
	if unk.is_empty():
		return
	unk.sort()
	var idx := {}
	var all := nb.keys()
	all.sort()
	for i in all.size():
		idx[all[i]] = i
	var nn := all.size()
	var lists: Array = []
	var deg := PackedFloat64Array()
	var ext: Array = []   # per vertex: the sum of the outside neighbours' positions (fixed, so a constant of the row)
	for v in all:
		var l := PackedInt32Array()
		for w in nb[v].keys():
			l.append(idx[w])
		lists.append(l)
		var e := Vector3.ZERO
		var d := float(l.size())
		if fixed.has(v) and outer.has(v):
			for w in outer[v].keys():
				if not nb[v].has(w) and not fixed.has(w) or (fixed.has(w) and not nb[v].has(w)):
					e += vs[w]
					d += 1.0
		deg.append(d)
		ext.append(e)
	var is_u := PackedByteArray()
	is_u.resize(nn)
	for v in unk:
		is_u[idx[v]] = 1
	for comp in 3:
		var x0 := PackedFloat64Array()
		x0.resize(nn)
		for i in nn:
			x0[i] = 0.0 if is_u[i] == 1 else st.vp[all[i]][comp]
		var exc := PackedFloat64Array()
		for i in nn:
			exc.append(ext[i][comp])
		var b := _lt_l(lists, deg, x0, exc)
		for i in nn:
			b[i] = -b[i] if is_u[i] == 1 else 0.0
		var x := PackedFloat64Array()
		x.resize(nn)
		var r := b.duplicate()
		var p := r.duplicate()
		var rs := _dot(r, r)
		var rs0 := rs
		if rs0 > 1e-30:
			for it in 4 * unk.size() + 60:
				var ap := _lt_l(lists, deg, p, PackedFloat64Array())
				for i in nn:
					if is_u[i] == 0:
						ap[i] = 0.0
				var pap := _dot(p, ap)
				if absf(pap) < 1e-300:
					break
				var al := rs / pap
				for i in nn:
					x[i] += al * p[i]
					r[i] -= al * ap[i]
				var rn := _dot(r, r)
				if rn < 1e-26 * rs0:
					break
				var be := rn / rs
				rs = rn
				for i in nn:
					p[i] = r[i] + be * p[i]
		for i in nn:
			if is_u[i] == 1:
				var pos: Vector3 = st.vp[all[i]]
				pos[comp] = x[i]
				st.vp[all[i]] = pos


static func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var s := 0.0
	for i in a.size():
		s += a[i] * b[i]
	return s


## L^T L x for the uniform umbrella operator L = I - D^-1 A over the fill's adjacency lists
static func _lt_l(lists: Array, deg: PackedFloat64Array, x: PackedFloat64Array, ext: PackedFloat64Array) -> PackedFloat64Array:
	var n := x.size()
	var y := PackedFloat64Array()
	y.resize(n)
	for i in n:
		var l: PackedInt32Array = lists[i]
		var s := 0.0
		for j in l:
			s += x[j]
		y[i] = x[i] - (s + (ext[i] if ext.size() > 0 else 0.0)) / deg[i]
	var z := PackedFloat64Array()
	z.resize(n)
	for i in n:
		z[i] = y[i]
	for i in n:
		var l2: PackedInt32Array = lists[i]
		var w: float = y[i] / deg[i]
		for j in l2:
			z[j] -= w
	return z


## ---- checks used by the bars
## open edges left in a triangle/polygon soup + edges used by more than 2 faces
static func edge_stats(faces: Array) -> Dictionary:
	var cnt := {}
	for f in faces:
		var n: int = f.size()
		for c in n:
			var k := Vector2i(f[c], f[(c + 1) % n])
			cnt[k] = int(cnt.get(k, 0)) + 1
	var open := 0
	var multi := 0
	var same_dir := 0
	for k in cnt:
		if int(cnt[k]) > 1:
			same_dir += 1
		if not cnt.has(Vector2i(k.y, k.x)):
			open += 1
	return {"open_edges": open, "same_direction_edges": same_dir, "multi": multi}


## faces that disagree with a neighbour across a shared edge: the edge traversed the same way by both, or the normals opposed
static func flipped(vs: PackedVector3Array, faces: Array) -> int:
	var em := {}
	var nrm := []
	for fi in faces.size():
		var f: PackedInt32Array = faces[fi]
		nrm.append((vs[f[1]] - vs[f[0]]).cross(vs[f[2]] - vs[f[0]]))
		for c in f.size():
			var a: int = f[c]
			var b: int = f[(c + 1) % f.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not em.has(key):
				em[key] = []
			(em[key] as Array).append([fi, a < b])
	var bad := 0
	for key in em:
		var l: Array = em[key]
		if l.size() != 2:
			continue
		if l[0][1] == l[1][1] or (nrm[l[0][0]] as Vector3).dot(nrm[l[1][0]]) <= 0.0:
			bad += 1
	return bad
