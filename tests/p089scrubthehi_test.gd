extends SceneTree
## p089scrubthehi (Friday plan item 89, Nick: monkey-brain easy): Scrub the history. A slider in the step list of Easy Part replays the build
## step by step: drag it back and the part is shown as it stood after the first N steps; drag to the end and all of it is back. A view only:
## no undo step, the record does not change. Real clicks at 1280 x 720 from the real start screen. Every number is measured from the BUILT
## result the view shows (the PartUI's res: the replay of the shown steps), never from the code's own variables.
##   S0 the box: Draw shape, Box chip, drag 40 mm on the grid, Pull it up; How far to 3 cm; Round the top edges, How round 2 mm
##   S1 the scrub slider (easypart_scrub) sits in the step list at the end: its value is the step count and its label says all of them
##   S2 a click on the slider to the step after the pull: the view shows the box 30 mm tall, the rounds NOT there (lost 0 pct of the box)
##   S3 the view changed by the scrub and not the record: the undo list did not move and the record JSON is the same
##   S4 a click to step 1 (the shape only): the view shows no solid; the label says Showing step 1
##   S5 a click back to the end: the rounds are there again (lost to the rounds within 15 pct of the want), the view is the whole part
## shots: C:/Temp/claude/p089scrubthehi/scrub.png, back.png
const SHOT := "C:/Temp/claude/p089scrubthehi"
const DIRT := "user://p089scrubthehi_test"
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
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


func mm(v: float) -> float:
	return v / Part.MM


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the newest step's slider (How far, How round...), or null
func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


func scrub_slider() -> HSlider:
	return find_named(m, "easypart_scrub") as HSlider


func scrub_label() -> String:
	var l := find_named(m, "easypart_scrub_label") as Label
	return String(l.text) if l != null else ""


## a real click on the slider's track at value v (the grabber centre sits at v; the track's ends keep half a grabber in)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := sl.get_theme_icon("grabber")
	var gw := float(g.get_width()) if g != null else 16.0
	var frac := (v - sl.min_value) / maxf(sl.max_value - sl.min_value, 0.0001)
	var lx := gw * 0.5 + frac * (sl.size.x - gw)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


## the view's built result (what the part shows now): the replay of the shown steps, read from the part UI
func shown() -> Dictionary:
	return m.bld.part.res


func shown_vol_mm3(s: Dictionary) -> float:
	var tot := 0.0
	for v in s.get("volumes", []):
		tot += float(v)
	return tot / (Part.MM * Part.MM * Part.MM)


## the loss of the rounds on the top four edges of a W x D box (mm3): (1 - pi/4) r^2 x the top perimeter
func round_loss(W: float, D: float, r: float) -> float:
	return (1.0 - PI / 4.0) * r * r * (2.0 * W + 2.0 * D)


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
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# S0 the box, pulled 3 cm, then the top edges rounded 2 mm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await slide_to(last_slider(), 3.0)
	await click_ctl(ep.round_btns["top"])
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	await slide_to(last_slider(), 0.2)
	var feats: Array = m.S.part.get("features", [])
	var n := feats.size()
	var k_pull := 0
	for i in n:
		if String(feats[i].get("t", "")) == "extrude":
			k_pull = i + 1
	var whole := shown()
	var whole_v := shown_vol_mm3(whole)
	var whole_bb: AABB = whole["aabb"]
	var W := mm(whole_bb.size.x)
	var D := mm(whole_bb.size.z)
	ok(int(whole["bodies"]) == 1 and k_pull > 0 and k_pull < n,
		"S0 the part is built: %d steps, the pull is step %d, %d body" % [n, k_pull, int(whole["bodies"])])

	# S1 the scrub slider is in the step list, at the end, and its label says all the steps
	var sl := scrub_slider()
	var at_end := sl != null and absf(sl.value - sl.max_value) < 0.01 and int(sl.max_value) == n
	ok(at_end and scrub_label().find("Showing all") >= 0,
		"S1 the scrub slider sits at the end: value %s of %d, label %s" % [str(sl.value) if sl != null else "none", n, scrub_label()])
	await shot("scrub")

	# S3 setup for the no-change check: the record and the undo list before the scrub
	var rec_before := JSON.stringify(m.S.part)
	var ub: int = m.undo.size()

	# S2 a click to the step after the pull: the box 30 mm tall, no rounds
	await slide_to(sl, float(k_pull))
	var s2 := shown()
	var bb2: AABB = s2["aabb"]
	var lost2 := mm(bb2.size.x) * mm(bb2.size.z) * mm(bb2.size.y) - shown_vol_mm3(s2)
	ok(int(s2["bodies"]) == 1 and absf(mm(bb2.size.y) - 30.0) <= 0.3 and absf(lost2) <= 0.01 * W * D * 30.0,
		"S2 the view after the pull: built height %.2f mm (want 30 +-0.3), lost %.2f mm3 to rounds (want 0, 1 pct of the box)" % [mm(bb2.size.y), lost2])
	ok(scrub_label().find("Showing step %d of %d" % [k_pull, n]) >= 0,
		"S2b the label names the step: %s" % scrub_label())
	await shot("scrub_mid")

	# S3 the view moved, the record and the undo list did not
	ok(JSON.stringify(m.S.part) == rec_before and m.undo.size() == ub,
		"S3 the scrub is a view only: record unchanged %s, undo list %d -> %d" % [JSON.stringify(m.S.part) == rec_before, ub, m.undo.size()])

	# S4 a click to step 1: the shape only, no solid
	await slide_to(sl, 1.0)
	var s4 := shown()
	ok(int(s4["bodies"]) == 0 and scrub_label().find("Showing step 1") >= 0,
		"S4 step 1 is the shape only: %d bodies, label %s" % [int(s4["bodies"]), scrub_label()])

	# S5 back to the end: the rounds are there, the view is the whole part again
	await slide_to(sl, float(n))
	var s5 := shown()
	var bb5: AABB = s5["aabb"]
	var lost5 := mm(bb5.size.x) * mm(bb5.size.z) * mm(bb5.size.y) - shown_vol_mm3(s5)
	var want5 := round_loss(W, D, 2.0)
	ok(absf(lost5 - want5) <= 0.15 * want5 and absf(shown_vol_mm3(s5) - whole_v) <= 0.01 * whole_v and scrub_label().find("Showing all") >= 0,
		"S5 back to the end: lost %.1f mm3 to the rounds (want %.1f, 15 pct), volume %.1f = the whole part %.1f" % [lost5, want5, shown_vol_mm3(s5), whole_v])
	await shot("back")

	print("p089scrubthehi %d fails" % fails)
	quit(1 if fails > 0 else 0)
