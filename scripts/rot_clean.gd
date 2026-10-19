## ROTATION CURVE CLEANUP (ROADMAP 64, "Clean rotation curves"). The exporters write one rotation per frame; a naive
## Euler decomposition wraps at +-180 and flips between the two equivalent solutions, and an engine interpolating
## the numbers spins the limb the long way round. Two passes, both exact (the decoded matrix equals the source):
##  - euler_track: per frame the ZXY angles (BvhExport's channel order, M = Rz Rx Ry) CLOSEST to the previous frame.
##    The canonical solution plus its 360-degree shifts is tried first; where that is not the continuous choice
##    (a wrap, or the alternate solution), the angles are re-solved from the previous frame by damped Gauss-Newton
##    on the 9 matrix entries in float64. Near gimbal lock (middle angle X = +-90) the canonical solution's free
##    angle is noise, so the re-solve is what keeps it continuous; it moves only the free direction there.
##  - hemisphere: quaternion sign continuity, dot(q_i, q_i-1) >= 0.
## clean = false returns the canonical decomposition, unchanged from the old writers.
## xyz = true takes FBX's Euler XYZ order (the FBX writer's eEulerXYZ) instead of BVH's ZXY; the same passes apply.
class_name RotClean
extends RefCounted


## M = Rz(z) Rx(x) Ry(y), row-major, from the angles v = (z, x, y) in radians
static func mat(v: Vector3) -> PackedFloat64Array:
	var cz := cos(v.x)
	var sz := sin(v.x)
	var cx := cos(v.y)
	var sx := sin(v.y)
	var cy := cos(v.z)
	var sy := sin(v.z)
	return PackedFloat64Array([
		cz * cy - sz * sx * sy, -sz * cx, cz * sy + sz * sx * cy,
		sz * cy + cz * sx * sy, cz * cx, sz * sy - cz * sx * cy,
		-cx * sy, sx, cx * cy])


## the matrix of the angles in the chosen order: ZXY (BVH: M = Rz Rx Ry, v = (z, x, y)) or, with xyz, FBX's eEulerXYZ
## (M = Rz(c) Ry(b) Rx(a), v = (a, b, c) = (X, Y, Z)), row-major, radians
static func mat_e(v: Vector3, xyz := false) -> PackedFloat64Array:
	if not xyz:
		return mat(v)
	var ca := cos(v.x)
	var sa := sin(v.x)
	var cb := cos(v.y)
	var sb := sin(v.y)
	var cc := cos(v.z)
	var sc := sin(v.z)
	return PackedFloat64Array([
		cc * cb, cc * sb * sa - sc * ca, cc * sb * ca + sc * sa,
		sc * cb, sc * sb * sa + cc * ca, sc * sb * ca - cc * sa,
		-sb, cb * sa, cb * ca])


## the rotation matrix of a quaternion, row-major, in float64 (the quaternion's own components)
static func mat_of(q: Quaternion) -> PackedFloat64Array:
	var n := q.normalized()
	var x := float(n.x)
	var y := float(n.y)
	var z := float(n.z)
	var w := float(n.w)
	return PackedFloat64Array([
		1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
		2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
		2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)])


## Gauss-Newton from start (radians) to the angles whose matrix is q's: [true, angles] or [false, start].
## The best iterate is kept: the target is a float32 quaternion, so its matrix is orthonormal only to ~1e-7, and near gimbal
## lock the residual valley is flat along the free direction, so the steps wander there.
static func _solve(start: Vector3, q: Quaternion, xyz := false) -> Array:
	var T := mat_of(q)
	var v := start
	var best := start
	var best_res := _resid(start, T, xyz)
	var h := 1e-6
	for _it in 40:
		if best_res < 1e-9:
			break
		# Jacobian columns (9 entries each), central differences
		var J := []
		for c in 3:
			var dv := Vector3.ZERO
			dv[c] = h
			var Mp := mat_e(v + dv, xyz)
			var Mm := mat_e(v - dv, xyz)
			var col := PackedFloat64Array()
			for k in 9:
				col.append((Mp[k] - Mm[k]) / (2.0 * h))
			J.append(col)
		var M := mat_e(v, xyz)
		var r := PackedFloat64Array()
		for k in 9:
			r.append(M[k] - T[k])
		# normal equations (JtJ + lambda I) d = -Jt r, solved by Cramer's rule
		var A := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		var g := [0.0, 0.0, 0.0]
		for a in 3:
			for b in 3:
				var s := 0.0
				for k in 9:
					s += (J[a] as PackedFloat64Array)[k] * (J[b] as PackedFloat64Array)[k]
				A[a][b] = s
			var t := 0.0
			for k in 9:
				t += (J[a] as PackedFloat64Array)[k] * r[k]
			g[a] = -t
		var lam: float = 1e-12 * (1.0 + float(A[0][0]) + float(A[1][1]) + float(A[2][2]))
		for a in 3:
			A[a][a] += lam
		var d := _cramer(A, g)
		if not d[0]:
			break
		var step := Vector3(d[1], d[2], d[3])
		v += step
		var res := _resid(v, T, xyz)
		if res < best_res:
			best_res = res
			best = v
		if maxf(absf(step.x), maxf(absf(step.y), absf(step.z))) < 1e-9:
			break
	return [best_res < 1e-6, best]


