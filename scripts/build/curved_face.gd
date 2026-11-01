class_name CurvedFace
extends RefCounted
## s211 DRAW ON A CURVED FACE (Easy Part): the tangent plane at a clicked point of a curved face of the shown mesh.
## The mesh is a tessellation (a cylinder is ~25 flat strips), so the true surface is FITTED to the connected smooth patch under the press:
## a sphere (least squares on its vertices), a cylinder (the axis is the direction every normal is square to; a circle fit across it), else
## the Phong blend of the corner normals. A fitted surface puts the plane's origin exactly ON the surface (a 10 mm rod: 5.000 mm from its axis,
## not the 4.96 mm of a flat strip) and its normal exactly radial. All lengths here are metres, like the mesh.
##   hit(tris, ro, rd, cam_right, cam_up) -> {} (no triangle under the ray) or
##   {"o": the point on the surface, "n": the unit normal (the side the eye sees), "x": the in-plane x (the cylinder's axis, else along the screen's right),
##    "kind": "cyl" | "sph" | "flat" | "smooth", "r": radius (cyl, sph), "convex": bool, "dist": ray distance, "tris": triangles in the patch}

const ANG_MAX := 40.0   # deg: neighbouring triangles bending by less than this belong to one smooth face (as _face_hit_at reads a curved face)


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1e6), roundi(v.y * 1e6), roundi(v.z * 1e6))


static func hit(tris: PackedVector3Array, ro: Vector3, rd: Vector3, cam_right: Vector3, cam_up: Vector3) -> Dictionary:
	var best := INF
	var bk := -1
	var bh := Vector3.ZERO
	for k in range(0, tris.size() - 2, 3):
		var h: Variant = SkinPick.ray_tri_mm(ro, rd, tris[k], tris[k + 1], tris[k + 2])
		if h != null and ro.distance_to(h as Vector3) < best:
			best = ro.distance_to(h as Vector3)
			bk = k
			bh = h
	if bk < 0:
		return {}
	# vertex ids by position, edges by their two ids, triangle normals
	var nt := tris.size() / 3
	var vid := {}
	var vpos: Array = []
	var ids := PackedInt32Array()
	ids.resize(tris.size())
	for i in tris.size():
		var key := _key(tris[i])
		if not vid.has(key):
			vid[key] = vpos.size()
			vpos.append(tris[i])
		ids[i] = vid[key]
	var nrm := PackedVector3Array()
	nrm.resize(nt)
	var edges := {}
	for t in nt:
		var a := tris[3 * t]
		nrm[t] = (tris[3 * t + 1] - a).cross(tris[3 * t + 2] - a).normalized()
		for e in 3:
			var i0 := ids[3 * t + e]
			var i1 := ids[3 * t + (e + 1) % 3]
			var ek: int = (mini(i0, i1) << 32) | maxi(i0, i1)
			if edges.has(ek):
				(edges[ek] as Array).append(t)
			else:
				edges[ek] = [t]
	var t0 := bk / 3
	var sgn := -1.0 if nrm[t0].dot(rd) > 0.0 else 1.0   # the normals as the eye sees them (the eye side of the hit triangle)
	var cos_max := cos(deg_to_rad(ANG_MAX))
	var seen := {t0: true}
	var queue: Array = [t0]
	var qi := 0
	while qi < queue.size():
		var t: int = queue[qi]
		qi += 1
		for e in 3:
			var i0 := ids[3 * t + e]
			var i1 := ids[3 * t + (e + 1) % 3]
			for u in edges[(mini(i0, i1) << 32) | maxi(i0, i1)]:
				if seen.has(u):
					continue
				if nrm[t].dot(nrm[u]) >= cos_max:
					seen[u] = true
					queue.append(u)
	var n0: Vector3 = nrm[t0] * sgn
	var pv := {}   # the patch's vertices
	var all_n := PackedVector3Array()
	var planar := true
	for t in queue:
		all_n.append(nrm[t] * sgn)
		if nrm[t].dot(nrm[t0]) < 0.99996:
			planar = false
		for e in 3:
			pv[ids[3 * t + e]] = true
	var out := {"dist": best, "tris": queue.size()}
	if planar:   # a tilted flat face: its own plane
		out.merge({"o": bh, "n": n0, "kind": "flat", "r": 0.0, "convex": true}, true)
		out["x"] = _in_plane_x(n0, Vector3.ZERO, cam_right, cam_up)
		return out
	var pts: Array = []
	var mean := Vector3.ZERO
	for i in pv.keys():
		pts.append(vpos[i])
		mean += vpos[i]
	mean /= float(pts.size())
	# a CYLINDER: the axis is square to every normal (the smallest direction of their spread)
	var ax := _min_axis(all_n)
	var square := true
	for v in all_n:
		if absf(v.dot(ax)) > 0.03:
			square = false
			break
	if square:
		var cyl := _fit_circle(pts, mean, ax)
		if not cyl.is_empty():
			var c0: Vector3 = cyl["c"]
			var q := bh - c0
			q -= ax * q.dot(ax)
			var rad := q.normalized()
			var convex := rad.dot(n0) > 0.0
			var n := rad if convex else -rad
			var xa := ax
			if absf(xa.dot(cam_right)) >= 0.2:
				xa = xa if xa.dot(cam_right) > 0.0 else -xa
			else:
				xa = xa if xa.dot(cam_up) > 0.0 else -xa
			out.merge({"o": bh - q + rad * float(cyl["r"]), "n": n, "x": xa, "kind": "cyl", "r": float(cyl["r"]), "convex": convex, "axis": ax, "axis_pt": c0}, true)
			return out
	# a SPHERE: |p|^2 = 2 c.p + k  (centred at the mean)
	var sph := _fit_sphere(pts, mean)
	if not sph.is_empty():
		var c: Vector3 = sph["c"]
		var rad: Vector3 = (bh - c).normalized()
		var convex := rad.dot(n0) > 0.0
		var n := rad if convex else -rad
		out.merge({"o": c + rad * float(sph["r"]), "n": n, "kind": "sph", "r": float(sph["r"]), "convex": convex}, true)
		out["x"] = _in_plane_x(n, Vector3.ZERO, cam_right, cam_up)
		return out
	# anything else smooth: the Phong blend of the corner normals (each corner's tangent plane, weighted by the hit's barycentre)
	var corner_n: Array = []
	for e in 3:
		var vi := ids[bk + e]
		var s := Vector3.ZERO
		for t in queue:
			if ids[3 * t] == vi or ids[3 * t + 1] == vi or ids[3 * t + 2] == vi:
				s += nrm[t] * sgn
		corner_n.append(s.normalized())
	var a0 := tris[bk]
	var b0 := tris[bk + 1]
	var c1 := tris[bk + 2]
	var w := _bary(bh, a0, b0, c1)
	var nn: Vector3 = (corner_n[0] * w.x + corner_n[1] * w.y + corner_n[2] * w.z).normalized()
	var pos := Vector3.ZERO
	var corners := [a0, b0, c1]
	for e in 3:
		var cn: Vector3 = corner_n[e]
		pos += (bh - cn * (bh - (corners[e] as Vector3)).dot(cn)) * w[e]
	out.merge({"o": pos, "n": nn, "kind": "smooth", "r": 0.0, "convex": true}, true)
	out["x"] = _in_plane_x(nn, Vector3.ZERO, cam_right, cam_up)
	return out


