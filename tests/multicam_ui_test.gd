## godot --path . -s tests/multicam_ui_test.gd     (roadmap 89, windowed; saves the panel's picture)
## THE MULTI-CAMERA PANEL, WITH THE TRUTH OVERLAID. The rig is solved from a standing clip (multicam_test.gd's synthetic
## set: three cameras, 2 px noise, the body standing, the spine set upright). Then walk_bat's mid-walk frame is triangulated
## through THAT solved rig (not the true one), and the panel draws the truth (red) over the reconstruction (blue-green):
##   1 the panel lists the three cameras, each with its reprojection error (px) and the joints it saw
##   2 PLACEMENT: in the whole-body view the head is above the ankles, shoulder above hip above knee, every joint inside the box
##   3 the solved rig is within 3 deg (yaw, pitch) and 5 cm (position) of the truth (the same bars as multicam_test)
##   4 the arm: the wrist of the reconstruction is within 4 cm of the truth on that frame (printed per arm, with the elbow)
##   5 the picture is saved to the job's tmp folder for reading
extends SceneTree

const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/multicam.png"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	root.size = Vector2i(900, 560)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var Ks := []
	for c in 3:
		Ks.append(MultiCam.intrinsics(1280, 720))
	var p_true := [4.0, 3.0, 120.0, 10.0, 3.0, 240.0, 5.0, 3.0]
	var truth_cams := MultiCam.rig(Ks, p_true)
	# the standing clip (as multicam_test.gd): the spine set upright, sway in the spine and arms, the feet still
	var spine := _upright(B)
	var stand := []
	var srng := RandomNumberGenerator.new()
	srng.seed = 11
	for i in 24:
		for j in Body.BODY:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3.ZERO
		for j in ["spine_01", "spine_02", "spine_03"]:
			B.ang[j] = Vector3(spine.x / 3.0 + srng.randf_range(-3.0, 3.0), spine.y / 3.0, 0.0)
		for j in ["lowerarm_l", "lowerarm_r", "upperarm_l", "upperarm_r"]:
			B.ang[j] = Vector3(srng.randf_range(-10.0, 10.0), 0.0, 0.0)
		B.fk()
		stand.append(VideoImport.landmarks_of(B))
	var sobs := _observe(truth_cams, stand, 2.0, 7)
	var pairs := MultiCam.bone_pairs(stand[0], 1.0)
	var sol := MultiCam.solve_extrinsics(Ks, [0.0, 2.6, 100.0, 4.0, 3.4, 255.0, -3.0, 2.8], sobs, pairs)
	var cams: Array = sol["cams"]
	# 3 the rig against the truth (the hips' mean moved to the origin, as the truth's)
	var H := Vector3.ZERO
	var rs := MultiCam.triangulate_all(cams, sobs)
	for h in rs["hips"]:
		H += h as Vector3
	H /= float(rs["hips"].size())
	var worst_ang := 0.0
	var worst_pos := 0.0
	for c in cams.size():
		var sc: Vector3 = (cams[c]["C"] as Vector3) - H - (MultiCam.TARGET - H)
		var tru: Vector3 = truth_cams[c]["C"] - MultiCam.TARGET
		var ya := rad_to_deg(absf(wrapf(atan2(sc.x, sc.z) - atan2(tru.x, tru.z), -PI, PI)))
		var pa := rad_to_deg(absf(asin(clampf(sc.normalized().y, -1.0, 1.0)) - asin(clampf(tru.normalized().y, -1.0, 1.0))))
		worst_ang = maxf(worst_ang, maxf(ya, pa))
		worst_pos = maxf(worst_pos, ((cams[c]["C"] as Vector3) - H).distance_to(truth_cams[c]["C"]))
	ok(worst_ang < 3.0 and worst_pos < 0.05, "3 the solved rig: worst %.2f deg, worst position %.2f cm (bars 3 deg, 5 cm)" % [worst_ang, worst_pos * 100.0])
	# the walk: truth = walk_bat's mid-walk body (hips at 0); views from the TRUE cameras with 2 px noise; triangulated by the SOLVED rig
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var t := S.length() * 0.5
	S.apply(B, t)
	B.fk()
	var truth := VideoImport.landmarks_of(B)
	var views := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for c in truth_cams.size():
		var uv := []
		var conf := []
		for j in 33:
			var q := MultiCam.project(truth_cams[c], truth[j])
			uv.append(Vector2(q.x + rng.randfn(0.0, 2.0), q.y + rng.randfn(0.0, 2.0)))
			conf.append(1.0)
		views.append({"uv": uv, "conf": conf})
	var res := MultiCam.triangulate_frame(cams, views)
	var pose := []
	for i in 33:
		pose.append(Vector3.ZERO)
	var ss := 0.0
	var nn := 0
	for j in res:
		if res[j]["ok"]:
			pose[j] = (res[j]["X"] as Vector3)
			for e in res[j]["errs"]:
				ss += float(e) * float(e)
				nn += 1
	var hip: Vector3 = ((pose[23] as Vector3) + (pose[24] as Vector3)) * 0.5
	for j in MultiCam.JOINTS:
		pose[j] = (pose[j] as Vector3) - hip
	var rms := sqrt(ss / maxi(nn, 1))
	# 4 the arm: the wrists and elbows of the reconstruction against the truth on this frame
	var arm := []
	for j in [13, 14, 15, 16]:
		arm.append((pose[j] as Vector3).distance_to(truth[j]))
	print("     arm, cm off the truth: elbow L %.2f, elbow R %.2f, wrist L %.2f, wrist R %.2f" % [arm[0] * 100.0, arm[1] * 100.0, arm[2] * 100.0, arm[3] * 100.0])
	ok(float(arm[2]) < 0.04 and float(arm[3]) < 0.04, "4 the wrists within 4 cm of the truth (L %.2f, R %.2f cm)" % [arm[2] * 100.0, arm[3] * 100.0])
	# the panel
	var info := []
	var seen := MultiCam.views_per_cam([{"cams": views}], 3)
	for c in cams.size():
		info.append({"name": "camera %d" % (c + 1), "C": (cams[c]["C"] as Vector3) - H, "rms": _cam_rms(res, c), "views": int(seen[c])})
	var panel := MultiCamPanel.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(900, 560)
	root.add_child(panel)
	panel.set_result(info, pose, t, rms)
	panel.truth = truth
	for k in 3:
		await process_frame
	# 1 the list
	var rl := ""
	for c in info:
		rl += " %.2f" % float(c["rms"])
	ok(panel.cams.size() == 3 and float(panel.cams[0]["rms"]) > 0.0, "1 the panel lists %d cameras, reprojection%s px" % [panel.cams.size(), rl])
	# 2 placement, on screen
	var r := panel.skel_rect()
	print("     panel %s, figure box %s" % [str(panel.size), str(r)])
	var head := panel.to_screen(pose[0], r)
	var ankle := panel.to_screen(pose[27], r)
	var ankle_r := panel.to_screen(pose[28], r)
	var shoulder := panel.to_screen(pose[11], r)
	var hipp := panel.to_screen(pose[23], r)
	var knee := panel.to_screen(pose[25], r)
	var inside := true
	for j in MultiCam.JOINTS:
		if not r.has_point(panel.to_screen(pose[j], r)):
			inside = false
	ok(head.y < minf(ankle.y, ankle_r.y) and shoulder.y < hipp.y and hipp.y < knee.y and inside,
		"2 placement: head above the ankles (%.0f < %.0f px), shoulder above hip above knee, every joint inside the box" % [head.y, minf(ankle.y, ankle_r.y)])
	# 5 the picture
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT)
	ok(FileAccess.file_exists(OUT), "5 the panel's picture saved: %s" % OUT)
	print("multicam_ui: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## the spine's (bend, side) in degrees that makes the rest trunk vertical: a grid search, 0.5 deg steps over +-15 deg
func _upright(B: Body) -> Vector2:
	var best := Vector2.ZERO
	var bs := INF
	var b := -15.0
	while b <= 15.0:
		var sd := -15.0
		while sd <= 15.0:
			for j in ["spine_01", "spine_02", "spine_03"]:
				B.ang[j] = Vector3(b / 3.0, sd / 3.0, 0.0)
			B.offset = Vector3.ZERO
			B.fk()
			var w := VideoImport.landmarks_of(B)
			var tv: Vector3 = ((w[11] as Vector3) + (w[12] as Vector3)) * 0.5 - ((w[23] as Vector3) + (w[24] as Vector3)) * 0.5
			var h := Vector2(tv.x, tv.z).length() / tv.length()
			if h < bs:
				bs = h
				best = Vector2(b, sd)
			sd += 0.5
		b += 0.5
	return best


func _observe(cams: Array, truth: Array, sigma: float, seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := []
	for i in truth.size():
		var cs := []
		for c in cams.size():
			var uv := []
			var conf := []
			for j in 33:
				var q := MultiCam.project(cams[c], truth[i][j])
				uv.append(Vector2(q.x + rng.randfn(0.0, sigma), q.y + rng.randfn(0.0, sigma)))
				conf.append(1.0)
			cs.append({"uv": uv, "conf": conf})
		out.append({"t": 0.1 * i, "cams": cs})
	return out


## one camera's reprojection error (px) over the frame's used views
func _cam_rms(res: Dictionary, c: int) -> float:
	var ss := 0.0
	var n := 0
	for j in res:
		if not res[j]["ok"]:
			continue
		for k in res[j]["used"].size():
			if res[j]["used"][k]["c"] == c:
				ss += float(res[j]["errs"][k]) * float(res[j]["errs"][k])
				n += 1
	return sqrt(ss / maxi(n, 1))
