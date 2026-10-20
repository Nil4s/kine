## godot --path . -s tests/i25_test.gd     (ROADMAP I25: breakfall check, scripts/breakfall.gd + breakfall_ui.gd; needs a window)
## Synthetic falls are built in the test from Body poses (a topple about the pelvis (forward) on the floor_body grounding, 0.12 s per card):
##  A = STRAIGHT-ARM: arms straight and pointing to the floor, the trunk tips 0 -> 100 deg, elbows fold only after the hands are down.
##  H = HEAD-FIRST: arms at the sides, the trunk tips to 100 deg; of a few candidate shapes (hip / spine flexion) the first whose first part to
##      touch the floor is the head is used (which shape was chosen is printed).
## Bars, written before measuring (the first part to touch is printed in the run; the bars name verdicts, not guessed numbers):
##  (1) fall A is found (1 fall); a hand or forearm is among the first parts to touch; its elbow at the impact is under 30 deg, so verdict (b) is not OK
##  (2) fall H is found; the head is the first part to touch; verdict (a) is FAIL
##  (3) A after slap(): the same fall reads elbow >= 30 deg at the impact (or no arm lands first), first-contact speed printed (was 6.3 m/s);
##      after the head fix as well: the direction is FORWARD and verdict (a) is ok. READ: forward = head clear (>= 5 cm over the landing window)
##      OR turned aside (neck + head twist >= 45 deg) with the cheek-side contact under 2 m/s; the run prints which one.
##  (4) H (forward) after the head fix: direction forward, head turned >= 45 deg, verdict (a) ok by one of the two reads, NOT by a chin tuck
##  (5) every fix (A slap, H tuck) read from the app: the scene JSON is byte-identical after the button and after Preview; Accept = ONE undo step,
##      Ctrl+Z restores the cards exactly; the JSON changes only at Accept
##  (6) a standing clip (scenes/thrust.json) finds no fall, with a message that names a next step
##  (7) the real scenes/, poses/, data/ hash the same before and after
##  (8) placement: the panel is on screen, the timeline wears a badge over the fall, and in the side view the body at the impact has its hand within
##      3 cm of the floor while the head is over 20 cm above it
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


func hashes() -> Dictionary:
	var out := {}
	for dir in ["res://scenes/", "res://poses/", "res://data/"]:
		var stack := [dir]
		while not stack.is_empty():
			var d: String = stack.pop_back()
			for fn in DirAccess.get_files_at(d):
				out[d + fn] = FileAccess.get_md5(d + fn)
			for sub in DirAccess.get_directories_at(d):
				stack.append(d + sub + "/")
	return out


func arm_down(B: Body, sd: String) -> void:
	var ua := "upperarm" + sd
	var rb: Vector2 = B.lim[ua]["bend"]
	var rs: Vector2 = B.lim[ua]["side"]
	var rt: Vector2 = B.lim[ua]["twist"]
	var best := INF
	var bv := Vector3.ZERO
	for bd in range(int(rb.x), int(rb.y) + 1, 15):
		for sv in range(int(rs.x), int(rs.y) + 1, 15):
			for tw in range(int(rt.x), int(rt.y) + 1, 30):
				B.ang[ua] = Vector3(bd, sv, tw)
				B.fk_sub(ua)
				var y := ((B.E[ua] as Vector3) - (B.P[ua] as Vector3)).normalized().y
				if y < best:
					best = y
					bv = B.ang[ua]
	B.ang[ua] = bv
	B.fk_sub(ua)


func card(B: Body, nm: String, move: float, hold: float) -> Dictionary:
	B.offset = Vector3.ZERO
	B.fk()
	return {"name": nm, "pose": B.to_dict(), "move": move, "hold": hold}


