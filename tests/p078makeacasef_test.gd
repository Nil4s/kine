extends SceneTree
## p078makeacasef (Friday plan item 78; Nick: monkey-brain easy): Make a case for this board. Parts > Boards > Raspberry Pi gives a box for the
## board: a 3 mm wall and floor, open at the top, four standoffs (5 mm across, 9 mm up) at the board's holes with a screw hole through each, two
## port openings in the +x wall, and a lid (3 mm) as its own plate beside the box. Arduino Uno switches the same case to the other board.
## Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Parts -> Boards -> Raspberry Pi -> Arduino Uno
## Bars (each one measured from the BUILT result: mesh rays, the replay bbox and volume, never from the code's own variables; the numbers
## below are the case's own dimensions for the Pi, 85 x 56 mm board, 3 mm wall, 1 mm clearance):
##   0 Parts > Boards, one click each: its two chips show
##   1 Raspberry Pi, one click: a case is on the floor: two bodies (the box and the lid), no build error
##   2 the bounding box: 196 x 26 x 64 mm (box 93 x 26 x 64 at x 0..93, lid 93 x 3 x 64 at x 103..196)
##   3 a standoff: a ray down beside its hole hits its top at 9 mm above the floor (21 mm from y = 30) (+-0.5)
##   4 the standoff's screw hole goes through the floor: a ray down its middle hits nothing
##   5 a port: a ray across the +x wall at a port's height passes it: first hit is the inside of the far wall, 110 mm (+-0.5)
##   6 the wall above the ports is solid: first hit at the outside of the +x wall, 20 mm (+-0.5)
##   7 the lid: a ray down onto it hits its top at 27 mm (3 mm lid) (+-0.5)
##   8 the lid's screw hole goes through: a ray down its middle hits nothing
##   9 the volume: shell 38694 + standoffs 308 - ports 900 + lid 17802 = 55904 mm3, within 2 pct
##  10 the Raspberry Pi pick is one undo step
##  11 Arduino Uno, one click: the case is the Uno's (bbox z 61.3 mm), still two bodies, no build error
##  12 the Uno pick is one undo step
## shots: C:/Temp/claude/p078makeacasef/

const SHOT_DIR := "C:/Temp/claude/p078makeacasef"
const DIRT := "user://p078makeacasef_test"

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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the built bounding box in mm
func bbox() -> AABB:
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func build_errors() -> int:
	return (pu().res.get("errors", {}) as Dictionary).size()


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


## every hit distance (mm, sorted, hits closer than 0.05 mm merged) of a ray from o (mm) along unit d through the built mesh (Moller-Trumbore)
func ray_all(o_mm: Vector3, d: Vector3) -> Array:
	var o := o_mm * Part.MM
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


