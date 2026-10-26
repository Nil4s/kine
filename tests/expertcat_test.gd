## godot --path . -s tests/expertcat_test.gd     (EXPERT "Open a scene" = the EASY CATALOG: chips, badges, filters, stars, List view; needs a window)
## Real clicks (root.push_input) on Expert's Open a scene, the chips, the tiles and the stars. The scene menu's Open item runs
## _open_scene_popup (main.gd) shows the list; its first row opens EasyScenes in its expert view. Planted copies live in user://expertcat_test (a _wip
## folder there is the Drafts group); the quality cache is the test's own file. The screenshot is C:/Temp/claude/ec/expertcat.png.
## BARS (stated before the run):
##  a. Expert: Browse scenes (the first row of Open a scene) shows the chips; the category chips' counts sum to the saved scenes on disk (examples not counted).
##  b. a click on the Fight chip shows only Fight tiles, the planted punch copy among them.
##  c. a tile click opens that scene in Expert: the scene path is the tile's file, the panel shuts, Expert stays on (Easy off).
##     (walk_bat is a shipped example: its tile opens a copy, so the click uses the planted punch copy.)
##  d. a star set in Expert is in the shared settings file and shows as ★ in Easy's My scenes (Favourites chip counts it).
##  e. no frame over 100 ms from the Open a scene click until every badge is ready (the Checks run in a worker process).
##  f. List view shuts the catalog and shows the old scene list (its popup is visible).
##  (Open a scene still opens the old list, which the existing suites drive; its first row "Browse scenes" opens this catalog.)
##  g. Hide weird ones hides the broken copy here too.
extends SceneTree

const DIR := "user://expertcat_test"
const BROKEN := "user://expertcat_test/expertcat_broken.json"
const PUNCH := "user://expertcat_test/expertcat_punch.json"
const DRAFT := "user://expertcat_test/_wip/expertcat_draft.json"
const WALK := "res://scenes/walk_bat.json"
const PNG := "C:/Temp/claude/ec/expertcat.png"
const CHIP_CATS := ["Walk & run", "Fight", "Weapons", "Jump & dodge", "Dance & other"]

var fails := 0
var m: Node
var scenes: EasyScenes


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## a real click at the centre of a control (scrolled into view first when it sits in the panel's scroll)
func click(c: Control) -> void:
	var sc := _scroll_of(c)
	if sc != null:
		sc.ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	btn(true, p)
	await process_frame
	btn(false, p)
	await idle(3)


func _scroll_of(c: Control) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


## the ☰ Scene button on the strip, a real click (its menu opens), then "Open scene" (its item id, as the menu sends it)
func open_catalog() -> void:
	var p: Vector2 = m.ui_scene_btn.get_global_rect().get_center()
	btn(true, p)
	await process_frame
	var on_press: bool = m.ui_scene_btn.get_popup().visible
	btn(false, p)
	await idle(3)
	var after: bool = m.ui_scene_btn.get_popup().visible
	ok(on_press or after, "f: a real click on the Scene (☰) button opens its menu (visible on press %s, after release %s)" % [on_press, after])
	m.ui_scene_btn.get_popup().hide()
	m.ui_scene_btn.get_popup().id_pressed.emit(1)   # Open scene
	await idle(4)


## f: the catalog is inside the window at this size, and the old scrolling list is not shown
func check_fit(label: String) -> void:
	var box := scenes.find_children("easy_scenes_box", "PanelContainer", true, false)[0] as Control
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	ok(scenes.visible and vp.encloses(box.get_global_rect()), "f: at %s the catalog panel is inside the window (%s in %s)" % [label, box.get_global_rect(), vp.size])
	ok(not m.ui_scenes.get_popup().visible, "f: at %s the old scrolling list is not shown" % label)


func count_chip(key: String) -> int:
	var t := scenes.chip(key).text
	var a := t.find("(")
	return int(t.substr(a + 1, t.find(")") - a - 1)) if a >= 0 else -1


## the saved scenes on disk (the rule the list reads: a .json with cards or keys), the examples left out
func count_saved() -> int:
	var ex := []
	for e in m.EXAMPLES:
		ex.append(String(e[1]))
	return count_in(["res://scenes", "res://moves", DIR], ex)


