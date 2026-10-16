## godot --headless --path . -s tests/names_disk_test.gd     (GATES X3, UPGRADES #13)
## NAMES THAT SURVIVE THE DISK: scene and card names with spaces, accents, other scripts, emoji and the characters a
## file system refuses save, re-open and show the same name, byte for byte; the FILE's name is safe and inside
## scenes/_wip (the only place this test writes); the escapes (../, .., a device name) are checked on safe_file alone,
## with no file written.
extends SceneTree

var fails := 0
var m: Node
const PRE := "_wip/zz_x3_"
const NAMES := ["my scene", "ação rápida", "日本語の型", "удар", "punch 🥊", "a/b\\c:d*e?f\"g<h>i|j", "trailing. ", "tab\there"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	var wip := ProjectSettings.globalize_path("res://scenes/_wip").replace("\\", "/")
	var written := []
	for nm in NAMES:
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		var card_name: String = nm.strip_edges() + " card"
		m._card_rename(0, card_name)
		m.ui_scene_name.text = PRE + nm
		m._save_scene()
		var path: String = m.scene_path
		var abs_path := ProjectSettings.globalize_path(path).replace("\\", "/")
		var fname := path.get_file()
		written.append(path)
		var inside := abs_path.get_base_dir() == wip and FileAccess.file_exists(path)
		var clean := true
		for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\t"]:
			clean = clean and not bad in fname
		m.S = Scene.new()
		m._load_scene(path)
		m._rebuild_cards()
		var shown: String = m.ui_scene_name.text
		ok(inside and clean and m.S.name == (PRE + nm).strip_edges() and shown == m.S.name and m.S.cards[0]["name"] == card_name.strip_edges(),
			"'%s': file %s (safe, in scenes/_wip); re-opened: scene '%s', box '%s', card 1 '%s'" % [nm.c_escape(), fname, m.S.name.c_escape(), shown.c_escape(), String(m.S.cards[0]["name"]).c_escape()])
	var distinct := {}
	for p in written:
		distinct[p] = true
	ok(distinct.size() == NAMES.size(), "%d names, %d different files (none overwrote another)" % [NAMES.size(), distinct.size()])
	for p in written:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var left := DirAccess.get_files_at("res://scenes/_wip")
	ok(Array(left).filter(func(f): return f.begins_with("zz_x3_")).is_empty(), "the test's files removed")

	# the escapes, on the function alone (nothing written)
	var cases := {"../escape": "", "..": "", "../../data/body_limits": "", "CON": "CON_", "com1.json": "com1.json_", "nul": "nul_",
		".hidden": "_hidden", "_wip/../x": "_wip/", "C:\\Windows\\x": "", "x".repeat(150): ""}
	var bad_out := []
	for k in cases:
		var f: String = m.safe_file(k)
		var esc: String = f.trim_prefix("_wip/")
		var safe: bool = not "/" in esc and not "\\" in esc and not ":" in esc and not esc.begins_with(".") and f.length() <= 105
		if cases[k] != "" and not (f == cases[k] or f.begins_with(cases[k])):
			safe = false
		var res := ProjectSettings.globalize_path("res://scenes/%s.json" % (f if f != "" else "scene_x")).simplify_path()
		if not res.begins_with(ProjectSettings.globalize_path("res://scenes").simplify_path()):
			safe = false
		if not safe:
			bad_out.append([k.left(20), f])
	ok(bad_out.is_empty(), "%d escapes made safe: nothing leaves scenes/, no device names, no leading dot, at most 100 characters (bad: %s)" % [cases.size(), bad_out])
	print("     e.g. '../escape' -> '%s', '..' -> '%s' (empty = a dated name), 'CON' -> '%s', '_wip/../x' -> '%s'" % [m.safe_file("../escape"), m.safe_file(".."), m.safe_file("CON"), m.safe_file("_wip/../x")])
	print("NAMES DISK: %d failed" % fails)
	quit(1 if fails > 0 else 0)
