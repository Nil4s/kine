class_name KMeshFill
extends RefCounted
## FILL, FILL HOLES, GRID FILL on a KMesh (ROADMAP_400 B06). Static ops: each edits the mesh in place (one rebuild at the
## end, so a KMeshUndo begin / commit around it is one "topo" step) and returns the new selection
## {"verts": [int], "edges": [Vector2i(lo, hi)], "faces": [int], "error": "" or a message with the next step}.
## Make face (F): 3+ verts (or the verts of a closed edge loop in edge mode) become one face. The order round the face:
##   the selected edges when they close one loop; else the mesh's open-border edges among the verts when they make one
##   loop or one chain (the face closes the chain); else the verts sorted by angle round their centre, in the plane of
##   their normals. The winding: every border edge the face takes runs against its neighbour's (a->b in the neighbour,
##   b->a in the new face: the majority wins), so the new face agrees with the faces round it; with no neighbour edge the
##   face's normal points away from the mesh's centre. Refused: a face already on those verts, or an edge that would get
##   a third face.
## Make edge (F on exactly 2 verts): a KMesh holds faces only (no wire edges), so the edge is made by splitting the face
##   the two verts share into two faces (Blender's "connect vertex path" on one face). Refused when they share no face,
##   or are already joined by an edge.
## Fill holes (Alt+F): every open border loop (KMeshValidate._holes) with a selected vert on it becomes one n-gon wound
##   to match its border, or (triangulate) an ear-clipped fan of triangles in the loop's own plane (a concave hole too).
## Grid fill (Ctrl+F): a border loop of an even number N of verts becomes a quad grid of span x (N/2 - span) quads.
##   The loop is cut into four sides at four corners (sides span, N/2 - span, span, N/2 - span); the interior verts are
##   a Coons patch of the four sides (each side blended across, the corners' bilinear part taken off), so a flat square
##   hole gets an even flat grid and a curved one follows its border. Auto span / offset: the four corners where the
##   border turns most (ties: the squarest grid). Behaviour learned from Blender's manual; no Blender code.
## Attributes (A09): kept on what was there; new faces / verts / corners / edges take the default (a split face's two
##   halves both copy the face they came from). Tests: tests/fill_test.gd.

const EPS := 1e-9


# ---------------------------------------------------------------- make face / make edge

## F on these verts (and, in edge mode, these edges): one new face, or (2 verts) the face between them split.
static func make_face(m: KMesh, verts: Array, edges: Array = []) -> Dictionary:
	var vs := {}
	for v in verts:
		vs[int(v)] = true
	for e in edges:
		vs[int(e.x)] = true
		vs[int(e.y)] = true
	if vs.size() == 2:
		var k: Array = vs.keys()
		return connect_verts(m, k[0], k[1])
	if vs.size() < 3:
		return _none("select 3 or more verts (or a closed edge loop) to make a face, or 2 verts on one face to join them")
	var loop := _cycle(edges, vs)
	if loop.is_empty():
		loop = _border_order(m, vs)
	if loop.is_empty():
		loop = _angle_order(m, vs.keys())
	loop = _wind(m, loop)
	var n := loop.size()
	for i in n:
		if m.find_half_edge(loop[i], loop[(i + 1) % n]) != -1 and m.find_half_edge(loop[(i + 1) % n], loop[i]) != -1:
			return _none("the edge %d-%d already has a face on both sides: a third would make it non-manifold" % [loop[i], loop[(i + 1) % n]])
		if m.find_half_edge(loop[i], loop[(i + 1) % n]) != -1:
			return _none("these verts cannot be wound to match the faces round them (pick the border of one hole)")
	var key := loop.duplicate()
	key.sort()
	for f in m.faces:
		var fk: Array = Array(f as PackedInt32Array)
		fk.sort()
		if fk == key:
			return _none("there is already a face on these %d verts" % n)
	var nf: Array = m.faces.duplicate()
	nf.append(PackedInt32Array(loop))
	_commit(m, m.verts.duplicate(), nf, m.faces.size())
	return _from_faces(m, [m.faces.size() - 1])


