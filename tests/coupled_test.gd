## godot --headless --path . -s tests/coupled_test.gd     (N028 COUPLED LIMITS, scripts/coupled_limits.gd)
## Two-joint muscles: the hip's flexion bar depends on the knee (hamstrings), the ankle's dorsiflexion on the knee
## (gastrocnemius), the hip's extension on the knee (rectus femoris). Bars, stated before measuring:
##   1 CURVES AT THE CITED POINTS (exact, 1e-6): hamstrings 90 at knee 0 (PSLR, Thomas 2022) and 120 at knee 60 (the table's hip
##     stop, reached at 30 / 0.5); gastrocnemius 25 at knee 0 and 39 at knee 20 (Baumbach 2014); rectus femoris -10.6 at knee 50
##     (Ferber 2010 / Peeler 2008) and 0 at knee 90 (Kendall via Peeler).
##   2 CONTINUOUS + MONOTONIC: each curve sampled every 0.05 deg of knee bend over 0..145: no step bigger than 0.05 x its
##     steepest segment's slope + 1e-4 (continuity), and never decreasing (a bent knee never lowers the hip-flexion or the
##     dorsiflexion bar, never lowers the extension bar's floor: every curve rises with knee bend).
##   3 STRAIGHT-LEG KICK: a 2-card scene, the right hip at 110 deg with the knee at 0: HumanLimits.findings has a COUPLED LIMIT
##     finding on thigh_r, WARN, its text names the hamstrings, "Thomas et al. 2022", the 90 deg bar and the knee bend that would
##     pass (40 deg).
##   4 BENT KNEE: the same hip 110 with the knee at 60: no COUPLED LIMIT finding.
##   5 TRUST: every bar of every coupling is a Trust.REG row with a file constant; MEASURED rows have a doi.org url, the only
##     UNVERIFIED rows are the one-joint table's (*_MAX); Trust.RULES has "COUPLED LIMIT"; Rulebook has its SRC, WHY and URL.
##   6 SERVE `limits`: thigh_r with {"calf_r": 0} -> healthy-adult bend max 90 and the text names the hamstrings; with
##     {"knee": 60} -> 120; calf_r with the hip at 110 -> knee at least 40; foot_r with the knee straight says the table
##     (25) is the tighter bar; an unknown joint is -32602.
##   7 OPT-IN CLAMP: by default set_ang puts the hip at 110 with a straight knee (unchanged behaviour); with
##     Body.coupled_clamp = 1 it stops at 90, and set_ang_safe's last_stop says "coupled" with the hamstring reason; the knee then cannot
##     straighten past 40 with the hip at 110.
##   8 FEASIBLE + NO DOUBLE: the 110 straight-leg kick adds no COUPLED LIMIT to Feasible (a WARN is a trained person's range);
##     a hip extended 25 deg with the knee at 90 (past mean - 2 SD, -19.2) does, as FAIL; Rulebook.check (human limits on) lists
##     that FAIL once, not twice.
##   9 NICK'S SCENES (scenes/*.json, read only): their COUPLED LIMIT findings are printed per scene. Bar: none flagged (stated from
##     a scan of their key poses before this test: no straight-knee hip above 85, every bent-knee hip inside its curve).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fresh() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


## a 2-card scene: rest, then the right leg at hip h / knee k (and an optional extra joint), held 0.5 s
func leg_scene(h: float, k: float, extra := {}) -> Scene:
	var B := fresh()
	var S := Scene.new()
	S.name = "zz_coupled"
	S.add("rest", B.to_dict())
	B.set_ang("thigh_r", Vector3(h, 0, 0))
	B.set_ang("calf_r", Vector3(k, 0, 0))
	for j in extra:
		B.set_ang(j, extra[j])
	B.fk()
	S.add("leg", B.to_dict())
	S.cards[1]["move"] = 0.3
	S.cards[1]["hold"] = 0.5
	return S


func coupled(fs: Array) -> Array:
	return fs.filter(func(f): return f["rule"] == "COUPLED LIMIT")


