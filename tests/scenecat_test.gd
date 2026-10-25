## godot --path . -s tests/scenecat_test.gd     (EASY "My scenes" CATALOG: chips, quality badges, filters, favourites; needs a window)
## Real clicks (root.push_input) on the bar's My scenes, the chips, the toggles and the stars. Planted copies live in user://scenecat_test
## (a _wip folder there is the Drafts group); the quality cache is the test's own file. BARS (stated before the run):
##  a. the chips show, and the category chips' counts sum to the number of saved scenes (My scenes' tiles = res://scenes + res://moves
##     scene files, the examples not counted).
##  b. a click on Fight shows only tiles whose SceneCat.category is Fight, and every such tile is shown; the planted kick copy is one
##     of them; the SHIPPED punch/kick saved scenes are there too (the bar as written: at least one shipped Fight scene).
##  c. quality: the planted broken copy's badge is "Weird"; scenes/walk_bat.json's is "Good" or "OK".
##  d. the cache: closing and reopening the panel runs 0 Checks (SceneCat.checks_run counted) and every badge is ready at once.
##  e. no frame over 100 ms while the badges fill (process frames measured from the My scenes click to the last badge).
##  f. Hide weird ones hides the broken copy (and shows it again when unticked); walk_bat stays shown.
##  g. a star survives closing and reopening the panel, is saved in the settings file, and a star click does not open the scene.
##  h. Best first puts the Weird copy last among the saved scenes; Newest first puts it back at the top.
extends SceneTree

const DIR := "user://scenecat_test"
const BROKEN := "user://scenecat_test/scenecat_broken.json"
const KICK := "user://scenecat_test/scenecat_kick.json"
const DRAFT := "user://scenecat_test/_wip/scenecat_draft.json"
const WALK := "res://scenes/walk_bat.json"
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
	var kd: Dictionary = JSON.parse_string(walk_txt)   # the kick copy: walk_bat's poses with fight names (its own card names must not say walk)
	var kn := ["ready", "kick", "ready again", "kick back"]
	for i in kd["cards"].size():
		kd["cards"][i]["name"] = kn[i % kn.size()]
	_write(KICK, JSON.stringify(kd))
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
	btn(true, pt)
	await process_frame
	btn(false, pt)
	var last := Time.get_ticks_usec()
	var guard := 0
	while scenes.pending() > 0 and guard < 2000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		guard += 1
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

	# b: the Fight chip
	await click(scenes.chip("Fight"))
	var all_match := true
	var fight_shown := 0
	var shipped_fight := 0
	for p in scenes.tile_paths(false) + scenes.tile_paths(true):
		var is_fight := scenes.tile_category(p) == "Fight"
		if scenes.tile_shown(p) != is_fight:
			all_match = false
		if is_fight and scenes.tile_shown(p):
			fight_shown += 1
			if String(p).begins_with("res://"):
				shipped_fight += 1
	ok(all_match, "b: under Fight, exactly the Fight tiles are shown (%d)" % fight_shown)
	ok(scenes.tile_shown(KICK), "b: the planted kick copy is under Fight")
	ok(shipped_fight >= 1, "b: a SHIPPED punch/kick scene is under Fight (%d shipped)" % shipped_fight)
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
	await click(my)
	await idle(4)
	ok(SceneCat.checks_run == 0, "d: reopening runs 0 Checks (ran %d)" % SceneCat.checks_run)
	ok(scenes.pending() == 0, "d: every badge is ready at once on reopen")
	ok(scenes.tile_badge(BROKEN) == "Weird", "d: the broken copy is still Weird after reopen")
	ok(scenes.tile_star(WALK).text == "★", "g: walk_bat's star survived the close and reopen")

	ok(worst < 100.0, "e: no frame over 100 ms while the badges fill (slowest %.0f ms)" % worst)
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
	for p in [BROKEN, KICK, DRAFT, SceneCat.cache_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
