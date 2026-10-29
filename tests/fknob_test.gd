extends SceneTree
## FKNOB (Nick 2026-10-28: "free 3D building, like Fusion 360, anything, nothing forced"): a beginner from the REAL start screen
## builds a cabinet knob and a drawer front with real clicks and drags at 1280 x 720, never having read a manual.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box) on the grid -> Pull it up = the drawer front (plate)
##   -> Draw shape (round) on the plate's top face -> Pull it up = the knob (cylinder, joined onto the plate)
##   -> Mirror that = the second knob on the other side of the middle line.
## Bars (run on the old code before the change; see the report):
##   K0 the BUILDING card, one click: page BUILD, a blank part, no chooser, the words name Easy; K0b Easy's big buttons come up
##      (the card body opens Expert's blank part; the old note said only "Press a plane in the browser or a Sketch tool")
##   K1 the plate: one body, a real volume
##   K2 a round drawn ON the plate's top face, Pull it up, joins the plate: still one body, volume grows by a knob
##   K3 Mirror that: two knobs, still one body, the volume grows by one more knob (within 5%), ONE undo step
##   K4 the knobs sit at the mirror places: the plate's x centre does not move and the knobs are both inside the plate's width
##   K5 no failed step and no jargon in the words (sketch, extrude, loft, boolean, feature, body) on the status lines
##   K6 the words after Pull it up on a face name the next step (Mirror that or Round the edges or Cut a hole)
## shots: C:/Temp/claude/fknob/plate.png, knob.png, mirror.png, open.png
const SHOT := "C:/Temp/claude/fknob"
const DIRT := "user://fknob_test"
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
	await click_ctl(ss._cards["building"])   # a beginner clicks the card itself
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and note_words.find("Easy") >= 0,
		"K0 BUILDING card, one click -> a blank part on page BUILD, no chooser, and the words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	await click_ctl(pu.easy_open_btn)   # the beginner presses the Easy the words named
	await idle(10)
	var ep = pu.ep
	ok(pu.easy and ep != null and ep.make_btns.has("draw"), "K0b Easy on: the big buttons are up")
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)
	await shot("open")

	# K1 the plate: Draw shape (box) on the grid, then Pull it up
	var ub0: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.05, 0.0, -0.04)), scr(Vector3(0.05, 0.0, 0.04))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var v1 := vol_mm3(s1)
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "K1 the plate is one body, volume %.0f mm3 (aabb x %.3f..%.3f, top y %.3f)" % [v1, bb1.position.x, bb1.end.x, bb1.end.y])
	await shot("plate")

	# K2 the knob: Draw shape with the Round shape on the plate's top face, then Pull it up (joins the plate)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	var top_y := bb1.end.y
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var c0 := scr(Vector3(0.02, top_y, 0.0))   # well inside the plate (x 0.02, the knob is 11 mm across: its edge stays inside the 50 mm half-width)
	await drag_pts([c0, c0 + Vector2(22, 0)])
	await click_ctl(ep.make_btns["draw"])
	var hint_before: String = String(ep.hint_l.text)
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var knob_v := v2 - v1
	var said2 := String(ep.hint_l.text)
	ok(int(s2["bodies"]) == 1 and knob_v > 50.0, "K2 the knob is on the plate: one body, +%.0f mm3 (hint before pull: %s)" % [knob_v, hint_before])
	ok(said2.to_lower().find("mirror") >= 0 or said2.to_lower().find("round the edges") >= 0 or said2.to_lower().find("cut a hole") >= 0,
		"K6 after Pull it up the words name the next step: [%s]" % said2)
	await shot("knob")

	# K3 Mirror that: the second knob, one body, one undo step
	var ub3: int = m.undo.size()
	await click_ctl(ep.make_btns["mirror"])
	await idle(10)
	var s3 := solid()
	var v3 := vol_mm3(s3)
	var lab := []
	labels(ep.status, lab)
	var words := " ".join(lab) + " " + String(ep.hint_l.text) + " " + String(ep.msg)
	var lumps: int = ep._lumps(s3)
	var added := v3 - v2
	ok(lumps == 1 and int(s3["bodies"]) == 1 and absf(added - knob_v) < 0.05 * knob_v and m.undo.size() == ub3 + 1 and (s3["errors"] as Dictionary).is_empty(),
		"K3 Mirror that: two knobs, one body (%d touching), +%.0f mm3 (one knob = %.0f), one undo step (%d -> %d)" % [lumps, added, knob_v, ub3, m.undo.size()])
	var bb3: AABB = s3["aabb"]
	ok(absf((bb3.position.x + bb3.end.x) - (bb1.position.x + bb1.end.x)) < 0.002 and absf(bb3.size.x - bb1.size.x) < 0.002,
		"K4 the mirror is across the middle: plate x %.3f..%.3f kept (now %.3f..%.3f)" % [bb1.position.x, bb1.end.x, bb3.position.x, bb3.end.x])
	var jargon := []
	for w in ["sketch", "extrude", "loft", "boolean", "feature", "body"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty() and (s3["errors"] as Dictionary).is_empty(), "K5 no failed step and no jargon on the words %s: [%s]" % [jargon, String(ep.msg)])
	await shot("mirror")
	print("fknob: %d fail" % fails)
	quit(1 if fails > 0 else 0)
