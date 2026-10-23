class_name KMeshCut
extends RefCounted
## LOOP CUT + SLIDE, KNIFE, EDGE SPLIT on a KMesh (ROADMAP_400 B04). Static ops: each edits the mesh in place with ONE
## from_arrays at the end (KMeshExtrude._commit, so the attributes follow and a KMeshUndo begin / commit around it is one
## "topo" step) and returns {"verts": [int], "edges": [Vector2i(lo, hi)], "faces": [int], "error": ""} (+ op extras).
## Loop cut: ring(a, b) walks the edge ring through edge a-b across quads, both ways from it, and stops where the next
##   face is a triangle or an n-gon (or a border), the way Blender does: the edge it stops on is still cut, so the face
##   past it gets the new vertex in its side (a triangle becomes a 4-gon) and nothing is left hanging. A ring that comes
##   back to its first edge is closed. Every ring edge p->q (p sides line up: p_i and p_i+1 share a quad side) gets N new
##   verts at t_k = (k + slide) / (N + 1), k = 1..N, along p->q, so slide 0 is the even split, slide > 0 moves the whole
##   new loop toward the q side (toward b of the edge you hovered), slide < 0 toward a. |slide| is held under SLIDE_MAX
##   (at 1 the new verts would sit on the old ones). Every ring quad becomes N + 1 quads in its own winding.
## Knife: a list of surface points {"face", "point"} (mesh-local). A point within `snap` of a vertex / an edge of its
##   face IS that vertex / a point on that edge. Between two points the cut follows the plane through both that holds
##   the faces' average normal, face to face: it leaves each face where that plane crosses its boundary ahead of the
##   point (the crossing nearest along the segment), on an edge (a new vertex there, put into both faces of the edge)
##   or through a vertex. Every face the cut crosses from boundary to boundary is split in two along it (points inside a
##   face on the way become the cut's own verts). A KMesh is faces only, so a cut that starts or ends INSIDE a face
##   (no edge to hang it on) is dropped up to its first / after its last boundary point.
## Edge split: around each vertex of a selected edge the faces are grouped by the unselected edges that join them; the
##   first group keeps the vertex, each other group gets its own copy (at the same place: validate counts those as
##   doubled until something moves them, as in Blender). A border edge has nothing to split from.
## Attributes: a new loop / knife vertex copies the nearer end of its edge, a split vertex its source; each new face the
## face it was cut from. Tests: tests/kmesh_cut_test.gd. Behaviour learned from Blender's manual; no Blender code.

const SLIDE_MAX := 0.99
const MAX_CUTS := 64
const SNAP := 1e-4          # m: a knife point this close to a vertex / an edge is on it
const PLANE_EPS := 1e-7     # m: a vertex this close to the knife's plane is on it
const MAX_STEPS := 100000   # faces one knife segment may cross before it gives up


# ---------------------------------------------------------------- loop cut

## the face on the left of half-edge a->b, or -1
static func _face_of(m: KMesh, a: int, b: int) -> int:
	var h := m.find_half_edge(a, b)
	return m.he_face[h] if h != -1 else -1


## the face across edge a-b from face fi, or -1
static func _other_face(m: KMesh, a: int, b: int, fi: int) -> int:
	for f in [_face_of(m, a, b), _face_of(m, b, a)]:
		if f != -1 and f != fi:
			return f
	return -1


static func _walk(m: KMesh, p: int, q: int, fi: int, start: Vector2i, seen: Dictionary) -> Dictionary:
	var es := []
	var fs := []
	var closed := false
	while fi >= 0 and not seen.has(fi):
		var f: PackedInt32Array = m.faces[fi]
		if f.size() != 4:
			break
		var i := f.find(p)
		var j := f.find(q)
		var pn := f[(i + 1) % 4] if f[(i + 1) % 4] != q else f[(i + 3) % 4]
		var qn := f[(j + 1) % 4] if f[(j + 1) % 4] != p else f[(j + 3) % 4]
		seen[fi] = true
		fs.append(fi)
		if KMeshSelect.ekey(pn, qn) == start:
			closed = true
			break
		es.append(Vector2i(pn, qn))
		fi = _other_face(m, pn, qn, fi)
		p = pn
		q = qn
	return {"edges": es, "faces": fs, "closed": closed}


