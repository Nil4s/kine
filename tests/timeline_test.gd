## godot --path . -s tests/timeline_test.gd     (GATES M2, M3, M4; needs a window)
## The timeline in the real poser window, driven by mouse events at the pixels it draws: retime by dragging edges
## (ripple, snapping, clamps, a zero hold pulled out), one Ctrl+Z per drag, click-to-pick (+ the card row scrolls),
## ruler scrub, and every cache rebuilt after a retime. Nick's scene file is never written.
extends SceneTree

var fails := 0
var m: Node
var tl: Timeline


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func mouse(kind: String, x: float, y := -1.0, shift := false) -> void:
	var p := Vector2(x, Timeline.RULER + 12.0 if y < 0.0 else y)
	var ev: InputEvent
	if kind == "move":
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = kind == "down"
	ev.position = p
	ev.shift_pressed = shift
	tl._gui_input(ev)


## press at x, move by dx in two steps (a real drag), release
func drag(x: float, dx: float, shift := false) -> void:
	mouse("down", x)
	mouse("move", x + dx * 0.5, -1.0, shift)
	mouse("move", x + dx, -1.0, shift)
	mouse("up", x + dx)


func ts() -> Array:
	return m.S.times()


func spins(i: int) -> Array:
	return (m.ui_cards.get_child(i) as Node).find_children("*", "SpinBox", true, false)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var src := "res://scenes/combo3.json"
	var file0 := FileAccess.get_file_as_string(src)
	m._load_scene(src)
	m._rebuild_cards()
	m.ov.trail_on = true
	m._refresh()
	await process_frame
	tl = m.ui_timeline
	var L0: float = m.S.length()
	print("     timeline %.0f px wide, %.1f px per second, scene %.2f s, %d cards" % [tl.size.x, tl.pps(), L0, m.S.cards.size()])
	ok(tl.visible and tl.size.x > 600.0 and tl.size.y >= 30.0, "the timeline is in the window (round 36: on the one strip, 34 px) (%.0f x %.0f px)" % [tl.size.x, tl.size.y])
	var k := tl.pps()

	# M2: card 2's arrival edge +0.2 s -> its move 0.4 -> 0.6; card 3 starts 0.2 later; its own move unchanged
	var t3 := float(ts()[2][0])
	var m3: float = m.S.move_time(2)
	var u0: int = m.undo.size()
	drag(tl.x_of(ts()[1][1]), 0.2 * k)
	ok(is_equal_approx(m.S.move_time(1), 0.6), "drag card 2's edge +0.2 s: its move 0.40 -> %.2f" % m.S.move_time(1))
	ok(absf(float(ts()[2][0]) - t3 - 0.2) < 1e-6 and is_equal_approx(m.S.move_time(2), m3) and absf(m.S.length() - L0 - 0.2) < 1e-6, "  ripple: card 3 starts 0.20 s later, its move still %.2f, scene %.2f -> %.2f s" % [m3, L0, m.S.length()])
	ok(m.undo.size() == u0 + 1, "  one undo step for the whole drag (%d)" % (m.undo.size() - u0))
	await process_frame   # the old card panels are freed at the end of the frame; read the new ones
	var sp: Array = spins(1)
	ok(is_equal_approx(float(sp[0].value), 0.6), "  card 2's move box reads %.2f (the boxes were rebuilt)" % sp[0].value)
	m._undo()
	ok(is_equal_approx(m.S.move_time(1), 0.4) and absf(m.S.length() - L0) < 1e-6, "  Ctrl+Z: move %.2f, scene %.2f s again" % [m.S.move_time(1), m.S.length()])

	# snapping: 0.033 s of drag -> 0.45 (snaps to 0.05); with Shift -> 0.43 (0.01)
	drag(tl.x_of(ts()[1][1]), 0.033 * k)
	var snapped: float = m.S.move_time(1)
	m._undo()
	drag(tl.x_of(ts()[1][1]), 0.033 * k, true)
	var fine: float = m.S.move_time(1)
	m._undo()
	ok(is_equal_approx(snapped, 0.4 + 1.0 / 30.0) and is_equal_approx(fine, 0.43), "snap (ROADMAP 47: whole frames): +0.033 s = 1 f -> %.4f, with Shift %.2f (0.01 steps)" % [snapped, fine])

	# a zero hold (card 3 CONTACT): right pulls a hold out, left shortens the move
	ok(float(m.S.cards[2]["hold"]) == 0.0, "card 3 has no hold (the edge is shared)")
	drag(tl.x_of(ts()[2][1]), 0.1 * k)
	ok(is_equal_approx(float(m.S.cards[2]["hold"]), 0.1) and is_equal_approx(m.S.move_time(2), m3), "  drag RIGHT: a 0.10 s hold pulled out (hold %.2f, move still %.2f)" % [m.S.cards[2]["hold"], m.S.move_time(2)])
	m._undo()
	# -0.052 s, not -0.05: that is exactly 1.5 frames, a rounding TIE that float32 mouse positions decide at random
	drag(tl.x_of(ts()[2][1]), -0.052 * k)
	ok(is_equal_approx(m.S.move_time(2), 0.15 - 2.0 / 30.0) and float(m.S.cards[2]["hold"]) == 0.0, "  drag LEFT: the move 0.15 -> %.2f, still no hold" % m.S.move_time(2))
	m._undo()

	# clamps: a hold can't go below 0, a move can't go below MIN_MOVE
	drag(tl.x_of(ts()[3][2]), -0.6 * k)
	ok(float(m.S.cards[3]["hold"]) == 0.0, "card 4's hold dragged 0.6 s left: %.2f (not negative)" % m.S.cards[3]["hold"])
	m._undo()
	drag(tl.x_of(ts()[2][1]), -1.0 * k)
	ok(is_equal_approx(m.S.move_time(2), Timeline.MIN_MOVE), "card 3's move dragged 1 s left: %.2f s (the floor)" % m.S.move_time(2))
	m._undo()
	ok(absf(m.S.length() - L0) < 1e-6 and is_equal_approx(m.S.move_time(2), m3), "after the undos: scene %.2f s, card 3 move %.2f, as loaded" % [m.S.length(), m.S.move_time(2)])

	# an AUTO move (move -1 = timed from the angles): dragging makes it the dragged value
	m.S.cards[4]["move"] = -1.0
	var auto: float = m.S.move_time(4)
	drag(tl.x_of(ts()[4][1]), 0.1 * k)
	ok(is_equal_approx(m.S.move_time(4), auto + 0.1) and float(m.S.cards[4]["move"]) > 0.0, "card 5 on auto (%.2f s): dragged +0.1 -> set to %.2f" % [auto, m.S.move_time(4)])
	m._undo()
	m.S.cards[4]["move"] = 0.3

	# M4: the caches follow a retime: trail/graph pass, the landed dummy copy, the Check panel
	m.dummy_on = true   # the landed copy only exists with the dummy on, solid, and hit: move it in until the swing hits
	m.solid = true
	for d in [1.6, 1.4, 1.2, 1.0, 0.9, 0.8, 0.7]:
		m.T.place(d)
		m._dummy_hits()
		await m.dummy_settle()   # round 14: measured on a worker thread
		if m.SL != null:
			break
	var b0: int = m.ov.builds
	var sl0 = m.SL
	print("     dummy on, solid, %.1f m out: landed copy %s" % [m.T.dist, "built" if sl0 != null else "NONE (no hit at any range)"])
	m.ui_find.visible = true
	drag(tl.x_of(ts()[1][1]), 0.2 * k)
	await process_frame
	await m.dummy_settle()
	await process_frame
	ok(m.ov.builds > b0 and absf(float(m.ov.curves["t"][-1]) - m._ps().length()) < 0.05, "after a retime the trail/graph pass re-ran (%d builds), its curve ends at %.2f s = what plays (the landed copy; the cards run to %.2f)" % [m.ov.builds - b0, m.ov.curves["t"][-1], m.S.length()])
	ok(sl0 != null and m.SL != null and not is_same(m.SL, sl0), "  the landed dummy copy was rebuilt for the new timing (a new object, plays %.2f s)" % (m.SL.length() if m.SL != null else -1.0))
	ok(not m.ui_find.visible, "  the old Check findings are put away (they graded the old timing)")
	m._undo()
	m.dummy_on = false
	m._dummy_hits()
	# the HOLD box: now undoable and it rebuilds the caches (before: it only refreshed)
	b0 = m.ov.builds
	u0 = m.undo.size()
	var hb: SpinBox = spins(3)[1]
	hb.value = 0.5
	m._refresh()
	await process_frame
	ok(is_equal_approx(float(m.S.cards[3]["hold"]), 0.5) and m.undo.size() == u0 + 1 and m.ov.builds > b0, "the hold box: card 4 hold 0.5, one undo step, the trail pass re-ran (%d builds)" % (m.ov.builds - b0))
	m._undo()
	ok(is_equal_approx(float(m.S.cards[3]["hold"]), 0.3), "  Ctrl+Z: hold %.2f" % m.S.cards[3]["hold"])

	# M3: click a block = pick the card at its pose; the card row scrolls to a far card
	k = tl.pps()
	var t11: Array = ts()[10]
	mouse("down", tl.x_of(lerpf(float(t11[0]), float(t11[1]), 0.5)))
	mouse("up", tl.x_of(lerpf(float(t11[0]), float(t11[1]), 0.5)))
	await process_frame
	await process_frame
	var sc: ScrollContainer = m.ui_cards.get_parent()
	var card: Control = m.ui_cards.get_child(10)
	var vis: bool = card.position.x - sc.scroll_horizontal >= -1.0 and card.position.x + card.size.x - sc.scroll_horizontal <= sc.size.x + 1.0
	ok(m.sel_card == 10 and absf(m.playhead - float(t11[1])) < 1e-6, "click in card 11's block: card %d picked, playhead %.2f s (its pose)" % [m.sel_card + 1, m.playhead])
	ok(vis and sc.scroll_horizontal > 0, "  the card row scrolled to it (scroll %d px, card fully in view: %s)" % [sc.scroll_horizontal, vis])
	# the ruler scrubs
	mouse("down", tl.x_of(2.0), 6.0)
	mouse("move", tl.x_of(3.0), 6.0)
	mouse("up", tl.x_of(3.0), 6.0)
	ok(absf(m.playhead - 3.0) < 0.02, "drag along the ruler 2 -> 3 s: playhead %.2f s" % m.playhead)
	ok(FileAccess.get_file_as_string(src) == file0, "combo3.json byte-identical (nothing was saved)")
	print("TIMELINE %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
