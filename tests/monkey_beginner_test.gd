## godot --path . -s tests/monkey_beginner_test.gd     (MONKEY BEGINNER TEST: the six beginner tasks in EASY mode, with only visible controls; needs a window)
## A beginner's pass. Every control is found by the text on screen (a Button's text, or the Label inside it) and pressed by
## emitting its `pressed` (a View menu item by emitting its id). No internal function is called to reach a control; the
## test only reads the state the app shows. MEASURES, FIXES NOTHING: a task the visible controls cannot reach is printed as
## "BLOCKED: <task>: <why>" and fails its bar. Also reported: visible Easy buttons with no tooltip, visible text over 40
## characters, and labels shared by two visible buttons.
## OUTPUT: user:// only. The Easy "Save video" button writes to res://exports/playblast (PlayblastExport.ROOT is a fixed
## const, no folder choice), so this test does not press it (task 6).
extends SceneTree

const LONG := 40

var fails := 0
var m: Node
var clicks := 0                  # presses in the task being run
var pressed_names: Array = []    # the texts of the buttons pressed in that task
var tasks: Array = []            # one line per task, printed at the end
var long_texts := {}             # visible text over LONG characters
var dupes := {}                  # visible labels shared by two visible buttons
var no_tip := {}                 # visible buttons with no tooltip
var tip_checked := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func blocked(task: String, why: String) -> void:
	print("BLOCKED: %s: %s" % [task, why])
	fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## every node under n, n first
func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		walk(c, out)
	return out


## every node a person can see (its own and its parents' visibility, in the window)
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


## the words on a button: its own text, else the first Label inside it (the Easy bar and the picture cards put one there)
func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):   # a library tile's "placeholder" (its category, until the picture lands) is not its name: the label under it is
		if n is Label and n.name != "placeholder" and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


## the first visible button whose words are txt (prefix = true: the words start with txt)
func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		var t := text_of(b)
		if t == txt or (prefix and t.begins_with(txt)):
			return b
	return null


## a click: the visible button with these words gets its pressed signal. false = no such visible control
func press(txt: String, prefix := false) -> bool:
	var b := find_btn(txt, prefix)
	if b == null:
		return false
	clicks += 1
	pressed_names.append(text_of(b))
	b.pressed.emit()
	await idle(2)
	return true


func begin() -> void:
	clicks = 0
	pressed_names = []


func end(task: String, reached: bool, note: String) -> void:
	tasks.append("TASK %s: clicks=%d buttons=%s reachable=%s %s" % [task, clicks, str(pressed_names), "yes" if reached else "NO", note])


## a clip plays: wait (up to a bound) until the playhead has moved from the start
func wait_playing(limit := 120) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


## the body is on screen: its middle projects inside the window and in front of the camera
func body_on_screen() -> bool:
	var c: Array = m.B.cap("pelvis")
	var at: Vector3 = (c[0] + c[1]) * 0.5
	var vp := m.get_viewport().get_visible_rect()
	return not m.cam.is_position_behind(at) and vp.has_point(m.cam.unproject_position(at))


## the checks on what is on screen now: tooltips, long text, shared labels
func snapshot() -> void:
	var seen := {}
	for b in visible_buttons():
		var t := text_of(b)
		tip_checked += 1
		if (b as Button).tooltip_text.strip_edges() == "":
			no_tip[t if t != "" else "(no words) " + str(b.name)] = true
		if t != "":
			if seen.has(t):
				dupes[t] = true
			seen[t] = true
	for n in visible_nodes():
		var s := ""
		if n is Label:
			s = (n as Label).text
		elif n is LineEdit:
			var e := n as LineEdit
			s = e.text if e.text != "" else e.placeholder_text
		elif n is Button:
			s = (n as Button).text
		s = s.strip_edges()
		if s.length() > LONG:
			long_texts[s] = true


