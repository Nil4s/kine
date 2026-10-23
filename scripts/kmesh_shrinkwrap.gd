class_name KMeshShrinkwrap
extends RefCounted
## B13 (docs/ROADMAP_400.md): SHRINKWRAP / PROJECT ONTO THE BODY. Moves a KMesh's vertices onto a TARGET surface, then
## `offset` metres along the target's OUTWARD normal there (+ = outside, - = sunk in). Three modes:
##   nearest  each vertex goes to the nearest point of the target surface (Blender's "Nearest Surface Point")
##   normal   each vertex is cast along its own vertex normal, both ways (or only out / only in), the nearest hit wins
##   axis     each vertex is cast along one direction (X / Y / Z or the view), both ways (or one), the nearest hit wins
## max_dist (m, 0 = no limit): a vertex whose surface point / hit is further than this is NOT moved (bit for bit).
## INFLUENCE: the selection (a list of vertices; empty = all) times an optional vertex float channel (A09) clamped 0..1:
##   the new position is old.lerp(wrapped, w); w = 0 leaves the vertex untouched (bit for bit).
## THE TARGET is any KMesh (n-gons fanned into triangles) with a transform into the wrapped mesh's space, held in a BVH
## (median-of-extent splits, LEAF triangles a leaf; the query walks near child first and prunes by box distance), so a
## 5k-vertex nearest wrap onto the 14k-triangle body is ~1 s in GDScript, most of it the parity checks of _settle()
## (tests/shrinkwrap_test.gd times it). The first body target of a skin generation costs ~3 s (the buried mask, once).
## THE BODY TARGET (body()): the fighter's G01 skin (BaseBody.read: the welded mannequin with its "skin:" weight channels)
## skinned by LBS at the skeleton's CURRENT pose (DqSkin.bind_mats: bone global pose x bind pose), in the body mesh's
## own space; cached by (skin generation, pose, placement), so a modifier re-evaluated on every edit rebuilds nothing.
## OUTSIDE IS OUTSIDE: the mannequin's file winds its faces INWARD (its signed volume is negative: A19 / H04 found it), so a
## triangle's own normal cannot be trusted. Every connected part of the target gets its winding from its signed volume
## (about the part's centroid) and its normals are turned to point out of it; the smooth normal at a surface point is the
## corner normals (area-weighted, oriented) mixed by the point's barycentric weights. tests/shrinkwrap_test.gd checks the
## result against a ray parity test (an odd number of crossings = inside) and against the bone axes, not against these
## normals. crossings() is that parity count, for B23 and the tests.
## THE SKIN IS THE UNION of the parts: the mannequin is 61 closed parts that overlap (fingers into the palm, the arms into
## the chest). A triangle inside another part (parity) is BURIED and left out of the wrap target; one with a corner inside
## is PARTIAL and a landing near it is checked; see _settle(). NEAREST + offset in a crease: the point offset from the
## nearest surface point can lie nearer ANOTHER face (armpit, between fingers); `refine` passes (default 6) re-take the
## nearest skin point from where the vertex landed and keep the landing whose true distance is closest to |offset|.
## Ops: mesh_tools "op:shrinkwrap" (nearest +4 mm onto the body, the selection, ONE undo step), "op:shrinkwrap_view"
## (project along the view), "op:shrinkwrap_target" (this mesh becomes the "other" target), "op:shrinkwrap_other" (wrap
## onto it); the A11 modifier "shrinkwrap" (kmesh_modifiers.gd) runs evaluate_mod() non-destructively. Known limit: the
## modifier panel re-evaluates on a mesh / stack change, not on a pose change (the pose is fixed while modeling).

const MODES := ["nearest", "normal", "axis"]
const DIRS := ["both", "out", "in"]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const LEAF := 4
const FAR := 1000.0   # m: "no limit" for a cast
const OFFSET_DEFAULT := 0.004   # m: B23's armour offset

## message of the last failed call (empty after a success); each names a next step
static var last_error := ""

# ---- the target, triangles in leaf order
var tp := PackedVector3Array()   # 3 corners per triangle (wrapped mesh's space)
var tcn := PackedVector3Array()  # 3 outward smooth corner normals per triangle
var tn := PackedVector3Array()   # the outward unit normal per triangle
var tsrc := PackedInt32Array()   # the source triangle of each (fan order over the target's faces)
var parts := 0                   # connected parts of the target
var flipped := 0                 # parts whose winding was inward (their normals turned)
var flipped_tris := 0
var tpart := PackedInt32Array()  # the connected part of each triangle
var buried := PackedByteArray()  # per source triangle: 1 = inside another part (left out of the wrap target), 2 = partly
var tpartial := PackedByteArray()  # per triangle (leaf order): 1 = a corner inside another part: a landing is checked
var full: KMeshShrinkwrap        # the uncut target when triangles were left out (the parity test needs every part)
# ---- the BVH (node arrays; a leaf has count > 0)
var bmin := PackedVector3Array()
var bmax := PackedVector3Array()
var bleft := PackedInt32Array()   # an inner node's two children
var bright := PackedInt32Array()
var bstart := PackedInt32Array()
var bcount := PackedInt32Array()
var build_ms := 0.0


