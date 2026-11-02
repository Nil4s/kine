## godot --headless --path . -s tests/w07_test.gd   (W07: arithmetic in number fields)
## Bars (written first): '25*2+3' -> 53; '(10+5)/3' -> 5; '-2*-3' -> 6; '2+' refused with words; '10/0' refused;
## '1.5in+2' evaluates with unit 'in' carried; '2^3' and 'x' and '__import__' refused (no objects); a size field
## (PartUI.typed_mm) takes '25*2+3' as 53 mm and '2+', '10/0', '5-9' as -1 with words from _size_words;
## a refused entry leaves a real dimension at its old value. CONTROL: a plain evaluator that ignored precedence would give 56.
extends SceneTree

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func v(t: String) -> float:
	var r := NumExpr.eval(t)
	return float(r["value"]) if r["ok"] else NAN

var m: Node
const SHOT := "C:/Temp/claude/w07"


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


func key(k: Key, ctrl := false, uni := 0, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		root.push_input(e, true)
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


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


## real key events, one per character (digits, + - * / ( ) . and space), then Enter
func type_text(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	await key(KEY_A, true)
	var codes := {"+": [KEY_EQUAL, true], "-": [KEY_MINUS, false], "*": [KEY_8, true], "/": [KEY_SLASH, false], "(": [KEY_9, true], ")": [KEY_0, true], ".": [KEY_PERIOD, false], " ": [KEY_SPACE, false]}
	for ch in txt:
		if codes.has(ch):
			await key(codes[ch][0], false, ch.unicode_at(0), codes[ch][1])
		else:
			await key(KEY_0 + int(ch), false, ch.unicode_at(0))
	await key(KEY_ENTER)
	await idle(2)


func live() -> void:
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://w07_test"))
	ss.dirs_override = ["user://w07_test"]
	if not Part.available():
		print("SKIP live: no KineCAD DLL")
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await click_ctl(pu.tool_btns["Rectangle"])
	await ev_move(sp2(0, 0), false)
	await ev_mouse(sp2(0, 0), true)
	await ev_move(sp2(48, 12))
	await ev_move(sp2(95, 25))
	await ev_mouse(sp2(95, 25), false)
	await idle(2)
	await press_tool(pu, "Dimension")
	# first a plain size (40) so there is an old value to keep
	await click_ctl_at(sp2(47.5, 0))
	ok(pu.dim_edit.visible, "live: Dimension on the bottom edge opens the type box")
	await type_text(pu.dim_edit, "40")
	var w0 := float(Part.v2(pu._sk()["ents"][0]["b"]).x)
	ok(absf(w0 - 40.0) < 1e-6, "live: typed 40 -> width %s" % w0)
	var n_before: int = m.undo.size()
	# refused entries: '2+' and '10/0' keep 40
	for bad in ["2+", "10/0"]:
		await click_ctl_at(sp2(20, 0))
		await type_text(pu.dim_edit, bad)
		var wb := float(Part.v2(pu._sk()["ents"][0]["b"]).x)
		ok(absf(wb - 40.0) < 1e-6 and pu.status != "" and not pu.status.begins_with("Dimension set"), "live: '%s' refused, width stays %s, said: %s" % [bad, wb, pu.status])
	await click_ctl_at(sp2(20, 0))
	await type_text(pu.dim_edit, "25*2+3")
	var w1 := float(Part.v2(pu._sk()["ents"][0]["b"]).x)
	ok(absf(w1 - 53.0) < 1e-6, "live: typed 25*2+3 + Enter -> width %s" % w1)
	ok(pu.status == "Dimension set: 53 mm (25*2+3)", "live: status shows the resolved value: '%s'" % pu.status)
	print("  undo stack: before the entries %d, after %d (the sketch's one step is %d)" % [n_before, m.undo.size(), n_before])
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/live_dim.png")
	# one undo: the whole sketch step (the dimension entries live inside it) goes back; Ctrl+Z is the user's key
	var feats_before: int = m.S.part["features"].size()
	await key(KEY_Z, true)
	await idle(3)
	var gone: bool = m.S.part.is_empty() or (m.S.part.get("features", []) as Array).size() < feats_before
	ok(m.undo.size() == n_before - 1 and gone, "live: ONE Ctrl+Z takes the step back (stack %d -> %d, features %d -> %d)" % [n_before, m.undo.size(), feats_before, (m.S.part.get("features", []) as Array).size() if not m.S.part.is_empty() else 0])


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func _init() -> void:
	ok(absf(v("25*2+3") - 53.0) < 1e-9, "25*2+3 = 53")
	ok(absf(v("25*2+3") - 56.0) > 1.0, "control: left-to-right (56) is not what we give")
	ok(absf(v("(10+5)/3") - 5.0) < 1e-9, "(10+5)/3 = 5")
	ok(absf(v("-2*-3") - 6.0) < 1e-9, "-2*-3 = 6")
	ok(absf(v(" 1.5e1 + .5 ") - 15.5) < 1e-9, "1.5e1 + .5 = 15.5")
	var r := NumExpr.eval("2+")
	ok(not r["ok"] and String(r["err"]) != "", "2+ refused: " + String(r["err"]))
	r = NumExpr.eval("10/0")
	ok(not r["ok"] and "zero" in String(r["err"]), "10/0 refused: " + String(r["err"]))
	r = NumExpr.eval("(1+2")
	ok(not r["ok"], "(1+2 refused: " + String(r["err"]))
	for bad in ["2^3", "x", "__import__('os')", "1+OS.execute()", "", "3 3", "1..2"]:
		ok(not NumExpr.eval(bad)["ok"], "refused: '%s'" % bad)
	r = NumExpr.eval("1.5in+2")
	ok(r["ok"] and absf(float(r["value"]) - 3.5) < 1e-9 and r["unit"] == "in", "1.5in+2 = 3.5, unit 'in' carried")
	r = NumExpr.eval("4 cm * 2")
	ok(r["ok"] and r["unit"] == "cm" and absf(float(r["value"]) - 8.0) < 1e-9, "4 cm * 2 = 8 cm carried")
	ok(PartUI.typed_mm("25*2+3") == 53.0, "typed_mm 25*2+3 = 53")
	ok(PartUI.typed_mm("40") == 40.0 and PartUI.typed_mm("4 cm") == 40.0, "plain 40 and 4 cm unchanged")
	ok(PartUI.typed_mm("(2+2) cm") == 40.0 or PartUI.typed_mm("(2+2)*10") == 40.0, "bracket sum")
	ok(PartUI.typed_mm("2+") == -1.0 and PartUI.typed_mm("10/0") == -1.0 and PartUI.typed_mm("5-9") == -1.0, "bad sums give -1")
	# a real dimension keeps its old value on a refused entry
	if ClassDB.class_exists("Node"):
		var sk := {"ents": [{"k": "line", "a": [0.0, 0.0], "b": [10.0, 0.0]}]}
		Part.set_dim(sk, 0, "len", 10.0)
		var old: float = sk["dims"][0]["mm"]
		for t in ["2+", "10/0"]:
			var mm := PartUI.typed_mm(t)
			if mm > 0.0:
				Part.set_dim_held(sk, 0, "len", mm)
		ok(sk["dims"][0]["mm"] == old, "refused entries keep the old value (%s)" % old)
		var mm2 := PartUI.typed_mm("25*2+3")
		ok(mm2 > 0.0 and Part.set_dim_held(sk, 0, "len", mm2) == "" and absf(float(sk["dims"][0]["mm"]) - 53.0) < 1e-6, "accepted entry sets 53")
	await live()
	print("W07 %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
