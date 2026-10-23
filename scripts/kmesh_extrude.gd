class_name KMeshExtrude
extends RefCounted
## EXTRUDE, INSET, BRIDGE on a KMesh (ROADMAP_400 B02, B03 inset + bridge). Static ops: each edits the mesh in place
## (one from_arrays at the end, so a KMeshUndo begin / commit around it is one "topo" step) and returns the new selection
## {"verts": [int], "edges": [Vector2i(lo, hi)], "faces": [int]} (+ "error": "" or a message with the next step).
## Faces, region: the selected faces that touch by an edge form an island; each island is lifted as one piece. Its
##   boundary vertices are copied (the copies go up with the faces, the originals stay with the rest of the mesh) and a
##   wall quad [a, b, b', a'] closes every boundary edge a->b, so two adjacent faces share their walls: no wall inside.
##   Vertices inside the island (no unselected face, no boundary edge) just move. The island goes along its average
##   (area-weighted) normal, so a flat region rises exactly `dist`; a closed island (average ~ 0) uses vertex normals.
## Faces, individual: every face is its own island (its own copies, its own four walls, its own normal).
## Inset: the same split, but the copies move INTO the face plane: at a corner with edge directions d_in, d_out and
##   normal n, the copy goes along the bisector of n x d_in and n x d_out by t / cos(half the turn), so each new inner
##   edge is exactly t from its old edge (a straight edge, a convex or a concave corner alike). Rim quads as walls.
## Edges: each selected edge gets a quad to its copy. On an open border the quad continues the surface outward (in the
##   face plane, away from the face), elsewhere it goes along the vertex normal; touching edges share copies.
## Verts: faces whose corners are all selected extrude as a region; else the edges between selected verts extrude.
##   A lone vertex would make a wire edge, which a KMesh (faces only) cannot hold: those are counted in "skipped".
## Bridge: the selected edges must make two closed loops of the same size. A face that exactly fills a loop (a cap)
##   is deleted first, then N quads join the loops. A loop that is an open border fixes its direction (the quads
##   continue the surface, so the result stays manifold); the rotation (which vertex pairs with which) is the one with
##   the least squared distance between the loops, each taken about its own centre (no twist).
## Attributes (A09) follow their element: a copied vertex copies its source's values, a wall / rim / bridge face copies
## the face it grew from, a corner copies the source face's corner at the same (source) vertex, a new edge copies the
## edge between its source vertices (a vertical wall edge has none: default). Custom split normals are dropped (their
## corners changed). Tests: tests/extrude_test.gd. Behaviour learned from Blender's manual; no Blender code.

const NORMAL_EPS := 1e-6
const MIN_COS := 0.1   # an inset corner sharper than ~170 degrees of turn is clamped (the copy would shoot away)


# ---------------------------------------------------------------- faces

## islands: face -> group id. Region: faces joined by an edge share a group; individual: each face its own.
static func _groups(m: KMesh, fs: Array, individual: bool) -> Dictionary:
	var g := {}
	if individual:
		for i in fs.size():
			g[int(fs[i])] = i
		return g
	var sel := {}
	for f in fs:
		sel[int(f)] = true
	var hf := m.he_face
	var n := 0
	for f0 in fs:
		if g.has(int(f0)):
			continue
		var stack: Array = [int(f0)]
		g[int(f0)] = n
		while not stack.is_empty():
			var fi: int = stack.pop_back()
			var f: PackedInt32Array = m.faces[fi]
			for i in f.size():
				var t := m.find_half_edge(f[(i + 1) % f.size()], f[i])
				if t == -1:
					continue
				var nf := hf[t]
				if sel.has(nf) and not g.has(nf):
					g[nf] = n
					stack.append(nf)
		n += 1
	return g


