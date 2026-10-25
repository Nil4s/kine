## godot --headless --path . -s tests/curve_mods_test.gd     (round 48, GATES DD2, UPGRADES_300 #248)
## CURVE MODIFIERS (Blender's F-Curve Noise, Stepped, Limits) on a joint's part keys (scripts/part_keys.gd header).
## Keys on the right forearm: bend 10 at 0 s -> 90 at 1 s (side 4, twist -6 held).
##   1 NON-DESTRUCTIVE: with any stack on, the keys are byte for byte the same; remove the stack and every frame is at()
##   2 LIMITS 20..60 on bend, mix 1: every frame's bend = clamp(at, 20, 60) (worked by hand from at), side / twist untouched;
##     mix 0.5: halfway between at and the clamp
##   3 STEPPED 0.1 s: the bend at t is at(floor(t / 0.1) * 0.1) (so it holds flat 0.1 s, then jumps); mix 0 = the keys
##   4 NOISE strength 6, scale 0.25 s: the offset from at stays within +-3 deg, is not flat (spread > 1 deg), is smooth (no
##     frame-to-frame jump above the strength x the frame / scale bound x 1.5), and on ch 1 only moves the side angle
##   5 the SCENE: Scene.sample (what playback and every export read) carries the stack: the forearm's bend at each frame
##     = value_at; saved (to_dict -> JSON -> from_dict) and loaded it is the same at every frame; a scene without mods
##     saves byte for byte without a "mods" field
##   6 MIRROR: the stack goes to the twin; a side limit 5..15 becomes -15..-5
##   7 put() a key BEFORE the first: the stack moves to the new first key (the curve keeps its modifiers)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func keys() -> Array:
	return [{"t": 0.0, "v": Vector3(10, 4, -6)}, {"t": 1.0, "v": Vector3(90, 4, -6)}]


func frames() -> Array:
	var out := []
	for i in 31:
		out.append(i / 30.0)
	return out


