extends SceneTree
## P082LIBFRAME (Kine's own): after a Parts library pick the camera frames the new part, so it is not a speck near the centre.
## Real clicks at 1280 x 720, from the BUILDING card: Parts -> Screws -> M4 x 16 (the library screw, 20 mm tall).
## Bar (one): the built part's box, projected through the camera onto the view, is at least 20 % of the view on its bigger side
## (max of its screen width / view width and screen height / view height). The corners come from the camera, not from the
## code's own framing variables. Measured once the camera has stopped easing.
## shots: C:/Temp/claude/p082libframe/*.png
const SHOT := "C:/Temp/claude/p082libframe"
const DIRT := "user://p082libframe_test"
const NEED := 0.20
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


## the built part's box on the view: its eight corners through the camera, the bigger side of their screen box as a share of the view
func view_share(bb: AABB) -> float:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var c: Vector3 = bb.get_endpoint(i)
		if m.cam.is_position_behind(c):
			return 0.0
		var p: Vector2 = m.cam.unproject_position(c)
		lo = lo.min(p)
		hi = hi.max(p)
	var sz := hi - lo
	return maxf(sz.x / vs.x, sz.y / vs.y)


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
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the Parts library: Screws, then M4 x 16
	await click_ctl(ep.parts_btn)
	await idle(5)
	await click_ctl(ep.screw_btns["4_16"])
	# the camera eases onto the part (0.3 s of frames); wait until it has stopped
	var guard := 0
	while not ep._ease.is_empty() and guard < 600:
		await process_frame
		guard += 1
	await idle(10)
	var bb: AABB = pu.res.get("aabb", AABB())
	var share := view_share(bb)
	print("p082libframe: M4 x 16 picked from Parts, box %.2f x %.2f x %.2f mm, bigger side %.1f %% of the view (need %.0f %%)" % [
		bb.size.x / Part.MM, bb.size.y / Part.MM, bb.size.z / Part.MM, share * 100.0, NEED * 100.0])
	ok(share >= NEED and (pu.res.get("errors", {}) as Dictionary).is_empty(),
		"F0 after a Parts library pick (M4 x 16) the part fills at least 20 %% of the view: its bigger side is %.1f %%" % (share * 100.0))
	await shot("lib_m4x16")
	print("p082libframe: %d fail" % fails)
	quit(1 if fails > 0 else 0)
