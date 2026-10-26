## godot --path . -s tests/startscreen_test.gd     (THE START SCREEN: scripts/start_screen.gd, scripts/start_art.gd; needs a window)
## Bars, stated before measuring (real mouse clicks through root.push_input; the screen is opened explicitly, tests skip it at boot):
##   0 boot      a test that boots main.tscn does not show the start screen
##   1 art       three cards, each with a real-render picture: a texture, the fighter's skin colour on it (not a stick figure)
##               and the picture cached under user://start_art/
##   2 cards     clicking ANIMATION / MODELING / 3D BUILDING with the Easy or Expert toggle set opens the screen's page
##               (POSE, MODEL with the body open, STAGE) in the mode chosen; the project kind is set
##   3 kind      the kind is written as "kind" in the scene file and read back; a file without one reads as animation
##   4 tiles     recent tiles show the existing SceneThumbs picture and their kind tag; a click opens that scene and closes
##   5 chips     All / Animation / Modeling / Building / Favourites filter the tiles by kind (and by the star)
##   6 search    the search box filters the tiles by name
##   7 empty     with no saved scene the screen shows the three example tiles and "No recent work yet"
##   8 resume    Resume (and Esc) closes the screen and opens the last scene
##   9 fit       at 1280 x 720 and at 1024 x 600 the bars and the three cards are inside the window and do not overlap
##  10 shots     C:/Temp/claude/ss/start.png, start_empty.png, start_1024.png
## Only user:// is written (user://startscreen_test, user://start_art, the test's own settings file).
extends SceneTree

const DIRT := "user://startscreen_test"
const DIRE := "user://startscreen_empty"
const SRC := "res://scenes/combo3.json"
const SHOT_DIR := "C:/Temp/claude/ss"

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


func write_scene(path: String, kind: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC))
	d["scene"] = path.get_file().get_basename()
	if kind == "":
		d.erase("kind")
	else:
		d["kind"] = kind
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func tile_of(path: String) -> Control:
	return ss._tiles[path]["tile"] if ss._tiles.has(path) else null


func visible_tiles() -> int:
	var n := 0
	for p in ss._tiles:
		if (ss._tiles[p]["tile"] as Control).visible:
			n += 1
	return n


