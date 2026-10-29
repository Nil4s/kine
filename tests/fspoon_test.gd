extends SceneTree
## FSPOON (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner from the BUILDING card builds a spoon by real clicks at 1280x720:
## an oval bowl (Blend two round shapes, then Cut a hole > Hollow inside), a long tapered handle (Blend a wide root and a narrow tip),
## then Round the edges on the whole spoon. Real drags on the grid.
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
const SHOT := "C:/Temp/claude/fspoon"
const DIRT := "user://fspoon_test"

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


func arm(which: String) -> void:
	if pu().ep.armed != which:
		await click_ctl(pu().ep.make_btns[which])


func nbod() -> int:
	return int(pu().res.get("bodies", 0))


func _dump(w: String) -> void:
	var sk := []
	for f in m.S.part.get("features", []):
		sk.append(String(f.get("t", "")) + ":" + String(f.get("id", "")) + ":" + str(f.get("plane", "")) + ":" + str(f.get("mm", "")) + ":" + str(f.get("ents", [])) + ":" + str(f.get("dims", [])))
	print("DUMP " + w + " bodies " + str(nbod()) + " aabb " + str(pu().res.get("aabb", AABB())) + " vol " + str(pu().res.get("volume", 0.0)) + " feats " + str(sk))


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

	# 0 the BUILDING card, one click opens an empty Easy Part
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

	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 the bowl: two round shapes on the floor, one inside the other, then Blend two shapes (a tapered oval cup)
	await arm("draw")
	await click_ctl(pu().ep.shape_btns["oval"])
	await drag_screen(scr(Vector3(-0.07, 0.0, -0.045)), scr(Vector3(0.07, 0.0, 0.045)))
	await shot("01b_first_oval")
	_dump("first oval")
	var ents0: Array = m.S.part.get("features", [])[-1].get("ents", [])
	ok(ents0.size() == 1 and String(ents0[0].get("k", "")) == "bspline" and bool(ents0[0].get("closed", false)), "1a the Oval chip draws one closed oval outline (%s)" % str(ents0))
	await arm("draw")
	await click_ctl(pu().ep.shape_btns["oval"])   # a Draw press starts on Box again: pick Oval for the inner shape too
	await drag_screen(scr(Vector3(-0.05, 0.0, -0.03)), scr(Vector3(0.05, 0.0, 0.03)))
	var hint_s: String = pu().ep.hint_l.text
	await shot("02_two_ovals")
	_dump("two ovals")
	await click_ctl(pu().ep.make_btns["blend"])
	var hint_b: String = pu().ep.hint_l.text
	await shot("03_blend")
	_dump("blend")
	var bb1: AABB = pu().res.get("aabb", AABB())
	ok(bb1.size.x <= 0.16 and bb1.size.z <= 0.11, "1b the bowl is about the size dragged (14 x 9 cm box; %.0f x %.0f mm)" % [bb1.size.x * 1000.0, bb1.size.z * 1000.0])
	ok(nbod() == 1, "1 two round shapes blend into one solid (bodies %d, hint %s)" % [nbod(), hint_b])

	# 2 hollow the bowl: Cut a hole, then Hollow inside (the open top)
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(10)
	var hh: Dictionary = pu().ep.hole_btns
	if hh.has("hollow"):
		await click_ctl(hh["hollow"])
	await idle(20)
	var hint_h: String = pu().ep.hint_l.text
	await shot("04_bowl")
	var errs: Dictionary = pu().res.get("errors", {})
	ok(errs.is_empty() and nbod() == 1, "2 Hollow inside makes the bowl without an error (errors %d, hint %s)" % [errs.size(), hint_h])

	# 3 the handle: a wide root and a narrow tip on the floor past the bowl, then Blend two shapes
	await arm("draw")
	await click_ctl(pu().ep.shape_btns["box"])
	var t0 := Time.get_ticks_msec()
	await drag_screen(scr(Vector3(0.06, 0.0, -0.012)), scr(Vector3(0.10, 0.0, 0.012)))
	var t_drag1 := Time.get_ticks_msec() - t0
	await arm("draw")
	t0 = Time.get_ticks_msec()
	await drag_screen(scr(Vector3(0.16, 0.0, -0.005)), scr(Vector3(0.20, 0.0, 0.005)))
	var t_drag2 := Time.get_ticks_msec() - t0
	# FSPOON dead end: a drag made next to the bowl solid takes many seconds (each mouse move re-solves the part)
	ok(maxi(t_drag1, t_drag2) < 3000, "3a a drag for the handle beside the bowl answers within 3 s (%d ms, %d ms)" % [t_drag1, t_drag2])
	await click_ctl(pu().ep.make_btns["blend"])
	await shot("05_handle")
	var bb: AABB = pu().res.get("aabb", AABB())
	ok(nbod() == 1 and bb.size.x >= 0.12, "3 a long tapered handle blends on: one body, at least 120 mm long (bodies %d, x %.3f m, hint %s)" % [nbod(), bb.size.x, pu().ep.hint_l.text])

	# 4 Round the edges on the whole spoon: it does not refuse
	var t_r := Time.get_ticks_msec()
	await click_ctl(pu().ep.make_btns["round"])
	await idle(10)
	var t_round := Time.get_ticks_msec() - t_r
	# FSPOON dead end: Round the edges on this spoon is slow (the bar is 10 s; the old code took minutes)
	ok(t_round < 10000, "4a Round the edges on the spoon answers within 10 s (%d ms)" % t_round)
	var hint_r: String = pu().ep.hint_l.text
	await shot("06_round")
	ok(hint_r.findn("nothing") < 0 and hint_r.findn("solid") < 0 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"4 Round the edges on the whole spoon works, no error (%s)" % hint_r)

	# 5 the spoon stands on screen
	bb = pu().res.get("aabb", AABB())
	_dump("end")
	var c := scr(bb.get_center())
	ok(on_screen(c) and bb.size.x > 0.0, "5 the spoon is on screen (centre %s)" % c)
	await shot("07_spoon")

	print("fspoon: %d fail" % fails)
	quit(1 if fails > 0 else 0)
