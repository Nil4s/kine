## MULTI-CAMERA VIDEO MOCAP (roadmap 89). Two or more cameras film one person; each camera's tracker (tools/see_video.py,
## MediaPipe, the same pose.json as the single-view import) gives 2D keypoints per frame. This module:
##   1 CAMERAS: a pinhole camera per view. Intrinsics from the picture's size and a horizontal field of view (HFOV_DEFAULT
##     unless the caller knows better; a phone is 65-70 deg); no lens distortion. Extrinsics: the cameras on a ring around
##     the subject, each looking at TARGET. Camera 0 is the gauge: yaw 0 and pitch 0, its radius sets the scale.
##   2 EXTRINSICS SOLVED (solve_extrinsics): the rig's yaws, pitches and radii are searched (coordinate descent) to minimise
##     the reprojection error of the triangulated joints PLUS a bone-length term: each bone must match its known length
##     (the body's rest length, scaled to the person). The bone lengths are what fix the scale that 2D views cannot.
##   3 TRIANGULATION (triangulate): each joint by weighted DLT (Hartley & Zisserman 12.2: the linear system from every view's
##     two equations, weights = the keypoint's confidence, rows re-weighted by depth so the residual is in pixels). A view
##     whose reprojection error is over OUTLIER_PX is dropped and the joint solved again, while two views remain.
##     Confidence 0 (occluded) drops the view outright.
##   4 OUT: triangulate_all gives frames {"t", "w"} in the layout VideoImport.parse makes (33 world points, y up, hips at 0),
##     so the existing VideoCleanup -> VideoImport.solve path takes them unchanged.
## Input is the person's own video, tracked by tools/see_video.py run with python -I (track_args). Nothing here reads a video.
class_name MultiCam
extends RefCounted

const OUTLIER_PX := 8.0     # px: a view this far off a joint's solution is dropped (2 px per-coordinate noise: 8 px is ~3 sigma)
const MIN_VIEWS := 2        # a joint needs two views to be triangulated
const HFOV_DEFAULT := 60.0  # deg: horizontal field of view assumed when the lens is unknown (a phone is 65-70)
const BONE_K := 1.0e5       # the bone-length term's weight: 1 % of a bone's length off costs 10 px^2 of reprojection
const TARGET := Vector3(0.0, 0.9, 0.0)   # what every camera looks at: the middle of a standing body (m, y up)
## the landmarks triangulated (MediaPipe's numbering): the head, ears, shoulders, elbows, wrists, hips, knees, ankles,
## heels and toes. The rest (eyes, mouth, fingers) are not reconstructed and stay 0
const JOINTS := [0, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
## the bones the rig is checked against: [a, b] landmark pairs (MediaPipe's numbering)
const BONES := [[11, 13], [13, 15], [12, 14], [14, 16], [23, 25], [25, 27], [24, 26], [26, 28], [11, 23], [12, 24], [11, 12], [23, 24]]


## a camera's intrinsics from the picture's size: focal length in px from the horizontal field of view, the centre of the picture
static func intrinsics(W: int, H: int, hfov := HFOV_DEFAULT) -> Dictionary:
	return {"W": W, "H": H, "f": (W * 0.5) / tan(deg_to_rad(hfov) * 0.5), "cx": W * 0.5, "cy": H * 0.5}


## a camera at C looking at target. B is camera-to-world (its columns: right, up, and back; the camera looks down -z)
static func cam_at(name: String, K: Dictionary, C: Vector3, target: Vector3) -> Dictionary:
	return {"name": name, "K": K, "C": C, "B": Basis.looking_at(target - C, Vector3.UP)}


## a camera on a ring about target: yaw about the vertical (deg, 0 = the +z side), pitch above the horizon (deg), radius (m)
static func on_ring(name: String, K: Dictionary, yaw: float, pitch: float, r: float, target := TARGET) -> Dictionary:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var C := target + r * Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y))
	return cam_at(name, K, C, target)


