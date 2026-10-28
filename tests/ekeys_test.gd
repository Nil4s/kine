extends SceneTree
## godot --path . --position 4000,4000 -s tests/ekeys_test.gd     (EKEYS: Easy Part keyboard: Ctrl+Z / Ctrl+Y undo and redo, Escape cancels a drag or a half-drawn shape, Delete removes the newest piece as one undo step; scripts/easy_part.gd _input; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen; the keys are real key events. Build: Draw shape on the floor, Pull it up (2 steps).
## Bars:
##   1 BUILT   the part has 2 steps (a shape and its pull), no failed step
##   2 UNDO    Ctrl+Z takes the pull back (2 -> 1) and the Redo button shows
##   3 REDO    Ctrl+Y puts it back (1 -> 2)
##   4 ESC-DRAW Escape in the middle of a drawn box: the release adds no shape, the steps stay 2
##   5 ESC-DRAG Escape in the middle of an amber dot drag (a Chair): the record is the same as before the drag
##   6 DELETE  Delete removes the newest piece (2 -> 1) and is ONE undo step; Ctrl+Z brings it back (1 -> 2)
const SHOT := "C:/Temp/claude/ekeys"
const DIRT := "user://ekeys_test"

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


## a real key press and release
func key(code: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code as Key
		e.physical_keycode = code as Key
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame
	await idle(2)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## a drag on the floor from world a to world b (metres); not released when hold_end is true
func draw_floor(a: Vector3, b: Vector3, esc_at := -1.0) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
		if esc_at >= 0.0 and i == int(esc_at * 12.0):
			await key(KEY_ESCAPE)
	await ev_mouse(pb, false)
	await idle(3)


func fresh() -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)


func nsteps() -> int:
	return (ep()._rec().get("features", []) as Array).size()


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
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	await fresh()

	# BUILD: draw a box on the floor, pull it up
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(-0.12, 0.0, -0.06), Vector3(-0.08, 0.0, -0.02))
	await press(ep().make_btns["pull"])
	await idle(3)
	var rec0: String = JSON.stringify(ep()._rec())
	ok(nsteps() == 2 and (Part.replay(ep()._rec())["errors"] as Dictionary).is_empty(), "1 BUILT %d steps" % nsteps())

	# UNDO / REDO with the keys
	await key(KEY_Z, true)
	ok(nsteps() == 1, "2 UNDO Ctrl+Z takes the pull back (steps 2 -> %d)" % nsteps())
	ok(ep().redo_btn.visible, "2 UNDO the Redo button shows")
	await key(KEY_Y, true)
	ok(nsteps() == 2 and JSON.stringify(ep()._rec()) == rec0, "3 REDO Ctrl+Y puts it back (steps -> %d, same record %s)" % [nsteps(), str(JSON.stringify(ep()._rec()) == rec0)])

	# ESC on a half-drawn shape: a press, a part of the drag, Escape, the rest, the release
	var u0: int = m.undo.size()
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(0.05, 0.0, 0.05), Vector3(0.12, 0.0, 0.11), 0.5)
	await idle(3)
	ok(nsteps() == 2, "4 ESC-DRAW Escape in a drawn box: no shape added (steps %d)" % nsteps())
	ok(m.undo.size() == u0, "4 ESC-DRAW no undo step left behind (%d -> %d)" % [u0, m.undo.size()])

	# DELETE: the newest piece goes, one undo step; Ctrl+Z brings it back
	var u1: int = m.undo.size()
	var n1 := nsteps()
	await key(KEY_DELETE)
	ok(nsteps() == n1 - 1 and m.undo.size() == u1 + 1, "6 DELETE removes the newest piece (%d -> %d) as one undo step (%d -> %d)" % [n1, nsteps(), u1, m.undo.size()])
	await key(KEY_Z, true)
	ok(nsteps() == n1, "6 DELETE Ctrl+Z brings it back (-> %d)" % nsteps())

	# ESC on a slider drag: the record is the same as before the drag
	await press(ep().chips["chair"])   # a template part: its amber dots are the drag
	await idle(3)
	var u2: int = m.undo.size()
	var dots: Array = ep()._dot_list()
	var rec1: String = JSON.stringify(ep()._rec())
	if dots.is_empty():
		ok(false, "5 ESC-DRAG a slider dot is on screen")
	else:
		var d0: Vector2 = dots[0]["scr"]
		await ev_move(d0, false)
		await ev_mouse(d0, true)
		await ev_move(d0 + Vector2(30, 0))
		await ev_move(d0 + Vector2(60, 0))
		await key(KEY_ESCAPE)
		await ev_move(d0 + Vector2(90, 0))
		await ev_mouse(d0 + Vector2(90, 0), false)
		await idle(3)
		ok(JSON.stringify(ep()._rec()) == rec1, "5 ESC-DRAG Escape in a slider drag: the record is unchanged")
		ok(m.undo.size() == u2, "5 ESC-DRAG no undo step from the cancelled drag (%d -> %d)" % [u2, m.undo.size()])

	DirAccess.make_dir_recursive_absolute(SHOT)
	await idle(20)
	root.get_texture().get_image().save_png("%s/ekeys.png" % SHOT)
	print("ekeys: %d fail" % fails)
	quit(1 if fails > 0 else 0)
