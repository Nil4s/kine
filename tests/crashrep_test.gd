## godot --position 4000,4000 --path . -s tests/crashrep_test.gd   (windowed; shots in C:/Temp/claude/crashrep/)
## CRASH REPORT (CG8 / ROADMAP P25): the last 20 commands with their page, in a local text file. Bars (stated before measuring):
##  1. 25 commands on two pages: the report holds exactly the last 20 (Cmd 6 .. Cmd 25), each with its own page; 21 lines (a header + 20)
##  2. the report has no personal folder: no drive letter, no user name, no home path; a res:// scene path stays as it is
##  3. File > Crash report (the menu entry, asked by the user) writes it, and the status line names the file
##  4. a kill (no clean quit) leaves the list; the next start keeps its 20 commands and the status line says the last run did not close
##  5. a clean quit leaves nothing: the next start keeps no list and deletes the old one
##  6. the File entry is plain words: no key names in its row
##  7. one command's list write costs at most 2 ms (avg over 100 commands, printed)
## The folders are user://zz_crashrep_test and user://zz_crashrep_journal (POSER_CRASH / POSER_JOURNAL): never user://crash.
extends SceneTree

const DIR := "user://zz_crashrep_test"
const JDIR := "user://zz_crashrep_journal"
const SHOTS := "C:/Temp/claude/crashrep/"
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


func wipe() -> void:
	for d in [DIR, JDIR]:
		var g := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(g):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(d.path_join(f)))


func report_lines(path: String) -> PackedStringArray:
	return FileAccess.get_file_as_string(path).split("\n", false)


func reports() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("report_"):
			out.append(f)
	return out


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOTS)
	root.get_texture().get_image().save_png(SHOTS + name)


