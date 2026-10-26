## godot --path . -s tests/scenecat_test.gd     (EASY "My scenes" CATALOG: chips, quality badges, filters, favourites; needs a window)
## Real clicks (root.push_input) on the bar's My scenes, the chips, the toggles and the stars. Planted copies live in user://scenecat_test
## (a _wip folder there is the Drafts group); the quality cache is the test's own file. BARS (stated before the run):
##  a. the chips show, and the category chips' counts sum to the number of saved scenes (My scenes' tiles = res://scenes + res://moves
##     scene files, the examples not counted).
##  b. (REWORDED in round 2: no shipped saved scene is punch or kick, so the bar plants a punch copy and a kick copy made from
##     templates/punch.json and templates/roundhouse.json, saved to the test's own folder) a click on Fight shows only Fight tiles,
##     both copies, and no Walk & run or Weapons tile.
##  c. quality: the planted broken copy's badge is "Weird"; scenes/walk_bat.json's is "Good" or "OK".
##  d. the cache: closing and reopening the panel starts no worker and runs 0 Checks in this process.
##  e. no frame over 100 ms from the My scenes click until every badge is ready (the Checks run in a worker process).
##  f. Hide weird ones hides the broken copy (and shows it again when unticked); walk_bat stays shown.
##  g. a star survives closing and reopening the panel, is saved in the settings file, and a star click does not open the scene.
##  h. Best first lists Good, then OK, then Weird; Newest first puts the saved scenes back in their own order.
##  i. the worker's results (in the cache file) equal the in-process Check's for walk_bat and the broken copy (same FAIL and WARN).
##  j. DELETE by real clicks: a planted user:// copy's trash button, then Delete in the dialog: the file is gone from its folder
##     and the list, it is in the trash folder, and the chips' counts (All, Fight) drop by 1. EASYDELETE_PNG (env) saves the tile row.
##  k. Keep (the same dialog's Keep button) leaves the planted kick copy on disk, in the list, and the counts unchanged.
##  l. no example tile has a trash button.
extends SceneTree

const DIR := "user://scenecat_test"
const BROKEN := "user://scenecat_test/scenecat_broken.json"
const PUNCH := "user://scenecat_test/scenecat_punch.json"
const KICK := "user://scenecat_test/scenecat_kick.json"
const DRAFT := "user://scenecat_test/_wip/scenecat_draft.json"
const WALK := "res://scenes/walk_bat.json"
const CHIP_CATS := ["Walk & run", "Fight", "Weapons", "Jump & dodge", "Dance & other"]

var fails := 0
var m: Node
var scenes: EasyScenes
var TRASHED: Array = []   # the trash files this run moved (cleanup removes them: the app's trash folder, our copies only)


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


