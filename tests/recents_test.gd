## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/recents_test.gd     (ROADMAP_400 P13; a window)
## RECENT SCENES WITH PICTURES (scripts/recents.gd). Bars, stated before measuring:
##   0 boot      a test that boots main.tscn sees NO start panel (it follows the tour's rule: never in a test)
##   1 list      14 scenes saved to user:// paths: the first three are at the top newest first; at most 12 are kept
##   2 pictures  each kept scene has user://thumbs/<sha256 of its path>.png, 256x144, and its centre region is not
##               uniform (the body is drawn): luminance variance of the centre third > 1e-4
##   3 missing   a deleted file's tile is greyed (disabled, alpha < 0.6) and carries "moved or deleted: remove from the
##               list"; pressing that drops it from the list and deletes its picture
##   4 open      pressing a tile opens that scene (the scene's name matches) and closes the panel
##   5 placement the panel is drawn inside the window, centred, with a picture on every present tile, a "New scene"
##               tile, and a screenshot (C:/Users/Nick/.claude/jobs/9afc22db/tmp/recents.png)
## Only user:// is written (the test's own settings file, user://zz_recents, user://thumbs).
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/recents.png"
const DIRP := "user://zz_recents"
const SRC := ["res://scenes/combo3.json", "res://scenes/thrust.json", "res://scenes/bo_spin.json"]

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func scene_path(i: int) -> String:
	return "%s/s_%02d.json" % [DIRP, i]


func scene_name(i: int) -> String:
	return "recents test %02d" % i


## the luminance variance of the middle third of a picture
func centre_var(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var s := 0.0
	var s2 := 0.0
	var n := 0
	for y in range(h / 3, 2 * h / 3):
		for x in range(w / 3, 2 * w / 3):
			var v := img.get_pixel(x, y).get_luminance()
			s += v
			s2 += v * v
			n += 1
	return s2 / n - (s / n) * (s / n)


## "save" scene i: its file written under user://, opened, noted as saved (the picture is taken from the view)
func save_scene(i: int) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC[i % 3]))
	d["scene"] = scene_name(i)
	var f := FileAccess.open(scene_path(i), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	m._load_scene(scene_path(i))
	m._rebuild_cards()
	await idle(2)
	m._recent_note(scene_path(i), true)
	await m.recents.settle()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute(gp(DIRP))
	var R: Recents = m.recents
	ok(m.settings != "user://poser.cfg", "the test's own settings file: %s" % m.settings)
	ok(R != null and (R.panel == null or not R.panel.visible), "0 boot: no start panel in a test")
	if FileAccess.file_exists(m.settings):
		DirAccess.remove_absolute(gp(m.settings))

	# 1 the list
	for i in 3:
		await save_scene(i)
	var l: Array = m._recent_list()
	ok(l == [scene_path(2), scene_path(1), scene_path(0)], "1 three scenes saved -> newest first: %s" % [l])
	for i in range(3, 14):
		await save_scene(i)
	l = m._recent_list()
	ok(l.size() == 12 and l[0] == scene_path(13) and l[11] == scene_path(2), "1 fourteen saved -> 12 kept, newest first (%d, first %s, last %s)" % [l.size(), l[0].get_file(), l[11].get_file()])
	var meta := R.meta_all()
	ok(meta.size() == 12 and int(meta[scene_path(13)]["cards"]) == m.S.cards.size() and float(meta[scene_path(13)]["len"]) > 0.0, "  each has a time, card count, length: %s" % [meta[scene_path(13)]])

	# 2 pictures
	var bad := []
	var minv := 1.0
	for p in l:
		var tp := Recents.thumb_path(p)
		if not FileAccess.file_exists(tp):
			bad.append(p.get_file() + " (no file)")
			continue
		var img := Image.load_from_file(tp)
		var v := centre_var(img)
		minv = minf(minv, v)
		if img.get_width() != 256 or img.get_height() != 144 or v <= 1e-4:
			bad.append("%s %dx%d var %.6f" % [p.get_file(), img.get_width(), img.get_height(), v])
	ok(bad.is_empty(), "2 all 12 pictures are 256x144 with a drawn centre (smallest centre variance %.5f) %s" % [minv, bad])

	# 3 a deleted file
	var gone := scene_path(9)
	DirAccess.remove_absolute(gp(gone))
	R.show_panel()
	await idle(3)
	var tile: Button = R.tiles.get(gone)
	var rm: Button = R.removes.get(gone)
	ok(tile != null and tile.disabled and tile.get_child(0).modulate.a < 0.6 and rm != null and rm.text.contains("moved or deleted: remove from the list"),
		"3 deleted file: tile disabled and greyed (alpha %.2f), button '%s'" % [tile.get_child(0).modulate.a if tile else -1.0, rm.text if rm else "none"])
	ok(R.removes.size() == 1, "  only the missing one has the remove action (%d)" % R.removes.size())
	rm.pressed.emit()
	await idle(3)
	l = m._recent_list()
	ok(l.size() == 11 and not l.has(gone) and not R.tiles.has(gone) and not FileAccess.file_exists(Recents.thumb_path(gone)), "  remove drops it: %d left, tile and picture gone" % l.size())

	# 5 placement (before the click closes the panel)
	await idle(2)
	var pics := 0
	for p in R.tiles:
		var tr := (R.tiles[p].get_child(0) as Node).get_child(0) as TextureRect
		if tr.texture != null:
			pics += 1
	var win := Rect2(Vector2.ZERO, Vector2(root.size))
	var pr: Rect2 = R.panel.get_global_rect()
	var cen := pr.get_center()
	ok(R.tiles.size() == 11 and pics == 11 and R.new_tile != null and R.new_tile.is_visible_in_tree(), "5 11 tiles with a picture each (%d) and a New scene tile" % pics)
	ok(win.encloses(pr) and absf(cen.x - win.get_center().x) < 40.0 and absf(cen.y - win.get_center().y) < 120.0,
		"  the panel %s is inside the window %s and centred (centre %s)" % [pr, win, cen])
	root.get_texture().get_image().save_png(SHOT)

	# 4 a click opens the scene
	m._load_scene(scene_path(13))
	m._rebuild_cards()
	await idle(2)
	R.show_panel()
	await idle(2)
	var want := scene_path(5)
	(R.tiles[want] as Button).pressed.emit()
	await idle(4)
	ok(m.S.name == scene_name(5) and m.scene_path == want and not R.panel.visible, "4 clicking a tile opens that scene: '%s', panel closed" % m.S.name)

	# clean up our files
	for i in 14:
		DirAccess.remove_absolute(gp(scene_path(i)))
		DirAccess.remove_absolute(gp(Recents.thumb_path(scene_path(i))))
	DirAccess.remove_absolute(gp(DIRP))
	print("recents_test: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
