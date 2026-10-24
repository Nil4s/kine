extends SceneTree
## A MOVE FROM WORDS (scripts/gen_move.gd, main's "Video: make a move from words"). No ComfyUI here: a stand-in for
## tools/gen_video.py (tests/py/gen_video_stub.py) copies a clip the real one made (tests/fixtures/gen_hammer.webm, Wan 2.1)
## to the out path; the tracking and the import after it are the real ones.
##   1 too few words are refused with an example, nothing started
##   2 the words -> the clip -> tracked -> a NEW scene opened in scenes/_wip with cards (removed again here)
##   3 ComfyUI down (the stand-in makes nothing): one line says how to start it, nothing opens
##   4 the command is in the palette
##   5 Expert's call carries NO fast setting (no --steps / --width / --height): tools/gen_video.py makes its default, 30 steps at 832x480
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var dir := OS.get_user_data_dir().path_join("gen_move_test_%d" % OS.get_process_id())
	m.gen_move.out_dir = dir
	m.gen_move.tool = "res://tests/py/gen_video_stub.py"

	# (1)
	m._gen_start("hit")
	ok(not m.gen_move.busy() and String(m.ui_status.text).contains("few words"), "(1) too few words: refused, nothing started: %s" % m.ui_status.text)

	# (2)
	OS.set_environment("GEN_STUB_SRC", ProjectSettings.globalize_path("res://tests/fixtures/gen_hammer.webm"))
	var args_log: String = dir.path_join("expert_args.log")
	OS.set_environment("GEN_STUB_ARGS", args_log)
	var before: String = m.scene_path
	m._gen_start("swings a sledgehammer down onto the ground")
	ok(m.gen_move.busy() or FileAccess.file_exists(m.gen_move.out), "(2) the clip is being made")
	var t_end := Time.get_ticks_msec() + 240000
	var opened := ""
	while Time.get_ticks_msec() < t_end:
		await idle(2)
		var sp: String = m.scene_path
		if sp != before and sp.begins_with("res://scenes/_wip/"):
			opened = sp
			break
	ok(opened != "" and m.S.cards.size() >= 3 and m.S.length() > 4.0, "(2) tracked and opened as a new scene: %s, %d cards, %.1f s" % [opened, m.S.cards.size(), m.S.length()])
	OS.set_environment("GEN_STUB_ARGS", "")
	# (5) Expert's call: no steps or size flags, so gen_video.py's defaults (30 steps, 832x480) apply, as before Easy's fast setting
	var ex_calls := []
	if FileAccess.file_exists(args_log):
		for l in FileAccess.get_file_as_string(args_log).split("\n", false):
			ex_calls.append(JSON.parse_string(l))
	var ex_argv: Array = ex_calls[0] if ex_calls.size() == 1 and ex_calls[0] is Array else []
	ok(ex_argv.size() > 0 and not ex_argv.has("--steps") and not ex_argv.has("--width") and not ex_argv.has("--height"),
		"(5) Expert's call carries the default (no --steps / --width / --height): %s" % str(ex_argv))
	if opened != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(opened))

	# (3)
	OS.set_environment("GEN_STUB_SRC", "")
	var sp0: String = m.scene_path
	m._gen_start("throws a spear forward with the right arm")
	t_end = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < t_end and m.gen_move.pid >= 0:
		await idle(2)
	await idle(4)
	ok(m.gen_move.pid < 0 and not FileAccess.file_exists(m.gen_move.out) and m.scene_path == sp0 and String(m.ui_status.text).contains("ComfyUI"), "(3) ComfyUI down: nothing opens, it says: %s" % m.ui_status.text)

	# (4)
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	ok(src.contains('add.call("Video: make a move from words'), "(4) the palette has Video: make a move from words")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	print("GEN MOVE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
