extends SceneTree
## FSIGN (Nick 2026-10-28: "free 3D building, like Fusion 360, anything, nothing forced"): a beginner from the REAL start screen builds a
## door sign with real clicks and drags at 1280 x 720: a rounded plate, a screw hole on the left, Mirror that = the second screw hole on the right.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box) on the grid -> Pull it up = the plate
##   -> Round the edges -> Draw shape (round) on the plate's top face, left of the middle -> Cut a hole -> Mirror that.
## Bars (run on the old code before the fix; see the report):
##   G0 the BUILDING card, one click: page BUILD, a blank part, no chooser; Easy's big buttons come up after one click
##   G1 the plate: one body, a real volume
##   G2 Round the edges: says the edges are rounded and takes a little volume off, not a lot
##   G3 the first screw hole: a round hole through the plate, one body, the volume drops by a hole
##   G4 Mirror that after the hole: the plate keeps BOTH holes (volume drop = two holes, within 10%); the old code filled the hole
##   G5 the second hole is on the other side of the middle: plate x extent unchanged
##   G6 no failed step and no jargon (sketch, extrude, fillet, boolean, feature, body, loft) on the words
##   G7 the words after Cut a hole name the next step (Mirror that or Repeat it)
## shots: C:/Temp/claude/fsign/open.png, plate.png, round.png, hole.png, mirror.png
const SHOT := "C:/Temp/claude/fsign"
const DIRT := "user://fsign_test"
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
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open,
		"G0 BUILDING card, one click -> a blank part on page BUILD, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	ok(pu.easy and ep != null and ep.make_btns.has("draw") and ep.make_btns.has("hole") and ep.make_btns.has("round"),
		"G0b Easy on: the big buttons (draw, round, hole, mirror) are up")
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)
	await shot("open")

	# G1 the plate: a box on the grid (18 cm x 6 cm), Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var v1 := vol_mm3(s1)
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "G1 the plate is one body, volume %.0f mm3 (aabb x %.3f..%.3f, top y %.3f)" % [v1, bb1.position.x, bb1.end.x, bb1.end.y])
	await shot("plate")

	# G2 Round the edges
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var said2 := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(v2 < v1 and v1 - v2 < 0.05 * v1 and said2.to_lower().find("rounded") >= 0,
		"G2 Round the edges: volume %.0f -> %.0f mm3, words [%s]" % [v1, v2, said2])

	# G3 the first screw hole: a round shape on the top face, left of the middle, then Cut a hole
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	var top_y := bb1.end.y
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var c0 := scr(Vector3(-0.06, top_y, 0.0))
	await drag_pts([c0, c0 + Vector2(12, 0)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var s3 := solid()
	var v3 := vol_mm3(s3)
	var h1 := v2 - v3
	var said3 := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(int(s3["bodies"]) == 1 and h1 > 5.0 and h1 < 0.5 * v2, "G3 the first screw hole: one body, -%.0f mm3 (words [%s])" % [h1, said3])
	await shot("hole")

	# G4 Mirror that: the second hole, on the other side of the middle
	await click_ctl(ep.make_btns["mirror"])
	await idle(10)
	var s4 := solid()
	var v4 := vol_mm3(s4)
	var total := v2 - v4
	ok(int(s4["bodies"]) == 1 and absf(total - 2.0 * h1) < 0.10 * h1 * 2.0,
		"G4 Mirror that: two holes, one body; total cut -%.0f mm3 (want two holes = %.0f)" % [total, 2.0 * h1])
	var bb4: AABB = s4["aabb"]
	ok(absf(bb4.position.x - bb1.position.x) < 0.002 and absf(bb4.end.x - bb1.end.x) < 0.002,
		"G5 the mirror keeps the plate's width: x %.3f..%.3f (was %.3f..%.3f)" % [bb4.position.x, bb4.end.x, bb1.position.x, bb1.end.x])
	var words := String(ep.hint_l.text) + " " + String(ep.msg)
	var lab := []
	labels(ep.status, lab)
	words += " " + " ".join(lab)
	var jargon := []
	for w in ["sketch", "extrude", "fillet", "boolean", "feature", "body", "loft"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty() and (s4["errors"] as Dictionary).is_empty(), "G6 no failed step and no jargon %s: [%s]" % [jargon, words])
	ok(said3.to_lower().find("mirror") >= 0 or said3.to_lower().find("repeat") >= 0, "G7 after Cut a hole the words name the next step: [%s]" % said3)
	await shot("mirror")
	print("fsign: %d fail" % fails)
	quit(1 if fails > 0 else 0)
