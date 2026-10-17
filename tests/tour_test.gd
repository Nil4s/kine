## godot --path . -s tests/tour_test.gd     (GATES S4; needs a window)
## FIRST-RUN TOUR, driven by the real input: each step shows, does NOT move on by itself (a few idle frames), and moves
## on when the user does the thing: a click on the body, a drag, Enter twice, Space, the Check button. The end saves
## "tour done"; Skip ends it and saves too; then the tour is no longer due (a later start shows nothing).
extends SceneTree

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


func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = down
		root.push_input(e)
	await process_frame


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the step stays put while nothing happens, then the action moves it on
func step(k: int, what: String, act: Callable) -> void:
	await idle()
	var shown: bool = m.ui_tour.visible and String(m.ui_tour.get_child(0).get_child(0).get_child(0).text).begins_with("Step %d of 5" % (k + 1))
	ok(m.tour_step == k and shown, "step %d (%s) shows and waits" % [k + 1, what])
	await act.call()
	await idle()
	ok(m.tour_step == k + 1 or (k == 4 and m.tour_step == -1), "  %s -> moves on (now %d)" % [what, m.tour_step])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	ok(m._tour_due() and m.tour_step == -1, "a fresh start owes the tour (a test does not start it by itself)")
	m._tour_start()
	# QQ2: the APP changing what a step watches (a pick by code, a scene loaded: no click, no key) moves nothing on
	await idle()
	m.sel = "head"
	m._refresh()
	m._load_scene("res://scenes/combo3.json")
	m.sel = "head"
	await idle(6)
	ok(m.tour_step == 0, "QQ2 the app picking a part and loading a scene by itself (no input): still step 1 (now %d)" % (m.tour_step + 1))
	m._new_scene()
	await idle()
	m._tour_start()
	var p := spot("upperarm_l")
	await step(0, "click a part", func():
		btn(true, p)
		await process_frame
		btn(false, p)
		await process_frame)
	await step(1, "drag it", func():
		btn(true, p)
		await process_frame
		for i in 6:
			move(p + Vector2(8, -8) * (i + 1), Vector2(8, -8))
			await process_frame
		btn(false, p + Vector2(48, -48))
		await process_frame)
	await step(2, "clip two moments", func():
		await key(KEY_ENTER)
		await idle(2)
		ok(m.tour_step == 2, "  one clip is not two: still step 3")
		await key(KEY_ENTER))
	await step(3, "play", func(): await key(KEY_SPACE))
	m.playing = false
	await step(4, "check", func():
		var cb: Array = m.ui_root.find_children("*", "Button", true, false).filter(func(b): return b.text == "Check" and b.is_visible_in_tree())
		ok(cb.size() >= 1, "  the Check button is on screen")
		cb[0].pressed.emit()
		await process_frame)
	ok(not m.ui_tour.visible and not m._tour_due(), "the end: the card goes and the tour is no longer due")
	# Skip, from a fresh settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	ok(m._tour_due(), "settings gone: due again")
	m._tour_start()
	await idle()
	var skip: Button = m.ui_tour.get_child(0).get_child(0).get_child(1)
	skip.pressed.emit()
	await idle()
	ok(m.tour_step == -1 and not m.ui_tour.visible and not m._tour_due() and skip.text == "Skip", "Skip ends it and it is not due again")
	# QQ3: the close (x) and Esc, each from a fresh settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	m._tour_start()
	await idle()
	var x: Button = m.ui_tour.find_child("tour_close", true, false)
	ok(x != null and x.is_visible_in_tree(), "QQ3 the card has a close (x) on screen")
	if x != null:
		var r := x.get_global_rect()
		btn(true, r.get_center())
		await process_frame
		btn(false, r.get_center())
		await idle()
	ok(m.tour_step == -1 and not m.ui_tour.visible and not m._tour_due(), "QQ3 a click on the (x) closes it and it is not due again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	m._tour_start()
	await idle()
	await key(KEY_ESCAPE)
	await idle()
	ok(m.tour_step == -1 and not m.ui_tour.visible and not m._tour_due(), "QQ3 Esc closes it and it is not due again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("TOUR TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
