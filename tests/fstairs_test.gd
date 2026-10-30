extends SceneTree
## FSTAIRS (Nick 2026-10-28, free 3D building like Fusion 360): a beginner builds a staircase of 8 steps from the BUILDING card by real clicks at 1280 x 720:
## a 300 x 250 x 175 mm block (Draw shape, Pull it up), Repeat it, the Up and Forward button, 8 steps. The handrail is a bar (not made yet).
## Bars: 0 BUILDING card one click; 1 TREAD block; 2 the Repeat it box has Up and Forward (old: FAIL, no button); 3 STAIRS 8 steps one body, no failed step;
## 4 VIEW the whole stair on screen; 5 WORDS no jargon; 6 HANDRAIL (open).
## Shots: C:/Temp/claude/fstairs/*.png (open, tread, repeat, stairs; LOOK at them)
const SHOT := "C:/Temp/claude/fstairs"
const DIRT := "user://fstairs_test"
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


## a visible Button under n whose text is t (a beginner reads the words, not the internal names)
func find_btn(n: Node, t: String) -> Button:
	if n is Button and (n as Button).text == t and (n as Button).is_visible_in_tree():
		return n
	for c in n.get_children():
		var f := find_btn(c, t)
		if f != null:
			return f
	return null


func box_on_screen(bb: AABB) -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	for i in 8:
		var c := bb.position + Vector3(bb.size.x * float(i & 1), bb.size.y * float((i >> 1) & 1), bb.size.z * float((i >> 2) & 1))
		var p := scr(c * Part.MM)
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

	# 1 TREAD: a floor rectangle 300 x 250 mm, pulled up 175 mm (one step block)
	await draw_floor(Vector3(-0.15, 0.0, -0.125), Vector3(0.15, 0.0, 0.125))
	await pull(17.5)
	var bp := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bp.size.x - 300.0) < 1.5 and absf(bp.size.z - 250.0) < 1.5 and absf(bp.size.y - 175.0) < 1.5,
		"1 TREAD one block 300 x 250 x 175 mm: %s" % bp)
	await shot("tread")

	# 2 REPEAT IT: the box offers Up and Forward (a stair: each copy goes up one step and forward one step)
	await click_ctl(ep().make_btns["repeat"])
	await settle(1.0)
	var uf := find_btn(ep().repeat_box, "Up and Forward")
	ok(uf != null, "2 REPEAT the Repeat it box has an Up and Forward button (a stair)")

	# 3 STAIRS: 8 steps, one body, no failed step: 8 x 175 mm tall, 8 x 250 mm deep
	if uf != null:
		await click_ctl(uf)
	await settle(1.5)
	var pt := last_of("pattern")
	var bb3 := bbox()
	var st_ok: bool = String(pt.get("kind", "")) == "stairs" and int(pt.get("count", 0)) == 8 and int(pu().res.get("bodies", 0)) == 1 \
		and (pu().res.get("errors", {}) as Dictionary).is_empty()
	ok(st_ok and absf(bb3.size.y - 8.0 * bp.size.y) < 2.0 and absf(bb3.size.z - 8.0 * bp.size.z) < 2.0,
		"3 STAIRS 8 steps (8 x the block: %.0f x %.0f mm), one body, no failed step: %s, box %s" % [8.0 * bp.size.y, 8.0 * bp.size.z, str(pt.get("kind", "")), bb3])
	hints.append(["stairs", ep().hint_l.text])
	check_words("stairs")

	# 4 VIEW: the whole stair on screen from a 3/4 view
	m.target = bb3.get_center() * Part.MM   # the camera looks at the middle of the stair (a view for the screenshot; the on-screen bar is the check)
	m.dist = maxf(bb3.size.length() * Part.MM * 2.5, 5.0)
	m.pitch = -25.0
	m.yaw = 80.0
	m._cam()
	await settle(1.5)
	ok(box_on_screen(bb3), "4 VIEW the whole stair is on screen from the 3/4 view (box %s)" % bb3)
	await shot("stairs")

	# 5 WORDS: no jargon on screen during the walk
	ok(words_bad.is_empty(), "5 WORDS no jargon on screen during the walk: %s" % [words_bad])

	# 6 HANDRAIL: a rail along the stairs by the same clicks (open: no easy step makes one yet)
	var rail_ok := false
	var rail_how := "no rail button in the Easy steps"
	ok(rail_ok, "6 HANDRAIL a rail along the stairs by real clicks: %s" % rail_how)

	print("fstairs: %d fail" % fails)
	quit(1 if fails > 0 else 0)
