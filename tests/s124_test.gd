extends SceneTree
## s124 GEARS DRIVE EACH OTHER (Friday plan 124): on a Gear pair, Turn it turns the small gear and the big one turns -N1 / N2 times as far, the teeth
## staying meshed. Real clicks and drags at 1280 x 720 from the BUILDING card. Every number is measured from the built meshes (Part.body_faces
## of the posed record): the angle each gear turned (a rotation fitted to its outline), the gap between the two outlines (mm, negative = overlap).
##   0  Parts > Gears > Gear pair: the Turn it panel (slider, Spin, Save pose) shows
##   1  a 20 : 40 pair; the slider dragged to 360: the pose reads small 360, big -180
##   2  ten sampled angles: the small gear turned a (+-0.5 deg), the big gear -a/2 (+-0.5 deg) by the fitted rotation of its mesh
##   3  the same ten angles: the smallest gap between the two outlines is >= -0.05 mm (the worst printed)
##   4  the record is byte-for-byte the same after the drags and the sampling, and no undo step was made
##   5  Spin: the preview angle changes by itself, the record still unchanged
##   6  a 2 : 1 chain of three gears (20, 40, 80 teeth) turned 90: +90, -45, +22.5 (signs alternate); a 4 : 1 step down (40, 20, 10): +90, -180, +360
##   7  Save pose: one undo step, the record keeps the angle, the built mesh stays turned (big gear -a/2 by its mesh)
##   8  Undo: the record has no pose again, the mesh is unturned
## shots: C:/Temp/claude/s124/
const SHOT := "C:/Temp/claude/s124"
const DIRT := "user://s124_test"
const GD := preload("res://scripts/gear_drive.gd")
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
	var _sc: Node = c.get_parent()   # navigation only (B07): a button below the fold of its scroll panel is scrolled into view before the click
	while _sc != null and not (_sc is ScrollContainer):
		_sc = _sc.get_parent()
	if _sc != null:
		(_sc as ScrollContainer).ensure_control_visible(c)
		await idle(3)
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


func pu():
	return m.bld.part


func row_of(ep, key: String) -> Dictionary:
	for r in ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	root.push_input(e, true)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func knob_x(s: HSlider, v: float) -> Vector2:
	var r := s.get_global_rect()
	var t := (v - s.min_value) / maxf(s.max_value - s.min_value, 1e-6)
	return Vector2(r.position.x + 12.0 + t * (r.size.x - 24.0), r.get_center().y)


func slide_to(s: HSlider, v: float) -> void:
	await drag_screen(knob_x(s, s.value), knob_x(s, v))


## the outline (mm) of body i of the record turned for the view by a (NAN: the record's own saved pose)
func outline(rec: Dictionary, i: int, a: float) -> Array:
	var w := {}
	if not is_nan(a):
		w["gear_turn"] = a
	var faces: Array = Part.body_faces(rec, -1, w)
	return GD.outline_of(faces[i]) if i < faces.size() else []


func pts_of(segs: Array, c: Vector2, rmin: float) -> Array:
	var out: Array = []
	for s in segs:
		var p: Vector2 = s[0] - c
		if p.length() > rmin:
			out.append(p)
	return out


