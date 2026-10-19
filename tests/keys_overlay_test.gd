## godot --path . -s tests/keys_overlay_test.gd     (GATES X2, UPGRADES #34; needs a window: the fit is measured)
## KEYS ON ONE SCREEN: holding "?" (by the character, as any keyboard types it) shows a list of every command that has a key,
## grouped by area, made from the command registry: every keyed entry on it, nothing else; releasing ? hides it, Esc closes it; a key a test adds
## to the registry shows up the next time it opens; it fits the window; a "?" typed into a text box is text, not this.
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
	await idle(2)


func press(code: Key, uni := 0, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = uni
	e.shift_pressed = shift
	e.pressed = true
	root.push_input(e)
	await process_frame
	await idle(2)


func release(code: Key, uni := 0, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = uni
	e.shift_pressed = shift
	e.pressed = false
	root.push_input(e)
	await process_frame
	await idle(2)


func shown() -> bool:
	return m.ui_keys != null and m.ui_keys.is_visible_in_tree()


func labels() -> Array:
	if m.ui_keys == null:
		return []
	return m.ui_keys.find_children("key_*", "Label", true, false).map(func(n): return String(n.name).substr(4))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await press(KEY_SLASH, 63, true)
	ok(shown(), "1 holding ? opens it")
	await release(KEY_SLASH, 63, true)
	ok(not shown(), "1b releasing ? hides it")
	await press(KEY_SLASH, 63, true)
	var keyed: Array = m.ui_cmd.commands.filter(func(c): return String(c["keys"]) != "").map(func(c): return String(c["id"]))
	var have := labels()
	var missing := keyed.filter(func(x): return not x in have)
	var extra := have.filter(func(x): return not x in keyed)
	ok(keyed.size() >= 30 and missing.is_empty() and extra.is_empty() and have.size() == keyed.size(),
		"2 every keyed registry command is on it and nothing else: %d of %d commands (missing %s, extra %s)" % [have.size(), m.ui_cmd.commands.size(), missing, extra])
	var heads: Array = m.ui_keys.find_children("*", "Label", true, false).map(func(n): return n.text) if m.ui_keys != null else []
	var shift_col: Node = m.ui_keys.find_child("key_mirror_the_whole_pose", true, false) if m.ui_keys != null else null
	ok("POSE" in heads and "VIEW" in heads and "TIMELINE" in heads and shift_col != null and shift_col.text == "Shift+M",
		"3 grouped by area (POSE / VIEW / TIMELINE ...); Shift+M is mirror")
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	ok(m.ui_keys != null and vr.encloses(m.ui_keys.get_global_rect()) and vr.size.x >= 1000, "4 it fits the window at 100 %%: %s inside %s" % [m.ui_keys.get_global_rect() if m.ui_keys != null else Rect2(), vr])
	await key(KEY_ESCAPE)
	m._set_scale(125)
	await idle(4)
	await press(KEY_SLASH, 63, true)
	var vr2: Rect2 = m.get_viewport().get_visible_rect()
	ok(m.ui_keys != null and vr2.encloses(m.ui_keys.get_global_rect()) and labels().size() == keyed.size(), "4b and at 125 %% (the UI has %s): %s, all %d keys still on it (it scrolls)" % [vr2.size, m.ui_keys.get_global_rect() if m.ui_keys != null else Rect2(), labels().size()])
	await key(KEY_ESCAPE)
	await release(KEY_SLASH, 63, true)
	m._set_scale(100)
	await idle(4)
	await press(KEY_SLASH, 63, true)
	await release(KEY_SLASH, 63, true)
	ok(not shown(), "5 releasing ? again hides it")
	await press(KEY_SLASH, 63, true)
	await key(KEY_ESCAPE)
	ok(not shown(), "6 Esc closes it")
	await release(KEY_SLASH, 63, true)
	m.ui_cmd.commands.append({"id": "zz_test_cmd", "name": "A command a test added", "keys": "Ctrl+Shift+K", "run": func(): pass, "also": "", "edits": false, "desc": "test"})
	await press(KEY_SLASH, 63, true)
	ok(m.ui_keys != null and m.ui_keys.find_child("key_zz_test_cmd", true, false) != null, "7 a command given a key in the registry shows up, nothing else changed")
	await key(KEY_ESCAPE)
	m.ui_cmd.commands.pop_back()
	m.ui_scene_name.grab_focus()
	await idle()
	await release(KEY_SLASH, 63, true)
	await key(KEY_SLASH, 63, true)
	ok(not shown(), "8 a ? typed into the scene-name box is text, not the list")
	m.ui_scene_name.release_focus()
	print("KEYS OVERLAY: %d failed" % fails)
	quit(1 if fails > 0 else 0)
