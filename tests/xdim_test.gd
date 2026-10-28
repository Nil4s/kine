extends SceneTree
## godot --path . --position 4000,4000 -s tests/xdim_test.gd     (XDIM: typed exact sizes in EXPERT Part; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720, from the real start screen (3D BUILDING card), Part button on BUILD.
## D1 RECT: a rectangle corner, then "40x30" + Enter makes a 40 x 30 mm rectangle; the pill shows the typed size while it is typed
## D2 CIRCLE: a circle centre, then "12" + Enter makes a circle of radius 12 mm
## D3 LINE: a length typed before the line has a start says so (no silent nothing); "0" for a length says why
## D4 DIM FIELD: a sketch size typed as "abc" says what to type; "0" says a size must be above 0; "4 cm" sets 40 mm
const SHOT := "C:/Temp/claude/xdim"
const DIRT := "user://xdim_test"
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
		print("SKIP: no KineCAD DLL; xdim needs it")
		quit(1)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on and pu.tool_btns.has("Rectangle"), "start: Part tools on (page %s)" % m.cur_page)

	# ---- D1 a typed rectangle size: 40 x 30 from the corner
	await press_tool(pu, "Rectangle")
	await click_at(sp("front", 0, 0))
	await ev_move(sp("front", 30, 20), false)
	await type_chars("40x30")
	var pt1 := String(pv(pu, "pill_text", ""))
	ok(pt1.find("40") >= 0 and pt1.find("30") >= 0, "D1 the typed rectangle size shows while typed (readout: %s)" % pt1)
	await key(KEY_ENTER)
	await idle(2)
	var r1 := {}
	for e in sk_ents():
		if String(e["k"]) == "rect":
			r1 = e
	ok(not r1.is_empty(), "D1 Enter makes the typed rectangle (%d shapes)" % sk_ents().size())
	if not r1.is_empty():
		var w1 := absf(Part.v2(r1["b"]).x - Part.v2(r1["a"]).x)
		var h1 := absf(Part.v2(r1["b"]).y - Part.v2(r1["a"]).y)
		ok(absf(w1 - 40.0) < 0.01 and absf(h1 - 30.0) < 0.01, "D1 the rectangle is exactly 40 x 30 mm (%.3f x %.3f)" % [w1, h1])
	await shot("xdim_1_rect_typed")
	await key(KEY_ESCAPE)

	# ---- D2 a typed circle radius: 12 mm from the centre
	await press_tool(pu, "Circle")
	await ev_move(sp("front", 60, 15), false)
	await ev_mouse(sp("front", 60, 15), true)
	await idle(2)
	await type_chars("12")   # while the mouse is held on the centre
	await key(KEY_ENTER)
	await ev_mouse(sp("front", 60, 15), false)
	await idle(2)
	var c2 := {}
	for e in sk_ents():
		if String(e["k"]) == "circle":
			c2 = e
	ok(not c2.is_empty(), "D2 Enter makes the typed circle (%d shapes)" % sk_ents().size())
	if not c2.is_empty():
		var r2 := float(c2["r"])
		ok(absf(r2 - 12.0) < 0.01, "D2 the circle radius is exactly 12 mm (%.3f)" % r2)

	# ---- D3 a length typed before a start says so; "0" says why
	await press_tool(pu, "Line")
	var n3 := sk_ents().size()
	pu.status = ""
	await type_chars("25")
	await key(KEY_ENTER)
	ok(sk_ents().size() == n3 and pu.status.find("start") >= 0, "D3 a length typed before the start says to click the start (status: %s)" % pu.status)
	note("D3 before: sk %s plane n %s cam %s pt %s" % [pu.sk, str(pu._plane()["n"]), str(m.cam.global_position), str(sp("front", 80, 35))])
	await click_at(sp("front", 80, 35))
	note("D3 after the start click: draft %s, status %s" % [str(pu.draft), pu.status])
	pu.status = ""
	await type_chars("0")
	await key(KEY_ENTER)
	ok(sk_ents().size() == n3 and pu.status.find("above 0") >= 0, "D3 a length of 0 says it must be above 0 (status: %s)" % pu.status)
	await key(KEY_ESCAPE)

	# ---- D4 the sketch size field: a line with a dimension, then typed values
	await press_tool(pu, "Line")
	await click_at(sp("front", 60, 42))
	await click_at(sp("front", 90, 42))
	await key(KEY_ESCAPE)
	await press_tool(pu, "Dimension")
	await click_at(sp("front", 75, 42))
	await idle(2)
	await type_chars("40")
	await key(KEY_ENTER)
	await idle(2)
	note("D4 after the dimension: %d lines, %d dims, status %s" % [sk_ents().size(), sk_dims().size(), pu.status])
	var fld: LineEdit = m.ui_root.find_child("part_dim_0", true, false)
	ok(fld != null, "D4 the sketch lists the dimension as a field")
	if fld == null:   # no field: the three size bars below fail too (they cannot run)
		ok(false, "D4 a size typed as abc says what to type (no field)")
		ok(false, "D4 a size of 0 says it must be above 0 (no field)")
		ok(false, "D4 4 cm sets the size to 40 mm (no field)")
	else:
		pu.status = ""
		await type_in(fld, "abc")
		ok(pu.status.find("type a size") >= 0, "D4 a size typed as abc says what to type (status: %s)" % pu.status)
		pu.status = ""
		await type_in(fld, "0")
		ok(pu.status.find("above 0") >= 0, "D4 a size of 0 says it must be above 0 (status: %s)" % pu.status)
		await type_in(fld, "4 cm")
		var d4 := -1.0
		for d in sk_dims():
			d4 = float(d["mm"])
		ok(absf(d4 - 40.0) < 0.01, "D4 4 cm sets the size to 40 mm (now %.3f)" % d4)
	await shot("xdim_4_dim_field")

	print("XDIM NOTES:")
	for l in log_lines:
		print("  " + l)
	print("XDIM %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
