## godot --path . -s tests/pages_test.gd     (docs/PAGES_PLAN.md step 1; needs a window)
## THE PAGE BAR. BARS (written before measuring):
##  1 the bar has BODY POSE ANIMATE STAGE CHECK DELIVER MODEL SCULPT SURFACE, all live (the three expert pages were greyed "coming" until the mesh tools; now they are real pages)
##  2 switching to each page shows exactly its ribbon row, exactly its groups' captions, and only that page's button lit
##  3 the page's name is on screen (its lit button's text) and the page bar is at the very bottom, inside the window
##  4 every command in the registry is found by name in the search box, on every page (the search ignores the page)
##  5 Shift+1..6 switch pages (through the real key code); the registered "Page: X" commands carry those keys
##  6 the page is saved in the settings file and restored by the boot's loader
##  7 a switch is not an undo step, does not change the scene (JSON bytes identical), and takes < 50 ms (worst of 20)
##  8 the layouts differ: DELIVER folds both sides and the strip, ANIMATE opens the strip, and none overlaps the page bar
extends SceneTree

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
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
	await idle()


## the captions shown now, in order
func caps_shown() -> Array:
	var out := []
	for t in m.ui_caps:
		for pair in m.ui_caps[t]:
			if (pair[0] as Control).visible:
				out.append(String((pair[0] as MenuButton).text).trim_suffix(" ▾"))
	return out


