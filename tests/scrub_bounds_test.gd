## godot --path . -s tests/scrub_bounds_test.gd     (GATES Y3, UPGRADES #8; needs a window: real mouse events)
## SCRUB BOUNDS: press on the speed graph and drag (real mouse events) past its right end, out of the graph and on
## to the window's edge: the playhead holds at the scene's end, the time shown is the end, the body is the last
## frame; then on past its left end, into the left panel: the playhead holds at 0, the body the first frame; no error
## logged; a press in the label margin (left of the plot) reads 0, not a negative time.
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


func mouse(p: Vector2, kind: String) -> void:
	var e: InputEvent
	if kind == "move":
		var mm := InputEventMouseMotion.new()
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm.position = p
		mm.global_position = p
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = kind == "down"
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if kind == "down" else 0
		mb.position = p
		mb.global_position = p
		e = mb
	root.push_input(e)
	await process_frame


func pose_gap(a: Dictionary, b: Dictionary) -> float:
	var g := 0.0
	for j in b:
		g = maxf(g, ((a[j] as Vector3) - (b[j] as Vector3)).abs()[(a[j] - b[j]).abs().max_axis_index()])
	return g


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.ov.graph_on = true
	m.ov.mark_dirty()
	await idle(8)
	for i in 60:
		if not m.ov.curves.is_empty():
			break
		await idle(2)
	m._refresh()
	await idle(3)
	var gr: Rect2 = m.ui_graph.get_global_rect()
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var L: float = m._ps().length()
	ok(m.ui_graph.is_visible_in_tree() and not m.ov.curves.is_empty() and gr.size.x > 300, "0 the speed graph is up: %s, the scene %.3f s" % [gr, L])
	# the last frame and the first, as the body shows them
	m._ps().apply(m.B, L)
	var last: Dictionary = m.B.ang.duplicate(true)
	m._ps().apply(m.B, 0.0)
	var first: Dictionary = m.B.ang.duplicate(true)

	var mid := Vector2(gr.position.x + gr.size.x * 0.5, gr.get_center().y)
	await mouse(mid, "down")
	var t_mid: float = m.playhead
	for x in [gr.end.x - 20.0, gr.end.x - 2.0, gr.end.x + 40.0, vr.end.x - 1.0]:
		await mouse(Vector2(x, mid.y), "move")
	await idle(2)
	var T: float = m.ov.curves["t"][-1]
	ok(t_mid > 0.2 * L and t_mid < 0.8 * L, "1 a press in the middle of the graph: the playhead %.3f s of %.3f" % [t_mid, L])
	ok(absf(m.playhead - L) < 1e-6 and m.ui_time_lbl.text == "%.2f / %.2f s" % [L, L] and pose_gap(m.B.ang, last) < 1e-4,
		"2 dragged past the right end and out to the window's edge: the playhead holds at the end (%.4f; the graph's last sample %.4f, the scene %.4f), shown '%s', the body the last frame" % [m.playhead, T, L, m.ui_time_lbl.text])
	for x in [gr.position.x + 130.0, gr.position.x + 60.0, gr.position.x - 40.0, 1.0]:
		await mouse(Vector2(x, mid.y), "move")
	await idle(2)
	ok(m.playhead == 0.0 and m.ui_time_lbl.text == "0.00 / %.2f s" % L and pose_gap(m.B.ang, first) < 1e-4,
		"3 on past the left end, through the label margin and into the left panel: holds at 0 (%.4f), shown '%s', the body the first frame" % [m.playhead, m.ui_time_lbl.text])
	await mouse(Vector2(1.0, mid.y), "up")
	await mouse(Vector2(gr.position.x + 30.0, mid.y), "down")
	await mouse(Vector2(gr.position.x + 30.0, mid.y), "up")
	ok(m.playhead == 0.0, "4 a press in the label margin (left of the plot): 0, not a negative time (%.4f)" % m.playhead)
	print("SCRUB BOUNDS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
