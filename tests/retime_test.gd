## godot --path . -s tests/retime_test.gd     (GATES X1, UPGRADES #57; needs a window)
## RETIME A RANGE: a real click on card 3 and a real Shift+click on card 6 pick cards 3-6 (shown picked); Slower then
## retimes those four (the move into each and its hold), nothing else, one undo step; undo restores byte-for-byte; a
## plain click picks one card again. retime(): the range's span grows by exactly span x (k - 1) (to 1 ms a card), every
## card outside byte-identical; bad ranges refused and named, with no undo step. And the CLI step retime=A-B:pct.
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


func click(addr: String, shift := false) -> bool:
	var n: Node = m
	for part in addr.split("/"):
		n = n.find_child(part, true, false) if n != null else null
	var c := n as Control
	if c == null or not c.is_visible_in_tree():
		return false
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.shift_pressed = shift
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(2)
	return true


func picked_look() -> Array:   # which cards are drawn as picked
	var out := []
	for i in m.S.cards.size():
		var pc := m.find_child("card_%d" % (i + 1), true, false) as PanelContainer
		if pc != null and (pc.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Tok.c("card_sel"):
			out.append(i)
	return out


func span(a: int, b: int) -> float:
	var s := 0.0
	for i in range(a, b + 1):
		s += (m.S.move_time(i) if i > 0 else 0.0) + float(m.S.cards[i]["hold"])
	return s


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()

	await click("card_3/b_pick")
	await click("card_6/b_pick", true)
	ok(m.card_range() == [2, 3, 4, 5] and picked_look() == [2, 3, 4, 5] and m.sel_card == 2,
		"1 click card 3, Shift+click card 6: cards 3-6 picked and shown picked (%s), card 3 still the picked one" % [picked_look().map(func(i): return i + 1)])
	var before: Array = m.S.cards.duplicate(true)
	var mv: Array = range(m.S.cards.size()).map(func(i): return m.S.move_time(i))
	var u0: int = m.undo.size()
	await click("b_slower")
	var right := true
	for i in m.S.cards.size():
		if i >= 2 and i <= 5:
			right = right and absf(float(m.S.cards[i]["hold"]) - snappedf(float(before[i]["hold"]) * 1.1, 0.01)) < 1e-9
			right = right and absf(float(m.S.cards[i]["move"]) - snappedf(maxf(0.04, mv[i] * 1.1), 0.01)) < 1e-9
		else:
			right = right and JSON.stringify(m.S.cards[i]) == JSON.stringify(before[i])
	ok(right and m.undo.size() == u0 + 1, "2 Slower: cards 3-6 each 10%% slower (move and hold), the other %d cards byte-identical, one undo step" % (m.S.cards.size() - 4))
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == JSON.stringify(before), "3 undo: every card byte-for-byte as before")
	await click("card_4/b_pick")
	ok(m.card_range() == [3] and picked_look() == [3], "4 a plain click on card 4: one card again (%s)" % [picked_look().map(func(i): return i + 1)])
	await click("card_6/b_pick", true)
	m._card_add()   # something else picks a card: the range must not follow it
	await idle()
	ok(m.card_range() == [m.sel_card], "5 a range, then Add (which picks the new card): the range ends with it, not carried over")
	m._undo()
	await idle()

	# exact: retime()
	before = m.S.cards.duplicate(true)
	var L0: float = m.S.length()
	var sp := span(2, 5)
	u0 = m.undo.size()
	var e: String = m.retime(2, 5, 150.0)
	var dl: float = m.S.length() - L0
	var outside := true
	for i in m.S.cards.size():
		if i < 2 or i > 5:
			outside = outside and JSON.stringify(m.S.cards[i]) == JSON.stringify(before[i])
	ok(e == "" and absf(dl - sp * 0.5) <= 0.001 * 8 and outside and m.undo.size() == u0 + 1,
		"6 retime 3-6 at 150 %%: the scene %.3f s longer = their span %.3f x 0.5 = %.3f (to 1 ms a card); the rest byte-identical; one undo step" % [dl, sp, sp * 0.5])
	m._undo()
	await idle()
	u0 = m.undo.size()
	var bad := [m.retime(5, 2, 150.0), m.retime(2, 40, 150.0), m.retime(2, 5, 0.0)]
	ok(bad.all(func(x): return x != "") and m.undo.size() == u0 and JSON.stringify(m.S.cards) == JSON.stringify(before),
		"7 refused, named, nothing changed, no undo step: %s" % [bad.map(func(x): return x.left(60))])

	# the CLI step, in its own process
	var out := []
	var proj := ProjectSettings.globalize_path("res://")
	OS.execute(OS.get_executable_path(), ["--headless", "--path", proj, "-s", "tools/poser_cli.gd", "--", "run", "scenes/combo3.json", "retime=3-6:150", "retime=6-3:150", "--json"], out, true)
	var js: Variant = null
	for line in String(out[0]).split("\n"):
		if line.begins_with("{"):
			js = JSON.parse_string(line)
	var steps: Array = js.get("steps", []) if js is Dictionary else []
	ok(steps.size() == 2 and steps[0]["ok"] and steps[0]["cards_changed"] and steps[0]["undo_steps"] == 1 and not steps[1]["ok"] and "not be after" in String(steps[1].get("error", "")),
		"8 the CLI: retime=3-6:150 ran (cards changed, 1 undo step); retime=6-3:150 refused: '%s'" % (String(steps[1].get("error", "")) if steps.size() > 1 else "no output"))
	print("RETIME: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
