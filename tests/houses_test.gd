extends SceneTree
## godot --path . -s tests/houses_test.gd     (MY HOUSES: saved houses, scripts/build/houses.gd + houses_ui.gd; needs a window)
## BARS, stated before any measurement (the folder is user://houses_test/, a parameter of Houses; nothing else is written):
##  H1  SAVE: the Save house button (empty name box) saves "House 1": the file exists under the folder, its picture exists, and reloading it
##      gives a record identical to the one saved (Building.to_file of both). Two more houses saved the same way are "House 2", "House 3".
##  H2  OVERWRITE asks IN THE PANEL: saving a second house under a taken name shows the Replace / Cancel strip (no file touched, no modal);
##      Cancel leaves the file as it was; Replace overwrites it.
##  H3  the library's My houses lists 3 houses, each with its picture (a texture on its card).
##  H4  a click on a house's card puts it in the set: props +1 (kind building:<name>), ONE undo step, the set has collision (solids), and
##      Undo takes it away.
##  H5  Open house (the BUILD button, the card): the house is the scene's building (one undo step); a room added and Save house updates
##      THE SAME file (no question, still 3 houses on the disk, the new room is in the file).
##  H6  Rename: the card's Rename + typed name + Enter: the file and picture move, the old name is gone, the record carries the new name.
##  H7  Delete: the file is not listed any more and sits in _trash/ (nothing erased); Delete twice does not overwrite the first.
##  H8  a corrupt file (not JSON; JSON that is not a house) is skipped with one line, named in Houses.skipped, the rest still list, no crash.
## Screenshots: C:/Temp/claude/houses/library.png and open.png.
const DIR := "user://houses_test"
const SHOT_DIR := "C:/Temp/claude/houses"

var fails := 0
var m: Node
var lib: ObjectLibrary


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func click_ctl(c: Control) -> void:
	var at: Vector2 = c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = at
	hm.global_position = at
	root.push_input(hm)
	await idle(2)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await idle(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	root.push_input(u, true)
	await idle(4)


## a control inside a scroll list, scrolled into view first (the left column is longer than a short window)
func reveal(c: Control) -> void:
	var n: Node = c.get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n != null:
		(n as ScrollContainer).ensure_control_visible(c)
	await idle(3)


func shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])
	print("SHOT %s/%s.png" % [SHOT_DIR, nm])


func wipe(d: String) -> void:
	var a := ProjectSettings.globalize_path(d)
	for f in DirAccess.get_files_at(a):
		DirAccess.remove_absolute(a + "/" + f)
	for sub in DirAccess.get_directories_at(a):
		wipe(d + "/" + sub)
		DirAccess.remove_absolute(a + "/" + sub)


func disk(p: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(p))


func names() -> Array:
	return Houses.list().map(func(h): return String(h["name"]))


func fresh_house(w: float, d: float, nm := "Untitled") -> void:
	m.S.building = Building.make(nm)
	Building.add_room(m.S.building, 0.0, 0.0, w, d)
	m.bld.houses.open_name = ""
	m.bld.houses.name_edit.text = ""
	m.bld.sync()
	await idle(2)


## a ribbon tool as a user reaches it: the button when it is on the bar, else from More (the bar puts its last tools there
## when the row is too long for the window; the BUILD row grew past it, and Open house went into More)
func tool_click(b: Button) -> void:
	await idle(2)   # the bar refits a frame after a change (a tool can be shown for that frame, past the window's edge)
	if b.is_visible_in_tree() and root.get_visible_rect().encloses(b.get_global_rect()):
		await click_ctl(b)
		return
	var i: int = m._more_tools.find(b)
	if i < 0:
		return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	m._more_pick(i)
	await idle(2)


func save_by_click() -> void:
	await tool_click(m.bld.houses.save_btn)
	await idle(12)   # the picture is drawn once, on this click
	for _i in 120:   # the save awaits its picture: done when the status line says so (or the ask is up)
		if String(m.ui_status.text).begins_with("House saved") or m.bld.houses.ask_box.visible:
			break
		await idle(1)


