extends SceneTree
## FRULER (Nick 2026-10-28, free 3D building: build a ruler 300 mm exactly with tick marks cut, Repeat it Row of thin cuts, check the exact size in Expert).
## Real clicks and drags at 1280 x 720 from the start screen: BUILDING card (one click, a blank Easy Part), a ruler drawn on the floor and pulled up,
## one tick cut into its top face (Cut a hole takes the drawn shape), Repeat it Row of that cut, How many dragged to 12, then Expert.
## Bars (run on the old code before the change: 2 and 3 FAILED: Repeat it copied the whole ruler, no row of cuts):
##   1 RULER    one body, 300 mm long (x), 20 mm wide (z), 20 mm thick (y), +-0.5 mm
##   2 TICK     one thin tick (3 to 8 mm wide, 10 mm across the top) cut into the top face: one body, the volume drops by width x 10 x 20 mm3 (+-2 pct)
##   3 ROW      Repeat it, Row, How many 12: a pattern step over the cut, 12 copies, the volume is 12 ticks less (+-1 pct), no failed step, the ruler is still 300 mm
##   4 EXPERT   "Exact sizes? Use Expert" opens the same record: the same features (JSON equal), the bounding box is 300 mm, and the Expert note reads "box 300 x 20 x 20 mm"
## Shots: C:/Temp/claude/fruler/ruler.png (after the row), expert.png (Expert with the ruler)
const SHOT := "C:/Temp/claude/fruler"
const DIRT := "user://fruler_test"

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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


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

	# 0 the BUILDING card, one click: a blank Easy Part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -70.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and (m.S.part.get("features", []) as Array).is_empty(), "0 BUILDING card -> a blank Easy Part on page BUILD")

	# 1 RULER: a 300 x 20 mm strip on the floor (the grid snaps to 5 mm), pulled up (the default 2 cm); the camera close and steep, so the 5 mm tick is a few pixels
	m.dist = 0.8
	m.pitch = -70.0
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.15, 0.0, -0.01)), scr(Vector3(0.15, 0.0, 0.01)))
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	var b1 := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(b1.size.x - 300.0) < 0.5 and absf(b1.size.z - 20.0) < 0.5 and absf(b1.size.y - 20.0) < 0.5,
		"1 RULER one body 300 x 20 x 20 mm (bodies %d, box %s)" % [int(pu().res.get("bodies", 0)), b1.size])
	var v0 := vol()

	# 2 TICK: a 5 x 10 mm strip drawn on the top face at x = -140 mm (the camera set again: the Pull settles it), Cut a hole takes that shape (through the ruler)
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.14, 0.02, -0.005)), scr(Vector3(-0.135, 0.02, 0.005)))   # inside the top face (the edge hits the side)
	await click_ctl(ep().make_btns["hole"])
	await idle(10)
	var v1 := vol()
	var tick := v0 - v1
	var tw := 0.0   # the drawn tick's width (mm, along X), read from its sketch: the grid snap decides it
	for f in m.S.part.get("features", []):
		if String(f["t"]) == "sketch" and (f["ents"] as Array).size() == 1 and String((f["ents"] as Array)[0].get("k", "")) == "rect":
			var e0: Dictionary = (f["ents"] as Array)[0]
			tw = absf(float(e0["b"][0]) - float(e0["a"][0]))
	ok(int(pu().res.get("bodies", 0)) == 1 and tw > 3.0 and tw < 8.0 and absf(tick - tw * 200.0) < tw * 200.0 * 0.02,
		"2 TICK one thin tick (%.1f mm wide) cut into the top: the volume drops by width x 10 x 20 mm3 (dropped %.0f, bodies %d)" % [tw, tick, int(pu().res.get("bodies", 0))])

	# 3 ROW: Repeat it (the newest step is the cut), Row, How many dragged to 12
	await click_ctl(ep().make_btns["repeat"])
	await idle(4)
	await click_ctl(ep().rep_btns["row"])
	await idle(4)
	var cnt_row = null
	for r in ep().rep_rows:
		if String(r["key"]) == "count":
			cnt_row = r
	if cnt_row != null:
		await drag_slider(cnt_row["slider"], 12.0)
	await idle(10)
	var rec: Dictionary = m.S.part
	var pats := 0
	var cnt := 0
	for f in rec.get("features", []):
		if String(f["t"]) == "pattern":
			pats += 1
			cnt = int(f.get("count", 0))
	var v2 := vol()
	var want := v0 - 12.0 * tick
	var errs: Dictionary = Part.replay(rec)["errors"]
	ok(pats == 1 and cnt == 12 and errs.is_empty() and absf(v2 - want) < want * 0.01 and absf(bbox().size.x - 300.0) < 0.5,
		"3 ROW Repeat it Row of the cut, 12 copies: one pattern step, volume %.0f (want %.0f), errors %s, box x %.1f" % [v2, want, errs, bbox().size.x])
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -55.0
	m.yaw = 25.0
	m.dist = 1.0
	m._cam()
	await shot("ruler")

	# 4 EXPERT: the same record opens in Expert; its size is 300 mm and 300 shows on screen
	var before_json := JSON.stringify(rec)
	await click_ctl(ep().use_btn)
	await idle(30)
	var rec2: Dictionary = m.S.part
	var rp: Dictionary = Part.replay(rec2)
	var bb: AABB = rp["aabb"]
	bb = AABB(bb.position / Part.MM, bb.size / Part.MM)
	var tx: Array = []
	texts_under(m, tx)
	var has300 := false   # the Expert note: "1 body, volume ... cm3, box 300 x 20 x 20 mm"
	for t in tx:
		if String(t).find("box 300 x 20 x 20 mm") >= 0:
			has300 = true
	var same := JSON.stringify(rec2) == before_json
	ok(same and absf(bb.size.x - 300.0) < 0.5 and has300,
		"4 EXPERT the same record (%s), box x %.2f mm, the box size shows in words %s" % [same, bb.size.x, has300])
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -55.0
	m.yaw = 25.0
	m.dist = 1.0
	m._cam()
	await shot("expert")

	print("fruler: %d fail" % fails)
	quit(1 if fails > 0 else 0)