func _init() -> void:
	var pk := {"lowerarm_r": keys()}
	var bare := var_to_str(pk)
	# 2 limits
	PartKeys.add_mod(pk, "lowerarm_r", {"type": "limits", "ch": 0, "min": 20.0, "max": 60.0, "mix": 1.0})
	var w2 := 0.0
	var other := true
	for t in frames():
		var a := PartKeys.at(pk["lowerarm_r"], t)
		var v := PartKeys.value_at(pk["lowerarm_r"], t)
		w2 = maxf(w2, absf(v.x - clampf(a.x, 20.0, 60.0)))
		other = other and v.y == a.y and v.z == a.z
	pk["lowerarm_r"][0]["mods"][0]["mix"] = 0.5
	var w2h := 0.0
	for t in frames():
		var a := PartKeys.at(pk["lowerarm_r"], t)
		var v := PartKeys.value_at(pk["lowerarm_r"], t)
		w2h = maxf(w2h, absf(v.x - (a.x + (clampf(a.x, 20.0, 60.0) - a.x) * 0.5)))
	ok(w2 < 1e-4 and w2h < 1e-4 and other, "2 limits 20..60 on bend: worst error vs clamp(at) %.6f, at mix 0.5 vs halfway %.6f; side and twist untouched %s" % [w2, w2h, other])
	# 1 non-destructive
	var keys_only: Array = pk["lowerarm_r"].map(func(k): return [k["t"], k["v"]])
	PartKeys.remove_mod(pk, "lowerarm_r", 0)
	var w1 := 0.0
	for t in frames():
		w1 = maxf(w1, (PartKeys.value_at(pk["lowerarm_r"], t) - PartKeys.at(pk["lowerarm_r"], t)).length())
	ok(var_to_str(pk) == bare and str(keys_only) == str(keys().map(func(k): return [k["t"], k["v"]])) and w1 == 0.0, "1 non-destructive: the keys never changed; the stack removed, the data is byte for byte the bare keys and value_at == at (worst %.6f)" % w1)
	# 3 stepped
	PartKeys.add_mod(pk, "lowerarm_r", {"type": "stepped", "step": 0.1, "offset": 0.0, "mix": 1.0})
	var w3 := 0.0
	for t in frames():
		var want := PartKeys.at(pk["lowerarm_r"], floorf(t / 0.1 + 1e-9) * 0.1).x
		w3 = maxf(w3, absf(PartKeys.value_at(pk["lowerarm_r"], t).x - want))
	var flat := PartKeys.value_at(pk["lowerarm_r"], 0.21).x == PartKeys.value_at(pk["lowerarm_r"], 0.29).x
	pk["lowerarm_r"][0]["mods"][0]["mix"] = 0.0
	var w3z := 0.0
	for t in frames():
		w3z = maxf(w3z, (PartKeys.value_at(pk["lowerarm_r"], t) - PartKeys.at(pk["lowerarm_r"], t)).length())
	ok(w3 < 1e-4 and flat and w3z < 1e-6, "3 stepped 0.1 s: worst error vs at(floor(t/0.1)*0.1) %.6f; flat across 0.21..0.29 %s; mix 0 = the keys (%.6f)" % [w3, flat, w3z])
	PartKeys.remove_mod(pk, "lowerarm_r", 0)
	# 4 noise
	PartKeys.add_mod(pk, "lowerarm_r", {"type": "noise", "ch": -1, "strength": 6.0, "scale": 0.25, "phase": 0.0, "seed": 1, "mix": 1.0})
	var lo := INF
	var hi := -INF
	var jump := 0.0
	var prev := 0.0
	for i in 301:
		var t := i / 300.0
		var d := PartKeys.value_at(pk["lowerarm_r"], t).x - PartKeys.at(pk["lowerarm_r"], t).x
		lo = minf(lo, d)
		hi = maxf(hi, d)
		if i > 0:
			jump = maxf(jump, absf(d - prev))
		prev = d
	var bound := 6.0 * 1.5 * (1.0 / 300.0) / 0.25 * 1.5   # smoothstep slope <= 1.5 x the value step (<= strength) per scale
	pk["lowerarm_r"][0]["mods"][0]["ch"] = 1
	var only_side := true
	for t in frames():
		var a := PartKeys.at(pk["lowerarm_r"], t)
		var v := PartKeys.value_at(pk["lowerarm_r"], t)
		only_side = only_side and v.x == a.x and v.z == a.z
	ok(lo >= -3.0 and hi <= 3.0 and hi - lo > 1.0 and jump <= bound and only_side, "4 noise strength 6: offset %.2f .. %.2f (bar within +-3, spread > 1); largest step between 1/300 s samples %.4f (bar <= %.4f, smooth); on ch 1 only the side moves %s" % [lo, hi, jump, bound, only_side])
	PartKeys.remove_mod(pk, "lowerarm_r", 0)
	# 5 the scene
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.name = "zz_curve_mods"
	S.add("a", B.to_dict())
	S.add("b", B.to_dict())
	S.cards[0]["move"] = 1.0
	S.part_keys = {"lowerarm_r": keys()}
	var plain := JSON.stringify(S.to_dict(B))
	PartKeys.add_mod(S.part_keys, "lowerarm_r", {"type": "limits", "ch": 0, "min": 20.0, "max": 60.0, "mix": 1.0})
	PartKeys.add_mod(S.part_keys, "lowerarm_r", {"type": "noise", "ch": 0, "strength": 4.0, "scale": 0.3, "seed": 2, "mix": 0.5})
	var w5 := 0.0
	for t in frames():
		var sm: Dictionary = S.sample(t)
		w5 = maxf(w5, ((sm["ang"] as Dictionary)["lowerarm_r"] - PartKeys.value_at(S.part_keys["lowerarm_r"], t)).length())
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(S.to_dict(B))))
	var w5b := 0.0
	for t in frames():
		w5b = maxf(w5b, ((S2.sample(t)["ang"] as Dictionary)["lowerarm_r"] - (S.sample(t)["ang"] as Dictionary)["lowerarm_r"]).length())
	ok(w5 < 1e-4 and w5b < 0.02 and not plain.contains("\"mods\":") and JSON.stringify(S.to_dict(B)).contains("\"mods\":"), "5 Scene.sample carries the stack (worst %.6f deg vs value_at); saved and loaded, worst %.4f deg (file keeps 0.01); a scene without mods has no 'mods' in its file" % [w5, w5b])
	# 6 mirror
	var f6 := {"lowerarm_r": [{"t": 0.0, "v": [10, 4, -6], "mods": [{"type": "limits", "ch": 1, "min": 5.0, "max": 15.0, "mix": 1.0}]}, {"t": 1.0, "v": [90, 4, -6]}]}
	var m6 := PartKeys.mirror_file(f6, B)
	var md: Dictionary = m6.get("lowerarm_l", [{}])[0].get("mods", [{}])[0]
	ok(m6.has("lowerarm_l") and float(md.get("min", 0)) == -15.0 and float(md.get("max", 0)) == -5.0, "6 mirrored: the stack is on lowerarm_l, the side limit 5..15 is now %s..%s" % [md.get("min"), md.get("max")])
	# 7 put before the first key
	var pk7 := {"lowerarm_r": [{"t": 0.5, "v": Vector3(10, 0, 0), "mods": [{"type": "stepped", "step": 0.1}]}, {"t": 1.0, "v": Vector3(90, 0, 0)}]}
	PartKeys.put(pk7, "lowerarm_r", 0.2, Vector3(0, 0, 0))
	ok(pk7["lowerarm_r"][0].has("mods") and not pk7["lowerarm_r"][1].has("mods") and PartKeys.mods_of(pk7["lowerarm_r"]).size() == 1, "7 a key put before the first: the stack moved to the new first key")
	print("CURVE MODS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
