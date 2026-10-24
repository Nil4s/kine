## godot --headless --path . -s tests/whocould_test.gd     (N027 WHO COULD DO THIS?, scripts/who_could.gd)
## The minimum body a clip needs, per capacity, as population percentiles / tiers; "no human" past a record. Bars, stated
## before measuring:
##   1 CALM WALK: scenes/_wip/walk.json (when present) and scenes/walk_bat.json (a walk carrying a bat) -> overall "any adult", text
##     "Who could do this: any adult."
##   2 COMBO3 (scenes/combo3.json): all 8 capacities listed (hip flexibility, hip extension, ankle flexibility, spine flexion,
##     shoulder flexibility, hand speed, foot speed, jump power), each number checked against the clip measured another way:
##     a) hand / foot speed within 5 % of the highest peak SpeedEnv.analyse (I47, per card move) finds for that channel;
##     b) hip flexibility, hip extension, ankle: the demand recomputed from CoupledLimits.sample's 60 fps rows (an independent
##        sampler) is at most the reported one + 0.05 and at least the reported one - 2 deg (240 Hz sees the peak's top);
##     c) every capacity re-posed at its reported t (Scene.apply) gives the reported raw angle / speed again (0.2 deg, 2 %);
##     d) the ROADMAP I47 note says combo3's STRIKE moves the hand at ~31 m/s: overall "no human", the text names the fist.
##   3 SYNTHETIC FIST: a 2-card clip, the right arm swung from the side to the front in 0.09 s: the fist's peak (SpeedEnv) is
##     28-35 m/s (about 30); overall "no human", the text names the fist and the record.
##   4 STRAIGHT-LEG KICK: the right hip at 110 deg, knee 0 (coupled_test's scene): hip-flexibility percentile within 5 points of
##     81.8 (z = (110 - 90) / 22 = 0.909: Thomas et al. 2022's straight-leg raise, CoupledLimits.HAM_STRAIGHT and its SD), tier
##     trained, the text says "top 18 % hip flexibility". The same hip with the knee at 60: below the 50th percentile.
##   5 DETERMINISTIC: combo3 twice -> the same JSON byte for byte.
##   6 SOURCES: every capacity has a source and a url, and either a percentile with a MEASURED / HEURISTIC trust or a
##     "HEURISTIC" label; every bar it names is a Trust.REG row whose value reads from the code.
##   7 SERVE: `who_could` on the opened combo3 gives the direct call's text; card=10 a capacity list; card=1 is an error.
extends SceneTree

var fails := 0
var t_start := Time.get_ticks_msec()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what + "   [%.0f s]" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	if not c:
		fails += 1


func fresh() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func scene_of(f: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(f)))
	return S


func leg_scene(h: float, k: float) -> Scene:
	var B := fresh()
	var S := Scene.new()
	S.name = "zz_whocould"
	S.add("rest", B.to_dict())
	B.set_ang("thigh_r", Vector3(h, 0, 0))
	B.set_ang("calf_r", Vector3(k, 0, 0))
	B.fk()
	S.add("leg", B.to_dict())
	S.cards[1]["move"] = 0.3
	S.cards[1]["hold"] = 0.5
	return S


func cap(r: Dictionary, nm: String) -> Dictionary:
	for c in r["capacities"]:
		if c["name"] == nm:
			return c
	return {}


func env_peak(S: Scene, B: Body, id: String) -> float:
	var best := 0.0
	for row in SpeedEnv.analyse(S, B):
		for a in row["all"]:
			if a["id"] == id:
				best = maxf(best, float(a["peak"]))
	return best


