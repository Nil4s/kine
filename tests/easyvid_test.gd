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
##  8 the copy's undo step is named "Copied video" (the Undo button's word and the status line after Undo)
##  9 while the tracker reads, the top bar's line and the status line say "Reading your video: N %"
## 10 during the copy the "What should he do?" picker is hidden, and exactly one Cancel is on screen
## 11 a clip with the feet out of frame (cut at the bottom): the tracker loses both legs and the status line says so, once
## 2b a whole-body clip (the fixture) gets no such caution
extends SceneTree

const CLIP := "res://tests/fixtures/fps16_hammer_2s.webm"
const MISSING := "C:/zz_no_such_video_easyvid.mp4"
const NO_PERSON := "Couldn't find a person in this video. Try one where the whole body is in view."
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


## the copy, and the unsaved scene's question (walk-through round) answered Replace: these bars test the copy itself, as before
func copy_replacing(home: EasyHome, path: String) -> void:
	home.copy_video_file(path)
	if home._copy_path != "":
		home.call("copy_choose", "replace")


## the copy with its screen read every frame: the top bar's line and the status line while the tracker reads (the first
## line with a "%"), whether the picker was on screen, and the most visible Cancel buttons seen at once
func watch_copy(path: String) -> Dictionary:
	var w := {"seen": false, "bar": "", "status": "", "picker": false, "cancels": 0}
	var home: EasyHome = m.easy.home
	copy_replacing(home, path)
	for i in 3000:
		if home._vid_busy:
			var st := String(m.ui_status.text)
			if st.contains("%"):
				w["seen"] = true
			if m._video_pid >= 0 and st.contains("%") and String(w["status"]) == "":
				w["status"] = st
				w["bar"] = String(m._imp_lbl.text)
			if home.shown() == "panel":
				w["picker"] = true
			w["cancels"] = maxi(int(w["cancels"]), visible_cancels(root))
		if not home._vid_busy:
			break
		await process_frame
	return w


## the strip's card buttons in card order (the picture button "b_pick" of each card_N)
func strip_buttons() -> Array:
	var rows := []
	for pc in m.ui_cards.get_children():
		if String(pc.name).begins_with("card_"):
			rows.append([int(String(pc.name).trim_prefix("card_")), pc.find_child("b_pick", true, false)])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	return rows.map(func(r): return r[1])


func strip_names() -> Array:
	var out := []
	for nb in strip_buttons():
		out.append(String((nb as Button).text) if nb != null else "")
	return out


## how many cards have no icon on their picture button (missing button or a null icon both count)
func missing_icons() -> int:
	var n := 0
	for nb in strip_buttons():
		if nb == null or (nb as Button).icon == null:
			n += 1
	return n


