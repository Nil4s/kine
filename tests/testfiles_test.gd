## godot --headless --path . -s tests/testfiles_test.gd
## TEST FILES: a run's own leftovers under user:// are removed by TestFiles.cleanup() (scripts/test_files.gd), and
## nothing else is. The writers are the app's own: an autosave (autosave_test_<pid>.json and its ring copies
## autosave_test_<pid>_<n>.json) and a suggestion journal (zz_suggestion_journal_<pid>.json). A look-alike file in a
## temp sub-folder of the test's own is not touched.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var pid := OS.get_process_id()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	# the writers, the app's own paths (main.gd testing block): an edit autosaved, and one suggestion logged
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.cards[2]["hold"] = float(m.S.cards[2]["hold"]) + 0.5
	m.autosave_now()
	m.sj.log("testfiles", "probe", 0, {}, 0)
	await idle(2)
	var auto := "user://autosave_test_%d.json" % pid
	var ring := "user://autosave_test_%d_1.json" % pid
	var journal := "user://zz_suggestion_journal_%d.json" % pid
	ok(FileAccess.file_exists(auto), "1 the autosave is written (%s)" % auto)
	ok(FileAccess.file_exists(ring), "2 its ring copy is written (%s)" % ring)
	ok(FileAccess.file_exists(journal), "3 the suggestion journal is written (%s)" % journal)
	# a look-alike of a real autosave, in a temp folder of the test's own: must survive the cleanup
	var tmp := "user://testfiles_%d" % pid
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp))
	var fake := tmp + "/autosave_1.json"
	var f := FileAccess.open(fake, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var fake2 := tmp + "/autosave_test_%d_1.json" % pid
	f = FileAccess.open(fake2, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	# the window goes, then the run's cleanup
	m.dummy_settle()
	root.remove_child(m)
	m.free()
	await idle()
	# the window's exit drops the per-process autosave itself (_exit_tree); the cleanup must take the rest
	var present := 0
	for q in [auto, ring, journal]:
		if FileAccess.file_exists(q):
			present += 1
	var removed := TestFiles.cleanup()
	ok(not FileAccess.file_exists(auto), "4 the autosave is gone after the run")
	ok(not FileAccess.file_exists(ring), "5 the cleanup removed its ring copy")
	ok(not FileAccess.file_exists(journal), "6 the cleanup removed the suggestion journal")
	ok(removed == present and present >= 1, "7 the cleanup counted exactly what was left (%d of %d)" % [removed, present])
	ok(FileAccess.file_exists(fake) and FileAccess.file_exists(fake2), "8 a look-alike in a temp sub-folder was not touched")
	TestFiles._rm_tree(ProjectSettings.globalize_path(tmp))
	print("TESTFILES: %d failed" % fails)
	quit(1 if fails > 0 else 0)