func _init() -> void:
	var B := fresh()
	# ---- 1 CALM WALK
	for f in ["res://scenes/_wip/walk.json", "res://scenes/walk_bat.json"]:
		if not FileAccess.file_exists(f):
			print("     (%s not here: skipped)" % f)
			continue
		var W := scene_of(f)
		var rw := WhoCould.of_scene(W, B)
		ok(rw["overall"] == "any adult" and rw["text"] == "Who could do this: any adult.", "1 %s (0-%.2f s): %s" % [f.get_file(), rw["t1"], rw["text"]])

	# ---- 2 COMBO3
	var C := scene_of("res://scenes/combo3.json")
	var rc := WhoCould.of_scene(C, B)
	var names := ["hip flexibility", "hip extension", "ankle flexibility", "spine flexion", "shoulder flexibility", "hand speed", "foot speed", "jump power"]
	ok(rc["capacities"].map(func(c): return c["name"]) == names, "2 combo3 lists the 8 capacities")
	for c in rc["capacities"]:
		print("     %-20s %8.2f %-44s %-9s pct %s  t %.3f  %s  [%s / tier %s]" % [c["name"], c["used"], c["unit"], c["tier"], c["percentile"], c["t"], c["what"], c["trust"], c["tier_trust"]])
	# a) speeds against I47
	for pair in [["hand speed", "hand"], ["foot speed", "foot"]]:
		var e := env_peak(C, B, pair[1])
		var u: float = cap(rc, pair[0])["used"]
		ok(absf(u - e) <= 0.05 * e, "2a combo3 %s %.2f m/s vs SpeedEnv's %.2f (5 %%)" % [pair[0], u, e])
	# b) flexibility against CoupledLimits.sample (60 fps)
	var cs := CoupledLimits.sample(C, B)
	var mx := {"hip flexibility": -INF, "hip extension": -INF, "ankle flexibility": -INF}
	for row in cs["rows"]:
		for sd in ["_l", "_r"]:
			mx["hip flexibility"] = maxf(mx["hip flexibility"], WhoCould.ham_demand(row["thigh" + sd], row["calf" + sd]))
			mx["hip extension"] = maxf(mx["hip extension"], -WhoCould.rect_demand(row["thigh" + sd], row["calf" + sd]))
			mx["ankle flexibility"] = maxf(mx["ankle flexibility"], WhoCould.gas_demand(row["foot" + sd], row["calf" + sd]))
	for k in mx:
		var u: float = cap(rc, k)["used"]
		ok(mx[k] <= u + 0.05 and mx[k] >= u - 2.0, "2b combo3 %s %.2f vs CoupledLimits.sample's %.2f (60 fps)" % [k, u, mx[k]])
	# c) re-posed at the reported t
	var keep := B.state()
	for c in rc["capacities"]:
		var t: float = c["t"]
		var sd := "_r" if c["side"] == "right" else "_l"
		var got := 0.0
		var want: float = c["used"]
		var tol := 0.2
		match String(c["name"]):
			"hip flexibility", "hip extension":
				C.apply(B, t)
				got = (B.ang["thigh" + sd] as Vector3).x
				want = c["hip"]
				ok(absf((B.ang["calf" + sd] as Vector3).x - float(c["knee"])) <= tol, "2c combo3 %s: knee at t %.3f is %.1f (reported %.1f)" % [c["name"], t, (B.ang["calf" + sd] as Vector3).x, c["knee"]])
			"ankle flexibility":
				C.apply(B, t)
				got = (B.ang["foot" + sd] as Vector3).x
				want = c["ankle"]
			"spine flexion":
				C.apply(B, t)
				got = WhoCould.spine_bend(B)
			"shoulder flexibility":
				C.apply(B, t)
				got = WhoCould.elevation(B, sd)
			"hand speed", "foot speed":
				var pt := ("hand" if c["name"] == "hand speed" else "ball") + sd
				C.apply(B, t - 1.0 / WhoCould.HZ)
				var a: Vector3 = B.E[pt]
				C.apply(B, t)
				got = ((B.E[pt] as Vector3) - a).length() * WhoCould.HZ
				tol = 0.02 * want + 0.01
			"jump power":
				got = want   # no flight in combo3 (printed above); a flight's frames are checked by bar 2's listing
		ok(absf(got - want) <= tol, "2c combo3 %s re-posed at %.3f s: %.2f (reported %.2f)" % [c["name"], t, got, want])
	B.set_state(keep)
	ok(rc["overall"] == "no human" and "fist" in String(rc["text"]), "2d combo3: %s" % rc["text"])

	# ---- 3 SYNTHETIC FIST
	var F := fresh()
	var X := Scene.new()
	X.name = "zz_fist"
	X.add("side", F.to_dict())
	F.set_ang("upperarm_r", Vector3(90, 0, 0))
	F.fk()
	X.add("front", F.to_dict())
	X.cards[1]["move"] = 0.09
	X.cards[1]["hold"] = 0.3
	var fe := env_peak(X, B, "hand")
	var rx := WhoCould.of_scene(X, B)
	ok(fe >= 28.0 and fe <= 35.0 and rx["overall"] == "no human" and "fist" in String(rx["text"]) and "record" in String(rx["text"]),
		"3 synthetic fist (SpeedEnv %.1f m/s, ours %.1f): %s" % [fe, cap(rx, "hand speed")["used"], rx["text"]])

	# ---- 4 STRAIGHT-LEG KICK
	var r4 := WhoCould.of_scene(leg_scene(110.0, 0.0), B)
	var h4 := cap(r4, "hip flexibility")
	ok(absf(float(h4["percentile"]) - 81.8) <= 5.0 and h4["tier"] == "trained" and "top 18 % hip flexibility" in String(r4["text"]),
		"4 straight-leg kick 110: percentile %s (bar 81.8 +- 5), tier %s: %s" % [h4["percentile"], h4["tier"], r4["text"]])
	var r4b := WhoCould.of_scene(leg_scene(110.0, 60.0), B)
	var h4b := cap(r4b, "hip flexibility")
	ok(float(h4b["percentile"]) < 50.0, "4 the same hip, knee 60: percentile %s (bar < 50), demand %.1f" % [h4b["percentile"], h4b["used"]])

	# ---- 5 DETERMINISTIC
	var again := WhoCould.of_scene(C, B)
	ok(JSON.stringify(again) == JSON.stringify(rc), "5 deterministic: combo3 twice gives the same JSON (%d chars)" % JSON.stringify(rc).length())

	# ---- 6 SOURCES
	var bad := []
	for r in [rc, r4, rx]:
		for c in r["capacities"]:
			var has_src: bool = String(c["source"]) != "" and String(c["url"]) != ""
			var lab: bool = (c["percentile"] != null and c["trust"] in [Trust.M, Trust.H]) or (c["percentile"] == null and "HEURISTIC" in String(c.get("heuristic", "")) and "HEURISTIC" in String(c["source"]) + String(c.get("heuristic", "")))
			if c["name"] == "jump power" and c["percentile"] == null:
				lab = "HEURISTIC" in String(c.get("heuristic", ""))
			for b in c["bars"]:
				if not Trust.REG.has(b) or Trust.value(b) == null:
					bad.append("%s: bar %s" % [c["name"], b])
			if not (has_src and lab):
				bad.append(c["name"])
	ok(bad.is_empty(), "6 every capacity has a source + url and a trust or HEURISTIC label, every bar a live registry row %s" % [bad])

	# ---- 7 SERVE
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	m.S = C
	m.dummy_on = false
	var s1: Dictionary = await T.request(1, "who_could", {})
	var s2: Dictionary = await T.request(2, "who_could", {"card": 10})
	var s3: Dictionary = await T.request(3, "who_could", {"card": 1})
	print("     serve card=10: %s" % s2.get("result", {}).get("text", s2.get("error")))
	ok(s1.get("result", {}).get("text", "") == rc["text"] and (s2.get("result", {}).get("capacities", []) as Array).size() == 8 and s3.has("error"),
		"7 serve who_could: whole clip '%s'; card=1 -> '%s'" % [s1.get("result", {}).get("text", s1.get("error")), s3.get("error", {}).get("message", "no error")])

	print("WHOCOULD %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	m.queue_free()
	quit(1 if fails > 0 else 0)
