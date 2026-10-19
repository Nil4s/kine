## godot --path . -s tests/confirm_test.gd     (GATES R3; needs a window)
## CONFIRM ONLY WHAT CAN'T BE UNDONE. (1) The audit: every function in main.gd that writes, renames or removes a file is
## listed with its policy, so a new file-writer fails this test until it is given one. (2) Every editing command in
## the registry runs with no dialog. (3) Delete on a scratch scene in scenes/_wip/ asks, naming it; Cancel keeps the
## file; OK moves it to trash/. (4) Save scene onto ANOTHER file asks; onto the open scene's own file it does not.
extends SceneTree

var fails := 0
var m: Node
const SCRATCH := "res://scenes/_wip/zz_confirm_test.json"
const OTHER := "res://scenes/_wip/zz_confirm_other.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func asking() -> bool:
	return m.ui_confirm != null and m.ui_confirm.visible


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	# (1) the audit, from the source
	var policy := {"_save_grip_now": "asked by _save_grip", "_save_pose_now": "asked by _save_pose when the name exists",
		"_save_scene_now": "asked by _save_scene when another file has the name", "_trash_now": "asked by _trash",
		"_polish": "a NEW machine copy in scenes/_wip/", "_template_build": "a NEW scene in scenes/_wip/ (never over an earlier one: _2, _3; the templates/ files are only read)", "_style_save": "a NEW machine copy in scenes/_wip/ (the style's own file; the scene it came from is untouched)", "_mirror_scene": "a NEW machine copy in scenes/_wip/", "_import_bvh": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)",
		"_import_pose": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)", "_import_anim": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)", "_import_video": "the tracker's pose file in user://video_track/ (its own, replaced per video)",
		"_import_file": "a COPY of the chosen file into the library (the original never written; never overwrites: _2)",
		"_rename_pose": "refuses an existing name; the old name is free again", "_exit_tree": "the test's own settings file",
		"_write": "the writer itself (callers above)", "_set_light": "the settings file (a preference, not work)", "_set_scale": "the settings file (a preference, not work)", "_save_settings": "the settings file", "_tour_end": "the settings file (tour done: a preference, not work)",
		"autosave_now": "user://autosave.json only (never scenes/): a copy of unsaved work, atomic", "_autosave_drop": "removes only the autosave file and its .tmp", "_fold": "the settings file (the layout: a preference, not work)",
		"_set_hints": "the settings file (a preference, not work)", "_taught": "the settings file (look/taught: the first start is over; a preference, not work)",
		"_recover_closed": "Discard button: removes the offered autosave (or the Later slot); Esc / x: MOVES it to <autosave>_later.json (kept, offered next start)",
		"_process": "the journal only (user://journal, ROADMAP 2): flushes the edit log; never scenes/",
		"_do": "the journal only (user://journal): appends the edit just made; never scenes/",
		"_push_undo": "the journal only (user://journal): appends the step; never scenes/",
		"_journal_boot": "the journal only (user://journal): opens / trims its own log",
		"_journal_restore": "the journal only: reads the log back into a NEW unsaved scene; the log is trimmed only after the user saves",
		"_offer_drop": "removes the offered autosave (or the Later slot) when unreadable or the same as its scene file",
		"_recover": "removes the Later slot once its work is open again (the autosave holds it from there)",
		"_export_game": "exports/<scene>.json and .cs (a separate export folder; never a scene, pose or data file)",
		"_export_glb": "exports/<scene>.glb (the export folder; never a scene, pose or data file)",
		"_export_bvh": "exports/<scene>.bvh (the export folder; never a scene, pose or data file)",
		"_export_usd": "exports/<scene>.usda (the export folder; never a scene, pose or data file)",
		"_save_version": "always a NEW file scenes/_versions/<scene>/vNNN.json (the next number; never the scene's own file)"}
	var src := FileAccess.get_file_as_string("res://scripts/main.gd").split("\n")
	var fn := ""
	var writers := {}
	for line in src:
		if line.begins_with("func "):
			fn = line.substr(5, line.find("(") - 5)
		elif line.contains("_write(") or line.contains("rename_absolute") or line.contains("remove_absolute") or (line.contains("FileAccess.WRITE") ) or line.contains(".save(settings") or line.contains("cfg.save("):
			writers[fn] = true
	var unlisted := writers.keys().filter(func(k): return not policy.has(k))
	print("     file-writing functions: %s" % [writers.keys()])
	ok(writers.size() >= 6 and unlisted.is_empty(), "%d functions touch files, every one has a policy (unlisted: %s)" % [writers.size(), unlisted])
	# (2) every editing command: no dialog
	m._load_scene("res://scenes/combo3.json")
	m._card_pick(2)
	var asked := []
	for c in m._commands():
		if c["edits"]:
			c["run"].call()
			await process_frame
			if asking():
				asked.append(c["name"])
				m.ui_confirm.hide()
	ok(asked.is_empty(), "every editing command in the registry ran without a dialog (asked: %s)" % [asked])
	# (3) delete a scratch file
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string("res://scenes/_wip/combo3_detail.json"))
	f.close()
	m._trash(SCRATCH)
	await process_frame
	ok(asking() and m.ui_confirm.dialog_text.contains("zz_confirm_test") and FileAccess.file_exists(SCRATCH), "Delete: a dialog naming 'zz_confirm_test'; the file is still there")
	m.ui_confirm.get_cancel_button().pressed.emit()
	await process_frame
	ok(not asking() and FileAccess.file_exists(SCRATCH), "  Cancel: the dialog closes, the file is kept")
	m._trash(SCRATCH)
	await process_frame
	m.ui_confirm.get_ok_button().pressed.emit()
	await process_frame
	var trashed: Array = Array(DirAccess.get_files_at("res://trash")).filter(func(x): return x.begins_with("zz_confirm_test"))
	ok(not FileAccess.file_exists(SCRATCH) and trashed.size() >= 1, "  OK: moved to trash/ (%s)" % [trashed])
	for t in trashed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://trash/" + t))
	# (4) save onto another file asks; onto its own does not
	var g := FileAccess.open(OTHER, FileAccess.WRITE)
	g.store_string("{\"keep\": true}")
	g.close()
	m.ui_scene_name.text = "_wip/zz_confirm_other"
	m._save_scene()
	await process_frame
	ok(asking() and FileAccess.get_file_as_string(OTHER) == "{\"keep\": true}", "Save scene onto another scene's file: asks; the file is untouched")
	m.ui_confirm.get_cancel_button().pressed.emit()
	await process_frame
	ok(FileAccess.get_file_as_string(OTHER) == "{\"keep\": true}", "  Cancel: still untouched")
	m._load_scene(OTHER.replace("zz_confirm_other", "combo3_detail"))
	var own := "res://scenes/_wip/zz_confirm_own.json"
	m.ui_scene_name.text = "_wip/zz_confirm_own"
	m._save_scene()   # a new name: no dialog
	await process_frame
	ok(not asking() and FileAccess.file_exists(own), "Save scene to a new name: no dialog, written")
	m._load_scene(own)
	m._card_pick(1)
	m._speed(1.1)
	m.ui_scene_name.text = "_wip/zz_confirm_own"
	m._save_scene()   # its own file: that is what Save means
	await process_frame
	ok(not asking(), "Save the open scene onto its own file: no dialog")
	for p in [OTHER, own]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("CONFIRM TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
