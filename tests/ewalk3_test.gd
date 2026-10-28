extends SceneTree
## godot --path . --position 4000,4000 -s tests/ewalk3_test.gd     (MONKEY WALK 3 of EASY PART: scripts/easy_part.gd; needs the CAD DLL and a window)
## A first-time user, mouse only, 1280 x 720, from Easy home (C:/Temp/claude/ewalk3/WALK.md). Three small frictions fixed in words:
## Bars (run once on the old code: all three FAIL there, the old refusals had no next step):
##   1 OPEN    Pull it up on an open Curvy line says how to close it ("drag back to the start to close it")
##   2 ROUND   Round the edges on a body too small to round says the next press ("Pull it up taller, then press Round the edges again")
##   3 BLEND   Blend two shapes that cannot be lofted says what to do ("draw both as closed shapes, then press Blend two shapes again")
const DIRT := "user://ewalk3_test"

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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the walk cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# 1 OPEN: an open curvy line (three points, not closed) pulled up
	var rec := Part.make("Box")
	var pts := [Part.arr2(Vector2(0, 0)), Part.arr2(Vector2(20, 10)), Part.arr2(Vector2(40, 0))]
	rec["features"] = [{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front",
		"ents": [{"k": "bspline", "pts": pts, "closed": false}], "dims": []}]
	rec["seq"] = 1
	var msg1: String = ep._pull(rec)
	ok(msg1.contains("drag back to the start to close it"), "1 OPEN open curve pull says how to close it [%s]" % msg1)

	# 2 ROUND: a body far too small to round (0.2 mm cube)
	var tiny := Part.make("Box")
	tiny["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [-0.1, -0.1], "b": [0.1, 0.1]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 0.2, "both": false, "op": "new"}]
	tiny["seq"] = 2
	var msg2: String = ep._round(tiny)
	ok(msg2.contains("Pull it up taller, then press Round the edges again"), "2 ROUND too small to round says the next press [%s]" % msg2)

	# 3 BLEND: two open curves on different planes cannot be lofted
	var bl := Part.make("Box")
	var op := [Part.arr2(Vector2(0, 0)), Part.arr2(Vector2(20, 10)), Part.arr2(Vector2(40, 0))]
	bl["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "bspline", "pts": op, "closed": false}], "dims": []},
		{"t": "sketch", "id": "f2", "name": "Sketch2", "plane": "top", "ents": [{"k": "bspline", "pts": op, "closed": false}], "dims": []}]
	bl["seq"] = 2
	var msg3: String = ep._blend(bl)
	ok(msg3.contains("draw both as closed shapes, then press Blend two shapes again"), "3 BLEND two shapes that cannot blend say what to do [%s]" % msg3)

	print("ewalk3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
