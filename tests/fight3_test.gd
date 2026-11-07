## godot --headless --path . -s tests/fight3_test.gd     (L74: N045 disarm truth, N048 one vs many)
## N045 (scripts/disarm_truth.gd): lever torque T = force * lever arm (m) about the wrist; the grip holds T up to hold = hands * 0.8 * grip_N * handle radius;
##   past that the weapon leaves the hand unless the wrist takes T / hands >= 30 Nm first. Verdicts: "grip holds" | "works" | "wrist breaks first".
##   bars: strong grip refused, weak grip succeeds, verdict monotone in lever arm (all 3 verdicts seen), more hands never lowers the hold, lever from the book.
## N048 (scripts/group_fight.gd): 3..6 attackers around the hero: 0 simultaneous same-side attacks, 0 out-of-reach starts, 0 LOS-blocked concurrent,
##   >= 1 window each, wait positions >= 0.75 m apart; a hand-made bad schedule is flagged for each rule.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	# ---- N045. katana handle r 0.016: one hand 400 N -> hold 5.12 Nm; two hands 600 N each -> 15.36 Nm
	var strong := DisarmTruth.judge({"kind": "katana", "hands": 2, "grip_n": 600.0, "force_n": 100.0, "lever_m": 0.10})
	ok(strong["verdict"] == "grip holds", "1a planted strong grip (2 hands 600 N, T=10 Nm < hold 15.4) refused: %s" % strong["verdict"])
	ok(absf(float(strong["hold_nm"]) - 15.36) < 0.05 and absf(float(strong["torque_nm"]) - 10.0) < 0.01, "1b numbers: hold %.2f torque %.2f" % [strong["hold_nm"], strong["torque_nm"]])
	var weak := DisarmTruth.judge({"kind": "katana", "hands": 2, "grip_n": 100.0, "force_n": 100.0, "lever_m": 0.10})
	ok(weak["verdict"] == "works", "1c planted weak grip (100 N, hold 2.56 < T 10) succeeds: %s" % weak["verdict"])
	var rank := {"grip holds": 0, "works": 1, "wrist breaks first": 2}
	var last := -1
	var seen := {}
	var mono := true
	for i in range(1, 101):
		var d := 0.01 * i
		var v: String = DisarmTruth.judge({"kind": "katana", "hands": 1, "grip_n": 400.0, "force_n": 100.0, "lever_m": d})["verdict"]
		var r: int = rank[v]
		if r < last:
			mono = false
		last = r
		seen[v] = true
	ok(mono, "2a verdict never steps back as the lever arm grows 0.01..1.00 m")
	ok(seen.size() == 3, "2b all three verdicts occur in the sweep (%s)" % [seen.keys()])
	var e1 := DisarmTruth.judge({"kind": "katana", "hands": 1, "grip_n": 400.0, "force_n": 100.0, "lever_m": 0.30})
	ok(e1["verdict"] == "wrist breaks first", "2c T=30 Nm on one wrist (>= 30) breaks it first: %s" % e1["verdict"])
	var h1 := DisarmTruth.judge({"kind": "katana", "hands": 1, "grip_n": 400.0, "force_n": 50.0, "lever_m": 0.20})
	var h2 := DisarmTruth.judge({"kind": "katana", "hands": 2, "grip_n": 400.0, "force_n": 50.0, "lever_m": 0.20})
	ok(float(h2["hold_nm"]) > float(h1["hold_nm"]) and h1["verdict"] == "works" and h2["verdict"] == "grip holds", "3a a second hand raises the hold (%.2f -> %.2f) and flips works -> grip holds" % [h1["hold_nm"], h2["hold_nm"]])
	var bk := DisarmTruth.judge({"kind": "katana", "grip": "one_hand", "force_n": 80.0})
	ok(int(bk["hands"]) == 1 and float(bk["lever_m"]) > 0.3 and float(bk["lever_m"]) < 1.0, "3b lever from the grip book: katana one_hand hands %d lever %.2f m" % [bk["hands"], bk["lever_m"]])
	var bk2 := DisarmTruth.judge({"kind": "katana", "grip": "two_hand", "force_n": 80.0})
	ok(int(bk2["hands"]) == 2, "3c book two_hand = 2 hands")
	ok(not DisarmTruth.judge({"kind": "katana", "grip": "nope"}).get("ok", true), "3d unknown grip refused")
	# ---- N048
	var worst_same := 0
	var worst_oor := 0
	var worst_los := 0
	var worst_win := 99
	var min_gap := 99.0
	var runs := 0
	for n in range(3, 7):
		for seed in 20:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 * n + seed
			var atk := []
			for i in n:
				var a := rng.randf() * TAU
				var d := rng.randf_range(1.5, 4.0)
				atk.append({"id": "a%d" % i, "pos": Vector2(sin(a) * d, cos(a) * d), "reach": 1.0})
			var plan := GroupFight.plan(atk)
			var c := GroupFight.check(plan, atk)
			worst_same = maxi(worst_same, int(c["same_side"]))
			worst_oor = maxi(worst_oor, int(c["out_of_reach"]))
			worst_los = maxi(worst_los, int(c["los"]))
			worst_win = mini(worst_win, int(c["min_windows"]))
			min_gap = minf(min_gap, float(c["min_wait_gap"]))
			runs += 1
	ok(worst_same == 0, "4a 0 simultaneous same-side attacks over %d scenarios of 3-6 attackers (worst %d)" % [runs, worst_same])
	ok(worst_oor == 0, "4b 0 out-of-reach starts (worst %d)" % worst_oor)
	ok(worst_los == 0, "4c 0 LOS-blocked concurrent attacks (worst %d)" % worst_los)
	ok(worst_win >= 1, "4d every attacker has >= 1 window (min %d)" % worst_win)
	ok(min_gap >= 0.75, "4e wait positions >= 0.75 m apart (min %.2f)" % min_gap)
	var atk6 := [{"id": "p", "pos": Vector2(0.2, 3.0), "reach": 1.0}, {"id": "q", "pos": Vector2(-0.2, 3.5), "reach": 1.0}, {"id": "r", "pos": Vector2(0, -3), "reach": 1.0}]
	var good := GroupFight.plan(atk6)
	ok(good["attacks"].size() >= 3 and good["waits"].size() == 3 and good["attacks"][0].has("t0") and good["waits"][0].has("pos"), "5a output is a timed schedule plus a wait position each")
	# planted bad schedule: p and q (same side, front) overlap; r starts from its far position; q has no window... (q listed, r has none)
	var bad := {"attacks": [{"id": "p", "t0": 0.0, "t1": 0.8, "from": Vector2(0.2, 0.9)}, {"id": "q", "t0": 0.2, "t1": 1.0, "from": Vector2(-0.2, 0.9)}, {"id": "r", "t0": 0.0, "t1": 0.8, "from": Vector2(0, -3)}], "waits": []}
	var cb := GroupFight.check(bad, atk6)
	ok(int(cb["same_side"]) >= 1, "6a planted same-side overlap flagged (%d)" % cb["same_side"])
	ok(int(cb["out_of_reach"]) >= 1, "6b planted far start flagged (%d)" % cb["out_of_reach"])
	var bad2 := {"attacks": [{"id": "p", "t0": 0.0, "t1": 0.8, "from": Vector2(0.2, 0.9)}], "waits": []}
	ok(int(GroupFight.check(bad2, atk6)["min_windows"]) == 0, "6c planted missing windows flagged")
	var tool_ok := Fight3Serve.serve("group_fight", null, {"attackers": [{"id": "a", "x": 0.0, "z": 3.0}, {"id": "b", "x": 3.0, "z": 0.0}, {"id": "c", "x": 0.0, "z": -3.0}]})
	ok(bool(tool_ok["ok"]) and int(tool_ok["result"]["checks"]["same_side"]) == 0, "7a agent tool group_fight serves a plan")
	var tool_d := Fight3Serve.serve("disarm_check", null, {"kind": "katana", "grip": "one_hand", "force_n": 80.0})
	ok(bool(tool_d["ok"]) and String(tool_d["result"]["verdict"]) != "", "7b agent tool disarm_check serves a verdict")
	print("fight3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
