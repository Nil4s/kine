## READY TO PRINT? (Friday plan 112): three plain-words checks of a part before STL / 3MF, read from the SAME bodies the files hold
## (MeshExport.bodies_of: millimetres, Z up, welded, outward winding; the floor of the part is the bed, z = 0).
##   thin walls  a point on the skin looks straight into the solid (against its outward normal); if the far side is nearer than 0.8 mm that is a thin wall.
##               Walls are counted as pieces of skin: the two faces of one wall are ONE wall (coplanar triangles and the faces that look at each other are joined).
##   overhangs   triangles that face down steeper than 45 degrees from the vertical (normal z < -sin 45), not resting on the bed and not sitting on another
##               solid; the area is summed in cm2.
##   floating    a piece (body) that neither reaches the bed (lowest point <= 0.05 mm) nor touches another piece that does, through any chain of pieces.
## analyse(bodies) -> {"thin": walls, "thinnest": mm (0 when none), "overhang_cm2": x, "floating": pieces, "lowest": mm of the lowest floating piece,
##                     "ok": bool, "lines": ["OK    ..." / "WARN  ..."]}; the first line is the verdict.
class_name PrintCheck
extends RefCounted

const THIN_MM := 0.8
const OVERHANG_DEG := 45.0
const BED_TOL := 0.05   # mm: a piece whose lowest point is this close to z = 0 sits on the bed
const TOUCH_TOL := 0.05   # mm: two pieces this close touch
const CELL := 2.0   # mm: the grid the rays look in
const SUPPORT_MM := 0.1   # a down face with a solid's up face this close below it is sitting on it

static var _cache_key := 0
static var _cache := {}


## the dialog's road: the lines for the part record (cached by the record's content, the dialog refreshes often)
static func lines_of(rec: Dictionary, bodies: Array) -> Array:
	var key := hash(JSON.stringify(rec))
	if key != _cache_key or _cache.is_empty():
		_cache = analyse(bodies)
		_cache_key = key
	return _cache["lines"]


static func analyse(bodies: Array) -> Dictionary:
	return _words(scan(bodies))


static func native_on() -> bool:
	return MeshCheckDoor.native_on()


## the numbers of the three scans: {"walls", "thinnest" (INF when none), "over_mm2", "floating", "lowest" (INF when none)}.
## KineMeshCheckNative.scan when the DLL is there (same arithmetic, native/src/kine_meshcheck_native.cpp), else the GDScript below.
static func scan(bodies: Array) -> Dictionary:
	var d = MeshCheckDoor.door()
	if d != null:
		return d.scan(bodies)
	return _scan_gd(bodies)


