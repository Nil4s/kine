extends SceneTree
## s168 + s169 (Friday plan 168 "Rebuild only the changed steps", 169 "Background tessellation so sliders stay smooth"): a slider change on step k
## replays only steps k..n (each step's kernel shape is kept under a hash of the record up to it) and the slider preview is tessellated on a
## WorkerThreadPool task, the old mesh staying until the new one is ready. Real clicks and drags at 1280 x 720 from the BUILDING card, on a 12-step part.
## Bars (measured from the built result: kernel-step counter, volumes, boxes, frame clock; never from a variable of the code):
##   0 the BUILDING card, one click: Easy Part on
##   1 the walk builds a 12-step part (5 pieces pulled up, the last one rounded and hollowed): 12 features, its newest slider is Wall
##   2 a FULL replay of that record (no cache) runs 12 steps (the counter counts what the kernel was asked)
##   3 a real drag of the LAST step's slider (Wall): every rebuild runs exactly 1 step (not 12); at least 3 rebuilds measured
##   4 the drag's end state equals a full replay of the same record: volume within 1e-6 (relative), box within 1e-6 m
##   5 a click on the 6th step's row and a drag of its slider: every rebuild runs exactly 7 steps (6..12), the result equals a full replay
##   6 Ctrl+Z after that drag: the volume is the one before it (1e-9 relative) and equals a full replay; one more drag after the undo still equals a full replay
##   7 a 2-second drag of the Wall slider: main-thread frame time p95 is lower than on origin (both printed; origin measured by the same test on origin)
##   8 background tessellation: meshes landed from the worker during the drag, nothing pending at rest, the shown mesh at rest is the full-detail one
## shots: C:/Temp/claude/s168/
const SHOT_DIR := "C:/Temp/claude/s168"
const DIRT := "user://s168_test"
const BASE := false   # the origin copy of this test (made by sed) measures only the frame time and writes it to base_p95.txt

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func runs() -> int:
	return Part.step_runs   # NEWAPI


func landed() -> int:
	return pu().tess_landed   # NEWAPI


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
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(12)


## the step list scrolls (12 rows, room for two): bring the row into view, then it is clicked for real
func show_row(row: Control) -> void:
	var sc: Node = row.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(row)
		await idle(4)


func feats() -> Array:
	return pu()._rec().get("features", [])


## the screen point of fraction f along a slider's track
func slider_pt(sl: HSlider, f: float) -> Vector2:
	var g := sl.get_theme_icon("grabber")
	var gw := float(g.get_width()) if g != null else 16.0
	var r := sl.get_global_rect()
	return Vector2(r.position.x + gw * 0.5 + (r.size.x - gw) * clampf(f, 0.0, 1.0), r.get_center().y)


func frac_of(sl: HSlider) -> float:
	return (sl.value - sl.min_value) / (sl.max_value - sl.min_value)


## a real drag along the slider from fraction a to b in n frames. Answers the kernel steps each frame's rebuild ran (only frames that ran some)
func drag_frac(sl: HSlider, a: float, b: float, n: int) -> Array:
	var per := []
	Part.inc_trace = true   # NEWAPI
	await ev_move(slider_pt(sl, a), false)
	await ev_mouse(slider_pt(sl, a), true)
	for i in range(1, n + 1):
		var r0 := runs()
		var tp := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tp < 120:   # a human hand: the 100 ms flush throttle lets one rebuild through per move
			await process_frame
		await ev_move(slider_pt(sl, lerpf(a, b, float(i) / float(n))))
		await process_frame
		var d := runs() - r0
		if d > 0:
			per.append(d)
	await ev_mouse(slider_pt(sl, b), false)
	await idle(3)
	Part.inc_trace = false   # NEWAPI
	return per


## a drag that lasts `secs` of wall time, the grabber swinging between 25 and 75 pct: the frame times in ms
func drag_timed(sl: HSlider, secs: float) -> Array:
	var dts := []
	await ev_move(slider_pt(sl, 0.25), false)
	await ev_mouse(slider_pt(sl, 0.25), true)
	var t0 := Time.get_ticks_usec()
	var last := t0
	while float(Time.get_ticks_usec() - t0) < secs * 1e6:
		var ph := float(Time.get_ticks_usec() - t0) / 1e6
		await ev_move(slider_pt(sl, 0.5 + 0.25 * sin(ph * TAU * 0.8)))
		var now := Time.get_ticks_usec()
		dts.append(float(now - last) / 1000.0)
		last = now
	await ev_mouse(slider_pt(sl, 0.5), false)
	await idle(3)
	return dts


func p95(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(ceil(0.95 * float(s.size()))) - 1)]) if s.size() > 0 else 0.0


