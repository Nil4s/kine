extends SceneTree
## godot --path . --position 4000,4000 -s tests/pcube_test.gd     (PCUBE: the Part side panels never sit under the ViewCube or its two menus; scripts/build/part_ui.gd layout, main.gd _place_cube; needs a window and the CAD DLL)
## Bars, at 1280 x 720 and 1600 x 900 (real clicks; a 3D BUILDING project with two bodies):
##   1 DIALOGS   each Part dialog opens by its ribbon button: Extrude, Pattern, Combine, Sweep, the Appearance panel (a browser row), the Measure panel
##   2 NO COVER  the side panel (or the measure / section panel) rect does not intersect the ViewCube rect nor its two menus (when shown)
##   3 INSIDE    every visible control in the panel is inside the window
##   4 CLICK     a click on the ViewCube turns the view (the camera basis changes)
## Shot: C:/Temp/claude/pcube/shot.png (Pattern dialog at 1280 x 720). Only user:// is written (and the screenshots). No DLL: SKIP.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/pcube"
const DIRT := "user://pcube_test"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900)]


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


## a Part tool as a user reaches it: its own button, else its group caption menu, else More
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


func rect_sketch(id: String, plane: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"t": "sketch", "id": id, "name": "Sketch" + id, "plane": plane, "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []}


## two 20 mm-deep bodies, then extra features (a spare closed sketch for Extrude, a path for Sweep)
func base_rec(extra: Array) -> Dictionary:
	var r := Part.make("Pcube test")
	var f: Array = [
		rect_sketch("f1", "front", -100.0, 0.0, -20.0, 40.0),
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"},
		rect_sketch("f3", "front", 60.0, 0.0, 140.0, 40.0),
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 20.0, "both": false, "op": "new"},
	]
	f.append_array(extra)
	r["features"] = f
	r["seq"] = f.size()
	return r


func spare_rec() -> Dictionary:
	return base_rec([rect_sketch("f5", "front", -60.0, 120.0, 0.0, 160.0)])


func sweep_rec() -> Dictionary:
	var path := {"t": "sketch", "id": "f6", "name": "Sketch6", "plane": "top", "ents": [{"k": "line", "a": [0.0, 0.0], "b": [0.0, -100.0]}], "dims": []}
	return base_rec([rect_sketch("f5", "front", -60.0, 120.0, 0.0, 160.0), path])


## the visible panels of the right column: the side panel, the measure panel, the section box
func panels(pu: PartUI) -> Array:
	var out := []
	for c in [pu.side, pu.meas_panel, pu.sec_box]:
		if c != null and c.is_visible_in_tree():
			out.append(c)
	return out


func check_panels(tag: String, pu: PartUI) -> void:
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var cube: Rect2 = m.ui_cube.get_global_rect()
	var blocks := [cube]
	for k in [m.ui_light_btn, m.ui_shade_btn]:
		if k != null and k.is_visible_in_tree():
			blocks.append((k as Control).get_global_rect())
	var ps := panels(pu)
	ok(not ps.is_empty(), "%s a panel is shown" % tag)
	for p in ps:
		var pr: Rect2 = (p as Control).get_global_rect()
		var hit := false
		for b in blocks:
			if pr.intersects(b):
				hit = true
		ok(not hit, "%s NO COVER: %s %s is clear of the ViewCube and its menus (cube %s)" % [tag, p.name, pr, cube])
		ok(vp.encloses(pr), "%s NO COVER: %s %s is inside the window %s" % [tag, p.name, pr, vp])
		var bad := []
		for c in (p as Node).find_children("*", "Control", true, false):
			var cc := c as Control
			if not cc.is_visible_in_tree():
				continue
			if cc.get_child_count() > 0 and not (cc is Button or cc is LineEdit or cc is OptionButton or cc is SpinBox):
				continue
			if cc.size.x <= 0.0 or cc.size.y <= 0.0:
				continue
			if cc is Label and (cc as Label).text == "":
				continue
			var r := cc.get_global_rect()
			if not vp.grow(0.5).encloses(r):
				bad.append("%s %s" % [cc.name, r])
		ok(bad.is_empty(), "%s INSIDE: every visible field in %s is inside the window %s" % [tag, p.name, bad])


func cube_click(tag: String) -> void:
	var cube: Rect2 = m.ui_cube.get_global_rect()
	var b0: Basis = m.cam.global_transform.basis
	var pick := Vector2(-1, -1)
	for y in range(40, 100, 4):   # a face the view is not already on, near the cube middle
		for x in range(40, 100, 4):
			var lp := Vector2(x, y)
			if m.ui_cube.face_at(lp) >= 0 and m.ui_cube.dir_at(lp).dot(b0.z) < 0.5:
				pick = lp
				break
		if pick.x >= 0.0:
			break
	ok(pick.x >= 0.0, "%s CLICK: the cube has a face to click" % tag)
	for down in [true, false]:   # a press and a release on the cube, delivered to the cube as its own input (local coordinates)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = pick
		e.global_position = cube.position + pick
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.ui_cube._gui_input(e)
	await idle(60)
	var b1: Basis = m.cam.global_transform.basis
	ok(not b0.is_equal_approx(b1), "%s CLICK: a click on the ViewCube turns the view" % tag)


func case_run(tag: String, pu: PartUI, rec: Dictionary, t: String, shot := "") -> void:
	m.S.part = rec
	m.bld.sync()
	await idle(3)
	await press_tool(pu, t)
	await idle(4)
	ok(pu.tool == t or not pu.dlg.is_empty() or pu.meas_panel.is_visible_in_tree(), "%s 1 %s opens" % [tag, t])
	check_panels(tag, pu)
	if shot != "":
		await idle(2)
		root.get_texture().get_image().save_png("%s/%s" % [SHOT, shot])
	if pu.cancel_btn != null and pu.cancel_btn.is_visible_in_tree():
		await click_ctl(pu.cancel_btn)
		await idle(2)


func run_size(sz: Vector2i) -> void:
	var tag := "%dx%d" % [sz.x, sz.y]
	DisplayServer.window_set_size(sz)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = sz
	await idle(10)
	var pu: PartUI = m.bld.part
	await case_run(tag + " EXTRUDE", pu, spare_rec(), "Extrude")
	await case_run(tag + " PATTERN", pu, base_rec([]), "Pattern", "shot.png" if sz.x == 1280 else "shot_1600.png")
	await case_run(tag + " COMBINE", pu, base_rec([]), "Combine")
	await case_run(tag + " SWEEP", pu, sweep_rec(), "Sweep")
	m.S.part = base_rec([])
	m.bld.sync()
	await idle(3)
	var row := pu.browser.find_child("part_body_0", true, false) as Button
	await click_ctl(row)
	await idle(3)
	await press_tool(pu, "Appearance")
	await idle(4)
	ok(pu.look_box.is_visible_in_tree(), "%s 1 Appearance panel opens" % tag)
	check_panels(tag + " APPEARANCE", pu)
	await case_run(tag + " MEASURE", pu, base_rec([]), "Measure")
	if sz.x == 1280:
		await cube_click(tag)


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: no window (the real clicks and the shot need one)")
		print("PCUBE SKIP")
		quit(0)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	if not Part.available():
		print("SKIP: no KineCAD DLL; pcube needs the kernel")
		print("PCUBE SKIP")
		quit(0)
		return
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(SHOT)
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on, "0 Part workspace on")
	for sz in SIZES:
		await run_size(sz)
	print("PCUBE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
