## godot --path . -s tests/r18_test.gd     (needs a window)
## R18: DRAG A CARD TO REORDER. BARS (written before measuring), combo3 (12 cards):
##  1 first->last, last->first, middle->middle: the card order is exactly remove+insert, and every card keeps its own pose,
##    move and hold (the dictionaries are equal to the ones before); each is ONE undo step and undo restores the scene JSON
##  2 mid-drag the thumbnail follows the mouse (ghost centre within 2 px of it) and the gold line is drawn in the strip: between
##    the two cards of the target slot (within 4 px of the gap), inside the strip's rows vertically, in Tok card_play
##  3 a 3 px wiggle is a click: no ghost, no undo step, the release is not eaten; a real drag's release IS eaten (no pick)
##  4 Esc mid-drag: nothing moves, no undo step, the ghost and line are gone, the release picks nothing
##  5 right-click still opens the card menu
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


func btn(i: int) -> Button:
	return m.ui_cards.get_node("card_%d" % (i + 1)).find_child("b_pick", true, false)


func centre(i: int) -> Vector2:
	return btn(i).get_global_rect().get_center()


func press(i: int, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	m._card_title_input(e, i, btn(i))


func move(i: int, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	m._card_title_input(e, i, btn(i))


func release(i: int, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	e.global_position = at
	m._card_title_input(e, i, btn(i))


func fp() -> Array:
	var a := []
	for c in m.S.cards:
		a.append(var_to_str(c))
	return a


func expect(base: Array, i: int, j: int) -> Array:
	var a := base.duplicate()
	var c = a[i]
	a.remove_at(i)
	a.insert(j, c)
	return a


func drag_case(label: String, i: int, target_x: float, want_j: int) -> void:
	var base := fp()
	var js := scene_json()
	var u0: int = m.undo.size()
	var y := centre(i).y
	var p0 := centre(i)
	press(i, p0)
	move(i, p0 + Vector2(10, 0))
	move(i, Vector2(target_x, y))
	var g: Control = m._cd_ghost
	var ln: Control = m._cd_line
	ok(g != null and ln != null and g.get_global_rect().get_center().distance_to(Vector2(target_x, y) + m.CARD_DRAG_LIFT) <= 2.0, "%s: the thumbnail follows the mouse (centre %.1f px off its lifted spot)" % [label, g.get_global_rect().get_center().distance_to(Vector2(target_x, y) + m.CARD_DRAG_LIFT) if g != null else -1.0])
	await idle(2)
	var slot: int = m._cd_slot
	var lx := ln.global_position.x + 1.5
	var gap_ok := false
	if slot == 0:
		gap_ok = absf(lx - btn(0).get_parent().get_parent().get_global_rect().position.x) <= 4.0
	elif slot == base.size():
		gap_ok = absf(lx - m.ui_cards.get_node("card_%d" % base.size()).get_global_rect().end.x) <= 4.0
	else:
		var a: Rect2 = m.ui_cards.get_node("card_%d" % slot).get_global_rect()
		var b: Rect2 = m.ui_cards.get_node("card_%d" % (slot + 1)).get_global_rect()
		gap_ok = lx >= a.end.x - 4.0 and lx <= b.position.x + 4.0
	var sr: Rect2 = m.ui_card_row.get_global_rect()
	ok(gap_ok and ln.get_global_rect().position.y >= sr.position.y - 2.0 and ln.get_global_rect().end.y <= sr.end.y + 2.0 and ln.color.is_equal_approx(Tok.c("card_play")),
		"%s: gold line at slot %d (x %.1f), inside the strip rows" % [label, slot, lx])
	release(i, Vector2(target_x, y))
	ok(m._cd_ghost == null and m._cd_line == null and m._cd_eat, "%s: ghost and line gone, the release is eaten" % label)
	await idle(2)
	ok(fp() == expect(base, i, want_j) and m.undo.size() == u0 + 1 and m.sel_card == want_j, "%s: card %d -> place %d, poses/move/hold travel with it, one undo step" % [label, i + 1, want_j + 1])
	m._card_pick_click(5)
	ok(m.sel_card == want_j, "%s: the eaten release did not pick a card" % label)
	m._undo()
	await idle(2)
	ok(scene_json() == js and fp() == base, "%s: undo restores the scene exactly" % label)
	await idle(2)


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
	await idle(3)
	var n: int = m.S.cards.size()
	ok(n == 12, "combo3 has 12 cards (%d)" % n)
	var last := centre(n - 1).x + 30.0
	await drag_case("first->last", 0, last, n - 1)
	await drag_case("last->first", n - 1, btn(0).get_global_rect().position.x + 3.0, 0)
	await drag_case("middle->middle", 3, centre(7).x + 2.0, 7)
	# 3 a 3 px wiggle
	var u0: int = m.undo.size()
	var base := fp()
	var p := centre(4)
	press(4, p)
	move(4, p + Vector2(3, 0))
	var on_mid: bool = m._cd_ghost != null
	release(4, p + Vector2(3, 0))
	ok(not on_mid and m._cd_ghost == null and not m._cd_eat and m.undo.size() == u0 and fp() == base, "3 px wiggle: no ghost, release not eaten (a click), no edit")
	m._card_pick_click(4)
	ok(m.sel_card == 4, "  and the click picks card 5")
	# 4 Esc (a pick is its own undo step: count from here)
	u0 = m.undo.size()
	press(2, centre(2))
	move(2, centre(2) + Vector2(40, 0))
	move(2, centre(6))
	var had: bool = m._cd_ghost != null and m._cd_line != null
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	m._input(esc)
	release(2, centre(6))
	m._card_pick_click(2)
	ok(had and m._cd_ghost == null and m._cd_line == null and fp() == base and m.undo.size() == u0 and m.sel_card == 4, "Esc mid-drag: cancelled, nothing moved, no undo step, release picked nothing")
	# screenshot mid-drag (placement: whole window); the cards were rebuilt by the picks, let them lay out
	await idle(4)
	press(1, centre(1))
	move(1, centre(1) + Vector2(20, -6))
	move(1, Vector2(centre(8).x + 2.0, centre(8).y - 10.0))
	await idle(4)
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/r18.png")
	release(1, centre(8))
	m._undo()
	await idle(2)
	# 5 right click
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.global_position = centre(2)
	m._card_title_input(rc, 2, btn(2))
	await idle(2)
	ok(m.ui_card_menu != null and m.ui_card_menu.visible, "right-click still opens the card menu")
	print("R18 %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
