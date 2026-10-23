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
var _he_vert := PackedInt32Array()
var _he_next := PackedInt32Array()
var _he_twin := PackedInt32Array()
var _he_face := PackedInt32Array()
var _face_he0 := PackedInt32Array()
var _face_normals := PackedVector3Array()
var _vert_normals := PackedVector3Array()
## A08 normals: the mode to_array_mesh uses by default, the auto-smooth angle, and optional custom split normals
## (custom_normals[f] = PackedVector3Array, one unit normal per corner of face f; empty array = none).
var normal_mode := NM_SMOOTH
var auto_angle := 30.0
var custom_normals: Array = []

const NM_SMOOTH := "smooth"
const NM_FLAT := "flat"
const NM_AUTO := "auto"
const NM_CUSTOM := "custom"
const FORMAT := "kmesh"
const VERSION := 1

## Message of the last failed from_dict / load_file / save (empty after a success). Every message names a next step.
static var last_error := ""
static var _b64_re: RegEx

## Lazy topology (A07): a mesh decoded from a file keeps verts/faces at once and builds the half-edge and normal arrays
## on first read (the build is the slow part of a 200k-vert load). The public names below fetch through _fresh().
var he_vert: PackedInt32Array:
	get:
		_fresh()
		return _he_vert
var he_next: PackedInt32Array:
	get:
		_fresh()
		return _he_next
var he_twin: PackedInt32Array:
	get:
		_fresh()
		return _he_twin
var he_face: PackedInt32Array:
	get:
		_fresh()
		return _he_face
var face_he0: PackedInt32Array:
	get:
		_fresh()
		return _face_he0
var face_normals: PackedVector3Array:
	get:
		_fresh()
		return _face_normals
var vert_normals: PackedVector3Array:
	get:
		_fresh()
		return _vert_normals
var _stale := false


func _fresh() -> void:
	if _stale:
		rebuild()

var _vf_start := PackedInt32Array()  # CSR: faces around each vertex
var _vf_list := PackedInt32Array()
var _edge_he := {}  # directed key a * V + b -> half-edge


func vert_count() -> int:
	return verts.size()


func face_count() -> int:
	return faces.size()


func half_edge_count() -> int:
	_fresh()
	return _he_vert.size()


# ---------------------------------------------------------------- attributes (ROADMAP_400 A09)
## Named channels on a domain: "vert" (one per vertex), "corner" (one per face corner, in face order: index
## face_he0[f] + i), "edge" (one per unique edge, in edges() order) or "face". Types: TYPE_FLOAT, TYPE_VECTOR2,
## TYPE_VECTOR3, TYPE_COLOR. Conventional names: "color" (Color) and "uv" (Vector2) feed to_array_mesh COLOR / TEX_UV;
## "mask", "weight" (float, vert), "crease" (float, edge).
## attrs: name -> {"domain", "type", "default", "data": PackedFloat32Array / PackedVector2Array / PackedVector3Array / PackedColorArray}
const AD_VERT := "vert"
const AD_CORNER := "corner"
const AD_EDGE := "edge"
const AD_FACE := "face"
const AD_ALL := ["vert", "corner", "edge", "face"]
const AT_ALL := [TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]
## A19: LABEL channels hold an index into a table (a bone, a region, an anatomy tag), not an amount: an op that makes a
## new item from several old ones gives it one of their values, never a blend (KMeshSubdiv; label_pick). APPEND ONLY
const LABEL_ATTRS := ["body_bone", "body_region", "anat_tag"]
var attrs := {}


static func is_label(attr_name: String) -> bool:
	return LABEL_ATTRS.has(attr_name)


## the value of a label channel for an item made from the items `src`: the most common, ties to the first listed
static func label_pick(d: PackedFloat32Array, src: PackedInt32Array) -> float:
	var best := d[src[0]]
	var bn := 0
	for i in src.size():
		var n := 0
		for j in src.size():
			if d[src[j]] == d[src[i]]:
				n += 1
		if n > bn:
			bn = n
			best = d[src[i]]
	return best
## A13 shape keys (scripts/kmesh_shapes.gd): {} = none; saved in to_dict "shapes", carried by KMeshUndo
var shapes := {}
## A11: the non-destructive modifier stack (KMeshModifiers; saved in the .kmesh, carried by KMeshUndo)
var modifiers: Array = []
## E01 material slots (scripts/kmesh_material.gd): [] = none; saved in to_dict "materials", carried by KMeshUndo
var materials: Array = []


