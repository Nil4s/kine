extends SceneTree
## FMUG3 (Nick 2026-10-28: "free 3D building, like Fusion 360; the BUILDING card opens a blank part"): a beginner from the REAL
## start screen builds a MUG with real clicks at 1280 x 720, never having read a manual. The walk counts CLICKS (a press on a
## button; drags on the grid are not clicks) from the blank part to the finished mug. Any one step needing more than 3 clicks is a bar.
##   BUILDING card (1) -> Easy (1) -> Draw shape + Round chip + drag a round shape on the grid + Pull it up (3: the body, a round cup)
##   -> Cut a hole + Hollow inside (2: the cup is open at the top with a wall)
##   -> the handle: Draw shape + Box chip + drag a box on the side of the cup + Pull it up (3).
## Bars:
##   G0 the BUILDING card, one click: page BUILD, a blank part, no chooser, the words name Easy
##   G1 the body: one body, round (x and z extents within 3%), 3 clicks or fewer
##   G2 the cup: Cut a hole then Hollow inside (<= 3 clicks), still one body, volume less than the solid body by 20%+
##   G3 the handle: a solid added by Draw shape + Pull it up (<= 3 clicks), one body with the cup
##   G4 the whole walk from the blank part to the mug is at most 14 clicks
##   G7 the cup stands taller than a third of its width after the body steps (a mug, not a puck)
##   G5 no jargon (sketch, extrude, loft, boolean, feature, body) on the words, and no failed step
##   G6 every press says a line (the hint or message is not empty after each click)
## shots: C:/Temp/claude/fmug3/open.png, body.png, cup.png, handle.png
const SHOT := "C:/Temp/claude/fmug3"
const DIRT := "user://fmug3_test"
var fails := 0
var m: Node
var clicks := 0
var step_clicks := {}
var said := []


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


func click_ctl(c: Control, step := "") -> void:
	clicks += 1
	if step != "":
		step_clicks[step] = int(step_clicks.get(step, 0)) + 1
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


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func say_now(ep) -> String:
	return String(ep.hint_l.text) + " | " + String(ep.msg)


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
	await click_ctl(ss._cards["building"], "start")
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and note_words.find("Easy") >= 0,
		"G0 BUILDING card, one click, a blank part on page BUILD, no chooser, words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	await click_ctl(pu.easy_open_btn, "easy")
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await shot("open")

	# G1 the body: Draw shape, Round chip, drag a round shape on the grid, Pull it up
	var c_body0 := clicks
	await click_ctl(ep.make_btns["draw"], "body")
	await click_ctl(ep.shape_btns["round"], "body")
	var cen := scr(Vector3(0.0, 0.0, 0.0))
	var edge := scr(Vector3(0.04, 0.0, 0.0))
	await drag_pts([cen, edge])
	await click_ctl(ep.make_btns["pull"], "body")
	await idle(10)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var v1 := vol_mm3(s1)
	var round_ok: bool = absf(bb1.size.x - bb1.size.z) < 0.03 * maxf(bb1.size.x, 0.001)
	var n_click_body := clicks - c_body0
	ok(int(s1["bodies"]) == 1 and v1 > 5000.0 and round_ok and n_click_body <= 3,
		"G1 the body: one body, %.0f mm3, x %.3f z %.3f (round %s), %d clicks (<= 3)" % [v1, bb1.size.x, bb1.size.z, round_ok, n_click_body])
	var ratio := bb1.size.y / maxf(bb1.size.x, 0.001)
	ok(ratio >= 0.35, "G7 the cup stands taller than a third of its width: height %.3f / width %.3f = %.2f (a mug, not a puck; >= 0.35)" % [bb1.size.y, bb1.size.x, ratio])
	said.append(say_now(ep))
	await shot("body")

	# G2 the cup: Cut a hole, then Hollow inside
	m.pitch = 50.0
	m._cam()
	await idle(40)
	var c_cup0 := clicks
	await click_ctl(ep.make_btns["hole"], "cup")
	await click_ctl(ep.hole_btns["hollow"], "cup")
	await idle(10)
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var n_click_cup := clicks - c_cup0
	ok(int(s2["bodies"]) == 1 and v2 < 0.8 * v1 and n_click_cup <= 3,
		"G2 the cup: one body, hollow %.0f mm3 of %.0f (less than 80 pct), %d clicks (<= 3)" % [v2, v1, n_click_cup])
	said.append(say_now(ep))
	await shot("cup")

	# G3 the handle: a box drawn on the side of the cup, pulled up
	var c_h0 := clicks
	await click_ctl(ep.make_btns["draw"], "handle")
	await click_ctl(ep.shape_btns["box"], "handle")
	var hx0 := scr(Vector3(0.036, 0.0, -0.006))
	var hx1 := scr(Vector3(0.06, 0.0, 0.006))
	await drag_pts([hx0, hx1])
	await click_ctl(ep.make_btns["pull"], "handle")
	await idle(10)
	var s3 := solid()
	var v3 := vol_mm3(s3)
	var n_click_h := clicks - c_h0
	ok(int(s3["bodies"]) == 1 and v3 > v2 * 1.02 and n_click_h <= 3,
		"G3 the handle: one body, %.0f -> %.0f mm3 (more than 2 pct), %d clicks (<= 3)" % [v2, v3, n_click_h])
	said.append(say_now(ep))
	await shot("handle")

	var total := clicks - 1
	ok(total <= 14, "G4 the walk from the blank part to the mug: %d clicks (<= 14). steps: %s" % [total, str(step_clicks)])
	var lab := []
	labels(ep.status, lab)
	var words := " ".join(lab) + " " + String(ep.hint_l.text) + " " + String(ep.msg)
	var jargon := []
	for w in ["sketch", "extrude", "loft", "boolean", "feature", "body"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty() and (s3["errors"] as Dictionary).is_empty(), "G5 no jargon %s and no failed step: [%s]" % [str(jargon), say_now(ep)])
	var silent := []
	for i in range(said.size()):
		if String(said[i]).strip_edges().length() < 3:
			silent.append(i)
	ok(silent.is_empty(), "G6 every press says a line (silent %s): %s" % [str(silent), str(said)])
	print("fmug3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
