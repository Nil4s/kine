class_name KMeshTopo
extends RefCounted
## F06 + F08 (docs/ROADMAP_400.md): triangulate / quadrangulate a KMesh, and grade its topology (the heat map).
## TRIANGULATE: a face of n corners becomes n - 2 triangles, wound like the face. Quads: by the shorter diagonal ("beauty",
##   the one that keeps both halves on the face; a concave quad has only one), else from corner 0. A convex n-gon: a fan from
##   corner 0. A concave n-gon: ear clipping in the face's plane (Newell normal), so no triangle lands outside the face.
## QUADRANGULATE ("tris to quads"): every pair of triangles across an edge is a candidate quad; it is kept only when the
##   two are near coplanar (the angle between their normals <= face_limit), the quad is convex and no corner is more than
##   shape_limit off 90 degrees, and (seams on) the corner / face attributes agree across the shared edge (a UV seam or a
##   material border stays). Candidates are joined greedily, best first (error = normal angle / face_limit + worst corner
##   deviation / shape_limit), each triangle at most once.
## Both carry the A09 attributes: a new corner takes its source corner's value, a new face its source face's, an edge
##   that existed keeps its value and a new diagonal takes the default; custom split normals ride with their corners.
## HEAT: per vertex, a pole = an interior vertex with 3 or fewer edges ("pole 3"), 5 ("pole 5") or 6 and more ("pole 6+");
##   a boundary vertex counts one edge more (3 edges on an open border is the regular case). Per face: triangle, n-gon,
##   stretched quad (opposite sides' mean length ratio > ASPECT_MAX, or a corner more than SKEW_MAX off 90 degrees).

const FACE_LIMIT := 40.0   # deg, as Blender's tris-to-quads default
const SHAPE_LIMIT := 40.0  # deg
const ASPECT_MAX := 3.0    # a quad 3 times longer than it is wide is stretched
const SKEW_MAX := 30.0     # deg off square
const EPS := 1e-12

const V_OK := 0
const V_POLE3 := 1
const V_POLE5 := 2
const V_POLE6 := 3
const F_QUAD := 0
const F_TRI := 1
const F_NGON := 2
const F_STRETCH := 3

## legend order: [key, name, words, colour] (fixed hues, readable on both palettes; the face ones are drawn as a tint)
const LEGEND := [
	["pole3", "pole 3", "3 or fewer edges at a vertex", Color(0.25, 0.55, 1.0)],
	["pole5", "pole 5", "5 edges at a vertex", Color(1.0, 0.55, 0.1)],
	["pole6", "pole 6+", "6 or more edges at a vertex", Color(0.95, 0.15, 0.2)],
	["tri", "triangle", "3-sided face", Color(1.0, 0.85, 0.15)],
	["ngon", "n-gon", "5 or more sides", Color(0.8, 0.3, 0.95)],
	["stretch", "stretched quad", "long, thin or skewed", Color(0.15, 0.85, 0.8)],
]
const V_KEY := ["", "pole3", "pole5", "pole6"]
const F_KEY := ["", "tri", "ngon", "stretch"]


static func color_of(key: String) -> Color:
	for r in LEGEND:
		if r[0] == key:
			return r[3]
	return Color.WHITE


# ---------------------------------------------------------------- plane helpers

## the face's corners in its own plane (u, v axes perpendicular to the Newell normal); CCW from outside = positive area
static func _plane2d(m: KMesh, f: PackedInt32Array) -> PackedVector2Array:
	var n := Vector3.ZERO
	for i in f.size():
		var a: Vector3 = m.verts[f[i]]
		var b: Vector3 = m.verts[f[(i + 1) % f.size()]]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if n.length_squared() < EPS:
		n = Vector3.UP
	n = n.normalized()
	var u := (Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP).cross(n).normalized()
	var v := n.cross(u)
	var out := PackedVector2Array()
	for i in f.size():
		var p: Vector3 = m.verts[f[i]]
		out.append(Vector2(p.dot(u), p.dot(v)))
	return out


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).cross(b - o)


static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	# inside or on the border of the CCW triangle abc
	return _cross2(a, b, p) >= -1e-12 and _cross2(b, c, p) >= -1e-12 and _cross2(c, a, p) >= -1e-12


