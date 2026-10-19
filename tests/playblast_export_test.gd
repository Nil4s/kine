## godot --path . -s tests/playblast_export_test.gd     (the command "Export playblast (video)"; needs a window: it renders)
## A 3-card built-in scene (24 fps) is exported through the command's own function into user:// (never scenes/, poses/, data/).
## FRAME COUNT = round((b - a) * fps) + 1, with [a, b] the preview range or [0, scene length].
##   1 whole scene: that many PNGs, no more, each the viewport's size; 1b a preview range 0.2..0.6 s: 11 PNGs
##   2 anti-vacuity: the mean |pixel difference| (RGB, 0..1, whole frame) of the frame at the middle and at the end against
##     frame 0 is above DIFF_BAR (the body moves); determinism: two exports are pixel-identical frame by frame;
##     the middle frame equals what the viewport shows when scrubbed to that time by hand (same path as play/scrub)
##   3 ffmpeg on PATH (or POSER_FFMPEG): the .mp4 exists and ffprobe counts the frames; else the message says how to get it
##   4 the app comes back as it was (playhead, panels visible)
extends SceneTree

var fails := 0
var m: Node
const DIFF_BAR := 0.0005   # mean abs difference of one 0..1 channel over the whole frame; the body is a few % of the window
var run_id := OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pngs(dir: String) -> Array:
	var l := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".png"))
	l.sort()
	return l


