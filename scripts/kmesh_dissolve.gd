class_name KMeshDissolve
extends RefCounted
## B05 (docs/ROADMAP_400.md): merge, dissolve and delete on a KMesh. Every op edits the face list, then rebuilds once.
##   merge(verts, "centre" | "first")   the verts become one, at their centroid or where the first one is
##   merge_by_distance(dist, only)      verts closer than dist become one (KMeshValidate._doubled finds the pairs)
##   dissolve_verts                     a valence-2 vert leaves its faces; any other vert takes its faces with it: they
##                                      join into one n-gon (an interior vert's fan becomes the ring around it)
##   dissolve_edges                     the two faces of each edge join (clean_verts: the ends left with 2 edges go too)
##   dissolve_faces                     each connected region becomes one n-gon; the verts inside it go
##   delete("verts" | "edges" | "faces" | "only_faces")  the faces touching the selection go, with the verts left in no
##                                      face (only_faces keeps every vert; KMesh has no loose edges to keep)
## A region joins only when its border is ONE loop that touches itself nowhere (no holes, no pinch): otherwise it is left.
## Attributes (A09) follow: a joined face takes the first face's values, each corner keeps the corner it came from, a
## merged vert keeps the target's. Bracket a call with KMeshUndo begin / commit for one undo step.

const MERGE_DIST := 1e-4   # m: merge by distance default, 0.1 mm


## working copy of the faces: each with the old corner index of its corners and the old face it stands for
class _W:
	var faces: Array = []   # PackedInt32Array; an empty one is removed
	var cs: Array = []      # per face: old corner index of each corner (-1 = new)
	var fs := PackedInt32Array()
	var nv := 0

	func _init(m: KMesh) -> void:
		nv = m.verts.size()
		var c := 0
		for fi in m.faces.size():
			var f: PackedInt32Array = m.faces[fi]
			faces.append(f.duplicate())
			var s := PackedInt32Array()
			for i in f.size():
				s.append(c + i)
			c += f.size()
			cs.append(s)
			fs.append(fi)

	func kill(fi: int) -> void:
		faces[fi] = PackedInt32Array()
		cs[fi] = PackedInt32Array()

	## faces (live) using v
	func around(v: int) -> Array:
		var out := []
		for fi in faces.size():
			if (faces[fi] as PackedInt32Array).has(v):
				out.append(fi)
		return out

	func neighbours(v: int, fl: Array) -> Dictionary:
		var nb := {}
		for fi in fl:
			var f: PackedInt32Array = faces[fi]
			var n := f.size()
			for i in n:
				if f[i] == v:
					nb[f[(i + 1) % n]] = true
					nb[f[(i + n - 1) % n]] = true
		return nb

	## take v out of every face that has it (a face left with < 3 corners goes)
	func drop_vert(v: int, fl: Array) -> void:
		for fi in fl:
			var f: PackedInt32Array = faces[fi]
			var c: PackedInt32Array = cs[fi]
			var i := f.find(v)
			while i >= 0:
				f.remove_at(i)
				c.remove_at(i)
				i = f.find(v)
			faces[fi] = f
			cs[fi] = c
			if f.size() < 3:
				kill(fi)

	## join the faces fl into one n-gon (into fl[0]) along their outer border, dropping drop_v from it. False = left as is.
	func join(fl: Array, drop_v := -1) -> bool:
		if fl.size() < 2 and drop_v < 0:
			return false
		var dir := {}
		for fi in fl:
			var f: PackedInt32Array = faces[fi]
			for i in f.size():
				dir[f[i] * nv + f[(i + 1) % f.size()]] = true
		var nxt := {}   # border: a -> [b, old corner of a]
		for fi in fl:
			var f: PackedInt32Array = faces[fi]
			var c: PackedInt32Array = cs[fi]
			for i in f.size():
				var a := f[i]
				var b := f[(i + 1) % f.size()]
				if dir.has(b * nv + a):
					continue
				if nxt.has(a):
					return false   # the border touches itself at a
				nxt[a] = [b, c[i]]
		if nxt.size() < 3:
			return false
		var s: int = nxt.keys()[0]
		var loop := PackedInt32Array()
		var lc := PackedInt32Array()
		var v := s
		while true:
			loop.append(v)
			lc.append(nxt[v][1])
			v = nxt[v][0]
			if v == s or not nxt.has(v) or loop.size() > nxt.size():
				break
		if v != s or loop.size() != nxt.size():
			return false   # more than one loop: a hole, or the faces are not connected
		var di := loop.find(drop_v) if drop_v >= 0 else -1
		if di >= 0:
			loop.remove_at(di)
			lc.remove_at(di)
		if loop.size() < 3:
			return false
		for fi in fl:
			kill(fi)
		faces[fl[0]] = loop
		cs[fl[0]] = lc
		return true

	## v -> r[v] on every face; repeats in a row collapse, a face left folded (< 3 verts, or a vert twice) goes
	func remap(r: PackedInt32Array) -> void:
		for fi in faces.size():
			var f: PackedInt32Array = faces[fi]
			if f.is_empty():
				continue
			var c: PackedInt32Array = cs[fi]
			var g := PackedInt32Array()
			var gc := PackedInt32Array()
			for i in f.size():
				var x := r[f[i]]
				if g.is_empty() or g[g.size() - 1] != x:
					g.append(x)
					gc.append(c[i])
			if g.size() > 1 and g[0] == g[g.size() - 1]:
				g.remove_at(g.size() - 1)
				gc.remove_at(gc.size() - 1)
			var uniq := {}
			for x in g:
				uniq[x] = true
			if g.size() < 3 or uniq.size() != g.size():
				kill(fi)
			else:
				faces[fi] = g
				cs[fi] = gc


