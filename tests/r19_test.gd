## godot --path . -s tests/r19_test.gd     (needs a window)
## R19: MULTI-SELECT CARDS (Ctrl+click toggles, Shift+click a range, batch retime / delete / copy+paste). BARS (written before measuring), combo3 (12 cards):
##  1 Ctrl+click adds/removes cards from the set (the first one takes the current card in), Shift+click selects the range from the current card,
##    a plain click selects exactly one again; selecting is no edit (no undo step)
##  2 batch retime x2 on 3 cards: exactly those cards' move (an auto move becomes its number) and hold are x2 (to 1 ms), every other card
##    dictionary is identical; ONE undo step; undo restores the scene JSON byte for byte
##  3 delete 3 cards: exactly those are gone, the rest keep order and content; one undo step; undo restores the JSON
##  4 copy 2 + paste after the current card: 2 new cards right after it with poses/move/hold/names identical to the copied ones, the
##    rest unchanged; one undo step; undo restores the JSON. Copy itself is no edit
##  5 PLACEMENT: a selected card is drawn with a 3 px outline in Tok card_multi (not the playhead's card_play frame), unselected cards have
##    none, and the pixels of the screenshot at the selected cards' top borders are that colour; the right-click menu on a selected card
##    lists the batch actions
##  6 dragging a card of a selection moves just that card (R18 stays), one undo step, the selection ends
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


