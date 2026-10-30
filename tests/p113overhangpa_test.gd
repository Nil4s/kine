extends SceneTree
## p113OVERHANGPA (Friday plan item 113, Kine's own): Easy Part, a box pulled up and tilted 20 degrees. Show overhangs paints red on the
## faces that point down more than 45 degrees (the tilted bottom); Lay it flat turns the part so the face with the least overhang sits on the
## floor (one step, one undo). Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Draw shape Box, a square on the floor -> Pull it up to 80 mm -> Show overhangs -> Tilt it 20 degrees -> Show overhangs
##   -> Lay it flat -> Lay it flat again -> Undo
## Bars (each one measured from the BUILT result: the mesh, the bounding box and the red copy's triangles in mm and mm2, never the code's own variables):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the square Pulled up: one solid, 80 mm cube within 2 mm
##   2 Show overhangs on a plain box: nothing is red (0 mm2)
##   3 Tilt it 20 degrees: the box is 102.5 mm tall (80 x (cos 20 + sin 20)) within 2 mm
##   4 Show overhangs on the tilted box: the red is the tilted bottom face, 6400 mm2 within 3 pct
##   5 Lay it flat (one click): the box stands 80 mm tall with its lowest point on the floor (0 within 0.5 mm)
##   6 Lay it flat adds exactly 1 undo step, and the newest step is the lay
##   7 after Lay it flat nothing is red (0 mm2)
##   8 Lay it flat again on the upright box: refused in words, no step added
##   9 Undo: the tilted box is 102.5 mm tall again (within 2 mm)
## shots: C:/Temp/claude/p113overhangpa/

const SHOT_DIR := "C:/Temp/claude/p113overhangpa"
const DIRT := "user://p113overhangpa_test"

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
	await click_at(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
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


func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var gw := _grab_w(s)
	var y := r.get_center().y
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


func ep():
	return pu().ep


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the built bounding box in mm
func bbox() -> AABB:
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


## the red copy's area in mm2 (the triangles of the overlay Easy Part draws over the part; 0 when it is hidden or absent)
func red_area() -> float:
	var mi := root.find_child("easypart_overhangs", true, false) as MeshInstance3D
	if mi == null or not mi.visible or mi.mesh == null:
		return 0.0
	var a := 0.0
	for s in mi.mesh.get_surface_count():
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for k in range(0, vs.size() - 2, 3):
			a += 0.5 * (vs[k + 1] - vs[k]).cross(vs[k + 2] - vs[k]).length()
	return a / (Part.MM * Part.MM)


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
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)

	# 1 a box: Draw shape (Box), a square on the floor, Pulled up to 80 mm by the slider
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.04)), scr(Vector3(0.04, 0.0, 0.04)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 8.0)
	var bb: AABB = bbox()
	var bodies: int = int(pu().res.get("bodies", 0))
	ok(bodies == 1 and absf(bb.size.x - 80.0) <= 2.0 and absf(bb.size.y - 80.0) <= 2.0 and absf(bb.size.z - 80.0) <= 2.0,
		"1 the square Pulled up: one solid, %.1f x %.1f x %.1f mm (solids %d)" % [bb.size.x, bb.size.y, bb.size.z, bodies])

	# 2 Show overhangs on a plain box: nothing is red
	await click_ctl(ep().paint_btn)
	var red0 := red_area()
	ok(ep().paint_on and red0 == 0.0 and String(ep().msg).contains("Nothing is red"),
		"2 Show overhangs on a plain box: nothing red, %.0f mm2 (words: %s)" % [red0, ep().msg])

	# 3 Tilt it 20 degrees: the box leans, and it is 80 x (cos 20 + sin 20) tall
	var u_t: int = m.undo.size()
	await click_ctl(ep().tilt_btn)
	bb = bbox()
	var want_h := 80.0 * (cos(deg_to_rad(20.0)) + sin(deg_to_rad(20.0)))
	ok(absf(bb.size.y - want_h) <= 2.0 and m.undo.size() == u_t + 1,
		"3 Tilt it 20 degrees: %.1f mm tall (want %.1f within 2 mm)" % [bb.size.y, want_h])

	# 4 Show overhangs on the tilted box: the red is the tilted bottom face (80 x 80 mm)
	ep()._ov_key = ""
	await idle(3)
	var red1 := red_area()
	ok(absf(red1 - 6400.0) <= 6400.0 * 0.03,
		"4 Show overhangs on the tilted box: red %.0f mm2 of the bottom face (want 6400 within 3 pct)" % red1)
	await shot("01_tilted_red")

	# 5 Lay it flat (one click): upright, 80 mm tall, lowest point on the floor
	var u_l: int = m.undo.size()
	await click_ctl(ep().lay_btn)
	bb = bbox()
	ok(absf(bb.size.y - 80.0) <= 1.6 and absf(bb.position.y) <= 0.5,
		"5 Lay it flat: %.1f mm tall, lowest point at %.2f mm (want 80 and 0)" % [bb.size.y, bb.position.y])

	# 6 one undo step, and the newest step is the lay
	var last_t := String(ep()._rec()["features"][-1]["t"])
	ok(m.undo.size() == u_l + 1 and last_t == "lay",
		"6 Lay it flat: %d undo step (want 1), newest step %s (want lay)" % [m.undo.size() - u_l, last_t])
	await shot("02_laid_flat")

	# 7 nothing red now
	ok(red_area() == 0.0, "7 after Lay it flat nothing is red: %.0f mm2" % red_area())

	# 8 Lay it flat again on the box already on its best face: refused in words, no step
	var u_r: int = m.undo.size()
	await click_ctl(ep().lay_btn)
	ok(m.undo.size() == u_r and String(ep().msg).to_lower().contains("support"),
		"8 Lay it flat on the best face again: refused, no step (steps %d -> %d; words: %s)" % [u_r, m.undo.size(), ep().msg])

	# 9 Undo: the tilted box is back
	await click_ctl(ep().undo_btn)
	bb = bbox()
	ok(absf(bb.size.y - want_h) <= 2.0,
		"9 Undo: the box leans again, %.1f mm tall (want %.1f within 2 mm)" % [bb.size.y, want_h])

	print("P113OVERHANGPA TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