## the split shared by extrude and inset: new vert / face arrays with the selected faces moved onto copies and the
## walls added. "dup": key g * V + v -> copy, "inner": key -> true for island-inside verts that stay themselves,
## "walls": [[a, b, face, g]] (a->b in the old face), "wall0": index of the first wall face.
static func _split(m: KMesh, fs: Array, individual: bool) -> Dictionary:
	var nv := m.verts.size()
	var grp := _groups(m, fs, individual)
	var hf := m.he_face
	var outside := {}
	for fi in m.faces.size():
		if not grp.has(fi):
			for v in (m.faces[fi] as PackedInt32Array):
				outside[v] = true
	var walls: Array = []
	var onb := {}
	for fi in grp:
		var f: PackedInt32Array = m.faces[fi]
		var g: int = grp[fi]
		for i in f.size():
			var a := f[i]
			var b := f[(i + 1) % f.size()]
			var t := m.find_half_edge(b, a)
			if t == -1 or int(grp.get(hf[t], -1)) != g:
				walls.append([a, b, fi, g])
				onb[g * nv + a] = true
				onb[g * nv + b] = true
	var nverts := m.verts.duplicate()
	var src_v := PackedInt32Array()
	for v in nv:
		src_v.append(v)
	var nfaces: Array = m.faces.duplicate()
	var src_f := PackedInt32Array()
	for fi in m.faces.size():
		src_f.append(fi)
	var dup := {}
	var inner := {}
	for fi in grp:
		var g: int = grp[fi]
		var f: PackedInt32Array = (m.faces[fi] as PackedInt32Array).duplicate()
		for i in f.size():
			var v := f[i]
			var key := g * nv + v
			if onb.has(key) or outside.has(v) or individual:
				if not dup.has(key):
					dup[key] = nverts.size()
					nverts.append(m.verts[v])
					src_v.append(v)
				f[i] = dup[key]
			else:
				inner[key] = true
		nfaces[fi] = f
	var wall0 := nfaces.size()
	for w in walls:
		var g: int = w[3]
		nfaces.append(PackedInt32Array([w[0], w[1], dup[g * nv + int(w[1])], dup[g * nv + int(w[0])]]))
		src_f.append(w[2])
	return {"grp": grp, "verts": nverts, "faces": nfaces, "src_v": src_v, "src_f": src_f, "dup": dup, "inner": inner,
		"walls": walls, "wall0": wall0, "nv": nv}


## the area-weighted normal of each group (Vector3.ZERO when it cancels out)
static func _group_normals(m: KMesh, grp: Dictionary) -> Dictionary:
	var gn := {}
	for fi in grp:
		gn[grp[fi]] = (gn.get(grp[fi], Vector3.ZERO) as Vector3) + m._newell(fi)
	for g in gn:
		var n: Vector3 = gn[g]
		gn[g] = n.normalized() if n.length() > NORMAL_EPS else Vector3.ZERO
	return gn


## normal of vertex v from the faces of group g around it
static func _vnormal(m: KMesh, grp: Dictionary, g: int, v: int) -> Vector3:
	var n := Vector3.ZERO
	for fi in m.vert_faces(v):
		if int(grp.get(fi, -1)) == g:
			n += m._newell(fi)
	return n.normalized() if n.length() > NORMAL_EPS else m.vert_normals[v]


## Extrude faces `dist` along their normal (region: islands as one piece; individual: face by face).
## Returns the lifted faces (same indices) as the new selection.
static func extrude_faces(m: KMesh, fs: Array, dist: float, individual := false) -> Dictionary:
	if fs.is_empty():
		return _none("pick faces first (3 = face mode, then click one)")
	var s := _split(m, fs, individual)
	var nv: int = s["nv"]
	var gn := _group_normals(m, s["grp"])
	var nverts: PackedVector3Array = s["verts"]
	var moved := {}
	for key in s["dup"]:
		moved[key] = s["dup"][key]
	for key in s["inner"]:
		moved[key] = key % nv
	for key in moved:
		var g: int = key / nv
		var n: Vector3 = gn[g]
		if n == Vector3.ZERO:
			n = _vnormal(m, s["grp"], g, key % nv)
		nverts[moved[key]] = m.verts[key % nv] + n * dist
	_commit(m, nverts, s["faces"], s["src_v"], s["src_f"])
	return _from_faces(m, fs)


