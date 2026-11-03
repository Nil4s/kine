extends SceneTree
## NFIXIT (Friday plan item 86; Nick: monkey-brain easy): Easy Part's Fix it button finds a problem in the part and fixes it in one click,
## with the fix named in plain words, one undo step. A beginner walk with real clicks at 1280 x 720 on the live Easy Part.
## Walk: BUILDING card -> Draw shape, a 120 x 100 mm box on the floor -> Pull it up (20 mm) -> Draw shape again, a second box apart from the
##   first (a loose piece: it floats, touching nothing) -> Pull it up -> press Fix it -> press Fix it again -> Ctrl+Z
## Every count is measured from the BUILT mesh (its surfaces' boxes), never from the code's own variables.
## Bars (each one measured from the built result in mm):
##   1 setup: the built result has two pieces and one of them is loose (joined to nothing, not touching the main piece)
##   2 the top bar has a Fix it button with an icon
##   3 one press on Fix it: the built result has no floating piece
##   4 that press left ONE piece: the first plate, still 20 mm tall (built aabb, mm)
##   5 that press adds exactly ONE undo step
##   6 the press says the fix in plain words (a line, with no jargon)
##   7 Ctrl+Z puts the loose piece back: two pieces built, one undo step fewer
##   8 Fix it with nothing left to fix says Nothing to fix and adds no undo step
## shots: C:/Temp/claude/nfixit/
const SHOT_DIR := "C:/Temp/claude/nfixit"
const DIRT := "user://nfixit_test"

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
	await click_at(p)


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
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## a floor point in mm (x right, y = -z) to the screen
func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the built pieces: each surface's box (mm), read from the built mesh the view shows
func built_boxes() -> Array:
	var out := []
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var bb := AABB(v[0], Vector3.ZERO)
		for p in v:
			bb = bb.expand(p)
		out.append(bb)
	return out


## how many built pieces are loose: the main piece is the one with the biggest box; a piece whose box (grown by 0.5 mm) meets
## neither the main piece's box nor a piece that does is loose (a separate piece, joined to nothing)
func floating_count() -> int:
	var bx := built_boxes()
	if bx.is_empty():
		return 0
	var main := 0
	for i in bx.size():
		if (bx[i] as AABB).get_volume() > (bx[main] as AABB).get_volume():
			main = i
	var linked := {main: true}
	var grew := true
	while grew:
		grew = false
		for i in bx.size():
			for j in linked.keys():
				if not linked.has(i) and (bx[i] as AABB).grow(0.0005).intersects(bx[j] as AABB):
					linked[i] = true
					grew = true
	return bx.size() - linked.size()


func built_h_mm() -> float:
	return (pu().res.get("aabb", AABB()) as AABB).size.y / Part.MM


func fix_button() -> Button:
	return find_named(m, "easypart_fix") as Button


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var ep = pu().ep
	ep.one_side = true   # P153 (a4512f9c): symmetry is on by default; this walk draws single boxes, so it uses One side only
	ep.one_side_btn.set_pressed_no_signal(true)

	# the walk: a plate, then a second box apart from it, pulled up too (it floats)
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(fl(-60, -50), fl(60, 50))
	await click_ctl(ep.make_btns["pull"])
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(fl(180, -40), fl(230, 40))
	await click_ctl(ep.make_btns["pull"])
	await shot("00_two_pieces")

	# 1 setup: two built pieces, one floating
	ok(int(pu().res.get("bodies", 0)) == 2 and floating_count() == 1,
		"1 setup: two built pieces, floating pieces %d (bodies %d)" % [floating_count(), int(pu().res.get("bodies", 0))])

	# 2 the Fix it button, with an icon
	var fb := fix_button()
	ok(fb != null and fb.text == "Fix it" and fb.icon != null,
		"2 the top bar has a Fix it button with an icon (%s)" % ("found" if fb != null else "missing"))

	# 3-5 one press: no floating piece, the plate still 20 mm, ONE undo step
	var ua: int = m.undo.size()
	if fb != null:
		await click_ctl(fb)
	await shot("01_fixed")
	var left := floating_count()
	var h := built_h_mm()
	ok(left == 0, "3 one press on Fix it: floating pieces left %d (was 1)" % left)
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(h - 20.0) <= 0.5,
		"4 that press left one piece: the plate, %.1f mm tall (20 mm), bodies %d" % [h, int(pu().res.get("bodies", 0))])
	ok(m.undo.size() == ua + 1, "5 that press adds exactly ONE undo step (undo %d -> %d)" % [ua, m.undo.size()])

	# 6 the words
	var msg := String(ep.msg)
	var jargon := false
	for w in ["kernel", "solid", "feature", "sketch", "body", "mesh", "replay", "null"]:
		jargon = jargon or msg.to_lower().contains(w)
	ok(msg.contains("piece") and msg.contains("Undo") and not jargon, "6 the press says the fix in plain words: the piece, and how to undo it (%s)" % msg)

	# 7 Ctrl+Z puts the loose piece back
	var ub: int = m.undo.size()
	await ctrl_z()
	ok(int(pu().res.get("bodies", 0)) == 2 and floating_count() == 1 and m.undo.size() == ub - 1,
		"7 Ctrl+Z puts the loose piece back: bodies %d, floating %d, undo %d -> %d" % [int(pu().res.get("bodies", 0)), floating_count(), ub, m.undo.size()])
	await shot("02_undone")

	# 8 Fix it again with nothing left to fix: says so, no undo step (the Ctrl+Z above put the piece back, so Fix it first)
	if fix_button() != null:
		await click_ctl(fix_button())
	var uc: int = m.undo.size()
	if fix_button() != null:
		await click_ctl(fix_button())
	var msg8 := String(ep.msg)
	ok(msg8.to_lower().contains("nothing") and m.undo.size() == uc,
		"8 Fix it with nothing to fix says Nothing to fix and adds no undo step (%s, undo %d -> %d)" % [msg8, uc, m.undo.size()])

	print("NFIXIT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
