class_name KMeshMask
extends RefCounted
## Sculpt masking (ROADMAP_400 C03). The mask is a 0..1 value per vertex kept as the A09 attribute channel "mask" (vert
## domain, float), so it is saved with the mesh (KMesh.to_dict) and taken back by KMeshUndo like any channel.
## 1 = frozen: every sculpt brush's displacement of a vert is multiplied by (1 - mask) (KMeshSculpt._keep), grab too.
##   paint (the "mask" brush of KMeshSculpt): each dab adds amount * falloff * pressure (erase: takes it away), clamped
##   invert: m -> 1 - m        clear: every m -> 0
##   blur: each vert takes the mean of itself and its edge neighbours (one pass, Jacobi: all read the old values)
##   cavity: concave verts by the mean-curvature sign. L = mean(neighbours) - v; c = L . n / (mean edge length): a vert in
##     a pit or the bottom of a groove has its neighbours above it along its normal (c > 0). mask = 1 where c > threshold,
##     0 elsewhere (a flat area has c = 0, a ridge or a sphere c < 0)
## Pure, no nodes; the tint that draws it on the mesh is KMeshMaskTint (scripts/kmesh_mask_tint.gd).

const NAME := "mask"
const CAVITY_THRESHOLD := 0.02


## the mask channel, made (all 0) if the mesh has none; true when it is there
static func ensure(m: KMesh) -> bool:
	if m.has_attr(NAME):
		return true
	return m.add_attr(NAME, KMesh.AD_VERT, TYPE_FLOAT, 0.0)


## the mask values (a copy-on-write reference), or an empty array when the mesh has no mask
static func values(m: KMesh) -> PackedFloat32Array:
	if m == null or not m.has_attr(NAME) or m.attr_info(NAME).get("domain", "") != KMesh.AD_VERT:
		return PackedFloat32Array()
	return m.attr_data(NAME)


static func _put(m: KMesh, d: PackedFloat32Array) -> void:
	ensure(m)
	m.set_attr_data(NAME, d)


static func fill(m: KMesh, value: float) -> void:
	var d := PackedFloat32Array()
	d.resize(m.vert_count())
	d.fill(clampf(value, 0.0, 1.0))
	_put(m, d)


static func clear(m: KMesh) -> void:
	fill(m, 0.0)


static func invert(m: KMesh) -> void:
	ensure(m)
	var d := values(m)
	for v in d.size():
		d[v] = 1.0 - d[v]
	_put(m, d)


## `passes` rounds of the neighbour mean
static func blur(m: KMesh, passes := 1) -> void:
	ensure(m)
	var d := values(m)
	for k in passes:
		var o := d.duplicate()
		for v in d.size():
			var nb := m.vert_neighbors(v)
			var s := o[v]
			for u in nb:
				s += o[u]
			d[v] = s / (nb.size() + 1)
	_put(m, d)


## the signed curvature of each vert (> 0 concave), see the header
static func cavity(m: KMesh) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(m.vert_count())
	var vs := m.verts
	var vn := m.vert_normals
	for v in vs.size():
		var nb := m.vert_neighbors(v)
		if nb.is_empty():
			continue
		var mean := Vector3.ZERO
		var el := 0.0
		for u in nb:
			mean += vs[u]
			el += vs[u].distance_to(vs[v])
		el /= nb.size()
		if el < 1e-12:
			continue
		out[v] = (mean / nb.size() - vs[v]).dot(vn[v]) / el
	return out


## mask = 1 on the concave verts (curvature above `threshold`), 0 elsewhere; returns how many were masked
static func by_cavity(m: KMesh, threshold := CAVITY_THRESHOLD) -> int:
	var c := cavity(m)
	var d := PackedFloat32Array()
	d.resize(c.size())
	var n := 0
	for v in c.size():
		if c[v] > threshold:
			d[v] = 1.0
			n += 1
	_put(m, d)
	return n


## one paint dab: verts `ids` with falloff weights `w`; amount * w * pressure is added (sgn -1 erases)
static func paint(m: KMesh, ids: PackedInt32Array, w: PackedFloat32Array, amount: float, sgn: float) -> int:
	ensure(m)
	var d := values(m)
	var n := 0
	for i in ids.size():
		var v := ids[i]
		var nv := clampf(d[v] + sgn * amount * w[i], 0.0, 1.0)
		if nv != d[v]:
			d[v] = nv
			n += 1
	_put(m, d)
	return n


## the dark tint as triangles (Godot's clockwise winding), pushed `off` out along the vertex normals, black with alpha
## alpha_max * mask per corner; only the faces with a masked corner. Empty arrays when nothing is masked.
static func tint_arrays(m: KMesh, off := 0.0015, alpha_max := 0.7) -> Array:
	var d := values(m)
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	if d.is_empty():
		return [pos, col]
	var vs := m.verts
	var vn := m.vert_normals
	var hid := KMeshFaceSets.hidden_faces(m)   # C09: no shade on a hidden face set
	for fi in m.face_count():
		if not hid.is_empty() and hid[fi]:
			continue
		var fp: PackedInt32Array = m.faces[fi]
		var any := false
		for v in fp:
			if d[v] > 0.001:
				any = true
				break
		if not any:
			continue
		for i in range(1, fp.size() - 1):
			for c in [0, i + 1, i]:
				var v: int = fp[c]
				pos.append(vs[v] + vn[v] * off)
				col.append(Color(0.0, 0.0, 0.0, alpha_max * d[v]))
	return [pos, col]
