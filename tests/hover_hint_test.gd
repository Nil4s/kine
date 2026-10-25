## godot --path . -s tests/hover_hint_test.gd     (GATES R4; needs a window)
## HOVER HINTS: every ribbon / top-bar button (the iconised ones) has a one-line hint; hovering one puts it in the
## status bar; leaving gives the normal bar back. Checked on every such button, each ribbon tab opened in turn.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var btns: Array = m.ui_root.find_children("*", "BaseButton", true, false).filter(func(b): return b is Button and m.ICON_OF.has(m.label_of(b)))
	var none: Array = btns.filter(func(b): return b.tooltip_text.strip_edges().length() < 8).map(func(b): return m.label_of(b))
	ok(btns.size() >= m.ICON_OF.size() and none.is_empty(), "%d ribbon / top-bar buttons, every one with a hint (none: %s)" % [btns.size(), none])
	var plain: String = m.bar_text()
	await process_frame
	var bad := []
	for b in btns:
		b.mouse_entered.emit()
		await process_frame
		var shown: String = m.ui_bar.text
		# round 36: an icon button's tooltip LEADS with its label (`_icon_only`); the bar says the label once, then the hint
		var hint: String = b.tooltip_text.trim_prefix(m.label_of(b) + "
").trim_prefix(m.label_of(b))
		if not (shown.begins_with(m.label_of(b)) and shown.contains(hint) and hint.length() >= 8):
			bad.append(m.label_of(b))
		b.mouse_exited.emit()
		await process_frame
		if m.ui_bar.text != plain:
			bad.append(m.label_of(b) + " (stuck)")
	ok(bad.is_empty(), "hover each: the bar shows '<button>:  <hint>'; leave: the normal bar is back (bad: %s)" % [bad])
	btns[0].mouse_entered.emit()
	await process_frame
	print("     e.g. '%s'" % m.ui_bar.text)
	btns[0].mouse_exited.emit()
	print("HOVER HINT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