## write the working faces back: drop the verts in `gone` and those the edit left in no face (unless keep_unused),
## compact, rebuild, and carry the attributes. r = where each old vert went (merge), empty = nowhere.
## Returns the new index of every old vert (-1 = gone).
static func _finish(m: KMesh, w: _W, gone: Dictionary, r := PackedInt32Array(), keep_unused := false) -> PackedInt32Array:
	var nv := m.verts.size()
	if r.is_empty():
		r.resize(nv)
		for v in nv:
			r[v] = v
	var was := PackedByteArray()
	was.resize(nv)
	for f in m.faces:
		for v in (f as PackedInt32Array):
			was[v] = 1
	var now := PackedByteArray()
	now.resize(nv)
	for f in w.faces:
		for v in (f as PackedInt32Array):
			now[v] = 1
	var idx := PackedInt32Array()
	idx.resize(nv)
	var nverts := PackedVector3Array()
	var vsrc := PackedInt32Array()
	for v in nv:
		idx[v] = -1
		if gone.has(v) or r[v] != v or (was[v] == 1 and now[v] == 0 and not keep_unused):
			continue
		idx[v] = nverts.size()
		nverts.append(m.verts[v])
		vsrc.append(v)
	var out := []
	var fsrc := PackedInt32Array()
	var csrc := PackedInt32Array()
	for fi in w.faces.size():
		var f: PackedInt32Array = w.faces[fi]
		if f.is_empty():
			continue
		var g := PackedInt32Array()
		for v in f:
			g.append(idx[v])
		out.append(g)
		fsrc.append(w.fs[fi])
		csrc.append_array(w.cs[fi])
	var has_a := not m.attrs.is_empty()
	var old_edges: Array = m.edges() if has_a else []
	var saved := m.attrs
	m.attrs = {}   # gathered below: from_arrays would only fit the old channels to the new counts
	m.from_arrays(nverts, out)
	if has_a:
		var by_pair := {}
		var n2 := nverts.size()
		for ei in old_edges.size():
			var e: Vector2i = old_edges[ei]
			var a := idx[r[e.x]]
			var b := idx[r[e.y]]
			if a >= 0 and b >= 0 and a != b and not by_pair.has(mini(a, b) * n2 + maxi(a, b)):
				by_pair[mini(a, b) * n2 + maxi(a, b)] = ei
		var esrc := PackedInt32Array()
		for e in m.edges():
			esrc.append(by_pair.get(e.x * n2 + e.y, -1))   # a joined face's new border edges take the default
		m.attrs = saved
		m.attr_remap(vsrc, fsrc, csrc, esrc)
	return idx


## the verts become one: at their centroid ("centre") or at the first one ("first"). Returns the merged vert's new
## index, -1 when fewer than 2 verts were given.
static func merge(m: KMesh, verts: Array, how := "centre") -> int:
	if verts.size() < 2:
		return -1
	var t: int = verts[0]
	if how == "centre":
		var c := Vector3.ZERO
		for v in verts:
			c += m.verts[v]
		m.verts[t] = c / verts.size()
	var r := PackedInt32Array()
	r.resize(m.verts.size())
	for v in r.size():
		r[v] = v
	for v in verts:
		r[v] = t
	var w := _W.new(m)
	w.remap(r)
	return _finish(m, w, {}, r)[t]


## verts closer than dist merge onto the first of their group (it keeps its place). only = limit to these verts.
## Returns how many verts went.
static func merge_by_distance(m: KMesh, dist := MERGE_DIST, only: Array = []) -> int:
	var lim := {}
	for v in only:
		lim[v] = true
	var pairs := KMeshValidate._doubled(m, dist, lim)
	if pairs.is_empty():
		return 0
	var r := PackedInt32Array()
	r.resize(m.verts.size())
	for v in r.size():
		r[v] = v
	for p in pairs:
		r[p[0]] = p[1]
	var w := _W.new(m)
	w.remap(r)
	_finish(m, w, {}, r)
	return pairs.size()