## the rig from its parameters: p = [pitch0, r0, yaw1, pitch1, r1, yaw2, pitch2, r2, ...] (deg, m). Camera 0 is at yaw 0 (the
## yaw gauge: a turn about the vertical moves nothing the fit can see), but its PITCH is free: gravity and the floor fix it
## (see _cost), not the gauge
static func rig(Ks: Array, p: Array, target := TARGET) -> Array:
	var cams := []
	cams.append(on_ring("cam0", Ks[0], 0.0, float(p[0]), float(p[1]), target))
	for c in range(1, Ks.size()):
		var k := 2 + 3 * (c - 1)
		cams.append(on_ring("cam%d" % c, Ks[c], float(p[k]), float(p[k + 1]), float(p[k + 2]), target))
	return cams


## a world point in a camera: Vector3(u px, v px, depth m; depth <= 0 is behind the lens)
static func project(cam: Dictionary, X: Vector3) -> Vector3:
	var K: Dictionary = cam["K"]
	var B: Basis = cam["B"]
	var d: Vector3 = X - (cam["C"] as Vector3)
	var xc := B.x.dot(d)
	var yc := B.y.dot(d)
	var depth := -B.z.dot(d)
	if depth <= 1e-6:
		return Vector3(0.0, 0.0, depth)
	var f: float = K["f"]
	return Vector3(float(K["cx"]) + f * xc / depth, float(K["cy"]) - f * yc / depth, depth)


## the reprojection error (px) of world point X in one view {"c", "uv", "w"}
static func _err(cams: Array, vw: Dictionary, X: Vector3) -> float:
	var q := project(cams[vw["c"]], X)
	if q.z <= 0.0:
		return 1.0e9
	return Vector2(q.x, q.y).distance_to(vw["uv"])


## one weighted DLT solve over the views. For a camera, two rows: a1 = f*bx + (u-cx)*bz and a2 = f*by + (cy-v)*bz, each with
## a1.(X - C) = 0. Least squares over the rows, weight = the keypoint's confidence; rows scaled by 1/|a| first, then by 1/depth
## (the second and third passes), so the residual is in pixels. Returns the point, or null when the views cannot fix it
static func _solve(cams: Array, views: Array) -> Variant:
	var X: Variant = null
	for it in 3:
		var m00 := 0.0
		var m01 := 0.0
		var m02 := 0.0
		var m11 := 0.0
		var m12 := 0.0
		var m22 := 0.0
		var rhs := Vector3.ZERO
		for vw in views:
			var cam: Dictionary = cams[vw["c"]]
			var K: Dictionary = cam["K"]
			var B: Basis = cam["B"]
			var C: Vector3 = cam["C"]
			var f: float = K["f"]
			var u: float = (vw["uv"] as Vector2).x
			var v: float = (vw["uv"] as Vector2).y
			var wt: float = vw["w"]
			var rows := [f * B.x + (u - float(K["cx"])) * B.z, f * B.y + (float(K["cy"]) - v) * B.z]
			for a: Vector3 in rows:
				var s := 1.0 / maxf(a.length(), 1e-9)
				if X != null:
					s = 1.0 / maxf(absf(-B.z.dot((X as Vector3) - C)), 1e-3)
				var r := a * s
				m00 += wt * r.x * r.x
				m01 += wt * r.x * r.y
				m02 += wt * r.x * r.z
				m11 += wt * r.y * r.y
				m12 += wt * r.y * r.z
				m22 += wt * r.z * r.z
				rhs += r * (wt * r.dot(C))
		var M := Basis(Vector3(m00, m01, m02), Vector3(m01, m11, m12), Vector3(m02, m12, m22))
		if absf(M.determinant()) < 1e-24:
			return null
		X = M.inverse() * rhs
	return X


