## godot --path . -s tests/multi_select_test.gd     (GATES II1, UPGRADES #66; a real window, real clicks and drags)
## SEVERAL PARTS AT ONCE: a plain click on the left thigh, real Ctrl+clicks on the right thigh and the left upper arm:
## a group of 3, no undo step from the Ctrl+clicks, all drawn selected, the title says "+ 2 more". A real drag on the
## left thigh (a member: the group kept): every member turned by the same change (the right thigh exactly, the arm at
## least changed), ONE undo step; Ctrl+Z puts all three back. Ctrl+click on the arm: it leaves the group. A locked member
## stays put in a group drag. A Ctrl+drag on the right hand is still the elbow swing. A plain click off the group: one
## part. The ring opened on another part ends the group.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func btn(b: MouseButton, down: bool, p: Vector2, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = p
	e.global_position = p
	e.ctrl_pressed = ctrl
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if b == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)
	await idle()


func move(p: Vector2, rel: Vector2, ctrl := false, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.ctrl_pressed = ctrl
	e.button_mask = mask
	root.push_input(e)
	await idle()


func click(j: String, ctrl := false) -> void:
	var p := spot(j)
	await btn(MOUSE_BUTTON_LEFT, true, p, ctrl)
	await btn(MOUSE_BUTTON_LEFT, false, p, ctrl)


func drag(j: String, step: Vector2, ctrl := false, f := 0.5) -> void:
	var p := spot(j, f)
	await btn(MOUSE_BUTTON_LEFT, true, p, ctrl)
	for i in 5:
		p += step
		await move(p, step, ctrl)
	await btn(MOUSE_BUTTON_LEFT, false, p, ctrl)


func spot(j: String, f := 0.5) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] as Vector3).lerp(c[1], f))


func ang(j: String) -> Vector3:
	return m.B.ang[j]


func col(j: String) -> Color:
	return m.skin_col(j)   # PRECISE PICK: the light is on the part's own skin


func members() -> Array:
	var g: Array = m.group()
	g.sort()
	return g


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	m.sel = "head"
	m._refresh()
	await idle(3)
	await click("thigh_l")
	var u0: int = m.undo.size()
	await click("thigh_r", true)
	await click("upperarm_l", true)
	var g: Array = members()
	var lit := true
	for j in g:
		if not col(j).is_equal_approx(col(m.sel)):
			lit = false
	ok(g == ["thigh_l", "thigh_r", "upperarm_l"] and m.undo.size() == u0 and lit and m.ui_title.text.contains("+ 2 more") and m.bar_text().contains("+ 2 more"),
		"1 a click on the left thigh, Ctrl+clicks on the right thigh and the left upper arm: %s, +%d undo steps, all drawn selected %s, title '%s'" % [g, m.undo.size() - u0, lit, m.ui_title.text])
	var a0 := {}
	for j in g:
		a0[j] = ang(j)
	await drag("thigh_l", Vector2(0, -30))
	var d: Vector3 = ang("thigh_l") - a0["thigh_l"]
	var dr: Vector3 = ang("thigh_r") - a0["thigh_r"]
	var da: Vector3 = ang("upperarm_l") - a0["upperarm_l"]
	ok(members() == g and d.length() > 5.0 and dr.is_equal_approx(d) and da.length() > 1.0 and m.undo.size() == u0 + 1,
		"2 a real drag on the left thigh: it turned %s, the right thigh %s (the same), the left upper arm %s; the group kept; +%d undo step" % [d, dr, da, m.undo.size() - u0])
	m._undo()
	await idle()
	var back := true
	for j in g:
		if not ang(j).is_equal_approx(a0[j]):
			back = false
	ok(back, "3 Ctrl+Z: all three back (%s)" % [g.map(func(j): return ang(j))])
	m.sel = "thigh_l"   # undo restores the body, not who is picked; the group is still thigh_l's
	m._refresh()
	var u1: int = m.undo.size()
	await click("upperarm_l", true)
	ok(members() == ["thigh_l", "thigh_r"] and m.undo.size() == u1, "4 Ctrl+click on the arm (a member): out, the group %s, +%d steps" % [members(), m.undo.size() - u1])
	m._toggle_lock("thigh_r")
	var r0 := ang("thigh_r")
	await drag("thigh_l", Vector2(0, -10))
	m._toggle_lock("thigh_r")
	ok(ang("thigh_r").is_equal_approx(r0) and not (ang("thigh_l") as Vector3).is_equal_approx(a0["thigh_l"]), "5 the right thigh locked, a drag on the left: it turned %s, the locked one stayed %s" % [ang("thigh_l"), ang("thigh_r")])
	var ua := ang("upperarm_r")
	var la := ang("lowerarm_r")
	await drag("hand_r", Vector2(12, 0), true, 0.9)   # ROADMAP 41: the forearm now swings toward the mouse too, so press the hand itself
	ok(not ang("upperarm_r").is_equal_approx(ua) or not ang("lowerarm_r").is_equal_approx(la), "6 a Ctrl+drag on the right hand: the elbow swung (upper arm %s -> %s, forearm %s -> %s)" % [ua, ang("upperarm_r"), la, ang("lowerarm_r")])
	await click("thigh_l")
	await click("thigh_r", true)
	await click("head")
	ok(members() == ["head"], "7 a group of the thighs, then a plain click on the head: one part %s" % [members()])
	await click("thigh_l")
	await click("thigh_r", true)
	var hp := spot("head")
	await btn(MOUSE_BUTTON_RIGHT, true, hp)
	await move(hp + Vector2(2, 1), Vector2(2, 1), false, MOUSE_BUTTON_MASK_RIGHT)
	await btn(MOUSE_BUTTON_RIGHT, false, hp + Vector2(2, 1))
	m.ui_ring.close()
	await idle()
	ok(members() == ["head"], "8 a group of the thighs, then the ring opened on the head: the group ends %s" % [members()])
	print("MULTI SELECT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
