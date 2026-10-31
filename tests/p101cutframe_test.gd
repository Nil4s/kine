extends SceneTree
## P101 CUT FRAME (Friday plan 101, follow-up to p101sectioneasy): with Cut view on, the camera frames the whole part in the free view
## (as Fit view does), not under the side panel: the cut part sat mostly off the view with an orange sliver at the edge.
## Real clicks at 1280 x 720, live Easy Part; the part is a box 40 mm square drawn on the grid and pulled up (blank building card).
## Bar (measured from the rendered picture, not from code variables):
##   1 Cut view on: the orange inside face covers at least 2 % of the clear view (pixels of the cap colour / pixels of the clear view)
## shots: C:/Temp/claude/p101cutframe/
const SHOT := "C:/Temp/claude/p101cutframe"
const DIRT := "user://p101cutframe_test"
const CAP := Color(0.91, 0.51, 0.23)
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the cap-coloured pixels inside the clear view of the rendered picture, and the clear view's own pixel area
func cap_share() -> Array:
	var img: Image = root.get_texture().get_image()
	var s := Vector2(img.get_size()) / m.get_viewport().get_visible_rect().size   # picture pixels per layout unit
	var cl: Rect2 = m.nav_clear_rect()
	var r := Rect2(cl.position * s, cl.size * s)
	var n := 0
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			var c := img.get_pixel(x, y)
			if absf(c.r - CAP.r) < 0.03 and absf(c.g - CAP.g) < 0.03 and absf(c.b - CAP.b) < 0.03:
				n += 1
	return [n, maxf(r.get_area(), 1.0)]


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep

	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)

	var cut := find_named(m, "easypart_view_cut") as Button
	if cut == null:
		print("FAIL the Cut view chip is missing")
		quit(1)
		return
	await click_ctl(cut)
	await idle(60)
	await shot("cut_on")

	var cs: Array = cap_share()
	var share: float = float(cs[0]) / float(cs[1])
	ok(cut.button_pressed and share >= 0.02,
		"BAR cut on: the orange inside face covers %.1f %% of the clear view (%d px, need >= 2 %%)" % [share * 100.0, cs[0]])

	print("p101cutframe: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
