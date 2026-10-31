extends SceneTree
## godot --path . --position 4000,4000 -s tests/p084mypartsapp_test.gd     (ROADMAP 84: My parts: a part file someone shared (its .json, its picture beside it) dropped on the window goes into My parts; the library lists it next to the standard ones; a name already saved is never replaced; a file that is not a part is refused with the next step. Needs a window and the CAD DLL)
## BARS, stated before any code (real clicks / drags at 1280 x 720; the store is user://myparts_test, a parameter of MyParts; the real user://parts is never touched; the shared copy is a plain file copy, the way a friend would send it):
##  S1  MAKE   a box drawn on the grid, pulled up, named "Bolt" in Easy Part, Use in a scene: the store has Bolt (record file and picture file) within 3 s
##  S2  SHARE  the test copies Bolt.json and Bolt.png out of the store to a folder (the file a friend sends), then empties the store (another computer): the copy exists, the store has 0 parts
##  S3  IMPORT a drop of the shared Bolt.json on the window (the real files_dropped path): the store has Bolt again within 3 s, its record equals the part made in S1 (features equal), its picture exists, the status line starts "imported"
##  S4  LIBRARY the My parts column lists Bolt alone, its card has a picture (a texture)
##  S5  CLICK  a click on the Bolt card puts a copy in the set: props +1, kind part:Bolt#, ONE undo step
##  S6  NO REPLACE a second drop of the same file: the store has 2 parts, "Bolt" is unchanged (record equal to S1), the new one is "Bolt 1" with the same features; the library lists 2
##  S7  REFUSE a drop of a .json that is not a part ({"hello": 1}): the store still has 2 parts, the status line says "is not a part file" and names the next step (Use in a scene), undo count unchanged
##  Shot: C:/Temp/claude/p084mypartsapp/shot.png (the library open on My parts, after S4).
var fails := 0
var m: Node
var lib: ObjectLibrary
const SHOT := "C:/Temp/claude/p084mypartsapp/shot.png"
const DIRT := "user://myparts_test"
const DIRP := "user://myparts_test/parts"
const SHARED := "C:/Temp/claude/p084mypartsapp/shared"


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


func count_named(sc, nm: String) -> int:
	var n := 0
	for pt in sc.list():
		if String(pt["name"]) == nm:
			n += 1
	return n


## the drop of files on the window, as the OS sends it (main connects files_dropped to its drop handler)
func drop(paths: Array) -> void:
	m.get_window().files_dropped.emit(PackedStringArray(paths))
	await idle(3)


