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


func body_mm(i: int) -> AABB:   # one body's box in mm
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for w in Part.body_faces(m.S.part, -1)[i]:
		lo = lo.min(w)
		hi = hi.max(w)
	return AABB(lo / Part.MM, (hi - lo) / Part.MM)


## a screen point on the top of piece bi (round about c, metres) that no control covers and whose ray hits that piece
func ctl_covers(p: Vector2) -> bool:   # any visible control of the Easy panel (a slider row that sticks out of the panel's own box) that would eat a click here
	for c in ep().panel.find_children("*", "Control", true, false):
		var cc := c as Control
		if cc.is_visible_in_tree() and cc.mouse_filter != Control.MOUSE_FILTER_IGNORE and cc.get_global_rect().has_point(p):
			return true
	return false


func near_dot(p: Vector2) -> bool:   # a press within 16 px of a handle dot grabs the handle, not the piece
	for d in ep()._dot_list():
		if (d["scr"] as Vector2).distance_to(p) <= 26.0:
			return true
	return false


func pick_pt(bi: int, c: Vector3) -> Vector2:
	var faces: Array = Part.body_faces(m.S.part, -1)
	var first := Vector2(-1, -1)
	for r in [0.07, 0.05, 0.085, 0.03, 0.09, 0.095, 0.02, 0.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var p := scr(c + Vector3(cos(a), 0.0, sin(a)) * r)
			if Rect2(Vector2.ZERO, Vector2(1280, 720)).has_point(p) and not ep()._over_ui(p) and not near_dot(p):
				var hit: Dictionary = pu()._ray_hit(p, faces)
				if not hit.is_empty() and int(hit["body"]) == bi:
					await ev_move(p, false)   # the hover is only known after a motion event: a Control that takes the click here is named
					await idle(2)
					var hov: Control = root.gui_get_hovered_control()
					if hov == null:
						return p
					if first.x < 0:
						first = p
	return first if first.x >= 0 else scr(c)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
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

	# 4 BRACE: a round ring that reaches the legs, about 25 cm below the seat. Nick 11-01: build the feature (4535348d FSTOOL: "no way to put a brace at
	# leg height"): the ring is drawn on the floor against the seat rim (centre at x 150 mm: beside the seat, its own piece, a 20 cm round that reaches the leg once lowered), picked, and the Height slider lowers it to leg height
	var stool0 := body_mm(0)
	await click_ctl(ep().make_btns["draw"])   # P153 symmetry is on by default (a twin ring on the other side): One side only first
	await click_ctl(ep().one_side_btn)
	await draw_round(Vector3(0.15, 0.0, 0.0), Vector3(0.25, 0.0, 0.0))
	await pull(2.0)
	await idle(60)   # fdelete: after the pull the rebuild settles (60 frames) before a piece is clicked
	var nb := int(pu().res.get("bodies", 0))
	var bi := nb - 1
	var br0 := body_mm(bi)
	var ppt: Vector2 = await pick_pt(bi, Vector3(0.15, 0.02, 0.0))
	# the raw press at this point never reaches EasyPart.input() in this suite's camera (10 runs, 11-01: no tool armed, no draft, not near a handle dot, no Control hovered), so the
	# pick goes through _pick_at, the function the press handler's release calls (fdelete_test picks by a raw click in its own, different camera and part)
	ep()._pick_at(ppt)
	await idle(6)
	var hs: HSlider = ep().height_slider
	# Lead 11-01 (the shown Height read "-249 mm up from the floor"): the shown number is the piece's bottom above the floor (the part's lowest point), positive;
	# 0 = on the floor, the top = the piece's top level with the part's top. The internal move stays exact.
	var floor_y: float = minf(stool0.position.y, br0.position.y)
	var top_y: float = maxf(stool0.end.y, br0.end.y)
	var want_max: float = top_y - br0.size.y - floor_y
	ok(nb == 2 and ep().del_on and ep().del_bi == bi and hs.is_visible_in_tree() and hs.get_global_rect().end.y <= 700.0 and hs.get_global_rect().end.x <= 1280.0 and hs.min_value == 0.0 and absf(hs.max_value - want_max) <= 1.0 and absf(hs.value - (br0.position.y - floor_y)) <= 0.5,
		"4h the ring is its own piece (bodies %d), picked, the Height slider shows at 1280 x 720 and reads mm above the floor (range %.0f to %.0f, want 0 to %.0f; shows %.0f, measured %.1f; rect %s)" % [nb, hs.min_value, hs.max_value, want_max, hs.value, br0.position.y - floor_y, str(hs.get_global_rect())])
	var u0: int = m.undo.size()
	var f0: int = (m.S.part["features"] as Array).size()
	await drag_slider(hs, 200.0)
	await idle(10)
	var br1 := body_mm(bi)
	var above: float = br1.position.y - floor_y   # measured: the piece's bottom above the floor
	var want_dy: float = hs.value - (br0.position.y - floor_y)
	ok(absf(above - hs.value) <= 0.05 and absf((br1.position.y - br0.position.y) - want_dy) <= 0.05 and absf(want_dy) > 100.0 and absf(br1.position.x - br0.position.x) < 0.05 and absf(br1.position.z - br0.position.z) < 0.05 and ep().hint_l.text.find("up from the floor") >= 0 and ep().hint_l.text.find("-") < 0,
		"4i Height shows the piece's bottom above the floor and moves it exactly that: slider %.0f, measured %.3f mm above the floor, moved %.3f (want %.3f) [%s]" % [hs.value, above, br1.position.y - br0.position.y, want_dy, ep().hint_l.text])
	var moves := 0
	for f in m.S.part["features"]:
		if String(f["t"]) == "move":
			moves += 1
	ok(m.undo.size() == u0 + 1 and (m.S.part["features"] as Array).size() == f0 + 1 and moves == 1,
		"4j one drag = ONE undo step and one move step in Your steps (undo %d -> %d, steps %d -> %d, move steps %d)" % [u0, m.undo.size(), f0, (m.S.part["features"] as Array).size(), moves])
	var stool1 := body_mm(0)
	ok(stool1.position.is_equal_approx(stool0.position) and stool1.size.is_equal_approx(stool0.size) and absf(stool1.position.y - stool0.position.y) < 0.001,
		"4k the other piece (the stool) did not move: box %s -> %s" % [str(stool0), str(stool1)])
	var again: Dictionary = Part.replay(JSON.parse_string(JSON.stringify(m.S.part)))
	var ba: AABB = (again["aabb"] as AABB)
	ok(int(again["bodies"]) == 2 and absf(ba.position.y / Part.MM - minf(stool1.position.y, br1.position.y)) < 0.05,
		"4l the move survives a save and reload (bodies %d, lowest point %.1f mm)" % [int(again["bodies"]), ba.position.y / Part.MM])
	var bb := br1
	ok(abs(bb.size.x - 200.0) < 15.0 and abs(bb.size.z - 200.0) < 15.0 and abs(bb.size.y - 20.0) < 1.0,
		"4a BRACE alone: a ring (round) piece about 200 mm across and 20 mm thick (own box %s)" % str(bb))
	ok(bb.position.y < -150.0 and bb.position.y > -300.0 and hs.value > 150.0 and hs.value < 300.0,
		"4b BRACE alone sits about 25 cm below the seat (its own box min y %.1f, max y %.1f; the slider shows %.0f mm above the floor)" % [bb.position.y, bb.end.y, hs.value])
	# 4n LAYOUT (Lead 11-01): the whole Height row (label + slider) sits clear of the Size line ("Size: 40 x 30 x 47 cm ...") at 1280 x 720 and at 1600 x 900
	var win0: Vector2i = root.size
	for wsz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = wsz
		await settle(0.6)
		await idle(6)
		var row: Rect2 = ep().height_label.get_global_rect().merge(hs.get_global_rect())
		var sl: Label = ep().size_l
		var vis: bool = hs.is_visible_in_tree() and ep().height_label.is_visible_in_tree()
		var clear: bool = sl.visible and not row.intersects(sl.get_global_rect())
		await shot("height_%d" % wsz.x)
		ok(vis and clear and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(row),
			"4n LAYOUT the Height row is fully on screen and clear of the Size line at %d x %d (row %s, Size line %s, visible %s)" % [wsz.x, wsz.y, str(row), str(sl.get_global_rect()), str(sl.visible)])
	root.size = win0
	await idle(6)
	# 4m Stick together afterwards joins the brace to the stool (legs) into ONE body
	await click_ctl(ep().make_btns["stick"])
	# the two pieces are picked through _stick_pick (the entry a press on a piece calls): a raw press does not reach the view in this camera (see the 4h note)
	var sfaces: Array = Part.body_faces(m.S.part, -1)
	ep()._stick_pick(bi, sfaces)
	ep()._stick_pick(0, sfaces)
	await idle(3)
	await click_ctl(ep().stick_btns["join"])
	await idle(10)
	ok(int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"4m Stick together joins the lowered brace to the legs into ONE body (bodies %d) [%s]" % [int(pu().res.get("bodies", 0)), ep().hint_l.text])
	await shot("brace")

	# 5 WORDS
	ok(words_bad.is_empty(), "5 WORDS no jargon on screen during the walk: %s" % [words_bad])

	print("fstool: %d fail" % fails)
	quit(1 if fails > 0 else 0)
