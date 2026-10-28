extends SceneTree
## godot --path . --position 4000,4000 -s tests/xtime_test.gd     (XTIME: EXPERT Part timeline edits; needs a window and the CAD DLL)
## Real clicks and keys (root.push_input) at 1280 x 720, from the real start screen (3D BUILDING card), Part button on BUILD.
## Build: S1 Rectangle 40 x 30 on Front, Extrude 10 (Join); S2 Circle r 5 at (60, 15) on Front, Extrude 10 (Join: a boss off the body);
##        S3 Circle r 5 at (20, 15) on Front, Extrude 5 (Cut). Six steps: Sketch1 Extrude1 Sketch2 Extrude2 Sketch3 Extrude3.
##   1 BUILD    six steps, two bodies, volume 12000 + 785.398 - 392.699 mm3, no failed step
##   2 EDIT     double-click Extrude1, depth 10 -> 20: still six steps, the boss and the hole replay: volume +12000 mm3, no failed step, one undo step
##   3 SUPPRESS click Extrude3 (the hole), Suppress: the hole is skipped (volume without the 392.699 mm3 hole), the step says it is suppressed; Undo brings it back
##   4 DELETE   click Sketch2 (a step in the middle), Delete step: five steps; Extrude2 (the boss) says in plain words that Sketch2 was deleted
##              (not "its sketch is gone"); the hole still replays; one undo step
##   5 UNDO     Undo of the delete: six steps again, the volume of bar 2 again
## Only user:// is written (and the screenshots in C:/Temp/claude/xtime).
const SHOT := "C:/Temp/claude/xtime"
const DIRT := "user://xtime_test"
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




func feats() -> Array:
	return m.S.part.get("features", []) if not m.S.part.is_empty() else []


## index of the step with this name ("Extrude1"), -1 when there is none
func idx_of(nm: String) -> int:
	for i in feats().size():
		if String(feats()[i]["name"]) == nm:
			return i
	return -1


func set_op(pu: PartUI, op: String) -> void:
	for i in pu.f_op.item_count:
		if pu.f_op.get_item_text(i) == op:
			pu.f_op.select(i)
			pu.f_op.item_selected.emit(i)
			await idle(2)
			return
	ok(false, "the operation %s is in the list" % op)


func dbl_step(pu: PartUI, i: int) -> void:
	await click_ctl(pu.tl_btns[i])
	await click_ctl(pu.tl_btns[i])   # the first press rebuilds the row: the second press takes the new button


