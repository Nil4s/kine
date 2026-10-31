extends SceneTree
## p131grippoint (Friday plan 131, "Prop-aware animation: a built part knows its grip point; the character grabs it right"): Easy Part's Colour page has a Hold here chip.
## Press it, then click the spot on the part where the hand holds it; the spot is stored in the record, and Give to a character holds the shape by it.
## Real clicks at 1280x720 from the BUILDING card's Easy Part (blank): a box 12 cm long drawn on the grid and pulled up 2 cm. Every number is measured from the built result
## (the solid's faces, Body.KINDS after Give, the undo count), never from the code's own variables. Bars (written before the code; the old code fails 1 to 5):
##   1 the Colour page (a real click on Colour) shows a Hold here chip
##   2 a real click on Hold here arms the grip pick: no undo step yet, the status says to click the part
##   3 a click off the part (empty grid) says so, takes no undo step and keeps the pick armed
##   4 a click on the top of the part, 3 cm right of its middle: ONE undo step; the status says how far from the butt the hand holds it (within 5 mm of the measured value)
##   5 Give to a character (a real click): the held shape's grip is that spot: Body.KINDS grip_u = the spot's distance from the butt (within 5 mm of the measured value), and the default (the origin, 6 cm from the butt) is 3 cm away
##   6 Undo twice (two real clicks: Give, then Hold here) and Give again: the grip is the origin again (grip_u within 5 mm of the origin's distance from the butt)
## shots: C:/Temp/claude/p131grippoint/hold_picked.png (the status after the pick), held.png (after Give)
const SHOT := "C:/Temp/claude/p131grippoint"
const DIRT := "user://p131grippoint_test"

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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the solid's lowest x (the butt) and highest y (the top), metres, from its faces
func butt_x() -> float:
	var x := INF
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			x = minf(x, (v as Vector3).x)
	return x


func top_y() -> float:
	var y := -INF
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			y = maxf(y, (v as Vector3).y)
	return y


func undo_n() -> int:
	return m.undo.size()


func held_kind() -> String:
	return String(m.B.wep_kind) if m.B.wep_on else ""


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# the BUILDING card, one click: a blank Easy Part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# a box 12 cm long (x -6..6 cm), 4 cm wide, pulled up 2 cm
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.06, 0.0, -0.02)), scr(Vector3(0.06, 0.0, 0.02)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	if pu().res.get("bodies", 0) != 1:
		print("p131grippoint: no solid to hold: cannot continue")
		quit(1)
		return

	# 1 the Colour page shows Hold here
	await click_ctl(pu().ep.make_btns["colour"])
	var hold = m.find_child("easypart_hold", true, false)
	ok(hold is Button and (hold as Button).is_visible_in_tree() and (hold as Button).text == "Hold here", "1 the Colour page shows a Hold here chip")
	if not (hold is Button):
		print("p131grippoint: %d fail" % fails)
		quit(1)
		return

	# 2 Hold here arms the pick: no step yet
	var u0 := undo_n()
	await click_ctl(hold)
	ok(pu().ep.armed == "hold" and undo_n() == u0 and "Click the spot" in String(pu().ep.msg), "2 Hold here arms the pick, no undo step (armed '%s', undo %d -> %d, says '%s')" % [pu().ep.armed, u0, undo_n(), pu().ep.msg])

	# 3 a click off the part says so and keeps the pick
	await click_at(scr(Vector3(0.3, 0.0, 0.3)))
	ok(pu().ep.armed == "hold" and undo_n() == u0 and "Click on the part itself" in String(pu().ep.msg), "3 a click off the part says so, no undo step, still armed (says '%s')" % pu().ep.msg)

	# 4 a click on the top, 3 cm right of the middle: one undo step, the status gives the distance from the butt
	var knob := butt_x()
	var want := 0.03 - knob
	await click_at(scr(Vector3(0.03, top_y(), 0.0)))
	await shot("hold_picked")
	ok(pu().ep.armed == "" and undo_n() == u0 + 1, "4a the pick ends with ONE undo step (undo %d -> %d)" % [u0, undo_n()])
	var says := String(pu().ep.msg)
	var said := -1.0
	var rx := RegEx.new()
	rx.compile("([0-9.]+) cm from the butt")
	var mt := rx.search(says)
	if mt != null:
		said = float(mt.get_string(1)) / 100.0
	ok(mt != null and absf(said - want) < 0.005, "4b the status names the grip: %.1f cm from the butt, the solid's butt to the spot is %.1f cm (says '%s')" % [said * 100.0, want * 100.0, says])

	# 5 Give to a character holds the shape by that spot
	await click_ctl(pu().ep.give_btn)
	await shot("held")
	var kind := held_kind()
	var grip_u := float(Body.KINDS[kind]["grip_u"]) if kind != "" and Body.KINDS.has(kind) else -1.0
	ok(kind.begins_with("part:") and absf(grip_u - want) < 0.005, "5 Give holds the shape at the spot: kind '%s', grip %.1f cm from the butt (want %.1f cm)" % [kind, grip_u * 100.0, want * 100.0])
	ok(absf(grip_u - (0.0 - knob)) > 0.02, "5b the spot is not the origin the shape held at before (origin %.1f cm from the butt)" % ((0.0 - knob) * 100.0))

	# 6 Undo twice (Give, then Hold here) and Give again: the grip is the origin again
	await click_ctl(pu().ep.undo_btn)
	await click_ctl(pu().ep.undo_btn)
	await click_ctl(pu().ep.give_btn)
	var kind2 := held_kind()
	var grip2 := float(Body.KINDS[kind2]["grip_u"]) if kind2 != "" and Body.KINDS.has(kind2) else -1.0
	ok(kind2.begins_with("part:") and absf(grip2 - (0.0 - knob)) < 0.005, "6 after Undo twice the grip is the origin again: %.1f cm from the butt (want %.1f cm)" % [grip2 * 100.0, (0.0 - knob) * 100.0])

	print("p131grippoint: %d fail" % fails)
	quit(1 if fails > 0 else 0)
