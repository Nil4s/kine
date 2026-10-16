## godot --path . -s tests/scene_list_test.gd     (GATES P1; needs a window)
## (a) the scene dropdown shows the OPEN scene after every way of opening one (start-up --scene, Open, a scene saved
##     under a new name), and an open scene that is not in the list (scenes/_wip) leaves NOTHING picked, so "Delete
##     scene" cannot trash a different scene than the one on screen (it trashes the dropdown's pick).
## (b) the right panel's title names the weapon in the hand (staff, long hammer), not "METAL BAT" for all of them.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func shown() -> String:
	var o: OptionButton = m.ui_scenes
	return "" if o.selected < 0 else String(o.get_item_metadata(o.selected))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	for p in ["res://scenes/combo3.json", "res://scenes/thrust.json", "res://scenes/bo_spin.json"]:
		m._load_scene(p)
		m._rebuild_cards()
		await process_frame
		ok(shown() == p, "opened %s -> the dropdown shows '%s'" % [p.get_file(), shown().get_file()])
	m._load_scene("res://scenes/_wip/combo3_detail.json")
	await process_frame
	ok(shown() == "", "opened a _wip scene (not in the list) -> nothing picked ('%s'), so Delete cannot hit another scene" % shown().get_file())
	m._delete_scene()
	# a press only ASKS (round 11: a dialog; before, a second press), so "the files are still there" would pass with
	# the bug: the check is that Delete REFUSES (it has nothing picked), before any dialog
	ok(String(m.ui_status.text).begins_with("pick the scene to delete") and FileAccess.file_exists("res://scenes/bo_spin.json"), "  Delete scene refuses: '%s'" % m.ui_status.text)
	# the Open button: pick thrust in the list, open it
	var o: OptionButton = m.ui_scenes
	for i in o.item_count:
		if String(o.get_item_metadata(i)).ends_with("/thrust.json"):
			o.select(i)
	m._load_scene(o.get_item_metadata(o.selected))
	await process_frame
	ok(shown().ends_with("/thrust.json") and m.S.name == "thrust", "Open scene (thrust picked) -> thrust open and shown")
	# the weapon's name on the right panel
	m._load_scene("res://scenes/combo3.json")
	for k in [["metal_bat", "METAL BAT"], ["staff", "BO STAFF"], ["long_hammer", "LONG HAMMER"]]:
		m._do(m._kind.bind(k[0]))
		m.sel = "bat_handle"
		m._refresh()
		ok(String(m.ui_title.text).begins_with(k[1]), "weapon %s -> the panel title '%s'" % [k[0], m.ui_title.text])
		var noun: String = k[1].to_lower()
		var how: String = m.ui_how.text
		var row: String = "%s   %s" % [m.ui_hips[0][1][0].text, m.ui_hips[0][1][1].text]   # the row's name + value (round 25: two labels)
		var stray: bool = k[0] != "metal_bat" and (how.replace("'Lock bat to hand'", "").contains("bat") or row.contains("bat"))
		ok(not stray and (how.contains(noun) or how.begins_with("FREE")) and row.begins_with(noun), "  its words: '%s' / '%s'" % [how.left(60), row])
	print("SCENE LIST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