func _init() -> void:
	EasyMode.start_fresh = true   # a fresh install: no settings file, so the app opens in Easy (no mode key = Easy)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	var home: EasyHome = m.easy.home

	# 1. app open: a FRESH start (no settings file) opens straight into Easy, the home panel showing. 0 clicks.
	begin()
	var fresh_easy: bool = m.easy.on
	ok(fresh_easy, "1. a fresh start (no settings file) opens in Easy")
	await idle(4)
	if home.shown() != "panel" and m.S.cards.size() > 0:   # a scene with cards is open: a new one first
		if await press("New scene"):
			await idle(4)
			await press("Don't save")
			await idle(4)
	ok(body_on_screen(), "1. the body is on screen (his middle projects inside the window)")
	ok(home.shown() == "panel", "1. the Easy home panel is visible (shown: %s)" % home.shown())
	snapshot()
	end("1 app open", fresh_easy and body_on_screen() and home.shown() == "panel", "(fresh start, no settings file)")

	# 2. "make him punch": the Punch card builds a clip and plays it
	begin()
	var punched := await press("Punch")
	var played := await wait_playing()
	ok(punched and played and m.S.cards.size() >= 2, "2. Punch card builds a clip of %d cards and plays it" % m.S.cards.size())
	if not punched:
		blocked("2 make him punch", "no visible button reads 'Punch' on the Easy home panel")
	end("2 make him punch", punched and played, "")

	# 3. "make it play again": a visible Again control plays the clip from its start
	begin()
	await idle(30)
	var before: float = m.playhead
	var again := find_btn("Again") != null
	var again_ok := false
	if again:
		again_ok = await press("Again")
		await idle(3)
		again_ok = again_ok and m.playing and m.playhead < before
		ok(again_ok, "3. Again plays the clip from its start (playhead %.2f -> %.2f)" % [before, m.playhead])
	else:
		blocked("3 make it play again", "no visible 'Again' button after the punch (the strip shows only once a clip is built)")
	end("3 make it play again", again_ok, "")

	# 4. "give him a sword": Easy's Library, the Weapons tab, the Sword tile. Ends with the sword in his right hand
	begin()
	var stopped := false   # a beginner does not stop the clip first: the pick is made WHILE the punch plays, and must stick
	var was_playing: bool = m.playing
	var lib := await press("Library")
	var tab := await press("Weapons", true)
	var sword := await press("Sword")
	var held: bool = m.B.wep_on and m.B.wep_kind == "sword" and m.B.wep_hand == "hand_r"
	ok(lib and tab and sword and held, "4. the Sword tile puts a sword in his right hand (on: %s, kind: %s, hand: %s)" % [str(m.B.wep_on), m.B.wep_kind, m.B.wep_hand])
	await idle(10)
	var kept: bool = m.B.wep_on and m.B.wep_kind == "sword"
	# the sword rides in the hand through the whole clip: the knob's distance from the wrist is the same on every frame (1 cm)
	var ride := -1.0
	if held and not m.S.cards.is_empty():
		var d0 := -1.0
		ride = 0.0
		var L: float = m.S.length()
		for q in 9:
			m.S.apply(m.B, L * float(q) / 8.0)
			var kn: Array = m.B.to_dict()["weapon"].get("knob", [0, 0, 0])
			var d: float = Vector3(kn[0], kn[1], kn[2]).distance_to(m.B.P["hand_r"])
			if d0 < 0.0:
				d0 = d
			ride = maxf(ride, absf(d - d0))
	ok(ride >= 0.0 and ride <= 0.01 and m.B.wep_on, "4. through the clip the sword stays in the hand: the knob-to-wrist distance varies %.2f cm (bar 1)" % [ride * 100.0])
	ok(kept, "4. the sword is still in his hand 10 frames later (on: %s; the clip was playing at the pick: %s, still playing: %s)" % [str(m.B.wep_on), str(was_playing), str(m.playing)])
	if not lib:
		blocked("4 give him a sword", "no visible 'Library' button in Easy")
	elif not tab:
		blocked("4 give him a sword", "the object library shows no visible 'Weapons' tab")
	elif not sword:
		blocked("4 give him a sword", "no visible 'Sword' tile under Weapons")
	snapshot()
	end("4 give him a sword", lib and tab and sword and held and kept, "(stopped first: %s)" % str(stopped))

	# 5. "make him kick": close the library (its Library button), Change it, the Kick card, a kick plays
	begin()
	var closed := await press("Library")
	var changed := await press("Change it")
	var kicked := await press("Kick")
	var kick_played := await wait_playing()
	ok(kicked and kick_played, "5. the Kick card builds a clip and plays it")
	if not changed:
		blocked("5 make him kick", "no visible 'Change it' to bring the picture cards back")
	elif not kicked:
		blocked("5 make him kick", "no visible 'Kick' card on the Easy home panel")
	snapshot()
	end("5 make him kick", closed and changed and kicked and kick_played, "")

	# 6. "save it and send me the video": the strip's Save video, pressed. Its folder is a test's user:// folder
	#    (EasyHome.video_root); the real default is the user's Videos folder, Kine/.
	begin()
	home.video_root = "user://monkey_out_%d" % OS.get_process_id()
	var pressed6 := await press("Save video")
	var t0 := Time.get_ticks_msec()
	while home.last_video.is_empty() and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	var mp4 := String(home.last_video.get("mp4", ""))
	var toast := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.begins_with("Your video is saved: "):
			toast = (n as Label).text
	var show_btn := find_btn("Open folder") != null
	var wrote := pressed6 and mp4 != "" and FileAccess.file_exists(mp4) and mp4.contains(home.video_root.trim_prefix("user://"))
	ok(wrote, "6. Save video writes a video file to the test folder: %s" % mp4)
	ok(toast != "" and show_btn, "6. a toast says '%s' with an Open folder button" % toast)
	snapshot()
	end("6 save and send the video", wrote and toast != "" and show_btn, "(test folder %s)" % home.video_root)

	# the other checks: every visible Easy button, all visible text, shared labels
	print("TOOLTIPS: %d visible buttons checked; no tooltip: %s" % [tip_checked, str(no_tip.keys())])
	print("LONG TEXT (over %d chars): %d: %s" % [LONG, long_texts.size(), str(long_texts.keys())])
	print("DUPLICATE LABELS: %s" % str(dupes.keys()))
	for t in tasks:
		print(t)
	print("MONKEY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
