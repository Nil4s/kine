extends SceneTree
## godot --path . -s tests/renderq_test.gd     (CG4 render queue: scene files in order, each job timed, a broken job named and skipped)
## BARS (stated before the run):
##  (1) 3 jobs of 3 formats (combo3 glb, walk_bat bvh, thrust fbx) all finish: 3 done, 0 failed, 3 files on disk, each over 1000 bytes;
##  (2) the glb job is byte-identical (sha256) to the app's own Export .glb of combo3 (main's _load_scene + _export_glb);
##  (3) the bvh starts with "HIERARCHY", the fbx with "Kaydara FBX" (binary FBX 7.x; the files are the formats they say);
##  (4) every job's log line ends "[x.xx s]", its time is above 0 and below 120 s, and it equals the result's secs within 0.01 s;
##  (5) a corrupt scene in the middle of the queue: its line is named "is not a scene file" with its time, the jobs after it still
##      land (2 done, 1 failed), the files come out in queue order (thrust, then walk_bat), and the failed line still carries a time (0.00 s is
##      a real reading: a refusal at the JSON check takes under 5 ms);
##  (6) the open scene (combo3) is byte-identical and in-memory identical after the queue runs;
##  (7) the batch dialog (Export... > Batch...) with 3 ticked scenes: summary "batch: 3 done, 0 failed" and 3 job lines, each with a time;
##  (8) screenshot of the dialog summary to C:/Temp/claude/renderq/renderq_dialog.png.
## Files go to user://zz_renderq_* (removed after). The autosave is never named.

var fails := 0
const PICKS := ["res://scenes/combo3.json", "res://scenes/walk_bat.json", "res://scenes/thrust.json"]
const ALONE := "user://zz_renderq_alone"
const OUT := "user://zz_renderq_out"
const UI_OUT := "user://zz_renderq_ui"
const SRC := "user://zz_renderq_src"
const SHOT_DIR := "C:/Temp/claude/renderq"
const SHOT := SHOT_DIR + "/renderq_dialog.png"


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


## the seconds a log line ends with: "... [0.42 s]" -> 0.42 (-1 when the line has no time)
func secs_of(line: String) -> float:
	var i := line.rfind("[")
	if i < 0 or not line.ends_with(" s]"):
		return -1.0
	return line.substr(i + 1).trim_suffix(" s]").to_float()


