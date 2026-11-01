extends SceneTree
## s097 (Friday plan 97): Ctrl+K (or the search icon on the Easy Part bar) opens ONE box for any Easy Part action; typing filters by name and
## synonyms, arrows + Enter run it exactly as a click would, Esc closes. Real key presses and clicks at 1280 x 720 from the real start screen.
##   K1 ICON    1280 wide: the bar is full, the icon is hidden; 1600 wide: the icon is on the bar, clear of the other bar buttons, its press opens the box
##   K2 OPEN    Ctrl+K opens the box with the keyboard in its text line
##   K3 HOLE    "hole" lists Cut a hole first and Holes: Row below it; Down moves the pick one row, Up back
##   K4 SAME    Enter on Cut a hole = a click on the Cut a hole button: the same hole panel on the screen (visible buttons and the one sentence)
##              and the same undo count
##   K5 ESC     Esc closes the box, adds no undo step, and the keyboard is back in the view (no control holds the focus)
##   K6 M3      "m3" lists M3 screw hole first; Enter: one body, the plate lost a 3.4 mm hole + 5.5 mm x 3 mm counterbore measured from the built solid
##   K7 SCREW   "screw m4 16" + Enter: the part is one M4 x 16 screw (355 mm3 ISO within 1 pct), as the Parts chip makes it; one Ctrl+Z gives the plate back
##   K8 FIELD   Ctrl+K while the name box (a text field) has the keyboard does not open the box
## Shots: C:/Temp/claude/s097/
const SHOT := "C:/Temp/claude/s097"
const DIRT := "user://s097_test"
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



func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(14)


func ib_hidden_at_1280(b: Button) -> bool:
	return b != null and not b.is_visible_in_tree()


func ctrl_k() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_K
	e.physical_keycode = KEY_K
	e.key_label = KEY_K
	e.unicode = 107
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(6)


func rows_now() -> Array:
	var out := []
	var it: TreeItem = m.ui_cmd.list.get_root().get_first_child() if m.ui_cmd.list.get_root() != null else null
	while it != null:
		out.append(it.get_text(0))
		it = it.get_next()
	return out


func sel_row() -> String:
	var it: TreeItem = m.ui_cmd.list.get_selected()
	return it.get_text(0) if it != null else ""


