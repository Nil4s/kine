## godot --path . -s tests/fix_window_test.gd     (GATES K1, K7; needs a window: the real poser UI is built)
## Press the real Fix buttons on combo3: findings drop, the card count never changes, the file is never written;
## Ctrl+Z (undo) brings the cards back EXACTLY, redo re-applies; "+ tween" (adds a card) is undone too.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the Fix button under the finding row for rule r (rows: finding button, then its Fix button or a "no fix" label)
func fix_button(m: Node, r: String) -> Button:
	var cur := ""
	for c in m.ui_find_list.get_children():
		if c is Button and c.text.contains(" s  card "):
			cur = c.text
		elif c is Button and c.text.begins_with("Fix:") and cur.contains("-  " + r):
			return c
	return null


func cards_json(m: Node) -> String:
	return JSON.stringify(m.S.cards)


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var src := "res://scenes/combo3.json"
	var file0 := FileAccess.get_file_as_string(src)
	m._load_scene(src)
	m._rebuild_cards()
	var c0 := cards_json(m)
	var n0: int = m.S.cards.size()
	m._check()
	await process_frame
	var f0: int = m.findings.size()
	var fails0: int = m.findings.filter(func(x): return x["sev"] == "FAIL").size()
	var nofix: int = m.ui_find_list.get_children().filter(func(c): return c is Label and c.text.contains("no automatic fix")).size()
	print("     combo3: %d findings (%d must fix); rows with no automatic fix: %d" % [f0, fails0, nofix])

	var steps := 0
	var seen := {}
	for r in ["HEAD QUIET", "TIP SPEED", "TIP SPEED", "HITCH"]:
		var b := fix_button(m, r)
		if b == null:
			print("     no Fix button left for %s" % r)
			continue
		var before := cards_json(m)
		var label: String = b.text
		b.pressed.emit()   # _fix is async ("fixing..." shows first) and rebuilds the panel: b is freed after
		while m._fixing:
			await process_frame
		var changed := cards_json(m) != before
		print("     panel now: %s" % str(m.findings.map(func(x): return "%s c%d %.2f" % [x["rule"], x["card"] + 1, x["t"]])))
		ok(m.S.cards.size() == n0, "pressed '%s' (%s): %s; cards still %d" % [label, r, m.ui_status.text, m.S.cards.size()])
		if changed:
			steps += 1
			var what: String = r + " on" + m.ui_status.text.get_slice(":", 1).get_slice("'", 0)
			ok(not seen.has(what), "  no problem fixed twice (%s): a stale row would re-fix one" % what.strip_edges())
			seen[what] = true
	var direct := Rulebook.check(m.S, m.ov.GB)
	ok(var_to_str(direct) == var_to_str(m.findings), "the panel's list == a fresh check of the scene as made (dummy on: %s, solid: %s)" % [m.dummy_on, m.solid])
	var f1: int = m.findings.size()
	var fails1: int = m.findings.filter(func(x): return x["sev"] == "FAIL").size()
	ok(steps >= 2 and fails1 < fails0, "after %d kept fixes: %d findings (%d must fix) -> %d (%d must fix): %s" % [steps, f0, fails0, f1, fails1, str(m.findings.map(func(x): return "%s %s %.2f" % [x["sev"], x["rule"], x["t"]]))])
	ok(FileAccess.get_file_as_string(src) == file0, "combo3.json on disk untouched by Fix (Save scene keeps a fix)")
	var fixed := cards_json(m)
	for k in steps:
		m._undo()
	await process_frame
	ok(cards_json(m) == c0, "Ctrl+Z x%d: the cards are back EXACTLY as loaded" % steps)
	ok(m.findings.size() == f0, "the open Check panel re-ran on undo: %d findings again" % m.findings.size())
	for k in steps:
		m._redo()
	ok(cards_json(m) == fixed, "redo x%d: the fixes are back exactly" % steps)

	# + tween adds a card: undo must take it away again
	for k in steps:
		m._undo()
	m._card_pick(2)
	m._tween_add()
	ok(m.S.cards.size() == n0 + 1, "+ tween added a card (%d -> %d)" % [n0, m.S.cards.size()])
	m._undo()
	ok(m.S.cards.size() == n0 and cards_json(m) == c0, "Ctrl+Z took the tween card away: %d cards, identical" % m.S.cards.size())

	# a snapshot never pastes cards into ANOTHER scene
	m._push_undo()
	m._load_scene("res://scenes/thrust.json")
	m._rebuild_cards()
	var t0 := cards_json(m)
	m._undo()
	ok(cards_json(m) == t0, "undo after opening thrust leaves thrust's cards alone")
	print("FIX WINDOW %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
