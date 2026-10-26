## godot --path . -s tests/startbugs_test.gd     (THE START SCREEN, Nick's hand-test bugs of 2026-10-26; needs a window)
## Bars, stated before measuring (real mouse clicks through root.push_input; only user:// is written):
##   A modeling   a modeling project (the MODELING card, a modeling tile, Resume, Open file...) lands on MODEL with the body open, in Expert,
##                never on POSE / animation chrome, from POSE, Easy, BUILD and STAGE
##   B home       a "Home" button (icon + word) is in the top bar in Expert and in Easy, on every page; one click opens the start screen and
##                changes nothing else; it does not ask about unsaved work (only a new project does)
##   C direct     ONE click on Easy or Expert of a card starts that kind of project in that mode (page, kind, Easy on / off); a card click still works
##   D unsaved    Easy / Expert over unsaved work asks Save / Don't save / Cancel; each does the right thing
##   E sizes      at 1024 x 600 and 1600 x 900 the Home button is inside the window and clear of its neighbours
##   F fast       a double click on a card / a fast second click starts one project, with no error
extends SceneTree

const DIRT := "user://startbugs_test"
const SRC := "res://scenes/combo3.json"
const SHOT_DIR := "C:/Temp/claude/ssbugs"

var fails := 0
var m: Node
var ss: StartScreen


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func click(c: Control, twice := false) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	for rep in (2 if twice else 1):
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = p
			e.global_position = p
			if down:
				e.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(e, true)
			if not twice:
				await process_frame
	await idle(4)
	return true


func write_scene(path: String, kind: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC))
	d["scene"] = path.get_file().get_basename()
	d["kind"] = kind
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func boot() -> void:
	if m != null:
		m.queue_free()
		await idle(6)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ss = m.start_screen
	ss.dirs_override = [DIRT]
	m.save_hook = func(): m._clean = m._doc_key()   # Save without touching res://scenes


