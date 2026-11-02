extends SceneTree
## godot --path . --position 4000,4000 -s tests/w06b_test.gd     (W06b: typed exact sizes in EXPERT Part; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720, from the real start screen (3D BUILDING card), Part button on BUILD.

const SHOT := "C:/Users/Nick/tools/kine_workers/out/w06b"
const DIRT := "user://w06b_test"
const MM := 0.001
var fails := 0
var m: Node
var log_lines: Array = []


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func note(w: String) -> void:
	print("   note: " + w)
	log_lines.append(w)


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


func key(k: Key, ctrl := false, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame


## one typed character as the key it is: digits, ".", "x", letters
func type_chars(s: String) -> void:
	for ch in s:
		var k: Key = KEY_PERIOD if ch == "." else (KEY_X if ch == "x" else (KEY_0 + int(ch) if ch >= "0" and ch <= "9" else KEY_A + (ch.unicode_at(0) - 97)))
		await key(k, false, ch.unicode_at(0))
	await idle(2)


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


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	await key(KEY_A, true)
	await type_chars(txt)
	await key(KEY_ENTER)
	await idle(2)


## a sketch point (mm) of a plane, as a screen point
func sp(pl_name: String, x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane(pl_name), Vector2(x, y)))


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
	ok(i >= 0, "%s is reachable (in More at this size)" % t)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func sk_ents() -> Array:
	return m.bld.part._sk()["ents"] if m.bld.part.sk != "" else []


func sk_dims() -> Array:
	return m.bld.part._sk().get("dims", []) if m.bld.part.sk != "" else []


func pv(pu: PartUI, nm: String, d: Variant) -> Variant:
	var v: Variant = pu.get(nm)
	return d if v == null else v



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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(1)
		return
	ss.show_screen()
	await idle(3)
	if ss._easy_btn["building"].button_pressed:
		await click_ctl(ss._easy_btn["building"])
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on and pu.tool_btns.has("Line"), "start: Part tools on")
	# bars: 1.5in -> 38.1 ; 2inx1in -> 50.8 x 25.4 ; inch dialog default in inches
	await press_tool(pu, "Line")
	await click_at(sp("front", 60, 42))
	await ev_move(sp("front", 90, 42), false)
	await type_chars("1.5in")
	await key(KEY_ENTER)
	await idle(2)
	var es := sk_ents()
	var L := -1.0
	for e in es:
		if e["k"] == "line":
			L = Part.v2(e["a"]).distance_to(Part.v2(e["b"]))
	ok(absf(L - 38.1) < 0.01, "B1 line typed 1.5in is 38.1 mm (%.3f)" % L)
	await key(KEY_ESCAPE)
	await press_tool(pu, "Rectangle")
	await click_at(sp("front", 20, 10))
	await ev_move(sp("front", 40, 25), false)
	await type_chars("2inx1in")
	await key(KEY_ENTER)
	await idle(2)
	var W := -1.0
	var H := -1.0
	for e in sk_ents():
		if e["k"] == "rect":
			W = absf(Part.v2(e["b"]).x - Part.v2(e["a"]).x)
			H = absf(Part.v2(e["b"]).y - Part.v2(e["a"]).y)
	ok(absf(W - 50.8) < 0.01 and absf(H - 25.4) < 0.01, "B2 rectangle 2inx1in is 50.8 x 25.4 (%.2f x %.2f)" % [W, H])
	# controls: plain 40x30 still 40 x 30 in mm; a planted wrong value fails the bar
	ok(absf(pu._typed_len("1.5in") - 38.1) < 0.01 and absf(pu._typed_len("40") - 40.0) < 1e-6 and pu._typed_len("x") < 0.0, "B3 control: bare number stays mm, junk refused")
	ok(absf(pu._typed_len("1.5in") - 1.5) > 1.0, "B3b control: the bar fails for the unit-blind value 1.5")
	await key(KEY_ESCAPE)
	var ub: Button = m.ui_root.find_child("part_unit", true, false)
	ok(ub != null, "B4 unit button still one row in the palette")
	await click_ctl(ub)
	await click_ctl(ub)
	ok(pu.unit() == "in", "B5 project unit is in")
	pu.open_dialog("Extrude", -1)
	await idle(3)
	ok(pu.f_num.text == "0.394" or pu.f_num.text.begins_with("0.39"), "B6 inch project extrude default reads in inches (%s)" % pu.f_num.text)
	await type_in(pu.f_num, "1in")
	var fd := pu.dialog_feature()
	ok(not fd.is_empty() and absf(float(fd.get("dist", 0)) - 25.4) < 0.01, "B7 typed 1in in the dialog is 25.4 mm")
	pu.open_dialog("Canvas", -1)
	await idle(2)
	await type_in(pu.f_num, "2in")
	ok(absf(pu._len(pu.f_num) - 50.8) < 0.01, "B8 canvas real-distance field takes 2in")
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		root.content_scale_size = sz
		root.size = sz
		await idle(4)
		await shot("w06b_%dx%d" % [sz.x, sz.y])
	print("W06b %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
