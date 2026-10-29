extends SceneTree
## FPHONE (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a PHONE STAND from the BUILDING card, real clicks at 1280x720.
## Parts: a base plate (Draw shape + drag + Pull it up), an angled back (two floor shapes, Blend two shapes: the newer one
## goes 40 mm up), a lip at the front (a small shape, Pull it up), a cable cut (Cut a hole).
## Bars (dead ends are bars; see the report for which fail on the old code):
##   0 the BUILDING card, one click: Easy Part on, empty, no chooser
##   1 base plate: one body, 120 x 90 x 20 mm
##   2 angled back: a shape on the plate top + a shape on the floor further back, Blend two shapes: ONE loft, one body, no failed step, top 55-65 mm, 70 mm+ back
##   3 lip: a small shape drawn on the plate top and pulled up: one body, no failed step
##   4 cable slot: a small rectangle drawn on the top, then Cut a hole: volume drops, one body
##   5 one Undo takes back only the cable slot
##   6 no jargon words (shape, pull, body...) in the visible hint and status texts
## shots: C:/Temp/claude/fphone/*.png
const SHOT := "C:/Temp/claude/fphone"
const DIRT := "user://fphone_test"

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


## a real press, a drag through the points, a release
func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


## a floor rectangle (metres, x and z) drawn by a real drag from its corner to the opposite one
func draw_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	var a := scr(Vector3(x0, 0.0, z0))
	var b := scr(Vector3(x1, 0.0, z1))
	var pts := []
	for i in 13:
		pts.append(a.lerp(b, i / 12.0))
	await drag_pts(pts)


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


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


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
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and not chooser_open and (m.S.part.get("features", []) as Array).is_empty(),
		"0 BUILDING card, one click: Easy Part on, empty, no chooser")
	var ep = pu().ep
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 base plate on the floor, 120 x 90 mm, pulled up 20 mm (a beginner's first step)
	await click_ctl(ep.make_btns["draw"])
	await draw_rect(-0.06, -0.045, 0.06, 0.045)
	await click_ctl(ep.make_btns["pull"])
	await idle(5)
	var bb: AABB = pu().res.get("aabb", AABB())
	var sz := bb.size / 0.001
	var bodies := int(pu().res.get("bodies", 0))
	ok(bodies == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty() and absf(sz.x - 120.0) <= 10.0 and absf(sz.z - 90.0) <= 9.0 and absf(sz.y - 20.0) <= 3.0,
		"1 base plate: one body, 120 x 90 x 20 mm (%.0f x %.0f x %.0f)" % [sz.x, sz.z, sz.y])
	await shot("01_base")

	# 2 angled back: a thin shape on the plate's top at the back edge, a second on the floor further back, then Blend two shapes.
	# Blend puts the newer shape 40 mm above the older one, so the back rises off the plate and leans back
	await click_ctl(ep.make_btns["draw"])
	await draw_rect(-0.05, -0.045, 0.05, -0.04)
	await click_ctl(ep.make_btns["draw"])
	await draw_rect(-0.05, -0.075, 0.05, -0.07)
	await click_ctl(ep.make_btns["draw"])
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["blend"])
	await idle(5)
	var r2: Dictionary = pu().res
	var errs: Dictionary = r2.get("errors", {})
	var lofts := 0
	for f in m.S.part.get("features", []):
		if String(f["t"]) == "loft":
			lofts += 1
	var bb2: AABB = r2.get("aabb", AABB())
	var top_mm := (bb2.position.y + bb2.size.y) / 0.001
	var back_mm := -(bb2.position.z) / 0.001
	ok(lofts == 1 and errs.is_empty() and int(r2.get("bodies", 0)) == 1 and m.undo.size() == ub + 1 and top_mm >= 55.0 and top_mm <= 65.0 and back_mm >= 70.0,
		"2 angled back: Blend two shapes, one loft, one body, no failed step, ONE undo step, top %.0f mm, %.0f mm back (errors %s)" % [top_mm, back_mm, errs.keys()])
	await shot("02_back")

	# 3 lip: a small shape drawn on the top of the plate at the front edge, pulled up
	await click_ctl(ep.make_btns["draw"])
	await draw_rect(-0.06, 0.035, 0.06, 0.045)
	await click_ctl(ep.make_btns["pull"])
	await idle(5)
	var v3 := float(pu().res.get("volume", 0.0))
	var b3 := int(pu().res.get("bodies", 0))
	ok(b3 == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(), "3 lip: one body, no failed step (bodies %d)" % b3)
	await shot("03_lip")

	# 4 cable slot: a small rectangle drawn on the TOP of the plate, then Cut a hole (a shape on a face is the hole)
	var v_before := v3
	await click_ctl(ep.make_btns["draw"])
	await draw_rect(-0.02, -0.01, 0.02, 0.01)
	await click_ctl(ep.make_btns["hole"])
	await idle(5)
	var v4 := float(pu().res.get("volume", 0.0))
	ok(v4 < v_before and int(pu().res.get("bodies", 0)) == 1, "4 cable slot: volume %.1f -> %.1f cm3, one body" % [v_before * 1e6, v4 * 1e6])
	await shot("04_cable")

	# 5 one Undo takes back only the cable slot
	await click_ctl(ep.undo_btn)
	await idle(5)
	var v5 := float(pu().res.get("volume", 0.0))
	ok(absf(v5 - v_before) < 1e-9, "5 one Undo takes back only the cable slot (%.1f cm3)" % (v5 * 1e6))

	# 6 words
	var texts: Array = []
	texts_under(ep.hint_l.get_parent(), texts)
	texts_under(ep.status_l.get_parent() if ep.status_l != null else ep.hint_l, texts)
	var bad := []
	for t in texts:
		var tl := String(t).to_lower()
		for w in ["kernel", "manifold", "extrude", "sketch", "loft", "fillet", "feature"]:
			if tl.find(w) >= 0:
				bad.append(String(t))
	ok(bad.is_empty(), "6 no jargon in the hint or status %s" % [bad])

	print("fphone: %d fail" % fails)
	quit(1 if fails > 0 else 0)