## The edge ring through edge a-b: {"edges": [Vector2i(p, q)] in ring order, the first p->q sides lined up, edge (a, b)
## among them as given; "faces": the quads between edges[i] and edges[i + 1] (closed: the last one joins the last edge
## to the first); "closed"}. No quad on either side: empty.
static func ring(m: KMesh, a: int, b: int) -> Dictionary:
	var start := KMeshSelect.ekey(a, b)
	var seen := {}
	var fwd := _walk(m, a, b, _face_of(m, a, b), start, seen)
	if fwd["closed"]:
		return {"edges": [Vector2i(a, b)] + fwd["edges"], "faces": fwd["faces"], "closed": true}
	var back := _walk(m, a, b, _face_of(m, b, a), start, seen)
	var es: Array = back["edges"].duplicate()
	es.reverse()
	var fs: Array = back["faces"].duplicate()
	fs.reverse()
	es.append(Vector2i(a, b))
	es.append_array(fwd["edges"])
	fs.append_array(fwd["faces"])
	if fs.is_empty():
		return {"edges": [], "faces": [], "closed": false}
	return {"edges": es, "faces": fs, "closed": false}


## where the N new verts go along a ring edge (fractions p -> q)
static func fractions(cuts: int, slide: float) -> PackedFloat32Array:
	var n := clampi(cuts, 1, MAX_CUTS)
	var s := clampf(slide, -SLIDE_MAX, SLIDE_MAX)
	var out := PackedFloat32Array()
	for k in range(1, n + 1):
		out.append((float(k) + s) / float(n + 1))
	return out


## what a loop cut would make, without making it: one polyline (mesh-local points, one per ring edge) per new loop,
## and whether it closes. The model preview draws this while you hover.
static func loop_preview(m: KMesh, a: int, b: int, cuts := 1, slide := 0.0) -> Dictionary:
	var r := ring(m, a, b)
	var lines := []
	for t in fractions(cuts, slide):
		var pl := PackedVector3Array()
		for e in r["edges"]:
			pl.append(m.verts[e.x].lerp(m.verts[e.y], t))
		lines.append(pl)
	return {"lines": lines, "closed": r["closed"], "ring": r}