## one joint: the views (each {"c": camera index, "uv": px, "w": confidence}) with w > 0, solved, the worst view dropped
## while its error is over OUTLIER_PX and more than MIN_VIEWS remain. Returns {"ok", "X", "used" (views), "errs" (px, per
## used view), "rms" (px), "rejected" (views dropped)}
static func triangulate(cams: Array, views: Array) -> Dictionary:
	var act := []
	for vw in views:
		if float(vw["w"]) > 0.0:
			act.append(vw)
	var rejected := 0
	var X: Variant = null
	while act.size() >= MIN_VIEWS:
		X = _solve(cams, act)
		if X == null:
			break
		var worst := -1
		var we := -1.0
		for i in act.size():
			var e := _err(cams, act[i], X as Vector3)
			if e > we:
				we = e
				worst = i
		if we > OUTLIER_PX and act.size() > MIN_VIEWS:
			act.remove_at(worst)
			rejected += 1
			continue
		break
	if X == null or act.size() < MIN_VIEWS:
		return {"ok": false, "X": Vector3.ZERO, "used": [], "errs": [], "rms": -1.0, "rejected": rejected}
	var errs := []
	var ss := 0.0
	for vw in act:
		var e := _err(cams, vw, X as Vector3)
		errs.append(e)
		ss += e * e
	return {"ok": true, "X": X, "used": act, "errs": errs, "rms": sqrt(ss / act.size()), "rejected": rejected}


## one frame: obs_cams[c] = {"uv": 33 Vector2 px, "conf": 33 floats} or null (no picture from that camera). Returns the
## per-joint results (the triangulate dictionary) for every joint in `joints`
static func triangulate_frame(cams: Array, obs_cams: Array, joints := JOINTS) -> Dictionary:
	var res := {}
	for j in joints:
		var views := []
		for c in obs_cams.size():
			var co = obs_cams[c]
			if co == null:
				continue
			views.append({"c": c, "uv": (co["uv"] as Array)[j], "w": float((co["conf"] as Array)[j])})
		res[j] = triangulate(cams, views)
	return res


## every frame. obs = [{"t", "cams": [...]}] (see triangulate_frame). A joint that cannot be solved holds its last value.
## Returns {"ok", "frames": [{"t", "w"}] (33 points, hips at 0, y up: VideoImport.parse's layout), "hips": the hips' midpoint
## before that centring (rig world), "rms": per frame px,
## "mean_rms" px, "cam_rms": per camera px, "rejected": views dropped, "fails": joint solves that failed}
static func triangulate_all(cams: Array, obs: Array, joints := JOINTS) -> Dictionary:
	var frames := []
	var hips := []
	var rms := []
	var cam_ss := []
	var cam_n := []
	for c in cams.size():
		cam_ss.append(0.0)
		cam_n.append(0)
	var rejected := 0
	var fails := 0
	var last := []
	for i in 33:
		last.append(Vector3.ZERO)
	for fr in obs:
		var res := triangulate_frame(cams, fr["cams"], joints)
		var X := []
		for i in 33:
			X.append(Vector3.ZERO)
		var ss := 0.0
		var nn := 0
		for j in joints:
			var r: Dictionary = res[j]
			rejected += int(r["rejected"])
			if r["ok"]:
				X[j] = r["X"]
				last[j] = r["X"]
				for k in r["used"].size():
					var e: float = r["errs"][k]
					ss += e * e
					nn += 1
					cam_ss[r["used"][k]["c"]] += e * e
					cam_n[r["used"][k]["c"]] += 1
			else:
				fails += 1
				X[j] = last[j]
		var hip: Vector3 = ((X[23] as Vector3) + (X[24] as Vector3)) * 0.5
		hips.append(hip)
		var w := []
		for i in 33:
			w.append(((X[i] as Vector3) - hip) if joints.has(i) else Vector3.ZERO)
		frames.append({"t": float(fr["t"]), "w": w})
		rms.append(sqrt(ss / maxi(nn, 1)))
	var mean := 0.0
	for r in rms:
		mean += float(r)
	mean /= maxf(1.0, float(rms.size()))
	var cam_rms := []
	for c in cams.size():
		cam_rms.append(sqrt(float(cam_ss[c]) / maxi(int(cam_n[c]), 1)))
	return {"ok": frames.size() >= 2, "frames": frames, "hips": hips, "rms": rms, "mean_rms": mean, "cam_rms": cam_rms,
		"rejected": rejected, "fails": fails}


