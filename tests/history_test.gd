## godot --path . -s tests/history_test.gd     (GATES R2; needs a window)
## UNDO HISTORY: six named edits -> six rows with those names, newest on top; clicking a row goes to exactly that step
## (the body and cards byte-identical to the state recorded right after it); clicking the newest goes back to the end;
## names survive undo / redo; a new edit after going back drops the future (as Ctrl+Z then an edit does).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fp() -> String:
	return JSON.stringify(m.B.state()) + JSON.stringify(m.S.cards)


func rows() -> Array:
	var out := []
	for c in m.ui_hist_list.get_children():
		if c is Button and c.text != "Close":
			out.append(c.text.strip_edges())
	return out


## run a command the way a user does from the S box (so the step is named as it would be)
func run(n: String) -> void:
	m.ui_cmd.open()
	m.ui_cmd.box.text = n
	m.ui_cmd._filter()
	var i: int = m.ui_cmd.shown.map(func(c): return c["name"]).find(n)
	m.ui_cmd._run(i)
	await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._card_pick(2)
	m.undo.clear()
	m.redo.clear()
	var hb: Button = m.ui_hist_btn
	ok(hb.is_visible_in_tree() and hb.icon != null, "the History button is in the top bar, with its icon")
	hb.pressed.emit()
	await process_frame
	ok(m.ui_hist.visible and rows().is_empty(), "History opens: empty so far")
	var states := [fp()]
	var cmds := {}
	for c in m._commands():
		cmds[c["name"]] = c["run"]
	for n in ["Copy right side to left", "Snap the part to 45", "Mirror the whole pose", "Arms down 25 deg", "Plant the right foot on this card", "Paste pose mirrored"]:
		if n == "Paste pose mirrored":
			cmds["Copy pose"].call()
		if n == "Snap the part to 45":
			m.sel = "upperarm_r"
		await run(n)
		states.append(fp())
	var r := rows()
	print("     rows: %s" % [r])
	ok(r.size() == 6 and m.undo.size() == 6, "6 edits -> 6 rows")
	ok(r[0].to_lower().contains("mirror") and r[0].to_lower().contains("paste") or r[0].to_lower().contains("pasted"), "  newest on top, named for what it did: '%s'" % r[0])
	ok(not r.any(func(x): return x == "change"), "  every row has a real name (none fell back to 'change')")
	# click row 4 from the top = the state after edit 3
	var btns: Array = m.ui_hist_list.get_children().filter(func(c): return c is Button and c.text != "Close")
	btns[3].pressed.emit()
	await process_frame
	ok(fp() == states[2] and m.undo.size() == 2 and m.redo.size() == 4, "click row 4: exactly the state after edit 2 of 6 (byte-identical), 4 steps ahead to redo")
	var r2 := rows()
	ok(r2.size() == 6 and r2.slice(0, 4) == r.slice(0, 4), "  the 4 undone steps stay listed above 'now', same names")
	# click the newest (top, a future row) -> back to the end
	m.ui_hist_list.get_children().filter(func(c): return c is Button and c.text != "Close")[0].pressed.emit()
	await process_frame
	ok(fp() == states[6] and m.undo.size() == 6 and m.redo.is_empty(), "click the newest: back to the end, byte-identical")
	ok(rows() == r, "  the names came back unchanged through undo and redo")
	# go back 2 and make a new edit: the future goes
	m._history_go(4)
	await run("Reset body")
	ok(m.redo.is_empty() and rows().size() == 5, "back to step 4, then a new edit: the 2 undone steps are gone, 5 rows")
	ok(cmds.has("Undo history"), "'Undo history' is in the command search")
	print("HISTORY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
