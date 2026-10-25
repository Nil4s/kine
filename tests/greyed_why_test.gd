## godot --path . -s tests/greyed_why_test.gd     (GATES CC3, UPGRADES #46; a window: the real UI)
## DISABLED SAYS WHY (every ribbon tab opened in turn): in each state - an empty scene, one card, a scene with no card picked, its first card picked, a
## later card picked, a Smooth (spline) scene, playing - every control on screen and every item of every menu (opened as
## a click opens it) is audited. Each one greyed (disabled, or not editable) must say why and what to do: its tooltip
## carries main.GREY_TAG ("NOT NOW:") and 5 words or more after it. No control that is NOT greyed may still carry one
## (a stale reason). The audit prints every greyed control it found, per state, with its reason.
extends SceneTree

var fails := 0
var m: Node
var seen := {}   # "control: reason" -> the states it was greyed in


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func reason(tip: String) -> String:
	var k := tip.find("NOT NOW:")
	return "" if k < 0 else tip.substr(k + 8).strip_edges()


func label(c: Node) -> String:
	var t = c.get("text")
	return "%s '%s'" % [c.get_class(), String(t).left(30) if t != null and String(t) != "" else String(c.name)]


func audit(state: String) -> void:
	await idle(3)
	var bad := []
	var greyed := 0
	var done := {}   # each control once, whichever tabs show it
	var shown := []
	for t in m.RIBBON:   # every ribbon tab in turn: a tool on a tab not open is still the user's
		m._ribbon(t)
		await idle(1)
		for c in m.ui_root.find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree() and not done.has(c.get_instance_id()):
				done[c.get_instance_id()] = true
				shown.append(c)
	m._ribbon("POSE")
	# round 36: the gear's box (Smooth, tween, ease) and the inspector's folded sections are closed boxes, the same way
	# a tab not open is: open each, take what it shows, close it again
	var was_open := {}
	for k in m.ui_secs:
		was_open[k] = m.ui_secs[k][1].visible if m.ui_secs[k] is Array else false
	if not m.ui_gear.visible:
		m._gear_open()
	for k in m.ui_secs:
		m._sec_open(k, true)
	await idle(1)
	for c in m.ui_root.find_children("*", "Control", true, false):
		if (c as Control).is_visible_in_tree() and not done.has(c.get_instance_id()):
			done[c.get_instance_id()] = true
			shown.append(c)
	m._gear_open()
	for k in m.ui_secs:
		m._sec_open(k, was_open[k])
	for c in shown:
		# P05's mouse-hint strip rebuilds its items when the page changes, so a hint label taken on an earlier tab is
		# freed by now; the strip's current items were taken again (new ids) on the tab that shows them
		if not is_instance_valid(c):
			continue
		var cc := c as Control
		var off: bool = (cc.get("disabled") == true) or (cc.get("editable") == false and (cc is LineEdit or cc is SpinBox or cc is TextEdit or cc is Slider))   # Slider: the per-card ease slider is greyed by editable=false
		var why := reason(cc.tooltip_text)
		if off:
			greyed += 1
			seen["%s: %s" % [label(cc), why]] = seen.get("%s: %s" % [label(cc), why], []) + [state]
			if why.split(" ", false).size() < 5:
				bad.append("%s greyed, no reason ('%s')" % [label(cc), cc.tooltip_text.right(40)])
		elif why != "":
			bad.append("%s NOT greyed but still says 'NOT NOW: %s'" % [label(cc), why.left(30)])
		# its menu, opened the way a click opens it
		var pm: PopupMenu = null
		if cc is MenuButton:
			(cc as MenuButton).about_to_popup.emit()
			pm = (cc as MenuButton).get_popup()
		elif cc is OptionButton:
			pm = (cc as OptionButton).get_popup()
		if pm != null:
			for i in pm.item_count:
				if pm.is_item_separator(i):
					continue
				var iw := reason(pm.get_item_tooltip(i))
				if pm.is_item_disabled(i):
					greyed += 1
					seen["%s item '%s': %s" % [label(cc), pm.get_item_text(i), iw]] = seen.get("%s item '%s': %s" % [label(cc), pm.get_item_text(i), iw], []) + [state]
					if iw.split(" ", false).size() < 5:
						bad.append("%s item '%s' greyed, no reason" % [label(cc), pm.get_item_text(i)])
				elif iw != "":
					bad.append("%s item '%s' NOT greyed but says why" % [label(cc), pm.get_item_text(i)])
	ok(bad.is_empty(), "%s: %d controls on the 4 tabs, %d greyed, each says why (bad: %s)" % [state, shown.size(), greyed, bad])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	await audit("empty scene")
	m._card_add()
	await audit("one card")
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.sel_card = -1
	m._refresh()
	await audit("combo3, no card picked")
	m.sel_card = 0
	m._refresh()
	await audit("combo3, the first card picked")
	m.sel_card = 3
	m._refresh()
	await audit("combo3, card 4 picked")
	var sp := false
	for f in DirAccess.get_files_at("res://scenes/"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f)) if f.ends_with(".json") else null
		if d is Dictionary and d.get("spline", false):
			m._load_scene("res://scenes/" + f)
			sp = true
			break
	if not sp:
		m.S.spline = true
	m._rebuild_cards()
	m.sel_card = 2
	m._refresh()
	await audit("a Smooth (spline) scene, card 3 picked")
	m.S.spline = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._press(KEY_SPACE)
	await idle(10)
	await audit("playing")
	m._press(KEY_SPACE)
	print("     every greyed control found, its reason, the states:")
	for k in seen:
		print("       %s   [%s]" % [k, ", ".join(seen[k])])
	ok(seen.size() >= 3, "the audit found greyed controls to judge (%d distinct)" % seen.size())
	print("GREYED WHY: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
