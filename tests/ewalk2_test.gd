extends SceneTree
## godot --path . --position 4000,4000 -s tests/ewalk2_test.gd     (MONKEY WALK 2 of EASY PART: scripts/easy_part.gd; needs the CAD DLL and a window)
## A first-time user, mouse only, 1280 x 720, from Easy home: a mug, a table and a shield were built with the MAKE buttons (C:/Temp/claude/ewalk2/WALK.md).
## Bars (written before the fix; each must FAIL on the old code):
##   1 WRAP    Mirror that with a gap: the whole words ("Push them together with Stick together") show, and the words do not run under the
##             'Change your part' panel (the hint's right edge is left of the panel)
##   2 HOLE    Cut a hole says it goes straight through (a mug's 'hole' is not a hollow)
##   3 STATUS  the status line after a mirror with a gap names the next press: "Stick together joins them"
## Shots: C:/Temp/claude/ewalk2/bar_mirror.png, C:/Temp/claude/ewalk2/bar_hole.png
const SHOT := "C:/Temp/claude/ewalk2"
const DIRT := "user://ewalk2_test"

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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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
	# a centred box (no gap after a mirror) for the hole
	var bx := Part.make("Box")
	bx["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [-10.0, -10.0], "b": [10.0, 10.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"}]
	bx["seq"] = 2
	m.S.part = bx
	pu.upto = -1
	pu.sync()
	await idle(3)
	# 2 HOLE
	await click_ctl(ep.make_btns["hole"])
	ok(ep.hint_l.text.contains("straight through"), "2 HOLE Cut a hole says it goes straight through [%s]" % ep.hint_l.text)
	await shot("bar_hole")
	# a box off the middle line (a gap after the mirror)
	var gb := Part.make("Box")
	gb["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [30.0, -10.0], "b": [50.0, 10.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"}]
	gb["seq"] = 2
	# design changed in 7c6bcd55 EMIRROR: Easy Part Mirror on a piece off the middle line goes across the middle of the part; bar rewritten 11-01 per Nick:
	# one box off the line no longer leaves a gap, so the fixture is two boxes JOINED with a gap between them (one body, two lumps)
	gb["features"].append({"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [70.0, -10.0], "b": [90.0, 10.0]}], "dims": []})
	gb["features"].append({"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 20.0, "both": false, "op": "join"})
	gb["seq"] = 4
	m.S.part = gb
	pu.upto = -1
	pu.sync()
	await idle(3)
	await click_ctl(ep.make_btns["mirror"])
	await idle(4)
	var words: String = ep.hint_l.text
	var panel: Control = ep.panel
	var hint_r: float = (ep.hint as Control).get_global_rect().end.x
	var clear: bool = not panel.is_visible_in_tree() or hint_r <= panel.get_global_rect().position.x + 0.5
	# 1 WRAP
	ok(words.contains("Push them together with Stick together") and clear,
		"1 WRAP Mirror with a gap: the whole words show and clear of the panel (hint right %.0f, panel left %.0f) [%s]" % [hint_r, panel.get_global_rect().position.x, words])
	# 3 STATUS
	ok(ep.status_l.text.contains("Stick together joins them"), "3 STATUS after a gap, the status names the next press [%s]" % ep.status_l.text)
	await shot("bar_mirror")
	print("ewalk2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
