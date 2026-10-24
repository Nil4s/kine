## godot --path . -s tests/easysave_test.gd     (EASY SAVE VIDEO, "monkey brain easy": the progress while it saves, the plain done message, Cancel, the empty-scene hint; needs a window: it renders)
## BARS (stated before measuring):
##  1 while a clip saves in Easy, the progress panel is up: its "Saving video..." line, its bar and a Cancel button
##  2 the done message is plain: "Your video is saved: <file name>" with a "Show it" button; the file it names exists
##    and is > 0 bytes (the .mp4 when ffmpeg is found; else the message says the video could not be made and the frames are kept)
##  3 Cancel part-way (the progress says 3 or more frames): the save stops, no .mp4 and no folder are left in the test folder,
##    the status line says "cancelled" and the done message does not show
##  4 an empty scene (no move): Save video says "Pick a move first", renders nothing (no progress, no folder, no file), and
##    the message has no "Show it" button
##  5 every file this test makes is under user://easysave_<pid> and is deleted at the end (the real Videos/Kine is never written)
## The test folder is a test's user:// folder (EasyHome.video_root); the real default is the user's Videos folder, Kine/.
extends SceneTree

var fails := 0
var m: Node
var base := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 1) -> void:
	for i in n:
		await process_frame


## the progress line while the panel is up and the save runs ("" when it is not shown)
func progress_text() -> String:
	if m._pb_layer != null and m._pb_layer.visible and m._pb_busy:
		return String(m._pb_label.text)
	return ""


## the number of files and folders under a user:// folder (0 when it does not exist)
func entries_under(dir: String) -> int:
	var g := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(g):
		return 0
	var n := 0
	for sub in DirAccess.get_directories_at(g):
		n += 1 + entries_under(dir.path_join(sub))
	n += DirAccess.get_files_at(g).size()
	return n


func _init() -> void:
	base = "user://easysave_%d" % OS.get_process_id()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(12)
	m.easy.set_on(true, false)
	await idle(3)
	var home: EasyHome = m.easy.home

	# 4 first: the empty scene (no clip yet): the hint, and nothing rendered
	m._new_scene()
	await idle(2)
	home.video_root = base + "/empty"
	home.last_video = {}
	await home.save_video()
	await idle(2)
	ok(home._toast.visible and home._toast_text.text.begins_with("Pick a move first"),
		"4. Save video on an empty scene says 'Pick a move first' (shown: '%s')" % home._toast_text.text)
	ok(not home._toast_show.visible, "4. the empty-scene hint has no 'Show it' button")
	ok(progress_text() == "" and not m._pb_busy and home.last_video.is_empty(), "4. the empty scene renders nothing: no progress, no result")
	ok(entries_under(base + "/empty") == 0, "4. the empty scene writes no folder and no file")
	home._toast.visible = false

	# a move to save: Walk-free, the punch card (the same clip the playblast test times)
	m._new_scene()
	await idle(2)
	home.card(3)
	var tw := Time.get_ticks_msec()
	while not m.playing and Time.get_ticks_msec() - tw < 60000:
		await process_frame
	await idle(3)

	# 1 and 2: a save runs to the end; the progress is up while it renders; the done message names the file
	home.video_root = base + "/ok"
	home.last_video = {}
	home.save_video()   # not awaited: it runs frame by frame beside this loop
	var seen := ""
	var cancel_seen := false
	var bar_seen := false
	var t0 := Time.get_ticks_msec()
	await idle(1)
	while m._pb_busy and Time.get_ticks_msec() - t0 < 120000:
		var txt := progress_text()
		if txt != "":
			seen = txt
			cancel_seen = cancel_seen or m._pb_cancel_btn.is_visible_in_tree()
			bar_seen = bar_seen or m._pb_bar.visible
		await process_frame
	await idle(2)
	ok(seen.begins_with("Saving video... ") and cancel_seen and bar_seen,
		"1. while it renders: the progress line reads '%s', the bar and Cancel are shown" % seen)

	var mp4 := String(home.last_video.get("mp4", ""))
	var ff := PlayblastExport.find_ffmpeg()
	var toast := String(home._toast_text.text)
	if ff != "" and mp4 != "":
		var size := FileAccess.get_file_as_bytes(mp4).size() if FileAccess.file_exists(mp4) else 0
		ok(size > 0, "2. the video the message names exists and is > 0 bytes (%d bytes: %s)" % [size, mp4.get_file()])
		ok(home._toast.visible and toast == "Your video is saved: %s" % mp4.get_file(),
			"2. the done message reads 'Your video is saved: <file name>': '%s'" % toast)
	else:
		ok(String(home.last_video.get("dir", "")) != "" and home._toast.visible and toast.begins_with("Could not make the video here"),
			"2. no ffmpeg: the message says the video could not be made and the frames are kept: '%s'" % toast)
		print("info: no ffmpeg on this computer, so no .mp4 was made (frames %s)" % String(home.last_video.get("dir", "")))
	ok(home._toast_show.visible and home._toast_show.text == "Show it", "2. the done message has a 'Show it' button")
	ok(String(home.last_video.get("dir", "")) != "" and home.last_video.get("dir", "").begins_with(ProjectSettings.globalize_path(base)),
		"5. the video is written under the test folder only")

	# 3. Cancel part-way: a second save, cancelled once the progress says 3 frames are done
	home.video_root = base + "/cancel"
	home.last_video = {}
	home._toast.visible = false
	home.save_video()
	var pressed := false
	t0 = Time.get_ticks_msec()
	while m._pb_busy and Time.get_ticks_msec() - t0 < 120000:
		var txt := progress_text()
		if not pressed and txt.begins_with("Saving video... ") and txt.contains(" of "):
			if int(txt.split(" ")[2]) >= 3 and not m._pb_cancel:
				m._pb_cancel_btn.pressed.emit()
				pressed = true
		await process_frame
	await idle(2)
	ok(pressed, "3. Cancel was pressed while the progress showed 3 or more frames")
	ok(home.last_video.is_empty(), "3. a cancelled save gives no result")
	ok(entries_under(base + "/cancel") == 0, "3. no folder and no .mp4 are left after Cancel (%d entries)" % entries_under(base + "/cancel"))
	ok(m.ui_status.text.contains("cancelled") and not (home._toast.visible and home._toast_text.text.begins_with("Your video is saved")),
		"3. the status line says it was cancelled: '%s'" % m.ui_status.text.left(70))

	# 5. the test folder is deleted: the files it made are not kept
	PlayblastExport.rm_tree(ProjectSettings.globalize_path(base))
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)), "5. the test folder is deleted at the end")
	print("EASYSAVE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
