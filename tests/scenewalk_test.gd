extends SceneTree
## godot --path . -s tests/scenewalk_test.gd     (SCENE WALK: a beginner saves three scenes, renames one, duplicates one, deletes one (to the trash) and restores it, reopens each)
## Real clicks (root.push_input) at 1280 x 720, from the real start screen. Every dead end is printed in plain words with its press.
## BARS:
##  1 save3     three scenes saved from Easy (a card each, New scene between them): three files in the scenes folder
##  2 list      My scenes lists the three tiles
##  3 rename    a tile Rename button: type a new name, OK: the file has the new name, the old name is gone
##  4 duplicate a tile Duplicate button: a copy file appears, the scenes folder has one more file
##  5 delete    the trash button on a tile: asks, then Delete: the file leaves the scenes folder
##  6 restore   a Trash button in My scenes lists the trashed scene: Put back: the file is back in the scenes folder
##  7 reopen    one click on each of the tiles reopens that scene with its card
##  8 presses   the whole walk takes at most 30 presses
## Only user:// is written (UserPaths.root = user://scenewalk_test, absolute).

const ROOT_DIR := "user://scenewalk_test"
const SHOT_DIR := "C:/Temp/claude/scenewalk"

var fails := 0
var m: Node
var ss: StartScreen
var presses := 0
var notes: Array = []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func shot(nm: String) -> void:
	if DirAccess.dir_exists_absolute(SHOT_DIR):
		m.get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/" + nm + ".png")


## a real click: press and release at the control centre, through the root viewport (scrolled into view first)
func click(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)
	return true


func press(c: Control, what: String) -> bool:
	presses += 1
	var r := await click(c)
	if not r:
		dead(what + ": nothing clickable there")
	return r


func dead(words: String) -> void:
	notes.append("DEAD END: " + words)
	print("DEAD END: " + words)


## the visible button with this text (anywhere in the window)
func button_text(t: String) -> Button:
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text) == t:
			return b
	return null


## only this test's own scenes (the shipped scenes in res://scenes are listed too, and are never touched here)
func mine_only(a: Array) -> Array:
	var out := []
	for p in a:
		if String(p).contains("scenewalk_test"):
			out.append(p)
	return out


## the visible button with this text inside one tile (a tile's own Rename / Duplicate)
func in_tile(p: String, t: String) -> Button:
	var tb: Control = m.easy.scenes.tile_button(p)
	if tb == null:
		return null
	for b in tb.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text) == t:
			return b
	return null


func scene_files(dir: String) -> Array:
	var out := []
	var d := gp(ROOT_DIR) + "/" + dir
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				out.append(f)
	return out


## Easy: the bar More button, then the More entry Save the scene (one press)
func more_save() -> void:
	await press(m.easy._btns["More"], "More")
	var idx := -1
	for i in m.easy._more_acts.size():
		if String(m.easy._more_acts[i][0]) == "Save the scene":
			idx = i
	m.easy._more_picked(idx)
	await idle(10)


