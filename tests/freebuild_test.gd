extends SceneTree
## FREEBUILD (Nick 2026-10-28: "free 3D building, no forced house"): the BUILDING card opens straight into a free Easy Part workspace
## (scripts/build/part_ui.gd open_easy, blank), like Fusion 360. Real clicks at 1280x720 from the real start screen.
## Bars (run on the old code before the change: 0, 1, 2b, 3, 4a, 4c FAILED; 2a passed there only because the Easy card's chooser hid the box):
##   0 the BUILDING card, one click: page BUILD, the chooser is NOT open, Easy Part is on
##   1 the part is empty (no steps) and named "Part N" (MyParts.free_name)
##   2 no "House name" control is visible; no visible words with "house" anywhere on screen
##   3 Draw shape works at once: a real drag on the grid, then Pull it up, makes one body
##   4 a house is still reachable: "What to build" -> House (Easy) -> the House name box shows
## shots: C:/Temp/claude/freebuild/open.png (after the card click), house.png (after House)
const SHOT := "C:/Temp/claude/freebuild"
const DIRT := "user://freebuild_test"

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

	# 0 the BUILDING card, one click (auto: a real launch shows the chooser, as main sets it)
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])   # the card's Easy button: one click starts the free Easy Part
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open,
		"0 BUILDING card, one click -> Easy Part on, page BUILD, no chooser (page %s, part on %s, chooser %s)" % [m.cur_page, pu().on, chooser_open])
	await shot("open")

	# 1 an empty part named Part N
	var nm := String(m.S.part.get("name", ""))
	var feats: Array = m.S.part.get("features", [])
	ok(feats.is_empty() and nm.begins_with("Part ") and nm.substr(5).is_valid_int(), "1 the part is empty and named \"Part N\" (name \"%s\", %d steps)" % [nm, feats.size()])

	# 2 no house name box, no house words
	var box = m.find_child("build_house_name", true, false)
	ok(box == null or not (box as Control).is_visible_in_tree(), "2a no House name box is visible on opening")
	var texts: Array = []
	texts_under(m, texts)
	var hw := []
	for t in texts:
		if String(t).to_lower().find("house") >= 0:
			hw.append(String(t))
	ok(hw.is_empty(), "2b no house words on screen %s" % [hw])

	# 3 Draw shape works at once: a real drag on the grid, then Pull it up
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	var bodies := int(pu().res.get("bodies", 0))
	ok(bodies == 1, "3 Draw shape + drag + Pull it up makes one body (bodies %d)" % bodies)

	# 4 a house is reachable: What to build -> House (Expert: the house ribbon has the House name box) -> the box
	var reopen = pu().reopen_btn
	ok(reopen != null and reopen.is_visible_in_tree(), "4a What to build is on the Part ribbon")
	if reopen != null:
		await click_ctl(reopen)
	await idle(6)
	ok(m.build_choose.open, "4b What to build opens the chooser")
	await click_ctl(m.build_choose.btns["house"]["expert"])
	await idle(10)
	var hbox = m.find_child("build_house_name", true, false)
	ok(hbox != null and (hbox as Control).is_visible_in_tree(), "4c House (Expert) shows the House name box")
	await shot("house")

	print("freebuild: %d fail" % fails)
	quit(1 if fails > 0 else 0)
