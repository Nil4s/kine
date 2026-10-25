## godot --path . --position 3000,3000 -s tests/walk_vid_beginner_test.gd   (BEGINNER WALK-THROUGH, VIDEO -> ANIMATION, EASY mode, real clicks)
## Eight goals a non-technical person would try: find "Copy a video", pick a file, watch progress, look at the result, trim,
## smooth, add a typed move after it, save the video, and then a second video during the first / a cancel mid-way.
## Every press is a real mouse click on a button or a menu row. The OS file dialog cannot be clicked from here: when the
## picker is a native dialog, the driver picks the file by emitting its file_selected signal (the same call its OK makes).
## A goal the UI does not offer is reported as NOT DONE with what was visible; nothing is worked around.
## Screenshots go to C:/Temp/claude/walkvid/ ; the log is printed to stdout. The AI video button is NEVER pressed.
## Only our own fixtures: tests/data/see_video_crop_small.mp4 and C:/Temp/claude/kine_batch_v2test/combat/*/video.mp4.
## The Easy settings file is the test's own (EasyMode.start_fresh). Files this run saves are deleted at the end.
extends SceneTree

const OUT := "C:/Temp/claude/walkvid/"
const VID1 := "C:/Users/Nick/Desktop/poser/.claude/worktrees/w4-easyvidwalk/tests/data/see_video_crop_small.mp4"
const VID2 := "C:/Temp/claude/kine_batch_v2test/combat/cmb01_jab/video.mp4"
const VID3 := "C:/Temp/claude/kine_batch_v2test/combat/cmb02_cross/video.mp4"
const WIP := "res://scenes/_wip"

var made_dirs: Array = []   # playblast folders this run saved (removed at the end)
var m: Node
var n_shot := 0
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var wip_before: Array = []


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):   # INTERNAL children too: a dialog's button row is internal
		walk(c, out)
	return out


func visible_nodes() -> Array:
	var out := []
	for n in walk(root, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in visible_nodes():
		if n is Button:
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		var t := text_of(b)
		if t == txt or (prefix and t.begins_with(txt)):
			return b
	return null


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		var t := text_of(b)
		if t != "":
			out.append(t)
	return str(out)


func visible_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return str(out)


## the visible label whose text starts with one of these words (the status line, the progress line)
func label_with(words: Array) -> String:
	for n in visible_nodes():
		if n is Label:
			var t := (n as Label).text.strip_edges()
			for w in words:
				if t.begins_with(w):
					return t
	return ""


func mouse_btn(down: bool, p: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


func hit_name(p: Vector2) -> String:
	var h := get_root().get_viewport().gui_get_hovered_control()
	return "none" if h == null else str(h.name) + " (" + h.get_class() + ")"


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var r := c.get_global_rect()
	var w := c.get_window()
	if w != null and w != get_root():
		r.position += Vector2(w.position)
	var p := r.get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name(p)])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return inside


