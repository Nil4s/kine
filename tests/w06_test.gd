extends SceneTree
## godot --path . --position 4000,4000 -s tests/w06_test.gd     (W06: typed exact sizes in EXPERT Part; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720, from the real start screen (3D BUILDING card), Part button on BUILD.

const SHOT := "C:/Users/Nick/tools/kine_workers/out/w06"
const DIRT := "user://w06_test"
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
	# ---- bars written first
	var P := LengthParse
	var r := P.parse_length("1.5in", "mm")
	ok(r["ok"] and absf(r["mm"] - 38.1) < 1e-6, "U1 '1.5in' -> 38.1 mm (%s)" % str(r))
	r = P.parse_length("4 cm", "mm")
	ok(r["ok"] and absf(r["mm"] - 40.0) < 1e-6, "U2 '4 cm' -> 40 mm")
	r = P.parse_length("4", "in")
	ok(r["ok"] and absf(r["mm"] - 101.6) < 1e-6, "U3 bare '4' in an inch project -> 101.6 mm")
	r = P.parse_length("4", "cm")
	ok(absf(r["mm"] - 40.0) < 1e-6, "U4 bare '4' in a cm project -> 40 mm")
	r = P.parse_length("1,5 IN", "mm")
	ok(r["ok"] and absf(r["mm"] - 38.1) < 1e-6, "U5 '1,5 IN' (comma, capitals) -> 38.1 mm")
	ok(not P.parse_length("abc", "mm")["ok"] and P.parse_length("abc", "mm")["error"] != "", "U6 'abc' is refused with words")
	ok(absf(P.parse_length("2m", "mm")["mm"] - 2000.0) < 1e-6 and absf(P.parse_length("40 mm", "in")["mm"] - 40.0) < 1e-6, "U7 m and an explicit mm beat the project unit")
	ok(P.label(38.1, "mm", true) == "38.1 mm (1.50 in)", "U8 dual label (%s)" % P.label(38.1, "mm", true))
	ok(P.label(38.1, "mm", false) == "38.1 mm", "U9 single label")
	ok(P.label(38.1, "in", true) == "1.5 in (38.1 mm)", "U10 inch project dual label (%s)" % P.label(38.1, "in", true))
	# control: the old behaviour (mm and cm only, no inches) would fail U1
	ok(absf(float("1.5in".replace("mm", "").trim_suffix("cm")) if "1.5in".replace("mm", "").trim_suffix("cm").is_valid_float() else -1.0) != 38.1, "U0 control: the old mm/cm-only reader cannot read 1.5in")
	var back := Part.from_file(JSON.parse_string(JSON.stringify(Part.to_file({"version": 1, "name": "x", "seq": 0, "features": [], "kept": true, "unit": "in", "dual": true}))))
	ok(back.get("unit", "") == "in" and back.get("dual", false) == true, "U11 unit and dual survive a save/load")

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
	var fld: LineEdit = m.ui_root.find_child("part_dim_0", true, false)
	ok(fld != null, "W1 the dimension field exists")
	var ub: Button = m.ui_root.find_child("part_unit", true, false)
	var dc: CheckBox = m.ui_root.find_child("part_dual", true, false)
	ok(ub != null and dc != null, "W2 unit button and Both units box exist")
	if fld == null or ub == null:
		print("W06 FAIL %d" % (fails + 1))
		quit(1)
		return
	await type_in(fld, "1.5in")
	ok(absf(float(sk_dims()[0]["mm"]) - 38.1) < 0.01, "W3 typing 1.5in in the field sets 38.1 mm (%.3f)" % float(sk_dims()[0]["mm"]))
	fld = m.ui_root.find_child("part_dim_0", true, false)
	await type_in(fld, "4 cm")
	ok(absf(float(sk_dims()[0]["mm"]) - 40.0) < 0.01, "W4 typing 4 cm sets 40 mm")
	await click_ctl(ub)
	await click_ctl(ub)
	ok(pu.unit() == "in" and ub.text == "in", "W5 two clicks on the unit button make the project unit in (%s)" % ub.text)
	fld = m.ui_root.find_child("part_dim_0", true, false)
	await type_in(fld, "4")
	ok(absf(float(sk_dims()[0]["mm"]) - 101.6) < 0.01, "W6 bare 4 in an inch project is 101.6 mm (%.3f)" % float(sk_dims()[0]["mm"]))
	fld = m.ui_root.find_child("part_dim_0", true, false)
	ok(fld.text.find("4") == 0 and fld.text.find("in") > 0, "W7 the field shows inches (%s)" % fld.text)
	await click_ctl(dc)
	fld = m.ui_root.find_child("part_dim_0", true, false)
	ok(fld.text == "4.0 in (101.6 mm)", "W8 dual on: field reads '4.0 in (101.6 mm)' (%s)" % fld.text)
	var fnt := fld.get_theme_font("font")
	var tw := fnt.get_string_size(fld.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fld.get_theme_font_size("font_size")).x
	ok(tw <= fld.size.x - 8.0, "W8b the dual text fits its field (text %.0f px, field %.0f px)" % [tw, fld.size.x])
	await click_ctl(ub)   # back to mm
	fld = m.ui_root.find_child("part_dim_0", true, false)
	ok(fld.text == "101.6 mm (4.00 in)", "W9 mm project dual: '101.6 mm (4.00 in)' (%s)" % fld.text)
	fld = m.ui_root.find_child("part_dim_0", true, false)
	await type_in(fld, "1.5in")   # the dual text itself must not be refused after typing over
	ok(absf(float(sk_dims()[0]["mm"]) - 38.1) < 0.01, "W10 1.5in again -> 38.1 mm")
	# an extrude/offset dialog field takes units too
	var rt := Part.from_file(Part.to_file(m.S.part))
	ok(rt.get("unit", "") == "mm" and rt.get("dual", false) == true, "W11 the part record carries unit and dual through save/load (%s, %s)" % [str(rt.get("unit")), str(rt.get("dual"))])
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		root.content_scale_size = sz
		root.size = sz
		await idle(4)
		await shot("w06_%dx%d" % [sz.x, sz.y])
	print("W06 %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