func _init() -> void:
	var cs := CoupledLimits.couplings()
	var by := {}
	for c in cs:
		by[c["id"]] = c
	var H: Array = by["hamstrings"]["curve"]
	var G: Array = by["gastrocnemius"]["curve"]
	var R: Array = by["rectus femoris"]["curve"]
	var at := CoupledLimits.at
	# 1
	var pts := [[H, 0.0, 90.0], [H, 60.0, 120.0], [G, 0.0, 25.0], [G, 20.0, 39.0], [R, 50.0, -10.6], [R, 90.0, 0.0]]
	var bad1 := pts.filter(func(p): return absf(at.call(p[0], p[1]) - float(p[2])) > 1e-6)
	ok(bad1.is_empty(), "1 the curves pass the cited points: hamstrings 90 @0 / 120 @60, gastrocnemius 25 @0 / 39 @20, rectus -10.6 @50 / 0 @90 (off: %s)" % [bad1])
	# 2
	for c in cs:
		var cv: Array = c["curve"]
		var steep := 0.0
		for i in range(1, cv.size()):
			steep = maxf(steep, absf((float(cv[i][1]) - float(cv[i - 1][1])) / maxf(float(cv[i][0]) - float(cv[i - 1][0]), 1e-9)))
		var worst_step := 0.0
		var drops := 0
		var prev: float = at.call(cv, 0.0)
		for i in range(1, 2901):
			var y: float = at.call(cv, i * 0.05)
			worst_step = maxf(worst_step, absf(y - prev))
			if y < prev - 1e-9:
				drops += 1
			prev = y
		ok(worst_step <= 0.05 * steep + 1e-4 and drops == 0, "2 %s: continuous (largest step %.4f deg per 0.05 deg, bound %.4f) and never decreasing (%d drops)" % [
			c["id"], worst_step, 0.05 * steep + 1e-4, drops])
	# 3
	var B := fresh()
	var K := leg_scene(110.0, 0.0)
	var kf := coupled(HumanLimits.findings(K, B)).filter(func(f): return f["joint"] == "thigh_r")
	var km: String = kf[0]["msg"] if kf.size() > 0 else "none"
	ok(kf.size() == 1 and kf[0]["sev"] == "WARN" and "hamstrings" in km and "Thomas et al. 2022" in km and "90 deg" in km and "bend the knee to 40 deg" in km and "lower the leg to 90 deg" in km,
		"3 straight-leg kick, hip 110 / knee 0: flagged once, WARN, hamstrings + source + 90 bar + 40 deg fix: %s" % km)
	# 4
	var Kb := leg_scene(110.0, 60.0)
	var bf := coupled(HumanLimits.findings(Kb, B))
	ok(bf.is_empty(), "4 the same hip 110 with the knee bent 60: no COUPLED LIMIT finding (%s)" % [bf.map(func(f): return f["msg"])])
	# 5
	var badrows := []
	var src := FileAccess.get_file_as_string("res://scripts/coupled_limits.gd")
	for c in cs:
		for n in c["bars"]:
			if not Trust.REG.has(n):
				badrows.append("%s: no registry row" % n)
				continue
			var r: Dictionary = Trust.REG[n]
			if not ("const " + String(n).split(".")[1] + " :=") in src or Trust.value(n) == null:
				badrows.append("%s: no constant" % n)
			if r["s"] == Trust.M and not String(r["url"]).begins_with("https://doi.org/"):
				badrows.append("%s: MEASURED without a doi" % n)
			if r["s"] == Trust.U and not String(n).ends_with("_MAX"):
				badrows.append("%s: UNVERIFIED outside the table rows" % n)
	ok(badrows.is_empty() and Trust.RULES.has("COUPLED LIMIT") and Rulebook.SRC.has("COUPLED LIMIT") and Rulebook.WHY.has("COUPLED LIMIT") and Rulebook.URL.has("COUPLED LIMIT"),
		"5 every coupling's bars have a trust row (M with a doi / H / U only for the table), rule registered: %s; per coupling %s" % [
			badrows, cs.map(func(c): return "%s %s" % [c["id"], CoupledLimits.trust_of(c)])])
	# 6
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var A := AgentTools.new(m)
	var l0: Dictionary = await A.request(1, "limits", {"joint": "thigh_r", "other_angles": {"calf_r": 0}})
	var l1: Dictionary = await A.request(2, "limits", {"joint": "right hip", "other_angles": {"knee": 60}})
	var l2: Dictionary = await A.request(3, "limits", {"joint": "calf_r", "other_angles": {"thigh_r": 110}})
	var l3: Dictionary = await A.request(4, "limits", {"joint": "foot_r", "other_angles": {"calf_r": 0}})
	var l4: Dictionary = await A.request(5, "limits", {"joint": "tail"})
	var r0: Dictionary = l0.get("result", {})
	var r1: Dictionary = l1.get("result", {})
	var r2: Dictionary = l2.get("result", {})
	var r3: Dictionary = l3.get("result", {})
	print("     limits thigh_r knee 0: ", JSON.stringify(r0).left(900))
	ok(absf(float(r0["bend"]["warn"][1]) - 90.0) < 1e-6 and "hamstrings" in String(r0["say"]) and absf(float(r1["bend"]["warn"][1]) - 120.0) < 1e-6
		and absf(float(r2["bend"]["warn"][0]) - 40.0) < 1e-6 and "the table is tighter" in String(r3["say"])
		and l4.has("error") and int(l4["error"]["code"]) == -32602,
		"6 serve limits: hip max %.0f @knee 0, %.0f @knee 60; knee min %.0f @hip 110; ankle: %s; bad joint -> %s" % [
			r0["bend"]["warn"][1], r1["bend"]["warn"][1], r2["bend"]["warn"][0], String(r3["say"]).right(160), l4.get("error", {}).get("code")])
	m.queue_free()
	# 7
	var C := fresh()
	C.set_ang("thigh_r", Vector3(110, 0, 0))   # set_ang: the table clamp alone (set_ang_safe also stops at contacts: 97.6 here)
	var def_h: float = (C.ang["thigh_r"] as Vector3).x
	var C2 := fresh()
	C2.coupled_clamp = 1
	C2.set_ang("thigh_r", Vector3(110, 0, 0))
	var cl_h: float = (C2.ang["thigh_r"] as Vector3).x
	C2.set_ang("thigh_r", Vector3.ZERO)
	C2.last_stop = {}
	C2.set_ang_safe("thigh_r", Vector3(110, 0, 0))   # 90 is short of the 97.6 contact: the coupling is what stops it
	var stop: Dictionary = C2.last_stop.duplicate()
	var C3 := fresh()
	C3.set_ang("calf_r", Vector3(60, 0, 0))
	C3.set_ang("thigh_r", Vector3(110, 0, 0))
	C3.coupled_clamp = 1
	C3.set_ang_safe("calf_r", Vector3(0, 0, 0))
	var cl_k: float = (C3.ang["calf_r"] as Vector3).x
	ok(absf(def_h - 110.0) < 1e-4 and absf(cl_h - 90.0) < 1e-4 and stop.get("kind", "") == "coupled" and "hamstrings" in String(stop.get("why", ""))
		and absf(cl_k - 40.0) < 1e-4,
		"7 clamp: default hip %.1f (unchanged), opt-in %.1f, stop '%s'; knee straightened under hip 110 stops at %.1f" % [def_h, cl_h, stop.get("kind", ""), cl_k])
	# 8
	var fk := Feasible.check(K, B)
	var fk_c := coupled(fk["findings"])
	var X := leg_scene(-25.0, 90.0)
	var fx := Feasible.check(X, B)
	var fx_c := coupled(fx["findings"])
	HumanLimits.on = true
	var rx := coupled(Rulebook.check(X, B))
	HumanLimits.on = false
	ok(fk_c.is_empty() and fx_c.size() == 1 and fx_c[0]["sev"] == "FAIL" and "rectus femoris" in String(fx_c[0]["msg"]) and fx["verdict"] != "PASS" and rx.size() == 1,
		"8 Feasible: straight kick adds %d; hip -25 / knee 90: %d FAIL (verdict %s); Check lists it %d time(s): %s" % [
			fk_c.size(), fx_c.size(), fx["verdict"], rx.size(), fx_c[0]["msg"] if fx_c.size() > 0 else "none"])
	# 9
	var flagged := []
	var da := DirAccess.open("res://scenes")
	var names := Array(da.get_files()).filter(func(f): return f.ends_with(".json"))
	names.sort()
	for fn in names:
		var N := Scene.new()
		N.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn)))
		var nf := CoupledLimits.findings(N, B)
		print("     scene %-22s %d coupled finding(s) %s" % [fn, nf.size(), nf.map(func(f): return "%s %s %.2f-%.2f over %.1f" % [f["sev"], f["joint"], f["t"], f["t1"], f["v"]])])
		for f in nf:
			print("       ", f["msg"])
		if not nf.is_empty():
			flagged.append(fn)
	ok(flagged.is_empty(), "9 Nick's %d scenes: flagged %s" % [names.size(), flagged])

	print("COUPLED TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
