## godot --path . -s tests/browser_test.gd     (GATES N3; needs a window)
## The browser tab, clicked with mouse events at the pixels its rows are drawn at: every joint has a row; a finger
## joint picked by name is selected (and the right panel shows it); a click in the view lights the row (without
## looping back); the scene's clips are listed and a click picks one; the weapon row only with a weapon. The Poses
## tab is still the first.
extends SceneTree

var fails := 0
var m: Node
var br: Browser


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func click_row(it: TreeItem) -> void:
	br.scroll_to_item(it, true)
	await process_frame
	var r := br.get_item_area_rect(it)
	# the row's middle on the SCREEN, sent to the window as a real click (Tree's input is native: no script call)
	var local := r.position + r.size * 0.5   # get_item_area_rect is already scrolled (minus the scroll hit nothing)
	ok(br.get_item_at_position(local) == it, "  (the click point is on the row '%s')" % it.get_text(0))
	var p := br.get_global_transform() * local
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e)
	await process_frame


func find(t: String, under: TreeItem = null) -> TreeItem:
	var stack: Array = [br.get_root() if under == null else under]
	while stack.size() > 0:
		var it: TreeItem = stack.pop_back()
		if it.get_text(0) == t:
			return it
		for c in it.get_children():
			stack.append(c)
	return null


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	br = m.ui_browser
	var tabs: TabContainer = br.get_parent()
	ok(tabs.current_tab == 0 and tabs.get_tab_title(0) == "Poses" and m.ui_poses.is_visible_in_tree(), "the Poses tab is first and open (the left panel as it was)")
	tabs.current_tab = 1
	await process_frame
	var missing := Body.ORDER.filter(func(j): return not br.rows.has(j))
	ok(missing.is_empty() and br.rows.size() == Body.ORDER.size() + 1, "every joint has a row: %d rows (%d joints + the weapon handle), missing %s" % [br.rows.size(), Body.ORDER.size(), str(missing)])

	# a finger joint, by name, by mouse: Body > Right arm > fingers > index > "index, middle joint"
	var arm := find("Right arm")
	var fing := find("fingers", arm)
	fing.collapsed = false
	var idx := find("index", fing)
	idx.collapsed = false
	await process_frame
	var row := find("index, middle joint", idx)
	await click_row(row)
	ok(m.sel == "index_02_r", "click 'index, middle joint' under Right arm: selected %s" % m.sel)
	ok(String(m.ui_title.text).to_lower().contains("index finger, middle"), "  the right panel shows it: '%s'" % m.ui_title.text)

	# the other way: a part picked in the view lights its row, and that does not come back as a browser pick
	var said: String = m.ui_status.text
	m.sel = "calf_l"
	m._refresh()
	await process_frame
	ok(br.get_selected() == br.rows["calf_l"] and m.ui_status.text == said, "pick the left knee in the view: its row lit ('%s'), no echo back" % br.get_selected().get_text(0))
	m.sel = "pinky_03_l"
	br.rows["pinky_03_l"].get_parent().collapsed = true
	m._refresh()
	await process_frame
	ok(br.get_selected() == br.rows["pinky_03_l"] and not br.rows["pinky_03_l"].get_parent().collapsed, "a finger picked in the view: its folded folder opens, the row lit")

	# the scene's clips
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await process_frame
	await process_frame   # the clip rows are rebuilt on the frame after
	var sc := find("Scene: combo3  (12 clips)")
	ok(sc != null and sc.get_child_count() == 12, "the Scene folder: 'combo3', %d clips listed" % (sc.get_child_count() if sc != null else -1))
	await click_row(sc.get_child(10))
	await process_frame
	ok(m.sel_card == 10, "click clip 11 in the browser: card %d picked" % (m.sel_card + 1))

	# the weapon row: only with a weapon
	m._bat_remove()
	m._refresh()
	var w0: bool = br.rows["bat_handle"].is_visible_in_tree()
	m._bat_put("hand_r")
	m._refresh()
	ok(not w0 and br.rows["bat_handle"].is_visible_in_tree(), "the weapon row: hidden with no weapon (%s), shown with one (%s)" % [w0, br.rows["bat_handle"].is_visible_in_tree()])
	m.sel = "head"   # _bat_put may select the handle itself: start from another part so the click has to do it
	m._refresh()
	await process_frame   # let the tree's own (deferred) scroll to 'head' land first
	await click_row(br.rows["bat_handle"])
	ok(m.sel == "bat_handle", "click it: the weapon handle selected (%s)" % m.sel)
	print("BROWSER %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
