## godot --path . -s tests/autokey_test.gd     (ROADMAP 42; needs a window: the real poser UI is built)
## Auto-key: Ctrl+K turns it on; the 3D view gets a red frame (its edge pixels read red; off, they do not). On a frame
## between two cards (no card there), a drag of a hand keys exactly one card at the playhead; with it off the same drag
## keys none; one Ctrl+Z takes the auto card away. The status line says "Auto-key ON: changes make keys".
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key_event(code: Key, ctrl: bool) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	return k


## one hand drag as the mouse makes it: a press (the undo step), the joint moved, the release
func hand_drag(m: Node) -> void:
	m._push_undo()
	m.sel = "hand_r"
	m.dragging = "joint"
	m._grab = Vector3(NAN, NAN, NAN)
	m._num_on = false
	for k in 20:
		m._drag_joint(Vector2(-0.6, 0.0), false, false, false)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = Vector2(200, 200)
	m._unhandled_input(mb)


func red_at(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	return c.r > 0.6 and c.g < 0.35 and c.b < 0.35


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await process_frame
	var ts: Array = m.S.times()
	ok(ts.size() >= 3, "scene has %d cards" % ts.size())
	# a frame between card 1 and card 2 (in the move into card 2): no card holds it
	m.playhead = (float(ts[2][0]) + float(ts[2][1])) * 0.5
	var no_card: bool = LimbIK.card_at(m.S, m.playhead) < 0
	ok(no_card, "playhead %.2f s is in a move: no card holds it" % m.playhead)
	m._refresh()
	await process_frame

	# OFF: the drag keys nothing
	var n0: int = m.S.cards.size()
	hand_drag(m)
	var n_off: int = m.S.cards.size()
	ok(n_off == n0, "auto-key off: the drag leaves the card count at %d (was %d)" % [n_off, n0])
	m._undo()
	ok(m.S.cards.size() == n0, "  Ctrl+Z after the plain drag: %d cards" % m.S.cards.size())

	# ON: Ctrl+K, then the same drag keys exactly one card
	m._unhandled_input(key_event(KEY_K, true))
	await process_frame
	ok(m.auto_key, "Ctrl+K turns auto-key on")
	var status: String = m.ui_status.text
	ok(status.contains("Auto-key ON: changes make keys"), "status line: \"%s\"" % status)
	for f in 3:
		await process_frame   # the frame is drawn on the next pass
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var img: Image = m.get_viewport().get_texture().get_image()
	var ex := int(m.lw()) + 2
	var ey := int((m.TOP_H + vs.y - m.bottom_h - m.LINE_H) * 0.5)
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/autokey.png")
	ok(red_at(img, ex, ey), "3D view edge pixel (%d, %d) is red: %s" % [ex, ey, img.get_pixel(ex, ey)])

	var n1: int = m.S.cards.size()
	hand_drag(m)
	var n2: int = m.S.cards.size()
	ok(n2 == n1 + 1, "auto-key on: the drag creates exactly one card (%d -> %d)" % [n1, n2])
	var at: int = m.sel_card
	ok(absf(float(m.S.times()[at][1]) - m.playhead) < 0.002, "the new card arrives at the playhead (%.3f s, card at %.3f s)" % [m.playhead, float(m.S.times()[at][1])])
	m._undo()
	ok(m.S.cards.size() == n1, "one Ctrl+Z removes the auto card (%d cards, was %d)" % [m.S.cards.size(), n1])

	# OFF again: the frame goes, the same drag keys none
	m._unhandled_input(key_event(KEY_K, true))
	await process_frame
	ok(not m.auto_key, "Ctrl+K turns auto-key off")
	for f in 3:
		await process_frame
	img = m.get_viewport().get_texture().get_image()
	ok(not red_at(img, ex, ey), "frame gone: the edge pixel is no longer red")
	var n3: int = m.S.cards.size()
	hand_drag(m)
	ok(m.S.cards.size() == n3, "auto-key off again: the drag keys none (%d cards)" % m.S.cards.size())

	print("AUTOKEY %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
