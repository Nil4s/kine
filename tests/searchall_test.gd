## godot --path . -s tests/searchall_test.gd     (GATES N1 style; needs a window)
## ROADMAP 52: the S box also finds the saved poses (poses/, moves/ pose files) and scenes (scenes/, scenes/_wip, moves/
## scene files). Checked against the files on disk: "walk", "bat", "scene: combo", "pose: bat" (no pose is called
## "guard": the file moves/bo_guard.json is the one that is), the kind prefix filter, Enter on a pose (one undo step),
## Enter on a scene (the normal open: asks first when there are unsaved changes), and the time per keystroke.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(code: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
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


func rows() -> Array:
	return m.ui_cmd.shown


func top(n := 1) -> Array:
	return rows().slice(0, n).map(func(c): return "%s [%s]" % [c["name"], c.get("kind", "command")])


func kind_of(c: Dictionary) -> String:
	return c.get("kind", "command")


func kinds() -> Array:
	return rows().map(func(c): return c.get("kind", "command"))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var cs: CommandSearch = m.ui_cmd
	var n_cmd: int = cs.commands.size()
	var files: Array = m._search_files()
	var n_pose := files.filter(func(c): return kind_of(c) == "pose").size()
	var n_scene := files.filter(func(c): return kind_of(c) == "scene").size()
	print("     on disk: %d commands, %d pose rows, %d scene rows" % [n_cmd, n_pose, n_scene])
	ok(n_pose >= 6 and n_scene >= 10 and files.any(func(c): return c["name"] == "bat hold") and files.any(func(c): return c["name"] == "combo3")
		and files.any(func(c): return c["name"] == "bo guard" and kind_of(c) == "pose"), "the rows come from disk: %d poses (bat hold, bo guard), %d scenes (combo3)" % [n_pose, n_scene])

	# the empty box still lists the commands only (the old list, recent first)
	await type("s")
	ok(cs.visible and cs.shown.size() == n_cmd and kinds().all(func(k): return k == "command"), "S, empty: the %d commands only" % n_cmd)

	# "walk": a scene's name, with no command named walk
	cs.box.text = ""
	await type("walk")
	print("     'walk' -> %s" % str(top(4)))
	# round 6 added more commands named walk ('Walk along a path...', 'Compare the walk to real walkers'): any of them may rank first on the tie
	# a command and the scene "walk bat" both have the whole word (12): the command ranks first on the tie (the rule), the scene is the first scene row
	var first_walk_scene := kinds().find("scene")
	ok(kind_of(rows()[0]) == "command" and str(rows()[0]["name"]).to_lower().contains("walk") and rows()[first_walk_scene]["name"] == "walk bat",
		"'walk': a command ties at the whole word and ranks first ('%s'); the scene 'walk bat' is the first scene row (#%d of %d hits)" % [rows()[0]["name"], first_walk_scene, rows().size()])

	# "bat": a command, a pose and a scene all have the word; the command ranks first on the equal score
	cs.box.text = ""
	await type("bat")
	print("     'bat' -> %s" % str(top(6)))
	var first_pose := kinds().find("pose")
	var first_scene := kinds().find("scene")
	ok(kinds().has("pose") and kinds().has("scene") and kinds().has("command"), "'bat': commands, poses and scenes all answer (%d hits)" % rows().size())
	ok(kind_of(rows()[0]) == "command" and first_pose > 0 and first_scene > 0, "'bat': a command ranks first on the tie, the file rows after it (first pose at %d, first scene at %d)" % [first_pose, first_scene])

	# "scene: combo": only scenes, the one called combo3 on top
	cs.box.text = ""
	await type("scene: combo")
	print("     'scene: combo' -> %s" % str(top(4)))
	ok(rows().size() >= 1 and rows()[0]["name"] == "combo3" and kind_of(rows()[0]) == "scene", "'scene: combo': top hit combo3 (%d hits)" % rows().size())
	ok(kinds().all(func(k): return k == "scene"), "the 'scene:' filter excludes every command and pose (%d rows, all scenes)" % rows().size())

	# "pose: bat" (the request said "pose: guard": no pose is called guard; moves/bo_guard.json is a pose file, so it is tested below)
	cs.box.text = ""
	await type("pose: bat")
	print("     'pose: bat' -> %s" % str(top(4)))
	ok(kinds().size() >= 4 and kinds().all(func(k): return k == "pose") and rows()[0]["name"].split(" ").has("bat"),
		"'pose: bat': only poses, every hit has the word bat, top '%s' (%d hits: bat hold and bat ready nick among them)" % [rows()[0]["name"], rows().size()])
	ok(rows().any(func(c): return c["name"] == "bat hold") and rows().any(func(c): return c["name"] == "bat ready nick"), "'pose: bat': bat hold and bat ready nick are both listed")
	cs.box.text = ""
	await type("pose: guard")
	print("     'pose: guard' -> %s" % str(top(3)))
	# two pose files hold the word guard: guard bat (poses/lib) and bo guard (moves/bo_guard.json); a tie keeps the list's order
	ok(rows().size() == 2 and rows()[0]["name"] == "guard bat" and rows()[1]["name"] == "bo guard" and kinds() == ["pose", "pose"],
		"'pose: guard': the two guard poses, guard bat first (tie, list order), bo guard (moves/) second (%d hits)" % rows().size())

	# Enter on a pose: the body takes it, ONE undo step restores the body exactly
	cs.box.text = ""
	await type("pose: bat hold")
	var before := JSON.stringify(m.B.to_dict())
	var undo0: int = m.undo.size()
	key(KEY_ENTER)
	await process_frame
	await process_frame
	var after := JSON.stringify(m.B.to_dict())
	ok(not cs.visible and after != before and m.undo.size() == undo0 + 1, "Enter on 'bat hold': the body changes (%d -> %d undo steps, box closed %s)" % [undo0, m.undo.size(), str(not cs.visible)])
	m._undo()
	await process_frame
	ok(JSON.stringify(m.B.to_dict()) == before, "one undo puts the body back exactly as it was")

	# Enter on a scene: the normal open. Clean first: it opens
	cs.open()
	await type("scene: combo")
	key(KEY_ENTER)
	await process_frame
	await process_frame
	ok(m.scene_path == "res://scenes/combo3.json" and (m.ui_save_ask == null or not m.ui_save_ask.visible), "Enter on combo3 (no changes): the scene opens (%s)" % m.scene_path)
	# unsaved changes: Enter asks first and the scene stays
	m.S.cards[0]["hold"] = float(m.S.cards[0]["hold"]) + 0.5
	cs.open()
	await type("scene: walk")
	key(KEY_ENTER)
	await process_frame
	await process_frame
	ok(m.scene_path == "res://scenes/combo3.json" and m.ui_save_ask != null and m.ui_save_ask.visible,   # the save prompt (ROADMAP 50: Save / Don't save / Cancel) is ui_save_ask now, not ui_confirm
		"Enter on walk bat with unsaved changes: asks first, combo3 stays open (dialog %s)" % str(m.ui_save_ask != null and m.ui_save_ask.visible))
	if m.ui_save_ask != null:
		m.ui_save_ask.hide()
	m.S.cards[0]["hold"] = float(m.S.cards[0]["hold"]) - 0.5
	cs.close()

	# keystrokes: the time of the search (the filter and the list rebuild) per keystroke, over every item
	cs.open()
	var worst := 0
	var worst_all := 0
	var total := 0
	var steps := 0
	var words := ["w", "wa", "wal", "walk", "walk ", "walk b", "walk ba", "walk bat", "b", "ba", "bat", "bat ", "scene: c", "scene: combo", "pose: g", "pose: guard", "zzq"]
	for w in words:
		cs.box.text = w
		var typed := CommandSearch.parse_box(w)
		# the fastest of 3 runs of each keystroke: other processes on the machine (the whole suite runs beside other agents' tests)
		# stretch a single run to 7 ms where the same search takes 3.5 ms alone; a slow search is slow all 3 times
		var dt := 1 << 40
		var found: Array = []
		for rep in 3:
			var t0 := Time.get_ticks_usec()
			found = cs.matches(typed[0], typed[1])   # the search: every item matched and ranked
			dt = mini(dt, Time.get_ticks_usec() - t0)
		var t1 := Time.get_ticks_usec()
		cs._filter()                                          # and the list drawn from it, as the box does per keystroke
		var dt_all := Time.get_ticks_usec() - t1
		worst = maxi(worst, dt)
		worst_all = maxi(worst_all, dt_all)
		total += dt
		steps += 1
		print("     keystroke %-16s search %.2f ms (%d rows), with the list drawn %.2f ms" % ["'" + w + "'", dt / 1000.0, found.size(), dt_all / 1000.0])
	print("     %d keystrokes over %d items: search worst %.2f ms, mean %.2f ms; with the list drawn, worst %.2f ms" % [steps, n_cmd + files.size(), worst / 1000.0, total / 1000.0 / steps, worst_all / 1000.0])
	ok(worst < 5000, "search over all items: worst keystroke %.2f ms (under 5 ms)" % (worst / 1000.0))
	cs.close()
	ok(not cs.visible, "the box closes")

	print("SEARCHALL %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
