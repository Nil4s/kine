extends SceneTree
## godot --path . --position 4000,4000 -s tests/etri_test.gd     (ETRI: Easy Part Pointy triangle: scripts/easy_part.gd; needs the CAD DLL and a window)
## Pointy is a third Draw shape chip (a triangle). The drag is the box corner to corner (snapped like Box): the base runs along the drag start
## side, the point sits at the middle of the far edge (the drag end side). It is three line entities. Works on the floor and on a face.
## Real clicks and drags at 1280 x 720, from an empty Easy part.
## Bars (bar 1 FAILED on the old code: there was no Pointy chip):
##   1 CHIP   the Pointy chip exists after Draw shape (easypart_shape_pointy) and a click selects it
##   2 FLOOR  a Pointy drag on the floor, Pull it up (20 mm): one body, volume = half the box area x 20 mm within 1 pct
##   3 HOUSE  a Box on the floor pulled up 60 mm, then a Pointy drawn on its FRONT face spanning its width (base on the wall top), pulled
##            60 mm back into the house (a Pointy on a face pulls INTO the solid): one body, the body top is above the walls (the roof point),
##            and the roof runs the house depth (z -30..30 mm)
##   4 UNDO   each press is one undo step: the house steps undo one at a time back to the empty part, and redo back
## Shots: C:/Temp/claude/etri/shot.png (the house, a 3/4 view), C:/Temp/claude/etri/front.png (the house from the front)
const SHOT := "C:/Temp/claude/etri"
const DIRT := "user://etri_test"

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


