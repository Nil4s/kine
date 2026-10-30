extends SceneTree
## NOPENTOP (Friday plan item 15; Nick: monkey-brain easy): Hollow inside, then one click on a flat face makes THAT face the open side
## (a tray: Open the top = open at the top). Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Draw shape Box, a square drawn on the floor (80 mm) -> Pull it up to 80 mm -> Cut a hole -> Hollow inside (chip)
##   -> one click on the side face that faces the camera (it becomes the open side) -> the Wall slider to 6 mm
## Bars (each one measured from the BUILT result in mm: mesh rays and the replay volume, never from the code's own variables;
## the wall in the expected numbers is the slider's own reading):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the square Pulled up: one solid, 80 x 80 x 80 mm within 2 pct
##   2 Hollow inside (chip): one body, the top open: a ray down the middle hits the inside floor at 497 mm from the ray start (the floor at 3 mm)
##   3 the hollow's volume = outer - inner (3 mm wall, open top) within 2 pct
##   4 a real click on the side face toward the camera: that side is open: a ray in from outside hits the far inside wall at 277 mm (+-2)
##     (FAILS on the old code: the click picks a piece, the side stays closed: 200 mm)
##   5 the top is closed now: a ray down the middle hits the top at 420 mm from the ray start (+-2) (FAILS on the old code: 497)
##   6 the side click adds exactly 1 undo step (FAILS on the old code: 0)
##   7 the words: the press that opened the side says a line with open in it (FAILS on the old code: no such line)
##   8 the Wall slider dragged to 6 mm: volume = outer - inner (6 mm wall, the side open) within 2 pct
##   9 the Wall drag adds exactly 1 undo step
## shots: C:/Temp/claude/nopentop/

const SHOT_DIR := "C:/Temp/claude/nopentop"
const DIRT := "user://nopentop_test"

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


## the built mesh's triangles in world metres
func world_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi: MeshInstance3D = pu().part_mesh
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


## the NEAREST hit distance (mm) of a ray from o along unit d through the built mesh (Moller-Trumbore), or NAN when nothing is hit
func ray_first(o: Vector3, d: Vector3) -> float:
	var tris := world_tris()
	var best := INF
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var e1 := tris[k + 1] - a
		var e2 := tris[k + 2] - a
		var p := d.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-12:
			continue
		var s := o - a
		var u := s.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var v := d.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var tt := e2.dot(q) / det
		if tt > 1e-6 and tt < best:
			best = tt
	return best / Part.MM if best < INF else NAN


## the volume (mm3) of a box of size sz (mm) with a wall w mm, open on the axis of n (the open side); the other two axes keep both walls
func tray_vol(sz: Vector3, n: Vector3, w: float) -> float:
	var dims := Vector3.ZERO
	for ax in 3:
		var e: bool = n[ax] != 0.0
		dims[ax] = sz[ax] - (w if e else 2.0 * w)
	return sz.x * sz.y * sz.z - dims.x * dims.y * dims.z


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


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

	# 1 a box: Draw shape (Box), a square on the floor 80 mm, Pulled up to 80 mm by the slider
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.04)), scr(Vector3(0.04, 0.0, 0.04)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 8.0)
	var bb: AABB = bbox()
	var bodies: int = int(pu().res.get("bodies", 0))
	ok(bodies == 1 and absf(bb.size.x - 80.0) <= 1.6 and absf(bb.size.y - 80.0) <= 1.6 and absf(bb.size.z - 80.0) <= 1.6,
		"1 the square Pulled up: one solid, %.1f x %.1f x %.1f mm (solids %d)" % [bb.size.x, bb.size.y, bb.size.z, bodies])

	# 2 Cut a hole, then the Hollow inside chip: the top is open (a ray down the middle hits the inside floor at 3 mm)
	await click_ctl(ep().make_btns["hole"])
	var hollow_chip: Button = root.find_child("easypart_hole_hollow", true, false) as Button
	if hollow_chip != null:
		await click_ctl(hollow_chip)
	var floor_d: float = ray_first(Vector3(0.0, 0.5, 0.0), Vector3.DOWN)
	ok(hollow_chip != null and int(pu().res.get("bodies", 0)) == 1 and absf(floor_d - 497.0) <= 1.5,
		"2 Hollow inside: one body, the top open: a ray down the middle hits the inside floor at %.1f mm (want 497)" % floor_d)
	await shot("01_hollow")

	# 3 the volume: outer - inner, the 3 mm wall open at the top
	var v3: float = vol()
	var want3: float = tray_vol(bb.size, Vector3.UP, 3.0)
	ok(absf(v3 - want3) <= want3 * 0.02,
		"3 the hollow's volume %.0f mm3 = outer - inner (3 mm wall, open top) %.0f mm3 (within 2 pct)" % [v3, want3])

	# 4 a real click on the side face that faces the camera: that side is open now
	var cen: Vector3 = Vector3(0.0, 0.04, 0.0)
	var n_side: Vector3 = Vector3.RIGHT
	var best_dot: float = -INF
	for cand in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var dd: float = cand.dot(m.cam.global_position - cen)
		if dd > best_dot:
			best_dot = dd
			n_side = cand
	var u_before: int = m.undo.size()
	await click_at(scr(cen + n_side * 0.04))
	var u_after: int = m.undo.size()
	var far: float = ray_first(cen + n_side * 0.24, -n_side)
	ok(absf(far - 277.0) <= 2.0,
		"4 a real click on the side facing the camera: that side is open: a ray in from outside hits the far inside wall at %.1f mm (want 277)" % far)
	await shot("02_side_open")

	# 5 the top is closed now: a ray down the middle hits the top at 420 mm from the ray start
	var top_d: float = ray_first(Vector3(0.0, 0.5, 0.0), Vector3.DOWN)
	ok(absf(top_d - 420.0) <= 2.0,
		"5 the top is closed now: a ray down the middle hits the top at %.1f mm from the ray start (want 420)" % top_d)

	# 6 one undo step for the click
	ok(u_after == u_before + 1, "6 the side click adds exactly 1 undo step (undo %d -> %d)" % [u_before, u_after])

	# 7 the words
	ok(String(ep().msg).to_lower().contains("open"), "7 the press that opened the side says a line with open in it (%s)" % ep().msg)

	# 8 the Wall slider to 6 mm: outer - inner (6 mm wall) with the side open
	var wall: HSlider = null
	for r in ep().rows:
		if String(r.get("label", "")) == "Wall":
			wall = r["slider"] as HSlider
	var u_w: int = m.undo.size()
	if wall != null:
		await drag_slider(wall, 6.0)
	var u_w2: int = m.undo.size()
	var v6: float = vol()
	var want6: float = tray_vol(bbox().size, n_side, 6.0)
	ok(wall != null and absf(v6 - want6) <= want6 * 0.02,
		"8 the Wall slider at 6 mm: volume %.0f mm3, outer - inner (6 mm wall, side open) %.0f mm3 (within 2 pct)" % [v6, want6])

	# 9 the Wall drag is one undo step
	ok(u_w2 == u_w + 1, "9 the Wall drag adds exactly 1 undo step (undo %d -> %d)" % [u_w, u_w2])
	await shot("03_wall6")

	print("NOPENTOP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