## the angle (deg) the outline `post` is turned from `base` about c: a fitted rotation, searched near `want` (+- 4 deg, less than half a tooth)
func fit_turn(base: Array, post: Array, c: Vector2, rmin: float, want: float) -> float:
	var B := pts_of(base, c, rmin)
	var P := pts_of(post, c, rmin)
	var sub: Array = []
	for i in range(0, P.size(), maxi(1, P.size() / 60)):
		sub.append(P[i])
	var cost := func(th: float) -> float:
		var tot := 0.0
		var rb: Array = []
		for q in B:
			rb.append((q as Vector2).rotated(deg_to_rad(th)))
		for p in sub:
			var best := INF
			for q in rb:
				best = minf(best, (p as Vector2).distance_squared_to(q))
			tot += best
		return tot
	var bt := want
	var bc := INF
	var th := want - 4.0
	while th <= want + 4.0:
		var cc: float = cost.call(th)
		if cc < bc:
			bc = cc
			bt = th
		th += 0.5
	var c0 := bt
	th = c0 - 0.5
	while th <= c0 + 0.5:
		var cc2: float = cost.call(th)
		if cc2 < bc:
			bc = cc2
			bt = th
		th += 0.05
	return bt


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
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3(0.03, 0.0, 0.0)
	m.pitch = -20.0
	m.yaw = 12.0
	m._cam()
	await idle(60)
	var ep = pu().ep
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_libgroup_Moving parts", true, false) as Control)   # navigation only: Gears moved into the Moving parts group tab (s239)
	await click_ctl(root.find_child("easypart_lib_Gears", true, false) as Control)
	await click_ctl(root.find_child("easypart_gearpair_pick", true, false) as Button)
	await idle(10)
	# a 20 : 40 pair: Small teeth dragged to 20 (the ratio stays 2 : 1)
	var rt := row_of(ep, "teeth")
	if rt.get("slider") != null:
		await slide_to(rt["slider"], 20.0)
	await idle(10)
	var gd = root.find_child("easypart_gear_drive", true, false)
	var gslider: HSlider = root.find_child("easypart_gear_turn", true, false) as HSlider
	var spin_b := root.find_child("easypart_gear_spin", true, false) as Button
	var save_b := root.find_child("easypart_gear_save_pose", true, false) as Button
	ok(gd != null and gd.is_visible_in_tree() and gslider != null and spin_b != null and save_b != null and gslider.is_visible_in_tree(),
		"0 Gear pair shows Turn it: slider, Spin, Save pose")
	var rec0 := JSON.stringify(m.S.part)
	var gp := GD.pair_of(m.S.part)
	ok(int(gp.get("n1", 0)) == 20 and int(gp.get("n2", 0)) == 40, "1a the pair is 20 : 40 teeth (%s)" % str(gp))
	var ub: int = m.undo.size()
	await shot("00_turn_panel")
	if gslider != null:
		var _sc: Node = gslider.get_parent()   # navigation only: the Gear pair has two more sliders now (Mode, Rack length), so Turn it can sit below the fold
		while _sc != null and not (_sc is ScrollContainer):
			_sc = _sc.get_parent()
		if _sc != null:
			(_sc as ScrollContainer).ensure_control_visible(gslider)
			await idle(3)
		await drag_screen(knob_x(gslider, gslider.value), knob_x(gslider, 360.0) + Vector2(60, 0))   # past the end: the slider stops at 360
	await idle(6)
	var wl := root.find_child("easypart_gear_turn_words", true, false) as Label
	var words := String(wl.text) if wl != null else ""
	ok(gslider != null and absf(gslider.value - 360.0) < 0.5 and absf(pu().gear_turn - 360.0) < 0.5 and words.contains("360") and words.contains("-180"),
		"1 slider dragged to 360: preview angle %.1f, words [%s]" % [pu().gear_turn, words])

	# 2 and 3: ten sampled angles, measured from the posed meshes
	var rec: Dictionary = m.S.part
	var c1 := Vector2.ZERO
	var c2 := Vector2(float(gp["d"]), 0.0)
	var r1 := 0.5 * float(gp["md"]) * float(gp["n1"])   # inner radius filter (mm): the teeth and the root only, not the centre hole
	var r2 := 0.5 * float(gp["md"]) * float(gp["n2"])
	var base1 := outline(rec, 0, 0.0)
	var base2 := outline(rec, 1, 0.0)
	var angles := [7.0, 38.0, 73.0, 111.0, 150.0, 187.0, 229.0, 264.0, 301.0, 349.0]
	var worst_a := 0.0
	var worst_b := 0.0
	var worst_gap := INF
	var gap_at := 0.0
	for a in angles:
		var o1 := outline(rec, 0, a)
		var o2 := outline(rec, 1, a)
		var t1 := fit_turn(base1, o1, c1, r1 * 0.8, a)
		var t2 := fit_turn(base2, o2, c2, r2 * 0.8, -a * 0.5)
		worst_a = maxf(worst_a, absf(t1 - a))
		worst_b = maxf(worst_b, absf(t2 - (-a * 0.5)))
		var g := GD.signed_gap(o1, o2)
		if g < worst_gap:
			worst_gap = g
			gap_at = a
		print("     a=%6.1f  small %.2f  big %.2f (want %.2f)  gap %.3f mm" % [a, t1, t2, -a * 0.5, g])
	ok(worst_a <= 0.5 and worst_b <= 0.5, "2 ten angles: small gear off by at most %.2f deg, big gear (-a/2) off by at most %.2f deg" % [worst_a, worst_b])
	ok(worst_gap >= -0.05, "3 ten angles: the smallest gap between the two outlines is %.3f mm (at %.0f deg; want >= -0.05)" % [worst_gap, gap_at])

	# 4 the record and the undo stack did not change; 5 Spin
	ok(JSON.stringify(m.S.part) == rec0 and m.undo.size() == ub, "4 the record is unchanged after the drag and the sampling, no undo step (%d -> %d)" % [ub, m.undo.size()])
	if gslider != null:
		gslider.set_value_no_signal(0.0)
		pu().gear_turn = 0.0
	if spin_b != null:
		await click_ctl(spin_b)
	var g0: float = pu().gear_turn
	for i in 30:
		await process_frame
	await shot("01_spinning")
	var g1: float = pu().gear_turn
	ok(spin_b != null and spin_b.button_pressed and absf(g1 - g0) > 1.0 and JSON.stringify(m.S.part) == rec0 and m.undo.size() == ub,
		"5 Spin: the preview angle moved by itself (%.1f -> %.1f), the record and the undo stack are unchanged" % [g0, g1])
	if spin_b != null:
		await click_ctl(spin_b)

	# 6 chains
	var ch := GD.chain_angles([20, 40, 80], 90.0)
	var ch2 := GD.chain_angles([40, 20, 10], 90.0)
	ok(absf(ch[0] - 90.0) < 1e-6 and absf(ch[1] + 45.0) < 1e-6 and absf(ch[2] - 22.5) < 1e-6 and absf(ch2[1] + 180.0) < 1e-6 and absf(ch2[2] - 360.0) < 1e-6,
		"6 chains: 20-40-80 turned 90 gives %s; 40-20-10 gives %s" % [str(ch), str(ch2)])

	# 7 Save pose at 73 degrees: one undo step, the record keeps the angle, the mesh stays turned
	if gslider != null:
		await slide_to(gslider, 73.0)
	await idle(4)
	var ang: float = gslider.value if gslider != null else 0.0
	var ub7: int = m.undo.size()
	if save_b != null:
		await click_ctl(save_b)
	await idle(8)
	await shot("02_saved")
	var rec7: Dictionary = m.S.part
	var o2s := outline(rec7, 1, NAN)
	var t2s := fit_turn(base2, o2s, c2, r2 * 0.8, -ang * 0.5)
	ok(m.undo.size() == ub7 + 1 and absf(float(rec7.get("gear_pose", 0.0)) - ang) < 0.01 and absf(t2s - (-ang * 0.5)) <= 0.5,
		"7 Save pose at %.0f: undo %d -> %d, record gear_pose %.1f, big gear turned %.2f by its mesh (want %.2f)" % [ang, ub7, m.undo.size(), float(rec7.get("gear_pose", 0.0)), t2s, -ang * 0.5])

	# 8 Undo
	await ctrl_z()
	var rec8: Dictionary = m.S.part
	var o2u := outline(rec8, 1, NAN)
	var t2u := fit_turn(base2, o2u, c2, r2 * 0.8, 0.0)
	ok(not rec8.has("gear_pose") and absf(t2u) <= 0.5, "8 Undo: no saved pose in the record, the big gear's mesh is back (turned %.2f deg)" % t2u)

	print("s124: %d fail" % fails)
	quit(1 if fails > 0 else 0)