## the edge a-b made by splitting the face both are on (a KMesh has no wire edges)
static func connect_verts(m: KMesh, a: int, b: int) -> Dictionary:
	if m.find_half_edge(a, b) != -1 or m.find_half_edge(b, a) != -1:
		return _none("verts %d and %d are already joined by an edge" % [a, b])
	for fi in m.faces.size():
		var f: PackedInt32Array = m.faces[fi]
		var ia := f.find(a)
		var ib := f.find(b)
		if ia == -1 or ib == -1:
			continue
		var f1 := PackedInt32Array()
		var f2 := PackedInt32Array()
		var i := ia
		while true:
			f1.append(f[i])
			if i == ib:
				break
			i = (i + 1) % f.size()
		i = ib
		while true:
			f2.append(f[i])
			if i == ia:
				break
			i = (i + 1) % f.size()
		var nf: Array = m.faces.duplicate()
		nf[fi] = f1
		nf.append(f2)
		var src_f := PackedInt32Array()
		for j in m.faces.size():
			src_f.append(j)
		src_f.append(fi)
		var src_v := PackedInt32Array()
		for v in m.verts.size():
			src_v.append(v)
		KMeshExtrude._commit(m, m.verts.duplicate(), nf, src_v, src_f)
		var r := _from_faces(m, [fi, m.faces.size() - 1])
		r["edges"] = [KMeshSelect.ekey(a, b)]
		r["verts"] = [a, b]
		return r
	return _none("verts %d and %d share no face: a mesh edge needs a face (select a 3rd vert for a triangle)" % [a, b])


## the selected edges as one closed loop through exactly the verts (else [])
static func _cycle(edges: Array, vs: Dictionary) -> Array:
	if edges.size() < 3:
		return []
	var adj := {}
	for e in edges:
		adj[int(e.x)] = (adj.get(int(e.x), []) as Array) + [int(e.y)]
		adj[int(e.y)] = (adj.get(int(e.y), []) as Array) + [int(e.x)]
	if adj.size() != vs.size() or edges.size() != vs.size():
		return []
	for v in adj:
		if (adj[v] as Array).size() != 2:
			return []
	return _walk(adj, adj.keys()[0], vs.size(), true)


## the open-border edges among the verts: one loop, or one chain through all of them (else [])
static func _border_order(m: KMesh, vs: Dictionary) -> Array:
	var adj := {}
	var ne := 0
	for a in vs:
		adj[a] = []
	for a in vs:
		for b in m.vert_neighbors(a):
			if b > a and vs.has(b) and m.is_boundary_edge(a, b):
				adj[a].append(b)
				adj[b].append(a)
				ne += 1
	var ends := []
	for v in adj:
		var d := (adj[v] as Array).size()
		if d == 0 or d > 2:
			return []
		if d == 1:
			ends.append(v)
	if ends.is_empty() and ne == vs.size():
		return _walk(adj, adj.keys()[0], vs.size(), true)
	if ends.size() == 2 and ne == vs.size() - 1:
		return _walk(adj, ends[0], vs.size(), false)
	return []


static func _walk(adj: Dictionary, start: int, n: int, closed: bool) -> Array:
	var out := [start]
	var prev := -1
	var v := start
	while out.size() < n:
		var nx := -1
		for w in adj[v]:
			if w != prev and not (w in out):
				nx = w
				break
		if nx == -1:
			return []
		out.append(nx)
		prev = v
		v = nx
	if closed and not (start in adj[v]):
		return []
	return out


## the verts sorted by angle round their centre, in the plane their normals agree on
static func _angle_order(m: KMesh, vs: Array) -> Array:
	var c := Vector3.ZERO
	var n := Vector3.ZERO
	for v in vs:
		c += m.verts[v]
		n += m.vert_normals[v] if v < m.vert_normals.size() else Vector3.ZERO
	c /= float(vs.size())
	if n.length() < 1e-6:   # the normals cancel: the plane through the spread of the points
		var far: int = vs[0]
		for v in vs:
			if m.verts[v].distance_squared_to(c) > m.verts[far].distance_squared_to(c):
				far = v
		var d1: Vector3 = m.verts[far] - c
		var best := 0.0
		for v in vs:
			var cr := d1.cross(m.verts[v] - c)
			if cr.length() > best:
				best = cr.length()
				n = cr
	if n.length() < 1e-12:
		n = Vector3.UP
	n = n.normalized()
	var u := (Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).cross(n).normalized()
	var w := n.cross(u)
	var keyed := []
	for v in vs:
		var d: Vector3 = m.verts[v] - c
		keyed.append([atan2(d.dot(w), d.dot(u)), v])
	keyed.sort_custom(func(p, q): return p[0] < q[0])
	return keyed.map(func(p): return p[1])


