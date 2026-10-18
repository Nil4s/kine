## godot --path . -s tests/dope_copy_test.gd     (round 49, GATES NA0, UPGRADES_300 #252 + #253; a window: real mouse events)
## DOPE SHEET LEFTOVERS. Four cards (arrivals 0, 0.5, 1.0, 1.5 s; holds 0.1, 0.1, 0.1, 0) and part keys on the right
## forearm and the right upper arm at 0.4 s and 0.9 s (one "arm_r" diamond at each time), 30 fps.
##   1 Shift-drag card 1's diamond to 0.80 s (inside card 2's move 0.60..1.00): a copy arrives at 0.80 with card 1's pose;
##     every original card still arrives when it did (1e-6); 5 cards; one undo step; Ctrl+Z = the 4 cards byte for byte
##   2 Shift-drag onto a hold (0.55 s, inside card 1's hold 0.50..0.60): refused, nothing changes, no undo step, said why
##   3 drag the 0.4 s arm diamond +6 frames: both joints' keys at 0.6 s, values unchanged, the 0.9 s keys stay; one undo
##   4 drag it far right (to 1.3 s): it stops one frame short of the 0.9 s neighbour (0.8667 s), never onto or past it
##   5 Shift-drag the 0.9 s arm diamond to 1.2 s: the 0.9 keys stay AND copies (same values) sit at 1.2 s: 3 keys a joint
##   6 stepped preview on, card 2 a breakdown and card 3 a moving hold: the card row shows cards 0 and 1 only (key,
##     key); off again: all four
##   7 control: a plain drag of card 2's diamond still retimes it (+3 frames = +0.1 s arrival)
extends SceneTree

var fails := 0
var m: Node
var cv: Control


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, motion := false, shift := false) -> void:
	var e: InputEventWithModifiers
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
	e.shift_pressed = shift
	root.push_input(e)
	await process_frame


func drag_to(d: Dictionary, t: float, shift := false) -> void:
	var p0: Vector2 = cv.get_global_rect().position + Vector2(d["x"], d["y"])
	var p1: Vector2 = cv.get_global_rect().position + Vector2(cv.x_of(t), d["y"])
	await mouse(p0, true, false, shift)
	for k in 4:
		await mouse(p0.lerp(p1, float(k + 1) / 4.0), false, true, shift)
	await mouse(p1, false, false, shift)
	await idle(3)


func card_d(i: int) -> Dictionary:
	for d in cv.diamonds():
		if d["row"] == -1 and d["i"] == i:
			return d
	return {}


func part_d(t: float) -> Dictionary:
	for d in cv.diamonds():
		if d["row"] >= 0 and absf(float(d["t"]) - t) < 1e-4:
			return d
	return {}


func arrivals() -> Array:
	return m.S.times().map(func(x): return snappedf(float(x[1]), 0.000001))


