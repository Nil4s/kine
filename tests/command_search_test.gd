## godot --path . -s tests/command_search_test.gd     (GATES N1; needs a window)
## S = command search, driven by key events: S opens it, typing filters, arrows + Enter run one, Esc closes, a click in
## the view closes it. Then EVERY command is run once through the box's own run path (the four that write files are
## checked by what they are bound to instead, so no pose / scene of Nick's is written). Errors: the sweep greps the log.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	root.push_input(k)


## typed as a keyboard sends it: one key event per letter, with its character
func type(t: String) -> void:
	for ch in t:
		var k := InputEventKey.new()
		k.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
		k.unicode = ch.unicode_at(0)
		k.pressed = true
		root.push_input(k)
	await process_frame


func names() -> Array:
	return m.ui_cmd.shown.map(func(c): return c["name"])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var cs: CommandSearch = m.ui_cmd
	var n_all: int = cs.commands.size()
	ok(not cs.visible, "the search box starts hidden (%d commands in it)" % n_all)
	await type("s")   # a real S: keycode AND the character 's'
	ok(cs.visible and cs.box.has_focus() and cs.shown.size() == n_all and cs.box.text == "", "S opens it, the cursor in the box, all %d listed, the box empty (no stray 's': '%s')" % [cs.shown.size(), cs.box.text])
	await type("s")   # typed into the box now, not a second open
	ok(cs.box.text == "s" and cs.visible, "a second S types into the box ('%s'), it does not reopen" % cs.box.text)
	cs.box.text = ""
	await type("mirr")
	print("     'mirr' -> %s" % str(names()))
	ok(cs.shown.size() >= 3 and names().all(func(x): return x.to_lower().contains("mirr") or x.contains("side")), "'mirr' lists only mirror commands (%d)" % cs.shown.size())
	cs.box.text = ""
	await type("trail")
	ok(names()[0] == "Motion trail on/off", "'trail': first is '%s'" % names()[0])
	var t0: bool = m.ov.trail_on
	key(KEY_ENTER)
	await process_frame
	ok(m.ov.trail_on != t0 and not cs.visible, "Enter runs it: trail %s -> %s, the box closed" % [t0, m.ov.trail_on])
	# arrows: 'view' -> Front, His right...; Down twice = His left? no: the third in the list
	key(KEY_S)
	await process_frame
	await type("view")
	var third: String = names()[2]
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_ENTER)
	await process_frame
	ok(names().slice(0, 6) == ["Front view", "His right view", "Top view", "Back view", "His left view", "Big view (hide the panels)"] and names().size() >= 7 and names().has("Stepped preview on/off")
		and names().slice(6).all(func(n): return n.to_lower().contains("preview")),
		"'view': the 5 views, Big view, then the preVIEWs (inside a word ranks lower): %s" % str(names()))
	ok(third == "Top view" and is_equal_approx(m.pitch, -89.0), "'view', Down, Down, Enter: '%s' ran (pitch %.0f)" % [third, m.pitch])
	key(KEY_S)
	await process_frame
	await type("staff bo")
	ok(names().size() >= 1 and names()[0] == "Weapon: bo staff", "two words in any order: 'staff bo' -> '%s'" % (names()[0] if names().size() > 0 else "nothing"))
	key(KEY_ESCAPE)
	await process_frame
	ok(not cs.visible and m.B.wep_kind != "staff", "Esc closes it, nothing ran (weapon still %s)" % m.B.wep_kind)
	cs.open()
	await type("zzzq")
	ok(cs.shown.size() == 0, "nonsense matches nothing")
	cs.open()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_MIDDLE
	click.pressed = true
	click.position = Vector2(700, 400)
	m._unhandled_input(click)
	ok(not cs.visible, "a click in the view puts it away")
	# a key typed into the box is the box's: S, T, Space... while typing run nothing in the view
	cs.open()
	var tr: bool = m.ov.trail_on
	await type("t ")
	ok(m.ov.trail_on == tr and cs.visible and not m.playing, "typing 't ' in the box toggles no trail and plays nothing")
	cs.close()
	m.dragging = ""

	# EVERY command, once, through the box's run path. The file writers: by what they are bound to
	var writers := {"Save pose": "_save_pose", "Save scene": "_save_scene", "Polish the scene (new copy)": "_polish", "Mirror the scene (left-handed copy)": "_tool", "Save a version": "_save_version", "Export to game": "_export_game", "Export animation (.glb)": "_export_glb", "Export animation (.bvh)": "_export_bvh", "Export playblast (video)": "_export_playblast", "Audio: add a sound file (wav / ogg / mp3)": "_audio_ask", "Import animation (fbx / glb / gltf / bvh)...": "_anim_import_ask"}
	var ran := 0
	for c in cs.commands:
		var f: Callable = c["run"]
		if writers.has(c["name"]):
			ok(f.get_method() == writers[c["name"]], "  '%s' is bound to %s (not run: it writes a file)" % [c["name"], f.get_method()])
			continue
		cs.open()
		cs.shown = [c]
		cs._run(0)
		await process_frame
		ran += 1
		if m.ui_help.visible:
			m.ui_help.visible = false
	ok(ran + writers.size() == n_all, "ran %d commands + %d checked by binding = all %d" % [ran, writers.size(), n_all])
	ok(not cs.visible, "the box is closed after each")
	print("COMMAND SEARCH %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
