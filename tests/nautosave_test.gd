extends SceneTree
## godot --path . --position 4000,4000 -s tests/nautosave_test.gd     (EASY PART, autosave every step to user:// and crash restore: "Bring back your part"; needs the CAD DLL)
## Bars (real clicks and drags through root.push_input at 1280 x 720, from Easy home: a 3D BUILDING project, Part, Easy; no keyboard):
##   1 REPEAT IT   refused in plain words with no solid; then a shape pulled up, Repeat it: ONE undo step, a Part pattern step (row, 3 copies),
##                 the volume is 3 times the shape (within 3 pct), no failed step; the How many slider drag to 5: ONE undo step, 5 copies
##   2 RING        Ring: ONE undo step, the pattern turns circular round the up axis (Y), no failed step; the Gap slider sizes the circle (bar redefined f9791999)
##   3 STICK       Cut in two (two pieces), Stick together, click each piece in the view, Keep the overlap: refused in words, no undo step;
##                 then Join: ONE undo step, one solid left, a combine step; with one piece left Stick together is refused in words
##   4 WORDS       no key name in any visible Easy text (labels, tooltips, hints, status) with the MAKE row, the repeat row and the stick row open
##   5 LAYOUT      at 1280 x 720 all twelve MAKE buttons are inside the window, and the MAKE row, panel, hint, status and repeat row overlap nothing
## Shots: C:/Temp/claude/nautosave/shot.png (the Easy column with the repeat row open), shot_stick.png (two pieces picked)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/nautosave"
const DIRT := "user://nautosave_test"
const AUTO := "user://nautosave_test/autosave/part.json"   # this test's own file (other Easy Part runs autosave to their own)


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


## a click at a point in the view (no control under it)
func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## a real press, a drag through every point, a release (the grid draws)
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


## the record's built size in mm: the bounds of every body corner (measured from Part.body_faces, not from the code's own numbers)
func bounds_mm(rec: Dictionary) -> Array:
	var faces := Part.body_faces(rec, -1)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in faces.size():
		for q in faces[i]:
			lo = lo.min(q)
			hi = hi.max(q)
	if faces.is_empty():
		return [Vector3.ZERO, Vector3.ZERO]
	return [lo * 1000.0, hi * 1000.0]


func bounds_same(a: Array, b: Array) -> bool:
	return a[0].distance_to(b[0]) < 0.05 and a[1].distance_to(b[1]) < 0.05


## the list of step kinds and ids: the step list the beginner sees
func step_list(rec: Dictionary) -> String:
	var out := []
	for f in rec.get("features", []):
		out.append("%s:%s" % [String(f.get("t", "")), String(f.get("id", ""))])
	return ",".join(out)


func saved_rec() -> Dictionary:
	if not FileAccess.file_exists(AUTO):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(AUTO))
	return Part.from_file(d) if d is Dictionary else {}


func find_btn(nm: String) -> Button:
	var b = root.find_child(nm, true, false)
	return b as Button if b is Button and (b as Button).is_visible_in_tree() else null


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUTO.get_base_dir()))
	DirAccess.open(AUTO.get_base_dir()).remove("part.json")   # this test's own file: a clean first start
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the autosave cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	ep.auto_path = AUTO
	m.S.part = {}
	pu.upto = -1
	pu.sync()
	await idle(3)
	# WALK: a beginner draws a box, pulls it up, mirrors it (real clicks)
	await click_ctl(ep.make_btns["draw"])
	var a0 := free_at(0.2, 0.25)
	await drag_pts([a0, a0 + Vector2(45, 35), a0 + Vector2(90, 70)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(4)
	var live1: Dictionary = m.S.part
	var s1 := saved_rec()
	var b1 := bounds_mm(live1)
	ok(FileAccess.file_exists(AUTO) and not s1.is_empty(), "A1 AUTOSAVE: after Pull it up the part is saved to %s" % AUTO)
	ok(s1.get("features", []).size() == live1.get("features", []).size() and step_list(s1) == step_list(live1),
		"A1 AUTOSAVE: the saved step list matches the part on screen (%d steps)" % live1.get("features", []).size())
	ok(not b1[0].is_equal_approx(b1[1]) and bounds_same(bounds_mm(s1), b1),
		"A1 AUTOSAVE: the saved part is the same size in mm (%s -> %s)" % [str(b1[1] - b1[0]), str(bounds_mm(s1)[1] - bounds_mm(s1)[0])])
	var n1: int = live1.get("features", []).size()
	await click_ctl(ep.make_btns["mirror"])
	await idle(4)
	var live2: Dictionary = m.S.part
	var s2 := saved_rec()
	ok(live2.get("features", []).size() > n1, "A2 WALK: Mirror that adds a step (%d -> %d)" % [n1, live2.get("features", []).size()])
	ok(step_list(s2) == step_list(live2) and bounds_same(bounds_mm(s2), bounds_mm(live2)) and not s2.is_empty(),
		"A2 AUTOSAVE: after Mirror that the saved file has the same %d steps and size in mm" % live2.get("features", []).size())
	var pre_steps := step_list(live2)
	var pre_b := bounds_mm(live2)
	var pre_bodies := int(pu.res.get("bodies", 0))
	var pre_undo: int = m.undo.size()
	# CRASH: the next start, an empty part (the card must offer the old one)
	m.S.part = {}
	pu.upto = -1
	pu.sync()
	await idle(4)
	var rb := find_btn("easypart_restore")
	ok(rb != null and rb.text == "Bring back your part", "B CARD: on the next start an empty Easy Part offers a button 'Bring back your part' (%s)" % ("missing" if rb == null else rb.text))
	if rb == null:
		quit(fails)
		return
	await shot("card")
	await click_ctl(rb)
	await idle(6)
	var live3: Dictionary = m.S.part
	ok(step_list(live3) == pre_steps and not pre_steps.is_empty(),
		"C1 RESTORE: the step list is intact (%d steps before, %d after)" % [pre_steps.split(",").size(), live3.get("features", []).size()])
	ok(bounds_same(bounds_mm(live3), pre_b), "C2 RESTORE: the part is the same size in mm (%s)" % str(bounds_mm(live3)[1] - bounds_mm(live3)[0]))
	ok(int(pu.res.get("bodies", 0)) == pre_bodies and pre_bodies > 0, "C2 RESTORE: the same number of solids (%d)" % int(pu.res.get("bodies", 0)))
	ok(m.undo.size() == pre_undo + 1 or m.undo.size() == 1, "C3 ONE STEP: the restore is one undo step (%d)" % m.undo.size())
	await click_ctl(ep.undo_btn)
	await idle(4)
	ok(live3 != null and m.S.part.get("features", []).size() == 0, "C3 UNDO: Undo takes the restore back (%d steps left)" % m.S.part.get("features", []).size())
	await click_ctl(ep.redo_btn)
	await idle(4)
	ok(step_list(m.S.part) == pre_steps, "C3 REDO: Redo brings the restored steps back")
	await shot("restored")
	DirAccess.open(AUTO.get_base_dir()).remove("part.json")
	print("nautosave: fails=%d" % fails)
	quit(fails)
