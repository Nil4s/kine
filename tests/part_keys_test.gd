## godot --headless --path . -s tests/part_keys_test.gd     (GATES WW1, UPGRADES #238 + #239; headless is fine)
## PART KEYS: one joint keyed on its own over the cards' blend (scripts/part_keys.gd). Checked by numbers:
##   the curve's values at known times (a hold-shaped segment and a PCHIP slope worked by hand), NO OVERSHOOT between
##   any two keys on an uneven zig-zag sampled densely, clamped before the first and after the last key, a real scene
##   (combo3, 60 fps over its whole length) with no part keys sampling to the BYTE as the card blend alone, a keyed
##   joint reaching the body through Scene.apply (the floor, pins) while the other joints stay as they were,
##   save / load (written only when there is one; the validator passes it and refuses a wrong joint name), Mirror
##   (hand_l's keys go to hand_r reflected exactly as Body.mirror_pose reflects a card; twice = back), and the
##   schema's joint list is Body.ORDER.
## REFERENCE: no body numbers (this moves nothing by itself); the curve rule is PCHIP (Fritsch & Carlson 1980, SIAM J.
## Numer. Anal. 17(2) 238-246; Brodlie's weights as scipy.interpolate.PchipInterpolator documents), with the ends'
## slope 0 as Blender's auto-clamped handles hold an extreme flat (the Blender manual's F-curve handle types).
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


