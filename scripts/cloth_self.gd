## cloth_self.gd - C54 (complaint #180, M #180): CLOTH SELF-COLLISION. A cape that folds onto itself (draped over a crouch, a skirt
## in a sit) must not pass through itself: no two triangles of the same cloth that share no vertex end a solve closer than the
## cloth's thickness (Cloth.THICK = 2 * MARGIN).
##
## HOW (position-based; our own code, the textbook vertex-triangle plus edge-edge proximity test of cloth solvers):
##   begin(p): once a substep, from the predicted positions p, a SPATIAL HASH (a uniform grid, cell CELL m, a Dictionary from the
##     cell to its triangle ids) finds the triangle pairs whose boxes (padded by thickness + PAD) overlap and that share no vertex.
##     A flat cloth has none (its triangles two apart are 27 mm clear); only a fold has pairs. Cost is ~ triangles, not triangles^2.
##   solve(p, pinned): for each pair, (a) each of the 3 vertices of one against the other triangle (closest point, barycentric weights),
##     (b) the 9 edge-edge pairs (closest points on two segments). A contact nearer than thick is pushed apart along the contact normal
##     by the missing depth, split by inverse mass x barycentric weight squared (a pin does not move).
## The contact normal runs from the other surface's closest point to the point. It is a position projection: it separates what is
## close; it cannot untangle cloth that already crossed (a substep is short: a vertex moves about a millimetre).
class_name ClothSelf
extends RefCounted

const CELL := 0.05      # m: the hash cell
const PAD := 0.004      # m: a box is padded by this on top of the thickness (positions move this much within a substep's passes)

var thick := 0.006
var tris := PackedInt32Array()
var pairs := PackedInt32Array()   # (tri a, tri b) pairs found by begin
var npairs := 0
var contacts := 0                  # contacts pushed in the last solve


func _init(faces: PackedInt32Array, thickness: float) -> void:
	tris = faces
	thick = thickness
	# the near ring: triangles within two vertex hops of each other (sharing a vertex, or sharing a vertex with a triangle that
	# does) are the distance constraints' business, not this solver's: a flat cloth then has no pairs at all
	var nt := tris.size() / 3
	var by_vert := {}
	for t in nt:
		for i in 3:
			var v := tris[3 * t + i]
			if not by_vert.has(v):
				by_vert[v] = PackedInt32Array()
			var l: PackedInt32Array = by_vert[v]
			l.append(t)
			by_vert[v] = l
	var sharing: Array = []
	for t in nt:
		var s := {}
		for i in 3:
			for u in (by_vert[tris[3 * t + i]] as PackedInt32Array):
				s[u] = true
		sharing.append(s)
	ring = {}
	for t in nt:
		for u in (sharing[t] as Dictionary):
			for w in (sharing[u] as Dictionary):
				ring[t * nt + w] = true


var ring := {}   # t * nt + u -> true for the triangles u within two hops of t


## the triangle pairs near each other (outside the near ring), through a spatial hash of the triangles' padded boxes. A pair is
## listed once, in the cell holding the larger corner of the two boxes' overlap (no dedupe table). A cheap sphere test drops
## boxes that merely touch.
func begin(p: PackedVector3Array) -> int:
	var nt := tris.size() / 3
	var grid := {}
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	var cen := PackedVector3Array()
	var rad := PackedFloat32Array()
	lo.resize(nt)
	hi.resize(nt)
	cen.resize(nt)
	rad.resize(nt)
	var pad := Vector3.ONE * (thick * 0.5 + PAD)
	var inv := 1.0 / CELL
	for t in nt:
		var a := p[tris[3 * t]]
		var b := p[tris[3 * t + 1]]
		var c := p[tris[3 * t + 2]]
		var l := a.min(b).min(c) - pad
		var h := a.max(b).max(c) + pad
		lo[t] = l
		hi[t] = h
		var ce := (a + b + c) / 3.0
		cen[t] = ce
		rad[t] = sqrt(maxf(maxf(a.distance_squared_to(ce), b.distance_squared_to(ce)), c.distance_squared_to(ce)))
		for ix in range(int(floor(l.x * inv)), int(floor(h.x * inv)) + 1):
			for iy in range(int(floor(l.y * inv)), int(floor(h.y * inv)) + 1):
				for iz in range(int(floor(l.z * inv)), int(floor(h.z * inv)) + 1):
					var key := (ix & 0x1FFFFF) | ((iy & 0x1FFFFF) << 21) | ((iz & 0x1FFFFF) << 42)
					if grid.has(key):
						var cell: PackedInt32Array = grid[key]   # a Packed array is a value: append, then store it back
						cell.append(t)
						grid[key] = cell
					else:
						grid[key] = PackedInt32Array([t])
	var out := PackedInt32Array()
	var reach := thick + 2.0 * PAD
	for key in grid:
		var lst: PackedInt32Array = grid[key]
		var n := lst.size()
		if n < 2:
			continue
		for i in n:
			var ta := lst[i]
			for j in range(i + 1, n):
				var tb := lst[j]
				var l1 := lo[ta]
				var h1 := hi[ta]
				var l2 := lo[tb]
				var h2 := hi[tb]
				if l1.x > h2.x or l2.x > h1.x or l1.y > h2.y or l2.y > h1.y or l1.z > h2.z or l2.z > h1.z:
					continue
				# the owner cell: the one holding the larger corner of the overlap
				var ox := int(floor(maxf(l1.x, l2.x) * inv))
				var oy := int(floor(maxf(l1.y, l2.y) * inv))
				var oz := int(floor(maxf(l1.z, l2.z) * inv))
				if key != ((ox & 0x1FFFFF) | ((oy & 0x1FFFFF) << 21) | ((oz & 0x1FFFFF) << 42)):
					continue
				if cen[ta].distance_to(cen[tb]) > rad[ta] + rad[tb] + reach:
					continue
				if ring.has(ta * nt + tb):
					continue
				out.append(ta)
				out.append(tb)
	pairs = out
	npairs = out.size() / 2
	return npairs


