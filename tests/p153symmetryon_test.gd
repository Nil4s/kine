extends SceneTree
## P153 SYMMETRY ON BY DEFAULT (Friday plan item 153; Nick: "Symmetry on by default with a clear One side only toggle"): on the Easy Part
## shape row, the chip "One side only" is OFF, so Symmetry is ON by default: a shape drawn on one side of the middle line comes with its
## copy on the other side, in the same Draw shape step. Press the chip and only the shape drawn is made. Real clicks at 1280 x 720 from
## the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Draw shape, Box -> a drag on the floor from x 10 mm to 70 mm (default, no chip press) -> Pull it up
##   -> One side only (chip, on) -> Draw shape, Box -> a drag on the right at z 120..160 mm -> Pull it up -> One side only (chip, off)
##   -> Draw shape, Box -> a drag on the right at z 200..240 mm -> Pull it up -> Draw shape, Box across the middle line -> Pull it up
## Bars (measured from the BUILT result: pieces, bbox in mm, rays on the built mesh, the undo list; never from the code's own variables;
## the drags and the chip are real input):
##   0 the BUILDING card, one click: Easy Part on, empty part, the chip One side only is not pressed
##   1 the default drag on one side adds exactly 1 undo step
##   2 Pulled up with no chip pressed: two pieces, mirror images across the middle (bbox symmetric about x = 0 within 1 mm, 140 mm wide +-2)
##   3 rays down at x = +50 and x = -50 mm (z 0) hit the same top, 20 mm high (within 1 mm, from 500 mm)
##   4 the middle line stays open: a ray down at x = 0 hits nothing
##   5 One side only pressed: the chip is pressed and the words say it is on
##   6 a drag on the right with the chip on adds exactly 1 undo step; Pulled up gives 3 pieces; nothing at x = -50 mm, z 140 mm; the top
##     at x = +40 mm, z 140 mm is 20 mm high (+-1)
##   7 the chip pressed again: not pressed, the words say symmetry is on; a drag at z 200..240 mm, Pulled up, gives its copy: a top at
##     x = -50 mm, z 220 mm, 20 mm high (+-1), 4 pieces
##   8 a shape across the middle line keeps no copy: 1 undo step, 5 pieces in all, bbox still symmetric about x = 0 (+-1 mm)
## shots: C:/Temp/claude/p153symmetryon/


const SHOT_DIR := "C:/Temp/claude/p153symmetryon"
const DIRT := "user://p153symmetryon_test"

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


## a held drag from a to b (screen px); the shot is taken while the button is still down (the live copy shows there)
func drag_screen(a: Vector2, b: Vector2, nm := "") -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await idle(3)
	if nm != "":
		await shot(nm)
	await ev_mouse(b, false)
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


## the number of separate pieces in the built mesh: triangles that share a welded vertex are one piece
func pieces() -> int:
	var tris := world_tris()
	var par := {}
	for k in range(0, tris.size() - 2, 3):
		var ks: Array = []
		for j in 3:
			var v := tris[k + j]
			ks.append(str(Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))))
		for j in 3:
			par[ks[j]] = par.get(ks[j], ks[j])
		for j in [1, 2]:
			var ra := _root(par, ks[0])
			var rb := _root(par, ks[j])
			if ra != rb:
				par[rb] = ra
	var roots := {}
	for key in par:
		roots[_root(par, key)] = true
	return roots.size()