func mean_diff(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return 1.0
	var tot := 0
	for i in da.size():
		tot += absi(int(da[i]) - int(db[i]))
	return float(tot) / float(da.size()) / 255.0


func same(a: Image, b: Image) -> bool:
	return a.get_size() == b.get_size() and a.get_data() == b.get_data()


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_playblast_export"
	S.fps = 24
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.4
		S.cards[i]["hold"] = 0.1 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.3
	m._refresh()
	await idle(3)
	var slen := S.length()
	var want := roundi(slen * S.fps) + 1
	print("     scene length %.4f s at %d fps: want round(%.4f * %d) + 1 = %d frames" % [slen, S.fps, slen, S.fps, want])
	var base := "user://zz_pb_%d" % run_id
	var vp := Vector2i(root.get_viewport().get_visible_rect().size)

	# 1 whole scene
	var r1: Dictionary = await m._export_playblast(base + "_a", "")
	var d1: String = r1.get("dir", "")
	var l1 := pngs(d1) if d1 != "" else []
	var img0 := Image.load_from_file(d1 + "/" + l1[0]) if not l1.is_empty() else null
	var sized := not l1.is_empty() and img0.get_size() == vp
	for f in l1:
		if sized and Image.load_from_file(d1 + "/" + f).get_size() != vp:
			sized = false
	ok(l1.size() == want and r1.get("frames", -1) == want and DirAccess.get_files_at(d1).size() >= want, "1 the whole scene: %d PNGs (want %d), the folder %s" % [l1.size(), want, d1.get_base_dir().get_file() + "/" + d1.get_file()])
	ok(sized, "  every frame is the viewport's size %s" % [vp])
	ok(d1.get_file().begins_with("zz_playblast_export_"), "  the folder is <scene name>_<timestamp>: %s" % d1.get_file())

	# 2 movement + determinism + same path as the viewport
	var mid := want / 2
	var imid := Image.load_from_file("%s/frame_%04d.png" % [d1, mid])
	var iend := Image.load_from_file("%s/frame_%04d.png" % [d1, want - 1])
	var dm := mean_diff(img0, imid) if imid != null else 0.0
	var de := mean_diff(img0, iend) if iend != null else 0.0
	ok(dm > DIFF_BAR and de > DIFF_BAR, "2 the body moves: mean |diff| of frame %d vs 0 = %.5f, of the last frame vs 0 = %.5f (bar > %.4f)" % [mid, dm, de, DIFF_BAR])
	var r2: Dictionary = await m._export_playblast(base + "_b", "")
	var d2: String = r2.get("dir", "")
	var l2 := pngs(d2) if d2 != "" else []
	var identical := l2.size() == l1.size() and not l1.is_empty()
	var worst := 0.0
	if identical:
		for k in l1.size():
			var a := Image.load_from_file("%s/%s" % [d1, l1[k]])
			var b := Image.load_from_file("%s/%s" % [d2, l2[k]])
			if not same(a, b):
				identical = false
				worst = maxf(worst, mean_diff(a, b))
	ok(identical, "  two exports of the same scene are pixel-identical on all %d frames (worst mean diff %.6f)" % [l1.size(), worst])
	# by hand: scrub to frame `mid`'s time, UI hidden, capture
	var t_mid := float(mid) / S.fps   # independent of the exporter
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	m.playhead = t_mid
	m._ps().apply(m.B, t_mid)
	m._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	var hand: Image = root.get_viewport().get_texture().get_image()
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	ok(imid != null and same(hand, imid), "  frame %d (t = %.4f s) equals the viewport scrubbed there by hand (mean diff %.6f)" % [mid, t_mid, mean_diff(hand, imid) if imid != null else -1.0])

	m.playhead = 0.3
	m._refresh()
	# 1b preview range
	m.pv_in = 0.2
	m.pv_out = 0.6
	var want_b := roundi((0.6 - 0.2) * S.fps) + 1
	var r3: Dictionary = await m._export_playblast(base + "_c", "")
	var l3 := pngs(r3.get("dir", "")) if r3.has("dir") else []
	ok(l3.size() == want_b, "1b preview range 0.2..0.6 s: %d PNGs (want round(0.4 * %d) + 1 = %d)" % [l3.size(), S.fps, want_b])
	m.pv_in = -1.0
	m.pv_out = -1.0

	# 3 ffmpeg
	var ff := PlayblastExport.find_ffmpeg()
	var said: String = m.ui_status.text
	if ff != "":
		print("     BRANCH: ffmpeg found at %s" % ff)
		var mp4: String = r1.get("mp4", "")
		var r4: Dictionary = await m._export_playblast(base + "_d", "")
		mp4 = r4.get("mp4", "")
		var probe := ff.get_base_dir() + "/ffprobe" + (".exe" if OS.get_name() == "Windows" else "")
		var out := []
		var n := -1
		if mp4 != "" and FileAccess.file_exists(mp4):
			OS.execute(probe if FileAccess.file_exists(probe) else "ffprobe", ["-v", "error", "-count_frames", "-select_streams", "v:0",
				"-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", mp4], out, true)
			n = int(String(out[0]).strip_edges()) if not out.is_empty() else -1
		ok(mp4 != "" and FileAccess.file_exists(mp4) and n == want, "3 the .mp4 exists (%s) and ffprobe counts %d frames (want %d)" % [mp4.get_file(), n, want])
	else:
		print("     BRANCH: ffmpeg NOT found (PATH and POSER_FFMPEG): PNG only")
		ok(r1.get("mp4", "x") == "" and said.contains("ffmpeg") and said.contains("install") and said.contains("No .mp4"), "3 no ffmpeg: no .mp4, and the message says how to get it: %s" % said.right(150))
		ok(PlayblastExport.find_ffmpeg("C:/zz_no_such/ffmpeg.exe") == "", "  a configured path that does not exist is not used")

	# 4 refusal + the app is back
	ok(absf(m.playhead - 0.3) < 1e-6 and m.ui_root.visible and not m.clean, "4 after exporting: playhead back at 0.30 (%.2f), panels visible, not in clean mode" % m.playhead)
	var S0: Scene = m.S
	m.S = Scene.new()
	var r5: Dictionary = await m._export_playblast(base + "_e", "")
	ok(r5.is_empty() and m.ui_status.text.contains("NOT NOW") and m.ui_status.text.contains("press Enter"), "  an empty scene is refused and says what to do: %s" % m.ui_status.text.left(90))
	m.S = S0

	for b in ["_a", "_b", "_c", "_d", "_e"]:
		_rm(ProjectSettings.globalize_path(base + b))
	print("PLAYBLAST EXPORT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _rm(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for d in DirAccess.get_directories_at(p):
		_rm(p + "/" + d)
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p + "/" + f)
	DirAccess.remove_absolute(p)