static func _attr_zero(type: int):
	match type:
		TYPE_VECTOR2:
			return Vector2.ZERO
		TYPE_VECTOR3:
			return Vector3.ZERO
		TYPE_COLOR:
			return Color(0, 0, 0, 0)
	return 0.0


static func _attr_make(type: int, n: int, def):
	var a
	match type:
		TYPE_VECTOR2:
			a = PackedVector2Array()
		TYPE_VECTOR3:
			a = PackedVector3Array()
		TYPE_COLOR:
			a = PackedColorArray()
		_:
			a = PackedFloat32Array()
	a.resize(n)
	a.fill(def)
	return a


static func _attr_bytes_to(type: int, raw: PackedByteArray):
	match type:
		TYPE_VECTOR2:
			return raw.to_vector2_array()
		TYPE_VECTOR3:
			return raw.to_vector3_array()
		TYPE_COLOR:
			return raw.to_color_array()
	return raw.to_float32_array()


static func _attr_type_name(type: int) -> String:
	return {TYPE_FLOAT: "float", TYPE_VECTOR2: "vec2", TYPE_VECTOR3: "vec3", TYPE_COLOR: "color"}.get(type, "")


static func _attr_type_of(nm: String) -> int:
	return {"float": TYPE_FLOAT, "vec2": TYPE_VECTOR2, "vec3": TYPE_VECTOR3, "color": TYPE_COLOR}.get(nm, -1)


## number of items in a domain right now
func domain_count(domain: String) -> int:
	match domain:
		AD_VERT:
			return verts.size()
		AD_FACE:
			return faces.size()
		AD_CORNER:
			var t := 0
			for f in faces:
				t += (f as PackedInt32Array).size()
			return t
		AD_EDGE:
			return edge_count()
	return -1


## Add a channel filled with `default` (the zero of the type when null). Returns false with last_error set when the name is
## taken or the domain/type is not one of the four.
func add_attr(attr_name: String, domain: String, type: int, default = null) -> bool:
	last_error = ""
	if attr_name == "" or attrs.has(attr_name):
		last_error = "attribute '%s' %s. Pick a new name, or remove_attr it first." % [attr_name, "has no name" if attr_name == "" else "already exists"]
		return false
	if not AD_ALL.has(domain) or not AT_ALL.has(type):
		last_error = "attribute domain must be vert, corner, edge or face and the type float, Vector2, Vector3 or Color."
		return false
	var def = _attr_zero(type) if default == null else type_convert(default, type)
	attrs[attr_name] = {"domain": domain, "type": type, "default": def, "data": _attr_make(type, domain_count(domain), def)}
	return true


func has_attr(attr_name: String) -> bool:
	return attrs.has(attr_name)


func remove_attr(attr_name: String) -> bool:
	return attrs.erase(attr_name)


## names of the channels (in the order they were added)
func list_attrs() -> Array:
	return attrs.keys()


## {"domain","type","default"} of one channel, or {}
func attr_info(attr_name: String) -> Dictionary:
	if not attrs.has(attr_name):
		return {}
	var r: Dictionary = attrs[attr_name]
	return {"domain": r["domain"], "type": r["type"], "default": r["default"]}


func get_attr(attr_name: String, i: int):
	return attrs[attr_name]["data"][i]


func set_attr(attr_name: String, i: int, value) -> void:
	attrs[attr_name]["data"][i] = value


## the whole channel as a packed array
func attr_data(attr_name: String):
	return attrs[attr_name]["data"]


## replace a channel's data (size must equal the domain count); false with last_error otherwise
func set_attr_data(attr_name: String, data) -> bool:
	last_error = ""
	if not attrs.has(attr_name) or data.size() != (attrs[attr_name]["data"] as Variant).size():
		last_error = "attribute '%s' %s. Pass one value per %s." % [attr_name, "does not exist" if not attrs.has(attr_name) else "has a different size", "item of its domain"]
		return false
	attrs[attr_name]["data"] = data
	return true


## index of the edge a-b in the "edge" domain, or -1
func edge_index(a: int, b: int) -> int:
	var i := 0
	var lo := mini(a, b)
	var hi := maxi(a, b)
	for e in edges():
		if e.x == lo and e.y == hi:
			return i
		i += 1
	return -1


