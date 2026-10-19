## godot --path . -s tests/batch_export_test.gd     (ROADMAP 80: batch export of many scenes; needs a window for the screenshot)
## BARS (stated before the run):
##  (1) 3 scenes x glb = 3 files, each byte-identical (sha256) to exporting that scene alone through the app (main's _load_scene + _export_glb);
##  (2) the open scene (combo3) is byte-identical before and after the batch: its file's sha256 and its in-memory state (to_dict JSON);
##  (3) nothing under scenes/ is written: every file's sha256 in scenes/ is the same before and after;
##  (4) a corrupt scene copy in a temp folder fails with a named "is not a scene file" line while the 2 good ones still export (2 done, 1 failed);
##  (5) folders: scenes/ itself is refused, scenes/_wip/x and user:// are accepted, '..' is refused;
##  (6) the Batch dialog (from Export...) lists the scenes, the run through the dialog writes 3 files and its summary says "3 done, 0 failed";
##  (7) screenshot of the batch panel to C:/Users/Nick/.claude/jobs/9afc22db/tmp/batchexport.png.
## Files go to user://zz_batch_* (removed after). The autosave is never named.
extends SceneTree

var fails := 0
const PICKS := ["res://scenes/combo3.json", "res://scenes/walk_bat.json", "res://scenes/thrust.json"]
const ALONE := "user://zz_batch_alone"
const OUT := "user://zz_batch_out"
const UI_OUT := "user://zz_batch_ui"
const SRC := "user://zz_batch_src"
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/batchexport.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func clean(d: String) -> void:
	var g := ProjectSettings.globalize_path(d)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


## a Button with this text anywhere under node (the custom buttons sit in the dialog's own button row, not as children)
func has_button(node: Node, text: String) -> bool:
	for c in node.get_children(true):   # include_internal: the dialog keeps its button row internal
		if c is Button and (c as Button).text == text:
			return true
		if has_button(c, text):
			return true
	return false


func scenes_hashes() -> Dictionary:
	var h := {}
	var d := DirAccess.open("res://scenes")
	for f in d.get_files():
		h[f] = FileAccess.get_sha256("res://scenes/" + f)
	return h


