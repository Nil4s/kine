extends SceneTree
## FTABLE2 (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a round dining table from the BUILDING card by real
## clicks at 1280 x 720, from the floor up: a flat foot bar on the floor, a round post on the foot, a round top on the post's top face,
## and the top coloured wood-like (Colour > Wood). Easy Part only. Each dead end is a bar. Bars marked (old) failed on the code before the fix.
##   0 BUILDING card, one click: page BUILD, Easy Part on, no chooser
##   1 FOOT a 600 x 60 mm box drawn on the floor, pulled up 10 mm: one body, 600 x 60 x 10 mm
##   2 POST a round 100 mm across drawn on the foot's top face, pulled up 650 mm: one body, top at 660 mm
##   3 TOP a round 900 mm across drawn on the post's top face, pulled up 30 mm: one body, top at 690 mm
##   4 WOOD Colour > Wood: one body, a wood-brown look (red > green > blue, red - blue >= 0.15)  (old)
##   5 WORDS no jargon word on screen during the walk
##   6 HINTS after the drawn foot the hint names Pull it up
## Shots: C:/Temp/claude/ftable2/*.png (foot, post, top, wood)
const SHOT := "C:/Temp/claude/ftable2"
const DIRT := "user://ftable2_test"
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


## Draw shape with the Round shape: the centre at a, the edge at b (metres, on the floor or a face)
func draw_round(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(a), scr(b))


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

	# 1 FOOT: a flat bar 600 x 60 mm on the floor, pulled up 10 mm (the table's foot, on the floor)
	await draw_floor(Vector3(-0.3, 0.0, -0.03), Vector3(0.3, 0.0, 0.03))
	hints.append(["drawn", ep().hint_l.text])
	check_words("drawn")
	await pull(1.0)
	var bf := bbox()
	hints.append(["foot", ep().hint_l.text])
	check_words("foot")
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bf.size.x - 600.0) < 1.0 and absf(bf.size.y - 10.0) < 1.0,
		"1 FOOT one body, a 600 x 60 x 10 mm bar on the floor: %s" % bf)
	await shot("foot")

	# 2 POST: a round 100 mm across drawn on the foot's top face, pulled up 650 mm
	await draw_round(Vector3(0.0, 0.01, 0.0), Vector3(0.05, 0.01, 0.0))
	await pull(65.0)
	var bp := bbox()
	hints.append(["post", ep().hint_l.text])
	check_words("post")
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bp.end.y - 660.0) < 1.5,
		"2 POST one body, the post tops out at %.1f mm (want 660)" % bp.end.y)
	await shot("post")

	# 3 TOP: a round 900 mm across drawn on the post's top face, pulled up 30 mm
	await settle(1.5)   # the camera eases in real time: the press points are projected from its settled view
	await draw_round(Vector3(0.0, 0.66, 0.0), Vector3(0.45, 0.66, 0.0))
	await pull(3.0)
	var bt := bbox()
	hints.append(["top", ep().hint_l.text])
	check_words("top")
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bt.size.x - 900.0) < 1.5 and absf(bt.end.y - 690.0) < 1.5,
		"3 TOP one body, the round top 900 mm across, top at 690 mm: %s" % bt)
	await shot("top")

	# 4 WOOD: Colour > Wood, one body with a wood-brown look
	await click_ctl(ep().make_btns["colour"])
	var wb: Button = ep().colour_box.find_child("easypart_colour_wood", true, false) as Button
	ok(wb != null, "4a WOOD a Wood colour chip is on the Colour row")
	if wb != null:
		await click_ctl(wb)
	var looks: Array = pu().res.get("body_looks", [])
	var lk: Dictionary = Part.look_at(looks, 0)
	var cc: Color = lk.get("c", Color.WHITE)
	ok(cc.r > cc.g and cc.g > cc.b and cc.r - cc.b >= 0.15,
		"4 WOOD the top is wood-brown: colour %s" % str(cc))
	await shot("wood")

	# 5 WORDS: jargon on screen during the walk
	ok(words_bad.is_empty(), "5 WORDS no jargon on screen during the walk: %s" % [words_bad])

	# 6 HINTS: after the top the hint names Pull it up
	var h_top := ""
	for h in hints:
		if h[0] == "drawn":
			h_top = h[1]
	ok(h_top.find("Pull it up") >= 0, "6 HINT after a drawn round names Pull it up [%s]" % h_top)

	print("ftable2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
