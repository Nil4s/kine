## godot --headless --path . -s tests/multicam_test.gd     (roadmap 89, MULTI-CAMERA VIDEO MOCAP)
## A SYNTHETIC RIG WITH A KNOWN ANSWER. walk_bat's joints (VideoImport.landmarks_of: MediaPipe's layout, hips at 0) are the
## 3D truth. Three known virtual cameras (yaw 0 / 120 / 240 deg, 3 m, 1280x720, 60 deg HFOV) project them to 2D, plus
## Gaussian noise of 2 px per coordinate (seeded). Bars, stated before measuring:
##   1 three cameras: the mean 3D joint error < 1.5 cm, the worst < 4 cm (MultiCam.triangulate_all)
##   2 one camera's left knee occluded (confidence 0, a junk picture): that knee still < 3 cm at its worst frame
##   3 reprojection error printed (per camera and the mean); the mean < 4 px (2 px per coordinate is ~2.8 px RMS)
##   4 a gross error (a wrist 150 px off in one camera): that view is rejected and the wrist stays < 4 cm
##   5 the extrinsics solved from a rough ring (yaws 20 deg off, radii 15 % off), with the bones' known lengths: the
##     mean joint error < 2 cm and the bone lengths within 2 % of the body's
##   6 the pose-file loader reads the trackers' JSON back to the same pixels (< 0.01 px), and the tracker is run with python -I
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	# the truth: 12 frames of walk_bat's body
	var truth := []
	var times := []
	for i in 12:
		var t := minf(S.length() * i / 11.0, S.length())
		S.apply(B, t)
		B.fk()
		truth.append(VideoImport.landmarks_of(B))
		times.append(snappedf(t, 0.001))
	var Ks := []
	for c in 3:
		Ks.append(MultiCam.intrinsics(1280, 720))
	var p_true := [3.0, 120.0, 10.0, 3.0, 240.0, 5.0, 3.0]
	var cams := MultiCam.rig(Ks, p_true)
	var obs := _observe(cams, truth, times, 2.0, 1)
	# 1 the rig and the three views
	var res := MultiCam.triangulate_all(cams, obs)
	var sum := 0.0
	var n := 0
	var worst := 0.0
	for i in truth.size():
		var w: Array = res["frames"][i]["w"]
		for j in MultiCam.JOINTS:
			var d := (w[j] as Vector3).distance_to(truth[i][j])
			sum += d
			n += 1
			worst = maxf(worst, d)
	var mean := sum / n
	print("     3 cameras, 2 px noise: mean joint error %.2f cm, worst %.2f cm" % [mean * 100.0, worst * 100.0])
	ok(res["ok"] and mean < 0.015 and worst < 0.04, "1 three cameras: mean %.2f cm < 1.5, worst %.2f cm < 4" % [mean * 100.0, worst * 100.0])
	# 3 the reprojection error
	print("     reprojection error: mean %.2f px; per camera %s px; %d views rejected, %d joint solves failed" % [res["mean_rms"],
		str(res["cam_rms"]), res["rejected"], res["fails"]])
	ok(float(res["mean_rms"]) < 4.0 and int(res["fails"]) == 0, "3 reprojection error %.2f px < 4, no failed solve" % float(res["mean_rms"]))
	# 2 the knee of camera 1 occluded
	var occ := _observe(cams, truth, times, 2.0, 2)
	var ro := MultiCam.triangulate_all(cams, occ)
	var kmax := 0.0
	for i in truth.size():
		kmax = maxf(kmax, ((ro["frames"][i]["w"] as Array)[25] as Vector3).distance_to(truth[i][25]))
	ok(kmax < 0.03, "2 camera 1's left knee occluded (confidence 0): worst %.2f cm < 3" % (kmax * 100.0))
	# 4 a gross error in one view: the view is rejected, the wrist is still right
	var bad := _observe(cams, truth, times, 2.0, 1)
	for i in truth.size():
		var uvs: Array = bad[i]["cams"][2]["uv"]
		uvs[15] = (uvs[15] as Vector2) + Vector2(150.0, 0.0)
	var rb := MultiCam.triangulate_all(cams, bad)
	var wmax := 0.0
	for i in truth.size():
		wmax = maxf(wmax, ((rb["frames"][i]["w"] as Array)[15] as Vector3).distance_to(truth[i][15]))
	ok(int(rb["rejected"]) >= truth.size() and wmax < 0.04, "4 a wrist 150 px off in one view: %d views rejected, worst wrist %.2f cm < 4" % [int(rb["rejected"]), wmax * 100.0])
	# 5 the extrinsics from a rough ring, with the bones' known lengths
	var pairs := MultiCam.bone_pairs(truth[0], 1.0)
	var p0 := [2.6, 100.0, 4.0, 3.4, 255.0, -3.0, 2.8]
	var sol := MultiCam.solve_extrinsics(Ks, p0, obs, pairs, 6)
	var rs := MultiCam.triangulate_all(sol["cams"], obs)
	var ssum := 0.0
	var sn := 0
	for i in truth.size():
		var w: Array = rs["frames"][i]["w"]
		for j in MultiCam.JOINTS:
			ssum += (w[j] as Vector3).distance_to(truth[i][j])
			sn += 1
	var bl := 0.0
	var bn := 0
	for i in truth.size():
		var w: Array = rs["frames"][i]["w"]
		for pr in MultiCam.bone_pairs(w, 1.0):
			var L := float(pr[2])
			var want := ((truth[i][pr[0]] as Vector3) - (truth[i][pr[1]] as Vector3)).length()
			bl += absf(L / want - 1.0)
			bn += 1
	var jerr := ssum / sn
	var blerr := bl / bn
	print("     solved rig %s after %d sweeps: reprojection %.2f px, mean joint error %.2f cm, bone lengths off %.2f %%" % [
		str(sol["p"]), sol["sweeps"], rs["mean_rms"], jerr * 100.0, blerr * 100.0])
	ok(jerr < 0.02 and blerr < 0.02, "5 solved extrinsics: mean joint error %.2f cm < 2, bones %.2f %% < 2" % [jerr * 100.0, blerr * 100.0])
	# 6 the loader and the tracker's command line
	var texts := []
	for c in 3:
		var fr := []
		for i in truth.size():
			var im := []
			for j in 33:
				var uv: Vector2 = (obs[i]["cams"][c]["uv"] as Array)[j]
				im.append([uv.x / 1280.0, uv.y / 720.0, 1.0])
			fr.append({"t": times[i], "image": im, "world": []})
		texts.append(JSON.stringify({"fps": 30.0, "size": [1280, 720], "frames": fr}))
	var L := MultiCam.obs_from_poses(texts)
	var pm := 0.0
	if L["ok"]:
		for i in truth.size():
			for c in 3:
				for j in 33:
					pm = maxf(pm, ((L["obs"][i]["cams"][c]["uv"] as Array)[j] as Vector2).distance_to((obs[i]["cams"][c]["uv"] as Array)[j]))
	ok(L["ok"] and pm < 0.01, "6 the pose files read back: worst %.4f px off" % pm)
	var args := MultiCam.track_args("C:/x/see_video.py", "C:/v/walk.mp4", "C:/o/pose.json")
	ok(args[0] == "-I" and args.size() == 4, "6 the tracker runs as python -I %s" % args[1].get_file())
	print("multicam: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## the synthetic views: truth projected by cams, + Gaussian noise (px per coordinate, seeded). mode 1: all views clean; 2: camera
## 1's left knee (25) occluded (confidence 0, a picture far off the frame)
func _observe(cams: Array, truth: Array, times: Array, sigma: float, mode: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
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
			if mode == 2 and c == 1:
				uv[25] = Vector2(3000.0, 2000.0)
				conf[25] = 0.0
			cs.append({"uv": uv, "conf": conf})
		out.append({"t": times[i], "cams": cs})
	return out
