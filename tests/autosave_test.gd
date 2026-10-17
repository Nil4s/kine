## godot --headless --path . -s tests/autosave_test.gd     (GATES W1, UPGRADES #68)
## AUTOSAVE + RECOVERY: an edit is autosaved (by call and by the 15 s tick), atomically; a window closed with unsaved
## work leaves it, and the next window offers it back; Recover restores the cards exactly, still unsaved; Discard
## deletes it; a save drops it and a saved scene offers nothing. The test's file is its own (POSER_AUTOSAVE): the
## real user://autosave.json is never touched.
extends SceneTree

var fails := 0
var AS := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func boot() -> Node:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	return m


func close(m: Node) -> void:   # the window goes: _exit_tree runs, as when Poser is closed
	m.dummy_settle()
	root.remove_child(m)
	m.free()
	await idle()


func held() -> Dictionary:
	if not FileAccess.file_exists(AS):
		return {}
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(AS))
	return a if a is Dictionary else {}


## card i's hold in the autosave, or NAN when there is none
func held_hold(i: int) -> float:
	var c: Array = held().get("scene", {}).get("cards", [])
	return float(c[i].get("hold", NAN)) if i < c.size() else NAN


func offered(m: Node) -> bool:
	return m.ui_recover != null and m.ui_recover.visible


func _init() -> void:
	AS = OS.get_environment("TMP").replace("\\", "/") + "/zz_autosave_w1.json"
	for q in [AS, AS + ".tmp"]:
		if FileAccess.file_exists(q):
			DirAccess.remove_absolute(q)
	OS.set_environment("POSER_AUTOSAVE", AS)
	var real := ProjectSettings.globalize_path("user://autosave.json")
	var real_was := FileAccess.get_modified_time(real) if FileAccess.file_exists(real) else -1
	var wip := ProjectSettings.globalize_path("res://scenes/_wip/zz_autosave_w1.json")

	var m := await boot()
	ok(not offered(m), "1 no autosave: nothing offered on start")
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	ok(m.autosave_now() == false and held().is_empty(), "2 combo3 just opened: nothing unsaved, nothing written")
	m.S.cards[2]["hold"] = float(m.S.cards[2]["hold"]) + 0.5
	var wrote: bool = m.autosave_now()
	ok(wrote and absf(held_hold(2) - float(m.S.cards[2]["hold"])) < 1e-3, "3 an edit (card 3 holds 0.5 s longer): autosaved, the file holds it (hold %s)" % held_hold(2))
	ok(not FileAccess.file_exists(AS + ".tmp") and held().get("path", "") == "res://scenes/combo3.json",
		"4 written through a temp file that is gone after the rename; it names its scene (%s)" % held().get("path", ""))
	ok(m.autosave_now() == false, "5 nothing new since: no second write")
	# the 15 s tick
	m.S.cards[4]["hold"] = float(m.S.cards[4]["hold"]) + 0.25
	m._as_wait = 15.0   # the tick is due: _process must write without being called
	await idle(3)
	ok(absf(held_hold(4) - float(m.S.cards[4]["hold"])) < 1e-3, "6 the 15 s tick writes the next edit by itself")
	var want: String = JSON.stringify(held().get("scene", {}).get("cards", []))
	await close(m)   # closed with unsaved work: it stays
	ok(FileAccess.file_exists(AS), "7 closing with unsaved work leaves the autosave")

	m = await boot()
	await idle(3)
	ok(offered(m) and "combo3" in m.ui_recover.dialog_text and "12 cards" in m.ui_recover.dialog_text,
		"8 the next start offers it, naming it: '%s'" % (m.ui_recover.dialog_text.replace("\n", " ") if m.ui_recover else "nothing"))
	if m.ui_recover != null:
		m.ui_recover.hide()
		m.ui_recover.confirmed.emit()
	await idle()
	var keep: Dictionary = m.B.state()
	var now: String = JSON.stringify(m.S.to_dict(m.B)["cards"])
	m.B.set_state(keep)
	ok(now == want and m.S.cards.size() == 12, "9 Recover: the cards are the autosaved ones, byte for byte (%d chars)" % now.length())
	ok(m._unsaved() and m.scene_path == "res://scenes/combo3.json" and FileAccess.file_exists(AS),
		"10 recovered work is still unsaved, on combo3's path, and the autosave stays until it is saved")
	await close(m)

	m = await boot()
	await idle(3)
	ok(offered(m), "11 not saved, so offered again")
	if m.ui_recover != null:   # QQ3: closing it (Esc, its x) is LATER, never Discard
		m.ui_recover.hide()
		m.ui_recover.canceled.emit()
	await idle()
	ok(FileAccess.file_exists(m._later_path()), "11b closed without Discard (Esc / its x): the work is kept (the Later slot)")
	await close(m)
	m = await boot()
	await idle(3)
	ok(offered(m), "11c and offered again on the next start")
	if m.ui_recover != null:
		m.ui_recover.get_cancel_button().pressed.emit()   # the Discard button, as clicked
	await idle()
	ok(not FileAccess.file_exists(AS) and not FileAccess.file_exists(m._later_path()) and m.S.cards.is_empty(), "12 Discard deletes it (and the Later slot) and opens nothing")
	# a save drops it
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.cards[2]["hold"] = float(m.S.cards[2]["hold"]) + 0.5
	m.autosave_now()
	var had := FileAccess.file_exists(AS)
	m.ui_scene_name.text = "_wip/zz_autosave_w1"
	m._save_scene()
	ok(had and FileAccess.file_exists(wip) and not FileAccess.file_exists(AS), "13 saving the scene removes its autosave")
	await close(m)
	m = await boot()
	await idle(3)
	ok(not offered(m), "14 a saved scene: nothing offered")
	await close(m)
	if FileAccess.file_exists(wip):
		DirAccess.remove_absolute(wip)
	var later := ProjectSettings.globalize_path(AS).get_basename() + "_later.json"
	if FileAccess.file_exists(later):
		DirAccess.remove_absolute(later)
	var real_now := FileAccess.get_modified_time(real) if FileAccess.file_exists(real) else -1
	ok(real_now == real_was, "15 the real user://autosave.json untouched (%s)" % ("absent" if real_now == -1 else str(real_now)))
	OS.set_environment("POSER_AUTOSAVE", "")
	print("AUTOSAVE: %d failed" % fails)
	quit(1 if fails > 0 else 0)
