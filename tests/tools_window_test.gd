## godot --path . -s tests/tools_window_test.gd     (GATES L3, L4, L6, L7, L8; needs a window)
## Every "Animator tools" item in the real poser window: mirror pose (and Ctrl+Z), mirror scene (a new _wip file, the
## source untouched), spacing ghosts + speed graph (built once per scene change, never per frame), stepped preview
## (the body holds the card's pose mid-move; off = the in-between again), moving holds (one undo step).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func pos(m: Node) -> Dictionary:
	var out := {}
	for j in Body.ORDER:
		out[j] = m.B.P[j]
	return out


func far(a: Dictionary, b: Dictionary) -> float:
	var w := 0.0
	for j in a:
		w = maxf(w, (a[j] as Vector3).distance_to(b[j]))
	return w


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var src := "res://scenes/combo3.json"
	var file0 := FileAccess.get_file_as_string(src)
	m._load_scene(src)
	m._rebuild_cards()
	var ts: Array = m.S.times()

	# MIRROR POSE: the whole body, then Ctrl+Z
	m._card_pick(9)
	await process_frame
	var p0 := pos(m)
	var hand0: String = m.B.wep_hand
	m._tool(0)
	var moved := 0.0
	for j in Body.ORDER:
		moved = maxf(moved, (m.B.P[Body.twin(j)] as Vector3).distance_to(Vector3(-p0[j].x, p0[j].y, p0[j].z)))
	ok(moved < 1e-3 and m.B.wep_hand == Body.twin(hand0), "Mirror the pose: every joint on its twin reflected (%.3f mm), the weapon %s -> %s" % [moved * 1000.0, hand0, m.B.wep_hand])
	m._undo()
	ok(far(pos(m), p0) < 1e-4 and m.B.wep_hand == hand0, "  Ctrl+Z: the pose back (%.4f mm)" % (far(pos(m), p0) * 1000.0))

	# SPACING + GRAPH: one build per scene change, none per frame
	m.ov.mark_dirty()
	m._tool(1)
	m._tool(2)
	await process_frame
	var b0: int = m.ov.builds
	var ghosts: int = m.ov._space.size()
	for k in 30:
		m.playhead = 0.03 * k
		m._ps().apply(m.B, m.playhead)
		m._refresh()
	ok(ghosts > 40 and m.ov._space_mesh.visible, "spacing ghosts: %d stored (every 0.1 s over %.2f s), drawn around the playhead" % [ghosts, m.S.length()])
	ok(m.ov.builds == b0, "  30 playhead moves: %d rebuilds (the pass runs once per scene change)" % (m.ov.builds - b0))
	ok(m.ui_graph.visible and m.ov.curves["t"].size() > 100 and m.ov.curves["cards"].size() == m.S.cards.size(), "speed graph: shown, %d samples, %d card marks" % [m.ov.curves["t"].size(), m.ov.curves["cards"].size()])
	var hp: float = m.ov.curves["head"].max()
	var hi: int = m.ov.curves["head"].find(hp)
	ok(absf(m.ov.curves["t"][hi] - 3.1) < 0.1, "  the graph's head peak (%.1f m/s) sits at %.2f s: the lurch Check flags at 3.13 s" % [hp, m.ov.curves["t"][hi]])
	# a click on the graph moves the playhead
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = Vector2(118.0 + (m.ui_graph.size.x - 126.0) * 0.5, 30)
	m._graph_input(ev)
	ok(absf(m.playhead - m.S.length() * 0.5) < 0.05, "  clicking the middle of the graph -> playhead %.2f s (scene %.2f s)" % [m.playhead, m.S.length()])

	# STEPPED: mid-move the body is the last card's pose; off again = the in-between
	var t: float = lerpf(float(ts[2][0]), float(ts[2][1]), 0.5)   # half-way into card 3
	m.playhead = t
	m._tool(3)
	await process_frame
	var st := pos(m)
	m.ov.GB.from_dict(m.S.cards[1]["pose"])
	m.S._ground(m.ov.GB)
	var ref := {}
	for j in Body.ORDER:
		ref[j] = m.ov.GB.P[j]
	ok(far(st, ref) < 1e-3, "Stepped preview: at %.2f s (half-way into card 3) the body IS card 2's pose (%.3f mm)" % [t, far(st, ref) * 1000.0])
	m._tool(3)
	ok(far(pos(m), ref) > 0.02, "  off: the in-between is back (%.0f mm from card 2)" % (far(pos(m), ref) * 1000.0))

	# MOVING HOLDS: on with one undo step, saved; Ctrl+Z off
	m._tool(4)
	ok(m.S.moving_holds and m.S.to_dict(m.B).get("moving_holds", false), "Moving holds: on, and in the saved scene")
	m._undo()
	ok(not m.S.moving_holds, "  Ctrl+Z: off again")

	# MIRROR SCENE: a new file in _wip, opened; the source untouched
	m._tool(5)
	var out := "res://scenes/_wip/combo3_mirrored.json"
	ok(FileAccess.file_exists(out) and m.S.name == "combo3_mirrored" and m.S.cards.size() == 12, "Mirror the scene: %s written and open (%d cards)" % [out.get_file(), m.S.cards.size()])
	ok(FileAccess.get_file_as_string(src) == file0, "  combo3.json byte-identical")
	ok(not m.S.moving_holds, "  the mirror keeps the scene's settings (moving holds off, as combo3)")
	# the strong check: the mirrored scene PLAYS as the original reflected (x -> -x), every frame, tip and hips
	var O := Scene.new()
	O.from_dict(JSON.parse_string(file0))
	var GB: Body = m.ov.GB
	var worst := 0.0
	for i in int(O.length() * 60.0) + 1:
		O.apply(GB, i / 60.0)
		var tip: Vector3 = Overlays.tracked(GB)
		var hip: Vector3 = GB.P["pelvis"]
		m.S.apply(GB, i / 60.0)
		worst = maxf(worst, maxf(Vector3(-tip.x, tip.y, tip.z).distance_to(Overlays.tracked(GB)), Vector3(-hip.x, hip.y, hip.z).distance_to(GB.P["pelvis"])))
	ok(worst < 0.002, "  it plays as the original reflected: worst tip/hips miss %.2f mm over %d frames" % [worst * 1000.0, int(O.length() * 60.0) + 1])
	var fs: Array = Rulebook.check(m.S, GB)
	var fs0: Array = Rulebook.check(O, GB)
	var names := func(a: Array) -> Array: return a.map(func(x): return "%s %.2f" % [x["rule"], x["t"]])
	ok(str(names.call(fs)) == str(names.call(fs0)), "  and Check grades it the same: %s" % str(names.call(fs)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
	print("TOOLS WINDOW %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