## triangles of one face as local corner triples [i, j, k] (each CCW like the face)
static func face_tris(m: KMesh, f: PackedInt32Array, beauty := true) -> Array:
	var n := f.size()
	if n < 3:
		return []
	if n == 3:
		return [[0, 1, 2]]
	var p := _plane2d(m, f)
	var scale := 0.0
	for q in p:
		scale = maxf(scale, (q - p[0]).length_squared())
	var tiny := scale * 1e-12
	if n == 4:
		var ok02 := _cross2(p[0], p[1], p[2]) > tiny and _cross2(p[0], p[2], p[3]) > tiny
		var ok13 := _cross2(p[0], p[1], p[3]) > tiny and _cross2(p[1], p[2], p[3]) > tiny
		var d02: float = (m.verts[f[0]] as Vector3).distance_to(m.verts[f[2]])
		var d13: float = (m.verts[f[1]] as Vector3).distance_to(m.verts[f[3]])
		var use13 := (ok13 and not ok02) or (ok13 and beauty and d13 < d02 - 1e-12)
		return [[0, 1, 3], [1, 2, 3]] if use13 else [[0, 1, 2], [0, 2, 3]]
	var convex := true
	for i in n:
		if _cross2(p[(i + n - 1) % n], p[i], p[(i + 1) % n]) < -tiny:
			convex = false
			break
	var out := []
	if convex:
		for i in range(1, n - 1):
			out.append([0, i, i + 1])
		return out
	# ear clipping
	var idx: Array = range(n)
	var guard := n * n
	while idx.size() > 3 and guard > 0:
		guard -= 1
		var k := idx.size()
		var cut := -1
		for t in k:
			var ia: int = idx[(t + k - 1) % k]
			var ib: int = idx[t]
			var ic: int = idx[(t + 1) % k]
			if _cross2(p[ia], p[ib], p[ic]) <= tiny:
				continue
			var empty := true
			for o in idx:
				if o != ia and o != ib and o != ic and p[o] != p[ia] and p[o] != p[ib] and p[o] != p[ic] and _in_tri(p[o], p[ia], p[ib], p[ic]):
					empty = false
					break
			if empty:
				cut = t
				break
		if cut < 0:
			cut = 0   # degenerate (self-touching or zero area): clip anyway so the face still closes
		out.append([idx[(cut + k - 1) % k], idx[cut], idx[(cut + 1) % k]])
		idx.remove_at(cut)
	if idx.size() == 3:
		out.append([idx[0], idx[1], idx[2]])
	return out


# ---------------------------------------------------------------- rebuild with attributes

static func _edge_map(m: KMesh) -> Dictionary:
	var nv := m.verts.size()
	var out := {}
	var es: Array = m.edges()
	for i in es.size():
		out[(es[i] as Vector2i).x * nv + (es[i] as Vector2i).y] = i
	return out


## replace the faces: nf[i] = new face, fsrc[i] = its old face, csrc = the old corner of each new corner (flat, in order)
static func _apply(m: KMesh, nf: Array, fsrc: PackedInt32Array, csrc: PackedInt32Array) -> void:
	var has_a := not m.attrs.is_empty()
	var old_e := _edge_map(m) if has_a else {}
	var cn_old: Array = m.custom_normals
	var cflat := PackedVector3Array()
	if not cn_old.is_empty():
		for c in cn_old:
			cflat.append_array(c as PackedVector3Array)
	var saved := m.attrs
	m.attrs = {}
	m.faces = nf
	m.rebuild()
	if not cn_old.is_empty() and cflat.size() > 0:
		var cn := []
		var at := 0
		for f in nf:
			var row := PackedVector3Array()
			for _i in (f as PackedInt32Array).size():
				row.append(cflat[csrc[at]] if csrc[at] >= 0 and csrc[at] < cflat.size() else Vector3.ZERO)
				at += 1
			cn.append(row)
		m.custom_normals = cn
	if has_a:
		var nv := m.verts.size()
		var esrc := PackedInt32Array()
		for e in m.edges():
			esrc.append(old_e.get((e as Vector2i).x * nv + (e as Vector2i).y, -1))
		m.attrs = saved
		m.attr_remap(null, fsrc, csrc, esrc)


static func _corner_base(m: KMesh) -> PackedInt32Array:
	var b := PackedInt32Array()
	var c := 0
	for f in m.faces:
		b.append(c)
		c += (f as PackedInt32Array).size()
	return b


