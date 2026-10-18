## godot --path . -s tests/dope_sheet_test.gd     (GATES XX3; needs a window: the real poser, real mouse events on the sheet)
## The DOPE SHEET (scripts/dope_sheet.gd). Opened by the registry command "Dope sheet". Bars:
##   - 8 rows, every Body.BODY joint in exactly one; each card diamond and part-key diamond is within 1 px of its key time;
##   - a REAL drag of N frames (mouse down, motion, up on the canvas) moves the card's arrival by N / fps (1e-6), the
##     later cards and a marker follow by the same, one undo step; Ctrl+Z puts it back;
##   - a card's type (card["ktype"], only when not "key") draws four different diamonds, round-trips save / load / mirror,
##     is one undo step, and a scene with no types saves byte for byte as before.
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


func mouse(p: Vector2, down: bool, motion := false) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
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


## a real drag of the card diamond i by dx pixels, in a few motion steps
func drag_card(cv: Control, i: int, dx: float) -> void:
	var d := diamond(cv, i)
	var p0: Vector2 = cv.get_global_rect().position + Vector2(d["x"], d["y"])
	await mouse(p0, true)
	for k in 4:
		await mouse(p0 + Vector2(dx * float(k + 1) / 4.0, 0), false, true)
	await mouse(p0 + Vector2(dx, 0), false)
	await idle(2)


func diamond(cv: Control, i: int) -> Dictionary:
	for d in cv.diamonds():
		if d["row"] == -1 and d["i"] == i:
			return d
	return {}


