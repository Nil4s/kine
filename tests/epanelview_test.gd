extends SceneTree
## EPANELVIEW (Nick 2026-10-28: "free 3D building", like Fusion 360): when a tool panel opens at the left of Easy Part
## (Repeat it, Round the edges, Cut a hole, Colour, Draw shape ...) it must not cover the part. The view re-frames so the part sits
## in the free area right of the panel. A beginner from the BUILDING card at 1280 x 720 by real clicks: a plate, then every tool.
## godot --path . --position 4000,4000 -s tests/epanelview_test.gd
##   0 BUILDING card, one click: Easy Part on, no chooser
##   1 PLATE a 300 x 120 mm plate drawn and pulled up
##   2 TOOL each tool's press: every open panel of Easy Part (the left and right panels) does not overlap the part's screen box
##     (old code: the Repeat it / Colour / Cut a hole / Cut in two / Draw panels cover the part, FAILED)
##   3 INSIDE the part's box sits inside the view
##   5 STICK two real clicks on two pieces, the Stick together panel is checked too
## Shots: C:/Temp/claude/epanelview/<tool>.png (LOOK at them)
const SHOT := "C:/Temp/claude/epanelview"
const DIRT := "user://epanelview_test"

var fails := 0
var m: Node
var bad := []   # "tool: panel name overlaps" lines


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


## a real drag of a slider knob to value v
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


## wait real seconds (the camera eases in real time)
func settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the part's screen box: the eight corners of its bounds, projected (zero size when a corner is behind the lens)
func part_box() -> Rect2:
	var bb: AABB = pu().res.get("aabb", AABB())
	if bb.size.length() < 1e-4:
		return Rect2()
	var r := Rect2()
	var first := true
	for i in 8:
		var q := bb.get_endpoint(i)
		if m.cam.is_position_behind(q):
			return Rect2()
		var sp: Vector2 = m.cam.unproject_position(q)
		r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
		first = false
	return r


## the open panels of Easy Part (visible in the tree) with their names
func open_panels() -> Array:
	var e = ep()
	var out := []
	for pr in [["shape", e.shape_box], ["hole", e.hole_box], ["split", e.split_box], ["colour", e.colour_box], ["repeat", e.repeat_box], ["stick", e.stick_box], ["panel", e.panel]]:
		var c: Control = pr[1]
		if c != null and c.is_visible_in_tree():
			out.append([pr[0], c.get_global_rect()])   # the same design space as the camera's projection (1280 x 720)
	return out


## an overlap of more than a few pixels each way
func overlaps(a: Rect2, b: Rect2) -> bool:
	var i := a.intersection(b)
	return i.size.x > 4.0 and i.size.y > 4.0


## the tool's press, then every open panel is checked against the part's screen box
func check_tool(nm: String, c: Control) -> void:
	await click_ctl(c)
	await check_now(nm)


## the panels and the part as they stand after a press
func check_now(nm: String) -> void:
	await settle(1.5)
	await idle(5)
	var pb := part_box()
	var clash := []
	for p in open_panels():
		if pb.size != Vector2.ZERO and overlaps(pb, p[1]):
			clash.append(String(p[0]))
	if pb.size == Vector2.ZERO:
		clash.append("part-behind-lens")
	var vp := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	var inside := pb.size != Vector2.ZERO and vp.encloses(pb)
	if not clash.is_empty():
		bad.append("%s: %s" % [nm, str(clash)])
	ok(clash.is_empty(), "2 TOOL %s: no open panel over the part (%s), part box %s" % [nm, str(clash), str(pb)])
	ok(inside, "3 INSIDE %s: the part's box sits in the view" % nm)
	await shot(nm)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## the screen point of body i's middle (the pieces of the part, Part.body_faces)
func body_at(i: int) -> Vector2:
	var faces := Part.body_faces(m.S.part, -1)
	var sum := Vector3.ZERO
	var n := 0
	for q in faces[i]:
		sum += q
		n += 1
	return m.cam.unproject_position(sum / float(maxi(n, 1)))


func last_of(t: String) -> Dictionary:
	var out := {}
	for f in m.S.part.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


## Draw shape, then a real drag on the floor from world a to b (metres)
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


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
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open,
		"0 BUILDING card, one click -> Easy Part on, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	m.target = Vector3.ZERO
	m.pitch = -30.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 PLATE: a 300 x 120 mm rectangle on the floor, pulled up
	await draw_floor(Vector3(-0.15, 0.0, -0.06), Vector3(0.15, 0.0, 0.06))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 1.5)
	await settle(1.5)
	await idle(5)
	ok(int(pu().res.get("bodies", 0)) == 1, "1 PLATE one body pulled up")

	# 2 TOOLS: every make button, one press each (Draw and Curvy arm a tool: the next press disarms it)
	var order := ["round", "hole", "mirror", "spin", "curve", "blend", "split", "colour", "draw", "repeat", "stick"]   # repeat last: its box stays open for the Up row
	for nm in order:
		var c: Control = ep().make_btns[nm]
		if nm == "stick":
			continue   # needs two picked pieces: no panel to check until then
		await check_tool(nm, c)

	# the Repeat it Up row stacks the copies: the part grows up into the view (the stack seen at the BUILDING card)
	var up_b = ep().rep_btns.get("up")
	if up_b != null and (up_b as Control).is_visible_in_tree():
		await click_ctl(up_b)
		await check_now("repeat_up")
	else:
		ok(false, "4 UP the Repeat it Up button is on the row")

	# the Stick together panel: two real clicks on the two pieces of the Repeat row, then its buttons show over the part's left
	await click_ctl(ep().make_btns["stick"])
	await click_at(body_at(0))
	await click_at(body_at(1))
	ok(ep().stick_picks.size() == 2, "5 STICK two real clicks pick two pieces")
	await check_now("stick")

	print("epanelview bad: %s" % str(bad))
	print("epanelview: %d fail" % fails)
	quit(1 if fails > 0 else 0)
