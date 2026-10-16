## godot --path . -s tests/ui_scale_test.gd     (GATES R5; needs a window, 1600 x 900)
## UI SIZE: at every size the window has room for (90 / 100 / 125 % on 1600 x 900) no button, label or list leaves the
## window (every visible control outside a scroll area is inside the visible rect: the layout check); 150 % is refused
## on this window with the size it needs, and greyed in the menu; the choice is saved in the settings; at 100 % the
## play row keeps all its buttons (the hiding only happens when a row would not fit).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func off_screen() -> Array:
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var out := []
	for c in m.ui_root.find_children("*", "Control", true, false):
		var cc := c as Control
		if not cc.is_visible_in_tree() or _in_scroll(cc) or cc is ScrollContainer:
			continue
		var r := cc.get_global_rect()
		if r.size.x > 0 and (r.end.x > vr.end.x + 1 or r.end.y > vr.end.y + 1 or r.position.x < -1):
			out.append("%s '%s'" % [cc.get_class(), cc.get("text") if cc.get("text") != null else cc.name])
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	ok(m.get_window().size == Vector2i(1600, 900), "the window is 1600 x 900 (%s)" % m.get_window().size)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	for sc in [90, 100, 125]:
		m._set_scale(sc)
		for k in 3:
			await process_frame
		var off := off_screen()
		var shown: int = m.ui_play_extra.filter(func(b): return b.visible).size()
		ok(m.ui_scale == sc and is_equal_approx(m.get_window().content_scale_factor, sc / 100.0) and off.is_empty(), "%d %%: the UI is %s, nothing off the window %s (play row keeps %d of 3 extras)" % [sc, m.get_viewport().get_visible_rect().size, off, shown])
		if sc <= 100:
			ok(shown == 3, "  at %d %% the play row keeps Check, Polish and Fix" % sc)
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(cf.get_value("look", "scale", 0) == 125, "the size is saved in the settings (%s)" % cf.get_value("look", "scale", 0))
	m._set_scale(150)
	await process_frame
	ok(m.ui_scale == 125 and String(m.ui_status.text).contains("needs a window of at least 1920 x 1080"), "150 %% on 1600 x 900: refused, '%s'" % m.ui_status.text)
	var us: MenuButton = null
	for b in m.ui_root.find_children("*", "MenuButton", true, false):
		if b.text == "UI size":
			us = b
	us.about_to_popup.emit()
	var pm := us.get_popup()
	ok(pm.is_item_disabled(3) and pm.get_item_text(3).contains("bigger window") and not pm.is_item_disabled(2) and pm.is_item_checked(2), "the menu: 150 greyed ('%s'), 125 on and ticked" % pm.get_item_text(3))
	m._set_scale(100)
	await process_frame
	ok(off_screen().is_empty() and m.ui_play_extra.all(func(b): return b.visible), "back to 100 %: everything back, the play row whole")
	print("UI SCALE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