## Triangulate `only` (face ids; null = every face). Returns {"faces": faces split, "tris": triangles made}.
static func triangulate(m: KMesh, only = null, beauty := true) -> Dictionary:
	var pick := {}
	if only != null:
		for fi in only:
			pick[int(fi)] = true
	var base := _corner_base(m)
	var nf := []
	var fsrc := PackedInt32Array()
	var csrc := PackedInt32Array()
	var split := 0
	var made := 0
	for fi in m.faces.size():
		var f: PackedInt32Array = m.faces[fi]
		if f.size() <= 3 or (only != null and not pick.has(fi)):
			nf.append(f)
			fsrc.append(fi)
			for i in f.size():
				csrc.append(base[fi] + i)
			continue
		split += 1
		for t in face_tris(m, f, beauty):
			nf.append(PackedInt32Array([f[t[0]], f[t[1]], f[t[2]]]))
			fsrc.append(fi)
			for c in t:
				csrc.append(base[fi] + int(c))
			made += 1
	if split > 0:
		_apply(m, nf, fsrc, csrc)
	return {"faces": split, "tris": made}


static func _corner_deg(a: Vector3, b: Vector3, c: Vector3) -> float:
	# the angle at b of the corner a-b-c
	var u := a - b
	var v := c - b
	if u.length_squared() < EPS or v.length_squared() < EPS:
		return 0.0
	return rad_to_deg(u.angle_to(v))


static func _attrs_agree(m: KMesh, ca: int, cb: int, dom: String) -> bool:
	for k in m.attrs:
		var r: Dictionary = m.attrs[k]
		if r["domain"] != dom:
			continue
		var d = r["data"]
		if ca < d.size() and cb < d.size() and d[ca] != d[cb]:
			return false
	return true


## Join triangle pairs into quads (`only` = face ids allowed to join; null = every triangle).
## Returns {"quads": quads made, "left": triangles left}.
static func quadrangulate(m: KMesh, only = null, face_limit := FACE_LIMIT, shape_limit := SHAPE_LIMIT, seams := true) -> Dictionary:
	var pick := {}
	for fi in m.faces.size():
		if (m.faces[fi] as PackedInt32Array).size() == 3:
			pick[fi] = true
	if only != null:
		var keep := {}
		for fi in only:
			if pick.has(int(fi)):
				keep[int(fi)] = true
		pick = keep
	var base := _corner_base(m)
	var cands := []
	var he0 := m.face_he0
	var tw := m.he_twin
	var hf := m.he_face
	var fn := m.face_normals
	for fi in pick:
		var A: PackedInt32Array = m.faces[fi]
		for i in 3:
			var t: int = tw[he0[fi] + i]
			if t < 0:
				continue
			var gi: int = hf[t]
			if gi <= fi or not pick.has(gi):
				continue
			var j: int = t - he0[gi]   # B's corner at b (the twin runs b -> a)
			var B: PackedInt32Array = m.faces[gi]
			var a := A[i]
			var b := A[(i + 1) % 3]
			if B[j] != b or B[(j + 1) % 3] != a:
				continue
			var quad := PackedInt32Array([b, A[(i + 2) % 3], a, B[(j + 2) % 3]])
			var qc := PackedInt32Array([base[fi] + (i + 1) % 3, base[fi] + (i + 2) % 3, base[fi] + i, base[gi] + (j + 2) % 3])
			if quad[1] == quad[3]:
				continue
			var ang := rad_to_deg((fn[fi] as Vector3).angle_to(fn[gi]))
			if ang > face_limit:
				continue
			if seams and not (_attrs_agree(m, base[fi] + i, base[gi] + (j + 1) % 3, KMesh.AD_CORNER) and _attrs_agree(m, base[fi] + (i + 1) % 3, base[gi] + j, KMesh.AD_CORNER) and _attrs_agree(m, fi, gi, KMesh.AD_FACE)):
				continue
			var p2 := _plane2d(m, quad)
			var convex := true
			var dev := 0.0
			for k in 4:
				if _cross2(p2[(k + 3) % 4], p2[k], p2[(k + 1) % 4]) <= 0.0:
					convex = false
				dev = maxf(dev, absf(_corner_deg(m.verts[quad[(k + 3) % 4]], m.verts[quad[k]], m.verts[quad[(k + 1) % 4]]) - 90.0))
			if not convex or dev > shape_limit:
				continue
			cands.append([ang / maxf(face_limit, 1e-6) + dev / maxf(shape_limit, 1e-6), fi, gi, quad, qc])
	cands.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and (x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]))))
	var used := {}
	var joined := {}   # the lower face id -> [quad, corners]; the higher is dropped
	for c in cands:
		if used.has(c[1]) or used.has(c[2]):
			continue
		used[c[1]] = true
		used[c[2]] = true
		joined[c[1]] = [c[3], c[4]]
	if joined.is_empty():
		return {"quads": 0, "left": pick.size()}
	var nf := []
	var fsrc := PackedInt32Array()
	var csrc := PackedInt32Array()
	for fi in m.faces.size():
		if joined.has(fi):
			nf.append(joined[fi][0])
			fsrc.append(fi)
			csrc.append_array(joined[fi][1])
		elif used.has(fi):
			continue
		else:
			var f: PackedInt32Array = m.faces[fi]
			nf.append(f)
			fsrc.append(fi)
			for i in f.size():
				csrc.append(base[fi] + i)
	_apply(m, nf, fsrc, csrc)
	return {"quads": joined.size(), "left": pick.size() - used.size()}


