## godot --path . -s tests/num_entry_test.gd     (GATES HH1, UPGRADES #29; a real window, real drags and keys)
## TYPE THE ANGLE WHILE DRAGGING: a real press on the right upper arm, then real keys 4 5: its bend is 45 at once (as
## the joint clamps it) and the bar says "TYPE bend = 45"; Tab, - 1 0: its side is -10 and the bend kept; the mouse
## moved while typed: no change; the release: the drag over, ONE undo step. Backspace takes a digit back. A forearm
## bend typed 400: clamped, and the bar shows the clamped number. Esc: the angles back, no undo step. Enter ends the drag
## (the mouse still down, its motion turns nothing). Outside a drag: 2 is still the side view, Tab still the big view.
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


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle()


func move(p: Vector2, rel: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(e)
	await idle()


func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle()


func keys(ks: Array) -> void:
	for k in ks:
		await key(k)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func ang(j: String) -> Vector3:
	return m.B.ang[j]


func want(j: String, v: Vector3) -> Vector3:
	return m.B.clamp_ang(j, v)


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
	var J := "upperarm_r"
	var a0 := ang(J)
	var u0: int = m.undo.size()
	var p := spot(J)
	await btn(true, p)
	await keys([KEY_4, KEY_5])
	var bar1: String = m.bar_text()
	var w1 := want(J, Vector3(45, a0.y, a0.z))
	ok(m.dragging == "joint" and ang(J).is_equal_approx(w1) and bar1.contains("TYPE bend = 45"), "1 a real press on the right upper arm, keys 4 5: %s (want %s), the bar '%s'" % [ang(J), w1, bar1.left(60)])
	await keys([KEY_TAB, KEY_MINUS, KEY_1, KEY_0])
	var w2 := want(J, Vector3(45, -10, a0.z))
	var bar2: String = m.bar_text()
	ok(ang(J).is_equal_approx(w2) and bar2.contains("TYPE side = -10"), "2 Tab, - 1 0: %s (want %s: the bend kept), the bar '%s'" % [ang(J), w2, bar2.left(40)])
	await keys([KEY_0, KEY_BACKSPACE])
	ok(ang(J).is_equal_approx(w2) and m.bar_text().contains("side = -10_"), "3 0 then Backspace: back to -10 (%s)" % ang(J))
	for i in 4:
		p += Vector2(9, -14)
		await move(p, Vector2(9, -14))
	ok(ang(J).is_equal_approx(w2), "4 the mouse moved 4 times while a number is typed: the arm holds %s" % ang(J))
	await btn(false, p)
	ok(m.dragging == "" and m.undo.size() == u0 + 1 and ang(J).is_equal_approx(w2) and not m.bar_text().contains("TYPE"), "5 the release: the drag over, +%d undo step, the arm %s" % [m.undo.size() - u0, ang(J)])
	# clamped
	var F := "lowerarm_r"
	await btn(true, spot(F))
	await keys([KEY_4, KEY_0, KEY_0])
	var wf := want(F, Vector3(400, ang(F).y, ang(F).z))
	var barf: String = m.bar_text()
	# set_ang_safe stops it at the joint's limit OR where it would enter the body, whichever comes first
	ok(m.sel == F and ang(F).x > 60.0 and ang(F).x <= wf.x + 1e-3 and barf.contains("(it is %.1f)" % ang(F).x), "6 the right forearm, bend typed 400: stopped at %.1f (the limit %.1f, or the body first), the bar shows it: '%s'" % [ang(F).x, wf.x, barf.left(50)])
	await btn(false, spot(F))
	# Esc cancels
	J = "thigh_l"   # the arm is folded now: the forearm lies over the upper arm's middle
	var u1: int = m.undo.size()
	var a1 := ang(J)
	var p2 := spot(J)
	await btn(true, p2)
	await keys([KEY_3, KEY_0])
	var mid := ang(J)
	await key(KEY_ESCAPE)
	var esc_drag: String = m.dragging
	await btn(false, p2)
	ok(mid.is_equal_approx(want(J, Vector3(30, a1.y, a1.z))) and ang(J).is_equal_approx(a1) and m.undo.size() == u1 and esc_drag == "", "7 a press on the left thigh, 3 0 (%s), Esc: back to %s, undo steps +%d, the drag over" % [mid, ang(J), m.undo.size() - u1])
	# Enter ends it while the mouse is still down
	await btn(true, p2)
	await keys([KEY_2, KEY_0, KEY_ENTER])
	var after_enter := ang(J)
	await move(p2 + Vector2(30, -40), Vector2(30, -40))
	ok(m.dragging == "" and after_enter.is_equal_approx(want(J, Vector3(20, a1.y, a1.z))) and ang(J).is_equal_approx(after_enter) and m.undo.size() == u1 + 1, "8 2 0 Enter: the drag over (%s), the mouse still down moves nothing (%s), +%d step" % [m.dragging, ang(J), m.undo.size() - u1])
	await btn(false, p2 + Vector2(30, -40))
	# outside a drag the keys are as they were
	await key(KEY_2)
	var side_view: bool = absf(m.yaw - (-90.0)) < 1.0
	var bv0: bool = m.big_view
	await key(KEY_TAB)
	var bv1: bool = m.big_view
	await key(KEY_TAB)
	ok(side_view and bv1 != bv0 and m.big_view == bv0, "9 outside a drag: 2 = the side view (yaw %.0f), Tab = the big view (%s -> %s)" % [m.yaw, bv0, bv1])
	print("NUM ENTRY: %d failed" % fails)
	quit(1 if fails > 0 else 0)
