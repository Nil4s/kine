## godot --path . -s tests/examples_test.gd     (GATES S3; needs a window)
## EXAMPLES: the empty state shows three example buttons; one click opens the example as a COPY (cards loaded, no path,
## a new name); an edit + Save writes the new name and leaves the example file byte-identical. (The save goes to
## scenes/_wip/ here, so the test writes nothing of Nick's; the name box is what the user would see.)
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	ok(m.S.cards.is_empty(), "the poser starts with no scene")
	var ex: Array = m.ui_cards.get_children().filter(func(c): return c is Button and c.text.begins_with("Example: "))
	ok(ex.size() == 3 and ex.all(func(b): return b.is_visible_in_tree()), "the empty state shows %s" % [ex.map(func(b): return b.text)])
	var before := {}
	for e in m.EXAMPLES:
		before[e[1]] = FileAccess.get_file_as_string(e[1])
	for k in 3:
		m.S = Scene.new()
		m.scene_path = ""
		m._rebuild_cards()
		await process_frame
		var b: Button = m.ui_cards.get_children().filter(func(c): return c is Button and c.text.begins_with("Example: "))[k]
		var bt := b.text   # the button goes when the cards are rebuilt
		b.pressed.emit()
		await process_frame
		ok(m.S.cards.size() >= 2 and m.scene_path == "" and m.S.name.ends_with("_mine") and m.ui_scene_name.text == m.S.name, "'%s': %d cards, opened as a copy named '%s' (no path)" % [bt, m.S.cards.size(), m.S.name])
	# edit + save: the example stays, the copy is written
	m._card_pick(1)
	m._speed(1.1)
	var out := "res://scenes/_wip/zz_example_mine.json"
	m.ui_scene_name.text = "_wip/zz_example_mine"
	m._save_scene()
	await process_frame
	ok(FileAccess.file_exists(out) and not (m.ui_confirm != null and m.ui_confirm.visible), "Save: the copy is written as a new file, no dialog")
	var same := true
	for e in m.EXAMPLES:
		same = same and FileAccess.get_file_as_string(e[1]) == before[e[1]]
	ok(same, "the three example files are byte-identical after open, edit and save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
	print("EXAMPLES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