# ---------------------------------------------------------------- building a target

## a target from a KMesh: xf maps its space into the space of the mesh that will be wrapped
## cull: leave out the buried triangles (see below); buried: a mask from an earlier build of the same triangles (per
## source triangle, 1 = buried) to skip finding them again (the body reuses its rest-pose mask at every pose)
static func build(target: KMesh, xf := Transform3D.IDENTITY, cull := true, buried := PackedByteArray()) -> KMeshShrinkwrap:
	var t0 := Time.get_ticks_usec()
	var sw := KMeshShrinkwrap.new()
	var nv := target.verts.size()
	var P := PackedVector3Array()
	P.resize(nv)
	for i in nv:
		P[i] = xf * target.verts[i]
	var tri := PackedInt32Array()
	for f in target.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			tri.append_array([fp[0], fp[i], fp[i + 1]])
	var nt := tri.size() / 3
	# connected parts (union-find over the corners), each part's signed volume about its centroid
	var up := PackedInt32Array()
	up.resize(nv)
	for i in nv:
		up[i] = i
	for k in nt:
		var a := _root(up, tri[k * 3])
		for c in [1, 2]:
			var b := _root(up, tri[k * 3 + c])
			if a != b:
				up[b] = a
	var part_of := {}
	var cen := []
	var cnt := []
	for i in nv:
		var r := _root(up, i)
		if not part_of.has(r):
			part_of[r] = cen.size()
			cen.append(Vector3.ZERO)
			cnt.append(0)
		var pi: int = part_of[r]
		cen[pi] += P[i]
		cnt[pi] += 1
	for pi in cen.size():
		cen[pi] /= maxf(1.0, float(cnt[pi]))
	var vol := PackedFloat64Array()
	vol.resize(cen.size())
	var used := {}
	for k in nt:
		var pi: int = part_of[_root(up, tri[k * 3])]
		used[pi] = true
		var o: Vector3 = cen[pi]
		var a := P[tri[k * 3]] - o
		vol[pi] += a.dot((P[tri[k * 3 + 1]] - o).cross(P[tri[k * 3 + 2]] - o))
	sw.parts = used.size()
	var sgn := PackedFloat32Array()
	sgn.resize(cen.size())
	for pi in cen.size():
		sgn[pi] = -1.0 if vol[pi] < 0.0 else 1.0
		if vol[pi] < 0.0 and used.has(pi):
			sw.flipped += 1
	# oriented triangle normals, area-weighted vertex normals
	var fnrm := PackedVector3Array()
	fnrm.resize(nt)
	var vnrm := PackedVector3Array()
	vnrm.resize(nv)
	for k in nt:
		var a := P[tri[k * 3]]
		var cr := (P[tri[k * 3 + 1]] - a).cross(P[tri[k * 3 + 2]] - a) * sgn[part_of[_root(up, tri[k * 3])]]
		if sgn[part_of[_root(up, tri[k * 3])]] < 0.0:
			sw.flipped_tris += 1
		fnrm[k] = cr.normalized()
		for c in 3:
			vnrm[tri[k * 3 + c]] += cr
	for i in nv:
		vnrm[i] = vnrm[i].normalized()
	var tpart := PackedInt32Array()
	tpart.resize(nt)
	for k in nt:
		tpart[k] = part_of[_root(up, tri[k * 3])]
	var all := PackedInt32Array()
	all.resize(nt)
	for k in nt:
		all[k] = k
	sw._fill(P, tri, fnrm, vnrm, tpart, all)
	# BURIED triangles: a part's triangle inside ANOTHER part (a finger root inside the palm) is not skin anyone sees;
	# wrapping onto it would put the vertex inside the body. They are left out of the wrap target (kept for parity)
	if cull and sw.parts > 1:
		if buried.size() != nt:
			buried = PackedByteArray()
			buried.resize(nt)
			for j in nt:
				var k := sw.tsrc[j]
				var c := (sw.tp[j * 3] + sw.tp[j * 3 + 1] + sw.tp[j * 3 + 2]) / 3.0 + sw.tn[j] * 1e-4
				if sw.inside(c, sw.tpart[j]):
					buried[k] = 1
			var vin := {}   # PARTIAL: a kept triangle with a corner inside another part (where an arm enters the chest)
			for j in nt:
				var k := sw.tsrc[j]
				if buried[k] == 1:
					continue
				for cc in 3:
					var vi := tri[k * 3 + cc]
					if not vin.has(vi):
						vin[vi] = sw.inside(P[vi] + vnrm[vi] * 1e-4, sw.tpart[j])
					if vin[vi]:
						buried[k] = 2
		for j in nt:
			sw.tpartial[j] = 1 if buried[sw.tsrc[j]] != 0 else 0   # the full target: a landing near any of them is checked
		var keep := PackedInt32Array()
		for k in nt:
			if buried[k] != 1:
				keep.append(k)
		if keep.size() < nt and keep.size() > 0:
			var cut := KMeshShrinkwrap.new()
			cut.parts = sw.parts
			cut.flipped = sw.flipped
			cut.flipped_tris = sw.flipped_tris
			cut.full = sw
			cut.buried = buried
			cut._fill(P, tri, fnrm, vnrm, tpart, keep)
			sw = cut
	sw.buried = buried
	sw.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return sw


