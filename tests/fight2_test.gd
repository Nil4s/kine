## godot --headless --path . -s tests/fight2_test.gd     (L72: N034 impact alignment, N042 hit reaction by body region, N046 body collision)
## N034 (scripts/impact_align.gd): at the contact frame a punch with the wrist bent / deviated, a kick with the knee locked, a wrist past the
##   safe load line are FLAGGED with the angle and a fix pose; a clean punch / kick is NOT.
## N042 (scripts/region_react.gd): 4 planted hits (liver, chin, thigh, solar plexus) each pick their own region and signature; amplitude grows
##   monotonically with the impulse; every joint stays inside data/body_limits.json.
## N046 (scripts/body_collide.gd): a shoulder charge shares momentum by de Leva masses: total momentum conserved within 5%, the lighter body
##   moves more, both bodies are keyed.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func rules(r: Dictionary) -> Array:
	var o := []
	for f in r["flags"]:
		o.append(f["rule"])
	return o


func load_scene(p: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return S


func _init() -> void:
	# ---- N034
	var clean := {"hand_r": Vector3(2, 3, 0), "lowerarm_r": Vector3(40, 0, 0), "calf_r": Vector3(25, 0, 0), "calf_l": Vector3(20, 0, 0)}
	var r0 := ImpactAlign.check(clean, "punch", "r")
	ok(r0["flags"].is_empty(), "1a clean punch (wrist 2/3 deg, elbow 40) not flagged %s" % [rules(r0)])
	var bent := {"hand_r": Vector3(28, 4, 0), "lowerarm_r": Vector3(40, 0, 0)}
	var r1 := ImpactAlign.check(bent, "punch", "r")
	ok("WRIST BENT" in rules(r1), "1b planted bent-wrist punch (28 deg) flagged %s" % [rules(r1)])
	if not r1["flags"].is_empty():
		var f: Dictionary = r1["flags"][0]
		ok(absf(float(f["deg"]) - 28.0) < 0.01 and f.has("fix") and absf((f["fix"]["hand_r"] as Vector3).x) < 5.0, "1c flag carries the angle (%.1f) and a fix pose with a straight wrist" % float(f["deg"]))
	var load_pose := {"hand_r": Vector3(45, 0, 0), "lowerarm_r": Vector3(40, 0, 0)}
	ok("WRIST LOAD" in rules(ImpactAlign.check(load_pose, "punch", "r")), "1d wrist at 45 deg is past the safe load line")
	var lock := {"calf_l": Vector3(2, 0, 0), "calf_r": Vector3(60, 0, 0), "hand_r": Vector3.ZERO}
	var k1 := ImpactAlign.check(lock, "kick", "l")
	ok("KNEE LOCKED" in rules(k1), "1e planted locked-knee kick flagged %s" % [rules(k1)])
	if not k1["flags"].is_empty():
		ok((k1["flags"][0]["fix"]["calf_l"] as Vector3).x >= 10.0, "1f fix pose bends the kicking knee to >= 10 deg")
	var k0 := ImpactAlign.check({"calf_l": Vector3(18, 0, 0)}, "kick", "l")
	ok(k0["flags"].is_empty(), "1g clean kick (knee 18 deg) not flagged")
	var miss := {"hand_r": Vector3(0, 0, 0), "lowerarm_r": Vector3(3, 0, 0)}
	ok("ELBOW SNAP" in rules(ImpactAlign.check(miss, "punch", "r", true)) and ImpactAlign.check(miss, "punch", "r", false)["flags"].is_empty(), "1h a punch that misses with the elbow snapped straight is flagged; the same arm on a landed punch is not")
	var combo := ImpactAlign.scene_check(load_scene("res://scenes/combo3.json"), 30)
	ok(combo.get("ok", false), "1i combo3 runs through the scene mode (contact frame %s)" % [str(combo.get("frame", -1))])

	# ---- N042
	var hits := [
		{"want": "liver", "tag": "obliques_r", "y": 0.66},
		{"want": "chin", "tag": "face", "y": 0.92, "head_y": 0.15},
		{"want": "thigh", "tag": "quadriceps_l", "y": 0.38},
		{"want": "solar_plexus", "tag": "abdominals", "y": 0.68},
	]
	var right := 0
	for h in hits:
		var got := RegionReact.pick(h["tag"], h["y"], h.get("head_y", 0.5))
		if got == h["want"]:
			right += 1
		print("     %-14s -> %s" % [h["tag"], got])
	ok(right == 4, "2a region picked correctly on %d of 4 planted hits" % right)
	var J := 60.0
	var li := RegionReact.react("liver", J, "r")
	var ch := RegionReact.react("chin", J, "r")
	var th := RegionReact.react("thigh", J, "l")
	var sp := RegionReact.react("solar_plexus", J, "r")
	ok(float(li["drop_delay_s"]) >= 0.2 and absf((li["joints"]["spine_01"] as Vector3).y) > 4.0, "2b liver folds to the hit side (spine side %.1f) with a delayed drop (%.2f s)" % [(li["joints"]["spine_01"] as Vector3).y, li["drop_delay_s"]])
	var hs: float = absf((ch["joints"]["head"] as Vector3).x)
	ok(hs > 10.0 and not li["joints"].has("head") and (ch["joints"]["calf_r"] as Vector3).x > 20.0 and (ch["joints"]["calf_l"] as Vector3).x > 20.0, "2c chin snaps the head (%.1f deg) and both knees buckle" % hs)
	ok(th["joints"].has("calf_l") and not th["joints"].has("calf_r") and float(th["drop_delay_s"]) == 0.0, "2d thigh buckles only the hit leg, no delayed drop")
	ok((sp["joints"]["spine_01"] as Vector3).x > (li["joints"]["spine_01"] as Vector3).x and sp["joints"].has("upperarm_r") and sp["joints"].has("upperarm_l"), "2e solar plexus folds forward the most, both arms to the belly")
	var prev := -1.0
	var mono := true
	for j in [5.0, 15.0, 30.0, 60.0, 120.0, 240.0]:
		var rr: Dictionary = RegionReact.react("solar_plexus", j, "r")
		var ang: float = (rr["joints"]["spine_01"] as Vector3).x
		if not (ang > prev):
			mono = false
		prev = ang
	ok(mono, "2f amplitude grows strictly with the impulse (5..240 N s)")
	var bl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))
	var outside := 0
	for reg in ["liver", "chin", "thigh", "solar_plexus"]:
		for j in [1.0, 60.0, 500.0, 5000.0]:
			var rr := RegionReact.react(reg, j, "r" if reg != "thigh" else "l")
			for jn in rr["joints"]:
				var key: String = String(jn).replace("_l", "_r") if String(jn).ends_with("_l") else String(jn)
				var lim: Dictionary = bl.get(key, {})
				var v: Vector3 = rr["joints"][jn]
				if lim.is_empty():
					outside += 1
					continue
				if v.x < lim["bend"][0] - 0.01 or v.x > lim["bend"][1] + 0.01 or v.y < lim["side"][0] - 0.01 or v.y > lim["side"][1] + 0.01 or v.z < lim["twist"][0] - 0.01 or v.z > lim["twist"][1] + 0.01:
					outside += 1
					print("     OUT %s %s %s" % [reg, jn, v])
	ok(outside == 0, "2g every reaction joint inside body_limits at 1..5000 N s (%d outside)" % outside)

	# ---- N046
	var c := BodyCollide.charge(80.0, Vector3(0, 0, 4.0), 60.0, Vector3.ZERO, "male", 0.1)
	var p0: float = c["p_before"]
	var p1: float = c["p_after"]
	ok(absf(p1 - p0) / p0 < 0.05, "3a momentum conserved within 5%% (before %.1f after %.1f kg m/s, %.3f%%)" % [p0, p1, 100.0 * absf(p1 - p0) / p0])
	ok(absf(float(c["dv_b"])) > absf(float(c["dv_a"])), "3b the lighter body (60 kg) changes speed more (%.2f vs %.2f m/s)" % [c["dv_b"], c["dv_a"]])
	ok(c["keys_a"].size() >= 3 and c["keys_b"].size() >= 3, "3c both bodies keyed (%d, %d keys)" % [c["keys_a"].size(), c["keys_b"].size()])
	ok(float(c["m_eff_a"]) < 80.0 and float(c["m_eff_a"]) > 40.0, "3d effective mass is the de Leva upper-body share (%.1f of 80 kg)" % c["m_eff_a"])
	var eq := BodyCollide.charge(70.0, Vector3(0, 0, 3), 70.0, Vector3.ZERO, "male", 0.0)
	ok(absf(float(eq["dv_a"]) - float(eq["dv_b"])) < 0.01, "3e equal masses change speed equally")

	print("FIGHT2 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
