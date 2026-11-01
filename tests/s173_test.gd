extends SceneTree
## godot --path . --position 4000,4000 -s tests/s173_test.gd     (Friday plans 173 + 174: touch / pen / gamepad; scripts/touch_input.gd; needs the CAD DLL)
## Bars (events injected with Input.parse_input_event; measured from the camera and from the sketch record):
##   1 DRAW   a one-finger drag of 100 px on the Line tool adds a line with the same endpoints as the mouse drag (within 0.5 mm)
##   2 ORBIT  two fingers dragged 200 px sideways turn the camera yaw by the same angle as a right-mouse drag of 200 px (within 1 deg)
##   3 PINCH  fingers 100 -> 200 px apart: the camera distance shrinks (factor printed)
##   4 TAP    a two-finger tap = ONE undo step taken back
##   5 PAD    left stick x = 1.0 for 1 s turns yaw by > 30 deg; 0.1 (inside the 0.15 deadzone) turns 0; triggers zoom, right stick pans, A fits, B goes back
##   6 PEN    a pen pressure of 0.3 gives a smaller sculpt stroke than full pressure
##   7 MOUSE  the mouse still draws (bar 1 uses it) and a left click on a bar button still works
## Shots: C:/Temp/claude/s173/touch_line.png, orbit.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s173"
const DIRT := "user://s173_test"
## Input.parse_input_event takes WINDOW pixels (the window is 1600 x 900 here, the viewport 1280 x 720): the helpers multiply viewport positions by this
var RATIO := 1.25
var pu: PartUI
var ep


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, btn := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true, rel := Vector2.ZERO, btn := MOUSE_BUTTON_MASK_LEFT, pr := 0.0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.pressure = pr
	if held:
		e.button_mask = btn
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