## Returns how many verts were dissolved.
static func dissolve_verts(m: KMesh, verts: Array) -> int:
	var w := _W.new(m)
	var gone := {}
	for v in verts:
		var fl := w.around(v)
		if fl.is_empty():
			continue
		if w.neighbours(v, fl).size() == 2:
			w.drop_vert(v, fl)
		elif not w.join(fl, v):
			continue
		gone[v] = true
	if not gone.is_empty():
		_finish(m, w, gone)
	return gone.size()


## edges: Vector2i (or [a, b]). The two faces of each join; edges with one face (a border) are left. clean_verts: then
## an end left with only 2 edges is dissolved too (a corner of a cube joined this way leaves the side faces triangles).
## Returns how many faces went.
static func dissolve_edges(m: KMesh, edges: Array, clean_verts := false) -> int:
	var nf0 := m.face_count()
	var up := PackedInt32Array()
	up.resize(nf0)
	for i in nf0:
		up[i] = i
	var ends := {}
	for e in edges:
		var a: int = e[0] if e is Array else e.x
		var b: int = e[1] if e is Array else e.y
		var h := m.find_half_edge(a, b)
		var g := m.find_half_edge(b, a)
		if h < 0 or g < 0:
			continue
		var fa := _root(up, m.he_face[h])
		var fb := _root(up, m.he_face[g])
		if fa != fb:
			up[maxi(fa, fb)] = mini(fa, fb)
		ends[a] = true
		ends[b] = true
	var groups := {}
	for fi in nf0:
		var k := _root(up, fi)
		if not groups.has(k):
			groups[k] = []
		groups[k].append(fi)
	var w := _W.new(m)
	var joined := false
	for k in groups:
		if (groups[k] as Array).size() > 1:
			joined = w.join(groups[k]) or joined
	if not joined:
		return 0
	var gone := {}
	if clean_verts:
		for v in ends:
			var fl := w.around(v)
			if not fl.is_empty() and w.neighbours(v, fl).size() == 2:
				w.drop_vert(v, fl)
				gone[v] = true
	_finish(m, w, gone)
	return nf0 - m.face_count()


static func _root(up: PackedInt32Array, i: int) -> int:
	while up[i] != i:
		up[i] = up[up[i]]
		i = up[i]
	return i


## each connected region (faces sharing an edge) becomes one n-gon. Returns how many faces went.
static func dissolve_faces(m: KMesh, faces: Array) -> int:
	var nf0 := m.face_count()
	var inset := {}
	for fi in faces:
		inset[int(fi)] = true
	var w := _W.new(m)
	var seen := {}
	var joined := false
	for s in inset:
		if seen.has(s):
			continue
		var comp := [s]
		seen[s] = true
		var q := [s]
		while not q.is_empty():
			var fi: int = q.pop_back()
			var f: PackedInt32Array = m.faces[fi]
			for i in f.size():
				var g := m.find_half_edge(f[(i + 1) % f.size()], f[i])
				if g < 0:
					continue
				var o: int = m.he_face[g]
				if inset.has(o) and not seen.has(o):
					seen[o] = true
					comp.append(o)
					q.append(o)
		if comp.size() > 1:
			joined = w.join(comp) or joined
	if not joined:
		return 0
	_finish(m, w, {})
	return nf0 - m.face_count()


## what: "verts" | "edges" | "faces" | "only_faces"; items: vert ids, Vector2i edges, or face ids.
## Returns how many faces went.
static func delete(m: KMesh, what: String, items: Array) -> int:
	var nf0 := m.face_count()
	var w := _W.new(m)
	var gone := {}
	match what:
		"verts":
			for v in items:
				gone[int(v)] = true
			for fi in nf0:
				for v in (m.faces[fi] as PackedInt32Array):
					if gone.has(v):
						w.kill(fi)
						break
		"edges":
			var ek := {}
			for e in items:
				var a: int = e[0] if e is Array else e.x
				var b: int = e[1] if e is Array else e.y
				ek[mini(a, b) * w.nv + maxi(a, b)] = true
			for fi in nf0:
				var f: PackedInt32Array = m.faces[fi]
				for i in f.size():
					var a := f[i]
					var b := f[(i + 1) % f.size()]
					if ek.has(mini(a, b) * w.nv + maxi(a, b)):
						w.kill(fi)
						break
		"faces", "only_faces":
			for fi in items:
				w.kill(int(fi))
		_:
			return 0
	_finish(m, w, gone, PackedInt32Array(), what == "only_faces")
	return nf0 - m.face_count()


## the selection as the op wants it, in the selection's mode: {"verts": [...], "edges": [...], "faces": [...]}
static func from_select(s: KMeshSelect) -> Dictionary:
	var vs := {}
	for v in s.verts:
		vs[v] = true
	for e in s.edges:
		vs[e.x] = true
		vs[e.y] = true
	for fi in s.faces:
		for v in (s.mesh.faces[fi] as PackedInt32Array):
			vs[v] = true
	return {"verts": vs.keys(), "edges": s.edges.keys(), "faces": s.faces.keys()}