## a real drag: press at a, move in steps to b (held), release
func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of the slider knob to value v (held with the left button, 24 mouse steps)
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
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
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the replay volume in mm3
func vol() -> float:
	var pu: PartUI = m.bld.part
	return float(pu.res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the points in mm of the last sketch entities (a, b, c)
func last_sketch_pts() -> Array:
	var out := []
	for f in m.S.part["features"]:
		if String(f["t"]) == "sketch":
			out = []
			for e in f["ents"]:
				for k in ["a", "b", "c"]:
					if e.has(k):
						out.append(Vector2(float(e[k][0]), float(e[k][1])))
	return out


func tweak_slider() -> HSlider:
	var ep = m.bld.part.ep
	var tw: HSlider = null
	for r in ep.rows:
		if String(r["kind"]) == "tweak":
			tw = r["slider"]
	return tw


## arms Draw shape (a press on the button when it is already armed would disarm it)
func arm_draw(ep) -> void:
	if String(ep.armed) != "draw":
		await click_ctl(ep.make_btns["draw"])


func fresh_part(pu: PartUI) -> void:
	m.S.part = Part.make("Pointy test")
	pu.upto = -1
	pu.sync()
	await idle(3)


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	await fresh_part(pu)

	# 1 CHIP
	await arm_draw(ep)
	var pb: Button = ep.shape_btns.get("pointy")
	var has_chip := pb != null and pb.name == "easypart_shape_pointy" and pb.is_visible_in_tree()
	ok(has_chip, "1a CHIP the Pointy chip exists after Draw shape (easypart_shape_pointy)")
	if has_chip:
		await click_ctl(pb)
	ok(has_chip and String(ep.shape) == "pointy", "1b CHIP a click on Pointy selects it (shape %s)" % String(ep.shape))

	# 2 FLOOR: a Pointy drag on the floor, Pull it up 20 mm
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = 35.0
	m.yaw = 0.0
	m._cam()
	await idle(60)
	await fresh_part(pu)
	await arm_draw(ep)
	await click_ctl(ep.shape_btns["pointy"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	var pts2 := last_sketch_pts()
	var w2 := 0.0
	var h2 := 0.0
	var sk_ok := pts2.size() == 6   # three lines: a and b of each (the corners twice)
	if sk_ok:
		var xs := []
		var ys := []
		for q in pts2:
			xs.append(q.x)
			ys.append(q.y)
		w2 = xs.max() - xs.min()
		h2 = ys.max() - ys.min()
	ok(sk_ok and w2 > 5.0 and h2 > 5.0, "2a FLOOR the sketch is three lines (6 corner points) on a %.1f x %.1f mm box" % [w2, h2])
	await click_ctl(ep.make_btns["pull"])
	await idle(3)
	var v2 := vol()
	var want2 := 0.5 * w2 * h2 * 20.0
	ok(int(pu.res.get("bodies", 0)) == 1, "2b FLOOR one body after Pull it up (%d)" % int(pu.res.get("bodies", 0)))
	ok(absf(v2 - want2) <= want2 * 0.01, "2c FLOOR volume = half the box area x 20 mm within 1 pct: %.0f mm3, want %.0f" % [v2, want2])

	# 3 HOUSE: a Box on the floor pulled up 60 mm, a Pointy on its front face, pulled out 60 mm
	await fresh_part(pu)
	m.target = Vector3(0.0, 0.03, 0.0)
	m.pitch = 5.0
	m.yaw = 0.0
	m._cam()
	await idle(60)
	var u0: int = m.undo.size()
	await arm_draw(ep)
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(-0.05, 0.0, -0.03)), scr(Vector3(0.05, 0.0, 0.03)))
	await click_ctl(ep.make_btns["pull"])
	var tw := tweak_slider()
	if tw != null:
		await drag_slider(tw, 6.0)   # 6 cm: the walls
	await idle(3)
	await idle(60)   # the Easy camera eases to frame the new box: the screen points below are taken after it settles
	var bb_wall: AABB = pu.res.get("aabb", AABB())
	var wall_top := bb_wall.end.y / Part.MM
	ok(absf(wall_top - 60.0) < 0.6, "3a HOUSE the box is pulled up to 60 mm (top %.1f mm)" % wall_top)
	# the front face: +Z (the camera side at yaw 0); its top edge is at y = 60 mm
	await arm_draw(ep)
	await click_ctl(ep.shape_btns["pointy"])
	m.target = Vector3(0.0, 0.1, 0.0)   # the look-at point above the walls: the house sits low, its roof clear of the chip row
	m.pitch = 5.0
	m.yaw = 0.0
	m._cam()
	await idle(60)   # the front view of the house, settled
	var dr0 := scr(Vector3(-0.045, 0.058, 0.03))
	var dr1 := scr(Vector3(0.045, 0.075, 0.03))   # the apex 15 mm above the wall top (a drag end over the chip row would not count)
	await drag_screen(dr0, dr1)
	ok(not ep._over_ui(dr1), "3b0 HOUSE the roof drag ends on the grid (%s)" % str(dr1))
	var said3: String = ep.hint_l.text
	var pl_n := Part.count_of(m.S.part, "plane")
	ok(pl_n == 1, "3b HOUSE one plane feature for the roof face (%d) [%s]" % [pl_n, said3])
	await click_ctl(ep.make_btns["pull"])
	var tw2 := tweak_slider()
	if tw2 != null:
		await drag_slider(tw2, 6.0)   # 6 cm: the house depth
	await idle(3)
	var bb_h: AABB = pu.res.get("aabb", AABB())
	var roof_top := bb_h.end.y / Part.MM
	print("house: top %.1f mm, bodies %d, z %.1f..%.1f" % [roof_top, int(pu.res.get("bodies", 0)), bb_h.position.z / Part.MM, bb_h.end.z / Part.MM])
	ok(int(pu.res.get("bodies", 0)) == 1, "3c HOUSE one body (%d)" % int(pu.res.get("bodies", 0)))
	ok(roof_top > wall_top + 10.0, "3d HOUSE the roof point is above the walls: body top %.1f mm, walls %.1f mm" % [roof_top, wall_top])
	ok(absf(bb_h.position.z / Part.MM + 30.0) < 0.6 and absf(bb_h.end.z / Part.MM - 30.0) < 0.6,
		"3e HOUSE the roof runs the house depth across the walls: z %.1f..%.1f mm (want -30..30)" % [bb_h.position.z / Part.MM, bb_h.end.z / Part.MM])
	m.target = Vector3(0.0, 0.05, 0.0)
	m.pitch = 18.0
	m.yaw = 35.0
	m._cam()
	await shot("shot")
	m.yaw = 0.0
	m.pitch = 5.0
	m._cam()
	await shot("front")

	# 4 UNDO: the house presses each undo one step, back to the empty part; then redo
	var steps: int = m.undo.size() - u0
	var n_undo := 0
	while m.undo.size() > u0 and n_undo < 20:
		m._undo()
		await idle(3)
		n_undo += 1
	ok(n_undo == steps and m.undo.size() == u0 and Part.count_of(m.S.part, "sketch") == 0,
		"4a UNDO one press per step: %d presses for %d steps, back to the empty part" % [n_undo, steps])
	for i in steps:
		m._redo()
		await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 1, "4b UNDO redo brings the house back in %d steps (bodies %d)" % [steps, int(pu.res.get("bodies", 0))])

	print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
