extends SceneTree
## godot --path . --position 4000,4000 -s tests/p129linkages_test.gd     (P129 LINKAGES, Friday plan 129: Easy Part, Parts > Hinges shows a 4-bar linkage panel with a drag handle on the crank's tip; scripts/easy_linkage.gd)
## Bars (real clicks and a real mouse drag through root.push_input at 1280 x 720, from the start screen: a 3D BUILDING project, Part, Easy, Parts, Hinges).
## Every number is read from the text on the panel (or from the knob's screen point), never from the code's own variables:
##   1 OPEN      Hinges shows the Linkage panel inside 1280 x 720: crank 30, coupler 80, rocker 60, frame 100 mm; Full turn: yes
##   2 DRAG      a real mouse drag on the crank's knob to 170 degrees: the knob moves at least 20 px; the tip is 30 mm from the pivot, the coupler 80 mm,
##               the rocker 60 mm, the frame 100 mm, and the tip sits at 170 degrees (+-2)
##   3 TOO LONG  Crank + pressed ten times (real clicks): crank 130 mm, Full turn: no, the words say it cannot turn all the way round and give the next step
##   4 RESET     Reset: crank 30 mm again, Full turn: yes, the frame and the rocker as in bar 1
##   5 NO STEP   no undo step was made by any of it (the linkage is a panel on the page, not a part)
## Shots: C:/Temp/claude/p129linkages/shots/. Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p129linkages/shots"
const DIRT := "user://p129linkages_test"
const RX_NUM := "-?[0-9]+(\\.[0-9]+)?"


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
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## every number on a line of text, in order (a minus sign is part of its number)
func nums(t: String) -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string(RX_NUM)
	for r in rx.search_all(t):
		out.append(r.get_string().to_float())
	return out