## Loop cut through edge a-b: `cuts` new loops, slid by `slide` (-1..1, see the class comment). Returns the new verts,
## the new loop edges, the faces of the cut ring, "ring": how many ring edges were cut, "closed".
static func loop_cut(m: KMesh, a: int, b: int, cuts := 1, slide := 0.0) -> Dictionary:
	if m.find_half_edge(a, b) == -1 and m.find_half_edge(b, a) == -1:
		return _none("hover an edge of the mesh first (Ctrl+R, then move over an edge)")
	var r := ring(m, a, b)
	if (r["faces"] as Array).is_empty():
		return _none("no quad on either side of this edge: a loop cut runs across quads (triangles and n-gons stop it)")
	var ts := fractions(cuts, slide)
	var n := ts.size()
	var es: Array = r["edges"]
	var nverts := m.verts.duplicate()
	var src_v := PackedInt32Array()
	for v in m.verts.size():
		src_v.append(v)
	var line := []      # per ring edge: [p, new..., q]
	var where := {}     # ekey -> ring edge index
	for i in es.size():
		var e: Vector2i = es[i]
		var l := [e.x]
		for t in ts:
			l.append(nverts.size())
			nverts.append(m.verts[e.x].lerp(m.verts[e.y], t))
			src_v.append(e.x if t < 0.5 else e.y)
		l.append(e.y)
		line.append(l)
		where[KMeshSelect.ekey(e.x, e.y)] = i
	var nfaces: Array = m.faces.duplicate()
	var src_f := PackedInt32Array()
	for fi in m.faces.size():
		src_f.append(fi)
	var ringf := {}
	var out_f := []
	var out_e := []
	var fs: Array = r["faces"]
	for k in fs.size():
		var fi: int = fs[k]
		ringf[fi] = true
		var li: Array = line[k]
		var lj: Array = line[(k + 1) % es.size()]
		var f: PackedInt32Array = m.faces[fi]
		var fwd: bool = f[(f.find(li[0]) + 1) % 4] == li[n + 1]
		for s in n + 1:
			var q := PackedInt32Array([li[s], li[s + 1], lj[s + 1], lj[s]])
			if not fwd:
				q.reverse()
			if s == 0:
				nfaces[fi] = q
				out_f.append(fi)
			else:
				out_f.append(nfaces.size())
				nfaces.append(q)
				src_f.append(fi)
		for s in range(1, n + 1):
			out_e.append(KMeshSelect.ekey(li[s], lj[s]))
	# the faces past the ring's ends (a triangle, an n-gon) get the new verts in their side
	for fi in m.faces.size():
		if ringf.has(fi):
			continue
		var f: PackedInt32Array = m.faces[fi]
		var g := PackedInt32Array()
		var hit := false
		for i in f.size():
			var x := f[i]
			var y := f[(i + 1) % f.size()]
			g.append(x)
			var ri: int = where.get(KMeshSelect.ekey(x, y), -1)
			if ri < 0:
				continue
			hit = true
			var l: Array = line[ri]
			if x == l[0]:
				for s in range(1, n + 1):
					g.append(l[s])
			else:
				for s in range(n, 0, -1):
					g.append(l[s])
		if hit:
			nfaces[fi] = g
	var new_v := []
	for i in range(m.verts.size(), nverts.size()):
		new_v.append(i)
	KMeshExtrude._commit(m, nverts, nfaces, src_v, src_f)
	return {"verts": new_v, "edges": out_e, "faces": out_f, "error": "", "ring": es.size(), "closed": r["closed"]}


# ---------------------------------------------------------------- edge split

## Split the edges `es` (Vector2i): the faces either side get their own verts. "verts": the copies made.
static func edge_split(m: KMesh, es: Array) -> Dictionary:
	var cut := {}
	for e in es:
		var k := KMeshSelect.ekey(e.x, e.y)
		if m.find_half_edge(k.x, k.y) != -1 and m.find_half_edge(k.y, k.x) != -1:
			cut[k] = true
	if cut.is_empty():
		return _none("select edges with a face on both sides first (2 = edge mode, then click one): a border has nothing to split from")
	var touched := {}
	for k in cut:
		touched[k.x] = true
		touched[k.y] = true
	var nverts := m.verts.duplicate()
	var src_v := PackedInt32Array()
	for v in m.verts.size():
		src_v.append(v)
	var nfaces: Array = m.faces.duplicate()
	var src_f := PackedInt32Array()
	for fi in m.faces.size():
		src_f.append(fi)
	var made := []
	var vs := touched.keys()
	vs.sort()
	for v in vs:
		var fan := m.vert_faces(v)
		var grp := {}
		for fi in fan:
			grp[fi] = fi
		var find := func(x: int) -> int:
			while grp[x] != x:
				x = grp[x]
			return x
		for fi in fan:
			var f: PackedInt32Array = m.faces[fi]
			var i := f.find(v)
			var nx := f[(i + 1) % f.size()]
			if cut.has(KMeshSelect.ekey(v, nx)):
				continue
			var g := _face_of(m, nx, v)
			if g != -1 and grp.has(g):
				var ra: int = find.call(fi)
				var rb: int = find.call(g)
				if ra != rb:
					grp[maxi(ra, rb)] = mini(ra, rb)
		var roots := {}
		for fi in fan:
			roots[find.call(fi)] = true
		var order := roots.keys()
		order.sort()
		for gi in range(1, order.size()):
			var nvid := nverts.size()
			nverts.append(m.verts[v])
			src_v.append(v)
			made.append(nvid)
			for fi in fan:
				if find.call(fi) == order[gi]:
					var f: PackedInt32Array = (nfaces[fi] as PackedInt32Array).duplicate()
					f[f.find(v)] = nvid
					nfaces[fi] = f
	KMeshExtrude._commit(m, nverts, nfaces, src_v, src_f)
	var out_e := []
	for fi in m.faces.size():
		var f: PackedInt32Array = m.faces[fi]
		for i in f.size():
			var a := src_v[f[i]]
			var b := src_v[f[(i + 1) % f.size()]]
			if cut.has(KMeshSelect.ekey(a, b)):
				out_e.append(KMeshSelect.ekey(f[i], f[(i + 1) % f.size()]))
	return {"verts": made, "edges": out_e, "faces": [], "error": ""}