## the rig's fit to the observations. Four terms, all in the rig's own frame (its world is gravity-up by the constraints below):
##   reprojection: mean squared error (px^2) over every used view
##   bones: BONE_K x the mean squared (ratio - 1) over the bones in `pairs` ([a, b, metres]): this fixes the scale
##   gravity: the standing body's trunk is vertical ON AVERAGE over the clip (a person stands; a tilted camera tilts the
##     whole body): GRAV_K x the squared horizontal part of the mean trunk direction. This is what identifies the cameras'
##     pitch. It needs a STANDING clip: a walker leans forward ~4-5 deg on average and would read as a tilted rig
##   floor: the lowest sole (heel or toe, either foot) is at one height in every frame: FLOOR_K x its variance (m^2). A
##     rig that is wrong in yaw or pitch makes the stance foot rise and fall
const GRAV_K := 1.0e5
const FLOOR_K := 1.0e5
static var _parts := []   # the last _cost's four terms (reprojection, bones, gravity, floor): for the test's printout
static func _cost(Ks: Array, p: Array, sub: Array, pairs: Array) -> float:
	var cams := rig(Ks, p)
	var ss := 0.0
	var nn := 0
	var bl := 0.0
	var nb := 0
	var trunk := Vector3.ZERO
	var nt := 0
	var floor_h := []
	var blen := []   # per bone: the sum of its length over the frames (a rigid bone is one length: the per-frame noise averages out)
	var bn := []
	for pr in pairs:
		blen.append(0.0)
		bn.append(0)

	for fr in sub:
		var X := {}
		for j in JOINTS:
			var views := []
			for c in fr["cams"].size():
				var co = fr["cams"][c]
				if co != null and float((co["conf"] as Array)[j]) > 0.0:
					views.append({"c": c, "uv": (co["uv"] as Array)[j], "w": float((co["conf"] as Array)[j])})
			var r := triangulate(cams, views)
			# every view counts, the rejected ones too, each truncated at OUTLIER_PX^2: a wrong rig must not win by having
			# its bad views dropped as outliers (the rejection made the cost drop with a worse rig)
			var solved: bool = r["ok"]
			if solved:
				X[j] = r["X"]
			for vw in views:
				var e := 0.0
				if solved:
					e = minf(_err(cams, vw, r["X"] as Vector3), OUTLIER_PX)
				else:
					e = OUTLIER_PX
				ss += e * e
				nn += 1
		for k in pairs.size():
			var pr: Array = pairs[k]
			if X.has(pr[0]) and X.has(pr[1]):
				blen[k] += ((X[pr[0]] as Vector3) - (X[pr[1]] as Vector3)).length()
				bn[k] += 1
		if X.has(11) and X.has(12) and X.has(23) and X.has(24):
			var hip: Vector3 = ((X[23] as Vector3) + (X[24] as Vector3)) * 0.5
			trunk += ((((X[11] as Vector3) + (X[12] as Vector3)) * 0.5) - hip).normalized()
			nt += 1
		if X.has(29) and X.has(30) and X.has(31) and X.has(32):
			floor_h.append(minf(minf((X[29] as Vector3).y, (X[30] as Vector3).y), minf((X[31] as Vector3).y, (X[32] as Vector3).y)))
	for k in pairs.size():
		if int(bn[k]) > 0:
			var ratio := (float(blen[k]) / float(bn[k])) / float(pairs[k][2])
			bl += (ratio - 1.0) * (ratio - 1.0)
			nb += 1
	var grav := 0.0
	if nt > 0:
		var tm := Vector2(trunk.x, trunk.z) / float(nt)
		grav = tm.length_squared()
	var fvar := 0.0
	if floor_h.size() > 1:
		var m := 0.0
		for h in floor_h:
			m += float(h)
		m /= floor_h.size()
		for h in floor_h:
			fvar += (float(h) - m) * (float(h) - m)
		fvar /= floor_h.size()
	_parts = [ss / maxf(float(nn), 1.0), BONE_K * bl / maxf(float(nb), 1.0), GRAV_K * grav, FLOOR_K * fvar]
	return ss / maxf(float(nn), 1.0) + BONE_K * bl / maxf(float(nb), 1.0) + GRAV_K * grav + FLOOR_K * fvar


