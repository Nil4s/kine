## godot --headless --path . -s tests/rules_test.gd      (GATES I4, I5)
## Every rule in scripts/rulebook.gd fed a series broken on purpose (it must fire) and a good one (it must stay quiet);
## then real scenes: Nick's combo3 flags the head at ~3.1 s, the smooth scenes come out clean.
extends SceneTree

var fails := 0
const F := Rulebook.FPS


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a series of n frames: base everywhere, a bell of height h centred on frame c with half-width w
func bell(n: int, c: int, w: int, h: float, base := 0.0) -> Array:
	var s := []
	for i in n:
		var x := float(i - c) / w
		s.append(base + (h * exp(-x * x) if absf(x) < 3.0 else 0.0))
	return s


func sm_of(n: int) -> Dictionary:
	var t := []
	var hp := []
	var fy := []
	for i in n:
		t.append(i / F)
		hp.append(Vector3(0, 1.6, 0))
		fy.append(0.05)
	return {"t": t, "tip": bell(n, 60, 6, 30.0), "hips": bell(n, 60, 10, 1.0), "head": bell(n, 60, 10, 0.5),
		"hand_l": bell(n, 60, 6, 5.0), "hand_r": bell(n, 60, 6, 5.0), "w_pelvis": bell(n, 45, 8, 400.0),
		"w_trunk": bell(n, 52, 8, 600.0), "w_weapon": bell(n, 60, 6, 2000.0), "head_pos": hp, "foot_y": fy,
		"armed": true, "kind": "metal_bat", "spline": true}


func rules(fs: Array) -> Array:
	return fs.map(func(f): return "%s %s" % [f["sev"], f["rule"]])