func _share(ta: int, tb: int) -> bool:
	for i in 3:
		var v := tris[3 * ta + i]
		if v == tris[3 * tb] or v == tris[3 * tb + 1] or v == tris[3 * tb + 2]:
			return true
	return false


## one projection pass over the pairs found by begin. Returns the contacts it pushed.
func solve(p: PackedVector3Array, pinned: PackedByteArray) -> int:
	var n := 0
	for k in npairs:
		var ta := pairs[2 * k]
		var tb := pairs[2 * k + 1]
		var a0 := tris[3 * ta]
		var a1 := tris[3 * ta + 1]
		var a2 := tris[3 * ta + 2]
		var b0 := tris[3 * tb]
		var b1 := tris[3 * tb + 1]
		var b2 := tris[3 * tb + 2]
		n += _vert_tri(p, pinned, a0, b0, b1, b2)
		n += _vert_tri(p, pinned, a1, b0, b1, b2)
		n += _vert_tri(p, pinned, a2, b0, b1, b2)
		n += _vert_tri(p, pinned, b0, a0, a1, a2)
		n += _vert_tri(p, pinned, b1, a0, a1, a2)
		n += _vert_tri(p, pinned, b2, a0, a1, a2)
		n += _edge_edge(p, pinned, a0, a1, b0, b1)
		n += _edge_edge(p, pinned, a0, a1, b1, b2)
		n += _edge_edge(p, pinned, a0, a1, b2, b0)
		n += _edge_edge(p, pinned, a1, a2, b0, b1)
		n += _edge_edge(p, pinned, a1, a2, b1, b2)
		n += _edge_edge(p, pinned, a1, a2, b2, b0)
		n += _edge_edge(p, pinned, a2, a0, b0, b1)
		n += _edge_edge(p, pinned, a2, a0, b1, b2)
		n += _edge_edge(p, pinned, a2, a0, b2, b0)
	contacts = n
	return n


func _vert_tri(p: PackedVector3Array, pinned: PackedByteArray, v: int, t0: int, t1: int, t2: int) -> int:
	var q := p[v]
	var bary := tri_bary(q, p[t0], p[t1], p[t2])
	var cp := p[t0] * bary.x + p[t1] * bary.y + p[t2] * bary.z
	var d := q - cp
	var dist := d.length()
	if dist >= thick:
		return 0
	var nrm: Vector3
	if dist > 1e-9:
		nrm = d / dist
	else:
		nrm = (p[t1] - p[t0]).cross(p[t2] - p[t0]).normalized()
		if nrm == Vector3.ZERO:
			nrm = Vector3.UP
	var wv := 0.0 if pinned[v] == 1 else 1.0
	var w0 := 0.0 if pinned[t0] == 1 else 1.0
	var w1 := 0.0 if pinned[t1] == 1 else 1.0
	var w2 := 0.0 if pinned[t2] == 1 else 1.0
	var den := wv + w0 * bary.x * bary.x + w1 * bary.y * bary.y + w2 * bary.z * bary.z
	if den < 1e-12:
		return 0
	var s := (thick - dist) / den
	p[v] += nrm * (s * wv)
	p[t0] -= nrm * (s * w0 * bary.x)
	p[t1] -= nrm * (s * w1 * bary.y)
	p[t2] -= nrm * (s * w2 * bary.z)
	return 1