## a real click on a dialog's button: the dialog is an embedded window, so its button's rect is in the dialog's own space
func click_in(c: Control, w: Window) -> void:
	var p := c.get_global_rect().get_center() + (Vector2(w.position) if w.is_embedded() else Vector2.ZERO)
	btn(true, p)
	await process_frame
	btn(false, p)
	await idle(3)


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
	SceneCat.cache_path = DIR + "/scene_quality.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SceneCat.cache_path))
	var walk_txt := FileAccess.get_file_as_string(WALK)
	# the broken copy: both knees folded 170 deg (far past a knee's limit) and a saved line that says the knee stays under 90
	var bd: Dictionary = JSON.parse_string(walk_txt)
	for c in bd["cards"]:
		for j in ["calf_l", "calf_r"]:
			c["pose"]["joints"][j]["bend"] = 170.0
	bd["asserts"] = ["left knee below 90 deg all clip"]
	_write(BROKEN, JSON.stringify(bd))
	# the punch and kick copies: the shipped templates (Templates.read), saved as scenes of the test's own
	var pu: Dictionary = Templates.read("punch")
	var ku: Dictionary = Templates.read("roundhouse")
	ok(not pu.is_empty() and not ku.is_empty(), "precondition: Templates.read gives the punch and the kick")
	_write(PUNCH, JSON.stringify(pu))
	_write(KICK, JSON.stringify(ku))
	_write(DRAFT, walk_txt)

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(4)
	m.easy.set_on(true)
	await idle(8)
	scenes = m.easy.scenes
	scenes.extra_dirs = [DIR]
	scenes.draft_dirs = [DIR + "/_wip"]   # only the planted draft: the shipped scenes/_wip is other runs' work copies (hundreds)
	var my: Button = m.easy.button("My scenes")
	ok(my != null, "the bar has My scenes")
	# e: the frames from the click to the last badge
	var worst := 0.0
	var frames := 0
	var pt: Vector2 = my.get_global_rect().get_center()
	var started := Time.get_ticks_msec()
	btn(true, pt)
	await process_frame
	btn(false, pt)
	var last := Time.get_ticks_usec()
	while scenes.pending() > 0 and Time.get_ticks_msec() - started < 120000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	ok(EasyScenes.workers_started >= 1, "the worker process ran (%d started)" % EasyScenes.workers_started)
	ok(scenes.visible, "My scenes opens the panel")
	print("   badges filled in %d frames, the slowest frame %.0f ms" % [frames, worst])

	# a: the chips and their counts
	for k in ["All", "Walk & run", "Fight", "Weapons", "Jump & dodge", "Dance & other", "Drafts", "Favourites"]:
		ok(scenes.chip(k) != null, "chip '%s' is there" % k)
	var saved := count_saved()
	var sum := 0
	for k in CHIP_CATS:
		sum += count_chip(k)
	ok(sum == saved and saved > 0, "a: the category chips sum to %d, the saved scenes (%d)" % [sum, saved])
	ok(count_chip("All") == saved and scenes.tile_paths(false).size() == saved, "a: All = %d = the saved scenes' tiles" % saved)
	var drafts := count_in([DIR + "/_wip"])
	ok(drafts >= 1 and count_chip("Drafts") == drafts, "a: Drafts counts the drafts on disk (%d, the planted one among them)" % drafts)

	# c: the badges
	ok(scenes.tile_badge(BROKEN) == "Weird", "c: the broken copy is Weird (badge '%s')" % scenes.tile_badge(BROKEN))
	var wb := scenes.tile_badge(WALK)
	ok(wb == "Good" or wb == "OK", "c: walk_bat.json is Good or OK (badge '%s')" % wb)

	# b: the Fight chip (REWORDED in round 2: the shipped scenes have no punch or kick, so the bar plants one of each from the templates)
	await click(scenes.chip("Fight"))
	var only_fight := true
	var fight_shown := 0
	for p in scenes.tile_paths(false) + scenes.tile_paths(true):
		if scenes.tile_shown(p):
			if scenes.tile_category(p) != "Fight":
				only_fight = false
			else:
				fight_shown += 1
	ok(only_fight and fight_shown >= 2, "b: under Fight only Fight tiles are shown (%d)" % fight_shown)
	ok(scenes.tile_shown(PUNCH), "b: the planted punch copy (from templates/punch.json) is under Fight")
	ok(scenes.tile_shown(KICK), "b: the planted kick copy (from templates/roundhouse.json) is under Fight")
	var walk_or_weapon := 0
	for p in scenes.tile_paths(false) + scenes.tile_paths(true):
		if scenes.tile_shown(p) and (scenes.tile_category(p) == "Walk & run" or scenes.tile_category(p) == "Weapons"):
			walk_or_weapon += 1
	ok(walk_or_weapon == 0, "b: no Walk & run or Weapons tile is shown under Fight (%d)" % walk_or_weapon)
	await click(scenes.chip("All"))

	# f: hide weird
	await click(scenes.hide_box())
	ok(scenes.hide_box().button_pressed, "f: Hide weird ones is ticked")
	ok(not scenes.tile_shown(BROKEN), "f: the broken copy is hidden")
	ok(scenes.tile_shown(WALK), "f: walk_bat stays shown")
	await click(scenes.hide_box())
	ok(scenes.tile_shown(BROKEN), "f: unticked, the broken copy is shown again")

	# h: best first
	var newest_before := scenes.tile_paths(false)
	scenes.sort_box().item_selected.emit(0)
	await idle(3)
	var mine := scenes.tile_paths(false)
	var rank_of := func(p: String) -> int:
		return {"Good": 0, "OK": 1, "Weird": 2}.get(scenes.tile_badge(p), 3)
	var monotone := true
	for i in range(1, mine.size()):
		if rank_of.call(mine[i]) < rank_of.call(mine[i - 1]):
			monotone = false
	ok(monotone and mine.size() > 1, "h: Best first lists Good, then OK, then Weird (the broken copy at %d of %d)" % [mine.find(BROKEN) + 1, mine.size()])
	scenes.sort_box().item_selected.emit(1)
	await idle(3)
	ok(scenes.tile_paths(false) == newest_before, "h: Newest first puts the saved scenes back in their own order")

	# g: a star, then close and reopen
	var star := scenes.tile_star(WALK)
	await click(star)
	ok(scenes.visible, "g: a star click does not open the scene (the panel stays)")
	ok(star.text == "★", "g: the star is filled")
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(Array(cf.get_value("easy_scenes", "favourites", [])).has(WALK), "g: the favourite is in the settings file")
	await click(m.easy.scenes.find_children("easy_scenes_close", "Button", true, false)[0])
	ok(not scenes.visible, "close hides the panel")

	# d: reopen: no Check runs
	SceneCat.checks_run = 0
	var started_workers := EasyScenes.workers_started
	await click(my)
	await idle(4)
	ok(SceneCat.checks_run == 0 and EasyScenes.workers_started == started_workers, "d: reopening runs 0 Checks and starts no worker (in-process %d, workers %d)" % [SceneCat.checks_run, EasyScenes.workers_started - started_workers])
	ok(scenes.pending() == 0, "d: every badge is ready at once on reopen")
	ok(scenes.tile_badge(BROKEN) == "Weird", "d: the broken copy is still Weird after reopen")
	ok(scenes.tile_star(WALK).text == "★", "g: walk_bat's star survived the close and reopen")

	ok(worst < 100.0, "e: no frame over 100 ms from the open until every badge is ready (slowest %.0f ms, %d frames)" % [worst, frames])
	# i: the worker's results (in the cache file) equal the in-process Check's, for the shipped walk and the broken copy
	var cached := SceneCat.load_cache()
	for p in [WALK, BROKEN]:
		var g := SceneCat.grade(p)
		var e: Dictionary = cached.get(p, {})
		var same: bool = int(e.get("fails", -1)) == g[0] and int(e.get("warns", -1)) == g[1]
		ok(same, "i: the worker's result for %s equals the in-process Check (worker %s/%s, in-process %d FAIL %d WARN, badge %s)" % [p.get_file(), str(e.get("fails", "?")), str(e.get("warns", "?")), g[0], g[1], SceneCat.grade_of(g[0], g[1])])
	# j: DELETE (the trash button, then Delete in the dialog, both real clicks): the planted punch copy leaves the list, its file
	# is in the trash folder, and the chips' counts drop by 1
	await click(scenes.chip("All"))
	var all_before := count_chip("All")
	var fight_before := count_chip("Fight")
	ok(scenes.tile_trash(PUNCH) != null, "j: the planted punch copy has a trash button")
	var row_png := OS.get_environment("EASYDELETE_PNG")
	if row_png != "":   # the tile row with the trash buttons, before anything is deleted
		await idle(2)
		var grid := scenes.find_child("easy_scenes_mine", true, false) as Control
		var gr := grid.get_global_rect()
		var shot := root.get_texture().get_image()
		var rw := mini(int(gr.size.x), shot.get_width() - int(gr.position.x))
		var rh := mini(int(gr.size.y), shot.get_height() - int(gr.position.y))
		shot.get_region(Rect2i(Vector2i(gr.position), Vector2i(rw, rh))).save_png(row_png)
		print("   tile row screenshot saved to %s" % row_png)
	var trash_dir := UserPaths.w("res://trash")
	var trash_before := DirAccess.get_files_at(trash_dir)
	await click(scenes.tile_trash(PUNCH))
	var dlg: ConfirmationDialog = m.ui_confirm
	ok(dlg != null and dlg.visible and dlg.dialog_text.contains("You can get it back from the Trash"), "j: the trash button asks, in plain words, before anything moves")
	await click_in(dlg.get_ok_button(), dlg)
	await idle(4)
	ok(not FileAccess.file_exists(PUNCH), "j: the planted copy is gone from its folder")
	ok(not scenes.tile_paths(false).has(PUNCH) and scenes.tile_button(PUNCH) == null, "j: the tile is gone from the list")
	ok(count_chip("All") == all_before - 1 and count_chip("Fight") == fight_before - 1, "j: the chip counts drop by 1 (All %d -> %d, Fight %d -> %d)" % [all_before, count_chip("All"), fight_before, count_chip("Fight")])
	var trashed := []
	for f in DirAccess.get_files_at(trash_dir):
		if not trash_before.has(f) and f.begins_with("scenecat_punch_"):
			trashed.append(f)
	for f in trashed:
		TRASHED.append(trash_dir.path_join(f))
	ok(trashed.size() == 1, "j: the copy is in the trash folder (%s)" % str(trashed))
	ok(scenes.visible, "j: the panel stays open after the delete")

	# k: Keep leaves the file (the kick copy, its trash button then Keep)
	var all_k := count_chip("All")
	await click(scenes.tile_trash(KICK))
	var dlg_k: ConfirmationDialog = m.ui_confirm
	ok(dlg_k.visible and dlg_k.get_cancel_button().text == "Keep", "k: the dialog offers Keep")
	await click_in(dlg_k.get_cancel_button(), dlg_k)
	await idle(3)
	ok(FileAccess.file_exists(KICK) and scenes.tile_paths(false).has(KICK), "k: Keep leaves the kick copy on disk and in the list")
	ok(count_chip("All") == all_k, "k: the counts do not move on Keep")

	# l: the examples have no trash button
	var ex_tiles := scenes.tile_paths(true)
	var ex_trash := 0
	for p in ex_tiles:
		if scenes.tile_trash(p) != null or (scenes.tile_button(p) != null and scenes.tile_button(p).find_child("trash", true, false) != null):
			ex_trash += 1
	ok(ex_tiles.size() > 0 and ex_trash == 0, "l: none of the %d examples has a trash button" % ex_tiles.size())

	var png := OS.get_environment("SCENECAT_PNG")
	if png != "":   # the picture of the panel, at 1280x720: scenes_cat's own look (a test run with SCENECAT_PNG set)
		await click(my)
		await idle(6)
		root.get_texture().get_image().save_png(png)
		print("   screenshot saved to %s" % png)
	print("RESULT %d failures" % fails)
	_cleanup()
	quit(fails)


func _write(p: String, txt: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(txt)
	f.close()


func _cleanup() -> void:
	for p in [BROKEN, PUNCH, KICK, DRAFT, SceneCat.cache_path, EasyScenes.LIST] + TRASHED:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
