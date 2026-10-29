extends SceneTree
## EREPEATUP (Nick 2026-10-28: "free 3D building"): Easy Part's Repeat it copies sideways only; a beginner building a wall shelf needs the copies stacked UP.
## A plate from the BUILDING card by real clicks at 1280 x 720: draw a floor rectangle 300 x 120 mm, Pull it up 15 mm, Repeat it (three copies, sideways),
## then the Up button on the Repeat it row stacks the same three copies upward.
## godot --path . --position 4000,4000 -s tests/erepeatup_test.gd
##   0 BUILDING card, one click: Easy Part on, no chooser
##   1 PLATE one body, 300 x 120 x 15 mm
##   2 REPEAT Repeat it: three copies in a row (direction x), no failed step
##   3 UP the Up button is on the Repeat it row and the press makes the copies direction y, still three, no failed step (old code: no Up button, FAILED)
##   4 STACK the box is three plates stacked: height 3 plates + 2 gaps (about 68 mm: the plate is 16 mm after the slider snap), width 300 mm, depth 120 mm (old code: FAILED)
##   5 FORWARD the Forward button turns the copies to direction z, three, no failed step (old code: FAILED)
## Shot: C:/Temp/claude/erepeatup/stack.png (LOOK at it)
const SHOT := "C:/Temp/claude/erepeatup"
const DIRT := "user://erepeatup_test"

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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of a slider knob to value v
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


## wait real seconds (the camera eases in real time)
func settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


## Draw shape, then a real drag on the floor from world a to b (metres)
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


## Pull it up, then the slider to h cm
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


func last_of(t: String) -> Dictionary:
	var out := {}
	for f in m.S.part.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


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
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open,
		"0 BUILDING card, one click -> Easy Part on, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	m.target = Vector3.ZERO
	m.pitch = -30.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 PLATE: a 300 x 120 mm rectangle on the floor, pulled up 15 mm
	await draw_floor(Vector3(-0.15, 0.0, -0.06), Vector3(0.15, 0.0, 0.06))
	await pull(1.5)
	var bp := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bp.size.x - 300.0) < 0.5 and absf(bp.size.z - 120.0) < 0.5 and absf(bp.size.y - 15.0) < 1.5,
		"1 PLATE one body, 300 x 120 x 15 mm: %s" % bp)

	# 2 REPEAT: Repeat it, three copies sideways
	m.pitch = -25.0
	m.yaw = 25.0
	m._cam()
	await idle(40)
	await click_ctl(ep().make_btns["repeat"])
	await settle(1.5)
	var pt := last_of("pattern")
	ok(int(pt.get("count", 0)) == 3 and String(pt.get("dir", "")) == "x" and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"2 REPEAT three copies sideways (dir %s, count %s), no failed step" % [str(pt.get("dir", "")), str(pt.get("count", 0))])

	# 3 UP: the Up button on the Repeat it row stacks the copies
	var up_b = ep().rep_btns.get("up")
	ok(up_b != null and (up_b as Control).is_visible_in_tree(), "3a UP the Up button is on the Repeat it row")
	if up_b != null:
		await click_ctl(up_b)
		await settle(1.5)
	pt = last_of("pattern")
	ok(String(pt.get("dir", "")) == "y" and int(pt.get("count", 0)) == 3 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"3 UP the copies go up: dir %s, count %s, no failed step" % [str(pt.get("dir", "")), str(pt.get("count", 0))])
	await shot("stack")

	# 4 STACK: three plates stacked, the width and depth stay
	var bs := bbox()
	var want_h := 3.0 * bp.size.y + 2.0 * 10.0   # three plates of the measured height, two gaps of 10 mm
	ok(absf(bs.size.y - want_h) < 1.5 and absf(bs.size.x - 300.0) < 0.5 and absf(bs.size.z - 120.0) < 0.5 and int(pu().res.get("bodies", 0)) == 1,
		"4 STACK three plates stacked: %s mm (want 300 x %.0f x 120, one body)" % [bs, want_h])

	# 5 FORWARD: the Forward button turns the same copies to the depth
	var fw_b = ep().rep_btns.get("forward")
	if fw_b != null:
		await click_ctl(fw_b)
		await settle(1.5)
	pt = last_of("pattern")
	ok(fw_b != null and String(pt.get("dir", "")) == "z" and int(pt.get("count", 0)) == 3 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"5 FORWARD the copies go forward: dir %s, count %s, no failed step" % [str(pt.get("dir", "")), str(pt.get("count", 0))])

	print("erepeatup: %d fail" % fails)
	quit(1 if fails > 0 else 0)
