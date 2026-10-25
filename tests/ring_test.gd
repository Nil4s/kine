## godot --path . -s tests/ring_test.gd     (GATES N4; needs a window)
## The right-click ring, every event pushed to the WINDOW as a mouse would send it: a right CLICK on a part opens the
## ring (and selects the part, the view does not turn); a right DRAG still turns the view and opens nothing; a right
## click on empty floor opens nothing. The wedges: each label's spot is its own wedge, the middle and outside cancel.
## Each action runs (reset, copy to the other side, snap, pin a trail, clip) and Ctrl+Z undoes the pose ones.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func btn(b: MouseButton, down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_RIGHT if b == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)


## the screen point of a part's middle (its capsule's centre), checked to pick that part. PRECISE PICK: the pick is the
## skin, so where another part's skin covers the centre (a resting hand's thumb on the forearm) the point slides along
## the part's axis to the first spot whose skin is the part's own
func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	for f in [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]:
		var p: Vector2 = m.cam.unproject_position((c[0] as Vector3).lerp(c[1], f))
		if m._pick(p) == j:
			return p
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func right_click(p: Vector2) -> void:
	btn(MOUSE_BUTTON_RIGHT, true, p)
	move(p + Vector2(2, 1), Vector2(2, 1))   # a hand is never perfectly still: 2 px of wobble
	btn(MOUSE_BUTTON_RIGHT, false, p + Vector2(2, 1))
	await process_frame


## open the ring on part j and click the wedge whose label says `label` (first line)
func choose(j: String, label: String) -> void:
	await right_click(spot(j))
	if m.sel != j:   # the click must be on the part asked for (a bent arm can put the hand's capsule over the forearm)
		ok(false, "the right-click for '%s' opened on '%s'" % [j, m.sel])
	var ring: RingMenu = m.ui_ring
	for i in ring.items.size():
		if String(ring.items[i]["name"]).begins_with(label):
			var p := ring.at + ring.dir(i) * RingMenu.R_TXT
			btn(MOUSE_BUTTON_LEFT, true, p)
			btn(MOUSE_BUTTON_LEFT, false, p)
			await process_frame
			return
	ok(false, "no wedge '%s'" % label)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var ring: RingMenu = m.ui_ring
	var j := "lowerarm_l"
	var p := spot(j)
	ok(m._pick(p) == j, "the left forearm's middle is at (%.0f, %.0f) and picks it" % [p.x, p.y])

	# right CLICK on a part -> the ring; the view does not turn
	var y0: float = m.yaw
	var pi0: float = m.pitch
	m.sel = "head"
	await right_click(p)
	ok(ring.visible and m.sel == j and m.yaw == y0 and m.pitch == pi0, "right-click the forearm: ring open %s, '%s' selected, the view did not turn (yaw %.2f)" % [ring.visible, m.sel, m.yaw])
	ok(ring.get_global_rect().size == Vector2(root.size), "  the ring covers the window (%s): a click anywhere reaches it" % ring.get_global_rect().size)
	ok(ring.title == m.nice(j) and ring.items.size() == 7, "  titled '%s', %d wedges" % [ring.title, ring.items.size()])
	# wedge geometry: each label's spot is its own wedge; middle and outside are none
	var wrong := 0
	for i in ring.items.size():
		if ring.wedge(ring.at + ring.dir(i) * RingMenu.R_TXT) != i:
			wrong += 1
	ok(wrong == 0 and ring.wedge(ring.at) == -1 and ring.wedge(ring.at + Vector2(0, -RingMenu.R_OUT - 5.0)) == -1, "  each label is on its own wedge (%d wrong); the middle and outside are none" % wrong)
	ok(ring.wedge(ring.at + Vector2(0, -60)) == 0 and String(ring.items[0]["name"]).begins_with("Reset"), "  straight up = Reset")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key)
	await process_frame
	ok(not ring.visible, "  Esc closes it")
	await right_click(p)
	btn(MOUSE_BUTTON_LEFT, true, ring.at)   # the middle
	btn(MOUSE_BUTTON_LEFT, false, ring.at)
	await process_frame
	ok(not ring.visible and m.yaw == y0, "  a click in the middle: closed, nothing ran")

	# right DRAG -> turns the view, no ring
	btn(MOUSE_BUTTON_RIGHT, true, p)
	for k in 6:
		move(p + Vector2(10 * (k + 1), 0), Vector2(10, 0))
	btn(MOUSE_BUTTON_RIGHT, false, p + Vector2(60, 0))
	await process_frame
	ok(not ring.visible and absf(m.yaw - y0) > 10.0, "right-DRAG 60 px from the forearm: the view turned (yaw %.0f -> %.0f), no ring" % [y0, m.yaw])
	m._view(1)
	await process_frame
	p = spot(j)
	# right click on nothing
	await right_click(Vector2(400, 480))
	ok(not ring.visible and m._pick(Vector2(400, 480)) == "", "right-click on the empty floor: no ring")

	# the actions
	m.B.ang[j] = Vector3(70, 0, 0)
	m.B.fk()
	m._refresh()   # the view drawn in that pose (the pick reads the skin as drawn)
	await choose(j, "Reset")
	ok((m.B.ang[j] as Vector3).length() < 1e-4, "Reset wedge: forearm bend 70 -> %.1f" % m.B.ang[j].x)
	m._undo()
	ok(is_equal_approx(m.B.ang[j].x, 70.0), "  Ctrl+Z: 70 again (%.1f)" % m.B.ang[j].x)
	var r0: Vector3 = m.B.ang["lowerarm_r"]
	await choose(j, "Copy to")
	ok(String(ring.items[2]["name"]).contains("right side") and not (m.B.ang["lowerarm_r"] as Vector3).is_equal_approx(r0) and is_equal_approx(absf(m.B.ang["lowerarm_r"].x), 70.0), "'Copy to right side': the right forearm %s -> %s" % [r0, m.B.ang["lowerarm_r"]])
	m._undo()
	ok((m.B.ang["lowerarm_r"] as Vector3).is_equal_approx(r0), "  Ctrl+Z: the right forearm back")
	m.B.ang[j] = Vector3(52, 0, 0)
	m.B.fk()
	m._refresh()   # the view drawn in that pose (the pick reads the skin as drawn)
	await choose(j, "Snap 90")
	ok(is_equal_approx(m.B.ang[j].x, 90.0) or is_equal_approx(m.B.ang[j].x, 0.0), "Snap 90: bend 52 -> %.0f" % m.B.ang[j].x)
	m.B.ang[j] = Vector3.ZERO   # straight again: bent 90, the hand's capsule sat over the forearm's middle and was picked
	m.B.fk()
	m._refresh()   # the view drawn in that pose (the pick reads the skin as drawn)
	await choose(j, "Pin a")
	ok(j in m.ov.pins, "Pin a trail: the forearm has its own trail (%s)" % str(m.ov.pins))
	var n0: int = m.S.cards.size()
	await choose(j, "CLIP")
	ok(m.S.cards.size() == n0 + 1, "CLIP wedge: %d -> %d cards" % [n0, m.S.cards.size()])
	# a part in the middle of the body: the mirror wedge is the whole pose
	await right_click(spot("spine_02"))
	ok(ring.visible and String(ring.items[2]["name"]).begins_with("Mirror"), "on the middle back the 3rd wedge is '%s'" % String(ring.items[2]["name"]).replace("\n", " "))
	ring.close()
	print("RING %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
