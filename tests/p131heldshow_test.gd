extends SceneTree
## p131heldshow (Friday plan 131, "Prop-aware animation": the held Part is shown in the picture): Easy Part, Give to a character.
## The Part's own view left him out of the picture (the BUILD page hides the figure and the Easy view frames the Part only).
## Real clicks at 1280x720 from the BUILDING card's Easy Part (blank): a box 12 cm long drawn on the grid and pulled up 2 cm, then Give to a character.
## Bar (one, measured from the picture's camera projection of him and the Part in his hand, not from the code's own variables):
##   1 after Give the whole figure and the Part in his hand project inside the clear view, and the figure is at least half the view's height
## shot: C:/Temp/claude/p131heldshow/held.png (the picture after Give)
const SHOT := "C:/Temp/claude/p131heldshow"
const DIRT := "user://p131heldshow_test"

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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu():
	return m.bld.part


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
		print("p131heldshow: no solid to hold: cannot continue")
		quit(1)
		return

	# Give to a character (a real click), then the picture
	await click_ctl(pu().ep.give_btn)
	await idle(30)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/held.png" % SHOT)

	# 1 the whole figure and the Part in his hand are in the clear view, the figure at least half its height
	var pts: Array = m.fit_points()
	var r := Rect2(scr(pts[0]), Vector2.ZERO)
	for q in pts:
		r = r.expand(scr(q))
	var clr := Rect2(330.0, 326.0, 360.0, 330.0)   # the clear view: between the left chips and the view column, under the say-line and the tool row (1280 x 720)
	var frac := r.size.y / clr.size.y
	ok(m.B.wep_on and m.man_root.is_visible_in_tree() and clr.encloses(r) and frac >= 0.5, "1 after Give the figure and the Part in his hand are framed in the clear view: box %s inside %s, %.0f%% of its height (want 50%% or more; figure drawn %s, in hand %s)" % [r, clr, frac * 100.0, m.man_root.is_visible_in_tree(), m.B.wep_on])

	print("p131heldshow: %d fail" % fails)
	quit(1 if fails > 0 else 0)
