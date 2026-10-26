## godot --path . -s tests/monkey_test.gd     (GATES J1-J3; needs a window: the real poser UI is built)
## Check lists the rulebook's findings as buttons; pressing one moves the playhead and the picked card there. Polish
## writes scenes/_wip/<name>_polished.json, opens it, and leaves Nick's file byte-identical.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var src := "res://scenes/combo3.json"
	var before := FileAccess.get_file_as_string(src)
	m._load_scene(src)
	m._rebuild_cards()
	m._check()
	await process_frame
	var rows: Array = m.ui_find_list.get_children().filter(func(c): return c is Button and c.text.contains(" s  card "))
	ok(m.ui_find.visible and rows.size() == m.findings.size() and rows.size() > 0, "Check: panel open, %d finding buttons for %d findings" % [rows.size(), m.findings.size()])
	await process_frame
	ok(m.ui_find.size.y > 200.0, "the panel has real height on screen: %.0f px (it collapsed to ~20 once)" % m.ui_find.size.y)
	var f: Dictionary = m.findings[-1]
	rows[-1].pressed.emit()
	ok(absf(m.playhead - f["t"]) < 1e-4 and m.sel_card == f["card"], "pressing '%s' jumps to %.2f s, card %d (playhead %.2f, card %d)" % [f["rule"], f["t"], f["card"] + 1, m.playhead, m.sel_card + 1])
	var n0: int = m.S.cards.size()
	var fails0: int = m.findings.filter(func(x): return x["sev"] == "FAIL").size()
	var out := "res://scenes/_wip/combo3_polished.json"
	# a leftover from an earlier run would make "Polish wrote it" pass with nothing written: keep its bytes, put it back
	var had := FileAccess.file_exists(out)
	var old := FileAccess.get_file_as_string(out) if had else ""
	var t0 := FileAccess.get_modified_time(out) if had else 0
	if had:
		await create_timer(1.1).timeout   # mtime is in whole seconds
	await m._polish()
	ok(FileAccess.file_exists(out) and FileAccess.get_modified_time(out) > t0 and m.S.name == "combo3_polished", "Polish wrote %s (fresh: modified time moved) and opened it (scene '%s')" % [out.get_file(), m.S.name])
	ok(m.S.cards.size() > n0 and m.S.spline, "Polish: %d cards -> %d, spline %s" % [n0, m.S.cards.size(), m.S.spline])
	ok(FileAccess.get_file_as_string(src) == before, "Nick's combo3.json byte-identical after Polish")
	ok(m.ui_spline.button_pressed, "the Smooth box shows the polished scene's setting")
	m._check()
	var after: Array = m.findings
	print("     check before polish: %d findings (%d FAIL); after: %d (%d FAIL): %s" % [rows.size(), fails0, after.size(), after.filter(func(x): return x["sev"] == "FAIL").size(), str(after.map(func(x): return "%s %s %.2f" % [x["sev"], x["rule"], x["t"]]))])
	# leave _wip as found: the test's file goes (or the old one comes back)
	if had:
		var fw := FileAccess.open(out, FileAccess.WRITE)
		fw.store_string(old)
		fw.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
	print("MONKEY %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