## copy of attrs that shares nothing with the live channels (an undo snapshot)
func attr_snapshot() -> Dictionary:
	var out := {}
	for k in attrs:
		var r: Dictionary = attrs[k]
		out[k] = {"domain": r["domain"], "type": r["type"], "default": r["default"], "data": r["data"].duplicate()}
	return out


## keep every channel the size of its domain after the topology changed (new items get the default)
func _attr_fit(edge_n: int) -> void:
	for k in attrs:
		var r: Dictionary = attrs[k]
		var n: int = edge_n if r["domain"] == AD_EDGE else (verts.size() if r["domain"] == AD_VERT else (faces.size() if r["domain"] == AD_FACE else _he_vert.size()))
		var d = r["data"]
		var old: int = d.size()
		if old != n:
			d.resize(n)
			for i in range(old, n):
				d[i] = r["default"]
			r["data"] = d


## new channels gathered from the old: src_v[i] = old vert of new vert i (-1 = new), same for src_f faces, src_c corners,
## src_e edges. A null source keeps that domain as it is. Used by KMeshValidate.repair.
func attr_remap(src_v, src_f, src_c, src_e) -> void:
	for k in attrs:
		var r: Dictionary = attrs[k]
		var src = {AD_VERT: src_v, AD_FACE: src_f, AD_CORNER: src_c, AD_EDGE: src_e}[r["domain"]]
		if src == null:
			continue
		var old = r["data"]
		var nd = _attr_make(r["type"], (src as PackedInt32Array).size(), r["default"])
		for i in (src as PackedInt32Array).size():
			var s: int = src[i]
			if s >= 0 and s < old.size():
				nd[i] = old[s]
		r["data"] = nd


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
	_stale = false
	var nv := verts.size()
	var nf := faces.size()
	var total := 0
	for f in faces:
		total += (f as PackedInt32Array).size()
	_he_vert.resize(total)
	_he_next.resize(total)
	_he_twin.resize(total)
	_he_face.resize(total)
	_face_he0.resize(nf)
	_he_twin.fill(-1)
	_edge_he.clear()
	var counts := PackedInt32Array()
	counts.resize(nv)
	var h := 0
	for fi in nf:
		var f: PackedInt32Array = faces[fi]
		var n := f.size()
		_face_he0[fi] = h
		for i in n:
			var a := f[i]
			var b := f[(i + 1) % n]
			_he_vert[h + i] = a
			_he_next[h + i] = h + (i + 1) % n
			_he_face[h + i] = fi
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
		_he_twin[_edge_he[key]] = tw
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
	if not attrs.is_empty():
		var en := 0
		for hh in total:
			var t2 := _he_twin[hh]
			if _he_vert[hh] != _he_vert[_he_next[hh]] and (t2 == -1 or hh < t2):
				en += 1
		_attr_fit(en)


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
	_face_normals.resize(nf)
	_vert_normals.resize(verts.size())
	_vert_normals.fill(Vector3.ZERO)
	for fi in nf:
		var nw := _newell(fi)
		_face_normals[fi] = nw.normalized()
		for v in (faces[fi] as PackedInt32Array):
			_vert_normals[v] += nw  # area-weighted: the vector's length is twice the area
	for v in verts.size():
		_vert_normals[v] = _vert_normals[v].normalized()


# ---------------------------------------------------------------- queries

func vert_faces(v: int) -> PackedInt32Array:
	_fresh()
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
	_fresh()
	var out: Array = []
	for h in _he_vert.size():
		var a := _he_vert[h]
		var b := _he_vert[_he_next[h]]
		if a == b:
			continue
		var t := _he_twin[h]
		# keep each undirected edge once: the half-edge whose twin is absent, or the lower of the pair
		if t == -1 or h < t:
			out.append(Vector2i(mini(a, b), maxi(a, b)))
	return out


func edge_count() -> int:
	return edges().size()


## the half-edge a->b, or -1
func find_half_edge(a: int, b: int) -> int:
	_fresh()
	return _edge_he.get(a * verts.size() + b, -1)


## true when the undirected edge a-b exists and only one face uses it
func is_boundary_edge(a: int, b: int) -> bool:
	var h := find_half_edge(a, b)
	var g := find_half_edge(b, a)
	return (h != -1) != (g != -1)


