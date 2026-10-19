## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/save_prompt_test.gd   (ROADMAP 50; needs a window)
## SAVE PROMPTS: the window's close, New and opening another scene ask "Save changes to <name>?" when the open scene has
## unsaved changes. Edit, then the close request: the dialog shows and the app does not quit; a second close while it
## asks does nothing more; Cancel: still running, scene intact, still unsaved; Don't save: the quit path is called and
## the autosave and journal are dropped; Save (a stand-in: the real Save writes scenes/, a test never does): saved, then
## quits; a Save that does not happen keeps the window open; no edit: the close quits at once, no dialog; New and opening
## another scene ask too; a kill (no close request) still leaves the journal, and the next start offers it.
## Paths: the journal in user://zz_saveprompt_test (POSER_JOURNAL) and the test's own autosave; never user://autosave.json,
## never poser.cfg, scenes/ only read.
extends SceneTree

const DIR := "user://zz_saveprompt_test"
var fails := 0
var quits := 0      # the quit path, counted instead of ending the test
var saves := 0      # the Save stand-in, counted
var save_works := true


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
	m.quit_fn = func(): quits += 1
	m.save_hook = func():
		if save_works:
			saves += 1
			m._clean = m._doc_key()   # what a real save does to "unsaved" (the file write itself is left out)
	return m


func asking(m: Node) -> bool:
	return m.ui_save_ask != null and m.ui_save_ask.visible


## the window goes without a clean quit: the kill (no close request, no prompt)
func kill(m: Node) -> void:
	m.dummy_settle()
	m.quit_clean = false
	root.remove_child(m)
	m.free()
	await idle()


func files() -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".jsonl"):
				out.append(f)
	return out


func wipe() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))


func edit(m: Node) -> void:
	m._do(func(): m.S.cards[0]["hold"] = float(m.S.cards[0]["hold"]) + 0.5)


