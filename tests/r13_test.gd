## godot --path . -s tests/r13_test.gd     (R13; needs a window)
## THE VIDEO IMPORT ON A WORKER. Bars, stated before measuring:
##   1 a 200-frame import (the tracker's walk_bat file looped to 200 frames) run in the background keeps the main loop alive:
##     the worst frame while it solves is under 50 ms (the sync import blocks it for seconds), and the progress bar rises
##   2 the result is IDENTICAL to the synchronous import's (the same scene dict, bit for bit, apart from the file name)
##   3 Cancel leaves the scene untouched: same scene dict, same path, no new file in scenes/_wip, the worker is joined
##   4 quitting in the middle of an import exits 0 (a child process of this test starts one and quits; exit code and seconds)
##   5 PLACEMENT: while it runs the progress panel is on screen, below the ribbon, centred, with its bar and a Cancel button,
##     and the screenshot (C:/Users/Nick/.claude/jobs/9afc22db/tmp/r13.png) is saved
extends SceneTree

var fails := 0
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r13.png"
const POSE := "user://r13_pose.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _pose_file(frames_n: int) -> String:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://refs/video/walk_bat_track.json"))
	var src: Array = d["frames"]
	var fr := []
	for i in frames_n:
		var f: Dictionary = (src[i % src.size()] as Dictionary).duplicate(true)
		f["t"] = snappedf(float(i + 1) / 30.0, 0.001)
		fr.append(f)
	d["frames"] = fr
	var f := FileAccess.open(POSE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	return ProjectSettings.globalize_path(POSE)


func _wip_files() -> Array:
	var out := []
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://scenes/_wip")):
		for f in DirAccess.get_files_at("res://scenes/_wip"):
			out.append(f)
	out.sort()
	return out


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var path := _pose_file(200)
	if OS.get_cmdline_user_args().has("quitmid"):
		m._import_pose(path, "r13.mp4", false, true)
		for i in 15:
			await process_frame
		print("child: busy=%s progress=%.2f, quitting at %d ms" % [m._imp_busy(), VideoIQ.progress, Time.get_ticks_msec()])
		quit(0)
		return
	var before_files := _wip_files()
	var keep: Dictionary = m.B.state()

	# 1 + 5: the background import, frame times, progress, the panel
	m._import_pose(path, "r13.mp4", false, true)
	var worst := 0.0
	var nfr := 0
	var prog := []
	var shot_done := false
	var panel_ok := false
	var t_last := Time.get_ticks_usec()
	var land_dt := 0.0
	var t0 := t_last
	while m._imp_busy():
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - t_last) / 1000.0
		t_last = now
		land_dt = dt
		if m._imp_busy():   # (the frame that lands the result is measured apart)
			worst = maxf(worst, dt)
			nfr += 1
			prog.append(VideoIQ.progress)
			if not shot_done and nfr == 30:
				var pn: Control = m._imp_panel
				var vs: Vector2 = root.get_visible_rect().size
				var r := pn.get_global_rect()
				panel_ok = pn.visible and r.position.y >= m.TOP_H and absf((r.position.x + r.size.x * 0.5) - vs.x * 0.5) < 4.0 \
					and m._imp_cancel_btn.visible and r.end.x <= vs.x and r.size.x > 300.0 and m._imp_bar.value > 0.0 and m._imp_bar.value < 100.0
				print("   panel rect %s in window %s, bar %.0f%%, label \"%s\"" % [r, vs, m._imp_bar.value, m._imp_lbl.text])
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				img.save_png(SHOT)
				shot_done = true
				t_last = Time.get_ticks_usec()
	var land_ms := land_dt
	var secs := float(Time.get_ticks_usec() - t0) / 1e6
	var rising := prog.size() > 5 and float(prog[-1]) > float(prog[0]) + 0.3
	ok(worst < 50.0 and nfr > 20, "1 during the %.1f s import the main loop ran %d frames, worst %.1f ms (bar < 50), progress %.2f -> %.2f" % [secs, nfr, worst, float(prog[0]) if not prog.is_empty() else -1.0, float(prog[-1]) if not prog.is_empty() else -1.0])
	ok(rising and panel_ok and shot_done, "5 the progress panel was drawn below the ribbon, centred, bar rising, Cancel present; screenshot %s" % SHOT)
	var async_path: String = m.scene_path
	var A: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(async_path))
	print("   landing frame (writes + opens the scene): %.0f ms; opened %s" % [land_ms, async_path])

	# 2 the synchronous import of the same file, from the same body state
	m.B.set_state(keep)
	var sp: String = m._import_pose(path, "r13.mp4", false)
	var Sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sp))
	var a2 := A.duplicate(true)
	var s2 := Sd.duplicate(true)
	a2.erase("scene")
	s2.erase("scene")
	var same := var_to_bytes(a2) == var_to_bytes(s2) and a2.hash() == s2.hash()
	ok(same and (A.get("cards", []) as Array).size() > 3, "2 the background import is identical to the synchronous one (%d cards, %d keys in the scene dict, plan equal %s)" % [(A.get("cards", []) as Array).size(), A.size(), a2.get("plan", "") == s2.get("plan", "")])

	# 3 cancel
	m.B.set_state(keep)
	var d_before: Dictionary = m.S.to_dict(m.B)
	var path_before: String = m.scene_path
	var files_before := _wip_files()
	var undo_before: int = m.hist.size() if "hist" in m else -1
	m._import_pose(path, "r13.mp4", false, true)
	for i in 12:
		await process_frame
	var was_busy: bool = m._imp_busy()
	var tc := Time.get_ticks_usec()
	m._imp_cancel_btn.pressed.emit()
	while m._imp_busy():
		await process_frame
	var cancel_ms := float(Time.get_ticks_usec() - tc) / 1000.0
	await process_frame
	var d_after: Dictionary = m.S.to_dict(m.B)
	ok(was_busy and var_to_bytes(d_before) == var_to_bytes(d_after) and m.scene_path == path_before and _wip_files() == files_before
		and String(m.ui_status.text).contains("cancelled") and not m._imp_panel.visible,
		"3 Cancel (pressed on the bar's button) stopped the worker in %.0f ms; scene dict equal, path %s kept, no new file, panel hidden; status: %s" % [cancel_ms, m.scene_path.get_file(), String(m.ui_status.text).left(70)])
	# a second import after a cancel works (the flag is rearmed)
	m._import_pose(_pose_file(40), "r13b.mp4", false, true)
	while m._imp_busy():
		await process_frame
	ok(m.scene_path != path_before and String(m.ui_status.text).begins_with("imported"), "3b an import after a cancel runs to the end: %s" % String(m.ui_status.text).left(60))

	# 4 quitting mid-import: a child process
	var out := []
	var tq := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/r13_test.gd", "--", "quitmid"]), out, true)
	var q_s := float(Time.get_ticks_msec() - tq) / 1000.0
	var said := "\n".join(PackedStringArray(out))
	ok(code == 0 and said.contains("child: busy=true") and not said.contains("SCRIPT ERROR"), "4 quitting in the middle of an import exits %d (bar 0) after %.1f s; the child said busy=%s" % [code, q_s, said.contains("child: busy=true")])

	# clean up what this test wrote
	for f in _wip_files():
		if not before_files.has(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scenes/_wip/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(POSE))
	print("r13: %d failed" % fails)
	quit(1 if fails > 0 else 0)