func mean(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t / maxf(1.0, float(a.size()))


func full_replay(rec: Dictionary) -> Dictionary:
	return Part.replay(rec, -1, {})


func box_close(a: AABB, b: AABB, tol: float) -> bool:
	return a.position.distance_to(b.position) <= tol and a.size.distance_to(b.size) <= tol


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-30)


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

	# 0 the BUILDING card, one click
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
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)
	var ep = pu().ep

	# 1 five pieces pulled up, the last rounded and hollowed
	var xs := [-150.0, -75.0, 0.0, 75.0]
	for x in xs:
		await click_ctl(ep.make_btns["draw"])
		await drag_screen(fl(x - 20.0, -20.0), fl(x + 20.0, 20.0))
		await click_ctl(ep.make_btns["pull"])
		await idle(6)
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(fl(120.0, -40.0), fl(200.0, 40.0))
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	await click_ctl(ep.make_btns["hole"])
	await idle(6)
	await click_ctl(ep.hole_btns["hollow"])
	await idle(12)
	var kinds := []
	for f in feats():
		kinds.append(String(f["t"]))
	print("MEASURE features=%d %s" % [feats().size(), str(kinds)])
	var sl: HSlider = last_slider()
	var lbl := ""
	if sl != null:
		for c in sl.get_parent().find_children("*", "Label", true, false):
			if String((c as Label).text) in ["Wall", "How far", "How round"]:
				lbl = String((c as Label).text)
	ok(feats().size() == 12 and sl != null and lbl == "Wall",
		"1 the walk builds a 12-step part (%d features), its newest slider is %s" % [feats().size(), lbl])
	await shot("01_part")

	# 2 a full replay without the cache runs every step
	var r0 := runs()
	var ref0 := full_replay(pu()._rec())
	var n_full := runs() - r0
	ok(n_full == feats().size(), "2 a full replay (no cache) runs %d steps (the part has %d)" % [n_full, feats().size()])

	if not BASE:
		Part.calls_log = []   # NEWAPI
		# 3 the LAST step's slider
		var v_before := float(pu().res.get("volume", 0.0))
		var per: Array = await drag_frac(sl, frac_of(sl), 0.9, 24)
		print("MEASURE last-step drag: rebuilds=%d steps per rebuild=%s" % [per.size(), str(per)])
		var all1 := not per.is_empty()
		for d in per:
			all1 = all1 and int(d) == 1
		ok(per.size() >= 3 and all1, "3 dragging the LAST step's slider: %d rebuilds, each ran exactly 1 step (not %d)" % [per.size(), feats().size()])
		var cl: Array = Part.calls_log   # NEWAPI
		var callers := {}
		for c in cl:
			var k := "%s:%s %s" % [c[3], c[4], c[2]]
			callers[k] = int(callers.get(k, 0)) + 1
		print("MEASURE replay calls during the drag by caller: %s" % str(callers))
		Part.calls_log = null   # NEWAPI
		# 4 the end state is the full replay's
		var rf := full_replay(pu()._rec())
		var vr := float(pu().res.get("volume", 0.0))
		var bb: AABB = pu().res.get("aabb", AABB())
		var bd := bb.position.distance_to((rf["aabb"] as AABB).position) + bb.size.distance_to((rf["aabb"] as AABB).size)
		ok(rel(vr, float(rf["volume"])) <= 1e-6 and vr != v_before and bd <= 1e-6,
			"4 the end state equals a full replay: volume %.3f vs %.3f mm3 (rel %s), box off by %s m" % [vr * 1e9, float(rf["volume"]) * 1e9, str(rel(vr, float(rf["volume"]))), str(bd)])
		await shot("02_after_last")

		# 5 the 6th step: click its row, drag its slider
		var f6: Dictionary = feats()[5]
		var row := find_named(m, "easypart_step_%s" % String(f6["id"])) as Button
		var v_pre6 := float(pu().res.get("volume", 0.0))
		var ub: int = m.undo.size()
		var row_ok := row != null   # the click rebuilds the step list: the button is freed after it
		if row != null:
			await show_row(row)
			await click_ctl(row)
			await idle(8)
		var sl6: HSlider = last_slider()
		var per6: Array = []
		if sl6 != null:
			var a6 := frac_of(sl6)
			per6 = await drag_frac(sl6, a6, (a6 + 0.4) if a6 < 0.5 else (a6 - 0.4), 24)
		print("MEASURE step-6 (%s) drag: rebuilds=%d steps per rebuild=%s, undo steps +%d" % [String(f6["t"]), per6.size(), str(per6), m.undo.size() - ub])
		var all7 := not per6.is_empty()
		for d in per6:
			all7 = all7 and int(d) == 7
		var rf6 := full_replay(pu()._rec())
		var vr6 := float(pu().res.get("volume", 0.0))
		print("MEASURE step-6 conditions: row=%s sl6=%s n=%d all7=%s rel=%s dv=%s" % [str(row_ok), str(sl6 != null), per6.size(), str(all7), str(rel(vr6, float(rf6["volume"]))), str(vr6 - v_pre6)])
		ok(row_ok and sl6 != null and per6.size() >= 3 and all7 and rel(vr6, float(rf6["volume"])) <= 1e-6 and absf(vr6 - v_pre6) > 0.0,
			"5 dragging the 6th step's slider: %d rebuilds, each ran exactly 7 steps (6..12); result = full replay (volume %.3f vs %.3f mm3)" % [per6.size(), vr6 * 1e9, float(rf6["volume"]) * 1e9])
		await shot("03_after_step6")

		# 6 undo
		await ctrl_z()
		var vu := float(pu().res.get("volume", 0.0))
		var rfu := full_replay(pu()._rec())
		ok(rel(vu, v_pre6) <= 1e-9 and rel(vu, float(rfu["volume"])) <= 1e-9,
			"6a Ctrl+Z puts the volume back: %.6f mm3 (before %.6f), a full replay says %.6f" % [vu * 1e9, v_pre6 * 1e9, float(rfu["volume"]) * 1e9])
		sl = last_slider()
		var per_u: Array = []
		if sl != null:
			var au := frac_of(sl)
			per_u = await drag_frac(sl, au, 0.8 if au < 0.5 else 0.2, 12)
		var rfa := full_replay(pu()._rec())
		var va := float(pu().res.get("volume", 0.0))
		ok(per_u.size() >= 1 and rel(va, float(rfa["volume"])) <= 1e-6 and box_close(pu().res.get("aabb", AABB()), rfa["aabb"], 1e-6),
			"6b a drag after the undo still equals a full replay (volume %.3f vs %.3f mm3, %d rebuilds %s)" % [va * 1e9, float(rfa["volume"]) * 1e9, per_u.size(), str(per_u)])

	# 7 the 2-second drag, frame times
	var last_row := find_named(m, "easypart_step_%s" % String(feats()[feats().size() - 1]["id"])) as Button
	if last_row != null:
		await show_row(last_row)
		await click_ctl(last_row)
		await idle(8)
	sl = last_slider()
	var l0 := 0 if BASE else landed()
	var dts: Array = []
	if sl != null:
		dts = await drag_timed(sl, 2.0)
	var l1 := 0 if BASE else landed()
	var p := p95(dts)
	print("MEASURE 2s drag: frames=%d mean=%.2f ms p95=%.2f ms max=%.2f ms landed=%d" % [dts.size(), mean(dts), p, (dts.max() if dts.size() > 0 else 0.0), l1 - l0])
	if BASE:
		var fb := FileAccess.open(SHOT_DIR + "/base_p95.txt", FileAccess.WRITE)
		fb.store_string("%.4f\n%.4f\n" % [p, mean(dts)])
		fb.close()
		print("s168base: %d fail" % fails)
		quit(0)
		return
	var base_p := -1.0
	if FileAccess.file_exists(SHOT_DIR + "/base_p95.txt"):
		base_p = float(FileAccess.get_file_as_string(SHOT_DIR + "/base_p95.txt").split("\n")[0])
	ok(base_p > 0.0 and p < base_p, "7 main-thread frame time over a 2 s drag: p95 %.2f ms now, %.2f ms on origin" % [p, base_p])
	ok(l1 - l0 > 0, "8a meshes from the worker reached the view during the drag (%d landed)" % (l1 - l0))
	await idle(10)
	var guard := 0
	while (not pu()._tess_run.is_empty() or not pu()._tess_next.is_empty()) and guard < 200:   # a job that was on its way when the slider let go finishes (and is dropped as stale)
		await process_frame
		guard += 1
	var rff := full_replay(pu()._rec())
	var t_rest := 0
	var me: Mesh = pu().part_mesh.mesh
	for s in me.get_surface_count():
		t_rest += (me.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var t_ref := 0
	for s in (rff["mesh"] as Mesh).get_surface_count():
		t_ref += ((rff["mesh"] as Mesh).surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("MEASURE pending: run=%s next=%s coarse=%s" % [str(pu()._tess_run.size()), str(pu()._tess_next.size()), str(pu().coarse)])
	ok(pu()._tess_run.is_empty() and pu()._tess_next.is_empty() and t_ref > 0 and absf(float(t_rest - t_ref)) <= 0.01 * float(t_ref),
		"8b at rest nothing is pending and the shown mesh is full detail: %d triangles vs %d from a full replay" % [t_rest, t_ref])
	await shot("04_rest")

	print("s168: %d fail" % fails)
	quit(fails)
