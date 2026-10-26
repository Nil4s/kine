## godot --path . -s tests/drafts_test.gd     (DRAFTS, 10-24: the scene list shows the saved scenes first and ONE collapsed
## group "Drafts (N)" with the _wip clips; Easy's Open shows the saved scenes then the newest 5 drafts; needs a window)
##   1 the saved scenes are the first two items of the list (newest first), their metadata is their path
##   2 collapsed: the group says "Drafts (T)" (T = the 25 test clips + the project's own res://scenes/_wip clips) and no draft is listed
##   3 expanded (its row picked, as a click does): the newest 20 drafts and "Show all 25 drafts"; each row's metadata is its path
##   4 "Show all 25 drafts": all 25; the group collapses again by its row
##   5 Easy's Open: the saved scenes, then "Recent drafts" with the newest 5 (no others)
##   6 with 300 drafts, _fill_scene_list takes under 30 ms once the files are read (the cache holds: no file is read again)
## Nothing is written outside user://drafts_<pid> (UserPaths.force + root): res:// is untouched, and the folder is removed at the end.
extends SceneTree

var fails := 0
var m: Node
var R := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func write(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"cards\": []}")
	f.close()


## the list's rows as [text, metadata]
func rows() -> Array:
	var out := []
	for i in m.ui_scenes.item_count:
		out.append([m.ui_scenes.get_item_text(i), String(m.ui_scenes.get_item_metadata(i)), i])
	return out


func draft_rows() -> Array:
	return rows().filter(func(r): return r[1].contains("/_wip/"))


func index_of(text_part: String) -> int:
	for r in rows():
		if r[0].contains(text_part):
			return r[2]
	return -1


## what a click on a list row does (the OptionButton selects it, then its item_selected runs the pick)
func pick(i: int) -> void:
	m.ui_scenes.select(i)
	m._scene_picked(i)
	m.ui_scenes.get_popup().hide()
	await idle(2)


func _init() -> void:
	R = "user://drafts_%d" % OS.get_process_id()
	var bundled := 0   # the project's own res://scenes/_wip is listed as well (other suites leave clips there): counted, not assumed empty
	for f in DirAccess.get_files_at("res://scenes/_wip"):
		if f.ends_with(".json"):
			bundled += 1
	var T := 25 + bundled   # the drafts the group counts
	UserPaths.force = true
	UserPaths.root = R
	DirAccess.make_dir_recursive_absolute(R + "/scenes/_wip")
	for k in 25:
		write(R + "/scenes/_wip/zz_draft_%03d.json" % k)
	write(R + "/scenes/zz_saved_a.json")
	OS.delay_msec(1100)   # the modified time is in whole seconds: b must be a second newer than a to be first
	write(R + "/scenes/zz_saved_b.json")
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.settings = R + "/settings.cfg"   # the recent list is this test's own (none), not the user's poser.cfg
	m.autosave = R + "/autosave.json"
	m.scene_path = R + "/scenes/zz_saved_b.json"   # a saved scene is the open one: the group stays collapsed
	m._lists()
	await idle(2)

	# 1
	var first: Array = rows().slice(0, 2).map(func(r): return r[1])
	ok(first == [R + "/scenes/zz_saved_b.json", R + "/scenes/zz_saved_a.json"], "1 the two saved scenes are the first two items: %s" % str(first))
	var saved_block := rows().filter(func(r): return not r[1].contains("/_wip/") and not r[1].begins_with("#"))
	var mt_ok := true
	for k in range(1, saved_block.size()):
		mt_ok = mt_ok and FileAccess.get_modified_time(saved_block[k - 1][1]) >= FileAccess.get_modified_time(saved_block[k][1])
	ok(mt_ok, "1 the saved scenes are newest first (%d rows)" % saved_block.size())

	# 2
	var hdr := index_of("Drafts (%d)" % T)
	ok(hdr >= 0 and String(m.ui_scenes.get_item_text(hdr)).begins_with("+ ") and draft_rows().is_empty(),
		"2 collapsed: the group says %d (25 test clips + bundled) and no draft is listed" % [T, bundled])

	# 3
	await pick(hdr)
	var dr := draft_rows()
	var mt_ok2 := true
	for k in range(1, dr.size()):
		mt_ok2 = mt_ok2 and FileAccess.get_modified_time(dr[k - 1][1]) >= FileAccess.get_modified_time(dr[k][1])
	ok(dr.size() == 20 and index_of("Show all %d drafts" % T) >= 0 and String(m.ui_scenes.get_item_text(index_of("Drafts (%d)" % T))).begins_with("- "),
		"3 expanded: 20 drafts and Show all (%d drafts listed)" % dr.size())
	ok(mt_ok2 and dr.all(func(r): return r[1].begins_with(R + "/scenes/_wip/") and r[1].ends_with(".json")),
		"3 the drafts are newest first, each row's metadata is its file path")

	# 4
	await pick(index_of("Show all %d drafts" % T))
	ok(draft_rows().size() == T and index_of("Show all") < 0, "4 Show all: all %d drafts listed, no 'Show all' row" % T)
	await pick(index_of("Drafts (%d)" % T))
	var h4 := index_of("Drafts (%d)" % T)
	ok(h4 >= 0 and String(m.ui_scenes.get_item_text(h4)).begins_with("+ ") and draft_rows().is_empty(),
		"4 the group's row collapses it again")

	# 5
	m.easy._open()
	await idle(2)
	var menu: PopupMenu = m.easy._menu
	var saved_rows := 0
	for r in rows():
		if not (r[1].contains("/_wip/") or r[1].begins_with("#")):
			saved_rows += 1
	var sep := -1
	for i in menu.item_count:
		if menu.is_item_separator(i):
			sep = i
	var after: Array = []
	for i in range(sep + 1, menu.item_count):
		after.append(menu.get_item_text(i))
	var want_after := []
	for p in m.draft_paths().slice(0, 5):
		want_after.append(String(p).get_file().get_basename().replace("_", " ") + "   (draft)")
	ok(menu.item_count == saved_rows + 6 and sep == saved_rows and after == want_after,
		"5 Open: %d saved rows, then 'Recent drafts' and the newest 5 drafts (%d rows in all: %s)" % [saved_rows, menu.item_count, str(after)])
	ok(menu.get_item_text(0).begins_with("zz saved b") and menu.get_item_text(1).begins_with("zz saved a"),
		"5 Open: the two saved scenes lead ('%s', '%s')" % [menu.get_item_text(0), menu.get_item_text(1)])
	menu.hide()
	await idle(2)

	# 6
	for k in range(25, 300 - bundled):
		write(R + "/scenes/_wip/zz_draft_%03d.json" % k)
	m._fill_scene_list()   # the first list reads the new files
	var t0 := Time.get_ticks_usec()
	m._fill_scene_list()
	var warm := (Time.get_ticks_usec() - t0) / 1000.0
	ok(m.draft_paths().size() >= 300 and warm < 30.0,   # at least 300: the checkout's own scenes/_wip clips add to the 300
		"6 with %d drafts _fill_scene_list takes %.1f ms (bar 30 ms, the cached list; collapsed)" % [m.draft_paths().size(), warm])

	# cleanup: this test's own folder only
	for d in [R + "/scenes/_wip", R + "/scenes"]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + f)
	for f in DirAccess.get_files_at(R):
		DirAccess.remove_absolute(R + "/" + f)
	DirAccess.remove_absolute(R + "/scenes/_wip")
	DirAccess.remove_absolute(R + "/scenes")
	DirAccess.remove_absolute(R)
	UserPaths.force = false
	UserPaths.root = ""
	print("DRAFTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
