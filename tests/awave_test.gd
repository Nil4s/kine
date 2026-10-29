extends SceneTree
## godot --path . -s tests/awave_test.gd     (AWAVE: a beginner makes a character wave hello from the start screen, plays it, makes it faster, saves the video)
## Real clicks (root.push_input) at 1280 x 720, from the real start screen. Every dead end is printed in plain words with its press.
## BARS (stated before measuring):
##  1 start     the ANIMATION card, then the Wave picture: one wave clip is built by real clicks (status "Made ...", playing,
##              no weapon in his hand: a hello has no sword)
##  2 play      Play / Stop stops it, a second press plays it again (the bar's button, real clicks)
##  3 faster    the strip's Faster button (one click) makes the clip shorter: length <= 0.9 x the wave's length (the old code: refused, one card is "Nothing to change yet")
##  4 slower    Slower (one click) makes it longer again: >= 1.1 x the faster length
##  5 save      the bar's Save video (one click), with one wave card: a video (mp4 or frames) is written and the status says saved
##              (the old code: "NOT NOW" / "Pick a move first" with one card: a single wave could never be saved)
##  6 typed     New scene (its Save / Don't save question answered: Don't save), the word "wave" typed in the box and Go (real clicks): a wave is built (status "Made ...")
##  7 presses   the whole walk takes at most 20 presses
## NOT BARS (printed): the typed build says "Made 'wave'." and the card build "Made the wave." (easyhome_test pins the quoted form);
## the New scene question after a saved video ("Save changes to wave?"), answered by a call: a dialog's buttons take no harness click.
## Only user:// is written (the video folder is a user:// folder of this test). Shots: C:/Temp/claude/awave/

const ROOT_DIR := "user://awave_test"
const SHOT_DIR := "C:/Temp/claude/awave"

var fails := 0
var m: Node
var ss: StartScreen
var presses := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func shot(nm: String) -> void:
	if DirAccess.dir_exists_absolute(SHOT_DIR):
		m.get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/" + nm + ".png")


## a real click: press and release at the control centre, through the root viewport (scrolled into view first)
func click(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)
	return true


func press(c: Control, what: String) -> bool:
	presses += 1
	var r := await click(c)
	if not r:
		dead(what + ": nothing clickable there")
	return r


func dead(words: String) -> void:
	print("DEAD END: " + words)


## the visible control with this node name (anywhere in the window)
func named(nm: String) -> Control:
	for b in m.find_children(nm, "Control", true, false):
		if (b as Control).is_visible_in_tree():
			return b
	return null


func wait_built(limit := 1500) -> void:
	var waited := 0
	while waited < limit and m.S.cards.is_empty():
		await process_frame
		waited += 1


