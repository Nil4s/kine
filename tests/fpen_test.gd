extends SceneTree
## FPEN (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a PEN from the BUILDING card by real clicks at 1280x720:
## a tapered tip by Blend (a small round and a bigger round on the floor, Blend two shapes), a long barrel pulled up from the top face of the tip,
## a clip drawn on the side and pulled out, and a cap as a separate piece. The world is metres: scr(Vector3(0.012, 0, 0)) is 12 mm out.
## Bars (run on the old code before the change; see the report for which failed):
##   0 the BUILDING card, one click: page BUILD, Easy Part on, the part empty
##   1 TIP      Blend two floor rounds (5 mm and 12 mm) -> ONE solid, one undo step, it stands 40 mm tall
##   2 TAPER    the tip is a taper: its volume is between 0.2 and 0.9 of the 12 mm cylinder of the same height
##   3 BARREL   a round drawn on the top face of the tip, Pull it up: still ONE body, reaching at least 60 mm
##   4 LONG     How far dragged to 12 cm: the pen is 130 to 220 mm tall and at least 3 times as long as it is wide
##   5 CLIP     a box drawn on the side of the barrel, Pull it out: still ONE body, it sticks out sideways (width grows >= 8 mm)
##   6 CAP      a round drawn on the floor apart from the pen, Pull it up: two or more pieces on the screen, no failed step
##   6b STICK   with those pieces, Stick together arms (old code: refused "needs two separate pieces", the handle count was 1)
##   7 UNDO     one Undo takes the cap away again (one body)
## shots: C:/Temp/claude/fpen/ (tip, barrel, long, clip, cap)
const SHOT := "C:/Temp/claude/fpen"
const DIRT := "user://fpen_test"
var fails := 0
var alt := false   # s211: Alt held (free sizes) for the clip only
var m: Node
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.alt_pressed = alt
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame
func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.alt_pressed = alt
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
func slider_x(s: HSlider, v: float) -> float:
	var r := s.get_global_rect()
	var gw := 24.0
	return r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
func drag_slider(s: HSlider, v: float) -> void:
	var y := s.get_global_rect().get_center().y
	var p0 := Vector2(slider_x(s, s.value), y)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	var x1 := slider_x(s, v)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)
func idle(n := 3) -> void:
	for i in n:
		await process_frame
func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)
## the Part result of the record as it is now (sync first: the replay is refreshed on the frame, a read right after a press can be one step old)
func res() -> Dictionary:
	m.bld.part.sync()
	return m.bld.part.res
## the pieces the screen counts ("3 pieces that do not touch"): the mesh's separate lumps, the Easy count
func pieces() -> int:
	return m.bld.part.ep._lumps(res())