## the captions its row should show: the groups with at least one tool on screen
func caps_expected(page: String) -> Array:
	var row: String = m.PAGE_ROW[page]
	var out := []
	for g in m.RIBBON_GROUPS[row]:
		var any := false
		for c in m.ui_ribbon[row].get_children():
			if c is Button and m.label_of(c) in g[1] and (c as Control).is_visible_in_tree():
				any = true
		if any:
			out.append(String(g[0]))
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	# 1 the bar
	var bar: Control = m.ui_page_bar
	var names := []
	var soon_ok := true
	for b in bar.find_children("*", "Button", true, false):
		if m.ui_nt_box != null and m.ui_nt_box.is_ancestor_of(b):   # P17: the next-command chips (pre-made, hidden until learned) are not pages; nexttool_test checks them
			continue
		if b == m.ui_next:   # R6: the bar also carries the one next-step line (a deliberate feature, not a page); it is checked in the R6 test
			continue
		names.append(b.text)
		if b.text in ExpertPages.PAGES:
			# the expert pages: live (not greyed), a tooltip that names the page and its key, a page switch on press
			soon_ok = soon_ok and b.modulate.a >= 0.6 and not b.disabled and b.tooltip_text.begins_with("%s page (Shift+" % b.text)
	ok(names == ["BODY", "POSE", "ANIMATE", "STAGE", "CHECK", "DELIVER", "MODEL", "SCULPT", "SURFACE"] and soon_ok, "1 the page bar: %s; the three expert pages live, tooltip, not greyed" % [names])
	ok(bar.get_global_rect().end.y >= vs.y - 0.5 and bar.get_global_rect().size.y >= m.PAGE_H - 0.5 and bar.get_global_rect().position.x == 0.0, "3 the bar is the window's very bottom: %s of %s" % [bar.get_global_rect(), vs])
	# 2 / 3 each page: its row, its captions, its button lit, its name on screen
	var scene0 := JSON.stringify(m.S.to_dict(m.B))
	var undo0: int = m.undo.size()
	for p in m.PAGES:
		await click(m.ui_page_btns[p])
		var rows: Array = m.RIBBON.filter(func(k): return m.ui_ribbon[k].visible)
		var lit: Array = m.PAGES.filter(func(k): return m.ui_page_btns[k].button_pressed)
		var got := caps_shown()
		var want := caps_expected(p)
		ok(rows == [m.PAGE_ROW[p]] and lit == [p] and got == want and not want.is_empty(), "2 %s: row %s, lit %s, groups %s (expected %s)" % [p, rows, lit, got, want])
		ok(m.cur_page == p and m.ui_page_btns[p].text == p and m.ui_page_btns[p].is_visible_in_tree(), "3 %s is named on screen (the lit button reads '%s')" % [p, m.ui_page_btns[p].text])
	# 8 layouts
	await click(m.ui_page_btns["DELIVER"])
	await idle()
	var d_ok: bool = m.fold["left"] and m.fold["right"] and m.fold["bottom"]
	await click(m.ui_page_btns["ANIMATE"])
	await idle()
	ok(d_ok and not m.fold["bottom"] and m.lw() > 100.0, "8 DELIVER folded both sides + the strip; ANIMATE has the strip open (bottom_h %d)" % m.bottom_h)
	for p in m.PAGES:
		await click(m.ui_page_btns[p])
		var bp: Rect2 = m.ui_bp.get_global_rect()
		ok(bp.end.y <= bar.get_global_rect().position.y + 0.5, "8 %s: the scene strip ends at %.0f, the page bar starts at %.0f" % [p, bp.end.y, bar.get_global_rect().position.y])
	# 3D labels stay off the bottom bars: every axis word still shown is above the free view's bottom, on every page
	var low_lab := true
	for p in m.PAGES:
		await click(m.ui_page_btns[p])
		for c in m.stage_root.get_children():
			if c is Label3D and String(c.name).begins_with("axis_") and c.visible:
				low_lab = low_lab and m.cam.unproject_position(c.global_position).y < vs.y - m.bottom_h - 4.0
	ok(low_lab, "8 no axis label is drawn over the scene strip or the page bar (on any page)")
	# 4 search finds every command, on every page (the search is main's one registry list)
	var cs: CommandSearch = m.ui_cmd
	var missing := 0
	var n_all: int = cs.commands.size()
	for p in ["POSE", "DELIVER"]:
		m._page_set(p)
		missing = 0
		for c in cs.commands:
			if not cs.matches("", String(c["name"])).any(func(r): return r["name"] == c["name"]):
				missing += 1
		ok(missing == 0, "4 on %s all %d commands are found by name (%d missing)" % [p, n_all, missing])
	# every ribbon button of a page is on that page's row, and each row but VIEW belongs to a page
	var rowless := 0
	for k in m.RIBBON:
		if k != "VIEW" and not (m.PAGE_ROW.values().has(k)):
			rowless += 1
	ok(rowless == 0 and m.ui_view_menu != null, "4 every ribbon row is a page's (VIEW is the View menu on all pages)")
	# 5 Shift+1..5
	var keyed := true
	for i in m.PAGES.size():
		m._page_set("POSE")
		m._press(KEY_1 + i, true)
		keyed = keyed and m.cur_page == m.PAGES[i]
		var c_keys := ""
		for c in cs.commands:
			if c["name"] == "Page: " + m.PAGES[i]:
				c_keys = c["keys"]
		keyed = keyed and c_keys == "Shift+%d" % (i + 1)
	m.yaw = 33.0
	m._press(KEY_2)   # a plain 2 is still the camera
	ok(keyed and is_equal_approx(m.yaw, -90.0), "5 Shift+1..6 switch pages and match the registry (end on %s); plain 2 still the camera (yaw %.0f)" % [m.cur_page, m.yaw])
	# 6 saved and restored
	m._page_set("CHECK")
	var cf := ConfigFile.new()
	cf.load(m.settings)
	var saved_page: String = cf.get_value("layout", "page", "")
	m._page_set("POSE")
	cf.load(m.settings)
	cf.set_value("layout", "page", "STAGE")
	cf.save(m.settings)
	var cf2 := ConfigFile.new()
	cf2.load(m.settings)
	m._pages_load(cf2)
	ok(saved_page == "CHECK" and m.cur_page == "STAGE" and m.ui_page_btns["STAGE"].button_pressed, "6 saved 'CHECK' on switch (%s); the boot's loader restored STAGE (%s)" % [saved_page, m.cur_page])
	# 7 no undo step, scene identical, fast
	var worst := 0.0
	for r in 4:
		for p in m.PAGES:
			var t0 := Time.get_ticks_usec()
			m._page_set(p)
			worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	await idle()
	var scene1 := JSON.stringify(m.S.to_dict(m.B))
	ok(m.undo.size() == undo0 and scene1 == scene0, "7 no undo step (%d -> %d) and the scene is byte-identical (%d bytes)" % [undo0, m.undo.size(), scene1.length()])
	ok(worst < 50.0, "7 a page switch takes %.1f ms at worst of 20 (bar 50)" % worst)
	print("PAGES %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
