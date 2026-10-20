## godot --path . -s tests/r8_test.gd     (ROADMAP round 2, R8; needs a window)
## A LIBRARY POSE DRAGGED FROM BROWSER > Poses ONTO THE CARD STRIP inserts a card at the drop position. By real mouse events.
## BARS (written before measuring):
##  1 drop at the start / the middle (between cards 6 and 7) / the end of combo3's 12 cards: the new card lands at index
##    0 / 6 / 12, the strip then has 13 cards, and every joint's bend / side / twist on the new card == the pose file's (<= 1e-4 deg)
##  2 PLACEMENT: while dragging, the gold line is visible, inside the strip, and within 4 px of the boundary where the card
##    will land (start: left of card 1; middle: between card 6 and 7; end: after card 12); it is Tok card_play
##    coloured and hidden again after the drop
##  3 each drop is ONE undo step; Ctrl+Z restores the scene JSON byte for byte
##  4 a drop outside the strip (over the 3D view) changes nothing: same JSON, same undo depth
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func scene_json() -> String:
	return JSON.stringify(m.S.to_dict(m.B), "", true)


var last := Vector2.ZERO


func mouse(p: Vector2, pressed: Variant, held := true) -> void:
	var e: InputEvent
	if pressed == null:
		var mm := InputEventMouseMotion.new()
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		mm.relative = p - last   # the drag threshold sums the relative motion
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e = mb
	(e as InputEventMouse).position = p
	(e as InputEventMouse).global_position = p
	last = p
	root.push_input(e)