## the bars that are about the window: every named bar and card is inside the window and no two cards overlap
func fit_check(label: String) -> void:
	(ss.find_child("content_scroll", true, false) as ScrollContainer).scroll_vertical = 0
	await idle(2)
	var win := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	var bars := [ss.find_child("top_bar", true, false), ss.find_child("bottom_bar", true, false), ss.find_child("new_project", true, false), ss.find_child("chip_all", true, false)]
	var cards := [ss.find_child("card_animation", true, false), ss.find_child("card_modeling", true, false), ss.find_child("card_building", true, false)]
	var outside := []
	for c in bars + cards:
		if c == null or not (c as Control).is_visible_in_tree():
			outside.append("missing")
			continue
		if not win.encloses((c as Control).get_global_rect()):
			outside.append("%s %s" % [c.name, (c as Control).get_global_rect()])
	ok(outside.is_empty(), "9 %s: the bars and the three cards are inside the window %s %s" % [label, win.size, outside])
	var over := []
	for i in cards.size():
		for j in range(i + 1, cards.size()):
			if (cards[i] as Control).get_global_rect().intersects((cards[j] as Control).get_global_rect()):
				over.append("%d/%d" % [i, j])
	var top: Rect2 = (bars[0] as Control).get_global_rect()
	var bot: Rect2 = (bars[1] as Control).get_global_rect()
	for c in cards:
		if (c as Control).get_global_rect().intersects(top) or (c as Control).get_global_rect().intersects(bot):
			over.append("card on a bar")
	ok(over.is_empty(), "9 %s: no card overlaps another card or a bar %s" % [label, over])


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
	ss = m.start_screen
	ok(ss != null and not ss.visible, "0 boot: the start screen is built and not shown in a test")
	DirAccess.make_dir_recursive_absolute(gp(DIRT))
	DirAccess.make_dir_recursive_absolute(gp(DIRE))
	DirAccess.make_dir_recursive_absolute(gp("user://start_art"))
	write_scene(DIRT + "/sst_mod.json", "modeling")
	write_scene(DIRT + "/sst_bld.json", "building")
	write_scene(DIRT + "/sst_old.json", "")
	ss.dirs_override = [DIRT]

	# 1 art
	ss.show_screen()
	var waited := 0
	while waited < 900 and (ss.art.get_art("animation") == null or ss.art.get_art("modeling") == null or ss.art.get_art("building") == null):
		await process_frame
		waited += 1
	var bad := []
	var skin_frac := 0.0
	for k in ["animation", "modeling", "building"]:
		var t: Texture2D = ss.art.get_art(k)
		if t == null or t.get_width() < 8:
			bad.append(k + " no texture")
			continue
		var img := t.get_image()
		var n := 0
		var total := img.get_width() * img.get_height()
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				if c.r > 0.6 and c.g > 0.6 and c.b > 0.6:
					n += 1
		if k == "animation":
			skin_frac = float(n) / float(total / 4.0)
		if k == "animation" and skin_frac < 0.02:
			bad.append("animation has no body (skin fraction %.3f)" % skin_frac)
	ok(bad.is_empty(), "1 art: three cards with a real-render picture, the body drawn (animation skin fraction %.3f) %s" % [skin_frac, bad])
	var cached := FileAccess.file_exists(StartArt.cache_path("animation"))
	ok(cached and ss.art.renders + ss.art.disk_hits >= 3, "1 art: the three pictures are cached under user://start_art/ (renders %d, disk %d)" % [ss.art.renders, ss.art.disk_hits])
	ok(ss._cards.size() == 3 and ss._card_art["animation"].texture != null, "1 art: the cards show their pictures")
	await fit_check("1280 x 720")

	# 2 cards: each opens its page in the mode its toggle shows
	var plan := [["animation", "POSE", true], ["modeling", "MODEL", false], ["building", "STAGE", false]]
	for pl in plan:
		ss.show_screen()
		await idle(3)
		var kind: String = pl[0]
		var want_easy: bool = pl[2]
		await click(ss.find_child("easy_" + kind, true, false) if want_easy else ss.find_child("expert_" + kind, true, false))
		await click(ss._cards[kind])
		await idle(4)
		var page: String = m.cur_page
		ok(not ss.visible and page == pl[1], "2 %s card: the screen closes and the page is %s (is %s)" % [kind, pl[1], page])
		ok(m.S.kind == kind, "2 %s card: the project kind is %s (is %s)" % [kind, kind, m.S.kind])
		ok(m.easy.on == (want_easy if kind == "animation" else false), "2 %s card: the mode is %s (Easy on: %s)" % [kind, "Easy" if want_easy else "Expert", m.easy.on])
	ok(m.S.cards.size() == 0 or m.S.kind == "building", "2 the last card made a new scene (kind building)")

	# 3 kind saved / loaded
	var d: Dictionary = m.S.to_dict(m.B, false)
	ok(String(d.get("kind", "")) == "building", "3 the scene file holds kind: building")
	var s2 := Scene.new()
	s2.from_dict(JSON.parse_string(FileAccess.get_file_as_string(DIRT + "/sst_mod.json")))
	var s3 := Scene.new()
	s3.from_dict(JSON.parse_string(FileAccess.get_file_as_string(DIRT + "/sst_old.json")))
	ok(s2.kind == "modeling" and s3.kind == "animation", "3 loaded: modeling (is %s); a file with no kind reads as animation (is %s)" % [s2.kind, s3.kind])

	# 4 tiles: pictures and tags; a click opens the scene
	ss.show_screen()
	await idle(3)
	var mpath := DIRT + "/sst_mod.json"
	m.thumbs.request(mpath)
	await m.thumbs.settle()
	await idle(3)
	ss._made(mpath)
	var pic: Texture2D = ss._tiles[mpath]["pic"].texture
	ok(ss._tiles.size() == 3 and pic != null, "4 tiles: three recent tiles, the modeling one with its SceneThumbs picture (%s)" % [pic != null])
	ok((ss._tiles[mpath]["tag"] as Label).text == "Modeling" and (ss._tiles[DIRT + "/sst_old.json"]["tag"] as Label).text == "Animation", "4 tiles: the kind tags show (Modeling, and Animation for the file with none)")
	await click(tile_of(mpath))
	await idle(4)
	ok(not ss.visible and String(m.scene_path) == mpath, "4 a tile opens its scene and closes the screen (scene %s)" % String(m.scene_path).get_file())

	# 5 chips
	ss.show_screen()
	await idle(3)
	await click(ss._chip_btns["modeling"])
	ok(visible_tiles() == 1 and (tile_of(mpath) as Control).visible, "5 chip Modeling: one tile shown (%d)" % visible_tiles())
	await click(ss._chip_btns["building"])
	ok(visible_tiles() == 1 and (tile_of(DIRT + "/sst_bld.json") as Control).visible, "5 chip Building: the building tile only (%d)" % visible_tiles())
	await click(ss._chip_btns["fav"])
	ok(visible_tiles() == 0, "5 chip Favourites: no favourite yet, no tile")
	await click(ss._chip_btns["all"])
	ok(visible_tiles() == 3, "5 chip All: three tiles (%d)" % visible_tiles())

	# 6 search
	ss._search.text = "bld"
	ss._search.text_changed.emit("bld")
	ok(visible_tiles() == 1, "6 search bld: one tile (%d)" % visible_tiles())
	ss._search.text = ""
	ss._search.text_changed.emit("")
	ok(visible_tiles() == 3, "6 search cleared: three tiles (%d)" % visible_tiles())
	await idle(2)
	ss._close()
	ss.show_screen()
	await idle(3)
	await fit_check("1280 x 720 with tiles")
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	get_root().get_texture().get_image().save_png(SHOT_DIR + "/start.png")

	# 8 resume (Esc): the last scene opens
	m._recent_note(DIRT + "/sst_bld.json", true)
	ss._close()
	ss.show_screen()
	await idle(3)
	ok(ss._resume_path == DIRT + "/sst_bld.json" and ss._resume_btn.visible, "8 resume strip names the last scene (%s)" % ss._resume_path.get_file())
	await click(ss._resume_btn)
	await idle(4)
	ok(not ss.visible and String(m.scene_path) == DIRT + "/sst_bld.json", "8 Resume closes the screen and opens the last scene (scene %s)" % String(m.scene_path).get_file())
	ss.show_screen()
	await idle(3)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc, true)
	await idle(3)
	ok(not ss.visible, "8 Esc closes the screen")

	# 7 empty state (first run: no saved scene)
	ss.dirs_override = [DIRE]
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value("recent", "scenes", [])
	cf.save(m.settings)
	ss.show_screen()
	await idle(3)
	ok(ss._tiles.size() == 3 and ss._example_paths().size() == 3, "7 empty: three example tiles (%d)" % ss._tiles.size())
	ok(ss._empty_note.text.begins_with("New here") and ss._resume_text.text.begins_with("No recent work"), "7 empty: 'New here' and 'No recent work yet' say so")
	get_root().get_texture().get_image().save_png(SHOT_DIR + "/start_empty.png")
	ss._close()

	# 9 at 1024 x 600
	ss.dirs_override = [DIRT]
	root.content_scale_size = Vector2i(1024, 600)
	await idle(6)
	ss.show_screen()
	await idle(4)
	await fit_check("1024 x 600")
	get_root().get_texture().get_image().save_png(SHOT_DIR + "/start_1024.png")
	ss._close()
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)

	print("RESULT %d FAIL" % fails if fails > 0 else "RESULT 0 FAIL")
	quit(1 if fails > 0 else 0)
