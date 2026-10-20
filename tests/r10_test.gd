## godot --headless --path . -s tests/r10_test.gd     (ROADMAP round 2, R10: "what would this angle do")
## BARS (stated before measuring):
##   1 the hand / foot / weapon-tip position `ask` predicts equals the one the app has after really applying the same angle
##     (step "set=joint:b,s,t", the undoable edit) within 1 mm: 5 queries, one past a limit, one with two joints at once
##   2 the nearest-parts gap and the contact list equal the app's own check (Body.depth over Body.pairs less the allowance;
##     Body.contacts()) on the body after the real apply, to 1e-6 m; a query that meets another part is stopped there
##   3 the balance verdict (inside / outside, margin cm, tipping) equals Balance.read + Check's HumanLimits._tipping on the real
##     result, and a REAL Check run on a scene holding that lean says TIPPING iff the query said tipping
##   4 a query changes nothing: body state, cards, undo stack, picked card / part, playhead identical (JSON) before and after
##   5 describe joint: the limits equal the body's, the words say the elbow closes toward the upper arm, and the direction it
##     names for + bend is the direction the end really moves (dot > 0.9)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func snap(m: Node) -> String:
	return JSON.stringify([m.B.state(), m.S.cards, m.undo.size(), m.sel_card, m.sel, m.playhead])


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var A := AgentTools.new(m)
	await A.request(1, "open", {"path": "scenes/combo3.json"})
	var B: Body = m.B
	# 1 + 2 + 4: queries against the real apply
	var cases := [
		["joint=elbow_r axis=flex value=90", [["lowerarm_r", Vector3(90, 0, 0)]]],
		["joint=upperarm_r axis=bend value=60; joint=upperarm_r axis=side value=30", [["upperarm_r", Vector3(60, 30, B.ang["upperarm_r"].z)]]],
		["joint=hip_l axis=flex value=70", [["thigh_l", Vector3(70, B.ang["thigh_l"].y, B.ang["thigh_l"].z)]]],
		["joint=knee_r axis=flex value=200", [["calf_r", Vector3(200, 0, 0)]]],
		["joint=elbow_r axis=flex value=90; joint=shoulder_r axis=bend value=-30", [["lowerarm_r", Vector3(90, 0, 0)], ["upperarm_r", Vector3(-30, B.ang["upperarm_r"].y, B.ang["upperarm_r"].z)]]],
	]
	var worst := 0.0
	var gap_worst := 0.0
	var contact_ok := true
	var stopped := 0
	for c in cases:
		await A.request(2, "run", {"steps": ["card=1"]})
		var s0 := snap(m)
		var q: Dictionary = await A.request(3, "ask", {"text": c[0]})
		var r: Dictionary = q["result"]
		ok(snap(m) == s0, "4 a query changes nothing: '%s'" % c[0])
		if r.get("changes", [])[0].has("stopped_by"):
			stopped += 1
		# the real thing
		for ch in c[1]:
			await A.step("set=%s:%s,%s,%s" % [ch[0], ch[1].x, ch[1].y, ch[1].z])
		for e in r["moved"]:
			var d := (B.P[e] as Vector3).distance_to(Vector3(r["moved"][e]["after"][0], r["moved"][e]["after"][1], r["moved"][e]["after"][2]))
			worst = maxf(worst, d)
		if r["weapon_tip"] != null:
			var tp: Array = r["weapon_tip"]["after"]
			worst = maxf(worst, B.wep_point(B.wep_len).distance_to(Vector3(tp[0], tp[1], tp[2])))
		# 2: the app's own check
		var best := INF
		for pr in B.pairs:
			if not B.wep_on and (pr[0] in Body.WEAPON or pr[1] in Body.WEAPON):
				continue
			if not B.wep2_on and (pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2):
				continue
			if B.wep_on and B.grip and pr[0].begins_with("hand") and pr[1].begins_with("hand"):
				continue
			best = minf(best, -(B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0))))
		gap_worst = maxf(gap_worst, absf(best - float(r["nearest"]["gap_m"])))
		var mine: Array = B.contacts().map(func(x): return "%s/%s" % [x[0], x[1]])
		var theirs: Array = r["nearest"]["in_contact"].map(func(x): return "%s/%s" % [x[0], x[1]])
		contact_ok = contact_ok and mine == theirs
		# 3: balance
		var bal := Balance.read(B)
		var sm := {"margin": [bal["margin"]], "down": [(bal["down"] as Array).size() > 0], "sup": [HumanLimits.supported(B)]}
		var rb: Dictionary = r["balance"]
		ok(rb["inside"] == (float(bal["margin"]) >= 0.0 and (bal["down"] as Array).size() > 0) and absf(rb["margin_cm"] - float(bal["margin"]) * 100.0) < 0.06
			and rb["tipping"] == HumanLimits._tipping(sm, 0), "3 balance of '%s': %s, %.1f cm, tipping %s" % [c[0], "inside" if rb["inside"] else "outside", rb["margin_cm"], rb["tipping"]])
		print("     " + " | ".join(r["text"]))
	ok(worst < 0.001, "1 predicted hand / foot / tip positions within 1 mm of the real apply: worst %.4f mm over %d queries" % [worst * 1000.0, cases.size()])
	ok(gap_worst < 1e-6 and contact_ok, "2 nearest gap and contact list equal the app's: worst difference %s m, contacts equal %s" % [gap_worst, contact_ok])
	# 2b: a query that really meets another part: search for one (hand toward the head / hip) on the rest-ish pose
	var hit := {}
	for cand in ["joint=upperarm_r axis=side value=90; joint=upperarm_r axis=bend value=120; joint=elbow_r axis=flex value=145; joint=wrist_r axis=bend value=0",
			"joint=upperarm_l axis=bend value=100; joint=elbow_l axis=flex value=145", "joint=upperarm_r axis=bend value=100; joint=elbow_r axis=flex value=145",
			"joint=thigh_l axis=bend value=120; joint=knee_l axis=flex value=145", "joint=thigh_r axis=bend value=120; joint=knee_r axis=flex value=145"]:
		await A.request(2, "run", {"steps": ["card=1"]})
		var q2: Dictionary = (await A.request(3, "ask", {"text": cand}))["result"]
		for ch in q2["changes"]:
			if ch.has("stopped_by") and ch["stopped_by"].get("kind", "") == "contact":
				hit = q2
				hit["cand"] = cand
		if not hit.is_empty():
			break
	ok(not hit.is_empty(), "2b a query that is cut short where parts meet: %s" % ("none found" if hit.is_empty() else str(hit["cand"]) + " -> " + str(hit["text"][0])))
	if not hit.is_empty():
		var sp: Array = []
		for ch in hit["changes"]:
			if ch.has("stopped_by") and ch["stopped_by"].get("kind", "") == "contact":
				sp = ch["stopped_by"]["pairs"]
		print("     stopped by ", sp, " nearest ", hit["nearest"])
		ok(not sp.is_empty(), "2b the stop names the parts that meet: %s" % [sp.slice(0, 2)])
	# 3b: a real Check run, on a scene that holds the pose: TIPPING (human limits on) and BALANCE (default rulebook)
	var tipped := 0
	for lean in [["joint=hip_l axis=flex value=70", "thigh_l:70,0,0"], ["joint=pelvis axis=bend value=25; joint=spine_03 axis=bend value=20", "pelvis:25,0,0"], ["joint=elbow_r axis=flex value=90", "lowerarm_r:90,0,0"]]:
		await A.request(1, "open", {"path": "scenes/combo3.json"})
		await A.request(2, "run", {"steps": ["card=1"]})
		var ql: Dictionary = (await A.request(3, "ask", {"text": lean[0]}))["result"]
		var steps := ["card=1", "set=" + lean[1], "update", "card=2", "set=" + lean[1], "update"]
		if lean[0].contains("spine_03"):
			steps = ["card=1", "set=pelvis:25,0,0", "set=spine_03:20,0,0", "update", "card=2", "set=pelvis:25,0,0", "set=spine_03:20,0,0", "update"]
		await A.request(2, "run", {"steps": steps})
		m.S.cards[0]["hold"] = 3.0
		m.S.cards[1]["hold"] = 3.0
		HumanLimits.on = true
		var win: float = (m.S.times() as Array)[1][2]   # only the two cards that hold the pose (combo3's later cards tip on their own)
		var fs := A.findings().filter(func(f): return float(f["t"]) <= win)
		HumanLimits.on = false
		var check_tip := fs.any(func(f): return f["rule"] == "TIPPING")
		var check_bal := fs.any(func(f): return f["rule"] == "BALANCE")
		print("     '%s': query %s | Check rules: %s" % [lean[0], ql["text"][-1], fs.map(func(f): return f["rule"])])
		ok(check_tip == ql["balance"]["tipping"] and check_bal == ql["balance"]["balance_rule"], "3 real Check: TIPPING=%s BALANCE=%s; the query said tipping=%s balance_rule=%s (margin %.1f cm)" % [check_tip, check_bal, ql["balance"]["tipping"], ql["balance"]["balance_rule"], ql["balance"]["margin_cm"]])
		tipped += 1 if check_tip or check_bal else 0
	ok(tipped >= 1, "3 at least one of the three poses is flagged by the real Check (so the match is not three nulls): %d" % tipped)
	# 5
	await A.request(1, "open", {"path": "scenes/combo3.json"})
	var dj: Dictionary = (await A.request(4, "describe", {"joint": "elbow_r"}))["result"]
	var lim: Vector2 = B.lim["lowerarm_r"]["bend"]
	ok(dj["axes"]["bend"]["lo"] == lim.x and dj["axes"]["bend"]["hi"] == lim.y and dj["axes"]["bend"]["lo"] == 0.0 and dj["axes"]["bend"]["hi"] == 145.0, "5 limits equal the body's: bend %s..%s" % [dj["axes"]["bend"]["lo"], dj["axes"]["bend"]["hi"]])
	ok(String(dj["axes"]["bend"]["words"]).contains("toward the upper arm"), "5 words: " + String(dj["axes"]["bend"]["words"]))
	# the named direction vs the real move of the forearm's end from the rest pose
	var keep: Dictionary = B.state()
	for jn in Body.BODY:
		B.ang[jn] = Vector3.ZERO
	B.fk()
	var e0: Vector3 = B.E["lowerarm_r"]
	B.set_ang("lowerarm_r", Vector3(10, 0, 0))
	var mv: Vector3 = (B.E["lowerarm_r"] as Vector3) - e0
	B.set_state(keep)
	var named := WhatIf.dir_words(mv.normalized())
	ok(named == dj["axes"]["bend"]["end_swings"], "5 + bend swings the end '%s' from rest; the real move (%.3f, %.3f, %.3f) reads '%s'" % [dj["axes"]["bend"]["end_swings"], mv.x, mv.y, mv.z, named])
	var bad: Dictionary = (await A.request(5, "ask", {"text": "joint=elbo axis=flex value=1"}))
	ok(bad.has("error") and String(bad["error"]["message"]).contains("say a part"), "errors name the next step: " + String(bad.get("error", {}).get("message", "")).left(80))
	print("R10 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
