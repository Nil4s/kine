## godot --path . -s tests/small_window_test.gd     (GATES BB1, UPGRADES #4; a real window, resized)
## SMALL WINDOWS: the window at 1280 x 720 and 1024 x 768, at 100 % and every larger UI size that fits there; each
## ribbon tab opened in turn by a real click: no visible control outside a scroll area leaves the window, the tab's
## tools do not overlap the always-there buttons on the right (Undo, Redo, Search, Help), and every tool the tab has is
## shown on screen or listed in the tab's More menu. 1024 x 768 is below the smallest the poser is made for: the
## window refuses it (min_size 1280 x 720) and the layout is checked at what the window became. A screenshot of each tab per size goes to %TEMP%/poser_shots (outside the project).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


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
		if r.size.x > 0 and (r.end.x > vr.end.x + 1 or r.end.y > vr.end.y + 1 or r.position.x < -1 or r.position.y < -1):
			out.append("%s '%s'" % [cc.get_class(), String(cc.get("text")).left(20) if cc.get("text") != null else String(cc.name)])
	return out


func click(n: Control) -> void:
	var p := n.get_global_rect().get_center()
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
	await idle(2)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var shots := OS.get_environment("TEMP").replace("\\", "/") + "/poser_shots"
	DirAccess.make_dir_recursive_absolute(shots)
	for size in [Vector2i(1280, 720), Vector2i(1024, 768)]:
		m.get_window().size = size
		await idle(8)
		var got: Vector2i = m.get_window().size
		if size.x < 1280:
			ok(got.x >= 1280 and got.y >= 720 and m.get_window().min_size == Vector2i(1280, 720),
				"%d x %d asked: refused, the window stays %d x %d (the poser's smallest is 1280 x 720: min_size %s)" % [size.x, size.y, got.x, got.y, m.get_window().min_size])
		for sc in [100, 125, 150]:
			if sc > 100 and not m.scale_fits(sc):
				continue
			m._set_scale(sc)
			await idle(6)
			var bad := []
			var tools_n := 0
			var n_more := 0
			for t in m.RIBBON:
				await click(m.ui_ribbon_tabs[t])
				await idle(2)
				var off := off_screen()
				var right: Array = m.ui_top_right.filter(func(b): return (b as Control).is_visible_in_tree())
				var tools: Array = m.ui_ribbon[t].get_children().filter(func(c): return c is Button)   # round 36: not the group dividers
				# a tool not shown must be in More, by its label
				var more: Array = []
				if m.ui_more.is_visible_in_tree():
					for i in m.ui_more.get_popup().item_count:
						more.append(m.ui_more.get_popup().get_item_text(i))
				var hidden := tools.filter(func(c): return not (c as Control).is_visible_in_tree() and not m.label_of(c) in more).map(func(c): return m.label_of(c))
				n_more += more.size()
				var over := []
				for tl in tools:
					for rb in right:
						if (tl as Control).is_visible_in_tree() and (tl as Control).get_global_rect().intersects((rb as Control).get_global_rect()):
							over.append([m.label_of(tl), m.label_of(rb)])
				tools_n += tools.size()
				if not off.is_empty() or not over.is_empty() or not hidden.is_empty() or right.size() != m.ui_top_right.size():
					bad.append([t, off, over, hidden, right.size()])
				m.get_viewport().get_texture().get_image().save_png("%s/%dx%d_%d_%s.png" % [shots, size.x, size.y, sc, t.to_lower()])
			ok(bad.is_empty(), "%d x %d at %d %% (the UI %s): every tab (%d tools in all) on screen or in More (%d), none under the %d always-there buttons, nothing off the window (bad: %s)" % [size.x, size.y, sc, m.get_viewport().get_visible_rect().size, tools_n, n_more, m.ui_top_right.size(), bad])
		m._set_scale(100)
		await idle(4)
	# round 36: the tools are icons, so 1280 x 720 needs no compacting (the name and key stay in the label and the
	# tooltip); four tools a test adds to ANIMATE still overflow into More, which lists them, and picking one runs it
	m.get_window().size = Vector2i(1280, 720)
	await idle(8)
	await click(m.ui_ribbon_tabs["ANIMATE"])
	var trail: Button = m.ui_ribbon["ANIMATE"].get_children().filter(func(b): return m.label_of(b).begins_with("Trail"))[0]
	ok(trail.text == "" and m.label_of(trail) == "Trail (T)" and trail.tooltip_text.begins_with("Trail (T)") and not m.ui_more.visible,
		"11 at 1280: an icon, its name and key in the label and the tooltip ('%s'), no More" % trail.tooltip_text.left(40))
	var ran := []
	for i in 12:   # round 36: icons leave room, so it takes more than four to overflow
		var b := Button.new()
		b.text = "Extra tool %d" % (i + 1)
		b.pressed.connect(func(): ran.append(i + 1))
		m.ui_ribbon["ANIMATE"].add_child(b)
	m._fit_top()
	await idle(3)
	var items := []
	for i in m.ui_more.get_popup().item_count:
		items.append(m.ui_more.get_popup().get_item_text(i))
	var off := off_screen()
	var pick: String = items[1] if items.size() > 1 else "none"   # round 36: icons leave room, the overflow starts later
	m._more_pick(items.find(pick))
	await idle(2)
	ok(m.ui_more.is_visible_in_tree() and "Extra tool 12" in items and items.size() >= 2 and off.is_empty() and ran == [int(pick.get_slice(" ", 2))],
		"12 twelve more tools on ANIMATE: More shows (%s), nothing off the window, picking '%s' ran it (%s), off the window: %s" % [items, pick, ran, off])
	for b in m.ui_ribbon["ANIMATE"].get_children().filter(func(b): return m.label_of(b).begins_with("Extra tool")):
		b.free()
	m.get_window().size = Vector2i(1600, 900)
	await idle(8)
	m._fit_top()
	await idle(2)
	ok(m.label_of(trail) == "Trail (T)" and not m.ui_more.visible, "13 back at 1600 x 900: the label '%s', no More" % m.label_of(trail))
	print("     screenshots: " + shots)
	print("SMALL WINDOW: %d failed" % fails)
	quit(1 if fails > 0 else 0)