func _init() -> void:
	clean(ALONE)
	clean(OUT)
	clean(UI_OUT)
	clean(SRC)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ALONE))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame

	# reference: each scene exported alone, through the app's own road (open it, Export .glb)
	var alone := {}
	for p in PICKS:
		m._load_scene(p)
		var path: String = m._export_glb(ALONE)
		alone[path.get_file()] = FileAccess.get_sha256(path)
	print("     alone: %s" % [alone.keys()])

	# the open scene: back to combo3, measured before the batch
	m._load_scene("res://scenes/combo3.json")
	var open_file_before := FileAccess.get_sha256("res://scenes/combo3.json")
	var open_state_before := JSON.stringify(m.S.to_dict(m.B, true))
	var scenes_before := scenes_hashes()

	# (1) the batch: 3 scenes, glb
	var res: Dictionary = BatchExport.run(PICKS, "glb", OUT)
	ok(int(res["done"]) == 3 and (res["failed"] as Array).is_empty(), "(1) 3 scenes x glb: %d done, %d failed" % [res["done"], (res["failed"] as Array).size()])
	var same := 0
	for f in res["files"]:
		var name := String(f).get_file()
		var got := FileAccess.get_sha256(String(f))
		var eq: bool = alone.has(name) and got != "" and got == alone[name]
		if eq:
			same += 1
		ok(eq, "(1) %s is byte-identical to exporting it alone (sha256 %s)" % [name, got.left(16)])
	ok(same == 3 and (res["files"] as Array).size() == 3, "(1) 3 files, all 3 identical to their alone export")

	# (2) the open scene did not move
	ok(FileAccess.get_sha256("res://scenes/combo3.json") == open_file_before, "(2) the open scene's file is byte-identical after the batch")
	ok(JSON.stringify(m.S.to_dict(m.B, true)) == open_state_before, "(2) the open scene's state is identical after the batch")

	# (3) nothing under scenes/ was written
	ok(scenes_hashes() == scenes_before, "(3) no file under scenes/ changed (%d files compared)" % scenes_before.size())

	# (4) a corrupt copy in a temp folder fails by name, the others still export
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SRC))
	var f1 := FileAccess.open(SRC + "/corrupt.json", FileAccess.WRITE)
	f1.store_string("{ this is not json")
	f1.close()
	var r4: Dictionary = BatchExport.run(["res://scenes/thrust.json", SRC + "/corrupt.json", "res://scenes/walk_bat.json"], "bvh", OUT + "_bvh")
	var lines := "\n".join(r4["lines"])
	print("     summary:\n" + lines)
	ok(int(r4["done"]) == 2 and (r4["failed"] as Array).size() == 1, "(4) corrupt among 3: %d done, %d failed" % [r4["done"], (r4["failed"] as Array).size()])
	ok(lines.contains("corrupt.json is not a scene file") and lines.contains("open it in the app"), "(4) the failure is named, with its next step")

	# (5) folders
	ok(BatchExport.check_dir("res://scenes") != "" and BatchExport.check_dir("res://scenes/") != "", "(5) scenes/ itself is refused")
	ok(BatchExport.check_dir("res://scenes/combo3_out") != "", "(5) a folder inside scenes/ (not _wip) is refused")
	ok(BatchExport.check_dir("res://scenes/_wip/batch") == "" and BatchExport.check_dir("user://zz_batch_x") == "", "(5) scenes/_wip/batch and user:// are accepted")
	ok(BatchExport.check_dir("res://scenes/_wip/../x") != "", "(5) '..' is refused")

	# (6) the batch dialog through Export...: list, tick 3, run
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	ok(has_button(ui.dlg, "Batch..."), "(6) the Export dialog has a Batch... button")
	ui._on_custom(&"batch")
	ok(ui.batch_ui != null and ui.batch_ui.dlg.visible, "(6) Batch... opens the batch dialog")
	ui.batch_ui.dlg.hide()
	ui.open_batch()
	var bd: BatchDialog = ui.batch_ui
	await process_frame
	ok(bd.picks.size() >= 3, "(6) the batch dialog lists %d scenes" % bd.picks.size())
	# (6b) select none / select all, and the stale refusal line is dropped on the first tick after it
	var b_all := bd.dlg.find_child("batch_select_all", true, false) as Button
	var b_none := bd.dlg.find_child("batch_select_none", true, false) as Button
	ok(b_all != null and b_none != null, "(6b) Select all and Select none buttons exist")
	b_none.pressed.emit()
	await bd._on_run()
	ok(bd.ui_status.text.begins_with("NOT NOW"), "(6b) an empty run is refused: %s" % bd.ui_status.text)
	(bd.picks[0][0] as CheckBox).button_pressed = true
	ok(not bd.ui_status.text.begins_with("NOT NOW"), "(6b) after ticking one scene the old refusal is gone: %s" % bd.ui_status.text)
	bd.ui_dir.text = "res://scenes"
	await bd._on_run()
	ok(bd.ui_status.text.begins_with("NOT NOW: a batch never writes"), "(6b) a scenes/ folder is refused: %s" % bd.ui_status.text.split("
")[0])
	bd.ui_dir.text = UI_OUT
	bd.ui_dir.text_changed.emit(UI_OUT)   # what typing in the box does (a code set of .text does not emit it)
	ok(not bd.ui_status.text.begins_with("NOT NOW"), "(6b) fixing the folder drops the old refusal line")
	b_all.pressed.emit()
	ok(bd._picked().size() == bd.picks.size(), "(6b) Select all ticks all %d scenes" % bd.picks.size())
	b_none.pressed.emit()
	ok(bd._picked().is_empty(), "(6b) Select none clears every tick")
	for pk in bd.picks:
		(pk[0] as CheckBox).button_pressed = PICKS.has(pk[1])
	bd.ui_dir.text = UI_OUT
	await bd._on_run()
	ok(bd.ui_summary.text.begins_with("batch: 3 done, 0 failed"), "(6) the dialog's summary: %s" % bd.ui_summary.text.split("\n")[0])
	ok(bd.ui_status.text.begins_with("Batch finished: 3 of 3"), "(6) the status line: %s" % bd.ui_status.text)
	ok(FileAccess.get_sha256("res://scenes/combo3.json") == open_file_before, "(6) the open scene still byte-identical after the dialog run")
	bd.ui_dir.text = "res://scenes"
	await bd._on_run()
	ok(bd.ui_status.text.begins_with("NOT NOW: a batch never writes into scenes/"), "(6) scenes/ typed in the folder box is refused on the spot")
	bd.ui_dir.text = UI_OUT
	bd.ui_dir.text_changed.emit(UI_OUT)   # the person fixes the folder by typing: the refusal line goes
	ok(not bd.ui_status.text.begins_with("NOT NOW"), "(6c) the panel shows no stale refusal after the folder is fixed")

	# (7) the panel, as the person sees it
	bd.dlg.popup_centered(Vector2i(680, 700))
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(SHOT)
	ok(err == OK, "(7) screenshot saved to %s (%s)" % [SHOT.get_file(), error_string(err)])

	m.export_ui.batch_ui.dlg.hide()
	clean(ALONE)
	clean(OUT)
	clean(OUT + "_bvh")
	clean(UI_OUT)
	clean(SRC)
	quit(1 if fails > 0 else 0)
