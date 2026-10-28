extends SceneTree
## godot --path . --position 4000,4000 -s tests/myparts_test.gd     (MY PARTS: a part made in Easy Part, Use in a scene saves it to the My parts store (scripts/build/myparts.gd) and the library's My parts column; needs a window and the CAD DLL)
## BARS, stated before any measurement (real clicks / drags at 1280 x 720; the folder is user://myparts_test, a parameter of MyParts; the real user://parts is never touched):
##  M1  STORE  a box drawn on the grid, pulled up and rounded in Easy Part, named in the top name box "Crank", Use in a scene: the store has "Crank" (its
##             record file) and a picture file of it (png), within 3 s
##  M2  LIBRARY the library's My parts column entry lists "Crank" alone, its card has the picture (a texture, no placeholder)
##  M3  CLICK  a click on the Crank card puts a second copy in the set: props +1, the kind is part:Crank#..., ONE undo step
##  M4  REPLACE Use in a scene again with the same name: still ONE saved part (one file), undo +1, the part record is unchanged
##  M5  REOPEN a fresh library (closed and opened again) still lists Crank with its picture; the store lists it from disk
##  M6  EXPERT the same card click in Expert (Easy off): props +1, ONE undo step, the page is STAGE
## Shot: C:/Temp/claude/myparts/shot.png (the library open on My parts).
var fails := 0
var m: Node
var lib: ObjectLibrary
const SHOT := "C:/Temp/claude/myparts/shot.png"
const DIRT := "user://myparts_test"
const DIRP := "user://myparts_test/parts"


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


## a control inside a scroll list, scrolled into view first (the library column is taller than a short window)
func reveal(c: Control) -> void:
	var n: Node = c.get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n != null:
		(n as ScrollContainer).ensure_control_visible(c)
	await idle(3)


## a saved record as JSON round-trips it (ints and floats are the same number on disk)
func norm(x) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(x)))


func wipe(d: String) -> void:
	var a := ProjectSettings.globalize_path(d)
	if not DirAccess.dir_exists_absolute(a):
		return
	for f in DirAccess.get_files_at(a):
		DirAccess.remove_absolute(a + "/" + f)
	for sub in DirAccess.get_directories_at(a):
		wipe(d + "/" + sub)
		DirAccess.remove_absolute(a + "/" + sub)


func disk(p: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(p))


## the store module, loaded by path (a missing module is a FAIL line, not a parse error)
func store() -> GDScript:
	return load("res://scripts/build/myparts.gd") as GDScript


func crank_count(sc) -> int:
	var n := 0
	for pt in sc.list():
		if String(pt["name"]) == "Crank":
			n += 1
	return n


