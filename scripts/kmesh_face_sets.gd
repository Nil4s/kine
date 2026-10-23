class_name KMeshFaceSets
extends RefCounted
## FACE SETS (ROADMAP_400 C09): every face belongs to one numbered set, kept as the A09 attribute channel "face_set"
## (face domain; a float channel holding whole numbers, exact up to 2^24), so it is saved with the mesh (KMesh.to_dict)
## and taken back by KMeshUndo like any channel. A face's value is its set id (1, 2, 3 ...; 1 = the default set every
## face starts in); a NEGATIVE value is the same set HIDDEN (-3 = set 3, hidden): hiding keeps the set, one channel holds
## both, and every op that copies a face (attr_remap, subdivision) carries both together.
##   MAKE: from_faces (the selection gets a new id), from_labels (one set per A19 anatomy tag, A18 body region, material
##     slot or UV island; the id is the label + 2, so "no label" (-1) is the default set 1). A vert-domain label (anat_tag,
##     body_region) becomes a face's by KMesh.label_pick over its corners (the most common, ties to the first corner),
##     the rule subdivision uses for a face point. paint: the face-set brush (a dab sets every visible face that has a
##     corner within the brush radius).
##   USE: hide / show / isolate a set; frozen(): the verts a sculpt stroke may not move: every corner of a hidden face, and
##     with "sculpt only this set" every corner of a face of another set. A vert on the seam of two sets is frozen too
##     (strict: the other sets, and the hidden faces, stay bit-exact, their seam included). grow / shrink: one ring of
##     faces, vertex-adjacent (KMeshSelect's ring: a 4 x 4 block grows to 6 x 6). A face shrunk off a set joins the most
##     common set among its vertex-neighbours outside it. mask_from: the C03 mask (KMeshMask) set to 1 on the verts of a
##     set ("set") or on every vert with a face outside it ("others": the seam too, as "sculpt only this set" freezes it),
##     kept where it was already higher (max).
##   SHOW: colour_of(id) is a stable colour per id (golden-angle hues), set 1 is not tinted; tint_arrays draws the visible
##     faces of the other sets as a see-through layer (KMeshFaceSetTint, scripts/kmesh_face_set_tint.gd).
## Pure, no nodes.

const NAME := "face_set"
const DEFAULT := 1
const LABELS := ["anatomy", "region", "material", "uv"]


## the channel, made (every face in set 1) if the mesh has none
static func ensure(m: KMesh) -> bool:
	if m.has_attr(NAME):
		return true
	return m.add_attr(NAME, KMesh.AD_FACE, TYPE_FLOAT, float(DEFAULT))


## the channel's values (a reference), or empty when the mesh has none
static func values(m: KMesh) -> PackedFloat32Array:
	if m == null or not m.has_attr(NAME) or m.attr_info(NAME).get("domain", "") != KMesh.AD_FACE:
		return PackedFloat32Array()
	return m.attr_data(NAME)


static func _put(m: KMesh, d: PackedFloat32Array) -> void:
	ensure(m)
	m.set_attr_data(NAME, d)


## the set of face fi (1 when the mesh has no channel)
static func set_of(m: KMesh, fi: int) -> int:
	var d := values(m)
	if fi < 0 or fi >= d.size():
		return DEFAULT
	return absi(int(d[fi]))


static func is_hidden(m: KMesh, fi: int) -> bool:
	var d := values(m)
	return fi >= 0 and fi < d.size() and d[fi] < 0.0


## 1 per hidden face, or EMPTY when no face is hidden (the cheap common case: callers test is_empty())
static func hidden_faces(m: KMesh) -> PackedByteArray:
	var d := values(m)
	var out := PackedByteArray()
	for fi in d.size():
		if d[fi] < 0.0:
			if out.is_empty():
				out.resize(d.size())
			out[fi] = 1
	return out


## the ids in use, sorted
static func ids(m: KMesh) -> PackedInt32Array:
	var seen := {}
	for x in values(m):
		seen[absi(int(x))] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


static func next_id(m: KMesh) -> int:
	var mx := DEFAULT
	for x in values(m):
		mx = maxi(mx, absi(int(x)))
	return mx + 1


