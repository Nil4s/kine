extends SceneTree
## P030 COUNTERSUN (Friday plan item 30, Kine's own idea: the hole knows the screw): a beginner from the BUILDING card makes a plate
## with a screw hole sized to the screw. Real clicks and drags at 1280 x 720.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box 18 x 6 cm) -> Pull it up = the plate (2 cm thick, 6 cm deep)
##   -> Cut a hole -> the screw chips M3 screw, M4 screw, M5 screw, M6 screw (one undo step each, the hole step is replaced)
## A screw hole = a clearance hole through the middle (M3 3.4 mm, M4 4.5 mm, M5 5.5 mm, M6 6.6 mm) + a counterbore from the top face
## for the screw head (head 5.5 / 7 / 8.5 / 10 mm across, 3 / 4 / 5 / 6 mm deep). Volume removed from the plate is measured from the
## built result (mm3) and compared with the sum of those two cylinders (computed here from the ISO numbers, never from the code).
## Bars (run on the code before this change: see the report):
##   P0 after Cut a hole the four screw chips are on the screen, each with a real size
##   P1 M4 screw: one body; the plate loses a 4.5 mm hole + a 7 mm x 4 mm counterbore (volume within 3 %)
##   P2 the words after M4 say its numbers: 4.5 mm hole, 7 mm head, 4 mm deep
##   P3 M4 screw is ONE undo step (the undo count goes up by one)
##   P4 M3 screw on the same plate: one body, the M3 numbers (1.7 mm radius, 2.75 mm counterbore, 3 mm deep) within 3 %
##   P5 no failed step and no jargon (sketch, extrude, boolean, feature, body, loft, cylinder) on the words
##   P6 the words after a screw hole name the next step (Mirror that or Repeat it)
## shots: C:/Temp/claude/p030countersun/plate.png, screw.png
const SHOT := "C:/Temp/claude/p030countersun"
const DIRT := "user://p030countersun_test"
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


## the volume a screw hole takes out of a plate T mm deep: a clearance cylinder through it + the counterbore ring for the head
func want_mm3(clear_mm: float, head_mm: float, head_h: float, T: float) -> float:
	var r := clear_mm / 2.0
	var R := head_mm / 2.0
	return PI * r * r * T + PI * (R * R - r * r) * head_h


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
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the plate: a box on the grid (18 cm x 6 cm), Pull it up (2 cm)
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var v1 := vol_mm3(s1)
	var bb1: AABB = s1["aabb"]
	var T := bb1.size.z / Part.MM   # the plate's depth in mm, from the built result
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "plate: one body, volume %.0f mm3, depth %.1f mm" % [v1, T])
	await shot("plate")

	# P0 Cut a hole, then the four screw chips
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var chips := []
	for sd in [3, 4, 5, 6]:
		var b: Button = ep.hole_btns.get("screw%d" % sd, null)
		chips.append("M%d:%s" % [sd, b != null and b.is_visible_in_tree() and b.size.x > 20.0])
	var all_on := true
	for c in chips:
		all_on = all_on and String(c).ends_with("true")
	ok(all_on and ep.hole_box.is_visible_in_tree(), "P0 after Cut a hole: the four screw chips are on the screen %s" % [chips])

	# P3 + P1 + P2: M4 screw, one undo step, the volume of its hole and counterbore
	var n0: int = m.undo.size()
	if ep.hole_btns.has("screw4"):
		await click_ctl(ep.hole_btns["screw4"])
	await idle(10)
	var n1: int = m.undo.size()
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var removed4 := v1 - v2
	var want4 := want_mm3(4.5, 7.0, 4.0, T)
	ok(int(s2["bodies"]) == 1 and absf(removed4 - want4) < 0.03 * want4,
		"P1 M4 screw: one body; plate lost %.1f mm3 (a 4.5 mm hole + 7 mm x 4 mm counterbore = %.1f mm3)" % [removed4, want4])
	var said := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(said.find("4.5") >= 0 and said.find("7 mm") >= 0 and said.find("4 mm") >= 0,
		"P2 the words name the M4 numbers: [%s]" % said)
	ok(n1 - n0 == 1, "P3 M4 screw is one undo step (undo count +%d)" % (n1 - n0))
	await shot("screw")

	# P4 M3 screw on the same plate (the hole step is replaced)
	if ep.hole_btns.has("screw3"):
		await click_ctl(ep.hole_btns["screw3"])
	await idle(10)
	var s3 := solid()
	var v3 := vol_mm3(s3)
	var removed3 := v1 - v3
	var want3 := want_mm3(3.4, 5.5, 3.0, T)
	ok(int(s3["bodies"]) == 1 and absf(removed3 - want3) < 0.03 * want3,
		"P4 M3 screw: one body; plate lost %.1f mm3 (a 3.4 mm hole + 5.5 mm x 3 mm counterbore = %.1f mm3)" % [removed3, want3])

	# P5 no jargon, no failed step; P6 the next step is named
	var words := String(ep.hint_l.text) + " " + String(ep.msg)
	var lab := []
	labels(ep.status, lab)
	words += " " + " ".join(lab)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty() and (s3["errors"] as Dictionary).is_empty(), "P5 no failed step and no jargon %s: [%s]" % [jargon, words])
	var nxt := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(nxt.to_lower().find("mirror") >= 0 or nxt.to_lower().find("repeat") >= 0, "P6 after a screw hole the words name the next step: [%s]" % nxt)
	await shot("m3")
	print("p030countersun: %d fail" % fails)
	quit(1 if fails > 0 else 0)