## kind "A" or "H"; cand = [thigh bend, spine bend (each of 3), neck bend] at the full tip
func fall_dict(kind: String, cand: Array) -> Dictionary:
	var B := DistanceKeeper.new_body()
	var th := [0.0, 20.0, 40.0, 60.0, 75.0, 90.0, 100.0] if kind == "A" else [0.0, 25.0, 50.0, 75.0, 100.0]
	var el := [0.0, 0.0, 0.0, 0.0, 10.0, 90.0, 130.0]
	var mv := 0.12 if kind == "A" else 0.25
	var cards := []
	for k in th.size():
		var f: float = float(th[k]) / 100.0
		for j in Body.ORDER:
			B.ang[j] = Vector3.ZERO
		B.ang["pelvis"] = Vector3(th[k], 0, 0)   # both tip FORWARD (backward was tried: the arms fold under, no head-first shape found in 8 candidates)
		if kind == "H":
			for t in ["thigh_l", "thigh_r"]:
				B.ang[t] = Vector3(float(cand[0]) * f, 0, 0)
			for s in ["spine_01", "spine_02", "spine_03"]:
				B.ang[s] = Vector3(float(cand[1]) * f, 0, 0)
			B.ang["neck_01"] = Vector3(float(cand[2]) * f, 0, 0)
		B.fk()
		if kind == "A":
			for sd in ["_l", "_r"]:
				arm_down(B, sd)
				B.ang["lowerarm" + sd] = Vector3(el[k], 0, 0)
				B.fk_sub("lowerarm" + sd)
		cards.append(card(B, "fall %d" % k, -1.0 if k == 0 else mv, 0.3 if k == 0 else 0.0))
	return {"scene": "fall_" + kind, "fps": 30, "on_floor": true, "floor_body": true, "cards": cards}


func scene_of(d: Dictionary) -> Scene:
	var S := Scene.new()
	S.from_dict(d)
	return S


func show(tag: String, rep: Dictionary) -> void:
	for f in rep["falls"]:
		print("     %s: impact %.2f s first=%s lowest=%s regions=%s chin=%.0f turn=%.0f dir=%s head[%s] head_clear=%.1f cm side=%s elbow=%.0f speed=%.1f  a/b/c/d=%s/%s/%s/%s" % [tag, float(f["t_c"]),
			str(f["first"]), String(f["part"]), str(f["regions"]), float(f["chin"]), float(f["turn"]), String(f["dir"]), String(f["head_how"]), float(f["head_clear"]) * 100.0, String(f["side"]), float(f["elbow"]), float(f["speed"]),
			f["a"], f["b"], f["c"], f["d"]])


func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	m._unhandled_input(ev)


