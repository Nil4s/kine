## godot --headless --path . -s tests/rangesweep_test.gd     (N013 SAFE RANGE SWEEP, scripts/range_sweep.gd)
## "what values of X keep ALL of these true" -> intervals of X with what bounds each end. Bars, stated before measuring:
##   1 ANALYTIC: the right elbow is a hinge (checked here first: the angle at the elbow between shoulder and wrist is
##     gamma0 - bend, within 0.01 deg, at bend 90). The wrist CENTRE (hand_r) to the shoulder's rest point S is then
##     d(bend) = sqrt(a^2 + b^2 - 2ab cos(gamma0 - bend)) (law of cosines; a, b, gamma0 read off the rest body), so
##     "reach hand_r to S within D" holds for bend >= gamma0 - acos((a^2 + b^2 - D^2) / 2ab). For D = 40 cm and 30 cm:
##     ONE interval, its low end within 0.2 deg of that, its high end the limit 145 bound by "joint limit".
##   2 BALANCE: sweeping the pelvis bend (the whole body tips) with "balance": one interval, both ends bound by balance;
##     at each reported end Balance.read (balance.gd) has a foot down and margin >= 0, and 0.1 deg OUTWARD it does not.
##     "balance 3 cm" gives an interval strictly inside it.
##   3 EMPTY: a reach 3 m overhead with "balance" -> no interval, `never` names exactly the reach, and the text says it
##     "holds for NO value". "balance" + "pelvis above 30 deg flex" (each holds alone, never both) -> empty, `never` is
##     empty and the text says they never hold at once.
##   4 UNTOUCHED: after a sweep in each mode (the live pose, t = 1.0 s, card 2 of combo3) the body state, every joint
##     point, the scene as its file would be (JSON text), the card's pose dictionary OBJECT and the playhead are
##     bit-identical to before.
##   5 SPEED: a 1D sweep through serve (right hip flex over its 145 deg, 3 conditions: balance, a reach, an N002 line)
##     answers in under 2 s.
##   6 N002 LINE ON ONE POSE: "right elbow below 60 deg flex" alone on the elbow -> exactly [0, 60] (within 0.05).
##   7 CARD MODE: combo3 card 2, the right elbow with "right elbow below 115 deg flex all clip" (measured over the clip):
##     BodyAssert.run passes with the card set to the reported pick, and fails 0.5 deg past any end not at a limit. The
##     frames-the-card-can't-move shortcut gives the same intervals as "exact" (every frame played every sample) on
##     100..130 deg. (Its time is printed, not barred: combo3 plays ~5 ms a frame.)
##   8 MAP: pelvis bend x right hip bend, "balance", 10 deg steps: a grid of (nx+1) x (ny+1) cells, rows top = the largest
##     hip value; 4 cells checked against Balance.read on the body set here.
##   9 SERVE: `range` gives the direct call's intervals; a bad joint, a locked axis and an unread condition are -32602
##     (the unread one with the N002 grammar in data).
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func bal_ok(B: Body) -> bool:
	var r := Balance.read(B)
	return (r["down"] as Array).size() > 0 and float(r["margin"]) >= 0.0