func wait_picture(sc) -> void:
	for i in 180:
		if disk(sc.thumb_of("Crank")):
			return
		await idle(1)


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
	var sc = store()
	if sc != null:
		sc.dir = DIRP
	wipe(DIRT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRP))
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28: free 3D building, no forced house. The BUILDING card now opens a blank part on Part; this bar opens the
	# Part itself from BUILD, as it did before, so it starts from the same state (Part off, no part) it always did
	pu.set_on(false)
	m.S.part = {}
	await idle(8)   # the ribbon moves once Part is off: let it settle before a click
	var ep: EasyPart = pu.ep
	if sc == null or not Part.available():
		ok(false, "M0 the store module and the CAD DLL load (store %s, DLL %s)" % [sc != null, Part.available()])
		print("myparts: %d fail" % fails)
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	m.S.part["name"] = "Crank"   # the part's own name (a template's, or one given earlier): the name it is saved under
	m.ui_scene_name.text = "Fight scene"   # the SCENE's name box: it must NOT name the part (every part would replace the last one)
	# make the part by clicks: draw a box on the grid, pull it up, round its edges
	await click_ctl(ep.make_btns["draw"])
	var cam: Camera3D = m.cam
	await drag_screen(cam.unproject_position(Vector3(1.4, 0.0, 0.0)), cam.unproject_position(Vector3(1.5, 0.1, 0.0)))
	await click_ctl(ep.make_btns["pull"])
	await idle(3)
	await click_ctl(ep.make_btns["round"])
	await idle(3)

	# M1 Use in a scene: the store has it with a picture
	await click_ctl(ep.use_scene_btn)
	await wait_picture(sc)
	ok(disk(sc.path_of("Crank")) and disk(sc.thumb_of("Crank")) and sc.path_of("Crank").begins_with(DIRP),
		"M1 Use in a scene: the store has Crank (record %s, picture %s) in the test folder" % [disk(sc.path_of("Crank")), disk(sc.thumb_of("Crank"))])
	var saved: Dictionary = sc.load_part("Crank")
	ok(not saved.is_empty() and norm(saved.get("features", [])) == norm(m.S.part.get("features", [])), "M1 the saved record is the part as made (features equal)")
	var rec_before := norm(m.S.part)

	# M2 the library's My parts column lists it, with its picture
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = DIRT + "/recent.json"
	lib.clear_recent()
	lib.open()
	await idle(3)
	var side := lib.find_child("cat_my_parts", true, false) as Button
	ok(side != null and side.is_visible_in_tree(), "M2 the My parts entry is in the library column")
	if side != null:
		await reveal(side)
		await click_ctl(side)
	await lib.thumbs.settle()
	await idle(3)
	var ps := lib.in_group("My parts")
	var tile := lib.find_child("tile_mypart_saved_Crank", true, false) as Button
	var pic: TextureRect = lib._pics.get("mypart:saved:Crank") as TextureRect
	ok(ps.size() == 1 and String(ps[0]["name"]) == "Crank" and tile != null and pic != null and pic.texture != null,
		"M2 My parts lists Crank alone, with its picture (cards %d, picture %s)" % [ps.size(), pic != null and pic.texture != null])

	# M3 a click on the card puts a second copy in the set: props +1, ONE undo step
	var u0: int = m.undo.size()
	var p0: int = m.S.props.size()
	await click_ctl(tile)
	await idle(4)
	var last: Dictionary = m.S.props[-1] if m.S.props.size() > 0 else {}
	ok(m.S.props.size() == p0 + 1 and String(last.get("kind", "")).begins_with("part:Crank#") and m.undo.size() == u0 + 1,
		"M3 a card click puts Crank in the set: props %d -> %d, kind %s, undo %d -> %d" % [p0, m.S.props.size(), String(last.get("kind", "")), u0, m.undo.size()])
	await idle(3)

	# M4 Use in a scene again, same name: replaced, not duplicated
	m._page_set("BUILD")
	pu.open_easy()
	await idle(4)
	var u1: int = m.undo.size()
	await click_ctl(ep.use_scene_btn)
	await idle(60)
	ok(crank_count(sc) == 1 and sc.list().size() == 1 and m.undo.size() == u1 + 1,
		"M4 the same name replaces: %d saved part(s), undo +%d" % [sc.list().size(), m.undo.size() - u1])
	ok(norm(sc.load_part("Crank").get("features", [])) == norm(m.S.part.get("features", [])) and norm(m.S.part) == rec_before,
		"M4 the saved record is the part again (unchanged)")

	# M5 reopen: a fresh library lists it from the disk
	m._library_toggle()
	await idle(3)
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.open()
	await idle(3)
	var side2 := lib.find_child("cat_my_parts", true, false) as Button
	if side2 != null:
		await reveal(side2)
		await click_ctl(side2)
	await lib.thumbs.settle()
	await idle(3)
	var ps2 := lib.in_group("My parts")
	var pic2: TextureRect = lib._pics.get("mypart:saved:Crank") as TextureRect
	ok(ps2.size() == 1 and sc.list().size() == 1 and pic2 != null and pic2.texture != null, "M5 reopened: the library lists Crank with its picture; the store has it on disk")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("C:/Temp/claude/myparts"))
	await idle(3)
	root.get_texture().get_image().save_png(SHOT)

	# M6 Expert: the same card click, ONE undo step
	m._page_set("BUILD")
	m.easy.set_on(false, false)
	await idle(4)
	m._library_toggle()
	await idle(3)
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.open()
	await idle(3)
	var side3 := lib.find_child("cat_my_parts", true, false) as Button
	if side3 != null:
		await reveal(side3)
		await click_ctl(side3)
	await idle(2)
	var tile3 := lib.find_child("tile_mypart_saved_Crank", true, false) as Button
	var u2: int = m.undo.size()
	var p2: int = m.S.props.size()
	if tile3 != null:
		await click_ctl(tile3)
	await idle(4)
	ok(tile3 != null and m.S.props.size() == p2 + 1 and m.undo.size() == u2 + 1 and m.cur_page == "STAGE",
		"M6 Expert: the card click puts Crank in the set: props %d -> %d, undo +%d, page %s" % [p2, m.S.props.size(), m.undo.size() - u2, m.cur_page])

	# M7 two new parts on the default name are saved apart ("Part 1", "Part 2"), and the scene's name never names them
	ok(not sc.exists("Fight scene"), "M7a the scene's name box did not name a saved part")
	var names: Array = []
	for i in 2:
		m._page_set("BUILD")
		m.S.part = Part.make("Part")
		m.easy.set_on(true, false)
		pu.open_easy()
		await idle(4)
		await click_ctl(ep.make_btns["draw"])
		await drag_screen(cam.unproject_position(Vector3(1.4, 0.0, 0.0)), cam.unproject_position(Vector3(1.5, 0.1, 0.0)))
		await click_ctl(ep.make_btns["pull"])
		await idle(3)
		await click_ctl(ep.use_scene_btn)
		await idle(60)
		names.append(String(m.S.part.get("name", "")))
	ok(names == ["Part 1", "Part 2"] and sc.exists("Part 1") and sc.exists("Part 2"), "M7b two new parts are saved apart: %s, %d saved" % [str(names), sc.list().size()])

	wipe(DIRT)
	print("myparts: %d fail" % fails)
	quit(1 if fails > 0 else 0)