func touch(i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p * RATIO
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func tdrag(i: int, p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p * RATIO
	e.relative = rel * RATIO
	Input.parse_input_event(e)


func pad(axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)
	await process_frame


func wait_s(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func last_line() -> Array:
	var sks: Array = m.S.part["features"].filter(func(f): return f["t"] == "sketch")
	if sks.is_empty():
		return []
	var ent: Dictionary = sks[-1]["ents"][0]
	return [ent.get("k", ""), ent.get("a", []), ent.get("b", [])]


func arm_line() -> void:
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["line"])


func yawd(a: float, b: float) -> float:
	return wrapf(b - a, -180.0, 180.0)


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
	print("     window %s, viewport %s" % [root.size, root.get_visible_rect().size])
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var cam: Camera3D = m.cam
	var ti = m.touch_in
	RATIO = 1.25
	ok(ti != null and Input.emulate_mouse_from_touch == false, "0 the touch handler is on main and the touch-to-mouse emulation is off")

	# 1 DRAW: mouse first (the reference), then one finger
	await arm_line()
	var s0 := cam.unproject_position(Vector3(1.2, 0.0, 0.0))
	var s1 := s0 + Vector2(100, 0)
	var ub: int = m.undo.size()
	var cam0 := [m.yaw, m.pitch, float(m.dist), m.target]   # the same camera for the mouse drag and the finger drag (a line's first step eases it)
	await ev_move(s0, false)
	await ev_mouse(s0, true)
	for k in 5:
		await ev_move(s0.lerp(s1, (k + 1) / 5.0))
	await ev_mouse(s1, false)
	await idle(3)
	var ml := last_line()
	ok(m.undo.size() == ub + 1 and ml.size() == 3 and ml[0] == "line", "7 MOUSE: a 100 px drag on the Line tool adds a line, ONE undo step: %s" % str(ml))
	m._undo()
	await idle(3)
	ok(m.undo.size() == ub, "   undo takes it back")
	await arm_line()
	m.yaw = cam0[0]
	m.pitch = cam0[1]
	m.dist = cam0[2]
	m.target = cam0[3]
	ep._ease = {}
	m._cam()
	await idle(2)
	await touch(0, s0, true)
	for k in 5:
		var p := s0.lerp(s1, (k + 1) / 5.0)
		tdrag(0, p, Vector2(20, 0))
		await process_frame
	await shot("touch_line")
	await touch(0, s1, false)
	await idle(3)
	var tl := last_line()
	var dmax := 99.0
	if tl.size() == 3 and ml.size() == 3 and tl[0] == "line":
		dmax = 0.0
		for key in [1, 2]:
			dmax = maxf(dmax, Vector2(tl[key][0], tl[key][1]).distance_to(Vector2(ml[key][0], ml[key][1])))
	ok(m.undo.size() == ub + 1 and dmax <= 0.5, "1 DRAW: one-finger 100 px drag: line %s vs mouse %s, endpoints differ by %.3f mm (bar 0.5), ONE undo step" % [str(tl), str(ml), dmax])

	# 4 TAP: the line above is one undo step; a two-finger tap takes it back
	var n0: int = m.undo.size()
	await touch(0, Vector2(500, 400), true)
	await touch(1, Vector2(560, 400), true)
	await touch(1, Vector2(560, 400), false)
	await touch(0, Vector2(500, 400), false)
	await idle(3)
	ok(m.undo.size() == n0 - 1 and ti.taps == 1, "4 TAP: a two-finger tap = ONE undo (%d -> %d steps)" % [n0, m.undo.size()])

	# 1b a second finger after the first has started a sketch drops the sketch (no line is written)
	await arm_line()
	n0 = m.undo.size()
	await touch(0, s0, true)
	for k in 3:
		tdrag(0, s0.lerp(s1, (k + 1) / 5.0), Vector2(20, 0))
		await process_frame
	var had: bool = not ep._draft.is_empty()
	await touch(1, Vector2(900, 500), true)
	await touch(1, Vector2(900, 500), false)
	await touch(0, s1, false)
	await idle(3)
	ok(had and ep._draft.is_empty() and m.undo.size() == n0, "1b a second finger lands mid-sketch: the sketch is dropped, no step written (draft was open %s)" % had)

	# 2 ORBIT: right mouse drag of 200 px, then two fingers
	m.dist = 3.0
	m._cam()
	var y0: float = m.yaw
	var p0: float = m.pitch
	if ep.armed != "":
		await click_ctl(ep.make_btns["draw"])
	await ev_mouse(s0, true, MOUSE_BUTTON_RIGHT)
	await ev_move(s0 + Vector2(200, 0), true, Vector2(200, 0), MOUSE_BUTTON_MASK_RIGHT)
	await ev_mouse(s0 + Vector2(200, 0), false, MOUSE_BUTTON_RIGHT)
	var dy_mouse := yawd(y0, m.yaw)
	m.yaw = y0
	m.pitch = p0
	m._cam()
	await idle(2)
	await touch(0, Vector2(300, 500), true)
	await touch(1, Vector2(400, 500), true)
	for k in 10:
		var dx := 20.0 * (k + 1)
		tdrag(0, Vector2(300 + dx, 500), Vector2(20, 0))
		tdrag(1, Vector2(400 + dx, 500), Vector2(20, 0))
		await process_frame
	await shot("orbit")
	await touch(0, Vector2(500, 500), false)
	await touch(1, Vector2(600, 500), false)
	var dy_touch := yawd(y0, m.yaw)
	ok(absf(dy_touch - dy_mouse) <= 1.0 and absf(dy_mouse) > 30.0, "2 ORBIT: right-mouse 200 px = %.2f deg, two fingers 200 px = %.2f deg (bar within 1)" % [dy_mouse, dy_touch])

	# 3 PINCH
	m.dist = 3.0
	m._cam()
	var d0: float = m.dist
	var yb: float = m.yaw
	await touch(0, Vector2(590, 400), true)
	await touch(1, Vector2(690, 400), true)
	for k in 10:
		var o := 5.0 * (k + 1)
		tdrag(0, Vector2(590 - o, 400), Vector2(-5, 0))
		tdrag(1, Vector2(690 + o, 400), Vector2(5, 0))
		await process_frame
	await touch(0, Vector2(540, 400), false)
	await touch(1, Vector2(740, 400), false)
	var d1: float = m.dist
	print("     pinch 100 -> 200 px: camera distance %.3f -> %.3f, factor %.3f" % [d0, d1, d1 / d0])
	ok(d1 < d0 * 0.6 and absf(yawd(yb, m.yaw)) < 0.01, "3 PINCH: distance shrank by a factor %.3f (yaw moved %.3f deg)" % [d1 / d0, yawd(yb, m.yaw)])

	# 5 PAD
	var y1: float = m.yaw
	await pad(JOY_AXIS_LEFT_X, 0.1)
	await wait_s(1.0)
	var inside := absf(yawd(y1, m.yaw))
	ok(inside < 0.001, "5 PAD: stick 0.1 (inside the 0.15 deadzone) for 1 s turned %.4f deg" % inside)
	await pad(JOY_AXIS_LEFT_X, 1.0)
	var t0 := Time.get_ticks_msec()
	await wait_s(1.0)
	await pad(JOY_AXIS_LEFT_X, 0.0)
	var full := absf(yawd(y1, m.yaw))
	ok(full > 30.0, "5 PAD: left stick x = 1.0 for %.2f s turned yaw %.1f deg (bar > 30)" % [(Time.get_ticks_msec() - t0) / 1000.0, full])
	var d2: float = m.dist
	await pad(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await wait_s(0.5)
	await pad(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	ok(m.dist < d2 * 0.9, "5 PAD: right trigger 0.5 s zooms in, distance %.3f -> %.3f" % [d2, m.dist])
	var tg0: Vector3 = m.target
	await pad(JOY_AXIS_RIGHT_X, 1.0)
	await wait_s(0.5)
	await pad(JOY_AXIS_RIGHT_X, 0.0)
	ok(m.target.distance_to(tg0) > 0.01, "5 PAD: right stick pans the look-at point by %.3f m" % m.target.distance_to(tg0))
	var pre := [m.yaw, m.pitch, m.dist, m.target]
	var ja := InputEventJoypadButton.new()
	ja.button_index = JOY_BUTTON_A
	ja.pressed = true
	Input.parse_input_event(ja)
	await idle(3)
	var fitted: bool = absf(m.dist - pre[2]) > 0.001 or m.target.distance_to(pre[3]) > 0.001
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_B
	jb.pressed = true
	Input.parse_input_event(jb)
	await idle(3)
	ok(fitted and absf(m.dist - pre[2]) < 0.001 and m.target.distance_to(pre[3]) < 0.001, "5 PAD: A fits the view, B brings the camera back (dist %.3f, fitted %s)" % [m.dist, fitted])

	# 7 MOUSE: a click on a bar button still works
	await click_ctl(ep.make_btns["draw"])
	ok(ep.armed != "", "7 MOUSE: a left click on Draw shape still arms it (armed '%s')" % ep.armed)

	# 6 PEN: pressure scales a sculpt stroke
	if ep.armed != "":
		await click_ctl(ep.make_btns["draw"])
	m._sculpt_start()
	await idle(4)
	var ui = m.ksc
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var c2: Camera3D = m.cam
	var cs := c2.unproject_position(wc)
	var peaks := []
	for pr in [1.0, 0.3]:
		var v0 = ui.mesh.verts.duplicate()
		await ev_move(cs + Vector2(-30, 0), false)
		await ev_mouse(cs + Vector2(-30, 0), true)
		for k in 8:
			await ev_move(cs + Vector2(-30 + 60.0 * (k + 1) / 8.0, 0), true, Vector2(7.5, 0), MOUSE_BUTTON_MASK_LEFT, pr)
		await ev_mouse(cs + Vector2(30, 0), false)
		await idle(2)
		var pk := 0.0
		for v in v0.size():
			pk = maxf(pk, (ui.mesh.verts[v] - v0[v]).length())
		peaks.append(pk)
		m._undo()
		await idle(3)
	print("     pen: peak move full pressure %.3f mm, pressure 0.3 %.3f mm" % [peaks[0] * 1000.0, peaks[1] * 1000.0])
	ok(peaks[0] > 0.0 and peaks[1] < peaks[0] and peaks[1] > 0.0 and ti.pen_pressure > 0.0, "6 PEN: pressure 0.3 stroke peak %.3f mm vs full %.3f mm (ratio %.2f)" % [peaks[1] * 1000.0, peaks[0] * 1000.0, peaks[1] / maxf(peaks[0], 1e-9)])
	print("s173: %d fail" % fails)
	quit(1 if fails > 0 else 0)