## the loop in the order that agrees with its neighbours (each shared border edge against theirs), else facing out
static func _wind(m: KMesh, loop: Array) -> Array:
	var n := loop.size()
	var vote := 0
	for i in n:
		var a: int = loop[i]
		var b: int = loop[(i + 1) % n]
		if m.find_half_edge(a, b) != -1:
			vote -= 1   # the neighbour already runs a->b: the face must run b->a
		if m.find_half_edge(b, a) != -1:
			vote += 1
	if vote == 0:
		var nrm := _newell(m.verts, loop)
		var lc := Vector3.ZERO
		for v in loop:
			lc += m.verts[v]
		lc /= float(n)
		var mc := Vector3.ZERO
		for p in m.verts:
			mc += p
		mc /= maxf(1.0, float(m.verts.size()))
		var out_dir := lc - mc
		if out_dir.length() < 1e-9:   # the mesh's centre is on the face: follow the verts' own normals
			for v in loop:
				out_dir += m.vert_normals[v]
		if nrm.dot(out_dir) < 0.0:
			vote = -1
	if vote < 0:
		var r := loop.duplicate()
		r.reverse()
		return r
	return loop


# ---------------------------------------------------------------- fill holes

## the open border loops (in face order: append one as a face and it matches its border) with a vert in `verts`
static func holes_touching(m: KMesh, verts: Array) -> Array:
	var vs := {}
	for v in verts:
		vs[int(v)] = true
	var out := []
	for l in KMeshValidate._holes(m):
		for v in l:
			if vs.has(int(v)):
				out.append(l)
				break
	return out


## Alt+F: every hole touching the verts becomes one n-gon (or triangles, ear-clipped in the hole's plane)
static func fill_holes(m: KMesh, verts: Array, triangulate := false) -> Dictionary:
	var hs := holes_touching(m, verts)
	if hs.is_empty():
		return _none("no open border touches the selection (select a vert on the edge of a hole)")
	var nf: Array = m.faces.duplicate()
	var f0 := nf.size()
	for l in hs:
		if triangulate:
			for t in ear_clip(m.verts, l):
				nf.append(PackedInt32Array(t))
		else:
			nf.append(PackedInt32Array(l))
	_commit(m, m.verts.duplicate(), nf, f0)
	var r := _from_faces(m, range(f0, m.faces.size()))
	r["holes"] = hs.size()
	return r


## triangles of a simple polygon (any concavity) in its own plane, wound like the loop; a stuck clip falls back to a fan
static func ear_clip(pts: PackedVector3Array, loop: Array) -> Array:
	var n := _newell(pts, loop).normalized()
	var idx := loop.duplicate()
	var tris := []
	var guard := 0
	while idx.size() > 3 and guard < 10000:
		guard += 1
		var cut := -1
		for i in idx.size():
			var a: Vector3 = pts[idx[(i - 1 + idx.size()) % idx.size()]]
			var b: Vector3 = pts[idx[i]]
			var c: Vector3 = pts[idx[(i + 1) % idx.size()]]
			if (b - a).cross(c - b).dot(n) <= EPS:
				continue   # reflex (or flat) corner: not an ear
			var inside := false
			for j in idx.size():
				if absi(j - i) <= 1 or absi(j - i) == idx.size() - 1:
					continue
				if _in_tri(pts[idx[j]], a, b, c, n):
					inside = true
					break
			if not inside:
				cut = i
				break
		if cut == -1:
			break
		tris.append([idx[(cut - 1 + idx.size()) % idx.size()], idx[cut], idx[(cut + 1) % idx.size()]])
		idx.remove_at(cut)
	for i in range(1, idx.size() - 1):   # what is left (3 verts, or a stuck clip): a fan
		tris.append([idx[0], idx[i], idx[i + 1]])
	return tris