func _init() -> void:
	EasyMode.start_fresh = true   # a beginner's first start: no settings file = Easy
	UserPaths.force = true
	UserPaths.root = gp(ROOT_DIR)
	var vid_dir := gp(ROOT_DIR + "/video")
	if DirAccess.dir_exists_absolute(vid_dir):
		for f in DirAccess.get_files_at(vid_dir):
			DirAccess.remove_absolute(vid_dir + "/" + f)
	DirAccess.make_dir_recursive_absolute(vid_dir)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	ss = m.start_screen
	ss.show_screen(true)   # the start-up screen, as a beginner sees it
	await idle(20)
	shot("00_start")

	# 1 start: ANIMATION, then the Wave picture
	await press(ss._card_art["animation"], "ANIMATION card")
	await idle(10)
	var home = m.easy.home
	var wave: Control = home.panel.find_child("eh_card_6", true, false) if home != null and home.panel != null else null
	await press(wave, "Wave picture")
	wait_built()
	await idle(10)
	shot("01_wave_built")
	var len0: float = m.S.length()
	var said: String = String(m.ui_status.text)
	ok(said.begins_with("Made") and len0 > 0.5 and m.playing and not m.B.wep_on,
		"1 start: wave built (%d poses, %.2f s, playing %s, sword in hand %s; status \"%s\")" % [m.S.cards.size(), len0, m.playing, m.B.wep_on, said])

	# 2 play: Play / Stop twice (the bar's button)
	var was_playing: bool = m.playing
	await press(m.easy._btns["Play / Stop"], "Play / Stop (1)")
	await idle(3)
	var stopped: bool = not m.playing
	await press(m.easy._btns["Play / Stop"], "Play / Stop (2)")
	await idle(3)
	ok(was_playing and stopped and m.playing, "2 play: playing after the build %s, Stop stops it %s, Play plays it again %s" % [was_playing, stopped, m.playing])

	# 3 faster (the strip's one click)
	await press(named("eh_faster"), "Faster")
	await idle(5)
	var len1: float = m.S.length()
	shot("02_faster")
	ok(len1 <= 0.9 * len0, "3 faster: %.2f s -> %.2f s (want <= %.2f s); status \"%s\"" % [len0, len1, 0.9 * len0, m.ui_status.text])

	# 4 slower
	await press(named("eh_slower"), "Slower")
	await idle(5)
	var len2: float = m.S.length()
	ok(len2 >= 1.1 * len1, "4 slower: %.2f s -> %.2f s (want >= %.2f s); status \"%s\"" % [len1, len2, 1.1 * len1, m.ui_status.text])

	# 5 save video (the bar's button, a test folder for the file)
	home.video_root = gp(ROOT_DIR + "/video")
	await press(m.easy._btns["Save video"], "Save video")
	var waited := 0
	while waited < 1500 and (m._pb_busy or m._video_pid >= 0):
		await process_frame
		waited += 1
	await idle(10)
	shot("03_saved")
	var r: Dictionary = home.last_video
	var got := false
	if not r.is_empty():
		got = (String(r.get("mp4", "")) != "" and FileAccess.file_exists(String(r["mp4"]))) or (String(r.get("dir", "")) != "" and DirAccess.get_files_at(String(r["dir"])).size() > 0)
	ok(got, "5 save: a video or its frames written (%s); status \"%s\"" % [str(r.get("mp4", r.get("dir", "none"))), m.ui_status.text])

	# 6 typed: a fresh scene, the word typed in the box, Go
	await press(m.easy._btns["New scene"], "New scene")
	await idle(10)
	shot("03b_new_scene")
	print("   after New scene: cards %d, status \"%s\", panel shown %s" % [m.S.cards.size(), m.ui_status.text, str(m.easy.home.shown()) if m.easy.home != null else "none"])
	var asked := false
	for d in m.find_children("*", "AcceptDialog", true, false):
		if (d as Window).visible:
			asked = true
			print("   dialog up: %s | %s" % [String((d as Window).title), String((d as AcceptDialog).dialog_text)])
			for b in d.find_children("*", "Button", true, false):
				print("   button: \"%s\" visible %s" % [String((b as Button).text), (b as Button).is_visible_in_tree()])
			presses += 1
			m._save_ask_choose("discard")   # the dialog is its own window: a click does not reach its button here (harness), so its choice is called
	if asked:
		await idle(10)
	print("   after the question: cards %d, status \"%s\"" % [m.S.cards.size(), m.ui_status.text])
	home = m.easy.home
	var box: LineEdit = named("eh_text") as LineEdit
	if box == null:
		dead("typed: no move box on the empty scene")
	else:
		presses += 1
		box.grab_focus()
		box.text = "wave"
		await press(named("eh_go"), "Go")
		wait_built()
		await idle(10)
		shot("04_typed")
	ok(m.S.cards.size() > 0 and String(m.ui_status.text).begins_with("Made"),
		"6 typed: \"wave\" typed and Go built a wave (%d poses; status \"%s\")" % [m.S.cards.size(), m.ui_status.text])

	ok(presses <= 20, "7 presses: %d (want <= 20)" % presses)
	print("awave: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