func snap_state() -> String:
	var B: Body = m.B
	var pts := {}
	for j in B.P:
		pts[j] = B.P[j]
	return var_to_str(B.state()) + var_to_str(pts) + JSON.stringify(T.scene_dict()) + str(m.playhead) + var_to_str(B.last_stop)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	T = AgentTools.new(m)
	var B: Body = m.B

	# 1 ANALYTIC
	B.set_ang("lowerarm_r", Vector3.ZERO)
	var S0: Vector3 = B.P["upperarm_r"]
	var E0: Vector3 = B.P["lowerarm_r"]
	var W0: Vector3 = B.P["hand_r"]
	var a := S0.distance_to(E0)
	var b := E0.distance_to(W0)
	var g0 := rad_to_deg((S0 - E0).angle_to(W0 - E0))
	B.set_ang("lowerarm_r", Vector3(90, 0, 0))
	var g90 := rad_to_deg((B.P["upperarm_r"] - B.P["lowerarm_r"] as Vector3).angle_to(B.P["hand_r"] - B.P["lowerarm_r"]))
	B.set_ang("lowerarm_r", Vector3.ZERO)
	ok(absf(g90 - (g0 - 90.0)) < 0.01, "1 the elbow is a hinge: gamma(90) %.4f = gamma0 %.4f - 90" % [g90, g0])
	for D in [0.40, 0.30]:
		var want := g0 - rad_to_deg(acos((a * a + b * b - D * D) / (2.0 * a * b)))
		var r := RangeSweep.run(m, {"joint": "right elbow", "axis": "flex", "conditions": [{"reach": "hand_r", "to": [S0.x, S0.y, S0.z], "within_cm": D * 100.0}]})
		var iv: Array = r.get("intervals", [])
		var good: bool = iv.size() == 1 and absf(float(iv[0]["from"]) - want) <= 0.2 and is_equal_approx(float(iv[0]["to"]), 145.0) \
			and String(iv[0]["ends"][1]["bound_by"][0]).begins_with("joint limit")
		ok(good, "1 reach within %.0f cm: low end %s, closed form %.3f deg (bar 0.2), high end %s" % [D * 100.0, iv[0]["from"] if iv.size() > 0 else "none", want, iv[0]["ends"][1]["bound_by"] if iv.size() > 0 else "-"])

	# 2 BALANCE
	var rb := RangeSweep.run(m, {"joint": "pelvis", "axis": "bend", "conditions": ["balance"]})
	var ib: Array = rb["intervals"]
	ok(ib.size() == 1 and ib[0]["ends"][0]["bound_by"] == ["balance"] and ib[0]["ends"][1]["bound_by"] == ["balance"], "2 pelvis bend + balance: one interval, both ends by balance: %s" % str(rb["text"]))
	if ib.size() == 1:
		var keep := B.state()
		for e in [[float(ib[0]["from"]), -0.1], [float(ib[0]["to"]), 0.1]]:
			B.set_ang("pelvis", Vector3(e[0], 0, 0))
			var at_end := bal_ok(B)
			var mg := float(Balance.read(B)["margin"])
			B.set_ang("pelvis", Vector3(e[0] + e[1], 0, 0))
			var outside := bal_ok(B)
			var mo := float(Balance.read(B)["margin"])
			ok(at_end and not outside, "2 at the end %.2f balance.gd holds (margin %.3f cm), at %.2f it does not (margin %.3f cm)" % [e[0], mg * 100.0, e[0] + e[1], mo * 100.0])
		B.set_state(keep)
		var r3 := RangeSweep.run(m, {"joint": "pelvis", "axis": "bend", "conditions": ["balance 3 cm"]})
		var i3: Array = r3["intervals"]
		ok(i3.size() == 1 and float(i3[0]["from"]) > float(ib[0]["from"]) and float(i3[0]["to"]) < float(ib[0]["to"]), "2 balance 3 cm is inside: %s" % str(r3["text"]))

	# 3 EMPTY
	var re := RangeSweep.run(m, {"joint": "right hip", "axis": "flex", "conditions": ["balance", "reach right fist to 0,3,0 within 2 cm"]})
	ok(re["empty"] and re["never"] == ["reach right fist to 0,3,0 within 2 cm"] and String(re["text"][1]).contains("holds for NO value"), "3 empty, the reach is never satisfiable: %s" % re["text"][1])
	var re2 := RangeSweep.run(m, {"joint": "pelvis", "axis": "bend", "conditions": ["balance", "pelvis above 30 deg flex"]})
	ok(re2["empty"] and (re2["never"] as Array).is_empty() and String(re2["text"][1]).contains("never all at once"), "3 each alone, never together: %s" % re2["text"][1])

	# 6 N002 LINE ON ONE POSE
	var rl := RangeSweep.run(m, {"joint": "elbow_r", "axis": "bend", "conditions": ["right elbow below 60 deg flex"]})
	var il: Array = rl["intervals"]
	ok(il.size() == 1 and absf(float(il[0]["from"])) <= 0.05 and absf(float(il[0]["to"]) - 60.0) <= 0.05, "6 elbow below 60: %s" % str(rl["text"]))

	# 5 SPEED (the default body, live pose)
	B.set_ang("lowerarm_r", Vector3(90, 0, 0))
	var fist: Vector3 = B.P["hand_r"]
	B.set_ang("lowerarm_r", Vector3.ZERO)
	var t0 := Time.get_ticks_msec()
	var rs: Dictionary = await T.request(1, "range", {"joint": "right hip", "axis": "flex", "conditions": ["balance",
		"reach right fist to %.3f,%.3f,%.3f within 50 cm" % [fist.x, fist.y, fist.z], "left knee below 30 deg flex"]})
	var ms := Time.get_ticks_msec() - t0
	ok(rs.has("result") and ms < 2000, "5 1D sweep through serve: %d ms (bar 2000), %d samples: %s" % [ms, rs.get("result", {}).get("samples", 0), str(rs.get("result", {}).get("text", rs))])

	# 4 UNTOUCHED: the live pose
	var s0 := snap_state()
	RangeSweep.run(m, {"joint": "right hip", "axis": "flex", "conditions": ["balance", "left foot planted"]})
	ok(snap_state() == s0, "4 untouched after a live-pose sweep")

	# 9 SERVE (default body)
	var direct := RangeSweep.run(m, {"joint": "pelvis", "axis": "bend", "conditions": ["balance"]})
	var sv: Dictionary = await T.request(2, "range", {"joint": "pelvis", "axis": "bend", "conditions": ["balance"]})
	ok(sv.has("result") and JSON.stringify(sv["result"]["intervals"]) == JSON.stringify(direct["intervals"]), "9 serve = direct")
	var e1: Dictionary = await T.request(3, "range", {"joint": "tail", "axis": "flex", "conditions": ["balance"]})
	var e2: Dictionary = await T.request(4, "range", {"joint": "elbow_r", "axis": "side", "conditions": ["balance"]})
	var e3: Dictionary = await T.request(5, "range", {"joint": "elbow_r", "axis": "flex", "conditions": ["the fist is happy"]})
	ok(e1.get("error", {}).get("code", 0) == -32602 and e2.get("error", {}).get("code", 0) == -32602 and String(e2["error"]["message"]).contains("LOCKED")
		and e3.get("error", {}).get("code", 0) == -32602 and e3["error"].get("data", {}).has("grammar"), "9 errors: %s | %s | %s" % [e1.get("error"), e2.get("error", {}).get("message"), e3.get("error", {}).get("message")])

	# 8 MAP
	var rm := RangeSweep.run(m, {"joint": "pelvis", "axis": "bend", "joint2": "right hip", "axis2": "flex", "conditions": ["balance"], "step": 10, "step2": 10})
	var mp: Dictionary = rm["map"]
	var nx: int = (mp["x"] as Array).size()
	var ny: int = (mp["y"] as Array).size()
	var good8: bool = (mp["rows"] as Array).size() == ny and String(mp["rows"][0]).length() == nx and mp["passing"] > 0 and mp["passing"] < nx * ny
	var keep8 := B.state()
	for c in [[0, 0], [nx / 2, 0], [nx / 2, ny - 1], [nx - 1, ny / 2]]:
		B.set_ang("pelvis", Vector3(float(mp["x"][c[0]]), 0, 0))
		B.set_ang("thigh_r", Vector3(float(mp["y"][c[1]]), 0, 0))
		var want8 := bal_ok(B)
		good8 = good8 and bool(mp["pass"][c[1]][c[0]]) == want8 and (String(mp["rows"][ny - 1 - c[1]])[c[0]] == "#") == want8
		B.set_state(keep8)
	ok(good8, "8 map %d x %d, %d pass; 4 cells = balance.gd:\n%s" % [nx, ny, mp["passing"], "\n".join(rm["text"])])

	# 4 + 7 on combo3: t mode, card mode
	await T.request(6, "open", {"path": "scenes/combo3.json"})
	var s1 := snap_state()
	var rt := RangeSweep.run(m, {"joint": "right hip", "axis": "flex", "t": 1.0, "conditions": ["balance", "right fist at least 20 cm from chin"]})
	ok(rt["ok"] and snap_state() == s1, "4 untouched after a t = 1.0 s sweep: %s" % str(rt.get("text", rt)))
	var pose0: Dictionary = m.S.cards[1]["pose"]
	var rc := RangeSweep.run(m, {"joint": "elbow_r", "axis": "flex", "card": 2, "step": 15, "conditions": ["right elbow below 115 deg flex all clip"]})
	ok(rc["ok"] and snap_state() == s1 and is_same(m.S.cards[1]["pose"], pose0), "4 untouched after a card 2 sweep (the same pose object): %s" % str(rc.get("text", rc)))
	var good7: bool = rc["ok"] and not (rc["intervals"] as Array).is_empty()
	for iv in rc.get("intervals", []):
		var pk := _card_check(1, "lowerarm_r", float(iv["pick"]), "right elbow below 115 deg flex all clip")
		good7 = good7 and pk
		for e in [[iv["ends"][0], -0.5], [iv["ends"][1], 0.5]]:
			if not String(e[0]["bound_by"][0]).begins_with("joint limit"):
				var past := _card_check(1, "lowerarm_r", float(e[0]["value"]) + float(e[1]), "right elbow below 115 deg flex all clip")
				good7 = good7 and not past
	m.S.cards[1]["pose"] = pose0
	var rx1 := RangeSweep.run(m, {"joint": "elbow_r", "axis": "flex", "card": 2, "from": 100, "to": 130, "step": 10, "conditions": ["right elbow below 115 deg flex all clip"]})
	var rx2 := RangeSweep.run(m, {"joint": "elbow_r", "axis": "flex", "card": 2, "from": 100, "to": 130, "step": 10, "exact": true, "conditions": ["right elbow below 115 deg flex all clip"]})
	ok(JSON.stringify(rx1["intervals"]) == JSON.stringify(rx2["intervals"]) and not (rx1["intervals"] as Array).is_empty(), "7 shortcut = exact on 100..130: %s (%s, %.0f ms) vs %.0f ms exact" % [str(rx1["text"][1]), rx1["clip_frames_played"], rx1["ms"], rx2["ms"]])
	ok(good7 and snap_state() == s1, "7 card mode agrees with BodyAssert.run at the pick and 0.5 deg past each end")

	print("RANGESWEEP: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)


## BodyAssert.run on the scene with card k's joint bend set to x (a copy of the pose; put back after)
func _card_check(k: int, j: String, x: float, line: String) -> bool:
	var S: Scene = m.S
	var p0: Dictionary = S.cards[k]["pose"]
	var p: Dictionary = p0.duplicate(true)
	p["joints"][j]["bend"] = x
	S.cards[k]["pose"] = p
	var r := BodyAssert.run(S, m.B, [line])
	S.cards[k]["pose"] = p0
	return bool(r["pass"])