# ---------------------------------------------------------------- heat

## {"vert": PackedInt32Array (V_*), "face": PackedInt32Array (F_*), "valence": PackedInt32Array, "counts": {key: n}}
static func heat(m: KMesh, aspect_max := ASPECT_MAX, skew_max := SKEW_MAX) -> Dictionary:
	var nv := m.verts.size()
	var val := PackedInt32Array()
	val.resize(nv)
	var bnd := PackedByteArray()
	bnd.resize(nv)
	var tw := m.he_twin
	var hv := m.he_vert
	var hn := m.he_next
	for h in tw.size():
		var a: int = hv[h]
		var b: int = hv[hn[h]]
		if a == b:
			continue
		if tw[h] < 0:
			bnd[a] = 1
			bnd[b] = 1
			val[a] += 1
			val[b] += 1
		elif h < tw[h]:
			val[a] += 1
			val[b] += 1
	var vk := PackedInt32Array()
	vk.resize(nv)
	var counts := {}
	for r in LEGEND:
		counts[r[0]] = 0
	for v in nv:
		var e: int = val[v] + (1 if bnd[v] == 1 else 0)
		var k := V_OK
		if val[v] == 0 or (bnd[v] == 1 and val[v] == 2):
			k = V_OK   # loose, or an open corner
		elif e <= 3:
			k = V_POLE3
		elif e == 5:
			k = V_POLE5
		elif e >= 6:
			k = V_POLE6
		vk[v] = k
		if k != V_OK:
			counts[V_KEY[k]] += 1
	var fk := PackedInt32Array()
	fk.resize(m.faces.size())
	for fi in m.faces.size():
		var f: PackedInt32Array = m.faces[fi]
		var k := F_QUAD
		if f.size() == 3:
			k = F_TRI
		elif f.size() >= 5:
			k = F_NGON
		elif f.size() == 4 and quad_stretch(m, f) > 0.0:
			var q := quad_shape(m, f)
			if q.x > aspect_max or q.y > skew_max:
				k = F_STRETCH
		fk[fi] = k
		if k != F_QUAD:
			counts[F_KEY[k]] += 1
	return {"vert": vk, "face": fk, "valence": val, "counts": counts}


## (aspect ratio of opposite sides' means, worst corner deviation from 90 deg)
static func quad_shape(m: KMesh, f: PackedInt32Array) -> Vector2:
	var p: Array = []
	for v in f:
		p.append(m.verts[v])
	var s0: float = ((p[0] as Vector3).distance_to(p[1]) + (p[2] as Vector3).distance_to(p[3])) * 0.5
	var s1: float = ((p[1] as Vector3).distance_to(p[2]) + (p[3] as Vector3).distance_to(p[0])) * 0.5
	var asp := maxf(s0, s1) / maxf(minf(s0, s1), 1e-12)
	var dev := 0.0
	for k in 4:
		dev = maxf(dev, absf(_corner_deg(p[(k + 3) % 4], p[k], p[(k + 1) % 4]) - 90.0))
	return Vector2(asp, dev)


## > 0 for a quad with any size at all (a zero-size quad is degenerate: KMeshValidate's business, not the heat map's)
static func quad_stretch(m: KMesh, f: PackedInt32Array) -> float:
	var s := 0.0
	for i in 4:
		s += (m.verts[f[i]] as Vector3).distance_to(m.verts[f[(i + 1) % 4]])
	return s


## one line for the status bar: what the heat map found
static func words(h: Dictionary) -> String:
	var c: Dictionary = h["counts"]
	var bits := []
	for r in LEGEND:
		if int(c[r[0]]) > 0:
			bits.append("%s x%d" % [r[1], int(c[r[0]])])
	if bits.is_empty():
		return "clean topology: all quads, every vertex has 4 edges"
	return ", ".join(bits)
