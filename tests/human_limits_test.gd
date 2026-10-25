## godot --headless --path . -s tests/human_limits_test.gd     (ROADMAP 10, "could a human do this?")
## JOINT SPEED, JOINT TORQUE and TIPPING (scripts/human_limits.gd; sources in docs/research/HUMAN_LIMITS.md).
## 1. a 0.05 s full arm swing (upper arm 180 deg, from -45 to 135) must flag the shoulder's speed AND its torque;
## 2. the shipped walk (scenes/walk_bat.json, read only) must flag nothing from these three rules;
## 3. the tipping bar on hand-built series: 30 cm past the feet for 1 s flags, for 0.1 s does not, and a hand on
##    something stands it down. (Series, not a real body: the body lean is already covered by balance_test.)
## 4. Nick's real bat swing (scenes/combo3.json, read only): its joint speeds against the in-sport bars, printed as margins;
##    passes when no joint-speed FAIL (a WARN is a peak over the in-sport peak, not an impossible frame).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the body with its right upper arm bent to b degrees (forward), as a pose dict; the body is reloaded after
func arm(B: Body, b: float) -> Dictionary:
	B.set_ang("upperarm_r", Vector3(b, 0, 0))
	B.fk()
	var d := B.to_dict()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return d


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()

	# the bars as printed (the numbers the findings quote)
	var sb := HumanLimits.shoulder_bars(75.0)
	ok(absf(float(sb[0]) - 67.0) < 1e-6 and absf(float(sb[1]) - 67.0 * HumanLimits.FAIL_K) < 1e-6,
		"0 torque bar at 75 kg: shoulder %.1f Nm (in-sport peak 67), FAIL %.1f" % [sb[0], sb[1]])
	ok(absf(HumanLimits.bars("shoulder")[0] - 6520.0) < 1e-6 and absf(HumanLimits.bars("trunk")[0] - 1120.0) < 1e-6,
		"0 speed bars: shoulder 6520, trunk 1120 deg/s (in-sport peaks); FAIL = %.3f x" % HumanLimits.FAIL_K)

	# 1. the swing
	var S := Scene.new()
	S.name = "zz_swing"
	S.add("rest", arm(B, -45.0))
	S.add("swing", arm(B, 135.0))
	S.cards[1]["move"] = 0.05
	var sm := HumanLimits.sample(S, B)
	var sp: Array = sm["speed"]["shoulder_r"]
	var tq: Array = sm["torque"]["shoulder_r"]
	var peak_sp := 0.0
	var peak_tq := 0.0
	for v in sp:
		peak_sp = maxf(peak_sp, float(v))
	for v in tq:
		peak_tq = maxf(peak_tq, float(v))
	print("     swing: shoulder_r peak turn %.0f deg/s (bar %.0f / FAIL %.0f), peak moment %.0f Nm (bar %.1f / FAIL %.1f)" % [
		peak_sp, HumanLimits.bars("shoulder")[0], HumanLimits.bars("shoulder")[1], peak_tq, sb[0], sb[1]])
	var fs := HumanLimits.findings(S, B, sm, true)
	var sp_f := fs.filter(func(f): return f["rule"] == "JOINT SPEED" and "shoulder r" in f["msg"])
	var tq_f := fs.filter(func(f): return f["rule"] == "JOINT TORQUE" and "shoulder r" in f["msg"])
	ok(sp_f.size() >= 1, "1 swing: shoulder_r speed flagged (%d finding(s)): %s" % [sp_f.size(), sp_f[0]["msg"] if sp_f.size() > 0 else "none"])
	ok(tq_f.size() >= 1, "2 swing: shoulder_r torque flagged (%d finding(s)): %s" % [tq_f.size(), tq_f[0]["msg"] if tq_f.size() > 0 else "none"])

	# 2. the walk: read only
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var wf := HumanLimits.findings(W, B)
	var mine := wf.filter(func(f): return f["rule"] in ["JOINT SPEED", "JOINT TORQUE", "TIPPING"])
	for f in mine:
		print("     walk finding: %s %s t=%.2f %s" % [f["sev"], f["rule"], f["t"], f["msg"]])
	ok(mine.is_empty(), "3 walk_bat (read only): no joint-speed, joint-torque or tipping finding (%d)" % mine.size())

	# 3. tipping on series: margin (+ inside, - past the feet), height, foot down, hand or weapon holding
	var n := 120
	var t := []
	var h := []
	var dn := []
	var sup := []
	for i in n:
		t.append(i / 60.0)
		h.append(0.9)
		dn.append(true)
		sup.append(false)
	var m1 := []
	var m6 := []
	for i in n:
		m1.append(-0.30 if i < 60 else 0.05)
		m6.append(-0.30 if i < 6 else 0.05)
	var tip1 := HumanLimits.rule_tipping({"t": t, "margin": m1, "h": h, "down": dn, "sup": sup})
	ok(tip1.size() == 1 and tip1[0]["rule"] == "TIPPING" and absf(float(tip1[0]["v"]) - 1.0) < 1e-6,
		"4 30 cm past the feet for 1 s, h 0.9 m (fall %.2f s): flagged: %s" % [sqrt(2.0 * 0.9 / 9.81), tip1[0]["msg"] if tip1.size() > 0 else "none"])
	var tip6 := HumanLimits.rule_tipping({"t": t, "margin": m6, "h": h, "down": dn, "sup": sup})
	ok(tip6.is_empty(), "5 the same 30 cm for 0.1 s: not flagged")
	var held := sup.map(func(_x): return true)
	var tip_h := HumanLimits.rule_tipping({"t": t, "margin": m1, "h": h, "down": dn, "sup": held})
	ok(tip_h.is_empty(), "6 the 1 s lean with a hand on something: not flagged")
	var tip_nd := HumanLimits.rule_tipping({"t": t, "margin": m1, "h": h, "down": dn.map(func(_x): return false), "sup": sup})
	ok(tip_nd.is_empty(), "7 the 1 s lean with no foot down (a jump): not graded here")

	# 4. Nick's bat swing: the speed bars against the real swing (margins printed, read only)
	var C := Scene.new()
	C.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var cm := HumanLimits.sample(C, B)
	var cf := HumanLimits.findings(C, B, cm)
	for j in cm["speed"]:
		var kind: String = String(j).split("_")[0]
		var pk := 0.0
		for v in cm["speed"][j]:
			pk = maxf(pk, float(v))
		var bar: Array = HumanLimits.bars(kind)
		print("     combo3 %-11s peak %6.0f deg/s  WARN %5.0f (margin %+5.1f%%)  FAIL %5.0f" % [
			j, pk, bar[0], (pk / float(bar[0]) - 1.0) * 100.0, bar[1]])
	var cspeed := cf.filter(func(f): return f["rule"] == "JOINT SPEED")
	var cfail := cspeed.filter(func(f): return f["sev"] == "FAIL")
	for f in cspeed:
		print("     combo3 finding: %s t=%.2f %s" % [f["sev"], f["t"], f["msg"]])
	ok(cfail.is_empty(), "8 combo3 bat swing (read only): no joint-speed FAIL with the in-sport bars (%d WARN, %d FAIL)" % [cspeed.size() - cfail.size(), cfail.size()])

	# 5. the knee at 3 x and at 0.9 x the cited peak (Manolopoulos 2006, 1874 deg/s): one frame (1/60 s) of calf bend.
	# (The shoulder cannot be built at 3 x: 3 x 6520 deg/s is 326 deg per 60 fps frame, past the 180 deg a rotation can show.)
	var kp := 1874.0
	for case in [[3.0, true], [0.9, false]]:
		var deg: float = kp * float(case[0]) / HumanLimits.FPS
		var K := Scene.new()
		K.name = "zz_knee"
		B.set_ang("calf_r", Vector3(0, 0, 0))
		B.fk()
		K.add("rest", B.to_dict())
		B.set_ang("calf_r", Vector3(deg, 0, 0))
		B.fk()
		K.add("kick", B.to_dict())
		B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		B.fk()
		K.cards[1]["move"] = 1.0 / 60.0
		var kf := HumanLimits.findings(K, B).filter(func(f): return f["rule"] == "JOINT SPEED" and f.get("joint", "") == "knee_r")
		if case[1]:
			ok(kf.size() >= 1 and "Manolopoulos 2006" in kf[0]["msg"] and kf[0]["sev"] == "FAIL",
				"9 knee at 3 x the cited peak (%.0f deg in one frame): FAIL on knee_r, reason names the source: %s" % [deg, kf[0]["msg"] if kf.size() > 0 else "none"])
		else:
			ok(kf.is_empty(), "10 knee at 0.9 x the cited peak (%.0f deg in one frame): not flagged" % deg)

	print("HUMAN LIMITS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