func _edge_edge(p: PackedVector3Array, pinned: PackedByteArray, a: int, b: int, c: int, d: int) -> int:
	var st := closest_segs(p[a], p[b], p[c], p[d])
	var s := st.x
	var t := st.y
	var dv := p[a].lerp(p[b], s) - p[c].lerp(p[d], t)
	var dist := dv.length()
	if dist >= thick:
		return 0
	var nrm: Vector3
	if dist > 1e-9:
		nrm = dv / dist
	else:
		nrm = (p[b] - p[a]).cross(p[d] - p[c]).normalized()
		if nrm == Vector3.ZERO:
			nrm = Vector3.UP
	var wa := 0.0 if pinned[a] == 1 else 1.0
	var wb := 0.0 if pinned[b] == 1 else 1.0
	var wc := 0.0 if pinned[c] == 1 else 1.0
	var wd := 0.0 if pinned[d] == 1 else 1.0
	var den := wa * (1 - s) * (1 - s) + wb * s * s + wc * (1 - t) * (1 - t) + wd * t * t
	if den < 1e-12:
		return 0
	var m := (thick - dist) / den
	p[a] += nrm * (m * wa * (1 - s))
	p[b] += nrm * (m * wb * s)
	p[c] -= nrm * (m * wc * (1 - t))
	p[d] -= nrm * (m * wd * t)
	return 1


## the barycentric weights (a, b, c) of the point on triangle abc closest to q (region test: vertices, edges, face)
static func tri_bary(q: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := q - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1, 0, 0)
	var bp := q - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return Vector3(1.0 - v, v, 0)
	var cq := q - c
	var d5 := ab.dot(cq)
	var d6 := ac.dot(cq)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return Vector3(1.0 - w, 0, w)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var w2 := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1.0 - w2, w2)
	var den := 1.0 / (va + vb + vc)
	var v2 := vb * den
	var w3 := vc * den
	return Vector3(1.0 - v2 - w3, v2, w3)


## closest parameters (s on p1-q1, t on p2-q2), both in 0..1
static func closest_segs(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector2:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-14 and e <= 1e-14:
		return Vector2.ZERO
	if a <= 1e-14:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-14:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			if den > 1e-14:
				s = clampf((b * f - c * e) / den, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return Vector2(s, t)


## the smallest distance between two triangles' surfaces (the 6 vertex-triangle and 9 edge-edge tests), for the MEASURE
static func tri_tri_dist(a: Array, b: Array) -> float:
	var best := INF
	for i in 3:
		var qb: Vector3 = a[i]
		var wb := tri_bary(qb, b[0], b[1], b[2])
		best = minf(best, qb.distance_to((b[0] as Vector3) * wb.x + (b[1] as Vector3) * wb.y + (b[2] as Vector3) * wb.z))
		var qa: Vector3 = b[i]
		var wa := tri_bary(qa, a[0], a[1], a[2])
		best = minf(best, qa.distance_to((a[0] as Vector3) * wa.x + (a[1] as Vector3) * wa.y + (a[2] as Vector3) * wa.z))
	for i in 3:
		for j in 3:
			var p1: Vector3 = a[i]
			var q1: Vector3 = a[(i + 1) % 3]
			var p2: Vector3 = b[j]
			var q2: Vector3 = b[(j + 1) % 3]
			var st := closest_segs(p1, q1, p2, q2)
			best = minf(best, p1.lerp(q1, st.x).distance_to(p2.lerp(q2, st.y)))
	return best


## how many same-cloth triangle pairs (sharing no vertex) are closer than limit: brute force over every pair, so it is the
## MEASURE, independent of the solver's hash
static func count_close(verts: PackedVector3Array, faces: PackedInt32Array, limit: float) -> int:
	var nt := faces.size() / 3
	var n := 0
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for i in nt:
		var a := verts[faces[3 * i]]
		var b := verts[faces[3 * i + 1]]
		var c := verts[faces[3 * i + 2]]
		lo.append(a.min(b).min(c) - Vector3.ONE * limit)
		hi.append(a.max(b).max(c) + Vector3.ONE * limit)
	for i in nt:
		for j in range(i + 1, nt):
			var l1 := lo[i]
			var h1 := hi[i]
			var l2 := lo[j]
			var h2 := hi[j]
			if l1.x > h2.x or l2.x > h1.x or l1.y > h2.y or l2.y > h1.y or l1.z > h2.z or l2.z > h1.z:
				continue
			var share := false
			for u in 3:
				for w in 3:
					if faces[3 * i + u] == faces[3 * j + w]:
						share = true
			if share:
				continue
			var ta := [verts[faces[3 * i]], verts[faces[3 * i + 1]], verts[faces[3 * i + 2]]]
			var tb := [verts[faces[3 * j]], verts[faces[3 * j + 1]], verts[faces[3 * j + 2]]]
			if tri_tri_dist(ta, tb) < limit:
				n += 1
	return n
