extends SceneTree
## p097searchboxf (Friday plan item 97, Nick: a search box for any action, "hole", "round", "screw", across Easy and Expert).
## The S box (scripts/command_search.gd) gets the Easy Part actions as rows (scripts/easy_search.gd): "Easy Part: Round the edges",
## "Easy Part: Cut a hole", "Easy Part: Screw M4 x 16 mm". A row runs the same press its button runs. Real keys and clicks at 1280 x 720
## from the real start screen, on the live Easy Part. Measured from the BUILT result (mm, mm3, body count), never from the code's variables;
## the top row is read off the S box's own list.
##   B1 SEARCH   the S key opens the box; typing "round" puts "Easy Part: Round the edges" on the top row
##   B2 ROUND    Enter on that row arms Round the edges; the How round slider to 2 mm: the built top edges lost the rounds
##               ((1 - pi/4) r^2 x the top perimeter, r = 2 mm, within 15 pct)
##   B3 SCREW    typing "screw m4 16" puts "Easy Part: Screw M4 x 16 mm" on the top row; Enter: one more body, and one body of
##               the ISO M4 x 16 volume (pi/4 (d^2 L + D^2 k) = 354.9 mm3, within 1 pct)
##   B4 UNDO     one Ctrl+Z after the screw: the body count is back and the volume is the volume before the screw (within 0.5 pct)
##   B5 HOLE     typing "hole" puts "Easy Part: Cut a hole" on the top row; Enter shows the hole's two chips (Through, Hollow inside)
##   B6 CLOSE    Enter closes the box (no box left on the screen)
## Shots: C:/Temp/claude/p097searchboxf/box_round.png, box_screw.png, box_hole.png
const SHOT := "C:/Temp/claude/p097searchboxf"
const DIRT := "user://p097searchboxf_test"
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
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


func solid() -> Dictionary:
	return Part.replay(m.S.part, -1, {"faces": true, "props": true})


func mm(v: float) -> float:
	return v / Part.MM


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


func grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


## a real click on the slider's track at value v (the grabber centre sits at v)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := grab_w(sl)
	var frac := (v - sl.min_value) / (sl.max_value - sl.min_value)
	var lx := g * 0.5 + frac * (sl.size.x - g)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


func key(code: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	root.push_input(k)
	await idle(3)


## typed as a keyboard sends it: one key event per letter, with its character
func type(t: String) -> void:
	for ch in t:
		var k := InputEventKey.new()
		k.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
		k.unicode = ch.unicode_at(0)
		k.pressed = true
		root.push_input(k)
	await idle(6)


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(20)


## the S box's top row (the first row of its list), "" when nothing is listed
func top_row() -> String:
	var lst: Tree = m.ui_cmd.list
	var it := lst.get_root().get_first_child() if lst.get_root() != null else null
	return it.get_text(0) if it != null else ""


## the solid's total volume (mm3), from the built bodies
func vol_mm3(s: Dictionary) -> float:
	var tot := 0.0
	for v in s.get("volumes", []):
		tot += float(v)
	return tot / (Part.MM * Part.MM * Part.MM)


func body_vols_mm3(s: Dictionary) -> Array:
	var out := []
	for v in s.get("volumes", []):
		out.append(float(v) / (Part.MM * Part.MM * Part.MM))
	return out


func round_loss(W: float, D: float, r: float) -> float:
	return (1.0 - PI / 4.0) * r * r * (2.0 * W + 2.0 * D)


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
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# a 40 mm box, pulled up 3 cm (30 mm), its top four edges rounded by the Round edges step's chip (Only the top)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await slide_to(last_slider(), 3.0)
	await click_ctl(ep.round_btns["top"])

	# B1 + B2: the S key opens the box, "round" finds the Round edges action, Enter runs it
	await key(KEY_S)
	ok(m.ui_cmd.visible, "B1a the S key opens the search box on Easy Part")
	await type("round")
	ok(top_row() == "Easy Part: Round the edges",
		"B1b typing \"round\" puts \"Easy Part: Round the edges\" on the top row (top row: \"%s\")" % top_row())
	await shot("box_round")
	await key(KEY_ENTER)
	await idle(10)
	await slide_to(last_slider(), 0.2)
	var s2 := solid()
	var bb2: AABB = s2["aabb"]
	var W := mm(bb2.size.x)
	var D := mm(bb2.size.z)
	var lost := W * D * mm(bb2.size.y) - vol_mm3(s2)
	var want := round_loss(W, D, 2.0)
	ok(absf(lost - want) <= 0.15 * want,
		"B2 the top edges are rounded 2 mm from the box: %.1f mm3 lost (want %.1f, 15 pct), box %.1f x %.1f mm" % [lost, want, W, D])

	# B3 + B4: "screw m4 16" finds M4 x 16, Enter drops it on the floor, one Ctrl+Z takes it back
	var before := solid()
	var v_before := vol_mm3(before)
	var n_before := int(before["bodies"])
	await key(KEY_S)
	await type("screw m4 16")
	ok(top_row() == "Easy Part: Screw M4 x 16 mm",
		"B3a typing \"screw m4 16\" puts \"Easy Part: Screw M4 x 16 mm\" on the top row (top row: \"%s\")" % top_row())
	await shot("box_screw")
	await key(KEY_ENTER)
	await idle(20)
	var after := solid()
	var iso := PI / 4.0 * (4.0 * 4.0 * 16.0 + 7.0 * 7.0 * 4.0)
	var found := false
	for v in body_vols_mm3(after):
		if absf(v - iso) <= 0.01 * iso:
			found = true
	ok(int(after["bodies"]) == n_before + 1 and found,
		"B3b Enter drops one M4 x 16 on the floor: %d bodies (was %d), one body of %.1f mm3 (ISO %.1f, 1 pct)" % [int(after["bodies"]), n_before, _closest(body_vols_mm3(after), iso), iso])
	await ctrl_z()
	var back := solid()
	ok(int(back["bodies"]) == n_before and absf(vol_mm3(back) - v_before) <= 0.005 * v_before,
		"B4 one Ctrl+Z takes the screw back: %d bodies (was %d), %.1f mm3 (before %.1f)" % [int(back["bodies"]), n_before, vol_mm3(back), v_before])

	# B5 + B6: "hole" finds Cut a hole, Enter shows its two chips; the box closes on Enter
	await key(KEY_S)
	await type("hole")
	ok(top_row() == "Easy Part: Cut a hole",
		"B5a typing \"hole\" puts \"Easy Part: Cut a hole\" on the top row (top row: \"%s\")" % top_row())
	await key(KEY_ENTER)
	await idle(10)
	var chips := 0
	var hb = ep.hole_box
	if hb != null and hb.visible:
		for b in hb.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree():
				chips += 1
	ok(chips >= 2, "B5b Enter shows the hole's chips (%d visible: Through, Hollow inside)" % chips)
	ok(not m.ui_cmd.visible, "B6 Enter closes the search box")
	await shot("box_hole")

	print("p097searchboxf: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)


func _closest(vals: Array, want: float) -> float:
	var best := -1.0
	for v in vals:
		if best < 0.0 or absf(float(v) - want) < absf(best - want):
			best = float(v)
	return best
