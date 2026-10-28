extends SceneTree
## godot --path . --position 4000,4000 -s tests/xwalk2_test.gd     (XWALK2: a beginner walk of EXPERT Part: a phone stand, a gear blank, a hinge leaf; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720 from the real start screen (3D BUILDING card), Part button on BUILD.
## Each thing gets its own start: the start screen, BUILDING card, Part. Dead ends are KNOWN bars: they pin the words and the state the walk met.
const SHOT := "C:/Temp/claude/xwalk2"
const DIRT := "user://xwalk2_test"
const MM := 0.001
const PI := 3.14159265358979
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


## back to the start screen and into a fresh Part (the real BUILDING card, the real Part button)
func fresh_part(pu: PartUI) -> void:
	if pu.on:
		await click_ctl(pu.part_btn)
		await idle(2)
	m.start_screen.show_screen()
	await idle(3)
	await click_ctl(m.start_screen._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(pu.part_btn)
	await idle(3)


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	m.start_screen.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL; xwalk2 needs it")
		quit(1)
		return
	m.start_screen.show_screen()
	await idle(3)

	# ================= THING 1: PHONE STAND (block, angled slot, fillet)
	await fresh_part(pu)
	ok(pu.on and pu.tool_btns.has("Rectangle"), "stand: Part tools on from the start screen")
	await press_tool(pu, "Rectangle")
	await drag_at(sp("front", 0, 0), sp("front", 80, 60))
	ok(sk_ents().size() == 1, "stand: a rectangle 80 x 60 on Front")
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "30")
	ok(absf(vol() - 144000.0 * MM * MM * MM) < 1e-10, "stand: block 80 x 60 x 30 (volume %s m3)" % str(vol()))
	await press_tool(pu, "Fillet")
	await click_at(sp("front", 40, 60))
	ok(pu.picked.size() == 1, "stand: the front top edge picks (%d picked)" % pu.picked.size())
	await type_in(pu.f_num, "5")
	var v_f := vol()
	ok(v_f < 144000.0 * MM * MM * MM and v_f > 140000.0 * MM * MM * MM, "stand: fillet 5 takes a little off the top edge (volume %s m3)" % str(v_f))
	await shot("phone_stand_fillet")
	await press_tool(pu, "Line")
	await click_at(sp("front", 20, 60))
	await click_at(sp("front", 30, 60))
	await click_at(sp("front", 52, 20))
	await click_at(sp("front", 42, 20))
	await click_at(sp("front", 20, 60))
	await key(KEY_ESCAPE)
	ok(sk_ents().size() == 4, "stand: the angled slot is 4 lines (%d)" % sk_ents().size())
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	var dop_s: String = pu.f_op.get_item_text(pu.f_op.selected)
	var words_s := dlg_words(pu)
	note("stand slot: a new Extrude opens on %s, words:%s" % [dop_s, words_s])
	ok(dop_s == "Join" and words_s.find("Cut needs") >= 0, "KNOWN stand: the slot cut from the top edge opens on Join, words say Cut needs the shape inside a face (%s)" % dop_s)
	await shot("phone_stand_slot_dialog")
	pu.f_op.select(2)
	pu.f_op.item_selected.emit(2)
	var v_pre := vol()
	await type_in(pu.f_num, "40")
	var rm_s := (v_pre - vol()) / (MM * MM * MM)
	ok(rm_s > 11500.0 and rm_s < 12000.5, "stand: Cut 40 through the angled slot takes about 400 x 30 mm3 (removed %.1f mm3; the fillet trims the top corner)" % rm_s)
	await shot("phone_stand")
	ok(vol() > 0.0, "stand: a body is left")

	# ================= THING 2: GEAR BLANK (disc, six pins round the axis, combine them away, hub)
	await fresh_part(pu)
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 0, 0), sp("front", 25, 0))
	ok(sk_ents().size() == 1, "gear: a circle r 25 at the origin")
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "10")
	ok(absf(vol() - PI * 625.0 * 10.0 * MM * MM * MM) < 1e-9, "gear: disc r 25 x 10 (volume %s m3)" % str(vol()))
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 15, 0), sp("front", 19, 0))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "10")
	await press_tool(pu, "Pattern")
	ok(pat_ok(pu), "gear: Pattern dialog opens")
	note("gear pattern words: " + dlg_words(pu))
	pat_set(pu, 1, "6", "360", "z", 1)
	await click_ctl(pu.ok_btn)
	await shot("gear_pattern")
	ok(int(pu.res.get("bodies", 0)) >= 6, "gear: circular pattern of the pin, 6 bodies round Z (bodies %s)" % str(pu.res.get("bodies", 0)))
	var v_g := vol()
	ok(absf(v_g - 113100.0 * MM * MM * MM) < 1e-7, "KNOWN gear: after the circular pattern the volume reads %.1f cm3 (six 0.5 cm3 pins on a 19.6 cm3 disc would read about 22.6)" % (v_g * 1e6))
	await press_tool(pu, "Combine")
	var words_c := dlg_words(pu)
	note("gear combine words at open: " + words_c)
	ok(words_c.find("Tools") >= 0, "gear: Combine opens with Tools and Target rows")
	await click_at(sp("front", 0, -12))
	note("gear combine after target click: " + dlg_words(pu))
	for k in 6:
		await click_at(sp("front", 15.0 * cos(k * PI / 3.0), 15.0 * sin(k * PI / 3.0)))
	note("gear combine after 6 tool clicks: " + dlg_words(pu))
	await shot("gear_combine")
	var tools_n: int = (pu.cmb.get("tools", []) as Array).size()
	ok(int(pu.cmb.get("target", -1)) == 3 and tools_n == 2, "KNOWN gear: 6 pin clicks set 2 tools and the target moved to Body4 (target %s, tools %d of 6 want 1 target Body1 and 6 tools)" % [str(pu.cmb.get("target", -1)), tools_n])
	await key(KEY_ESCAPE)
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 0, 0), sp("front", 8, 0))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "15")
	await shot("gear_blank")
	note("gear done status: " + pu.status + " | volume %s" % str(vol()))

	# ================= THING 3: HINGE LEAF (plate, three holes in a row, chamfer)
	await fresh_part(pu)
	await press_tool(pu, "Rectangle")
	await drag_at(sp("front", 0, 0), sp("front", 60, 20))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "3")
	ok(absf(vol() - 3600.0 * MM * MM * MM) < 1e-12, "leaf: plate 60 x 20 x 3 (volume %s m3)" % str(vol()))
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 10, 10), sp("front", 12, 10))
	note("leaf r2 drag: draft empty %s, status: %s, circles %d" % [str(pu.draft.is_empty()), pu.status, sk_ents().size()])
	ok(sk_ents().size() == 0 and pu.status.find("Drag further") >= 0, "KNOWN leaf: a 2 mm radius hole drag is snapped away (Drag further to set the size)")
	await drag_at(sp("front", 10, 10), sp("front", 15, 10))
	await drag_at(sp("front", 30, 10), sp("front", 35, 10))
	await drag_at(sp("front", 50, 10), sp("front", 55, 10))
	ok(sk_ents().size() == 3, "leaf: three holes r 5 in one sketch (%d)" % sk_ents().size())
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	pu.f_op.select(2)
	pu.f_op.item_selected.emit(2)
	var v_l := vol()
	await type_in(pu.f_num, "3")
	ok(absf((v_l - vol()) - 3.0 * PI * 25.0 * 3.0 * MM * MM * MM) < 1e-10, "leaf: three holes r 5 cut 3 deep (removed %s m3)" % str(v_l - vol()))
	await press_tool(pu, "Chamfer")
	await click_at(sp("front", 30, 20))
	ok(pu.picked.size() == 1, "leaf: the top front edge picks for the chamfer (%d)" % pu.picked.size())
	var v_c := vol()
	await type_in(pu.f_num, "1")
	var dc := v_c - vol()
	ok(dc > 2e-8 and dc < 4e-8, "leaf: chamfer 1 takes a thin strip off the edge (removed %s m3)" % str(dc))
	await shot("hinge_leaf")
	note("leaf done: volume %s, status %s" % [str(vol()), pu.status])

	print("XWALK2 NOTES:")
	for l in log_lines:
		print("  " + l)
	print("XWALK2 %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)


func pat_ok(pu: PartUI) -> bool:
	return not pu.pat.is_empty()


func pat_set(pu: PartUI, kind: int, count: String, deg: String, axis: String, op: int) -> void:
	(pu.pat["kind"] as OptionButton).select(kind)
	(pu.pat["count"] as LineEdit).text = count
	(pu.pat["deg"] as LineEdit).text = deg
	var ai := ["x", "y", "z"].find(axis)
	(pu.pat["axis"] as OptionButton).select(maxi(ai, 0))
	(pu.pat["op"] as OptionButton).select(op)
