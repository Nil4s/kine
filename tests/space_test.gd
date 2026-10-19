## godot --headless --path . -s tests/space_test.gd     (ROADMAP 63: IK space switching, scripts/limb_ik.gd "SPACES")
## combo3, A = the CONTACT card's arrival. Bars, written before measuring:
##   1 CHEST: the right hand switched world -> chest at A (LimbIK.switch_space, which pins it first), the chest turning
##     30 deg after A (a part key on spine_03). (a) at A the wrist moves < 0.1 mm by the switch; (b) the wrist in the
##     chest's frame stays constant within 0.1 mm at 6 frames over 0.5 s while the chest turns >= 29.5 deg; ANTI-VACUITY:
##     the same hand left in the world sits > 20 mm off that offset at the end (so the chest-frame offset is not trivial).
##   2 BOTH WAYS: chest -> world at a later frame B moves the wrist < 0.1 mm, and from B on the wrist is still while the
##     chest turns on; the frame BEFORE the switch (one frame earlier) plays as the chest curve (no jump: both < 0.1 mm of
##     the wrist's own step there + 0.1 mm).
##   3 WEAPON: the left hand (the right holds the bat) switched to the weapon's space at A, then the bat carried 8 cm up
##     by the right hand's IK keys: the wrist in the bat's frame constant within 0.1 mm at 6 frames; the bat moved
##     >= 5 cm (anti-vacuity); a loop (right hand in the weapon's space while it holds it) is refused.
##   4 FILE + MIRROR: the keys with spaces save "space", reload and replay within 0.1 mm (the file rounds points to 0.1 mm; my first bar said 0.05 and was wrong); a scene with none saves no
##     "space"; Scene.mirror_file swaps hand_r -> hand_l and its space (hand_r <-> hand_l; chest stays chest) and the
##     mirrored scene's wrist plays at the mirrored place (x negated) within 1 mm; the weapon case likewise.
##   5 THE LANE: LimbIK.space_lane gives the world, chest and (after the switch back) world segments with their times.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func combo() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	return S


## the wrist in a joint's frame
func rel(B: Body, tip: String, j: String) -> Vector3:
	return (B.G[j] as Quaternion).inverse() * ((B.P[tip] as Vector3) - (B.P[j] as Vector3))


func rel_wep(B: Body, tip: String) -> Vector3:
	var x := B.wep_xform()
	return (x[1] as Quaternion).inverse() * ((B.P[tip] as Vector3) - (x[0] as Vector3))


