## godot --path . -s tests/easyvid_test.gd     (COPY A VIDEO in Easy, "monkey brain easy"; needs a window)
## BARS (stated before measuring):
##  1 the More menu of Easy has "Copy a video", and the bar still has its 7 buttons (no 8th)
##  2 copying the clip (tests/fixtures/fps16_hammer_2s.webm, the video_import_test clip) in Easy: at least 2 cards, and the clip plays (playing)
##  3 a missing file and a garbage file (text named .mp4) each give one plain sentence on the status line, the exact words
##    Easy shows, and no script error; the scene does not change
##  4 one Undo after the copy gives back the card count the scene had before it
##  5 the progress sentence ("Reading the video: N %") was on the status line while the tracker ran (printed, not a bar)
##  6 Cancel while the tracker reads the clip (the bar's button, the progress file seen first): the tracker process is gone,
##    no partial file is left (the .json nor the .progress), the card count and the undo count are as before, the scene is
##    the same, the status line says "Stopped. Nothing was changed.", and the bar is hidden
##  7 a second copy after that cancel still succeeds (>= 2 cards, playing)
extends SceneTree

const CLIP := "res://tests/fixtures/fps16_hammer_2s.webm"
const MISSING := "C:/zz_no_such_video_easyvid.mp4"
const NO_PERSON := "No person found in the video. Try a clip where the whole body is visible."
const NOT_FOUND := "That video file could not be found. Pick it again with Copy a video."

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 1) -> void:
	for i in n:
		await process_frame


## the copy runs in the background: wait (up to a bound) until Easy says it is over
func wait_copy(limit := 3000) -> bool:
	var seen := false
	for i in limit:
		if String(m.ui_status.text).contains("%"):
			seen = true
		if not m.easy.home._vid_busy:
			return seen
		await process_frame
	return seen


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	var was_size: Vector2i = root.content_scale_size
	var was_mode: int = root.content_scale_mode
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(8)
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(3)
	var home: EasyHome = m.easy.home

	# 1 the More entry, and the bar is still 7 buttons
	ok("Copy a video" in m.easy.more_labels() and m.easy.labels().size() == 7,
		"1 More has \"Copy a video\" (%d entries); the bar has %d buttons (bar 7)" % [m.easy.more_labels().size(), m.easy.labels().size()])

	# 2 the copy: >= 2 cards, the clip plays at once
	var n0: int = m.S.cards.size()
	var clip := ProjectSettings.globalize_path(CLIP)
	home.copy_video_file(clip)
	var saw := await wait_copy()
	var c1: int = m.S.cards.size()
	await idle(3)
	ok(c1 >= 2 and m.playing and home.shown() == "strip" and String(m.ui_status.text).begins_with("Copied"),
		"2 copied %s: %d cards (bar >= 2), playing %s, shown %s, status: \"%s\"" % [CLIP.get_file(), c1, m.playing, home.shown(), m.ui_status.text])
	print("   progress sentence seen on the status line while it ran: %s" % saw)

	# 4 one Undo gives back the count before the copy
	m._undo()
	await idle(3)
	ok(m.S.cards.size() == n0 and c1 != n0, "4 one Undo: %d cards (before the copy: %d)" % [m.S.cards.size(), n0])

	# 3a a missing file
	home.copy_video_file(MISSING)
	await idle(2)
	ok(String(m.ui_status.text) == NOT_FOUND and not home._vid_busy and m.S.cards.size() == n0,
		"3a missing file: \"%s\" (scene %d cards, as before)" % [m.ui_status.text, m.S.cards.size()])

	# 3b a garbage file: text named .mp4 (the tracker finds no person in it)
	var junk := "user://zz_garbage_easyvid.mp4"
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("not a video at all")
	f.close()
	var junk_g := ProjectSettings.globalize_path(junk)
	var path0: String = m.scene_path
	home.copy_video_file(junk_g)
	await wait_copy()
	await idle(2)
	ok(String(m.ui_status.text) == NO_PERSON and not home._vid_busy and m.S.cards.size() == n0 and m.scene_path == path0,
		"3b garbage file: \"%s\" (scene %d cards, as before)" % [m.ui_status.text, m.S.cards.size()])
	DirAccess.remove_absolute(junk_g)

	# 6 cancel while the tracker reads the clip, with the bar's own Cancel button
	var c_before: int = m.S.cards.size()
	var u_before: int = m.undo.size()
	var s_before := String(m.scene_path)
	home.copy_video_file(clip)
	var pid: int = m._video_pid
	var reading := false
	for i in 3000:
		if m._video_pid < 0:
			break
		if FileAccess.file_exists(m._video_prog) and FileAccess.get_file_as_string(m._video_prog).to_float() > 0.0:
			reading = true
			break
		await process_frame
	var was_tracking: bool = m._video_pid >= 0 and reading
	if was_tracking:
		m._imp_cancel_btn.pressed.emit()
	await wait_copy()
	var gone := false
	for i in 300:
		if not OS.is_process_running(pid):
			gone = true
			break
		await process_frame
	await idle(2)
	ok(was_tracking and gone, "6a Cancel while the tracker read the clip (read seen %s, tracker pid %d) and the tracker is no longer running: %s" % [reading, pid, gone])
	ok(not FileAccess.file_exists(m._video_out) and not FileAccess.file_exists(m._video_prog),
		"6b no partial file left (the pose .json and the .progress are removed)")
	ok(m.S.cards.size() == c_before and m.undo.size() == u_before and String(m.scene_path) == s_before,
		"6c scene as before: %d cards (was %d), undo %d (was %d), same scene" % [m.S.cards.size(), c_before, m.undo.size(), u_before])
	ok(String(m.ui_status.text) == "Stopped. Nothing was changed." and (m._imp_panel == null or not m._imp_panel.visible),
		"6d status line: \"%s\", and the bar is hidden" % m.ui_status.text)

	# 7 a second copy after the cancel still succeeds
	home.copy_video_file(clip)
	await wait_copy()
	await idle(3)
	ok(m.S.cards.size() >= 2 and m.playing and String(m.ui_status.text).begins_with("Copied"),
		"7 second copy after the cancel: %d cards, playing %s, status: \"%s\"" % [m.S.cards.size(), m.playing, m.ui_status.text])

	m.easy.set_on(false, false)
	root.content_scale_size = was_size
	root.content_scale_mode = was_mode
	m.queue_free()
	print("EASY VIDEO TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