## the same four terms as _cost, as RESIDUALS (a sum of squares: the reprojection error of every view in px, the bone
## ratios x sqrt(BONE_K), the gravity x sqrt(GRAV_K), the floor's deviation per frame x sqrt(FLOOR_K / frames)). Every view
## is kept (no outlier cut): the fit must be smooth in the rig's parameters for the Jacobian
static func _resid(Ks: Array, p: Array, sub: Array, pairs: Array) -> Array:
	var cams := rig(Ks, p)
	var out := []
	var blen := []
	var bn := []
	for pr in pairs:
		blen.append(0.0)
		bn.append(0)
	var tm := Vector2.ZERO
	var nt := 0
	var floor_h := []
	for fr in sub:
		var X := {}
		for j in JOINTS:
			var views := []
			for c in fr["cams"].size():
				var co = fr["cams"][c]
				if co != null and float((co["conf"] as Array)[j]) > 0.0:
					views.append({"c": c, "uv": (co["uv"] as Array)[j], "w": float((co["conf"] as Array)[j])})
			var Xj = _solve(cams, views)
			if Xj == null:
				for vw in views:
					out.append(0.0)
					out.append(0.0)
				continue
			X[j] = Xj
			for vw in views:
				var q := project(cams[vw["c"]], Xj as Vector3)
				out.append(q.x - (vw["uv"] as Vector2).x)
				out.append(q.y - (vw["uv"] as Vector2).y)
		for k in pairs.size():
			var pr: Array = pairs[k]
			if X.has(pr[0]) and X.has(pr[1]):
				blen[k] += ((X[pr[0]] as Vector3) - (X[pr[1]] as Vector3)).length()
				bn[k] += 1
		if X.has(11) and X.has(12) and X.has(23) and X.has(24):
			var hip: Vector3 = ((X[23] as Vector3) + (X[24] as Vector3)) * 0.5
			var d: Vector3 = ((((X[11] as Vector3) + (X[12] as Vector3)) * 0.5) - hip).normalized()
			tm += Vector2(d.x, d.z)
			nt += 1
		if X.has(29) and X.has(30) and X.has(31) and X.has(32):
			floor_h.append(minf(minf((X[29] as Vector3).y, (X[30] as Vector3).y), minf((X[31] as Vector3).y, (X[32] as Vector3).y)))
	for k in pairs.size():
		if int(bn[k]) > 0:
			out.append(sqrt(BONE_K) * ((float(blen[k]) / float(bn[k])) / float(pairs[k][2]) - 1.0))
	if nt > 0:
		out.append(sqrt(GRAV_K) * tm.x / float(nt))
		out.append(sqrt(GRAV_K) * tm.y / float(nt))
	if floor_h.size() > 1:
		var m := 0.0
		for h in floor_h:
			m += float(h)
		m /= floor_h.size()
		for h in floor_h:
			out.append(sqrt(FLOOR_K / float(floor_h.size())) * (float(h) - m))
	return out


static func _ss(r: Array) -> float:
	var t := 0.0
	for x in r:
		t += float(x) * float(x)
	return t


