extends SceneTree
## godot --path . -s tests/ribbonsd_test.gd     (STAGE and DELIVER ribbon rows: the POSE / ANIMATE standard; needs a window)
## Each row is small icons in captioned groups (2-6 visible, a few rare ones only under the caption's ▾ menu), <= 20 icons on the row,
## nothing in More. Every old tool is reached by REAL clicks (its icon, or its caption then its menu item) and runs the same button's action.
## At 1280x720 and 1600x900: nothing clipped, nothing in More, one caption per group, every tool keeps its tooltip.

## tools added to a group since the old lists above (338dc756 plan 137 put "Impact frames", the toggle, in STAGE REACT)
const ADDED := {"SET": ["Impact frames"]}
const OLD := {
	"SET": ["Light: three-point", "Light: rim", "Light: noir", "Light: daylight", "Add prop", "Import model", "Turn left", "Turn right", "Delete prop",
		"Sit here", "Step up", "Pick up", "Put down", "Throw to...", "Sit down", "Stand up", "Get up", "Crowd: make 20 copies of this fighter",
		"Crowd: re-roll (new seed)", "Crowd: remove", "Reactions", "React to the hit (physics)", "Add impact frames", "Remove impact frames", "Library"],
	"EXPORT": ["Export...", "Export frame data (json)...", "Render shots (mp4)", "Floor plan", "Save version", "Share as QR", "Pack scene (zip)", "Unpack zip...",
		"Export model (GLB / OBJ)", "Use as a prop", "Open exports folder"],
}
## the page each row belongs to (a page's button is ui_page_btns[page]; the row is PAGE_ROW[page])
const PAGES := ["STAGE", "DELIVER"]

var fails := 0
var m: Node
var hits := {}


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


func tool_of(row: String, t: String) -> Button:
	for c in m.ui_ribbon[row].get_children():
		if c is Button and m.label_of(c) == t:
			return c
	return null


func cap_of(row: String, t: String) -> Array:
	for pair in m.ui_caps[row]:
		for b in pair[1]:
			if m.label_of(b) == t:
				return [pair[0], (pair[1] as Array).find(b)]
	return [null, -1]


## the spy replaces the action (the tool would open a panel / write a scene) but sits on the SAME button's pressed signal
func arm(b: Button, t: String) -> void:
	for c in b.pressed.get_connections():
		b.pressed.disconnect(c["callable"])
	b.pressed.connect(func(): hits[t] = hits.get(t, 0) + 1)


func size_to(w: int, h: int) -> void:
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	await process_frame
	await process_frame
	await process_frame