func visible_cancels(n: Node) -> int:
	var c := 0
	if n is Button and (n as Button).text == "Cancel" and n.is_visible_in_tree():
		c = 1
	for ch in n.get_children():
		c += visible_cancels(ch)
	return c


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

	# 1 the More entry, and the bar is still 7 buttons (+ Redo, the 8th: shown only after an Undo); Copy is not on the bar
	ok("Copy a video" in m.easy.more_labels() and m.easy.labels().size() == 9 and "Redo" in m.easy.labels() and not ("Copy a video" in m.easy.labels()),
		"1 More has \"Copy a video\" (%d entries); the bar has %d buttons (bar 7)" % [m.easy.more_labels().size(), m.easy.labels().size()])

	# 2 the copy: >= 2 cards, the clip plays at once
	var n0: int = m.S.cards.size()
	var clip := ProjectSettings.globalize_path(CLIP)
	var w := await watch_copy(clip)
	var saw: bool = w["seen"]
	var c1: int = m.S.cards.size()
	await idle(3)
	ok(c1 >= 2 and m.playing and home.shown() == "strip" and String(m.ui_status.text).begins_with("Copied"),
		"2 copied %s: %d cards (bar >= 2), playing %s, shown %s, status: \"%s\"" % [CLIP.get_file(), c1, m.playing, home.shown(), m.ui_status.text])
	print("   progress sentence seen on the status line while it ran: %s" % saw)
	ok(not String(m.ui_status.text).contains("outside the video"), "2b whole-body clip: no limb caution on the status line (\"%s\")" % m.ui_status.text)

	# 12 the strip's names after the copy: "Video 1" .. "Video N" in order (the stored names stay v0, v10, ...; walk-through round: plain names)
	var names := strip_names()
	var want_names := []
	for i in m.S.cards.size():
		want_names.append("Video %d" % (i + 1))
	ok(names == want_names and names.size() >= 2,
		"12 strip names after the copy: %s (want Video 1..%d)" % [names, m.S.cards.size()])

	# 13 every card's picture button has an icon (a non-null texture) within 300 frames of the copy
	var missing := -1
	for fr in 300:
		missing = missing_icons()
		if missing == 0:
			break
		await process_frame
	ok(missing == 0, "13 card pictures: %d of %d cards still without an icon after %d frames" % [missing, m.S.cards.size(), 300])

	# 9 the progress words while the tracker read: the top bar and the status line, the same Easy sentence
	var prog_ok := String(w["status"]).begins_with("Reading your video: ") and String(w["status"]).ends_with(" %")
	ok(prog_ok and String(w["bar"]) == String(w["status"]),
		"9 while it read: status \"%s\", top bar \"%s\" (Easy's words, the same line on both)" % [w["status"], w["bar"]])

	# 10 the picker is hidden during the copy, and one Cancel is on screen (the bar's)
	ok(not bool(w["picker"]) and int(w["cancels"]) == 1,
		"10 during the copy: picker shown %s (want hidden), visible Cancel buttons at most %d (want 1)" % [w["picker"], w["cancels"]])

	# 4 one Undo gives back the count before the copy
	m._undo()
	await idle(3)
	ok(m.S.cards.size() == n0 and c1 != n0, "4 one Undo: %d cards (before the copy: %d)" % [m.S.cards.size(), n0])
	ok(String(m.ui_status.text) == "Took back: Copied video", "8 Undo names the copy \"Copied video\": status \"%s\"" % m.ui_status.text)

	# 3a a missing file
	copy_replacing(home, MISSING)
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
	copy_replacing(home, junk_g)
	await wait_copy()
	await idle(2)
	ok(String(m.ui_status.text) == NO_PERSON and not home._vid_busy and m.S.cards.size() == n0 and m.scene_path == path0,
		"3b garbage file: \"%s\" (scene %d cards, as before)" % [m.ui_status.text, m.S.cards.size()])
	DirAccess.remove_absolute(junk_g)

	# 3c a real, decodable clip with an odd size (333x201) and no person in it: the tracker reads it and finds 0 frames, and
	# Easy shows the same plain sentence (no exit code, no stack). Made by ffmpeg into user:// and deleted; skipped if no ffmpeg
	var odd := "user://zz_odd_noperson_easyvid.webm"
	var odd_g := ProjectSettings.globalize_path(odd)
	var fo := []
	var rc_ff := OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "color=c=gray:s=333x201:d=1:r=16",
		"-c:v", "libvpx", "-b:v", "200k", odd_g], fo, true)
	if rc_ff == 0 and FileAccess.file_exists(odd):
		var n3: int = m.S.cards.size()
		var sp3: String = m.scene_path
		copy_replacing(home, odd_g)
		await wait_copy()
		await idle(2)
		ok(String(m.ui_status.text) == NO_PERSON and not home._vid_busy and m.S.cards.size() == n3 and m.scene_path == sp3,
			"3c odd-size clip with no person (333x201 webm): \"%s\" (scene %d cards, as before)" % [m.ui_status.text, m.S.cards.size()])
	else:
		print("skip 3c: ffmpeg could not make the odd-size clip (exit %d)" % rc_ff)
	if FileAccess.file_exists(odd):
		DirAccess.remove_absolute(odd_g)

	# 6 cancel while the tracker reads the clip, with the bar's own Cancel button. A Punch card first: the scene the cancel
	# must leave alone has cards (an empty scene compared 0 with 0)
	home.card(3)
	await idle(20)
	var c_before: int = m.S.cards.size()
	var u_before: int = m.undo.size()
	var s_before := String(m.scene_path)
	copy_replacing(home, clip)
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
	ok(c_before >= 2 and m._imp_panel != null and m._imp_panel.visible and m._imp_cancel_btn.is_visible_in_tree(),
		"6 while the tracker reads: the bar and its Cancel are on screen (the scene has %d cards to keep)" % c_before)
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
	copy_replacing(home, clip)
	await wait_copy()
	await idle(3)
	ok(m.S.cards.size() >= 2 and m.playing and String(m.ui_status.text).begins_with("Copied"),
		"7 second copy after the cancel: %d cards, playing %s, status: \"%s\"" % [m.S.cards.size(), m.playing, m.ui_status.text])

	# 11 a clip with both feet out of frame (the bottom 40 % cut off, made by ffmpeg into user:// and deleted; skipped if no ffmpeg)
	var cut := "user://zz_cut_feet_easyvid.webm"
	var cut_g := ProjectSettings.globalize_path(cut)
	var fcut := []
	var rc_cut := OS.execute("ffmpeg", ["-v", "error", "-y", "-i", ProjectSettings.globalize_path(CLIP), "-vf", "crop=iw:ih*0.6:0:0",
		"-c:v", "libvpx", "-b:v", "400k", cut_g], fcut, true)
	if rc_cut == 0 and FileAccess.file_exists(cut):
		var wc := await watch_copy(cut_g)
		await idle(3)
		var cap := String(m.ui_status.text)
		var head := "Part of him was outside the video, so his "   # the limbs the tracker lost name it: legs, arms, or both
		var tail := " may look wrong: drag it to fix it."
		var at := cap.find(head)
		ok(at > 0 and cap.ends_with(tail) and cap.count(head) == 1 and cap.substr(at).length() > head.length() + tail.length()
			and m.S.cards.size() >= 2 and m.playing,
			"11 feet out of frame: status \"%s\" (want the caution once, after the copy's sentence)" % cap)
		# 13b the same clip's cards (the feet-cut one): every picture gets its icon too, the last card included
		var miss_cut := -1
		for fr in 300:
			miss_cut = missing_icons()
			if miss_cut == 0:
				break
			await process_frame
		ok(miss_cut == 0, "13b feet-cut copy: %d of %d cards without an icon after 300 frames (names %s)" % [miss_cut, m.S.cards.size(), strip_names()])
	else:
		print("skip 11: ffmpeg could not make the cut clip (exit %d)" % rc_cut)
	if FileAccess.file_exists(cut):
		DirAccess.remove_absolute(cut_g)

	m.easy.set_on(false, false)
	root.content_scale_size = was_size
	root.content_scale_mode = was_mode
	m.queue_free()
	print("EASY VIDEO TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
