## godot --path . -s tests/strip_test.gd     (GATES RR4; needs a window)
## ONE TIMELINE, ONE CAMERA BAR: with the clips panel folded the bottom is ONE strip at most 44 px tall: first /
## previous / play / next / last, the clips' track, the time, the speed, Loop, Natural, a gear (Smooth, tween, ease,
## + tween), Clips (opens the cards above). Check / Polish / Fix are not on it (the ribbon's CHECK has them). The view's
## Orbit / Pan / zoom / Fit / Grid are one icon bar at the status line's right end (amended: the bottom centre covered the feet), inside the view, over neither the
## inspector nor the cube. Every control clicked through the window and checked by what it changes.
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
	await idle(2)


func on_strip(t: String) -> Button:
	for b in m.ui_play_row.find_children("*", "Button", true, false):
		if m.label_of(b) == t and (b as Button).is_visible_in_tree():
			return b
	return null


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._fold("bottom", true)
	await idle(4)
	var bp: Rect2 = m.ui_bp.get_global_rect()
	var tl: Rect2 = m.ui_timeline.get_global_rect()
	var pl: Rect2 = m.ui_play.get_global_rect()
	ok(bp.size.y <= 44.0 and m.ui_timeline.is_visible_in_tree() and absf(tl.get_center().y - pl.get_center().y) < 4.0 and bp.encloses(tl) and bp.encloses(pl),
		"folded: ONE strip %.0f px tall (at most 44), the track and Play on one row (centres %.0f / %.0f)" % [bp.size.y, tl.get_center().y, pl.get_center().y])
	var missing := []
	for t in ["First clip (Home)", "Previous clip", "Play (Space)", "Next clip", "Last clip (End)", "Slower", "Faster", "Play options", "Clips"]:
		if on_strip(t) == null:
			missing.append(t)
	ok(missing.is_empty() and m.ui_loop.is_visible_in_tree() and m.ui_natural.is_visible_in_tree() and m.ui_time_lbl.is_visible_in_tree(), "on the strip: the transport, speed, Loop, Natural, the time, the gear, Clips (missing %s)" % [missing])
	var gone := []
	for t in ["Check", "Polish", "Fix moves through the body"]:
		if on_strip(t) != null:
			gone.append(t)
	var in_ribbon := []
	for b in m.ui_ribbon["CHECK"].get_children():
		if b is Button:
			in_ribbon.append(m.label_of(b))
	ok(gone.is_empty() and in_ribbon.has("Check") and in_ribbon.has("Polish") and in_ribbon.has("Fix moves through the body"), "Check / Polish / Fix: off the strip %s, in CHECK %s" % [gone, in_ribbon])
	# the transport
	var t: Array = m.S.times()
	m.playhead = 1.0
	await click(on_strip("First clip (Home)"))
	ok(m.playhead == 0.0, "First: the playhead at %.2f" % m.playhead)
	await click(on_strip("Next clip"))
	ok(m.sel_card == 0 or is_equal_approx(m.playhead, t[m.sel_card][1]), "Next: clip %d, playhead %.2f" % [m.sel_card + 1, m.playhead])
	var c1: int = m.sel_card
	await click(on_strip("Next clip"))
	ok(m.sel_card == c1 + 1 and is_equal_approx(m.playhead, t[m.sel_card][1]), "  Next again: clip %d -> %d" % [c1 + 1, m.sel_card + 1])
	await click(on_strip("Previous clip"))
	ok(m.sel_card == c1, "Previous: back to clip %d" % (m.sel_card + 1))
	await click(on_strip("Last clip (End)"))
	ok(is_equal_approx(m.playhead, m.S.length()), "Last: the playhead at the end %.2f" % m.playhead)
	await click(on_strip("First clip (Home)"))
	await click(m.ui_play)
	ok(m.playing and m.label_of(m.ui_play) == "Stop (Space)", "Play clicked: playing, its label '%s'" % m.label_of(m.ui_play))
	await click(m.ui_play)
	ok(not m.playing and m.label_of(m.ui_play) == "Play (Space)", "  clicked again: stopped")
	# speed, loop, natural
	m.sel_card = -1
	var len0: float = m.S.length()
	await click(on_strip("Slower"))
	ok(m.S.length() > len0 + 0.01, "Slower: %.2f -> %.2f s" % [len0, m.S.length()])
	len0 = m.S.length()
	await click(on_strip("Faster"))
	ok(m.S.length() < len0 - 0.01, "Faster: %.2f -> %.2f s" % [len0, m.S.length()])
	var lp0: bool = m.S.loop
	await click(m.ui_loop)
	ok(m.S.loop != lp0, "Loop clicked: %s -> %s" % [lp0, m.S.loop])
	var n0: bool = m.S.natural
	await click(m.ui_natural)
	ok(m.S.natural != n0, "Natural clicked: %s -> %s" % [n0, m.S.natural])
	# the gear
	await click(on_strip("Play options"))
	ok(m.ui_gear.visible and m.ui_spline.is_visible_in_tree() and m.ui_tween.is_visible_in_tree() and m.ui_ease.is_visible_in_tree(), "the gear: its box opens with Smooth, tween, ease")
	var sp0: bool = m.S.spline
	await click(m.ui_spline)
	ok(m.S.spline != sp0, "  Smooth (spline) clicked: %s -> %s" % [sp0, m.S.spline])
	await click(m.ui_spline)
	m._timeline_pick(2)
	await idle()
	if not m.ui_gear.visible:
		await click(on_strip("Play options"))
	var nc: int = m.S.cards.size()
	var tw: Button = null
	for b in m.ui_gear.find_children("*", "Button", true, false):
		if (b as Button).text == "+ tween":
			tw = b
	if tw != null:
		await click(tw)
	ok(tw != null and m.S.cards.size() == nc + 1, "  + tween clicked: %d -> %d clips" % [nc, m.S.cards.size()])
	await click(m.ui_play)   # a press outside closes the box
	await click(m.ui_play)
	ok(not m.ui_gear.visible, "  a click elsewhere closes the gear's box")
	# Clips opens the cards; Fold folds them
	await click(on_strip("Clips"))
	ok(not m.fold["bottom"] and m.ui_card_row.is_visible_in_tree() and m.ui_bp.get_global_rect().size.y > 200.0, "Clips: the cards open above the strip (%.0f px)" % m.ui_bp.get_global_rect().size.y)
	await click(m.ui_fold_btn["bottom"])
	ok(m.fold["bottom"] and m.ui_bp.get_global_rect().size.y <= 44.0, "Fold: one strip again")
	# the camera bar
	var vs := root.get_visible_rect().size
	var nr: Rect2 = m.ui_nav.get_global_rect()
	var view := Rect2(m.lw(), m.TOP_H, vs.x - m.lw(), vs.y - m.bottom_h - m.TOP_H)
	var cx: float = vs.x - 12.0   # RR4 amended: the line's right end (the bottom centre covered the feet)
	ok(view.encloses(nr) and absf(nr.end.x - cx) < 4.0 and nr.end.y > vs.y - m.bottom_h - 120.0 and not nr.intersects(m.ui_insp.get_global_rect()) and not nr.intersects(m.ui_cube.get_global_rect()) and nr.size.y <= 40.0,
		"the camera bar: %s, the status line's right end (ends at %.0f, the line's %.0f), one row, over neither the inspector nor the cube" % [nr, nr.end.x, cx])
	var b: Button = m.ui_nav.get_node("nav_orbit")
	ok(b.text == "" and b.icon != null and b.tooltip_text.begins_with("Orbit"), "  icons, the names in the tooltips")
	await click(b)
	ok(m.nav_tool == "orbit", "  Orbit clicked: on")
	await click(b)
	await click(m.ui_nav.get_node("nav_pan"))
	ok(m.nav_tool == "pan", "  Pan clicked: on")
	await click(m.ui_nav.get_node("nav_pan"))
	var d0: float = m.dist
	await click(m.ui_nav.get_node("nav_in"))
	ok(m.dist < d0, "  Zoom in: %.2f -> %.2f" % [d0, m.dist])
	d0 = m.dist
	await click(m.ui_nav.get_node("nav_out"))
	ok(m.dist > d0, "  Zoom out: %.2f -> %.2f" % [d0, m.dist])
	m.dist = 11.0
	m._cam()
	await click(m.ui_nav.get_node("nav_fit"))
	ok(m.dist < 9.0, "  Fit: 11 -> %.2f" % m.dist)
	var g0: bool = m.grid_node.visible
	await click(m.ui_nav.get_node("nav_grid"))
	ok(m.grid_node.visible != g0, "  Grid: %s -> %s" % [g0, m.grid_node.visible])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("STRIP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