# ---------------------------------------------------------------- knife

## a knife node: {"k": "v", "v"} a vertex, {"k": "e", "a", "b" (a < b), "t" (a -> b)} a point on an edge, {"k": "f",
## "f"} a point inside a face; each with "pos" (local) and "id" (unique per node)
static var _uid := 0


static func _node(k: String, pos: Vector3, d := {}) -> Dictionary:
	_uid += 1
	var n := {"k": k, "pos": pos, "id": _uid}
	n.merge(d)
	return n


static func _snap(m: KMesh, fi: int, p: Vector3, snap: float) -> Dictionary:
	var f: PackedInt32Array = m.faces[fi]
	for v in f:
		if m.verts[v].distance_to(p) <= snap:
			return _node("v", m.verts[v], {"v": v})
	for i in f.size():
		var a := f[i]
		var b := f[(i + 1) % f.size()]
		var pa := m.verts[a]
		var ab := m.verts[b] - pa
		var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-30), 0.0, 1.0)
		if pa.lerp(m.verts[b], t).distance_to(p) <= snap:
			return _edge_node(m, a, b, t)
	return _node("f", p, {"f": fi})


static func _edge_node(m: KMesh, a: int, b: int, t: float) -> Dictionary:
	if a > b:
		var x := a
		a = b
		b = x
		t = 1.0 - t
	return _node("e", m.verts[a].lerp(m.verts[b], t), {"a": a, "b": b, "t": t})


static func _faces_of(m: KMesh, n: Dictionary) -> Array:
	match n["k"]:
		"v":
			return Array(m.vert_faces(n["v"]))
		"e":
			var out := []
			for f in [_face_of(m, n["a"], n["b"]), _face_of(m, n["b"], n["a"])]:
				if f != -1:
					out.append(f)
			return out
	return [n["f"]]


static func _same(x: Dictionary, y: Dictionary) -> bool:
	if x["k"] != y["k"]:
		return false
	match x["k"]:
		"v":
			return x["v"] == y["v"]
		"e":
			return x["a"] == y["a"] and x["b"] == y["b"]
	return x["id"] == y["id"]


static func _boundary(n: Dictionary) -> bool:
	return n["k"] != "f"


## the knife's way from node P to node Q: [[from, to, face]] or [] when it cannot get there
static func _segment(m: KMesh, P: Dictionary, Q: Dictionary, nrm: Vector3) -> Array:
	var p0: Vector3 = P["pos"]
	var d: Vector3 = Q["pos"] - p0
	if d.length() < 1e-9:
		return []
	var dn := d.normalized()
	var pn := dn.cross(nrm)
	if pn.length() < 1e-6:
		return []
	pn = pn.normalized()
	var segs := []
	var cur := P
	var cur_s := 0.0
	var seen := {}
	var qf := _faces_of(m, Q)
	for step in MAX_STEPS:
		var here := _faces_of(m, cur)
		for f in here:
			if qf.has(f) and not seen.has(f):
				segs.append([cur, Q, f])
				return segs
		var best = null
		var best_s := INF
		var best_f := -1
		for fi in here:
			if seen.has(fi):
				continue
			var f: PackedInt32Array = m.faces[fi]
			var sd := []
			for v in f:
				sd.append((m.verts[v] - p0).dot(pn))
			for i in f.size():
				var c = null
				if absf(sd[i]) < PLANE_EPS:
					c = {"k": "v", "v": f[i], "pos": m.verts[f[i]]}
				else:
					var j := (i + 1) % f.size()
					if absf(sd[j]) >= PLANE_EPS and (sd[i] > 0.0) != (sd[j] > 0.0):
						var t: float = sd[i] / (sd[i] - sd[j])
						var a := mini(f[i], f[j])
						c = {"k": "e", "a": a, "b": maxi(f[i], f[j]), "t": t if a == f[i] else 1.0 - t,
							"pos": m.verts[f[i]].lerp(m.verts[f[j]], t), "id": -1}
				if c == null or _same(c, cur):
					continue
				var s: float = ((c["pos"] as Vector3) - p0).dot(dn)
				if s > cur_s + PLANE_EPS and s < best_s:
					best_s = s
					best = c
					best_f = fi
		if best == null:
			return []
		var nd := _node(best["k"], best["pos"], best)
		nd["id"] = _uid
		segs.append([cur, nd, best_f])
		seen[best_f] = true
		cur = nd
		cur_s = best_s
	return []