func boundary_edge_count() -> int:
	_fresh()
	var c := 0
	for h in _he_twin.size():
		if _he_twin[h] == -1 and _he_vert[h] != _he_vert[_he_next[h]]:
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
	return _he_vert.size() > 0 and boundary_edge_count() == 0


func he_prev(h: int) -> int:
	_fresh()
	var f := _he_face[h]
	var n := (faces[f] as PackedInt32Array).size()
	var i := h - _face_he0[f]
	return _face_he0[f] + (i + n - 1) % n


## Manifold: no directed edge used twice, no degenerate edge, and every vertex's faces form one fan
## (a disc for an interior vertex, a single open strip on the boundary).
func is_manifold() -> bool:
	_fresh()
	var nv := verts.size()
	for h in _he_vert.size():
		var a := _he_vert[h]
		var b := _he_vert[_he_next[h]]
		if a == b or _edge_he.get(a * nv + b, -1) != h:
			return false
	for v in nv:
		var out_he: Array = []
		for fi in vert_faces(v):
			var f: PackedInt32Array = faces[fi]
			for i in f.size():
				if f[i] == v:
					out_he.append(_face_he0[fi] + i)
		if out_he.is_empty():
			continue
		# walk the fan: from a half-edge leaving v to twin(prev) = the next face around v
		var start := -1
		var boundary_starts := 0
		for h in out_he:
			if _he_twin[h] == -1:  # nothing walks into this face: it opens the fan
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
			var nxt: int = _he_twin[he_prev(h2)]
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


