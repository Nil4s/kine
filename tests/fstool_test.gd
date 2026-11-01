extends SceneTree
## FSTOOL (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a three-legged stool from the BUILDING card by real clicks
## at 1280 x 720: a round seat (Draw shape, Round chip, Pull it up 2 cm), one leg drawn under the seat and pulled down 45 cm, Repeat it in a Ring
## (three copies round the up axis), and a ring brace between the legs. Dead ends are bars.
##   0 BUILDING card, one click: Easy Part on, no chooser
##   1 SEAT a round disc on the floor, pulled up 2 cm: one body, about 300 mm across
##   2 LEG a 4 cm square drawn under the seat (camera from below), pulled down 45 cm: one body, box min y -450 mm
##   3 RING Repeat it, Ring, How many 3: the pattern has 3 copies, one body, no failed step
##   3b DEAD END the seat stays round after the Ring (Ring copies the whole stool so far)
##   4 BRACE a round ring brace between the legs, about 25 cm below the seat: one body, box min y between -300 and -150 mm   (11-01: bar 4 now measures the brace ALONE, 4a size, 4b height)
##   5 WORDS no visible word with sketch / extrude / body / profile / fillet / pattern / feature / plane while the walk runs
## Shots: C:/Temp/claude/fstool/*.png (LOOK at them)
const SHOT := "C:/Temp/claude/fstool"
const DIRT := "user://fstool_test"
const JARGON := ["sketch", "extrude", "body", "profile", "fillet", "pattern", "feature", "plane"]

var fails := 0
var m: Node
var words_bad: Array = []


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


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


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


func draw_round(c: Vector3, edge: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(c), scr(edge))


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
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("open")
	check_words("open")

	# 1 SEAT: a round disc of radius 15 cm drawn on the floor, pulled up 2 cm
	await draw_round(Vector3.ZERO, Vector3(0.15, 0.0, 0.0))
	await pull(2.0)
	var bs := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bs.size.x - 300.0) < 25.0 and absf(bs.size.z - 300.0) < 25.0,
		"1 SEAT a round seat, one body, about 300 mm across (box %s)" % bs)
	await shot("seat")
	check_words("seat")

	# 2 LEG: a 4 cm square under the seat at radius 12 cm, drawn from below, pulled down 45 cm
	m.pitch = 35.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await draw_floor(Vector3(0.10, 0.0, -0.02), Vector3(0.14, 0.0, 0.02))
	await pull(45.0)
	var bl := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bl.position.y + 450.0) < 5.0,
		"2 LEG one leg under the seat, one body, box min y %.1f (want -450)" % bl.position.y)
	await shot("leg")
	check_words("leg")

	# 3 RING: Repeat it, Ring, How many 3
	m.pitch = -25.0
	m._cam()
	await idle(40)
	await click_ctl(ep().make_btns["repeat"])
	await idle(5)
	await click_ctl(ep().rep_btns["ring"])
	for r in ep().rep_rows:
		if String(r["key"]) == "count":
			await drag_slider(r["slider"], 3.0)
	await settle(1.5)
	var pt := last_of("pattern")
	ok(int(pt.get("count", 0)) == 3 and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"3 RING three legs round the seat, one body, no failed step: count %s" % str(pt.get("count", 0)))
	await shot("ring")
	check_words("ring")
	# 3b DEAD END: Ring copies the whole stool so far, the seat too: the seat must stay round (about 300 mm across, not a clover)
	var bx := bbox()
	ok(bx.size.x < 330.0, "3b RING the seat stays round: box x %.0f mm (a round seat is about 300 mm)" % bx.size.x)

	# 4 BRACE: a round ring between the legs, about 25 cm below the seat (DEAD END: Draw shape only lays a shape on the floor plane or a face; no way to lift it to leg height)
	await draw_round(Vector3.ZERO, Vector3(0.12, 0.0, 0.0))
	await pull(2.0)
	# bar 4 rewritten 11-01 per Nick (PLAN_FRIDAY.md item 2 "fstool bar 4 - Nick decision: measure the brace alone vs legs not to -450 mm", from the
	# worker report fstooly / fstoolyr: the old bar read the WHOLE part's box, whose min y is always the leg's -450, so a brace at leg height could
	# never move it; commit 4535348d FSTOOL named the dead end "no way to put a brace at leg height"). Now the brace is measured ALONE: its own
	# steps (the newest plane, sketch and extrude) replayed as a piece of their own.
	var feats: Array = m.S.part.get("features", [])
	var alone := Part.make("Brace alone")
	var bf := []
	for f in feats.slice(feats.size() - 3):
		var f2: Dictionary = (f as Dictionary).duplicate(true)
		if String(f2["t"]) == "extrude":
			f2["op"] = "new"
			f2.erase("into")
		bf.append(f2)
	alone["features"] = bf
	alone["seq"] = 3
	var ra: Dictionary = Part.replay(alone)
	var ab: AABB = ra["aabb"]
	var abb := AABB(ab.position / Part.MM, ab.size / Part.MM)
	ok(int(pu().res.get("bodies", 0)) == 1 and int(ra["bodies"]) == 1 and abs(abb.size.x - 240.0) < 15.0 and abs(abb.size.z - 240.0) < 15.0 and abs(abb.size.y - 20.0) < 1.0,
		"4a BRACE alone: a ring (round) piece about 240 mm across and 20 mm thick, joined into one body (own box %s)" % str(abb))
	ok(abb.position.y < -150.0 and abb.position.y > -300.0,
		"4b BRACE alone sits about 25 cm below the seat (its own box min y %.1f, max y %.1f; DEAD END: Draw shape lays the ring on the seat's top face, there is no way to lower it to leg height)" % [abb.position.y, abb.end.y])
	await shot("brace")

	# 5 WORDS
	ok(words_bad.is_empty(), "5 WORDS no jargon on screen during the walk: %s" % [words_bad])

	print("fstool: %d fail" % fails)
	quit(1 if fails > 0 else 0)