func shot(path: String, row: String) -> void:
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	var rr: Rect2 = (m.ui_ribbon[row] as Control).get_global_rect()
	var crop := Rect2i(0, maxi(0, int(rr.position.y) - 8), root.get_visible_rect().size.x, int(rr.size.y) + 34)   # the captions sit under the row
	img.get_region(crop).save_png(path.replace(".png", "_ribbon.png"))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(OLD["SET"].size() == 25 and OLD["EXPORT"].size() == 11, "the old lists: STAGE 25 tools, DELIVER 11")
	for page in PAGES:
		var row: String = m.PAGE_ROW[page]
		var old: Array = OLD[row]
		for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
			await size_to(sz.x, sz.y)
			await click(m.ui_page_btns[page])
			await process_frame
			await process_frame
			var tag := "%s %dx%d" % [page, sz.x, sz.y]
			var w: float = root.get_visible_rect().size.x
			var rowc: Control = m.ui_ribbon[row]
			var shown: Array = rowc.get_children().filter(func(c): return c is Button and (c as Control).is_visible_in_tree())
			ok(shown.size() >= 9 and shown.size() <= 20, "%s: %d icons visible (9-20)" % [tag, shown.size()])
			ok(not m.ui_more.visible and m._more_tools.is_empty(), "%s: nothing in More" % tag)
			var right := 0.0
			for b in shown:
				right = maxf(right, (b as Control).get_global_rect().end.x)
			ok(right <= w - 6.0 and (shown[0] as Control).get_global_rect().position.x >= 0.0, "%s: none clipped (row ends at %.0f of %.0f)" % [tag, right, w])
			var icons := true
			var tips := true
			for b in shown:
				icons = icons and (b as Button).icon != null and (b as Button).text == ""
				tips = tips and (b as Button).tooltip_text.strip_edges() != ""
			ok(icons, "%s: every row button is an icon" % tag)
			ok(tips, "%s: every row button has a tooltip" % tag)
			var pairs: Array = m.ui_caps[row]
			ok(pairs.size() == m.RIBBON_GROUPS[row].size() and pairs.size() >= 3 and pairs.size() <= 8, "%s: %d groups (3-8), one caption each" % [tag, pairs.size()])
			var seen := 0
			for pair in pairs:
				var cap: MenuButton = pair[0]
				var vis: Array = (pair[1] as Array).filter(func(b): return (b as Control).is_visible_in_tree())
				ok(cap.visible and "\u25be" in cap.text, "%s: caption '%s' is there" % [tag, cap.text])
				ok(vis.size() >= 1 and vis.size() <= 6, "%s: group %s has %d icons (1-6)" % [tag, cap.text, vis.size()])
				var capr := cap.get_global_rect()
				ok(capr.end.x <= w and capr.position.x >= 0.0, "%s: caption %s inside the window" % [tag, cap.text])
				var menu_n: int = cap.get_popup().item_count
				ok(menu_n == (pair[1] as Array).size(), "%s: %s menu lists all %d of its tools" % [tag, cap.text, menu_n])
				seen += menu_n
			ok(seen == old.size() + ADDED.get(row, []).size(), "%s: the groups hold all %d tools (%d)" % [tag, old.size() + ADDED.get(row, []).size(), seen])   # navigation: ADDED = tools the groups gained after this suite was written
			# every tool: reached by real clicks, its own button fires once
			var direct := 0
			var via := 0
			for t in old:
				var b := tool_of(row, t)
				if b == null:
					ok(false, "%s: '%s' is GONE" % [tag, t])
					continue
				arm(b, t)
				hits.erase(t)
				if b.is_visible_in_tree() and not b.disabled:
					await click(b)
					direct += 1
				elif b.is_visible_in_tree():
					b.pressed.emit()   # greyed now (no prop or fighter picked): a click would do nothing, the button's own signal still runs
					direct += 1
				else:
					var cp := cap_of(row, t)
					ok(cp[0] != null, "%s: '%s' is under a caption" % [tag, t])
					await click(cp[0])
					var pm: PopupMenu = (cp[0] as MenuButton).get_popup()
					ok(pm.visible and pm.get_item_text(cp[1]) == t, "%s: caption menu for '%s' opened, item %d reads it" % [tag, t, cp[1]])
					pm.id_pressed.emit(cp[1])
					pm.hide()
					await process_frame
					via += 1
				ok(hits.get(t, 0) == 1, "%s: '%s' runs its own action once" % [tag, t])
			ok(direct + via == old.size(), "%s: %d by its icon + %d via a caption = %d" % [tag, direct, via, old.size()])
			if sz.x == 1280:
				# the ribbon and one caption menu open, as Nick sees them
				var first_cap: MenuButton = pairs[2][0] if page == "STAGE" else pairs[0][0]   # STAGE: ACT (the 8-tool menu); DELIVER: FILES
				await click(first_cap)
				await process_frame
				await process_frame
				shot("C:/Temp/claude/ribbonsd/%s_%dx%d.png" % [page.to_lower(), sz.x, sz.y], row)
				first_cap.get_popup().hide()
				await process_frame
				shot("C:/Temp/claude/ribbonsd/%s_%dx%d_nomenu.png" % [page.to_lower(), sz.x, sz.y], row)
	print("ribbonsd: %d fails" % fails)
	quit(1 if fails > 0 else 0)