func click(i: int, ctrl := false, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.position = centre(i)
	e.global_position = centre(i)
	m._card_title_input(e, i, btn(i))


func plain(i: int) -> void:
	m._card_pick_click(i)


func fp() -> Array:
	var a := []
	for c in m.S.cards:
		a.append(var_to_str(c))
	return a


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
	var js0 := scene_json()
	var base := fp()

	# 1 selection
	plain(1)
	await idle(2)
	var u0: int = m.undo.size()
	click(4, true)
	click(6, true)
	ok(m.msel == [1, 4, 6] and m.sel_card == 1, "Ctrl+click 5 and 7 after picking 2: selection %s, current card still %d" % [str(m.msel), m.sel_card + 1])
	await idle(2)
	click(4, true)
	ok(m.msel == [1, 6], "Ctrl+click 5 again takes it out: %s" % str(m.msel))
	click(4, false, true)
	ok(m.msel == [1, 2, 3, 4] and m.sel_card == 1, "Shift+click 5 selects the range 2-5: %s" % str(m.msel))
	plain(5)
	ok(m.msel == [] and m.sel_card == 5, "a plain click selects one card again (selection empty, current card 6)")
	ok(m.undo.size() == u0 + 1, "selecting made no undo step beyond the one plain pick (%d)" % (m.undo.size() - u0))

	# 2 retime x2 on cards 3, 6, 9 (indices 2, 5, 8)
	plain(2)
	click(5, true)
	click(8, true)
	await idle(2)
	var sel: Array = m.msel.duplicate()
	ok(sel == [2, 5, 8], "selection for retime: %s" % str(sel))
	var cards0: Array = m.S.cards.duplicate(true)
	var mv0 := []
	for i in n:
		mv0.append(m.S.move_time(i) if i > 0 else 0.0)
	var js := scene_json()
	u0 = m.undo.size()
	m.cards_retime(2.0)
	await idle(2)
	var good := true
	var diff := ""
	for i in n:
		var c: Dictionary = m.S.cards[i]
		if i in sel:
			var wm: float = snappedf(maxf(0.04, mv0[i] * 2.0), 0.001)
			var wh: float = snappedf(float(cards0[i]["hold"]) * 2.0, 0.001)
			if absf(float(c["move"]) - wm) > 1e-6 or absf(float(c["hold"]) - wh) > 1e-6 or var_to_str(c["pose"]) != var_to_str(cards0[i]["pose"]):
				good = false
				diff += " card %d move %.3f/%.3f hold %.3f/%.3f" % [i + 1, c["move"], wm, c["hold"], wh]
		elif var_to_str(c) != var_to_str(cards0[i]):
			good = false
			diff += " card %d changed" % (i + 1)
	ok(good and m.undo.size() == u0 + 1, "retime x2: exactly cards 3, 6, 9 doubled (move %.2f->%.2f, hold %.2f->%.2f on card 3), the other 9 identical, one undo step%s" % [mv0[2], m.S.cards[2]["move"], cards0[2]["hold"], m.S.cards[2]["hold"], diff])
	m._undo()
	await idle(2)
	ok(scene_json() == js, "undo restores the scene JSON exactly")
	# set hold
	u0 = m.undo.size()
	m.msel = sel.duplicate()
	m.cards_set_hold(0.5)
	var hold_ok := true
	for i in n:
		hold_ok = hold_ok and absf(float(m.S.cards[i]["hold"]) - (0.5 if i in sel else float(cards0[i]["hold"]))) < 1e-6
	ok(hold_ok and m.undo.size() == u0 + 1, "set hold 0.5 s: exactly the 3 selected, one undo step")
	m._undo()
	await idle(2)
	ok(scene_json() == js, "  undo restores the JSON")

	# 3 delete cards 2, 5, 8 (indices 1, 4, 7), current card 10 (index 9)
	plain(9)
	click(1, true)
	click(4, true)
	click(7, true)
	await idle(2)
	ok(m.msel == [1, 4, 7, 9], "selection %s includes the current card (it was taken in with the first Ctrl+click)" % str(m.msel))
	m.card_toggle(9)   # take the current card out again: delete exactly three
	ok(m.msel == [1, 4, 7], "current card toggled out: %s" % str(m.msel))
	js = scene_json()
	var before := fp()
	u0 = m.undo.size()
	m.cards_delete()
	await idle(2)
	var want := []
	for i in n:
		if not i in [1, 4, 7]:
			want.append(before[i])
	ok(m.S.cards.size() == n - 3 and fp() == want and m.undo.size() == u0 + 1 and m.sel_card == 6, "delete 3: %d cards left, exactly cards 2, 5, 8 gone, the rest in order, one undo step, current card follows its card (now %d)" % [m.S.cards.size(), m.sel_card + 1])
	m._undo()
	await idle(2)
	ok(scene_json() == js and fp() == before, "undo restores the scene JSON exactly")

	# 4 copy 2, paste after the current card
	plain(2)
	click(3, false, true)
	ok(m.msel == [2, 3], "Shift range 3-4 selected")
	u0 = m.undo.size()
	m.cards_copy()
	ok(m.undo.size() == u0 and m.card_clip.size() == 2, "copy is no edit")
	plain(6)
	js = scene_json()
	before = fp()
	u0 = m.undo.size()
	m.cards_paste()
	await idle(2)
	var a := fp()
	var pasted_ok: bool = a.size() == n + 2 and a[7] == before[2] and a[8] == before[3] and m.msel == [7, 8] and m.sel_card == 6
	for i in n:
		var j := i if i <= 6 else i + 2
		pasted_ok = pasted_ok and a[j] == before[i]
	ok(pasted_ok and m.undo.size() == u0 + 1, "paste: cards 8-9 are copies of 3-4 (poses, move, hold, names identical), the 12 others unmoved, one undo step")
	m._undo()
	await idle(2)
	ok(scene_json() == js, "undo restores the scene JSON exactly")

	# 5 placement
	plain(1)
	click(3, true)
	click(6, true)
	click(9, true)
	await idle(4)
	var okb := true
	var st_txt := ""
	for i in n:
		var pc: PanelContainer = m.ui_cards.get_node("card_%d" % (i + 1))
		var sb := pc.get_theme_stylebox("panel") as StyleBoxFlat
		var want_sel: bool = i in m.msel
		var is_multi: bool = sb.border_width_left == 3 and sb.border_color.is_equal_approx(Tok.c("card_multi"))
		if is_multi != want_sel:
			okb = false
			st_txt += " card %d" % (i + 1)
	ok(okb and m.msel == [1, 3, 6, 9], "selected cards 2, 4, 7, 10 have the 3 px card_multi outline, the other 8 do not%s" % st_txt)
	ok(not Tok.c("card_multi").is_equal_approx(Tok.c("card_play")), "the selection colour differs from the current-card gold")
	# right-click the selected card 7: the batch menu
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.global_position = centre(6)
	m._card_title_input(rc, 6, btn(6))
	await idle(4)
	var labels := []
	for k in m.ui_card_menu.item_count:
		labels.append(m.ui_card_menu.get_item_text(k))
	var has_all := true
	for w in ["Retime x2 (slower)", "Retime x0.5 (faster)", "Set hold to 0", "Copy 4 cards", "Delete 4 cards"]:
		has_all = has_all and labels.has(w)
	ok(m.ui_card_menu.visible and has_all, "right-click on a selected card opens the batch menu: %s" % str(labels))
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/r19.png")
	var pix_ok := true
	var shown := 0
	for i in [1, 3, 6, 9]:
		var r: Rect2 = m.ui_cards.get_node("card_%d" % (i + 1)).get_global_rect()
		var mr := Rect2(m.ui_card_menu.position, m.ui_card_menu.size).grow(14.0)   # the menu covers part of cards 7 and 10: sample the uncovered end
		var sx := r.position.x + 12.0 if not mr.has_point(Vector2(r.position.x + 12.0, r.position.y + 1.0)) else r.end.x - 12.0
		var px := img.get_pixel(int(sx), int(r.position.y) + 1)
		if absf(px.r - Tok.c("card_multi").r) > 0.1 or absf(px.g - Tok.c("card_multi").g) > 0.1 or absf(px.b - Tok.c("card_multi").b) > 0.1:
			pix_ok = false
			print("  card %d top border pixel %s" % [i + 1, px])
		shown += 1
	ok(pix_ok and shown == 4, "screenshot: the 4 selected cards' top borders are drawn in card_multi")
	m.ui_card_menu.hide()
	await idle(2)

	# 6 dragging a selected card moves just that card
	var b2 := fp()
	u0 = m.undo.size()
	var p0 := centre(6)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p0
	e.global_position = p0
	m._card_title_input(e, 6, btn(6))
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.global_position = p0 + Vector2(12, 0)
	mm.position = mm.global_position
	m._card_title_input(mm, 6, btn(6))
	mm = InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.global_position = centre(10) + Vector2(2, 0)
	mm.position = mm.global_position
	m._card_title_input(mm, 6, btn(6))
	e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.global_position = mm.global_position
	e.position = mm.global_position
	m._card_title_input(e, 6, btn(6))
	await idle(2)
	var w2 := b2.duplicate()
	var cc = w2[6]
	w2.remove_at(6)
	w2.insert(10, cc)
	ok(fp() == w2 and m.undo.size() == u0 + 1 and m.msel == [], "drag of selected card 7 to place 11 moved just that card, one undo step, selection ended")
	m._undo()
	await idle(2)
	ok(scene_json() == js0, "undo restores the scene JSON exactly (back at the start)")
	print("R19 %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
