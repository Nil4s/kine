## godot --path . -s tests/userpaths_test.gd     (USER PATHS: an exported build writes the user's files to the user's folder; needs a window)
## An exported build packs res:// READ-ONLY. UserPaths.force makes this run behave as one, with the user's folder in user://.
##   1 as run from source (force off): w() returns res:// paths unchanged (the editor and every other test write as before)
##   2 force on: w() maps res://scenes|moves|poses|exports|bodies|trash/... into the user's folder; other paths unchanged
##   3 an Easy card's clip (scenes/_wip) is written in the user's folder, and NO new file appears in res://scenes
##   4 Save scene writes the user's folder; scene_path points there; the scene list offers it; opening it loads its cards
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func count_res(dir: String) -> int:
	var n := 0
	var stack := [dir]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		n += DirAccess.get_files_at(d).size()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
	return n


func _init() -> void:
	# 1
	UserPaths.force = false
	ok(OS.has_feature("template") or UserPaths.w("res://scenes/_wip/a.json") == "res://scenes/_wip/a.json", "1 from source: res://scenes/_wip/a.json stays itself")
	# 2
	var R := "user://up_%d" % OS.get_process_id()
	UserPaths.force = true
	UserPaths.root = R
	ok(UserPaths.w("res://scenes/_wip/a.json") == R + "/scenes/_wip/a.json" and UserPaths.w("res://exports") == R + "/exports"
		and UserPaths.w("res://data/skeleton.json") == "res://data/skeleton.json", "2 forced: scenes/exports map into %s; data/ stays" % R)
	ok(UserPaths.dirs("res://scenes") == ["res://scenes", R + "/scenes"], "2 a list reads the bundled folder and the user's: %s" % str(UserPaths.dirs("res://scenes")))

	EasyMode.start_fresh = true
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	# 3
	m.easy.home.card(3)   # Punch
	await idle(20)
	var sp: String = m.scene_path
	ok(sp.begins_with(R + "/scenes/_wip/") and FileAccess.file_exists(sp), "3 the Punch clip is written in the user's folder: %s" % sp)
	# 4
	m.ui_scene_name.text = "up_test_scene"
	m._save_scene_now("up_test_scene")
	await idle(4)
	var saved := R + "/scenes/up_test_scene.json"
	ok(FileAccess.file_exists(saved) and m.scene_path == saved, "4 Save scene writes %s (scene_path %s)" % [saved, m.scene_path])
	m._fill_scene_list()
	var listed := false
	for i in m.ui_scenes.item_count:
		if String(m.ui_scenes.get_item_metadata(i)) == saved:
			listed = true
	ok(listed, "4 the scene list offers the saved scene")
	var n_cards: int = m.S.cards.size()
	m._new_scene()
	await idle(3)
	m._load_scene(saved)
	await idle(3)
	ok(m.S.cards.size() == n_cards and n_cards >= 2, "4 opening it loads its %d cards" % m.S.cards.size())
	# by a name only this test uses (other suites, run from source, write their own punch_N clips into res:// meanwhile,
	# under the same names: bar 3 shows where the clip went)
	ok(not FileAccess.file_exists("res://scenes/up_test_scene.json"), "4 the saved scene is not under res://scenes")

	UserPaths.force = false
	UserPaths.root = ""
	OS.move_to_trash(ProjectSettings.globalize_path(R))
	print("USERPATHS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
