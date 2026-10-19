## godot --path . -s tests/lock_part_test.gd     (GATES GG3, UPGRADES #24; a real window, real clicks and drags)
## LOCK A PART: the left forearm bent 70, then locked from the RING (a real right-click on it, a real click on the
## "Lock" wedge): drawn LOCK_COL, the title says LOCKED, the panel's button says Unlock, its sliders are not editable.
## A REAL drag on it: picked, not turned (angles the same), no undo step, the status line says it is locked and how to
## unlock. Reset body and Mirror pose: every other part changes, the forearm keeps its 70. A drag on the upper arm (its
## parent): the forearm's own angles stay. Unlocked by a real click on the PANEL's button: a real drag turns it again
## (one undo step). Locked again from the SEARCH's command. The lock is never written: the scene saved locked and saved
## unlocked are the same bytes.
extends SceneTree

var fails := 0
var m: Node
const J := "lowerarm_l"
const OUT := "_wip/zz_lock_part"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func btn(b: MouseButton, down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_RIGHT if b == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle(2)


func move(p: Vector2, rel: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
	root.push_input(e)
	await idle(2)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


## a real left drag from part j's middle, 6 steps of (0, -12) px
func drag(j: String) -> void:
	var p := spot(j)
	await move(p, Vector2(1, 0), 0)
	await btn(MOUSE_BUTTON_LEFT, true, p)
	for i in 6:
		p += Vector2(4, -12)
		await move(p, Vector2(4, -12), MOUSE_BUTTON_MASK_LEFT)
	await btn(MOUSE_BUTTON_LEFT, false, p)


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await btn(MOUSE_BUTTON_LEFT, true, p)
	await btn(MOUSE_BUTTON_LEFT, false, p)


func ang(j: String) -> Vector3:
	return m.B.ang[j]


func scene_bytes() -> String:
	m._save_scene_now(OUT)
	return FileAccess.get_file_as_string("res://scenes/%s.json" % OUT)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	m.B.ang[J] = Vector3(70, 0, 0)
	m.B.ang["upperarm_l"] = Vector3(0, 0, 25)
	m.B.ang["upperarm_r"] = Vector3(10, 0, -40)
	m.B.fk()
	m.sel = "head"
	m._refresh()
	await idle(3)
	# 1 lock from the ring
	var p := spot(J)
	await btn(MOUSE_BUTTON_RIGHT, true, p)
	await move(p + Vector2(2, 1), Vector2(2, 1), MOUSE_BUTTON_MASK_RIGHT)
	await btn(MOUSE_BUTTON_RIGHT, false, p + Vector2(2, 1))
	var ring: RingMenu = m.ui_ring
	var wedge := -1
	for i in ring.items.size():
		if String(ring.items[i]["name"]).begins_with("Lock"):
			wedge = i
	if wedge >= 0:
		var wp: Vector2 = ring.at + ring.dir(wedge) * RingMenu.R_TXT
		await btn(MOUSE_BUTTON_LEFT, true, wp)
		await btn(MOUSE_BUTTON_LEFT, false, wp)
	await idle(2)
	var sel_col: Color = m.skin_col(J)   # selected + locked: SEL greyed toward the lock (PRECISE PICK: on its skin)
	var sel_greyed: bool = sel_col.a > 0.0 and not Color(sel_col.r, sel_col.g, sel_col.b).is_equal_approx(Tok.c("pick_sel"))
	m.sel = "head"
	m._refresh()
	var col: Color = m.skin_col(J)   # not selected: the lock look itself
	var lit: bool = Color(col.r, col.g, col.b).is_equal_approx(Tok.c("pick_lock")) and sel_greyed
	m.sel = J
	m._refresh()
	await idle(2)
	var sliders_off: bool = not (m.ui_rows["bend"]["slider"] as HSlider).editable
	ok(m.sel == J and wedge >= 0 and m.locked_parts.has(J) and lit and m.ui_title.text.contains("LOCKED") and m.label_of(m.ui_lock_btn) == "Unlock this part" and sliders_off,
		"1 a real right-click on the left forearm, the ring's Lock wedge (%d): locked %s, drawn %s (selected: %s, not plain SEL), title '%s', panel button '%s', sliders editable %s" % [wedge, m.locked_parts.keys(), col, sel_col, m.ui_title.text, m.label_of(m.ui_lock_btn), not sliders_off])
	# 1b the slider set by value (a key or a script; editable=false only stops the mouse): the angle stays
	(m.ui_rows["bend"]["slider"] as HSlider).value = 10.0
	await idle(2)
	ok(ang(J).is_equal_approx(Vector3(70, 0, 0)), "1b its bend slider set to 10 while locked: the forearm keeps %s" % ang(J))
	m._refresh()
	# 2 a real drag on it is refused
	var a0 := ang(J)
	var u0: int = m.undo.size()
	await drag(J)
	var said: String = m.ui_status.text
	ok(ang(J).is_equal_approx(a0) and m.undo.size() == u0 and said.contains("locked") and said.contains("Unlock") and m.sel == J,
		"2 a real drag on the locked forearm: angles %s -> %s, undo steps +%d, the status says '%s'" % [a0, ang(J), m.undo.size() - u0, said])
	# 3 Reset body and Mirror pose leave it
	var others0: Vector3 = ang("upperarm_r")
	m._do(m._reset_all)
	var reset_ok: bool = ang(J).is_equal_approx(a0) and not ang("upperarm_r").is_equal_approx(others0)
	m.B.ang["upperarm_r"] = Vector3(10, 0, -40)
	m.B.fk()
	var r0: Vector3 = ang("lowerarm_r")
	m._tool(0)
	var mirror_ok: bool = ang(J).is_equal_approx(a0) and not ang("upperarm_l").is_equal_approx(Vector3.ZERO)
	ok(reset_ok and mirror_ok, "3 Reset body: the forearm keeps %s, the right upper arm reset (%s); Mirror pose: the forearm keeps %s, the left upper arm took the right's (%s)" % [a0, reset_ok, ang(J), ang("upperarm_l")])
	# 4 a real drag on its parent: the forearm's own angles stay
	await drag("upperarm_l")
	ok(ang(J).is_equal_approx(a0) and m.sel == "upperarm_l", "4 a real drag on the left upper arm (its parent, moved %s): the locked forearm's own angles stay %s" % [ang("upperarm_l"), ang(J)])
	# 4b a real drag on the hand (its reach turns the arm, IK): the locked forearm still keeps its angles
	var hand0: Vector3 = m.B.P["hand_l"]
	await drag("hand_l")
	var hand_moved: float = (m.B.P["hand_l"] as Vector3).distance_to(hand0)
	ok(m.sel == "hand_l" and ang(J).is_equal_approx(a0), "4b a real drag on the left hand (its reach, IK; the hand moved %.3f m): the locked forearm keeps %s" % [hand_moved, ang(J)])
	# 5 unlock from the panel: a real drag turns it again, one step
	m.sel = J
	m._refresh()
	await idle(2)
	await click(m.ui_lock_btn)
	var u1: int = m.undo.size()
	await drag(J)
	ok(not m.locked_parts.has(J) and not ang(J).is_equal_approx(a0) and m.undo.size() == u1 + 1 and m.label_of(m.ui_lock_btn) == "Lock this part",
		"5 a real click on the panel's button: unlocked; a real drag turns it %s -> %s, +%d undo step" % [a0, ang(J), m.undo.size() - u1])
	# 6 lock from the search
	var cmd := {}
	for c in m._commands():
		if String(c["name"]).begins_with("Lock / unlock"):
			cmd = c
	if not cmd.is_empty():
		(cmd["run"] as Callable).call()
	await idle(2)
	ok(m.locked_parts.has(J), "6 the search's 'Lock / unlock this part' on the selected forearm: locked %s" % m.locked_parts.keys())
	# 7 never written
	m._card_add()
	var b_locked := scene_bytes()
	m._toggle_lock(J)
	var b_free := scene_bytes()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scenes/%s.json" % OUT))
	ok(b_locked != "" and b_locked == b_free and not m.locked_parts.has(J), "7 the scene saved locked and unlocked: the same %d bytes (%s)" % [b_locked.length(), b_locked == b_free])
	print("LOCK PART: %d failed" % fails)
	quit(1 if fails > 0 else 0)
