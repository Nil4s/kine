## godot --path . -s tests/recent_test.gd     (ROADMAP 59; needs a window)
## RECENT + RESTORE. File > Recent: the scenes opened are kept newest first, no duplicates, at most 10, in the test's own
## settings file (never poser.cfg); a deleted scene shows "(missing)" greyed in the scene list and the palette.
## File > Restore...: the autosaves rotate, 6 writes keep 5 (the oldest dropped); a restore opens a NEW scene in
## scenes/_wip whose cards equal that autosave's, and a second restore makes another file (never over one).
## Temp paths only: the test's own settings and autosave files (per process), two zz_ scenes in scenes/_wip, removed.
extends SceneTree

var fails := 0
var m: Node
const GONE := "res://scenes/_wip/zz_recent_gone.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func drop(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(gp(p))


## the palette's File > Recent rows (their names)
func recent_cmds() -> Array:
	var out := []
	for c in m._commands():
		if String(c["name"]).begins_with("File > Recent: "):
			out.append(c["name"])
	return out


func row_of(path: String) -> int:
	var o: OptionButton = m.ui_scenes
	for i in o.item_count:
		if String(o.get_item_metadata(i)) == path:
			return i
	return -1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute(gp("res://scenes/_wip"))   # a fresh worktree may not have the folder yet
	var real_cfg := gp("user://poser.cfg")
	var real_cfg_was := FileAccess.get_modified_time(real_cfg) if FileAccess.file_exists(real_cfg) else -1
	var real_as := gp("user://autosave.json")
	var real_as_was := FileAccess.get_modified_time(real_as) if FileAccess.file_exists(real_as) else -1
	ok(m.settings != "user://poser.cfg" and m.autosave != "user://autosave.json",
		"the test's own settings (%s) and autosave (%s), not the real ones" % [m.settings, m.autosave])
	# a clean start: no recent list, no autosaves of this process
	drop(m.settings)
	for n in range(1, 8):
		drop(m._ring_path(n))
	drop(m.autosave)
	drop(GONE)

	# 1-2 three scenes opened: newest first
	m._load_scene("res://scenes/combo3.json")
	m._load_scene("res://scenes/thrust.json")
	m._load_scene("res://scenes/bo_spin.json")
	var want := ["res://scenes/bo_spin.json", "res://scenes/thrust.json", "res://scenes/combo3.json"]
	ok(m._recent_list() == want, "1 three scenes opened -> Recent newest first: %s" % str(m._recent_list()))
	m._load_scene("res://scenes/thrust.json")
	want = ["res://scenes/thrust.json", "res://scenes/bo_spin.json", "res://scenes/combo3.json"]
	ok(m._recent_list() == want, "2 thrust opened again -> moved to the front, not listed twice: %s" % str(m._recent_list()))
	await idle()
	var o: OptionButton = m.ui_scenes
	ok(o.get_item_metadata(0) == "res://scenes/thrust.json" and o.get_item_text(0).ends_with("(recent)"),
		"  the scene list starts with the recent rows: '%s'" % o.get_item_text(0))
	ok(o.selected >= 0 and String(o.get_item_metadata(o.selected)) == "res://scenes/thrust.json" and o.selected > 2,
		"  the open scene is selected on its own row in the list (row %d)" % o.selected)

	# 3 max ten: twelve more scenes opened
	for k in 12:
		m._recent_note("res://scenes/zz_recent_%02d.json" % k)
	var r: Array = m._recent_list()
	var seen := {}
	for p in r:
		seen[p] = true
	ok(r.size() == 12 and seen.size() == 12 and r[0] == "res://scenes/zz_recent_11.json" and r[11] == "res://scenes/zz_recent_00.json",
		"3 twelve more noted -> twelve kept, newest first, no duplicate (first %s, last %s)" % [r[0], r[9]])
	ok(recent_cmds().size() == 12, "  the palette's File > Recent group has the same ten (%d)" % recent_cmds().size())

	# 4 a deleted scene: greyed "(missing)" in the list and the palette
	m._load_scene("res://scenes/combo3.json")
	DirAccess.copy_absolute(gp("res://scenes/combo3.json"), gp(GONE))
	m._load_scene(GONE)
	await idle()
	drop(GONE)
	m._recent_changed()
	await idle()
	var i := row_of(GONE)
	ok(i >= 0 and String(m.ui_scenes.get_item_text(i)).ends_with("(missing)") and m.ui_scenes.is_item_disabled(i),
		"4 a deleted scene -> its row says (missing) and is greyed: '%s'" % (m.ui_scenes.get_item_text(i) if i >= 0 else "no row"))
	ok("File > Recent: zz recent gone  (missing)" in recent_cmds(), "  the palette row says (missing) too")
	m._open_recent(GONE)
	ok(String(m.ui_status.text).contains("not on disk any more"), "  picking it says what happened: '%s'" % m.ui_status.text)

	# 5 six autosaves: five kept, the oldest dropped
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var base: float = m.S.cards[2]["hold"]
	var holds := []
	var wrote_all := true
	for k in 6:
		m.S.cards[2]["hold"] = base + 0.1 * (k + 1)
		holds.append(float(m.S.cards[2]["hold"]))
		wrote_all = wrote_all and m.autosave_now()
	ok(wrote_all, "5 six edits, each autosaved")
	var rows: Array = m._ring_list()
	ok(rows.size() == 5, "  five autosaves kept (%d)" % rows.size())
	var got := []
	for row in rows:
		got.append(float(row["a"]["scene"]["cards"][2]["hold"]))
	var first_ok := absf(float(got[0]) - holds[5]) < 1e-3 and absf(float(got[4]) - holds[1]) < 1e-3
	var oldest_gone := true
	for g in got:
		oldest_gone = oldest_gone and absf(float(g) - holds[0]) > 1e-3
	ok(first_ok and oldest_gone and not FileAccess.file_exists(m._ring_path(6)),
		"  newest first: holds %s; the first write (%.2f) is gone" % [str(got), holds[0]])
	ok(FileAccess.get_modified_time(real_as) == real_as_was if real_as_was != -1 else not FileAccess.file_exists(real_as),
		"  the real user://autosave.json untouched")

	# 6 Restore...: the list, the picked row's words and picture
	m._restore_open()
	await idle()
	ok(m.ui_restore != null and m.ui_restore.visible and m.ui_restore_list.item_count == 5,
		"6 Restore... opens the list of 5 autosaves (%d)" % (m.ui_restore_list.item_count if m.ui_restore != null else -1))
	m._restore_pick(2)
	ok(m.ui_restore_info.text.contains("%d cards" % rows[2]["cards"]) and m.ui_restore_info.text.contains("scenes/_wip"),
		"  the picked one says its time, scene, cards: '%s'" % m.ui_restore_info.text.split("\n")[1])
	if m.thumbs != null:
		await m.thumbs.settle()
		ok(m.ui_restore_pic.texture != null, "  its picture is drawn")

	# 7 restore: a NEW scene in scenes/_wip, equal to the autosave, clean
	m._restore_copy(rows[2])
	await idle()
	var p1: String = m.scene_path
	ok(p1.begins_with("res://scenes/_wip/") and FileAccess.file_exists(p1), "7 restored as a NEW scene in scenes/_wip: %s" % p1.get_file())
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(p1))
	var same := disk is Dictionary and JSON.stringify(disk["cards"]) == JSON.stringify(rows[2]["a"]["scene"]["cards"])
	ok(same and absf(float(m.S.cards[2]["hold"]) - holds[3]) < 1e-3,
		"  its cards equal that autosave's (card 3 holds %.2f, the 3rd newest write)" % float(m.S.cards[2]["hold"]))
	ok(not m._unsaved(), "  it opens clean: nothing unsaved in the copy")

	# 8 never overwrites: a second restore is a second file
	var before := FileAccess.get_file_as_string(p1)
	m._restore_copy(rows[2])
	await idle()
	var p2: String = m.scene_path
	ok(p2 != p1 and FileAccess.file_exists(p2) and FileAccess.get_file_as_string(p1) == before,
		"8 a second restore: another file (%s), the first untouched" % p2.get_file())

	# clean up: this process's files only
	drop(p1)
	drop(p2)
	for n in range(1, 8):
		drop(m._ring_path(n))
	drop(m.autosave)
	drop(m.settings)
	ok(FileAccess.get_modified_time(real_cfg) == real_cfg_was if real_cfg_was != -1 else not FileAccess.file_exists(real_cfg),
		"9 the real poser.cfg untouched")
	print("RECENT: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