## Triangulate n-gons by fan from corner 0.
## mode "" resolves to: custom normals when present, else flat when smooth=false, else `normal_mode`.
## smooth: shared vertices with the area-weighted vertex normals. flat: every face gets its own vertices and its face
## normal. auto / custom: one vertex per distinct (vertex, corner normal), so split corners are separate vertices.
func to_array_mesh(smooth := true, mode := "") -> ArrayMesh:
	_fresh()
	if mode == "":
		if not custom_normals.is_empty():
			mode = NM_CUSTOM
		elif not smooth:
			mode = NM_FLAT
		else:
			mode = normal_mode
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var idx := PackedInt32Array()
	var ca = attrs.get("color")   # drawn attrs: "color" (Color) -> COLOR, "uv" (Vector2) -> TEX_UV
	var ua = attrs.get("uv")
	if ca != null and (ca["type"] != TYPE_COLOR or ca["domain"] == AD_EDGE):
		ca = null
	if ua != null and (ua["type"] != TYPE_VECTOR2 or ua["domain"] == AD_EDGE):
		ua = null
	var want: bool = ca != null or ua != null
	var split: bool = want and ((ca != null and ca["domain"] != AD_VERT) or (ua != null and ua["domain"] != AD_VERT))
	var ov := PackedInt32Array()   # per output vertex: source vertex, face, corner (only when an attr is drawn)
	var of := PackedInt32Array()
	var oc := PackedInt32Array()
	if mode == NM_SMOOTH and not split:
		pos = verts.duplicate()
		nor = _vert_normals.duplicate()
		for f in faces:
			var fp: PackedInt32Array = f
			for i in range(1, fp.size() - 1):
				idx.append(fp[0])
				idx.append(fp[i])
				idx.append(fp[i + 1])
	elif mode == NM_FLAT:
		var cbase := 0
		for fi in faces.size():
			var fp: PackedInt32Array = faces[fi]
			var base := pos.size()
			for v in fp:
				pos.append(verts[v])
				nor.append(_face_normals[fi])
				if want:
					ov.append(v)
					of.append(fi)
					oc.append(cbase + ov.size() - 1 - base)
			cbase += fp.size()
			for i in range(1, fp.size() - 1):
				idx.append(base)
				idx.append(base + i)
				idx.append(base + i + 1)
	else:
		var cn := corner_normals(mode, auto_angle) if mode != NM_SMOOTH else []
		var seen := {}  # (vertex, quantised normal, drawn values) -> output vertex
		var cbase := 0
		for fi in faces.size():
			var fp: PackedInt32Array = faces[fi]
			var cn_f: PackedVector3Array = cn[fi] if mode != NM_SMOOTH else PackedVector3Array()
			var local := PackedInt32Array()
			for i in fp.size():
				var n: Vector3 = cn_f[i] if mode != NM_SMOOTH else _vert_normals[fp[i]]
				var key := [fp[i], roundi(n.x * 1e5), roundi(n.y * 1e5), roundi(n.z * 1e5)]
				if want:
					key.append(_attr_at(ca, fp[i], fi, cbase + i))
					key.append(_attr_at(ua, fp[i], fi, cbase + i))
				var got: int = seen.get(key, -1)
				if got == -1:
					got = pos.size()
					seen[key] = got
					pos.append(verts[fp[i]])
					nor.append(n)
					if want:
						ov.append(fp[i])
						of.append(fi)
						oc.append(cbase + i)
				local.append(got)
			cbase += fp.size()
			for i in range(1, fp.size() - 1):
				idx.append(local[0])
				idx.append(local[i])
				idx.append(local[i + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_INDEX] = idx
	if want:
		if ca != null:
			arr[Mesh.ARRAY_COLOR] = _attr_gather(ca, pos.size(), ov, of, oc)
		if ua != null:
			arr[Mesh.ARRAY_TEX_UV] = _attr_gather(ua, pos.size(), ov, of, oc)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _attr_at(r, v: int, fi: int, ci: int):
	if r == null:
		return 0
	return r["data"][v if r["domain"] == AD_VERT else (fi if r["domain"] == AD_FACE else ci)]


## a drawn channel as one value per output vertex; the plain smooth path has none of ov/of/oc and one per source vertex
func _attr_gather(r: Dictionary, n: int, ov: PackedInt32Array, of: PackedInt32Array, oc: PackedInt32Array):
	if r["domain"] == AD_VERT and ov.is_empty():
		return r["data"].duplicate()
	var out = _attr_make(r["type"], n, r["default"])
	var src: PackedInt32Array = ov if r["domain"] == AD_VERT else (of if r["domain"] == AD_FACE else oc)
	var d = r["data"]
	for i in n:
		out[i] = d[src[i]]
	return out


func triangle_count() -> int:
	var t := 0
	for f in faces:
		t += (f as PackedInt32Array).size() - 2
	return t


# ---------------------------------------------------------------- symmetry (ROADMAP_400 A04)

## Mirror partner of every vertex across the plane (coordinate `axis` == `plane`; axis 0 = X, 1 = Y, 2 = Z).
## Result[v] = the vertex within `tol` of the mirror image of v (the nearest one), v itself for a vertex on the
## plane, -1 when there is none. Only mutual pairs are kept (partner[partner[v]] == v), so a lone near-duplicate
## never yields a one-way link. Spatial hash with cells of 4 * tol: O(V), no all-pairs search.
func symmetry_map(axis := 0, tol := 1e-4, plane := 0.0) -> PackedInt32Array:
	var nv := verts.size()
	var out := PackedInt32Array()
	out.resize(nv)
	out.fill(-1)
	if nv == 0:
		return out
	var cell := maxf(tol, 1e-9) * 4.0
	var head := {}  # Vector3i cell -> first vertex
	var chain := PackedInt32Array()
	chain.resize(nv)
	for v in nv:
		var p := verts[v]
		var k := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		chain[v] = head.get(k, -1)
		head[k] = v
	var cand := PackedInt32Array()
	cand.resize(nv)
	for v in nv:
		var m := verts[v]
		m[axis] = 2.0 * plane - m[axis]
		var lo := Vector3i(floori((m.x - tol) / cell), floori((m.y - tol) / cell), floori((m.z - tol) / cell))
		var hi := Vector3i(floori((m.x + tol) / cell), floori((m.y + tol) / cell), floori((m.z + tol) / cell))
		var best := -1
		var bd := tol * tol
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				for cz in range(lo.z, hi.z + 1):
					var u: int = head.get(Vector3i(cx, cy, cz), -1)
					while u != -1:
						var d := verts[u].distance_squared_to(m)
						if d <= bd:
							bd = d
							best = u
						u = chain[u]
		cand[v] = best
	for v in nv:
		var u := cand[v]
		if u != -1 and cand[u] == v:
			out[v] = u
	return out


# ---------------------------------------------------------------- normals (ROADMAP_400 A08)

## Per-corner normals: result[f][i] is the normal at corner i of face f.
## "smooth": the area-weighted vertex normal. "flat": the face normal. "auto": at each corner, the area-weighted sum of
## the faces around the vertex whose normal is within `angle` degrees of this corner's own face, so an edge sharper than
## the threshold splits the vertex into one normal per smooth patch (a cube stays 24 hard corners, a sphere stays smooth).
## "custom": the stored custom_normals (falls back to smooth for a face without one).
func corner_normals(mode := NM_SMOOTH, angle := 30.0) -> Array:
	_fresh()
	var out: Array = []
	out.resize(faces.size())
	var cos_t := cos(deg_to_rad(angle))
	var nw: Array = []
	if mode == NM_AUTO:
		nw.resize(faces.size())
		for fi in faces.size():
			nw[fi] = _newell(fi)
	for fi in faces.size():
		var f: PackedInt32Array = faces[fi]
		var cn := PackedVector3Array()
		cn.resize(f.size())
		for i in f.size():
			match mode:
				NM_FLAT:
					cn[i] = _face_normals[fi]
				NM_AUTO:
					var s := Vector3.ZERO
					for g in vert_faces(f[i]):
						if _face_normals[g].dot(_face_normals[fi]) >= cos_t - 1e-6:
							s += nw[g]
					cn[i] = s.normalized() if s.length_squared() > 0.0 else _face_normals[fi]
				NM_CUSTOM:
					if fi < custom_normals.size() and (custom_normals[fi] as PackedVector3Array).size() == f.size():
						cn[i] = custom_normals[fi][i]
					else:
						cn[i] = _vert_normals[f[i]]
				_:
					cn[i] = _vert_normals[f[i]]
		out[fi] = cn
	return out


## Store custom split normals (one PackedVector3Array per face, one entry per corner); switches normal_mode to custom.
## Returns false (and sets last_error) when the shape does not match the faces. An empty array clears them.
func set_custom_normals(cn: Array) -> bool:
	if cn.is_empty():
		custom_normals = []
		if normal_mode == NM_CUSTOM:
			normal_mode = NM_SMOOTH
		return true
	if cn.size() != faces.size():
		last_error = "custom normals: %d faces given, mesh has %d. Pass one PackedVector3Array per face." % [cn.size(), faces.size()]
		return false
	for fi in faces.size():
		if (cn[fi] as PackedVector3Array).size() != (faces[fi] as PackedInt32Array).size():
			last_error = "custom normals: face %d needs %d corner normals. Pass one normal per corner." % [fi, (faces[fi] as PackedInt32Array).size()]
			return false
	custom_normals = []
	for c in cn:
		custom_normals.append((c as PackedVector3Array).duplicate())
	normal_mode = NM_CUSTOM
	return true


# ---------------------------------------------------------------- .kmesh file (ROADMAP_400 A07)

static func _pack(raw: PackedByteArray) -> Dictionary:
	return {"n": raw.size(), "z": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}


static func _unpack(d, what: String) -> PackedByteArray:
	if not (d is Dictionary) or not d.has("n") or not d.has("z"):
		last_error = "%s block is missing. The file is damaged: re-save it from the app, or restore a backup." % what
		return PackedByteArray()
	var b64 := String(d["z"])
	if _b64_re == null:
		_b64_re = RegEx.new()
		_b64_re.compile("^[A-Za-z0-9+/]*={0,2}$")
	# pre-check so a bad block is an error message, not an engine error line from base64_to_raw
	var z := Marshalls.base64_to_raw(b64) if b64.length() % 4 == 0 and _b64_re.search(b64) != null else PackedByteArray()
	var n := int(d["n"])
	if z.is_empty() and n > 0:
		last_error = "%s block is not valid base64. The file is damaged: re-save it from the app, or restore a backup." % what
		return PackedByteArray()
	var raw := z.decompress(n, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != n:
		last_error = "%s block is corrupt (expected %d bytes, got %d). The file is damaged: re-save it from the app, or restore a backup." % [what, n, raw.size()]
		return PackedByteArray()
	return raw


## JSON-ready dictionary: header ("format","version","verts","faces","corners","attrs") plus the arrays. Verts are
## float32 little-endian, faces int32; a mesh whose faces all have the same size stores just the indices ("face_size"),
## else [n, i0..in-1, ...]. Blocks are deflated then base64. "normals" holds mode, angle and any custom corner normals.
func to_dict() -> Dictionary:
	var uniform := not faces.is_empty()
	var fs := (faces[0] as PackedInt32Array).size() if uniform else 0
	var flat := PackedInt32Array()
	var total := 0
	for f in faces:
		total += (f as PackedInt32Array).size()
		if (f as PackedInt32Array).size() != fs:
			uniform = false
	flat.resize(total + (0 if uniform else faces.size()))
	var p := 0
	for f in faces:
		var fp: PackedInt32Array = f
		if not uniform:
			flat[p] = fp.size()
			p += 1
		for v in fp:
			flat[p] = v
			p += 1
	var d := {
		"format": FORMAT, "version": VERSION, "verts": verts.size(), "faces": faces.size(), "corners": total,
		"face_size": fs if uniform else 0, "attrs": {},
		"v": _pack(verts.to_byte_array()), "f": _pack(flat.to_byte_array()),
		"normals": {"mode": normal_mode, "angle": auto_angle},
	}
	for k in attrs:
		var r: Dictionary = attrs[k]
		var dflt = _attr_make(r["type"], 1, r["default"])
		d["attrs"][k] = {"domain": r["domain"], "type": _attr_type_name(r["type"]), "def": Marshalls.raw_to_base64(dflt.to_byte_array()),
			"d": _pack(r["data"].to_byte_array())}
	if not custom_normals.is_empty():
		var cn := PackedVector3Array()
		for c in custom_normals:
			cn.append_array(c)
		d["normals"]["custom"] = _pack(cn.to_byte_array())
	if not shapes.is_empty():
		d["shapes"] = KMeshShapes.to_file(shapes)   # A13
	if not modifiers.is_empty():
		d["modifiers"] = KMeshModifiers.to_file(modifiers)   # A11
	if not materials.is_empty():
		d["materials"] = KMeshMaterial.to_file(materials)   # E01
	if has_meta("lods"):
		d["lods"] = KMeshLOD.to_file(self)   # F04
	if has_meta(KMeshRefPlanes.META):
		d["refplanes"] = KMeshRefPlanes.to_file(self)   # B21: path + hash, never the pixels
	return d


## Fill from a to_dict() dictionary. Returns self, or null with last_error set (nothing is changed on failure).
func from_dict(d: Dictionary) -> KMesh:
	last_error = ""
	if d.get("format", "") != FORMAT:
		last_error = "not a .kmesh file (format is '%s'). Pick a file saved by Kine's mesh export." % str(d.get("format", ""))
		return null
	if int(d.get("version", 0)) != VERSION:
		last_error = "unsupported .kmesh version %s (this build reads %d). Update Kine or re-export the mesh." % [str(d.get("version", "?")), VERSION]
		return null
	var nv := int(d.get("verts", -1))
	var nf := int(d.get("faces", -1))
	var nc := int(d.get("corners", -1))
	var fs := int(d.get("face_size", 0))
	if nv < 0 or nf < 0 or nc < 0:
		last_error = "the header has no vertex/face counts. The file is damaged: re-save it from the app."
		return null
	var vraw := _unpack(d.get("v"), "vertex")
	if last_error != "":
		return null
	if vraw.size() != nv * 12:
		last_error = "vertex count %d does not match the data (%d bytes). The file is damaged: restore a backup." % [nv, vraw.size()]
		return null
	var fraw := _unpack(d.get("f"), "face")
	if last_error != "":
		return null
	var flat := fraw.to_int32_array()
	var new_faces: Array = []
	new_faces.resize(nf)
	if fs > 0:
		if nf * fs != nc or flat.size() != nc:
			last_error = "face count %d x size %d does not match the data (%d indices). The file is damaged: restore a backup." % [nf, fs, flat.size()]
			return null
		for fi in nf:
			new_faces[fi] = flat.slice(fi * fs, fi * fs + fs)
	else:
		var p := 0
		for fi in nf:
			if p >= flat.size():
				last_error = "face data ends early (face %d of %d). The file is damaged: restore a backup." % [fi, nf]
				return null
			var n := flat[p]
			if n < 3 or p + 1 + n > flat.size():
				last_error = "face %d has a bad size (%d). The file is damaged: restore a backup." % [fi, n]
				return null
			new_faces[fi] = flat.slice(p + 1, p + 1 + n)
			p += 1 + n
		if p != flat.size() or flat.size() - nf != nc:
			last_error = "face data length does not match the header. The file is damaged: restore a backup."
			return null
	var bad := false
	if fs > 0:
		if not flat.is_empty():
			var sorted := flat.duplicate()
			sorted.sort()
			bad = sorted[0] < 0 or sorted[sorted.size() - 1] >= nv
	else:
		for fi in nf:
			for v in (new_faces[fi] as PackedInt32Array):
				if v < 0 or v >= nv:
					bad = true
					break
			if bad:
				break
	if bad:
		last_error = "a face points at a vertex outside 0..%d. The file is damaged: restore a backup." % (nv - 1)
		return null
	var new_custom: Array = []
	var nmode := NM_SMOOTH
	var nangle := 30.0
	var nd = d.get("normals", {})
	if nd is Dictionary:
		nmode = String(nd.get("mode", NM_SMOOTH))
		nangle = float(nd.get("angle", 30.0))
		if nd.has("custom"):
			var craw := _unpack(nd["custom"], "custom normal")
			if last_error != "":
				return null
			if craw.size() != nc * 12:
				last_error = "custom normals count does not match the face corners (%d). The file is damaged: restore a backup." % nc
				return null
			var cn := craw.to_vector3_array()
			var q := 0
			for fi in nf:
				var sz := (new_faces[fi] as PackedInt32Array).size()
				new_custom.append(cn.slice(q, q + sz))
				q += sz
	if not [NM_SMOOTH, NM_FLAT, NM_AUTO, NM_CUSTOM].has(nmode) or (nmode == NM_CUSTOM and new_custom.is_empty()):
		nmode = NM_SMOOTH
	var new_attrs := {}
	var ad = d.get("attrs", {})
	if ad is Dictionary:
		for k in ad:
			var ar = ad[k]
			if not (ar is Dictionary):
				last_error = "attribute '%s' is damaged. Re-save the mesh from the app, or restore a backup." % str(k)
				return null
			var dom := String(ar.get("domain", ""))
			var ty := _attr_type_of(String(ar.get("type", "")))
			if not AD_ALL.has(dom) or ty < 0:
				last_error = "attribute '%s' has an unknown domain or type. Update Kine, or restore a backup." % str(k)
				return null
			var araw := _unpack(ar.get("d"), "attribute '%s'" % str(k))
			if last_error != "":
				return null
			var data = _attr_bytes_to(ty, araw)
			var want := nv if dom == AD_VERT else (nf if dom == AD_FACE else (nc if dom == AD_CORNER else -1))
			if want >= 0 and data.size() != want:
				last_error = "attribute '%s' has %d values but its %s domain has %d. The file is damaged: restore a backup." % [str(k), data.size(), dom, want]
				return null
			var dd = _attr_bytes_to(ty, Marshalls.base64_to_raw(String(ar.get("def", ""))))
			new_attrs[String(k)] = {"domain": dom, "type": ty, "default": dd[0] if dd.size() == 1 else _attr_zero(ty), "data": data}
	var new_shapes := KMeshShapes.from_file(d.get("shapes"), nv)   # A13
	if last_error != "":
		return null
	var new_mods := KMeshModifiers.from_file(d.get("modifiers"))   # A11
	if KMeshModifiers.last_error != "":
		last_error = KMeshModifiers.last_error
		return null
	var new_mats := KMeshMaterial.from_file(d.get("materials"))   # E01
	if last_error != "":
		return null
	verts = vraw.to_vector3_array()
	attrs = new_attrs
	shapes = new_shapes
	modifiers = new_mods
	materials = new_mats
	faces = new_faces
	custom_normals = new_custom
	normal_mode = nmode
	auto_angle = nangle
	KMeshLOD.from_file(self, d.get("lods"))   # F04
	KMeshRefPlanes.from_file(self, d.get("refplanes"))   # B21
	_stale = true  # topology and normals build on first read (see _fresh)
	return self


## Write a .kmesh (JSON text). Returns OK or an Error; last_error explains a failure.
func save(path: String) -> int:
	last_error = ""
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var e := FileAccess.get_open_error()
		last_error = "could not write '%s' (error %d). Pick a folder you can write to." % [path, e]
		return e
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return OK


## Read a .kmesh. Returns the KMesh, or null with KMesh.last_error set (never crashes on a bad file).
static func load_file(path: String) -> KMesh:
	last_error = ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "could not open '%s'. Pick an existing .kmesh file." % path
		return null
	var txt := f.get_as_text()
	f.close()
	var js := JSON.new()
	var parsed = js.data if js.parse(txt) == OK else null
	if not (parsed is Dictionary):
		last_error = "'%s' is not valid .kmesh JSON. Pick a file saved by Kine, or restore a backup." % path
		return null
	return KMesh.new().from_dict(parsed)