## the linear system A x = b (Gauss-Jordan, partial pivoting); zeros when it is singular
static func _solve_lin(A: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for i in n:
		var row: Array = (A[i] as Array).duplicate()
		row.append(b[i])
		M.append(row)
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf(float(M[r][c])) > absf(float(M[piv][c])):
				piv = r
		var tmp = M[c]
		M[c] = M[piv]
		M[piv] = tmp
		var d := float(M[c][c])
		if absf(d) < 1e-30:
			var z := []
			for i in n:
				z.append(0.0)
			return z
		for r in n:
			if r != c:
				var f := float(M[r][c]) / d
				for k in range(c, n + 1):
					M[r][k] = float(M[r][k]) - f * float(M[c][k])
	var x := []
	for i in n:
		x.append(float(M[i][n]) / float(M[i][i]))
	return x


## Levenberg-Marquardt on _resid from p0: the Jacobian by forward differences, the damping (lambda) up after a rejected step
## and down after an accepted one. Returns {"p", "cost" (sum of squares), "sweeps" (iterations)}
static func _lm(Ks: Array, p0: Array, sub: Array, pairs: Array, iters: int) -> Dictionary:
	var p := p0.duplicate()
	var r := _resid(Ks, p, sub, pairs)
	var f := _ss(r)
	var lam := 1.0e-2
	var it := 0
	while it < iters:
		it += 1
		var n := p.size()
		var m := r.size()
		var J := []
		for k in n:
			var q := p.duplicate()
			q[k] = float(q[k]) + 1.0e-3
			var rk := _resid(Ks, q, sub, pairs)
			var col := []
			for i in m:
				col.append((float(rk[i]) - float(r[i])) / 1.0e-3)
			J.append(col)
		var A := []
		var g := []
		for k in n:
			var row := []
			for l in n:
				var v := 0.0
				for i in m:
					v += float(J[k][i]) * float(J[l][i])
				row.append(v)
			A.append(row)
			var gv := 0.0
			for i in m:
				gv += float(J[k][i]) * float(r[i])
			g.append(-gv)
		var accepted := false
		var step_max := 0.0
		for tries in 12:
			var M := []
			for k in n:
				var row: Array = (A[k] as Array).duplicate()
				row[k] = float(row[k]) * (1.0 + lam) + 1.0e-9
				M.append(row)
			var d := _solve_lin(M, g)
			var q := p.duplicate()
			for k in n:
				q[k] = float(q[k]) + float(d[k])
			var rq := _resid(Ks, q, sub, pairs)
			var fq := _ss(rq)
			if fq < f:
				p = q
				r = rq
				f = fq
				lam = maxf(lam / 3.0, 1.0e-7)
				accepted = true
				for k in n:
					step_max = maxf(step_max, absf(float(d[k])))
				break
			lam *= 4.0
		if not accepted or step_max < 1.0e-6:
			break
	return {"p": p, "cost": f, "sweeps": it}


## the extrinsics from the person's own keypoints. Two stages. (1) A coarse GRID, camera by camera: each non-reference
## camera's yaw (+-30 deg about its ring start, 10 deg steps) and pitch (-5..15 deg), and camera 0's pitch (-5..10), scored
## on `sample` evenly spaced frames: a greedy descent from the ring stalls in a valley (camera 1 sat 15-17 deg off in the
## test). (2) Levenberg-Marquardt from the grid's best on ALL the frames (_lm). `pairs` are [a, b, metres] for the bones.
## p0 is the ring: [pitch0, r0, yaw1, pitch1, r1, ...]. Returns {"p", "cost" (of _cost), "cams", "sweeps"}
## max_frames > 0 caps the frames the Levenberg-Marquardt stage reads (evenly spaced): a 300-frame clip in GDScript takes
## minutes; the app uses 120. 0 = every frame (the test's 24 are all of them)
static func solve_extrinsics(Ks: Array, p0: Array, obs: Array, pairs: Array, sample := 8, max_frames := 0) -> Dictionary:
	var coarse := []
	var sc := maxi(1, obs.size() / maxi(1, sample))
	for i in range(0, obs.size(), sc):
		coarse.append(obs[i])
	var bestp := p0.duplicate()
	var bc := INF
	for pt in [-5.0, 0.0, 5.0, 10.0]:
		var q := p0.duplicate()
		q[0] = pt
		var cq := _cost(Ks, q, coarse, pairs)
		if cq < bc:
			bc = cq
			bestp = q
	for c in range(1, Ks.size()):
		var k := 2 + 3 * (c - 1)
		bc = INF
		var cur := bestp.duplicate()
		for dy in [-30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0]:
			for pt in [-5.0, 0.0, 5.0, 10.0, 15.0]:
				var q := cur.duplicate()
				q[k] = float(p0[k]) + dy
				q[k + 1] = pt
				var cq := _cost(Ks, q, coarse, pairs)
				if cq < bc:
					bc = cq
					bestp = q
	var lm_obs := obs
	if max_frames > 0 and obs.size() > max_frames:
		lm_obs = []
		var st := float(obs.size()) / float(max_frames)
		for i in max_frames:
			lm_obs.append(obs[int(i * st)])
	var res := _lm(Ks, bestp, lm_obs, pairs, 25)
	return {"p": res["p"], "cost": _cost(Ks, res["p"], obs, pairs), "cams": rig(Ks, res["p"]), "sweeps": res["sweeps"]}


## the bones' lengths of one frame of the 33 points (metres), the scale the rig is checked against: pairs with `scale`
## (the person's height over the body the lengths were measured on)
static func bone_pairs(w: Array, scale := 1.0) -> Array:
	var out := []
	for b in BONES:
		out.append([b[0], b[1], (w[b[0]] as Vector3).distance_to(w[b[1]] as Vector3) * scale])
	return out


## the bones of the mannequin standing at rest, as bone_pairs gives them. height 0 (the default: the app has no height field
## yet) keeps the mannequin's own size; a height in m scales every bone by height / the mannequin's standing height. The rest
## pose is restored after. The bones fix the rig's scale: a person of another height than the mannequin puts the rig at the
## wrong distance unless the height is given
static func rest_bones(B: Body, height := 0.0) -> Array:
	var keep := {}
	for j in B.ang:
		keep[j] = B.ang[j]
		B.ang[j] = Vector3.ZERO
	B.fk()
	var w := VideoImport.landmarks_of(B)
	var body_h := maxf((w[0] as Vector3).y - minf((w[29] as Vector3).y, (w[30] as Vector3).y), 0.5)
	for j in keep:
		B.ang[j] = keep[j]
	B.fk()
	var scale := 1.0 if height <= 0.0 else height / body_h
	return bone_pairs(w, scale)


## how many frames each camera saw each joint of the JOINTS with confidence > 0 (the panel's "joints seen")
static func views_per_cam(obs: Array, n: int) -> Array:
	var out := []
	for c in n:
		out.append(0)
	for fr in obs:
		for c in mini(n, (fr["cams"] as Array).size()):
			var co = fr["cams"][c]
			if co == null:
				continue
			for j in JOINTS:
				if float((co["conf"] as Array)[j]) > 0.0:
					out[c] += 1
	return out


## the views from the trackers' pose files (tools/see_video.py's JSON texts, one per camera, the first is the reference).
## Each frame of the first camera is matched to the nearest frame of every other within `tol` seconds (else null for that
## camera). Returns {"ok", "why", "obs", "sizes": [[W, H] per camera]}
static func obs_from_poses(texts: Array, tol := 0.02) -> Dictionary:
	var views := []
	var sizes := []
	for txt in texts:
		var d = JSON.parse_string(str(txt))
		if not d is Dictionary or not (d as Dictionary).has("frames") or not (d as Dictionary).has("size"):
			return {"ok": false, "why": "a pose file has no \"size\" or \"frames\" (tools/see_video.py writes both)", "obs": [], "sizes": []}
		var sz: Array = d["size"]
		var fr := []
		for f in d["frames"]:
			if f is Dictionary and (f as Dictionary).has("image") and (f["image"] as Array).size() >= 33:
				var uv := []
				var cf := []
				for p in f["image"]:
					uv.append(Vector2(float(p[0]) * float(sz[0]), float(p[1]) * float(sz[1])))
					cf.append(float(p[2]))
				fr.append({"t": float(f.get("t", 0.0)), "uv": uv, "conf": cf})
		if fr.size() < 2:
			return {"ok": false, "why": "a pose file has fewer than 2 usable frames (the tracker found nobody in it?)", "obs": [], "sizes": []}
		views.append(fr)
		sizes.append([int(sz[0]), int(sz[1])])
	var obs := []
	for f in views[0]:
		var cams := [{"uv": f["uv"], "conf": f["conf"]}]
		for v in views.slice(1):
			var best = null
			var bd := INF
			for g in v:
				var dt := absf(float(g["t"]) - float(f["t"]))
				if dt < bd:
					bd = dt
					best = g
			cams.append({"uv": best["uv"], "conf": best["conf"]} if best != null and bd <= tol else null)
		obs.append({"t": f["t"], "cams": cams})
	return {"ok": true, "why": "", "obs": obs, "sizes": sizes}


## the tracker's command line: python -I (isolated: no current directory or user site on the path; the videos are the user's
## own, and nothing from their folder is imported). tool = see_video.py's path, video and out the files
static func track_args(tool: String, video: String, out: String) -> PackedStringArray:
	return PackedStringArray(["-I", tool, video, out])
