## godot --path . -s tests/toolbar_test.gd     (GATES RR1; needs a window)
## THE TOOLBAR, FUSION'S WAY: two thin rows inside TOP_H (at most 76). Every ribbon tool and every top-right button
## shows NO words, has an icon, and keeps a label (its old full name) that its tooltip leads with; each group's caption
## sits under its own group (its x span overlaps the group's first to last tool, below them, inside TOP_H); a caption's
## menu runs its tool (BODY... Collision is SHOW's; CAMERA > Front (1) sets the view); the tabs are in the top row; the
## strip names the open scene and shows the unsaved dot after an edit. Clicked through the window where it can be.
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


## the caption whose menu lists this label, in this tab
func cap_of(tab: String, label: String) -> Array:
	for pair in m.ui_caps[tab]:
		for b in pair[1]:
			if m.label_of(b) == label:
				return [pair[0], (pair[1] as Array).find(b)]
	return [null, -1]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	ok(m.TOP_H <= 76, "the bar is %d px (round 35: 68, the gate: at most 76)" % m.TOP_H)
	var w: float = root.get_visible_rect().size.x
	# every tool: no words, an icon, a label its tooltip leads with
	var words := []
	var n := 0
	for tab in m.RIBBON:
		await click(m.ui_ribbon_tabs[tab])
		await idle()
		for b in m.ui_ribbon[tab].get_children():
			if not b is Button:
				continue
			n += 1
			var lab: String = m.label_of(b)
			if b.text != "" or b.icon == null or lab == "" or not b.tooltip_text.begins_with(lab):
				words.append("%s: text '%s' icon %s tip '%s'" % [lab, b.text, b.icon != null, b.tooltip_text.left(30)])
			if b.get_global_rect().end.y > m.TOP_H or b.get_global_rect().end.x > w:
				words.append("%s off the bar: %s" % [lab, b.get_global_rect()])
		# each caption under its group
		var bad := []
		for pair in m.ui_caps[tab]:
			var cap: Control = pair[0]
			var tools: Array = pair[1]
			var a: Rect2 = (tools[0] as Control).get_global_rect()
			var z: Rect2 = (tools[-1] as Control).get_global_rect()
			var c: Rect2 = cap.get_global_rect()
			if not cap.visible or c.position.y < z.end.y - 1 or c.end.y > m.TOP_H + 1 or c.end.x < a.position.x or c.position.x > z.end.x:
				bad.append("%s at %s, its tools %s..%s" % [cap.text, c, a, z])
		ok(bad.is_empty() and m.ui_caps[tab].size() == m.RIBBON_GROUPS[tab].size(), "%s: %d captions, each under its own group %s" % [tab, m.ui_caps[tab].size(), bad if not bad.is_empty() else ""])
	for b in m.ui_top_right:
		var lab: String = m.label_of(b)
		if b.text != "" or b.icon == null or lab == "" or not b.tooltip_text.begins_with(lab):
			words.append("top right %s: text '%s' tip '%s'" % [lab, b.text, b.tooltip_text.left(30)])
		if b.get_global_rect().end.y > m.STRIP_H + 2:
			words.append("top right %s below the strip: %s" % [lab, b.get_global_rect()])
	ok(words.is_empty() and n >= 27, "%d tools and %d top-right buttons: no words, an icon, the name in the tooltip %s" % [n, m.ui_top_right.size(), words if not words.is_empty() else ""])
	# the tabs in the top row
	var low := 0.0
	for tab in m.RIBBON:
		low = maxf(low, m.ui_ribbon_tabs[tab].get_global_rect().end.y)
	ok(low <= m.STRIP_H + 1, "the five tabs in the top row (they end at y %.0f, the strip %d)" % [low, m.STRIP_H])
	# a caption's menu runs its tool
	await click(m.ui_ribbon_tabs["POSE"])
	await idle()
	var f := cap_of("POSE", "Collision (C)")
	var c0: bool = m.show_caps
	await click(f[0])
	await idle()
	var pm: PopupMenu = (f[0] as MenuButton).get_popup()
	var shown := pm.visible
	pm.id_pressed.emit(pm.get_item_id(f[1]))
	pm.hide()
	await idle()
	ok(shown and m.show_caps != c0, "SHOW's caption, clicked, opens its menu (%s); 'Collision (C)' from it: %s -> %s" % [shown, c0, m.show_caps])
	await click(m.ui_ribbon_tabs["VIEW"])
	await idle()
	m.yaw = 33.0
	f = cap_of("VIEW", "His right (2)")
	pm = (f[0] as MenuButton).get_popup()
	pm.id_pressed.emit(pm.get_item_id(f[1]))
	await idle()
	ok(is_equal_approx(m.yaw, -90.0), "CAMERA's menu > 'His right (2)': yaw %.0f" % m.yaw)
	var items := []
	for i in pm.item_count:
		items.append(pm.get_item_text(i))
	ok(items == m.RIBBON_GROUPS["VIEW"][0][1], "CAMERA's menu lists its tools by full name: %s" % [items])
	# the strip names the scene; the dot after an edit
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await create_timer(0.6).timeout
	await idle()
	ok(m.ui_doc.text.begins_with(m.S.name) and ("%d clips" % m.S.cards.size()) in m.ui_doc.text and m.S.name == "combo3",
		"the strip: '%s'" % m.ui_doc.text)
	var dot0: bool = m.ui_doc_dot.visible
	m.B.ang["upperarm_r"] = Vector3(30, 5, 0)
	m.B.fk()
	m._card_update(0)
	await create_timer(0.6).timeout   # the strip is worked out at most every 0.4 s
	await idle()
	ok(not dot0 and m.ui_doc_dot.visible, "the unsaved dot: %s after opening, %s after an edit" % [dot0, m.ui_doc_dot.visible])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("TOOLBAR TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
