extends SceneTree
## FHANDLE (Nick 2026-10-28: free 3D building, like Fusion 360, anything, nothing forced): a beginner from the BUILDING card builds a
## door handle by real clicks and drags at 1280 x 720, never having read a manual.
##   BUILDING card (one click) -> Draw shape (box) on the floor = the back plate (130 x 40 mm) -> Pull it up 5 mm
##   -> Curvy line drawn as a closed bent loop on the plate top face (the lever bar, 12 mm wide) -> Pull it up 10 mm (joins the plate)
##   -> Round the edges -> Mirror that (the other side of the middle line).
## Bars (run on the old code before the fix: see the report for the FAIL lines):
##   H0 the BUILDING card, one click: page BUILD, Easy Part on, the chooser is not open
##   H1 the plate is one body, 130 x 40 x 5 mm
##   H2 the closed Curvy loop on the plate top: the words name Pull it up (not a sweep, not a pipe)
##   H3 Pull it up on the loop: still one body, the lever is a real bar (5 to 50 pct of the plate volume)
##   H4 Round the edges: one fillet step, no failed step, one body, the box keeps its size
##   H5 Mirror that: one body, the volume grows by one lever (within 10 pct), ONE undo step, no failed step
##   H6 Undo takes the mirror back out (the volume is the one before the mirror)
##   H7 no jargon (sketch, extrude, body, profile, fillet, loft, feature, plane, boolean) on the words during the walk
##   H8 the handle's box stays on screen once the view settles
## shots: C:/Temp/claude/fhandle/ (open, plate, lever, round, mirror; LOOK at them)
const SHOT := "C:/Temp/claude/fhandle"
const DIRT := "user://fhandle_test"
const JARGON := ["sketch", "extrude", "body", "profile", "fillet", "loft", "feature", "plane", "boolean"]

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


