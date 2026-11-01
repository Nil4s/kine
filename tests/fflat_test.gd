extends SceneTree
## FFLAT (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a flat-pack shelf unit from the BUILDING card by real clicks
## at 1280 x 720: two side panels, a base shelf, Repeat it Up for four shelves, a back panel, then Stick together joins every piece into ONE body.
## godot --path . --position 4000,4000 -s tests/fflat_test.gd
##   0 BUILDING card, one click: Easy Part on, no chooser
##   1 SIDE A one body, 20 x 200 x 200 mm
##   2 SIDE B drawn apart from side A: two bodies
##   1 SHELF base shelf 280 x 200 x 15 mm pulled up, one step, no failed step
##   2 UP Repeat it, Up, four shelves stacked (dir y, count 4), no failed step
##   3 BACK a back panel drawn on the floor behind the shelves, pulled up: no failed step
##   4 SIDE A a floor panel pulled up beside the shelves is its own piece (three solids)
##   5 SIDE B the other side (four solids)
##   6 STICK Stick together joins the touching pieces two at a time until ONE body
##   7 ONE BODY the finished unit is one body, box about 320 x 200 x 220 mm, no failed step
## Shots: C:/Temp/claude/fflat/*.png (LOOK at them)
const SHOT := "C:/Temp/claude/fflat"
const DIRT := "user://fflat_test"

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


## the pieces the user sees (the status line's count): apart solids are pieces even when the kernel says one body
func pieces() -> int:
	return ep()._lumps(pu().res)


func errs() -> Dictionary:
	return pu().res.get("errors", {}) as Dictionary


func last_of(t: String) -> Dictionary:
	var out := {}
	for f in m.S.part.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


## Draw shape, then a real drag on the floor from world a to b (metres)
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


## Pull it up, then the How far slider to h cm
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


## Stick together: click piece a, click piece b, press Join. True when the press joined them
func stick(a: Vector3, b: Vector3) -> bool:
	var before: int = pieces()
	await click_ctl(ep().make_btns["stick"])
	await click_at(scr(a))
	await click_at(scr(b))
	var join_b: Button = null
	for c in ep().stick_box.find_children("*", "Button", true, false):
		if (c as Button).text == "Join" and (c as Button).is_visible_in_tree():
			join_b = c
	if join_b == null:
		return false
	await click_ctl(join_b)
	await settle(0.5)
	return pieces() < before


