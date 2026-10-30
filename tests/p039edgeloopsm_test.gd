extends SceneTree
## p039edgeloopsm (Friday plan item 39: Edge loop smoothing for drawn curves: a wobbly hand drawing becomes a clean curve; a Smooth strength slider).
## A beginner from the REAL start screen, real clicks and drags at 1280 x 720 on the live Easy Part: Curvy line, a wobbly stroke drawn by hand,
## then the Smooth slider on the new line is clicked to its right end; then a stroke with one deliberate corner, smoothed the same way.
## Bars (measured from the RECORD the built part replays from: the kernel's curve points of the newest sketch, never from the code's variables):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 a wobbly Curvy line is drawn (one sketch, one bspline curve, ONE undo step)
##   2 the newest step's slider is labelled Smooth and sits at 0 (the pill says 0 pct: the line is kept as drawn)
##   3 the Smooth slider at its right end (about 100 pct): the curve's wobble (sum of the turns between its points) falls to half or less
##   4 the curve keeps its two ends: its first and last points move by 0.5 mm or less
##   5 the whole Smooth change is ONE undo step, and Ctrl+Z puts the wobble back within 1 pct
##   6 the slider's end words are plain: Wobbly and Smooth
##   7 a deliberate corner (a right angle drawn on purpose) is still a corner at full Smooth: one turn of 60 degrees or more
## shots: C:/Temp/claude/p039edgeloopsm/
const SHOT := "C:/Temp/claude/p039edgeloopsm"
const DIRT := "user://p039edgeloopsm_test"
const WOBBLE_BAR := 0.5
const END_BAR_MM := 0.5

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
	await idle(2)


## a real press and release at a point (a click on a slider's track)
func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## a real press, a drag through every point, a release
func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func dot_near(p: Vector2) -> bool:
	var ep = m.bld.part.ep
	for d in ep._dot_list():
		if (d["scr"] as Vector2).distance_to(p) <= 30.0:
			return true
	return false


## a point in the clear view at fractions (fx, fy), moved down until no amber dot or Easy panel is under it
func free_at(fx: float, fy: float) -> Vector2:
	var ep = m.bld.part.ep
	var cl: Rect2 = m.nav_clear_rect()
	var p := Vector2(cl.position.x + cl.size.x * fx, cl.position.y + cl.size.y * fy)
	for i in 40:
		if not dot_near(p) and not ep._over_ui(p):
			return p
		p += Vector2(0, 14)
	return p


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the newest step's slider and the slider's label words (the row the panel shows)
func smooth_row() -> Array:
	var sl := find_named(m, "easypart_slider_last") as HSlider
	if sl == null:
		return [null, ""]
	var lbl := ""
	for c in sl.get_parent().find_children("*", "Label", true, false):
		if String((c as Label).text) == "Smooth":
			lbl = "Smooth"
	return [sl, lbl]


## the kernel's curve points of the newest sketch, read back from the record (the built part)
func newest_curve() -> Array:
	var fs: Array = m.S.part["features"]
	var f: Dictionary = fs[-1]
	if String(f.get("t", "")) != "sketch":
		return []
	var ents: Array = f["ents"]
	if ents.is_empty() or String(ents[0].get("k", "")) != "bspline":
		return []
	var out := []
	for p in ents[0]["pts"]:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## the wobble of a curve: the sum of the absolute turns between its points (a straight line is 0)
func wobble(pts: Array) -> float:
	var s := 0.0
	for i in range(1, pts.size() - 1):
		var a: Vector2 = pts[i] - pts[i - 1]
		var b: Vector2 = pts[i + 1] - pts[i]
		s += absf(a.angle_to(b))
	return s