static func _resid(v: Vector3, T: PackedFloat64Array, xyz := false) -> float:
	var M := mat_e(v, xyz)
	var res := 0.0
	for k in 9:
		res = maxf(res, absf(M[k] - T[k]))
	return res


## 3x3 solve A x = b by Cramer's rule: [ok, x0, x1, x2]
static func _cramer(A: Array, b: Array) -> Array:
	var det := _det3(A)
	if absf(det) < 1e-300:
		return [false, 0.0, 0.0, 0.0]
	var out := [true, 0.0, 0.0, 0.0]
	for c in 3:
		var B := [[A[0][0], A[0][1], A[0][2]], [A[1][0], A[1][1], A[1][2]], [A[2][0], A[2][1], A[2][2]]]
		for rr in 3:
			B[rr][c] = b[rr]
		out[c + 1] = _det3(B) / det
	return out


static func _det3(M: Array) -> float:
	return M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1]) - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0]) + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0])


## the largest entry difference (deg) between q's matrix and the matrix of the ZXY Euler triple e (deg), in float64
static func err64(q: Quaternion, e: Vector3, xyz := false) -> float:
	var A := mat_of(q)
	var B := mat_e(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)), xyz)
	var m := 0.0
	for k in 9:
		m = maxf(m, absf(A[k] - B[k]))
	return rad_to_deg(m)


## the per-frame ZXY Euler angles (degrees) of one joint's rotations, qs[i] = the frame i rotation.
## clean = false: the canonical solution of each frame (BvhExport.zxy).
static func euler_track(qs: Array, clean := true, xyz := false) -> Array:
	var out := []
	var prev := Vector3.ZERO   # degrees, the last written frame
	for i in qs.size():
		var q: Quaternion = qs[i]   # the writers normalize their rotations already (a second pass would move the last bits)
		var e: Vector3 = FbxExport._euler_deg(Transform3D(Basis(q), Vector3.ZERO)) if xyz else BvhExport.zxy(q)
		if clean and i > 0:
			# the canonical solution shifted by whole turns, nearest to the previous frame
			var c := e
			for k in 3:
				var turns := roundf((prev[k] - c[k]) / 360.0)
				if turns != 0.0:   # a zero stays as it was (-0.0 + 0.0 would print as 0.00000 where the canonical text has -0.00000)
					c[k] += 360.0 * turns
			var mc := err64(q, c, xyz)
			var sol: Array = _solve(prev * (PI / 180.0), q, xyz)
			if sol[0]:
				var v: Vector3 = sol[1]
				var th := v * (180.0 / PI)
				# the canonical shift when it is the same solution at the float32 accuracy of the source (so a frame that is
				# not a flip keeps its text); otherwise the continuous solution (the free direction of a gimbal lock, where the
				# canonical solution is ~1e-4 deg off, or a flip's other branch)
				var d := maxf(absf(c.x - th.x), maxf(absf(c.y - th.y), absf(c.z - th.z)))
				e = c if (d < 1e-3 and mc <= err64(q, th, xyz) + 5e-5) else th
			else:
				e = c
		out.append(e)
		prev = e
	return out


## quaternion sign continuity: a frame whose dot with the previous (written) frame is negative is negated
static func hemisphere(qs: Array, clean := true) -> Array:
	var out := []
	var prev := Quaternion.IDENTITY
	for i in qs.size():
		var q: Quaternion = qs[i]
		if clean and i > 0 and q.dot(prev) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		out.append(q)
		prev = q
	return out