## the BVH over the triangles `ids` (source numbering) and the triangle arrays in leaf order
func _fill(P: PackedVector3Array, tri: PackedInt32Array, fnrm: PackedVector3Array, vnrm: PackedVector3Array, tpart_src: PackedInt32Array, ids: PackedInt32Array) -> void:
	var nt := tri.size() / 3
	var cx := PackedVector3Array()
	cx.resize(nt)
	for k in ids:
		cx[k] = (P[tri[k * 3]] + P[tri[k * 3 + 1]] + P[tri[k * 3 + 2]]) / 3.0
	ids = ids.duplicate()
	_bvh(ids, cx, P, tri)
	var n := ids.size()
	tp.resize(n * 3)
	tcn.resize(n * 3)
	tn.resize(n)
	tpart.resize(n)
	tpartial.resize(n)
	tsrc = ids
	for j in n:
		var k := ids[j]
		tn[j] = fnrm[k]
		tpart[j] = tpart_src[k]
		tpartial[j] = 1 if buried.size() > k and buried[k] == 2 else 0
		for c in 3:
			tp[j * 3 + c] = P[tri[k * 3 + c]]
			var vn := vnrm[tri[k * 3 + c]]
			tcn[j * 3 + c] = vn if vn != Vector3.ZERO else fnrm[k]


static func _root(up: PackedInt32Array, i: int) -> int:
	while up[i] != i:
		up[i] = up[up[i]]
		i = up[i]
	return i


## builds the node arrays; reorders ids so every leaf is a run [start, start + count)
func _bvh(ids: PackedInt32Array, cx: PackedVector3Array, P: PackedVector3Array, tri: PackedInt32Array) -> void:
	var stack := [[0, ids.size(), -1, false]]   # [start, end, parent, is_right]
	while not stack.is_empty():
		var job: Array = stack.pop_back()
		var s: int = job[0]
		var e: int = job[1]
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var clo := Vector3.INF
		var chi := -Vector3.INF
		for j in range(s, e):
			var k := ids[j]
			for c in 3:
				lo = lo.min(P[tri[k * 3 + c]])
				hi = hi.max(P[tri[k * 3 + c]])
			clo = clo.min(cx[k])
			chi = chi.max(cx[k])
		var node := bmin.size()
		bmin.append(lo)
		bmax.append(hi)
		bleft.append(-1)
		bright.append(-1)
		bstart.append(s)
		bcount.append(0)
		if job[2] >= 0:
			if job[3]:
				bright[job[2]] = node
			else:
				bleft[job[2]] = node
		var n := e - s
		if n <= LEAF:
			bcount[node] = n
			continue
		var ext := chi - clo
		var ax := 0 if ext.x >= ext.y and ext.x >= ext.z else (1 if ext.y >= ext.z else 2)
		var mid := (clo[ax] + chi[ax]) * 0.5
		var i := s
		var j2 := e - 1
		while i <= j2:   # partition about the middle of the centroids' extent
			if cx[ids[i]][ax] < mid:
				i += 1
			else:
				var t := ids[i]
				ids[i] = ids[j2]
				ids[j2] = t
				j2 -= 1
		if i == s or i == e:   # every centroid on one side (equal centroids): split the run in half
			i = s + n / 2
		stack.append([i, e, node, true])
		stack.append([s, i, node, false])


func tri_count() -> int:
	return tn.size()


# ---------------------------------------------------------------- queries

## closest point on triangle (a, b, c) to p as barycentric weights (Ericson, Real-Time Collision Detection 5.1.5)
static func closest_bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1, 0, 0)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return Vector3(1.0 - v, v, 0)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return Vector3(1.0 - w, 0, w)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1.0 - w, w)
	var den := va + vb + vc
	if absf(den) < 1e-30:
		return Vector3(1, 0, 0)
	var v := vb / den
	var w := vc / den
	return Vector3(1.0 - v - w, v, w)