func rec_of(b: Dictionary) -> String:
	return JSON.stringify(Building.to_file(b))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	Houses.dir = DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	wipe(DIR)
	m._new_scene()
	await idle(4)
	m.S.kind = "building"
	m._page_set("BUILD")
	await idle(4)
	var hu: HousesUI = m.bld.houses

	# H1 save three houses
	await fresh_house(4.0, 3.0)
	await save_by_click()
	ok(disk(Houses.path_of("House 1")) and disk(Houses.thumb_of("House 1")), "H1 the house is saved as House 1: file %s, picture %s" % [disk(Houses.path_of("House 1")), disk(Houses.thumb_of("House 1"))])
	var back := Houses.load_house("House 1")
	ok(not back.is_empty() and rec_of(back) == rec_of(m.S.building), "H1 reloading gives an identical record")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(Houses.path_of("House 1")))
	ok(raw is Dictionary and int(raw.get("version", 0)) == Building.VERSION and String(raw.get("name", "")) == "House 1", "H1 the file is the versioned Building record (version %s)" % str(raw.get("version") if raw is Dictionary else "?"))
	await fresh_house(5.0, 4.0)
	await save_by_click()
	await fresh_house(3.0, 3.0)
	m.bld.houses.name_edit.text = ""
	await save_by_click()
	ok(names() == ["House 1", "House 2", "House 3"], "H1 the autosave names are House 1, 2, 3 (%s)" % str(names()))

	# H2 overwrite asks in the panel
	await fresh_house(6.0, 6.0)
	hu.name_edit.text = "House 1"
	var before := FileAccess.get_file_as_string(Houses.path_of("House 1"))
	await tool_click(hu.save_btn)
	await idle(6)
	ok(hu.ask_box.visible and FileAccess.get_file_as_string(Houses.path_of("House 1")) == before, "H2 a taken name asks in the panel and touches nothing")
	await click_ctl(hu.ask_box.find_child("build_house_keep", true, false) as Button)
	ok(not hu.ask_box.visible and FileAccess.get_file_as_string(Houses.path_of("House 1")) == before, "H2 Cancel leaves the file as it was")
	await tool_click(hu.save_btn)
	await idle(2)
	await click_ctl(hu.ask_box.find_child("build_house_replace", true, false) as Button)
	await idle(12)
	ok(FileAccess.get_file_as_string(Houses.path_of("House 1")) != before and rec_of(Houses.load_house("House 1")).contains("6"), "H2 Replace overwrites the file")
	ok(names().size() == 3, "H2 still 3 houses (%s)" % str(names()))

	# H3 the library lists them with pictures
	m._new_scene()
	await idle(4)
	m.S.kind = "building"
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = "user://houses_test_recent.json"
	lib.clear_recent()
	lib.open()
	await idle(3)
	var side := lib.find_child("cat_my_houses", true, false) as Button
	ok(side != null and side.is_visible_in_tree(), "H3 the My houses entry is in the left column")
	if side != null:
		await reveal(side)
		await click_ctl(side)
	await lib.thumbs.settle()
	var hs := lib.in_group("My houses")
	var pics := 0
	for it in hs:
		var t := lib.find_child("tile_" + String(it["id"]).replace(":", "_"), true, false) as Button
		if t != null:
			for tr in t.find_children("*", "TextureRect", true, false):
				if (tr as TextureRect).texture != null:
					pics += 1
	ok(hs.size() == 3 and pics == 3, "H3 My houses lists %d houses, %d with a picture" % [hs.size(), pics])
	await shot("library")

	# H4 a click puts the house in the set
	var tile2 := lib.find_child("tile_house_saved_House 2", true, false) as Button
	var n0: int = m.S.props.size()
	var u0: int = m.undo.size()
	if tile2 != null:
		await click_ctl(tile2)
	await idle(3)
	var kind := String(m.S.props[-1]["kind"]) if not m.S.props.is_empty() else ""
	ok(m.S.props.size() == n0 + 1 and kind == "building:House 2" and m.undo.size() == u0 + 1, "H4 the card puts the house in the set in ONE undo step (props %d -> %d, undo %d -> %d, kind %s)" % [n0, m.S.props.size(), u0, m.undo.size(), kind])
	ok(not (Props.kind_of(kind).get("solids", []) as Array).is_empty() and rec_of(m.S.building) == rec_of(Houses.load_house("House 2")), "H4 the set has collision (%d solids) and the scene's house is the saved record" % (Props.kind_of(kind).get("solids", []) as Array).size())
	m._undo()
	await idle(3)
	ok(m.S.props.size() == n0 and m.S.building.is_empty(), "H4 Undo takes the set away (props %d, building %s)" % [m.S.props.size(), "empty" if m.S.building.is_empty() else "kept"])
	m._library_toggle()
	await idle(2)

	# H5 open, edit, save
	m._page_set("BUILD")
	await idle(3)
	await tool_click(hu.open_btn)
	await idle(3)
	var card := hu.open_panel.find_child("house_card_House 3", true, false) as Button
	ok(hu.open_panel.visible and card != null, "H5 Open house shows the saved houses as cards")
	await shot("open")
	u0 = m.undo.size()
	if card != null:
		await click_ctl(card)
	await idle(3)
	ok(String(m.S.building.get("name", "")) == "House 3" and m.undo.size() == u0 + 1 and hu.name_edit.text == "House 3", "H5 a click opens it in BUILD in ONE undo step (name %s, undo %d -> %d)" % [m.S.building.get("name"), u0, m.undo.size()])
	var rooms0: int = (Houses.load_house("House 3")["rooms"] as Array).size()
	Building.add_room(m.S.building, 5.0, 0.0, 3.0, 3.0)
	m.bld.sync()
	await save_by_click()
	ok(not hu.ask_box.visible and names().size() == 3 and (Houses.load_house("House 3")["rooms"] as Array).size() == rooms0 + 1, "H5 Save house updates the same file without asking (rooms %d -> %d, %d houses)" % [rooms0, (Houses.load_house("House 3")["rooms"] as Array).size(), names().size()])

	# H6 rename
	await tool_click(hu.open_btn)
	await idle(3)
	var rn := hu.open_panel.find_child("house_rename_House 2", true, false) as Button
	if rn != null:
		await click_ctl(rn)
	await idle(3)
	var le := hu.open_panel.find_child("house_rename_edit", true, false) as LineEdit
	if le != null:
		le.text = "Barn"
		le.text_submitted.emit("Barn")
	await idle(3)
	ok(Houses.exists("Barn") and not Houses.exists("House 2") and disk(Houses.thumb_of("Barn")) and not disk(Houses.thumb_of("House 2")) and String(Houses.load_house("Barn").get("name")) == "Barn", "H6 renamed: House 2 -> Barn (file, picture, record name)")
	ok(names() == ["Barn", "House 1", "House 3"], "H6 the list is %s" % str(names()))

	# H7 delete goes to _trash
	var del := hu.open_panel.find_child("house_delete_Barn", true, false) as Button
	if del != null:
		await click_ctl(del)
	await idle(3)
	var trashed := Houses.dir + "/_trash/Barn.json"
	ok(names() == ["House 1", "House 3"] and disk(trashed) and disk(Houses.dir + "/_trash/Barn.png"), "H7 Delete: Barn is off the list and its file is in _trash (%s)" % str(names()))
	Houses.save(Building.from_file({"name": "Barn", "rooms": [{"id": "r1", "x": 0, "z": 0, "w": 3, "d": 3}]}), "Barn")
	Houses.trash("Barn")
	ok(disk(Houses.dir + "/_trash/Barn_1.json") and disk(trashed), "H7 a second Delete of the same name keeps the first in the trash")

	# H8 corrupt files
	var f := FileAccess.open(Houses.dir + "/broken.json", FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	f = FileAccess.open(Houses.dir + "/notahouse.json", FileAccess.WRITE)
	f.store_string("{\"hello\": 1}")
	f.close()
	var listed := names()
	ok(listed == ["House 1", "House 3"] and Houses.skipped.size() == 2 and Houses.skipped.has("broken.json") and Houses.skipped.has("notahouse.json"), "H8 two bad files skipped and named (%s), the rest listed %s" % [str(Houses.skipped), str(listed)])
	hu.refresh()
	lib.open()
	await idle(3)
	ok(hu.grid.get_child_count() == 2 and lib.in_group("My houses").size() == 2, "H8 the cards and the library still show the 2 good houses")

	# H9 names: accented letters keep their file apart, an older "_" file still opens by its own name, a case-only rename works
	wipe(DIR)
	var nb := {"name": "x", "rooms": [{"id": "r1", "x": 0.0, "z": 0.0, "w": 4.0, "d": 3.0}]}
	Houses.save(nb, "Pão")
	ok(Houses.exists("Pão") and not Houses.exists("Pêo") and Houses.file_stem("Pão") != Houses.file_stem("Pêo"), "H9 Pão and Pêo are two houses (files %s / %s)" % [Houses.file_stem("Pão"), Houses.file_stem("Pêo")])
	var lg := nb.duplicate(true)
	lg["name"] = "João"
	f = FileAccess.open(Houses.dir + "/Jo_o.json", FileAccess.WRITE)   # saved under the first rule (non-ASCII -> "_")
	f.store_string(JSON.stringify(lg))
	f.close()
	ok(Houses.exists("João") and not Houses.load_house("João").is_empty() and not Houses.exists("Joáo"), "H9 the older Jo_o.json opens as João, and not as Joáo")
	Houses.save(nb, "dojo")
	ok(Houses.rename("dojo", "Dojo") and names().has("Dojo") and not names().has("dojo"), "H9 a case-only rename: dojo -> Dojo (%s)" % [names()])
	ok(Houses.rename("João", "Casa do João") and Houses.exists("Casa do João") and not disk(Houses.dir + "/Jo_o.json"), "H9 renaming the older João moves its file to the new name")

	wipe(DIR)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://houses_test_recent.json"))
	print("HOUSES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
