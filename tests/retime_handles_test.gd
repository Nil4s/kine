## godot --path . -s tests/retime_handles_test.gd     (ROADMAP 47; needs a window)
## The timeline's right-edge handles in the real poser window, driven through Timeline._gui_input (the same path a mouse
## takes). combo3 is loaded in memory; no file is written. BARS, stated before the run:
##   plain drag of card 3's handle +6 f: cards 0..3 keep their starts; cards 4..N start exactly 6 f (0.200 s) later; one undo
##   alt-drag of card 3's handle +6 f: card 4's move shrinks by exactly 6 f, every other start and arrival is unchanged
##   alt-drag +10 s: card 4's move clamps at Timeline.MIN_MOVE, card 4's arrival stays, no card crosses another
##   plain drag -10 s: card 3's hold clamps at 0, the later cards shift by exactly the hold it had
##   +2.4 f snaps to +2 f; a click that moves nothing makes no undo step; undo restores the scene hash byte-for-byte
##   the handle is at least 10 px wide and lights on hover
extends SceneTree

var fails := 0
var m: Node
var tl: Timeline


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func mouse(kind: String, x: float, shift := false, alt := false) -> void:
	var p := Vector2(x, Timeline.RULER + 12.0)
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
	ev.alt_pressed = alt
	tl._gui_input(ev)


## press at x, move by dx in two steps (a real drag), release
func drag(x: float, dx: float, alt := false) -> void:
	mouse("down", x, false, alt)
	mouse("move", x + dx * 0.5, false, alt)
	mouse("move", x + dx, false, alt)
	mouse("up", x + dx, false, alt)


func ts() -> Array:
	return m.S.times()


func starts() -> Array:
	var out := []
	for r in ts():
		out.append(float(r[0]))
	return out


func arrivals() -> Array:
	var out := []
	for r in ts():
		out.append(float(r[1]))
	return out


