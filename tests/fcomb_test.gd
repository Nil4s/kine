extends SceneTree
## FCOMB (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a comb from the BUILDING card by real clicks at 1280 x 720:
## a tooth (drawn on the floor, pulled up 4 cm), Repeat it in a Row of 20 teeth (How many slider to 20, Gap to 0.5 cm), a bar drawn across the
## tooth bases and pulled up 1 cm, Round the edges. Easy Part only. Bars marked (old) FAILED on the code before the fix (run once before, see the commit).
##   0 BUILDING card, one click: page BUILD, Easy Part on, the chooser is not open
##   1 TOOTH one body, box height 40 mm
##   2 ROW 20 teeth: How many slider reaches 20 (old: stops at 12, FAILED), no failed step, one body, box x >= 230 mm
##   3 BAR the bar across the tooth bases: one body, box height still 40 mm, box x >= 270 mm, no failed step
##   4 ROUND Round the edges: one fillet step, no failed step, box size kept
##   5 WORDS no jargon on screen during the walk
##   6 HINT after the drawn tooth the hint names Pull it up
## Shots: C:/Temp/claude/fcomb/*.png (open, tooth, row, bar, comb = a 3/4 view; LOOK at them)
##   0 BUILDING card, one click: page BUILD, Easy Part on, the chooser is not open
##   1 PLATE a floor rectangle 300 x 120 mm pulled up 15 mm: one body (box 300 x 120 x 15)
##   2 BRACKET two blocks drawn on the underside of the plate (camera from below) and pulled down 80 mm: still one body, box min y -80 mm
##   3 REPEAT Repeat it: the newest body (the whole shelf) is copied in a row, three copies, no failed step; box x span >= 900 mm
##   4 ROUND Round the edges on the three shelves: one fillet step, no failed step, and the box keeps its size
##   5 WORDS no visible word with sketch / extrude / body / profile / fillet / pattern / feature / plane in the Easy column while the walk runs
##   6 HINTS after each step the hint names the next button (Pull it up after a drawn shape, Repeat it after a body)
## Shots: C:/Temp/claude/fshelf/*.png (open, plate, brackets, repeat, round, shelf = a 3/4 view; LOOK at them)
const SHOT := "C:/Temp/claude/fcomb"
const DIRT := "user://fcomb_test"
const JARGON := ["sketch", "extrude", "body", "profile", "fillet", "pattern", "feature", "plane"]

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
	await shot("open")
	check_words("open")

	# 1 TOOTH: an 8 x 30 mm rectangle on the floor, pulled up 40 mm
	await draw_floor(Vector3(-0.004, 0.0, 0.0), Vector3(0.004, 0.0, -0.030))
	hints.append(["drawn", ep().hint_l.text])
	check_words("drawn")
	await pull(4.0)
	var bt := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bt.size.y - 40.0) < 1.5,
		"1 TOOTH one body, box height 40 mm: %s" % bt)
	await shot("tooth")

	# 2 ROW: Repeat it, then the How many slider to 20 and the Gap slider to 0.5 cm
	m.pitch = -25.0
	m.yaw = 25.0
	m._cam()
	await idle(40)
	await click_ctl(ep().make_btns["repeat"])
	await settle(1.0)
	for rw in ep().rep_rows:
		if String(rw["key"]) == "count":
			await drag_slider(rw["slider"], 20.0)
		elif String(rw["key"]) == "gap":
			await drag_slider(rw["slider"], 0.5)
	await settle(1.5)
	var pt := last_of("pattern")
	var br := bbox()
	hints.append(["row", ep().hint_l.text])
	check_words("row")
	ok(int(pt.get("count", 0)) == 20 and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty() and br.size.x >= 230.0,
		"2 ROW 20 teeth in a row: count %s, one body, box x %.0f mm, no failed step" % [str(pt.get("count", 0)), br.size.x])
	await shot("row")

	# 3 BAR: a bar across the tooth bases (z -2 .. 10 mm, in front of the teeth: a press behind a tooth would draw on the tooth face), pulled up 1 cm
	m.pitch = -30.0
	m.yaw = 20.0
	m._cam()
	await idle(40)
	await draw_floor(Vector3(-0.012, 0.0, 0.010), Vector3(0.285, 0.0, -0.002))
	await pull(1.0)
	var bb3 := bbox()
	hints.append(["bar", ep().hint_l.text])
	check_words("bar")
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bb3.size.y - 40.0) < 1.5 and bb3.size.x >= 270.0 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"3 BAR one body with the teeth, height %.0f mm, x %.0f mm, no failed step" % [bb3.size.y, bb3.size.x])
	await shot("bar")

	# 4 ROUND: the edges of the comb
	await click_ctl(ep().make_btns["round"])
	await idle(10)
	var bb4 := bbox()
	var fl := last_of("fillet")
	check_words("rounded")
	ok(not fl.is_empty() and (pu().res.get("errors", {}) as Dictionary).is_empty() and absf(bb4.size.x - bb3.size.x) < 0.5,
		"4 ROUND the edges: one round step, no failed step, box x %.0f mm (was %.0f)" % [bb4.size.x, bb3.size.x])
	await settle(1.0)
	await shot("comb")

	# 5 WORDS
	ok(words_bad.is_empty(), "5 WORDS no jargon on screen during the walk: %s" % [words_bad])

	# 6 HINT after the drawn tooth names Pull it up
	var h_drawn := ""
	for h in hints:
		if h[0] == "drawn":
			h_drawn = h[1]
	ok(h_drawn.find("Pull it up") >= 0, "6a HINT after a drawn shape names Pull it up [%s]" % h_drawn)

	print("fcomb: %d fail" % fails)
	quit(1 if fails > 0 else 0)
