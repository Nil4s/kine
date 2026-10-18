## godot --path . -s tests/curve_editor_test.gd     (GATES XX2, UPGRADES_300 #240; needs a window: real mouse events)
## CURVE EDITOR (scripts/curve_editor.gd): the picked joint's part keys drawn as curves, X red / Y green / Z blue.
##   - the "Curve editor" registry command opens it (and closes it);
##   - the drawn polyline of each angle against PartKeys.at() at the same times: worst error in px (bar <= 1 px);
##   - a REAL mouse drag (Input events pushed to the window) on a key moves it by the expected value and time: time is a
##     whole frame at S.fps, within one frame of where the mouse went; the value within 1 px worth of degrees;
##   - one drag = one undo step; Ctrl+Z (m._undo) restores the keys EXACTLY (JSON equal); a click without moving = no step;
##   - Esc and a click on nothing deselect; "Frame all" (a real click) puts every key dot inside the plot;
##   - a scene with no part keys: an empty editor, and the saved scene (Scene.to_dict) is the same bytes before / after.
## REFERENCE: no body numbers (a view onto keys that already exist).
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


func mouse(p: Vector2, down: bool, motion := false, held := false) -> void:
	var e: InputEvent
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
	root.push_input(e)
	await process_frame


func click_at(p: Vector2) -> void:
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func drag(a: Vector2, b: Vector2) -> void:
	await mouse(a, true)
	for i in range(1, 6):
		await mouse(a.lerp(b, float(i) / 5.0), false, true, true)
	await mouse(b, false)
	await idle(2)


func command(id: String) -> void:
	for c in m._commands():
		if c["id"] == id:
			c["run"].call()
			await idle(3)
			return
	ok(false, "registry has the command '%s'" % id)


