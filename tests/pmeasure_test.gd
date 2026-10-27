extends SceneTree
## godot --headless --path . -s tests/pmeasure_test.gd     (GAP 8: MEASURE and SECTION for Part solids: scripts/build/part_ui.gd, view only, no record step, no undo.
## Needs a window (real clicks and the shot); headless = SKIP. Bars, written before measuring:
##   1 DISTANCE  a 100 mm edge of a 100 x 60 x 40 mm box: two real clicks on its two vertices read 100.0 mm within 0.1 mm (the panel says so too)
##   2 LENGTH    one real click on the middle of that edge reads its length, 100.0 mm within 0.1 mm
##   3 AREA      one real click on the 100 x 60 mm face reads 6000 mm2 within 0.5 %
##   4 NO UNDO   measures (and the section) add no undo step; the record is the same
##   5 SECTION   a 100 mm cube (x, y, z 0..100): the Section tool (real click) cuts at the middle (offset 50 mm on the Front plane); the rendered pixels
##               of the cut are the cap colour (#e8833a): at least 500 pixels within 0.02 of it
##   6 SHOT      C:/Temp/claude/pmeasure/shot.png: the cut cube in the Part view, the cap filled
const SHOT := "C:/Temp/claude/pmeasure"
const CAP := Color("#e8833a")
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func box_rec() -> Dictionary:   # 100 x 60 mm, 40 mm high (+Z)
	var rec := Part.make("Box")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 60]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 40.0, "both": false, "op": "new"},
	]
	return rec


func cube_rec() -> Dictionary:
	var rec := Part.make("Cube")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
	]
	return rec


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP 1-6: no window (the real clicks and the shot need one)")
		print("PMEASURE SKIP")
		quit(0)
		return
	if not Part.available():
		print("SKIP 1-6: the CAD kernel is not available")
		quit(0)
		return
	await ui_bars()
	print("PMEASURE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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


## a real click at a screen point: the pointer moves there, then the button goes down and up
func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


## a Part tool picked as a user does: its ribbon button, or (when the row is full at this window) More, then the tool in its menu
func pick_tool(m, pu: PartUI, nm: String) -> void:
	var b: Button = pu.tool_btns[nm]
	if b.visible:
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	await idle(2)
	m._more_pick(m._more_tools.find(b))
	await idle(2)


func last_v(pu: PartUI) -> float:
	return float(pu.meas_out.back()["v"]) if not pu.meas_out.is_empty() else -1.0


func ui_bars() -> void:
	var m = (load("res://main.tscn") as PackedScene).instantiate()
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
	var dirt := "user://pmeasure_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.S.part = box_rec()
	if not pu.on:
		await click_ctl(pu.part_btn)
		await idle(3)
	pu._rebuild(true)
	pu._view_model()
	await idle(4)
	ok(pu.tool_btns.has("Measure") and pu.tool_btns.has("Section") and (pu.tool_btns["Measure"].visible or m.ui_more.visible), "0 RIBBON: Measure and Section are on the Part ribbon (row or More)")

	# 1 DISTANCE and 2 LENGTH on the 100 mm edge along x (y 0, z 0)
	var e100: Dictionary = {}
	var best_sep := 0.0
	for e in pu.edge_cache:
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		if absf(float(e["len"]) - 0.1) < 1e-4 and absf(a.y) < 1e-6 and absf(a.z) < 1e-6 and absf(b.y) < 1e-6 and absf(b.z) < 1e-6:
			var sep: float = m.cam.unproject_position(a).distance_to(m.cam.unproject_position(b))
			if sep > best_sep:
				best_sep = sep
				e100 = e
	await pick_tool(m, pu, "Measure")
	await idle(2)
	ok(pu.tool == "Measure", "1a MEASURE: the Measure tool is on (real click)")
	var n0: int = m.undo.size()
	var rec0 := JSON.stringify(m.S.part)
	if e100.is_empty():
		ok(false, "1 DISTANCE: no 100 mm edge found")
	else:
		var pa: Vector2 = m.cam.unproject_position(e100["a"])
		var pb: Vector2 = m.cam.unproject_position(e100["b"])
		await click_at(pa)
		await click_at(pb)
		var d1 := last_v(pu)
		ok(absf(d1 - 100.0) < 0.1 and pu.meas_out.size() >= 1 and String(pu.meas_out.back()["txt"]).begins_with("Distance") and pu.meas_l.text.contains("Distance"),
				"1 DISTANCE: two vertex clicks read %.3f mm (panel: %s)" % [d1, pu.meas_l.text.replace("\n", " | ")])
		var mid: Vector2 = (pa + pb) * 0.5
		await click_at(mid)
		var l2 := last_v(pu)
		ok(absf(l2 - 100.0) < 0.1 and String(pu.meas_out.back()["txt"]).begins_with("Edge length"), "2 LENGTH: an edge click reads %.3f mm (%s)" % [l2, pu.meas_out.back()["txt"]])

	# 3 AREA: the 100 x 60 face, seen face-on from the Front plane
	pu._view_plane("front")
	await idle(4)
	var fc: Vector2 = m.cam.unproject_position(Vector3(0.05, 0.03, 0.04))
	await click_at(fc)
	var a3 := last_v(pu)
	ok(absf(a3 / 6000.0 - 1.0) < 0.005 and String(pu.meas_out.back()["txt"]).begins_with("Face area"), "3 AREA: a 100 x 60 face reads %.2f mm2 (want 6000)" % a3)

	# 4 NO UNDO
	ok(m.undo.size() == n0 and JSON.stringify(m.S.part) == rec0, "4 NO UNDO: %d measures, undo steps %d -> %d, record unchanged" % [pu.meas_out.size(), n0, m.undo.size()])

	# 5 SECTION: a 100 mm cube, cut at the middle (Front plane, offset 50 mm along its normal)
	m.S.part = cube_rec()
	pu._rebuild(true)
	await idle(2)
	pu._view_plane("front")
	await idle(3)
	var n5: int = m.undo.size()
	var rec5 := JSON.stringify(m.S.part)
	await pick_tool(m, pu, "Section")
	await idle(3)
	pu.sec_slider.value = 50.0
	await idle(4)
	ok(pu.sec_on and pu.sec_box.visible and m.undo.size() == n5 and JSON.stringify(m.S.part) == rec5, "5a SECTION: the Section tool (real click) cuts; no undo step, record unchanged (on %s, box %s, undo %d -> %d, record same %s, tool %s)" % [pu.sec_on, pu.sec_box.visible, n5, m.undo.size(), JSON.stringify(m.S.part) == rec5, pu.tool])
	await shot("shot")
	var img := root.get_texture().get_image()
	var hits := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - CAP.r) < 0.02 and absf(c.g - CAP.g) < 0.02 and absf(c.b - CAP.b) < 0.02:
				hits += 1
	ok(hits >= 500, "5b SECTION: cap-coloured pixels in the view: %d (want >= 500 at half density)" % hits)
	DirAccess.make_dir_recursive_absolute(SHOT)
	pu.sec_mm = 0.0
	pu._sec_apply()
	await idle(3)
	pu.sec_on = false
	pu._sec_apply()
	await idle(2)
	ok(not pu.sec_on and m.undo.size() == n5, "5c SECTION off: the solid is whole again (no undo step)")