func arm_ts(j: String) -> Array:
	return m.S.part_keys[j].map(func(k): return snappedf(float(k["t"]), 0.0001))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.name = "zz_dope_copy"
	S.fps = 30
	for i in 4:
		B.ang["upperarm_r"] = Vector3(10.0 * i, 20.0 * i, 0)
		B.fk()
		S.add("c%d" % i, B.to_dict())
		S.cards[i]["move"] = 0.4
		S.cards[i]["hold"] = 0.1 if i < 3 else 0.0
	S.part_keys = {"lowerarm_r": [{"t": 0.4, "v": Vector3(30, 0, 0)}, {"t": 0.9, "v": Vector3(60, 0, 0)}],
		"upperarm_r": [{"t": 0.4, "v": Vector3(5, 10, 0)}, {"t": 0.9, "v": Vector3(15, 20, 0)}]}
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m._refresh()
	await idle(2)
	for c in m._commands():
		if c["id"] == "dope_sheet":
			c["run"].call()
	await idle(4)
	cv = m.ui_dope.canvas
	var a0 := arrivals()
	print("     arrivals %s" % [a0])
	# 1 copy
	var before := JSON.stringify(S.to_dict(m.B))
	var u0: int = m.undo.size()
	await drag_to(card_d(1), 0.8, true)
	var a1 := arrivals()
	var copy_ok: bool = S.cards.size() == 5 and absf(float(a1[2]) - 0.8) < 1e-6 and JSON.stringify(S.cards[2]["pose"]) == JSON.stringify(S.cards[1]["pose"])
	var kept: bool = a1[0] == a0[0] and a1[1] == a0[1] and a1[3] == a0[2] and a1[4] == a0[3]
	ok(copy_ok and kept and m.undo.size() == u0 + 1, "1 Shift-drag card 1 to 0.80 s: arrivals %s (was %s), the copy at 0.80 with card 1's pose %s, the others unchanged %s, undo steps %d" % [a1, a0, copy_ok, kept, m.undo.size() - u0])
	m._undo()
	await idle(3)
	ok(JSON.stringify(S.to_dict(m.B)) == before, "  Ctrl+Z: the 4 cards byte for byte")
	# 2 onto a hold
	var u1: int = m.undo.size()
	await drag_to(card_d(1), 0.55, true)
	var said: String = m.ui_status.text
	ok(S.cards.size() == 4 and m.undo.size() == u1 and JSON.stringify(S.to_dict(m.B)) == before and said.contains("NOT COPIED"), "2 a copy dropped on a hold (0.55 s): refused, 4 cards, no undo step; said: %s" % said.left(110))
	# 3 move part diamond +6 frames
	var u2: int = m.undo.size()
	await drag_to(part_d(0.4), 0.6)
	var la := arm_ts("lowerarm_r")
	var ua := arm_ts("upperarm_r")
	var vals: bool = S.part_keys["lowerarm_r"][0]["v"] == Vector3(30, 0, 0) and S.part_keys["upperarm_r"][0]["v"] == Vector3(5, 10, 0)
	ok(la == [0.6, 0.9] and ua == [0.6, 0.9] and vals and m.undo.size() == u2 + 1, "3 the 0.4 s arm diamond dragged +6 frames: forearm %s, upper arm %s, values unchanged %s, undo steps %d" % [la, ua, vals, m.undo.size() - u2])
	m._undo()
	await idle(3)
	# 4 not past the neighbour
	await drag_to(part_d(0.4), 1.3)
	la = arm_ts("lowerarm_r")
	ok(absf(float(la[0]) - 0.8667) < 1e-3 and la.size() == 2 and float(la[0]) < float(la[1]), "4 dragged toward 1.3 s it stops one frame short of the 0.9 s key: %s" % [la])
	m._undo()
	await idle(3)
	# 5 shift copy part keys
	await drag_to(part_d(0.9), 1.2, true)
	la = arm_ts("lowerarm_r")
	ua = arm_ts("upperarm_r")
	var cv_ok: bool = S.part_keys["lowerarm_r"][2]["v"] == Vector3(60, 0, 0) and S.part_keys["upperarm_r"][2]["v"] == Vector3(15, 20, 0)
	ok(la == [0.4, 0.9, 1.2] and ua == [0.4, 0.9, 1.2] and cv_ok, "5 Shift-drag the 0.9 s diamond to 1.2 s: forearm %s, upper arm %s, the copies carry the values %s" % [la, ua, cv_ok])
	m._undo()
	await idle(3)
	# 6 stepped view
	S.cards[2]["ktype"] = "breakdown"
	S.cards[3]["ktype"] = "moving_hold"
	S.stepped = true
	var shown: Array = cv.diamonds().filter(func(d): return d["row"] == -1).map(func(d): return d["i"])
	S.stepped = false
	var shown2: Array = cv.diamonds().filter(func(d): return d["row"] == -1).map(func(d): return d["i"])
	S.cards[2].erase("ktype")
	S.cards[3].erase("ktype")
	ok(shown == [0, 1] and shown2 == [0, 1, 2, 3], "6 stepped preview: the card row shows %s (keys and extremes only); off: %s" % [shown, shown2])
	# 7 control: plain retime
	var a7 := arrivals()
	await drag_to(card_d(2), float(a7[2]) + 0.1)
	var a8 := arrivals()
	ok(absf(float(a8[2]) - float(a7[2]) - 0.1) < 1e-6 and S.cards.size() == 4, "7 control: a plain drag of card 2 retimes it: arrival %.4f -> %.4f s, still 4 cards" % [a7[2], a8[2]])
	m.queue_free()
	print("DOPE COPY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