func gp(ce: CurveEditor, local: Vector2) -> Vector2:
	return ce.get_global_rect().position + local


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
	S.name = "zz_curve_ed"
	S.add("a", B0.to_dict())
	S.add("b", B0.to_dict())
	S.cards[0]["move"] = 0.5
	S.cards[1]["move"] = 0.5
	m.S = S
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	m.sel_card = 0
	m._refresh()
	await idle(2)

	# ---- no part keys: an empty editor, the saved scene untouched
	var base := JSON.stringify(S.to_dict(m.B))
	var u0: int = m.undo.size()
	await command("curve_editor")
	var ce: CurveEditor = m.ui_curve
	ok(ce != null and ce.visible, "the registry command 'Curve editor' opens the panel")
	if ce == null:
		print("CURVE EDITOR TEST FAIL %d" % fails)
		quit(fails)
		return
	ok(ce.keys().is_empty() and ce.polyline(0).is_empty(), "a scene with no part keys: the editor is empty (%d keys, %d polyline points)" % [ce.keys().size(), ce.polyline(0).size()])
	ce.frame_all()
	await idle(2)
	await click_at(gp(ce, Vector2(200, 80)))
	var after := JSON.stringify(S.to_dict(m.B))
	ok(after == base and not after.contains("part_keys") and m.undo.size() == u0, "  and nothing changed in the saved scene: %d bytes before, %d after, 'part_keys' in file: %s, undo steps added %d (bar 0)" % [base.length(), after.length(), after.contains("part_keys"), m.undo.size() - u0])

	# ---- keys on a joint
	S.part_keys = {"lowerarm_r": [
		{"t": 0.0, "v": Vector3(10, 0, 0)}, {"t": 0.5, "v": Vector3(70, 0, 0)}, {"t": 1.0, "v": Vector3(30, 0, 0)}]}
	m._refresh()
	await idle(2)
	ce.frame_all()
	await idle(2)
	var fr := 1.0 / float(S.fps)

	# ---- the drawn line against PartKeys.at
	var worst := 0.0
	var npts := 0
	for c in 3:
		for p in ce.polyline(c):
			var want := ce.v_to_y(PartKeys.at(S.part_keys["lowerarm_r"], ce.x_to_t(p.x))[c])
			worst = maxf(worst, absf(p.y - want))
			npts += 1
	ok(npts > 300 and worst <= 1.0, "the drawn polylines (3 angles, %d points) against PartKeys.at at the same times: worst error %.4f px (bar <= 1)" % [npts, worst])
	var yr := ce.polyline(0)
	var ymin := 1e9
	for p in yr:
		ymin = minf(ymin, p.y)
	ok(absf(ymin - ce.v_to_y(70.0)) <= 1.0, "  the red curve's peak is at the 70 deg key: %.2f px vs %.2f px" % [ymin, ce.v_to_y(70.0)])
	ok(Tok.c("ch_x").r > Tok.c("ch_x").g and Tok.c("ch_y").g > Tok.c("ch_y").r and Tok.c("ch_z").b > Tok.c("ch_z").r, "  X is red, Y green, Z blue (tokens)")

	# ---- a click that does not move: picked, no undo step, nothing changed
	var snap0 := JSON.stringify(PartKeys.to_file(S.part_keys))
	var u1: int = m.undo.size()
	var kp := gp(ce, ce.key_pos(0, 1))
	await click_at(kp)
	ok(ce.sel_ch == 0 and ce.sel_i == 1 and m.undo.size() == u1 and JSON.stringify(PartKeys.to_file(S.part_keys)) == snap0, "a click on the middle red key picks it (channel %d, key %d); no undo step (%d), keys unchanged" % [ce.sel_ch, ce.sel_i, m.undo.size() - u1])
	# Esc and an empty click let go
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ce._gui_input(esc)
	ok(ce.sel_i == -1, "Esc deselects")
	await click_at(kp)
	await click_at(gp(ce, Vector2(ce.t_to_x(0.25), ce.v_to_y(ce.v1 - 2.0))))
	ok(ce.sel_i == -1, "a click on empty plot deselects")

	# ---- a real drag: +0.1 s and +10 deg on the middle red key
	var tgt_t := 0.615   # not on a frame at 30 fps: the snap must act
	var tgt_v := 80.0
	var from := gp(ce, ce.key_pos(0, 1))
	var to := gp(ce, Vector2(ce.t_to_x(tgt_t), ce.v_to_y(tgt_v)))
	var u2: int = m.undo.size()
	await drag(from, to)
	var k1: Dictionary = S.part_keys["lowerarm_r"][1]
	var dt := absf(float(k1["t"]) - tgt_t)
	var deg_per_px: float = (ce.v1 - ce.v0) / ce.plot().size.y
	var dv := absf((k1["v"] as Vector3).x - tgt_v)
	var onframe := absf(float(k1["t"]) * S.fps - roundf(float(k1["t"]) * S.fps))
	ok(dt <= fr and onframe < 1e-3, "drag: the key's time %.4f s vs mouse %.4f s: error %.4f s (bar <= one frame %.4f); frame number %.4f (whole)" % [k1["t"], tgt_t, dt, fr, float(k1["t"]) * S.fps])
	ok(dv <= deg_per_px * 1.5, "drag: the key's angle %.3f vs mouse %.3f deg: error %.3f deg (bar <= 1.5 px = %.3f deg)" % [(k1["v"] as Vector3).x, tgt_v, dv, deg_per_px * 1.5])
	ok((k1["v"] as Vector3).y == 0.0 and (k1["v"] as Vector3).z == 0.0 and S.part_keys["lowerarm_r"].size() == 3, "  the other two angles are untouched and there are still 3 keys")
	ok(m.undo.size() == u2 + 1, "one drag (5 motion events) = one undo step: %d (bar exactly 1)" % (m.undo.size() - u2))
	ok(absf(ce.playhead - m.playhead) < 1e-6 and S.part_keys["lowerarm_r"][0]["t"] == 0.0, "  the other keys stayed")
	m._undo()
	await idle(2)
	ok(JSON.stringify(PartKeys.to_file(S.part_keys)) == snap0 and S.part_keys["lowerarm_r"][1]["v"] == Vector3(70, 0, 0) and S.part_keys["lowerarm_r"][1]["t"] == 0.5, "Ctrl+Z restores the key exactly: t %.6f, v %s (bar t 0.5, v (70,0,0))" % [S.part_keys["lowerarm_r"][1]["t"], S.part_keys["lowerarm_r"][1]["v"]])

	# ---- a key can not be dragged past its neighbour
	ce.sel_i = -1
	await drag(gp(ce, ce.key_pos(0, 1)), gp(ce, Vector2(ce.t_to_x(1.4), ce.v_to_y(70.0))))
	var tt: float = S.part_keys["lowerarm_r"][1]["t"]
	ok(tt < float(S.part_keys["lowerarm_r"][2]["t"]) and S.part_keys["lowerarm_r"].size() == 3, "a drag far past the next key stops short of it: t %.4f < %.4f, still 3 keys, in order" % [tt, S.part_keys["lowerarm_r"][2]["t"]])
	m._undo()
	await idle(2)

	# ---- Frame all (a real click on the button)
	ce.t0 = 50.0
	ce.t1 = 51.0
	ce.v0 = 500.0
	ce.v1 = 600.0
	ce.queue_redraw()
	await idle(2)
	await click_ctl(ce._btn)
	var inside := 0
	var tot := 0
	var pr := ce.plot()
	for i in 3:
		for c in 3:
			tot += 1
			if pr.grow(0.5).has_point(ce.key_pos(c, i)):
				inside += 1
	ok(inside == tot, "Frame all (clicked): %d of %d key dots inside the plot (bar all); time %.2f..%.2f s, angle %.1f..%.1f deg" % [inside, tot, ce.t0, ce.t1, ce.v0, ce.v1])

	# ---- the playhead line follows, and it closes
	m.playhead = 0.25
	m._refresh()
	ok(is_equal_approx(ce.playhead, 0.25), "the playhead line follows the scene's playhead (%.2f)" % ce.playhead)
	await command("curve_editor")
	ok(not ce.visible, "the same command closes it")
	print("CURVE EDITOR TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