static func _scan_gd(bodies: Array) -> Dictionary:
	# the triangle soup of every body: global vertex ids (per body offset), corners, unit outward normals, area
	var ia := PackedInt32Array()
	var ib := PackedInt32Array()
	var ic := PackedInt32Array()
	var pa := PackedVector3Array()
	var pb := PackedVector3Array()
	var pc := PackedVector3Array()
	var nn := PackedVector3Array()
	var body := PackedInt32Array()
	var area := PackedFloat32Array()
	var off := 0
	var bmin: Array = []
	var bmax: Array = []
	var bverts: Array = []   # per body: its triangle indices
	for bi in bodies.size():
		var v: PackedVector3Array = bodies[bi]["v"]
		var t: PackedInt32Array = bodies[bi]["t"]
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in v:
			lo = lo.min(p)
			hi = hi.max(p)
		bmin.append(lo)
		bmax.append(hi)
		var mine := PackedInt32Array()
		for i in range(0, t.size(), 3):
			var a := v[t[i]]
			var b := v[t[i + 1]]
			var c := v[t[i + 2]]
			var cr := (b - a).cross(c - a)
			var ar := cr.length() * 0.5
			if ar < 1e-9:
				continue
			mine.append(pa.size())
			ia.append(off + t[i])
			ib.append(off + t[i + 1])
			ic.append(off + t[i + 2])
			pa.append(a)
			pb.append(b)
			pc.append(c)
			nn.append(cr.normalized())
			body.append(bi)
			area.append(ar)
		bverts.append(mine)
		off += v.size()
	var nt := pa.size()
	# the grid: cell -> triangle indices
	var grid := {}
	for i in nt:
		var lo := pa[i].min(pb[i]).min(pc[i])
		var hi := pa[i].max(pb[i]).max(pc[i])
		var c0 := _cell(lo)
		var c1 := _cell(hi)
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					var k := Vector3i(x, y, z)
					if not grid.has(k):
						grid[k] = []   # an Array: a packed array cast with "as" is a copy and the append would be lost
					(grid[k] as Array).append(i)

	# ---- thin walls
	var thin := {}   # triangle -> true
	var partner := {}   # triangle -> the triangle across the wall
	var thinnest := INF
	for i in nt:
		var best := INF
		var bj := -1
		for s in 4:
			var q: Vector3
			match s:
				0:
					q = (pa[i] + pb[i] + pc[i]) / 3.0
				1:
					q = (pa[i] * 2.0 + pb[i] + pc[i]) * 0.25
				2:
					q = (pa[i] + pb[i] * 2.0 + pc[i]) * 0.25
				_:
					q = (pa[i] + pb[i] + pc[i] * 2.0) * 0.25
			var o := q - nn[i] * 0.001
			var h := _hit(grid, pa, pb, pc, nn, body, o, -nn[i], THIN_MM + 0.002, i, body[i], 1)
			if h[0] >= 0.0 and h[0] + 0.001 < best:
				best = h[0] + 0.001
				bj = int(h[1])
		if best < THIN_MM - 0.0005:
			thin[i] = true
			partner[i] = bj
			thinnest = minf(thinnest, best)
	var parent := {}
	for i in thin.keys():
		parent[i] = i
	for i in partner.keys():
		var j: int = partner[i]
		if not parent.has(j):
			parent[j] = j
		_union(parent, i, j)
	var edge_tris := {}
	for i in parent.keys():
		for e in [[ia[i], ib[i]], [ib[i], ic[i]], [ic[i], ia[i]]]:
			var key: int = (mini(e[0], e[1]) << 32) | maxi(e[0], e[1])
			if not edge_tris.has(key):
				edge_tris[key] = []
			(edge_tris[key] as Array).append(i)
	for key in edge_tris:
		var l: Array = edge_tris[key]
		for x in l.size():
			for y in range(x + 1, l.size()):
				if nn[l[x]].dot(nn[l[y]]) > 0.966:
					_union(parent, l[x], l[y])
	var roots := {}
	for i in parent.keys():
		roots[_find(parent, i)] = true
	var walls := roots.size()

	# ---- overhangs
	var down_z := -sin(deg_to_rad(OVERHANG_DEG)) - 1e-4
	var over_mm2 := 0.0
	for i in nt:
		if nn[i].z >= down_z:
			continue
		if maxf(pa[i].z, maxf(pb[i].z, pc[i].z)) <= BED_TOL:
			continue   # on the bed: that is the floor, not an overhang
		var cen := (pa[i] + pb[i] + pc[i]) / 3.0
		var sup := _hit(grid, pa, pb, pc, nn, body, cen + Vector3(0, 0, 0.001), Vector3(0, 0, -1), SUPPORT_MM + 0.002, i, -1, 2)
		if sup[0] >= 0.0:
			continue   # sitting on another solid's up face
		over_mm2 += area[i]

	# ---- floating pieces
	var nb := bodies.size()
	var on_bed := []
	for bi in nb:
		on_bed.append(nb > 0 and (bmin[bi] as Vector3).z <= BED_TOL and (bmin[bi] as Vector3).z != INF)
	var reach := on_bed.duplicate()
	var changed := true
	var touch := {}
	while changed:
		changed = false
		for a in nb:
			for b in nb:
				if a == b or not reach[a] or reach[b]:
					continue
				var k := a * 1000 + b
				if not touch.has(k):
					touch[k] = _touching(a, b, bmin, bmax, bverts, grid, pa, pb, pc, nn, body, ia, ib, ic)
					touch[b * 1000 + a] = touch[k]
				if touch[k]:
					reach[b] = true
					changed = true
	var floating := 0
	var lowest := INF
	for bi in nb:
		if not reach[bi]:
			floating += 1
			lowest = minf(lowest, (bmin[bi] as Vector3).z)

	return {"walls": walls, "thinnest": thinnest, "over_mm2": over_mm2, "floating": floating, "lowest": lowest}