func K(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		out.append({"t": float(p[0]), "v": p[1]})
	return out


func maxdiff(a: Dictionary, b: Dictionary) -> float:
	var m := 0.0
	for j in a["ang"]:
		if not b["ang"].has(j):
			return INF
		var d := ((a["ang"][j] as Vector3) - (b["ang"][j] as Vector3)).abs()
		m = maxf(m, maxf(d.x, maxf(d.y, d.z)))
	return m


func _init() -> void:
	# 1 known values
	var k1 := K([[0.2, Vector3(0, 0, 0)], [0.6, Vector3(60, 10, -20)], [1.0, Vector3(30, 10, 40)]])
	var v := PartKeys.at(k1, 0.4)
	# key 0 is an end (slope 0) and every angle turns back or stops at key 1 (slope 0): the middle is exactly halfway
	ok(v.is_equal_approx(Vector3(30, 5, -10)), "halfway between two flat keys: %s (bar (30, 5, -10))" % v)
	ok(PartKeys.at(k1, 0.6) == Vector3(60, 10, -20), "on a key the value is the key's exactly: %s" % PartKeys.at(k1, 0.6))
	var k2 := K([[0, Vector3(0, 0, 0)], [1, Vector3(10, 0, 0)], [2, Vector3(40, 0, 0)]])
	# by hand: secants 10 and 30, equal spacing -> slope at key 1 = 2 / (1/10 + 1/30) = 15; at s = 0.5:
	# h01(0.5) * 10 + h11(0.5) * 15 = 0.5 * 10 - 0.125 * 15 = 3.125
	var b := PartKeys.at(k2, 0.5).x
	ok(absf(b - 3.125) < 1e-5, "PCHIP slope through a rising key: %.5f at 0.5 s (bar 3.12500 by hand)" % b)
	var b2 := PartKeys.at(k2, 1.5).x
	# segment 2: a = 10, slope 15; b = 40, slope 0 (an end): h00 10 + h10 15 + h01 40 = 0.5*10 + 0.125*15 + 0.5*40 = 26.875
	ok(absf(b2 - 26.875) < 1e-5, "  and after it: %.5f at 1.5 s (bar 26.87500 by hand)" % b2)

	# 2 no overshoot: an uneven zig-zag, every angle, 2001 samples
	var zz := K([[0.0, Vector3(0, 50, -10)], [0.13, Vector3(40, 52, 30)], [0.9, Vector3(-30, 52.5, 31)], [1.0, Vector3(80, 90, -60)],
		[1.7, Vector3(79, 0, -59)], [1.75, Vector3(-80, 1, 120)]])
	var worst := 0.0
	for n in 2001:
		var t := 1.75 * n / 2000.0
		var i := 0
		while i < zz.size() - 2 and t >= float(zz[i + 1]["t"]):
			i += 1
		var x := PartKeys.at(zz, t)
		var lo: Vector3 = (zz[i]["v"] as Vector3).min(zz[i + 1]["v"])
		var hi: Vector3 = (zz[i]["v"] as Vector3).max(zz[i + 1]["v"])
		for c in 3:
			worst = maxf(worst, maxf(lo[c] - x[c], x[c] - hi[c]))
	ok(worst <= 1e-9, "no overshoot: the most any angle leaves its two keys' range on a 6-key zig-zag, 2001 samples: %.9f deg (bar 0)" % worst)

	# 3 clamped ends
	ok(PartKeys.at(k1, -3.0) == Vector3(0, 0, 0) and PartKeys.at(k1, 0.1) == Vector3(0, 0, 0), "before the first key: the first key's value (%s at 0.1 s)" % PartKeys.at(k1, 0.1))
	ok(PartKeys.at(k1, 1.01) == Vector3(30, 10, 40) and PartKeys.at(k1, 99.0) == Vector3(30, 10, 40), "after the last key: the last key's value (%s at 99 s)" % PartKeys.at(k1, 99.0))
	ok(PartKeys.at(K([[0.5, Vector3(1, 2, 3)]]), 0.0) == Vector3(1, 2, 3), "one key = that value at every time")

	# 4 empty = byte-identical on a real scene, 60 fps over its whole length
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var T := S.length()
	var n60 := int(ceil(T * 60.0)) + 1
	var diff := 0.0
	var bytes := 0
	for f in n60:
		var t := minf(f / 60.0, T)
		var a := S.sample(t)
		var c := S._sample_cards(t)
		diff = maxf(diff, maxdiff(a, c))
		if var_to_str(a) != var_to_str(c):
			bytes += 1
	ok(S.part_keys.is_empty() and diff == 0.0 and bytes == 0, "combo3 with no part keys, %d frames at 60 fps over %.2f s: max angle diff %.1f deg (bar exactly 0), %d frames not byte-identical (bar 0)" % [n60, T, diff, bytes])
	var B := body()
	var D0 := S.to_dict(B)
	ok(not D0.has("part_keys"), "no part keys: the file has no part_keys field")
	# anti-vacuity: the same check sees a key
	S.part_keys = {"lowerarm_r": K([[0.5, Vector3(90, 0, 0)]])}
	var seen := 0.0
	for f in n60:
		seen = maxf(seen, maxdiff(S.sample(minf(f / 60.0, T)), S._sample_cards(minf(f / 60.0, T))))
	ok(seen > 1.0, "  the same check with one key on the right forearm sees it: max diff %.1f deg (bar > 1)" % seen)

	# 5 into the body: the keyed joint has its key's angles after apply (floor, pins); the others as unkeyed
	var ts: Array = S.times()
	var tm := (float(ts[2][1]) + float(ts[3][1])) / 2.0
	S.part_keys = {"lowerarm_r": K([[0.0, Vector3(20, 0, 0)], [T, Vector3(120, 0, 0)]])}
	var want := PartKeys.at(S.part_keys["lowerarm_r"], tm)
	S.apply(B, tm)
	var got: Vector3 = B.ang["lowerarm_r"]
	var other: Vector3 = B.ang["upperarm_l"]
	var S0 := Scene.new()
	S0.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var B0 := body()
	S0.apply(B0, tm)
	ok(got.distance_to(B.clamp_ang("lowerarm_r", want)) < 0.01, "Scene.apply at %.3f s: the keyed forearm is %s (its key curve %s)" % [tm, got, want])
	ok(other.distance_to(B0.ang["upperarm_l"]) < 1e-4 and B0.ang["lowerarm_r"].distance_to(got) > 1.0, "  an unkeyed joint is as without keys (moved %.5f deg); the forearm differs from the cards' by %.1f deg" % [other.distance_to(B0.ang["upperarm_l"]), B0.ang["lowerarm_r"].distance_to(got)])

	# 6 save / load + the validator
	S.part_keys = {}
	PartKeys.put(S.part_keys, "hand_l", 0.8, Vector3(-30, 10, 25))
	PartKeys.put(S.part_keys, "hand_l", 0.3, Vector3(10, -5, 5))
	PartKeys.put(S.part_keys, "hand_l", 0.3005, Vector3(12, -5, 5))   # within 1 ms of the 0.3 key: replaces it
	PartKeys.put(S.part_keys, "head", 1.0, Vector3(5, 0, 10))
	var hk: Array = S.part_keys["hand_l"]
	ok(hk.size() == 2 and float(hk[0]["t"]) == 0.3 and hk[0]["v"] == Vector3(12, -5, 5), "put: in time order, a key at the same time replaced (%d keys, first %s at %.3f)" % [hk.size(), hk[0]["v"], hk[0]["t"]])
	var D := S.to_dict(B)
	var R := Scene.new()
	R.from_dict(JSON.parse_string(JSON.stringify(D)))
	var rd := 0.0
	for f in n60:
		rd = maxf(rd, maxdiff(S.sample(minf(f / 60.0, T)), R.sample(minf(f / 60.0, T))))
	ok(D.has("part_keys") and R.part_keys.size() == 2 and rd < 1e-9, "saved and loaded: %d keyed joints, max angle diff over every frame %.9f deg (bar 0: keys are written to 0.01)" % [R.part_keys.size(), rd])
	var p := "user://zz_part_keys.json"
	var fw := FileAccess.open(p, FileAccess.WRITE)
	fw.store_string(JSON.stringify(D, " "))
	fw.close()
	var errs: Array = Validate.file(p)
	ok(errs.is_empty(), "the validator passes the saved file (%d errors%s)" % [errs.size(), (": " + str(errs[0])) if not errs.is_empty() else ""])
	D["part_keys"]["hand_ll"] = D["part_keys"]["hand_l"]
	fw = FileAccess.open(p, FileAccess.WRITE)
	fw.store_string(JSON.stringify(D, " "))
	fw.close()
	errs = Validate.file(p)
	ok(errs.size() == 1 and String(errs[0]["path"]) == "$.part_keys.hand_ll", "  and refuses a joint name typo: %s" % str(errs))
	D["part_keys"].erase("hand_ll")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var sch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/scene.schema.json"))
	ok(sch["$defs"]["scene"]["properties"]["part_keys"]["propertyNames"]["enum"] == Body.ORDER, "the schema's part_keys joint names are Body.ORDER (%d)" % Body.ORDER.size())
	ok(Scene.MIRROR_SCENE.has("part_keys"), "part_keys is on Mirror's list (MIRROR_SCENE)")

	# 7 mirror: hand_l's keys -> hand_r, reflected as Body.mirror_pose reflects a card
	var M := body()
	var mf := PartKeys.mirror_file(D["part_keys"], M)
	ok(mf.has("hand_r") and not mf.has("hand_l") and mf.has("head"), "mirrored: hand_l's keys are on hand_r (%s)" % str(mf.keys()))
	var P := body()
	var src: Array = D["part_keys"]["hand_l"][1]["v"]
	P.ang["hand_l"] = Vector3(src[0], src[1], src[2])
	P.fk()
	P.mirror_pose()
	var mv: Array = mf["hand_r"][1]["v"]
	var mirrored := Vector3(mv[0], mv[1], mv[2])
	ok(mirrored.distance_to(P.ang["hand_r"]) < 0.01, "  the value is mirror_pose's: %s (mirror_pose gives %s)" % [mirrored, P.ang["hand_r"]])
	var back := PartKeys.mirror_file(mf, M)
	var bv: Array = back["hand_l"][1]["v"]
	ok(Vector3(bv[0], bv[1], bv[2]).distance_to(Vector3(src[0], src[1], src[2])) < 0.02 and back["hand_l"][1]["t"] == D["part_keys"]["hand_l"][1]["t"],
		"  mirrored twice = back: %s (was %s), the time kept" % [Vector3(bv[0], bv[1], bv[2]), Vector3(src[0], src[1], src[2])])
	var C := S.clone()
	ok(var_to_str(C.part_keys) == var_to_str(S.part_keys) and not is_same(C.part_keys, S.part_keys), "clone() carries the part keys (a copy)")

	print("PART KEYS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
