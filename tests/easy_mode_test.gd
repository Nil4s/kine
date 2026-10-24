## godot --path . -s tests/easy_mode_test.gd     (EASY MODE, docs/ROADMAP.md 3 and 4; needs a window)
## The mode rule (fresh = Easy, existing = Expert, a test = Expert unless it says so); Easy shows exactly the 7 big
## buttons (More holds the rest, one click away) and hides the expert panels; each action runs; Expert puts every panel's visibility back exactly
## as it was; the tour advances on the real actions only. The settings are the test's own file (user://poser_test_*.cfg).
extends SceneTree

const LABELS := ["Library", "Save video", "Play / Stop", "Undo", "New scene", "More", "Switch to Expert"]   # the bar (7)
const MORE := ["Save this pose as a card", "Move his arms and legs", "Redo", "Open a saved scene", "Copy a video", "Save the scene", "Flip left and right", "Put his feet on the floor"]

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


## a point well inside the part's own capsule (the middle of a hand is nearer its forearm's pick)
func inside(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(c[0].lerp(c[1], 0.75))


## a real drag of a part: press on it, move in steps, let go
func drag(j: String) -> void:
	var p := inside(j)
	btn(true, p)
	await process_frame
	for i in 6:
		move(p + Vector2(8, -8) * (i + 1), Vector2(8, -8))
		await process_frame
	btn(false, p + Vector2(48, -48))
	await process_frame


## every card's line (the picture's name button and the timing line): text by node name, "" when none
func card_lines() -> Dictionary:
	var out := {}
	for n in m.ui_cards.find_children("*", "Button", true, false):
		if n.name == "b_pick" or n.name == "b_timing":
			out[str(n.get_parent().get_parent().name) + "/" + str(n.name)] = String(n.text)
	return out


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the words on the Easy bar's Undo button (its child Label, as easy_mode._big builds it)
func undo_words() -> String:
	var b: Button = m.easy.button("Undo")
	return String(b.get_node("label").text) if b != null else "?"


func panels() -> Array:
	return [m.ui_top_bar, m.ui_side_of["left"], m.ui_side_of["right"], m.ui_cube, m.ui_nav, m.ui_bh, m.ui_play_row] + m.ui_rails.values()


func vis_now() -> Array:
	return panels().map(func(n): return n.visible)


func cfg_mode() -> String:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return String(cf.get_value("look", "mode", ""))


func _init() -> void:
	# 1. the rule, from in-memory settings (no window needed for this part)
	var cf := ConfigFile.new()
	ok(EasyMode.mode_for(cf), "a fresh config (no file, no sections) is Easy")
	cf.set_value("layout", "fold_left", true)
	ok(not EasyMode.mode_for(cf), "an existing config (sections, no mode key) stays Expert")
	cf.set_value("look", "mode", "easy")
	ok(EasyMode.mode_for(cf), "a stored mode wins over the sections")
	cf.set_value("look", "mode", "expert")
	ok(not EasyMode.mode_for(cf), "a stored Expert is Expert")
	ok(not EasyMode.mode_for(ConfigFile.new(), true), "under a test with no key: Expert (the suites keep their app)")

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	ok(m.easy != null and not m.easy.on, "a test starts in Expert (no key in its own settings file)")
	ok(cfg_mode() == "", "and writes no mode into its settings file at start")

	# 2. Expert before anything: remember every panel's visibility, then check Easy hides exactly those
	m._new_scene()
	await idle()
	var before := vis_now()
	var dummy0: bool = m.dummy_on
	m.easy.set_on(true, false)
	await idle()
	ok(dummy0 and not m.dummy_on, "Easy puts the target dummy away (it stood between the camera and the body): on %s -> %s" % [str(dummy0), str(m.dummy_on)])
	ok(m.easy.bar.visible, "Easy: the bar is on screen")
	var bts: Array = m.easy.labels()
	var shown: Array = []
	for n in m.easy.bar.find_children("*", "Button", true, false):
		if n.get_meta("label", "") != "":
			shown.append(n.get_meta("label"))
	ok(shown.size() == 7 and LABELS.all(func(l): return l in shown) and bts.size() == 7, "Easy shows exactly the 7 labelled buttons: %s" % str(shown))
	ok(vis_now().all(func(v): return not v), "Easy hides every expert panel, top tools, the scene header, the play row and the nav/cube %s" % str(range(panels().size()).filter(func(i): return panels()[i].visible)))
	ok(m.ui_bp.visible, "the bottom panel (timeline and cards) stays: the tour and Play need it")
	ok(m.lw() == 0.0 and m.rw() == 0.0, "the body view takes the room the hidden side panels had")
	ok(m.easy.button("Undo") != null and m.easy.more_labels() == MORE, "Undo is on the bar; the More menu holds the other %d actions" % MORE.size())
	ok(m.easy.button("New scene").pressed.get_connections().size() > 0 and m.easy.button("Save video").pressed.get_connections().size() > 0, "New scene and Save video are wired (not run here: a dialog / a render)")
	
	m._refresh()
	var dots_on: Array = m.dots.values().filter(func(d): return d.visible)
	ok(not m.tag.visible and dots_on.is_empty() and m.axis_tags.all(func(a): return not a.visible),
		"Easy quiet: no part name tag (%s), no joint dots (%d shown), no axis names on the floor" % [str(m.tag.visible), dots_on.size()])
	m.easy.set_on(false, false)
	await idle()
	m._refresh()
	ok(m.tag.visible and m.dots.values().any(func(d): return d.visible) and m.axis_tags.all(func(a): return a.visible),
		"Expert: the part name tag, the joint dots and the axis names are back")
	ok(vis_now() == before, "Expert restores every panel's visibility exactly as it was, on the same scene: %s" % str(before))
	ok(m.dummy_on == dummy0, "Expert brings the target dummy back as it was (%s)" % str(m.dummy_on))

	# 2b. the hint row and the readout: Easy's one plain line and no readout; Expert's exactly as they were (stored in Expert first)
	m.ui_mouse.refresh()
	await idle(2)
	var x_hint: String = m.ui_mouse.shown_text()
	var x_bar_text: String = m.ui_bar.text
	var x_bar_vis: bool = m.ui_bar.visible
	m.easy.set_on(true, false)
	await idle(4)
	m.ui_mouse.refresh()
	await idle(2)
	var e_hint: String = m.ui_mouse.shown_text()
	var e_bad_words := []
	for w in ["nothing", "pan", "pick", "Middle"]:
		if e_hint.contains(w):
			e_bad_words.append(w)
	ok(e_hint != "" and e_bad_words.is_empty(), "Easy: the hint row is one plain line with none of nothing / pan / pick / Middle: '%s'" % e_hint)
	ok(not m.ui_bar.visible, "Easy: the readout (the card count and the seconds) is hidden")
	var w_status: String = m.ui_status.text
	m.ui_status.text = "Your video is saved: punch_2.mp4"   # the welcome line is gone: the one-line hint row must show
	await idle(2)
	m.ui_mouse.refresh()
	await idle(2)
	ok(m.ui_mouse.visible, "Easy: the hint row is on screen once the welcome line is gone")
	m.ui_status.text = w_status
	m.easy.set_on(false, false)
	await idle(4)
	m.ui_mouse.refresh()
	await idle(2)
	ok(m.ui_mouse.shown_text() == x_hint, "Expert switch: the hint row is its old text again ('%s')" % x_hint)
	ok(m.ui_bar.visible == x_bar_vis and m.ui_bar.text == x_bar_text, "Expert switch: the readout is shown again, as it was ('%s')" % x_bar_text)
	m.easy.set_on(true, false)
	await idle()

	# 3. each button runs its action
	m.easy.pick_more("Move his arms and legs")
	await idle()
	ok(m.ui_status.text.begins_with("Drag a part"), "Move his arms and legs says how to pose, on the say line")
	var n0: int = m.S.cards.size()
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.S.cards.size() == n0 + 1, "Save this pose as a card adds a card (%d -> %d)" % [n0, m.S.cards.size()])
	m.easy.button("Undo").pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0, "Undo (on the bar) takes the card back")
	m.easy.pick_more("Redo")
	await idle()
	ok(m.S.cards.size() == n0 + 1, "Redo puts it back")
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.S.cards.size() == n0 + 2, "a second card: two are needed to play")
	m._pose_words("raise the right arm 90")
	await idle()
	var body_before := JSON.stringify(m.B.state())
	m.easy.pick_more("Flip left and right")
	await idle()
	ok(JSON.stringify(m.B.state()) != body_before, "Flip left and right changes the body (a raised right arm goes to the left)")
	m.easy.button("Undo").pressed.emit()
	await idle()
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(m.playing, "Play / Stop starts the scene (two cards)")
	await idle(2)
	ok(m.easy.button("Play / Stop").text == "Stop", "while it plays the button says Stop (%s)" % m.easy.button("Play / Stop").text)
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(not m.playing, "Play / Stop again stops it")
	await idle(2)
	ok(m.easy.button("Play / Stop").text == "Play", "stopped, the button says Play (%s)" % m.easy.button("Play / Stop").text)
	m.easy.pick_more("Put his feet on the floor")
	await idle()
	ok(true, "Put his feet on the floor runs without an error")
	# B: the More menu closes as its item runs (after_08: it stayed open behind New scene's "Unsaved changes" dialog)
	ok(not m.easy._more.visible, "B: the More menu is closed after its item (Put his feet on the floor) runs")
	m.easy._more_open()
	await idle()
	ok(m.easy._more.visible, "B: More opens its menu (precondition for the bar check)")
	m.easy.button("Play / Stop").pressed.emit()   # a bar button runs while More is open: More closes too
	await idle()
	ok(not m.easy._more.visible, "B: pressing a bar button (Play / Stop) closes the More menu that was open")
	m.easy.button("Play / Stop").pressed.emit()   # stop again
	await idle()
	m.easy.pick_more("Open a saved scene")
	await idle()
	# Open (drafts 10-24): the SAVED scenes the list has, then a "Recent drafts" separator and the newest 5 drafts (not every draft)
	var saved_rows := 0
	for i in m.ui_scenes.item_count:
		var mp := String(m.ui_scenes.get_item_metadata(i))
		if not (mp.begins_with("#") or m.is_draft_path(mp)):
			saved_rows += 1
	var nd := mini(5, m.draft_paths().size())
	var want_menu := saved_rows + (nd + 1 if nd > 0 else 0)
	ok(m.easy._menu.item_count == want_menu and saved_rows > 0, "Open a saved scene lists the saved scenes (%d) then 'Recent drafts' with the newest %d: %d rows, want %d" % [saved_rows, nd, m.easy._menu.item_count, want_menu])
	m.easy._menu.hide()
	await idle()

	# 4. the tour: each step waits, and moves on only on the real action
	m._new_scene()
	await idle()
	m.easy.tour_start()
	await idle()
	ok(m.easy.tour_step == 0 and m.easy.tour_card.visible, "the tour starts at step 1 and its card is on screen")
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.easy.tour_step == 0, "step 1 (drag a hand) does not move on for a Save-the-pose press")
	await drag("hand_r")
	await idle()
	ok(m.easy.tour_step == 1, "step 1: dragging a hand moves on (now %d)" % (m.easy.tour_step + 1))
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.easy.tour_step == 2, "step 2: Save this pose as a card moves on (now %d)" % (m.easy.tour_step + 1))
	var ph0: float = m.playhead
	var tl: Control = m.ui_timeline
	var length: float = m._ps().length()
	var at_t := 0.25 * length if absf(ph0 - 0.25 * length) > 0.1 * length else 0.75 * length   # far from where it is now
	var x0: float = tl.x_of(at_t)   # a real click on the ruler
	var y := Timeline.RULER * 0.5   # the ruler (the top strip of the timeline) is the scrub: a click there moves the playhead
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(x0, y)
	tl._gui_input(press)
	await idle()
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(x0, y)
	tl._gui_input(rel)
	await idle()
	print("probe tl ph0=%.3f ph=%.3f step=%d playing=%s len=%.2f at=%.2f" % [ph0, m.playhead, m.easy.tour_step, m.playing, length, at_t])
	ok(absf(m.playhead - ph0) > 0.005 and m.easy.tour_step == 3, "step 3: a click on the timeline moves the playhead and moves on (playhead %.2f)" % m.playhead)
	await drag("hand_l")
	await idle()
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.easy.tour_step == 4, "step 4: change the pose and save again moves on (now %d)" % (m.easy.tour_step + 1))
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(m.easy.tour_step == -1 and not m.easy.tour_due(), "step 5: Play ends the tour, and it is done (not due again)")
	m.playing = false
	# Skip, from a fresh settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	m.easy.tour_start()
	await idle()
	m.easy.tour_card.find_child("easy_tour_skip", true, false).pressed.emit()
	await idle()
	ok(m.easy.tour_step == -1 and not m.easy.tour_card.visible and not m.easy.tour_due(), "Skip ends the tour and it is not due again")

	# 4b. a Punch card (EasyHome.CARDS 3): Easy's card lines and bottom panel, and Expert's exactly as they were
	m.easy.set_on(false, false)
	await idle()
	m.easy.home.card(3)
	await idle(12)
	var x_lines := card_lines()
	var x_h: float = m.ui_bp.size.y
	m.easy.set_on(true, false)
	await idle(12)
	m._refresh()
	await idle(2)
	var e_lines := card_lines()
	var e_names := []
	for c in m.S.cards:
		e_names.append(m._easy_card_name(c["name"]))
	var e_bad := []
	for k in e_lines:
		var t: String = e_lines[k]
		if t.find(" s") >= 0 or t.to_lower().find("hold") >= 0 or k.ends_with("/b_timing"):
			e_bad.append(t)
	var e_picks := []
	for k in e_lines:
		if k.ends_with("/b_pick"):
			e_picks.append(e_lines[k])
	ok(m.S.cards.size() >= 4 and e_bad.is_empty(), "Easy after the Punch card: no card line has seconds, a hold or a timing line %s" % str(e_bad))
	ok(e_picks.size() == m.S.cards.size() and e_picks.all(func(t): return t in e_names) and e_picks[0] == "Guard", "Easy: each card's line is its name, capitalised (%s)" % str(e_picks))
	ok(m.ui_bp.size.y <= m.ui_card_row.size.y + 40.0, "Easy: the bottom panel (%d px) is no taller than the card row (%d px) + 40" % [int(m.ui_bp.size.y), int(m.ui_card_row.size.y)])
	var lim := []
	for j in Body.ORDER:
		if m.part_look(j) == "limit":
			lim.append(j)
	ok(not lim.is_empty(), "the Punch card puts a body part at its joint limit (so the bar below has something to check): %s" % str(lim))
	ok(lim.all(func(j): return m.skin_col(j).a == 0.0), "Easy: no body part has the limit tint (%s)" % str(lim))
	m.easy.set_on(false, false)
	await idle(12)
	m._refresh()
	await idle(2)
	ok(lim.any(func(j): return m.skin_col(j).a > 0.0), "Expert: the limit tint shows on the same body (the check above can see it)")
	ok(card_lines() == x_lines, "Expert switch: every card line is the old text again (%d lines)" % x_lines.size())
	ok(absf(m.ui_bp.size.y - x_h) < 0.5, "Expert switch: the bottom panel is its old height (%d px -> %d px)" % [int(x_h), int(m.ui_bp.size.y)])
	m.easy.set_on(true, false)
	await idle(4)

	# 5. Expert: every panel's visibility exactly as before the Easy switch
	m.easy.button("Switch to Expert").pressed.emit()
	await idle()
	ok(not m.easy.on and not m.easy.bar.visible, "Switch to Expert leaves Easy")
	ok(m.ui_top_bar.visible and m.ui_side_of["left"].visible and m.ui_side_of["right"].visible and m.ui_bh.visible and m.ui_cube.visible and m.ui_nav.visible, "Expert switch: the top bar, both side panels, the scene header, cube and nav are back")
	ok(cfg_mode() == "expert", "the Expert choice is saved in the settings file")
	ok(m.lw() == m.LEFT_W and m.rw() == m.RIGHT_W, "the view's room is the side panels' again")
	m.easy.set_on(true)
	await idle()
	ok(m.easy.on and cfg_mode() == "easy", "turning Easy on again is saved as easy")
	m.easy.set_on(false)
	await idle()

	# 6. UNDO SAYS WHAT IT TAKES BACK (Easy only): "Undo: Walk", "Undo: Faster", "Undo" with nothing to undo; the toast says the short name
	m.easy.set_on(true, false)
	m.undo.clear()
	m.redo.clear()
	m._new_scene()
	m.undo.clear()
	m.redo.clear()
	await idle(3)
	ok(undo_words() == "Undo", "6: an empty scene with nothing to undo: the Undo button reads 'Undo' (%s)" % undo_words())
	m.easy.home.panel.find_child("eh_card_0", true, false).pressed.emit()   # Walk
	await idle(30)
	ok(undo_words() == "Undo: Walk", "6: after the Walk card the Undo button reads 'Undo: Walk' (%s)" % undo_words())
	m.easy.home.strip.find_child("eh_faster", true, false).pressed.emit()
	await idle(10)
	ok(undo_words() == "Undo: Faster", "6: after Faster the Undo button reads 'Undo: Faster' (%s)" % undo_words())
	m.easy.button("Undo").pressed.emit()
	await idle(10)
	ok(undo_words() == "Undo: Walk", "6: after Undo the button reads 'Undo: Walk' (%s)" % undo_words())
	ok(m.ui_toast != null and m.ui_toast.text == "Undid: Faster", "6: the toast after Undo says 'Undid: Faster' (%s)" % (m.ui_toast.text if m.ui_toast else "none"))
	m.easy.button("Undo").pressed.emit()
	await idle(10)
	ok(undo_words() == "Undo", "6: undoing the Walk card leaves nothing to undo: 'Undo' (%s)" % undo_words())
	# a placed library object is one undo step, named by its tile
	m._library_toggle()
	await idle(3)
	var sword_id := ""
	for it in m.ui_library.items:
		if it["name"] == "Sword":
			sword_id = String(it["id"])
	var u0: int = m.undo.size()
	var placed: bool = sword_id != "" and m.ui_library.place(sword_id)
	await idle(6)
	ok(placed and m.undo.size() == u0 + 1, "6: a library Sword is one undo step (%d -> %d steps; id '%s')" % [u0, m.undo.size(), sword_id])
	ok(undo_words() == "Undo: Sword", "6: after a library Sword the Undo button reads 'Undo: Sword' (%s)" % undo_words())
	m.easy.button("Undo").pressed.emit()
	await idle(4)
	ok(undo_words() == "Undo", "6: undoing the Sword leaves nothing to undo: 'Undo' (%s)" % undo_words())
	m.ui_library.hide_panel()
	# More's entries that change the body: one undo step each, named in Easy ("Flip", "Feet on floor")
	m.easy.pick_more("Flip left and right")
	await idle(4)
	ok(undo_words() == "Undo: Flip" and m.undo.size() == 1, "6: More > Flip left and right is one step: 'Undo: Flip' (%s, %d steps)" % [undo_words(), m.undo.size()])
	m.easy.button("Undo").pressed.emit()
	await idle(4)
	m.easy.pick_more("Put his feet on the floor")
	await idle(4)
	# feet on the floor keeps nothing on an empty scene: the step is dropped (Fixer.plant_all: "one undo step, or none"), so no step
	ok(undo_words() == "Undo" and m.undo.size() == 0, "6: More > Put his feet on the floor with nothing to plant adds no step (%s, %d steps)" % [undo_words(), m.undo.size()])
	# the button never grows: a long name is cut to 18 characters (+ "..") and the bar's button keeps its height
	var h0: float = m.easy.button("Undo").size.y
	m._step_easy = "a very long typed move name that is cut"
	m._push_undo()
	await idle(3)
	var cut := undo_words()
	ok(cut.begins_with("Undo: a very long type") and cut.length() <= 24 and cut.ends_with(".."), "6: a long name is cut in the button: '%s'" % cut)
	ok(is_equal_approx(m.easy.button("Undo").size.y, h0), "6: the Undo button keeps its height with a long name (%.0f -> %.0f px)" % [h0, m.easy.button("Undo").size.y])
	m._undo()
	await idle(2)
	# Expert: the step's name never uses the Easy short name, and Expert's Undo tooltip is the Expert name
	var ex: Dictionary = {"name": "Cards 1-8 at 80 %: the scene is now 3.96 s", "easy": "Faster"}
	ok(m._step_label(ex) == "Cards 1-8 at 80 %: the scene is now 3.96 s", "6: Expert's _step_label ignores the Easy name")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("EASY MODE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
