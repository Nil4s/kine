extends SceneTree
## FFRAME (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a picture frame from the BUILDING card by real clicks
## at 1280 x 720: an outer rectangle pulled up (the frame), an inner rectangle drawn on its top face and cut (Cut a hole), the edges rounded
## (the bevelled front), a stand drawn under the back edge and pulled down. Easy Part only. Every dead end is a bar.
##   0 BUILDING card, one click: page BUILD, Easy Part on, no chooser
##   1 FRAME a 300 x 220 mm rectangle pulled up 15 mm: one body, box 300 x 220 x 15 mm
##   2 INNER a 200 x 130 mm rectangle drawn on the top face, Cut a hole: the volume drops by 0.3..0.5 of the hole (the hole is a rectangle, not a round hole)
##   3 BEVEL Round the edges: one round step, no failed step, box size kept
##   4 STAND a 40 x 30 mm block drawn under the back edge and pulled down 30 mm: one body, box min y -30 mm
##   5 WORDS no jargon on screen during the walk
##   6 HINTS after the inner shape the hint names Cut a hole
## Shots: C:/Temp/claude/fframe/*.png (LOOK at them)
const SHOT := "C:/Temp/claude/fframe"
const DIRT := "user://fframe_test"
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

	# 1 FRAME: a 300 x 220 mm rectangle on the floor, pulled up 15 mm
	await draw_floor(Vector3(-0.15, 0.0, -0.11), Vector3(0.15, 0.0, 0.11))
	hints.append(["drawn", ep().hint_l.text])
	await pull(1.5)
	var bp := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bp.size.x - 300.0) < 0.5 and absf(bp.size.z - 220.0) < 0.5 and absf(bp.size.y - 15.0) < 1.5,
		"1 FRAME one body, 300 x 220 x 15 mm: %s" % bp)
	check_words("frame")
	await shot("plate")

	# 2 INNER: a 200 x 130 mm rectangle drawn on the top face, then Cut a hole
	m.pitch = -70.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var v0 := float(pu().res.get("volume", 0.0))
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.10, 0.015, -0.065)), scr(Vector3(0.10, 0.015, 0.065)))
	hints.append(["inner", ep().hint_l.text])
	check_words("inner")
	await click_ctl(ep().make_btns["hole"])
	await idle(10)
	var v1 := float(pu().res.get("volume", 0.0))
	var frac := (v0 - v1) / maxf(v0, 1e-12)
	var expect := (0.2 * 0.13 * 0.015) / maxf(v0, 1e-12)
	ok(v1 < v0 - 1e-9 and absf(frac - expect) < 0.08 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"2 INNER the rectangle is cut out: volume removed %.2f of the frame (want about %.2f)" % [frac, expect])
	await shot("inner")

	# 3 BEVEL: round the edges of the frame
	var bb2 := bbox()
	await click_ctl(ep().make_btns["round"])
	await idle(10)
	var bb3 := bbox()
	var fl := last_of("fillet")
	hints.append(["rounded", ep().hint_l.text])
	check_words("rounded")
	ok(not fl.is_empty() and (pu().res.get("errors", {}) as Dictionary).is_empty() and absf(bb3.size.x - bb2.size.x) < 0.5,
		"3 BEVEL the edges are rounded: one round step, no failed step, box x %.0f mm" % bb3.size.x)
	await shot("bevel")

	# 4 STAND: a block under the back edge, drawn from below, pulled down 30 mm
	m.pitch = 35.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await draw_floor(Vector3(-0.02, 0.0, -0.10), Vector3(0.02, 0.0, -0.08))
	hints.append(["stand", ep().hint_l.text])
	await pull(3.0)
	var bb4 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bb4.position.y + 30.0) < 0.5,
		"4 STAND one body, the stand hangs 30 mm under the frame: box min y %.1f (want -30)" % bb4.position.y)
	check_words("stand")
	m.pitch = -30.0
	m.yaw = 25.0
	m._cam()
	await settle(1.0)
	await shot("frame")

	# 5 WORDS
	ok(words_bad.is_empty(), "5 WORDS no jargon on screen during the walk: %s" % [words_bad])

	# 6 HINTS: after the inner shape the hint names Cut a hole
	var h_in := ""
	for h in hints:
		if h[0] == "inner":
			h_in = h[1]
	ok(h_in.find("Cut a hole") >= 0, "6 HINT after the inner shape names Cut a hole [%s]" % h_in)

	print("fframe: %d fail" % fails)
	quit(1 if fails > 0 else 0)
