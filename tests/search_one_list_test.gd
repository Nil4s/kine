## godot --path . -s tests/search_one_list_test.gd     (GATES AA1, UPGRADES #7; a window: real clicks and keys)
## SEARCH STAYS ONE LIST: every ribbon tab clicked (twice round), the theme switched and back, the UI scale changed and
## back, a scene opened, then 20 commands run from the search (S, the name typed, a real Enter; the same one twice in
## a row too): the registry is the size it was, its ids and names unique; the empty search lists every command exactly
## once; a word search's hits are each listed once; the recent list has no repeats and at most RECENT_N.
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


func key(code: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.pressed = down
		root.push_input(e)
		await process_frame


func click(n: Control) -> void:
	var p := n.get_global_rect().get_center()
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
	await idle(2)


func listed() -> Array:
	var out := []
	var r: TreeItem = m.ui_cmd.list.get_root()
	if r == null:
		return out
	for it in r.get_children():
		out.append(it.get_text(0))
	return out


func dupes(a: Array) -> Array:
	var seen := {}
	var out := []
	for x in a:
		if seen.has(x):
			out.append(x)
		seen[x] = true
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var n0: int = m.ui_cmd.commands.size()
	var scale0: int = m.ui_scale
	var dark0: bool = Tok.dark

	for round in 2:
		for t in m.ui_ribbon_tabs:
			await click(m.ui_ribbon_tabs[t])
	m._set_light(dark0)
	await idle(3)
	m._set_light(not dark0)
	await idle(3)
	m._set_scale(125)
	await idle(4)
	m._set_scale(scale0)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(3)

	var runs := ["Front view", "His right view", "Top view", "Front view", "Front view", "Back view", "His left view",
		"Every key on one screen", "Front view", "Top view", "Top view", "Back view", "His right view", "Front view",
		"His left view", "Front view", "Back view", "Back view", "Top view", "Front view"]
	var ran := 0
	for name in runs:
		await key(KEY_S, 115)
		if not m.ui_cmd.visible:
			continue
		m.ui_cmd.box.text = name
		m.ui_cmd._filter()
		await process_frame
		var picked: String = listed()[0] if listed().size() > 0 else ""
		await key(KEY_ENTER)
		await idle(2)
		if m.ui_keys != null and m.ui_keys.visible:
			m.keys_overlay(false)
		if picked == name and not m.ui_cmd.visible:
			ran += 1
	ok(ran == runs.size(), "1 %d of %d commands run from the search (S, typed, a real Enter), the same one twice in a row 4 times" % [ran, runs.size()])

	var cs: Array = m.ui_cmd.commands
	# the recent merge: opening a scene adds one "File > Recent: <scene>" command, which is the feature; the rest must be as at start
	var cs0: Array = cs.filter(func(c): return not String(c["name"]).begins_with("File > Recent:"))
	var ids := cs0.map(func(c): return c["id"])
	var names := cs0.map(func(c): return c["name"])
	ok(cs0.size() == n0 and dupes(ids).is_empty() and dupes(names).is_empty(),
		"2 after 2 rounds of every tab, the theme and the scale switched and back, a scene opened: the registry %d commands as at start (%d), ids and names unique (dupes: %s %s)" % [cs0.size(), n0, dupes(ids), dupes(names)])
	await key(KEY_S, 115)
	m.ui_cmd.box.text = ""
	m.ui_cmd._filter()
	await process_frame
	var all := listed()
	ok(all.size() == cs.size() and dupes(all).is_empty() and names.all(func(x): return x in all),
		"3 the empty search lists every command once: %d rows for %d commands (dupes: %s)" % [all.size(), cs.size(), dupes(all)])
	var rec: Array = m.ui_cmd.recent
	ok(dupes(rec).is_empty() and rec.size() <= m.ui_cmd.RECENT_N and rec.size() > 0 and rec[0] == "Front view" and all.slice(0, rec.size()) == rec,
		"4 the recent list: %s - no repeats, at most %d, newest first, on top of the empty search" % [rec, m.ui_cmd.RECENT_N])
	m.ui_cmd.box.text = "view"
	m.ui_cmd._filter()
	await process_frame
	var hits := listed()
	ok(hits.size() >= 5 and dupes(hits).is_empty(), "5 a word search ('view'): %d hits, each once" % hits.size())
	await key(KEY_ESCAPE)
	m.ui_cmd.close()
	print("SEARCH ONE LIST: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
