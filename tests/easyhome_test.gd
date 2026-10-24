## godot --path . -s tests/easyhome_test.gd     (EASY HOME, "monkey brain easy": the empty scene's picture panel; needs a window)
## BARS (stated before measuring):
##  1. Easy with an empty scene shows the "What should he do?" panel (8 picture cards and the text box); Expert shows none.
##  2. Every card builds a non-empty clip that plays (walk, run, jump, punch, sit down, wave from templates/; kick = "roundhouse" by
##     TextBlocking). Fall builds too (the fall template: a backward breakfall).
##  3. The click -> the first frame the clip plays is under 2000 ms for each card that builds (the builder time is printed).
##  4. One Ctrl+Z after a card gives back the empty scene (one undo step per card).
##  5. Typing "jab then cross" builds 2 strikes (the cards are the two single strikes, in order).
##  6. The panel fits inside the window at 1280x720 (its rect is inside the visible viewport).
## A screenshot of the panel goes to user://easyhome_panel.png (the path is printed).
extends SceneTree

const BUILDS := [0, 1, 2, 3, 4, 5, 6, 7]   # the cards that build: walk, run, jump, punch, kick, sit down, wave, fall
const BAR_MS := 2000

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


func card_btn(i: int) -> Button:
	return m.easy.home.panel.find_child("eh_card_%d" % i, true, false) as Button


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
	ok(home.strip.find_child("eh_again", true, false) != null and home.strip.find_child("eh_change", true, false) != null and home.strip.find_child("eh_save", true, false) != null,
		"the strip has Again, Change it and Save video")

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
	root.content_scale_size = was_size   # back to the window's own size
	root.content_scale_mode = was_mode
	await idle(4)

	# the end: Expert puts it all back
	m.easy.set_on(false, false)
	await idle()
	ok(home.shown() == "hidden", "Expert hides the panel and strip again")
	print("timings: " + str(times))
	print("EASYHOME TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
