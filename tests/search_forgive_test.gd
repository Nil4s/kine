## godot --path . -s tests/search_forgive_test.gd     (GATES R1; needs a window)
## SEARCH THAT FORGIVES: every command has a description, every shortcut main answers to is in the shortcut column,
## the words people use for a thing find it (one SYNONYMS table), a one-letter typo still finds it, and the last
## commands run head the empty search, newest first, marked "recent".
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func top(q: String, n: int) -> Array:
	m.ui_cmd.box.text = q
	m.ui_cmd._filter()
	return m.ui_cmd.shown.slice(0, n).map(func(c): return c["name"])


func _init() -> void:
	CommandSearch.user_files_off = true   # the user's own saved poses / scenes (scenes/_wip drafts) must not change this result
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var cs: Array = m._commands()
	var nodesc := cs.filter(func(c): return String(c["desc"]).strip_edges().length() < 8).map(func(c): return c["name"])
	ok(nodesc.is_empty(), "%d commands, every one with a description %s" % [cs.size(), nodesc])
	# every key main's keyboard handler answers to (scripts/main.gd _unhandled_input) is shown in the search
	var keys := cs.map(func(c): return c["keys"])
	var missing := []
	for k in ["Ctrl+Z", "Ctrl+Y", "Ctrl+S", "Ctrl+C", "Ctrl+V", "Ctrl+Shift+V", "Enter", "Space", "Tab", "R", "Q", "Shift+Q", "M", "N", "Shift+M",
			"C", "T", "Shift+T", "O", "Shift+O", "Y", "H", "B", "L", "G", "F", "[", "]", ",", ".", "-", "=", "1", "2", "3", "4", "5"]:
		if not k in keys:
			missing.append(k)
	ok(missing.is_empty(), "every shortcut is in the shortcut column (missing: %s)" % [missing])
	m.ui_cmd.open()
	await process_frame
	# synonyms: the word people type -> the command they mean
	# (keytypes merge: plain "inbetween" now exactly names "Part key type: inbetween", so the card command is asked with "card" too)
	for pair in [["keyframe", "CLIP this pose (add a card)"], ["flip", "Mirror the whole pose"], ["rewind", "Undo"],
			["pin foot", "Plant the left foot on this card"], ["dark", "Light / dark theme"], ["inbetween card", "Add an in-between card"],
			["duplicate pose", "Copy pose"], ["screenshot", ""], ["sword", "Weapon: metal bat"]]:
		# "sword" literally names rows now (the command "New from template: Sword swing" and, when the scenes folder has them, the
		# files "sword swing", "sword swing 2"), which rightly rank first; the SYNONYM it exercises (sword -> weapon) must still put
		# the weapon rows right behind those literal hits: top 6, not top 3
		var t := top(pair[0], 6 if pair[0] == "sword" else 3)
		if pair[1] == "":
			continue
		ok(pair[1] in t, "'%s' -> %s in the top %d %s" % [pair[0], pair[1], t.size(), t])
	# typos: one letter off ("pase" is one off BOTH paste and pose/pause: ambiguous, so a swap is used for paste)
	for pair in [["mirorr", "Mirror the whole pose"], ["onoin", "Onion skin on/off"], ["trial", "Motion trail on/off"], ["chekc", "Check the motion"],
			["plish", "Polish the scene (new copy)"], ["dummmy", "Dummy on/off"], ["weapn", "Remove the weapon"], ["patse", "Paste pose"],
			["undp", "Undo"], ["spedd graph", "Speed graph on/off"]]:
		# 'chekc' also fits the three new CHECK commands (Page: CHECK, Check: weapon clashes, Check: could a human do this?), all one
		# swap away and all legitimately first: it is looked for in the top 6 (round 6 added the page bar and the check switches)
		var t := top(pair[0], 6 if pair[0] == "chekc" else 3)
		ok(pair[1] in t or (pair[0] == "weapn" and t.any(func(x): return "eapon" in x)), "typo '%s' -> %s %s" % [pair[0], pair[1], t])
	ok(top("zzqx", 99).is_empty() and top("bat", 99).size() < cs.size() / 2, "nonsense finds nothing; a real word still narrows (bat: %d of %d)" % [top("bat", 99).size(), cs.size()])
	# recent: run three, newest first on the empty search, marked
	for n in ["Onion skin on/off", "Motion trail on/off", "Speed graph on/off"]:
		top(n, 1)
		m.ui_cmd._run(0)
		await process_frame
	m.ui_cmd.open()
	await process_frame
	var t3 := top("", 3)
	var it: TreeItem = m.ui_cmd.list.get_root().get_first_child()
	ok(t3 == ["Speed graph on/off", "Motion trail on/off", "Onion skin on/off"] and it.get_text(1).begins_with("recent"), "the empty search starts with the last three run, newest first, marked: %s / '%s'" % [t3, it.get_text(1)])
	m.ui_cmd._run(2)   # running one again moves it to the top, no duplicate
	m.ui_cmd.open()
	ok(top("", 3) == ["Onion skin on/off", "Speed graph on/off", "Motion trail on/off"] and m.ui_cmd.recent.size() == 3, "run one again: it moves to the top, no duplicate %s" % [top("", 3)])
	print("SEARCH FORGIVE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