## the Library row of the pose called `want` (the browser unfolded and scrolled to it) -> its screen centre
func row_pos(want: String) -> Vector2:
	var br: Tree = m.ui_browser
	m.ui_browser._poses_root.collapsed = false
	m.ui_browser._lib.collapsed = false
	await idle(3)
	for it in m.ui_browser._lib.get_children():
		if it.get_text(0).begins_with(want):
			br.scroll_to_item(it)
			await idle(10)
			var r := br.get_item_area_rect(it, 0)
			var lp := r.get_center()
			if br.get_item_at_position(lp) != it:
				print("     row not under its own rect centre ", lp)
			return br.get_global_rect().position + lp
	return Vector2(-1, -1)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(2)
	root.get_window().size = Vector2i(1600, 900)
	await idle(6)
	m._load_scene("res://scenes/combo3.json")
	m._page_set("ANIMATE", false)
	await idle(3)
	m._rebuild_cards()
	await m.thumbs.settle()
	await idle(4)
	var pose_name := "bat up"
	var path := ""
	for i in m.ui_poses.item_count:
		if m.ui_poses.get_item_text(i).begins_with(pose_name):
			path = m.ui_poses.get_item_metadata(i)
	ok(path != "", "the library has '%s' (%s)" % [pose_name, path])
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var base := scene_json()
	var n0: int = m.S.cards.size()
	var shot := OS.get_environment("R8_SHOT")

	var cards := func() -> Array:
		var a := []
		for pc in m.ui_cards.get_children():
			if String(pc.name).begins_with("card_"):
				a.append(pc)
		return a
	var cs: Array = cards.call()
	var strip: Rect2 = m.ui_card_row.get_global_rect()
	var y := strip.position.y + 40.0
	var targets := {
		0: Vector2((cs[0] as Control).get_global_rect().position.x + 6.0, y),
		6: Vector2((cs[5] as Control).get_global_rect().get_center().x + 8.0, y),
		12: Vector2((cs[11] as Control).get_global_rect().end.x - 4.0, y)}
	var line_x := {
		0: (cs[0] as Control).get_global_rect().position.x - 2.0,
		6: ((cs[5] as Control).get_global_rect().end.x + (cs[6] as Control).get_global_rect().position.x) * 0.5,
		12: (cs[11] as Control).get_global_rect().end.x + 1.0}

	for idx in [0, 6, 12]:
		var from := await row_pos(pose_name)
		ok(from.x > 0, "[%d] the row is on screen at %s" % [idx, from])
		var u0: int = m.undo.size()
		mouse(from, true)
		await process_frame
		for k in range(1, 7):   # past the drag threshold, then across to the strip
			mouse(from.lerp(targets[idx], k / 6.0), null)
			await process_frame
		await idle(3)
		var dragging: bool = root.gui_is_dragging()
		var dd: Variant = root.gui_get_drag_data()
		# Godot polls can_drop at the OS cursor (not at pushed events), so the strip's half is called as Godot calls it: with the
		# control under the target and the point in its local space. The drag itself (press, 6 steps, data) was by real events.
		mouse(targets[idx], null)
		await idle(2)
		var hv: Control = root.gui_get_hovered_control()
		var at: Vector2 = hv.get_global_transform().affine_inverse() * targets[idx]
		var cando: bool = m._card_can_drop(at, dd, 0, hv)
		await idle(2)
		print("     dragging %s data %s target %s hovered %s line %s %s" % [dragging, dd, targets[idx], hv, m.ui_card_row.get_node("drop_line").visible, m.ui_card_row.get_global_rect()])
		if dd is Dictionary:
			want = JSON.parse_string(FileAccess.get_file_as_string(dd["kine_pose"]))
		var ln: ColorRect = m.ui_card_row.get_node("drop_line")
		var lx := ln.global_position.x + 1.0
		ok(dragging and cando and ln.visible and absf(lx - line_x[idx]) <= 4.0 and strip.grow(4.0).encloses(ln.get_global_rect()) and ln.color == Tok.c("card_play"),
			"[%d] mid-drag: gold line visible at x %.1f (the boundary %.1f), inside the strip" % [idx, lx, line_x[idx]])
		if idx == 6 and shot != "":
			root.get_texture().get_image().save_png(shot)
		m._card_drop(at, dd, 0, hv)
		mouse(Vector2(900, 300), false)   # the release off the strip: Godot's own drop finds no target
		await idle(4)
		var n1: int = m.S.cards.size()
		var c: Dictionary = m.S.cards[idx] if idx < n1 else {}
		var jd := 0.0
		for j in want["joints"]:
			for k in ["bend", "side", "twist"]:
				jd = maxf(jd, absf(float(c["pose"]["joints"][j][k]) - float(want["joints"][j][k])))
		ok(n1 == n0 + 1 and jd <= 1e-4 and m.sel_card == idx, "[%d] inserted at index %d: %d cards, worst joint difference %.6f deg, picked card %d" % [idx, idx, n1, jd, m.sel_card + 1])
		ok(not ln.visible, "[%d] the line is gone after the drop" % idx)
		ok(m.undo.size() == u0 + 1, "[%d] ONE undo step (%d)" % [idx, m.undo.size() - u0])
		m._undo()
		await idle(3)
		ok(scene_json() == base, "[%d] Ctrl+Z restores the scene JSON exactly" % idx)

	# outside the strip: over the 3D view
	var from2 := await row_pos(pose_name)
	var u1: int = m.undo.size()
	var out := Vector2(900, 300)
	mouse(from2, true)
	await process_frame
	for k in range(1, 7):
		mouse(from2.lerp(out, k / 6.0), null)
		await process_frame
	await idle(2)
	var ln2: ColorRect = m.ui_card_row.get_node("drop_line")
	var hid := not ln2.visible
	var can_out: bool = m._card_can_drop(Vector2.ZERO, {"kine_pose": path, "name": "x"}, 0, root.gui_get_hovered_control())
	mouse(out, false)
	await idle(4)
	ok(not can_out and hid and scene_json() == base and m.undo.size() == u1, "drop outside the strip: no line, same JSON, same undo depth (%d)" % (m.undo.size() - u1))

	print("R8 FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
