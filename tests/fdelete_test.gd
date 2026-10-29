extends SceneTree
## FDELETE (Nick 2026-10-28: like Fusion 360; a beginner clicks one piece of a multi-piece part, then presses Delete or Remove; Undo brings it back).
## Real clicks at 1280x720 from the real start screen: the BUILDING card's Easy Part (free, blank), two separate pieces, and a piece pulled on top of the first.
## Bars (on the old code 1 to 6 FAIL: there is no pick and no Remove):
##   1 a click on piece 2 (a real press and release, nothing armed) picks it: the Remove button shows on the bar; no word "delete" on screen
##   2 Remove (a real click) takes piece 2 out: 1 body left, and the body left is piece 1
##   3 Undo (a real click) brings piece 2 back: 2 bodies
##   4 pick piece 2 again, press the real Delete key: piece 2 goes (1 body, piece 1 stays); Undo brings it back
##   5 a click on empty grid clears the pick: Remove hides; Remove with nothing picked changes nothing
##   6 a piece pulled on top of piece 1 (joined into one body): pick it, Remove: shorter, the volume drops, still 2 bodies
## shots: C:/Temp/claude/fdelete/pick.png (piece 2 picked), removed.png (after Remove), top_removed.png (after bar 6)
const SHOT := "C:/Temp/claude/fdelete"
const DIRT := "user://fdelete_test"

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


func ev_key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	var r := InputEventKey.new()
	r.keycode = k
	r.physical_keycode = k
	r.pressed = false
	root.push_input(r, true)
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


## the mean corner of the part's corners on one side of x (metres): a point inside that piece
func inside_of(x_min: float, x_max: float) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			if v.x > x_min and v.x < x_max:
				s += v
				n += 1
	return s / float(maxi(n, 1))


func top_of(i: int) -> float:
	var faces: Array = Part.body_faces(m.S.part, -1)
	var y := -INF
	for v in faces[i]:
		y = maxf(y, v.y)
	return y


func pick_on() -> bool:
	return bool(pu().ep.get("del_on"))


func bodies() -> int:
	return pu().ep._lumps(pu().res)   # the pieces that do not touch (a join of apart pieces is one body)


func vol() -> float:
	return float(pu().res.get("volume", 0.0))


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
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# two separate pieces: piece 1 on the grid in the middle, piece 2 on the grid at x = +15 cm
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	await click_ctl(draw)
	await drag_screen(scr(Vector3(0.12, 0.0, -0.03)), scr(Vector3(0.18, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	ok(bodies() == 2, "setup: two separate pieces (bodies %d)" % bodies())
	if bodies() != 2:
		print("fdelete: cannot continue")
		quit(1)
		return

	# 1 a real click on piece 2 picks it
	var rm = m.find_child("easypart_remove", true, false)
	var hidden_before: bool = rm == null or not (rm as Control).is_visible_in_tree()
	if rm == null:
		ok(false, "1 the bar has no Remove button")
		print("fdelete: %d fail" % fails)
		quit(1)
		return
	var sp := scr(inside_of(0.06, 0.2))
	ok(sp.x > 0 and sp.x < 1280 and sp.y > 0 and sp.y < 720, "setup: piece 2 is on screen at %s" % sp)
	await click_at(sp)
	await idle(6)
	ok(hidden_before and pick_on() and rm != null and (rm as Control).is_visible_in_tree(), "1 a click on piece 2 picks it: Remove shows on the bar (picked %s)" % pick_on())
	var texts: Array = []
	texts_under(m, texts)
	var dw := []
	for t in texts:
		if String(t).to_lower().find("delete") >= 0:
			dw.append(String(t))
	ok(dw.is_empty(), "1b no word delete on screen %s" % [dw])
	await shot("pick")

	# 2 Remove takes piece 2 out
	await click_ctl(rm)
	await idle(10)
	var left_x := 0.0
	var faces: Array = Part.body_faces(m.S.part, -1)
	for f in faces:
		for v in f:
			left_x = maxf(left_x, v.x)
	ok(bodies() == 1 and left_x < 0.05, "2 Remove takes piece 2 out: 1 body, the one left is piece 1 (bodies %d, max x %.3f)" % [bodies(), left_x])
	await shot("removed")

	# 3 Undo brings it back
	await click_ctl(pu().ep.undo_btn)
	await idle(10)
	ok(bodies() == 2, "3 Undo brings piece 2 back (bodies %d)" % bodies())

	# 4 pick piece 2 again, press the real Delete key
	await click_at(scr(inside_of(0.06, 0.2)))
	await idle(6)
	await ev_key(KEY_DELETE)
	await idle(10)
	faces = Part.body_faces(m.S.part, -1)
	var lo_x := 9.0
	left_x = 0.0
	for f in faces:
		for v in f:
			left_x = maxf(left_x, v.x)
			lo_x = minf(lo_x, v.x)
	ok(bodies() == 1 and lo_x < 0.05 and left_x < 0.05, "4 a pick and the Delete key take piece 2 out (bodies %d, x %.3f..%.3f)" % [bodies(), lo_x, left_x])
	await click_ctl(pu().ep.undo_btn)
	await idle(10)
	ok(bodies() == 2, "4b Undo brings it back again (bodies %d)" % bodies())

	# 5 a click on empty grid clears the pick; Remove with nothing picked changes nothing
	await click_at(scr(inside_of(0.06, 0.2)))
	await idle(4)
	await click_at(Vector2(200, 420))
	await idle(6)
	rm = m.find_child("easypart_remove", true, false)
	ok(rm != null and not (rm as Control).is_visible_in_tree() and not pick_on(), "5 a click on empty grid clears the pick: Remove hides")
	var b0 := bodies()
	await click_ctl(rm)
	await idle(6)
	ok(bodies() == b0, "5b Remove with nothing picked changes nothing (bodies %d -> %d)" % [b0, bodies()])

	# 6 a piece pulled on top of piece 1 (joined into one body): pick it, Remove, the solid gets shorter
	var top0 := top_of(0)
	var v0 := vol()
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.025, top0, -0.025)), scr(Vector3(0.025, top0, 0.025)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	ok(bodies() == 2 and vol() > v0 + 1e-9, "6 a piece pulled on top of piece 1 joins it (bodies %d, volume %.9f -> %.9f)" % [bodies(), v0, vol()])
	var v1 := vol()
	var top_on := top_of(0)
	await click_at(scr(Vector3(0.0, top_on - 0.002, 0.0)))
	await idle(6)
	ok(pick_on(), "6b a click on the top piece picks it")
	await click_ctl(rm)
	await idle(10)
	ok(bodies() == 2 and vol() < v1 - 1e-9 and top_of(0) < top_on - 1e-4, "6c Remove takes the top piece out: 2 bodies, shorter (top %.4f -> %.4f, volume %.9f -> %.9f)" % [top_on, top_of(0), v1, vol()])
	await shot("top_removed")

	print("fdelete: %d fail" % fails)
	quit(1 if fails > 0 else 0)