## Inset faces by `t` (metres, measured edge to edge in the face plane). Returns the inner faces (same indices).
static func inset_faces(m: KMesh, fs: Array, t: float, individual := false) -> Dictionary:
	if fs.is_empty():
		return _none("pick faces first (3 = face mode, then click one)")
	var s := _split(m, fs, individual)
	var nv: int = s["nv"]
	var nverts: PackedVector3Array = s["verts"]
	var into := {}   # key -> [the wall ending at v, the wall leaving v]
	for w in s["walls"]:
		var g: int = w[3]
		var kb: int = g * nv + int(w[1])
		var ka: int = g * nv + int(w[0])
		if not into.has(kb):
			into[kb] = [null, null]
		if not into.has(ka):
			into[ka] = [null, null]
		if into[kb][0] == null:
			into[kb][0] = w
		if into[ka][1] == null:
			into[ka][1] = w
	for key in into:
		var pair: Array = into[key]
		if pair[0] == null or pair[1] == null:
			continue
		var v: int = key % nv
		var n := _vnormal(m, s["grp"], key / nv, v)
		var p := m.verts[v]
		var d_in := (p - m.verts[int(pair[0][0])]).normalized()
		var d_out := (m.verts[int(pair[1][1])] - p).normalized()
		var m1 := n.cross(d_in).normalized()
		var m2 := n.cross(d_out).normalized()
		var bis := m1 + m2
		bis = bis.normalized() if bis.length() > NORMAL_EPS else m1
		nverts[s["dup"][key]] = p + bis * (t / maxf(bis.dot(m1), MIN_COS))
	_commit(m, nverts, s["faces"], s["src_v"], s["src_f"])
	return _from_faces(m, fs)


# ---------------------------------------------------------------- edges and verts

## Extrude edges by `dist` (or by `offset` when it is not zero). Returns the new (copied) edges and their verts.
static func extrude_edges(m: KMesh, es: Array, dist: float, individual := false, offset := Vector3.ZERO) -> Dictionary:
	if es.is_empty():
		return _none("pick edges first (2 = edge mode, then click one)")
	var nv := m.verts.size()
	var hf := m.he_face
	var nverts := m.verts.duplicate()
	var src_v := PackedInt32Array()
	for v in nv:
		src_v.append(v)
	var nfaces: Array = m.faces.duplicate()
	var src_f := PackedInt32Array()
	for fi in m.faces.size():
		src_f.append(fi)
	var dup := {}
	var dirs := {}
	var quads: Array = []   # [p, q, face] = the quad [p, q, q', p']
	for i in es.size():
		var e: Vector2i = es[i]
		var g := i if individual else 0
		var h := m.find_half_edge(e.x, e.y)
		var r := m.find_half_edge(e.y, e.x)
		var p := e.x
		var q := e.y
		var src := -1
		if h != -1 and r == -1:
			p = e.y   # the face runs x->y: the quad takes y->x
			q = e.x
			src = hf[h]
		elif r != -1:
			src = hf[r]
			if h != -1:
				src = hf[h]
				p = e.y
				q = e.x
		for v in [p, q]:
			var key: int = g * nv + v
			if not dup.has(key):
				dup[key] = nverts.size()
				nverts.append(m.verts[v])
				src_v.append(v)
				dirs[key] = Vector3.ZERO
		if src != -1 and (h == -1) != (r == -1):
			var out := (m.verts[p] - m.verts[q]).normalized().cross(m.face_normals[src])   # q->p is the face's edge: d x n points away from it
			dirs[g * nv + p] += out
			dirs[g * nv + q] += out
		quads.append([p, q, src, g])
	for key in dup:
		var d: Vector3 = offset
		if d == Vector3.ZERO:
			var u: Vector3 = dirs[key]
			u = u.normalized() if u.length() > NORMAL_EPS else m.vert_normals[key % nv]
			d = u * dist
		nverts[dup[key]] = m.verts[key % nv] + d
	var new_faces := []
	var new_edges := []
	for qd in quads:
		var g: int = qd[3]
		var a2: int = dup[g * nv + int(qd[0])]
		var b2: int = dup[g * nv + int(qd[1])]
		new_faces.append(nfaces.size())
		nfaces.append(PackedInt32Array([qd[0], qd[1], b2, a2]))
		src_f.append(qd[2])
		new_edges.append(KMeshSelect.ekey(a2, b2))
	_commit(m, nverts, nfaces, src_v, src_f)
	var vs := {}
	for e in new_edges:
		vs[e.x] = true
		vs[e.y] = true
	return {"verts": vs.keys(), "edges": new_edges, "faces": [], "error": ""}


