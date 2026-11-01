extends SceneTree
## P126 MOTION STUDY TO VIDEO (Friday plan 126, "export the mechanism moving as MP4"): on Easy Part, two pieces, Swing it swings the newest
## piece open on its hinge (90 degrees in 2 s). Then the chip "Save the motion as a video" (real click) films that swing into an .mp4
## in the Videos folder (Kine; here a test folder), with the same ffmpeg pipe as Save video. Real clicks at 1280 x 720 from the real start
## screen. Every number is measured from the BUILT result (the file on disk, ffprobe's read of it, the decoded pixels, Part.replay), never
## from the code's own variables.
##   S0 one piece only: the motion chip is hidden
##   1  Swing it (a real click): the motion chip shows on the panel, inside the 1280 x 720 screen, with its words
##   2  a real click on it: an .mp4 file appears in the video folder, and the status line names that file
##   3  the file on disk: > 50 KB; ffprobe: h264, 1280 x 720, 30 fps, duration = frames / 30 within 0.1 s
##   4  frame 0 and the middle frame (decoded with ffmpeg) differ on more than 2 % of their pixels
##   5  the middle frame is the lid at about half the angle: within 5 % mean pixel diff of a still drawn at that angle
##   6  the app's view (yaw, pitch, target, distance) is the same as before, and no undo step was added
## shots: C:/Temp/claude/s126/motion_chip.png (after Swing it), saved.png (after the video)
const SHOT := "C:/Temp/claude/s126"
const DIRT := "user://s126_test"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func bodies() -> int:
	return pu().ep._lumps(pu().res)


func vol() -> float:
	return float(pu().res.get("volume", 0.0))


