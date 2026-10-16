## godot --path . -s tests/symmetry_test.gd     (GATES CC1, UPGRADES #65; a real window, real drags and clicks)
## SYMMETRY MODE: the body made lopsided (the legs, the left arm), the weapon off (a two-hand grip refits the off hand
## after every edit: that is the grip's job, not symmetry's). The Symmetry button clicked on; then REAL drags: the right
## upper arm swung, the left forearm rolled (Shift), the right hand pulled (IK), and the right panel's bend slider moved.
## At EVERY frame of each drag, each sided joint the drag changed has its twin = its angles reflected (bend, side,
## -twist, clamped as Copy side does); the joints it did not change (the legs, lopsided) stay as they were; the middle
## (spine, neck, head) never changes. One Ctrl+Z undoes a drag and its mirror. Clicked off: a drag moves one side only.
extends SceneTree

var fails := 0
var m: Node
var worst := 0.0   # the largest twin mismatch seen on any frame, deg
var frames := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func spot(j: String, f := 0.5) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(c[0] + (c[1] - c[0]) * f)


func click(n: Control) -> void:
	var p := n.get_global_rect().get_center()
	await mouse(true, p)
	await mouse(false, p)
	await idle(2)


func mouse(down: bool, p: Vector2, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.shift_pressed = shift
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func ang() -> Dictionary:
	return m.B.ang.duplicate()


## a sided joint's twin, as symmetry must make it
func want(j: String) -> Vector3:
	var v: Vector3 = m.B.ang[j]
	return m.B.clamp_ang(Body.twin(j), Vector3(v.x, v.y, -v.z))


## every frame: the joints changed since the drag began have their twins mirrored; nothing else moved
func check_frame(a0: Dictionary, on: bool, bad: Array) -> void:
	frames += 1
	for j in Body.ORDER:
		var t := Body.twin(j)
		var changed: bool = not (m.B.ang[j] as Vector3).is_equal_approx(a0[j])
		if t == j:
			if changed:
				bad.append("the middle joint %s moved" % j)
			continue
		var tw_changed: bool = not (m.B.ang[t] as Vector3).is_equal_approx(a0[t])
		if not changed and not tw_changed:
			continue
		if on:
			var d: float = (m.B.ang[t] as Vector3).distance_to(want(j))
			worst = maxf(worst, d)
			if d > 1e-3:
				bad.append("%s %s -> twin %s %s, wanted %s" % [j, m.B.ang[j], t, m.B.ang[t], want(j)])


## a real drag of part j: press on it, 10 moves, release; checked every frame
func drag(j: String, d: Vector2, shift: bool, on: bool, f := 0.5) -> Array:
	var p := spot(j, f)
	var a0 := ang()
	var bad := []
	await mouse(true, p, shift)
	await idle(1)
	for k in 10:
		var e := InputEventMouseMotion.new()
		e.position = p + d * (k + 1) / 10.0
		e.global_position = e.position
		e.relative = d / 10.0
		e.shift_pressed = shift
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
		check_frame(a0, on, bad)
	await mouse(false, p + d, shift)
	await idle(2)
	if m.sel != j:
		bad.append("the press picked '%s', not %s" % [m.sel, j])
	return [bad, a0]


func moved(a0: Dictionary, js: Array) -> bool:
	return js.any(func(j): return not (m.B.ang[j] as Vector3).is_equal_approx(a0[j]))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.B.wep_on = false
	m._reset_all()
	# lopsided: the legs, and the left arm, not mirror images
	for jv in [["thigh_l", Vector3(35, 10, 0)], ["calf_l", Vector3(40, 0, 0)], ["thigh_r", Vector3(-10, 0, 5)], ["upperarm_l", Vector3(20, -40, 10)]]:
		m.B.ang[jv[0]] = m.B.clamp_ang(jv[0], jv[1])
	m.B.fk()
	m._refresh()
	await idle(3)
	var legs := ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
	var legs0 := ang()

	var b: Button = m.ui_ribbon["POSE"].get_children().filter(func(x): return x is Button and x.text == "Symmetry")[0]
	await click(m.ui_ribbon_tabs["POSE"])
	await click(b)
	ok(m.symmetry and b.button_pressed and b.icon != null, "1 the Symmetry button (POSE, with its icon) clicked: on and lit")

	var r := await drag("upperarm_r", Vector2(60, -50), false, true)
	ok(r[0].is_empty() and moved(r[1], ["upperarm_r"]) and moved(r[1], ["upperarm_l"]) and not moved(r[1], legs),
		"2 the right upper arm swung by a real drag: every frame the left one = it reflected, the lopsided legs untouched (bad: %s)" % [r[0].slice(0, 3)])
	r = await drag("upperarm_l", Vector2(50, 0), true, true)
	ok(r[0].is_empty() and moved(r[1], ["upperarm_l"]) and absf((m.B.ang["upperarm_r"] as Vector3).z + (m.B.ang["upperarm_l"] as Vector3).z) < 1e-3 and absf((m.B.ang["upperarm_l"] as Vector3).z) > 1.0,
		"3 the left upper arm ROLLED (Shift+drag; the forearm's roll is locked by design): the right one rolled the other way, twist %.1f / %.1f (bad: %s)" % [m.B.ang["upperarm_l"].z, m.B.ang["upperarm_r"].z, r[0].slice(0, 3)])
	r = await drag("hand_r", Vector2(-40, -60), false, true, 0.85)
	ok(r[0].is_empty() and moved(r[1], ["upperarm_r", "lowerarm_r"]) and moved(r[1], ["upperarm_l", "lowerarm_l"]) and not moved(r[1], legs),
		"4 the right hand PULLED (IK: the shoulder and elbow follow it): the left arm's same joints follow, reflected (bad: %s)" % [r[0].slice(0, 3)])
	var sl: Array = m.ui_side[1].find_children("*", "HSlider", true, false).filter(func(x): return x.is_visible_in_tree())
	var a0 := ang()
	var bad := []
	(sl[0] as HSlider).value = (sl[0] as HSlider).value + 25.0
	await idle(2)
	check_frame(a0, true, bad)
	ok(bad.is_empty() and moved(a0, ["hand_r"]) and moved(a0, ["hand_l"]), "5 the right panel's first slider moved 25 (the right hand, picked by the pull): the left hand follows (bad: %s)" % [bad.slice(0, 3)])
	ok(not moved(legs0, legs), "6 after 4 edits the legs are exactly as they were (lopsided, never copied)")

	# one Ctrl+Z = the drag and its mirror
	var before := ang()
	r = await drag("upperarm_r", Vector2(-50, 40), false, true)
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.ctrl_pressed = true
	for down in [true, false]:
		e.pressed = down
		root.push_input(e.duplicate())
		await process_frame
	await idle(2)
	ok(not moved(before, ["upperarm_r", "upperarm_l"]), "7 one Ctrl+Z after a drag: both arms back as before it (right %s, left %s)" % [m.B.ang["upperarm_r"], m.B.ang["upperarm_l"]])

	await click(b)
	r = await drag("upperarm_r", Vector2(60, -50), false, false)
	ok(not m.symmetry and moved(r[1], ["upperarm_r"]) and not moved(r[1], ["upperarm_l", "lowerarm_l", "hand_l"]), "8 clicked off: a drag of the right upper arm moves the right one only")
	print("     %d frames checked, the worst twin mismatch %.6f" % [frames, worst])
	print("SYMMETRY: %d failed" % fails)
	quit(1 if fails > 0 else 0)