## Extrude vertices: whole faces as a region, else the edges between them (see the class comment).
static func extrude_verts(m: KMesh, vs: Array, dist: float) -> Dictionary:
	var set := {}
	for v in vs:
		set[int(v)] = true
	var fs := []
	for fi in m.faces.size():
		var all := true
		for v in (m.faces[fi] as PackedInt32Array):
			if not set.has(v):
				all = false
				break
		if all:
			fs.append(fi)
	if not fs.is_empty():
		var r := extrude_faces(m, fs, dist)
		return r
	var es := []
	var used := {}
	for e in m.edges():
		if set.has(e.x) and set.has(e.y):
			es.append(e)
			used[e.x] = true
			used[e.y] = true
	if es.is_empty():
		var r0 := _none("select two touching vertices (or a face): a lone vertex would make a wire edge, and a mesh here is faces only")
		r0["skipped"] = vs.size()
		return r0
	var r2 := extrude_edges(m, es, dist)
	r2["skipped"] = vs.size() - used.size()
	return r2


# ---------------------------------------------------------------- bridge

## Join two closed edge loops (the selected edges) with quads. Returns the new faces.
static func bridge_loops(m: KMesh, es: Array) -> Dictionary:
	var adj := {}
	for e in es:
		for pr in [[e.x, e.y], [e.y, e.x]]:
			if not adj.has(pr[0]):
				adj[pr[0]] = []
			if not (pr[1] in adj[pr[0]]):
				adj[pr[0]].append(pr[1])
	var loops: Array = []
	var seen := {}
	for v0 in adj:
		if seen.has(v0):
			continue
		var lp: Array = [v0]
		seen[v0] = true
		var prev: int = -1
		var cur: int = v0
		while true:
			if (adj[cur] as Array).size() != 2:
				return _none("the edges must make closed loops (every vertex on two of them): select two whole edge loops")
			var nxt: int = adj[cur][0] if int(adj[cur][0]) != prev else adj[cur][1]
			if nxt == v0:
				break
			if seen.has(nxt):
				return _none("the edges cross themselves: select two separate closed loops")
			seen[nxt] = true
			lp.append(nxt)
			prev = cur
			cur = nxt
		loops.append(lp)
	if loops.size() != 2:
		return _none("bridge needs exactly two closed loops (got %d): select two edge loops" % loops.size())
	var la: Array = loops[0]
	var lb: Array = loops[1]
	if la.size() != lb.size():
		return _none("the loops have different sizes (%d and %d vertices): bridge joins equal loops only" % [la.size(), lb.size()])
	# a face that fills a loop exactly (a cap) goes first
	var nfaces: Array = []
	var src_f := PackedInt32Array()
	var caps := {}
	for lp in loops:
		var ls := {}
		for v in lp:
			ls[v] = true
		for fi in m.faces.size():
			var f: PackedInt32Array = m.faces[fi]
			if f.size() == lp.size() and f.size() == ls.size():
				var all := true
				for v in f:
					if not ls.has(v):
						all = false
						break
				if all:
					caps[fi] = lp
	for fi in m.faces.size():
		if not caps.has(fi):
			nfaces.append(m.faces[fi])
			src_f.append(fi)
	var dirs := {}   # directed edges still in a face: a * V + b -> the face (old index)
	var nv := m.verts.size()
	for i in nfaces.size():
		var f: PackedInt32Array = nfaces[i]
		for k in f.size():
			dirs[f[k] * nv + f[(k + 1) % f.size()]] = src_f[i]
	var fixed := []   # per loop: 1 = runs with the existing border, 0 = free (no face on it)
	for li in 2:
		var lp: Array = loops[li]
		var fw := 0
		var bw := 0
		for k in lp.size():
			var a: int = lp[k]
			var b: int = lp[(k + 1) % lp.size()]
			fw += 1 if dirs.has(a * nv + b) else 0
			bw += 1 if dirs.has(b * nv + a) else 0
		if fw > 0 and bw > 0:
			return _none("a loop has faces on both sides: bridge joins open borders (or caps it deletes). Delete the faces between first")
		if bw > 0:
			lp.reverse()
		fixed.append(1 if fw + bw > 0 else 0)
	if fixed[0] == 0 and fixed[1] == 1:   # the fixed loop leads, the free one turns to meet it
		loops.reverse()
		fixed.reverse()
		la = loops[0]
		lb = loops[1]
	# pairing a_i <-> b_(s - i): try every s (and the other direction of a free loop b)
	var n := la.size()
	var ca := Vector3.ZERO
	var cb := Vector3.ZERO
	for k in n:
		ca += m.verts[la[k]]
		cb += m.verts[lb[k]]
	ca /= float(n)
	cb /= float(n)
	var best := INF
	var bs := 0
	var brev := false
	for rev in ([false, true] if fixed[1] == 0 else [false]):
		var b: Array = lb.duplicate()
		if rev:
			b.reverse()
		for s in n:
			var cost := 0.0
			for i in n:
				cost += ((m.verts[la[i]] - ca) - (m.verts[b[posmod(s - i, n)]] - cb)).length_squared()
			if cost < best - 1e-12:
				best = cost
				bs = s
				brev = rev
	if brev:
		lb.reverse()
	var quads: Array = []
	for i in n:
		quads.append(PackedInt32Array([la[(i + 1) % n], la[i], lb[posmod(bs - i, n)], lb[posmod(bs - i - 1, n)]]))
	if fixed[0] == 0 and fixed[1] == 0:
		# nothing fixes the direction: make the tube face away from its axis
		var axis := (cb - ca).normalized()
		var score := 0.0
		for q in quads:
			var c := Vector3.ZERO
			for v in q:
				c += m.verts[v]
			c /= 4.0
			var rad := (c - ca) - axis * (c - ca).dot(axis)
			score += (m.verts[q[1]] - m.verts[q[0]]).cross(m.verts[q[2]] - m.verts[q[1]]).dot(rad)
		if score < 0.0:
			for q in quads:
				q.reverse()
	var out := []
	for i in n:
		var a: int = la[i]
		var b: int = la[(i + 1) % n]
		var sf: int = int(dirs.get(b * nv + a, dirs.get(a * nv + b, -1)))
		if sf == -1:
			var cf: Array = caps.keys()
			sf = cf[0] if not cf.is_empty() else -1
		out.append(nfaces.size())
		nfaces.append(quads[i])
		src_f.append(sf)
	var src_v := PackedInt32Array()
	for v in nv:
		src_v.append(v)
	_commit(m, m.verts.duplicate(), nfaces, src_v, src_f)
	return _from_faces(m, out)