static func _words(sc: Dictionary) -> Dictionary:
	var walls := int(sc["walls"])
	var thinnest := float(sc["thinnest"])
	var over_mm2 := float(sc["over_mm2"])
	var floating := int(sc["floating"])
	var lowest := float(sc["lowest"])
	# ---- the words
	var out := []
	var bad := 0
	var l_thin := ""
	var l_over := ""
	var l_float := ""
	if walls > 0:
		bad += 1
		l_thin = "WARN  %d wall%s thinner than %.1f mm (the thinnest is %.2f mm): thicken %s, or the printer may leave %s out or break %s" % [walls, "" if walls == 1 else "s", THIN_MM, thinnest, "it" if walls == 1 else "them", "it" if walls == 1 else "them", "it" if walls == 1 else "them"]
	else:
		l_thin = "OK    walls: none thinner than %.1f mm" % THIN_MM
	var over_cm2 := over_mm2 / 100.0
	if over_cm2 > 0.005:
		bad += 1
		l_over = "WARN  overhangs: %.2f cm2 of faces point down steeper than %d degrees: they may need supports (or turn the part)" % [over_cm2, int(OVERHANG_DEG)]
	else:
		l_over = "OK    overhangs: nothing points down steeper than %d degrees" % int(OVERHANG_DEG)
	if floating > 0:
		bad += 1
		l_float = "WARN  %d piece%s floating: %s touch%s neither the bed nor another piece (the lowest is %.1f mm up), so %s would print in mid-air" % [floating, "" if floating == 1 else "s", "it does" if floating == 1 else "they do", "" if floating == 1 else "", lowest, "it" if floating == 1 else "they"]
		if floating == 1:
			l_float = "WARN  1 piece floating: it touches neither the bed nor another piece (the lowest point is %.1f mm up), so it would print in mid-air" % lowest
		else:
			l_float = "WARN  %d pieces floating: they touch neither the bed nor another piece (the lowest is %.1f mm up), so they would print in mid-air" % [floating, lowest]
	else:
		l_float = "OK    floating: every piece rests on the bed or on another piece"
	if bad == 0:
		out.append("OK    Ready to print: all good (walls, overhangs, floating pieces)")
	else:
		out.append("WARN  Ready to print? %d thing%s to look at below. You can still export" % [bad, "" if bad == 1 else "s"])
	out.append(l_thin)
	out.append(l_over)
	out.append(l_float)
	return {"thin": walls, "thinnest": 0.0 if walls == 0 else thinnest, "overhang_cm2": over_cm2, "floating": floating, "lowest": 0.0 if floating == 0 else lowest, "ok": bad == 0, "lines": out}


static func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


static func _find(parent: Dictionary, i: int) -> int:
	var r := i
	while int(parent[r]) != r:
		r = int(parent[r])
	var c := i
	while int(parent[c]) != r:
		var nx := int(parent[c])
		parent[c] = r
		c = nx
	return r


static func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


## the nearest hit of a ray within maxd: [t, triangle] or [-1, -1]. body_only >= 0: only that body's triangles. mode 1: only triangles whose normal opposes the
## ray's start triangle (the far side of a wall); mode 2: only triangles that face up (a solid under a down face)
static func _hit(grid: Dictionary, pa: PackedVector3Array, pb: PackedVector3Array, pc: PackedVector3Array, nn: PackedVector3Array, body: PackedInt32Array, o: Vector3, d: Vector3, maxd: float, self_tri: int, body_only: int, mode: int) -> Array:
	var e := o + d * maxd
	var c0 := _cell(o.min(e) - Vector3(0.01, 0.01, 0.01))
	var c1 := _cell(o.max(e) + Vector3(0.01, 0.01, 0.01))
	var best := INF
	var bj := -1
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			for z in range(c0.z, c1.z + 1):
				var k := Vector3i(x, y, z)
				if not grid.has(k):
					continue
				for j in (grid[k] as Array):
					if j == self_tri or (body_only >= 0 and body[j] != body_only):
						continue
					if mode == 1 and nn[j].dot(d) < 0.0:   # a face looking against the ray is the far side of the wall? no: the far wall's normal points WITH the ray
						continue
					if mode == 2 and nn[j].z <= 0.3:
						continue
					var t := _ray_tri(o, d, pa[j], pb[j], pc[j])
					if t >= 0.0 and t <= maxd and t < best:
						best = t
						bj = j
	return [-1.0, -1] if bj < 0 else [best, bj]


