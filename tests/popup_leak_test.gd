## godot --path . -s tests/popup_leak_test.gd     (GATES Z2, UPGRADES #15; a window: the keys are real)
## NOTHING LEFT BEHIND: each pop-up opened and closed 100 times - Search (S, then Esc: real keys, a word typed so the
## list refilters), the keys list (? and ? again: real keys), Help (its button), the Animator tools menu (shown and
## hidden), the ring menu on a part - and after each, once the frame has freed what it queued, the node count, the
## orphan nodes and the object count have not grown over 100 cycles and are exactly flat over 100 more.
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


func key(code: Key, uni := 0, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame


func counts() -> Array:
	await idle(4)
	return [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT))]


func cycle(what: String) -> void:
	match what:
		"search":
			await key(KEY_S, 115)
			m.ui_cmd.box.text = "mir"
			m.ui_cmd._filter()
			await process_frame
			await key(KEY_ESCAPE)
			if m.ui_cmd.visible:   # Esc in the box: the search's own key handler
				m.ui_cmd.close()
		"keys":
			await key(KEY_SLASH, 63, true)
			await key(KEY_SLASH, 63, true)
		"help":
			m.find_child("b_help", true, false).emit_signal("pressed") if m.find_child("b_help", true, false) != null else (func(): m.ui_help.visible = not m.ui_help.visible).call()
			await process_frame
			m.ui_help.visible = false
		"tools":
			m.ui_tools.show_popup()
			await process_frame
			m.ui_tools.get_popup().hide()
		"ring":
			m._ring_open("lowerarm_r", Vector2(600, 400))
			await process_frame
			m.ui_ring.close()
	await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	# settle first: the dummy and the card previews finish their first work off-thread and free what they used (a
	# first run measured search's objects 3399 -> 3395: that settling, not the search)
	var was := -1
	for i in 120:
		await idle(5)
		var now := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if now == was:
			break
		was = now
	for what in ["search", "keys", "help", "tools", "ring"]:
		for i in 3:
			await cycle(what)
		var a := await counts()
		for i in 100:
			await cycle(what)
		var b := await counts()
		for i in 100:
			await cycle(what)
		var c := await counts()
		# no growth over the first 100, and exactly flat over the next 100 (a count can DROP while something timed
		# elsewhere finishes: traced, search's objects fell 3399 -> 3395 at cycle 8 whatever was open; a leak grows)
		ok(b[0] <= a[0] and b[1] <= a[1] and b[2] <= a[2] and c == b,
			"%-6s opened and closed 100 + 100 times: nodes %d -> %d -> %d, orphan nodes %d -> %d -> %d, objects %d -> %d -> %d" % [what, a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2]])
	print("POPUP LEAK: %d failed" % fails)
	quit(1 if fails > 0 else 0)