func dist(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the Parts page cannot open")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# open Parts, then the Hinges category, with real clicks
	await click_ctl(ep.parts_btn)
	await click_ctl(ep.lib_btns["Hinges"])
	await idle(4)
	var lb = root.find_child("easypart_linkage", true, false)
	var ub0: int = m.undo.size()
	var crank_t := root.find_child("easypart_linkage_crank", true, false) as Label
	var pos_t := root.find_child("easypart_linkage_pos", true, false) as Label
	var turn_t := root.find_child("easypart_linkage_turn", true, false) as Label
	var coupler_t := root.find_child("easypart_linkage_coupler", true, false) as Label
	var rocker_t := root.find_child("easypart_linkage_rocker", true, false) as Label
	var frame_t := root.find_child("easypart_linkage_frame", true, false) as Label
	var ok_all := lb != null and crank_t != null and pos_t != null and turn_t != null and coupler_t != null and rocker_t != null and frame_t != null
	if not ok_all:
		print("FAIL: the Linkage panel or one of its labels is missing")
		fails += 1
		print("P129LINKAGES fails=%d" % fails)
		quit(1)
		return

	# 1 OPEN
	var r: Rect2 = lb.get_global_rect()
	ok(lb.visible and ep.lib_btns["Hinges"].button_pressed == true and Rect2(0, 0, 1280, 720).encloses(r),
		"1 Parts > Hinges shows the Linkage panel inside 1280 x 720 (visible %s, rect %s)" % [str(lb.visible), str(r)])
	var n_crank: Array = nums(crank_t.text)
	var n_cou: Array = nums(coupler_t.text)
	var n_roc: Array = nums(rocker_t.text)
	var n_fr: Array = nums(frame_t.text)
	ok(not n_crank.is_empty() and is_equal_approx(n_crank[0], 30.0) and not n_cou.is_empty() and is_equal_approx(n_cou[0], 80.0)
		and not n_roc.is_empty() and is_equal_approx(n_roc[0], 60.0) and not n_fr.is_empty() and is_equal_approx(n_fr[0], 100.0),
		"1 the lengths read crank 30, coupler 80, rocker 60, frame 100 mm [%s | %s | %s | %s]" % [crank_t.text, coupler_t.text, rocker_t.text, frame_t.text])
	ok(turn_t.text.contains("Full turn: yes"), "1 the panel says Full turn: yes [%s]" % turn_t.text)
	await shot("linkage_open")

	# 2 DRAG: a real drag on the knob to 60 degrees
	var knob0: Vector2 = lb.knob_px()
	var piv: Vector2 = lb.pivot_px()
	var before_tip := nums(pos_t.text)
	var target: Vector2 = piv + 200.0 * Vector2(cos(deg_to_rad(170.0)), -sin(deg_to_rad(170.0)))
	await ev_move(knob0, false)
	await ev_mouse(knob0, true)
	for i in range(1, 9):
		await ev_move(knob0.lerp(target, float(i) / 8.0), true)
	await ev_mouse(target, false)
	await idle(3)
	var knob1: Vector2 = lb.knob_px()
	ok(dist(knob0, knob1) >= 20.0, "2 the knob moved on screen at least 20 px (%.0f px) [knob %s -> %s]" % [dist(knob0, knob1), str(knob0), str(knob1)])
	var p := nums(pos_t.text)
	if p.size() >= 6:
		var tip := Vector2(p[0], p[1])
		var jt := Vector2(p[2], p[3])
		var far := Vector2(p[4], p[5])
		var ang := rad_to_deg(atan2(tip.y, tip.x))
		ok(absf(tip.length() - 30.0) <= 0.5, "2 the tip is 30 mm from the pivot (%.2f mm)" % tip.length())
		ok(absf(dist(tip, jt) - 80.0) <= 0.5, "2 the coupler is 80 mm (%.2f mm)" % dist(tip, jt))
		ok(absf(dist(jt, far) - 60.0) <= 0.5, "2 the rocker is 60 mm (%.2f mm)" % dist(jt, far))
		ok(absf(far.length() - 100.0) <= 0.5, "2 the frame is 100 mm (%.2f mm)" % far.length())
		ok(absf(ang - 170.0) <= 2.0, "2 the tip sits at 170 degrees (%.2f deg) [%s]" % [ang, pos_t.text])
	else:
		ok(false, "2 the joint readout has six numbers [%s]" % pos_t.text)
	ok(before_tip.size() >= 6 and turn_t.text.contains("Full turn: yes"), "2 still Full turn: yes after the drag [%s]" % turn_t.text)
	await shot("linkage_drag")

	# 3 TOO LONG: Crank + pressed ten times, real clicks
	var plus := root.find_child("easypart_linkage_crank_plus", true, false) as Button
	for i in 10:
		await click_ctl(plus)
	var nc := nums(crank_t.text)
	ok(not nc.is_empty() and is_equal_approx(nc[0], 130.0), "3 the crank reads 130 mm after ten + clicks [%s]" % crank_t.text)
	ok(turn_t.text.contains("Full turn: no"), "3 the panel says Full turn: no [%s]" % turn_t.text)
	ok(ep.msg.contains("cannot") and ep.msg.to_lower().contains("next step"), "3 the words say it cannot turn all the way round and give the next step [%s]" % ep.msg)
	await shot("linkage_too_long")

	# 4 RESET
	var reset := root.find_child("easypart_linkage_reset", true, false) as Button
	await click_ctl(reset)
	var nc2 := nums(crank_t.text)
	ok(not nc2.is_empty() and is_equal_approx(nc2[0], 30.0) and turn_t.text.contains("Full turn: yes"),
		"4 Reset brings the crank back to 30 mm and Full turn: yes [%s | %s]" % [crank_t.text, turn_t.text])
	var nr := nums(rocker_t.text)
	var nf := nums(frame_t.text)
	ok(not nr.is_empty() and is_equal_approx(nr[0], 60.0) and not nf.is_empty() and is_equal_approx(nf[0], 100.0), "4 the rocker and the frame are still 60 and 100 mm")

	# 5 NO STEP
	ok(m.undo.size() == ub0, "5 no undo step was made by the panel (undo %d -> %d)" % [ub0, m.undo.size()])

	print("P129LINKAGES fails=%d" % fails)
	quit(1 if fails > 0 else 0)
