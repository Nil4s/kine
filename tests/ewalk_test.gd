extends SceneTree
## godot --path . --position 4000,4000 -s tests/ewalk_test.gd     (MONKEY WALK of EASY PART: scripts/easy_part.gd; needs the CAD DLL and a window)
## A first-time user with the mouse only, 1280 x 720, from Easy home, an EMPTY part: every MAKE button once, the most obvious thing first.
## Shots: C:/Temp/claude/ewalk/<button>.png
## Bars (written before the fix; the three fixed frictions, each must FAIL on the old code):
##   1 COVER    the Easy home 'What should he do?' panel (the animate page's, still on) is not over Easy Part: hidden, and clear of the MAKE row,
##              the colour chips and the draw area
##   2 REFUSE   Round the edges, Cut a hole, Mirror that and Cut in two, pressed on an empty part, say what to press next (Pull it up)
##   3 SPIN     Spin it round after the shape was pulled up says what to do (draw a new shape), not just "Draw a shape first"
##   4 LIVE     every one of the twelve buttons the walk presses changes the part or says something (no dead button)
const SHOT := "C:/Temp/claude/ewalk"
const DIRT := "user://ewalk_test"

var fails := 0
var m: Node
var ep: Node
var dead: Array = []
var refuse: Array = []
var cover_faults: Array = []


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


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


func click_at(p: Vector2) -> void:
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


func free_at(fx: float, fy: float) -> Vector2:
	var cl: Rect2 = m.nav_clear_rect()
	var p := Vector2(cl.position.x + cl.size.x * fx, cl.position.y + cl.size.y * fy)
	for i in 40:
		var near := false
		for d in ep._dot_list():
			if (d["scr"] as Vector2).distance_to(p) <= 30.0:
				near = true
		if not near and not ep._over_ui(p):
			return p
		p += Vector2(0, 14)
	return p


func shot(nm: String) -> void:
	await idle(4)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func report(key: String, tag: String) -> void:
	await idle(4)
	refuse.append([key + ("_empty" if tag.begins_with("A") else ""), ep.msg])
	var panel: Control = m.easy.home.panel if m.easy != null and m.easy.home != null else null
	if panel != null and panel.is_visible_in_tree():
		cover_faults.append(key)
	print("WALK %s | %s | msg=[%s] hint=[%s] status=[%s] bodies=%s" % [key, tag, ep.msg, ep.hint_l.text, ep.status_l.text, str(ep.pu.res.get("bodies", 0))])
	await shot(key)


func _hits(n: Node, p: Vector2, out: Array) -> Array:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).get_global_rect().has_point(p) and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		out.append("%s:%d" % [n.get_path(), (n as Control).mouse_filter])
	for c in n.get_children():
		_hits(c, p, out)
	return out


## a press is alive when the part changes or the screen says something (a refusal in words counts)
func press(key: String) -> void:
	var u0: int = m.undo.size()
	var s0: String = JSON.stringify(m.S.part)
	var t0: String = ep.hint_l.text
	await click_ctl(ep.make_btns[key])
	await idle(3)
	if m.undo.size() == u0 and JSON.stringify(m.S.part) == s0 and ep.hint_l.text == t0 and ep.hint_l.text.strip_edges() == "":
		dead.append(key)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
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
	ss.show_screen()
	await idle(4)
	await click_ctl(ss.find_child("easy_building", true, false))
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(m.ui_root.find_child("easybuild_btn_what_to_build", true, false) as Control)
	await click_ctl(m.build_choose.root_box.find_child("easy_part", true, false) as Control)
	await idle(6)
	ep = m.bld.part.ep
	m.S.part = {}   # the Part card starts a sword: the walk starts with NO template (the task's empty part)
	ep.entered()
	m.bld.part.sync()
	await idle(6)
	print("START easy=%s msg=[%s] hint=[%s] status=[%s]" % [str(m.bld.part.easy), ep.msg, ep.hint_l.text, ep.status_l.text])
	await shot("start")

	# pass A: the first press of each solid-making button on the EMPTY part (refusals, nothing changes)
	for k in ["pull", "spin", "round", "hole", "mirror", "blend", "split", "repeat", "stick"]:
		await press(k)
		await report(k, "A empty part first press")
	# pass B: the walk left to right, the way a beginner reads the row
	await press("draw")
	await report("draw", "arm Draw shape (empty part)")
	await drag_pts([Vector2(700, 400), Vector2(760, 450), Vector2(820, 500)])
	await report("draw_drag", "drag a box on the grid")
	await press("pull")
	await report("pull", "Pull it up")
	await press("spin")
	await report("spin", "Spin it round (no new shape)")
	await press("round")
	await report("round", "Round the edges")
	await press("hole")
	await report("hole", "Cut a hole")
	await press("mirror")
	await report("mirror", "Mirror that")
	await press("curve")
	await report("curve", "arm Curvy line")
	var loop: Array = []
	for i in 25:
		var a := TAU * i / 24.0
		loop.append(Vector2(860, 420) + Vector2(cos(a), sin(a)) * 40.0)
	await drag_pts(loop)
	await report("curve_drag", "drag a loop")
	await press("blend")
	await report("blend", "Blend two shapes")
	await press("split")
	await report("split", "Cut in two")
	await press("colour")
	await report("colour", "arm Colour")
	var chip: Button = null
	for b in ep.colour_box.find_children("*", "Button", true, false):
		chip = b
		break
	if chip != null:
		await click_ctl(chip)
	await report("colour_chip", "Colour: first chip")
	await press("repeat")
	await report("repeat", "Repeat it")
	await press("stick")
	await report("stick", "Stick together (arm)")
	var faces := Part.body_faces(m.S.part, -1)
	for i in mini(2, faces.size()):
		var sum := Vector3.ZERO
		for q in faces[i]:
			sum += q
		await click_at(m.cam.unproject_position(sum / float(maxi(faces[i].size(), 1))))
	await report("stick_picked", "Stick together: two pieces picked")
	await click_ctl(ep.stick_btns["join"])
	await report("stick_join", "Stick together: Join")
	var rd := {}
	for r in refuse:
		rd[r[0]] = String(r[1])
	var bad := []
	for k in ["round", "hole", "mirror", "split"]:
		if not String(rd.get(k + "_empty", "")).contains("Pull it up"):
			bad.append(k)
	ok(bad.is_empty(), "2 REFUSE solid-first refusals say what to press next (not: %s)" % str(bad))
	ok(String(rd.get("spin", "")).contains("Draw a new one"), "3 SPIN after a pull, Spin it round says to draw a new shape: %s" % str(rd.get("spin", "")))
	ok(cover_faults.is_empty(), "1 COVER the animate panel was over Easy Part at: %s" % str(cover_faults))
	ok(dead.is_empty(), "4 LIVE buttons that did nothing: %s" % str(dead))
	print("ewalk: %d fail" % fails)
	quit(1 if fails > 0 else 0)