## the nearest surface point to p: {"t": triangle (leaf order), "b": barycentric, "p": point, "d": distance}; {} when
## nothing is within max_d (0 = no limit). hint: a triangle to try first (a neighbour's answer: a tight start bound);
## only_part >= 0: that connected part's triangles alone
func nearest(p: Vector3, max_d := 0.0, hint := -1, only_part := -1) -> Dictionary:
	var best := INF if max_d <= 0.0 else max_d * max_d
	var bt := -1
	var bb := Vector3.ZERO
	if hint >= 0 and (only_part < 0 or tpart[hint] == only_part):
		var ba := closest_bary(p, tp[hint * 3], tp[hint * 3 + 1], tp[hint * 3 + 2])
		var q := tp[hint * 3] * ba.x + tp[hint * 3 + 1] * ba.y + tp[hint * 3 + 2] * ba.z
		var d2 := p.distance_squared_to(q)
		if d2 <= best:
			best = d2
			bt = hint
			bb = ba
	var stack := PackedInt32Array([0])
	while not stack.is_empty():
		var nd := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var dv := (bmin[nd] - p).max(p - bmax[nd]).max(Vector3.ZERO)
		if dv.length_squared() > best:
			continue
		var cn := bcount[nd]
		if cn > 0:
			var s := bstart[nd]
			for j in range(s, s + cn):
				if only_part >= 0 and tpart[j] != only_part:
					continue
				var a := tp[j * 3]
				var b := tp[j * 3 + 1]
				var c := tp[j * 3 + 2]
				var ba := closest_bary(p, a, b, c)
				var d2 := p.distance_squared_to(a * ba.x + b * ba.y + c * ba.z)
				if d2 < best:
					best = d2
					bt = j
					bb = ba
			continue
		var l := bleft[nd]
		var r := bright[nd]
		var dl := (bmin[l] - p).max(p - bmax[l]).max(Vector3.ZERO).length_squared()
		var dr := (bmin[r] - p).max(p - bmax[r]).max(Vector3.ZERO).length_squared()
		if dl < dr:   # the nearer child is popped first
			stack.append(r)
			stack.append(l)
		else:
			stack.append(l)
			stack.append(r)
	if bt < 0:
		return {}
	var pt := tp[bt * 3] * bb.x + tp[bt * 3 + 1] * bb.y + tp[bt * 3 + 2] * bb.z
	return {"t": bt, "b": bb, "p": pt, "d": sqrt(best)}


## the outward smooth normal at a surface point (triangle t, barycentric b)
func normal_at(t: int, b: Vector3) -> Vector3:
	var n := tcn[t * 3] * b.x + tcn[t * 3 + 1] * b.y + tcn[t * 3 + 2] * b.z
	return n.normalized() if n.length_squared() > 1e-20 else tn[t]