func step_btn(pu: PartUI, i: int) -> Button:
	return pu.tl_btns[i] if i < pu.tl_btns.size() else null


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
		print("SKIP: no KineCAD DLL; xtime needs it")
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

	# ---- build: S1 rectangle, E1 extrude 10; S2 boss circle, E2 Join 10; S3 hole circle, E3 Cut 5
	await press_tool(pu, "Rectangle")
	await drag_at(sp("front", 0, 0), sp("front", 40, 30))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "10")
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 60, 15), sp("front", 65, 15))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "10")
	await press_tool(pu, "Circle")
	await drag_at(sp("front", 20, 15), sp("front", 25, 15))
	await click_ctl(pu.finish_btn)
	await press_tool(pu, "Extrude")
	await set_op(pu, "Cut")
	await type_in(pu.f_num, "5")
	await idle(3)
	var v0 := 12000.0 + 785.398 - 392.699
	var names := []
	for f in feats():
		names.append(String(f["name"]))
	note("steps: %s" % str(names))
	ok(feats().size() == 6, "1 BUILD six steps (%d)" % feats().size())
	ok(absf(vol() - v0 * MM * MM * MM) < 1e-10, "1 BUILD volume %s m3 (want %s)" % [f4(vol()), f4(v0 * MM * MM * MM)])
	ok((pu.res.get("errors", {}) as Dictionary).is_empty(), "1 BUILD no failed step")
	await shot("xtime_1_build")

	# ---- 2 EDIT: double-click Extrude1 (depth 10), type 20
	var e1 := idx_of("Extrude1")
	var n2: int = m.undo.size()
	await dbl_step(pu, e1)
	ok(pu.dlg.get("edit", -1) == e1, "2 EDIT double-click on Extrude1 opens its dialog (step %d)" % e1)
	await type_in(pu.f_num, "20")
	var v1 := v0 + 12000.0
	ok(feats().size() == 6, "2 EDIT still six steps (%d)" % feats().size())
	ok(absf(vol() - v1 * MM * MM * MM) < 1e-10, "2 EDIT depth 20: the boss and the hole replay, volume %s m3 (want %s)" % [f4(vol()), f4(v1 * MM * MM * MM)])
	ok((pu.res.get("errors", {}) as Dictionary).is_empty(), "2 EDIT no failed step")
	ok(m.undo.size() == n2 + 1, "2 EDIT one undo step (%d -> %d)" % [n2, m.undo.size()])
	await shot("xtime_2_edit")

	# ---- 3 SUPPRESS the hole (Extrude3)
	var e3 := idx_of("Extrude3")
	await click_ctl(step_btn(pu, e3))
	var sup := m.find_child("part_suppress", true, false) as Button
	ok(sup != null, "3 SUPPRESS a Suppress button sits on the timeline")
	if sup != null:
		var n3: int = m.undo.size()
		await click_ctl(sup)
		var v2 := v1 + 392.699
		ok(bool(feats()[e3].get("off", false)), "3 SUPPRESS the step is marked off in the record")
		ok(absf(vol() - v2 * MM * MM * MM) < 1e-10, "3 SUPPRESS the hole is skipped: volume %s m3 (want %s)" % [f4(vol()), f4(v2 * MM * MM * MM)])
		ok((pu.res.get("errors", {}) as Dictionary).is_empty(), "3 SUPPRESS no failed step (a suppressed step is not a failure)")
		ok(step_btn(pu, e3).tooltip_text.findn("suppress") >= 0, "3 SUPPRESS the step says suppressed (%s)" % step_btn(pu, e3).tooltip_text)
		ok(m.undo.size() == n3 + 1, "3 SUPPRESS one undo step")
		await shot("xtime_3_suppress")
		await key(KEY_Z, true)
		await idle(2)
		ok(not bool(feats()[e3].get("off", false)) and absf(vol() - v1 * MM * MM * MM) < 1e-10, "3 UNDO brings the hole back (volume %s m3)" % f4(vol()))

	# ---- 4 DELETE the boss sketch (Sketch2, a step in the middle)
	var s2 := idx_of("Sketch2")
	await click_ctl(step_btn(pu, s2))
	var del := m.find_child("part_delete_step", true, false) as Button
	ok(del != null, "4 DELETE a Delete step button sits on the timeline")
	if del != null:
		var n4: int = m.undo.size()
		await click_ctl(del)
		ok(feats().size() == 5, "4 DELETE five steps left (%d)" % feats().size())
		var ext2 := idx_of("Extrude2")
		var err2 := String((pu.res.get("errors", {}) as Dictionary).get(String(feats()[ext2]["id"]) if ext2 >= 0 else "", ""))
		note("4 DELETE the boss step says: " + err2)
		ok(err2.find("Sketch2") >= 0 and err2.find("deleted") >= 0, "4 DELETE Extrude2 says in plain words that Sketch2 was deleted (%s)" % err2)
		var v3 := v1 - 785.398   # the boss goes (+785.398); the hole stays (-392.699)
		ok(absf(vol() - v3 * MM * MM * MM) < 1e-10, "4 DELETE the boss is gone, the hole replays: volume %s m3 (want %s)" % [f4(vol()), f4(v3 * MM * MM * MM)])
		ok(m.undo.size() == n4 + 1, "4 DELETE one undo step")
		await shot("xtime_4_delete")
		# ---- 5 UNDO
		await key(KEY_Z, true)
		await idle(2)
		ok(feats().size() == 6 and absf(vol() - v1 * MM * MM * MM) < 1e-10, "5 UNDO six steps, volume %s m3 (want %s)" % [f4(vol()), f4(v1 * MM * MM * MM)])

	print("XTIME NOTES:")
	for l in log_lines:
		print("  " + l)
	print("XTIME %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