## the piece (body index) whose box holds world point w (metres), or -1
func body_at(w: Vector3) -> int:
	var faces: Array = Part.body_faces(m.S.part, -1)
	for bi in faces.size():
		var pts: PackedVector3Array = faces[bi]
		if pts.size() == 0:
			continue
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		if bb.grow(0.002).has_point(w):
			return bi
	return -1


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
	m.target = Vector3(0, 0.1, 0)
	m.pitch = -80.0
	m.yaw = 0.0
	m._cam()
	await idle(60)

	ep().one_side = true   # P153 draws the mirror twin of a one-sided shape by default; this fixture draws each side panel itself

	# 1 SHELF: the base shelf on the floor, 280 x 200 mm, pulled up 15 mm (drawn first: nothing solid around it yet)
	await draw_floor(Vector3(-0.14, 0.0, -0.10), Vector3(0.14, 0.0, 0.10))
	await pull(1.5)
	var b1 := bbox()
	ok(errs().is_empty() and int(pu().res.get("bodies", 0)) == 1 and absf(b1.size.x - 280.0) < 2.0 and absf(b1.size.y - 15.0) < 2.0 and absf(b1.size.z - 200.0) < 2.0,
		"1 SHELF base shelf, 280 x 200 x 15 mm, one step, no failed step: %s" % b1)
	await shot("shelf")

	# 2 UP: Repeat it, Up, four shelves stacked (the newest piece alone is copied)
	await click_ctl(ep().make_btns["repeat"])
	await settle(1.0)
	var up_b = ep().rep_btns.get("up")
	if up_b != null:
		await click_ctl(up_b)
		await settle(1.0)
	for r in ep().rep_rows:
		if String(r["key"]) == "count":
			await drag_slider(r["slider"], 4.0)
	await settle(1.5)
	var pt := last_of("pattern")
	var bu := bbox()
	ok(String(pt.get("dir", "")) == "y" and int(pt.get("count", 0)) == 4 and errs().is_empty() and bu.size.x < 290.0 and bu.size.y > 60.0,
		"2 UP four shelves stacked: dir %s, count %s, box %s, no failed step" % [str(pt.get("dir", "")), str(pt.get("count", 0)), bu])
	await shot("up")

	# 3 BACK: the back panel behind, pressed at its outer corner
	await draw_floor(Vector3(-0.16, 0.0, -0.12), Vector3(0.16, 0.0, -0.10))
	await pull(20.0)
	ok(errs().is_empty(), "3 BACK back panel pulled up, no failed step (bodies %d)" % int(pu().res.get("bodies", 0)))
	await shot("back")

	# 4 SIDE A: a floor panel beside the shelves (pressed at its far corner, toward the viewer), 20 x 200 x 200 mm, pulled up 20 cm: its own piece
	await draw_floor(Vector3(-0.16, 0.0, 0.10), Vector3(-0.14, 0.0, -0.10))
	await pull(20.0)
	var n3 := int(pu().res.get("bodies", 0))
	ok(errs().is_empty() and n3 == 3, "4 SIDE A pulled beside the shelves is its own piece: three solids (bodies %d)" % n3)
	await shot("side_a")

	# 5 SIDE B: the other side
	await draw_floor(Vector3(0.16, 0.0, 0.10), Vector3(0.14, 0.0, -0.10))
	await pull(20.0)
	var n4 := int(pu().res.get("bodies", 0))
	ok(errs().is_empty() and n4 == 4, "5 SIDE B its own piece: four solids (bodies %d)" % n4)
	await shot("sides")

	# 6 STICK: join the touching pieces two at a time
	var pairs := [
		[Vector3(-0.15, 0.1, 0.0), Vector3(0.0, 0.0075, 0.0)],     # side A with the shelves
		[Vector3(0.15, 0.1, 0.0), Vector3(0.0, 0.0075, 0.0)],      # side B
		[Vector3(0.0, 0.1, -0.11), Vector3(-0.15, 0.1, 0.0)],      # back panel with side A
		[Vector3(0.0, 0.1, -0.11), Vector3(0.15, 0.1, 0.0)],       # back panel with side B
	]
	var joined := 0
	for pr in pairs:
		if int(pu().res.get("bodies", 0)) <= 1:
			break
		print("INFO stick pair dll bodies %d pieces %d" % [int(pu().res.get("bodies", 0)), pieces()])
		var ba := body_at(pr[0])
		var bq := body_at(pr[1])
		if ba < 0 or bq < 0 or ba == bq:
			continue
		if await stick(pr[0], pr[1]):
			joined += 1
	await shot("stuck")
	var nb := pieces()
	ok(nb == 1 and int(pu().res.get("bodies", 0)) == 1, "6 STICK Stick together joined the pieces into one body (joins %d, pieces %d, bodies %d)" % [joined, nb, int(pu().res.get("bodies", 0))])

	# 7 ONE BODY
	var b7 := bbox()
	ok(nb == 1 and int(pu().res.get("bodies", 0)) == 1 and errs().is_empty() and absf(b7.size.x - 320.0) < 2.0 and absf(b7.size.y - 200.0) < 2.0 and absf(b7.size.z - 220.0) < 2.0,
		"7 ONE BODY box about 320 x 200 x 220 mm, no failed step: %s" % b7)
	await shot("unit")

	print("fflat: %d fail" % fails)
	quit(1 if fails > 0 else 0)
