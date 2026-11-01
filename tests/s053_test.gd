extends SceneTree
## s053 (Friday plan 53) MOVE A PIECE BY DRAG with snap-to-face. Real mouse drags at 1280x720 from the real start screen (a blank Easy Part).
## Pieces: a 40x40x10 plate and a 20 mm cube (record steps, exact sizes); every move is a real press-drag-release.
## Bars: cube dropped on the plate's top: bottom at 10.000 (0.01), fully inside the top face, x/z on the face are whole mm, ONE undo step "Moved a piece";
## Ctrl+Z puts it back exactly; dropped on the plate's side face: gap 0.000 (0.01), the other two coordinates whole mm; ghost visible mid-drag;
## a drag on empty floor orbits/pans as before and moves nothing.
## shots: C:/Temp/claude/s053/ghost.png (mid-drag), top.png, side.png
const SHOT := "C:/Temp/claude/s053"
const DIRT := "user://s053_test"
const HALF_MM := 0.0005

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


var last_p := Vector2.ZERO


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = p - last_p
	last_p = p
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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)



func box_of(i: int) -> Array:
	var faces: Array = Part.body_faces(m.S.part, -1)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in faces[i]:
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo * 1000.0, hi * 1000.0]   # mm


func whole(v: float) -> bool:
	return absf(v - roundf(v)) < 0.005


func rect_piece(rec: Dictionary, a: Vector2, b: Vector2, h: float) -> void:
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [a.x, a.y], "b": [b.x, b.y]}], "dims": []})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": h, "both": false, "op": "new"}))


