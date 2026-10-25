## godot --path . -s tests/multicam_app_test.gd     (roadmap 89, windowed: THE CLICK PATH, end to end on the synthetic set)
## "Import from several cameras" in the app, on three synthetic cameras of a standing body (multicam_test.gd's rig, 2 px noise):
## the videos are dummy files, and the tracker is a stub (tests/fixtures/mc_stub.py, run as python -I) that copies each
## video's sidecar pose file, as tools/see_video.py would write its own. Bars, stated before measuring:
##   1 the ribbon has "From several cameras" (its icon), and the search finds "Import from several cameras..." by "cameras"
##   2 one video, or five, is refused with a sentence and the scene does not change
##   3 three videos: each is tracked in turn (python -I), the rig is solved, and the frames land as ONE edit: the scene's
##     cards change, and Ctrl+Z puts the cards back (one undo step)
##   4 the panel opens with three cameras, and the rig the app solved is within 3 deg (yaw, pitch) and 5 cm (position) of truth
##   5 the reconstruction's mean reprojection error is under 4 px
extends SceneTree

const DIR := "user://mc_test"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:

	_run.call_deferred()


func _run() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	# 1 the button and the search
	var found := false
	for b in (m.ui_ribbon["ANIMATE"] as Node).find_children("*", "Button", true, false):
		if String((b as Button).tooltip_text).begins_with("From several cameras"):   # the ribbon's tooltip: the label, then the description
			found = true
	var by_name := false
	for c in m.ui_cmd.commands:
		if c["name"] == "Import from several cameras..." and "cameras" in (String(c["name"]) + " " + String(c.get("also", ""))).to_lower():
			by_name = true
	print("     ribbon %s, search %s" % [found, by_name])
	ok(found and m.ICON_OF.get("From several cameras", "") == "cameras" and by_name,
		"1 ANIMATE has From several cameras (icon %s), the search has Import from several cameras... by cameras" % m.ICON_OF.get("From several cameras", "-"))
	# the synthetic set: the standing body, 24 frames, three cameras
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var stand := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 24:
		for j in Body.BODY:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3.ZERO
		for j in ["spine_01", "spine_02", "spine_03"]:
			B.ang[j] = Vector3(rng.randf_range(-3.0, 3.0), 0.0, 0.0)
		for j in ["lowerarm_l", "lowerarm_r", "upperarm_l", "upperarm_r"]:
			B.ang[j] = Vector3(rng.randf_range(-10.0, 10.0), 0.0, 0.0)
		B.fk()
		stand.append(VideoImport.landmarks_of(B))
	DirAccess.make_dir_recursive_absolute(DIR)
	var Ks := []
	for c in 3:
		Ks.append(MultiCam.intrinsics(1280, 720))
	var p_true := [4.0, 3.0, 120.0, 10.0, 3.0, 240.0, 5.0, 3.0]
	var cams := MultiCam.rig(Ks, p_true)
	var vids := PackedStringArray()
	for c in 3:
		var vp := "%s/cam%d.mp4" % [DIR, c]
		var f := FileAccess.open(vp, FileAccess.WRITE)
		f.store_string("not a real video: the stub tracker reads the sidecar")
		f.close()
		var fr := []
		var noise := RandomNumberGenerator.new()
		noise.seed = 7 + c
		for i in stand.size():
			var im := []
			for j in 33:
				var q := MultiCam.project(cams[c], stand[i][j])
				var u := q.x + noise.randfn(0.0, 2.0)
				var v := q.y + noise.randfn(0.0, 2.0)
				im.append([u / 1280.0, v / 720.0, 1.0])
			fr.append({"t": 0.1 * i, "image": im, "world": []})
		var pf := FileAccess.open(vp + ".pose.json", FileAccess.WRITE)
		pf.store_string(JSON.stringify({"fps": 10.0, "size": [1280, 720], "frames": fr}))
		pf.close()
		vids.append(ProjectSettings.globalize_path(vp))
	m.multicam_tool = "res://tests/fixtures/mc_stub.py"
	m.multicam_python = "python"
	# 2 refused
	var before: int = m.S.cards.size()
	var d_before := JSON.stringify(m.S.to_dict(m.B))   # VIDEO IQ: the whole scene before, to compare byte for byte after the undo
	m._multicam_start(PackedStringArray([vids[0]]))
	var refused1: bool = m.ui_status.text.contains("needs 2 to 4")
	m._multicam_start(PackedStringArray([vids[0], vids[1], vids[2], vids[0], vids[1]]))
	var refused5: bool = m.ui_status.text.contains("needs 2 to 4")
	ok(refused1 and refused5 and m.S.cards.size() == before and m._mc_i < 0, "2 one video and five videos are refused with a sentence, the scene is unchanged")
	# 3 the click path: three videos, tracked in turn, landed as one edit
	m._multicam_start(vids)
	var t0 := Time.get_ticks_msec()
	while m._mc_i >= 0 and Time.get_ticks_msec() - t0 < 240000:
		await create_timer(0.05).timeout
	var landed: bool = m.ui_status.text.contains("imported 3 cameras")
	var after: int = m.S.cards.size()
	print("     status: %s" % m.ui_status.text)
	ok(landed and after != before and after > 1, "3 three videos tracked, landed as one edit: %d cards became %d (%.1f s)" % [before, after, (Time.get_ticks_msec() - t0) / 1000.0])
	var iq_in: bool = (m.S.iq.get("conf", null) is Array) and not (m.S.iq.get("contacts", null) == null)
	# the panel
	var win: Window = m._mc_win
	var panel: MultiCamPanel = null
	if win != null and is_instance_valid(win) and win.get_child_count() > 0:
		panel = win.get_child(0) as MultiCamPanel
	# 4 the rig the app solved, against the truth
	var worst_ang := 0.0
	var worst_pos := 0.0
	if not m.mc_last.is_empty():
		var H: Vector3 = m.mc_last["H"]
		for c in cams.size():
			var sc: Vector3 = (m.mc_last["cams"][c]["C"] as Vector3) - H - (MultiCam.TARGET - H)
			var tru: Vector3 = cams[c]["C"] - MultiCam.TARGET
			var ya := rad_to_deg(absf(wrapf(atan2(sc.x, sc.z) - atan2(tru.x, tru.z), -PI, PI)))
			var pa := rad_to_deg(absf(asin(clampf(sc.normalized().y, -1.0, 1.0)) - asin(clampf(tru.normalized().y, -1.0, 1.0))))
			var pos := ((m.mc_last["cams"][c]["C"] as Vector3) - H).distance_to(cams[c]["C"])
			worst_ang = maxf(worst_ang, maxf(ya, pa))
			worst_pos = maxf(worst_pos, pos)
	ok(panel != null and panel.cams.size() == 3 and not m.mc_last.is_empty() and worst_ang < 3.0 and worst_pos < 0.05,
		"4 the panel has 3 cameras; the app's rig: worst %.2f deg, worst position %.2f cm" % [worst_ang, worst_pos * 100.0])
	# 5 the reprojection
	var rms := 99.0
	if panel != null:
		rms = panel.rms_frame
	ok(rms < 4.0, "5 the reconstruction's reprojection %.2f px < 4" % rms)
	# the undo: one step back to the cards before
	m._undo()
	ok(m.S.cards.size() == before, "3 Ctrl+Z takes the import back in one step: %d cards again" % m.S.cards.size())
	ok(iq_in and JSON.stringify(m.S.to_dict(m.B)) == d_before and m.S.iq.is_empty(), "3b VIDEO IQ: the import carried its confidence lane and contacts (Scene.iq), and the one undo restored the scene exactly (iq in %s, iq now %d keys)" % [iq_in, m.S.iq.size()])
	print("multicam_app: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
