extends SceneTree
## godot --path . --position 4000,4000 -s tests/pcanvas_test.gd     (GAP item 3, CANVAS: a reference picture on the Front plane in the Part workspace; scripts/build/part.gd canvas_* and part_ui.gd Canvas; needs a window and the CAD DLL)
## A 600 x 300 px test picture with two marks 400 px apart (made here in user://). Canvas on the Front plane (Canvas, caption CREATE), the picture chosen,
## two real clicks on the marks, the real distance typed as 100 mm (the marks are 100 mm apart). Bars, written before measuring:
##   1 RIBBON   Canvas is reached from the Part ribbon (its row or its caption menu): the dialog opens with its own rows
##   2 PICK     the picture is loaded in the dialog (a working picture, not yet a step): no undo step, no canvas in the record yet
##   3 CLICK    two real mouse clicks on the marks: the two points read within 1 px of the marks, 400 px apart; the hint asks for the distance
##   4 OK       the distance typed, OK by click: ONE undo step, one canvas feature on Front: path, w 600, h 300, dist 100, opacity 0.8, shown; no solid
##   5 LINEUP   a 100 mm rectangle sketched by real drags from the first mark (100,-100) to (200,-40) mm on Front: the second mark lies on its corner
##              within 1 mm on the screen at 1280 x 720 (screen distance divided by mm per pixel)
##   6 MOVE     a real drag on the saved picture moves it 20 mm: ONE undo step, its position moves by 20 mm exactly
##   7 HIDE     the browser row of the picture hides it (one undo step), a second click shows it (one undo step)
##   8 OPACITY  the picture step opens its dialog; the opacity 0.3 by its slider and OK: one undo step, opacity 0.3
##   9 FILE     save, new scene, load: the same record (JSON) and the same replay
##  10 SHOT     the Front sketch with the picture behind it: C:/Temp/claude/pcanvas/shot.png
const SHOT := "C:/Temp/claude/pcanvas"
const DIRT := "user://pcanvas_test"
const MARK1 := Vector2(100, 100)
const MARK2 := Vector2(500, 100)
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


