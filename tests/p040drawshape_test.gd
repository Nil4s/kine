extends SceneTree
## p040drawshape (Friday plan item 40: Draw shape, straight / curvy toggle per segment while drawing: hold Shift = curve).
## A beginner from the REAL start screen, real clicks, drags and Shift at 1280 x 720 on the live Easy Part:
##   a) Draw shape, shape chip Line, one drag with no Shift: every segment is straight (ONE line in the built sketch)
##   b) Draw shape, shape chip Line, a drag whose first stretch is straight and whose last two stretches are held with Shift:
##      the built sketch is a straight line joined to a curve, and the curve bends away from its chord
## Bars (measured from the BUILT result: the newest sketch feature in the saved part, its entity kinds and points in mm; the
## undo count; the words on the status line; never from variables of the code):
##   0 the Line chip exists, says Line, and one click on it selects it
##   1 a drag with no Shift draws ONE straight line entity (kind line), in mm, and the line has real length
##   2 that drag is ONE undo step
##   3 a drag with Shift on its last stretches draws a line then a curve: entity kinds are [line, bspline]
##   4 the curve joins the line at the same point (end of the line = start of the curve, within 0.01 mm)
##   5 the curve bends: a point on it is more than 2 mm off the chord from its first to its last point
##   6 the Shift drag is ONE undo step
##   7 the status line says Line drawn in plain words
## shots: C:/Temp/claude/p040drawshape/
const SHOT := "C:/Temp/claude/p040drawshape"
const DIRT := "user://p040drawshape_test"
const BEND_MM := 2.0

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.shift_pressed = shift
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true, shift := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.shift_pressed = shift
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


## a real press, a drag through every point (shift[i] = Shift held for the move to point i), a release
func drag_pts(pts: Array, shifts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i], true, bool(shifts[i]))
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


## the newest sketch feature of the saved part (its entities), or {} when there is none
func newest_sketch() -> Dictionary:
	var fs: Array = m.S.part.get("features", [])
	for i in range(fs.size() - 1, -1, -1):
		if String(fs[i].get("t", "")) == "sketch":
			return fs[i]
	return {}


## the distance (mm) from p to the straight chord a-b
func off_chord(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ln := a.distance_to(b)
	if ln < 1e-6:
		return p.distance_to(a)
	return absf((b - a).cross(p - a)) / ln


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

	# 0 the Line chip: it exists, says Line, and one click selects it
	var has_line: bool = ep.shape_btns.has("line")
	ok(has_line and String((ep.shape_btns["line"] as Button).text) == "Line", "0a CHIP the Draw shape row has a Line chip (%s)" % str(has_line))
	await click_ctl(ep.make_btns["draw"])
	if has_line:
		await click_ctl(ep.shape_btns["line"])
		ok((ep.shape_btns["line"] as Button).button_pressed and ep.shape == "line", "0b CHIP one click on Line selects it (shape %s)" % str(ep.shape))
	else:
		ok(false, "0b CHIP one click on Line selects it (no Line chip)")

	# 1 + 2 a drag with no Shift: ONE straight line, ONE undo step
	var ub1: int = m.undo.size()
	var c0 := free_at(0.2, 0.3)
	var pa := [c0, c0 + Vector2(60, 0), c0 + Vector2(120, 0), c0 + Vector2(180, 0)]
	await drag_pts(pa, [false, false, false, false])
	var sk := newest_sketch()
	var ents: Array = sk.get("ents", [])
	var kinds := []
	for e in ents:
		kinds.append(String(e.get("k", "")))
	var seg_len := 0.0
	if ents.size() == 1 and kinds[0] == "line":
		seg_len = e_a(ents[0]).distance_to(e_b(ents[0]))
	ok(kinds == ["line"] and seg_len > 5.0, "1 STRAIGHT a drag with no Shift draws ONE line entity, %.1f mm long (kinds %s)" % [seg_len, str(kinds)])
	ok(m.undo.size() == ub1 + 1, "2 UNDO the straight drag is ONE undo step (%d -> %d)" % [ub1, m.undo.size()])
	await shot("straight")

	# 3 to 6 a drag: a straight first stretch, then two stretches held with Shift that bend
	var ub2: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])   # a drawing disarms Draw: the second line is armed again, as a beginner presses it
	await click_ctl(ep.shape_btns["line"])
	var c1 := free_at(0.2, 0.62)
	var pb := [c1, c1 + Vector2(60, 0), c1 + Vector2(90, 50), c1 + Vector2(150, 0)]
	await drag_pts(pb, [false, false, true, true])
	sk = newest_sketch()
	ents = sk.get("ents", [])
	kinds = []
	for e in ents:
		kinds.append(String(e.get("k", "")))
	ok(kinds == ["line", "bspline"], "3 MIXED a straight stretch then a Shift stretch: the sketch is [line, bspline] (kinds %s)" % str(kinds))
	var joined := false
	var bend := 0.0
	if kinds == ["line", "bspline"]:
		var bp: Array = ents[1].get("pts", [])
		joined = e_b(ents[0]).distance_to(Vector2(bp[0][0], bp[0][1])) <= 0.01
		var fa := Vector2(bp[0][0], bp[0][1])
		var fb := Vector2(bp[bp.size() - 1][0], bp[bp.size() - 1][1])
		for i in range(1, bp.size() - 1):
			bend = maxf(bend, off_chord(Vector2(bp[i][0], bp[i][1]), fa, fb))

	ok(joined, "4 JOINED the line's end is the curve's start (same point in mm)")
	ok(bend > BEND_MM, "5 CURVED a Shift stretch bends away from its chord by %.1f mm (more than %.1f)" % [bend, BEND_MM])
	ok(m.undo.size() == ub2 + 1, "6 UNDO the mixed drag is ONE undo step (%d -> %d)" % [ub2, m.undo.size()])
	await shot("mixed")

	# 7 the words on the status line
	var st := String(ep.msg)   # the words under the drawing (the say line), not the solid's status
	ok(st.begins_with("Line drawn"), "7 WORDS the say line says Line drawn (%s)" % st)

	print("p040drawshape: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)


## the start and end of a line entity, in mm (the stored Part arrays)
func e_a(e: Dictionary) -> Vector2:
	return Vector2(e["a"][0], e["a"][1])


func e_b(e: Dictionary) -> Vector2:
	return Vector2(e["b"][0], e["b"][1])
