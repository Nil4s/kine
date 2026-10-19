## godot --headless --path . -s tests/human_limits_test.gd     (ROADMAP 10, "could a human do this?")
## JOINT SPEED, JOINT TORQUE and TIPPING (scripts/human_limits.gd; sources in docs/research/HUMAN_LIMITS.md).
## 1. a 0.05 s full arm swing (upper arm 180 deg, from -45 to 135) must flag the shoulder's speed AND its torque;
## 2. the shipped walk (scenes/walk_bat.json, read only) must flag nothing from these three rules;
## 3. the tipping bar on hand-built series: 30 cm past the feet for 1 s flags, for 0.1 s does not, and a hand on
##    something stands it down. (Series, not a real body: the body lean is already covered by balance_test.)
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

	# the limits as printed (the numbers the findings quote)
	var kn := HumanLimits.knee_limit(75.0)
	var sh := HumanLimits.shoulder_limit(75.0)
	ok(absf(kn - 184.7) < 1e-6 and absf(sh - 52.5) < 1e-6,
		"0 bars at 75 kg: knee %.1f Nm (mean 184.7), shoulder %.1f Nm (0.70 Nm/kg x 75)" % [kn, sh])

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
	print("     swing: shoulder_r peak turn %.0f deg/s (bar 4766 / FAIL 6310), peak moment %.0f Nm (bar %.1f / FAIL %.1f)" % [
		peak_sp, peak_tq, sh, sh * HumanLimits.SHOULDER_NM_KG[1] / HumanLimits.SHOULDER_NM_KG[0]])
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

	print("HUMAN LIMITS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