func key(k: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		root.push_input(e, true)
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## a Part tool as a user reaches it: its own row button, else its group caption menu, else More
func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	for pair in m.ui_caps.get("BUILD", []):
		if (pair[1] as Array).has(b):
			await click_ctl(pair[0])
			(pair[0] as MenuButton).get_popup().hide()
			m._run_tool(b, pair[0])
			await idle(2)
			return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


## the screen point of a plane point (mm)
func spp(pl: Dictionary, x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(pl, Vector2(x, y)))


func drag_on(pl: Dictionary, x0: float, y0: float, x1: float, y1: float) -> void:
	await ev_move(spp(pl, x0, y0), false)
	await ev_mouse(spp(pl, x0, y0), true)
	await ev_move(spp(pl, (x0 + x1) * 0.5, (y0 + y1) * 0.5))
	await ev_move(spp(pl, x1, y1))
	await ev_mouse(spp(pl, x1, y1), false)
	await idle(2)


## the picture pixel as a screen point, through the record mapping of the picture feature
func pix_screen(f: Dictionary, px: Vector2) -> Vector2:
	var pl := Part.resolve_plane(m.S.part, String(f["plane"]))
	return m.cam.unproject_position(Part.to_world(pl, Part.canvas_px_to_mm(f, px)))


func make_picture(path: String) -> void:
	var img := Image.create(600, 300, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	img.fill_rect(Rect2i(int(MARK1.x) - 4, int(MARK1.y) - 4, 9, 9), Color.RED)
	img.fill_rect(Rect2i(int(MARK2.x) - 4, int(MARK2.y) - 4, 9, 9), Color.RED)
	img.save_png(path)


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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL; pcanvas needs the kernel for the Part workspace")
		quit(0)
		return
	var pic := DIRT + "/marks.png"
	make_picture(pic)
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	var front := Part.plane("front")

	# 1 RIBBON
	await press_tool(pu, "Canvas")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "canvas" and pu.side.visible and pu.f_cv_pick != null, "1 RIBBON: Canvas opens its dialog on the right (dlg %s)" % String(pu.dlg.get("t", "none")))
	await idle(2)

	# 2 PICK (the file chooser sends this signal when its OK is pressed)
	var n0: int = m.undo.size()
	pu.f_cv_file.file_selected.emit(pic)
	await idle(3)
	ok(String(pu.dlg["cv"]["path"]) == pic and int(pu.dlg["cv"]["w"]) == 600 and int(pu.dlg["cv"]["h"]) == 300 and m.undo.size() == n0 and (m.S.part.get("features", []) as Array).is_empty(), "2 PICK: the picture is loaded (600 x 300), no step yet")
	await shot("picked")

	# 3 CLICK: two real clicks on the marks (at 1 mm per pixel until calibrated)
	await click_at(spp(front, MARK1.x, -MARK1.y))
	await click_at(spp(front, MARK2.x, -MARK2.y))
	var pts: Array = pu.dlg["cv"]["pts"]
	ok(pts.size() == 2 and Part.v2(pts[0]).distance_to(MARK1) < 1.0 and Part.v2(pts[1]).distance_to(MARK2) < 1.0, "3 CLICK: the two points on the marks %s (within 1 px)" % [pts])
	ok(pts.size() == 2 and Part.v2(pts[1]).distance_to(Part.v2(pts[0])) > 399.0 and Part.v2(pts[1]).distance_to(Part.v2(pts[0])) < 401.0, "3 CLICK: 400 px apart")
	ok(String(pu.dlg_info.text).contains("distance"), "3 CLICK: the hint asks for the distance (%s)" % String(pu.dlg_info.text).left(60))

	# 4 OK: the distance typed (the picture follows it), then OK by click
	await click_ctl(pu.f_num)
	await key(KEY_A)
	pu.f_num.text = ""
	for ch in "100":
		await key(KEY_0 + int(ch), ch.unicode_at(0))
	await idle(2)
	var cvf: Dictionary = pu._canvas_feature(false)
	ok(absf(float(cvf["dist"]) - 100.0) < 1e-6 and absf(Part.canvas_scale(cvf) - 0.25) < 1e-3, "4 typed 100 mm: 0.25 mm per pixel (%s)" % Part.canvas_scale(cvf))
	n0 = m.undo.size()
	await click_ctl(pu.ok_btn)
	await idle(3)
	var cf := Part.feature(m.S.part, "f1")
	ok(String(cf.get("t", "")) == "canvas" and String(cf.get("plane", "")) == "front" and int(cf.get("w", 0)) == 600 and absf(float(cf.get("dist", 0.0)) - 100.0) < 1e-6 and absf(float(cf.get("opacity", 0.0)) - 0.8) < 1e-6 and bool(cf.get("show", false)), "4 OK: one canvas feature on Front: %s" % [cf])
	ok(m.undo.size() == n0 + 1, "4 OK: ONE undo step (%d)" % (m.undo.size() - n0))
	ok(int(pu.res.get("bodies", 0)) == 0 and pu.res.get("mesh", null) == null, "4 the picture is not a solid: 0 bodies, no mesh")
	var at0 := Vector2(float(cf["at"][0]), float(cf["at"][1]))
	ok(at0.distance_to(Vector2(75, -75)) < 0.5, "4 the picture sits at (75, -75) mm, so the first mark is at (100, -100) (%s)" % [at0])

	# 5 LINEUP: a 100 mm rectangle from the first mark, 60 mm down, by real drags on Front
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await press_tool(pu, "Rectangle")
	await drag_on(front, 100, -100, 200, -40)
	var er: Array = pu._sk().get("ents", [])
	ok(er.size() == 1 and er[0]["k"] == "rect" and Part.v2(er[0]["a"]).is_equal_approx(Vector2(100, -100)) and Part.v2(er[0]["b"]).is_equal_approx(Vector2(200, -40)), "5 LINEUP: the rectangle is 100 x 60 mm from (100, -100): %s" % [er])
	var m2: Vector2 = pix_screen(cf, MARK2)
	var rc: Vector2 = spp(front, 200, -100)
	var mm_px: float = spp(front, 201, -100).distance_to(spp(front, 200, -100))
	var err_mm := m2.distance_to(rc) / maxf(mm_px, 1e-6)
	ok(err_mm < 1.0, "5 LINEUP: the picture 100 mm mark and the rectangle corner differ by %.3f mm on screen (%.1f px per mm)" % [err_mm, mm_px])
	await shot("sketch")
	await click_ctl(pu.finish_btn)
	await idle(2)

	# 6 MOVE: a real drag on the saved picture, 20 mm to the right
	n0 = m.undo.size()
	var pc := Part.feature(m.S.part, "f1")
	var before := Vector2(float(pc["at"][0]), float(pc["at"][1]))
	await drag_on(front, 150, -110, 170, -110)
	pc = Part.feature(m.S.part, "f1")
	var after := Vector2(float(pc["at"][0]), float(pc["at"][1]))
	ok(after.distance_to(before + Vector2(20, 0)) < 1e-3 and m.undo.size() == n0 + 1, "6 MOVE: moved 20 mm (%s -> %s), ONE undo step (%d)" % [before, after, m.undo.size() - n0])
	await idle(2)

	# 7 HIDE / SHOW by the browser row
	n0 = m.undo.size()
	var row := pu.browser.find_child("part_canvas_f1", true, false) as Button
	ok(row != null, "7 HIDE: the picture is a browser row (part_canvas_f1)")
	if row != null:
		await click_ctl(row)
		ok(not bool(Part.feature(m.S.part, "f1")["show"]) and m.undo.size() == n0 + 1, "7 HIDE: hidden, one undo step (%d)" % (m.undo.size() - n0))
		row = pu.browser.find_child("part_canvas_f1", true, false) as Button
		await click_ctl(row)
		ok(bool(Part.feature(m.S.part, "f1")["show"]) and m.undo.size() == n0 + 2, "7 SHOW: shown again, one undo step")
	await shot("model")

	# 8 OPACITY: the step opens the dialog; the slider to 0.3; OK
	n0 = m.undo.size()
	pu.edit_step(Part.index_of(m.S.part, "f1"))
	await idle(3)
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "canvas" and int(pu.dlg["edit"]) == Part.index_of(m.S.part, "f1"), "8 OPACITY: the picture step opens its dialog")
	pu.f_cv_op.value = 0.3
	await idle(2)
	await click_ctl(pu.ok_btn)
	await idle(2)
	ok(absf(float(Part.feature(m.S.part, "f1")["opacity"]) - 0.3) < 1e-6 and m.undo.size() == n0 + 1, "8 OPACITY: 0.3 kept, ONE undo step (%d)" % (m.undo.size() - n0))

	# 9 FILE
	var saved := JSON.stringify(JSON.parse_string(ps()))
	var rep0: Dictionary = Part.replay(m.S.part)
	var path := DIRT + "/pcanvas.json"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	fh.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(2)
	ok(m.S.part.is_empty(), "9 a new scene has no part")
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	var rep1: Dictionary = Part.replay(m.S.part)
	ok(JSON.stringify(JSON.parse_string(ps())) == saved and String(Part.feature(m.S.part, "f1").get("path", "")) == pic, "9 FILE: the same record, the picture path kept")
	ok(int(rep1["bodies"]) == int(rep0["bodies"]), "9 FILE: the same replay (bodies %s)" % rep1["bodies"])

	# 10 SHOT: the Front sketch with the picture behind it
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await idle(3)
	await shot("shot")
	await click_ctl(pu.finish_btn)
	print("pcanvas: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