## the nearest hit distance (mm) of a ray from o (mm) along d, or NAN when nothing is hit
func ray_first(o_mm: Vector3, d: Vector3) -> float:
	var h := ray_all(o_mm, d)
	return float(h[0]) if not h.is_empty() else NAN


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

	# the BUILDING card, one click: Easy Part on, empty
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

	# 0 Parts, then Boards: the two board chips show
	var parts: Button = root.find_child("easypart_chip_parts", true, false) as Button
	if parts != null:
		await click_ctl(parts)
	var boards: Button = root.find_child("easypart_lib_Boards", true, false) as Button
	if boards != null:
		await click_ctl(boards)
	var pi_b: Button = root.find_child("easypart_board_pi", true, false) as Button
	var uno_b: Button = root.find_child("easypart_board_uno", true, false) as Button
	ok(boards != null and pi_b != null and uno_b != null and pi_b.is_visible_in_tree() and uno_b.is_visible_in_tree(),
		"0 Parts > Boards shows the Raspberry Pi and Arduino Uno chips")

	# 1 Raspberry Pi: a case on the floor
	var u0: int = m.undo.size()
	if pi_b != null:
		await click_ctl(pi_b)
	await shot("01_pi_case")
	var bodies: int = int(pu().res.get("bodies", 0))
	ok(bodies == 2 and build_errors() == 0,
		"1 Raspberry Pi: a case on the floor, two bodies (box and lid), no build error (bodies %d, errors %d)" % [bodies, build_errors()])

	# 2 the bounding box: 196 x 26 x 64 mm
	var bb: AABB = bbox()
	ok(absf(bb.size.x - 196.0) <= 0.5 and absf(bb.size.y - 26.0) <= 0.5 and absf(bb.size.z - 64.0) <= 0.5,
		"2 bounding box %.1f x %.1f x %.1f mm (want 196 x 26 x 64)" % [bb.size.x, bb.size.y, bb.size.z])

	# 3 a standoff: beside its hole (x 7.5 + 1.8, z 7.5) a ray down hits the standoff top at 9 mm: 30 - 9 = 21 mm
	var st_d: float = ray_first(Vector3(9.3, 30.0, 7.5), Vector3.DOWN)
	ok(absf(st_d - 21.0) <= 0.5, "3 a standoff stands 9 mm up: a ray down beside its hole hits it at %.1f mm (want 21)" % st_d)

	# 4 the standoff's screw hole goes through the floor: a ray down the middle hits nothing
	var hole_d: float = ray_first(Vector3(7.5, 30.0, 7.5), Vector3.DOWN)
	ok(is_nan(hole_d), "4 the standoff's screw hole goes through: a ray down its middle hits nothing (got %s)" % str(hole_d))

	# 5 a port in the +x wall (board x 8..20 -> z 12..24, y 11..21 mm): a ray across it passes to the far wall at 110 mm
	var port_d: float = ray_first(Vector3(113.0, 16.0, 18.0), Vector3.LEFT)
	ok(absf(port_d - 110.0) <= 0.5, "5 a port: a ray across the +x wall at a port's height first hits the far wall at %.1f mm (want 110)" % port_d)

	# 6 above the ports the +x wall is solid: a ray across it hits the outside at 20 mm
	var wall_d: float = ray_first(Vector3(113.0, 24.0, 18.0), Vector3.LEFT)
	ok(absf(wall_d - 20.0) <= 0.5, "6 the wall above the ports is solid: first hit at %.1f mm (want 20)" % wall_d)

	# 7 the lid: a ray down onto it (x 130, z 32) hits its top at 3 mm: 30 - 3 = 27 mm
	var lid_d: float = ray_first(Vector3(130.0, 30.0, 32.0), Vector3.DOWN)
	ok(absf(lid_d - 27.0) <= 0.5, "7 the lid is 3 mm: a ray down onto it hits at %.1f mm (want 27)" % lid_d)

	# 8 the lid's screw hole (x 103 + 4 + 3.5, z 7.5) goes through
	var lhole_d: float = ray_first(Vector3(110.5, 30.0, 7.5), Vector3.DOWN)
	ok(is_nan(lhole_d), "8 the lid's screw hole goes through: a ray down its middle hits nothing (got %s)" % str(lhole_d))

	# 9 the volume: shell 38694 + standoffs 308 - ports 900 + lid 17802 = 55904 mm3
	var v9: float = vol()
	ok(absf(v9 - 55904.0) <= 55904.0 * 0.02, "9 the volume %.0f mm3 (want 55904 within 2 pct)" % v9)

	# 10 the pick is one undo step
	var u1: int = m.undo.size()
	ok(u1 == u0 + 1, "10 the Raspberry Pi pick is one undo step (undo %d -> %d)" % [u0, u1])

	# 11 Arduino Uno: the same case for the other board (bbox z 53.3 + 8 = 61.3 mm)
	if uno_b != null:
		await click_ctl(uno_b)
	await shot("02_uno_case")
	var bb2: AABB = bbox()
	var bodies2: int = int(pu().res.get("bodies", 0))
	ok(absf(bb2.size.z - 61.3) <= 0.5 and bodies2 == 2 and build_errors() == 0,
		"11 Arduino Uno: the case is 61.3 mm deep (%.1f), two bodies, no build error (bodies %d, errors %d)" % [bb2.size.z, bodies2, build_errors()])

	# 12 the Uno pick is one undo step
	var u2: int = m.undo.size()
	ok(u2 == u1 + 1, "12 the Uno pick is one undo step (undo %d -> %d)" % [u1, u2])

	print("P078MAKEACASEF TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