func wait_disk(p: String) -> void:
	for i in 180:
		if disk(p):
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
	wipe(SHARED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRP))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARED))
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
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	var ep: EasyPart = pu.ep
	if sc == null or not Part.available():
		ok(false, "S0 the store module and the CAD DLL load (store %s, DLL %s)" % [sc != null, Part.available()])
		print("p084mypartsapp: %d fail" % fails)
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	m.S.part["name"] = "Bolt"
	await click_ctl(ep.make_btns["draw"])
	var cam: Camera3D = m.cam
	await drag_screen(cam.unproject_position(Vector3(1.4, 0.0, 0.0)), cam.unproject_position(Vector3(1.5, 0.1, 0.0)))
	await click_ctl(ep.make_btns["pull"])
	await idle(3)
	await click_ctl(ep.make_btns["round"])
	await idle(3)
	var made := norm(m.S.part.get("features", []))

	# S1 make and save: the store has Bolt with its picture
	await click_ctl(ep.use_scene_btn)
	await wait_disk(sc.thumb_of("Bolt"))
	ok(disk(sc.path_of("Bolt")) and disk(sc.thumb_of("Bolt")), "S1 Use in a scene: the store has Bolt (record %s, picture %s)" % [disk(sc.path_of("Bolt")), disk(sc.thumb_of("Bolt"))])
	var rec_made := norm(sc.load_part("Bolt"))

	# S2 share: the file a friend gets (copied out), then the store is empty (another computer)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(sc.path_of("Bolt")), SHARED + "/Bolt.json")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(sc.thumb_of("Bolt")), SHARED + "/Bolt.png")
	wipe(DIRT + "/parts")
	ok(FileAccess.file_exists(SHARED + "/Bolt.json") and FileAccess.file_exists(SHARED + "/Bolt.png") and sc.list().size() == 0,
		"S2 shared: Bolt.json and Bolt.png copied out (%s), the store has %d part(s)" % [FileAccess.file_exists(SHARED + "/Bolt.json"), sc.list().size()])

	# S3 import: a drop of the shared file puts it in My parts
	await drop([SHARED + "/Bolt.json"])
	await wait_disk(sc.path_of("Bolt"))
	await wait_disk(sc.thumb_of("Bolt"))
	var st: String = m.ui_status.text if m.ui_status != null else ""
	ok(sc.list().size() == 1 and norm(sc.load_part("Bolt").get("features", [])) == made and disk(sc.thumb_of("Bolt")) and st.begins_with("imported"),
		"S3 import: the store has Bolt (features %s, picture %s), status \"%s\"" % [norm(sc.load_part("Bolt").get("features", [])) == made, disk(sc.thumb_of("Bolt")), st.left(60)])

	# S4 library: My parts lists it, with its picture
	m._library_toggle()
	await idle(3)
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = DIRT + "/recent.json"
	lib.clear_recent()
	lib.open()
	await idle(3)
	var side := lib.find_child("cat_my_parts", true, false) as Button
	if side != null:
		await reveal(side)
		await click_ctl(side)
	await lib.thumbs.settle()
	await idle(3)
	var ps := lib.in_group("My parts")
	var tile := lib.find_child("tile_mypart_saved_Bolt", true, false) as Button
	var pic: TextureRect = lib._pics.get("mypart:saved:Bolt") as TextureRect
	ok(ps.size() == 1 and String(ps[0]["name"]) == "Bolt" and tile != null and pic != null and pic.texture != null,
		"S4 My parts lists Bolt alone, with its picture (cards %d, picture %s)" % [ps.size(), pic != null and pic.texture != null])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("C:/Temp/claude/p084mypartsapp"))
	await idle(3)
	root.get_texture().get_image().save_png(SHOT)

	# S5 a card click puts a copy in the set: props +1, ONE undo step
	var u0: int = m.undo.size()
	var p0: int = m.S.props.size()
	if tile != null:
		await click_ctl(tile)
	await idle(4)
	var last: Dictionary = m.S.props[-1] if m.S.props.size() > 0 else {}
	ok(m.S.props.size() == p0 + 1 and String(last.get("kind", "")).begins_with("part:Bolt#") and m.undo.size() == u0 + 1,
		"S5 the card click puts Bolt in the set: props %d -> %d, kind %s, undo +%d" % [p0, m.S.props.size(), String(last.get("kind", "")), m.undo.size() - u0])

	# S6 the same file again: nothing is replaced, the copy is "Bolt 1"
	await drop([SHARED + "/Bolt.json"])
	await wait_disk(sc.path_of("Bolt 1"))
	await idle(3)
	ok(sc.list().size() == 2 and norm(sc.load_part("Bolt")) == rec_made and norm(sc.load_part("Bolt 1").get("features", [])) == made,
		"S6 no replace: %d parts, Bolt unchanged %s, Bolt 1 has the same features" % [sc.list().size(), norm(sc.load_part("Bolt")) == rec_made])

	m._library_toggle()
	await idle(3)
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.open()
	await idle(3)
	var side6 := lib.find_child("cat_my_parts", true, false) as Button
	if side6 != null:
		await reveal(side6)
		await click_ctl(side6)
	await lib.thumbs.settle()
	ok(lib.in_group("My parts").size() == 2, "S6 the library lists both (%d cards)" % lib.in_group("My parts").size())

	# S7 a file that is not a part is refused, with the next step
	var junk := SHARED + "/notes.json"
	var jf := FileAccess.open(junk, FileAccess.WRITE)
	jf.store_string("{\"hello\": 1}")
	jf.close()
	var u7: int = m.undo.size()
	await drop([junk])
	st = m.ui_status.text if m.ui_status != null else ""
	ok(sc.list().size() == 2 and st.contains("is not a part file") and st.contains("Use in a scene") and m.undo.size() == u7,
		"S7 refused: %d parts, status \"%s\", undo %d -> %d" % [sc.list().size(), st.left(90), u7, m.undo.size()])

	wipe(DIRT)
	print("p084mypartsapp: %d fail" % fails)
	quit(1 if fails > 0 else 0)
