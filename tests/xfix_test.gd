extends SceneTree
## godot --path . --position 4000,4000 -s tests/xfix_test.gd     (XFIX: three beginner frictions in EXPERT Part; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720, from the real start screen (3D BUILDING card), Part button on BUILD.
## F1 GHOST: a Circle drag shorter than the 5 mm snap draws nothing, says "Drag further to set the size", leaves no half circle (a click after it adds nothing)
## F2 OPEN ON CUT: a sketch on a body face with its shape inside that face opens a new Extrude on Cut; its words say why (a rectangle 40 x 30
##    extruded 20, then a circle r 5 inside its front face: Cut 20 removes pi 5^2 20 mm3)
## F3 TWO LOOPS: two separate closed circles in one sketch extrude / cut as two profiles at once, one undo step, no jargon in the words
##    (two circles r 5 cut 20: 2 pi 5^2 20 mm3 off the body)
const SHOT := "C:/Temp/claude/xfix"
const DIRT := "user://xfix_test"
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


## a real drag from screen point a to b, in steps
func drag_at(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	await ev_move(a.lerp(b, 0.5))
	await ev_move(b)
	await ev_mouse(b, false)
	await idle(2)


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	await key(KEY_A, true)
	for ch in txt:
		await key(KEY_0 + int(ch) if ch != "." else KEY_PERIOD, false, ch.unicode_at(0))
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


func f4(v: float) -> String:
	return String.num_scientific(v)


func vol() -> float:
	return float(Part.replay(m.S.part)["volume"]) if not m.S.part.is_empty() else 0.0


func sk_ents() -> Array:
	return m.bld.part._sk()["ents"] if m.bld.part.sk != "" else []


## every label's text under the dialog rows (the words the user reads)
func dlg_words(pu: PartUI) -> String:
	var out := ""
	var stack: Array = pu.dlg_rows.get_children()
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Label:
			out += " | " + (c as Label).text
		stack.append_array(c.get_children())
	return out


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
		print("SKIP: no KineCAD DLL; xfix needs it")
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
	ok(pu.on and pu.tool_btns.has("Circle"), "start: Part tools on (page %s)" % m.cur_page)

	# ---- F1 GHOST: a short Circle drag cancels in words, no half circle
	await press_tool(pu, "Circle")
	var st0: String = pu.status
	await drag_at(sp("front", 20, 20), sp("front", 21, 20))
	var n_short := sk_ents().size()
	ok(pu.draft.is_empty() and n_short == 0, "F1 a Circle drag under the 5 mm snap leaves no half circle (draft empty=%s, %d circles)" % [str(pu.draft.is_empty()), n_short])
	ok(pu.status.find("Drag further to set the size") >= 0, "F1 the words say Drag further to set the size (status: %s)" % pu.status)
	note("F1 status after the short drag: %s (was %s)" % [pu.status, st0])
	await click_at(sp("front", 40, 25))
	ok(sk_ents().size() == 0, "F1 a click after the short drag completes nothing (%d circles, want 0)" % sk_ents().size())
	await shot("xfix_1_ghost")
	await key(KEY_ESCAPE)

	# ---- F2 OPEN ON CUT: a rectangle body, then a circle inside its front face
	await press_tool(pu, "Rectangle")
	await drag_at(sp("front", 0, 0), sp("front", 40, 30))
	ok(sk_ents().size() == 1, "F2 a rectangle 40 x 30 on Front (%d shape)" % sk_ents().size())
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "20")
	ok(absf(vol() - 24000.0 * MM * MM * MM) < 1e-10 and int(pu.res.get("bodies", 0)) == 1, "F2 body: 40 x 30 x 20 (volume %s m3)" % f4(vol()))
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 20, 15), sp("front", 25, 15))
	ok(sk_ents().size() == 1, "F2 a circle r 5 at (20, 15) in the sketch on Front")
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	var dop: String = pu.f_op.get_item_text(pu.f_op.selected)
	var words := dlg_words(pu)
	ok(dop == "Cut", "F2 a new Extrude on the face opens on Cut (operation shows %s)" % dop)
	ok(words.find("face") >= 0 and words.find("inside") >= 0, "F2 the words say why (%s)" % words)
	note("F2 dialog words: " + words)
	var v_before := vol()
	await type_in(pu.f_num, "20")
	var want_f2 := v_before - PI * 25.0 * 20.0 * MM * MM * MM
	ok(absf(vol() - want_f2) < 5e-10, "F2 Enter cuts the hole: volume %s m3 (want %s)" % [f4(vol()), f4(want_f2)])
	await shot("xfix_2_cut")

	# ---- F2 the other side: a circle off the body's face opens on Join, and says why
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 60, 15), sp("front", 65, 15))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	var dop_out: String = pu.f_op.get_item_text(pu.f_op.selected)
	var words_out := dlg_words(pu)
	ok(dop_out == "Join" and words_out.find("Join") >= 0, "F2 a circle off the body's face opens on Join, with the words (operation %s)" % dop_out)
	note("F2 off-face dialog words: " + words_out)

	# ---- F3 TWO LOOPS: two separate circles in one sketch cut as two profiles at once
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 10, 25), sp("front", 15, 25))
	await drag_at(sp("front", 30, 10), sp("front", 35, 10))
	ok(sk_ents().size() == 2, "F3 two separate circles in one sketch (%d)" % sk_ents().size())
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	pu.f_op.select(2)
	pu.f_op.item_selected.emit(2)
	await idle(2)
	var n3: int = m.undo.size()
	var v3 := vol()
	await type_in(pu.f_num, "20")
	var want_f3 := v3 - 2.0 * PI * 25.0 * 20.0 * MM * MM * MM
	ok(absf(vol() - want_f3) < 5e-10 and m.undo.size() == n3 + 1, "F3 two loops cut 20 at once: volume %s m3 (want %s), one undo step" % [f4(vol()), f4(want_f3)])
	var words3 := pu.dlg_info.text
	ok(words3.find("connected") < 0 and words3.find("join") < 0, "F3 no jargon in the words (%s)" % words3)
	await shot("xfix_3_two_loops")

	print("XFIX NOTES:")
	for l in log_lines:
		print("  " + l)
	print("XFIX %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