static func _in_plane_x(n: Vector3, _unused: Vector3, cam_right: Vector3, cam_up: Vector3) -> Vector3:
	var x := cam_right - n * cam_right.dot(n)
	if x.length() < 0.2:
		x = cam_up - n * cam_up.dot(n)
	return x.normalized()


static func _bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-30:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / den
	var w := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)


## Gaussian elimination with partial pivoting: A x = b (A as rows). [] when singular
static func _solve(a: Array, b: Array) -> Array:
	var n := b.size()
	for i in n:
		var piv := i
		for r in range(i + 1, n):
			if absf(a[r][i]) > absf(a[piv][i]):
				piv = r
		if absf(a[piv][i]) < 1e-30:
			return []
		var tmp: Array = a[i]
		a[i] = a[piv]
		a[piv] = tmp
		var tb: float = b[i]
		b[i] = b[piv]
		b[piv] = tb
		for r in range(i + 1, n):
			var f: float = a[r][i] / a[i][i]
			for c in range(i, n):
				a[r][c] -= f * a[i][c]
			b[r] -= f * b[i]
	var x: Array = []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = b[i]
		for c in range(i + 1, n):
			s -= a[i][c] * x[c]
		x[i] = s / a[i][i]
	return x


## a sphere through the points, or {} when they do not lie on one (relative misfit above 2e-4 of the radius)
static func _fit_sphere(pts: Array, mean: Vector3) -> Dictionary:
	var m4 := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	var rhs := [0.0, 0.0, 0.0, 0.0]
	for p in pts:
		var q: Vector3 = (p as Vector3) - mean
		var row := [2.0 * q.x, 2.0 * q.y, 2.0 * q.z, 1.0]
		var rr := q.length_squared()
		for i in 4:
			for j in 4:
				m4[i][j] += row[i] * row[j]
			rhs[i] += row[i] * rr
	var s := _solve(m4, rhs)
	if s.is_empty():
		return {}
	var c := Vector3(s[0], s[1], s[2])
	var r2: float = s[3] + c.length_squared()
	if r2 <= 1e-12:
		return {}
	var r := sqrt(r2)
	for p in pts:
		if absf((((p as Vector3) - mean) - c).length() - r) > 2e-4 * r + 1e-7:
			return {}
	return {"c": c + mean, "r": r}