# ---------------------------------------------------------------- selection-driven entry points

## Extrude what `sel` holds in its mode, then select the result. Returns the op's dictionary.
static func extrude(m: KMesh, sel: KMeshSelect, dist: float, individual := false) -> Dictionary:
	var r: Dictionary
	match sel.mode:
		KMeshSelect.FACE:
			r = extrude_faces(m, sel.faces.keys(), dist, individual)
		KMeshSelect.EDGE:
			r = extrude_edges(m, sel.edges.keys(), dist, individual)
		_:
			r = extrude_verts(m, sel.verts.keys(), dist)
	select_result(sel, r)
	return r


## Inset the selected faces (face mode; in vertex / edge mode the faces whose corners are all selected).
static func inset(m: KMesh, sel: KMeshSelect, t: float, individual := false) -> Dictionary:
	var md := sel.mode
	sel.set_mode(KMeshSelect.FACE)
	var r := inset_faces(m, sel.faces.keys(), t, individual)
	sel.set_mode(md)
	select_result(sel, r)
	return r


static func bridge(m: KMesh, sel: KMeshSelect) -> Dictionary:
	var md := sel.mode
	sel.set_mode(KMeshSelect.EDGE)
	var r := bridge_loops(m, sel.edges.keys())
	sel.set_mode(md)
	select_result(sel, r)
	return r


