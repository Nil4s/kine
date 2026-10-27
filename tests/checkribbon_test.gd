## godot --path . -s tests/checkribbon_test.gd     (CHECK page ribbon redo; needs a window)
## CHECK's 41 tools (40, plus A1's Keep this pose) are 8 captioned groups like POSE / ANIMATE: <= 20 icons on the row, the rest under each group's caption (its
## menu). Every old tool is reached by REAL clicks (its icon, or its caption then its menu item) and runs the same button's action.
## At 1280x720 and 1600x900: nothing clipped, nothing in More, captions there.
extends SceneTree

const OLD := ["Check", "Polish", "Fix moves through the body", "Timing coach", "Weapon weight", "Parry rebound", "What I learned from you", "Fight to the beat", "Choreograph to the song",
	"Fight distance", "Sell the hit", "Gaze director", "Safety sheet", "Reaction direction", "Fight rhythm", "Breakfall check", "Recovery step", "Precog check", "Auto opponent", "Fatigue",
	"Momentum ledger", "Airborne spin check", "Real-mocap check", "Realism score", "My style", "Use my style", "Star this clip", "My best take", "Make this one more like my best", "Speed limits",
	"My combos", "Auto camera", "My camera", "Frame it my way", "Make it physical", "Accept span", "Keep this pose", "Dummy (H)", "Frame data", "Frame boxes", "Frame rate"]

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


func tool_of(t: String) -> Button:
	for c in m.ui_ribbon["CHECK"].get_children():
		if c is Button and m.label_of(c) == t:
			return c
	return null


func cap_of(t: String) -> Array:
	for pair in m.ui_caps["CHECK"]:
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


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	# 41 = 40 + "Keep this pose" (A1, commit 78efc4f2: the priority flag on the PHYSICS group)
	ok(OLD.size() == 41, "the old CHECK list has 41 tools")
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		await size_to(sz.x, sz.y)
		await click(m.ui_page_btns["CHECK"])
		await process_frame
		await process_frame
		var tag := "%dx%d" % [sz.x, sz.y]
		var w: float = root.get_visible_rect().size.x
		var row: Control = m.ui_ribbon["CHECK"]
		var shown: Array = row.get_children().filter(func(c): return c is Button and (c as Control).is_visible_in_tree())
		ok(shown.size() <= 20 and shown.size() >= 12, "%s: %d icons visible (<= 20)" % [tag, shown.size()])
		ok(not m.ui_more.visible and m._more_tools.is_empty(), "%s: nothing in More (the row is the same at every size)" % tag)
		var right := 0.0
		for b in shown:
			right = maxf(right, (b as Control).get_global_rect().end.x)
		ok(right <= w - 6.0 and (shown[0] as Control).get_global_rect().position.x >= 0.0, "%s: none clipped (row ends at %.0f of %.0f)" % [tag, right, w])
		var pairs: Array = m.ui_caps["CHECK"]
		ok(pairs.size() >= 7 and pairs.size() <= 9, "%s: %d groups" % [tag, pairs.size()])
		var seen := 0
		for pair in pairs:
			var cap: MenuButton = pair[0]
			var vis: Array = (pair[1] as Array).filter(func(b): return (b as Control).is_visible_in_tree())
			ok(cap.visible and cap.text.strip_edges() != "" and "\u25be" in cap.text, "%s: caption '%s' is there" % [tag, cap.text])
			ok(vis.size() >= 2 and vis.size() <= 6, "%s: group %s has %d icons (2-6)" % [tag, cap.text, vis.size()])
			var capr := cap.get_global_rect()
			ok(capr.end.x <= w and capr.position.x >= 0.0, "%s: caption %s inside the window" % [tag, cap.text])
			var menu_n: int = cap.get_popup().item_count
			ok(menu_n == (pair[1] as Array).size(), "%s: %s menu lists all %d of its tools" % [tag, cap.text, menu_n])
			seen += menu_n
		ok(seen == 41, "%s: the groups hold all 41 tools (%d)" % [tag, seen])
		ok(shown[0] is Button and m.label_of(shown[0]) == "Check", "%s: the main Check is first" % tag)
		# every tool: reached by real clicks, its own button fires
		var direct := 0
		var via := 0
		for t in OLD:
			var b := tool_of(t)
			if b == null:
				ok(false, "%s: '%s' is GONE" % [tag, t])
				continue
			if tag == "1600x900":
				ok(b.pressed.get_connections().size() >= 2, "  '%s' has its action wired" % t)
			arm(b, t)
			hits.erase(t)
			if b.is_visible_in_tree():
				await click(b)
				direct += 1
			else:
				var cp := cap_of(t)
				ok(cp[0] != null, "%s: '%s' is under a caption" % [tag, t])
				await click(cp[0])
				var pm: PopupMenu = (cp[0] as MenuButton).get_popup()
				ok(pm.visible and pm.get_item_text(cp[1]) == t, "%s: caption menu for '%s' opened, item %d reads it" % [tag, t, cp[1]])
				pm.id_pressed.emit(cp[1])
				pm.hide()
				await process_frame
				via += 1
			ok(hits.get(t, 0) == 1, "%s: '%s' runs its own action once" % [tag, t])
		ok(direct + via == 41, "%s: %d by its icon + %d via a caption = 41" % [tag, direct, via])
		var sh: String = "C:/Temp/claude/checkribbon/test_%s.png" % tag
		DirAccess.make_dir_recursive_absolute("C:/Temp/claude/checkribbon")
		root.get_texture().get_image().save_png(sh)
	# the on-state is an underline, not the amber fill
	var dm := tool_of("Dummy (H)")
	ok(dm.theme_type_variation == "RibbonUnder", "toggles on CHECK use the underline look")
	print("checkribbon: %d fails" % fails)
	quit(1 if fails > 0 else 0)
