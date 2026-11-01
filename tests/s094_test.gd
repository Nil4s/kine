extends SceneTree
## godot --path . -s tests/s094_test.gd     (p094, Friday plan 94: tooltips with tiny looping clips of the action on Easy Part's MAKE buttons; needs the CAD DLL and a window)
## Real mouse moves at 1280 x 720 (canvas units) onto each of the twelve MAKE buttons. Measured from the PNG sheets on disk and from the panel's own rect.
## Bars:
##   1 CLIPS    all 12 MAKE buttons have a clip in assets/tips/easy/tips.json: a sheet of 14 frames (12 to 16) of 200 x 120, 12 fps
##   2 MOTION   each clip's first and middle frame (read from the PNG) differ in more than 2 % of the pixels
##   3 SIZE     the whole folder is under 3 MB (printed)
##   4 SHOWS    hover on each button: the panel is visible within 0.8 s of the first move, it shows that button's clip and the button's own tooltip words
##   5 PLACED   the panel is whole inside the 1280 x 720 window, sits just under its button (not over the row), and does not cover the part (the origin of the grid)
##   6 LOOPS    the clip frame index takes more than 5 different values in 1.9 s of hover
##   7 HIDES    the pointer leaves: the panel is gone within 0.2 s
##   8 NOUNDO   twelve hovers add no undo step and no part step
##   9 SMOOTH   frames while a clip plays: median and worst printed, none over 33 ms
## Shots: C:/Temp/claude/s094/tip_<id>.png (LOOK at them)
const SHOT := "C:/Temp/claude/s094"
const DIRT := "user://s094_test"
const IDS := ["draw", "pull", "spin", "round", "hole", "mirror", "curve", "blend", "split", "colour", "repeat", "stick"]
const SHOTS := ["pull", "hole", "spin"]

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = win(p)
	e.global_position = win(p)
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = win(p)
	e.global_position = win(p)
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func ep():
	return m.bld.part.ep


func pu():
	return m.bld.part


func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func nsteps() -> int:
	return (ep()._rec().get("features", []) as Array).size()


