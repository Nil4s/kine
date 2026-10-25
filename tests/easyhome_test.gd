## godot --path . -s tests/easyhome_test.gd     (EASY HOME, "monkey brain easy": the empty scene's picture panel; needs a window)
## BARS (stated before measuring):
##  1. Easy with an empty scene shows the "What should he do?" panel (8 picture cards and the text box); Expert shows none.
##  2. Every card builds a non-empty clip that plays (walk, run, jump, punch, sit down, wave from templates/; kick = "roundhouse" by
##     TextBlocking). Fall builds too (the fall template: a backward breakfall).
##  3. The click -> the first frame the clip plays is under 2000 ms for each card that builds (the builder time is printed).
##  4. One Ctrl+Z after a card gives back the empty scene (one undo step per card).
##  5. Typing "jab then cross" builds 2 strikes (the cards are the two single strikes, in order).
##  5b. Typing "walk", "jump", "walk then wave", "jump then kick", "sit down then fall" in the box builds >= 2 cards, no "can't build".
##  5c. Typing "dance" builds nothing, and its sentence names the cards' moves (never one Kine cannot build).
##  6. The panel fits inside the window at 1280x720 (its rect is inside the visible viewport).
##  8. The Library opened over the empty scene hides the panel; Close brings it back.
##  7. Every card that builds: its click to the first moving frame is under 500 ms (the Kick card built live took 3.6 s; baked it is a file).
##  11. CHAIN: with a walk built, Change it and a card (Add after, the default) keeps the walk and adds the wave after it:
##     cards = walk + wave, the walk first; Undo takes the add back in one step; Start over replaces the clip.
##  14. SIT ON A CHAIR, VIEW BUTTONS: a placed chair shows "Sit on it"; the click or typed "sit on the chair" seats him on it; Front / Side / Back turn the view.
##  15. EDIT A PICKED CARD: a card picked on the strip, the body dragged: that card takes the pose (one undo step, "Change pose");
##      the count and the other cards stay; moving the pick off keeps the edit; Ctrl+Z puts the card's pose back.
##  16. HELP IN EASY: a visible Help button (the panel and the strip) opens the help text and the tour button; Help again hides it.
##  17. A typed question ('how do I make him jump') names the move to type, or gives the help line; never "doesn't know".
##  18. After a typed move is used the box is empty; a failed line keeps its words, and Change it selects them.
##  C. (the layout) At 1280x720 and at 1600x900 the home panel covers at most 15 % of the body's screen box (the body's capsule
##     ends projected with m.cam.unproject_position): the body is visible beside the panel, not under it.
## A screenshot of the panel goes to user://easyhome_panel.png (the path is printed).
extends SceneTree

const BUILDS := [0, 1, 2, 3, 4, 5, 6, 7]   # the cards that build: walk, run, jump, punch, kick, sit down, wave, fall
const BAR_MS := 2000
const FAST_MS := 500     # bar 7: every card's click to its first moving frame (a beginner thinks a slower one froze)

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the clip plays: wait (up to a bound) until the body has moved from the start
func wait_playing(limit := 120) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


## the body's screen box: each capsule end (Turntable.points: the joints and their ends, the weapons) projected by m.cam, grown
## by its radius in px (the same px-per-metre as the Easy framing: 2 d tan(fov/2) / view height)
func body_box() -> Rect2:
	var cam: Camera3D = m.cam
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var mpp: float = 2.0 * float(m.dist) * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in Turntable.points(m.B):
		if cam.is_position_behind(p[0]):
			continue
		var q := cam.unproject_position(p[0])
		var r: float = float(p[1]) / mpp
		lo = lo.min(q - Vector2(r, r))
		hi = hi.max(q + Vector2(r, r))
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2()


## the picked prop (a chair) under the hips: [the pelvis's middle is over its seat, the hips' lowest surface over the seat minus
## the seat's top] (the same measure as use_set_test's sit: Body.SEAT_PARTS, Props._over)
func seat_gap() -> Array:
	var p: Dictionary = m.S.props[m.sel_prop]
	var sup: Dictionary = Props.supports(p)[0]
	var top: float = sup["y"]
	var B: Body = m.B
	var mid: Vector3 = (B.cap("pelvis")[0] + B.cap("pelvis")[1]) * 0.5
	var lo := INF
	for part in Body.SEAT_PARTS:
		var c = B.cap(part)
		for k in 41:
			var q: Vector3 = (c[0] as Vector3).lerp(c[1], k / 40.0)
			if Props._over(sup, q):
				lo = minf(lo, q.y - float(B.rad[part]))
	return [Props._over(sup, mid), lo - top]


