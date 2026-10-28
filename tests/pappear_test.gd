extends SceneTree
## godot --path . --position 4000,4000 -s tests/pappear_test.gd     (GAP item 5, APPEARANCE per body: scripts/build/part.gd appear step and look
## replay, scripts/build/part_ui.gd APPEARANCE panel; needs a window and the CAD DLL). Bars, written before measuring:
##   1 SPLIT     a 100 mm cube split by the Right plane at x = 50 mm (record): 2 bodies whose default looks differ (colour by index)
##   2 PICK      Browser: click Body1 and the APPEARANCE panel opens for it; the Appearance ribbon tool (MODIFY caption menu) keeps a body picked
##   3 COLOUR    Red chip on Body1: ONE undo step, one appear step (body 0, colour red)
##   4 GLASS     Body2 (the front one): Grey chip then Glass preset: two undo steps; the record step holds alpha 0.4 and preset Glass
##   5 SEE       the view: the pixels of the glass front face show the red body behind it (R minus G > 0.05); opaque Paint (the same view): the glass R minus G exceeds the paint R minus G by 0.05 (the light is warm, so a lit grey reads about 0.05; first bar version was an absolute < 0.03, it measured 0.05 and was changed to this relative bar)
##   6 PICKER    the colour picker closing with a new colour: ONE undo step
##   7 FILE      the record as JSON and back: the same looks, the same replay; the Glass step keeps alpha 0.4 exactly
##   8 SPLIT VIEW after a split the view has two surfaces with two colours (the Part mesh overrides)
##   9 SHOT      the Part view with the glass body and the panel: C:/Temp/claude/pappear/glass.png
## Only user:// is written (and the screenshots). With no DLL it says so and stops.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/pappear"
const DIRT := "user://pappear_test"


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
	await idle(2)


## a Part tool as a user reaches it: its own button, else its group caption menu (as ploft_test does)
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
	await idle(2)


func rect_sketch(id: String, plane: String) -> Dictionary:
	return {"t": "sketch", "id": id, "name": "Sketch" + id, "plane": plane, "ents": [{"k": "rect", "a": [0, 0], "b": [100, 60]}], "dims": []}


## the test record: a 100 x 60 x 40 mm body at z 0..40 (Body1), and one at z 60..100 (Body2, in front of it, from an offset plane 60 mm out)
func two_bodies() -> Dictionary:
	var rec := Part.make("Glass test")
	rec["features"] = [
		rect_sketch("f1", "front"),
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 40.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f3", "name": "Plane1", "from": "front", "mm": 60.0},
		rect_sketch("f4", "f3"),
		{"t": "extrude", "id": "f5", "name": "Extrude2", "sketch": "f4", "dist": 40.0, "both": false, "op": "new"},
	]
	rec["seq"] = 5
	return rec


func cube_split() -> Dictionary:
	var rec := Part.make("Split test")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
		{"t": "split", "id": "f3", "name": "Split1", "plane": "right", "at": 50.0},
	]
	rec["seq"] = 3
	return rec