static func _in_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> bool:
	return (b - a).cross(p - a).dot(n) >= -EPS and (c - b).cross(p - b).dot(n) >= -EPS and (a - c).cross(p - c).dot(n) >= -EPS


# ---------------------------------------------------------------- grid fill

## Ctrl+F: each hole touching the verts (even vert count) becomes a quad grid. span = quads along side 0 (0 = auto),
## offset = the loop index of the first corner (-1 = auto)
static func grid_fill(m: KMesh, verts: Array, span := 0, offset := -1) -> Dictionary:
	var hs := holes_touching(m, verts)
	if hs.is_empty():
		return _none("no open border touches the selection (select a vert on the edge of a hole)")
	var nverts := m.verts.duplicate()
	var nf: Array = m.faces.duplicate()
	var f0 := nf.size()
	for l in hs:
		var nl := (l as Array).size()
		if nl % 2 == 1 or nl < 4:
			return _none("grid fill needs a border of an even number of verts (this one has %d): Alt+F fills it as one face" % nl)
		var g := _grid_sides(nverts, l, span, offset)
		if g.is_empty():
			return _none("span %d does not fit a border of %d verts (span 1 to %d)" % [span, nl, nl / 2 - 1])
		_grid(nverts, nf, l, g[0], g[1], g[2])
	_commit(m, nverts, nf, f0)
	var r := _from_faces(m, range(f0, m.faces.size()))
	r["holes"] = hs.size()
	return r


## [a, b, s]: a quads along sides 0 and 2, b along 1 and 3, the first corner at loop index s
static func _grid_sides(pts: PackedVector3Array, l: Array, span: int, offset: int) -> Array:
	var n := l.size()
	var half := n / 2
	if span > 0 and span >= half:
		return []
	var turn := PackedFloat32Array()
	for i in n:
		var d0: Vector3 = pts[l[i]] - pts[l[(i - 1 + n) % n]]
		var d1: Vector3 = pts[l[(i + 1) % n]] - pts[l[i]]
		turn.append(d0.angle_to(d1) if d0.length() > EPS and d1.length() > EPS else 0.0)
	var best := [-1.0, 1, 0]
	for a in (range(span, span + 1) if span > 0 else range(1, half)):
		var b: int = half - a
		for s in (range(offset % n, offset % n + 1) if offset >= 0 else range(n)):
			var sc: float = turn[s] + turn[(s + a) % n] + turn[(s + a + b) % n] + turn[(s + 2 * a + b) % n] - 1e-3 * absi(a - b)
			if sc > best[0] + 1e-6:
				best = [sc, a, s]
	return [best[1], half - best[1], best[2]]


## the Coons-patch grid on loop l: (a + 1) x (b + 1) points, the border ones the loop's own, a x b quads appended
static func _grid(pts: PackedVector3Array, nf: Array, l: Array, a: int, b: int, s: int) -> void:
	var n := l.size()
	var at := func(k: int) -> int: return l[(s + k) % n]
	var gi := {}   # i * (b + 1) + j -> vert
	for i in a + 1:
		gi[i * (b + 1)] = at.call(i)                    # side 0: (i, 0)
		gi[i * (b + 1) + b] = at.call(a + b + (a - i))  # side 2: (i, b), running back
	for j in b + 1:
		gi[a * (b + 1) + j] = at.call(a + j)            # side 1: (a, j)
		gi[j] = at.call((2 * a + b + (b - j)) % n)      # side 3: (0, j), running back
	var p := func(i: int, j: int) -> Vector3: return pts[gi[i * (b + 1) + j]]
	var p00: Vector3 = p.call(0, 0)
	var p10: Vector3 = p.call(a, 0)
	var p01: Vector3 = p.call(0, b)
	var p11: Vector3 = p.call(a, b)
	for i in range(1, a):
		for j in range(1, b):
			var u := float(i) / a
			var v := float(j) / b
			var q: Vector3 = (1.0 - v) * p.call(i, 0) + v * p.call(i, b) + (1.0 - u) * p.call(0, j) + u * p.call(a, j) \
				- ((1.0 - u) * (1.0 - v) * p00 + u * (1.0 - v) * p10 + (1.0 - u) * v * p01 + u * v * p11)
			gi[i * (b + 1) + j] = pts.size()
			pts.append(q)
	for i in a:
		for j in b:
			nf.append(PackedInt32Array([gi[i * (b + 1) + j], gi[(i + 1) * (b + 1) + j], gi[(i + 1) * (b + 1) + j + 1], gi[i * (b + 1) + j + 1]]))


