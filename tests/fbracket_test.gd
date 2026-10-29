extends SceneTree
## FBRACKET (Nick 2026-10-28: "free 3D building, anything, nothing forced"): a beginner who never read a manual builds an L bracket from the
## BUILDING card by real clicks at 1280x720: base plate drawn on the floor and pulled up, a flange drawn ON the top face and pulled up,
## Round the edges, Cut a hole, then Expert and back to Easy. Dead ends are bars.
## Bars (run on the old code before the change: see the report):
##   0 the BUILDING card, one click: Easy Part on, blank (no steps)
##   1 a box drawn on the floor and pulled up: one body, volume > 0
##   2 a flange drawn ON the top face (back edge) and pulled up: still one body, volume grows to an L (more than 1.5x the plate)
##   3 Round the edges: ONE undo step, bodies 1, volume goes down a little (the corners are softened)
##   4 Cut a hole: ONE undo step, the volume goes down
##   5 two screw holes (5b: the refusal says the middle already has a hole and names Expert): a second Cut a hole press adds a second hole (the volume goes down again, step count +1)
##   6 Expert and back: Expert opens the same part (same step count), Easy comes back on with the same volume
## shots: C:/Temp/claude/fbracket/open.png, flange.png, round.png, hole.png, expert.png
const SHOT := "C:/Temp/claude/fbracket"
const DIRT := "user://fbracket_test"

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


func vol() -> float:
	return float(pu().res.get("volume", 0.0))


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(pu().on and pu().easy and pu().res.get("bodies", 0) == 0, "0 BUILDING card, one click -> blank Easy Part")
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("open")

	# 1 base plate: Draw shape on the floor, Pull it up
	var ep = pu().ep
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.015)), scr(Vector3(0.03, 0.0, 0.015)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var v1 := vol()
	ok(int(pu().res.get("bodies", 0)) == 1 and v1 > 0.0, "1 base plate drawn and pulled: one body, volume %.1f cm3" % (v1 * 1e6))

	# 2 flange: Draw shape ON the top face at the back edge, then Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.03, 0.02, -0.015)), scr(Vector3(0.03, 0.02, -0.011)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var v2 := vol()
	ok(int(pu().res.get("bodies", 0)) == 1 and v2 > 1.5 * v1, "2 flange drawn on the top face and pulled: one body, L volume %.1f cm3 (plate %.1f)" % [v2 * 1e6, v1 * 1e6])
	print("     hint after the flange: %s" % ep.hint_l.text)
	await shot("flange")

	# 3 Round the edges: one undo step, volume goes down
	var n0: int = m.undo.size()
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	var v3 := vol()
	ok(m.undo.size() == n0 + 1 and int(pu().res.get("bodies", 0)) == 1 and v3 < v2 and v3 > 0.9 * v2,
		"3 Round the edges: one undo step, one body, volume %.1f -> %.1f cm3" % [v2 * 1e6, v3 * 1e6])
	await shot("round")

	# 4 Cut a hole: one undo step, volume down
	n0 = m.undo.size()
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var v4 := vol()
	ok(m.undo.size() == n0 + 1 and v4 < v3, "4 Cut a hole: one undo step, volume %.1f -> %.1f cm3" % [v3 * 1e6, v4 * 1e6])
	await shot("hole")

	# 5 a second screw hole: a second Cut a hole press adds another hole (volume down again)
	n0 = m.undo.size()
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var v5 := vol()
	var hh: String = ep.hint_l.text
	ok(hh.find("already has a hole") >= 0 and hh.find("Expert") >= 0, "5b the refusal says why and where: \"%s\"" % hh)
	ok(v5 < v4 - 1e-12, "5 second screw hole: a second Cut a hole press removes more volume (%.2f -> %.2f cm3, undo +%d)" % [v4 * 1e6, v5 * 1e6, m.undo.size() - n0])

	# 6 Expert and back: the same part, then Easy on again
	var steps: int = m.S.part.get("features", []).size()
	await click_ctl(ep.expert_btn)
	await idle(20)
	ok(not pu().easy and m.S.part.get("features", []).size() == steps, "6a Expert opens the same part (%d steps)" % steps)
	await shot("expert")
	await click_ctl(pu().easy_open_btn)   # the Expert ribbon's Easy (the one a beginner sees)
	await idle(20)
	ok(pu().easy and absf(vol() - v5) < 1e-12, "6b back to Easy: same volume %.2f cm3" % (vol() * 1e6))

	print("fbracket: %d fail" % fails)
	quit(1 if fails > 0 else 0)
