class_name KMesh
extends RefCounted
## KMesh: Kine's editable mesh core (ROADMAP_400 A01). Every modelling / sculpt tool stands on this.
## Data: verts, faces (n-gons, counter-clockwise seen from outside), half-edges, face and vertex normals.
## Half-edge h of face f at corner i: he_vert[h] = faces[f][i] (its origin), he_next[h] = the next corner's half-edge
## (wraps), he_face[h] = f, he_twin[h] = the opposite half-edge (b->a for a->b) or -1 on a boundary.
## Half-edges of face f are face_he0[f] .. face_he0[f] + size - 1, in corner order.
## A directed edge used twice (non-manifold, or a face that repeats a vertex) keeps the first as the twin owner and the
## rest get twin -1; is_manifold() reports it.
## Welding (from_array_mesh): positions within WELD_TOL (1e-6 m, grid-quantised) become one vertex, so the file's
## split-at-seam triangles become one connected surface. UVs and skin weights are NOT kept (this is geometry only).

const WELD_TOL := 1e-6

var verts := PackedVector3Array()
var faces: Array = []  # of PackedInt32Array
var he_vert := PackedInt32Array()
var he_next := PackedInt32Array()
var he_twin := PackedInt32Array()
var he_face := PackedInt32Array()
var face_he0 := PackedInt32Array()
var face_normals := PackedVector3Array()
var vert_normals := PackedVector3Array()

var _vf_start := PackedInt32Array()  # CSR: faces around each vertex
var _vf_list := PackedInt32Array()
var _edge_he := {}  # directed key a * V + b -> half-edge


func vert_count() -> int:
	return verts.size()


func face_count() -> int:
	return faces.size()


func half_edge_count() -> int:
	return he_vert.size()


## Build from positions and n-gon faces. Returns self.
func from_arrays(p_verts: PackedVector3Array, p_faces: Array) -> KMesh:
	verts = p_verts.duplicate()
	faces = []
	for f in p_faces:
		faces.append(PackedInt32Array(f))
	rebuild()
	return self


## Recompute adjacency and normals from verts/faces (call after editing them).
func rebuild() -> void:
	var nv := verts.size()
	var nf := faces.size()
	var total := 0
	for f in faces:
		total += (f as PackedInt32Array).size()
	he_vert.resize(total)
	he_next.resize(total)
	he_twin.resize(total)
	he_face.resize(total)
	face_he0.resize(nf)
	he_twin.fill(-1)
	_edge_he.clear()
	var counts := PackedInt32Array()
	counts.resize(nv)
	var h := 0
	for fi in nf:
		var f: PackedInt32Array = faces[fi]
		var n := f.size()
		face_he0[fi] = h
		for i in n:
			var a := f[i]
			var b := f[(i + 1) % n]
			he_vert[h + i] = a
			he_next[h + i] = h + (i + 1) % n
			he_face[h + i] = fi
			counts[a] += 1
			if a != b:
				var key := a * nv + b
				if not _edge_he.has(key):
					_edge_he[key] = h + i
		h += n
	for key in _edge_he:
		var a: int = key / nv
		var b: int = key % nv
		var tw: int = _edge_he.get(b * nv + a, -1)
		he_twin[_edge_he[key]] = tw
	# vertex -> faces (CSR)
	_vf_start.resize(nv + 1)
	var acc := 0
	for v in nv:
		_vf_start[v] = acc
		acc += counts[v]
	_vf_start[nv] = acc
	_vf_list.resize(acc)
	var fill := PackedInt32Array()
	fill.resize(nv)
	for fi in nf:
		for v in (faces[fi] as PackedInt32Array):
			_vf_list[_vf_start[v] + fill[v]] = fi
			fill[v] += 1
	_compute_normals()


func _newell(fi: int) -> Vector3:
	# Newell's vector: direction = face normal, length = 2 * area (works for any planar-ish n-gon)
	var f: PackedInt32Array = faces[fi]
	var n := f.size()
	var s := Vector3.ZERO
	for i in n:
		var a := verts[f[i]]
		var b := verts[f[(i + 1) % n]]
		s.x += (a.y - b.y) * (a.z + b.z)
		s.y += (a.z - b.z) * (a.x + b.x)
		s.z += (a.x - b.x) * (a.y + b.y)
	return s


func _compute_normals() -> void:
	var nf := faces.size()
	face_normals.resize(nf)
	vert_normals.resize(verts.size())
	vert_normals.fill(Vector3.ZERO)
	for fi in nf:
		var nw := _newell(fi)
		face_normals[fi] = nw.normalized()
		for v in (faces[fi] as PackedInt32Array):
			vert_normals[v] += nw  # area-weighted: the vector's length is twice the area
	for v in verts.size():
		vert_normals[v] = vert_normals[v].normalized()


# ---------------------------------------------------------------- queries

func vert_faces(v: int) -> PackedInt32Array:
	return _vf_list.slice(_vf_start[v], _vf_start[v + 1])