func _init() -> void:
	wipe()
	OS.set_environment("POSER_JOURNAL", JDIR)
	OS.set_environment("POSER_CRASH", DIR)
	var user_name := OS.get_environment("USERNAME")
	var home := OS.get_environment("USERPROFILE")

	# 1. the report of 25 synthetic commands, scrubbed: a personal path in the middle, a res:// scene path at the end
	var raw := []
	for k in 25:
		raw.append(CrashReport.line(1700000000.0 + k, "MODEL" if k < 9 else "SURFACE", "Cmd %d" % (k + 1)))
	raw.append(CrashReport.line(1700000100.0, "SURFACE", "Open C:\\Users\\%s\\Desktop\\poser\\scenes\\x.json" % user_name))
	raw.append(CrashReport.line(1700000101.0, "POSE", "Open res://scenes/combo3.json"))
	var p1 := CrashReport.write(DIR, raw, "SURFACE", "synthetic")
	var l1 := report_lines(p1)
	ok(l1.size() == 21 and l1[0].begins_with("Kine crash report"),
		"1 25 + 2 commands: the report is a header and 20 lines (%d lines in all)" % l1.size())
	ok(l1[1].contains("Cmd 8") and l1[1].contains("MODEL") and l1[3].contains("Cmd 10") and l1[3].contains("SURFACE") and l1[18].contains("Cmd 25"),
		"1b the first line is Cmd 8 (the cut keeps the newest 20); each line has its page: MODEL through Cmd 9, SURFACE from Cmd 10")
	var text := FileAccess.get_file_as_string(p1)
	ok(not text.contains("Users\\" + user_name) and not text.contains("Users/" + user_name) and not text.contains(user_name) and not text.contains("C:") and not text.contains(home),
		"2 no drive letter, no user name, no home path in the report")
	ok(text.contains("res://scenes/combo3.json") and text.contains("<folder>/x.json"),
		"2b the res:// scene path stays; the personal path becomes <folder>/x.json")

	# 3..5. the app: 25 palette commands (the running signal the palette sends), then File > Crash report; then a kill; then a clean quit
	var m := await boot()
	ok(m.crash_dir == DIR, "3 the app writes its list in the test folder (%s)" % m.crash_dir)
	for k in 25:
		m.cur_page = "MODEL" if k < 9 else "SURFACE"
		m.ui_cmd.running.emit("Cmd %d" % (k + 1))
	var before := reports()
	m._crash_report_now()
	await idle()
	var fresh: Array = reports().filter(func(f): return not before.has(f))
	ok(fresh.size() == 1, "3a File > Crash report writes one new report file in the test folder (%d new)" % fresh.size())
	var l2 := report_lines(ProjectSettings.globalize_path(DIR.path_join(fresh[0])) if fresh.size() == 1 else "")
	ok(l2.size() == 21 and l2[1].contains("Cmd 6") and l2[20].contains("Cmd 25") and l2[20].contains("SURFACE"),
		"3b the app's report: 20 command lines, from Cmd 6 to Cmd 25 (%d lines)" % l2.size())
	ok(m.ui_status.text.contains("crash report saved") and m.ui_status.text.contains("20 commands"),
		"3c the status line: '%s'" % m.ui_status.text.left(120))
	await shot("status_after_report.png")

	await close(m, false)   # the kill: no clean-quit flag
	ok(FileAccess.file_exists(DIR.path_join(CrashReport.RECENT)), "4a the kill leaves the recent list in the test folder")

	m = await boot()
	await idle(4)
	ok(m.crash_prev.size() == 20 and m.crash_prev[0].contains("Cmd 6") and m.crash_prev[19].contains("Cmd 25"),
		"4 the next start keeps the 20 commands of the session that was killed (%d kept)" % m.crash_prev.size())
	ok(m.ui_status.text.contains("did not close cleanly"),
		"4b the status line says so: '%s'" % m.ui_status.text.left(120))
	var before2 := reports()
	m._crash_report_now()
	await idle()
	var fresh2: Array = reports().filter(func(f): return not before2.has(f))
	var l3 := report_lines(ProjectSettings.globalize_path(DIR.path_join(fresh2[0])) if fresh2.size() == 1 else "")
	ok(l3.size() == 21 and l3[0].contains("did not close cleanly"),
		"4c the report of the killed session: 20 lines, the header says it (%d lines)" % l3.size())
	await shot("status_after_kill.png")

	await close(m, true)   # a clean quit
	m = await boot()
	await idle(4)
	ok(m.crash_prev.is_empty() and not FileAccess.file_exists(DIR.path_join(CrashReport.RECENT)) and not FileAccess.file_exists(DIR.path_join(CrashReport.OLD)),
		"5 after a clean quit the next start keeps nothing and removes the old list")
	await close(m, true)

	# 6. the File entry: plain words, no keys
	var m2 := await boot()
	var row := {}
	for c in m2.ui_cmd.commands:
		if c["name"] == "File > Crash report (last 20 commands)":
			row = c
	ok(not row.is_empty() and str(row.get("keys", "x")) == "" and not str(row.get("how", "")).contains("Ctrl"),
		"6 the File entry exists with no key names (%s)" % str(row.get("keys", "missing")))

	# 7. the cost of one list write
	var t0 := Time.get_ticks_usec()
	for k in 250:
		m2._crash_note("Timing %d" % k)
	var per_ms := float(Time.get_ticks_usec() - t0) / 250.0 / 1000.0
	print("list write per command (250 commands, the file cut back past %d lines): %.3f ms avg" % [CrashReport.TRIM, per_ms])
	ok(per_ms <= 2.0, "7 one command's list write costs at most 2 ms (%.3f ms)" % per_ms)
	var rl := CrashReport.read(DIR.path_join(CrashReport.RECENT))
	ok(rl.size() <= CrashReport.TRIM and rl.size() >= CrashReport.KEEP and rl[-1].ends_with("Timing 249") and rl[-20].ends_with("Timing 230"),
		"7b past %d lines the file is cut back: %d lines now, the newest is Timing 249" % [CrashReport.TRIM, rl.size()])
	await close(m2, true)

	wipe()
	print("CRASHREP: %d failed" % fails)
	quit(1 if fails > 0 else 0)
