extends SceneTree
## FWHEEL (Nick 2026-10-28: "free 3D building, anything, nothing forced"): a beginner builds a wheel from the BUILDING card by real
## clicks at 1280 x 720: a disc, a hub, spokes made by Repeat it round the middle, a tyre ring. Every dead end, confusing word or
## missing step is a bar. Shots: C:/Temp/claude/fwheel/*.png
## Bars (run on the old code before the change: see the report):
##   0 the BUILDING card, one click -> Easy Part on, page BUILD
##   1 SPOKE: a thin box on the floor from the middle to the rim, pulled up -> one body, out to 95 mm
##   2a the Ring hint does not say "beside" (the copies go round the middle for a spoke)
##   2 SPOKES: Repeat it, Ring, 6 copies -> six spokes fanned out, a 190 x 170 mm box centred on the middle (the ring goes round the middle, not beside the spoke)
##   3 DISC: a round on the middle, pulled up -> the spokes join it: one body, 200 mm across
##   4 HUB: a small round on the disc top face, pulled up 4 cm -> one body, top at 60 mm
##   5 TYRE: a 40 mm round on the floor at the rim, Spin it round the middle -> one body, 260 mm across (a ring)
const SHOT := "C:/Temp/claude/fwheel"
const DIRT := "user://fwheel_test"

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


func bodies() -> int:
	return int(pu().res.get("bodies", 0))


func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
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
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)
	m.target = Vector3.ZERO
	m.pitch = -60.0
	m.yaw = 20.0
	m.dist = 0.9
	m._cam()
	await idle(60)
	await shot("01_open")

	# 1 SPOKE first: a thin box on the floor from the middle out to the rim, pulled up 2 cm (the disc comes after, so its spokes are not on a face)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(0.03, 0.0, -0.006)), scr(Vector3(0.095, 0.0, 0.006)))
	await pull(2.0)
	var bb := bbox()
	ok(bodies() == 1 and absf(bb.end.x - 95.0) < 1.0, "1 SPOKE one body, out to 95 mm: bodies %d box %s hint %s" % [bodies(), bb, ep().hint_l.text])
	await shot("03_spoke")

	# 2 SPOKES: Repeat it, Ring, 6 copies round the middle
	await click_ctl(ep().make_btns["repeat"])
	await click_ctl(ep().rep_btns["ring"])
	var cnt = null
	for r in ep().rep_rows:
		if String(r["key"]) == "count":
			cnt = r["slider"]
	if cnt != null:
		await drag_slider(cnt, 6.0)
	await idle(10)
	bb = bbox()
	ok(ep().hint_l.text.find("beside") < 0 and ep().hint_l.text.find("Ring") >= 0, "2a the Ring hint names Ring and does not say beside (%s)" % ep().hint_l.text)
	ok(bodies() == 1 and absf(bb.size.x - 190.0) < 1.0 and absf(bb.size.z - 170.0) < 1.0 and Vector2(bb.get_center().x, bb.get_center().z).length() < 1.0,
		"2 SPOKES Ring of 6 round the middle: 190 x 170 mm box centred on the middle, one body (bodies %d, box %s)" % [bodies(), bb])
	await shot("04_spokes")

	# 3 DISC: a round on the floor at the middle, 100 mm out, pulled up 2 cm: the spokes join it
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3.ZERO), scr(Vector3(0.1, 0.0, 0.0)))
	await pull(2.0)
	bb = bbox()
	ok(bodies() == 1 and absf(bb.size.x - 200.0) < 1.0, "3 DISC joins the spokes into one body, 200 mm across: bodies %d box %s" % [bodies(), bb])
	await shot("05_disc")

	# 4 HUB: a small round on the disc's top face (a press on a solid draws on its face), pulled up 4 cm
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.02, 0.0)), scr(Vector3(0.025, 0.02, 0.0)))
	await pull(4.0)
	bb = bbox()
	ok(bodies() == 1 and absf(bb.end.y - 60.0) < 1.0, "4 HUB one body, stands 40 mm above the 20 mm disc (top at 60 mm): bodies %d top %.1f" % [bodies(), bb.end.y])
	await shot("06_hub")

	# 5 TYRE: a 40 mm round on the floor at the rim (centre 100 mm out), Spin it round the middle: a ring round the wheel
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.11, 0.0, 0.0)), scr(Vector3(0.13, 0.0, 0.0)))
	await shot("07_tyre_drawn")
	await click_ctl(ep().make_btns["spin"])
	await idle(10)
	bb = bbox()
	await shot("08_tyre")
	ok(bodies() == 1 and absf(bb.size.x - 260.0) < 1.0, "5 TYRE a round at the rim, spun round the middle: one body, 260 mm across (bodies %d box %s hint %s)" % [bodies(), bb, ep().hint_l.text])

	print("fwheel: %d fail" % fails)
	quit(1 if fails > 0 else 0)