func _init() -> void:
	clean(ALONE)
	clean(OUT)
	clean(UI_OUT)
	clean(SRC)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ALONE))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame

	# reference for (2): combo3 exported through the app's own Export .glb road
	m._load_scene("res://scenes/combo3.json")
	var app_glb: String = m._export_glb(ALONE)
	var app_sha := FileAccess.get_sha256(app_glb)

	# the open scene: combo3, measured before the queue runs
	m._load_scene("res://scenes/combo3.json")
	var open_file_before := FileAccess.get_sha256("res://scenes/combo3.json")
	var open_state_before := JSON.stringify(m.S.to_dict(m.B, true))

	# (1)-(4): 3 jobs, 3 formats
	var jobs := [RenderQueue.job(PICKS[0], "glb"), RenderQueue.job(PICKS[1], "bvh"), RenderQueue.job(PICKS[2], "fbx")]
	var res: Dictionary = RenderQueue.run(jobs, OUT)
	print("     summary:\n" + "\n".join(res["lines"]))
	ok(int(res["done"]) == 3 and (res["failed"] as Array).is_empty(), "(1) 3 jobs finish: %d done, %d failed" % [res["done"], (res["failed"] as Array).size()])
	var files: Array = res["files"]
	var big := 0
	for f in files:
		if FileAccess.get_file_as_bytes(String(f)).size() > 1000:
			big += 1
	ok(files.size() == 3 and big == 3, "(1) 3 files on disk, each over 1000 bytes (%d of 3)" % big)

	var glb := String(files[0])
	ok(glb.get_file() == "combo3.glb" and FileAccess.get_sha256(glb) == app_sha, "(2) combo3.glb is byte-identical to the app's Export .glb (sha256 %s)" % app_sha.left(16))
	var bvh_head := FileAccess.get_file_as_string(String(files[1])).left(9)
	ok(String(files[1]).ends_with(".bvh") and bvh_head == "HIERARCHY", "(3) walk_bat.bvh starts with HIERARCHY (%s)" % bvh_head)
	var fbx_head := FileAccess.get_file_as_bytes(String(files[2])).slice(0, 12).get_string_from_ascii()
	ok(String(files[2]).ends_with(".fbx") and fbx_head == "Kaydara FBX ", "(3) thrust.fbx starts with 'Kaydara FBX' (%s)" % fbx_head)

	var times_ok := 0
	var secs_match := 0
	var line_idx := 1
	for r in res["results"]:
		var line := String((r as Dictionary)["line"])
		var s := secs_of(line)
		if s > 0.0 and s < 120.0:
			times_ok += 1
		if absf(s - float((r as Dictionary)["secs"])) < 0.01:
			secs_match += 1
		print("     job %d: %s" % [line_idx, line])
		line_idx += 1
	ok(times_ok == 3, "(4) each of the 3 log lines ends with a time above 0 and below 120 s (%d of 3)" % times_ok)
	ok(secs_match == 3, "(4) each logged time equals the job's measured time within 0.01 s (%d of 3)" % secs_match)

	# (5) a corrupt scene in the middle: named, timed, and the jobs after it still land
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SRC))
	var f1 := FileAccess.open(SRC + "/corrupt.json", FileAccess.WRITE)
	f1.store_string("{ this is not json")
	f1.close()
	var r5: Dictionary = RenderQueue.run([RenderQueue.job("res://scenes/thrust.json", "bvh"), RenderQueue.job(SRC + "/corrupt.json", "bvh"),
		RenderQueue.job("res://scenes/walk_bat.json", "bvh")], OUT + "_mid")
	var lines5 := "\n".join(r5["lines"])
	print("     summary:\n" + lines5)
	ok(int(r5["done"]) == 2 and (r5["failed"] as Array).size() == 1, "(5) corrupt in the middle: %d done, %d failed" % [r5["done"], (r5["failed"] as Array).size()])
	var bad_line := String((r5["results"] as Array)[1]["line"])
	ok(bad_line.contains("corrupt.json is not a scene file") and secs_of(bad_line) >= 0.0, "(5) the failure is named and carries its time: %s" % bad_line.strip_edges())
	var names5 := []
	for f in r5["files"]:
		names5.append(String(f).get_file())
	ok(names5 == ["thrust.bvh", "walk_bat.bvh"], "(5) the jobs after it land, in queue order: %s" % [names5])

	# (6) the open scene did not move
	ok(FileAccess.get_sha256("res://scenes/combo3.json") == open_file_before, "(6) the open scene's file is byte-identical after the queue")
	ok(JSON.stringify(m.S.to_dict(m.B, true)) == open_state_before, "(6) the open scene's state is identical after the queue")

	# (7) the batch dialog through Export...: tick 3, run
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	ui.open_batch()
	var bd: BatchDialog = ui.batch_ui
	await process_frame
	for pk in bd.picks:
		(pk[0] as CheckBox).button_pressed = PICKS.has(pk[1])
	bd.ui_dir.text = UI_OUT
	await bd._on_run()
	var sl := bd.ui_summary.text.split("\n")
	print("     dialog summary:\n" + bd.ui_summary.text)
	ok(sl.size() == 4 and sl[0].begins_with("batch: 3 done, 0 failed"), "(7) the dialog's summary: %s" % sl[0])
	var timed := 0
	for i in range(1, sl.size()):
		if secs_of(sl[i]) > 0.0:
			timed += 1
	ok(timed == 3, "(7) each of the 3 job lines in the dialog has a time (%d of 3)" % timed)
	ok(FileAccess.file_exists(ProjectSettings.globalize_path(UI_OUT) + "/combo3.glb"), "(7) the dialog run wrote combo3.glb into its folder")

	# (8) the panel, as the person sees it
	bd.dlg.popup_centered(Vector2i(680, 700))
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(SHOT)
	ok(err == OK, "(8) screenshot saved to %s (%s)" % [SHOT, error_string(err)])

	m.export_ui.batch_ui.dlg.hide()
	clean(ALONE)
	clean(OUT)
	clean(OUT + "_mid")
	clean(UI_OUT)
	clean(SRC)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
