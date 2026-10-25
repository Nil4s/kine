class_name KMeshSelect
extends RefCounted
## KMeshSelect: vertex / edge / face selection for a KMesh (ROADMAP_400 A02).
## Three sets, each a Dictionary used as a set: verts {int: true}, edges {Vector2i(min, max): true}, faces {int: true}.
## `mode` says which set is live; the other two are kept empty, so the mode set is always the truth.
## Switching mode converts (set_mode): going down takes every corner; going up needs the WHOLE element
## (a face is selected only when all its verts / edges are selected).
## Grow / shrink step by one ring of adjacency. Faces choose how they touch: vertex_adjacent (default; one quad
## grows to its 3x3 block = 9) or edge-adjacent (shares an edge: 1 -> 5). Shrink keeps an element only when every
## neighbour of the same kind is selected, so shrink(grow(x)) == x away from mesh edges.
## Loop: from an edge, at each interior vertex of valence 4 continue to the edge opposite the one you arrived on;
## stop at poles (valence != 4), boundary vertices and when the loop closes. Ring: across quads, the edge facing
## the current one; stops at non-quads / boundaries. A ring across a column of n quads holds n + 1 edges.

enum { VERT, EDGE, FACE }

var mesh: KMesh
var mode := VERT
var verts := {}
var edges := {}
var faces := {}


func _init(m: KMesh = null, p_mode := VERT) -> void:
	mesh = m
	mode = p_mode