func _init() -> void:
	var n := 120
	var good := sm_of(n)
	var st: Dictionary = Rulebook.strikes(good["tip"])[0]
	ok(Rulebook.strikes(good["tip"]).size() == 1 and st["pk"] == 60, "strikes: one bell = one strike at its peak (frame %d)" % st["pk"])

	# SEQUENCE / HIPS TURN
	ok(Rulebook.rule_sequence(good, st).is_empty(), "SEQUENCE quiet on hips -> chest -> weapon")
	var late := sm_of(n)
	late["w_pelvis"] = bell(n, 62, 8, 400.0)
	ok(rules(Rulebook.rule_sequence(late, st)) == ["FAIL SEQUENCE"], "SEQUENCE fires: hips peak after the weapon -> %s" % str(rules(Rulebook.rule_sequence(late, st))))
	var chest := sm_of(n)
	chest["w_trunk"] = bell(n, 63, 8, 600.0)
	ok(rules(Rulebook.rule_sequence(chest, st)) == ["FAIL SEQUENCE"], "SEQUENCE fires: chest after the weapon")
	var still := sm_of(n)
	still["w_pelvis"] = bell(n, 45, 8, 40.0)
	ok(rules(Rulebook.rule_sequence(still, st)) == ["WARN HIPS TURN"], "HIPS TURN fires: hips peak 40 deg/s")

	# HEAD QUIET
	ok(Rulebook.rule_head(good, st).is_empty(), "HEAD QUIET quiet on a still head")
	var nod := sm_of(n)
	for i in n:
		nod["head_pos"][i] = Vector3(0, 1.6 - 0.05 * clampf((i - 45) / 15.0, 0.0, 1.0), 0)
	ok(Rulebook.rule_head(nod, st).is_empty(), "HEAD QUIET quiet on a 5 cm drop (hitters drop ~9)")
	var lurch := sm_of(n)
	for i in n:
		lurch["head_pos"][i] = Vector3(0.4 * clampf((i - 45) / 15.0, 0.0, 1.0), 1.6, 0)
	ok(rules(Rulebook.rule_head(lurch, st)) == ["FAIL HEAD QUIET"], "HEAD QUIET fires: 40 cm")
	var jump := lurch.duplicate(true)
	for i in range(50, 70):
		jump["foot_y"][i] = 0.4
	ok(Rulebook.rule_head(jump, st).is_empty(), "HEAD QUIET stands down when the feet leave the ground")

	# TIP SPEED / STRIKE FRAMES
	ok(Rulebook.rule_weapon(good, st).is_empty(), "TIP SPEED quiet at 30 m/s on a bat (cap 40)")
	var fast := sm_of(n)
	fast["tip"] = bell(n, 60, 6, 50.0)
	ok(rules(Rulebook.rule_weapon(fast, Rulebook.strikes(fast["tip"])[0])) == ["FAIL TIP SPEED"], "TIP SPEED fires at 50 m/s")
	var slow := sm_of(n)
	slow["tip"] = bell(n, 60, 14, 30.0)
	ok(rules(Rulebook.rule_weapon(slow, Rulebook.strikes(slow["tip"])[0])) == ["WARN STRIKE FRAMES"], "STRIKE FRAMES fires on a wide swing (%d frames at 60)" % (Rulebook.strikes(slow["tip"])[0]["b"] - Rulebook.strikes(slow["tip"])[0]["a"] + 1))
	var unarmed_tip := fast.duplicate(true)
	unarmed_tip["armed"] = false
	ok(Rulebook.rule_weapon(unarmed_tip, st).is_empty(), "weapon rules stand down with no weapon")

	# FIST SPEED
	var bare := sm_of(n)
	bare["armed"] = false
	ok(Rulebook.rule_fist(bare).is_empty(), "FIST quiet at 5 m/s")
	bare["hand_r"] = bell(n, 60, 6, 13.0)
	ok(rules(Rulebook.rule_fist(bare)) == ["WARN FIST SPEED"], "FIST warns at 13 m/s")
	bare["hand_r"] = bell(n, 60, 6, 17.0)
	ok(rules(Rulebook.rule_fist(bare)) == ["FAIL FIST SPEED"], "FIST fails at 17 m/s (over 11.95 + 2 x 1.84)")
	ok(Rulebook.rule_fist(fast).is_empty(), "FIST stands down when armed")

	# HITCH
	ok(Rulebook.rule_hitch(good, []).is_empty(), "HITCH quiet on one bell per part")
	var stop := sm_of(n)
	stop["tip"][60] = 0.0
	var h := Rulebook.rule_hitch(stop, [])
	ok(rules(h) == ["WARN HITCH"], "HITCH fires on a dead stop mid-swing -> %s" % str(rules(h)))
	ok(Rulebook.rule_hitch(stop, [[59.0 / F, 61.0 / F]]).is_empty(), "HITCH stands down inside a card's hold")
	var all3 := stop.duplicate(true)
	all3["hips"][60] = 0.0
	all3["head"][60] = 0.0
	all3["head"] = bell(n, 60, 10, 2.0)
	all3["head"][60] = 0.0
	all3["hips"] = bell(n, 60, 10, 2.0)
	all3["hips"][60] = 0.0
	ok(Rulebook.rule_hitch(all3, []).size() == 1, "HITCH: tip + hips + head stopping together = ONE finding")

	# FOOT SLIDE (Karunratanakul 2023: down = under 5 cm, skating = over 2.5 cm; here over a settled stretch)
	var feet := {"t": good["t"], "ball_l": [], "ball_r": []}
	for i in n:
		feet["ball_l"].append(Vector3(0.2, 0.025, 0.0))
		feet["ball_r"].append(Vector3(-0.2, 0.025, 0.0))
	ok(Rulebook.rule_feet(feet).is_empty(), "FOOT SLIDE quiet on two feet standing still")
	var creep := feet.duplicate(true)
	for i in n:
		creep["ball_l"][i] = Vector3(0.2 + 0.0008 * i, 0.025, 0.0)   # 0.8 mm a frame (5 cm/s): slow, settled, creeping
	var fc := Rulebook.rule_feet(creep)
	ok(rules(fc) == ["WARN FOOT SLIDE"] and fc[0]["v"] > 0.09, "FOOT SLIDE fires on a foot creeping 0.8 mm a frame (%.1f cm)" % (fc[0]["v"] * 100.0 if not fc.is_empty() else 0.0))
	var land := feet.duplicate(true)
	for i in n:   # a step: lifts, travels 40 cm fast, lands and stands
		var u := clampf((i - 40) / 20.0, 0.0, 1.0)
		land["ball_l"][i] = Vector3(0.2 + 0.4 * u, 0.025 + 0.08 * sin(PI * u), 0.0)
	ok(Rulebook.rule_feet(land).is_empty(), "FOOT SLIDE quiet on a step: the fast lift-off and landing near the floor are not skating")
	var pivot := feet.duplicate(true)
	for i in n:
		pivot["ball_l"][i] = Vector3(0.2 + 0.0002 * i, 0.025, 0.0)   # 2.4 cm over 2 s: just under the bar
	ok(Rulebook.rule_feet(pivot).is_empty(), "FOOT SLIDE quiet on 2.4 cm of creep (bar 2.5)")
	var lifted := creep.duplicate(true)
	for i in n:
		lifted["ball_l"][i].y = 0.08
	ok(Rulebook.rule_feet(lifted).is_empty(), "FOOT SLIDE stands down for a foot in the air (8 cm)")

	# real scenes
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	S.name = "combo3"
	var head := Rulebook.check(S, B).filter(func(f): return f["rule"] == "HEAD QUIET")
	ok(head.size() == 1 and head[0]["sev"] == "FAIL" and absf(head[0]["t"] - 3.1) < 0.1, "combo3: the head lurch flagged near 3.1 s (%s)" % str(head.map(func(f): return "%s %.2f" % [f["sev"], f["t"]])))
	for nm in ["swing_fore_detail", "swing_fore_flow"]:
		S = Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/_wip/%s.json" % nm)))
		S.name = nm
		var fs := Rulebook.check(S, B)
		ok(fs.is_empty(), "%s (spline) comes out clean: %d findings" % [nm, fs.size()])
	print("RULES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
