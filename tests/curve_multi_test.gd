## godot --path . -s tests/curve_multi_test.gd     (round 48, GATES DD0, UPGRADES_300 #243; a window: real mouse events)
## MANY KEYS AT ONCE in the curve editor. Five keys on the right forearm (0, 0.2, 0.45, 0.7, 1.0 s; bend 10/40/70/40/10,
## side 0, twist 5); three cards (0, 0.5, 1.0 s).
##   1 a box dragged on empty plot round the three middle BEND dots selects exactly those three
##   2 the control: a plain click on an unselected dot selects only it; Shift+click adds a dot, Shift+click again removes it
##   3 MOVE: the box selection dragged by the middle key +0.115 s / +5 deg: every selected key moves by the same whole-
##     frame time change and +5 deg on bend, the unselected keys and the other angles stay; one undo step; Ctrl+Z exact
##   4 Ctrl+drag (one key, 0.7 s, toward 0.55 s): its time lands on the nearest card (0.5 s)
##   5 a selected key cannot pass an unselected neighbour: the three dragged +0.6 s stop short of the 1.0 s key
##   6 Alt+drag SCALES: 75 px left = time x0.5 about the playhead (0.45 s): 0.2 -> 0.325, 0.7 -> 0.575 (on whole frames);
##     then 75 px up = angles x1.5 about the selection's mean bend (50): 40 -> 35, 70 -> 80; one undo step each
extends SceneTree

var fails := 0
var m: Node
var ce: CurveEditor


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, motion := false, held := false, mods := "") -> void:
	var e: InputEventWithModifiers
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	e.shift_pressed = mods.contains("shift")
	e.ctrl_pressed = mods.contains("ctrl")
	e.alt_pressed = mods.contains("alt")
	root.push_input(e)
	await process_frame


func click_at(p: Vector2, mods := "") -> void:
	await mouse(p, true, false, false, mods)
	await mouse(p, false, false, false, mods)
	await idle(2)


func drag(a: Vector2, b: Vector2, mods := "") -> void:
	await mouse(a, true, false, false, mods)
	for i in range(1, 6):
		await mouse(a.lerp(b, float(i) / 5.0), false, true, true, mods)
	await mouse(b, false, false, false, mods)
	await idle(2)


func gp(local: Vector2) -> Vector2:
	return ce.get_global_rect().position + local


func dot(c: int, i: int) -> Vector2:
	return gp(ce.key_pos(c, i))


func ks() -> Array:
	return m.S.part_keys["lowerarm_r"]


func box_middle() -> void:
	ce.picked = []
	var a := gp(Vector2(ce.t_to_x(0.1), ce.v_to_y(78.0)))
	var b := gp(Vector2(ce.t_to_x(0.8), ce.v_to_y(30.0)))
	await drag(a, b)