func max_turn_deg(pts: Array) -> float:
	var mx := 0.0
	for i in range(1, pts.size() - 1):
		var a: Vector2 = pts[i] - pts[i - 1]
		var b: Vector2 = pts[i + 1] - pts[i]
		mx = maxf(mx, rad_to_deg(absf(a.angle_to(b))))
	return mx


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(4)


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
	# 0 the BUILDING card, one click: Easy Part on, empty part
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	ok(pu.ep != null and m.S.part is Dictionary, "0 the BUILDING card opens the Easy Part (one click)")

	# 1 a wobbly Curvy line by hand: twelve points 20 px apart, zigzagging 18 px up and down
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["curve"])
	var c0 := free_at(0.14, 0.3)
	var hand := []
	for i in 13:
		hand.append(c0 + Vector2(20 * i, 18.0 if i % 2 == 0 else -18.0))
	await drag_pts(hand)
	var raw := newest_curve()
	var wob0 := wobble(raw)
	ok(raw.size() >= 4 and wob0 > 0.5 and m.undo.size() == ub + 1,
		"1 CURVY LINE a wobbly hand line is one curve (%d points, wobble %.2f, ONE undo step %d -> %d)" % [raw.size(), wob0, ub, m.undo.size()])
	await shot("drawn")

	# 2 the Smooth slider on the new line: labelled Smooth, at 0 (kept as drawn)
	await idle(4)
	var sr := smooth_row()
	var sl := sr[0] as HSlider
	ok(sl != null and String(sr[1]) == "Smooth" and sl.value == 0.0,
		"2 SMOOTH the newest line's slider is labelled Smooth and sits at 0 (label '%s', value %s)" % [String(sr[1]), str(sl.value) if sl != null else "none"])
	if sl == null:
		print("p039edgeloopsm: %d fail" % fails)
		m.queue_free()
		quit(1)
		return

	# 3 click the Smooth slider at its right end: the curve's wobble falls to half or less
	var ub3: int = m.undo.size()
	var r := sl.get_global_rect()
	await click_at(Vector2(r.position.x + r.size.x * 0.98, r.get_center().y))
	await idle(4)
	var smooth_pts := newest_curve()
	var wob1 := wobble(smooth_pts)
	ok(wob1 <= WOBBLE_BAR * wob0, "3 SMOOTH at the right end (value %.0f pct): the wobble %.2f -> %.2f (half or less)" % [sl.value, wob0, wob1])
	await shot("smoothed")

	# 4 the two ends stay where the hand put them
	var e0 := (smooth_pts[0] as Vector2).distance_to(raw[0] as Vector2)
	var e1 := (smooth_pts[-1] as Vector2).distance_to(raw[-1] as Vector2)
	ok(e0 <= END_BAR_MM and e1 <= END_BAR_MM, "4 ENDS the first and last points move %.2f and %.2f mm (0.5 mm or less)" % [e0, e1])

	# 5 one undo step for the Smooth change; Ctrl+Z puts the wobble back
	ok(m.undo.size() == ub3 + 1, "5a UNDO the Smooth change is ONE undo step (%d -> %d)" % [ub3, m.undo.size()])
	await ctrl_z()
	var wback := wobble(newest_curve())
	ok(absf(wback - wob0) <= 0.01 * wob0, "5b UNDO Ctrl+Z puts the wobble back within 1 pct (%.2f, as drawn %.2f)" % [wback, wob0])

	# 6 the words are plain
	var sr2 := smooth_row()
	var words_ok := false
	if sr2[0] != null:
		var txt := []
		for c in (sr2[0] as HSlider).get_parent().find_children("*", "Label", true, false):
			txt.append(String((c as Label).text))
		words_ok = "Wobbly" in txt and "Smooth" in txt
	ok(words_ok, "6 WORDS the Smooth slider's end words are Wobbly and Smooth")

	# 7 a deliberate corner stays a corner: a right angle drawn on purpose, smoothed to the right end
	await idle(2)
	var c1 := free_at(0.14, 0.62)
	var corner := []
	for i in 7:
		corner.append(c1 + Vector2(20 * i, 0))
	for i in range(1, 7):
		corner.append(c1 + Vector2(120, 20 * i))
	await click_ctl(ep.make_btns["curve"])
	await drag_pts(corner)
	var sr3 := smooth_row()
	if sr3[0] != null:
		var r3 := (sr3[0] as HSlider).get_global_rect()
		await click_at(Vector2(r3.position.x + r3.size.x * 0.98, r3.get_center().y))
		await idle(4)
	var cpts := newest_curve()
	var turn := max_turn_deg(cpts)
	ok(cpts.size() >= 3 and turn >= 60.0, "7 CORNER the right angle drawn on purpose stays a corner at full Smooth (largest turn %.0f degrees, 60 or more)" % turn)
	await shot("corner")

	print("p039edgeloopsm: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
