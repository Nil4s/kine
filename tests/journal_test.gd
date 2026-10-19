## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/journal_test.gd   (ROADMAP 2, CRASH-PROOF)
## THE JOURNAL: 30 edits on a two-fighter scene are journaled, one entry each; a window that goes without a clean quit
## leaves them; the next start offers them in the status line (the time, the edit count, the command); File: restore
## unsaved work gives the 30th state exactly; a save trims the journal; a clean quit offers nothing; an append costs at
## most 2 ms. The journal folder is user://zz_journal_test (POSER_JOURNAL): never user://journal, never
## user://autosave.json, never poser.cfg. scenes/ is only read.
extends SceneTree

const DIR := "user://zz_journal_test"
var fails := 0


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


## the window goes. clean = false is the simulated kill: no clean-quit flag is written
func close(m: Node, clean := true) -> void:
	m.dummy_settle()
	m.quit_clean = clean
	root.remove_child(m)
	m.free()
	await idle()


func files(ext := ".jsonl") -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		return out
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(ext):
			out.append(f)
	return out


func wipe() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))


## a state as the journal stores it: JSON round trip, so int and float numbers compare the same
func norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _init() -> void:
	var real_journal := ProjectSettings.globalize_path("user://journal")
	var real_journal_was := DirAccess.dir_exists_absolute(real_journal)
	var real_auto := ProjectSettings.globalize_path("user://autosave.json")
	var real_auto_was := FileAccess.get_modified_time("user://autosave.json") if FileAccess.file_exists("user://autosave.json") else -1
	wipe()
	OS.set_environment("POSER_JOURNAL", DIR)

	# the format alone: 120 entries (a whole scene every 50, diffs between, keys added and dropped)
	var j := Journal.new()
	j.open(DIR, "res://scenes/zz_synthetic.json")
	var st := {"a": 0, "b": [0], "c": "x"}
	var last := {}
	for k in 120:
		st = st.duplicate(true)
		st["a"] = k
		if k % 7 == 0:
			st.erase("b")
		else:
			st["b"] = [k]
		if k % 11 == 0:
			st["d%d" % (k % 3)] = k
		j.append(st)
		last = st.duplicate(true)
	var rj := Journal.restore(j.file())
	ok(not rj.is_empty() and norm(rj["state"]) == norm(last) and int(rj["n"]) == 120,
		"1 120 entries (a whole scene every %d, diffs between) read back to the last state" % Journal.FULL_EVERY)
	j.trim()
	ok(files().is_empty(), "2 a trimmed journal is gone")

	# the app, a two-fighter scene
	var m := await boot()
	ok(m.journal_on and m.journal_dir == DIR, "3 the journal runs in its own folder (%s)" % m.journal_dir)
	ok(m.journal_offer.is_empty(), "4 an empty folder offers nothing")
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._actor_add()   # the second fighter: an edit, journaled too
	await idle()
	m.journal.trim()   # the 30 edits below are the journal's whole content
	ok(files().is_empty(), "5 the journal starts empty (%d cards, %d fighters)" % [m.S.cards.size(), m.S.actors.size() + 1])

	m.journal.total_us = 0
	m.journal.appends = 0
	m.journal_capture_us = 0
	var n: int = m.S.cards.size()
	var worst := 0
	var steady_us := 0
	for k in 30:
		var i: int = k % n
		m._do(func(): m.S.cards[i]["hold"] = float(m.S.cards[i]["hold"]) + 0.01 * (k + 1))
		if k == 0:
			print("first entry (a whole state): %.3f ms" % [float(m.journal.last_us) / 1000.0])
		else:
			steady_us += m.journal.last_us
		worst = maxi(worst, m.journal.last_us)
	var state30: Dictionary = m._scene_dict(false)
	var lines := FileAccess.get_file_as_string(m.journal.file()).count("\n") if FileAccess.file_exists(m.journal.file()) else -1
	ok(m.journal.appends == 30 and lines == 30 and files().size() == 1,
		"6 30 edits: 30 journal entries (%d appends, %d lines, %d file)" % [m.journal.appends, lines, files().size()])
	var per_append: float = float(m.journal.total_us) / 30.0 / 1000.0
	var per_capture: float = float(m.journal_capture_us) / 30.0 / 1000.0
	var per_edit := per_append + per_capture
	print("time per edit (two fighters, %d cards): append %.3f ms avg, %.3f ms worst; scene capture %.3f ms avg; total %.3f ms per edit" % [
		n, per_append, float(worst) / 1000.0, per_capture, per_edit])
	print("steady edit (a diff, no whole state): append %.3f ms avg over 29" % [float(steady_us) / 29.0 / 1000.0])
	ok(per_edit <= 2.0, "7 an edit costs at most 2 ms in the journal (%.3f ms)" % per_edit)

	await close(m, false)   # the window goes without a clean quit: the kill
	var sess: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("session.json")))
	ok(files().size() == 1 and sess is Dictionary and sess.get("clean") == false,
		"8 the kill leaves the journal and no clean-quit flag")

	m = await boot()
	await idle(3)
	var txt: String = m.ui_status.text if m.ui_status != null else ""
	ok(not m.journal_offer.is_empty() and int(m.journal_offer["n"]) == 30,
		"9 the next start offers the 30 edits (offer n = %s)" % str(m.journal_offer.get("n", "none")))
	ok("Restore the work from" in txt and "30 edits after the last save" in txt and "File: restore unsaved work" in txt,
		"10 the status line names it: '%s'" % txt)
	m._journal_restore()
	await idle()
	var got: Dictionary = m._scene_dict(false)
	ok(norm(got) == norm(state30), "11 File: restore unsaved work gives the 30th state exactly (%d chars)" % norm(state30).length())
	ok(m.scene_path == "res://scenes/combo3.json" and m._unsaved() and m.journal_offer.is_empty(),
		"12 on combo3's path, still unsaved, offer taken")
	var rj2 := Journal.restore(m.journal.file())
	ok(files().size() == 1 and norm(rj2.get("state", {})) == norm(state30),
		"13 the restored state is the journal's first entry: a second crash is covered too")

	m._journal_saved()   # what a save does to the journal (Save scene itself writes scenes/, which a test never does)
	ok(files().is_empty(), "14 a save trims the journal")

	m._do(func(): m.S.cards[0]["hold"] = float(m.S.cards[0]["hold"]) + 0.5)   # one edit, unsaved, the window closes cleanly
	await close(m, true)
	ok(files().size() == 1, "15 a clean quit with unsaved work keeps the journal (the autosave dialog offers it)")
	m = await boot()
	await idle(3)
	ok(m.journal_offer.is_empty(), "16 after a clean quit nothing is offered by the journal")
	await close(m, true)

	wipe()
	var real_journal_now := DirAccess.dir_exists_absolute(real_journal)
	var real_auto_now := FileAccess.get_modified_time("user://autosave.json") if FileAccess.file_exists("user://autosave.json") else -1
	ok(real_journal_now == real_journal_was and real_auto_now == real_auto_was,
		"17 user://journal and user://autosave.json untouched by the test")
	print("JOURNAL: %d failed" % fails)
	quit(1 if fails > 0 else 0)
