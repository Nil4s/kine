extends SceneTree
## godot --path . --position 4000,4000 -s tests/emirror_test.gd     (EMIRROR: Easy Part Mirror that on a piece OFF the middle line; scripts/easy_part.gd, scripts/build/part.gd; needs the CAD DLL and a window)
## A beginner from the REAL start screen (building card, Part, Easy). Real clicks and drags at 1280 x 720 only.
##   Draw shape: a box dragged on the grid to one side of the middle line, Pull it up, Mirror that.
## Bars:
##   M0  the piece sits off the middle line (the solid does not touch x = 0)
##   M1  Mirror that: ONE body (one touching piece, not two lumps), no failed step, ONE undo step
##   M2  the mirror is across the middle of the PART: the solid keeps its place (its x centre and width do not move)
##   M3  the words do not send the beginner to Stick together (the two halves do not touch)
## Shots: C:/Temp/claude/emirror/off_line.png, mirrored.png

const SHOT := "C:/Temp/claude/emirror"
const DIRT := "user://emirror_test"
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


func labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


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
		print("FAIL: no KineCAD DLL, the Mirror cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	await click_ctl(ep.empty_chip)   # a clean floor (the sword is the default)
	# a box dragged on the grid on the left of the clear view (the middle line is the grid's x = 0)
	await click_ctl(ep.make_btns["draw"])
	var a0 := free_at(0.92, 0.25)
	await drag_pts([a0, a0 + Vector2(14, 10), a0 + Vector2(28, 20)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(2)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	var off := bb0.position.x > 0.005 or bb0.end.x < -0.005
	ok(off and int(s0["bodies"]) == 1, "M0 the piece sits off the middle line: x %.3f .. %.3f m, %d body" % [bb0.position.x, bb0.end.x, int(s0["bodies"])])
	await shot("off_line")
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["mirror"])
	await idle(3)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var lab := []
	labels(ep.status, lab)
	var words := " ".join(lab) + " " + String(ep.hint_l.text) + " " + String(ep.msg)
	var lumps: int = ep._lumps(s1)   # the same test as the status line: pieces that touch
	ok(lumps == 1 and (s1["errors"] as Dictionary).is_empty() and m.undo.size() == ub + 1,
		"M1 Mirror that: ONE body (%d touching pieces), failed steps %s, ONE undo step (%d -> %d)" % [lumps, str(s1["errors"]), ub, m.undo.size()])
	ok(absf((bb1.position.x + bb1.end.x) - (bb0.position.x + bb0.end.x)) < 0.002 and absf(bb1.size.x - bb0.size.x) < 0.002,
		"M2 across the middle of the part: x %.3f .. %.3f m -> %.3f .. %.3f m (the piece keeps its place)" % [bb0.position.x, bb0.end.x, bb1.position.x, bb1.end.x])
	ok(words.to_lower().find("stick together") < 0 and words.to_lower().find("do not touch") < 0,
		"M3 the words do not send you to Stick together: '%s'" % String(ep.msg))
	await shot("mirrored")
	print("emirror: %d fail" % fails)
	quit(1 if fails > 0 else 0)
