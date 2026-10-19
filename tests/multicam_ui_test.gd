## godot --path . -s tests/multicam_ui_test.gd     (roadmap 89, windowed; saves the panel's picture)
## THE MULTI-CAMERA PANEL, ON THE SYNTHETIC RIG (multicam_test.gd's three cameras, walk_bat's mid-walk pose, 2 px noise):
##   1 the panel lists the three cameras, each with its reprojection error (px) and the joints it saw
##   2 PLACEMENT: drawn in the whole-body view the head is above the ankles and the hips lie between the shoulders and the
##     knees (on screen), and every reconstructed joint lies inside the picture's box
##   3 the picture is saved to the job's tmp folder for reading
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
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var t := S.length() * 0.5
	S.apply(B, t)
	B.fk()
	var truth := VideoImport.landmarks_of(B)
	var Ks := []
	for c in 3:
		Ks.append(MultiCam.intrinsics(1280, 720))
	var cams := MultiCam.rig(Ks, [3.0, 120.0, 10.0, 3.0, 240.0, 5.0, 3.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var views := []
	for c in cams.size():
		var uv := []
		var conf := []
		for j in 33:
			var q := MultiCam.project(cams[c], truth[j])
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
			pose[j] = res[j]["X"]
			for e in res[j]["errs"]:
				ss += float(e) * float(e)
				nn += 1
	var hip: Vector3 = ((pose[23] as Vector3) + (pose[24] as Vector3)) * 0.5
	for j in MultiCam.JOINTS:
		pose[j] = (pose[j] as Vector3) - hip
	var rms := sqrt(ss / maxi(nn, 1))
	var info := []
	for c in cams.size():
		var seen := 0
		for j in res:
			for u in res[j]["used"]:
				if u["c"] == c:
					seen += 1
		info.append({"name": cams[c]["name"], "C": cams[c]["C"], "rms": _cam_rms(cams, res, c), "views": seen})
	var panel := MultiCamPanel.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(900, 560)
	root.add_child(panel)
	panel.set_result(info, pose, t, rms)
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
		var q := panel.to_screen(pose[j], r)
		if not r.has_point(q):
			inside = false
	ok(head.y < minf(ankle.y, ankle_r.y) and shoulder.y < hipp.y and hipp.y < knee.y and inside,
		"2 placement: head above the ankles (%.0f < %.0f px), shoulder above hip above knee, every joint inside the box" % [head.y, minf(ankle.y, ankle_r.y)])
	# 3 the picture
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT)
	ok(FileAccess.file_exists(OUT), "3 the panel's picture saved: %s" % OUT)
	print("multicam_ui: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## the reprojection error (px) of one camera over the frame's used views
func _cam_rms(cams: Array, res: Dictionary, c: int) -> float:
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
