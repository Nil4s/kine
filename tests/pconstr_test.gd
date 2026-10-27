extends SceneTree
## godot --headless --path . -s tests/pconstr_test.gd     (GAP 9 CONSTRAINTS: sketch Horizontal, Vertical, Coincident, Parallel, Perpendicular, Equal and an Angle, from the SKETCH Constrain row by real clicks; needs the CAD DLL)
## Bars, written before measuring (lengths mm, angles deg):
##   1 RECT     four Lines (0,0) (100,0) (100,60) (0,60) by clicks; 4 Coincident corners, Horizontal on the bottom and top, Vertical on the sides,
##              Perpendicular bottom / right: 9 rules, ONE undo step each (the undo count rises by 9); all rules hold
##   2 DRAG     the top-right corner dragged to (120, 75) (no tool picked): the rectangle stays a rectangle: every corner angle 90 within 0.01 deg,
##              the top is level, the right side upright, the corners meet (the dragged corner is at (120, 75))
##   3 ANGLE    line A (150,0)-(200,0) and line B (150,20)-(180,40); Angle 30 typed: the angle is 30 within 0.01 deg; dragging the far end of B to
##              (200, 60) keeps 30 within 0.01 deg
##   4 EQUAL    line C 30 mm and line D 40 mm: Equal (C, D): |D| = |C| = 30 within 0.01 mm
##   5 REFUSE   Perpendicular on A and B (30 deg apart) is refused in words ("Cannot add"), nothing changes, no undo step is taken
##   6 REPLAY   the record replays with no sketch error; a record with a conflicting rule pasted in answers the sketch with its error (no silent break)
##   7 FILE     save -> new scene -> load: the same record (constraints too), the same answer from the replay
## Shots: C:/Temp/claude/pconstr/shot_*.png (the rectangle with its rules, the drag, the angle). Only user:// is written (the test folder).
const SHOT := "C:/Temp/claude/pconstr"
const DIRT := "user://pconstr_test"
var fails := 0
var m: Node


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


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
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


## a Part tool as a user reaches it: its own ribbon button (the rule row shows while Constrain is open)
func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	for pair in m.ui_caps.get("BUILD", []):   # Constrain (like Dimension) lives under its SKETCH caption
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


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	var sa := InputEventKey.new()   # select all, then type over it
	sa.keycode = KEY_A
	sa.physical_keycode = KEY_A
	sa.ctrl_pressed = true
	sa.pressed = true
	root.push_input(sa, true)
	await process_frame
	for ch in txt:
		var e := InputEventKey.new()
		e.keycode = KEY_0 + int(ch)
		e.physical_keycode = KEY_0 + int(ch)
		e.unicode = ch.unicode_at(0)
		e.pressed = true
		root.push_input(e, true)
		await process_frame
	await key(KEY_ENTER)


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