## Knife through the surface points `pts` ([{"face", "point"}], mesh-local), in order. Returns the cut's verts (new and
## old) and edges, the faces it made or changed, "chords": how many face splits it made.
static func knife(m: KMesh, pts: Array, snap := SNAP) -> Dictionary:
	if pts.size() < 2:
		return _none("click two or more points on the surface first (Shift+K, click, click, Enter)")
	var nodes := []
	for p in pts:
		nodes.append(_snap(m, int(p["face"]), p["point"], snap))
	var segs := []
	for i in nodes.size() - 1:
		var nrm: Vector3 = m.face_normals[int(pts[i]["face"])] + m.face_normals[int(pts[i + 1]["face"])]
		if nrm.length() < 1e-6:
			nrm = m.face_normals[int(pts[i]["face"])]
		var s := _segment(m, nodes[i], nodes[i + 1], nrm.normalized())
		if s.is_empty() and not (nodes[i]["pos"] as Vector3).is_equal_approx(nodes[i + 1]["pos"]):
			return _none("the cut could not get from point %d to point %d across the surface: click points closer together" % [i + 1, i + 2])
		segs.append_array(s)
	# chords: boundary -> (inside points) -> boundary, all in one face
	var chords := []
	var ch = null
	if _boundary(nodes[0]):
		ch = {"u": nodes[0], "f": -1, "mids": []}
	for sg in segs:
		var B: Dictionary = sg[1]
		var F: int = sg[2]
		if ch != null and ch["f"] == -1:
			ch["f"] = F
		if ch != null and ch["f"] != F:
			ch = null
		if ch != null:
			if _boundary(B):
				ch["w"] = B
				chords.append(ch)
				ch = null
			else:
				ch["mids"].append(B)
		if ch == null and _boundary(B):
			ch = {"u": B, "f": -1, "mids": []}
	if chords.is_empty():
		return _none("the cut never crosses a face from side to side: start and end it on an edge or past one")
	# verts for the nodes the chords use
	var nverts := m.verts.duplicate()
	var src_v := PackedInt32Array()
	for v in m.verts.size():
		src_v.append(v)
	var vid := {}   # node id -> vertex
	var on_edge := {}   # Vector2i(a, b) -> [[t, vertex]]
	var vid_of := func(n: Dictionary) -> int:
		if n["k"] == "v":
			return n["v"]
		if vid.has(n["id"]):
			return vid[n["id"]]
		var id := nverts.size()
		nverts.append(n["pos"])
		if n["k"] == "e":
			src_v.append(n["a"] if float(n["t"]) < 0.5 else n["b"])
			var k := Vector2i(n["a"], n["b"])
			if not on_edge.has(k):
				on_edge[k] = []
			on_edge[k].append([float(n["t"]), id])
		else:
			src_v.append((m.faces[n["f"]] as PackedInt32Array)[0])
		vid[n["id"]] = id
		return id
	for c in chords:
		c["uv"] = vid_of.call(c["u"])
		c["wv"] = vid_of.call(c["w"])
		var mv := []
		for x in c["mids"]:
			mv.append(vid_of.call(x))
		c["mv"] = mv
	for k in on_edge:
		(on_edge[k] as Array).sort_custom(func(x, y): return x[0] < y[0])
	# new edge verts into every face of their edge
	var nfaces: Array = m.faces.duplicate()
	var src_f := PackedInt32Array()
	for fi in m.faces.size():
		src_f.append(fi)
	var changed := {}
	if not on_edge.is_empty():
		for fi in m.faces.size():
			var f: PackedInt32Array = m.faces[fi]
			var g := PackedInt32Array()
			var hit := false
			for i in f.size():
				var x := f[i]
				var y := f[(i + 1) % f.size()]
				g.append(x)
				var lst = on_edge.get(Vector2i(mini(x, y), maxi(x, y)))
				if lst == null:
					continue
				hit = true
				var ids: Array = (lst as Array).map(func(z): return z[1])
				if x > y:
					ids.reverse()
				for id in ids:
					g.append(id)
			if hit:
				nfaces[fi] = g
				changed[fi] = true
	# split the faces along the chords
	var sub := {}
	var made := 0
	var out_e := {}
	for c in chords:
		var F: int = c["f"]
		if not sub.has(F):
			sub[F] = [F]
		var u: int = c["uv"]
		var w: int = c["wv"]
		var mv: Array = c["mv"]
		if u == w:
			continue
		for g in sub[F]:
			var L: PackedInt32Array = nfaces[g]
			var i := L.find(u)
			var j := L.find(w)
			if i < 0 or j < 0:
				continue
			var n := L.size()
			if mv.is_empty() and ((i + 1) % n == j or (j + 1) % n == i):
				break   # along an edge it already has
			var A := PackedInt32Array()
			var k := i
			while true:
				A.append(L[k])
				if k == j:
					break
				k = (k + 1) % n
			for x in range(mv.size() - 1, -1, -1):
				A.append(mv[x])
			var Bf := PackedInt32Array()
			k = j
			while true:
				Bf.append(L[k])
				if k == i:
					break
				k = (k + 1) % n
			for x in mv:
				Bf.append(x)
			nfaces[g] = A
			changed[g] = true
			sub[F].append(nfaces.size())
			changed[nfaces.size()] = true
			nfaces.append(Bf)
			src_f.append(F)
			made += 1
			var chain := [u] + mv + [w]
			for x in chain.size() - 1:
				out_e[KMeshSelect.ekey(chain[x], chain[x + 1])] = true
			break
	if made == 0:
		return _none("the cut runs only along edges the mesh already has")
	var vs := {}
	for e in out_e:
		vs[e.x] = true
		vs[e.y] = true
	KMeshExtrude._commit(m, nverts, nfaces, src_v, src_f)
	return {"verts": vs.keys(), "edges": out_e.keys(), "faces": changed.keys(), "error": "", "chords": made}


# ---------------------------------------------------------------- selection-driven

## the edges a selection names: edge mode its edges; vertex mode the edges with both ends selected; face mode the
## border of the selected region (edges with a selected face on one side only)
static func selected_edges(m: KMesh, sel: KMeshSelect) -> Array:
	var out := {}
	match sel.mode:
		KMeshSelect.EDGE:
			for e in sel.edges:
				out[e] = true
		KMeshSelect.VERT:
			for e in m.edges():
				if sel.verts.has(e.x) and sel.verts.has(e.y):
					out[e] = true
		_:
			for fi in sel.faces:
				var f: PackedInt32Array = m.faces[fi]
				for i in f.size():
					var o := _face_of(m, f[(i + 1) % f.size()], f[i])
					if o == -1 or not sel.faces.has(o):
						out[KMeshSelect.ekey(f[i], f[(i + 1) % f.size()])] = true
	return out.keys()


static func _none(msg: String) -> Dictionary:
	return {"verts": [], "edges": [], "faces": [], "error": msg}