## put the op's result in `sel` (its own mode); an op that failed leaves the selection as it was
static func select_result(sel: KMeshSelect, r: Dictionary) -> void:
	if String(r.get("error", "")) != "":
		return
	var md := sel.mode
	sel.clear()
	if md == KMeshSelect.FACE and (r["faces"] as Array).is_empty():
		md = KMeshSelect.EDGE   # edges extruded from face mode have no face to show: show the new edges
	match md:
		KMeshSelect.FACE:
			for f in r["faces"]:
				sel.faces[f] = true
		KMeshSelect.EDGE:
			for e in r["edges"]:
				sel.edges[e] = true
		_:
			for v in r["verts"]:
				sel.verts[v] = true
	sel.mode = md


# ---------------------------------------------------------------- shared

static func _none(msg: String) -> Dictionary:
	return {"verts": [], "edges": [], "faces": [], "error": msg}


static func _from_faces(m: KMesh, fs: Array) -> Dictionary:
	var vs := {}
	var es := {}
	for fi in fs:
		var f: PackedInt32Array = m.faces[fi]
		for i in f.size():
			vs[f[i]] = true
			es[KMeshSelect.ekey(f[i], f[(i + 1) % f.size()])] = true
	return {"verts": vs.keys(), "edges": es.keys(), "faces": fs.duplicate(), "error": ""}


## write the new arrays into m (one rebuild) and carry the attributes over (see the class comment)
static func _commit(m: KMesh, nverts: PackedVector3Array, nfaces: Array, src_v: PackedInt32Array, src_f: PackedInt32Array) -> void:
	m.custom_normals = []
	if m.attrs.is_empty():
		m.from_arrays(nverts, nfaces)
		return
	var he0 := m.face_he0
	var src_c := PackedInt32Array()
	for i in nfaces.size():
		var sf: int = src_f[i]
		var of: PackedInt32Array = m.faces[sf] if sf >= 0 else PackedInt32Array()
		for v in (nfaces[i] as PackedInt32Array):
			var c := -1
			for j in of.size():
				if of[j] == src_v[v]:
					c = he0[sf] + j
					break
			src_c.append(c)
	var old_e := {}
	var k := 0
	for e in m.edges():
		old_e[e] = k
		k += 1
	var edge_data := {}
	for nm in m.attrs:
		if m.attrs[nm]["domain"] == KMesh.AD_EDGE:
			edge_data[nm] = m.attrs[nm]["data"].duplicate()
	m.attr_remap(src_v, src_f, src_c, null)
	m.from_arrays(nverts, nfaces)
	if edge_data.is_empty():
		return
	var src_e := PackedInt32Array()
	for e in m.edges():
		var a := src_v[e.x]
		var b := src_v[e.y]
		src_e.append(int(old_e.get(KMeshSelect.ekey(a, b), -1)) if a != b else -1)
	for nm in edge_data:
		m.attrs[nm]["data"] = edge_data[nm]
	m.attr_remap(null, null, null, src_e)
