extends SceneTree
## p027loftbetwee (Friday plan item 27: Loft between two drawn shapes, a circle bottom and a square top, with a Twist slider on the Blend).
## A beginner from the REAL start screen, real clicks and drags at 1280 x 720 on the live Easy Part: a round shape on the floor, a square
## shape on the floor (it goes 40 mm above), Blend two shapes, then drag the new Twist slider to the right (+45 degrees).
## Bars (measured from the BUILT result: Part.replay of the record the view shows, the view mesh, the slider on screen; never from variables of the code):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the blend builds ONE solid from the round and the square, the newest step is a loft, ONE undo step
##   2 the newest step's slider is labelled Twist and sits at 0 (the pill says 0 degrees)
##   3 dragging Twist to the right (about +45 degrees) changes the built solid: its volume moves by more than 0.5 pct of the untwisted one
##   4 the whole Twist drag is ONE undo step, and Ctrl+Z puts the built volume back within 0.5 pct of the untwisted one
##   5 the Twist slider's words are plain: Twist left / Twist right
## shots: C:/Temp/claude/p027loftbetwee/
const SHOT := "C:/Temp/claude/p027loftbetwee"
const DIRT := "user://p027loftbetwee_test"
const VOL_BAR := 0.005

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


## the built result: a full replay of the record the view shows (m3)
func built_volume() -> float:
	return float(Part.replay(m.S.part)["volume"])


func built_bodies() -> int:
	return int(Part.replay(m.S.part)["bodies"])


## the newest step's slider (its row) and its label words
func twist_row() -> Array:
	var sl := find_named(m, "easypart_slider_last") as HSlider
	if sl == null:
		return [null, "", ""]
	var lbl := ""
	for c in sl.get_parent().find_children("*", "Label", true, false):
		var t := String((c as Label).text)
		if t == "Twist":
			lbl = t
	return [sl, lbl]


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

	# the walk: a round shape on the floor, a square shape on the floor, Blend two shapes
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var c0 := free_at(0.22, 0.3)
	await drag_pts([c0, c0 + Vector2(30, 0), c0 + Vector2(60, 0)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	var b0 := free_at(0.12, 0.5)
	await drag_pts([b0, b0 + Vector2(40, 40)])
	await click_ctl(ep.make_btns["draw"])
	var ub2: int = m.undo.size()
	await click_ctl(ep.make_btns["blend"])
	var v0 := built_volume() / (Part.MM * Part.MM * Part.MM)
	var last_t := String(m.S.part["features"][-1]["t"]) if not (m.S.part["features"] as Array).is_empty() else ""
	ok(last_t == "loft" and built_bodies() == 1 and v0 > 1000.0 and m.undo.size() == ub2 + 1,
		"1 BLEND the round and the square make ONE solid (bodies %d, volume %.0f mm3), the newest step is a loft, ONE undo step (%d -> %d) [%s]"
		% [built_bodies(), v0, ub2, m.undo.size(), ep.hint_l.text])
	await shot("blend")

	# 2 the Twist slider: its label and its pill at 0
	await idle(4)
	var tr := twist_row()
	var sl := tr[0] as HSlider
	ok(sl != null and String(tr[1]) == "Twist" and sl.value == 0.0, "2 TWIST the newest step's slider is labelled Twist and sits at 0 (label '%s', value %s)" % [String(tr[1]), str(sl.value) if sl != null else "none"])
	if sl == null:
		print("p027loftbetwee: %d fail" % fails)
		m.queue_free()
		quit(1)
		return

	# 3 drag Twist to the right: a click at 3/4 of the track is about +45 degrees (the slider runs -90 to +90)
	var ub3: int = m.undo.size()
	var r := sl.get_global_rect()
	await click_at(Vector2(r.position.x + r.size.x * 0.75, r.get_center().y))
	await idle(4)
	var v45 := built_volume() / (Part.MM * Part.MM * Part.MM)
	var moved := absf(v45 - v0) / v0
	ok(moved > VOL_BAR, "3 TWIST dragged right (value %.0f degrees) changes the built solid: volume %.0f -> %.0f mm3 (%.2f pct)" % [sl.value, v0, v45, moved * 100.0])
	await shot("twist")

	# 4 one undo step for the Twist change, and Ctrl+Z puts the untwisted volume back
	ok(m.undo.size() == ub3 + 1, "4a UNDO the Twist change is ONE undo step (%d -> %d)" % [ub3, m.undo.size()])
	await ctrl_z()
	var vback := built_volume() / (Part.MM * Part.MM * Part.MM)
	ok(absf(vback - v0) / v0 <= VOL_BAR, "4b UNDO Ctrl+Z puts the built volume back within 0.5 pct (%.0f mm3, untwisted %.0f)" % [vback, v0])

	# 5 the words are plain
	var tr2 := twist_row()
	var words_ok := false
	for c in (tr2[0] as HSlider).get_parent().find_children("*", "Label", true, false):
		var t := String((c as Label).text)
		if t == "Twist left" or t == "Twist right":
			words_ok = true
	ok(words_ok, "5 WORDS the Twist slider's end words are Twist left and Twist right")

	print("p027loftbetwee: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