func mm3(v: float) -> float:
	return v / (Part.MM * Part.MM * Part.MM)
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
	var pu = m.bld.part
	var ep = pu.ep
	ok(m.cur_page == "BUILD" and pu.on and pu.easy and (m.S.part.get("features", []) as Array).is_empty(),
		"0 BUILDING card, one click -> an empty Easy Part (page %s, on %s)" % [m.cur_page, pu.on])
	m.target = Vector3(0.0, 0.03, 0.0)
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	# 1 TIP: a 5 mm round, then a 12 mm round, both on the floor; Blend two shapes
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(Vector3(0, 0, 0)), scr(Vector3(0.005, 0, 0))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(Vector3(0, 0, 0)), scr(Vector3(0.012, 0, 0))])
	await click_ctl(ep.make_btns["draw"])
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["blend"])
	var r1 := res()
	var tip_h: float = float(r1.get("aabb", AABB()).end.y) * 1000.0
	ok(int(r1.get("bodies", 0)) == 1 and float(r1.get("volume", 0.0)) > 0.0 and (r1.get("errors", {}) as Dictionary).is_empty() and m.undo.size() == ub + 1 and absf(tip_h - 40.0) < 2.0,
		"1 TIP the 5 and 12 mm rounds blend into ONE solid, one undo step, %.1f mm tall (bodies %d, errors %s) [%s]" % [tip_h, int(r1.get("bodies", 0)), r1.get("errors", {}), ep.hint_l.text])
	await shot("tip")

	# 2 TAPER: the volume of the tip is less than the 12 mm cylinder of its height, more than a fifth of it
	var cyl := PI * 12.0 * 12.0 * 40.0
	var tv := mm3(float(r1.get("volume", 0.0)))
	ok(tv > 0.2 * cyl and tv < 0.9 * cyl, "2 TAPER the tip is a taper: %.0f mm3 against a 12 mm cylinder %.0f mm3" % [tv, cyl])

	# 3 BARREL: a 12 mm round on the top face of the tip (the face at 40 mm), Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(Vector3(0, 0.04, 0)), scr(Vector3(0.012, 0.04, 0))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	var r3 := res()
	var top3: float = float(r3.get("aabb", AABB()).end.y) * 1000.0
	ok(int(r3.get("bodies", 0)) == 1 and (r3.get("errors", {}) as Dictionary).is_empty() and top3 >= 60.0,
		"3 BARREL a round on the top face of the tip pulls up into ONE body reaching %.1f mm (bodies %d) [%s]" % [top3, int(r3.get("bodies", 0)), ep.hint_l.text])
	await shot("barrel")
	# 4 LONG: How far dragged to 12 cm (a pen, not a pole: the tip 4 cm and the barrel about 12 cm)
	var sl: HSlider = ep.rows[-1]["slider"]
	await drag_slider(sl, 12.0)
	var r4 := res()
	var ab: AABB = r4.get("aabb", AABB())
	var h4 := ab.size.y * 1000.0
	var w4 := maxf(ab.size.x, ab.size.z) * 1000.0
	ok(int(r4.get("bodies", 0)) == 1 and h4 >= 130.0 and h4 <= 220.0 and h4 >= 3.0 * w4,
		"4 LONG the pen is %.0f mm long and %.0f mm wide (bodies %d)" % [h4, w4, int(r4.get("bodies", 0))])
	await shot("long")

	# 5 CLIP: a box on the side of the barrel (+X), Pull it out
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	# s211: the barrel is 10 mm in radius, so the old aim (x = 12 mm) was OUTSIDE it and the press fell on the floor. The press now lands ON the barrel, on the side
	# that faces the camera and the right (35 degrees round from +X): a drag from the click out along the barrel (its axis) and across it draws the clip centred on the click
	var pc := Vector3(0.010 * cos(deg_to_rad(35.0)), 0.09, 0.010 * sin(deg_to_rad(35.0)))
	var lat := Vector3(-sin(deg_to_rad(35.0)), 0.0, cos(deg_to_rad(35.0)))
	alt = true
	await drag_pts([scr(pc), scr(pc + Vector3(0, 0.01, 0) + lat * 0.003), scr(pc + Vector3(0, 0.01, 0) + lat * 0.003)])
	alt = false
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	var r5 := res()
	var ab5: AABB = r5.get("aabb", AABB())
	ok(int(r5.get("bodies", 0)) == 1 and (r5.get("errors", {}) as Dictionary).is_empty() and ab5.size.x * 1000.0 >= w4 + 8.0,
		"5 CLIP a box on the side sticks out: %.1f mm wide against %.1f (bodies %d) [%s]" % [ab5.size.x * 1000.0, w4, int(r5.get("bodies", 0)), ep.hint_l.text])
	await shot("clip")

	# 6 CAP: a round on the floor apart from the pen, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(Vector3(0.06, 0, 0.06)), scr(Vector3(0.068, 0, 0.06))])
	await click_ctl(ep.make_btns["draw"])
	var ub6: int = m.undo.size()   # after the drawing (its own undo step): the Pull is the one step this bar counts
	await click_ctl(ep.make_btns["pull"])
	var r6 := res()
	var pc6 := pieces()
	print("diag cap: bodies %d pieces %d errors %s status [%s]" % [int(r6.get("bodies", 0)), pc6, r6.get("errors", {}), ep.hint_l.text])
	ok(pc6 >= 2 and (r6.get("errors", {}) as Dictionary).is_empty() and m.undo.size() == ub6 + 1,
		"6 CAP the cap is a separate piece: %d pieces on the screen, no failed step, one undo step" % pc6)
	await shot("cap")

	# 6b STICK: with two pieces on the screen, Stick together arms (it is not refused for "needs two separate pieces")
	await click_ctl(ep.make_btns["stick"])
	ok(ep.armed == "stick" and not ep.hint_l.text.contains("needs two"),
		"6b STICK TOGETHER arms with %d pieces on the screen (armed '%s', status [%s])" % [pc6, ep.armed, ep.hint_l.text])

	# 7 UNDO takes the cap away again
	m._undo()
	await idle(10)
	ok(int(res().get("bodies", 0)) == 1, "7 UNDO takes the cap away: one body again (bodies %d)" % int(res().get("bodies", 0)))

	print("fpen: %d fail" % fails)
	quit(1 if fails > 0 else 0)
