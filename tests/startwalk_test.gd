extends SceneTree
## godot --path . -s tests/startwalk_test.gd     (START WALK: a beginner from the start screen to a first saved scene; needs a window)
## Real clicks (root.push_input) at 1280 x 720, from the real start screen. Every press is counted; every dead end is a FAIL line.
## BARS:
##  1 card     one click on the ANIMATION card opens POSE in Easy with the home panel up (1 press)
##  2 build    one click on a home card ("Walk") builds a clip (>= 1 card) within 20 s (1 press)
##  3 save     the first save is one press away on screen: a visible "Save scene" button (bar or strip), not only in More
##  4 file     the save writes the scene file in the user's folder, kind "animation", with the card in it
##  5 home     Home (the bar's button) opens the start screen, and the saved scene is a recent tile tagged Animation
##  6 reopen   one click on that tile opens the scene again with its card
##  7 presses  the whole walk (card to saved scene) takes at most 6 presses
## Only user:// is written (UserPaths.root = user://startwalk_test, absolute).

const ROOT_DIR := "user://startwalk_test"
const SHOT_DIR := "C:/Temp/claude/startwalk"

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


## a real click: press and release at the control's centre, through the root viewport (scrolled into view first)
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
		notes.append("DEAD END: %s: nothing clickable there" % what)
	return r


func _init() -> void:
	EasyMode.start_fresh = true   # a beginner's first start: no settings file = Easy (the test's own settings file is new each run)
	UserPaths.force = true
	UserPaths.root = gp(ROOT_DIR)
	for sub in ["scenes", "moves"]:   # this test's own folder: last run's files out, so the names are the same each run
		for f in DirAccess.get_files_at(gp(ROOT_DIR + "/" + sub)) if DirAccess.dir_exists_absolute(gp(ROOT_DIR + "/" + sub)) else []:
			DirAccess.remove_absolute(gp(ROOT_DIR + "/" + sub + "/" + f))
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

	# 1 card
	var card: Control = ss.find_child("card_animation", true, false)
	var pic: Control = ss._card_art["animation"]
	await press(pic, "ANIMATION card")
	await idle(10)
	var home = m.easy.home if m.easy != null else null
	var panel_up: bool = home != null and home.shown() == "panel"
	ok(m.S.kind == "animation" and m.cur_page == "POSE" and m.easy.on and panel_up,
		"1 card: one click on ANIMATION opens POSE in Easy with the home panel (kind %s page %s easy %s panel %s presses %d)"
		% [m.S.kind, m.cur_page, m.easy.on, panel_up, presses])

	# 2 build
	var c0: Control = home.panel.find_child("eh_card_0", true, false) if home != null and home.panel != null else null
	await press(c0, "Walk card")
	var waited := 0
	while waited < 1200 and m.S.cards.is_empty():
		await process_frame
		waited += 1
	ok(not m.S.cards.is_empty(), "2 build: the Walk card builds a clip (%d cards after %d frames)" % [m.S.cards.size(), waited])
	await idle(20)
	m.get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/walk_built.png") if DirAccess.dir_exists_absolute(SHOT_DIR) else null

	# 3 save: a bar button for the scene
	var save_btn: Control = null
	var bar_save := false
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text) == "Save scene":
			bar_save = true
			save_btn = b
	ok(bar_save, "3 save: a visible Save scene button after the first card (not only in More)")
	if not bar_save:
		notes.append("DEAD END: saving the scene means More > Save the scene: no visible Save scene button")
		# the walk goes on the way a beginner finds it: More, then the item
		presses += 1
		m.easy._more_open()
		await idle(3)
		var idx := -1
		for i in m.easy._more_acts.size():
			if String(m.easy._more_acts[i][0]) == "Save the scene":
				idx = i
		m.easy._more_picked(idx)
		await idle(10)
	else:
		await press(save_btn, "Save scene")
		await idle(10)

	var ms: Control = m.easy._btns["My scenes"]
	await click(ms)   # not a walk press: the check that My scenes lists the new scene
	await idle(15)
	var sp = m.easy.scenes
	var listed := false
	for n in sp.find_children("*", "Label", true, false):
		if (n as Label).is_visible_in_tree() and (n as Label).text == "walk":
			listed = true
	ok(listed and sp.visible, "4b scenes: My scenes lists the saved scene by name (walk)")
	if sp.visible:
		sp.close_panel()
	await idle(4)
	# 4 file
	var f: String = String(m.scene_path)
	var on_disk: bool = f != "" and FileAccess.file_exists(f)
	var kind_ok := false
	var has_card := false
	if on_disk:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if d is Dictionary:
			kind_ok = String((d as Dictionary).get("kind", "")) == "animation"
			has_card = ((d as Dictionary).get("cards", []) as Array).size() >= 1
	ok(on_disk and kind_ok and has_card, "4 file: the scene is saved in the user's folder (%s) with kind animation and a card" % f.get_file())

	# 5 home
	var home_b: Control = null
	for b in m.find_children("home_btn", "Button", true, false):
		if (b as Control).is_visible_in_tree():
			home_b = b
	await press(home_b, "Home")
	await idle(10)
	var tile_path := f
	var tagged := false
	if ss._tiles.has(tile_path):
		tagged = String(ss._tiles[tile_path]["tag"].text) == "Animation"
	ok(ss.visible and ss._tiles.has(tile_path) and tagged, "5 home: Home opens the start screen with the saved scene as a tile tagged Animation")

	# 6 reopen
	m._new_scene()
	await idle(4)
	if ss._tiles.has(tile_path):
		await press(ss._tiles[tile_path]["tile"], "saved tile")
	await idle(20)
	ok(String(m.scene_path) == f and m.S.cards.size() >= 1, "6 reopen: one click on the tile reopens the scene with its card (%d)" % m.S.cards.size())

	# 8 ctrl+s: the shortcut every beginner knows saves the scene they are in (not a pose into moves/)
	var mov_before := DirAccess.get_files_at(gp(ROOT_DIR) + "/moves").size() if DirAccess.dir_exists_absolute(gp(ROOT_DIR) + "/moves") else 0
	await idle(3)
	var ek := InputEventKey.new()
	ek.keycode = KEY_S
	ek.physical_keycode = KEY_S
	ek.key_label = KEY_S
	ek.unicode = 115
	ek.ctrl_pressed = true
	ek.pressed = true
	root.push_input(ek, true)
	await idle(10)
	var mov_after := DirAccess.get_files_at(gp(ROOT_DIR) + "/moves").size() if DirAccess.dir_exists_absolute(gp(ROOT_DIR) + "/moves") else 0
	var said := String(m.ui_scene_name.text) if m.ui_scene_name != null else ""
	ok(mov_after == mov_before, "8 ctrl+s: Ctrl+S in Easy saves the scene, not a pose (poses in moves/: %d -> %d; msg '%s')" % [mov_before, mov_after, said])
	if mov_after != mov_before:
		notes.append("DEAD END: Ctrl+S (the save every beginner knows) saves a POSE into moves/, not the scene")

	# 7 presses
	ok(presses <= 6, "7 presses: the walk took %d presses (at most 6)" % presses)
	for n in notes:
		print("note " + String(n))
	print("startwalk presses=%d dead_ends=%d fails=%d" % [presses, notes.size(), fails])
	print("startwalk %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
