## godot --path . -s tests/empty_back_test.gd     (GATES AA3, UPGRADES #10; a window: screen rects)
## EMPTY AND BACK: the layout as it stands on screen - each side panel, the bottom panel, the status line, the speed
## graph, the view cube, the timeline, the play row, the cards' strip, and the 3D view's centring (the camera's
## offsets) - recorded the FIRST time in each state, then compared to the pixel on every return: empty -> combo3 ->
## empty (New empty scene, a real click) -> combo3 -> the cards deleted down to none -> combo3, the speed graph on.
extends SceneTree

var fails := 0
var m: Node
var first := {}   # state -> its layout the first time


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func layout() -> Dictionary:
	await idle(5)
	var out := {}
	var named := {"bottom": m.ui_bp, "status": m.ui_status, "graph": m.ui_graph, "cube": m.ui_cube, "timeline": m.ui_timeline,
		"play_row": m.ui_play_row, "cards": m.ui_cards}
	for i in m.ui_side.size():
		named["side_%d" % i] = m.ui_side[i]
	for k in named:
		var c: Control = named[k]
		# a hidden panel: only that it is hidden (its rect is not on screen, and Godot does not lay it out)
		out[k] = ([true, c.get_global_rect()] if c.is_visible_in_tree() else [false]) if c != null else null
		if c != null and c == m.ui_side_of.get("left") and c.is_visible_in_tree():   # round 36 (RR6): the browser is as
			var r := c.get_global_rect()                                           # tall as its rows (a weapon out adds
			out[k] = [true, r.position, r.size.x]                                  # two): its place and width, not its height
	out["camera"] = [snappedf(m.cam.v_offset, 1e-5), snappedf(m.cam.h_offset, 1e-5)]
	return out


func visit(state: String, what: String) -> void:
	var now := await layout()
	if not first.has(state):
		first[state] = now
		var shown := now.keys().filter(func(k): return now[k] is Array and now[k][0] is bool and now[k][0])
		ok(shown.size() >= 4, "%s: %s - recorded (%d panels shown)" % [state, what, shown.size()])
		return
	var diff := []
	for k in now:
		if var_to_str(now[k]) != var_to_str(first[state][k]):
			diff.append([k, first[state][k], now[k]])
	ok(diff.is_empty(), "%s again: %s - every panel's rect and the camera's centring as the first time (differ: %s; weapon out %s)" % [state, what, diff, m.B.wep_on])


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


func open_combo() -> void:
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 1.0
	m._refresh()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.ov.graph_on = true
	await visit("EMPTY", "at start")
	open_combo()
	await visit("SCENE", "combo3 opened")
	ok(m.ui_scene_btn.is_visible_in_tree(), "  the Scene menu (New empty scene is its item) is on screen")
	await click(m.ui_scene_btn)
	m.ui_scene_btn.get_popup().hide()
	m._scene_menu_pick(3)
	await idle(3)
	await visit("EMPTY", "New empty scene clicked")
	open_combo()
	await visit("SCENE", "combo3 opened again")
	while m.S.cards.size() > 0:
		m._card_del(m.S.cards.size() - 1)
	await visit("EMPTY", "every card deleted")
	open_combo()
	await visit("SCENE", "combo3 a third time")
	print("EMPTY BACK: %d failed" % fails)
	quit(1 if fails > 0 else 0)
