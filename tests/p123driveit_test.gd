extends SceneTree
## P123 DRIVE IT (Friday plan 123, "Drive it: a lid opens, a gear turns"): on Easy Part, two pieces made apart, the Swing it chip swings the
## newest piece open on a hinge step (90 degrees in 2 s, its back top edge, a step on the timeline). Real clicks at 1280 x 720 from the
## real start screen. Every number is measured from the BUILT result (Part.replay / body_faces / hinge_sweep), never from the code's variables.
##   S0 one piece only: the Swing it chip is hidden
##   1  two pieces: the Swing it chip shows on the bar
##   2  a real click on Swing it adds one hinge step: 2 bodies still, the built volume unchanged (the hinge adds no solid)
##   3  Undo (a real click) takes the hinge step away: no hinge, 2 bodies (one undo step)
##   4  Swing it again: the hinge's body is the newest piece (piece 2: its box min x = 120 mm +-1, its top = the hinge's height +-0.5 mm)
##   5  the hinge's swing, measured by Part.hinge_sweep: ok, 50 frames (2 s at 25 fps), first contact = -1 (it clears piece 1)
##   6  the timeline (the step list on the side) reads "Swung it open 90 degrees"
## shots: C:/Temp/claude/p123driveit/swing.png (after the press), undone.png (after Undo)
const SHOT := "C:/Temp/claude/p123driveit"
const DIRT := "user://p123driveit_test"

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


func click_at(p: Vector2) -> void:
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


func inside_of(x_min: float, x_max: float) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			if v.x > x_min and v.x < x_max:
				s += v
				n += 1
	return s / float(maxi(n, 1))


func bodies() -> int:
	return pu().ep._lumps(pu().res)


func vol() -> float:
	return float(pu().res.get("volume", 0.0))


## the hinge steps in the record (their ids order kept)
func hinges() -> Array:
	var out: Array = []
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "hinge":
			out.append(f)
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

	# the BUILDING card, one click: a blank Easy Part
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

	# S0 one piece only: the chip is hidden
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	var sw = m.find_child("easypart_swing_it", true, false)
	ok(sw != null and not (sw as Control).is_visible_in_tree(), "S0 one piece only: the Swing it chip is hidden")

	# two separate pieces: piece 2 on the grid at x = +15 cm
	await click_ctl(draw)
	await drag_screen(scr(Vector3(0.12, 0.0, -0.03)), scr(Vector3(0.18, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	if bodies() != 2:
		print("p123driveit: cannot continue, bodies %d" % bodies())
		quit(1)
		return

	# 1 the chip shows
	sw = m.find_child("easypart_swing_it", true, false)
	var shows: bool = sw != null and (sw as Control).is_visible_in_tree()
	ok(shows, "1 two pieces: the Swing it chip shows on the bar")
	if not shows:
		print("p123driveit: %d fail" % fails)
		quit(1)
		return
	var v0 := vol()

	# 2 a real click adds one hinge step; the built solid is the same
	await click_ctl(sw)
	await idle(10)
	var h := hinges()
	ok(h.size() == 1 and bodies() == 2 and absf(vol() - v0) < 1e-9, "2 a click on Swing it adds one hinge step: hinges %d, bodies %d, volume %.9f -> %.9f" % [h.size(), bodies(), v0, vol()])
	await shot("swing")

	# 3 Undo takes the step away (one step)
	await click_ctl(pu().ep.undo_btn)
	await idle(10)
	ok(hinges().is_empty() and bodies() == 2, "3 Undo takes the hinge step away: hinges %d, bodies %d" % [hinges().size(), bodies()])
	await shot("undone")

	# 4 Swing it again: the hinge's body is piece 2 (the newest), at its back top edge
	await click_ctl(sw)
	await idle(10)
	h = hinges()
	var faces: Array = Part.body_faces(m.S.part, -1)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	if h.size() == 1 and faces.size() == 2:
		for v in faces[1]:
			lo = lo.min(v)
			hi = hi.max(v)
	var o: Array = h[0]["o"] if h.size() == 1 else [0, 0, 0]
	var bi := int(h[0].get("body", -1)) if h.size() == 1 else -1
	ok(h.size() == 1 and bi == 1 and absf(float(o[0]) - lo.x / Part.MM) < 1.0 and absf(float(o[1]) - hi.y / Part.MM) < 0.5 and absf(float(o[2]) - lo.z / Part.MM) < 1.0, "4 the hinge sits on piece 2 (body %d) at its back top edge: o %s mm, box min x %.1f mm, top %.1f mm" % [bi, o, lo.x / Part.MM, hi.y / Part.MM])

	# 5 the swing, measured by the kernel: 50 frames, clear of piece 1
	var sweep := Part.hinge_sweep(m.S.part, String(h[0]["id"]) if h.size() == 1 else "")
	ok(bool(sweep.get("ok", false)) and int(sweep.get("frames", 0)) == 50 and int(sweep.get("first", 0)) == -1, "5 the swing: ok %s, frames %s (2 s at 25 fps), first contact %s (-1 = clear)" % [sweep.get("ok", false), sweep.get("frames", -1), sweep.get("first", "?")])

	# 6 the step list reads the step in plain words
	var texts: Array = []
	texts_under(m, texts)
	var found := false
	for t in texts:
		if String(t).find("Swung it open 90 degrees") >= 0:
			found = true
	ok(found, "6 the timeline step reads \"Swung it open 90 degrees\"")

	print("p123driveit: %d fail" % fails)
	quit(1 if fails > 0 else 0)
