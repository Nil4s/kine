## godot --path . -s tests/rise_ui_test.gd     (ROADMAP 94; needs a window; the buttons are clicked)
## SET > Sit down / Stand up / Get up. BARS (ours): each click adds its whole run of cards as ONE undo step and Ctrl+Z
## takes the run (and the scene settings Get up changes) back; with no chair picked Sit down / Stand up are greyed and,
## run from the command search, are refused in words naming what to pick and change nothing; the three commands are in
## the command search (_commands) by the names "Sit down on the chair", "Stand up", "Get up from the floor".
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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)


func on_set(t: String) -> BaseButton:
	for b in m.ui_ribbon["SET"].find_children("*", "BaseButton", true, false):
		if m.label_of(b) == t:
			return b
	return null


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_rise_ui"
	m.sel_card = 0
	m._ribbon("SET")
	await idle(3)
	var names: Array = m._commands().map(func(c): return c["name"])
	ok("Sit down on the chair" in names and "Stand up" in names and "Get up from the floor" in names, "command search lists the three commands")
	# no prop picked: greyed, and the command says what to pick
	m.sel_prop = -1
	m._props_show()
	await idle(2)
	var n0: int = m.S.cards.size()
	var u0: int = m.undo.size()
	ok(on_set("Sit down").disabled and on_set("Stand up").disabled and not on_set("Get up").disabled, "no chair picked: Sit down and Stand up greyed, Get up live")
	m._rise_stand_up()
	ok(m.S.cards.size() == n0 and m.undo.size() == u0 and m.ui_status.text.contains("pick one"), "Stand up with no chair: refused ('%s'), nothing changed" % m.ui_status.text.left(80))
	# a chair
	m._prop_add("chair")
	await idle(2)
	for t in ["Stand up", "Sit down"]:
		m.sel_card = 0
		var a: int = m.S.cards.size()
		var u: int = m.undo.size()
		await click_ctl(on_set(t))
		var added: int = m.S.cards.size() - a
		ok(added == 9 and m.undo.size() == u + 1, "%s clicked: %d cards, one undo step" % [t, added])
		m._undo()
		await idle(2)
		ok(m.S.cards.size() == a, "  Ctrl+Z: back to %d cards" % a)
	# get up
	m.sel_card = 0
	var nat0: bool = m.S.natural
	var fl0: bool = m.S.on_floor
	var a2: int = m.S.cards.size()
	var u2: int = m.undo.size()
	await click_ctl(on_set("Get up"))
	var added2: int = m.S.cards.size() - a2
	ok(added2 >= 9 and m.undo.size() == u2 + 1 and not m.S.natural and not m.S.on_floor, "Get up clicked: %d cards, one undo step, scene natural=%s on_floor=%s" % [added2, m.S.natural, m.S.on_floor])
	m._undo()
	await idle(2)
	ok(m.S.cards.size() == a2 and m.S.natural == nat0 and m.S.on_floor == fl0, "  Ctrl+Z: %d cards, natural and on_floor back (%s, %s)" % [m.S.cards.size(), m.S.natural, m.S.on_floor])
	print("RESULT %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