func count_in(dirs: Array, ex := []) -> int:
	var n := 0
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".json"):
				continue
			var p: String = d + "/" + f
			var txt := FileAccess.get_file_as_string(p)
			if (txt.contains("\"keys\"") or txt.contains("\"cards\"")) and not ex.has(p):
				n += 1
	return n


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/_wip"))
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/ec")
	SceneCat.cache_path = DIR + "/scene_quality.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SceneCat.cache_path))
	var walk_txt := FileAccess.get_file_as_string(WALK)
	# the broken copy: both knees folded 170 deg and a saved line that says the knee stays under 90
	var bd: Dictionary = JSON.parse_string(walk_txt)
	for c in bd["cards"]:
		for j in ["calf_l", "calf_r"]:
			c["pose"]["joints"][j]["bend"] = 170.0
	bd["asserts"] = ["left knee below 90 deg all clip"]
	_write(BROKEN, JSON.stringify(bd))
	var pu: Dictionary = Templates.read("punch")
	ok(not pu.is_empty(), "precondition: Templates.read gives the punch")
	_write(PUNCH, JSON.stringify(pu))
	_write(DRAFT, walk_txt)

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	scenes = m.easy.scenes
	scenes.extra_dirs = [DIR]
	scenes.draft_dirs = [DIR + "/_wip"]   # only the planted draft (the shipped scenes/_wip holds other runs' work copies)
	var fav_before := _favs()
	ok(not m.easy.on, "precondition: Expert is on (Easy off)")

	# e + a: Open a scene (the scene menu's Open item) in Expert: the catalog opens, badges fill from the worker
	var worst := 0.0
	var frames := 0
	await open_catalog()
	ok(scenes.visible and scenes.expert, "Open scene opens the catalog in Expert")
	var last := Time.get_ticks_usec()
	var started := Time.get_ticks_msec()
	while scenes.pending() > 0 and Time.get_ticks_msec() - started < 120000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	ok(scenes.visible and scenes.expert, "Open a scene opens the catalog in Expert")
	ok(EasyScenes.workers_started >= 1, "the worker process ran (%d started)" % EasyScenes.workers_started)
	print("   badges filled in %d frames, the slowest frame %.0f ms" % [frames, worst])
	ok(worst < 100.0, "e: no frame over 100 ms while the badges fill (slowest %.0f ms, %d frames)" % [worst, frames])
	check_fit("1280 x 720")
	root.get_texture().get_image().save_png(PNG)   # the path: the ☰ Scene button, Open scene, the catalog (1280 x 720)
	print("   screenshot saved to %s" % PNG)
	await click(scenes.find_children("easy_scenes_close", "Button", true, false)[0])
	root.content_scale_size = Vector2i(1024, 600)
	await idle(6)
	await open_catalog()
	check_fit("1024 x 600")
	await click(scenes.find_children("easy_scenes_close", "Button", true, false)[0])
	root.content_scale_size = Vector2i(1280, 720)
	await idle(6)
	await open_catalog()

	for k in ["All", "Walk & run", "Fight", "Weapons", "Jump & dodge", "Dance & other", "Drafts", "Favourites"]:
		ok(scenes.chip(k) != null, "a: chip '%s' is there" % k)
	var saved := count_saved()
	var sum := 0
	for k in CHIP_CATS:
		sum += count_chip(k)
	ok(sum == saved and saved > 0, "a: the category chips sum to %d, the saved scenes (%d)" % [sum, saved])
	ok(count_chip("All") == saved and scenes.tile_paths(false).size() == saved, "a: All = %d = the saved scenes' tiles" % saved)
	ok(scenes.tile_badge(BROKEN) == "Weird", "a: the broken copy is Weird (badge '%s')" % scenes.tile_badge(BROKEN))

	# b: the Fight chip, by a real click
	await click(scenes.chip("Fight"))
	var only_fight := true
	var fight_shown := 0
	for p in scenes.tile_paths(false) + scenes.tile_paths(true):
		if scenes.tile_shown(p):
			if scenes.tile_category(p) != "Fight":
				only_fight = false
			else:
				fight_shown += 1
	ok(only_fight and scenes.tile_shown(PUNCH), "b: under Fight only Fight tiles, the planted punch among them (%d shown)" % fight_shown)
	await click(scenes.chip("All"))

	# g: Hide weird ones
	await click(scenes.hide_box())
	ok(not scenes.tile_shown(BROKEN) and scenes.tile_shown(WALK), "g: Hide weird ones hides the broken copy, walk_bat stays")
	await click(scenes.hide_box())

	# d: a star in Expert, saved to the shared settings file
	await click(scenes.tile_star(WALK))
	ok(scenes.visible and scenes.tile_star(WALK).text == "★", "d: a star click in Expert fills the star and keeps the panel open")
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(Array(cf.get_value("easy_scenes", "favourites", [])).has(WALK), "d: the favourite is in the shared settings file")
	await click(scenes.find_children("easy_scenes_close", "Button", true, false)[0])
	ok(not scenes.visible, "close hides the catalog")
	# d (cont.): Easy's My scenes shows the same star in its Favourites chip
	m.easy.set_on(true)
	await idle(6)
	await click(m.easy.button("My scenes"))
	ok(scenes.tile_star(WALK).text == "★" and count_chip("Favourites") == 1, "d: Easy's My scenes shows the star and Favourites (1)")
	await click(scenes.find_children("easy_scenes_close", "Button", true, false)[0])
	m.easy.set_on(false)
	await idle(6)
	ok(not m.easy.on, "Easy is off again (Expert)")

	# f + c: reopen in Expert; List view shows the old list; then a tile click opens that scene in Expert
	await open_catalog()
	ok(scenes.visible and scenes.expert, "reopened in Expert")
	await click(scenes.find_children("easy_scenes_list", "Button", true, false)[0])
	ok(not scenes.visible and m.ui_scenes.get_popup().visible, "f: List view shuts the catalog and shows the old scene list")
	m.ui_scenes.get_popup().hide()
	await idle(2)
	await open_catalog()
	await click(scenes.chip("All"))
	await click(scenes.tile_button(PUNCH))   # a saved copy (walk_bat is a shipped example: its tile opens a copy, no file path)
	ok(m.scene_path == PUNCH, "c: the tile click opens the punch copy in Expert (scene_path '%s')" % m.scene_path.get_file())
	ok(not m.easy.on and not scenes.visible, "c: Expert stays on and the catalog shuts")

	await click(scenes.find_children("easy_scenes_close", "Button", true, false)[0])

	# clean up: the star this run set is taken off again (the settings file keeps the user's other favourites)
	if not fav_before.has(WALK):
		_set_favs(fav_before)
	print("RESULT %d failures" % fails)
	_cleanup()
	quit(fails)


func _favs() -> Array:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return Array(cf.get_value("easy_scenes", "favourites", []))


func _set_favs(v: Array) -> void:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value("easy_scenes", "favourites", v)
	cf.save(m.settings)


func _write(p: String, txt: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(txt)
	f.close()


func _cleanup() -> void:
	for p in [BROKEN, PUNCH, DRAFT, SceneCat.cache_path, EasyScenes.LIST]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
