## godot --path . -s tests/graph_read_test.gd     (GATES DD2, UPGRADES #44; a real window, real mouse motion)
## A SPEED GRAPH YOU CAN READ: combo3, the speed graph on. The axis ticks: every 0.5 s up to 6 s, every 1 s past it,
## from 0, none past the end. REAL mouse moves (no button) over the graph at 5 places: the readout's time is the time
## under the mouse, and its three speeds are the curves at that time, interpolated here independently (within 0.01
## m/s). A move off the graph: no readout. A press still scrubs. A screenshot of the hover goes to %TEMP%/poser_shots.
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


func motion(p: Vector2, mask := 0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = mask
	root.push_input(e)
	await idle(2)


## the curve at t, interpolated here (not by main.graph_value)
func curve(row: String, t: float) -> float:
	var ts: Array = m.ov.curves["t"]
	var s: Array = m.ov.curves[row]
	var i := ts.bsearch(t)
	if i <= 0:
		return float(s[0])
	if i >= ts.size():
		return float(s[-1])
	return float(s[i - 1]) + (float(s[i]) - float(s[i - 1])) * (t - float(ts[i - 1])) / (float(ts[i]) - float(ts[i - 1]))


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
	m._refresh()
	await idle(6)
	var t1: Array = m.graph_ticks(4.67)
	var t2: Array = m.graph_ticks(8.2)
	var t3: Array = m.graph_ticks(6.0)
	ok(t1.size() == 10 and t1[0] == 0.0 and t1[-1] == 4.5 and t2.size() == 9 and t2[-1] == 8.0 and t2[1] == 1.0 and t3[-1] == 6.0 and t3[1] == 0.5,
		"1 the axis: 4.67 s -> %d ticks 0..%.1f by 0.5; 8.2 s -> %d ticks 0..%.0f by 1; 6 s -> ends on 6 by 0.5" % [t1.size(), t1[-1], t2.size(), t2[-1]])
	var g: Control = m.ui_graph
	ok(g.is_visible_in_tree() and not m.ov.curves.is_empty(), "   the graph is on screen with curves (%s)" % g.get_global_rect())
	var T: float = m.ov.curves["t"][-1]
	var lw := 118.0
	var worst := 0.0
	var tworst := 0.0
	var bad := []
	for f in [0.05, 0.3, 0.5, 0.77, 0.98]:
		var lx: float = lw + (g.size.x - lw - 8.0) * f
		await motion(g.get_global_transform() * Vector2(lx, g.size.y * 0.5))
		var txt: String = m.graph_readout()
		var parts := txt.replace("m/s", "").split(" ", false)   # "t s tip v hips v head v"
		if parts.size() < 8:
			bad.append("readout '%s'" % txt)
			continue
		var want_t: float = f * T
		tworst = maxf(tworst, absf(float(parts[0]) - want_t))
		for r in [["tip", 3], ["hips", 5], ["head", 7]]:
			worst = maxf(worst, absf(float(parts[r[1]]) - curve(r[0], want_t)))
		if f == 0.5:
			var shots := OS.get_environment("TEMP").replace("\\", "/") + "/poser_shots"
			DirAccess.make_dir_recursive_absolute(shots)
			root.get_texture().get_image().save_png(shots + "/graph_hover.png")
	ok(bad.is_empty() and tworst <= 0.006 and worst <= 0.01, "2 real mouse moves at 5 places: the readout's time within %.3f s of the mouse's, its speeds within %.4f m/s of the curves (bad: %s); e.g. '%s'" % [tworst, worst, bad, m.graph_readout()])
	await motion(g.get_global_transform() * Vector2(g.size.x * 0.5, -60.0))
	ok(m.graph_readout() == "" and m._graph_hover < 0.0, "3 the mouse moved off the graph: no readout")
	var p := g.get_global_transform() * Vector2(lw + (g.size.x - lw - 8.0) * 0.25, g.size.y * 0.5)
	await motion(p)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await idle(2)
	ok(absf(m.playhead - 0.25 * T) < 0.02, "4 a press still scrubs: the playhead at %.2f s (a quarter of %.2f)" % [m.playhead, T])
	print("GRAPH READ: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
