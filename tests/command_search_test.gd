## godot --path . -s tests/command_search_test.gd     (GATES N1; needs a window)
## S = command search, driven by key events: S opens it, typing filters, arrows + Enter run one, Esc closes, a click in
## the view closes it. Then EVERY command is run once through the box's own run path (the four that write files are
## checked by what they are bound to instead, so no pose / scene of Nick's is written). Errors: the sweep greps the log.
extends SceneTree

var fails := 0
var m: Node
var t0 := 0


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


## the folders this test's commands may write into (the user's work lives there too: only files NEW during the run go)
const OWNED := ["res://bodies", "res://scenes", "res://poses"]

func listing() -> Dictionary:
	var out := {}
	for d in OWNED:
		_walk(d, out)
	return out


func _walk(dir: String, out: Dictionary) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		out[dir.path_join(f)] = true
	for s in da.get_directories():
		_walk(dir.path_join(s), out)


## delete the files this run created inside OWNED (never one that existed before, never outside res://)
func remove_run_files(before: Dictionary) -> int:
	var n := 0
	for p in listing():
		if before.has(p) or not String(p).begins_with("res://"):
			continue
		var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		print("removed run file %s (%s)" % [p, "ok" if err == OK else "error %d" % err])
		n += 1
	return n


func _windows(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Window:
			out.append(c)
		out.append_array(_windows(c))
	return out


func names() -> Array:
	return m.ui_cmd.shown.map(func(c): return c["name"])


func stamp(what: String) -> void:   # TIMING (temporary): when each phase ends, to find where a run stops
	print("T+%7.1fs %s" % [(Time.get_ticks_msec() - t0) / 1000.0, what])


func _init() -> void:
	t0 = Time.get_ticks_msec()
	stamp("start")
	root.tree_exiting.connect(func(): stamp("root tree_exiting"))
	CommandSearch.user_files_off = true   # the user's own saved poses / scenes (scenes/_wip drafts) must not change this result
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
	ok(cs.shown.size() >= 3 and m.ui_cmd.shown.all(func(c): return (c["name"] + " " + str(c.get("also", ""))).to_lower().contains("mirr") or c["name"].contains("side")), "'mirr' lists only mirror commands (%d)" % cs.shown.size())
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
		and m.ui_cmd.shown.slice(6).all(func(c): return (c["name"] + " " + str(c.get("also", ""))).to_lower().contains("view")),
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
	var times := []
	var files_before := listing()
	var seen_files := files_before.duplicate()
	stamp("sweep start (%d commands)" % n_all)
	for c in cs.commands:
		var f: Callable = c["run"]
		if writers.has(c["name"]):
			var fw: Callable = c.get("raw", f)
			ok(fw.get_method() == writers[c["name"]], "  '%s' is bound to %s (not run: it writes a file)" % [c["name"], fw.get_method()])
			continue
		cs.open()
		cs.shown = [c]
		var ct := Time.get_ticks_msec()
		cs._run(0)
		await process_frame
		times.append([Time.get_ticks_msec() - ct, c["name"]])
		var now_files := listing()   # which command wrote a file of its own (named in the log, removed below)
		for p in now_files:
			if not seen_files.has(p):
				print("WROTE %s by '%s'" % [p, c["name"]])
				seen_files[p] = true
		ran += 1
		if m.ui_help.visible:
			m.ui_help.visible = false
	stamp("sweep done")
	# the commands left dialogs open (Save changes?, template, restore, a file picker): an exclusive window left up at quit is
	# what the exit then waits on, so they are put away first (hidden, then freed) and the box with them
	cs.close()
	var left := 0
	for w in _windows(m):
		if (w as Window).visible:   # only the ones a command left up: the app's own windows stay as they are
			(w as Window).hide()
			left += 1
	print("closed %d open window(s) before quit" % left)
	for _k in 3:
		await process_frame
	var removed := remove_run_files(files_before)
	ok(true, "removed %d file(s) this run created in %s" % [removed, str(OWNED)])
	times.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(10, times.size()):
		print("SLOW %6d ms  %s" % [times[i][0], times[i][1]])
	ok(ran + writers.size() == n_all, "ran %d commands + %d checked by binding = all %d" % [ran, writers.size(), n_all])
	ok(not cs.visible, "the box is closed after each")
	print("COMMAND SEARCH %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	stamp("quit(%d)" % fails)
	quit(fails)
