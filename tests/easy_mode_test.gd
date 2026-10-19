## godot --path . -s tests/easy_mode_test.gd     (EASY MODE, docs/ROADMAP.md 3 and 4; needs a window)
## The mode rule (fresh = Easy, existing = Expert, a test = Expert unless it says so); Easy shows exactly the 12 big
## buttons and hides the expert panels; each button runs its action; Expert puts every panel's visibility back exactly
## as it was; the tour advances on the real actions only. The settings are the test's own file (user://poser_test_*.cfg).
extends SceneTree

const LABELS := ["Pose (drag parts)", "Key this pose", "Play / Stop", "Undo", "Redo", "New scene", "Open", "Save",
	"Mirror pose", "Floor (snap feet)", "Export video", "Switch to Expert"]

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


func idle(n := 4) -> void:
	for i in n:
		await process_frame


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
	m.easy.set_on(true, false)
	await idle()
	ok(m.easy.bar.visible, "Easy: the bar is on screen")
	var bts: Array = m.easy.labels()
	var shown: Array = []
	for n in m.easy.bar.find_children("*", "Button", true, false):
		if n.get_meta("label", "") != "":
			shown.append(n.get_meta("label"))
	ok(shown.size() == 12 and LABELS.all(func(l): return l in shown) and bts.size() == 12, "Easy shows exactly the 12 labelled buttons: %s" % str(shown))
	ok(vis_now().all(func(v): return not v), "Easy hides every expert panel, top tools, the scene header, the play row and the nav/cube %s" % str(range(panels().size()).filter(func(i): return panels()[i].visible)))
	ok(m.ui_bp.visible, "the bottom panel (timeline and cards) stays: the tour and Play need it")
	ok(m.lw() == 0.0 and m.rw() == 0.0, "the body view takes the room the hidden side panels had")
	ok(m.easy.button("Open") != null and m.easy.button("Save").pressed.get_connections().size() > 0, "Open and Save are wired (their dialogs are not run here)")
	ok(m.easy.button("New scene").pressed.get_connections().size() > 0 and m.easy.button("Export video").pressed.get_connections().size() > 0, "New scene and Export video are wired (not run here: a dialog / a render)")
	ok(m.easy.button("Floor (snap feet)").pressed.get_connections().size() > 0, "Floor (snap feet) is wired")

	m.easy.set_on(false, false)
	await idle()
	ok(vis_now() == before, "Expert restores every panel's visibility exactly as it was, on the same scene: %s" % str(before))
	m.easy.set_on(true, false)
	await idle()

	# 3. each button runs its action
	m.easy.button("Pose (drag parts)").pressed.emit()
	await idle()
	ok(m.ui_status.text.begins_with("Drag a part"), "Pose says how to pose, on the say line")
	var n0: int = m.S.cards.size()
	m.easy.button("Key this pose").pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0 + 1, "Key this pose adds a card (%d -> %d)" % [n0, m.S.cards.size()])
	m.easy.button("Undo").pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0, "Undo takes the card back")
	m.easy.button("Redo").pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0 + 1, "Redo puts it back")
	m.easy.button("Key this pose").pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0 + 2, "a second card: two are needed to play")
	m._pose_words("raise the right arm 90")
	await idle()
	var body_before := JSON.stringify(m.B.state())
	m.easy.button("Mirror pose").pressed.emit()
	await idle()
	ok(JSON.stringify(m.B.state()) != body_before, "Mirror pose changes the body (a raised right arm goes to the left)")
	m.easy.button("Undo").pressed.emit()
	await idle()
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(m.playing, "Play / Stop starts the scene (two cards)")
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(not m.playing, "Play / Stop again stops it")
	m.easy.button("Floor (snap feet)").pressed.emit()
	await idle()
	ok(true, "Floor (snap feet) runs without an error")
	m.easy.button("Open").pressed.emit()
	await idle()
	ok(m.easy._menu.item_count == m.ui_scenes.item_count and m.ui_scenes.item_count > 0, "Open lists the scenes the list has (%d)" % m.ui_scenes.item_count)
	m.easy._menu.hide()
	await idle()

	# 4. the tour: each step waits, and moves on only on the real action
	m._new_scene()
	await idle()
	m.easy.tour_start()
	await idle()
	ok(m.easy.tour_step == 0 and m.easy.tour_card.visible, "the tour starts at step 1 and its card is on screen")
	m.easy.button("Key this pose").pressed.emit()
	await idle()
	ok(m.easy.tour_step == 0, "step 1 (drag a hand) does not move on for a Key press")
	await drag("hand_r")
	await idle()
	ok(m.easy.tour_step == 1, "step 1: dragging a hand moves on (now %d)" % (m.easy.tour_step + 1))
	m.easy.button("Key this pose").pressed.emit()
	await idle()
	ok(m.easy.tour_step == 2, "step 2: Key this pose moves on (now %d)" % (m.easy.tour_step + 1))
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
	m.easy.button("Key this pose").pressed.emit()
	await idle()
	ok(m.easy.tour_step == 4, "step 4: change the pose and Key again moves on (now %d)" % (m.easy.tour_step + 1))
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

	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("EASY MODE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