func reset_pieces() -> void:
	var rec := Part.make("Part")
	rect_piece(rec, Vector2(-20, -20), Vector2(20, 20), 10.0)
	rect_piece(rec, Vector2(80, -10), Vector2(100, 10), 20.0)
	m.S.part = rec
	pu().sync()


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
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 Easy Part on (page %s)" % m.cur_page)
	m.target = Vector3.ZERO
	m.pitch = -30.0
	m.yaw = 25.0
	m._cam()
	await idle(40)
	reset_pieces()
	await idle(40)
	var nb: int = Part.body_faces(m.S.part, -1).size()
	var pl0 := box_of(0)
	var cu0 := box_of(1)
	ok(nb == 2 and absf(float(pl0[1].y) - 10.0) < 0.01 and absf(float(cu0[1].y) - 20.0) < 0.01, "setup: 2 pieces, plate top y %.3f, cube top y %.3f (mm, y is up)" % [pl0[1].y, cu0[1].y])
	if nb != 2:
		print("s053: 1 fail")
		quit(1)
		return

	# 1 drop on the top face, a spot that is not on the grid (12.3, 7.1 mm from the middle)
	var grab := Vector3(0.09, 0.020, 0.0)
	var drop := Vector3(0.0123, 0.010, 0.0071)
	var u0: int = m.undo.size()
	await ev_move(scr(grab), false)
	await ev_mouse(scr(grab), true)
	for i in range(1, 9):
		await ev_move(scr(grab).lerp(scr(drop), i / 9.0))
	await ev_move(scr(drop))
	await idle(3)
	await shot("ghost")
	var ghost_vis: bool = pu().ep._mv_layer != null and not (pu().ep._mv.get("plan", {}) as Dictionary).is_empty()
	ok(ghost_vis, "1 mid-drag over the plate: a ghost plan exists")
	await ev_mouse(scr(drop), false)
	await idle(10)
	var cu := box_of(1)
	var pl := box_of(0)
	ok(absf(float(cu[0].y) - 10.0) < 0.01, "2 cube bottom at y = %.4f (want 10.000)" % cu[0].y)
	var inside: bool = cu[0].x >= pl[0].x - 0.01 and cu[1].x <= pl[1].x + 0.01 and cu[0].z >= pl[0].z - 0.01 and cu[1].z <= pl[1].z + 0.01
	ok(inside, "3 cube inside the plate's top face: x %.3f..%.3f z %.3f..%.3f" % [cu[0].x, cu[1].x, cu[0].z, cu[1].z])
	ok(whole(float(cu[0].x)) and whole(float(cu[0].z)), "4 x/z on the face are whole mm: %.4f, %.4f" % [cu[0].x, cu[0].z])
	var hint := String(m.undo[-1].get("hint", "")) if m.undo.size() > 0 else ""
	ok(m.undo.size() == u0 + 1 and hint.findn("Moved a piece") >= 0, "5 ONE undo step: %d -> %d, named '%s'" % [u0, m.undo.size(), hint])
	await shot("top")
	await click_ctl(pu().ep.undo_btn)
	await idle(10)
	var cub := box_of(1)
	var same: bool = (cub[0] as Vector3).distance_to(cu0[0]) < 0.001 and (cub[1] as Vector3).distance_to(cu0[1]) < 0.001
	ok(same and m.undo.size() == u0, "6 Undo puts the cube back exactly: min %s (was %s)" % [str(cub[0]), str(cu0[0])])

	# 2 side face: the plate's side the camera sees
	m.yaw = 0.0
	m.pitch = -14.0
	m.dist = 1.0
	m.target = Vector3(0.05, 0.005, 0.0)
	m._cam()
	await idle(20)
	var sgn := 1.0 if m.cam.global_position.z > 0.0 else -1.0
	var grab2 := Vector3(0.09, 0.010, 0.010)
	print("  cam at %s dist %.2f grab px %s" % [str(m.cam.global_position), m.dist, str(scr(grab2))])
	var drop2 := Vector3(0.0043, 0.0065, sgn * 0.020)
	await drag_screen(scr(grab2), scr(drop2))
	await idle(10)
	var cs := box_of(1)
	var gap: float = float(cs[0].z) - 20.0 if sgn > 0.0 else -20.0 - float(cs[1].z)
	print("  side: cam x %.3f sgn %.0f drop px %s msg '%s' cube %s" % [m.cam.global_position.x, sgn, str(scr(drop2)), String(pu().ep.msg), str(cs)])
	ok(absf(gap) < 0.01, "7 side drop: gap to the plate's face %.4f (want 0.000)" % gap)
	ok(whole(float(cs[0].x)) and whole(float(cs[0].y)), "8 side drop: x/y on the face are whole mm: %.4f, %.4f" % [cs[0].x, cs[0].y])
	await shot("side")
	await click_ctl(pu().ep.undo_btn)
	await idle(10)

	# 3 empty floor: a left drag moves nothing and adds no step; a right drag still orbits (the camera is not ours)
	var steps: int = m.undo.size()
	await drag_screen(Vector2(200, 640), Vector2(300, 600))
	await idle(5)
	ok(m.undo.size() == steps and (box_of(1)[0] as Vector3).distance_to(cu0[0]) < 0.001, "9 a left drag on empty floor: no undo step, cube unmoved")
	var yaw0: float = m.yaw
	var rp := Vector2(200, 640)
	var er := InputEventMouseButton.new()
	er.button_index = MOUSE_BUTTON_RIGHT
	er.pressed = true
	er.position = rp
	er.global_position = rp
	er.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(er, true)
	await process_frame
	for i in range(1, 9):
		var em := InputEventMouseMotion.new()
		em.position = rp + Vector2(10 * i, 0)
		em.global_position = em.position
		em.relative = Vector2(10, 0)
		em.button_mask = MOUSE_BUTTON_MASK_RIGHT
		root.push_input(em, true)
		await process_frame
	er = er.duplicate()
	er.pressed = false
	er.button_mask = 0
	root.push_input(er, true)
	await idle(3)
	ok(absf(m.yaw - yaw0) > 1.0, "9b a right drag on empty floor still orbits (yaw %.2f -> %.2f)" % [yaw0, m.yaw])

	# 4 a click on a piece still picks it
	await click_at(scr(Vector3(0.09, 0.020, 0.0)))
	await idle(6)
	ok(bool(pu().ep.get("del_on")), "10 a click (no drag) on a piece still picks it")

	print("s053: %d fail" % fails)
	quit(1 if fails > 0 else 0)