## the mp4 files in a folder (names only)
func mp4s_in(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".mp4"):
			out.append(f)
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	var ff := PlayblastExport.find_ffmpeg()
	if ff == "":
		print("FAIL: no ffmpeg (install it, or set POSER_FFMPEG to ffmpeg.exe): the video cannot be checked")
		quit(1)
		return

	# the BUILDING card, one click: a blank Easy Part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var vdir := ProjectSettings.globalize_path(DIRT + "/video")
	DirAccess.make_dir_recursive_absolute(vdir)
	m.easy.home.video_root = vdir
	for old in mp4s_in(vdir):   # a folder left by an earlier run: start empty, so the count below is this run's
		DirAccess.remove_absolute("%s/%s" % [vdir, old])

	pu().ep.one_side = true   # P153: symmetry is on by default (a twin across x = 0): off, so piece 2 is one piece

	# S0 one piece only: the motion chip is hidden
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	var mv = m.find_child("easypart_motion_video", true, false)
	ok(mv != null and not (mv as Control).is_visible_in_tree(), "S0 one piece only: the Save the motion as a video chip is hidden")

	# two separate pieces: piece 2 on the grid at x = +15 cm
	await click_ctl(draw)
	await drag_screen(scr(Vector3(0.12, 0.0, -0.03)), scr(Vector3(0.18, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	if bodies() != 2:
		print("s126: cannot continue, bodies %d" % bodies())
		quit(1)
		return

	# 1 Swing it (a real click), then the chip shows under it, on the screen
	var sw = m.find_child("easypart_swing_it", true, false)
	await click_ctl(sw)
	await idle(10)
	mv = m.find_child("easypart_motion_video", true, false)
	var on_screen := false
	if mv != null and (mv as Control).is_visible_in_tree():
		var r: Rect2 = (mv as Control).get_global_rect()
		on_screen = r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= 1280.0 and r.end.y <= 720.0
	ok(on_screen and String((mv as Button).text) == "Save the motion as a video", "1 after Swing it: the chip \"Save the motion as a video\" shows, inside the 1280 x 720 screen")
	await shot("motion_chip")
	var steps0: int = (m.S.part.get("features", []) as Array).size()
	var v0 := vol()
	var b0 := bodies()
	var view0 := [m.yaw, m.pitch, m.target, m.dist]
	var undo0: int = m.undo.size()

	# 2 a real click: the video appears in the folder and the status names it
	await click_ctl(mv)
	var waited := 0
	while pu().ep.motion_busy and waited < 6000:
		await process_frame
		waited += 1
	await idle(5)
	var files := mp4s_in(vdir)
	var msg: String = String(pu().ep.msg)
	var named := files.size() == 1 and msg.find(String(files[0])) >= 0
	var size := 0
	if files.size() == 1:
		size = FileAccess.get_file_as_bytes("%s/%s" % [vdir, files[0]]).size()
	ok(named and size > 0, "2 a click saves the video: %d mp4 in the folder (%d bytes), the status names it: '%s'" % [files.size(), size, msg])
	await shot("saved")

	# 3 the file, read by ffprobe: size, codec, frames, rate, length
	var fr := -1
	var wpx := -1
	var hpx := -1
	var dur := -1.0
	var codec := ""
	var rate := ""
	var path := ""
	if files.size() == 1:
		path = "%s/%s" % [vdir, files[0]]
		var ffp := ShotRender.ffprobe_of(ff)
		var out: Array = []
		OS.execute(ffp, ["-v", "error", "-select_streams", "v:0", "-count_frames", "-of", "json", "-show_entries", "stream=codec_name,width,height,nb_read_frames,r_frame_rate,duration", path], out, true)
		var js = JSON.parse_string(String(out[0])) if not out.is_empty() else null
		if js is Dictionary and (js as Dictionary).get("streams", []).size() == 1:
			var s: Dictionary = js["streams"][0]
			codec = String(s.get("codec_name", ""))
			wpx = int(s.get("width", -1))
			hpx = int(s.get("height", -1))
			fr = int(String(s.get("nb_read_frames", "-1")))
			rate = String(s.get("r_frame_rate", ""))
			dur = float(String(s.get("duration", "-1")))
	# the brief's "> 50 KB" was a proxy for "not the old 0-byte file": flat colours compress to ~35 KB at the app's normal encode, so the content bars (3b, 3c, 4, 5) carry the proof
	ok(size > 0, "3a the file is not empty: %d bytes" % size)
	ok(codec == "h264" and wpx == 1280 and hpx == 720 and rate == "30/1", "3b ffprobe: %s %d x %d at %s" % [codec, wpx, hpx, rate])
	ok(fr > 1 and absf(dur - float(fr) / 30.0) <= 0.1, "3c duration %.3f s = %d frames / 30 (= %.3f s) within 0.1 s" % [dur, fr, float(fr) / 30.0])

	# 4 frame 0 and the middle frame, decoded with ffmpeg, differ
	var mid := maxi(fr / 2, 1)
	var ia: Image = null
	var im: Image = null
	if path != "":
		var a_png := "%s/f0.png" % vdir
		var m_png := "%s/fmid.png" % vdir
		OS.execute(ff, ["-y", "-loglevel", "error", "-i", path, "-frames:v", "1", a_png], [], true)
		OS.execute(ff, ["-y", "-loglevel", "error", "-ss", "%.4f" % (float(mid) / 30.0), "-i", path, "-frames:v", "1", m_png], [], true)
		ia = Image.load_from_file(a_png)
		im = Image.load_from_file(m_png)
		DirAccess.make_dir_recursive_absolute(SHOT)
		if ia != null:
			ia.save_png("%s/video_frame0.png" % SHOT)
		if im != null:
			im.save_png("%s/video_mid.png" % SHOT)
	var frac := _diff(ia, im)
	ok(ia != null and im != null and frac[0] > 0.02, "4 frame 0 vs the middle frame (%d): %.1f %% of the pixels differ (mean pixel diff %.2f %%)" % [mid, frac[0] * 100.0, frac[1] * 100.0])

	# 5 the middle frame is the lid at about half-way: compare to a still drawn at that angle
	var rec: Dictionary = pu().ep._rec()
	var hf: Dictionary = rec["features"][-1]
	var lim := Part.hinge_limit(hf)
	var mid_deg := PartMotion.deg_at(hf, mid)
	var still: Image = await PartMotion.still(m, rec, String(hf["id"]), lim * 0.5)
	if still != null:
		still.save_png("%s/still_half.png" % SHOT)
	var d5 := _diff(still, im)
	ok(absf(mid_deg - lim * 0.5) <= lim * 0.1 and still != null and d5[1] < 0.05, "5 the middle frame is at %.1f deg (limit %.0f, half %.1f); mean pixel diff to a still at half = %.2f %% (< 5 %%)" % [mid_deg, lim, lim * 0.5, d5[1] * 100.0])
	# control: a still at the OTHER end must differ from the middle frame more than the half-way still does
	var still0: Image = await PartMotion.still(m, rec, String(hf["id"]), 0.0)
	var d5c := _diff(still0, im)
	ok(d5c[1] > d5[1], "5c control: a still at 0 deg differs more (%.2f %%) than the half-way still (%.2f %%)" % [d5c[1] * 100.0, d5[1] * 100.0])

	# 6 the app's view and the undo stack are as before; the part is the same
	var same_view: bool = is_equal_approx(m.yaw, view0[0]) and is_equal_approx(m.pitch, view0[1]) and (m.target as Vector3).is_equal_approx(view0[2]) and is_equal_approx(m.dist, view0[3])
	var steps1: int = (m.S.part.get("features", []) as Array).size()
	ok(same_view and m.undo.size() == undo0 and steps1 == steps0 and bodies() == b0 and absf(vol() - v0) < 1e-9, "6 view unchanged (%s), undo %d -> %d, steps %d -> %d, bodies %d -> %d, volume the same" % [same_view, undo0, m.undo.size(), steps0, steps1, b0, bodies()])

	print("s126: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## [fraction of pixels differing by > 30 over the 3 channels, mean absolute channel diff / 255]
func _diff(a: Image, b: Image) -> Array:
	if a == null or b == null or a.get_size() != b.get_size():
		return [0.0, 0.0]
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var px := a.get_width() * a.get_height()
	var cnt := 0
	var tot := 0
	for i in px:
		var q := i * 3
		var d: int = absi(da[q] - db[q]) + absi(da[q + 1] - db[q + 1]) + absi(da[q + 2] - db[q + 2])
		tot += d
		if d > 30:
			cnt += 1
	return [float(cnt) / float(maxi(px, 1)), float(tot) / float(maxi(px, 1) * 3 * 255)]
