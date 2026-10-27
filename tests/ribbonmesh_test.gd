## godot --path . -s tests/ribbonmesh_test.gd     (RIBBON STANDARD on MODEL / SCULPT / SURFACE; needs a window)
## The CHECK ribbon standard (tests/checkribbon_test.gd) on the three mesh pages: icon-only buttons in 2-6 captioned groups,
## <= 20 icons on the row, the rarer tools under each group's caption (its menu), nothing in More, nothing clipped. Every old
## tool of the page is reached by REAL clicks (its icon, or its caption then its menu item) and runs the same button's action.
## At 1280x720 and 1600x900. Shots: C:/Temp/claude/ribbonmesh/ (the row, and one caption menu, per page at 1280x720).
extends SceneTree

## the old rows (18 / 12 / 6 tools): every one must still be on the page
const OLD := {
	"MODEL": ["Test cube", "Edit body", "Save to body", "Save", "Open...", "Use in scene", "Extrude", "Inset", "Move", "Rotate", "Scale", "Loop cut", "Knife", "Bevel",
		"Proportional", "Modifiers", "Validate", "Repair"],
	# SCULPT has 12 tools since Voxel remesh joined its START group (remesh, commit 1e2500f5): a count, not a quality bar
	"SCULPT": ["Test sphere", "Sculpt the body", "Voxel remesh", "Draw", "Inflate", "Grab", "Clay", "Crease", "Smooth", "Flatten", "Pinch", "Snake"],
	"SURFACE": ["Paint", "UV editor", "Game UVs 2k", "Pack UVs", "Export UVs", "Material from photo"],
}
## the key each tool keeps (the tooltip carries it, as before)
const KEYS := {"Move": "(G)", "Rotate": "(R)", "Scale": "(S)", "Draw": "(key D)"}

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


func row_of(p: String) -> HBoxContainer:
	return m.ui_ribbon[p]


func tool_of(p: String, t: String) -> Button:
	for c in row_of(p).get_children():
		if c is Button and m.label_of(c) == t:
			return c
	return null


func cap_of(p: String, t: String) -> Array:
	for pair in m.ui_caps[p]:
		for b in pair[1]:
			if m.label_of(b) == t:
				return [pair[0], (pair[1] as Array).find(b)]
	return [null, -1]


## the spy replaces the action (a tool would open a panel or change the mesh) but sits on the SAME button's pressed signal
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


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/ribbonmesh")
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		await size_to(sz.x, sz.y)
		var tag := "%dx%d" % [sz.x, sz.y]
		var w: float = root.get_visible_rect().size.x
		for p in ["MODEL", "SCULPT", "SURFACE"]:
			await click(m.ui_page_btns[p])
			await process_frame
			await process_frame
			var row: Control = row_of(p)
			var shown: Array = row.get_children().filter(func(c): return c is Button and (c as Control).is_visible_in_tree())
			ok(shown.size() >= 5 and shown.size() <= 20, "%s %s: %d icons visible (5-20)" % [tag, p, shown.size()])
			ok(not m.ui_more.visible and m._more_tools.is_empty(), "%s %s: nothing in More" % [tag, p])
			var right := 0.0
			var icon_only := true
			for b in shown:
				right = maxf(right, (b as Control).get_global_rect().end.x)
				icon_only = icon_only and (b as Button).text == "" and (b as Button).icon != null and String((b as Button).tooltip_text) != ""
			ok(right <= w - 6.0 and (shown[0] as Control).get_global_rect().position.x >= 0.0, "%s %s: none clipped (row ends at %.0f of %.0f)" % [tag, p, right, w])
			ok(icon_only, "%s %s: every row button is an icon with a tooltip" % [tag, p])
			var pairs: Array = m.ui_caps[p]
			ok(pairs.size() >= 2 and pairs.size() <= 5, "%s %s: %d groups (2-5)" % [tag, p, pairs.size()])
			var seen := 0
			for pair in pairs:
				var cap: MenuButton = pair[0]
				var vis: Array = (pair[1] as Array).filter(func(b): return (b as Control).is_visible_in_tree())
				ok(cap.visible and "\u25be" in cap.text, "%s %s: caption '%s' is there" % [tag, p, cap.text])
				ok(vis.size() >= 2 and vis.size() <= 6, "%s %s: group %s has %d icons (2-6)" % [tag, p, cap.text, vis.size()])
				var capr := cap.get_global_rect()
				ok(capr.end.x <= w and capr.position.x >= 0.0, "%s %s: caption %s inside the window" % [tag, p, cap.text])
				var menu_n: int = cap.get_popup().item_count
				ok(menu_n == (pair[1] as Array).size(), "%s %s: %s menu lists all %d of its tools" % [tag, p, cap.text, menu_n])
				seen += menu_n
			ok(seen == OLD[p].size(), "%s %s: the groups hold all %d tools (%d)" % [tag, p, OLD[p].size(), seen])
			var direct := 0
			var via := 0
			for t in OLD[p]:
				var b := tool_of(p, t)
				if b == null:
					ok(false, "%s %s: '%s' is GONE" % [tag, p, t])
					continue
				if KEYS.has(t) and KEYS[t] != "":
					ok(String(b.tooltip_text).contains(KEYS[t]), "%s %s: '%s' tooltip keeps its key %s" % [tag, p, t, KEYS[t]])
				arm(b, t)
				hits.erase(t)
				if b.is_visible_in_tree():
					await click(b)
					direct += 1
				else:
					var cp := cap_of(p, t)
					ok(cp[0] != null, "%s %s: '%s' is under a caption" % [tag, p, t])
					await click(cp[0])
					var pm: PopupMenu = (cp[0] as MenuButton).get_popup()
					ok(pm.visible and pm.get_item_text(cp[1]) == t, "%s %s: caption menu opened, item %d reads '%s'" % [tag, p, cp[1], t])
					pm.id_pressed.emit(cp[1])
					pm.hide()
					await process_frame
					via += 1
				ok(hits.get(t, 0) == 1, "%s %s: '%s' runs its own action once" % [tag, p, t])
			ok(direct + via == OLD[p].size(), "%s %s: %d by its icon + %d via a caption = %d" % [tag, p, direct, via, OLD[p].size()])
			# the row, and (at 1280) one caption menu open
			await process_frame
			root.get_texture().get_image().save_png("C:/Temp/claude/ribbonmesh/ribbon_%s_%dx%d.png" % [p.to_lower(), sz.x, sz.y])
			if sz.x == 1280:
				var big: Array = pairs[0]
				for pair in pairs:
					if (pair[1] as Array).size() > (big[1] as Array).size():
						big = pair
				await click(big[0])
				await process_frame
				await process_frame
				root.get_texture().get_image().save_png("C:/Temp/claude/ribbonmesh/menu_%s_1280x720.png" % p.to_lower())
				(big[0] as MenuButton).get_popup().hide()
				await process_frame
	# the on-state of a toggle on these rows is the underline, not the amber fill
	var pv := tool_of("SURFACE", "Paint")
	ok(pv != null and (not pv.toggle_mode or pv.theme_type_variation == "RibbonUnder"), "SURFACE Paint: an on toggle uses the underline look")
	print("ribbonmesh: %d fails" % fails)
	quit(1 if fails > 0 else 0)
