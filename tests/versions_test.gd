## godot --path . -s tests/versions_test.gd     (GATES JJ1, UPGRADES #69; a real window, a real click on the menu)
## SCENE VERSIONS on a scratch scene _wip/zz_ver: 2 cards -> "Save a version now" from the Versions menu (a real click
## opens it; the pick: its popup is its own window, so id_pressed) = v001 with 2 cards; a 3rd card, Save scene (the
## scene's file: 3 cards), the search's "Save a version" = v002. The menu lists v2 (3 cards) then v1 (2 cards). Going
## back to v1: 2 cards, ONE undo step, the scene unsaved, its file byte-for-byte the same; a real Ctrl+Z: 3 cards again.
## Another scene lists "no versions yet" (disabled). Every file and folder it wrote is removed after.
extends SceneTree

var fails := 0
var m: Node
const NM := "_wip/zz_ver"
const FILE := "res://scenes/_wip/zz_ver.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)


## a real click opens the menu; [opened, its items as text]
func open_menu() -> Array:
	await click(m.ui_scene_btn)   # the Scene menu, then its Versions item
	m.ui_scene_btn.get_popup().hide()
	m._scene_menu_pick(2)
	await idle(2)
	var pm: PopupMenu = m.ui_versions.get_popup()
	var opened := pm.visible
	var items := []
	for i in pm.item_count:
		if not pm.is_item_separator(i):
			items.append([pm.get_item_text(i), pm.get_item_id(i), pm.is_item_disabled(i)])
	pm.hide()
	await idle()
	return [opened, items]


func pick(id: int) -> void:
	m.ui_versions.get_popup().id_pressed.emit(id)
	await idle(3)


func cards_in(path: String) -> int:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d.get("cards", []) as Array).size() if d is Dictionary else -1


func pose(z: float) -> void:
	m.B.ang["upperarm_r"] = Vector3(0, 0, z)
	m.B.fk()


func cleanup() -> void:
	for f in ["res://scenes/_versions/_wip/zz_ver/v001.json", "res://scenes/_versions/_wip/zz_ver/v002.json", "res://scenes/_versions/_wip/zz_ver/v003.json", "res://scenes/_versions/_wip/zz_ver_other/v001.json", FILE]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	for dpath in ["res://scenes/_versions/_wip/zz_ver", "res://scenes/_versions/_wip/zz_ver_other", "res://scenes/_versions/_wip", "res://scenes/_versions"]:
		var d := DirAccess.open(dpath)
		if d != null and d.get_files().is_empty() and d.get_directories().is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dpath))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	cleanup()
	m._new_scene()
	m.S.name = NM
	pose(10)
	m._card_add()
	pose(40)
	m._card_add()
	m._rebuild_cards()
	await idle()
	var first := await open_menu()
	var none: bool = first[1].any(func(it): return it[0] == "no versions yet" and it[2])
	await pick(0)
	var v1: String = m.versions_dir() + "/v001.json"
	ok(first[0] and none and FileAccess.file_exists(v1) and cards_in(v1) == 2 and not FileAccess.file_exists(FILE),
		"1 a real click opens Versions (%s), 'no versions yet' shown disabled (%s); 'Save a version now': %s with %d cards; the scene's own file not written (%s)" % [first[0], none, v1, cards_in(v1), FileAccess.file_exists(FILE)])
	pose(70)
	m._card_add()
	m._save_scene_now(NM)
	var bytes := FileAccess.get_file_as_string(FILE)
	for c in m._commands():
		if c["name"] == "Save a version":
			(c["run"] as Callable).call()
	await idle()
	var v2: String = m.versions_dir() + "/v002.json"
	var listed := await open_menu()
	var rows: Array = listed[1].filter(func(it): return it[1] >= 100).map(func(it): return it[0])
	ok(cards_in(v2) == 3 and rows.size() == 2 and String(rows[0]).begins_with("v2") and String(rows[0]).ends_with("3 cards") and String(rows[1]).begins_with("v1") and String(rows[1]).ends_with("2 cards"),
		"2 a 3rd card, Save scene, the search's 'Save a version': v002 with %d cards; the menu, newest first: %s" % [cards_in(v2), rows])
	var u0: int = m.undo.size()
	await pick(101)   # the second row: v1
	ok(m.S.cards.size() == 2 and m.undo.size() == u0 + 1 and m._unsaved() and FileAccess.get_file_as_string(FILE) == bytes,
		"3 back to v1: %d cards, +%d undo step, unsaved %s, the scene's file the same bytes (%s)" % [m.S.cards.size(), m.undo.size() - u0, m._unsaved(), FileAccess.get_file_as_string(FILE) == bytes])
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_Z
		e.physical_keycode = KEY_Z
		e.ctrl_pressed = true
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(3)
	ok(m.S.cards.size() == 3 and not m._unsaved(), "4 a real Ctrl+Z: %d cards, saved again (%s)" % [m.S.cards.size(), not m._unsaved()])
	m._new_scene()
	m.S.name = "_wip/zz_ver_other"
	var other := await open_menu()
	var other_rows: Array = other[1].filter(func(it): return it[1] >= 100)
	var other_none: bool = other[1].any(func(it): return it[0] == "no versions yet" and it[2])
	ok(other_rows.is_empty() and other_none, "5 another scene: none of zz_ver's versions (%d rows), 'no versions yet' %s" % [other_rows.size(), other_none])
	cleanup()
	var left := FileAccess.file_exists(v1) or FileAccess.file_exists(FILE) or DirAccess.open("res://scenes/_versions/_wip/zz_ver") != null
	ok(not left, "6 everything it wrote removed (%s)" % left)
	print("VERSIONS: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
