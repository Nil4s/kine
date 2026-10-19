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


## the rig from its parameters: p = [r0, yaw1, pitch1, r1, yaw2, pitch2, r2, ...]. Camera 0 is at yaw 0, pitch 0, radius r0
static func rig(Ks: Array, p: Array, target := TARGET) -> Array:
	var cams := []
	cams.append(on_ring("cam0", Ks[0], 0.0, 0.0, float(p[0]), target))
	for c in range(1, Ks.size()):
		var k := 1 + 3 * (c - 1)
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
## Returns {"ok", "frames": [{"t", "w"}] (33 points, hips at 0, y up: VideoImport.parse's layout), "rms": per frame px,
## "mean_rms" px, "cam_rms": per camera px, "rejected": views dropped, "fails": joint solves that failed}
static func triangulate_all(cams: Array, obs: Array, joints := JOINTS) -> Dictionary:
	var frames := []
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
	return {"ok": frames.size() >= 2, "frames": frames, "rms": rms, "mean_rms": mean, "cam_rms": cam_rms,
		"rejected": rejected, "fails": fails}


## the rig's fit to the observations: mean squared reprojection (px^2) over every used view, plus BONE_K times the mean
## squared bone-length error (ratio - 1) over the bones in `pairs` ([a, b, metres]). The bones are what fix the scale
static func _cost(Ks: Array, p: Array, sub: Array, pairs: Array) -> float:
	var cams := rig(Ks, p)
	var ss := 0.0
	var nn := 0
	var bl := 0.0
	var nb := 0
	for fr in sub:
		var res := triangulate_frame(cams, fr["cams"])
		var X := {}
		for j in res:
			if res[j]["ok"]:
				X[j] = res[j]["X"]
				for e in res[j]["errs"]:
					ss += float(e) * float(e)
					nn += 1
		for pr in pairs:
			if X.has(pr[0]) and X.has(pr[1]):
				var ratio := ((X[pr[0]] as Vector3) - (X[pr[1]] as Vector3)).length() / float(pr[2])
				bl += (ratio - 1.0) * (ratio - 1.0)
				nb += 1
	return ss / maxf(float(nn), 1.0) + BONE_K * bl / maxf(float(nb), 1.0)


## the extrinsics from the person's own keypoints: coordinate descent on the rig parameters p (see rig), from p0 (a rough ring:
## the yaws about 360/N apart, the radii a few metres). `pairs` are [a, b, metres] for the bones. Up to `sample` frames of
## obs are used (evenly spaced). Returns {"p", "cost", "cams", "sweeps"}
static func solve_extrinsics(Ks: Array, p0: Array, obs: Array, pairs: Array, sample := 8) -> Dictionary:
	var sub := []
	var step_i := maxi(1, obs.size() / maxi(1, sample))
	for i in range(0, obs.size(), step_i):
		sub.append(obs[i])
	var p := p0.duplicate()
	var step := []
	for k in p.size():
		step.append(0.1 if k % 3 == 0 else 2.0)   # radii (m) and angles (deg) move in their own units
	var best := _cost(Ks, p, sub, pairs)
	var sweeps := 0
	while sweeps < 200:
		sweeps += 1
		var improved := false
		for k in p.size():
			for s in [1.0, -1.0]:
				var q := p.duplicate()
				q[k] = float(q[k]) + s * float(step[k])
				var c := _cost(Ks, q, sub, pairs)
				if c < best:
					best = c
					p = q
					improved = true
					break
		if not improved:
			for k in step.size():
				step[k] = float(step[k]) * 0.5
			var tiny := true
			for k in step.size():
				if float(step[k]) > 0.02:
					tiny = false
			if tiny:
				break
	return {"p": p, "cost": best, "cams": rig(Ks, p), "sweeps": sweeps}


## the bones' lengths of one frame of the 33 points (metres), the scale the rig is checked against: pairs with `scale`
## (the person's height over the body the lengths were measured on)
static func bone_pairs(w: Array, scale := 1.0) -> Array:
	var out := []
	for b in BONES:
		out.append([b[0], b[1], (w[b[0]] as Vector3).distance_to(w[b[1]] as Vector3) * scale])
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