func picked_str() -> String:
	var p := ce.picked.duplicate()
	p.sort()
	return str(p)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B0.fk()
	var S := Scene.new()
	S.name = "zz_curve_multi"
	S.fps = 30
	for n in ["a", "b", "c"]:
		S.add(n, B0.to_dict())
	for c in S.cards:
		c["move"] = 0.5
		c["hold"] = 0.0
	S.part_keys = {"lowerarm_r": []}
	for kv in [[0.0, 10.0], [0.2, 40.0], [0.45, 70.0], [0.7, 40.0], [1.0, 10.0]]:
		S.part_keys["lowerarm_r"].append({"t": kv[0], "v": Vector3(kv[1], 0, 5)})
	m.S = S
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	m.sel_card = 0
	m.playhead = 0.45
	m._refresh()
	await idle(2)
	for c in m._commands():
		if c["id"] == "curve_editor":
			c["run"].call()
	await idle(3)
	ce = m.ui_curve
	ce.frame_all()
	await idle(2)
	var cts: Array = ce.card_times
	print("     card times %s, fps %d" % [cts, S.fps])
	var fr := 1.0 / 30.0
	# 1 box
	await box_middle()
	ok(picked_str() == "[[0, 1], [0, 2], [0, 3]]", "1 a box round the three middle bend dots selects them: %s" % picked_str())
	# 2 control + shift
	await click_at(dot(0, 4))
	var one := picked_str()
	await box_middle()
	await click_at(dot(2, 4), "shift")
	var four := ce.picked.size()
	await click_at(dot(2, 4), "shift")
	ok(one == "[[0, 4]]" and four == 4 and picked_str() == "[[0, 1], [0, 2], [0, 3]]", "2 a plain click selects only its dot (%s); Shift+click adds (%d dots), Shift+click again removes (%s)" % [one, four, picked_str()])
	# 3 move the box selection by the middle key
	var before := JSON.stringify(PartKeys.to_file(S.part_keys))
	var t0s := ks().map(func(k): return float(k["t"]))
	var v0s := ks().map(func(k): return k["v"])
	var u0: int = m.undo.size()
	await drag(dot(0, 2), gp(Vector2(ce.t_to_x(0.45 + 0.115), ce.v_to_y(75.0))))
	var dts := []
	var dvs := []
	for i in 5:
		dts.append(snappedf(float(ks()[i]["t"]) - float(t0s[i]), 0.0001))
		dvs.append((ks()[i]["v"] as Vector3) - (v0s[i] as Vector3))
	var dt: float = dts[2]
	var deg_px: float = (ce.v1 - ce.v0) / ce.plot().size.y
	var same: bool = dts[1] == dt and dts[3] == dt and dts[0] == 0.0 and dts[4] == 0.0
	var frames := absf(float(ks()[2]["t"]) * 30.0 - roundf(float(ks()[2]["t"]) * 30.0)) < 1e-3
	var vals := true
	for i in 5:
		var d: Vector3 = dvs[i]
		var want := 5.0 if i in [1, 2, 3] else 0.0
		vals = vals and absf(d.x - want) <= deg_px * 1.5 and d.y == 0.0 and d.z == 0.0
	ok(same and frames and absf(dt - 0.115) <= fr and vals and m.undo.size() == u0 + 1,
		"3 move: time changes %s (the three selected the same, on whole frames, the ends 0), bend +%.2f deg on the selected only, one undo step (%d)" % [dts, (dvs[2] as Vector3).x, m.undo.size() - u0])
	m._undo()
	await idle(2)
	ok(JSON.stringify(PartKeys.to_file(S.part_keys)) == before, "  Ctrl+Z restores all five keys exactly")
	# 4 Ctrl snap to a card (the box selection cleared first: a click on an already selected dot keeps the selection)
	ce.picked = []
	await click_at(dot(0, 3))
	await drag(dot(0, 3), gp(Vector2(ce.t_to_x(0.55), ce.key_pos(0, 3).y)), "ctrl")
	ok(absf(float(ks()[3]["t"]) - 0.5) < 1e-6, "4 Ctrl+drag toward 0.55 s: the key lands on the card at %.4f s (cards %s)" % [ks()[3]["t"], cts])
	m._undo()
	await idle(2)
	# 5 not past a neighbour
	await box_middle()
	await drag(dot(0, 2), gp(Vector2(ce.t_to_x(1.05), ce.key_pos(0, 2).y)))
	ok(float(ks()[3]["t"]) < 1.0 and float(ks()[4]["t"]) == 1.0 and ks().size() == 5, "5 the three dragged +0.6 s stop short of the 1.0 s key: last selected at %.4f s, the neighbour still at %.2f, 5 keys" % [ks()[3]["t"], ks()[4]["t"]])
	m._undo()
	await idle(2)
	# 6 scale: time then angle
	await box_middle()
	ce.playhead = 0.45
	var u1: int = m.undo.size()
	var p := dot(0, 2)
	await drag(p, p + Vector2(-75, 0), "alt")
	var want1 := snappedf(0.45 + (0.2 - 0.45) * 0.5, fr)
	var want3 := snappedf(0.45 + (0.7 - 0.45) * 0.5, fr)
	var t_ok := absf(float(ks()[1]["t"]) - want1) < 1e-4 and absf(float(ks()[3]["t"]) - want3) < 1e-4 and float(ks()[2]["t"]) == 0.45
	p = dot(0, 2)   # the view may have moved with the keys: the dot where it is now
	await mouse(p + Vector2(0, 120), false, true)
	await idle(10)
	await drag(p, p + Vector2(0, -75), "alt")
	var b1: float = (ks()[1]["v"] as Vector3).x
	var b2: float = (ks()[2]["v"] as Vector3).x
	ok(t_ok and absf(b1 - 35.0) < 0.01 and absf(b2 - 80.0) < 0.01 and m.undo.size() == u1 + 2,
		"6 Alt+drag: 75 px left -> times %.4f / %.4f (want %.4f / %.4f, about the playhead); 75 px up -> bends %.2f / %.2f (want 35 / 80, about the mean 50); undo steps %d (bar 2)" % [ks()[1]["t"], ks()[3]["t"], want1, want3, b1, b2, m.undo.size() - u1])
	m.queue_free()
	print("CURVE MULTI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