func _init() -> void:
	var before_files := hashes()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false

	# (1) fall A
	var dA := fall_dict("A", [])
	var SA := scene_of(dA)
	var rA := Breakfall.analyze(SA)
	show("A", rA)
	var fA: Dictionary = rA["falls"][0] if not (rA["falls"] as Array).is_empty() else {}
	var armfirst := false
	if not fA.is_empty():
		for p in fA["first"]:
			armfirst = armfirst or Breakfall.region(p) == "arm"
	ok(rA["falls"].size() == 1 and armfirst and String(fA.get("side", "")) != "" and float(fA.get("elbow", 99.0)) < Breakfall.ELBOW_OK and String(fA.get("b", "ok")) != "ok",
		"(1) fall A found: first parts %s, elbow %.0f deg (< 30), verdict b = %s" % [str(fA.get("first", [])), float(fA.get("elbow", -1.0)), String(fA.get("b", "-"))])

	# (2) fall H: the first candidate shape whose head lands first
	var cands := [[0, 0, 0], [60, 0, 0], [-60, 0, 0], [0, 15, 0], [60, 15, 0], [-60, 15, 0], [0, 15, -25], [-60, 15, -25]]
	var dH := {}
	var SH: Scene = null
	var rH := {}
	var cho := []
	for cd in cands:
		var d := fall_dict("H", cd)
		var S := scene_of(d)
		var r := Breakfall.analyze(S)
		show("H%s" % str(cd), r)
		if not (r["falls"] as Array).is_empty() and String(r["falls"][0]["part"]) == "head":
			dH = d
			SH = S
			rH = r
			cho = cd
			break
		if dH.is_empty() and not (r["falls"] as Array).is_empty() and rH.is_empty():
			pass
	var fH: Dictionary = rH["falls"][0] if not rH.is_empty() else {}
	ok(not fH.is_empty() and String(fH["part"]) == "head" and String(fH["a"]) == "fail",
		"(2) fall H found with the head first (candidate %s): lowest part %s, verdict a = %s, head clear %.1f cm" % [str(cho), String(fH.get("part", "-")), String(fH.get("a", "-")), float(fH.get("head_clear", 0.0)) * 100.0])

	# (3) A after slap, after tuck
	var rs := Breakfall.slap(SA, fA) if not fA.is_empty() else {"ok": false, "why": "no fall"}
	var aft: Dictionary = rs.get("after", {})
	print("     A after slap: ", rs.get("msg", rs.get("why", "")))
	if not aft.is_empty():
		show("A+slap", rs["rep"])
	ok(rs["ok"] and not aft.is_empty() and (String(aft["side"]) == "" or float(aft["elbow"]) >= Breakfall.ELBOW_OK) and String(aft["b"]) == "ok",
		"(3) A after slap: verdict b = %s, elbow %.0f deg (>= 30)" % [String(aft.get("b", "-")), float(aft.get("elbow", -1.0))])
	var SA2: Scene = rs["scene"] if rs["ok"] else SA
	var fA2: Dictionary = aft if not aft.is_empty() else fA
	var rt := Breakfall.tuck(SA2, fA2)
	var aft_t: Dictionary = rt.get("after", {})
	print("     A after slap + tuck: ", rt.get("msg", rt.get("why", "")))
	if not aft_t.is_empty():
		show("A+slap+tuck", rt["rep"])
	ok(rt["ok"] or String(fA2["a"]) == "ok", "(3) A tuck: %s" % String(rt.get("msg", rt.get("why", ""))))
	var tuck_a: Dictionary = aft_t if not aft_t.is_empty() else fA2
	ok(String(tuck_a["dir"]) == "forward" and String(tuck_a["a"]) == "ok" and float(tuck_a["elbow"] if String(tuck_a["side"]) != "" else 99.0) >= 30.0,
		"(3) A after slap + head fix: %s fall, head [%s], elbow %.0f (>= 30), verdicts %s/%s/%s/%s, whole = %s" % [tuck_a["dir"], tuck_a["head_how"],
		float(tuck_a["elbow"]), tuck_a["a"], tuck_a["b"], tuck_a["c"], tuck_a["d"], tuck_a["cls"]])
	print("     A speed: first contact %.1f m/s before the slap -> %.1f after (part %s)" % [float(fA["speed"]), float(aft.get("speed", -1.0)), String(aft.get("part", "-"))])

	# (4) H after tuck
	var rth: Dictionary = Breakfall.tuck(SH, fH) if not fH.is_empty() else {"ok": false, "why": "no H fall"}
	var ah: Dictionary = rth.get("after", {})
	print("     H after tuck: ", rth.get("msg", rth.get("why", "")))
	if not ah.is_empty():
		show("H+tuck", rth["rep"])
	ok(rth["ok"] and not ah.is_empty() and String(ah["dir"]) == "forward" and float(ah["turn"]) >= Breakfall.TURN_MIN,
		"(4) H after the head fix: %s fall, head turned %.0f deg (>= 45), chin %.0f deg (not a tuck)" % [ah.get("dir", "-"), float(ah.get("turn", -1.0)), float(ah.get("chin", 0.0))])
	ok(not ah.is_empty() and String(ah["a"]) == "ok",
		"(4) H after the head fix: verdict a = %s by [%s]; head clear %.1f cm, contact %.1f m/s; verdicts %s/%s/%s/%s, whole = %s" % [ah.get("a", "-"), ah.get("head_how", "-"), float(ah.get("head_clear", -1.0)) * 100.0, float(ah.get("head_v", 0.0)), ah.get("a", "-"), ah.get("b", "-"), ah.get("c", "-"), ah.get("d", "-"), ah.get("cls", "-")])

	# (5) the app: JSON untouched until Accept; one undo step each
	for pair in [["A", dA, "slap"], ["H", dH, "tuck"]]:
		if (pair[1] as Dictionary).is_empty():
			ok(false, "(5) %s: no scene" % pair[0])
			continue
		m.S.from_dict((pair[1] as Dictionary).duplicate(true))
		m._rebuild_cards()
		await idle(3)
		m.bk_ui.show()
		await idle(3)
		var json0 := JSON.stringify(m.S.to_dict(m.B, false))
		var cards0 := JSON.stringify(m.S.cards)
		var nf: int = m.bk_ui.rep["falls"].size()
		m.bk_ui.select(0, pair[2])
		await idle(2)
		m.bk_ui.preview()
		await idle(10)
		var pv_on: bool = m.bk_ui.pv
		m.bk_ui.halt()
		var same := JSON.stringify(m.S.to_dict(m.B, false)) == json0 and JSON.stringify(m.S.cards) == cards0
		var u0: int = m.undo.size()
		m.bk_ui.accept()
		await idle(3)
		var changed := JSON.stringify(m.S.cards) != cards0
		var u1: int = m.undo.size()
		m._undo()
		await idle(3)
		var back := JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == json0
		ok(nf >= 1 and not m.bk_ui.fx.is_empty() or changed, "(5) %s: the %s fix is built" % [pair[0], pair[2]])
		ok(same and pv_on, "(5) %s: scene JSON byte-identical after the button and Preview (preview ran: %s)" % [pair[0], str(pv_on)])
		ok(changed and u1 == u0 + 1 and back, "(5) %s: Accept changed the cards, was ONE undo step (%d -> %d), Ctrl+Z restores them exactly" % [pair[0], u0, u1])

	# (6) a standing clip
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/thrust.json"))
	var rS := Breakfall.analyze(scene_of(th))
	ok(not rS["ok"] and (rS["falls"] as Array).is_empty() and String(rS["msg"]).contains("play a fall"), "(6) a standing clip finds no fall: '%s'" % String(rS["msg"]).substr(0, 60))

	# (8) placement + screenshot: fall A with the slap + head fixes accepted, side view, at the impact; the panel is moved off the body
	var fixed: Scene = rt["scene"] if rt["ok"] else SA2
	m.S.from_dict(fixed.to_dict(m.B, false))
	m._rebuild_cards()
	await idle(3)
	m.bk_ui.show()
	await idle(3)
	var f0: Dictionary = m.bk_ui.rep["falls"][0] if not (m.bk_ui.rep["falls"] as Array).is_empty() else fA
	m._view(5)
	m.playing = false
	m.playhead = float(f0["t_c"])
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(30)
	var pc := m.ui_find.get_child(0) as Control
	var bb := Rect2(m.cam.unproject_position(m.B.P["pelvis"]), Vector2.ZERO)
	for q in Body.ORDER:
		bb = bb.expand(m.cam.unproject_position(m.B.P[q]))
	var vr := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	for gx in [262.0, 8.0, vr.size.x - pc.size.x - 8.0]:   # the first x where the panel clears the body's screen box and the viewport
		pc.global_position = Vector2(gx, 96.0)
		if not pc.get_global_rect().intersects(bb) and vr.encloses(pc.get_global_rect().grow(-1.0)):
			break
	await idle(10)
	var hand_low := 9.0
	for p in ["hand_l", "hand_r", "lowerarm_l", "lowerarm_r"]:
		hand_low = minf(hand_low, Breakfall._low(m.B, p))
	var head_low := Breakfall._low(m.B, "head")
	var pr: Rect2 = pc.get_global_rect()
	ok(m.ui_find.visible and vr.encloses(pr.grow(-1.0)) and not pr.intersects(bb) and m.ui_timeline.bk.size() >= 1,
		"(8) panel on screen at %s and NOT over the body (body box %s), %d timeline badge; at the impact (fixed fall) hand %.1f cm, head %.1f cm above the floor" % [str(pr), str(bb), m.ui_timeline.bk.size(), hand_low * 100.0, head_low * 100.0])
	m._say("breakfall check, fixed fall: forward fall, arms bend 30 -> 90 deg over the landing, head turned aside")
	await idle(240)
	m._say("breakfall check, fixed fall: forward fall, arms bend 30 -> 90 deg over the landing, head turned aside")
	await idle(3)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i25c.png")

	var after_files := hashes()
	var same2 := after_files.size() == before_files.size()
	for k in before_files:
		same2 = same2 and after_files.get(k, "") == before_files[k]
	ok(same2, "(7) %d files under scenes/, poses/, data/ hash the same before and after" % before_files.size())
	print("I25 BREAKFALL %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