func _init() -> void:
	var real_auto := ProjectSettings.globalize_path("user://autosave.json")
	var real_auto_was := FileAccess.get_modified_time("user://autosave.json") if FileAccess.file_exists("user://autosave.json") else -1
	var real_journal := ProjectSettings.globalize_path("user://journal")
	var real_journal_was := DirAccess.dir_exists_absolute(real_journal)
	wipe()
	OS.set_environment("POSER_JOURNAL", DIR)

	var m := await boot()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var cards0 := JSON.stringify(m.S.cards)
	ok(not m._unsaved() and not asking(m), "1 a scene just opened is clean (no unsaved work)")

	# no edit: the close quits at once, no dialog
	quits = 0
	m.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await idle()
	ok(quits == 1 and not asking(m), "2 no edit: the close goes straight to the quit path (quits %d, asking %s)" % [quits, asking(m)])

	# an edit, then the close request: the dialog, and no quit
	edit(m)
	await idle()
	ok(m._unsaved(), "3 an edit makes the scene unsaved")
	var cards1 := JSON.stringify(m.S.cards)
	quits = 0
	m.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await idle()
	ok(asking(m) and quits == 0 and m.ui_save_ask.dialog_text.begins_with("Save changes to ") and m.ui_save_ask.dialog_text.contains("?"),
		"4 edit then close: 'Save changes to ...?' shows and the app does not quit (quits %d, text '%s')" % [quits, m.ui_save_ask.dialog_text.get_slice("\n", 0)])
	m.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await idle()
	ok(quits == 0 and asking(m), "5 a second close while it asks does nothing more")

	# Cancel: still running, scene intact, still unsaved
	m.ui_save_ask.canceled.emit()
	await idle()
	ok(not asking(m) and quits == 0 and m.is_inside_tree() and JSON.stringify(m.S.cards) == cards1 and m._unsaved(),
		"6 Cancel: still running, scene intact (edit kept), still unsaved")

	# Don't save: the quit path is called, and the work's autosave and journal are dropped
	m.autosave_now()
	var had_auto := FileAccess.file_exists(m.autosave)
	var had_journal := files().size() == 1
	quits = 0
	m.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await idle()
	m.ui_save_ask.custom_action.emit(&"discard")
	await idle()
	ok(quits == 1 and had_auto and had_journal and not FileAccess.file_exists(m.autosave) and files().is_empty(),
		"7 Don't save: the quit path is called (quits %d), the autosave (%s) and journal (%s) are dropped" % [quits, had_auto, had_journal])

	# Save: saved, then the quit path
	edit(m)
	await idle()
	quits = 0
	saves = 0
	m.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await idle()
	m.ui_save_ask.confirmed.emit()
	await idle()
	ok(saves == 1 and quits == 1 and not m._unsaved(), "8 Save: the save ran (%d) and then the quit path (%d); nothing unsaved" % [saves, quits])

	# a Save that does not happen keeps the window open
	edit(m)
	await idle()
	save_works = false
	quits = 0
	m.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await idle()
	m.ui_save_ask.confirmed.emit()
	await idle()
	save_works = true
	ok(quits == 0 and m.is_inside_tree() and m._unsaved() and not asking(m),
		"9 a Save that does not happen (the scene still unsaved): no quit, the window stays open")

	# New: asks; Cancel keeps the scene; Don't save starts the new one
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	edit(m)
	await idle()
	var cards_new_before := JSON.stringify(m.S.cards)
	m._new_asked()
	await idle()
	ok(asking(m) and JSON.stringify(m.S.cards) == cards_new_before and m.S.cards.size() > 0,
		"10 New with unsaved changes asks first (asking %s, %d cards kept)" % [asking(m), m.S.cards.size()])
	m.ui_save_ask.canceled.emit()
	await idle()
	var cards_new: int = m.S.cards.size()
	m._new_asked()
	await idle()
	m.ui_save_ask.custom_action.emit(&"discard")
	await idle()
	ok(m.S.cards.is_empty() and m.scene_path == "" and cards_new > 0 and not m._unsaved(),
		"11 New, then Don't save: a new empty scene; nothing unsaved (before: %d cards)" % cards_new)

	# New with nothing unsaved: no dialog
	m._new_asked()
	await idle()
	ok(not asking(m), "12 New with nothing unsaved: no dialog")

	# opening another scene asks too
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	edit(m)
	await idle()
	var pick := -1
	for i in m.ui_scenes.item_count:
		if String(m.ui_scenes.get_item_metadata(i)).ends_with("walk_bat.json"):
			pick = i
	ok(pick >= 0, "13 the scene list holds walk_bat.json (item %d)" % pick)
	if pick < 0:
		fails += 1
		quit(1)
		return
	var cards_open := JSON.stringify(m.S.cards)
	m._scene_picked(pick)
	await idle()
	ok(asking(m) and JSON.stringify(m.S.cards) == cards_open and m.scene_path == "res://scenes/combo3.json",
		"14 opening another scene with unsaved changes asks first, and opens nothing (scene %s)" % m.scene_path)
	m.ui_save_ask.custom_action.emit(&"discard")
	await idle()
	ok(m.scene_path == "res://scenes/walk_bat.json" and not m._unsaved() and not asking(m),
		"15 Don't save: the other scene opens, nothing unsaved")

	# a kill still recovers through the journal: no prompt, the edit is in the journal, the next start offers it
	edit(m)
	await idle()
	ok(files().size() == 1, "16 the edit is in the journal (%d journal file)" % files().size())
	await kill(m)
	var sess: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("session.json")))
	ok(files().size() == 1 and sess is Dictionary and sess.get("clean") == false, "17 the kill leaves the journal and no clean-quit flag")
	m = await boot()
	await idle(3)
	ok(not m.journal_offer.is_empty(), "18 the next start offers the work the kill left in the journal")
	await kill(m)
	wipe()

	var real_auto_now := FileAccess.get_modified_time("user://autosave.json") if FileAccess.file_exists("user://autosave.json") else -1
	var real_journal_now := DirAccess.dir_exists_absolute(real_journal)
	ok(real_auto_now == real_auto_was and real_journal_now == real_journal_was,
		"19 user://autosave.json and user://journal untouched by the test")
	print("SAVEPROMPT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
