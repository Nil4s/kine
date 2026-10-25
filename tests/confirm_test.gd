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
	var policy := {"_selfcheck_save": "only with --selfcheck-save (the exported build's self-check): a NEW scene selfcheck_<unix time> + user://selfcheck.txt", "_video_cancel": "deletes only the tracker's own temp output + .progress under user://video_track/ (the clip being cancelled); never a scene", "_ring_push": "user://autosave_N.json only (the rotating autosaves, RING_N = 5; never scenes/)", "_recent_note": "the settings file (File > Recent: a preference, not work)", "_restore_copy": "a NEW scene in scenes/_wip/ (never over a file: _2, _3)", "_save_grip_now": "asked by _save_grip", "_save_pose_now": "asked by _save_pose when the name exists",
		"_save_scene_now": "asked by _save_scene when another file has the name (G07: an applied body with no file is first saved as a NEW .kbody, BodyFile.before_save, never over a file)", "_trash_now": "asked by _trash",
		"_polish": "a NEW machine copy in scenes/_wip/", "_template_build": "a NEW scene in scenes/_wip/ (never over an earlier one: _2, _3; the templates/ files are only read)", "_words_build": "a NEW machine copy in scenes/_wip/ (the move built from words)", "_ragdoll_fall": "a NEW machine copy in scenes/_wip/ (<name>_ragdoll[_N], never overwrites)", "_style_save": "a NEW machine copy in scenes/_wip/ (the style's own file; the scene it came from is untouched)", "_mirror_scene": "a NEW machine copy in scenes/_wip/", "_import_bvh": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)",
		"_import_land": "a NEW scene in scenes/_wip/ (the landing of _import_pose)", "_import_pose": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)", "_import_physics": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)", "_import_anim": "a NEW scene in scenes/_wip/ (never over an earlier import: _2, _3)", "_import_video": "the tracker's pose file in user://video_track/ (its own, replaced per video)",
		"_import_file": "a COPY of the chosen file into the library (the original never written; never overwrites: _2)",
		"autover_tick": "no file of its own: the timed snapshot goes through _autover_write (always a NEW vNNN.json under the versions root; never the scene's own file)",
		"_rehearse_land": "user://rehearse/<take>.json only (the app's own copy of the compared video take, replaced per take; never scenes/, poses/ or data/)",
		"_qr_open_camera": "removes only the scratch file <QR out dir>/_cam.json before the camera reader starts (its own temp, user:// side; never a scene, pose or data file)",
		"_qr_cam_poll": "reads, then removes only the scratch file <QR out dir>/_cam.json the camera reader wrote; the decoded text then goes through the ordinary open-from-QR path (asks as any open does)",
		"_set_api": "the settings file only (user://poser.cfg api section: on/port, a preference, not work)",
		"_retarget_toggle": "the settings file only (user://poser.cfg video section: retarget, a preference, not work)",
		"_rename_pose": "refuses an existing name; the old name is free again", "_exit_tree": "the test's own settings file",
		"_write": "the writer itself (callers above)", "_set_light": "the settings file (a preference, not work)", "_toggle_keep_balance": "the settings file (POSE > Keep balance: a preference, not work)", "_set_scale": "the settings file (a preference, not work)", "_save_settings": "the settings file", "_tour_end": "the settings file (tour done: a preference, not work)",
		"autosave_now": "user://autosave.json only (never scenes/): a copy of unsaved work, atomic", "_autosave_drop": "removes only the autosave file and its .tmp", "_fold": "the settings file (the layout: a preference, not work)",
		"_page_set": "the settings file (the page shown: a preference, not work)", "_set_hints": "the settings file (a preference, not work)", "_taught": "the settings file (look/taught: the first start is over; a preference, not work)",
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
		"_share_viewer": "user://share/<scene>/ only (the .glb, index.html, <scene>_one_file.html; replaced per run, its temp .glb in user://share/_tmp removed; never a scene, pose or data file)",
		"_export_obj": "user://exports/<scene>.obj + .mtl (ObjIO.export; the app's own export folder, never a scene, pose or data file)",
		"_export_bvh": "exports/<scene>.bvh (the export folder; never a scene, pose or data file)",
		"_export_usd": "exports/<scene>.usda (the export folder; never a scene, pose or data file)",
		"_render_shots": "exports/shots/<scene>_<stamp>/ frames and <scene>.mp4 (the export folder, a new folder per run; never a scene, pose or data file)",
		"_export_judge_render": "user://breakdowns/<scene>_<stamp>.avi (+ .mp4 from ffmpeg) only: a NEW file per run, named by the clock; never scenes/, poses/ or data/",
		"_export_turntable": "user://turntables/<scene>_<stamp>.avi (+ .mp4 from ffmpeg) only: a NEW file per run, named by the clock; never scenes/, poses/ or data/",
		"_export_review": "exports/review/<scene>_<date>[_N].html (the export folder, never over an earlier page: _2, _3; never a scene, pose or data file) and its own temp frames in user://review_frames, removed after",
		"_onion_save": "the settings file only (user://poser.cfg onion section: a preference, not work)",
		"_save_theme": "the settings file only (user://poser.cfg look section: a preference, not work)",
		"_template_build_now": "a NEW scene in scenes/_wip/ (Templates.new_path never over an earlier one: _2, _3; the templates/ files are only read)",
		"_wp_dab": "no file of its own (paints the in-memory skin weights); the remove_absolute lines the scan sees belong to the static _rm_tree below it, which deletes a test's own library folder (SS6)",
		"_multicam_start": "the tracker's pose files in user://video_track/ only (its own: each old <video>.json there is removed before that video is tracked; never scenes/)",
		"_shot_cut_drag": "no file of its own: on the drag's end it calls _journal_write (the journal only: user://journal, the crash-recovery log, never scenes/); the drag itself writes nothing",
		"_autover_write": "R20 timed snapshot: always a NEW file <versions_root>/<scene>/vNNN.json (scenes/_versions by default; never the scene's own file)",
		"_autover_prune": "removes only the OLDEST timed snapshots (version.auto) beyond the newest 30 of that scene; manual versions are never removed",
		"_autover_cfg_save": "the settings file only (user://poser.cfg versions section: a preference, not work)",
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
	# (1b) I42 FLOOR PLAN writes outside main.gd (scripts/floor_plan_ui.gd): policy = the page and the PNG, each a NEW or replaced file of its own name
	# <scene>_floor_plan.html / .png under FloorPlan.DIR = user://floor_plan (never scenes/, poses/, data/); only those two writes exist in the file
	var fpsrc := FileAccess.get_file_as_string("res://scripts/floor_plan_ui.gd")
	ok(FloorPlan.DIR.begins_with("user://") and fpsrc.count("FileAccess.WRITE") == 2 and not fpsrc.contains("res://scenes") and not fpsrc.contains("DirAccess.remove"), "the floor plan writes only its page and picture, under %s" % FloorPlan.DIR)
	# (1c) N15 PACK PROJECT (scripts/pack_zip.gd): policy = user://packs/<scene>.kinezip (Pack) and a NEW folder under user:// (Unpack); never scenes/, poses/, data/
	var pzsrc := FileAccess.get_file_as_string("res://scripts/pack_zip.gd")
	ok(PackZip.DIR.begins_with("user://") and pzsrc.contains("dest.begins_with(\"user://\")") and not pzsrc.contains("res://scenes") and not pzsrc.contains("DirAccess.remove"), "Pack writes only under %s, Unpack only into a user:// folder" % PackZip.DIR)
	# (1d) E15 MATERIAL FROM A PHOTO (scripts/photo_material.gd): policy = user://materials/<name>/{albedo,rough,normal}.png + material.tres only; never scenes/, poses/, data/
	var pmsrc := FileAccess.get_file_as_string("res://scripts/photo_material.gd")
	ok(PhotoMaterial.DIR.begins_with("user://") and pmsrc.count("FileAccess.WRITE") == 1 and not pmsrc.contains("res://scenes") and not pmsrc.contains("DirAccess.remove"), "Material from a photo writes only under %s" % PhotoMaterial.DIR)
	# (1e) D11 UV LAYOUT EXPORT (scripts/kmesh_uv_export.gd): policy = NEW files only, user://uv_layouts/<name>_uv_<size>[_N].png + .svg
	# (free_base never reuses a name: _2, _3); never scenes/, poses/, data/; nothing removed
	var uvsrc := FileAccess.get_file_as_string("res://scripts/kmesh_uv_export.gd")
	ok(KMeshUVExport.DIR.begins_with("user://") and uvsrc.count("FileAccess.WRITE") == 1 and uvsrc.count("save_png(") == 1 and uvsrc.contains("free_base(dir") and not uvsrc.contains("res://scenes") and not uvsrc.contains("DirAccess.remove"), "UV layout export writes only NEW files under %s" % KMeshUVExport.DIR)
	# (1f) G07 / G12 BODIES (scripts/body_file.gd, body_thumbs.gd, body_export.gd): policy = a NEW .kbody in BodyFile.dir (never over a
	# file: _2, _3; the same body twice is the same file), its picture in user://thumbs, the body .glb in exports/; nothing removed, never scenes/
	var bsrc := FileAccess.get_file_as_string("res://scripts/body_file.gd")
	var tsrc := FileAccess.get_file_as_string("res://scripts/body_thumbs.gd")
	var esrc := FileAccess.get_file_as_string("res://scripts/body_export.gd")
	var bnew := bsrc.contains("while FileAccess.file_exists(path):") and bsrc.count("FileAccess.WRITE") == 1
	var bnone := true
	for t in [bsrc, tsrc, esrc]:
		bnone = bnone and not t.contains("DirAccess.remove") and not t.contains("res://scenes") and not t.contains("rename_absolute")
	ok(bnew and bnone and tsrc.count("save_png") == 1 and BodyThumbs.DIR.begins_with("user://") and not tsrc.contains("FileAccess.WRITE") and not esrc.contains("FileAccess.WRITE") and BodyExport.DIR == "res://exports",
		"bodies: one NEW-file .kbody writer (never over a file), pictures only under %s, the body .glb only in exports/; nothing removed" % BodyThumbs.DIR)
	# (1h) OBJECT LIBRARY thumbnails (scripts/library_thumbs.gd): policy = a picture per object, written ONCE under user://thumbs/lib
	# (a PNG named by its shapes' sha256), never in scenes/ or exports/; the panel (object_library.gd) writes no file at all
	var lsrc := FileAccess.get_file_as_string("res://scripts/library_thumbs.gd")
	var osrc := FileAccess.get_file_as_string("res://scripts/object_library.gd")
	ok(lsrc.count("save_png") == 1 and not lsrc.contains("FileAccess.WRITE") and not lsrc.contains("DirAccess.remove") and not lsrc.contains("res://scenes") and LibraryThumbs.DIR == "user://thumbs/lib" and not osrc.contains("save_png") and not osrc.contains("FileAccess.WRITE"),
		"object library: one PNG writer (the thumbnail cache, user://thumbs/lib), nothing removed, no file written by the panel")
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
	f.store_string(FileAccess.get_file_as_string("res://tests/data/scenes/combo3_detail.json"))
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
	TestFiles.cleanup()
	quit(fails)
