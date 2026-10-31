extends SceneTree
## P107 FITVIEW (Friday plan item 107, Nick: monkey-brain easy): a row of five view buttons at the top of the Easy Part panel, in words:
## "Fit view", "Front", "Top", "Side", "3/4". Real clicks at 1280 x 720 from the real start screen, on the live Easy Part. They move the
## camera only: no step is made, so no undo step. The camera is read from the live camera node; the part's extent from the BUILT solid.
##   V1 the five buttons are there, in those words, and each sits inside the clear view (the panel's own row)
##   V2 Front: the camera looks along the part's depth axis (Z) square on, 8 degrees down (the Front number)
##   V3 Top: the camera looks straight down (forward within 1 degree of -Y)
##   V4 Side: the camera looks along X, square on
##   V5 3/4: the camera looks from a corner: its forward has both X and Z parts between 0.2 and 0.9
##   V6 Fit view: after a 3/4 turn, all eight corners of the built solid project inside the clear view
##   V7 no view press adds a step: the feature count is the same after all five presses
## shots: C:/Temp/claude/p107fitviewfro/views.png
const SHOT := "C:/Temp/claude/p107fitviewfro"
const DIRT := "user://p107fitviewfro_test"
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


## the view buttons: name -> Button (the panel's own row)
func view_btn(k: String) -> Button:
	return find_named(m, "easypart_view_" + k) as Button


## the camera's forward (where it looks), from the live camera node
func forward() -> Vector3:
	return -m.cam.global_basis.z


## the eight corners of the built solid's box, projected: all inside the clear view?
func corners_in_view() -> bool:
	var s := Part.replay(m.S.part, -1, {"faces": true, "props": true})
	var bb: AABB = s["aabb"]
	var cl: Rect2 = m.nav_clear_rect()
	for i in 8:
		var c := bb.position + Vector3(bb.size.x * float(i & 1), bb.size.y * float((i >> 1) & 1), bb.size.z * float((i >> 2) & 1))
		if m.cam.is_position_behind(c):
			return false
		var p := scr(c)
		if not cl.has_point(p):
			return false
	return true


func feature_count() -> int:
	return (m.bld.part._rec().get("features", []) as Array).size()


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

	# the part: Draw shape, Box, a 40 mm drag on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)

	# V1 the five buttons, in words, inside the clear view
	var names := ["fit", "front", "top", "side", "3q"]
	var words := ["Fit view", "Front", "Top", "Side", "3/4"]
	var cl: Rect2 = m.nav_clear_rect()
	var inside := true
	var said := true
	for i in names.size():
		var b := view_btn(names[i])
		if b == null or not b.visible or String(b.text) != words[i]:
			said = false
		elif not cl.encloses(b.get_global_rect()):
			inside = false
	ok(said and inside, "V1 five view buttons Fit view, Front, Top, Side, 3/4, inside the clear view")
	await shot("views")

	var n0 := feature_count()

	# V2 Front: square on the depth axis, 8 degrees down
	await click_ctl(view_btn("front"))
	await idle(60)
	var f2 := forward()
	ok(absf(f2.z) > 0.98 and absf(rad_to_deg(asin(clampf(-f2.y, -1.0, 1.0))) - 8.0) <= 0.5,
		"V2 Front: looks along Z square on, 8 deg down (forward %s)" % [str(f2)])

	# V3 Top: straight down
	await click_ctl(view_btn("top"))
	await idle(60)
	var f3 := forward()
	ok(-f3.y > 0.9998, "V3 Top: looks straight down (forward y %.4f)" % [f3.y])

	# V4 Side: square on X
	await click_ctl(view_btn("side"))
	await idle(60)
	var f4 := forward()
	ok(absf(f4.x) > 0.99, "V4 Side: looks along X square on (forward %s)" % [str(f4)])

	# V5 3/4: a corner view
	await click_ctl(view_btn("3q"))
	await idle(60)
	var f5 := forward()
	ok(absf(f5.x) > 0.2 and absf(f5.x) < 0.9 and absf(f5.z) > 0.2 and absf(f5.z) < 0.9,
		"V5 3/4: looks from a corner (forward %s)" % [str(f5)])

	# V6 Fit view: the whole built part is in the clear view after a 3/4 turn
	await click_ctl(view_btn("fit"))
	await idle(60)
	ok(corners_in_view(), "V6 Fit view: the eight corners of the built solid are inside the clear view")
	await shot("fit")

	# V7 the presses add no step
	var n1 := feature_count()
	ok(n1 == n0, "V7 the five view presses add no step (features %d before, %d after)" % [n0, n1])

	print("P107FITVIEW %d fails" % fails)
	quit(1 if fails > 0 else 0)