func _root(par: Dictionary, k: String) -> String:
	while par[k] != k:
		k = par[k]
	return k


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
	var chip: Button = ep().one_side_btn
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0 and chip != null and not chip.button_pressed,
		"0 BUILDING card, one click -> Easy Part on, empty; the chip One side only is not pressed (page %s)" % m.cur_page)

	# 1 Draw shape, Box, then a drag on the floor on the right of the middle line (x 10 to 70 mm, z -30 to 30 mm): no chip press, one undo step
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	var u_draw: int = m.undo.size()
	await drag_screen(scr(Vector3(0.01, 0.0, -0.03)), scr(Vector3(0.07, 0.0, 0.03)), "10_default_live")
	var u_drawn: int = m.undo.size()
	ok(u_drawn == u_draw + 1, "1 the default drag on one side adds exactly 1 undo step (undo %d -> %d)" % [u_draw, u_drawn])

	# 2 Pull it up: two solids, mirror images across the middle line (the copy came in the same step)
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	var bb: AABB = bbox()
	var pc: int = pieces()
	ok(pc == 2 and absf(bb.position.x + bb.end.x) <= 1.0 and absf(bb.size.x - 140.0) <= 2.0,
		"2 Pulled up with no chip: two pieces, mirror images across the middle (pieces %d, x from %.1f to %.1f mm, want 140 wide)" % [pc, bb.position.x, bb.end.x])
	await shot("11_pulled_default")

	# 3 rays down at x = +50 and -50 mm from 500 mm: the same top, 20 mm high
	var d_pos: float = ray_first(Vector3(0.05, 0.5, 0.0), Vector3.DOWN)
	var d_neg: float = ray_first(Vector3(-0.05, 0.5, 0.0), Vector3.DOWN)
	ok(absf(d_pos - d_neg) <= 0.5 and absf((500.0 - d_pos) - 20.0) <= 1.0,
		"3 rays at x = +50 and -50 mm hit the same top, 20 mm high: %.1f and %.1f mm from 500 (want 480, the same)" % [d_pos, d_neg])

	# 4 the middle line stays open
	var d_mid: float = ray_first(Vector3(0.0, 0.5, 0.0), Vector3.DOWN)
	ok(is_nan(d_mid), "4 the middle line stays open: a ray down at x = 0 hits nothing (%s)" % str(d_mid))

	# 5 One side only: the chip pressed, the words say it is on (the chip sits on the shape row: press Draw shape first)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(chip)
	ok(chip.button_pressed and String(ep().msg).to_lower().contains("one side only"),
		"5 One side only: the chip is pressed and the words say it is on (pressed %s, words: %s)" % [str(chip.button_pressed), ep().msg])

	# 6 a box on the right at z 120 to 160 mm: one undo step, no copy on the left
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	var u_b: int = m.undo.size()
	await drag_screen(scr(Vector3(0.01, 0.0, 0.12)), scr(Vector3(0.07, 0.0, 0.16)), "12_one_side_live")
	var u_a: int = m.undo.size()
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	var pc3: int = pieces()
	var d_left: float = ray_first(Vector3(-0.05, 0.5, 0.14), Vector3.DOWN)
	var d_right: float = ray_first(Vector3(0.04, 0.5, 0.14), Vector3.DOWN)
	ok(u_a == u_b + 1 and pc3 == 3 and is_nan(d_left) and absf((500.0 - d_right) - 20.0) <= 1.0,
		"6 One side only: 1 undo step, 3 pieces, nothing at x = -50 mm (%s), the top at x = +40 mm 20 mm high (%.1f mm from 500); pieces %d" % [str(d_left), d_right, pc3])

	# 7 the chip off: the words say symmetry is on; a box at z 200 to 240 mm gets its copy (2 pieces)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(chip)
	var off_ok := not chip.button_pressed and String(ep().msg).to_lower().contains("symmetry is on")
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(0.01, 0.0, 0.20)), scr(Vector3(0.07, 0.0, 0.24)))
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	var pc4: int = pieces()
	var d_copy: float = ray_first(Vector3(-0.05, 0.5, 0.22), Vector3.DOWN)
	ok(off_ok and pc4 == 5 and absf((500.0 - d_copy) - 20.0) <= 1.0,
		"7 the chip off: symmetry is on again (words: %s); its copy is built: a top at x = -50 mm, z 220 mm, 20 mm high (%.1f mm from 500); pieces %d" % [ep().msg, d_copy, pc4])
	await shot("13_symmetry_back")

	# 8 a shape across the middle line: no copy, one undo step, one piece across x = 0
	var u_c: int = m.undo.size()
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(-0.02, 0.0, -0.22)), scr(Vector3(0.02, 0.0, -0.18)))
	var u_d: int = m.undo.size()
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	var pc5: int = pieces()
	var bb2: AABB = bbox()
	ok(u_d == u_c + 1 and pc5 == 6 and absf(bb2.position.x + bb2.end.x) <= 1.0,
		"8 a shape across the middle line keeps no copy: 1 undo step, 6 pieces in all (pieces %d), bbox still symmetric about x = 0 (%.1f to %.1f mm)" % [pc5, bb2.position.x, bb2.end.x])

	print("P153SYMMETRYON TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
