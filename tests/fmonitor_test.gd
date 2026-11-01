extends SceneTree
## FMONITOR (Nick 2026-10-28): a beginner from the REAL start screen builds a computer monitor with real clicks at 1280 x 720.
## Bars:
##   N0 the BUILDING card, one click: page BUILD, a blank part, the words name Easy
##   N1 the screen: one body, thin (depth <= 3 cm), wide (>= 15 cm), tall (>= 10 cm)
##   N2 rounded corners: Round the edges takes volume off the screen (>= 0.1%), no failed step
##   N3 the screen is dark: a Dark colour chip exists and paints the screen body under brightness 0.2
##   N4 the neck: one body, the volume grows by a neck (r 2.5 cm, 10 cm tall, within 10%)
##   N5 the base: one body, the volume grows by a disc (r 6 cm, 1 cm thick, within 10%)
##   N6 the base is OVAL (x and z extents differ by 20%): Easy Draw shape has only Box / Round / Pointy
## shots: C:/Temp/claude/fmonitor/screen.png, dark.png, neck.png, monitor.png
const SHOT := "C:/Temp/claude/fmonitor"
const DIRT := "user://fmonitor_test"
var fails := 0
var m: Node
var ep: Node


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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the How far slider the last Pull it up opened: a real click on its track at the fraction of the cm value
func set_how_far(cm: float) -> bool:
	var sl: HSlider = ep.rows_vb.find_child("easypart_slider_last", true, false) as HSlider   # the newest step's slider (its name: easypart_slider_last)
	if sl == null or not sl.is_visible_in_tree():
		return false
	var f := (cm - sl.min_value) / maxf(sl.max_value - sl.min_value, 0.0001)
	var r := sl.get_global_rect()
	var gw := float(sl.get_theme_icon("grabber").get_width())   # the knob: grab it where it sits, drag it to the cm value
	var y := r.get_center().y
	var x0 := r.position.x + gw * 0.5 + (sl.value - sl.min_value) / maxf(sl.max_value - sl.min_value, 0.0001) * (r.size.x - gw)
	var x1 := r.position.x + gw * 0.5 + f * (r.size.x - gw)
	await ev_move(Vector2(x0, y), false)
	await ev_mouse(Vector2(x0, y), true)
	for k in range(1, 9):
		await ev_move(Vector2(lerpf(x0, x1, k / 8.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(6)
	return true


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and note_words.find("Easy") >= 0,
		"N0 BUILDING card, one click: page BUILD, a blank part, the words name Easy (page %s, words [%s])" % [m.cur_page, note_words])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	ep = pu.ep
	m.target = Vector3(0.0, 0.05, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# N1 the screen: a thin box on the grid, pulled up 13 cm
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.10, 0.0, -0.01)), scr(Vector3(0.10, 0.0, 0.01))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	var slid := await set_how_far(13.0)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var v1 := vol_mm3(s1)
	var depth_cm := bb1.size.z * 100.0
	var wide_cm := bb1.size.x * 100.0
	var tall_cm := bb1.size.y * 100.0
	ok(int(s1["bodies"]) == 1 and depth_cm <= 3.0 and wide_cm >= 15.0 and tall_cm >= 10.0 and slid,
		"N1 the screen: one body, %.1f x %.1f x %.1f cm (w x depth x tall), volume %.0f mm3" % [wide_cm, depth_cm, tall_cm, v1])
	await shot("screen")

	# N2 rounded corners: Round the edges on the screen
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var lost := (v1 - v2) / maxf(v1, 1.0)
	ok(lost >= 0.001 and (s2["errors"] as Dictionary).is_empty() and int(s2["bodies"]) == 1,
		"N2 rounded corners (a corner of 1.5 mm or more): Round the edges took %.2f%% off the screen, one body, no failed step" % [lost * 100.0])

	# N3 colour the screen dark (Colour -> Dark), before the neck is added
	await click_ctl(ep.make_btns["colour"])
	var dark_btn = ep.colour_box.find_child("easypart_colour_dark", true, false)
	var dark_ok := false
	if dark_btn != null:
		await click_ctl(dark_btn)
		var looks: Array = pu.res.get("body_looks", [])
		var c: Color = Part.look_at(looks, 0)["c"]
		dark_ok = c.get_luminance() < 0.2
	ok(dark_ok, "N3 the screen is dark: the Dark chip exists and paints the screen under brightness 0.2 (chip %s)" % [dark_btn != null])
	await shot("dark")

	# N4 the neck: a round shape on the grid behind the screen's bottom, pulled up 10 cm (joins the screen)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(Vector3(0.0, 0.0, -0.01)), scr(Vector3(0.025, 0.0, -0.01))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await set_how_far(10.0)
	var s4 := solid()
	var v4 := vol_mm3(s4)
	var neck_v := v4 - v2
	# the neck's centre sits on the screen's back face (z -1 cm): the part of its round inside the 2 cm screen is not new volume
	var h := 20.0
	var over := h * sqrt(625.0 - h * h) + 625.0 * asin(h / 25.0)   # mm2 of the round inside the screen's 2 cm slab
	var neck_want := (PI * 625.0 - over) * 100.0
	ok(int(s4["bodies"]) == 1 and absf(neck_v - neck_want) < 0.10 * neck_want,
		"N4 the neck: one body, +%.0f mm3 (a 2.5 cm round 10 cm tall, outside the screen, is %.0f)" % [neck_v, neck_want])
	await shot("neck")

	# N5 the base: an OVAL on the grid (Draw shape > Oval, a 22 x 9 cm drag box, a little wider than the 20 cm screen), 1 cm thick, joins the neck
	# N5/N6 rewritten 11-01 per Nick. N5: the expected volume is the UNION, not a lone disc: the base's footprint overlaps the screen's slab
	# and the neck, so only the part of the oval outside both is new (it was a lone 6 cm round, 113097 mm3, but the union adds about 78500).
	# Computed here from the shapes, not copied from a measurement: the oval, the screen strip |z| <= 10 and the neck's round (centre z -10, r 25)
	# are sampled on a 0.5 mm grid. N6: design changed in 24d176c8 FSPOON: Easy Part Draw shape gets an Oval chip (a closed bspline outline,
	# no "ellipse" entity), so the test now really presses Oval and reads the closed outline's x and z extents.
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["oval"])
	await drag_pts([scr(Vector3(-0.11, 0.0, -0.045)), scr(Vector3(0.11, 0.0, 0.045))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await set_how_far(1.0)
	var s5 := solid()
	var v5 := vol_mm3(s5)
	var base_v := v5 - v4
	# the oval as drawn: its half extents and centre in world x and z (mm), read from the closed outline's points
	var ox0 := INF
	var ox1 := -INF
	var oz0 := INF
	var oz1 := -INF
	for f in m.S.part["features"]:
		for e in f.get("ents", []):
			if String(e.get("k", "")) == "bspline" and bool(e.get("closed", false)):
				for q in e["pts"]:
					var wq: Vector3 = Part.to_world(Part.plane(String(f.get("plane", "top"))), Vector2(float(q[0]), float(q[1])))
					ox0 = minf(ox0, wq.x)
					ox1 = maxf(ox1, wq.x)
					oz0 = minf(oz0, wq.z)
					oz1 = maxf(oz1, wq.z)
	var ocx := (ox0 + ox1) * 0.5 / Part.MM
	var ocz := (oz0 + oz1) * 0.5 / Part.MM
	var orx := (ox1 - ox0) * 0.5 / Part.MM
	var orz := (oz1 - oz0) * 0.5 / Part.MM
	var cells := 0
	var zz := ocz - orz
	while zz <= ocz + orz:
		var xx := ocx - orx
		while xx <= ocx + orx:
			var in_oval := ((xx - ocx) / orx) * ((xx - ocx) / orx) + ((zz - ocz) / orz) * ((zz - ocz) / orz) <= 1.0
			var in_screen := absf(zz) <= 10.0 and absf(xx) <= 100.0
			var in_neck := xx * xx + (zz + 10.0) * (zz + 10.0) <= 625.0
			if in_oval and not in_screen and not in_neck:
				cells += 1
			xx += 0.5
		zz += 0.5
	var base_want := float(cells) * 0.25 * 10.0
	ok(int(s5["bodies"]) == 1 and absf(base_v - base_want) < 0.10 * base_want,
		"N5 the base: one body, +%.0f mm3 (an oval %.0f x %.0f cm, 1 cm thick, outside the screen slab and the neck, is %.0f; a lone disc would be 113097)" % [base_v, orx * 0.2, orz * 0.2, base_want])
	# N6: the Oval chip draws one closed outline whose x and z extents differ by 20% or more
	var oval_dx := 0.0
	var oval_dz := 0.0
	var ovals := 0
	for f in m.S.part["features"]:
		for e in f.get("ents", []):
			if String(e.get("k", "")) == "bspline" and bool(e.get("closed", false)) and (e.get("pts", []) as Array).size() >= 12:
				var lo := Vector2(INF, INF)
				var hi := Vector2(-INF, -INF)
				for q in e["pts"]:
					lo = lo.min(Vector2(float(q[0]), float(q[1])))
					hi = hi.max(Vector2(float(q[0]), float(q[1])))
				ovals += 1
				oval_dx = hi.x - lo.x
				oval_dz = hi.y - lo.y
	ok(ovals == 1 and absf(oval_dx - oval_dz) >= 0.2 * maxf(oval_dx, oval_dz),
		"N6 the base is oval: %d closed outline from the Oval chip, extents %.1f x %.1f mm (differ by %.0f%%, want 20%% or more)" % [ovals, oval_dx, oval_dz, 100.0 * absf(oval_dx - oval_dz) / maxf(maxf(oval_dx, oval_dz), 1.0)])
	await shot("monitor")
	print("fmonitor: %d fail" % fails)
	quit(1 if fails > 0 else 0)