func home_btn() -> Button:
	var l: Array = []
	for b in m.find_children("home_btn", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			l.append(b)
	return l[0] if l.size() == 1 else null


func where() -> String:
	return "page %s, kind %s, Easy %s, screen %s" % [m.cur_page, m.S.kind, m.easy.on, ss.visible]


## the app shows a modeling project: MODEL page, the body open, Expert
func is_model_now() -> bool:
	return m.cur_page == "MODEL" and BaseBody.is_open(m) and not m.easy.on and m.S.kind == "modeling" and not ss.visible and not m.ui_bp.visible and not (m.ui_next.get_parent() as Control).visible


func mark_unsaved() -> void:
	if m.S.building.is_empty():
		m.S.building = Building.make()
	Building.add_room(m.S.building, 0.0, 0.0, 4.0, 3.0)


func esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e, true)
	await idle(3)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(gp(DIRT))
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var mod := DIRT + "/sbt_model.json"
	var bld := DIRT + "/sbt_house.json"
	var ani := DIRT + "/sbt_move.json"
	write_scene(mod, "modeling")
	write_scene(bld, "building")
	write_scene(ani, "animation")
	await boot()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)

	# A: a modeling project lands on MODEL, from every starting place
	for from in ["POSE", "STAGE", "BUILD", "EASY"]:
		for how in ["card", "start", "tile", "resume", "file"]:
			m.easy.set_on(from == "EASY")
			await idle(2)
			m._new_scene()
			if from == "BUILD":
				m.S.kind = "building"
				m._page_set("BUILD")
			elif from != "EASY":
				m._page_set(from)
			await idle(3)
			ss.show_screen()
			await idle(3)
			if how == "card":
				await click(ss._cards["modeling"])
			elif how == "start":
				await click(ss.find_child("start_modeling", true, false))
			elif how == "tile":
				ss._pick_chip("modeling")
				await idle(2)
				await click(ss._tiles[mod]["tile"])
			elif how == "resume":
				ss._resume_path = mod
				await click(ss._resume_btn)
			else:
				ss.file_dialog_inline = true
				await click(ss.find_child("open_file_btn", true, false))
				var dlg: FileDialog = ss.last_dialog
				dlg.file_selected.emit(gp(mod))
				await idle(4)
				ss.file_dialog_inline = false
			ok(is_model_now(), "A %s -> %s: a modeling project is on MODEL with the body open, in Expert (%s)" % [from, how, where()])
			if from == "POSE" and how == "tile":
				get_root().get_texture().get_image().save_png(SHOT_DIR + "/modeling_after_tile.png")
			if from == "POSE" and how == "card":
				get_root().get_texture().get_image().save_png(SHOT_DIR + "/modeling_after_card.png")
	m.easy.set_on(false)
	m._new_scene()
	await idle(3)

	# an animation tile / a building tile after a modeling project
	m._page_set("POSE")
	ss.show_screen()
	await click(ss._cards["modeling"])
	ss.show_screen()
	await idle(3)
	ss._pick_chip("animation")
	await idle(2)
	await click(ss._tiles[ani]["tile"])
	ok(m.cur_page == "POSE" and m.S.kind == "animation" and not ss.visible and not BaseBody.is_open(m), "A an animation tile after a modeling project: POSE, body closed (%s)" % where())
	ss.show_screen()
	await idle(3)
	ss._pick_chip("building")
	await idle(2)
	await click(ss._tiles[bld]["tile"])
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and not ss.visible, "A a building tile: BUILD (%s)" % where())
	m._new_scene()
	m._page_set("POSE")

	# C: Easy / Expert start at once
	for kind in ["animation", "building"]:
		for easy in [true, false]:
			m._new_scene()
			m.easy.set_on(not easy)
			await idle(3)
			ss.show_screen()
			await idle(3)
			var b: Button = ss.find_child(("easy_" if easy else "expert_") + kind, true, false)
			ok(b != null and b.is_visible_in_tree(), "C %s %s: the button is there" % [kind, "Easy" if easy else "Expert"])
			await click(b)
			var page: String = "POSE" if kind == "animation" else "BUILD"
			ok(not ss.visible and m.S.kind == kind and m.easy.on == easy and m.cur_page == page, "C one click on %s %s starts it at once (page %s, Easy %s, screen %s)" % [kind.to_upper(), "Easy" if easy else "Expert", m.cur_page, m.easy.on, ss.visible])
	# Easy again when Easy is already the mode shown: still starts
	m._new_scene()
	m.easy.set_on(true)
	ss.show_screen()
	await idle(3)
	await click(ss.find_child("easy_animation", true, false))
	ss.show_screen()
	await idle(3)
	await click(ss.find_child("easy_animation", true, false))
	ok(not ss.visible and m.easy.on and m.cur_page == "POSE", "C Easy when Easy was already the mode shown still starts (%s)" % where())
	ss.show_screen()
	await idle(3)
	await click(ss._cards["animation"])
	ok(not ss.visible and m.S.kind == "animation", "C a plain card click still starts the project (%s)" % where())

	# B: Home on every page, Expert and Easy
	for easy in [false, true]:
		m.easy.set_on(easy)
		await idle(3)
		var pages: Array = ["POSE", "STAGE", "MODEL", "BUILD"] if not easy else ["POSE", "BUILD"]
		for pg in pages:
			m._new_scene()
			if pg == "BUILD":
				m.S.kind = "building"
			elif pg == "MODEL":
				m.S.kind = "modeling"
			m._page_set(pg)
			await idle(4)
			var h := home_btn()
			ok(h != null and h.text == "Home" and h.icon != null, "B Home button (icon + word) is in the %s bar on %s" % ["Easy" if easy else "Expert", pg])
			if h == null:
				continue
			var kind_was: String = m.S.kind
			await click(h)
			ok(ss.visible and m.S.kind == kind_was and m.cur_page == pg, "B Home on %s opens the start screen and changes nothing (%s)" % [pg, where()])
			await esc()
			ok(not ss.visible and m.S.kind == kind_was, "B Esc after Home goes back to the work (%s)" % where())
	# the shots: Home in Expert and in Easy
	m.easy.set_on(false)
	m._new_scene()
	m._page_set("POSE")
	await idle(4)
	get_root().get_texture().get_image().save_png(SHOT_DIR + "/home_expert.png")
	m.easy.set_on(true)
	await idle(4)
	get_root().get_texture().get_image().save_png(SHOT_DIR + "/home_easy.png")
	m.easy.set_on(false)
	# Home does not ask about unsaved work
	m._new_scene()
	m.S.kind = "building"
	m._page_set("BUILD")
	mark_unsaved()
	await idle(3)
	await click(home_btn())
	ok(ss.visible and (m.ui_save_ask == null or not m.ui_save_ask.visible), "B Home over unsaved work opens the screen without a question")
	ss._close()

	# D: unsaved work: Easy / Expert ask first
	for how in ["cancel", "discard", "save"]:
		m.easy.set_on(false)
		m._new_scene()
		m.S.kind = "building"
		m._page_set("BUILD")
		mark_unsaved()
		await idle(3)
		ss.show_screen()
		await idle(3)
		await click(ss.find_child("easy_animation", true, false))
		ok(m.ui_save_ask.visible and m.S.kind == "building", "D Easy over an unsaved house asks first (%s)" % where())
		m._save_ask_choose(how)
		await idle(4)
		if how == "cancel":
			ok(m.S.kind == "building" and not m.S.building.is_empty() and (m.ui_save_ask == null or not m.ui_save_ask.visible), "D Cancel keeps the house (%s)" % where())
		else:
			ok(m.S.kind == "animation" and m.easy.on and m.cur_page == "POSE" and m.S.building.is_empty(), "D %s: the Easy animation project starts (%s)" % [how, where()])
	m.easy.set_on(true)
	m._new_scene()
	m.S.kind = "building"
	mark_unsaved()
	ss.show_screen()
	await idle(3)
	await click(ss.find_child("expert_building", true, false))
	ok(m.ui_save_ask.visible, "D Expert over unsaved work asks first too")
	m._save_ask_choose("discard")
	await idle(4)
	ok(m.S.kind == "building" and not m.easy.on and m.cur_page == "BUILD", "D Don't save: the Expert building project starts (%s)" % where())

	# E: sizes
	for sz in [Vector2i(1024, 600), Vector2i(1600, 900)]:
		for easy in [false, true]:
			m.easy.set_on(easy)
			root.content_scale_size = sz
			await idle(6)
			var h := home_btn()
			var win := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
			ok(h != null and win.encloses(h.get_global_rect()), "E %s %s: the Home button is inside the window (%s)" % [sz, "Easy" if easy else "Expert", h.get_global_rect() if h != null else null])
			if h != null:
				var over := []
				for sib in h.get_parent().get_children():
					if sib != h and sib is Control and (sib as Control).visible and (sib as Control).get_global_rect().intersects(h.get_global_rect().grow(-1)):
						over.append(sib.name)
				ok(over.is_empty(), "E %s %s: Home overlaps no neighbour %s" % [sz, "Easy" if easy else "Expert", over])
			ss.show_screen()
			await idle(4)
			ss._pick_chip("all")
			if easy:
				get_root().get_texture().get_image().save_png(SHOT_DIR + "/start_%d.png" % sz.x)
			ss._close()
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	m.easy.set_on(false)
	await idle(3)
	ss.show_screen()
	await idle(4)
	get_root().get_texture().get_image().save_png(SHOT_DIR + "/start_screen.png")
	ss._close()

	# G: a confused user clicks every control of the screen
	m.easy.set_on(false)
	m._new_scene()
	m._page_set("POSE")
	ss.show_screen()
	await idle(3)
	await click(ss.find_child("help_btn", true, false))
	var hp: Control = m.ui_help
	ok(hp != null and hp.is_visible_in_tree() and hp.get_index() > ss.get_index() or (hp != null and hp.get_parent() != ss.get_parent() and hp.is_visible_in_tree()), "G Help on the start screen shows its help in front of the screen (help visible %s, screen visible %s)" % [hp.visible if hp != null else null, ss.visible])
	if hp != null:
		hp.visible = false
	await click(ss.find_child("settings_btn", true, false))
	ok(ss._settings.visible and ss.visible, "G Settings opens its box on the screen")
	await click(ss.find_child("settings_btn", true, false))
	ok(not ss._settings.visible, "G Settings again closes the box")
	await click(ss.find_child("settings_btn", true, false))
	await click(ss.find_child("show_start", true, false))
	await click(ss.find_child("show_start", true, false))
	await esc()
	ok(ss.visible and not ss._settings.visible, "G Esc closes the Settings box first, the screen stays")
	await esc()
	ok(not ss.visible, "G a second Esc closes the screen")
	ss.show_screen()
	await idle(3)
	for key in ["modeling", "building", "fav", "animation", "all"]:
		await click(ss._chip_btns[key])
		ok(ss._chip == key and ss._chip_btns[key].button_pressed, "G chip %s is the one pressed" % key)
	await click(ss._chip_btns["all"])
	ok(ss._chip == "all" and ss._chip_btns["all"].button_pressed, "G pressing the chip that is already on keeps it on")
	ss._search.text = "zzz"
	ss._search.text_changed.emit("zzz")
	await idle(2)
	var vis := 0
	for p in ss._tiles:
		if (ss._tiles[p]["tile"] as Control).visible:
			vis += 1
	ok(vis == 0, "G a search with no match shows no tile (%d)" % vis)
	ss._search.text = ""
	ss._search.text_changed.emit("")
	var star: Button = ss._tiles[mod]["star"]
	await click(star)
	ok(star.text == "★" and ss.visible, "G the star favourites a tile and does not open it")
	await click(star)
	ok(star.text == "☆" and ss.visible, "G the star again un-favourites it")
	ss.file_dialog_inline = true
	await click(ss.find_child("open_file_btn", true, false))
	var dl: FileDialog = ss.last_dialog
	dl.canceled.emit()
	await idle(3)
	ss.file_dialog_inline = false
	ok(ss.visible, "G Open file... then Cancel leaves the start screen open")
	await click(ss.find_child("examples_btn", true, false))
	ok(not ss.visible and m.easy.scenes != null and m.easy.scenes.visible, "G Examples closes the screen and opens the catalog (screen %s)" % ss.visible)
	m.easy.scenes.close_panel()
	# resize with the screen open
	ss.show_screen()
	for sz in [Vector2i(1024, 600), Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.content_scale_size = sz
		await idle(5)
		ok(Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).encloses(ss.get_global_rect()), "G the screen fills the window at %s" % sz)
	ss._close()
	# unsaved work + a tile: Cancel / Don't save / Save
	for how in ["cancel", "discard", "save"]:
		m._new_scene()
		m.S.kind = "building"
		m._page_set("BUILD")
		mark_unsaved()
		ss.show_screen()
		await idle(3)
		ss._pick_chip("modeling")
		await idle(2)
		await click(ss._tiles[mod]["tile"])
		ok(m.ui_save_ask != null and m.ui_save_ask.visible, "G a modeling tile over an unsaved house asks first (%s)" % how)
		m._save_ask_choose(how)
		await idle(4)
		if how == "cancel":
			ok(m.S.kind == "building" and not ss.visible and not m.ui_save_ask.visible, "G Cancel: the house stays (%s)" % where())
		else:
			ok(is_model_now(), "G %s: the modeling project opens on MODEL (%s)" % [how, where()])

	# F: fast double clicks
	m._new_scene()
	m._page_set("POSE")
	ss.show_screen()
	await idle(3)
	await click(ss._cards["modeling"], true)
	ok(is_model_now(), "F a double click on the MODELING card: one modeling project, on MODEL (%s)" % where())
	m._new_scene()
	m._page_set("POSE")
	ss.show_screen()
	await idle(3)
	await click(ss.find_child("expert_animation", true, false), true)
	ok(not ss.visible and m.S.kind == "animation", "F a double click on Expert ANIMATION: started once, screen closed (%s)" % where())

	print("RESULT %d FAIL" % fails if fails > 0 else "RESULT 0 FAIL")
	quit(1 if fails > 0 else 0)