## two-sided ray / triangle (Moller-Trumbore): Vector4(t, u, v, 1) or Vector4.ZERO with w = 0 when there is no hit
static func ray_tri(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector4:
	var e1 := b - a
	var e2 := c - a
	var pv := d.cross(e2)
	var det := e1.dot(pv)
	if absf(det) < 1e-18:
		return Vector4.ZERO
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(pv) * inv
	if u < 0.0 or u > 1.0:
		return Vector4.ZERO
	var qv := tv.cross(e1)
	var v := d.dot(qv) * inv
	if v < 0.0 or u + v > 1.0:
		return Vector4.ZERO
	return Vector4(e2.dot(qv) * inv, u, v, 1.0)


## the slab interval of the line o + t d (t in [t0, t1]) inside node nd: Vector2(enter, exit), enter > exit = missed
func _slab(nd: int, o: Vector3, inv: Vector3, t0: float, t1: float) -> Vector2:
	var a := (bmin[nd] - o) * inv
	var b := (bmax[nd] - o) * inv
	var lo := a.min(b)
	var hi := a.max(b)
	return Vector2(maxf(t0, maxf(lo.x, maxf(lo.y, lo.z))), minf(t1, minf(hi.x, minf(hi.y, hi.z))))


## the hit of the line o + t d (d unit) with t in [t0, t1] nearest to o (smallest |t|): {"t", "tri", "b", "p"}; {} = none
func cast(o: Vector3, d: Vector3, t0: float, t1: float) -> Dictionary:
	var inv := Vector3(1.0 / d.x if d.x != 0.0 else INF, 1.0 / d.y if d.y != 0.0 else INF, 1.0 / d.z if d.z != 0.0 else INF)
	var best := INF   # |t|
	var bt := -1
	var bh := Vector4.ZERO
	var stack := PackedInt32Array([0])
	while not stack.is_empty():
		var nd := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var iv := _slab(nd, o, inv, t0, t1)
		if is_nan(iv.x) or is_nan(iv.y):
			iv = Vector2(t0, t1)   # the line runs in a box face plane: 0 * INF; test the box's triangles anyway
		if iv.x > iv.y:
			continue
		var near := 0.0 if (iv.x <= 0.0 and iv.y >= 0.0) else minf(absf(iv.x), absf(iv.y))
		if near >= best:
			continue
		var cn := bcount[nd]
		if cn > 0:
			var s := bstart[nd]
			for j in range(s, s + cn):
				var h := ray_tri(o, d, tp[j * 3], tp[j * 3 + 1], tp[j * 3 + 2])
				if h.w > 0.0 and h.x >= t0 and h.x <= t1 and absf(h.x) < best:
					best = absf(h.x)
					bt = j
					bh = h
			continue
		stack.append(bright[nd])
		stack.append(bleft[nd])
	if bt < 0:
		return {}
	var b := Vector3(1.0 - bh.y - bh.z, bh.y, bh.z)
	return {"t": bh.x, "tri": bt, "b": b, "p": o + d * bh.x}


## per connected part, how many times the ray o + t d (t > 0) crosses it: {part: count}; an odd count = o is inside that
## part (the parity test). Parts are counted apart: where two closed parts overlap, a point inside both crosses twice
func crossings(o: Vector3, d: Vector3) -> Dictionary:
	if full != null:
		return full.crossings(o, d)
	var inv := Vector3(1.0 / d.x if d.x != 0.0 else INF, 1.0 / d.y if d.y != 0.0 else INF, 1.0 / d.z if d.z != 0.0 else INF)
	var out := {}
	var stack := PackedInt32Array([0])
	while not stack.is_empty():
		var nd := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var iv := _slab(nd, o, inv, 0.0, FAR)
		if not is_nan(iv.x) and not is_nan(iv.y) and iv.x > iv.y:
			continue
		var cn := bcount[nd]
		if cn > 0:
			for j in range(bstart[nd], bstart[nd] + cn):
				var h := ray_tri(o, d, tp[j * 3], tp[j * 3 + 1], tp[j * 3 + 2])
				if h.w > 0.0 and h.x > 0.0:
					out[tpart[j]] = int(out.get(tpart[j], 0)) + 1
			continue
		stack.append(bright[nd])
		stack.append(bleft[nd])
	return out


## inside the target (inside ANY closed part but `skip`), by parity: the majority of 3 skew rays (a ray grazing an edge
## counts it twice or not at all; three rarely all graze)
func inside(p: Vector3, skip := -1) -> bool:
	var votes := 0
	for d in [Vector3(0.267, 0.534, 0.802), Vector3(-0.577, 0.211, -0.789), Vector3(0.123, -0.951, 0.284)]:
		var cr := crossings(p, (d as Vector3).normalized())
		for part in cr:
			if int(part) != skip and int(cr[part]) & 1 == 1:
				votes += 1
				break
		if votes >= 2:
			return true
	return false


# ---------------------------------------------------------------- wrapping

## the options with their defaults filled: mode, offset (m), max_dist (m, 0 = none), dirs, axis (a direction in the
## mesh's space, for "axis"), verts (the selection; empty = every vertex), channel (a vertex float channel, "" = none),
## refine (nearest passes)
static func opts_of(o: Dictionary) -> Dictionary:
	var d := {"mode": "nearest", "offset": OFFSET_DEFAULT, "max_dist": 0.0, "dirs": "both", "axis": Vector3.UP,
		"verts": PackedInt32Array(), "channel": "", "refine": 6}
	d.merge(o, true)
	return d


## THE OP: the vertices of `mesh` wrapped onto this target IN PLACE (the caller brackets it as one KMeshUndo step).
## -> {"moved", "missed" (out of range / no hit), "ms", "error"}
func wrap_mesh(mesh: KMesh, options := {}) -> Dictionary:
	last_error = ""
	var o := opts_of(options)
	var t0 := Time.get_ticks_usec()
	var res := {"moved": 0, "missed": 0, "ms": 0.0, "error": ""}
	if tri_count() == 0:
		last_error = "the target has no faces. Pick a mesh with a surface as the target."
		res["error"] = last_error
		return res
	var mode := String(o["mode"])
	if not mode in MODES:
		last_error = "no shrinkwrap mode '%s'. Use one of %s." % [mode, ", ".join(MODES)]
		res["error"] = last_error
		return res
	var nv := mesh.verts.size()
	var w := PackedFloat32Array()
	w.resize(nv)
	var sel: PackedInt32Array = PackedInt32Array(o["verts"])
	if sel.is_empty():
		w.fill(1.0)
	else:
		for v in sel:
			if v >= 0 and v < nv:
				w[v] = 1.0
	var ch := String(o["channel"])
	if ch != "":
		if not mesh.has_attr(ch) or mesh.attr_info(ch).get("domain", "") != KMesh.AD_VERT or mesh.attr_info(ch).get("type", -1) != TYPE_FLOAT:
			last_error = "no vertex weight channel '%s' on this mesh. Paint one first, or wrap the selection." % ch
			res["error"] = last_error
			return res
		var cd: PackedFloat32Array = mesh.attr_data(ch)
		for v in nv:
			w[v] *= clampf(cd[v] if v < cd.size() else 0.0, 0.0, 1.0)
	var off := float(o["offset"])
	var md := float(o["max_dist"])
	var lim := md if md > 0.0 else FAR
	var dirs := String(o["dirs"])
	var ta := -lim if dirs != "out" else 0.0
	var tb := lim if dirs != "in" else 0.0
	var axis: Vector3 = (o["axis"] as Vector3).normalized()
	var vn := mesh.vert_normals if mode == "normal" else PackedVector3Array()
	var refine := int(o["refine"])
	var V := mesh.verts
	var hint := -1
	for v in nv:
		if w[v] <= 0.0:
			continue
		var p := V[v]
		var q: Vector3
		if mode == "nearest":
			var h := nearest(p, md, hint)
			if h.is_empty():
				res["missed"] += 1
				continue
			hint = h["t"]
			q = h["p"] + normal_at(h["t"], h["b"]) * off
			if off != 0.0:
				q = _settle(q, off, refine)
		else:
			var d: Vector3 = vn[v] if mode == "normal" else axis
			if d.length_squared() < 1e-20:
				res["missed"] += 1
				continue
			var h := cast(p, d.normalized(), ta, tb)
			if h.is_empty():
				res["missed"] += 1
				continue
			q = h["p"] + normal_at(h["tri"], h["b"]) * off
			if off > 0.0 and tpartial[h["tri"]] == 1:
				q = _settle(q, off, 0)
		V[v] = q if w[v] >= 1.0 else p.lerp(q, w[v])
		res["moved"] += 1
	mesh.verts = V
	mesh.rebuild()
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return res


## SETTLE a landing q (offset off from a surface point): the TRUE skin is the union of the target's closed parts, so
## (1) a landing inside a part (by parity; checked near a triangle that is partly or wholly inside another part, where
## it happens: the chest's skin where the arm enters it, and on every landing about to be kept) is pushed out of that part: its nearest point on that
## part's own surface, offset again; (2) a landing whose distance to the skin (the nearest of every part) is off |off|
## by > 2 % (a crease: the armpit, between fingers) lands again from the nearest skin point to where it is. Up to
## `passes` + 6 tries; the outside landing nearest |off| is kept
func _settle(q: Vector3, off: float, passes: int) -> Vector3:
	var src: KMeshShrinkwrap = full if full != null else self
	var best := q   # the landing nearest |off| ...
	var err := INF
	var obest := q  # ... and the one of those known to be outside (preferred)
	var oerr := INF
	var check := full != null or parts > 1
	for i in passes + 6:
		var h := src.nearest(q)
		if h.is_empty():
			break
		var e := absf(float(h["d"]) - absf(off))
		if check and off > 0.0 and (src.tpartial[h["t"]] == 1 or e < absf(off) * 0.02):   # verify before keeping
			var part := _odd_part(q)
			if part >= 0:
				var hp := src.nearest(q, 0.0, -1, part)
				if hp.is_empty():
					break
				var od: Vector3 = hp["p"] - q   # q is inside the part: out through its nearest skin point
				q = hp["p"] + (od.normalized() if od.length_squared() > 1e-16 else src.normal_at(hp["t"], hp["b"])) * off
				continue
		var ok := not check or off <= 0.0 or src.tpartial[h["t"]] == 1 or e < absf(off) * 0.02   # verified outside above
		if ok and e < oerr:
			oerr = e
			obest = q
		if e < err:
			err = e
			best = q
		if e < absf(off) * 0.02:
			break
		var dv: Vector3 = q - h["p"]   # along the distance field's gradient: a crease is climbed out of, not bounced in
		if dv.length_squared() > 1e-16:
			q = h["p"] + dv.normalized() * absf(off)
		else:
			q = h["p"] + src.normal_at(h["t"], h["b"]) * off
	return obest if oerr < INF else best


## the closed part a point is inside (parity, the majority of 3 rays), -1 = none
func _odd_part(p: Vector3) -> int:
	var votes := {}
	for d in [Vector3(0.267, 0.534, 0.802), Vector3(-0.577, 0.211, -0.789), Vector3(0.123, -0.951, 0.284)]:
		var cr := crossings(p, (d as Vector3).normalized())
		for part in cr:
			if int(cr[part]) & 1 == 1:
				votes[part] = int(votes.get(part, 0)) + 1
				if votes[part] >= 2:
					return int(part)
	return -1


## a wrapped COPY (the modifier's way): the base is not touched
func wrapped(mesh: KMesh, options := {}) -> KMesh:
	var r := KMesh.new().from_arrays(mesh.verts, mesh.faces)
	r.attrs = mesh.attr_snapshot() if not mesh.attrs.is_empty() else {}
	wrap_mesh(r, options)
	return r


# ---------------------------------------------------------------- targets: the body, another mesh

static var _body_cache := {}    # {"gen", "rest": KMesh, "w": weights per vertex, "sig", "sw"}
static var _other := {}         # {"mesh": KMesh (stage space), "sw_sig", "sw"}
static var host: WeakRef        # main (the fighter): set by the ops; found in the tree when the modifier runs first


static func _host() -> Node:
	var h: Node = host.get_ref() if host != null else null
	if h != null and is_instance_valid(h):
		return h
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		for c in (ml as SceneTree).root.get_children():
			if c.get("pieces") != null and c.get("skel") != null:
				host = weakref(c)
				return c
	return null


## the fighter's skin at its current pose, in the body mesh's own space (see the header). null without a fighter
static func posed_body(m: Node) -> KMesh:
	if m == null or m.get("pieces") == null or m.pieces.is_empty() or m.get("skel") == null:
		return null
	var skin := BaseBody.skin_of(m)
	if skin == null:
		return null
	var g := BaseBody.gen(m)
	if _body_cache.get("gen", -1) != g or not _body_cache.has("rest"):
		var rest := BaseBody.read(m)
		_body_cache = {"gen": g, "rest": rest, "w": BaseBody.weights_of(rest, skin)}
	var rest: KMesh = _body_cache["rest"]
	var ws: Array = _body_cache["w"]
	var mats := DqSkin.bind_mats(m.skel, skin)
	var V := PackedVector3Array()
	V.resize(rest.verts.size())
	for v in rest.verts.size():
		var d: Dictionary = ws[v]
		if d.is_empty():
			V[v] = rest.verts[v]
			continue
		var acc := Vector3.ZERO
		var tw := 0.0
		for b in d:
			var wb: float = d[b]
			acc += ((mats[b] as Transform3D) * rest.verts[v]) * wb
			tw += wb
		V[v] = acc / tw
	return KMesh.new().from_arrays(V, rest.faces)


## the body piece's transform into the space of the mesh being edited (identity when that mesh IS the body)
static func body_xf(m: Node) -> Transform3D:
	var p0 := m.pieces.values()[0] as MeshInstance3D
	var ed = m.get("kmed")
	if ed != null and ed.on and ed.view != null and is_instance_valid(ed.view) and ed.view.is_inside_tree() and p0.is_inside_tree():
		return ed.view.global_transform.affine_inverse() * p0.global_transform
	return Transform3D.IDENTITY


## THE BODY TARGET (cached: the same skin generation, pose and placement build nothing). null without a fighter
static func body(m: Node = null) -> KMeshShrinkwrap:
	if m == null:
		m = _host()
	if m == null or m.get("skel") == null or BaseBody.skin_of(m) == null:
		last_error = "there is no fighter body to wrap onto. Load a fighter first."
		return null
	host = weakref(m)
	var xf := body_xf(m)
	var mats := DqSkin.bind_mats(m.skel, BaseBody.skin_of(m))
	var sig := hash([BaseBody.gen(m), mats, xf])
	if _body_cache.get("sig", 0) == sig and _body_cache.has("sw"):
		return _body_cache["sw"]
	var k := posed_body(m)
	if k == null:
		return null
	if not _body_cache.has("buried"):   # found once per skin generation, at rest (a pose barely moves which are buried)
		_body_cache["buried"] = build(_body_cache["rest"]).buried
	var sw := build(k, xf, true, _body_cache["buried"])
	_body_cache["sig"] = sig
	_body_cache["sw"] = sw
	return sw


## "this mesh is the other target": a copy kept in stage space (so it stays put when another mesh is opened)
static func set_other(mesh: KMesh, to_stage := Transform3D.IDENTITY) -> void:
	var V := PackedVector3Array()
	V.resize(mesh.verts.size())
	for i in V.size():
		V[i] = to_stage * mesh.verts[i]
	_other = {"mesh": KMesh.new().from_arrays(V, mesh.faces)}


static func has_other() -> bool:
	return _other.has("mesh")


## the other target, in the space of the mesh being edited (stage -> view). null when none is set
static func other(m: Node = null) -> KMeshShrinkwrap:
	if not has_other():
		last_error = "no other target yet. Open the mesh to wrap onto and run \"Model: shrinkwrap target = this mesh\"."
		return null
	if m == null:
		m = _host()
	var xf := Transform3D.IDENTITY
	if m != null and m.get("kmed") != null and m.kmed.on and m.kmed.view != null and is_instance_valid(m.kmed.view):
		xf = m.kmed.view.transform.affine_inverse()
	var sig := hash(xf)
	if _other.get("sig", null) == sig and _other.has("sw"):
		return _other["sw"]
	_other["sig"] = sig
	_other["sw"] = build(_other["mesh"], xf)
	return _other["sw"]


# ---------------------------------------------------------------- the A11 modifier

## the "shrinkwrap" modifier on m (a cleaned dictionary, KMeshModifiers.PARAMS): a new KMesh. No target: an unchanged copy
## (last_error says why)
static func evaluate_mod(m: KMesh, c: Dictionary) -> KMesh:
	var sw: KMeshShrinkwrap = body() if int(c.get("target", 0)) == 0 else other()
	if sw == null:
		var r := KMesh.new().from_arrays(m.verts, m.faces)
		r.attrs = m.attr_snapshot() if not m.attrs.is_empty() else {}
		return r
	var ax: Vector3 = AXES[clampi(int(c.get("axis", 1)), 0, 2)]
	return sw.wrapped(m, {"mode": MODES[clampi(int(c.get("mode", 0)), 0, 2)], "offset": float(c.get("offset", OFFSET_DEFAULT)),
		"max_dist": float(c.get("max_dist", 0.0)), "dirs": DIRS[clampi(int(c.get("dirs", 0)), 0, 2)], "axis": ax,
		"channel": String(c.get("channel", "")), "refine": 6})


# ---------------------------------------------------------------- the ops (mesh_tools "op:")

## the model preview's selection as vertices (edges / faces give their corners); empty = nothing selected
static func sel_verts(sel: KMeshSelect, mesh: KMesh) -> PackedInt32Array:
	var out := {}
	if sel == null:
		return PackedInt32Array()
	match sel.mode:
		KMeshSelect.EDGE:
			for e in sel.edges:
				out[(e as Vector2i).x] = true
				out[(e as Vector2i).y] = true
		KMeshSelect.FACE:
			for fi in sel.faces:
				if int(fi) < mesh.faces.size():
					for v in (mesh.faces[int(fi)] as PackedInt32Array):
						out[v] = true
		_:
			for v in sel.verts:
				out[int(v)] = true
	var r := PackedInt32Array(out.keys())
	r.sort()
	return r


## "shrinkwrap" (nearest, +4 mm, onto the body), "shrinkwrap_view" (cast along the view, both ways), "shrinkwrap_other"
## (nearest onto the other target), "shrinkwrap_target" (this mesh becomes the other target). The wrap is ONE undo step
static func op(name: String, m: Node, options := {}) -> String:
	var ui = m.kmed
	host = weakref(m)
	if name == "shrinkwrap_target":
		set_other(ui.mesh, ui.view.transform)
		return "Model: this mesh (%d verts, %d faces) is now the other shrinkwrap target: open another mesh and run \"Model: shrinkwrap onto the other target\"" % [ui.mesh.verts.size(), ui.mesh.faces.size()]
	var sw: KMeshShrinkwrap = other(m) if name == "shrinkwrap_other" else body(m)
	if sw == null:
		return "Model: " + last_error
	var o := {"verts": sel_verts(ui.sel, ui.mesh)}
	if name == "shrinkwrap_view":
		var cam: Camera3D = m.cam
		var fwd: Vector3 = -cam.global_transform.basis.z
		o["mode"] = "axis"
		o["axis"] = (ui.view.global_transform.basis.inverse() * fwd).normalized()
	o.merge(options, true)
	ui.undo.begin(ui.mesh)
	var r := sw.wrap_mesh(ui.mesh, o)
	ui.undo.commit("Shrinkwrap")
	ui.view.mark_dirty()
	if String(r["error"]) != "":
		return "Model: " + String(r["error"])
	var of := float(opts_of(o)["offset"])
	return "Model: shrinkwrapped %d verts onto the %s (%s, offset %s%s; %.0f ms; one undo step)" % [r["moved"],
		"other target" if name == "shrinkwrap_other" else "body at its current pose", String(opts_of(o)["mode"]) if name != "shrinkwrap_view" else "along the view",
		Units.len(of), (", %d out of reach left alone" % r["missed"]) if int(r["missed"]) > 0 else "", r["ms"]]