## a circle through the points seen along `ax`, or {} when they do not lie on one
static func _fit_circle(pts: Array, mean: Vector3, ax: Vector3) -> Dictionary:
	var helper := Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := ax.cross(helper).normalized()
	var v := ax.cross(u).normalized()
	var m3 := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var rhs := [0.0, 0.0, 0.0]
	for p in pts:
		var q: Vector3 = (p as Vector3) - mean
		var pu := q.dot(u)
		var pw := q.dot(v)
		var row := [2.0 * pu, 2.0 * pw, 1.0]
		var rr := pu * pu + pw * pw
		for i in 3:
			for j in 3:
				m3[i][j] += row[i] * row[j]
			rhs[i] += row[i] * rr
	var s := _solve(m3, rhs)
	if s.is_empty():
		return {}
	var r2: float = s[2] + s[0] * s[0] + s[1] * s[1]
	if r2 <= 1e-12:
		return {}
	var r := sqrt(r2)
	for p in pts:
		var q: Vector3 = (p as Vector3) - mean
		if absf(Vector2(q.dot(u) - s[0], q.dot(v) - s[1]).length() - r) > 2e-4 * r + 1e-7:
			return {}
	return {"c": mean + u * s[0] + v * s[1], "r": r}


## the direction the (unit) normals spread the least in: the smallest eigenvector of sum(n n^T), by cyclic Jacobi
static func _min_axis(ns: PackedVector3Array) -> Vector3:
	var a := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for n in ns:
		var c := [n.x, n.y, n.z]
		for i in 3:
			for j in 3:
				a[i][j] += c[i] * c[j]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	for _sweep in 40:
		if absf(a[0][1]) + absf(a[0][2]) + absf(a[1][2]) < 1e-12:
			break
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-18:
				continue
			var th: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
			var t: float = (1.0 if th >= 0.0 else -1.0) / (absf(th) + sqrt(th * th + 1.0))
			var c := 1.0 / sqrt(t * t + 1.0)
			var s := t * c
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[k][q] = s * akp + c * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
			for k in 3:
				var vkp: float = v[k][p]
				var vkq: float = v[k][q]
				v[k][p] = c * vkp - s * vkq
				v[k][q] = s * vkp + c * vkq
	var best := 0
	for i in 3:
		if a[i][i] < a[best][best]:
			best = i
	return Vector3(v[0][best], v[1][best], v[2][best]).normalized()


## how far (mm) the curved surface falls away from its tangent plane at the in-plane point (u, v) mm: the gap a flat shape of that size leaves
## under its edge. kind "cyl": across the axis only (v); "sph": by the distance from the click. A concave face or a non-fitted one has none
static func sag(kind: String, r_mm: float, convex: bool, u: float, v: float) -> float:
	if r_mm <= 0.0 or not convex:
		return 0.0
	var d2 := v * v if kind == "cyl" else (u * u + v * v if kind == "sph" else 0.0)
	return r_mm - sqrt(maxf(r_mm * r_mm - d2, 0.0))


## the gap (mm) from the tangent plane `pl` (o, x, y, n in metres) to the mesh `tris` under the in-plane point (u, v) mm, along -n; 0 when none
static func sag_mesh(tris: PackedVector3Array, pl: Dictionary, u: float, v: float) -> float:
	var up := 0.01
	var w: Vector3 = (pl["o"] as Vector3) + (pl["x"] as Vector3) * (u * 0.001) + (pl["y"] as Vector3) * (v * 0.001) + (pl["n"] as Vector3) * up
	var best := INF
	for k in range(0, tris.size() - 2, 3):
		var h: Variant = SkinPick.ray_tri_mm(w, -(pl["n"] as Vector3), tris[k], tris[k + 1], tris[k + 2])
		if h != null:
			best = minf(best, w.distance_to(h as Vector3))
	return clampf((best - up) * 1000.0, 0.0, 30.0) if best < INF else 0.0
