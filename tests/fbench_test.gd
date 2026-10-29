extends SceneTree
## FBENCH (Nick 2026-10-28: "free 3D building, like Fusion 360; a park bench: slats by Repeat it (Up/Forward), two side frames by Mirror, round all edges"):
## a beginner from the BUILDING card (Easy Part, blank) by real clicks at 1280 x 720. Every dead end is a bar.
##   0 BUILDING card, one click: page BUILD, Easy Part on, no chooser
##   1 BASE a 640 x 60 mm strip drawn on the floor across the middle, pulled up 4 cm: one body, box x 640 mm
##   2 FRAME a 40 x 400 mm plate drawn on the floor on the left (it stands on the base), pulled up 45 cm: one body, box y 490 mm
##   3 MIRROR Mirror that copies the frame to the right: the solid gains one frame volume (0.0072 m3 +- 0.0005)
##   4 SLAT a 620 x 60 mm board drawn on the top of the left frame, pulled up 4 cm: one body, box y 530 mm
##   5 REPEAT FORWARD Repeat it offers Forward (copies along the depth, Z); five slats in a row: one body, no failed step
##   5c REPEAT copies the newest PIECE (the slat), not the whole bench it joined (640 x 400 mm stays). Was an open dead end, fixed in Part's pattern src.
##   6 ROUND Round the edges: one fillet step, no failed step, the box keeps its size
##   7 WORDS no jargon on screen during the walk
##   8 HINTS after the drawn shape the hint names Pull it up
## Bars marked (old) FAILED on the code before the fix (run once before, see the commit).
## Shots: C:/Temp/claude/fbench/*.png (open, base, frame, mirror, slat, repeat, round; LOOK at them)
const SHOT := "C:/Temp/claude/fbench"
const DIRT := "user://fbench_test"
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


## a visible button under n whose text is t (null = none)
func button_named(n: Node, t: String) -> Button:
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text == t:
		return n
	for c in n.get_children():
		var b := button_named(c, t)
		if b != null:
			return b
	return null


func pu():
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


## Draw shape, then a real drag on the floor (or on a face) from world a to b (metres)
func draw_on(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


## Pull it up, then the slider to h cm (the default is 2 cm)
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
	await shot("open")
	check_words("open")

	# 1 BASE: a 640 x 60 mm strip across the middle, pulled up 4 cm
	await draw_on(Vector3(-0.32, 0.0, -0.03), Vector3(0.32, 0.0, 0.03))
	await pull(4.0)
	var b1 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(b1.size.x - 640.0) < 0.5 and absf(b1.size.z - 60.0) < 0.5,
		"1 BASE one body, 640 x 60 mm wide: %s" % b1)
	await shot("base")

	# 2 FRAME: a 40 x 400 mm plate on the left, standing on the base, pulled up 45 cm
	m.pitch = -35.0
	m.yaw = 25.0
	m._cam()
	await idle(40)
	await draw_on(Vector3(-0.32, 0.0, -0.2), Vector3(-0.28, 0.0, 0.2))
	hints.append(["frame", ep().hint_l.text])
	await pull(45.0)
	var b2 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(b2.size.y - 450.0) < 1.5,
		"2 FRAME one body, the frame stands 45 cm up from the floor: box y %.0f mm (want 450)" % b2.size.y)
	await shot("frame")
	check_words("frame")

	# 3 MIRROR: Mirror that copies the frame to the right
	var v0: float = float(pu().res.get("volume", 0.0))
	var mb := ep().make_btns["mirror"] as Button
	await click_ctl(mb)
	await idle(10)
	var v1: float = float(pu().res.get("volume", 0.0))
	ok((pu().res.get("errors", {}) as Dictionary).is_empty() and absf((v1 - v0) - 0.0072) < 0.0005,
		"3 MIRROR the frame is copied to the right: volume %.5f -> %.5f m3 (want +0.0072)" % [v0, v1])
	hints.append(["mirrored", ep().hint_l.text])
	await shot("mirror")
	check_words("mirror")

	# 4 SLAT: a 620 x 60 mm board drawn on the top face of the left frame, pulled up 4 cm
	m.pitch = -40.0
	m.yaw = 15.0
	m._cam()
	await idle(40)
	await draw_on(Vector3(-0.31, 0.45, -0.19), Vector3(0.31, 0.45, -0.13))
	hints.append(["slat", ep().hint_l.text])
	await pull(4.0)
	var b4 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(b4.size.y - 490.0) < 1.5,
		"4 SLAT one body, the slat sits on both frames: box y %.0f mm (want 490), bodies %d" % [b4.size.y, int(pu().res.get("bodies", 0))])
	await shot("slat")
	check_words("slat")

	# 5 REPEAT FORWARD: copies along the depth (Z), five slats in a row
	await click_ctl(ep().make_btns["repeat"])
	await idle(5)
	var fwd := button_named(ep().repeat_box, "Forward")
	ok(fwd != null, "5a REPEAT a Forward button is on the Repeat it box (Row / Ring / Corners alone copy sideways)")
	if fwd != null:
		await click_ctl(fwd)
		await idle(5)
		var rep := last_of("pattern")
		ok(String(rep.get("dir", "")) == "z", "5b REPEAT Forward copies along the depth: dir %s (want z)" % str(rep.get("dir", "")))
	await drag_slider(ep().rep_rows[0]["slider"], 5.0)
	await settle(1.0)
	var pt := last_of("pattern")
	var b5 := bbox()
	hints.append(["repeated", ep().hint_l.text])
	check_words("repeated")
	ok(int(pt.get("count", 0)) == 5 and String(pt.get("dir", "")) == "z" and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"5 REPEAT five slats, one body, no failed step: count %s, bodies %d" % [str(pt.get("count", 0)), int(pu().res.get("bodies", 0))])
	ok(absf(b5.size.x - 640.0) < 1.0 and absf(b5.size.z - 400.0) < 1.0,
		"5c REPEAT copies the slat, not the whole bench (the bench stays 640 x 400 mm), box %s" % b5)
	await shot("repeat")

	# 6 ROUND: the edges of the whole bench
	await click_ctl(ep().make_btns["round"])
	await idle(10)
	var bb6 := bbox()
	var fl := last_of("fillet")
	hints.append(["rounded", ep().hint_l.text])
	check_words("rounded")
	ok(not fl.is_empty() and (pu().res.get("errors", {}) as Dictionary).is_empty() and absf(bb6.size.x - b5.size.x) < 0.5,
		"6 ROUND the edges: one round step, no failed step, box x %.0f mm (was %.0f)" % [bb6.size.x, b5.size.x])
	await settle(1.0)
	await shot("round")

	# 7 WORDS
	ok(words_bad.is_empty(), "7 WORDS no jargon on screen during the walk: %s" % [words_bad])

	# 8 HINTS: after the drawn shape the hint names Pull it up
	var h_frame := ""
	for h in hints:
		if h[0] == "frame":
			h_frame = h[1]
	ok(h_frame.find("Pull it up") >= 0, "8 HINT after a drawn shape names Pull it up [%s]" % h_frame)

	print("fbench: %d fail" % fails)
	quit(1 if fails > 0 else 0)
