extends SceneTree
## FREEWALK (Nick 2026-10-28): a beginner who never used 3D builds a free thing from the BUILDING card. Real clicks at 1280x720.
## Walk: BUILDING Easy -> Draw shape + drag -> Pull it up -> Round the edges -> Cut a hole. Dead ends found on the old code:
##   D1 the empty part opens with the grid tile in the lower right corner, its origin below the screen (bar 1 FAILS)
##   D2 after Cut a hole the solid is off the screen (bar 3 FAILS)
##   D3 a drag with no tool armed does nothing; the hint only says what to press (bar 2 passes: the words name Draw shape)
## Bars (run on the old code before the change: 0, 1, 2b, 3, 4a, 4c FAILED; 2a passed there only because the Easy card's chooser hid the box):
##   0 the BUILDING card, one click: page BUILD, the chooser is NOT open, Easy Part is on
##   1 the part is empty (no steps) and named "Part N" (MyParts.free_name)
##   2 no "House name" control is visible; no visible words with "house" anywhere on screen
##   3 Draw shape works at once: a real drag on the grid, then Pull it up, makes one body
##   4 a house is still reachable: "What to build" -> House (Easy) -> the House name box shows
## shots: C:/Temp/claude/freebuild/open.png (after the card click), house.png (after House)
const SHOT := "C:/Temp/claude/freewalk"
const DIRT := "user://freewalk_test"

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


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func on_screen(p: Vector2) -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= vs.x and p.y <= vs.y


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
	await idle(20)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy,
		"0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)

	# 1 D1: the empty grid is in view at open: its middle (the origin) and its corners are on the 1280 x 720 screen
	var corners := [scr(Vector3(-0.5, 0.0, -0.5)), scr(Vector3(0.5, 0.0, -0.5)), scr(Vector3(0.5, 0.0, 0.5)), scr(Vector3(-0.5, 0.0, 0.5))]
	var all_in := true
	var wide := 0.0
	for p in corners:
		all_in = all_in and on_screen(p)
		wide = maxf(wide, absf(p.x - corners[0].x))
	ok(all_in and wide >= 400.0, "1 D1 the empty grid (1 m square) is on screen at open and at least 400 px wide (corners %s, width %.0f)" % [corners, wide])

	# 2 D3: a drag with no tool armed gives words that name Draw shape
	await drag_screen(Vector2(830, 560), Vector2(950, 610))
	var hint: String = pu().ep.hint_l.text
	ok(hint.find("Draw shape") >= 0, "2 D3 a drag with no tool: the hint names Draw shape (%s)" % hint)

	# the walk: Draw shape, drag, Pull it up, Round the edges, Cut a hole
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(Vector2(830, 560), Vector2(950, 610))
	await click_ctl(pu().ep.make_btns["pull"])
	await click_ctl(pu().ep.make_btns["round"])
	await shot("04_round")
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(20)
	await shot("05_hole")
	# 3 D2: after Cut a hole the solid is still on screen (its box middle projects inside the screen)
	var bb: AABB = pu().res.get("aabb", AABB())
	var c := scr(bb.get_center())
	ok(bb.size.length() > 1e-4 and on_screen(c), "3 D2 after Cut a hole the solid is on screen (centre %s, box %s)" % [c, bb.size])

	print("freewalk: %d fail" % fails)
	quit(1 if fails > 0 else 0)
