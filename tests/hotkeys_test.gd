## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/hotkeys_test.gd    (HOTKEYS, docs/ROADMAP.md item 5)
## The cheat sheet (held ?) lists exactly the commands that have keys, grouped by area; K can be rebound to J (J keys the
## part, K does nothing); a key another command has is refused until it is pressed again; reset restores; the keys are
## saved to the test's own config and read back. Screenshot of the cheat sheet: env HOTKEYS_SHOT (default user://).
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


func send(code: Key, down: bool, uni := 0, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = uni
	e.shift_pressed = shift
	e.pressed = down
	root.push_input(e)
	await process_frame
	await idle(2)


func tap(code: Key, uni := 0, shift := false) -> void:
	await send(code, true, uni, shift)
	await send(code, false, uni, shift)


func shown() -> bool:
	return m.ui_keys != null and m.ui_keys.is_visible_in_tree()


func labels() -> Array:
	if m.ui_keys == null:
		return []
	return m.ui_keys.find_children("key_*", "Label", true, false).map(func(n): return String(n.name).substr(4))


func keyed_ids() -> Array:
	return m.ui_cmd.commands.filter(func(c): return String(c["keys"]) != "").map(func(c): return String(c["id"]))


func cmd(id: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["id"] == id:
			return c
	return {}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var cfg: String = m.settings
	ok(cfg.begins_with("user://poser_test_") and cfg != "user://poser.cfg", "0 the test saves to its own config (%s), never poser.cfg" % cfg)

	# 1. the cheat sheet: held ? shows every keyed command, grouped by area; released it hides
	await send(KEY_SLASH, true, 63, true)
	ok(shown(), "1 holding ? (Shift+/) shows the cheat sheet")
	var keyed := keyed_ids()
	var have := labels()
	var missing := keyed.filter(func(x): return not x in have)
	var extra := have.filter(func(x): return not x in keyed)
	ok(keyed.size() >= 30 and missing.is_empty() and extra.is_empty() and have.size() == keyed.size(),
		"2 the sheet lists exactly the commands that have keys: %d (missing %s, extra %s)" % [have.size(), missing, extra])
	var heads: Array = m.ui_keys.find_children("*", "Label", true, false).map(func(n): return n.text) if m.ui_keys != null else []
	var areas := Hotkeys.cheat_groups(m.ui_cmd.commands).map(func(g): return String(g[0]).to_upper())
	var want_heads := areas.filter(func(a): return a in heads)
	ok(areas.size() >= 6 and want_heads.size() == areas.size() and "POSE" in heads and "VIEW" in heads and "TIMELINE" in heads,
		"3 grouped by area: %s" % [areas])
	var shot := OS.get_environment("HOTKEYS_SHOT")
	if shot == "":
		shot = "user://hotkeys_cheat.png"
	await idle(3)
	m.get_viewport().get_texture().get_image().save_png(shot)
	print("     screenshot: %s" % ProjectSettings.globalize_path(shot) if shot.begins_with("user://") else "     screenshot: %s" % shot)
	await send(KEY_SLASH, false, 63, true)
	ok(not shown(), "4 releasing ? hides it")

	# 2. the editor command is in the registry
	var edit := cmd("help_edit_hotkeys")
	ok(not edit.is_empty() and String(edit["keys"]) == "", "5 Help: edit hotkeys is a command with no key")

	# 3. rebinding K to J: J keys the part, K does nothing
	m._card_add()
	m.sel = "upperarm_r"
	var before_undo: int = m.undo.size()
	var r: Dictionary = m.hk.set_key("key_the_part_here", "J")
	ok(r["ok"] and cmd("key_the_part_here")["keys"] == "J" and cmd("key_the_part_here")["default"] == "K",
		"6 K's command is now on J: %s" % r["msg"])
	m.keys_overlay(true)
	var shown_j: String = m.ui_keys.find_child("key_key_the_part_here", true, false).text if m.ui_keys != null and m.ui_keys.find_child("key_key_the_part_here", true, false) != null else "?"
	m.keys_overlay(false)
	ok(shown_j == "J", "6b the cheat sheet shows J for it after the change (it says %s)" % shown_j)
	await tap(KEY_K)
	ok(m.undo.size() == before_undo and not m.S.part_keys.has("upperarm_r"), "7 K does nothing now")
	await tap(KEY_J)
	ok(m.S.part_keys.has("upperarm_r") and m.undo.size() == before_undo + 1, "8 J keys the picked part (one undo step)")

	# 4. a conflict is refused until the same key is pressed again, in the editor
	var rc: Dictionary = m.hk.set_key("undo", "J")
	ok(not rc["ok"] and rc.get("conflict", "") == "key_the_part_here" and cmd("key_the_part_here")["keys"] == "J",
		"9 J taken by Key the part: refused, it keeps J (%s)" % rc["msg"])
	m.hk.open_editor()
	await idle(2)
	ok(m.hk.ui.is_visible_in_tree() and m.hk.rows.get_child_count() >= 200, "10 the editor lists every command (%d rows)" % m.hk.rows.get_child_count())
	m.hk.begin_capture("undo")
	await tap(KEY_J)
	ok(cmd("undo")["keys"] == "Ctrl+Z" and m.hk.pending == "J" and "Press J again" in m.hk.status.text,
		"11 typing J in the editor is refused the first time: %s" % m.hk.status.text)
	await tap(KEY_J)
	ok(cmd("undo")["keys"] == "J" and cmd("key_the_part_here")["keys"] == "" and m.hk.capture == "",
		"12 pressed again, Undo takes J and Key the part has no key")
	await tap(KEY_ESCAPE)
	ok(not m.hk.ui.visible, "13 Esc closes the editor")

	# 5. reset restores the built-in keys
	m.hk.reset_all()
	ok(cmd("undo")["keys"] == "Ctrl+Z" and cmd("key_the_part_here")["keys"] == "K" and m.hk.over.is_empty(),
		"14 reset to defaults: Undo is Ctrl+Z, Key the part is K")
	var u0: int = m.undo.size()
	await tap(KEY_K)
	ok(m.undo.size() == u0 + 1, "15 K keys the part again after reset (one undo step)")

	# 6. saved and reloaded
	m.hk.set_key("key_the_part_here", "J")
	var cf := ConfigFile.new()
	cf.load(cfg)
	ok(cf.get_value("hotkeys", "key_the_part_here", "") == "J",
		"16 saved under [hotkeys] in the test config")
	m.hk.over.clear()
	m.hk.load_from(cfg)
	m.ui_cmd.commands = m._commands()
	ok(cmd("key_the_part_here")["keys"] == "J" and m.hk.over.size() == 1, "17 read back at start: K's command is on J")
	m.hk.reset_all()
	cf = ConfigFile.new()
	cf.load(cfg)
	ok(not cf.has_section("hotkeys") or cf.get_section_keys("hotkeys").is_empty(), "18 reset clears the saved section")

	print("HOTKEYS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