## faces -> the set of each (empty when there is none)
static func faces_of(m: KMesh, id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var d := values(m)
	for fi in d.size():
		if absi(int(d[fi])) == id:
			out.append(fi)
	return out


# ---------------------------------------------------------------- make

## the faces get a new set (visible); returns its id (-1 when `faces` is empty)
static func from_faces(m: KMesh, faces) -> int:
	if faces.is_empty():
		return -1
	ensure(m)
	var id := next_id(m)
	var d := values(m)
	for fi in faces:
		d[int(fi)] = float(id)
	_put(m, d)
	return id


## the label of each face for `kind` (anatomy / region / material / uv), -1 = none; empty when the mesh has no such data
static func face_labels(m: KMesh, kind: String) -> PackedInt32Array:
	var nf := m.face_count()
	var out := PackedInt32Array()
	match kind:
		"anatomy", "region":
			var ch := KMeshAnatomy.CH if kind == "anatomy" else KMeshBody.CH_REGION
			if not m.has_attr(ch) or m.attr_info(ch)["domain"] != KMesh.AD_VERT:
				return out
			var vd: PackedFloat32Array = m.attr_data(ch)
			out.resize(nf)
			for fi in nf:
				out[fi] = int(KMesh.label_pick(vd, m.faces[fi]))
		"material":
			if m.materials.is_empty():
				return out
			out.resize(nf)
			for fi in nf:
				out[fi] = KMeshMaterial.face_slot(m, fi)
		"uv":
			out = KMeshUV.topology(m)["island"]
	return out


## one set per label: face fi gets set label + 2 (no label: set 1); every face visible. Returns the sets made (the
## distinct labels), -1 when the mesh has no such data
static func from_labels(m: KMesh, kind: String) -> int:
	var lb := face_labels(m, kind)
	if lb.is_empty():
		return -1
	ensure(m)
	var d := PackedFloat32Array()
	d.resize(lb.size())
	var seen := {}
	for fi in lb.size():
		d[fi] = float(maxi(lb[fi], -1) + 2)
		if lb[fi] >= 0:
			seen[lb[fi]] = true
	_put(m, d)
	return seen.size()


## one face-set brush dab: every visible face with a corner among `vids` (weights `w` > 0) joins set `id`; returns the
## faces changed
static func paint(m: KMesh, vids: PackedInt32Array, w: PackedFloat32Array, id: int) -> int:
	ensure(m)
	var d := values(m)
	var n := 0
	for i in vids.size():
		if w[i] <= 0.0:
			continue
		for fi in m.vert_faces(vids[i]):
			if d[fi] > 0.0 and int(d[fi]) != id:
				d[fi] = float(id)
				n += 1
	_put(m, d)
	return n


# ---------------------------------------------------------------- use

## hide (or show) every face of set `id`; returns the faces changed
static func hide(m: KMesh, id: int, on := true) -> int:
	ensure(m)
	var d := values(m)
	var n := 0
	for fi in d.size():
		if absi(int(d[fi])) == id and (d[fi] > 0.0) == on:
			d[fi] = -d[fi]
			n += 1
	_put(m, d)
	return n


static func show_all(m: KMesh) -> int:
	ensure(m)
	var d := values(m)
	var n := 0
	for fi in d.size():
		if d[fi] < 0.0:
			d[fi] = -d[fi]
			n += 1
	_put(m, d)
	return n


## set `id` shown, every other set hidden; returns the faces hidden
static func isolate(m: KMesh, id: int) -> int:
	ensure(m)
	var d := values(m)
	var n := 0
	for fi in d.size():
		var s := absi(int(d[fi]))
		d[fi] = float(s) if s == id else -float(s)
		if s != id:
			n += 1
	_put(m, d)
	return n


## per vert 1 = a sculpt stroke may not move it: a corner of a hidden face, or (only > 0) of a face not in set `only`.
## EMPTY when nothing is frozen
static func frozen(m: KMesh, only := 0) -> PackedByteArray:
	var d := values(m)
	var out := PackedByteArray()
	for fi in d.size():
		if d[fi] < 0.0 or (only > 0 and absi(int(d[fi])) != only):
			if out.is_empty():
				out.resize(m.vert_count())
			for v in (m.faces[fi] as PackedInt32Array):
				out[v] = 1
	return out


## per vert 1 = a corner of a face of set `id`
static func _verts_of(m: KMesh, d: PackedFloat32Array, id: int) -> PackedByteArray:
	var on := PackedByteArray()
	on.resize(m.vert_count())
	for fi in d.size():
		if absi(int(d[fi])) == id:
			for v in (m.faces[fi] as PackedInt32Array):
				on[v] = 1
	return on


## set `id` takes every visible face that shares a vert with it (one ring); returns the faces added
static func grow(m: KMesh, id: int) -> int:
	ensure(m)
	var d := values(m)
	var on := _verts_of(m, d, id)
	var add := PackedInt32Array()
	for fi in d.size():
		if d[fi] < 0.0 or absi(int(d[fi])) == id:
			continue
		for v in (m.faces[fi] as PackedInt32Array):
			if on[v]:
				add.append(fi)
				break
	for fi in add:
		d[fi] = float(id)
	_put(m, d)
	return add.size()


## set `id` gives up every face that shares a vert with a face outside it (one ring); each joins the most common other
## set among its vertex-neighbour faces (ties: the lowest id). Returns the faces removed
static func shrink(m: KMesh, id: int) -> int:
	ensure(m)
	var d := values(m)
	var out_v := PackedByteArray()   # a corner of a face of another set
	out_v.resize(m.vert_count())
	for fi in d.size():
		if absi(int(d[fi])) != id:
			for v in (m.faces[fi] as PackedInt32Array):
				out_v[v] = 1
	var nd := d.duplicate()
	var n := 0
	for fi in d.size():
		if absi(int(d[fi])) != id:
			continue
		var cnt := {}
		for v in (m.faces[fi] as PackedInt32Array):
			if not out_v[v]:
				continue
			for g in m.vert_faces(v):
				var s := absi(int(d[g]))
				if s != id:
					cnt[s] = int(cnt.get(s, 0)) + 1
		if cnt.is_empty():
			continue
		var best := -1
		for s in cnt:
			if best < 0 or cnt[s] > cnt[best] or (cnt[s] == cnt[best] and s < best):
				best = s
		nd[fi] = float(best) * signf(d[fi])
		n += 1
	_put(m, nd)
	return n


## C03: the mask set to 1 on the verts of set `id` (mode "set") or on every vert with a face of another set ("others":
## only the inner verts of the set stay free, as frozen(m, id) leaves them), the higher of that and the old mask kept;
## returns the verts that are 1 now because of it
static func mask_from(m: KMesh, id: int, mode := "set") -> int:
	KMeshMask.ensure(m)
	var on := _verts_of(m, values(m), id) if mode == "set" else frozen(m, id)
	var mk := KMeshMask.values(m).duplicate()
	var n := 0
	for v in mk.size():
		var want := on.size() > v and on[v] == 1
		if want:
			if mk[v] < 1.0:
				n += 1
			mk[v] = 1.0
	m.set_attr_data(KMeshMask.NAME, mk)
	return n


# ---------------------------------------------------------------- show

## a stable colour per id: golden-angle hues, two saturation steps; set 1 (the default) is clear (not drawn)
static func colour_of(id: int) -> Color:
	if id == DEFAULT:
		return Color(1, 1, 1, 0)
	var h := fposmod(float(id) * 0.618033988749895, 1.0)
	return Color.from_hsv(h, 0.55 if id % 2 == 0 else 0.75, 0.95)


## the colour layer as triangles (Godot's clockwise winding), pushed `off` out along the vertex normals: each visible face
## of a set other than 1, flat in its set's colour with alpha `alpha`. Empty arrays when there is nothing to draw.
static func tint_arrays(m: KMesh, off := 0.0012, alpha := 0.5) -> Array:
	var d := values(m)
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var vs := m.verts
	var vn := m.vert_normals
	for fi in d.size():
		var s := int(d[fi])
		if s <= DEFAULT:   # hidden (< 0) or the default set
			continue
		var c := colour_of(s)
		c.a = alpha
		var fp: PackedInt32Array = m.faces[fi]
		for i in range(1, fp.size() - 1):
			for k in [0, i + 1, i]:
				var v: int = fp[k]
				pos.append(vs[v] + vn[v] * off)
				col.append(c)
	return [pos, col]