func _init() -> void:
	EasyMode.start_fresh = true   # a beginner's first start: no settings file = Easy (the settings file is new each run)
	UserPaths.force = true
	UserPaths.root = gp(ROOT_DIR)
	for sub in ["scenes", "moves", "trash"]:   # this folder: last run files out, so the names are the same each run
		var d := gp(ROOT_DIR + "/" + sub)
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d + "/" + f)
	DirAccess.make_dir_recursive_absolute(gp(ROOT_DIR))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	ss = m.start_screen
	ss.dirs_override = [gp(ROOT_DIR) + "/scenes"]
	ss.show_screen(true)   # the start-up screen, as a beginner sees it
	await idle(20)
	shot("00_start")

	# the first card: ANIMATION, then the Walk card; then New scene and another card, three scenes in all
	await press(ss._card_art["animation"], "ANIMATION card")
	await idle(10)
	var home = m.easy.home
	var first_card: Control = home.panel.find_child("eh_card_0", true, false) if home != null and home.panel != null else null
	await press(first_card, "Walk card")
	var waited := 0
	while waited < 1200 and m.S.cards.is_empty():
		await process_frame
		waited += 1
	await idle(10)
	await more_save()
	for n in [1, 2]:
		await press(m.easy._btns["New scene"], "New scene")
		await idle(10)
		var c: Control = m.easy.home.panel.find_child("eh_card_%d" % n, true, false) if m.easy.home != null and m.easy.home.panel != null else null
		await press(c, "home card %d" % n)
		waited = 0
		while waited < 1200 and m.S.cards.is_empty():
			await process_frame
			waited += 1
		await idle(10)
		await more_save()
	shot("01_saved3")
	var made := scene_files("scenes").size()
	ok(made == 3, "1 save3: three saved scenes in the scenes folder (%d: %s)" % [made, str(scene_files("scenes"))])

	# 2 list: My scenes
	await press(m.easy._btns["My scenes"], "My scenes")
	await idle(15)
	var sp = m.easy.scenes
	var tiles: Array = mine_only(sp.tile_paths(false))
	ok(sp.visible and tiles.size() == 3, "2 list: My scenes lists the three tiles (%d)" % tiles.size())
	shot("02_my_scenes")

	# 3 rename: a Rename button on a tile
	var rn: Control = in_tile(String(tiles[0]), "Rename")
	var old_name := String(tiles[0]).get_file() if tiles.size() > 0 else ""
	if rn == null:
		dead("Rename: My scenes has no Rename on a tile (the tile has a star and a trash button only)")
	else:
		await press(rn, "Rename")
		var ed: LineEdit = null
		for e in m.find_children("*", "LineEdit", true, false):
			if (e as LineEdit).is_visible_in_tree():
				ed = e
		if ed != null:
			ed.text = "zz_renamed"
			ed.text_submitted.emit("zz_renamed")
		await idle(10)
	var renamed := FileAccess.file_exists(gp(ROOT_DIR) + "/scenes/zz_renamed.json") and not FileAccess.file_exists(gp(ROOT_DIR) + "/scenes/" + old_name)
	ok(renamed, "3 rename: the scene file has the new name (old %s gone, zz_renamed.json there)" % old_name)
	shot("03_renamed")

	# 4 duplicate
	var before := scene_files("scenes").size()
	var cur := mine_only(sp.tile_paths(false))
	var dup: Control = in_tile(String(cur[1]), "Duplicate") if cur.size() > 1 else null
	if dup == null:
		dead("Duplicate: My scenes has no Duplicate on a tile (a copy of a scene: none)")
	else:
		await press(dup, "Duplicate")
		await idle(10)
	var after := scene_files("scenes").size()
	ok(after == before + 1, "4 duplicate: a copy file appears (%d -> %d)" % [before, after])
	shot("04_duplicated")

	# 5 delete the last tile to the trash
	if not sp.visible:
		await press(m.easy._btns["My scenes"], "My scenes")
		await idle(10)
	var tl: Array = mine_only(sp.tile_paths(false))
	var victim: String = String(tl[tl.size() - 1])
	var vname := victim.get_file()
	await press(sp.tile_trash(victim), "trash on %s" % vname)
	await idle(6)
	var asked: bool = m.ui_confirm != null and m.ui_confirm.visible
	if asked:
		m.ui_confirm.confirmed.emit()   # the confirm dialog OK button (Delete)
		m.ui_confirm.hide()
	await idle(10)
	ok(asked and not FileAccess.file_exists(victim), "5 delete: the trash button asks, Delete moves %s out of the scenes folder" % vname)
	shot("05_deleted")

	# 6 restore: a Trash control in My scenes
	var tr: Control = null
	for b in sp.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text).begins_with("Trash"):
			tr = b
	if tr == null:
		dead("Restore: after Delete, My scenes has no Trash: the message says you can get it back from the Trash, but no button there lists it (the trash is a folder: put it back by hand)")
	else:
		await press(tr, "Trash")
		await idle(10)
	var pb: Control = button_text("Put back")
	if pb != null:
		await press(pb, "Put back")
		await idle(10)
	var back := FileAccess.file_exists(gp(ROOT_DIR) + "/scenes/" + vname)
	ok(back, "6 restore: Put back returns the scene to the scenes folder (%s)" % vname)
	shot("06_restored")

	# 7 reopen each tile (the Trash chip is still on: the walk presses All, as a beginner does)
	var all_chip: Control = null
	for b in sp.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text).begins_with("All"):
			all_chip = b
	if all_chip != null:
		await press(all_chip, "All")
	if not sp.visible:
		await press(m.easy._btns["My scenes"], "My scenes")
		await idle(10)
	var reopen_ok := 0
	var paths: Array = mine_only(sp.tile_paths(false))
	for p in paths:
		if not sp.visible:
			await press(m.easy._btns["My scenes"], "My scenes")
			await idle(10)
		print("before tile %s: panel %s tile %s at %s" % [String(p).get_file(), sp.visible, sp.tile_button(String(p)) != null, str(sp.tile_button(String(p)).get_global_rect()) if sp.tile_button(String(p)) != null else "-"])
		await press(sp.tile_button(String(p)), "tile " + String(p).get_file())
		await idle(10)
		if m.ui_save_ask != null and m.ui_save_ask.visible:   # the open scene (the one deleted) is unsaved: the app asks first
			notes.append("NOTE: opening a tile after the delete asks Save changes to %s?: the test answers Save" % String(m.scene_path).get_file())
			m.ui_save_ask.confirmed.emit()
			m.ui_save_ask.hide()
		var wt := 0
		while wt < 600 and String(m.scene_path) != String(p):   # the open is a load: wait for its path (up to 10 s)
			await process_frame
			wt += 1
		await idle(20)
		print("reopen %s: scene_path %s cards %d ask %s confirm %s panel %s" % [String(p).get_file(), String(m.scene_path), m.S.cards.size(), str(m.ui_save_ask != null and m.ui_save_ask.visible), str(m.ui_confirm != null and m.ui_confirm.visible), sp.visible])
		shot("07_reopen_" + String(p).get_file().get_basename())
		if String(m.scene_path) == String(p) and m.S.cards.size() >= 1:
			reopen_ok += 1
	ok(reopen_ok == paths.size() and paths.size() >= 3, "7 reopen: each tile reopens its scene with its card (%d of %d)" % [reopen_ok, paths.size()])

	ok(presses <= 30, "8 presses: the walk took %d presses (at most 30)" % presses)
	for n in notes:
		print("note " + String(n))
	print("scenewalk presses=%d dead_ends=%d fails=%d" % [presses, notes.size(), fails])
	print("scenewalk %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