## the angle between two lines (deg, 0..180) from the sketch's ends
func angle_of(ents: Array, a: int, b: int) -> float:
	var da := Part.v2(ents[a]["b"]) - Part.v2(ents[a]["a"])
	var db := Part.v2(ents[b]["b"]) - Part.v2(ents[b]["a"])
	return rad_to_deg(acos(clampf(da.normalized().dot(db.normalized()), -1.0, 1.0)))


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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL (Part.available() false)")
		quit(0)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on, "0 Part workspace on")

	# 1 RECT: the rectangle as four Lines, then the rules
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "", "1 the Front plane starts a sketch")
	await press_tool(pu, "Line")
	for q in [[0, 0], [100, 0], [100, 60], [0, 60], [0, 0]]:
		await click_at(sp2(q[0], q[1]))
	var ents: Array = pu._sk().get("ents", [])
	ok(ents.size() == 4 and String(ents[3]["k"]) == "line", "1 four lines drawn by clicks (%d)" % ents.size())
	await key(KEY_ESCAPE)
	var n0: int = m.undo.size()
	await press_tool(pu, "Constrain")
	ok(pu.con_open and pu.tool_btns["Horizontal"].is_visible_in_tree(), "1 Constrain opens the rule row")
	# coincident corners: the first end, then the other line's end at the same spot
	for c in [[100, 0], [100, 60], [0, 60], [0, 0]]:
		await press_tool(pu, "Coincident")
		await click_at(sp2(c[0], c[1]))
		await click_at(sp2(c[0], c[1]))
	await press_tool(pu, "Horizontal")
	await click_at(sp2(50, 0))
	await press_tool(pu, "Horizontal")
	await click_at(sp2(50, 60))
	await press_tool(pu, "Vertical")
	await click_at(sp2(100, 30))
	await press_tool(pu, "Vertical")
	await click_at(sp2(0, 30))
	await press_tool(pu, "Perpendicular")
	await click_at(sp2(50, 0))
	await click_at(sp2(100, 30))
	var cons: Array = pu._sk().get("cons", [])
	ok(cons.size() == 9, "1 nine rules kept: %s" % [cons.map(func(c): return Part.con_name(c))])
	ok(m.undo.size() == n0 + 9, "1 one undo step per rule (%d steps for 9 rules)" % (m.undo.size() - n0))
	ok(Part.con_fail(pu._sk()) == "", "1 every rule holds now")
	await press_tool(pu, "Constrain")
	ok(not pu.con_open and pu.tool == "", "1 Constrain closed: no tool picked")
	await shot("shot_rect")

	# 2 DRAG: the top-right corner (line 1's end at (100, 60)) to (120, 75)
	await ev_move(sp2(100, 60), false)
	await ev_mouse(sp2(100, 60), true)
	await ev_move(sp2(105, 65))
	await ev_move(sp2(110, 70))
	await ev_move(sp2(120, 75))
	await ev_mouse(sp2(120, 75), false)
	await idle(2)
	ents = pu._sk()["ents"]
	var worst := 0.0
	for pr in [[0, 1], [1, 2], [2, 3], [3, 0]]:
		worst = maxf(worst, absf(angle_of(ents, pr[0], pr[1]) - 90.0))
	ok(Part.v2(ents[1]["b"]).is_equal_approx(Vector2(120, 75)), "2 the dragged corner is at (120, 75): %s" % [ents[1]["b"]])
	ok(worst < 0.01, "2 corners stay square: worst deviation %s deg (within 0.01)" % worst)
	ok(absf(Part.v2(ents[2]["a"]).y - Part.v2(ents[2]["b"]).y) < 1e-4 and absf(Part.v2(ents[1]["a"]).x - Part.v2(ents[1]["b"]).x) < 1e-4,
		"2 the top is level and the right side upright")
	ok(Part.v2(ents[0]["b"]).distance_to(Part.v2(ents[1]["a"])) < 1e-4 and Part.v2(ents[2]["b"]).distance_to(Part.v2(ents[3]["a"])) < 1e-4,
		"2 the corners still meet")
	await shot("shot_drag")

	# 3 ANGLE: A (150,0)-(200,0) and B (150,20)-(180,40), Angle 30 typed
	await press_tool(pu, "Line")
	await click_at(sp2(150, 0))
	await click_at(sp2(200, 0))
	await key(KEY_ESCAPE)
	await click_at(sp2(150, 20))
	await click_at(sp2(180, 40))
	await key(KEY_ESCAPE)
	await click_at(sp2(210, 0))
	await click_at(sp2(210, 30))
	await key(KEY_ESCAPE)
	await click_at(sp2(230, 0))
	await click_at(sp2(230, 40))
	await key(KEY_ESCAPE)
	ents = pu._sk()["ents"]
	ok(ents.size() == 8, "3 lines A, B, C, D drawn (%d ents)" % ents.size())
	await press_tool(pu, "Constrain")
	await press_tool(pu, "Angle")
	await click_at(sp2(175, 0))
	await click_at(sp2(165, 30))
	await idle(2)
	ok(pu.dim_edit.visible, "3 the angle box opens after the two lines")
	await type_in(pu.dim_edit, "30")
	ents = pu._sk()["ents"]
	ok(absf(angle_of(ents, 4, 5) - 30.0) < 0.01, "3 the angle is 30 within 0.01 deg: %s (status %s)" % [angle_of(ents, 4, 5), pu.status])
	await press_tool(pu, "Constrain")
	await shot("shot_angle")
	await ev_move(sp2(180, 40), false)
	await ev_mouse(sp2(180, 40), true)
	await ev_move(sp2(190, 50))
	await ev_move(sp2(200, 60))
	await ev_mouse(sp2(200, 60), false)
	await idle(2)
	ents = pu._sk()["ents"]
	var da := angle_of(ents, 4, 5)
	ok(absf(da - 30.0) < 0.01, "3 dragged the far end of B to (200, 60): the angle is still 30 within 0.01 deg (%s)" % da)

	# 4 EQUAL: C (30 mm) and D (40 mm) made the same length
	await press_tool(pu, "Constrain")
	await press_tool(pu, "Equal")
	await click_at(sp2(210, 15))
	await click_at(sp2(230, 20))
	ents = pu._sk()["ents"]
	var lc := Part.v2(ents[6]["b"]).distance_to(Part.v2(ents[6]["a"]))
	var ld := Part.v2(ents[7]["b"]).distance_to(Part.v2(ents[7]["a"]))
	ok(absf(lc - ld) < 0.01, "4 Equal: C %s mm and D %s mm, the same within 0.01 mm" % [lc, ld])
	await press_tool(pu, "Constrain")

	# 5 REFUSE: Perpendicular on A and B (30 deg apart)
	var n1: int = m.undo.size()
	var c1: int = (pu._sk().get("cons", []) as Array).size()
	await press_tool(pu, "Constrain")
	await press_tool(pu, "Perpendicular")
	ents = pu._sk()["ents"]
	var ma := (Part.v2(ents[4]["a"]) + Part.v2(ents[4]["b"])) * 0.5   # the lines' middles now (B moved in step 3)
	var mb := (Part.v2(ents[5]["a"]) + Part.v2(ents[5]["b"])) * 0.5
	await click_at(sp2(ma.x, ma.y))
	await click_at(sp2(mb.x, mb.y))
	await press_tool(pu, "Constrain")
	ok(String(pu.status).begins_with("Cannot add Perpendicular"), "5 refused in words: %s" % pu.status)
	ok(m.undo.size() == n1 and (pu._sk().get("cons", []) as Array).size() == c1, "5 nothing changed and no undo step taken")

	# 6 REPLAY: no sketch error for the good record; a conflicting rule in the record is the sketch's error
	var r: Dictionary = Part.replay(m.S.part)
	ok((r["errors"] as Dictionary).is_empty(), "6 replay: no errors for the rules (%s)" % [r["errors"]])
	var bad: Dictionary = JSON.parse_string(ps())
	var sk_id := String(pu.sk)
	for f in bad["features"]:
		if String(f["id"]) == sk_id:
			(f["cons"] as Array).append({"k": "perp", "a": 4, "b": 5})
	var rb: Dictionary = Part.replay(bad)
	ok((rb["errors"] as Dictionary).has(sk_id) and String(rb["errors"][sk_id]).contains("cannot all hold"),
		"6 a conflicting rule in the record is the sketch's error: %s" % [rb["errors"]])

	# 7 FILE
	await press_tool(pu, "Constrain")
	await click_ctl(pu.finish_btn)
	var saved := JSON.stringify(JSON.parse_string(ps()))
	var path := DIRT + "/pconstr.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	f.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	var same := JSON.stringify(JSON.parse_string(ps())) == saved
	var total := 0
	for f2 in m.S.part.get("features", []):
		total += (f2.get("cons", []) as Array).size()
	ok(same and total == 11, "7 reopened: the same record, %d rules kept (9 + angle + equal = 11)" % total)

	print("pconstr: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])
