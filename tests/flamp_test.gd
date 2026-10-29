extends SceneTree
## FLAMP (Nick 2026-10-28): a beginner, no manual, real clicks at 1280x720 from the real start screen, builds a desk lamp in
## the free BUILDING part: round base, thin arm, cone-ish shade (a round shape pulled up), each part coloured on its own.
## Bars (run on the old code before the change: see the report):
##   0 the BUILDING card, one click: page BUILD, Easy Part on
##   1 Draw shape + Round chip + a drag + Pull it up makes the base: one body
##   2 Colour then Red: the base is red (the chip is found and the press is one step)
##   3 the arm (a box beside the base, pulled up) makes a second body; Colour then Blue paints ONLY the arm:
##     the base stays red (dead end on the old code: Colour painted every body the same colour)
##   4 the shade (a round shape pulled up) makes a third body; Colour then Yellow paints only the shade
##   5 the three bodies have three different colours on screen (the looks list: base red, arm blue, shade yellow)
## shots: C:/Temp/claude/flamp/*.png
const SHOT := "C:/Temp/claude/flamp"
const DIRT := "user://flamp_test"

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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func looks_of(i: int) -> Color:
	var looks: Array = pu().res.get("body_looks", [])
	return Part.look_at(looks, i)["c"]


func near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.06 and absf(a.g - b.g) < 0.06 and absf(a.b - b.b) < 0.06


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
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("01_open")

	# 1 the base: Draw shape, Round chip, a drag on the grid, Pull it up
	var ep = pu().ep
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_screen(scr(Vector3(-0.08, 0.0, -0.08)), scr(Vector3(0.08, 0.0, 0.08)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await shot("02_base")
	ok(int(pu().res.get("bodies", 0)) == 1, "1 the base is one body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 2 Colour, Red: the base is red
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(m.find_child("easypart_colour_red", true, false))
	await idle(10)
	await shot("03_base_red")
	ok(near(looks_of(0), Color("#c0392b")), "2 Colour Red: the base is red (%s)" % looks_of(0))

	# 3 the arm: a box beside the base, pulled up; Colour Blue on it only
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(0.22, 0.0, -0.02)), scr(Vector3(0.3, 0.0, 0.02)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	ok(int(pu().res.get("bodies", 0)) == 2, "3a the arm makes a second body (bodies %d)" % int(pu().res.get("bodies", 0)))
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(m.find_child("easypart_colour_blue", true, false))
	await idle(10)
	await shot("04_arm_blue")
	ok(near(looks_of(1), Color("#3a7bd5")) and near(looks_of(0), Color("#c0392b")),
		"3b Colour Blue paints only the arm: base %s, arm %s" % [looks_of(0), looks_of(1)])

	# 4 the shade: a round shape pulled up above the arm's side; Colour Yellow on it only
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_screen(scr(Vector3(-0.55, 0.0, 0.45)), scr(Vector3(-0.45, 0.0, 0.55)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	ok(int(pu().res.get("bodies", 0)) == 3, "4a the shade makes a third body (bodies %d)" % int(pu().res.get("bodies", 0)))
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(m.find_child("easypart_colour_yellow", true, false))
	await idle(10)
	await shot("05_shade_yellow")
	ok(near(looks_of(2), Color("#f2c94c")) and near(looks_of(1), Color("#3a7bd5")) and near(looks_of(0), Color("#c0392b")),
		"5 three bodies, three colours: base %s, arm %s, shade %s" % [looks_of(0), looks_of(1), looks_of(2)])

	print("flamp: %d fail" % fails)
	quit(1 if fails > 0 else 0)