func card_btn(i: int) -> Button:
	return m.easy.home.panel.find_child("eh_card_%d" % i, true, false) as Button


## the strip's picture button of card i (0-based): the pick button inside its card's panel
func pick_btn(i: int) -> Control:
	var pc: Node = m.ui_cards.get_node_or_null("card_%d" % (i + 1))
	return pc.find_child("b_pick", true, false) as Control if pc != null else null


## a real click on a Control (the mouse goes down and up on its middle, through the viewport's input)
func click_ctl(c: Control) -> void:
	var at: Vector2 = c.get_global_rect().get_center()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	root.push_input(u)
	await idle(4)


## a real drag of one part on the body: the pointer goes to the part, down, six moves, up at the end of d
func drag_part(j: String, d: Vector2) -> void:
	var c: Array = m.B.cap(j)
	var p: Vector2 = m.cam.unproject_position(c[0].lerp(c[1], 0.75))
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await idle(2)
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.position = p
	dn.global_position = p
	dn.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(dn)
	await process_frame
	var st := d / 6.0
	for i in 6:
		var mm := InputEventMouseMotion.new()
		mm.position = p + st * (i + 1)
		mm.global_position = mm.position
		mm.relative = st
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p + d
	up.global_position = p + d
	root.push_input(up)
	await idle(3)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	# the 2D layout at 1280x720 (the suite's window is embedded and keeps its host's size, so the layout size is set)
	var was_size: Vector2i = root.content_scale_size
	var was_mode: int = root.content_scale_mode
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(8)
	var home: EasyHome = m.easy.home

	# 1. Expert: no panel; Easy with an empty scene: the panel, with 8 cards and the text box
	m._new_scene()
	await idle()
	m.easy.set_on(false, false)
	await idle()
	ok(home.shown() == "hidden", "1. Expert shows no Easy home panel (shown: %s)" % home.shown())
	m.easy.set_on(true, false)
	await idle()
	ok(home.shown() == "panel", "1. Easy with an empty scene shows the panel (shown: %s)" % home.shown())
	var titles: Array = home.panel.find_children("eh_title", "Label", true, false)
	ok(titles.size() == 1 and (titles[0] as Label).text == "What should he do?", "1. the panel's title is 'What should he do?'")
	var cards := 0
	for i in 8:
		if card_btn(i) != null:
			cards += 1
	ok(cards == 8, "1. the panel has the 8 picture cards (%d)" % cards)
	var edit := home.panel.find_child("eh_text", true, false) as LineEdit
	ok(edit != null and edit.placeholder_text.begins_with("or type a move: 'jab then cross'"), "1. the text box says 'or type a move: ...'")

	# 2 and 3. every card: builds (or says why not), plays, times the click to the first played frame
	var times := []
	var fast_ms := []
	for i in 8:
		m.playing = false
		m._new_scene()
		await idle(2)
		var before: int = m.undo.size()
		var t0 := Time.get_ticks_msec()
		card_btn(i).pressed.emit()
		var played := await wait_playing()
		var ms := Time.get_ticks_msec() - t0
		var name := String(card_btn(i).get_meta("label"))
		if i in BUILDS:
			ok(m.S.cards.size() >= 2 and played, "2. %s builds a clip of %d cards and plays it" % [name, m.S.cards.size()])
			ok(m.undo.size() == before + 1, "4. %s is one undo step" % name)
			# the bar is per card, except where the builder alone is slower: then the builder's time is reported and the
			# rest of the click (the scene load, the redraw, the start of play) must still fit the bar
			var rest := home.last_ms - home.last_build_ms
			if home.last_build_ms >= BAR_MS:
				ok(home.last_ms >= 0 and rest < BAR_MS, "3. %s: the builder alone takes %d ms (over the bar: reported); click to the first played frame %d ms, the rest after the build %d ms" % [name, home.last_build_ms, home.last_ms, rest])
			else:
				ok(home.last_ms >= 0 and home.last_ms < BAR_MS, "3. %s: click to the first played frame %d ms (builder %d ms; bar %d ms)" % [name, home.last_ms, home.last_build_ms, BAR_MS])
			times.append([name, home.last_build_ms, home.last_ms])
			# 7. the beginner's wait: every card's click to its first moving frame under 500 ms (the Kick card was 3.6 s live)
			ok(home.last_ms >= 0 and home.last_ms < FAST_MS, "7. %s: click to the first moving frame %d ms (bar %d ms)" % [name, home.last_ms, FAST_MS])
			fast_ms.append("%s %d" % [name, home.last_ms])
		else:
			ok(m.S.cards.is_empty() and home.shown() == "panel" and home.panel.find_child("eh_msg", true, false).text != "",
				"2. %s has no builder yet: the scene stays empty and one plain sentence says why: '%s'" % [name, (home.panel.find_child("eh_msg", true, false) as Label).text])

	# 4. one Ctrl+Z after a card gives back the empty scene
	m.playing = false
	m._new_scene()
	await idle(2)
	card_btn(0).pressed.emit()
	await idle(2)
	ok(not m.S.cards.is_empty(), "4. a card built a clip before the undo check")
	var n_undo: int = m.undo.size()
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.physical_keycode = KEY_Z
	k.ctrl_pressed = true
	k.pressed = true
	root.push_input(k)
	await idle(3)
	print("diag ctrl+z: undo steps %d -> %d, cards %d, focus %s" % [n_undo, m.undo.size(), m.S.cards.size(), str(root.gui_get_focus_owner())])
	ok(m.S.cards.is_empty(), "4. one Ctrl+Z after Walk gives back the empty scene (%d cards)" % m.S.cards.size())
	ok(home.shown() == "panel", "4. the panel comes back for the empty scene (shown: %s)" % home.shown())

	# 5. "jab then cross" = two strikes
	var two: Dictionary = home._words_dict("jab then cross")
	var jab: Dictionary = home._words_dict("jab")
	var cross: Dictionary = home._words_dict("cross")
	ok(two["ok"] and two["strikes"] == 2, "5. 'jab then cross' builds 2 strikes")
	ok(two["ok"] and (two["dict"]["cards"] as Array).size() == (jab["dict"]["cards"] as Array).size() + (cross["dict"]["cards"] as Array).size(),
		"5. its cards are the jab's cards then the cross's")
	m._new_scene()
	await idle(2)
	edit.text = "jab then cross"
	edit.text_submitted.emit("jab then cross")
	await idle(2)
	ok(not m.S.cards.is_empty() and home.shown() == "strip", "5. typed 'jab then cross' builds a clip and the panel shrinks to the strip (shown: %s)" % home.shown())
	ok(home.strip.find_child("eh_again", true, false) != null and home.strip.find_child("eh_change", true, false) != null and home.strip.find_child("eh_save", true, false) == null,
		"the strip has Again and Change it; Save video is on the Easy bar only (one button per label)")

	# 5b. the typed box builds a card's word alone or in a chain ("walk then wave"), the same moves as the cards: no "can't build"
	for t in ["walk", "jump", "walk then wave", "jump then kick", "sit down then fall"]:
		m._new_scene()
		await idle(2)
		edit.text = t
		edit.text_submitted.emit(t)
		await idle(2)
		var said: String = m.ui_status.text + " " + (home.panel.find_child("eh_msg", true, false) as Label).text
		ok(m.S.cards.size() >= 2 and not "can't build" in said,
			"5b. typed '%s' builds %d cards and never says \"can't build\" (says: '%s')" % [t, m.S.cards.size(), said.strip_edges()])
	# 5c. a word Kine cannot build builds nothing, and its sentence names only what Kine accepts (the cards' words, then strikes)
	m._new_scene()
	await idle(2)
	edit.text = "dance"
	edit.text_submitted.emit("dance")
	await idle(2)
	var why := (home.panel.find_child("eh_msg", true, false) as Label).text
	var try_names := []
	for n in ["walk", "punch", "kick", "wave"]:
		try_names.append(home.panel.find_child("eh_try_%s" % n, true, false) as Button)
	ok(m.S.cards.is_empty() and why == "Kine doesn't know 'dance' yet." and home._try_row.visible and not try_names.has(null),
		"5c. typed 'dance' builds nothing, says one short line, and offers the Or-try moves (says: '%s')" % why)

	# 6. the panel fits the window at 1280x720 (the empty scene's panel)
	m._new_scene()
	await idle(3)
	var vis := m.get_viewport().get_visible_rect()
	var r: Rect2 = home.panel.get_global_rect()
	ok(vis.size == Vector2(1280, 720) and vis.encloses(r), "6. the panel fits inside the 1280x720 window (panel %s in %s)" % [str(r), str(vis)])
	ok(home.shown() == "panel", "6. the empty-scene panel is up for the screenshot (shown: %s)" % home.shown())
	edit.text = ""   # the box shows its hint in the picture
	await idle(2)
	var img: Image = m.get_viewport().get_texture().get_image()
	var shot := "user://easyhome_panel.png"
	img.save_png(shot)
	print("screenshot %s" % ProjectSettings.globalize_path(shot))
	# C. the body is visible beside the panel: its screen box (every capsule end projected by m.cam, with its radius) is covered
	# by the panel by at most 15 % of its area. Measured at 1280x720 (the bar) and at 1600x900 (the window the beginner had)
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.content_scale_size = sz
		await idle(6)
		m._cam()
		await idle(2)
		var pr: Rect2 = home.panel.get_global_rect()
		var br := body_box()
		var frac := pr.intersection(br).get_area() / maxf(br.get_area(), 1.0)
		ok(home.shown() == "panel" and br.get_area() > 0.0 and frac <= 0.15,
			"C. at %dx%d the panel covers %.1f %% of the body's screen box (panel %s, body %s; bar 15 %%)" % [sz.x, sz.y, frac * 100.0, str(pr), str(br)])
	root.content_scale_size = was_size   # back to the window's own size
	root.content_scale_mode = was_mode
	await idle(4)

	# 8. the Library opened over an empty Easy scene: the panel steps aside (the library covered its left half), and comes back on Close
	m._new_scene()
	await idle()
	m._library_toggle()
	await idle()
	ok(not home.panel.visible and m.ui_library.visible, "8. the open Library hides the home panel (no half-covered cards)")
	var lr: Rect2 = m.ui_library.get_global_rect()
	ok(lr.end.y <= m.get_viewport().get_visible_rect().size.y + 0.5, "8. the Library ends inside the window (bottom %.0f px, window %.0f; it once grew to 1572 px over the cards)" % [lr.end.y, m.get_viewport().get_visible_rect().size.y])
	m._library_toggle()
	await idle()
	ok(home.panel.visible, "8. closing the Library brings the home panel back")

	# 9. a built clip's strip (Again, Change it, Faster...) steps aside while the Library is open (it covered them), and comes back on Close
	m._new_scene()
	await idle()
	home.card(0)
	await idle(8)
	ok(home.shown() == "strip", "9. a built clip shows the strip (shown: %s)" % home.shown())
	m._library_toggle()
	await idle()
	ok(home.shown() == "hidden" and m.ui_library.visible, "9. the open Library hides the strip too (shown: %s)" % home.shown())
	m._library_toggle()
	await idle()
	ok(home.shown() == "strip", "9. closing the Library brings the strip back (shown: %s)" % home.shown())

	# 10. the say line names the clip just built, not the last one's words (a typed 'wave' after a walk said 'the walk')
	m._new_scene()
	await idle()
	home.card(0)
	await idle(4)
	ok(m.ui_status.text.begins_with("Made the walk"), "10. the say line names the built card (says: '%s')" % m.ui_status.text)
	home.card(6)
	await idle(4)
	ok(m.ui_status.text.begins_with("Made the wave"), "10. the say line follows the next card (says: '%s')" % m.ui_status.text)

	# 11. CHAIN: "walk, then wave" from the cards. With a clip built, the picker's "Then:" row (Add after is the default) keeps
	# the walk and adds the wave's cards after it (one undo step); Start over replaces it (today's behaviour). Undo takes the add back.
	m._new_scene()
	await idle(2)
	ok(home.panel.find_child("eh_then", true, false).visible == false, "11. the Then: row is hidden on an empty scene (nothing to add after)")
	home.card(0)
	await idle(4)
	var walk_n: int = m.S.cards.size()
	var walk_len: float = m.S.length()
	var walk_names: Array = []
	for c in m.S.cards:
		walk_names.append(c["name"])
	m._new_scene()
	await idle(2)
	home.card(6)
	await idle(4)
	var wave_n: int = m.S.cards.size()
	var wave_name: String = String(m.S.cards[0]["name"])
	var add_btn := home.panel.find_child("eh_then_add", true, false) as Button
	var start_btn := home.panel.find_child("eh_then_start", true, false) as Button
	m._new_scene()
	await idle(2)
	home.card(0)
	await idle(4)
	home._change()   # Change it: the picker comes back over the walk, with the Then: row
	await idle(4)
	ok(home.shown() == "panel" and add_btn != null and add_btn.button_pressed and home.panel.find_child("eh_then", true, false).visible,
		"11. with a walk built, Change it shows the picker with the Then: row and Add after chosen (shown: %s)" % home.shown())
	var before_u: int = m.undo.size()
	var chain_img: Image = m.get_viewport().get_texture().get_image()
	chain_img.save_png("user://easy_chain_picker.png")
	print("chain screenshot %s" % ProjectSettings.globalize_path("user://easy_chain_picker.png"))
	card_btn(6).pressed.emit()
	await idle(4)
	var names_now: Array = []
	for c in m.S.cards:
		names_now.append(c["name"])
	ok(m.S.cards.size() == walk_n + wave_n, "11. Walk, then Wave by cards: %d cards = the walk's %d + the wave's %d (%d)" % [m.S.cards.size(), walk_n, wave_n, m.S.cards.size()])
	ok(names_now.slice(0, walk_n) == walk_names and String(names_now[walk_n]) == wave_name,
		"11. the walk's cards come first, then the wave's (the card at %d is '%s')" % [walk_n, String(names_now[walk_n]) if names_now.size() > walk_n else ""])
	ok(m.S.length() > walk_len + 0.4 and home.shown() == "strip", "11. the clip runs past the walk's end (%.2f s after %.2f s); the strip shows (shown: %s)" % [m.S.length(), walk_len, home.shown()])
	ok(m.undo.size() == before_u + 1, "11. the add is one undo step (%d -> %d)" % [before_u, m.undo.size()])
	ok(m.ui_status.text.begins_with("Made the wave") and m.ui_status.text.contains("added after the walk"), "11. the say line says the wave was added after the walk (says: '%s')" % m.ui_status.text)
	m._undo()
	await idle(4)
	var back_names: Array = []
	for c in m.S.cards:
		back_names.append(c["name"])
	ok(back_names == walk_names, "11. Undo takes the add back: the walk's cards only (%d cards)" % m.S.cards.size())
	# Start over: the same two moves, the wave replaces the walk (today's behaviour)
	home._change()
	await idle(4)
	start_btn.button_pressed = true   # the click: the group turns Add after off and this one on (toggled sets the choice)
	await idle(1)
	card_btn(6).pressed.emit()
	await idle(4)
	ok(m.S.cards.size() == wave_n and String(m.S.cards[0]["name"]) == wave_name, "11. Start over: the wave replaces the walk (%d cards, the wave's %d)" % [m.S.cards.size(), wave_n])

	# 12. THE SAVED-VIDEO MESSAGE IS ABOUT THAT CLIP (walk-through round 4): it stays while nothing changes, goes when the save
	# question comes up or the clip changes (New scene), and the save question's words are not repeated in Easy's status line
	m._new_scene()
	await idle(4)
	card_btn(3).pressed.emit()   # Punch
	await idle(4)
	m.playing = false
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	await idle(3)
	var sv: Control = home._toast
	ok(sv.visible, "12. the saved-video message shows while the clip is unchanged")
	var st0: String = m.ui_status.text
	m._ask_save("this scene", func(): pass)
	await idle(3)
	ok(not sv.visible, "12. the save question takes the saved-video message down")
	ok(m.ui_status.text == st0 and not m.ui_status.text.contains("Don't save throws"), "12. Easy: the status line does not repeat the save question ('%s')" % m.ui_status.text)
	m._save_ask_choose("cancel")
	await idle(2)
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	await idle(2)
	m.S.cards.clear()
	await idle(3)
	ok(not sv.visible, "12. the clip changing takes the saved-video message down")
	home._show_toast("Nothing here yet", "")   # a message with no file (the empty-scene hint) is not a saved-video message: it stays
	await idle(3)
	ok(sv.visible, "12. a message with no file is left alone")
	sv.visible = false
	m._new_scene()
	await idle(4)

	# 13. A WORD KINE CANNOT BUILD IS SAID ONCE (walk-through round 4): the panel says it, the status line doesn't repeat it
	m._new_scene()
	await idle(4)
	edit.text = "backflip"
	edit.text_submitted.emit("backflip")
	await idle(4)
	var said13: String = (home.panel.find_child("eh_msg", true, false) as Label).text
	ok(said13.contains("backflip") and not m.ui_status.text.contains("backflip"), "13. 'backflip' is said in the panel only (panel '%s', status '%s')" % [said13, m.ui_status.text])
	m._new_scene()
	await idle(4)

	# 14. SIT ON A CHAIR, AND VIEW BUTTONS (walk-through round 5, goals 4 and 7). A chair placed in Easy shows "Sit on it" in the
	# panel; the click seats him on it (SET's own sit: main._prop_sit); typed "sit on the chair" does the same. Front, Side and
	# Back turn the camera 0 / 90 / 180 deg; Front returns it exactly
	m._new_scene()
	await idle(4)
	var sit_btn := home.panel.find_child("eh_sit", true, false) as Button
	ok(sit_btn != null and not sit_btn.visible, "14. no chair picked: no 'Sit on it' button in the panel")
	m._prop_add("chair")
	await idle(4)
	sit_btn = home.panel.find_child("eh_sit", true, false) as Button
	ok(sit_btn != null and sit_btn.visible and not sit_btn.disabled, "14. a chair placed: 'Sit on it' is visible in the panel and live")
	if sit_btn != null:
		sit_btn.pressed.emit()
	await idle(6)
	var g14: Array = seat_gap()
	ok(m.S.cards.size() == 1 and String(m.S.cards[0]["name"]).begins_with("sit on the chair"), "14. Sit on it builds the chair's sit card (%d cards)" % m.S.cards.size())
	ok(bool(g14[0]), "14. click: the hips are over the chair's seat")
	ok(float(g14[1]) > -0.005 and float(g14[1]) < 0.15, "14. click: the hips end %.3f m above the seat's top (within 0.15)" % float(g14[1]))
	m._new_scene()
	await idle(4)
	m._prop_add("chair")
	await idle(4)
	var n14: int = m.S.cards.size()
	edit.text = "sit on the chair"
	edit.text_submitted.emit("sit on the chair")
	await idle(6)
	ok(m.S.cards.size() == n14 + 1 and String(m.S.cards[m.sel_card]["name"]).begins_with("sit on the chair"), "14. typed 'sit on the chair' adds the chair's sit card (%d cards)" % m.S.cards.size())
	g14 = seat_gap()
	ok(bool(g14[0]), "14. typed: the hips are over the chair's seat")
	ok(float(g14[1]) > -0.005 and float(g14[1]) < 0.15, "14. typed: the hips end %.3f m above the seat's top (within 0.15)" % float(g14[1]))
	m._new_scene()
	await idle(4)
	home.card(0)   # a clip first (round 5 placed the chair after building moves): the panel is hidden, the strip shows
	await idle(6)
	m.playing = false
	m._prop_add("chair")
	await idle(4)
	var sit_s := home.strip.find_child("eh_sit_strip", true, false) as Button
	ok(home.strip.visible and sit_s != null and sit_s.visible and sit_s.is_visible_in_tree(), "14. a clip built, then a chair placed: 'Sit on it' is on the strip (the panel is hidden)")
	var n14s: int = m.S.cards.size()
	if sit_s != null:
		sit_s.pressed.emit()
	await idle(6)
	m.playing = false   # the clip plays from its start (the walk): look at the sit card itself
	var k14s: int = m.sel_card
	m._card_pick(k14s)
	await idle(3)
	g14 = seat_gap()
	ok(String(m.S.cards[k14s]["name"]).begins_with("sit on the chair") and k14s == m.S.cards.size() - 1, "14. the sit card comes after the clip (card %d of %d: '%s')" % [k14s + 1, m.S.cards.size(), String(m.S.cards[k14s]["name"])])
	ok(m.S.cards.size() > n14s and bool(g14[0]) and float(g14[1]) > -0.005 and float(g14[1]) < 0.15, "14. the strip's Sit on it seats him on the chair after the clip (%d -> %d cards, %.3f m above the seat)" % [n14s, m.S.cards.size(), float(g14[1])])
	m._new_scene()
	await idle(4)
	var front := m.easy.views.find_child("easy_view_front", true, false) as Button
	var side := m.easy.views.find_child("easy_view_side", true, false) as Button
	var back := m.easy.views.find_child("easy_view_back", true, false) as Button
	var reset := m.easy.views.find_child("easy_view_reset", true, false) as Button
	ok(front != null and side != null and back != null and reset != null and m.easy.views.visible and front.visible, "14. Easy shows the view buttons Front, Side, Back, Reset view")
	m._turn_to(37.0, -8.0, m.dist, m.target, false)   # the camera starts off the front: Front must do the turn itself
	await idle(2)
	if front != null:
		front.pressed.emit()
		await create_timer(0.6).timeout
	var yf0: float = wrapf(m.yaw, -180.0, 180.0)
	ok(absf(yf0) < 0.01, "14. Front: the camera faces the front (yaw %.2f)" % m.yaw)
	if side != null:
		side.pressed.emit()
		await create_timer(0.6).timeout
	ok(absf(absf(wrapf(m.yaw, -180.0, 180.0)) - 90.0) < 0.5, "14. Side turns the camera 90 deg (yaw %.2f)" % m.yaw)
	if back != null:
		back.pressed.emit()
		await create_timer(0.6).timeout
	ok(absf(absf(wrapf(m.yaw, -180.0, 180.0)) - 180.0) < 0.5, "14. Back turns the camera 180 deg (yaw %.2f)" % m.yaw)
	if front != null:
		front.pressed.emit()
		await create_timer(0.6).timeout
	ok(absf(wrapf(m.yaw, -180.0, 180.0)) < 0.01, "14. Front returns the camera exactly (yaw %.3f)" % m.yaw)
	m._new_scene()
	await idle(4)

	# 15. EDIT A PICKED CARD (walk-through round 5, goal 3): a beginner picks the middle card, drags the arm, and THAT card takes
	# the new pose in place: one undo step ("Change pose"), the card count and the other cards unchanged; moving the timeline off
	# the card keeps the edit; Ctrl+Z puts the card's pose back. Real mouse: the card's picture is clicked, the arm dragged on the body.
	m._new_scene()
	await idle(2)
	home.card(0)   # the walk: several cards
	await idle(6)
	m.playing = false
	var n15: int = m.S.cards.size()
	var k15: int = n15 / 2
	ok(n15 >= 3, "15. the walk has %d cards: a middle one to pick" % n15)
	await click_ctl(pick_btn(k15))
	ok(m.sel_card == k15, "15. a real click picks the middle card %d (picked: %d)" % [k15 + 1, m.sel_card + 1])
	var before15: Dictionary = m.S.cards[k15]["pose"].duplicate(true)
	var others15: Array = []
	for i in n15:
		if i != k15:
			others15.append(m.S.cards[i]["pose"].duplicate(true))
	var undo15: int = m.undo.size()
	await drag_part("hand_r", Vector2(-70, -30))
	m.playing = false
	ok(m.S.cards.size() == n15, "15. the drag keeps the card count (%d -> %d)" % [n15, m.S.cards.size()])
	ok(not EasyMode.same_pose(m.S.cards[k15]["pose"], before15), "15. the picked card's pose changed (the arm is dragged)")
	ok(EasyMode.same_pose(m.S.cards[k15]["pose"], m.B.to_dict()), "15. the picked card holds the body's pose now (in place, no new card)")
	var others_same := true
	var oi := 0
	for i in n15:
		if i != k15:
			if not EasyMode.same_pose(m.S.cards[i]["pose"], others15[oi]):
				others_same = false
			oi += 1
	ok(others_same, "15. the other cards' poses are unchanged")
	ok(m.undo.size() == undo15 + 1 and String(m.undo[-1].get("easy", "")) == "Change pose",
		"15. the drag is one undo step named 'Change pose' (%d -> %d, '%s')" % [undo15, m.undo.size(), String(m.undo[-1].get("easy", ""))])
	var changed15: Dictionary = m.S.cards[k15]["pose"].duplicate(true)
	# moving the timeline off the card: the edit stays on that card
	var other15: int = k15 + 1 if k15 + 1 < n15 else k15 - 1
	await click_ctl(pick_btn(other15))
	ok(m.sel_card == other15, "15. a click on another card moves the pick (picked: %d)" % (m.sel_card + 1))
	ok(EasyMode.same_pose(m.S.cards[k15]["pose"], changed15), "15. moving the timeline off the card keeps the edit on it")
	# Ctrl+Z (repeated until the card is back: the pick is an undo step of its own) puts the card's pose back
	for z in 4:
		if EasyMode.same_pose(m.S.cards[k15]["pose"], before15):
			break
		var kz := InputEventKey.new()
		kz.keycode = KEY_Z
		kz.physical_keycode = KEY_Z
		kz.ctrl_pressed = true
		kz.pressed = true
		root.push_input(kz)
		await idle(3)
	ok(EasyMode.same_pose(m.S.cards[k15]["pose"], before15), "15. Ctrl+Z restores the picked card's pose")
	ok(m.S.cards.size() == n15, "15. the card count after the undo is the walk's %d (%d)" % [n15, m.S.cards.size()])
	m._new_scene()
	await idle(4)

	# 16. HELP IN EASY (walk-through round 5): a visible Help button on the panel opens the help (what Easy can do, and the tour);
	#     the strip after a clip has Help too; Show the tour is there
	m._new_scene()
	await idle(4)
	var help_btn := home.panel.find_child("eh_help", true, false) as Button
	ok(help_btn != null and help_btn.is_visible_in_tree(), "16. the panel has a visible Help button in Easy")
	var help_lbl := home.panel.find_child("eh_help_text", true, false) as Label
	ok(help_lbl != null and not help_lbl.visible, "16. the help text is hidden until Help is pressed")
	if help_btn != null:
		help_btn.pressed.emit()
		await idle(3)
	ok(help_lbl != null and help_lbl.is_visible_in_tree() and help_lbl.text.contains("Then") and help_lbl.text.contains("Library"),
		"16. Help opens the help text (what Easy can do: cards, typing, Then, Slower, Library, save video)")
	ok(card_btn(0) != null and not card_btn(0).is_visible_in_tree(), "16. the help text takes the picture cards' place while it is on")
	var tour_btn := home.panel.find_child("eh_help_tour", true, false) as Button
	ok(tour_btn != null and tour_btn.is_visible_in_tree(), "16. the help has a Show the tour button (the existing tour)")
	if help_btn != null:
		help_btn.pressed.emit()   # Help again: the cards come back
		await idle(3)
	ok(card_btn(0) != null and card_btn(0).is_visible_in_tree(), "16. Help again brings the picture cards back")
	m._new_scene()
	await idle(3)
	home.card(0)   # a walk built: the strip shows, with its own Help
	await idle(8)
	var strip_help := home.strip.find_child("eh_help_strip", true, false) as Button
	ok(strip_help != null and strip_help.is_visible_in_tree(), "16. the strip after a clip has a visible Help button")
	if strip_help != null:
		strip_help.pressed.emit()
		await idle(4)
	ok(home.shown() == "panel" and help_lbl != null and help_lbl.is_visible_in_tree(), "16. the strip's Help brings the panel up with the help text")
	m._new_scene()
	await idle(4)

	# 17. A TYPED QUESTION IS ANSWERED WITH HELP (walk-through round 5): "how do I make him jump" names the move to type, never "doesn't know"
	m._new_scene()
	await idle(4)
	edit.text = "how do I make him jump"
	edit.text_submitted.emit(edit.text)
	await idle(4)
	var msg17 := (home.panel.find_child("eh_msg", true, false) as Label).text
	ok(msg17.contains("'jump'") and not msg17.contains("doesn't know") and not m.S.cards.size() > 0,
		"17. 'how do I make him jump' says to type 'jump' (panel '%s')" % msg17)
	ok(not m.ui_status.text.contains("doesn't know"), "17. the question is not refused in the status line either (status '%s')" % m.ui_status.text)
	edit.text = "how to make him dance"
	edit.text_submitted.emit(edit.text)
	await idle(4)
	var msg15b := (home.panel.find_child("eh_msg", true, false) as Label).text
	ok(msg15b.contains("Type a move") and not msg15b.contains("doesn't know"), "17. a how-to with no known move gives the help line ('%s')" % msg15b)
	m._new_scene()
	await idle(4)

	# 18. THE TYPED BOX CLEARS AFTER A MOVE IS USED, AND A CLICK SELECTS WHAT IS LEFT (walk-through round 5)
	m._new_scene()
	await idle(4)
	edit.text = "walk"
	edit.text_submitted.emit("walk")
	await idle(6)
	ok(m.S.cards.size() > 0, "18. typed 'walk' built a clip (cards %d)" % m.S.cards.size())
	ok(edit.text == "", "18. after a typed move is used, the box is empty (box '%s')" % edit.text)
	edit.text = "backflip"
	edit.text_submitted.emit("backflip")
	await idle(4)
	ok(edit.text == "backflip", "18. a line Kine cannot build keeps its words, for editing (box '%s')" % edit.text)
	home._change()
	await idle(4)
	ok(edit.has_selection() and edit.get_selected_text() == "backflip", "18. Change it selects the box's words, so typing replaces them (selected '%s')" % edit.get_selected_text())
	m._new_scene()
	await idle(4)

	# the end: Expert puts it all back
	m.easy.set_on(false, false)
	await idle()
	ok(home.shown() == "hidden", "Expert hides the panel and strip again")
	print("timings: " + str(times))
	print("card ms (click -> first moving frame): " + ", ".join(fast_ms))
	print("EASYHOME TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
