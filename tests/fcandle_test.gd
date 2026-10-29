extends SceneTree
## FCANDLE (Nick 2026-10-28: "free 3D building, like Fusion 360, anything, nothing forced"): a beginner builds a candle holder from the BUILDING card
## by real clicks at 1280 x 720: a round base, a cup (Cut a hole, Hollow inside), a curved arm (Curvy line, Pull it up), Repeat it Ring for three. Easy Part only.
## Every dead end, confusing word or missing step is a bar. Bars marked (old) FAILED on the code before the fix (run once before, see the commit).
##   0 BUILDING card, one click: page BUILD, Easy Part on, the chooser is not open
##   1 PLATE a floor rectangle 300 x 120 mm pulled up 15 mm: one body (box 300 x 120 x 15)
##   2 BRACKET two blocks drawn on the underside of the plate (camera from below) and pulled down 80 mm: still one body, box min y -80 mm
##   3 REPEAT Repeat it: the newest body (the whole shelf) is copied in a row, three copies, no failed step; box x span >= 900 mm
##   4 ROUND Round the edges on the three shelves: one fillet step, no failed step, and the box keeps its size
##   5 WORDS no visible word with sketch / extrude / body / profile / fillet / pattern / feature / plane in the Easy column while the walk runs
##   6 HINTS after each step the hint names the next button (Pull it up after a drawn shape, Repeat it after a body)
## Shots: C:/Temp/claude/fshelf/*.png (open, plate, brackets, repeat, round, shelf = a 3/4 view; LOOK at them)
const SHOT := "C:/Temp/claude/fcandle"
const DIRT := "user://fcandle_test"
const JARGON := ["sketch", "extrude", "body", "profile", "fillet", "pattern", "feature", "plane", "shell", "loft", "spline", "revolve"]

var fails := 0
var m: Node
var words_bad: Array = []
var hints: Array = []


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


## wait real seconds (the camera eases in real time: a few frames of a headless run are not 0.3 s)
func settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


## the visible Easy words now (panel, make row, hint); jargon words are noted
func check_words(step: String) -> void:
	var texts: Array = []
	texts_under(ep().panel, texts)
	texts_under(ep().make_box, texts)
	texts_under(ep().hint, texts)
	for t in texts:
		for j in JARGON:
			if String(t).to_lower().find(j) >= 0:
				words_bad.append("%s: %s in %s" % [step, j, t])


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


## Pull it up, then the slider to h cm (the default is 2 cm)
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


## every corner of the box is inside the 1280 x 720 screen
func box_on_screen(bb: AABB) -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	for i in 8:
		var c := bb.position + Vector3(bb.size.x * float(i & 1), bb.size.y * float((i >> 1) & 1), bb.size.z * float((i >> 2) & 1))
		var p := scr(c * Part.MM)   # the box is in mm here: back to metres for the camera
		if p.x < 0.0 or p.y < 0.0 or p.x > vs.x or p.y > vs.y:
			return false
	return true


func last_of(t: String) -> Dictionary:
	var out := {}
	for f in m.S.part.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


## a real drag of a closed path through the world points (metres on the floor), then back to the start
func draw_path(pts: Array) -> void:
	var first: Vector2 = scr(pts[0])
	await ev_move(first, false)
	await ev_mouse(first, true)
	for i in range(1, pts.size()):
		var a: Vector2 = scr(pts[i - 1])
		var b: Vector2 = scr(pts[i])
		for k in range(1, 9):
			await ev_move(a.lerp(b, k / 8.0))
	await ev_mouse(first, false)
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
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open,
		"0 BUILDING card, one click -> Easy Part on, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	m.target = Vector3.ZERO
	m.pitch = -55.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("open")
	check_words("open")

	# 1 BASE: a round shape 80 mm across on the floor, pulled up 15 mm
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	# a round shape: the first press is its middle, the drag sets its radius (40 mm)
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	hints.append(["base_drawn", ep().hint_l.text])
	await pull(1.5)
	var b1 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(b1.size.x - 80.0) < 2.0 and absf(b1.size.z - 80.0) < 2.0 and absf(b1.size.y - 15.0) < 1.5,
		"1 BASE a round 80 mm base, one body, 80 x 80 x 15 mm: %s" % b1)
	check_words("base")
	await shot("base")

	# 2 CUP: a round 50 mm shape on the base's middle, pulled up 80 mm: one body
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.025, 0.0, 0.0)))
	await pull(8.0)
	var b2 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and b2.end.y > 90.0 and b2.end.y < 100.0 and b2.size.x < 81.0,
		"2 CUP a 50 mm cup stands on the base and is pulled up 80 mm: one body, top %.1f mm (want 96 = 16 + 80)" % b2.end.y)
	check_words("cup")
	await shot("cup")

	# 3 HOLLOW: Cut a hole, then Hollow inside: the cup is open at the top, the volume goes down
	var v_before := float(pu().res.get("volume", 0.0))
	await click_ctl(ep().make_btns["hole"])
	await click_ctl(ep().hole_btns["hollow"])
	var v_after := float(pu().res.get("volume", 0.0))
	var hollow_on: bool = ep().hole_mode == "hollow"
	ok(hollow_on and v_after < v_before * 0.6 and v_after > v_before * 0.2 and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"3 HOLLOW the cup is hollowed (Hollow inside chip on), open at the top: volume %.0f -> %.0f cm3, one body, no failed step" % [v_before * 1e6, v_after * 1e6])
	check_words("hollow")
	await shot("hollow")

	# 4 ARM: a thin curved loop on the floor beside the cup, closed, pulled up 50 mm: one body
	m.pitch = -70.0
	m._cam()
	await idle(40)
	await click_ctl(ep().make_btns["curve"])
	var pts: Array = []
	for i in range(0, 13):
		var t := i / 12.0
		pts.append(Vector3(0.03 + 0.07 * t, 0.0, 0.012 * sin(PI * t)))
	for i in range(12, -1, -1):
		var t := i / 12.0
		pts.append(Vector3(0.03 + 0.07 * t, 0.0, 0.012 * sin(PI * t) - 0.008))
	pts.append(pts[0])
	await draw_path(pts)
	hints.append(["arm_drawn", ep().hint_l.text])
	await pull(5.0)
	var b4 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty() and b4.end.x > 90.0 and b4.size.y > 45.0,
		"4 ARM a curved arm drawn on the base, pulled up 50 mm: one body, no failed step, box %s" % b4)
	check_words("arm")
	await shot("arm")

	# 5 RING: Repeat it, Ring: three holders round in a circle, no failed step
	m.pitch = -40.0
	m._cam()
	await idle(40)
	await click_ctl(ep().make_btns["repeat"])
	await click_ctl(ep().rep_btns["ring"])
	await settle(1.5)
	var pt := last_of("pattern")
	var b5 := bbox()
	hints.append(["ring", ep().hint_l.text])
	check_words("ring")
	ok(String(pt.get("kind", "")) == "circular" and int(pt.get("count", 0)) == 3 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"5 RING three holders in a ring, no failed step: kind %s, count %s" % [str(pt.get("kind", "")), str(pt.get("count", 0))])
	await shot("ring")

	# 6 WORDS / HINTS
	ok(words_bad.is_empty(), "6 WORDS no jargon on screen during the walk: %s" % [words_bad])
	var h_base := ""
	for h in hints:
		if h[0] == "base_drawn":
			h_base = h[1]
	ok(h_base.find("Pull it up") >= 0, "7 HINT after a drawn round shape names Pull it up [%s]" % h_base)

	print("fcandle: %d fail" % fails)
	quit(1 if fails > 0 else 0)
