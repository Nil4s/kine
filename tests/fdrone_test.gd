extends SceneTree
## FDRONE (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner who never read a manual builds a toy drone from the BUILDING card.
## Real clicks at 1280x720 from the real start screen. Walk (Easy Part): a flat body (Draw shape + Pull it up), an arm out of one side
##   (Draw shape + Pull it up), a motor cylinder on the arm's end (Draw shape with the Round chip + Pull it up), then Repeat it -> Ring,
##   How many 5 (4 arms + the original), then Mirror that.
## Bars (run on the old code before the change: the FAIL lines are the dead ends):
##   0 the BUILDING card, one click: Easy Part on, no chooser, the part is empty
##   1 the flat body: one solid, the volume of a 7 x 7 x 2 cm box
##   2 the arm: drawn beside the body and pulled, it joins the body (one solid, the volume grows by the arm)
##   3 the motor: a round shape on the arm's end, pulled up, joins the arm (one solid, the volume grows)
##   4 Repeat it -> Ring -> How many 5: five arms (+ motors) round the middle, one solid, no failed step, volume 5 x (arm + motor)
##   5 Mirror that on the drone: the other side is added, one undo step, no failed step
## shots: C:/Temp/claude/fdrone/
const SHOT := "C:/Temp/claude/fdrone"
const DIRT := "user://fdrone_test"

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


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func count_kind(rec: Dictionary, t: String) -> int:
	var n := 0
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			n += 1
	return n


func last_of(rec: Dictionary, t: String) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
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
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open and m.S.part.get("features", []).is_empty(),
		"0 BUILDING card, one click -> empty Easy Part, no chooser (chooser %s)" % chooser_open)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("01_open")

	var ep = pu().ep
	var unit_box := 0.07 * 0.07 * 0.02
	# 1 the arm first (Repeat copies the newest solid: a body already joined would be copied whole, see the note in the header)
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(0.03, 0.0, -0.008)), scr(Vector3(0.12, 0.0, 0.008)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await shot("02_arm")
	var v1 := float(pu().res.get("volume", 0.0))
	var b1 := int(pu().res.get("bodies", 0))
	var arm_vol := 0.09 * 0.02 * 0.02   # the grid snaps the bar to 2 cm wide
	ok(b1 == 1 and absf(v1 - arm_vol) < 0.2 * arm_vol, "1 arm: one solid, volume %.3f cm3 (bar 9x2x2 cm = %.3f)" % [v1 * 1e6, arm_vol * 1e6])

	# 2 the motor: a round shape on the arm's end (Round chip), pulled up, joins the arm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_screen(scr(Vector3(0.105, 0.0, 0.0)), scr(Vector3(0.12, 0.0, 0.0)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await shot("03_motor")
	var v2 := float(pu().res.get("volume", 0.0))
	var b2 := int(pu().res.get("bodies", 0))
	ok(b2 == 1 and v2 > v1 + 0.001 * arm_vol, "2 motor on the arm end: one solid, volume +%.3f cm3" % [(v2 - v1) * 1e6])
	var am := v2   # one arm with its motor

	# 3 Repeat it -> Ring -> How many 5 (five arms with motors round the middle)
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["repeat"])
	await click_ctl(ep.rep_btns["ring"])
	await idle(5)
	var rows: Dictionary = {}
	for rw in ep.rep_rows:
		rows[rw["key"]] = rw
	if rows.has("count"):
		await drag_slider(rows["count"]["slider"], 5.0)
	await idle(10)
	await shot("04_ring")
	var pt := last_of(m.S.part, "pattern")
	var r3: Dictionary = pu().res
	var expect3 := 5.0 * am
	ok(String(pt.get("kind", "")) == "circular" and int(pt.get("count", 0)) == 5 and (r3.get("errors", {}) as Dictionary).is_empty()
		and absf(float(r3.get("volume", 0.0)) - expect3) < 0.05 * expect3 and m.undo.size() == ub + 3,
		"3 Ring, How many 5: five arms with motors, no failed step, volume %.3f cm3 (expect %.3f; undo %d -> %d, errors %s)" % [float(r3.get("volume", 0.0)) * 1e6, expect3 * 1e6, ub, m.undo.size(), str(r3.get("errors", {}))])

	# 4 the flat body in the middle, pulled up: it joins the five arms into one solid
	var ub4: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.035, 0.0, -0.035)), scr(Vector3(0.035, 0.0, 0.035)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await shot("05_body")
	var r4: Dictionary = pu().res
	var v4 := float(r4.get("volume", 0.0))
	var body_vol := 0.07 * 0.07 * 0.02
	ok(int(r4.get("bodies", 0)) == 1 and (r4.get("errors", {}) as Dictionary).is_empty() and v4 > expect3 + 0.5 * body_vol and v4 < expect3 + body_vol,
		"4 flat body in the middle joins the arms: one solid, volume %.3f cm3 (arms %.3f + body up to %.3f)" % [v4 * 1e6, expect3 * 1e6, body_vol * 1e6])

	# 4b a Ring round the finished drone (it straddles the middle): the copies go round in a circle beside it, no failed step, one undo step per press
	var ub4b: int = m.undo.size()
	await click_ctl(ep.make_btns["repeat"])
	await idle(5)
	await click_ctl(ep.rep_btns["ring"])
	await idle(8)
	var r4b: Dictionary = pu().res
	var say4b: String = ep.hint_l.text
	ok(m.undo.size() == ub4b + 2 and (r4b.get("errors", {}) as Dictionary).is_empty() and say4b.find("circle") >= 0,
		"4b Ring round the finished drone: copies go round beside it, no failed step, two undo steps (says: %s)" % say4b)
	await shot("05b_ring_beside")
	m._undo()
	m._undo()
	await idle(10)
	ok(absf(float(pu().res.get("volume", 0.0)) - v4) < 0.01 * v4, "4c two Undos take the ring back: the drone again (volume %.3f cm3)" % [float(pu().res.get("volume", 0.0)) * 1e6])

	# 5 Mirror that on the drone: one undo step, no failed step
	var ub5: int = m.undo.size()
	var v5: float = v4
	await click_ctl(ep.make_btns["mirror"])
	await idle(10)
	await shot("06_mirror")
	var r5: Dictionary = pu().res
	ok((r5.get("errors", {}) as Dictionary).is_empty() and m.undo.size() == ub5 + 1,
		"5 Mirror that on the finished drone: one undo step, no failed step, volume %.3f -> %.3f cm3 (the drone is already symmetric)" % [v5 * 1e6, float(r5.get("volume", 0.0)) * 1e6])

	print("fdrone: %d fail" % fails)
	quit(1 if fails > 0 else 0)
