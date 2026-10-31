extends SceneTree
## godot --headless --path . -s tests/p046equalandst_test.gd     (P046 SMART GUIDES: while a sketch Line is drawn, Equal (same length as a line already there), Straight (level or upright) and Right angle (square to the line before it) light up in words and in the lit line; real clicks)
## Bars, written before coding (lengths mm, angles deg, sketch on the Front plane, snap 5 mm):
##   1 EQUAL    line 1 (0,0)-(30,0) by clicks. Line 2 started at (0,20), the pointer at (0,50): the readout says "Equal to line 1" and "Straight: upright"
##   2 EQUAL    the click at (0,50) keeps line 2: its length is line 1's length within 0.01 mm (measured from the record ends)
##   3 STRAIGHT line 3 started at (60,0), the pointer at (95,0): the readout says "Straight: level" and NOT "Equal" (35 mm is no other line's length)
##   4 RIGHT    line 3 is kept at 35 mm; line 4 runs on from (95,0) to (95,30) (the pointer, then the click): the readout says "Right angle" and "Equal to line 1";
##              the angle between lines 3 and 4 is 90 within 0.01 deg
##   5 PLAIN    Esc, then a line from (0,-40) to (25,-35): the readout has none of "Equal", "Straight", "Right" (no guide lights for a plain line)
##   6 COUNT    the guides add no line and no undo step: the undo count does not move while the pointer hovers (the guides light), and the walk leaves 4 lines in the record
##              (a sketch's lines are one undo step together, when the sketch is used, so line clicks alone add none: measured 0 on the base code)
##   7 SHOT     the drawn sketch with line 2 lit (the Equal guide): user://p046equalandst_test/shot_equal.png, the file exists and is not empty
const DIRT := "user://p046equalandst_test"
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


## the pointer moves over a sketch point (mm) with no button: the readout follows it
func hover_at(p: Vector2) -> void:
	await ev_move(p, false)
	await idle(2)


## a Part tool as a user reaches it: its own ribbon button
func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func line_len(ents: Array, i: int) -> float:
	return Part.v2(ents[i]["a"]).distance_to(Part.v2(ents[i]["b"]))


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
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on, "0 Part workspace on")

	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "", "0 the Front plane starts a sketch")
	await press_tool(pu, "Line")
	var u0: int = m.undo.size()

	# 1-2 EQUAL: line 1 (30 mm), then line 2 vertical from (0,20) to (0,50), the same length
	await click_at(sp2(0, 0))
	await click_at(sp2(30, 0))
	await key(KEY_ESCAPE)
	var ents: Array = pu._sk().get("ents", [])
	ok(ents.size() == 1, "1 line 1 drawn by clicks (%d lines)" % ents.size())
	await click_at(sp2(0, 20))
	var uh: int = m.undo.size()
	await hover_at(sp2(0, 50))
	ok(m.undo.size() == uh, "6 the guide adds no undo step while hovering")
	ok(pu.pill_text.contains("Equal to line 1"), "1 EQUAL lights while line 2 is drawn: '%s'" % pu.pill_text)
	ok(pu.pill_text.contains("Straight: upright"), "1 STRAIGHT (upright) lights too: '%s'" % pu.pill_text)
	var shot := m.get_viewport().get_texture().get_image()
	shot.save_png(ProjectSettings.globalize_path(DIRT + "/shot_equal.png"))
	await click_at(sp2(0, 50))
	ents = pu._sk().get("ents", [])
	ok(ents.size() == 2, "2 line 2 kept (%d lines)" % ents.size())
	ok(ents.size() == 2 and absf(line_len(ents, 1) - line_len(ents, 0)) < 0.01,
		"2 line 2 is as long as line 1: %.4f vs %.4f mm" % [line_len(ents, 1), line_len(ents, 0)] if ents.size() == 2 else "2 line 2 missing")
	await key(KEY_ESCAPE)

	# 3 STRAIGHT: line 3 level from (60,0) to (95,0): 35 mm, no other line has that length
	await click_at(sp2(60, 0))
	await hover_at(sp2(95, 0))
	ok(pu.pill_text.contains("Straight: level"), "3 STRAIGHT (level) lights: '%s'" % pu.pill_text)
	ok(not pu.pill_text.contains("Equal"), "3 no EQUAL for 35 mm: '%s'" % pu.pill_text)
	await click_at(sp2(95, 0))
	ents = pu._sk().get("ents", [])
	ok(ents.size() == 3 and absf(line_len(ents, 2) - 35.0) < 0.01, "3 line 3 is 35 mm (%d lines)" % ents.size())

	# 4 RIGHT ANGLE: the chain runs on from (95,0) up to (95,30): square to line 3, as long as line 1
	await hover_at(sp2(95, 30))
	ok(pu.pill_text.contains("Right angle") and pu.pill_text.contains("Equal to line 1"),
		"4 RIGHT ANGLE and EQUAL light on the chain: '%s'" % pu.pill_text)
	await click_at(sp2(95, 30))
	ents = pu._sk().get("ents", [])
	ok(ents.size() == 4, "4 line 4 kept (%d lines)" % ents.size())
	ok(ents.size() == 4 and absf(angle_of(ents, 2, 3) - 90.0) < 0.01,
		"4 lines 3 and 4 meet at 90 deg: %.4f" % (angle_of(ents, 2, 3) if ents.size() == 4 else -1.0))
	await key(KEY_ESCAPE)

	# 5 PLAIN: a slanted line from (0,-40) to (25,-35): no guide words
	await click_at(sp2(0, -40))
	await hover_at(sp2(25, -35))
	var plain: String = pu.pill_text
	ok(not (plain.contains("Equal") or plain.contains("Straight") or plain.contains("Right")),
		"5 a plain line shows no guide: '%s'" % plain)
	await key(KEY_ESCAPE)

	# 6 COUNT: four lines in the record; the undo count did not move with the guides
	ents = pu._sk().get("ents", [])
	ok(ents.size() == 4, "6 four lines in the record (%d)" % ents.size())
	ok(m.undo.size() == u0, "6 no undo step taken by the walk's hovers (%d steps)" % (m.undo.size() - u0))

	# 7 SHOT: the lit guide was saved to the test folder
	var f := FileAccess.open(ProjectSettings.globalize_path(DIRT + "/shot_equal.png"), FileAccess.READ)
	ok(f != null and f.get_length() > 0, "7 the lit sketch is saved (shot_equal.png)")
	print("RESULT p046equalandst fails=%d" % fails)
	quit(1 if fails > 0 else 0)
