extends SceneTree
## p022shellwalls (Friday plan item 22; Nick: monkey-brain easy): Shell walls of different thickness per face. After Hollow inside
## (a 3 mm wall all round, open at the top), press Thicker wall, then click the outside of one side wall: that wall gets an Extra wall
## slider (how much thicker). The other walls keep the 3 mm. Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Draw shape Box, a square drawn on the floor (80 mm) -> Pull it up to 80 mm -> Cut a hole -> Hollow inside
##   -> Thicker wall -> one click on the side wall that faces the camera -> the Extra wall slider to 6 mm
## Bars (each one measured from the BUILT result in mm: mesh rays and the replay volume, never from the code's own variables;
## the wall in the expected numbers is the slider's own reading):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the square Pulled up: one solid, 80 x 80 x 80 mm within 2 pct
##   2 Hollow inside (chip): one body, the top open: a ray down the middle hits the inside floor at 497 mm (+-1.5)
##   3 the Thicker wall chip shows under the hollow (FAILS on the old code: no such chip)
##   4 after Thicker wall and a click on the wall facing the camera: that wall is still closed, 4 mm thick at the default
##     Extra wall of 1 mm: a ray from outside through it hits its outside and inside (+-0.5) (FAILS on the old code: the click opens the side)
##   5 the words say thicker (FAILS on the old code: no such line)
##   6 the Extra wall slider dragged to 6 mm: that wall is 9 mm thick (3 + 6) (+-0.5) (FAILS on the old code: no slider, 3 mm)
##   7 the wall opposite it is still 3 mm (+-0.5) (passes on the old code too: it never changed)
##   8 the top is still open: a ray down the middle hits the floor at 497 mm (+-1.5) (FAILS on the old code: the click opens the front, 420)
##   9 the volume: outer - inner with the 9 mm wall and the 3 mm walls, open top, within 2 pct (FAILS on the old code)
##  10 the Extra wall drag adds exactly 1 undo step (FAILS on the old code: no slider)
## shots: C:/Temp/claude/p022shellwalls/

const SHOT_DIR := "C:/Temp/claude/p022shellwalls"
const DIRT := "user://p022shellwalls_test"

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


## every hit distance (mm, sorted, hits closer than 0.05 mm merged) of a ray from o along unit d through the built mesh (Moller-Trumbore)
func ray_all(o: Vector3, d: Vector3) -> Array:
	var tris := world_tris()
	var hits: Array = []
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
		if tt > 1e-6:
			hits.append(tt / Part.MM)
	hits.sort()
	var out: Array = []
	for h in hits:
		if out.is_empty() or float(h) - float(out[-1]) > 0.05:
			out.append(h)
	return out


## the nearest hit distance (mm) of a ray from o along d, or NAN when nothing is hit
func ray_first(o: Vector3, d: Vector3) -> float:
	var h := ray_all(o, d)
	return float(h[0]) if not h.is_empty() else NAN


## the thickness (mm) of the wall that a ray from outside (20 mm out from the face) crosses: the outside hit to the inside hit
func wall_mm(face_c: Vector3, n: Vector3) -> float:
	var h := ray_all(face_c + n * 0.02, -n)
	return float(h[1]) - float(h[0]) if h.size() >= 2 else NAN


## the volume (mm3) of a box of size sz (mm) with the walls removed per axis (a wall of w mm on each side; the open top is one wall)
func cup_vol(sz: Vector3, wall: Array) -> float:
	var dims := Vector3.ZERO
	for ax in 3:
		dims[ax] = sz[ax] - float(wall[ax])
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
	await drag_screen_box()
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

	# 3 the Thicker wall chip shows under the hollow
	var wall_chip: Button = root.find_child("easypart_hole_wall", true, false) as Button
	ok(wall_chip != null and wall_chip.is_visible_in_tree(),
		"3 the Thicker wall chip shows under Hollow inside")

	# the side that faces the camera
	var cen: Vector3 = Vector3(0.0, 0.04, 0.0)
	var n_side: Vector3 = Vector3.RIGHT
	var best_dot: float = -INF
	for cand in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var dd: float = cand.dot(m.cam.global_position - cen)
		if dd > best_dot:
			best_dot = dd
			n_side = cand
	var face_c: Vector3 = cen + n_side * 0.04

	# 4 Thicker wall, then a real click on the wall facing the camera: the wall stays closed, 4 mm at the default 1 mm extra
	if wall_chip != null:
		await click_ctl(wall_chip)
	await click_at(scr(face_c))
	var w4: float = wall_mm(face_c, n_side)
	ok(absf(w4 - 4.0) <= 0.5,
		"4 the click on the wall facing the camera: that wall is closed, %.1f mm thick (want 4: 3 mm wall + 1 mm extra)" % w4)
	await shot("01_wall_picked")

	# 5 the words
	ok(String(ep().msg).to_lower().contains("thicker"), "5 the words say thicker (%s)" % ep().msg)

	# 6 the Extra wall slider to 6 mm: that wall is 9 mm thick
	var extra: HSlider = null
	for r in ep().rows:
		if String(r.get("label", "")) == "Extra wall":
			extra = r["slider"] as HSlider
	var u_w: int = m.undo.size()
	if extra != null:
		await drag_slider(extra, 6.0)
	var u_w2: int = m.undo.size()
	var w6: float = wall_mm(face_c, n_side)
	ok(extra != null and absf(w6 - 9.0) <= 0.5,
		"6 the Extra wall slider at 6 mm: that wall is %.1f mm thick (want 9: 3 + 6)" % w6)

	# 7 the wall opposite is still 3 mm
	var w_opp: float = wall_mm(cen - n_side * 0.04, -n_side)
	ok(absf(w_opp - 3.0) <= 0.5, "7 the wall opposite is still 3 mm thick: %.1f mm (want 3)" % w_opp)

	# 8 the top is still open
	var top_d: float = ray_first(Vector3(0.0, 0.5, 0.0), Vector3.DOWN)
	ok(absf(top_d - 497.0) <= 1.5, "8 the top is still open: a ray down the middle hits the floor at %.1f mm (want 497)" % top_d)

	# 9 the volume: outer - inner with the 9 mm wall, the 3 mm walls, and the open top
	var sz: Vector3 = bbox().size
	var wall_w: Array = [6.0, 3.0, 6.0]
	for ax in 3:
		if absf(n_side[ax]) > 0.5:
			wall_w[ax] = 12.0
	var want9: float = cup_vol(sz, wall_w)
	var v9: float = vol()
	ok(absf(v9 - want9) <= want9 * 0.02,
		"9 the volume %.0f mm3 = outer - inner (9 mm wall, 3 mm walls, open top) %.0f mm3 (within 2 pct)" % [v9, want9])
	await shot("02_wall6")

	# 10 the Extra wall drag is one undo step
	ok(u_w2 == u_w + 1, "10 the Extra wall drag adds exactly 1 undo step (undo %d -> %d)" % [u_w, u_w2])

	print("P022SHELLWALLS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


## a drag on the floor, a square 80 mm across, on the grid of the box
func drag_screen_box() -> void:
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.04)), scr(Vector3(0.04, 0.0, 0.04)))


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)