# ---------------------------------------------------------------- selection-driven entry points + the preview keys

## the verts the selection names (any mode)
static func sel_verts(sel: KMeshSelect) -> Array:
	return KMeshDissolve.from_select(sel)["verts"]


## F / Alt+F / Ctrl+F on the selection, the result selected. what: "face" | "holes" | "holes_tri" | "grid"
static func fill(m: KMesh, sel: KMeshSelect, what := "face") -> Dictionary:
	var r: Dictionary
	match what:
		"holes", "holes_tri":
			r = fill_holes(m, sel_verts(sel), what == "holes_tri")
		"grid":
			r = grid_fill(m, sel_verts(sel))
		_:
			r = make_face(m, sel_verts(sel), sel.edges.keys() if sel.mode == KMeshSelect.EDGE else [])
	if String(r.get("error", "")) == "":
		var md := sel.mode
		if (r["faces"] as Array).size() > 0 and what != "face":
			sel.mode = KMeshSelect.FACE   # filled holes: show the new faces
		elif what == "face" and (r["edges"] as Array).size() == 1 and md == KMeshSelect.FACE:
			sel.mode = KMeshSelect.EDGE   # a made edge: show the edge
		KMeshExtrude.select_result(sel, r)
	return r


## the model preview's keys (kmesh_edit_ui.gd): F make face / edge, Alt+F fill holes (Shift+Alt+F triangulated),
## Ctrl+F grid fill. One KMeshUndo step each; true = the key was ours
static func key(ui, k: InputEventKey) -> bool:
	if k.keycode != KEY_F or (k.ctrl_pressed and k.alt_pressed):
		return false
	var what := "grid" if k.ctrl_pressed else (("holes_tri" if k.shift_pressed else "holes") if k.alt_pressed else "face")
	var label: String = {"face": "Make face", "holes": "Fill holes", "holes_tri": "Fill holes (triangles)", "grid": "Grid fill"}[what]
	var nf0: int = ui.mesh.face_count()
	ui.undo.begin(ui.mesh)
	var r := fill(ui.mesh, ui.sel, what)
	ui.undo.commit(label)
	ui.view.mark_dirty()
	if String(r.get("error", "")) != "":
		ui.m._say("Model: %s: %s" % [label.to_lower(), r["error"]])
	elif what == "face" and (r["faces"] as Array).size() == 2 and (r["edges"] as Array).size() == 1:
		ui.m._say("Model: joined the 2 verts with an edge (their face split in two). Ctrl+Z takes it back")
	else:
		ui.m._say("Model: %s: %d new faces (%d faces now)%s. Ctrl+Z takes it back" % [label.to_lower(), ui.mesh.face_count() - nf0, ui.mesh.face_count(), "" if what == "face" else ", %d holes" % int(r.get("holes", 0))])
	return true


# ---------------------------------------------------------------- shared

static func _newell(pts: PackedVector3Array, loop: Array) -> Vector3:
	var n := Vector3.ZERO
	for i in loop.size():
		var p: Vector3 = pts[loop[i]]
		var q: Vector3 = pts[loop[(i + 1) % loop.size()]]
		n += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
	return n


## faces from index f0 on are new (no source); verts past the old count are new
static func _commit(m: KMesh, nverts: PackedVector3Array, nfaces: Array, f0: int) -> void:
	var src_v := PackedInt32Array()
	for v in nverts.size():
		src_v.append(v if v < m.verts.size() else -1)
	var src_f := PackedInt32Array()
	for i in nfaces.size():
		src_f.append(i if i < f0 else -1)
	KMeshExtrude._commit(m, nverts, nfaces, src_v, src_f)


static func _none(msg: String) -> Dictionary:
	return {"verts": [], "edges": [], "faces": [], "error": msg}


static func _from_faces(m: KMesh, fs: Array) -> Dictionary:
	return KMeshExtrude._from_faces(m, Array(fs))
