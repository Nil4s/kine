## godot --path . -s tests/ribbon_test.gd     (GATES N6; needs a window)
## The ribbon replaced the old top bar: NOTHING may be lost. Every button the old bar had (its 14 labels, written here
## from the round-6 bar) is found in some tab, the tab is opened by a click, and the button is clicked through the
## window at its pixels; the ones with a visible effect are checked for it. Each tab fits the screen (the bar ran off
## once). Exactly one tab is lit. The on/off buttons follow the keys (T turns the Trail button on).
extends SceneTree

const OLD_BAR := ["Front (1)", "His right (2)", "Top (3)", "Back (4)", "His left (5)", "Undo (Ctrl+Z)", "Redo (Ctrl+Y)",
	"Collision (C)", "Reset body", "Arms 25 deg", "Big view (Tab)", "Search (S)", "? Help", "Animator tools"]

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func click(b: Control) -> void:
	var p := b.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
	await process_frame


## the top bar's button with this text, and the tab it lives in ("" = always shown)
func find(t: String) -> Array:
	for tab in m.RIBBON:
		for c in m.ui_ribbon[tab].get_children():
			if c is Button and m.label_of(c) == t:   # round 36: icons only, the name kept as the label
				return [c, tab]
	for c in m.ui_top_right:
		if c is Button and m.label_of(c) == t:
			return [c, ""]
	return [null, ""]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var w: float = m.get_viewport().get_visible_rect().size.x
	var help: Button = find("? Help")[0]
	# each tab: opened by a click, the only one lit, its row the only one shown, everything on screen
	for tab in m.RIBBON:
		await click(m.ui_ribbon_tabs[tab])
		var lit: Array = m.RIBBON.filter(func(k): return m.ui_ribbon_tabs[k].button_pressed)
		var shown: Array = m.RIBBON.filter(func(k): return m.ui_ribbon[k].visible)
		ok(lit == [tab] and shown == [tab] and help.get_global_rect().end.x <= w, "click %s: lit %s, shown %s, '? Help' ends at %.0f of %.0f" % [tab, lit, shown, help.get_global_rect().end.x, w])
	# every old button: found, its tab opened, clicked at its pixels
	var found := 0
	for t in OLD_BAR:
		var f := find(t)
		var b: Button = f[0]
		if b == null:
			ok(false, "'%s' is GONE from the bar" % t)
			continue
		if f[1] != "":
			await click(m.ui_ribbon_tabs[f[1]])
		ok(b.is_visible_in_tree() and b.get_global_rect().end.x <= w, "  '%s': in %s, on screen" % [t, f[1] if f[1] != "" else "the always-there group"])
		found += 1
	ok(found == OLD_BAR.size(), "all %d of the old bar's %d buttons are there" % [found, OLD_BAR.size()])
	# their effects, clicked
	m.yaw = 33.0
	await click(m.ui_ribbon_tabs["VIEW"])
	await click(find("His right (2)")[0])
	ok(is_equal_approx(m.yaw, -90.0), "VIEW > 'His right (2)': yaw %.0f" % m.yaw)
	await click(m.ui_ribbon_tabs["POSE"])
	var caps0: bool = m.show_caps
	await click(find("Collision (C)")[0])
	ok(m.show_caps != caps0 and find("Collision (C)")[0].button_pressed == m.show_caps, "POSE > 'Collision (C)': %s -> %s, the button shows it" % [caps0, m.show_caps])
	m.B.ang["upperarm_r"] = Vector3(40, 10, 0)
	m.B.fk()
	await click(find("Reset body")[0])
	ok((m.B.ang["upperarm_r"] as Vector3).length() < 1e-4, "POSE > 'Reset body': the arm back to 0")
	await click(find("Undo (Ctrl+Z)")[0])
	ok(is_equal_approx(m.B.ang["upperarm_r"].x, 40.0), "'Undo (Ctrl+Z)': the arm back to 40 (%.0f)" % m.B.ang["upperarm_r"].x)
	await click(find("Search (S)")[0])
	ok(m.ui_cmd.visible, "'Search (S)': the search box opens")
	m.ui_cmd.close()
	# the toggles follow the keys
	await click(m.ui_ribbon_tabs["ANIMATE"])
	var trail: Button = find("Trail (T)")[0]
	var t0: bool = trail.button_pressed
	m._press(KEY_T)
	ok(trail.button_pressed != t0 and trail.button_pressed == m.ov.trail_on, "key T: the Trail button follows (%s -> %s)" % [t0, trail.button_pressed])
	await click(trail)
	ok(trail.button_pressed == m.ov.trail_on and m.ov.trail_on == t0, "click Trail: trail %s, the button agrees" % m.ov.trail_on)
	await click(find("Speed graph (Y)")[0])
	ok(m.ov.graph_on and find("Speed graph (Y)")[0].button_pressed, "click Speed graph: on, lit")
	var pm: PopupMenu = (find("Animator tools")[0] as MenuButton).get_popup()
	ok(pm.is_item_checked(pm.get_item_index(2)), "  the Animator tools menu agrees (its Speed graph item checked)")
	print("RIBBON %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