static func ekey(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


func _live() -> Dictionary:
	match mode:
		EDGE:
			return edges
		FACE:
			return faces
	return verts


func count() -> int:
	return _live().size()


## the selection as a value (KMeshUndo keeps one before and after each step)
func snapshot() -> Dictionary:
	return {"mode": mode, "verts": verts.duplicate(), "edges": edges.duplicate(), "faces": faces.duplicate()}


## the picks of a snapshot that still exist in the mesh (an undo can remove the ones made by the edit); {} clears
func restore(snap: Dictionary) -> void:
	clear()
	if snap.is_empty() or mesh == null:
		return
	mode = int(snap["mode"])
	var nv := mesh.vert_count()
	var nf := mesh.face_count()
	for v in snap["verts"]:
		if int(v) < nv:
			verts[v] = true
	for e in snap["edges"]:
		if e.x < nv and e.y < nv and mesh.find_half_edge(e.x, e.y) >= 0:
			edges[e] = true
	for f in snap["faces"]:
		if int(f) < nf:
			faces[f] = true


func is_empty() -> bool:
	return _live().is_empty()


func clear() -> void:
	verts.clear()
	edges.clear()
	faces.clear()


# ---------------------------------------------------------------- mesh helpers

## faces using the undirected edge a-b
func edge_faces(a: int, b: int) -> Array:
	var out: Array = []
	var h := mesh.find_half_edge(a, b)
	if h != -1:
		out.append(mesh.he_face[h])
	var g := mesh.find_half_edge(b, a)
	if g != -1 and mesh.he_face[g] not in out:
		out.append(mesh.he_face[g])
	return out


func face_edges(fi: int) -> Array:
	var f: PackedInt32Array = mesh.faces[fi]
	var out: Array = []
	for i in f.size():
		var a := f[i]
		var b := f[(i + 1) % f.size()]
		if a != b:
			out.append(ekey(a, b))
	return out


func _vert_edges(v: int) -> Array:
	var out: Array = []
	for n in mesh.vert_neighbors(v):
		out.append(ekey(v, n))
	return out


func _all_in(f: PackedInt32Array, set: Dictionary) -> bool:
	for v in f:
		if not set.has(v):
			return false
	return f.size() > 0


# ---------------------------------------------------------------- modes and conversion

## Convert the selection to mode m (see the class comment) and make it live.
func set_mode(m: int) -> void:
	if m == mode:
		return
	var nv := {}
	var ne := {}
	var nf := {}
	match mode:
		VERT:
			if m == EDGE:
				for e in mesh.edges():
					if verts.has(e.x) and verts.has(e.y):
						ne[e] = true
			else:
				for fi in mesh.face_count():
					if _all_in(mesh.faces[fi], verts):
						nf[fi] = true
		EDGE:
			if m == VERT:
				for e in edges:
					nv[e.x] = true
					nv[e.y] = true
			else:
				for fi in mesh.face_count():
					var fe := face_edges(fi)
					var all := not fe.is_empty()
					for e in fe:
						if not edges.has(e):
							all = false
							break
					if all:
						nf[fi] = true
		FACE:
			for fi in faces:
				if m == VERT:
					for v in (mesh.faces[fi] as PackedInt32Array):
						nv[v] = true
				else:
					for e in face_edges(fi):
						ne[e] = true
	verts = nv
	edges = ne
	faces = nf
	mode = m


# ---------------------------------------------------------------- all / none / invert

func select_all() -> void:
	clear()
	match mode:
		VERT:
			for v in mesh.vert_count():
				verts[v] = true
		EDGE:
			for e in mesh.edges():
				edges[e] = true
		FACE:
			for f in mesh.face_count():
				faces[f] = true


func select_none() -> void:
	clear()


func invert() -> void:
	var old := _live().duplicate()
	select_all()
	var live := _live()
	for k in old:
		live.erase(k)


# ---------------------------------------------------------------- grow / shrink

func grow(vertex_adjacent := true) -> void:
	var add: Array = []
	for k in _live():
		add.append_array(_neighbours(k, vertex_adjacent))
	var live := _live()
	for k in add:
		live[k] = true


func shrink(vertex_adjacent := true) -> void:
	var live := _live()
	var drop: Array = []
	for k in live:
		for n in _neighbours(k, vertex_adjacent):
			if not live.has(n):
				drop.append(k)
				break
	for k in drop:
		live.erase(k)


## elements of the same kind adjacent to k
func _neighbours(k, vertex_adjacent: bool) -> Array:
	var out: Array = []
	match mode:
		VERT:
			for n in mesh.vert_neighbors(k):
				out.append(n)
		EDGE:  # edges sharing an endpoint
			for v in [k.x, k.y]:
				for e in _vert_edges(v):
					if e != k:
						out.append(e)
		FACE:
			if vertex_adjacent:
				for v in (mesh.faces[k] as PackedInt32Array):
					for g in mesh.vert_faces(v):
						if g != k:
							out.append(g)
			else:
				for e in face_edges(k):
					for g in edge_faces(e.x, e.y):
						if g != k:
							out.append(g)
	return out


# ---------------------------------------------------------------- linked

## Everything connected (through shared vertices) to the current selection.
func select_linked() -> void:
	var seen := {}
	var stack: Array = []
	match mode:
		VERT:
			stack = verts.keys()
		EDGE:
			for e in edges:
				stack.append(e.x)
				stack.append(e.y)
		FACE:
			for fi in faces:
				stack.append_array(Array(mesh.faces[fi]))
	for v in stack:
		seen[v] = true
	while not stack.is_empty():
		var v: int = stack.pop_back()
		for fi in mesh.vert_faces(v):
			for w in (mesh.faces[fi] as PackedInt32Array):
				if not seen.has(w):
					seen[w] = true
					stack.append(w)
	clear()
	match mode:
		VERT:
			verts = seen
		EDGE:
			for e in mesh.edges():
				if seen.has(e.x):
					edges[e] = true
		FACE:
			for fi in mesh.face_count():
				if seen.has((mesh.faces[fi] as PackedInt32Array)[0]):
					faces[fi] = true


# ---------------------------------------------------------------- loop / ring

## Select the edge loop through edge a-b (switches to edge mode).
func select_loop(a: int, b: int, add := false) -> void:
	set_mode(EDGE)
	if not add:
		clear()
	edges[ekey(a, b)] = true
	_walk_loop(a, b)
	_walk_loop(b, a)


func _walk_loop(a: int, b: int) -> void:
	while true:
		var c := _through(a, b)
		if c < 0:
			return
		var k := ekey(b, c)
		if edges.has(k):
			return
		edges[k] = true
		a = b
		b = c


## arriving at b along a->b: the vertex to continue to, or -1 to stop
func _through(a: int, b: int) -> int:
	var nb := mesh.vert_neighbors(b)
	if nb.size() == 3:
		return _through_corner(a, b, nb)
	if nb.size() != 4:
		return -1
	for n in nb:
		if mesh.is_boundary_edge(b, n):
			return -1
	var fs := edge_faces(a, b)
	if fs.size() != 2:
		return -1
	var skip := {a: true}
	for fi in fs:
		var f: PackedInt32Array = mesh.faces[fi]
		var n := f.size()
		for i in n:
			if f[i] == b:
				skip[f[(i + 1) % n]] = true
				skip[f[(i + n - 1) % n]] = true
	var rest := -1
	for n in nb:
		if not skip.has(n):
			if rest != -1:
				return -1
			rest = n
	return rest


## a rim ring turns a corner: at a valence-3 vertex (a box or bevel corner) the loop goes on along the neighbour edge
## whose shared face with a-b faces the most up (the top of a rim; then the bigger face), so the ring stays on the top,
## as Blender does for a rim. Only across a crease (the faces of a-b meet at more than 30 degrees): flat folds stop as before.
func _through_corner(a: int, b: int, nb: PackedInt32Array) -> int:
	var fs := edge_faces(a, b)
	if fs.size() != 2:
		return -1
	var n0: Vector3 = mesh.face_normals[fs[0]]
	var n1: Vector3 = mesh.face_normals[fs[1]]
	if n0.dot(n1) > 0.866:
		return -1
	var best := -1
	var best_score := -INF
	for n in nb:
		if n == a:
			continue
		var shared := 0
		var sf := -1
		for f in edge_faces(b, n):
			if fs.has(f):
				shared += 1
				sf = f
		if shared != 1:
			continue
		var score: float = mesh.face_normals[sf].y + 0.01 * _face_area(sf)
		if score > best_score:
			best_score = score
			best = n
	return best


func _face_area(fi: int) -> float:
	var f: PackedInt32Array = mesh.faces[fi]
	var nrm := Vector3.ZERO
	for i in f.size():
		nrm += mesh.verts[f[i]].cross(mesh.verts[f[(i + 1) % f.size()]])
	return nrm.length() * 0.5


## Select the edge ring through edge a-b (switches to edge mode).
func select_ring(a: int, b: int, add := false) -> void:
	set_mode(EDGE)
	if not add:
		clear()
	var start := ekey(a, b)
	edges[start] = true
	for f0 in edge_faces(a, b):
		var fi: int = f0
		var cur := start
		while true:
			var opp := _opposite(fi, cur)
			if opp.x < 0 or edges.has(opp):
				break
			edges[opp] = true
			var nxt := -1
			for g in edge_faces(opp.x, opp.y):
				if g != fi:
					nxt = g
			if nxt == -1:
				break
			fi = nxt
			cur = opp


## the edge of quad fi facing edge e, or (-1, -1)
func _opposite(fi: int, e: Vector2i) -> Vector2i:
	var f: PackedInt32Array = mesh.faces[fi]
	if f.size() != 4:
		return Vector2i(-1, -1)
	for i in 4:
		if ekey(f[i], f[(i + 1) % 4]) == e:
			return ekey(f[(i + 2) % 4], f[(i + 3) % 4])
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- by normal

## Faces whose normal is within `degrees` of `dir`. Switches to face mode.
func select_by_normal(dir: Vector3, degrees: float, add := false) -> void:
	set_mode(FACE)
	if not add:
		clear()
	var d := dir.normalized()
	var lim := cos(deg_to_rad(degrees))
	for fi in mesh.face_count():
		if mesh.face_normals[fi].dot(d) >= lim - 1e-9:
			faces[fi] = true


# ---------------------------------------------------------------- symmetry

## Mirror the selection through a KMesh.symmetry_map; `add` keeps the original too (symmetric select).
## Elements with no partner drop out (or stay, when adding).
func mirror_selection(map: PackedInt32Array, add := false) -> void:
	var nv := {}
	var ne := {}
	var nf := {}
	for v in verts:
		if map[v] != -1:
			nv[map[v]] = true
	for e in edges:
		if map[e.x] != -1 and map[e.y] != -1:
			ne[ekey(map[e.x], map[e.y])] = true
	for fi in faces:
		var f: PackedInt32Array = mesh.faces[fi]
		var m := {}
		var okf := true
		for v in f:
			if map[v] == -1:
				okf = false
				break
			m[map[v]] = true
		if not okf:
			continue
		for g in mesh.vert_faces(map[f[0]]):
			var gf: PackedInt32Array = mesh.faces[g]
			if gf.size() == f.size() and _all_in(gf, m):
				nf[g] = true
				break
	if add:
		verts.merge(nv)
		edges.merge(ne)
		faces.merge(nf)
	else:
		verts = nv
		edges = ne
		faces = nf
