class_name KMeshDecimate
extends RefCounted
## F03 (docs/ROADMAP_400.md): DECIMATE a KMesh, two ways, each one KMeshUndo step when bracketed by begin / commit.
##
## COLLAPSE: quadric error metrics, Garland & Heckbert 1997 ("Surface Simplification Using Quadric Error Metrics",
##   SIGGRAPH). The mesh is triangulated first (KMeshTopo.triangulate, attributes carried). Each vertex holds the
##   quadric Q = sum of K_p = p p^T over the planes p = (a, b, c, d) of its triangles, weighted by the triangle's area;
##   the error of a point x is x^T Q x (the summed squared distance to those planes). Pairs = the mesh's edges (no
##   non-edge pairs: a closed mesh never joins two pieces). Placement: the paper's "subset" variant, the vertex u goes
##   onto its neighbour v (a half-edge collapse, cost = (Q_u + Q_v)(v)), both directions candidates. Kept this way every
##   vertex left is an ORIGINAL vertex with its own position, UVs and weights: no attribute is interpolated, so a UV map
##   stays exactly right at every corner (only the triangles get coarser). Collapses go cheapest first from a binary heap
##   with lazy deletion (a vertex's stamp changes when it moves or takes a neighbour; stale entries are skipped).
## TARGET: a ratio of the TRIANGLE count (a quad counts 2) or a triangle count; it stops at the target or when no
##   collapse is allowed. An interior collapse removes 2 triangles, a border one 1, so it lands on the target or one under.
## KEPT (G&H section 5 + the usual rules of practice):
##   FEATURE EDGES: a border, a non-manifold edge, a UV seam (or any corner attribute: the two triangles' corners differ
##   at either end), a face attribute border (material), an edge attribute that is set (crease, seam mark), split custom
##   normals. Each feature edge adds a constraint plane through it, perpendicular to its triangle(s), weighted
##   FEATURE_W * length^2, to its two ends (G&H's boundary planes), so a feature line keeps its shape.
##   A vertex on exactly 2 feature edges may only slide ALONG one of them (onto the next vertex of its line); a vertex on
##   1 (a line's tip) or 3+ (a corner, a junction) never moves; lock_features = true: no vertex on a feature moves at all
##   (every seam / border vertex kept). Corners: the corners of u's triangles take the corner of v ON THE SAME SIDE of
##   the feature ("wedges": the corners round a vertex that share all their values); a collapse whose sides do not map
##   one-to-one is refused.
##   MANIFOLD: the link condition (the neighbours u and v share are exactly the far corners of their 1 or 2 triangles).
##   NO FLIP: a triangle whose normal would turn more than acos(FLIP_DOT) (78 deg), or that would lose its area, refuses
##   the collapse.
## Attributes (A09) follow by source: a vertex keeps its own, a triangle its source face's, a corner the corner it now
##   stands for, an edge that still joins the same two vertices (or that a slide carried along) its own; new edges get
##   the default. Shape keys (A13) and custom normals follow their vertices / corners.
##
## PLANAR: Blender's "limited dissolve". Every edge whose two faces' normals are within `angle` degrees and that is not
##   a feature edge (above) is dissolved (KMeshDissolve.dissolve_edges joins the faces into n-gons, corners keep their
##   values), then each vertex left with 2 edges that are in line within `angle` is dissolved (KMeshDissolve.dissolve_verts).
##   A region whose border would touch itself (a ring) is left as it is (KMeshDissolve's rule).
##
## MEASURES (used by the tests and the LOD errors): distance(a, b) = the two-sided sampled Hausdorff distance (samples
##   = every vertex and face centroid of one mesh, nearest point on the other's triangles, both ways; a uniform grid
##   finds the nearest triangle); flipped(after, before) = the faces of `after` whose normal points against the face of
##   `before` nearest their centroid.

const FEATURE_W := 100.0
const FLIP_DOT := 0.2
const PLANAR_ANGLE := 5.0   # deg, Blender's limited dissolve default

## the stats of the last collapse / planar
static var last := {}


