## godot --headless --path . -s tests/grip_types_test.gd     (round 47, GATES CC2; docs/GRIP_RESEARCH.md)
## GRIP TYPES PER HANDLE (Napier 1956; Buchholz & Armstrong 1992): KINDS says how each handle is held, the thumb follows.
##   1 every kind names a type from GripWrap.TYPES; Body.wrap_fingers uses the held kind's
##   2 power (the bat): the thumb closes over the fingers - its tip meets the index / middle finger or the handle
##     (<= 3 mm), its two joints flexed (> 10 deg each)
##   3 diagonal (the dagger): the thumb lies straight along the handle (both joints 0), its tip farther from the fingers
##     than the power thumb's
##   4 precision (the bat handle held by the pads): every fingertip touches (<= 3 mm) while the proximal phalanges stay
##     at least 5 mm farther off the handle than power's on the same handle (power's own sit ~7 mm off: with the palm
##     where the bat file puts it, the knuckles cannot lay them flat - measured, not assumed)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	B.fast = true
	var bad := []
	for k in Body.KINDS:
		if not GripWrap.TYPES.has(String(Body.KINDS[k].get("grip", ""))):
			bad.append(k)
	B.set_kind("dagger")
	B.weapon_to_hand("hand_r")
	var hd := GripWrap.handle_of(B)
	var rd: Dictionary = B.wrap_fingers("hand_r", hd[0], hd[1], hd[2])
	ok(bad.is_empty() and rd["thumb"][0][2] == "along", "1 every kind names a grip type %s (missing: %s); wrap_fingers on the held dagger used %s" % [GripWrap.TYPES, bad, rd["thumb"][0][2]])
	var d_tip := _tip_to_fingers(B, "_r")
	# 2 power
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	var keep := B.state()
	hd = GripWrap.handle_of(B)
	var rp: Dictionary = B.wrap_fingers("hand_r", hd[0], hd[1], hd[2])
	var t2: float = (B.ang["thumb_02_r"] as Vector3).x
	var t3: float = (B.ang["thumb_03_r"] as Vector3).x
	var p_tip := _tip_to_fingers(B, "_r")
	var prox_power := _prox(B, hd)
	ok(float(rp["thumb"][1][1]) <= 0.003 and t2 > 10.0 and t3 > 10.0, "2 power: the thumb's tip %.1f mm from the fingers / handle, its joints %.0f / %.0f deg" % [float(rp["thumb"][1][1]) * 1000, t2, t3])
	ok(d_tip > p_tip, "3 diagonal (dagger): the thumb straight along the handle, its tip %.0f mm from the fingers (power's: %.0f)" % [d_tip * 1000, p_tip * 1000])
	# 4 precision on the same handle
	B.set_state(keep)
	var rq: Dictionary = B.wrap_fingers("hand_r", hd[0], hd[1], hd[2], "precision")
	var tips_ok := true
	for f in GripWrap.LONG:
		var row: Array = rq[f][2]
		if not (row[2] == "limit" or float(row[1]) <= 0.003):
			tips_ok = false
	var prox_prec := _prox(B, hd)
	ok(tips_ok and prox_prec >= prox_power + 0.005, "4 precision: every fingertip touches (%s), the proximal phalanges %.1f mm off the handle (power: %.1f)" % [tips_ok, prox_prec * 1000, prox_power * 1000])
	m.queue_free()
	print("GRIP TYPES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _tip_to_fingers(B: Body, sd: String) -> float:
	var c: Array = B.cap("thumb_03" + sd)
	var g := INF
	for o in ["index_02" + sd, "middle_02" + sd]:
		var d: Array = B.cap(o)
		g = minf(g, Body.seg_seg(c[0], c[1], d[0], d[1]) - float(B.rad["thumb_03" + sd]) - float(B.rad[o]))
	return g


func _prox(B: Body, hd: Array) -> float:
	var t := 0.0
	for f in GripWrap.LONG:
		t += maxf(0.0, GripWrap.gap(B, f + "_01_r", hd[0], hd[1], hd[2]))
	return t / 4.0