func legs(thigh: float, calf: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for sd in ["_l", "_r"]:
		R.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		R.set_ang("calf" + sd, Vector3(calf, 0, 0))
	R.fk()
	return R.to_dict()


func ink_count(img: Image, c: Vector2, bg: Color) -> int:
	var n := 0
	for y in range(int(c.y) - 11, int(c.y) + 12):
		for x in range(int(c.x) - 11, int(c.x) + 12):
			if absf(img.get_pixel(x, y).r - bg.r) + absf(img.get_pixel(x, y).g - bg.g) + absf(img.get_pixel(x, y).b - bg.b) > 0.1:
				n += 1
	return n


func command(id: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["id"] == id:
			return c
	return {}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_dope"
	var pose := [[0, 0], [50, 90], [10, 20], [50, 90], [0, 0]]
	var mv := [0.3, 0.3, 0.2855, 0.2855, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.add("c%d" % i, legs(pose[i][0], pose[i][1]))
		S.cards[i]["move"] = mv[i]
		S.cards[i]["hold"] = hd[i]
	m.S = S
	m._rebuild_cards()
	m.sel_card = 2
	m._refresh()
	await idle(2)

	# the byte baseline: the scene as saved with no type anywhere
	var base_json := JSON.stringify(S.to_dict(m.B))
	ok(not base_json.contains("ktype"), "a scene with no types writes no ktype at all (%d bytes)" % base_json.length())

	# --- open it through the registry
	ok(not command("dope_sheet").is_empty() and not command("cycle_card_key_type").is_empty(), "registry has 'Dope sheet' and 'Cycle card key type'")
	ok(bool(command("cycle_card_key_type").get("edits", false)) and not bool(command("dope_sheet").get("edits", true)), "the type command is marked edits, the opener is not")
	command("dope_sheet")["run"].call()
	await idle(4)
	ok(m.ui_dope != null and m.ui_dope.visible, "the Dope sheet command opens the panel")
	var cv: Control = m.ui_dope.canvas
	ok(cv.size.x > 300.0 and cv.size.y > 100.0, "  the canvas has room (%.0f x %.0f)" % [cv.size.x, cv.size.y])

	# --- rows
	var seen := {}
	for g in DopeSheet.GROUPS:
		for j in g[1]:
			seen[j] = int(seen.get(j, 0)) + 1
	var every := true
	for j in Body.BODY:
		every = every and int(seen.get(j, 0)) == 1
	ok(DopeSheet.GROUPS.size() == 8 and every and seen.size() == Body.BODY.size(), "%d rows; each of the %d body joints is in exactly one (%d placed)" % [DopeSheet.GROUPS.size(), Body.BODY.size(), seen.size()])

	# --- part keys on the arm_r and hands rows
	m.S.part_keys = {}
	PartKeys.put(m.S.part_keys, "upperarm_r", 0.5, Vector3(10, 0, 0))
	PartKeys.put(m.S.part_keys, "lowerarm_r", 0.5, Vector3(20, 0, 0))   # same time, same row: ONE diamond
	PartKeys.put(m.S.part_keys, "hand_l", 0.9, Vector3(5, 0, 0))
	await idle(3)
	var L: float = m.S.length()
	var ts: Array = m.S.times()
	var worst := 0.0
	for d in cv.diamonds():
		var want: float = cv.LBL + float(d["t"]) * (cv.size.x - cv.LBL - cv.PAD) / maxf(L, 0.5)
		worst = maxf(worst, absf(float(d["x"]) - want))
	for i in 5:
		var d := diamond(cv, i)
		worst = maxf(worst, absf(float(d["x"]) - (cv.LBL + float(ts[i][1]) * (cv.size.x - cv.LBL - cv.PAD) / maxf(L, 0.5))))
	ok(worst < 1.0, "every diamond's x is within 1 px of its key time (worst %.4f px, bar < 1)" % worst)
	var arm_r := 0
	var hands := 0
	var parts := []
	for d in cv.diamonds():
		if d["row"] >= 0:
			parts.append(d)
			if DopeSheet.GROUPS[d["row"]][0] == "arm_r":
				arm_r += 1
			if DopeSheet.GROUPS[d["row"]][0] == "hands":
				hands += 1
	ok(parts.size() == 2 and arm_r == 1 and hands == 1 and parts[0]["joints"].size() == 2, "part keys: %d diamonds (arm_r %d with %d joints, hands %d); two joints keyed together show once" % [parts.size(), arm_r, parts[0]["joints"].size(), hands])
	var card_ds := 0
	for d in cv.diamonds():
		if d["row"] == -1:
			card_ds += 1
	ok(card_ds == 5, "the card row has one diamond per card (%d of 5)" % card_ds)

	# --- a real drag of N frames; a marker in card 4's hold rides along
	m.S.part_keys = {}
	m.S.markers = Markers.from_list([{"t": float(ts[3][1]) + 0.05, "name": "m1", "kind": "note"}])
	var fps := float(m.S.fps)
	var t0: Array = m.S.times().duplicate(true)
	var mk0: float = m.S.markers[0]["t"]
	var u0: int = m.undo.size()
	var pps: float = cv.pps()
	var N := 5
	await drag_card(cv, 2, float(N) / fps * pps + 1.3)   # 1.3 px past 5 frames: still snaps to 5
	var t1: Array = m.S.times()
	var d_arr := float(t1[2][1]) - float(t0[2][1])
	ok(absf(d_arr - float(N) / fps) < 1e-6, "dragged card 3 by %d frames: its arrival moved %.9f s, bar %.9f s (1e-6)" % [N, d_arr, float(N) / fps])
	ok(absf(float(t1[3][1]) - float(t0[3][1]) - float(N) / fps) < 1e-6 and absf(float(t1[1][1]) - float(t0[1][1])) < 1e-9, "  later cards slid by the same, earlier ones did not (card 4 +%.6f, card 2 +%.9f)" % [float(t1[3][1]) - float(t0[3][1]), float(t1[1][1]) - float(t0[1][1])])
	ok(absf(float(m.S.markers[0]["t"]) - mk0 - float(N) / fps) < 0.001, "  the marker (stored to the ms) followed (+%.6f s, bar %.6f within 0.001)" % [float(m.S.markers[0]["t"]) - mk0, float(N) / fps])
	ok(m.undo.size() == u0 + 1, "  one undo step for the whole drag (%d)" % (m.undo.size() - u0))
	var x_after := float(diamond(cv, 2)["x"])
	ok(absf(x_after - (cv.LBL + float(t1[2][1]) * cv.pps())) < 1.0, "  the diamond is redrawn at the new time (within %.3f px)" % absf(x_after - (cv.LBL + float(t1[2][1]) * cv.pps())))
	m._undo()
	await idle(3)
	var t2: Array = m.S.times()
	ok(absf(float(t2[2][1]) - float(t0[2][1])) < 1e-9 and absf(float(m.S.markers[0]["t"]) - mk0) < 1e-9, "Ctrl+Z puts the arrival (%.9f vs %.9f) and the marker back" % [float(t2[2][1]), float(t0[2][1])])
	# a drag left by 3 frames
	pps = cv.pps()
	await drag_card(cv, 3, -3.0 / fps * pps)
	ok(absf((float(m.S.times()[3][1]) - float(t0[3][1])) + 3.0 / fps) < 1e-6, "dragged card 4 left 3 frames: arrival moved %.9f s, bar %.9f s" % [float(m.S.times()[3][1]) - float(t0[3][1]), -3.0 / fps])
	m._undo()
	await idle(2)
	# card 1 cannot be moved; a click picks
	var u1: int = m.undo.size()
	await drag_card(cv, 0, 40.0)
	ok(absf(float(m.S.times()[0][1])) < 1e-12 and m.undo.size() <= u1 + 1, "card 1 arrives at 0 and a drag does not move it (arrival %.6f)" % float(m.S.times()[0][1]))
	m.sel_card = 0
	var dd := diamond(cv, 4)
	var pc: Vector2 = cv.get_global_rect().position + Vector2(dd["x"], dd["y"])
	await mouse(pc, true, false)
	await mouse(pc, false, false)
	await idle(2)
	ok(m.sel_card == 4, "a click on a card diamond picks that card (sel_card %d, bar 4)" % m.sel_card)

	# --- types
	m.sel_card = 2
	base_json = JSON.stringify(m.S.to_dict(m.B))   # the baseline with the markers and part keys as they are now
	var ud: int = m.undo.size()
	var kinds := []
	for k in 4:
		command("cycle_card_key_type")["run"].call()
		kinds.append(DopeSheet.kind_of(m.S.cards[2]))
	ok(kinds == ["breakdown", "moving_hold", "extreme", "key"], "Cycle card key type: %s" % str(kinds))
	ok(m.undo.size() == ud + 4 and not m.S.cards[2].has("ktype"), "  one undo step each (%d for 4); back to a key the field is gone" % (m.undo.size() - ud))
	ok(JSON.stringify(m.S.to_dict(m.B)) == base_json, "  a scene typed and then returned to key saves byte for byte as the baseline")
	m.S.cards[1]["ktype"] = "breakdown"
	m.S.cards[2]["ktype"] = "moving_hold"
	m.S.cards[3]["ktype"] = "extreme"
	m._refresh()
	await idle(4)
	var img := root.get_texture().get_image()
	var bg := Tok.c("tl_bg")
	var counts := []
	for i in [0, 1, 2, 3]:
		var d := diamond(cv, i)
		var c: Vector2 = cv.get_global_rect().position + Vector2(d["x"], d["y"])
		counts.append(ink_count(img, c, bg))
	var uniq := {}
	for c in counts:
		uniq[c] = true
	ok(uniq.size() == 4 and counts[3] > counts[0] and counts[1] < counts[0], "key / breakdown / moving hold / extreme draw four different shapes (ink pixels %s)" % str(counts))
	# round trip
	var d: Dictionary = m.S.to_dict(m.B)
	ok(d["cards"][1].get("ktype", "") == "breakdown" and d["cards"][2].get("ktype", "") == "moving_hold" and not d["cards"][0].has("ktype") and not d["cards"][4].has("ktype"), "the file holds ktype only on typed cards")
	var back := Scene.new()
	back.from_dict(JSON.parse_string(JSON.stringify(d)))
	var rt := true
	for i in 5:
		rt = rt and DopeSheet.kind_of(back.cards[i]) == DopeSheet.kind_of(m.S.cards[i])
	ok(rt, "save then load: all 5 types come back (%s)" % str(back.cards.map(func(c): return DopeSheet.kind_of(c))))
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mc := Scene.mirror_card(d["cards"][3], M)
	ok(mc.get("ktype", "") == "extreme" and not Scene.mirror_card(d["cards"][0], M).has("ktype"), "mirror keeps the type (card 4 '%s') and adds none" % mc.get("ktype", ""))
	# a bad type in a file is ignored
	var bad: Dictionary = JSON.parse_string(JSON.stringify(d))
	bad["cards"][0]["ktype"] = "bogus"
	var bs := Scene.new()
	bs.from_dict(bad)
	ok(not bs.cards[0].has("ktype"), "an unknown type in a file is dropped")
	# undo restores the type
	m.sel_card = 4
	var u2: int = m.undo.size()
	m._ktype_set("extreme")
	ok(m.S.cards[4].get("ktype", "") == "extreme" and m.undo.size() == u2 + 1, "the Extreme button sets card 5 in one undo step")
	m._undo()
	ok(not m.S.cards[4].has("ktype"), "Ctrl+Z takes the type back")
	var u3: int = m.undo.size()
	m._ktype_set("key")
	ok(m.undo.size() == u3 and String(m.ui_status.text).contains("already"), "setting the type it already has: no undo step, says why ('%s')" % m.ui_status.text)
	print("DOPE SHEET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
