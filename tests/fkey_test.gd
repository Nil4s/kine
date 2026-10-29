extends SceneTree
## FKEY (Nick 2026-10-28: "free 3D building, anything"): a beginner from the BUILDING card builds a house key by real clicks at 1280x720:
## a flat head, a hole in the head (Cut a hole), a long blade drawn over the head, three teeth on one edge. Real drags on the grid.
## Walk: BUILDING Easy -> Draw shape + drag -> Pull it up -> Round the edges -> Cut a hole. Dead ends found on the old code:
##   D1 the empty part opens with the grid tile in the lower right corner, its origin below the screen (bar 1 FAILS)
##   D2 after Cut a hole the solid is off the screen (bar 3 FAILS)
##   D3 a drag with no tool armed does nothing; the hint only says what to press (bar 2 passes: the words name Draw shape)
## Bars (run on the old code before the change: 0, 1, 2b, 3, 4a, 4c FAILED; 2a passed there only because the Easy card's chooser hid the box):
##   0 the BUILDING card, one click: page BUILD, the chooser is NOT open, Easy Part is on
##   1 the part is empty (no steps) and named "Part N" (MyParts.free_name)
##   2 no "House name" control is visible; no visible words with "house" anywhere on screen
##   3 Draw shape works at once: a real drag on the grid, then Pull it up, makes one body
##   4 a house is still reachable: "What to build" -> House (Easy) -> the House name box shows
## shots: C:/Temp/claude/freebuild/open.png (after the card click), house.png (after House)
const SHOT := "C:/Temp/claude/fkey"
const DIRT := "user://fkey_test"

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


func on_screen(p: Vector2) -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= vs.x and p.y <= vs.y


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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy,
		"0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)
	var hint0: String = pu().ep.hint_l.text
	ok(hint0.begins_with("Press Draw shape") and hint0.find("drag") >= 0, "1 an empty part says what to press first: Press Draw shape, then drag (%s)" % hint0)

	# 1b a beginner presses Pull it up with nothing drawn: the words say what to do first
	await click_ctl(pu().ep.make_btns["pull"])
	var hint_p: String = pu().ep.hint_l.text
	ok(hint_p.findn("draw") >= 0, "1b Pull it up with nothing drawn says to draw first (%s)" % hint_p)
	# 1c Draw shape armed, no drag yet: the words say to drag on the grid
	await click_ctl(pu().ep.make_btns["draw"])
	var hint_a: String = pu().ep.hint_l.text
	ok(hint_a.findn("drag") >= 0 or hint_a.findn("grid") >= 0, "1c Draw shape armed says how to draw (%s)" % hint_a)
	await click_ctl(pu().ep.make_btns["draw"])   # disarm again

	# 2 the head: Draw shape, drag, Pull it up
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.06, 0.0, -0.03)), scr(Vector3(-0.02, 0.0, 0.03)))
	var hint_d: String = pu().ep.hint_l.text
	ok(hint_d.find("Pull it up") >= 0, "2 after a drag the hint names Pull it up (%s)" % hint_d)
	await click_ctl(pu().ep.make_btns["pull"])
	await shot("02_head")
	ok(int(pu().res.get("bodies", 0)) == 1, "2b the head is one body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 3 the hole in the head
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(20)
	await shot("03_hole")
	var n_cut := 0
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "extrude" and String(f.get("op", "")) == "cut":
			n_cut += 1
	ok(n_cut == 1, "3 Cut a hole adds one cut step through the head (cuts %d)" % n_cut)

	# 4 the blade: Draw shape, a long drag over the head's right edge, Pull it up
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.006)), scr(Vector3(0.11, 0.0, 0.006)))
	await click_ctl(pu().ep.make_btns["pull"])
	await shot("04_blade")
	ok(int(pu().res.get("bodies", 0)) == 1, "4 the blade joins the head: one body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 5 the teeth on the blade's lower edge: three small boxes, each Draw shape then Pull it up
	for tx in [0.02, 0.05, 0.08]:
		await click_ctl(pu().ep.make_btns["draw"])
		await drag_screen(scr(Vector3(tx - 0.006, 0.0, 0.003)), scr(Vector3(tx + 0.006, 0.0, 0.012)))
		await click_ctl(pu().ep.make_btns["pull"])
	await shot("05_teeth")
	ok(int(pu().res.get("bodies", 0)) == 1, "5 three teeth join the blade: one body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 5b Undo takes off the last tooth only: one undo step, bodies still 1
	var nb_before := int(pu().res.get("bodies", 0))
	m._undo()
	await idle(20)
	ok(int(pu().res.get("bodies", 0)) == 1 and m.S.part.get("features", []).size() > 0, "5b Undo leaves the key with one body (bodies %d, was %d)" % [int(pu().res.get("bodies", 0)), nb_before])
	# 5c Round the edges on the whole key: it works and says so
	await click_ctl(pu().ep.make_btns["round"])
	await idle(10)
	var hint_r: String = pu().ep.hint_l.text
	ok(hint_r.findn("solid") < 0 and hint_r.findn("nothing") < 0, "5c Round the edges on the key does not refuse (%s)" % hint_r)
	await shot("05c_round")
	# 5d after Undo, the Round slider says How round (not the How far of the pull it replaced)
	var rows_lab := String(pu().ep.rows[-1]["label"]) if not pu().ep.rows.is_empty() else ""
	ok(rows_lab == "How round", "5d the slider after Round is named How round, after an Undo (row \"%s\", tweak %s)" % [rows_lab, str(pu().ep.tweak.get("label", ""))])

	# 6 the key stands on screen and is long: its box is at least 0.12 m long
	var bb: AABB = pu().res.get("aabb", AABB())
	var c := scr(bb.get_center())
	ok(bb.size.x >= 0.12 and on_screen(c), "6 the key is at least 120 mm long and on screen (box %s, centre %s)" % [bb.size, c])
	await shot("06_key")

	print("fkey: %d fail" % fails)
	quit(1 if fails > 0 else 0)