func moves() -> Array:
	var out := []
	for i in m.S.cards.size():
		out.append(m.S.move_time(i))
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	await process_frame
	tl = m.ui_timeline
	var N: int = m.S.cards.size()
	var fps := float(m.S.fps)
	var fr := tl.pps() / fps   # px per frame
	print("     combo3: %d cards at %d fps, timeline %.1f px per second" % [N, int(fps), tl.pps()])
	ok(N >= 6, "combo3 has 6+ cards (%d)" % N)
	ok(Timeline.HANDLE_W >= 10.0, "the handle is at least 10 px wide (%.0f px)" % Timeline.HANDLE_W)

	var hx3 := tl.x_of(ts()[3][2])
	var h := tl.hit(Vector2(hx3, Timeline.RULER + 12.0))
	ok(h.get("kind", "") == "hold" and int(h.get("i", -1)) == 3, "card 3's right edge (index 3) is a hold handle under the pointer: %s" % str(h))
	mouse("move", hx3)   # a motion with no button: the handle lights
	ok(tl._hover.get("kind", "") == "hold" and int(tl._hover.get("i", -1)) == 3, "hover: the handle is the hover target (lit)")

	var hash0 := CoEdit.hash_of(m.S.cards)
	var s0 := starts()
	var a0 := arrivals()
	var mv0 := moves()
	var L0: float = m.S.length()

	# 1. PLAIN: +6 frames on card 3's handle ripples the later cards and nothing before them
	var u0: int = m.undo.size()
	drag(hx3, 6.0 * fr)
	var s1 := starts()
	var worst_before := 0.0
	for i in 4:
		worst_before = maxf(worst_before, absf(float(s1[i]) - float(s0[i])))
	var worst_after := 0.0
	var ripple_ok := true
	for i in range(4, N):
		var dd := float(s1[i]) - float(s0[i])
		worst_after = maxf(worst_after, absf(dd - 6.0 / fps))
	ok(worst_before < 1e-6, "plain +6 f: cards 0..3 (index 0-3) keep their starts (worst change %.6f s)" % worst_before)
	ok(worst_after < 1e-6, "  cards 4..%d (index 4..%d) start exactly 6 f = %.3f s later (worst error %.6f s)" % [N, N - 1, 6.0 / fps, worst_after])
	ok(absf(float(m.S.length()) - L0 - 6.0 / fps) < 1e-6, "  the scene grew by exactly 6 f: %.3f -> %.3f s" % [L0, m.S.length()])
	ok(m.undo.size() == u0 + 1, "  one undo step for the drag (%d)" % (m.undo.size() - u0))
	m._undo()
	ok(CoEdit.hash_of(m.S.cards) == hash0, "  undo: the scene hash is back to the loaded one")

	# 2. ALT: +6 frames on card 3's handle changes only card 4's move (the gap between them)
	u0 = m.undo.size()
	var hold3_0: float = float(m.S.cards[3]["hold"])
	drag(hx3, 6.0 * fr, true)
	var mv1 := moves()
	var a1 := arrivals()
	var s2 := starts()
	# card 4 (index 4) is the one card whose move changes; card 3's hold takes the 6 f; every other start and arrival stays
	var other_bad := 0.0
	for i in N:
		if i != 4:
			other_bad = maxf(other_bad, absf(float(mv1[i]) - float(mv0[i])))
		if i != 4:
			other_bad = maxf(other_bad, absf(float(s2[i]) - float(s0[i])))
		other_bad = maxf(other_bad, absf(float(a1[i]) - float(a0[i])))
	ok(absf(float(mv1[4]) - (float(mv0[4]) - 6.0 / fps)) < 1e-6, "alt +6 f: card 4's move shrinks by exactly 6 f: %.3f -> %.3f s" % [mv0[4], mv1[4]])
	ok(absf(float(m.S.cards[3]["hold"]) - hold3_0 - 6.0 / fps) < 1e-6, "  card 3's hold takes the 6 f: %.3f -> %.3f s" % [hold3_0, m.S.cards[3]["hold"]])
	ok(other_bad < 1e-6, "  every other move, start and arrival is unchanged (worst change %.6f s)" % other_bad)
	ok(m.undo.size() == u0 + 1, "  one undo step for the alt-drag (%d)" % (m.undo.size() - u0))
	m._undo()
	ok(CoEdit.hash_of(m.S.cards) == hash0, "  undo: the scene hash is back to the loaded one")

	# 3. ALT clamp: far right stops at card 4's move floor; the arrival of card 4 stays; no card crosses
	drag(hx3, 10.0 * tl.pps(), true)
	var mv2 := moves()
	var a2 := arrivals()
	var crossed := false
	for i in N:
		var r: Array = ts()[i]
		if r[0] > r[1] + 1e-9 or r[1] > r[2] + 1e-9:
			crossed = true
		if i + 1 < N and r[2] > float(ts()[i + 1][0]) + 1e-9:
			crossed = true
	ok(absf(float(mv2[4]) - Timeline.MIN_MOVE) < 1e-6, "alt +10 s clamps card 4's move at MIN_MOVE: %.3f s" % mv2[4])
	ok(absf(float(a2[4]) - float(a0[4])) < 1e-6 and not crossed, "  card 4's arrival stays at %.3f s and no card crosses another" % a2[4])
	m._undo()
	ok(CoEdit.hash_of(m.S.cards) == hash0, "  undo after the clamp: the scene hash is back")

	# 4. PLAIN clamp: far left stops card 3's hold at 0 and the later cards shift by exactly the hold it had
	var hold3: float = float(m.S.cards[3]["hold"])
	drag(hx3, -10.0 * tl.pps())
	var s3 := starts()
	ok(float(m.S.cards[3]["hold"]) == 0.0, "plain -10 s: card 3's hold clamps at 0 (was %.3f s)" % hold3)
	ok(absf(float(s3[4]) - (float(s0[4]) - hold3)) < 1e-6 and absf(float(s3[3]) - float(s0[3])) < 1e-9, "  card 4 starts %.3f s earlier, card 3 not at all" % (float(s0[4]) - float(s3[4])))
	m._undo()
	ok(CoEdit.hash_of(m.S.cards) == hash0, "  undo: the scene hash is back")

	# 5. snap: +2.4 frames -> +2 frames (whole frames, not a fraction of one)
	drag(hx3, 2.4 * fr)
	ok(absf(float(m.S.cards[3]["hold"]) - (hold3 + 2.0 / fps)) < 1e-6, "+2.4 f snaps to +2 f: hold %.4f -> %.4f" % [hold3, m.S.cards[3]["hold"]])
	m._undo()

	# the live readout: held down, 4 f out, the drag reads +4 f (not released yet)
	mouse("down", hx3)
	mouse("move", hx3 + 4.0 * fr)
	var rd := roundi(float(tl._drag.get("d", 0.0)) * fps)
	mouse("up", hx3 + 4.0 * fr)
	ok(rd == 4, "the readout mid-drag reads +4 f (the drag's delta is %d f)" % rd)
	m._undo()

	# 6. a click that moves nothing is not an edit
	u0 = m.undo.size()
	mouse("down", hx3)
	mouse("up", hx3)
	ok(m.undo.size() == u0 and CoEdit.hash_of(m.S.cards) == hash0, "a click on the handle that moves nothing: no undo step, scene unchanged")

	print("%s: %d failures" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