## a real drag through the screen points in order (held), release at the last
func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		for i in range(1, 9):
			await ev_move(a.lerp(b, i / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


## a real drag of a slider knob to value v (the pull slider is in cm)
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


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## Draw shape (box) on the floor from world a to b (metres), a real drag
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_path([scr(a), scr(b)])
	await click_ctl(ep().make_btns["draw"])


## Pull it up, then the slider to h cm
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


func box_on_screen(bb: AABB) -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	for i in 8:
		var c := bb.position + Vector3(bb.size.x * float(i & 1), bb.size.y * float((i >> 1) & 1), bb.size.z * float((i >> 2) & 1))
		var p := scr(c)
		if p.x < 0.0 or p.y < 0.0 or p.x > vs.x or p.y > vs.y:
			return false
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

	# H0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	if not pu().easy and pu().easy_open_btn != null and pu().easy_open_btn.is_visible_in_tree():
		await click_ctl(pu().easy_open_btn)
		await idle(10)
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and not chooser_open,
		"H0 BUILDING card, one click -> Easy Part on, no chooser (page %s, easy %s, chooser %s)" % [m.cur_page, pu().easy, chooser_open])
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -55.0   # negative pitch looks DOWN from above (positive looks up from below: the loop then lands on the underside)
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("open")
	check_words("open")

	# H1 the back plate: 130 x 40 mm on the floor, pulled up 6 mm (the slider steps 2 mm from 2 mm)
	await draw_floor(Vector3(-0.065, 0.0, -0.02), Vector3(0.065, 0.0, 0.02))
	await pull(0.6)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var sz := bb1.size / Part.MM
	ok(int(s1["bodies"]) == 1 and absf(sz.x - 130.0) < 1.0 and absf(sz.z - 40.0) < 1.0 and absf(sz.y - 6.0) < 1.0,
		"H1 the back plate is one body, %.1f x %.1f x %.1f mm (want 130 x 40 x 6)" % [sz.x, sz.z, sz.y])
	check_words("plate")
	await shot("plate")

	# H2 the lever: a closed bent loop, 12 mm wide, drawn on the plate top face (Curvy line)
	var top_y := bb1.end.y
	var cl := [Vector2(0.010, 0.0), Vector2(0.030, 0.0), Vector2(0.045, 0.012), Vector2(0.058, 0.012)]
	var loop_w: Array = []
	for i in cl.size():
		loop_w.append(Vector3(cl[i].x, top_y, cl[i].y - 0.006))
	for i in range(cl.size() - 1, -1, -1):
		loop_w.append(Vector3(cl[i].x, top_y, cl[i].y + 0.006))
	loop_w.append(loop_w[0])
	m.pitch = -60.0
	m.yaw = 15.0
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["curve"])
	var sp: Array = []
	for w in loop_w:
		sp.append(scr(w))
	await drag_path(sp)
	var said2 := String(ep().msg) + " | " + String(ep().hint_l.text)
	ok(said2.to_lower().find("pull it up") >= 0 and said2.to_lower().find("pipe") < 0 and said2.to_lower().find("sweep") < 0,
		"H2 the closed Curvy loop names Pull it up (words: [%s])" % said2)
	check_words("curve")
	await shot("lever_drawn")

	# H3 Pull it up on the loop: the lever joins the plate
	var plate_v := vol_mm3(solid())
	await pull(1.0)
	var s3 := solid()
	var lever_v := vol_mm3(s3) - plate_v
	ok(int(s3["bodies"]) == 1 and lever_v > 0.05 * plate_v and lever_v < 0.5 * plate_v,
		"H3 the lever joins the plate: one body, +%.0f mm3 (plate %.0f mm3)" % [lever_v, plate_v])
	var bb3: AABB = s3["aabb"]
	var top3 := bb3.end.y / Part.MM
	var lever_top := (top_y + 0.010) / Part.MM
	ok(absf(top3 - lever_top) < 0.5 and bb3.position.y / Part.MM > -0.5,
		"H3c the lever stands 10 mm up from the plate top, not down through the floor (top %.1f mm, want %.1f; bottom %.1f mm)" % [top3, lever_top, bb3.position.y / Part.MM])
	m.target = Vector3(0.02, top_y + 0.005, 0.0)
	m.pitch = -30.0
	m.yaw = 30.0
	m.dist = 0.3
	m._cam()
	await idle(40)
	await shot("lever")
	m.target = Vector3(0.035, top_y + 0.005, 0.0)   # close, straight down: the lever's plan
	m.pitch = -85.0   # negative pitch looks down from above (the view from below shows the BOTTOM cube face)
	m.yaw = 0.0
	m.dist = 0.22
	m._cam()
	await idle(60)
	await shot("lever_top")

	# H4 Round the edges
	await click_ctl(ep().make_btns["round"])
	await idle(10)
	var s4 := solid()
	var bb4: AABB = s4["aabb"]
	var fl := false
	for f in m.S.part.get("features", []):
		if String(f["t"]) == "fillet":
			fl = true
	ok(fl and (s4["errors"] as Dictionary).is_empty() and int(s4["bodies"]) == 1 and absf(bb4.size.x - s3["aabb"].size.x) < 0.5e-3,
		"H4 Round the edges: one round step, no failed step, one body (words [%s])" % String(ep().msg))
	check_words("round")
	await settle(1.0)
	await shot("round")

	# H5 Mirror that: the other side of the middle line
	var v5b := vol_mm3(solid())
	var ub5: int = m.undo.size()
	await click_ctl(ep().make_btns["mirror"])
	await idle(10)
	var s5 := solid()
	var added := vol_mm3(s5) - v5b
	ok(int(s5["bodies"]) == 1 and absf(added - lever_v) < 0.10 * lever_v and m.undo.size() == ub5 + 1 and (s5["errors"] as Dictionary).is_empty(),
		"H5 Mirror that: one body, +%.0f mm3 (one lever %.0f), one undo step (%d -> %d)" % [added, lever_v, ub5, m.undo.size()])
	check_words("mirror")
	await settle(1.0)
	await shot("mirror")
	var bb5: AABB = s5["aabb"]
	ok(box_on_screen(bb5), "H8 the handle is on screen once the view settles (box %s)" % bb5)

	# H6 Undo takes the mirror back out (Ctrl+Z)
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.physical_keycode = KEY_Z
	ev.ctrl_pressed = true
	ev.pressed = true
	root.push_input(ev, true)
	await idle(10)
	var v6 := vol_mm3(solid())
	ok(absf(v6 - v5b) < 0.5, "H6 Undo takes the mirror back out (volume %.0f, before the mirror %.0f)" % [v6, v5b])

	# H7 no jargon on the words during the walk
	ok(words_bad.is_empty(), "H7 no jargon on the words during the walk: %s" % [words_bad])

	print("fhandle: %d fail" % fails)
	quit(1 if fails > 0 else 0)