func _init() -> void:
	var B := body()
	var S := combo()
	var ts := S.times()
	var A: float = snappedf(float(ts[2][1]), 1.0 / S.fps)   # the CONTACT card's arrival
	var dt := 1.0 / S.fps

	# ---- 1 CHEST
	S.apply(B, A)
	var chest0: Quaternion = B.G["spine_03"]
	for j in ["pelvis", "spine_01", "spine_02", "spine_03"]:   # the 30 deg is shared by the hips and the trunk joints (each has a small twist range)
		var a0: Vector3 = B.ang[j]
		PartKeys.put(S.part_keys, j, A, a0)
		PartKeys.put(S.part_keys, j, A + 0.5, B.clamp_ang(j, a0 + Vector3(0, 0, 18.0)))
	S.apply(B, A)
	var wr0: Vector3 = B.P["hand_r"]
	var r1 := LimbIK.switch_space(S, B, "hand_r", A, "world")   # pins first
	S.apply(B, A)
	var d_pin := ((B.P["hand_r"] as Vector3) - wr0).length()
	var Sworld := Scene.new()   # the same scene with the hand left in the world, for the anti-vacuity read
	Sworld.from_dict(JSON.parse_string(JSON.stringify(S.to_dict(B))))
	var before: Vector3 = B.P["hand_r"]
	var r2 := LimbIK.switch_space(S, B, "hand_r", A, "chest")
	var d_sw: float = r2["moved"]
	S.apply(B, A)
	var base := rel(B, "hand_r", "spine_03")
	var worst := 0.0
	var turn := 0.0
	var wend := 0.0
	var Bw := body()
	for i in 6:
		var t := A + 0.1 * (i + 1)
		S.apply(B, t)
		worst = maxf(worst, (rel(B, "hand_r", "spine_03") - base).length())
		turn = maxf(turn, rad_to_deg(chest0.angle_to(B.G["spine_03"])))
		Sworld.apply(Bw, t)
		wend = (rel(Bw, "hand_r", "spine_03") - base).length()
	var miss: float = (S.ik_last.get("hand_r", {}) as Dictionary).get("miss", 9.0)
	print("  pin moved %.4f mm, switch moved %.4f mm, chest turned %.1f deg, offset drift %.4f mm, IK miss %.4f mm, world-left hand off by %.1f mm" % [d_pin * 1000, d_sw * 1000, turn, worst * 1000, miss * 1000, wend * 1000])
	ok(d_sw < 0.0001 and r2["ok"], "1a world -> chest at A moves the wrist %.5f mm (bar 0.1)" % (d_sw * 1000.0))
	ok(turn >= 29.5 and worst < 0.0001, "1b the wrist stays %.5f mm from its chest-frame offset while the chest turns %.1f deg (bar 0.1 mm, >= 29.5 deg: the turn is capped by the joints' own limits)" % [worst * 1000.0, turn])
	ok(wend > 0.02, "1c anti-vacuity: left in the world the hand is %.1f mm off that offset (bar > 20)" % (wend * 1000.0))

	# ---- 2 BOTH WAYS
	var Bt := A + 0.3
	S.apply(B, Bt)
	var pre: Vector3 = B.P["hand_r"]
	var r3 := LimbIK.switch_space(S, B, "hand_r", Bt, "world")
	S.apply(B, Bt)
	var still := 0.0
	var p_b: Vector3 = B.P["hand_r"]
	for i in 3:
		S.apply(B, Bt + 0.1 * (i + 1))
		still = maxf(still, ((B.P["hand_r"] as Vector3) - p_b).length())
	S.apply(B, Bt - dt)
	var before_step := ((B.P["hand_r"] as Vector3) - pre).length()   # one frame earlier: the chest curve moves it a little
	S.apply(B, Bt)
	var mid_step := ((B.P["hand_r"] as Vector3) - pre).length()
	print("  chest -> world at %.2f: moved %.4f mm; still %.4f mm after; the frame before differs from B by %.2f mm" % [Bt, float(r3["moved"]) * 1000, still * 1000, before_step * 1000])
	ok(float(r3["moved"]) < 0.0001 and mid_step < 0.0001, "2a chest -> world moves the wrist %.5f mm (bar 0.1)" % (mid_step * 1000.0))
	ok(still < 0.0001, "2b from B on the wrist stays in the world (%.5f mm over 0.3 s, bar 0.1) while the chest turns on" % (still * 1000.0))

	# ---- 5 THE LANE
	var lane := LimbIK.space_lane(S.ik, S.length())
	var names := lane.map(func(s): return s["space"])
	ok(names == ["world", "chest", "world"] and absf(float(lane[1]["t0"]) - A) < 1e-6 and absf(float(lane[2]["t0"]) - Bt) < 1e-6,
		"5 the lane: %s with the chest from %.3f s to %.3f s" % [names, float(lane[1]["t0"]), float(lane[1]["t1"])])

	# ---- 3 WEAPON
	var S3 := combo()
	S3.apply(B, A)
	var loop := LimbIK.switch_space(S3, B, "hand_r", A, "weapon")
	ok(not loop["ok"] and loop["why"] == "loop", "3a the hand that holds the bat cannot be in the bat's space (%s)" % loop["why"])
	LimbIK.switch_space(S3, B, "hand_r", A, "world")   # pins the right hand (it carries the bat)
	var k0: Dictionary = S3.ik["hand_r"][-1]
	S3.apply(B, A)
	var l0: Vector3 = B.P["hand_l"]
	var r4 := LimbIK.switch_space(S3, B, "hand_l", A, "weapon")
	S3.apply(B, A)
	var wk := B.wep_xform()
	var base_w := rel_wep(B, "hand_l")
	var k1 := k0.duplicate(true)
	k1["t"] = A + 0.4
	k1["target"] = (k0["target"] as Vector3) + Vector3(0, 0.08, 0)
	k1["pole"] = (k0["pole"] as Vector3) + Vector3(0, 0.08, 0)
	LimbIK.put(S3.ik, "hand_r", k1)
	var worst_w := 0.0
	var moved := 0.0
	var mw := 0.0
	for i in 6:
		S3.apply(B, A + 0.08 * (i + 1))
		worst_w = maxf(worst_w, (rel_wep(B, "hand_l") - base_w).length())
		moved = maxf(moved, ((B.wep_xform()[0] as Vector3) - (wk[0] as Vector3)).length())
		mw = maxf(mw, float((S3.ik_last.get("hand_l", {}) as Dictionary).get("miss", 9.0)))
	print("  weapon: switch moved %.4f mm, bat carried %.1f mm, offset drift %.4f mm, IK miss %.4f mm" % [float(r4["moved"]) * 1000, moved * 1000, worst_w * 1000, mw * 1000])
	ok(r4["ok"] and float(r4["moved"]) < 0.0001 and moved >= 0.05 and worst_w < 0.0001,
		"3b the left wrist stays %.5f mm from its bat-frame offset while the bat is carried %.1f mm (bars 0.1 mm, >= 50 mm)" % [worst_w * 1000.0, moved * 1000.0])

	# ---- 4 FILE + MIRROR
	var plain := combo()
	ok(not JSON.stringify(plain.to_dict(B)).contains("\"space\""), "4a a scene without spaces saves no \"space\"")
	var d1: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(B)))
	var Sl := Scene.new()
	Sl.from_dict(d1)
	var d2: Dictionary = JSON.parse_string(JSON.stringify(Sl.to_dict(B)))
	var Bb := body()
	var rt := 0.0
	for i in 12:
		var t := A - 0.1 + 0.1 * i
		S.apply(B, t)
		Sl.apply(Bb, t)
		rt = maxf(rt, ((B.P["hand_r"] as Vector3) - (Bb.P["hand_r"] as Vector3)).length())
	ok(JSON.stringify(d1["ik"]) == JSON.stringify(d2["ik"]) and JSON.stringify(d1["ik"]).contains("\"space\":\"chest\"") and rt < 0.0001,
		"4b save -> load -> save equal, spaces kept; the reload plays within %.5f mm (bar 0.1: the file rounds points to 0.1 mm)" % (rt * 1000.0))
	var M := body()
	var dm := Scene.mirror_file(d1, M)
	var Sm := Scene.new()
	Sm.from_dict(dm)
	var spaces := {}
	for tip in Sm.ik:
		spaces[tip] = (Sm.ik[tip] as Array).map(func(k): return LimbIK.space_of(k))
	var mm := 0.0
	var Bm := body()
	for i in 12:
		var t := A - 0.1 + 0.1 * i
		S.apply(B, t)
		Sm.apply(Bm, t)
		var a: Vector3 = B.P["hand_r"]
		mm = maxf(mm, (Vector3(-a.x, a.y, a.z) - (Bm.P["hand_l"] as Vector3)).length())
	print("  mirrored spaces: %s" % spaces)
	ok(Sm.ik.has("hand_l") and not Sm.ik.has("hand_r") and "chest" in spaces["hand_l"] and mm < 0.001,
		"4c mirror: hand_r's chest keys are hand_l's; the mirrored wrist plays %.4f mm from the mirrored place (bar 1)" % (mm * 1000.0))
	var d3: Dictionary = JSON.parse_string(JSON.stringify(S3.to_dict(B)))
	var dm3 := Scene.mirror_file(d3, M)
	var S3m := Scene.new()
	S3m.from_dict(dm3)
	var sp3: Array = (S3m.ik["hand_r"] as Array).map(func(k): return LimbIK.space_of(k))
	var mm3 := 0.0
	for i in 6:
		var t := A + 0.08 * (i + 1)
		S3.apply(B, t)
		S3m.apply(Bm, t)
		var a: Vector3 = B.P["hand_l"]
		mm3 = maxf(mm3, (Vector3(-a.x, a.y, a.z) - (Bm.P["hand_r"] as Vector3)).length())
	ok(S3m.ik.has("hand_r") and "weapon" in sp3 and S3m.ik.has("hand_l") and mm3 < 0.001,
		"4d mirror, weapon case: hand_l's weapon keys are hand_r's; the mirrored wrist plays %.4f mm from the mirrored place (bar 1)" % (mm3 * 1000.0))

	print("space_test: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(0 if fails == 0 else 1)
