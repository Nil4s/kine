## godot --path . -s tests/r25_test.gd     (R25; needs a window)
## ONBOARDING: the first launch is a 3-step guide (BODY: pick a body; POSE: drag a part; ANIMATE: clip twice, play).
## BARS (stated before measuring):
##  1 a fresh settings file (no look/onboarded key): begin() shows step 1 on the BODY page; an existing file with the key: no guide (pending false).
##  2 the real actions move it on 1 -> 2 -> 3 -> done (a body preset; a real mouse drag of a hand; two clips and Play); no Next button exists
##    (the only button on the callout is Skip); the pages are BODY, POSE, ANIMATE; done writes the key.
##  3 a click on a part without a drag does not advance step 2.
##  4 Skip at step 2 writes the key; a relaunch (a fresh Onboarding reading the same file) has nothing pending, and begin is not auto-started.
##  5 PLACEMENT, each step, at UI size 100 and 150: the callout's rect is inside the window, does not overlap its target's rect (nor the
##    arrow's gap), and the arrow's tip ends short of the target by 1..12 px. Step 2's target is the drawn body; screenshot saved to $R25_PNG.
extends SceneTree

var fails := 0
var m: Node
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


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


func inside(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(c[0].lerp(c[1], 0.75))


func drag(j: String, moved := true) -> void:
	var p := inside(j)
	btn(true, p)
	await process_frame
	if moved:
		for i in 6:
			move(p + Vector2(8, -8) * (i + 1), Vector2(8, -8))
			await process_frame
	btn(false, p + (Vector2(48, -48) if moved else Vector2.ZERO))
	await idle(2)


func key_written() -> bool:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return cf.has_section_key("look", "onboarded")


## placement of the callout for the current step
func placed(label: String) -> void:
	var o: Onboarding = m.onboard
	await idle(3)
	var win: Rect2 = m.get_viewport().get_visible_rect()
	var c := Rect2(o.card.global_position, o.card.size)
	var t := o.target_rect()
	var gap := o.arrow_tip().distance_to(Vector2(clampf(o.arrow_tip().x, t.position.x, t.end.x), clampf(o.arrow_tip().y, t.position.y, t.end.y)))
	ok(t.size.x > 20 and t.size.y > 20, "%s: target rect %s" % [label, t])
	ok(win.encloses(c), "%s: callout %s inside window %s" % [label, c, win.size])
	ok(not c.intersects(t), "%s: callout does not overlap its target %s" % [label, t])
	ok(gap >= 1.0 and gap <= 12.0, "%s: arrow tip %.1f px short of the target" % [label, gap])


func _init() -> void:
	# 1. the rule
	var cf := ConfigFile.new()
	ok(Onboarding.is_due(cf), "a fresh config: due")
	cf.set_value("look", "onboarded", true)
	ok(not Onboarding.is_due(cf), "a config with the key: not due")

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	var o: Onboarding = m.onboard
	ok(o != null and o.step == -1 and not key_written(), "a test starts with no guide and no key (its own file %s)" % m.settings)
	m._new_scene()
	await idle()
	var cf2 := ConfigFile.new()
	cf2.load(m.settings)
	o.prepare(cf2, true)
	ok(o.pending, "fresh file + real launch: pending")
	var cf3 := ConfigFile.new()
	cf3.set_value("look", "onboarded", true)
	o.prepare(cf3, true)
	ok(not o.pending, "a file with the key: nothing pending (no guide)")
	o.prepare(cf2, false)
	ok(not o.pending, "a test/shot launch: nothing pending")

	# 2. the walk
	o.begin()
	await idle(3)
	ok(o.step == 0 and m.cur_page == "BODY" and o.card.visible, "step 1 shows on the BODY page")
	var btns := o.card.find_children("*", "Button", true, false)
	ok(btns.size() == 1 and (btns[0] as Button).text == "Skip", "the callout has only a Skip button (no Next)")
	await placed("step 1 @100")
	var s0 := JSON.stringify(m.S.body)
	m.ui_body._quick(95.0)
	await idle(3)
	ok(JSON.stringify(m.S.body) != s0 and o.step == 1 and m.cur_page == "POSE", "a body preset (95th) -> step 2 on the POSE page")
	await placed("step 2 @100")
	await drag("hand_r", false)
	ok(o.step == 1, "a click on a part without a drag does not advance step 2")
	await drag("hand_r")
	ok(o.step == 2 and m.cur_page == "ANIMATE", "a real drag of a hand -> step 3 on the ANIMATE page (step %d)" % o.step)
	await placed("step 3 clip @100")
	m._card_add()
	await idle(3)
	ok(o.step == 2, "one clip: still step 3")
	m._card_add()
	await idle(3)
	ok(o.step == 2, "two clips, not playing: still step 3")
	await placed("step 3 play @100")
	m._toggle_play()
	await idle(3)
	ok(o.step == -1 and not o.card.visible and key_written(), "Play after two clips: done, callout gone, key written")
	m._toggle_play()
	await idle(2)

	# 3. skip at step 2, relaunch
	var cfg: String = m.settings
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg))
	ok(not key_written(), "(the test's own file cleared)")
	o.begin()
	await idle(2)
	m.ui_body._quick(5.0)
	await idle(3)
	ok(o.step == 1, "back at step 2")
	(o.card.find_child("onboard_skip", true, false) as Button).pressed.emit()
	await idle(2)
	ok(o.step == -1 and not o.card.visible and key_written(), "Skip at step 2: guide gone, key written")
	var re := Onboarding.new()
	var cf4 := ConfigFile.new()
	cf4.load(m.settings)
	re.prepare(cf4, true)
	ok(not re.pending and not Onboarding.is_due(cf4), "relaunch (re-init on the same file): nothing pending, never again")
	re.free()

	# 4. placement at 150 %
	m.get_window().size = Vector2i(1920, 1080)
	await idle(4)
	m._set_scale(150)
	await idle(4)
	ok(m.ui_scale == 150, "UI size 150 set (window %s)" % m.get_window().size)
	for k in 3:
		o.begin()
		o.step = -1
		o._go(k)
		await placed("step %d @150" % (k + 1))
	m._set_scale(100)
	await idle(3)
	for k in 3:
		o._go(k)
		await placed("step %d @100 (again)" % (k + 1))

	# 5. the screenshot: step 2, pointing at the body
	o._go(1)
	await idle(6)
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OS.get_environment("R25_PNG") if OS.get_environment("R25_PNG") != "" else TMP + "r25.png"))
	var c := Rect2(o.card.global_position, o.card.size)
	var bodyr := o.body_rect()
	ok(c.get_center().x > bodyr.end.x or c.get_center().x < bodyr.position.x, "step 2 callout sits beside the body (card %s, body %s)" % [c, bodyr])
	o.finish(true, false)
	print("fails=", fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
