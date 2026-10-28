extends SceneTree
## godot --path . --position 4000,4000 -s tests/xfix2_test.gd     (XFIX2: three beginner frictions in EXPERT Part; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720, from the real start screen (3D BUILDING card), Part button on BUILD.
## S SNAP: while a line / rectangle / circle is dragged, a pill next to the cursor reads the snapped size and says it is snapped
##    (cursor at 37 mm on a 5 mm snap: "35 mm, snapped to 5 mm"; a rectangle 42 x 31 reads "40 x 30 mm, snapped to 5 mm")
## R REFUSALS: a click on a greyed tool says why (Extrude: "sketch a closed profile first"; Finish: "no sketch is open"); a zero-height
##    rectangle says "Drag further"; a line back onto its own start says "different point"; a Fillet click on no edge says "No edge there"
## T STALE: after Ctrl+Z the "Undid" toast goes at the next action (a tool pick, or a click in the sketch)
const SHOT := "C:/Temp/claude/xfix2"
const DIRT := "user://xfix2_test"
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


## a PartUI field the readout keeps (absent on a build without it: the default)
func pv(pu: PartUI, nm: String, d: Variant) -> Variant:
	var v: Variant = pu.get(nm)
	return d if v == null else v


func toast_words() -> String:
	var t: Label = m.ui_toast
	return t.text if t != null and t.visible else ""


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
		print("SKIP: no KineCAD DLL; xfix2 needs it")
		quit(1)
		return
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
	ok(pu.on and pu.tool_btns.has("Circle"), "start: Part tools on (page %s)" % m.cur_page)

	# ---- R1 a click on a greyed button says why
	pu.status = ""
	await click_ctl(pu.tool_btns["Extrude"])
	ok(pu.status.find("sketch a closed profile first") >= 0, "R1 Extrude with no sketch: the click says why (status: %s)" % pu.status)
	pu.status = ""
	await click_ctl(pu.finish_btn)
	ok(pu.status.find("no sketch is open") >= 0, "R1 Finish sketch with no sketch open: the click says why (status: %s)" % pu.status)

	# ---- S1 SNAP: a line dragged to 37 mm on a 5 mm snap reads the snapped length next to the cursor
	await press_tool(pu, "Line")
	await click_at(sp("front", 0, 0))
	var cur1 := sp("front", 37, 0)
	await ev_move(cur1, false)
	await idle(2)
	var pt1 := String(pv(pu, "pill_text", ""))
	var pa1: Vector2 = pv(pu, "pill_at", Vector2(-99999, -99999))
	ok(pt1.find("35") >= 0 and pt1.find("snapped") >= 0, "S1 line to 37 mm on a 5 mm snap reads the snapped length and says so (readout: %s)" % pt1)
	ok(pa1.distance_to(cur1) < 80.0, "S1 the readout sits next to the cursor (%d px away)" % int(pa1.distance_to(cur1)))
	await shot("xfix2_1_line_readout")
	await key(KEY_ESCAPE)

	# ---- S2 SNAP: a rectangle dragged to 42 x 31 reads 40 x 30 mm, snapped
	await press_tool(pu, "Rectangle")
	await ev_move(sp("front", 0, 0), false)
	await ev_mouse(sp("front", 0, 0), true)
	await ev_move(sp("front", 42, 31))
	await idle(2)
	var pt2 := String(pv(pu, "pill_text", ""))
	var pa2: Vector2 = pv(pu, "pill_at", Vector2(-99999, -99999))
	ok(pt2.find("40") >= 0 and pt2.find("snapped") >= 0, "S2 rectangle dragged to 42 x 31 reads 40 x 30 mm, snapped (readout: %s)" % pt2)
	ok(pa2.distance_to(sp("front", 42, 31)) < 80.0, "S2 the rectangle readout sits next to the cursor (%d px away)" % int(pa2.distance_to(sp("front", 42, 31))))
	await ev_mouse(sp("front", 42, 31), false)
	await idle(2)
	ok(sk_ents().size() == 1, "S2 the rectangle is made (%d shape)" % sk_ents().size())

	# ---- S3 SNAP: a circle dragged to 7 mm from its centre reads R 5 mm, snapped
	await press_tool(pu, "Circle")
	await ev_move(sp("front", 60, 15), false)
	await ev_mouse(sp("front", 60, 15), true)
	await ev_move(sp("front", 67, 15))
	await idle(2)
	var pt3 := String(pv(pu, "pill_text", ""))
	ok(pt3.find("R 5") >= 0 and pt3.find("snapped") >= 0, "S3 circle dragged to 7 mm reads R 5 mm, snapped (readout: %s)" % pt3)
	await ev_mouse(sp("front", 67, 15), false)
	await idle(2)
	ok(sk_ents().size() == 2, "S3 the circle is made (%d shapes)" % sk_ents().size())
	await shot("xfix2_3_snap_readouts")

	# ---- R2 a rectangle with no height says why
	await press_tool(pu, "Rectangle")
	var n_sk := sk_ents().size()
	await drag_at(sp("front", 0, 45), sp("front", 40, 45))
	ok(sk_ents().size() == n_sk and pu.status.find("Drag further") >= 0, "R2 a rectangle with no height adds nothing and says Drag further (status: %s)" % pu.status)

	# ---- R3 a line back onto its own start says why
	await press_tool(pu, "Line")
	await click_at(sp("front", 0, 50))
	await click_at(sp("front", 0, 50))
	ok(pu.status.find("different point") >= 0, "R3 a line clicked back on its own start says why (status: %s)" % pu.status)
	await key(KEY_ESCAPE)

	# ---- body: the rectangle and the circle extruded 20
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "20")
	ok(vol() > 0.0 and int(pu.res.get("bodies", 0)) >= 1, "body: the sketch extruded 20 (volume %s m3)" % f4(vol()))

	# ---- R4 a Fillet click on no edge says why
	await press_tool(pu, "Fillet")
	await click_at(sp("front", 20, 15))
	ok(pu.status.find("No edge there") >= 0, "R4 a Fillet click on the middle of a face says why (status: %s)" % pu.status)
	await key(KEY_ESCAPE)

	# ---- T STALE: the Undid toast goes at the next action
	# the Extrude number box still holds the keyboard after Enter: Ctrl+Z would edit its text, so focus is let go first
	pu.f_num.release_focus()
	await idle(2)
	await key(KEY_Z, true)
	await idle(2)
	var t0 := toast_words()
	note("T0 after Ctrl+Z: status %s, undo steps left %d" % [pu.status, m.undo.size()])
	ok(t0.find("Undid") >= 0 or t0.find("Took back") >= 0, "T Ctrl+Z says what it took back (toast: %s)" % t0)
	await press_tool(pu, "Line")
	var t1 := toast_words()
	ok(t1.find("Undid") < 0 and t1.find("Took back") < 0, "T a tool pick takes the Undid toast down (toast now: '%s')" % t1)
	await key(KEY_Z, true)
	await idle(2)
	var t2 := toast_words()
	ok(t2.find("Undid") >= 0 or t2.find("Took back") >= 0, "T Ctrl+Z again says what it took back (toast: %s)" % t2)
	await click_at(sp("front", 0, 0))
	var t3 := toast_words()
	ok(t3.find("Undid") < 0 and t3.find("Took back") < 0, "T a click in the sketch takes the Undid toast down (toast now: '%s')" % t3)

	print("XFIX2 NOTES:")
	for l in log_lines:
		print("  " + l)
	print("XFIX2 %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
