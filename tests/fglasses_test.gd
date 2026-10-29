extends SceneTree
## FGLASSES (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner from the REAL start screen builds a pair of glasses
## with real clicks and drags at 1280 x 720, never having read a manual. BUILDING card -> blank Easy Part.
## Walk: Draw shape (box) across the middle = the bridge -> Pull it up -> Draw shape (Round) = the left ring -> Pull it up
##   -> Cut a hole (the ring's hole) -> Draw shape (box) at the ring's outer edge = the left arm -> Pull it up
##   -> Mirror that = the right ring and the right arm (one step).
## Bars:
##   G0 the BUILDING card, one click: page BUILD, Easy Part on, empty part
##   G1 the bridge: Draw shape + drag across the middle + Pull it up = one body
##   G2 the ring: Round chip, press at the centre, drag out = the radius; Pull it up joins the bridge: one body, more volume
##   G3 Cut a hole: the ring's volume goes down (the hole is in it)
##   G4 the arm: Draw shape + drag at the ring's outer edge + Pull it up joins: one body, more volume
##   G5 Mirror that: still one body, one piece (no gap), the glasses are symmetric across x = 0 (the bbox), wider than 20 cm
##   G6 the words: every press says a line, and no jargon (sketch, extrude, loft, boolean, feature, body) after any press
## shots: C:/Temp/claude/fglasses/ (open, bridge, ring, hole, arm, mirror)
const SHOT := "C:/Temp/claude/fglasses"
const DIRT := "user://fglasses_test"

var fails := 0
var m: Node
var words: Array = []


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func note(press: String) -> void:
	words.append([press, pu().ep.msg])


func jargon_on(s: String) -> Array:
	var out := []
	for w in ["sketch", "extrude", "loft", "boolean", "feature", "body"]:
		if s.to_lower().find(w) >= 0:
			out.append(w)
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

	# G0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("00_open")
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"G0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)
	var ep = pu().ep

	# G1 the bridge: Draw shape (box) across the middle, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.02, 0.0, -0.004)), scr(Vector3(0.02, 0.0, 0.004)))
	note("draw bridge")
	await click_ctl(ep.make_btns["pull"])
	note("pull bridge")
	var b1 := int(pu().res.get("bodies", 0))
	var v1: float = float(pu().res.get("volume", 0.0))
	ok(b1 == 1 and v1 > 0.0, "G1 the bridge: Draw shape + drag + Pull it up = one body (bodies %d, %.2f cm3) [%s]" % [b1, v1 * 1e6, ep.msg])
	await shot("01_bridge")

	# G2 the left ring: Round chip, press at its centre (-35 mm), drag out 20 mm (radius), Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_screen(scr(Vector3(-0.035, 0.0, 0.0)), scr(Vector3(-0.015, 0.0, 0.0)))   # Fusion's circle: the press is the centre, the drag is the radius (20 mm)
	await click_ctl(ep.make_btns["pull"])
	note("pull ring")
	var b2 := int(pu().res.get("bodies", 0))
	var v2: float = float(pu().res.get("volume", 0.0))
	ok(b2 == 1 and v2 > v1 + 1e-9, "G2 the ring joins the bridge: one body, more volume (%.2f -> %.2f cm3) [%s]" % [v1 * 1e6, v2 * 1e6, ep.msg])
	await shot("02_ring")

	# G3 Cut a hole: the ring gets its hole
	await click_ctl(ep.make_btns["hole"])
	note("cut hole")
	var v3: float = float(pu().res.get("volume", 0.0))
	ok(v3 < v2 - 1e-9 and int(pu().res.get("bodies", 0)) == 1, "G3 Cut a hole: the volume goes down (%.2f -> %.2f cm3) [%s]" % [v2 * 1e6, v3 * 1e6, ep.msg])
	await shot("03_hole")

	# G4 the left arm: Draw shape (box) from the ring's outer edge out to 110 mm, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(-0.11, 0.0, -0.002)), scr(Vector3(-0.05, 0.0, 0.002)))   # a box: the two corners (60 mm x 4 mm)
	await click_ctl(ep.make_btns["pull"])
	note("pull arm")
	var b4 := int(pu().res.get("bodies", 0))
	var v4: float = float(pu().res.get("volume", 0.0))
	ok(b4 == 1 and v4 > v3 + 1e-9, "G4 the arm joins the ring: one body, more volume (%.2f -> %.2f cm3) [%s]" % [v3 * 1e6, v4 * 1e6, ep.msg])
	await shot("04_arm")

	# G5 Mirror that: the right ring and the right arm, one step
	await click_ctl(ep.make_btns["mirror"])
	note("mirror")
	var v5: float = float(pu().res.get("volume", 0.0))
	var b5 := int(pu().res.get("bodies", 0))
	var s5 := Part.replay(m.S.part)
	var bb: AABB = s5.get("aabb", AABB())
	var lumps: int = ep._lumps(s5)
	var sym := absf(bb.position.x + bb.end.x) < 0.002
	ok(b5 == 1 and lumps == 1 and v5 > v4 + 1e-9 and sym and bb.size.x > 0.2,
		"G5 Mirror that: one body, one piece (%d), volume %.2f -> %.2f cm3, x %.3f..%.3f (symmetric %s) [%s]" % [lumps, v4 * 1e6, v5 * 1e6, bb.position.x, bb.end.x, str(sym), ep.msg])
	await shot("05_mirror")

	# G6 the words: no empty press, no jargon
	var empty := []
	var jg := []
	for w in words:
		if String(w[1]).strip_edges() == "":
			empty.append(String(w[0]))
		for j in jargon_on(String(w[1])):
			jg.append("%s:%s" % [w[0], j])
	ok(empty.is_empty() and jg.is_empty(), "G6 every press says a line (empty %s), no jargon (%s) %s" % [str(empty), str(jg), str(words)])

	print("fglasses: %d fail" % fails)
	quit(1 if fails > 0 else 0)