## distinct vertices sharing an edge with v
func vert_neighbors(v: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for fi in vert_faces(v):
		var f: PackedInt32Array = faces[fi]
		var n := f.size()
		for i in n:
			if f[i] == v:
				for w in [f[(i + 1) % n], f[(i + n - 1) % n]]:
					if w != v and not out.has(w):
						out.append(w)
	return out


## unique undirected edges as Vector2i(a, b) with a < b
func edges() -> Array:
	var out: Array = []
	for h in he_vert.size():
		var a := he_vert[h]
		var b := he_vert[he_next[h]]
		if a == b:
			continue
		var t := he_twin[h]
		# keep each undirected edge once: the half-edge whose twin is absent, or the lower of the pair
		if t == -1 or h < t:
			out.append(Vector2i(mini(a, b), maxi(a, b)))
	return out


func edge_count() -> int:
	return edges().size()


## the half-edge a->b, or -1
func find_half_edge(a: int, b: int) -> int:
	return _edge_he.get(a * verts.size() + b, -1)


## true when the undirected edge a-b exists and only one face uses it
func is_boundary_edge(a: int, b: int) -> bool:
	var h := find_half_edge(a, b)
	var g := find_half_edge(b, a)
	return (h != -1) != (g != -1)


func boundary_edge_count() -> int:
	var c := 0
	for h in he_twin.size():
		if he_twin[h] == -1 and he_vert[h] != he_vert[he_next[h]]:
			c += 1
	return c


func face_center(fi: int) -> Vector3:
	var s := Vector3.ZERO
	var f: PackedInt32Array = faces[fi]
	for v in f:
		s += verts[v]
	return s / float(f.size())


## V - E + F
func euler() -> int:
	return verts.size() - edge_count() + faces.size()


func is_closed() -> bool:
	return he_vert.size() > 0 and boundary_edge_count() == 0


func he_prev(h: int) -> int:
	var f := he_face[h]
	var n := (faces[f] as PackedInt32Array).size()
	var i := h - face_he0[f]
	return face_he0[f] + (i + n - 1) % n


## Manifold: no directed edge used twice, no degenerate edge, and every vertex's faces form one fan
## (a disc for an interior vertex, a single open strip on the boundary).
func is_manifold() -> bool:
	var nv := verts.size()
	for h in he_vert.size():
		var a := he_vert[h]
		var b := he_vert[he_next[h]]
		if a == b or _edge_he.get(a * nv + b, -1) != h:
			return false
	for v in nv:
		var out_he: Array = []
		for fi in vert_faces(v):
			var f: PackedInt32Array = faces[fi]
			for i in f.size():
				if f[i] == v:
					out_he.append(face_he0[fi] + i)
		if out_he.is_empty():
			continue
		# walk the fan: from a half-edge leaving v to twin(prev) = the next face around v
		var start := -1
		var boundary_starts := 0
		for h in out_he:
			if he_twin[h] == -1:  # nothing walks into this face: it opens the fan
				boundary_starts += 1
				start = h
		if boundary_starts > 1:
			return false
		if start == -1:
			start = out_he[0]
		var count := 0
		var h2: int = start
		while count <= out_he.size():
			count += 1
			var nxt: int = he_twin[he_prev(h2)]
			if nxt == -1 or nxt == start:
				break
			h2 = nxt
		if count != out_he.size():
			return false
	return true


# ---------------------------------------------------------------- Godot interop

## Weld a surface of an ArrayMesh (triangles) into a connected KMesh.
func from_array_mesh(am: ArrayMesh, surface := 0) -> KMesh:
	var arr := am.surface_get_arrays(surface)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx.resize(pos.size())
		for i in pos.size():
			idx[i] = i
	var inv := 1.0 / WELD_TOL
	var grid := {}
	var remap := PackedInt32Array()
	remap.resize(pos.size())
	var out := PackedVector3Array()
	for i in pos.size():
		var p := pos[i]
		var key := Vector3i(roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv))
		var got: int = grid.get(key, -1)
		if got == -1:
			got = out.size()
			grid[key] = got
			out.append(p)
		remap[i] = got
	var fs: Array = []
	for t in idx.size() / 3:
		fs.append(PackedInt32Array([remap[idx[t * 3]], remap[idx[t * 3 + 1]], remap[idx[t * 3 + 2]]]))
	return from_arrays(out, fs)


## Triangulate n-gons by fan from corner 0. smooth: shared vertices with the area-weighted vertex normals;
## flat: every face gets its own vertices and its face normal.
func to_array_mesh(smooth := true) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var idx := PackedInt32Array()
	if smooth:
		pos = verts.duplicate()
		nor = vert_normals.duplicate()
		for f in faces:
			var fp: PackedInt32Array = f
			for i in range(1, fp.size() - 1):
				idx.append(fp[0])
				idx.append(fp[i])
				idx.append(fp[i + 1])
	else:
		for fi in faces.size():
			var fp: PackedInt32Array = faces[fi]
			var base := pos.size()
			for v in fp:
				pos.append(verts[v])
				nor.append(face_normals[fi])
			for i in range(1, fp.size() - 1):
				idx.append(base)
				idx.append(base + i)
				idx.append(base + i + 1)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func triangle_count() -> int:
	var t := 0
	for f in faces:
		t += (f as PackedInt32Array).size() - 2
	return t