## the mean colour of a 5 x 5 patch at a screen point (viewport coordinates) of the captured view
func patch(img: Image, p: Vector2) -> Color:
	var vs := root.get_visible_rect().size
	var q := p * Vector2(img.get_size()) / vs
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var x := clampi(int(q.x) + dx, 0, img.get_width() - 1)
			var y := clampi(int(q.y) + dy, 0, img.get_height() - 1)
			acc += img.get_pixel(x, y)
			n += 1
	return acc / float(n)


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("SKIP: no KineCAD DLL; appearance needs the kernel")
		quit(0)
		return

	# 1 SPLIT (record): the cube cut in two; each half has its own default look
	var rs := Part.replay(cube_split(), -1, {"edges": false})
	var looks: Array = rs["body_looks"]
	ok(int(rs["bodies"]) == 2 and looks.size() == 2, "1 split: 2 bodies (%d)" % int(rs["bodies"]))
	ok(looks.size() == 2 and not (looks[0]["c"] as Color).is_equal_approx(looks[1]["c"]), "1 split: the two bodies have different default colours")

	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	m.S.part = two_bodies()
	pu.sync()
	await idle(4)
	var nb: int = int(pu.res.get("bodies", 0))
	ok(nb == 2, "setup: two bodies replayed (%d)" % nb)

	# 2 PICK: a browser row picks the body; the panel opens
	var row1 := pu.browser.find_child("part_body_0", true, false) as Button
	await click_ctl(row1)
	ok(pu.sel_body == 0 and pu.look_box.visible and pu.side.visible, "2 Body1 row picks it: the APPEARANCE panel opens")
	ok(String(pu.side_title.text) == "APPEARANCE" and String(pu.look_title.text) == "Body1", "2 the panel is titled APPEARANCE for Body1")
	await press_tool(pu, "Appearance")
	ok(pu.sel_body >= 0 and pu.look_box.visible, "2 the Appearance tool (its MODIFY caption menu) keeps a body picked")

	# 3 COLOUR: red chip on Body1, one undo step
	var n0: int = m.undo.size()
	await click_ctl(pu.look_chips[1])
	var fs: Array = m.S.part["features"]
	var last: Dictionary = fs[-1]
	var lc: Array = last.get("color", [0, 0, 0])
	ok(String(last.get("t", "")) == "appear" and int(last.get("body", -1)) == 0 and float(lc[0]) > 0.6 and float(lc[1]) < 0.3, "3 red chip: an appear step for Body1 holds red (%s)" % [last])
	ok(m.undo.size() == n0 + 1, "3 red chip: one undo step (%d)" % (m.undo.size() - n0))

	# 4 GLASS: Body2 (the front one) grey, then Glass; two steps
	await click_ctl(pu.browser.find_child("part_body_1", true, false))
	ok(pu.sel_body == 1, "4 Body2 row picks the front body")
	await click_ctl(pu.look_chips[0])
	await idle(2)
	n0 = m.undo.size()
	await click_ctl(pu.look_presets["Glass"])
	fs = m.S.part["features"]
	last = fs[-1]
	ok(String(last.get("preset", "")) == "Glass" and absf(float(last.get("alpha", 1.0)) - 0.4) < 1e-9 and int(last.get("body", -1)) == 1, "4 Glass: the record step has alpha 0.4 on Body2 (%s)" % [last])
	ok(m.undo.size() == n0 + 1, "4 Glass preset: one undo step (%d)" % (m.undo.size() - n0))
	ok(pu.look_presets["Glass"].button_pressed, "4 the Glass button shows as the material of Body2")

	# 5 SEE: the glass front face shows the red body behind it
	var pl2 := Part.resolve_plane(m.S.part, "f3")
	var c_glass: Vector2 = m.cam.unproject_position(Part.to_world(pl2, Vector2(50, 30)))
	await idle(4)
	var img := root.get_texture().get_image()
	var g := patch(img, c_glass)
	ok(g.r - g.g > 0.05, "5 SEE glass: the glass front shows the red body behind it (R %.3f G %.3f B %.3f)" % [g.r, g.g, g.b])
	img.save_png("%s/glass.png" % SHOT)
	print("shot %s/glass.png" % SHOT)
	n0 = m.undo.size()
	await click_ctl(pu.look_presets["Paint"])
	await idle(4)
	img = root.get_texture().get_image()
	var o := patch(img, c_glass)
	ok(g.r - g.g > o.r - o.g + 0.05, "5 SEE: the glass shows more red than the paint did (glass R-G %.3f, paint R-G %.3f; paint R %.3f G %.3f B %.3f)" % [g.r - g.g, o.r - o.g, o.r, o.g, o.b])

	# 6 PICKER: a colour picked, one step when it closes
	n0 = m.undo.size()
	pu.look_picker.color = Color(0.1, 0.2, 0.9)
	pu.look_picker.popup_closed.emit()
	await idle(2)
	ok(m.undo.size() == n0 + 1, "6 picker: one undo step on close (%d)" % (m.undo.size() - n0))
	fs = m.S.part["features"]
	ok(String((fs[-1] as Dictionary).get("preset", "")) == "Custom" and int((fs[-1] as Dictionary).get("body", -1)) == 1, "6 picker: the step is a custom colour on Body2")

	# 7 FILE: JSON and back, same looks
	var back: Variant = JSON.parse_string(JSON.stringify(m.S.part))
	var r1 := Part.replay(m.S.part, -1, {"edges": false})
	var r2 := Part.replay(back as Dictionary, -1, {"edges": false})
	var same := (r1["body_looks"] as Array).size() == (r2["body_looks"] as Array).size()
	for i in (r1["body_looks"] as Array).size():
		var a: Dictionary = (r1["body_looks"] as Array)[i]
		var b: Dictionary = (r2["body_looks"] as Array)[i]
		same = same and (a["c"] as Color).is_equal_approx(b["c"]) and absf(float(a["alpha"]) - float(b["alpha"])) < 1e-12 and absf(float(a["rough"]) - float(b["rough"])) < 1e-12
	var gl: Dictionary = Part.feature(back as Dictionary, "f8")   # the Glass step itself (after it: the picker and Paint steps)
	ok(same and absf(float(gl.get("alpha", 0.0)) - 0.4) < 1e-12 and String(gl.get("preset", "")) == "Glass", "7 FILE: the record JSON and back give the same looks; the Glass step keeps alpha 0.4 (%s)" % [gl.get("alpha", "-")])

	# 8 SPLIT VIEW: two surfaces, two colours in the view
	m.S.part = cube_split()
	pu.sync()
	await idle(4)
	var s0 := pu.part_mesh.get_surface_override_material(0) as StandardMaterial3D
	var s1 := pu.part_mesh.get_surface_override_material(1) as StandardMaterial3D
	ok(pu.part_mesh.mesh != null and pu.part_mesh.mesh.get_surface_count() == 2 and s0 != null and s1 != null and not s0.albedo_color.is_equal_approx(s1.albedo_color), "8 split view: two surfaces, two colours")

	print("pappear: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
