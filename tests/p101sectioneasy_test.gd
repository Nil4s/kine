extends SceneTree
## P101 SECTION (Friday plan item 101, Nick: monkey-brain easy): Easy Part gets a Cut view chip at the foot of the view column
## (a toggle, words "Cut view"). On: the built part is cut in half across the Front normal, through its middle, and the inside
## shows in orange; the camera turns to the cut side. View only: no record step, no undo. Real clicks at 1280 x 720, live Easy Part.
## Every number is measured from the built mesh, the live camera, the live shader uniform, or the screenshot pixels.
##   C1 the chip is there, in those words, a toggle, inside the clear view (the view column, no new row)
##   C2 Cut view on and off: the part record is byte-for-byte the same (no step, no undo step)
##   C3 cut on: the built part wears the cut shader and its cut is in the middle of the solid (the removed share of the solid's Z span is 0.4..0.6)
##   C4 cut on: the camera is on the cut side (the side the cut removes), measured from the live camera node
##   C5 cut on: the orange cap shows on screen (at least 500 px of the cap colour in the clear view); cut off: none
##   C6 cut off: the part shows whole again (the material override is gone)
##   C7 on an empty part the chip says what to do next and stays off
## shots: C:/Temp/claude/p101sectioneasy/
const SHOT := "C:/Temp/claude/p101sectioneasy"
const DIRT := "user://p101sectioneasy_test"
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


## the cap-coloured pixels inside the clear view of the live screen
func cap_px() -> int:
	var img: Image = root.get_texture().get_image()
	var cl: Rect2 = m.nav_clear_rect()
	var n := 0
	for y in range(int(cl.position.y), int(cl.end.y)):
		for x in range(int(cl.position.x), int(cl.end.x)):
			var c := img.get_pixel(x, y)
			if absf(c.r - CAP.r) < 0.03 and absf(c.g - CAP.g) < 0.03 and absf(c.b - CAP.b) < 0.03:
				n += 1
	return n


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

	# the part: Draw shape, Box, a 40 mm drag on the grid, Pull it up (real clicks)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)

	var cut := find_named(m, "easypart_view_cut") as Button
	var cl: Rect2 = m.nav_clear_rect()

	# C1 the chip: words, a toggle, inside the clear view
	ok(cut != null and cut.toggle_mode and String(cut.text) == "Cut view" and cut.visible and cl.encloses(cut.get_global_rect()),
		"C1 the Cut view chip is there, in those words, a toggle, inside the clear view")

	var rec0 := JSON.stringify(m.S.part)
	var pix0 := cap_px()

	# C2 + C3 + C4 + C5: on, by a real click
	await click_ctl(cut)
	await idle(60)
	var rec1 := JSON.stringify(m.S.part)
	ok(cut.button_pressed and rec0 == rec1, "C2 Cut view on: the part record is unchanged (no step, no undo step)")

	var mat := pu.part_mesh.material_override as ShaderMaterial
	var wb: AABB = pu.part_mesh.global_transform * pu.part_mesh.mesh.get_aabb()   # the built solid, from its mesh
	var cutp: Vector4 = mat.get_shader_parameter("cut") if mat != null else Vector4()
	var zn := signf(cutp.z) if absf(cutp.z) > 0.5 else 0.0
	var frac := -1.0
	if zn != 0.0:
		var pz := cutp.w / cutp.z   # the cut plane's Z, from the live uniform (plane: n . p = w, n = (0, 0, +-1))
		frac = (pz - wb.position.z) / maxf(wb.size.z, 1e-6)
	ok(mat != null and float(mat.get_shader_parameter("on")) > 0.5 and frac > 0.4 and frac < 0.6,
		"C3 cut on: the built part wears the cut and the cut is in the middle (removed share of the Z span %.2f, 0.4..0.6)" % frac)

	var cam_rel: Vector3 = m.cam.global_position - wb.get_center()
	var cam_side := cam_rel.z * cutp.z
	ok(absf(cam_rel.z) > absf(cam_rel.x) and absf(cam_rel.z) > absf(cam_rel.y) and cam_side > 0.0,
		"C4 cut on: the camera is on the cut side, looking along the cut (camera Z offset %.1f mm)" % (cam_rel.z / Part.MM))

	await shot("cut_on")
	var pix1 := cap_px()
	ok(pix1 >= 500 and pix0 < 500, "C5 the orange cap shows: %d px on, %d px before the chip" % [pix1, pix0])

	# C6 off: by a real click, the whole part shows again
	await click_ctl(cut)
	await idle(60)
	var rec2 := JSON.stringify(m.S.part)
	ok(not cut.button_pressed and pu.part_mesh.material_override == null and rec2 == rec0,
		"C6 Cut view off: the part shows whole again (no override), record unchanged")
	await shot("cut_off")

	# C7 an empty part: the chip says what to do and stays off
	await click_ctl(ep.empty_chip)
	await idle(20)
	await click_ctl(cut)
	await idle(20)
	ok(not cut.button_pressed and String(ep.msg).find("Nothing to cut yet") >= 0,
		"C7 an empty part: Cut view stays off and says what to do next (%s)" % String(ep.msg))
	await shot("cut_empty")

	print("p101sectioneasy: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