## a click on the first visible button with these words (the words a beginner reads on it)
func click_text(txt: String, prefix := false) -> bool:
	var b := find_btn(txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s' | buttons: %s" % [txt, btn_names()])
		return false
	clicks += 1
	say("   click '%s' (tooltip: %s)" % [text_of(b), b.tooltip_text])
	return await click_ctl(b)


## a click on one row of a popup menu (Easy's More list): the row's place in the list
func click_menu_item(menu: PopupMenu, txt: String) -> bool:
	if menu == null or not menu.visible:
		say("   NOT VISIBLE: the menu is not open (wanted '%s')" % txt)
		return false
	var idx := -1
	var items := []
	for i in menu.item_count:
		items.append(menu.get_item_text(i))
		if menu.get_item_text(i) == txt:
			idx = i
	if idx < 0:
		say("   NOT VISIBLE: the menu has %s, not '%s'" % [str(items), txt])
		return false
	clicks += 1
	var pos := Vector2(menu.position)
	var sz := Vector2(menu.size)
	var rowh := sz.y / float(menu.item_count)
	var p := Vector2(pos.x + sz.x * 0.5, pos.y + (idx + 0.5) * rowh)
	say("   click menu row '%s' (of %s)" % [txt, str(items)])
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return true


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | cards: %d | playing: %s" % [f, m.S.cards.size(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note: String) -> void:
	say("== END %s: done=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, (Time.get_ticks_msec() - t0) / 1000.0, note])


func card_names() -> Array:
	var out := []
	for c in m.S.cards:
		out.append(str(c.get("name", "?")))
	return out


func box() -> LineEdit:
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with("or type"):
			return n
	return null


## the file picker of Copy a video: a FileDialog child of main (native on Windows: the OS window is not on this capture)
func find_picker() -> FileDialog:
	for i in 180:
		for c in m.get_children():
			if c is FileDialog:
				return c
		await process_frame
	return null


## Easy's picker stands in for the OS dialog: its OK is the file_selected signal with the chosen path
func pick_file(path: String) -> bool:
	var fd := await find_picker()
	if fd == null:
		say("   NOT VISIBLE: no file dialog appeared after Copy a video")
		return false
	say("   file dialog: visible=%s native=%s title='%s' filters=%s" % [str(fd.visible), str(fd.use_native_dialog), fd.title, str(fd.filters)])
	if fd.visible:
		await shot("file_dialog")
	say("   (driver) OK with file: %s" % path)
	fd.file_selected.emit(path)
	await idle(4)
	return true


func copy_flow(path: String) -> bool:
	var a := await click_text("More")
	if not a:
		return false
	var b := await click_menu_item(m.easy._more, "Copy a video")
	if not b:
		return false
	return await pick_file(path)


func _init() -> void:
	EasyMode.start_fresh = true
	DirAccess.make_dir_recursive_absolute(OUT)
	wip_before = list_wip()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	await shot("00_start")

	# 1. FIND HOW TO TURN A VIDEO INTO MOVES
	begin_goal("1 find: where is 'turn my video into moves'?")
	var g1a := await click_text("More")
	var g1b := await click_menu_item(m.easy._more, "Copy a video")
	var fd1 := await find_picker()
	await shot("01_after_find")
	var g1 := g1a and g1b and fd1 != null
	end_goal(g1, "(copy route: More > Copy a video, then the picker)")

	# 2. PICK THE VIDEO AND WATCH THE PROGRESS (the copy runs to its end here)
	begin_goal("2 pick a video; watch progress; how long")
	var t_start := Time.get_ticks_msec()
	var fd2 := await find_picker()
	if fd2 == null:
		say("   NOT VISIBLE: no file dialog (goal 1 found none)")
	else:
		say("   file dialog: visible=%s native=%s title='%s' filters=%s" % [str(fd2.visible), str(fd2.use_native_dialog), fd2.title, str(fd2.filters)])
		if fd2.visible:
			await shot("02_file_dialog")
		say("   (driver) OK pressed with the file: %s" % VID1)
		fd2.file_selected.emit(VID1)
		await idle(4)
	var seen := []
	var shot_mid := false
	var shot_fit := false
	var t_track_end := -1
	var cancel_seen := false
	var bar_seen := false
	var last := ""
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 900000:
		await process_frame
		var lab := label_with(["Reading your video", "Fitting the moves", "Cancelled", "Stopped", "Couldn't", "The video", "That video", "Copied"])
		if lab != "" and lab != last:
			last = lab
			seen.append("%.1fs: %s" % [(Time.get_ticks_msec() - t_start) / 1000.0, lab])
		var cb := find_btn("Cancel")
		if cb != null:
			cancel_seen = true
		if m._imp_bar != null and (m._imp_bar as Control).is_visible_in_tree():
			bar_seen = true
		if not shot_mid and lab.begins_with("Reading your video:") and lab.contains("%"):
			var pct := lab.get_slice(":", 1).strip_edges().trim_suffix("%").strip_edges().to_int()
			if pct >= 40:
				await shot("02_progress_reading")
				shot_mid = true
		if not shot_fit and lab.begins_with("Fitting"):
			await shot("03_progress_fitting")
			shot_fit = true
		if t_track_end < 0 and m.easy.home._vid_busy and m._video_pid < 0 and m._imp_busy():
			t_track_end = Time.get_ticks_msec() - t_start
		if not m.easy.home._vid_busy:
			break
	var t_total := (Time.get_ticks_msec() - t_start) / 1000.0
	await idle(6)
	await shot("02b_after_copy")
	for s in seen:
		say("   progress line: " + str(s))
	var landed: bool = not m.S.cards.is_empty() and not m.easy.home._vid_busy
	say("   cancel button seen: %s | import bar seen: %s | track->fit at: %s" % [str(cancel_seen), str(bar_seen), str(t_track_end)])
	say("   copy took %.1f s in total | cards after: %d" % [t_total, m.S.cards.size()])
	end_goal(landed and cancel_seen, "(landed: %s, cards: %s)" % [str(landed), str(card_names())])

	# 3. THE RESULT: PLAYS? LOOKS LIKE THE VIDEO? JITTER?
	begin_goal("3 result: does it play, does it look like the video, jitter")
	var playing := await wait_playing()
	await shot("04_result_playing")
	if m.playing:
		m._toggle_play()
		await idle(4)
	var L: float = m.S.length()
	var fr := [0.25, 0.5, 0.75]
	for i in fr.size():
		m.playhead = L * float(fr[i])
		var ps3 = m._ps()
		ps3.apply(m.B, ps3.play_t(m.playhead))
		await idle(5)
		var f := "%slook_body_%d.png" % [OUT, i + 1]
		root.get_texture().get_image().save_png(f)
		say("   LOOK body at %.0f%% of the clip (%.2f s): %s" % [fr[i] * 100.0, L * float(fr[i]), f])
	# jitter: the hand and the foot centres every 1/30 s
	var hp := []
	var fp := []
	var nS := int(ceil(L * 30.0))
	for i in nS:
		m.playhead = float(i) / 30.0
		var ps4 = m._ps()
		ps4.apply(m.B, ps4.play_t(m.playhead))
		await idle(1)
		var hc: Array = m.B.cap("hand_r")
		var fc: Array = m.B.cap("foot_r")
		hp.append(((hc[0] + hc[1]) * 0.5) as Vector3)
		fp.append(((fc[0] + fc[1]) * 0.5) as Vector3)
	var sp := []
	var spf := []
	var tot := 0.0
	for i in range(1, hp.size()):
		var d: float = (hp[i] as Vector3).distance_to(hp[i - 1])
		sp.append(d)
		tot += d
		spf.append((fp[i] as Vector3).distance_to(fp[i - 1]))
	var mean_sp := tot / maxf(1.0, float(sp.size()))
	var spikes := 0
	for d in sp:
		if float(d) > 4.0 * mean_sp and float(d) > 0.02:
			spikes += 1
	var moved := 0.0
	for d in sp:
		moved = maxf(moved, float(d))
	say("   samples %d at 30/s | hand_r mean step %.4f m, max step %.4f m, spikes (>4x mean) %d | foot_r max step %.4f m" % [hp.size(), mean_sp, moved, spikes, (spf.max() if spf.size() > 0 else 0.0)])
	m.playhead = 0.0
	var ps5 = m._ps()
	ps5.apply(m.B, ps5.play_t(0.0))
	await idle(3)
	var ok3 := playing and hp.size() > 2 and moved > 0.0
	end_goal(ok3, "(playing: %s, spikes: %d, motion seen: %s)" % [str(playing), spikes, str(moved > 0.0)])

	# 4. TRIM: KEEP ONLY THE GOOD PART
	begin_goal("4 keep only the good part (trim)")
	var trim_found := []
	for b in visible_buttons():
		var t := text_of(b).to_lower()
		for w in ["trim", "cut", "keep", "shorten", "start", "end", "remove", "delete", "crop"]:
			if t.contains(w):
				trim_found.append(text_of(b))
				break
	say("   buttons that could trim: %s | all buttons: %s" % [str(trim_found), btn_names()])
	await shot("05_trim_look")
	end_goal(not trim_found.is_empty(), "(no trim control was offered in Easy: nothing to click)")

	# 5. SMOOTHER / CLEANER
	begin_goal("5 make it smoother or cleaner")
	var smooth_found := []
	for b in visible_buttons():
		var t := text_of(b).to_lower()
		for w in ["smooth", "steady", "clean", "jitter", "shake", "stabil", "calm", "tidy", "less"]:
			if t.contains(w):
				smooth_found.append(text_of(b))
				break
	var tips := []
	for w in ["Faster", "Slower", "Bigger", "Smaller", "Again"]:
		var bb := find_btn(w)
		if bb != null:
			tips.append("%s = '%s'" % [w, bb.tooltip_text])
	say("   smoothing controls: %s | the tweak buttons present: %s" % [str(smooth_found), str(tips)])
	await shot("06_smooth_look")
	end_goal(not smooth_found.is_empty(), "(Easy's tweaks are Faster, Slower, Bigger, Smaller: none of them smooths the motion)")

	# 6. A TYPED MOVE AFTER IT: 'then wave'
	begin_goal("6 combine: then wave (typed after the copied clip)")
	var n6: int = m.S.cards.size()
	var before6 := card_names()
	var chg := await click_text("Change it")
	await shot("07_change_it")
	var bx := box()
	var added := false
	if bx != null:
		clicks += 1
		await click_ctl(bx)
		var ab := find_btn("Add after")
		say("   'Add after' choice on screen: %s | tooltip: %s" % [str(ab != null), (ab.tooltip_text if ab != null else "")])
		await type_text("wave", true)
		added = await wait_for(func(): return m.S.cards.size() > n6 and not m.easy.home._gen_on, 1800)
		await idle(30)
	else:
		say("   NOT VISIBLE: no text box after Change it")
	await shot("08_then_wave")
	var after6 := card_names()
	var prefix_kept := after6.size() >= before6.size() and after6.slice(0, before6.size()) == before6
	say("   cards before %d -> after %d | first cards kept: %s | label: %s" % [before6.size(), after6.size(), str(prefix_kept), label_with(["Made", "Wave", "Added", "Could", "Stopped"])])
	end_goal(added and prefix_kept, "(wave after the copy: %s)" % str(after6.slice(before6.size())))

	# 7. SAVE THE VIDEO AND FIND THE FILE
	begin_goal("7 save the video; find the file")
	var sv := await click_text("Save video")
	var tws := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tws < 300000:
		await process_frame
	await idle(10)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	var dirp := String(m.easy.home.last_video.get("dir", ""))
	var exists := mp4 != "" and FileAccess.file_exists(mp4)
	if dirp != "":
		made_dirs.append(dirp)
	say("   save took %.1f s | mp4: %s (exists %s) | frames dir: %s" % [(Time.get_ticks_msec() - tws) / 1000.0, mp4, str(exists), dirp])
	await shot("09_video_saved")
	var toast := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "" and (n as Label).text.length() > 14:
			toast += " || " + (n as Label).text
	say("   toast/long text: " + toast)
	end_goal(sv and exists, "(found it: the toast names the file and says where it is)")

	# 8. A SECOND VIDEO WHILE THE FIRST IS PROCESSING; THEN A CANCEL MID-WAY
	begin_goal("8 second video during the first; cancel mid-way")
	var before8 := card_names()
	var path8 := String(m.scene_path)
	var ca := await click_text("More")
	var cb2 := await click_menu_item(m.easy._more, "Copy a video")
	var fd8 := await find_picker()
	if fd8 != null:
		say("   picker opened for the first copy")
		fd8.file_selected.emit(VID2)
		await idle(4)
	var tracking := false
	var tw8 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw8 < 120000:
		await process_frame
		if m._video_pid >= 0 or m._imp_busy():
			tracking = true
			break
	await idle(30)
	say("   first copy running: %s | words: %s" % [str(tracking), label_with(["Reading", "Fitting"])])
	await shot("10_second_during_first")
	var ca2 := await click_text("More")
	var cb3 := await click_menu_item(m.easy._more, "Copy a video")
	await idle(20)
	var said2 := label_with(["A video is already", "Reading", "Fitting"])
	var second_picker = await find_picker()
	say("   second copy request answered with: '%s' | a second picker opened: %s" % [said2, str(second_picker != null)])
	await shot("11_second_refused")
	var cancelled := false
	var cn := find_btn("Cancel")
	if tracking and cn != null and m.easy.home._vid_busy:
		clicks += 1
		say("   click 'Cancel' (the first copy's own Cancel, mid-way)")
		cancelled = await click_ctl(cn)
	var tw9 := Time.get_ticks_msec()
	while m.easy.home._vid_busy and Time.get_ticks_msec() - tw9 < 300000:
		await process_frame
	await idle(10)
	var msg := label_with(["Stopped", "Cancelled", "Copied", "Couldn't", "Made", "Reading", "Fitting"])
	var same8 := card_names() == before8 and String(m.scene_path) == path8
	say("   after the cancel: '%s' | scene unchanged: %s | cards %d" % [msg, str(same8), m.S.cards.size()])
	await shot("12_after_cancel")
	# recovery: a new copy works after the cancel
	var rec := await copy_flow(VID3)
	var tw10 := Time.get_ticks_msec()
	while m.easy.home._vid_busy and Time.get_ticks_msec() - tw10 < 900000:
		await process_frame
	await idle(10)
	var rec_ok: bool = not m.S.cards.is_empty() and String(m.scene_path) != path8
	say("   second video after the cancel: landed %s | '%s' | cards %d" % [str(rec_ok), label_with(["Copied", "Couldn't", "Made"]), m.S.cards.size()])
	await shot("13_recovered")
	end_goal(tracking and cancelled and same8 and rec_ok, "(first cancelled mid-way: %s, scene kept: %s, next copy worked: %s)" % [str(cancelled), str(same8), str(rec_ok)])

	# CLEAN UP: the run's own playblast folder and scene files; the video process it started (only its own PID)
	for d in made_dirs:
		if DirAccess.dir_exists_absolute(str(d)):
			_rm_tree(str(d))
	var mp4_done := String(m.easy.home.last_video.get("mp4", ""))
	if mp4_done != "" and FileAccess.file_exists(mp4_done):
		DirAccess.remove_absolute(mp4_done)
		say("   removed the run's saved video: " + mp4_done)
	for f in list_wip():
		if not wip_before.has(f):
			DirAccess.remove_absolute(WIP + "/" + f)
			say("   removed scene file this run made: " + f)
	if m._video_pid >= 0:
		OS.kill(m._video_pid)
	say("\nlast video: " + str(m.easy.home.last_video))
	m.queue_free()
	quit(0)


func wait_playing(limit := 240) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


func wait_for(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


func type_text(s: String, enter := false) -> void:
	for c in s:
		var kd := InputEventKey.new()
		kd.keycode = (KEY_SPACE if c == " " else c.to_upper().unicode_at(0)) as Key
		kd.unicode = c.unicode_at(0)
		kd.pressed = true
		root.push_input(kd)
		await process_frame
		var ku := InputEventKey.new()
		ku.keycode = kd.keycode
		ku.unicode = kd.unicode
		ku.pressed = false
		root.push_input(ku)
		await process_frame
	if enter:
		var ke := InputEventKey.new()
		ke.keycode = KEY_ENTER
		ke.pressed = true
		root.push_input(ke)
		await process_frame
		ke.pressed = false
		root.push_input(ke)
		await process_frame


func list_wip() -> Array:
	var out := []
	var da := DirAccess.open(WIP)
	if da == null:
		return out
	for f in da.get_files():
		out.append(f)
	return out


func _rm_tree(p: String) -> void:
	var da := DirAccess.open(p)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(p + "/" + f)
	for d in da.get_directories():
		_rm_tree(p + "/" + d)
	DirAccess.remove_absolute(p)
	say("   removed the run's saved folder: " + p)