## working state of one collapse
class _S:
	var P: PackedVector3Array
	var tv := PackedInt32Array()      # 3 verts per triangle
	var tc := PackedInt32Array()      # the source corner standing at each triangle corner
	var talive := PackedByteArray()
	var vf: Array = []                # per vertex: triangles (dead ones dropped lazily)
	var valive := PackedByteArray()
	var ver := PackedInt32Array()
	var Q := PackedFloat64Array()
	var ccls := PackedInt32Array()    # class of each source corner (same class = same values)
	var has_cls := false
	var emap := {}                    # edge key (lo * nv + hi, current verts) -> source edge
	var efeat := PackedByteArray()    # source edge has a set edge attribute
	var has_e := false
	var nv := 0
	var lock := false
	var fcache := PackedInt32Array()
	var last_sh := PackedInt32Array()   # _try's findings for the collapse that follows it
	var last_nbu := {}
	var last_cmap := {}
	# heap
	var hc := PackedFloat64Array()
	var hk := PackedInt64Array()   # (u << 32) | (v << 1) | only-this-direction
	var hs := PackedInt64Array()   # (ver[u] << 32) | ver[v] when pushed
	var top_c := 0.0
	var top_k := 0
	var top_s := 0
	var n_heap := 0

	func tris_of(v: int) -> PackedInt32Array:
		var l: PackedInt32Array = vf[v]
		var out := PackedInt32Array()
		for t in l:
			if talive[t] == 1:
				out.append(t)
		if out.size() != l.size():
			vf[v] = out
		return out

	func slot(t: int, v: int) -> int:
		var b := 3 * t
		return 0 if tv[b] == v else (1 if tv[b + 1] == v else 2)

	func has_v(t: int, v: int) -> bool:
		var b := 3 * t
		return tv[b] == v or tv[b + 1] == v or tv[b + 2] == v

	func shared(a: int, b: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		for t in tris_of(a):
			if has_v(t, b):
				out.append(t)
		return out

	func neighbours(v: int) -> Dictionary:
		var nb := {}
		for t in tris_of(v):
			var b := 3 * t
			for k in 3:
				if tv[b + k] != v:
					nb[tv[b + k]] = true
		return nb

	func is_feature(a: int, b: int) -> bool:
		var sh := shared(a, b)
		return feat2(a, b, sh[0] if sh.size() > 0 else -1, sh[1] if sh.size() == 2 else -1)

	## the edge a-b with its triangles t1, t2 (t2 < 0: a border or non-manifold) is a feature edge
	func feat2(a: int, b: int, t1: int, t2: int) -> bool:
		if t1 < 0 or t2 < 0:
			return true
		if has_cls:
			if ccls[tc[3 * t1 + slot(t1, a)]] != ccls[tc[3 * t2 + slot(t2, a)]]:
				return true
			if ccls[tc[3 * t1 + slot(t1, b)]] != ccls[tc[3 * t2 + slot(t2, b)]]:
				return true
		if has_e:
			var s: int = emap.get(mini(a, b) * nv + maxi(a, b), -1)
			if s >= 0 and efeat[s] == 1:
				return true
		return false

	## how many feature edges meet at v (cached until v's fan changes)
	func fdeg(v: int) -> int:
		if fcache[v] < 0:
			var n := 0
			for w in neighbours(v):
				if is_feature(v, w):
					n += 1
			fcache[v] = n
		return fcache[v]

	func cost(u: int, v: int) -> float:
		var p := P[v]
		var x := p.x
		var y := p.y
		var z := p.z
		var a := 10 * u
		var b := 10 * v
		var q0 := Q[a] + Q[b]
		var q1 := Q[a + 1] + Q[b + 1]
		var q2 := Q[a + 2] + Q[b + 2]
		var q3 := Q[a + 3] + Q[b + 3]
		var q4 := Q[a + 4] + Q[b + 4]
		var q5 := Q[a + 5] + Q[b + 5]
		var q6 := Q[a + 6] + Q[b + 6]
		var q7 := Q[a + 7] + Q[b + 7]
		var q8 := Q[a + 8] + Q[b + 8]
		var q9 := Q[a + 9] + Q[b + 9]
		return maxf(0.0, q0 * x * x + 2.0 * q1 * x * y + 2.0 * q2 * x * z + 2.0 * q3 * x + q4 * y * y + 2.0 * q5 * y * z + 2.0 * q6 * y + q7 * z * z + 2.0 * q8 * z + q9)

	func add_plane(v: int, n: Vector3, d: float, w: float) -> void:
		var a := 10 * v
		Q[a] += w * n.x * n.x
		Q[a + 1] += w * n.x * n.y
		Q[a + 2] += w * n.x * n.z
		Q[a + 3] += w * n.x * d
		Q[a + 4] += w * n.y * n.y
		Q[a + 5] += w * n.y * n.z
		Q[a + 6] += w * n.y * d
		Q[a + 7] += w * n.z * n.z
		Q[a + 8] += w * n.z * d
		Q[a + 9] += w * d * d

	## the edge u-v in its cheaper direction (u goes onto v); only_dir: that direction alone (the other was refused)
	func push(u: int, v: int, only_dir := false) -> void:
		var c := cost(u, v)
		if not only_dir:
			var c2 := cost(v, u)
			if c2 < c:
				c = c2
				var x := u
				u = v
				v = x
		var key := (u << 32) | (v << 1) | (1 if only_dir else 0)
		var st := (ver[u] << 32) | ver[v]
		var i := n_heap
		n_heap += 1
		if hc.size() < n_heap:
			var cap := maxi(64, n_heap * 2)
			hc.resize(cap)
			hk.resize(cap)
			hs.resize(cap)
		while i > 0:
			var p := (i - 1) >> 1
			if hc[p] <= c:
				break
			hc[i] = hc[p]
			hk[i] = hk[p]
			hs[i] = hs[p]
			i = p
		hc[i] = c
		hk[i] = key
		hs[i] = st

	## remove the top entry into top_c / top_k / top_s
	func pop() -> void:
		top_c = hc[0]
		top_k = hk[0]
		top_s = hs[0]
		n_heap -= 1
		if n_heap > 0:
			var c := hc[n_heap]
			var lk := hk[n_heap]
			var ls := hs[n_heap]
			var i := 0
			var n := n_heap
			while true:
				var l := 2 * i + 1
				if l >= n:
					break
				var r := l + 1
				var s := r if r < n and hc[r] < hc[l] else l
				if hc[s] >= c:
					break
				hc[i] = hc[s]
				hk[i] = hk[s]
				hs[i] = hs[s]
				i = s
			hc[i] = c
			hk[i] = lk
			hs[i] = ls


## the class of every corner: corners with the same corner-attribute values, face-attribute values and custom normal
## share a class. Returns [] when the mesh has none of these (every corner alike).
static func _corner_classes(m: KMesh) -> PackedInt32Array:
	var cn: Array = []
	var nc := m.domain_count(KMesh.AD_CORNER)
	var cnames := []
	var fnames := []
	for k in m.attrs:
		var dom: String = m.attrs[k]["domain"]
		if dom == KMesh.AD_CORNER:
			cnames.append(k)
		elif dom == KMesh.AD_FACE:
			fnames.append(k)
	var has_cn := not m.custom_normals.is_empty()
	if cnames.is_empty() and fnames.is_empty() and not has_cn:
		return PackedInt32Array()
	if has_cn:
		for f in m.custom_normals:
			for nrm in (f as PackedVector3Array):
				cn.append(nrm)
	var ids := {}
	var out := PackedInt32Array()
	out.resize(nc)
	if cnames.size() == 1 and fnames.is_empty() and not has_cn:   # the common case: one UV map
		var data = m.attrs[cnames[0]]["data"]
		for c in nc:
			var id: int = ids.get(data[c], -1)
			if id < 0:
				id = ids.size()
				ids[data[c]] = id
			out[c] = id
		return out
	var he0 := m.face_he0
	for fi in m.faces.size():
		var n := (m.faces[fi] as PackedInt32Array).size()
		for i in n:
			var c := he0[fi] + i
			var key := []
			for k in cnames:
				key.append(m.attrs[k]["data"][c])
			for k in fnames:
				key.append(m.attrs[k]["data"][fi])
			if has_cn and c < cn.size():
				key.append(cn[c])
			var kk = key[0] if key.size() == 1 else key
			var id: int = ids.get(kk, -1)
			if id < 0:
				id = ids.size()
				ids[kk] = id
			out[c] = id
	return out


## Collapse to `ratio` of the triangle count, or to `target_tris` triangles when > 0. lock_features: no vertex on a
## border / seam / attribute border moves. Returns {"tris_before", "tris_after", "target", "collapses", "refused_flip",
## "refused_link", "refused_side", "refused_lock", "max_cost", "ms"} (also in `last`). One KMeshUndo step when bracketed.
static func collapse(m: KMesh, ratio := 0.5, target_tris := -1, lock_features := false) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var tris0 := m.triangle_count()
	var target := target_tris if target_tris > 0 else int(round(tris0 * ratio))
	target = maxi(target, 4)
	var res := {"tris_before": tris0, "tris_after": tris0, "target": target, "collapses": 0, "refused_flip": 0,
		"refused_link": 0, "refused_side": 0, "refused_lock": 0, "max_cost": 0.0, "ms": 0.0}
	if target >= tris0 or m.faces.is_empty():
		last = res
		return res
	if tris0 != m.faces.size():
		KMeshTopo.triangulate(m)   # n-gons -> triangles, A09 attributes + custom normals carried
	var s := _S.new()
	s.lock = lock_features
	s.P = m.verts
	var nv := m.verts.size()
	var nt := m.faces.size()
	s.nv = nv
	s.tv.resize(3 * nt)
	s.tc.resize(3 * nt)
	s.talive.resize(nt)
	s.talive.fill(1)
	s.valive.resize(nv)
	s.valive.fill(1)
	s.ver.resize(nv)
	s.Q.resize(10 * nv)
	s.Q.fill(0.0)
	s.fcache.resize(nv)
	s.fcache.fill(-1)
	var cnt := PackedInt32Array()
	cnt.resize(nv)
	for t in nt:
		var f: PackedInt32Array = m.faces[t]
		for k in 3:
			s.tv[3 * t + k] = f[k]
			s.tc[3 * t + k] = 3 * t + k
			cnt[f[k]] += 1
	var vstart := PackedInt32Array()
	vstart.resize(nv + 1)
	for v in nv:
		vstart[v + 1] = vstart[v] + cnt[v]
	var vlist := PackedInt32Array()
	vlist.resize(vstart[nv])
	cnt.fill(0)
	for t in nt:
		for k in 3:
			var v := s.tv[3 * t + k]
			vlist[vstart[v] + cnt[v]] = t
			cnt[v] += 1
	s.vf.resize(nv)
	for v in nv:
		s.vf[v] = vlist.slice(vstart[v], vstart[v + 1])
	s.ccls = _corner_classes(m)
	s.has_cls = not s.ccls.is_empty()
	for k in m.attrs:
		if m.attrs[k]["domain"] == KMesh.AD_EDGE:
			s.has_e = true
	var src_edges: Array = m.edges() if s.has_e else []
	if s.has_e:
		s.efeat.resize(src_edges.size())
		for ei in src_edges.size():
			var e: Vector2i = src_edges[ei]
			s.emap[e.x * nv + e.y] = ei
			for k in m.attrs:
				var r: Dictionary = m.attrs[k]
				if r["domain"] == KMesh.AD_EDGE and r["data"][ei] != r["default"]:
					s.efeat[ei] = 1
	# quadrics: the planes of the triangles, area weighted
	for t in nt:
		var a := s.P[s.tv[3 * t]]
		var b := s.P[s.tv[3 * t + 1]]
		var c := s.P[s.tv[3 * t + 2]]
		var cr := (b - a).cross(c - a)
		var ln := cr.length()
		if ln < 1e-20:
			continue
		var n := cr / ln
		var d := -n.dot(a)
		for k in 3:
			s.add_plane(s.tv[3 * t + k], n, d, ln * 0.5)
	# feature edges: constraint planes through them
	# (half-edge h = corner h = triangle h / 3 after the triangulation; its twin's next is the twin face's corner at a)
	var he_t := m.he_twin
	var he_n := m.he_next
	for h in 3 * nt:
		var a := s.tv[h]
		var b := s.tv[3 * (h / 3) + (h + 1) % 3]
		var g := he_t[h]
		var feat := g < 0
		if not feat and s.has_cls:
			feat = s.ccls[h] != s.ccls[he_n[g]] or s.ccls[he_n[h]] != s.ccls[g]
		if not feat and s.has_e:
			var se: int = s.emap.get(mini(a, b) * nv + maxi(a, b), -1)
			feat = se >= 0 and s.efeat[se] == 1
		if not feat:
			continue
		var t := h / 3
		var ed := s.P[b] - s.P[a]
		var fn := (s.P[s.tv[3 * t + 1]] - s.P[s.tv[3 * t]]).cross(s.P[s.tv[3 * t + 2]] - s.P[s.tv[3 * t]])
		var pn := ed.cross(fn)
		if pn.length_squared() < 1e-30:
			continue
		pn = pn.normalized()
		var d := -pn.dot(s.P[a])
		var w := FEATURE_W * ed.length_squared()
		s.add_plane(a, pn, d, w)
		s.add_plane(b, pn, d, w)
	for h in 3 * nt:
		var g := he_t[h]
		if g < 0 or h < g:
			s.push(s.tv[h], s.tv[3 * (h / 3) + (h + 1) % 3])
	var alive := nt
	while alive > target and s.n_heap > 0:
		s.pop()
		var u: int = s.top_k >> 32
		var v: int = (s.top_k & 0xFFFFFFFF) >> 1
		if s.valive[u] == 0 or s.valive[v] == 0 or s.top_s != ((s.ver[u] << 32) | s.ver[v]):
			continue
		var why := _try(s, u, v)
		if why != "":
			res[why] = int(res[why]) + 1
			if why != "refused_link" and (s.top_k & 1) == 0:
				s.push(v, u, true)   # the other way round may still go
			continue
		var sh := s.last_sh
		var nbu := s.last_nbu
		var cmap := s.last_cmap
		for t in sh:
			s.talive[t] = 0
			alive -= 1
		var lv: PackedInt32Array = s.tris_of(v)
		for t in s.tris_of(u):
			var k := s.slot(t, u)
			s.tv[3 * t + k] = v
			if s.has_cls:
				s.tc[3 * t + k] = cmap[s.ccls[s.tc[3 * t + k]]]
			lv.append(t)
		s.vf[v] = lv
		s.vf[u] = PackedInt32Array()
		if not s.emap.is_empty():
			s.emap.erase(mini(u, v) * nv + maxi(u, v))
			for w in nbu:
				if w == v:
					continue
				var ku: int = mini(u, w) * nv + maxi(u, w)
				var kv: int = mini(v, w) * nv + maxi(v, w)
				var su: int = s.emap.get(ku, -1)
				if su >= 0:
					var sv: int = s.emap.get(kv, -1)
					if sv < 0 or (s.efeat[su] == 1 and s.efeat[sv] == 0):
						s.emap[kv] = su
					s.emap.erase(ku)
		for i in 10:
			s.Q[10 * v + i] += s.Q[10 * u + i]
		s.valive[u] = 0
		s.fcache[v] = -1
		for w in nbu:
			s.fcache[w] = -1
		s.ver[u] += 1
		s.ver[v] += 1
		res["max_cost"] = maxf(float(res["max_cost"]), s.top_c)
		res["collapses"] = int(res["collapses"]) + 1
		for w in s.neighbours(v):
			s.push(v, w)
	_write_back(m, s, src_edges)
	res["tris_after"] = m.face_count()
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	last = res
	return res


## "" when u -> v may go, else the stat it counts under
static func _try(s: _S, u: int, v: int) -> String:
	var tu := s.tris_of(u)
	var f1 := {}   # neighbour w of u -> the first triangle of u's fan with w, f2 the second (-2: a third, non-manifold)
	var f2 := {}
	for t in tu:
		var b := 3 * t
		for k in 3:
			var w := s.tv[b + k]
			if w == u:
				continue
			if not f1.has(w):
				f1[w] = t
			elif not f2.has(w):
				f2[w] = t
			else:
				f2[w] = -2
	if not f1.has(v):
		return "refused_link"
	if s.fcache[u] < 0:
		var n := 0
		for w in f1:
			if s.feat2(u, w, f1[w], f2.get(w, -1)):
				n += 1
		s.fcache[u] = n
	var fd := s.fcache[u]
	if fd > 0 and (s.lock or fd != 2 or not s.feat2(u, v, f1[v], f2.get(v, -1))):
		return "refused_lock"
	var sh := PackedInt32Array([f1[v]])
	var t2: int = f2.get(v, -1)
	if t2 == -2:
		return "refused_link"
	if t2 >= 0:
		sh.append(t2)
	# link condition
	var nbv := s.neighbours(v)
	var opp := {}
	for t in sh:
		for k in 3:
			var x := s.tv[3 * t + k]
			if x != u and x != v:
				opp[x] = true
	var common := 0
	for x in f1:
		if nbv.has(x):
			if not opp.has(x):
				return "refused_link"
			common += 1
	if common != opp.size():
		return "refused_link"
	if f1.size() + nbv.size() - 2 - common <= 2 and sh.size() == 2:
		return "refused_link"   # a tetrahedron would fold flat
	var cmap := _side_map(s, u, v, sh, tu)
	if cmap.is_empty():
		return "refused_side"
	# no flip, no lost area
	var pv := s.P[v]
	for t in tu:
		var b := 3 * t
		var i0 := s.tv[b]
		var i1 := s.tv[b + 1]
		var i2 := s.tv[b + 2]
		if i0 == v or i1 == v or i2 == v:
			continue
		var a0 := s.P[i0]
		var a1 := s.P[i1]
		var a2 := s.P[i2]
		var n0 := (a1 - a0).cross(a2 - a0)
		if i0 == u:
			a0 = pv
		elif i1 == u:
			a1 = pv
		else:
			a2 = pv
		var n1 := (a1 - a0).cross(a2 - a0)
		var l0 := n0.length()
		var l1 := n1.length()
		if l1 <= l0 * 1e-6 or n0.dot(n1) < FLIP_DOT * l0 * l1:
			return "refused_flip"
	s.last_sh = sh
	s.last_nbu = f1
	s.last_cmap = cmap
	return ""


## class of u's corner -> the source corner of v on the same side; {} when the sides do not map one-to-one
static func _side_map(s: _S, u: int, v: int, sh: PackedInt32Array, tu: PackedInt32Array) -> Dictionary:
	if not s.has_cls:
		return {0: -1}
	var cmap := {}
	var ccv := {}
	var used := {}
	for t in sh:
		var cu := s.ccls[s.tc[3 * t + s.slot(t, u)]]
		var srcv := s.tc[3 * t + s.slot(t, v)]
		var cv := s.ccls[srcv]
		if ccv.has(cu):
			if ccv[cu] != cv:
				return {}
			continue
		if used.has(cv):
			return {}   # two sides of u would become one side of v: the seam would close
		ccv[cu] = cv
		used[cv] = true
		cmap[cu] = srcv
	for t in tu:
		if not cmap.has(s.ccls[s.tc[3 * t + s.slot(t, u)]]):
			return {}   # u has a side that does not touch the edge (a seam crosses u elsewhere)
	return cmap


## the live triangles back into m: verts compacted, every attribute, custom normal and shape key by its source
static func _write_back(m: KMesh, s: _S, src_edges: Array) -> void:
	var nv := m.verts.size()
	var idx := PackedInt32Array()
	idx.resize(nv)
	idx.fill(-1)
	var vsrc := PackedInt32Array()
	var nverts := PackedVector3Array()
	var nf: Array = []
	var fsrc := PackedInt32Array()
	var csrc := PackedInt32Array()
	for t in s.talive.size():
		if s.talive[t] == 0:
			continue
		var f := PackedInt32Array()
		for k in 3:
			var v := s.tv[3 * t + k]
			if idx[v] < 0:
				idx[v] = nverts.size()
				nverts.append(m.verts[v])
				vsrc.append(v)
			f.append(idx[v])
			csrc.append(s.tc[3 * t + k])
		nf.append(f)
		fsrc.append(t)
	var cflat := PackedVector3Array()
	for c in m.custom_normals:
		cflat.append_array(c as PackedVector3Array)
	var saved := m.attrs
	m.attrs = {}
	m.from_arrays(nverts, nf)
	if cflat.size() > 0:
		var cn := []
		for i in nf.size():
			cn.append(PackedVector3Array([cflat[csrc[3 * i]], cflat[csrc[3 * i + 1]], cflat[csrc[3 * i + 2]]]))
		m.custom_normals = cn
	else:
		m.custom_normals = []
	if not saved.is_empty():
		var esrc := PackedInt32Array()
		for e in m.edges():
			var a := vsrc[(e as Vector2i).x]
			var b := vsrc[(e as Vector2i).y]
			esrc.append(s.emap.get(mini(a, b) * nv + maxi(a, b), -1))
		m.attrs = saved
		m.attr_remap(vsrc, fsrc, csrc, esrc)
	if not m.shapes.is_empty():
		var sh: Dictionary = m.shapes
		sh["basis"] = _pick(sh["basis"], vsrc)
		for k in sh.get("keys", []):
			k["delta"] = _pick(k["delta"], vsrc)


static func _pick(a: PackedVector3Array, src: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = a[src[i]] if src[i] < a.size() else Vector3.ZERO
	return out


## a copy that shares nothing with m (verts, faces, attributes, custom normals; no shape keys)
static func copy(m: KMesh) -> KMesh:
	var c := KMesh.new().from_arrays(m.verts, m.faces)
	c.attrs = m.attr_snapshot()
	c.custom_normals = m.custom_normals.duplicate(true)
	c.normal_mode = m.normal_mode
	c.auto_angle = m.auto_angle
	return c


## MeshTools.op "decimate" (half), "decimate_quarter", "decimate_planar" on the model preview's mesh: one undo step;
## returns what to say
static func op(name: String, m) -> String:
	var ui = m.kmed
	if ui == null or ui.mesh == null:
		return ""
	var f0: int = ui.mesh.face_count()
	ui.undo.begin(ui.mesh)
	var r := planar(ui.mesh) if name == "decimate_planar" else collapse(ui.mesh, 0.25 if name == "decimate_quarter" else 0.5)
	var st: Dictionary = ui.undo.commit("planar decimate" if name == "decimate_planar" else "decimate")
	ui._after_topo()   # a fresh selection; the view shows the mesh (LOD0) again
	if st.is_empty():
		return "Model: nothing to decimate (%s)" % ("no neighbouring faces in one plane" if name == "decimate_planar" else "already at or under the target")
	if name == "decimate_planar":
		return "Model: planar decimate: %d faces -> %d (neighbours within %.0f deg joined, seams and borders kept). Ctrl+Z undoes" % [f0, ui.mesh.face_count(), PLANAR_ANGLE]
	return "Model: decimated (quadric collapse): %d triangles -> %d (target %d), borders and UV seams kept, nothing flipped. Ctrl+Z undoes" % [int(r["tris_before"]), int(r["tris_after"]), int(r["target"])]


# ---------------------------------------------------------------- planar

## Dissolve the faces that are coplanar within `angle` degrees (features kept). Returns {"faces_before",
## "faces_after", "edges", "verts"} (also in `last`). One KMeshUndo step when bracketed.
static func planar(m: KMesh, angle := PLANAR_ANGLE) -> Dictionary:
	var f0 := m.face_count()
	var cosl := cos(deg_to_rad(angle))
	var cls := _corner_classes(m)
	var nv := m.verts.size()
	var efeat := {}
	var es: Array = m.edges()
	for k in m.attrs:
		var r: Dictionary = m.attrs[k]
		if r["domain"] == KMesh.AD_EDGE:
			for ei in es.size():
				if r["data"][ei] != r["default"]:
					efeat[(es[ei] as Vector2i).x * nv + (es[ei] as Vector2i).y] = true
	var fn := m.face_normals
	var he_t := m.he_twin
	var he_f := m.he_face
	var he_v := m.he_vert
	var he_n := m.he_next
	var list := []
	for h in he_t.size():
		var g := he_t[h]
		if g < 0 or g < h:
			continue
		var a := he_v[h]
		var b := he_v[he_n[h]]
		if efeat.has(mini(a, b) * nv + maxi(a, b)):
			continue
		if fn[he_f[h]].dot(fn[he_f[g]]) < cosl:
			continue
		# corners: h's corner at a vs g's next (at a); h's next (at b) vs g (at b)
		if not cls.is_empty() and (cls[h] != cls[he_n[g]] or cls[he_n[h]] != cls[g]):
			continue
		list.append(Vector2i(a, b))
	var ne := 0
	if not list.is_empty():
		ne = KMeshDissolve.dissolve_edges(m, list, false)
	# verts left between 2 edges in line
	var nb := {}
	for f in m.faces:
		var n := (f as PackedInt32Array).size()
		for i in n:
			var a: int = f[i]
			if not nb.has(a):
				nb[a] = {}
			nb[a][f[(i + 1) % n]] = true
			nb[a][f[(i + n - 1) % n]] = true
	var vl := []
	for v in nb:
		var ws: Array = (nb[v] as Dictionary).keys()
		if ws.size() != 2:
			continue
		var d1: Vector3 = m.verts[v] - m.verts[ws[0]]
		var d2: Vector3 = m.verts[ws[1]] - m.verts[v]
		if d1.length_squared() > 0.0 and d2.length_squared() > 0.0 and d1.normalized().dot(d2.normalized()) >= cosl:
			vl.append(v)
	var nd := 0
	if not vl.is_empty():
		nd = KMeshDissolve.dissolve_verts(m, vl)
	last = {"faces_before": f0, "faces_after": m.face_count(), "edges": list.size(), "faces_joined": ne, "verts": nd}
	return last


# ---------------------------------------------------------------- measures

## nearest-triangle search over one mesh (its faces fan-split), a uniform grid of cells
class _Grid:
	var P: PackedVector3Array
	var T := PackedInt32Array()
	var TN := PackedVector3Array()
	var org := Vector3.ZERO
	var h := 1.0
	var dim := Vector3i.ONE
	var cs := PackedInt32Array()
	var cl := PackedInt32Array()

	func _init(m: KMesh) -> void:
		P = m.verts
		for f in m.faces:
			var fp := f as PackedInt32Array
			for i in range(1, fp.size() - 1):
				T.append_array([fp[0], fp[i], fp[i + 1]])
		var nt := T.size() / 3
		var box := AABB(P[0], Vector3.ZERO) if P.size() > 0 else AABB()
		for p in P:
			box = box.expand(p)
		var el := 0.0
		for t in nt:
			var a := P[T[3 * t]]
			var b := P[T[3 * t + 1]]
			var c := P[T[3 * t + 2]]
			el += a.distance_to(b) + b.distance_to(c) + c.distance_to(a)
			TN.append((b - a).cross(c - a).normalized())
		h = maxf(el / maxf(3.0 * nt, 1.0) * 2.0, box.get_longest_axis_size() / 96.0)
		h = maxf(h, 1e-6)
		org = box.position - Vector3.ONE * h * 0.5
		dim = Vector3i((box.size / h).ceil()) + Vector3i.ONE
		var ncell := dim.x * dim.y * dim.z
		var cnt := PackedInt32Array()
		cnt.resize(ncell + 1)
		for pass_i in 2:
			var fill := PackedInt32Array()
			if pass_i == 1:
				cs.resize(ncell + 1)
				var acc := 0
				for i in ncell:
					cs[i] = acc
					acc += cnt[i]
				cs[ncell] = acc
				cl.resize(acc)
				fill.resize(ncell)
			for t in nt:
				var lo := Vector3i(((_minv(t) - org) / h).floor())
				var hi := Vector3i(((_maxv(t) - org) / h).floor())
				for x in range(maxi(lo.x, 0), mini(hi.x, dim.x - 1) + 1):
					for y in range(maxi(lo.y, 0), mini(hi.y, dim.y - 1) + 1):
						for z in range(maxi(lo.z, 0), mini(hi.z, dim.z - 1) + 1):
							var ci := (x * dim.y + y) * dim.z + z
							if pass_i == 0:
								cnt[ci] += 1
							else:
								cl[cs[ci] + fill[ci]] = t
								fill[ci] += 1

	func _minv(t: int) -> Vector3:
		return P[T[3 * t]].min(P[T[3 * t + 1]]).min(P[T[3 * t + 2]])

	func _maxv(t: int) -> Vector3:
		return P[T[3 * t]].max(P[T[3 * t + 1]]).max(P[T[3 * t + 2]])

	## [distance, triangle] of the nearest triangle to p
	func closest(p: Vector3) -> Array:
		var c := Vector3i(((p - org) / h).floor()).clamp(Vector3i.ZERO, dim - Vector3i.ONE)
		var best := INF
		var bt := -1
		var kmax := maxi(dim.x, maxi(dim.y, dim.z))
		for k in kmax + 1:
			if k > 0 and best <= (k - 1) * h:
				break
			for x in range(c.x - k, c.x + k + 1):
				if x < 0 or x >= dim.x:
					continue
				for y in range(c.y - k, c.y + k + 1):
					if y < 0 or y >= dim.y:
						continue
					var edge_xy := absi(x - c.x) == k or absi(y - c.y) == k
					var zs := range(c.z - k, c.z + k + 1) if edge_xy else [c.z - k, c.z + k]
					for zz in zs:
						var z: int = zz
						if z < 0 or z >= dim.z:
							continue
						var ci: int = (x * dim.y + y) * dim.z + z
						for j in range(cs[ci], cs[ci + 1]):
							var t := cl[j]
							var d := p.distance_to(KMeshDecimate.closest_on_tri(p, P[T[3 * t]], P[T[3 * t + 1]], P[T[3 * t + 2]]))
							if d < best:
								best = d
								bt = t
		return [best, bt]


## the point of triangle abc nearest p (Ericson, Real-Time Collision Detection 5.1.5)
static func closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


static func _samples(m: KMesh) -> PackedVector3Array:
	var out := m.verts.duplicate()
	for fi in m.faces.size():
		out.append(m.face_center(fi))
	return out


## two-sided sampled Hausdorff distance: {"max", "ab", "ba", "mean"} (metres)
static func distance(a: KMesh, b: KMesh) -> Dictionary:
	var gb := _Grid.new(b)
	var ga := _Grid.new(a)
	var ab := 0.0
	var ba := 0.0
	var sum := 0.0
	var n := 0
	for p in _samples(a):
		var d: float = gb.closest(p)[0]
		ab = maxf(ab, d)
		sum += d
		n += 1
	for p in _samples(b):
		var d: float = ga.closest(p)[0]
		ba = maxf(ba, d)
		sum += d
		n += 1
	return {"max": maxf(ab, ba), "ab": ab, "ba": ba, "mean": sum / maxi(n, 1)}


## faces of `after` whose normal points against the `before` face nearest their centroid
static func flipped(after: KMesh, before: KMesh) -> int:
	var g := _Grid.new(before)
	var n := 0
	for fi in after.faces.size():
		var r := g.closest(after.face_center(fi))
		if int(r[1]) >= 0 and after.face_normals[fi].dot(g.TN[int(r[1])]) < 0.0:
			n += 1
	return n


## the diagonal of the mesh's bounding box
static func diag(m: KMesh) -> float:
	if m.verts.is_empty():
		return 0.0
	var box := AABB(m.verts[0], Vector3.ZERO)
	for p in m.verts:
		box = box.expand(p)
	return box.size.length()