## Moller-Trumbore: the distance along d (unit) to the triangle, or -1
static func _ray_tri(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := d.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-12:
		return -1.0
	var inv := 1.0 / det
	var s := o - a
	var u := s.dot(p) * inv
	if u < -1e-6 or u > 1.0 + 1e-6:
		return -1.0
	var q := s.cross(e1)
	var v := d.dot(q) * inv
	if v < -1e-6 or u + v > 1.0 + 1e-6:
		return -1.0
	var t := e2.dot(q) * inv
	return t if t >= 0.0 else -1.0


static func _point_tri_dist(p: Vector3, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> float:
	var dist := (p - a).dot(n)
	var proj := p - n * dist
	var v0 := c - a
	var v1 := b - a
	var v2 := proj - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d02 := v0.dot(v2)
	var d11 := v1.dot(v1)
	var d12 := v1.dot(v2)
	var den := d00 * d11 - d01 * d01
	if absf(den) > 1e-12:
		var u := (d11 * d02 - d01 * d12) / den
		var w := (d00 * d12 - d01 * d02) / den
		if u >= 0.0 and w >= 0.0 and u + w <= 1.0:
			return absf(dist)
	var m := minf(p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b)), p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
	return minf(m, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))


## do pieces a and b touch (or cross)? a vertex of one on the skin of the other (within 0.05 mm), an edge of one through a face of the other, or one inside the other
static func _touching(a: int, b: int, bmin: Array, bmax: Array, bverts: Array, grid: Dictionary, pa: PackedVector3Array, pb: PackedVector3Array, pc: PackedVector3Array, nn: PackedVector3Array, body: PackedInt32Array, ia: PackedInt32Array, ib: PackedInt32Array, ic: PackedInt32Array) -> bool:
	var amin: Vector3 = (bmin[a] as Vector3) - Vector3(TOUCH_TOL, TOUCH_TOL, TOUCH_TOL)
	var amax: Vector3 = (bmax[a] as Vector3) + Vector3(TOUCH_TOL, TOUCH_TOL, TOUCH_TOL)
	var bmn: Vector3 = bmin[b]
	var bmx: Vector3 = bmax[b]
	if amax.x < bmn.x or bmx.x < amin.x or amax.y < bmn.y or bmx.y < amin.y or amax.z < bmn.z or bmx.z < amin.z:
		return false
	var ta: PackedInt32Array = bverts[a]
	var tb: PackedInt32Array = bverts[b]
	if ta.is_empty() or tb.is_empty():
		return false
	var checks := 0
	for pair in [[ta, tb], [tb, ta]]:
		var src: PackedInt32Array = pair[0]
		var dst: PackedInt32Array = pair[1]
		for i in src:
			for p in [pa[i], pb[i], pc[i]]:
				for j in dst:
					checks += 1
					if checks > 3000000:
						return true   # too big to settle: do not raise a false alarm
					if _point_tri_dist(p, pa[j], pb[j], pc[j], nn[j]) <= TOUCH_TOL:
						return true
	# edges through faces
	var ed := 0
	for i in ta:
		for pair2 in [[pa[i], pb[i]], [pb[i], pc[i]], [pc[i], pa[i]]]:
			for j in tb:
				ed += 1
				if ed > 3000000:
					return true
				if Geometry3D.segment_intersects_triangle(pair2[0], pair2[1], pa[j], pb[j], pc[j]) != null:
					return true
	# one inside the other: the first vertex of a, a ray along +x through b's triangles (odd = inside), and the other way round
	for pair3 in [[ta, tb], [tb, ta]]:
		var i0: int = (pair3[0] as PackedInt32Array)[0]
		var inside := 0
		for j in (pair3[1] as PackedInt32Array):
			var t := _ray_tri(pa[i0], Vector3(0.6, 0.64, 0.48).normalized(), pa[j], pb[j], pc[j])
			if t >= 0.0:
				inside += 1
		if inside % 2 == 1:
			return true
	return false