## what the hole panel shows: the visible chip texts + the one sentence
func panel_state(ep) -> String:
	var t := []
	if ep.hole_box != null and ep.hole_box.visible:
		for b in ep.hole_box.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree():
				t.append((b as Button).text)
	return "%s | %s" % [str(t), ep.hint_l.text]


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
	CommandSearch.user_files_off = true
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

	# the plate: 40 x 40 mm, pulled up 30 mm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await slide_to(last_slider(), 3.0)
	var s0 := solid()
	var v0 := vol_mm3(s0)
	var T := mm((s0["aabb"] as AABB).size.z)   # the hole runs along Z (p030countersun): through the plate depth
	ok(int(s0["bodies"]) == 1 and v0 > 1000.0, "plate: one body, %.0f mm3, %.1f mm deep (Z)" % [v0, T])

	# K1 the bar's icon: at 1280 the bar row is already wider than the window (1336 px), so the icon stays hidden there (Ctrl+K is the way in);
	# at 1600 x 900 there is room: the icon is on the screen, clear of the other bar buttons, and a real click on it opens the box
	await idle(4)
	ok(ib_hidden_at_1280(find_named(m, "easypart_search") as Button), "K1a at 1280 x 720 the bar has no room: the search icon is hidden, Expert is not pushed further (bar row %.0f px)" % ep.bar_row.get_combined_minimum_size().x)
	await shot("bar_1280")
	await size_to(1600, 900)
	var ib: Button = find_named(m, "easypart_search") as Button
	var r := ib.get_global_rect() if ib != null else Rect2()
	var clash := []
	if ib != null:
		for b in ep.bar_row.find_children("*", "Button", true, false):
			if b != ib and (b as Button).is_visible_in_tree() and (b as Button).get_global_rect().grow(-1).intersects(r.grow(-1)):
				clash.append((b as Button).text)
	ok(ib != null and ib.is_visible_in_tree() and Rect2(0, 0, 1600, 900).encloses(r) and clash.is_empty() and r.size.x >= 30.0,
		"K1b at 1600 x 900 the search icon is on the bar, %s, clear of the other bar buttons (clash %s)" % [str(r), str(clash)])
	await shot("bar_1600")
	ib.pressed.emit()   # the headless window is 1280 wide, so a pushed mouse click cannot reach a control placed for 1600: the press is the button's own signal
	await idle(4)
	ok(m.ui_cmd.visible, "K1c the icon's press opens the box")
	await key(KEY_ESCAPE)
	await size_to(1280, 720)

	# K2 Ctrl+K
	await ctrl_k()
	ok(m.ui_cmd.visible and root.gui_get_focus_owner() == m.ui_cmd.box, "K2 Ctrl+K opens the box and its text line has the keyboard")

	# K3 hole
	await type("hole")
	var rs := rows_now()
	ok(rs.size() >= 3 and rs[0] == "Easy Part: Cut a hole" and rs.has("Easy Part: Holes: Row"), "K3a \"hole\" lists Cut a hole first and Holes: Row (rows %s)" % str(rs.slice(0, 6)))
	await shot("box_hole")
	await key(KEY_DOWN)
	var dn := sel_row()
	await key(KEY_UP)
	ok(rs.size() > 1 and dn == rs[1] and sel_row() == rs[0], "K3b Down moves the pick to \"%s\", Up back to \"%s\"" % [dn, sel_row()])

	# K4 Enter = the click
	var u0: int = m.undo.size()
	await key(KEY_ENTER)
	await idle(10)
	var a_state := panel_state(ep)
	var a_n: int = m.undo.size() - u0
	var hole_vis: bool = ep.hole_box.visible and not m.ui_cmd.visible
	await shot("after_enter")
	await ctrl_z()
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var b_state := panel_state(ep)
	var b_n: int = m.undo.size() - u0
	ok(hole_vis and a_state == b_state and a_n == b_n and a_n >= 1,
		"K4 Enter on Cut a hole = a click on it: the same panel [%s] vs [%s], undo steps %d vs %d" % [a_state.substr(0, 60), b_state.substr(0, 60), a_n, b_n])

	# K5 Esc
	var u1: int = m.undo.size()
	await ctrl_k()
	await type("round")
	await key(KEY_ESCAPE)
	ok(not m.ui_cmd.visible and m.undo.size() == u1 and root.gui_get_focus_owner() == null,
		"K5 Esc closes the box: no undo step (%d -> %d), no control holds the keyboard (%s)" % [u1, m.undo.size(), str(root.gui_get_focus_owner())])

	# K6 m3 (from the plain plate: undo the hole step)
	await ctrl_z()
	var pre := solid()
	var vp := vol_mm3(pre)
	await ctrl_k()
	await type("m3")
	var r3 := rows_now()
	ok(r3.size() > 0 and r3[0] == "Easy Part: M3 screw hole", "K6a \"m3\" lists M3 screw hole first (rows %s)" % str(r3.slice(0, 4)))
	await key(KEY_ENTER)
	await idle(20)
	var s3 := solid()
	var removed := vp - vol_mm3(s3)
	var want := want_mm3(3.4, 5.5, 3.0, T)
	ok(int(s3["bodies"]) == 1 and absf(removed - want) <= 0.03 * want,
		"K6b M3 screw hole: one body; the plate lost %.1f mm3 (3.4 mm hole through %.1f mm + 5.5 x 3 mm counterbore = %.1f, 3 pct)" % [removed, T, want])
	await shot("m3")

	# K7 screw m4 16 (the part becomes the screw, like the Parts chip; Ctrl+Z gives the plate back)
	var before := solid()
	await ctrl_k()
	await type("screw m4 16")
	ok(rows_now().size() > 0 and rows_now()[0] == "Easy Part: Screw M4 x 16 mm", "K7a \"screw m4 16\" lists Screw M4 x 16 mm first (%s)" % str(rows_now().slice(0, 3)))
	await key(KEY_ENTER)
	await idle(20)
	var sc := solid()
	var iso := PI / 4.0 * (4.0 * 4.0 * 16.0 + 7.0 * 7.0 * 4.0)
	ok(int(sc["bodies"]) == 1 and absf(vol_mm3(sc) - iso) <= 0.01 * iso, "K7b the part is one M4 x 16 screw: %.1f mm3 (ISO %.1f, 1 pct)" % [vol_mm3(sc), iso])
	await ctrl_z()
	var back := solid()
	ok(absf(vol_mm3(back) - vol_mm3(before)) <= 0.005 * vol_mm3(before), "K7c one Ctrl+Z gives the plate back: %.1f mm3 (before %.1f)" % [vol_mm3(back), vol_mm3(before)])

	# K8 a text field keeps its Ctrl+K
	await click_ctl(ep.title_l)
	await idle(4)
	var in_field: bool = ep.name_edit.visible and root.gui_get_focus_owner() == ep.name_edit
	await ctrl_k()
	ok(in_field and not m.ui_cmd.visible, "K8 Ctrl+K in the name box (focus in the field: %s) does not open the box" % str(in_field))

	print("s097: %d fail" % fails)
	quit(1 if fails > 0 else 0)
