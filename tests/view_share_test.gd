## godot --path . -s tests/view_share_test.gd     (GATES RR6, amended; needs a window)
## THE ROOM, MEASURED: 1600 x 900, combo3 open, a part picked (the inspector shown), the browser shown, the clip cards
## folded to the one strip, not a first start: the view (the window's pixels no panel, rail, strip or line covers,
## sampled every 4 px, as tools/layout_measure.gd counts them) is at least 70 % of the window. Everything open is
## measured and PRINTED (not barred: its ceiling is 53.8 %, GATES RR6). The browser box is as tall as its rows: a
## folder opened grows it by its rows, folded back it shrinks again, never past the scene panel.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func share() -> float:
	var vs: Vector2 = root.get_visible_rect().size
	var chrome: Array = []
	for c in m.ui_root.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and (c is PanelContainer or c is Panel or c == m.ui_status or c == m.ui_bar):
			var r: Rect2 = (c as Control).get_global_rect()
			if r.get_area() > 0 and c != m.ui_tour:
				chrome.append(r)
	var free := 0
	var tot := 0
	var y := 0.0
	while y < vs.y:
		var x := 0.0
		while x < vs.x:
			tot += 1
			var cov: bool = y < m.TOP_H
			if not cov:
				for r in chrome:
					if (r as Rect2).has_point(Vector2(x, y)):
						cov = true
						break
			if not cov:
				free += 1
			x += 4.0
		y += 4.0
	return 100.0 * free / tot


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.get_window().size == Vector2i(1600, 900), "the window is 1600 x 900 (%s)" % m.get_window().size)
	m._end_teach()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.sel = "upperarm_r"
	m._refresh()
	await idle(6)
	var open := share()
	m._fold("bottom", true)
	await idle(6)
	var lp: Control = m.ui_side_of["left"]
	var s := share()
	ok(m.ui_insp.is_visible_in_tree() and lp.is_visible_in_tree() and m.ui_play_row.is_visible_in_tree() and s >= 70.0,
		"the browser, the inspector and the one strip shown: the view is %.1f %% of the window (at least 70); everything open %.1f %% (reported, not barred)" % [s, open])
	var room: float = root.get_visible_rect().size.y - m.bottom_h - 6.0
	var h0 := lp.get_global_rect().size.y
	ok(lp.get_global_rect().end.y < room - 100.0, "  the browser as tall as its rows: %.0f px, ends at %.0f (the panel at %.0f)" % [h0, lp.get_global_rect().end.y, room])
	var leg: TreeItem = null
	var it: TreeItem = m.ui_browser.get_root().get_first_child()
	while it != null:
		if it.get_text(0) == "Left leg":
			leg = it
		it = it.get_next_in_tree()
	leg.collapsed = false
	await idle(4)
	var h1 := lp.get_global_rect().size.y
	ok(h1 > h0 + 3 * 20.0, "  a folder opened (Left leg, 4 rows): the box grows %.0f -> %.0f px" % [h0, h1])
	leg.collapsed = true
	await idle(4)
	ok(absf(lp.get_global_rect().size.y - h0) < 1.0, "  folded back: %.0f px again" % lp.get_global_rect().size.y)
	m.ui_browser.open_all()
	m.ui_browser._lib.collapsed = false
	await idle(4)
	ok(absf(lp.get_global_rect().end.y - room) < 1.0, "  every folder open: the box stops at the scene panel (%.0f), the tree scrolls" % lp.get_global_rect().end.y)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("VIEW SHARE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