func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SHOT + "/tip_" + id + ".png")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)

	# 1-3 the files, read from disk
	var man := EasyTips.load_manifest()
	var clips: Dictionary = man.get("clips", {})
	var all_ok := not man.is_empty() and int(man.get("w", 0)) == 200 and int(man.get("h", 0)) == 120 and int(man.get("fps", 0)) == 12
	var bad := []
	for id in IDS:
		if not clips.has(id):
			all_ok = false
			bad.append(id + " (no clip)")
			continue
		var c: Dictionary = clips[id]
		var img := Image.load_from_file(ProjectSettings.globalize_path(EasyTips.DIR + String(c["sheet"])))
		var fr := int(c["frames"])
		var cols := int(c["cols"])
		if img == null or fr < 12 or fr > 16 or img.get_width() != cols * 200 or img.get_height() != int(ceil(float(fr) / cols)) * 120:
			all_ok = false
			bad.append(id + " (sheet)")
	ok(all_ok and clips.size() == 12, "1 CLIPS twelve clips, 14 frames of 200 x 120 at 12 fps each %s" % str(bad))
	var worst := 100.0
	var shares := []
	for id in IDS:
		if not clips.has(id):
			continue
		var c: Dictionary = clips[id]
		var img := Image.load_from_file(ProjectSettings.globalize_path(EasyTips.DIR + String(c["sheet"])))
		var cols := int(c["cols"])
		var mid := int(c["frames"]) / 2
		var a := img.get_region(Rect2i(0, 0, 200, 120))
		var b := img.get_region(Rect2i((mid % cols) * 200, (mid / cols) * 120, 200, 120))
		var diff := 0
		for y in 120:
			for x in 200:
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					diff += 1
		var pct := 100.0 * diff / 24000.0
		worst = minf(worst, pct)
		shares.append("%s %.0f" % [id, pct])
	ok(worst > 2.0, "2 MOTION first vs middle frame changed pixels, percent: %s (least %.1f, want > 2)" % [", ".join(shares), worst])
	var bytes := EasyTips.dir_bytes()
	ok(bytes < 3 * 1048576, "3 SIZE assets/tips/easy is %d bytes = %.2f MB (limit 3 MB)" % [bytes, bytes / 1048576.0])

	# into Easy Part from the start screen
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -38.0
	m.yaw = 25.0
	m._cam()
	await idle(40)
	# a real part to look at: a box drawn on the floor and pulled up
	await press(ep().make_btns["draw"])
	var pa: Vector2 = m.cam.unproject_position(Vector3(-0.03, 0.0, -0.03))
	var pb: Vector2 = m.cam.unproject_position(Vector3(0.03, 0.0, 0.03))
	await ev_move(pa)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0), true)
	await ev_mouse(pb, false)
	await idle(3)
	await press(ep().make_btns["pull"])
	await idle(10)
	ep()._ease_end()
	var origin: Vector2 = m.cam.unproject_position(Vector3(0.0, 0.01, 0.0))
	var u0: int = m.undo.size()
	var n0 := nsteps()
	var tv: EasyTips = ep().tips
	var delays := []
	var placed_bad := []
	var shows_bad := []
	var hide_ms := 0.0
	var loops_bad := []
	var frame_ms := []
	for id in IDS:
		var b: Button = ep().make_btns[id]
		var at := b.get_global_rect().get_center()
		await ev_move(Vector2(40.0, 600.0))   # off the buttons, the panel gone
		await idle(2)
		var t0 := Time.get_ticks_usec()
		await ev_move(at + Vector2(0.0, 40.0))
		await ev_move(at)
		var seen := {}
		var shown_at := -1.0
		var last := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 1900000:
			await process_frame
			var now := Time.get_ticks_usec()
			if shown_at < 0.0 and tv.panel.visible:
				shown_at = (now - t0) / 1000.0
				if SHOTS.has(id):
					await shot(id)   # the screenshot's own cost is not the hover's: this frame is left out of the timing
					last = Time.get_ticks_usec()
					continue
			if shown_at >= 0.0:
				seen[tv.frame] = true
				frame_ms.append((now - last) / 1000.0)
				if (now - last) > 33000:
					print("  slow frame %.1f ms: %s, %.0f ms after the hover began, clip frame %d" % [(now - last) / 1000.0, id, (now - t0) / 1000.0, tv.frame])
			last = now
		delays.append(shown_at)
		var words := String(b.get_meta("tip_text", b.tooltip_text))
		if not (shown_at >= 0.0 and shown_at <= 800.0 and tv.shown_id == id and tv.title.text == b.text and tv.body.text == words and words != ""):
			shows_bad.append("%s (%.0f ms, shows %s)" % [id, shown_at, tv.shown_id])
		var r := Rect2(tv.panel.get_global_rect())
		var br := b.get_global_rect()
		var inside := Rect2(0, 0, 1280, 720).encloses(r)
		var under := r.position.y >= br.end.y and r.position.y - br.end.y < 20.0 and r.get_center().x > br.position.x - 100.0 and r.get_center().x < br.end.x + 100.0
		if not inside or not under or r.has_point(origin):
			placed_bad.append("%s rect %s button %s part %s" % [id, str(r), str(br), str(origin)])
		if seen.size() <= 5:
			loops_bad.append("%s %d" % [id, seen.size()])
		var th := Time.get_ticks_usec()
		await ev_move(Vector2(40.0, 600.0))
		var guard := 0
		while tv.panel.visible and guard < 30:
			await process_frame
			guard += 1
		hide_ms = maxf(hide_ms, (Time.get_ticks_usec() - th) / 1000.0)
	var dmax := 0.0
	for d in delays:
		dmax = maxf(dmax, float(d))
	ok(shows_bad.is_empty(), "4 SHOWS all 12 panels showed (slowest %.0f ms, limit 800) with their clip and words %s" % [dmax, str(shows_bad)])
	ok(placed_bad.is_empty(), "5 PLACED all 12 panels whole in 1280 x 720, just under their button, off the part %s" % str(placed_bad))
	ok(loops_bad.is_empty(), "6 LOOPS every clip took more than 5 frame values in 1.9 s %s" % str(loops_bad))
	ok(hide_ms <= 200.0, "7 HIDES worst time from the pointer leaving to the panel gone: %.0f ms (limit 200)" % hide_ms)
	ok(m.undo.size() == u0 and nsteps() == n0, "8 NOUNDO twelve hovers: undo %d -> %d, part steps %d -> %d" % [u0, m.undo.size(), n0, nsteps()])
	frame_ms.sort()
	var med := float(frame_ms[frame_ms.size() / 2]) if frame_ms.size() > 0 else 999.0
	var over := 0
	for f in frame_ms:
		if float(f) > 33.0:
			over += 1
	var mx := float(frame_ms[-1]) if frame_ms.size() > 0 else 999.0
	ok(frame_ms.size() > 100 and over == 0, "9 SMOOTH %d frames while clips play: median %.1f ms, worst %.1f ms, %d over 33 ms" % [frame_ms.size(), med, mx, over])
	print("s094: %d fail" % fails)
	quit(1 if fails > 0 else 0)
