## godot --headless --path . -s tests/ik_pin_test.gd     (GAP_ANALYSIS row 13: IK / FK with pole targets, scripts/limb_ik.gd)
## Bars, written before measuring:
##   1 THE TABLE: a 3-card scene (24 fps) whose trunk turns and bends 30+ deg; the left hand pinned at card 1. At every
##     frame the wrist is within 1 mm of the pin (the worst printed). ANTI-VACUITY: without the pin it drifts > 5 cm.
##   2 POLE: (a) the elbow lies in the root-target-pole plane within 1 deg at every frame of the table, on the pole's side;
##     (b) the pole moved 90 deg round the root-target axis moves the elbow's plane 90 +- 1 deg.
##   3 WEIGHT 0 / NO IK: (a) the table scene with IK keys at weight 0 plays every joint angle (and the hips) bit-identical
##     to the scene without keys, every frame; (b) every scene in scenes/ (read only) plays bit-identical with weight-0 IK
##     keys added; (c) a scene saves "ik" only when keyed, and a keyed one round-trips through its file within 0.1 mm.
##   4 RELEASE WITHOUT A POP: the table played in spline (card 2 passed through at speed), the hand pinned at card 1 and
##     released at card 2 (LimbIK.release: the IK pose written into the card, then weight 0). MEASURE: the release's
##     EXTRA step: per arm joint, (its angle change over the frame before -> the frame of the release) minus (the same
##     change in the scene where the pin is kept), the largest (deg, any of bend / side / twist). BAR: below the largest
##     angle change of ANY joint over those two frames with the pin kept (the motion of one frame without release).
##     ANTI-VACUITY: a naive release (weight 0 keyed, no FK snap) steps more than that.
##     REVISED AFTER THE FIRST RUN (said, not hidden): the first measure was the arm's raw step (1.243 deg) against the
##     whole body's step with the pin kept (1.241 deg). With a clean release those two are the SAME motion (the arm's IK
##     step is the reference's largest), so it could only pass by luck; it failed by 0.002 deg, the card file's 0.01-deg
##     rounding. The raw step is still printed, not barred.
##   5 LIMITS: no joint outside its limits (Body.clamp_ang leaves it unchanged within 1e-4 deg) on any frame of 1, 2, 4.
##   6 CLOSED FORM vs AN INDEPENDENT CHECK: 200 random reachable targets (50 per limb: each made by a random legal pose of
##     trunk and limb, the pole read from that pose; then the limb scrambled): after solve() the body's own FK puts the
##     wrist / ankle on the target within 0.1 mm, both bone lengths unchanged within 1e-6 m, the elbow / knee in the
##     plane within 1 deg (bent limbs).
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


func pose(B: Body, angs: Dictionary) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


const ARMS := {"upperarm_l": Vector3(45, -50, 0), "lowerarm_l": Vector3(70, 0, 0), "upperarm_r": Vector3(0, -80, 0), "lowerarm_r": Vector3(10, 0, 0)}


func with_trunk(bend: float, side: float, twist: float) -> Dictionary:
	var d := ARMS.duplicate()
	for j in ["spine_01", "spine_02", "spine_03"]:
		d[j] = Vector3(bend, side, twist)
	return d


## the table: reach (hold 0.25) -> turn (arrive 0.75, hold 0) -> lean (arrive 1.5, hold 0.5); length 2.0 s
func table(B: Body) -> Scene:
	var S := Scene.new()
	S.fps = 24
	S.add("reach", pose(B, ARMS))
	S.add("turn", pose(B, with_trunk(5, 0, -14)))
	S.add("lean", pose(B, with_trunk(16, -5, 6)))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.25
	S.cards[1]["move"] = 0.5
	S.cards[1]["hold"] = 0.0
	S.cards[2]["move"] = 0.75
	S.cards[2]["hold"] = 0.5
	return S


func frames(S: Scene) -> int:
	return int(ceilf(S.length() * S.fps - 1e-6)) + 1


func tf(S: Scene, f: int) -> float:
	return minf(float(f) / S.fps, S.length())


## every frame: {ang, offset, P (a copy), ik_last}
func play(S: Scene, B: Body) -> Array:
	var out := []
	for f in frames(S):
		S.apply(B, tf(S, f))
		out.append({"ang": B.ang.duplicate(), "offset": B.offset, "P": B.P.duplicate(), "ik": S.ik_last.duplicate(true)})
	return out


## the elbow's angle off the root-target-pole plane (deg) and whether it is on the pole's side
func plane_off(R: Vector3, T: Vector3, pole: Vector3, E: Vector3) -> Array:
	var ax := (T - R).normalized()
	var n := ax.cross(pole - R).normalized()
	var e := E - R
	var off := rad_to_deg(asin(clampf(absf(n.dot(e.normalized())), 0.0, 1.0)))
	var pe := e - ax * e.dot(ax)
	var pp := (pole - R) - ax * (pole - R).dot(ax)
	return [off, pe.dot(pp) > 0.0]


func limit_bad(fr: Array, B: Body) -> Array:
	var worst := 0.0
	var where := ""
	for k in fr.size():
		for j in fr[k]["ang"]:
			var a: Vector3 = fr[k]["ang"][j]
			var d: Vector3 = (B.clamp_ang(j, a) - a).abs()
			var m: float = d[d.max_axis_index()]
			if m > worst:
				worst = m
				where = "%s @ frame %d" % [j, k]
	return [worst, where]


func step_max(fr: Array, f: int, js: Array) -> Array:
	var worst := 0.0
	var who := ""
	for j in js:
		var d: Vector3 = ((fr[f]["ang"][j] as Vector3) - (fr[f - 1]["ang"][j] as Vector3)).abs()
		var m: float = d[d.max_axis_index()]
		if m > worst:
			worst = m
			who = j
	return [worst, who]


## per joint: (its step f-1 -> f in a) minus (its step in b), the largest component
func extra_step(a: Array, b: Array, f: int, js: Array) -> Array:
	var worst := 0.0
	var who := ""
	for j in js:
		var da: Vector3 = (a[f]["ang"][j] as Vector3) - (a[f - 1]["ang"][j] as Vector3)
		var db: Vector3 = (b[f]["ang"][j] as Vector3) - (b[f - 1]["ang"][j] as Vector3)
		var d := (da - db).abs()
		var m: float = d[d.max_axis_index()]
		if m > worst:
			worst = m
			who = j
	return [worst, who]


func _init() -> void:
	var B := body()
	var C := ["upperarm_l", "lowerarm_l", "hand_l"]

	# ------------------------------------------------ 1 THE TABLE
	var S := table(B)
	var fk_fr := play(S, B)
	S.apply(B, 0.0)
	var c0: Quaternion = B.G["spine_03"]
	var turn := 0.0
	for f in frames(S):
		S.apply(B, tf(S, f))
		turn = maxf(turn, rad_to_deg(((B.G["spine_03"] as Quaternion) * c0.inverse()).get_angle()))
	S.apply(B, 0.0)
	var pin := LimbIK.pin(S, B, "hand_l", 0.0)
	var pt: Vector3 = pin["target"]
	var fr := play(S, B)
	var worst := 0.0
	var worst_f := 0
	var drift := 0.0
	for f in fr.size():
		var d: float = ((fr[f]["P"]["hand_l"] as Vector3) - pt).length()
		if d > worst:
			worst = d
			worst_f = f
		drift = maxf(drift, ((fk_fr[f]["P"]["hand_l"] as Vector3) - pt).length())
	print("     at the worst frame the IK pass said: %s; arm angles %s %s" % [fr[worst_f]["ik"], fr[worst_f]["ang"]["upperarm_l"], fr[worst_f]["ang"]["lowerarm_l"]])
	ok(turn >= 30.0, "1 fixture: the chest turns / bends up to %.1f deg from card 1 over the scene (bar 30+), %d frames at %d fps" % [turn, fr.size(), S.fps])
	ok(worst <= 0.001, "1 THE TABLE: the pinned left wrist stays within %.4f mm of the pin at every frame (worst at frame %d; bar 1 mm)" % [worst * 1000.0, worst_f])
	ok(drift > 0.05, "1 anti-vacuity: without the pin the same wrist drifts up to %.1f cm from that spot (bar > 5 cm)" % (drift * 100.0))

	# ------------------------------------------------ 2 POLE
	var poff := 0.0
	var pside := true
	for f in fr.size():
		var k := LimbIK.sample(S.ik["hand_l"], tf(S, f))
		var r := plane_off(fr[f]["P"]["upperarm_l"], k["target"], k["pole"], fr[f]["P"]["lowerarm_l"])
		poff = maxf(poff, r[0])
		pside = pside and r[1]
	ok(poff <= 1.0 and pside, "2a POLE: the elbow is within %.4f deg of the shoulder-target-pole plane at every frame (bar 1 deg), on the pole's side at every frame: %s" % [poff, pside])
	# 2b: card 1's body, the pole turned 90 deg about the shoulder-target axis (from -45 to +45 round the pose's own pole)
	pose(B, ARMS)
	var R: Vector3 = B.P["upperarm_l"]
	var T: Vector3 = B.P["hand_l"]
	var ax := (T - R).normalized()
	var p0 := LimbIK.pole_from_pose(B, "hand_l")
	var base := (p0 - R) - ax * (p0 - R).dot(ax)
	var ends := []
	var rep := []
	for deg in [-45.0, 45.0]:
		pose(B, ARMS)
		var pl: Vector3 = R + ax * (T - R).length() * 0.5 + Quaternion(ax, deg_to_rad(deg)) * base
		var r := LimbIK.solve(B, "hand_l", T, pl)
		var e: Vector3 = (B.P["lowerarm_l"] as Vector3) - R
		ends.append(e - ax * e.dot(ax))
		rep.append("pole %+.0f: miss %.4f mm, clamped %s, plane off %.3f deg" % [deg, r["miss"] * 1000.0, r["clamped"], plane_off(R, T, pl, B.P["lowerarm_l"])[0]])
	var turned := rad_to_deg((ends[0] as Vector3).signed_angle_to(ends[1], ax))
	ok(absf(absf(turned) - 90.0) <= 1.0, "2b POLE turned 90 deg round the shoulder-target axis: the elbow's plane turned %.3f deg (bar 90 +- 1) [%s]" % [turned, "; ".join(rep)])

	# ------------------------------------------------ 3 WEIGHT 0 / NO IK
	var S0 := table(B)
	var a0 := play(S0, B)
	var S1 := table(B)
	S1.ik = {"hand_l": [{"t": 0.0, "target": pt, "pole": pin["pole"], "w": 0.0}, {"t": 1.0, "target": pt + Vector3(0, 0.2, 0), "pole": pin["pole"], "w": 0.0}],
		"foot_r": [{"t": 0.5, "target": Vector3(-0.1, 0.1, 0.2), "pole": Vector3(-0.1, 0.5, 1.0), "w": 0.0}]}
	var a1 := play(S1, B)
	var same := a0.size() == a1.size()
	var first_diff := -1
	for f in mini(a0.size(), a1.size()):
		if var_to_str(a0[f]["ang"]) != var_to_str(a1[f]["ang"]) or a0[f]["offset"] != a1[f]["offset"] or not a1[f]["ik"].is_empty():
			same = false
			first_diff = f
			break
	ok(same, "3a weight 0: the table with weight-0 IK keys on two limbs plays every joint and the hips bit-identical to no keys, %d frames (first differing frame %d)" % [a0.size(), first_diff])
	var nsc := 0
	var nfr := 0
	var differ := []
	for fn in DirAccess.get_files_at("res://scenes"):
		if not fn.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn))
		var Sa := Scene.new()
		Sa.from_dict(d)
		var Sb := Scene.new()
		Sb.from_dict(d)
		if not Sa.ik.is_empty():
			differ.append(fn + " (already has ik)")
		var L := Sb.length()
		Sb.ik = {"hand_r": [{"t": 0.0, "target": Vector3(-0.3, 1.0, 0.3), "pole": Vector3(-0.6, 1.0, -0.3), "w": 0.0}, {"t": L, "target": Vector3(-0.3, 1.2, 0.4), "pole": Vector3(-0.6, 1.0, -0.3), "w": 0.0}],
			"foot_l": [{"t": L * 0.5, "target": Vector3(0.1, 0.1, 0.0), "pole": Vector3(0.1, 0.5, 1.0), "w": 0.0}]}
		var Ba := body()
		var Bb := body()
		var n := int(ceilf(L * Sa.fps - 1e-6)) + 1
		for f in n:
			var t := minf(float(f) / Sa.fps, L)
			Sa.apply(Ba, t)
			Sb.apply(Bb, t)
			nfr += 1
			if var_to_str(Ba.ang) != var_to_str(Bb.ang) or Ba.offset != Bb.offset or var_to_str(Ba.wep_xform()) != var_to_str(Bb.wep_xform()):
				differ.append("%s frame %d" % [fn, f])
				break
		nsc += 1
	ok(nsc >= 5 and differ.is_empty(), "3b every scene in scenes/ (%d, %d frames, read only) plays bit-identical with weight-0 IK keys added (differ: %s)" % [nsc, nfr, differ])
	var Sd := table(B)
	var plain: Dictionary = Sd.to_dict(B)
	Sd.ik = S.ik.duplicate(true)
	var keyed: Dictionary = JSON.parse_string(JSON.stringify(Sd.to_dict(B)))
	var Sr := Scene.new()
	Sr.from_dict(keyed)
	var rt := play(Sr, B)
	var rtw := 0.0
	for f in rt.size():
		rtw = maxf(rtw, ((rt[f]["P"]["hand_l"] as Vector3) - (fr[f]["P"]["hand_l"] as Vector3)).length())
	ok(not plain.has("ik") and keyed.has("ik") and Sr.ik.has("hand_l") and rtw <= 1e-4, "3c the file: no \"ik\" without keys (%s), \"ik\" with them (%s); loaded back the pinned wrist plays within %.4f mm of the original (bar 0.1 mm)" % [plain.has("ik"), keyed.has("ik"), rtw * 1000.0])

	# ------------------------------------------------ 4 RELEASE WITHOUT A POP
	var Sp := table(B)
	Sp.spline = true
	Sp.apply(B, 0.0)
	LimbIK.pin(Sp, B, "hand_l", 0.0)
	var t_r: float = Sp.times()[1][1]
	var f_r := int(roundf(t_r * Sp.fps))
	var Sk := Sp.clone()   # the pin kept
	var Sn := Sp.clone()   # a naive release: weight 0 keyed, no FK snap
	LimbIK.put(Sn.ik, "hand_l", {"t": t_r - 1.0 / Sn.fps, "target": pt, "pole": Sn.ik["hand_l"][0]["pole"], "w": 1.0})
	LimbIK.put(Sn.ik, "hand_l", {"t": t_r, "target": pt, "pole": Sn.ik["hand_l"][0]["pole"], "w": 0.0})
	var rr := LimbIK.release(Sp, B, "hand_l", t_r)
	var fp_ := play(Sp, B)
	var fk_ := play(Sk, B)
	var fn_ := play(Sn, B)
	var raw: Array = step_max(fp_, f_r, C)
	var ref: Array = step_max(fk_, f_r, Body.ORDER)
	var pop: Array = extra_step(fp_, fk_, f_r, C)
	var naive: Array = extra_step(fn_, fk_, f_r, C)
	var hand_jump := ((fp_[f_r]["P"]["hand_l"] as Vector3) - (fp_[f_r - 1]["P"]["hand_l"] as Vector3)).length()
	var after_w: float = LimbIK.weight_at(Sp.ik["hand_l"], t_r + 0.1)
	for f in range(f_r - 2, f_r + 3):
		print("     frame %d: released wrist %.2f mm from the pin (w %.3f), kept %.2f mm" % [f, ((fp_[f]["P"]["hand_l"] as Vector3) - pt).length() * 1000.0, LimbIK.weight_at(Sp.ik["hand_l"], tf(Sp, f)), ((fk_[f]["P"]["hand_l"] as Vector3) - pt).length() * 1000.0])
	ok(rr["ok"] and abs(tf(Sp, f_r) - t_r) < 1e-6 and after_w == 0.0, "4 fixture: released at card 2 (%.3f s = frame %d, on a frame), card %d written (FK at t off the IK by %.4f deg), weight after it %.1f, a hold key before it: %s" % [t_r, f_r, int(rr["card"]) + 1, rr["residual"], after_w, rr.get("pre", false)])
	ok(pop[0] < ref[0], "4 RELEASE: frames %d -> %d the release adds %.4f deg at most to the arm's step (%s; raw step %.3f deg, not barred; the wrist moves %.3f mm), below the %.3f deg the body moves over the same frame with the pin kept (%s)" % [f_r - 1, f_r, pop[0], pop[1], raw[0], hand_jump * 1000.0, ref[0], ref[1]])
	ok(naive[0] > ref[0], "4 anti-vacuity: a naive release (weight 0 keyed, no FK snap) adds %.2f deg (%s) over that frame" % [naive[0], naive[1]])

	# ------------------------------------------------ 5 LIMITS
	var lim_rep := []
	var lim_ok := true
	for pair in [["table pinned", fr], ["spline pinned", fk_], ["spline released", fp_]]:
		var lb := limit_bad(pair[1], B)
		lim_rep.append("%s %.5f (%s)" % [pair[0], lb[0], lb[1]])
		lim_ok = lim_ok and lb[0] <= 1e-4
	ok(lim_ok, "5 LIMITS: no joint past its limits on any frame; the most any angle sits outside: %s" % ", ".join(lim_rep))

	# ------------------------------------------------ 6 CLOSED FORM vs THE BODY'S FK
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var w_miss := 0.0
	var w_len := 0.0
	var w_plane := 0.0
	var n_plane := 0
	var per := {}
	for i in 200:
		var tip: String = LimbIK.LIMBS[i % 4]
		var ch := LimbIK.chain(B, tip)
		for j in Body.ORDER:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.1), rng.randf_range(-0.5, 0.5))
		for j in ["pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"] + ch:
			var L: Dictionary = B.lim[j]
			var v := Vector3(rng.randf_range(L["bend"].x, L["bend"].y), rng.randf_range(L["side"].x, L["side"].y), rng.randf_range(L["twist"].x, L["twist"].y))
			if j == "pelvis":
				v = Vector3(rng.randf_range(-20, 20), rng.randf_range(-10, 10), rng.randf_range(-180, 180))
			B.ang[j] = v
		B.fk()
		var T6: Vector3 = B.P[tip]
		var P6 := LimbIK.pole_from_pose(B, tip)
		var bent: bool = (B.ang[ch[1]] as Vector3).x > 3.0
		for j in ch:   # scramble the limb
			var L: Dictionary = B.lim[j]
			B.ang[j] = Vector3(rng.randf_range(L["bend"].x, L["bend"].y), rng.randf_range(L["side"].x, L["side"].y), rng.randf_range(L["twist"].x, L["twist"].y))
		B.fk()
		var r := LimbIK.solve(B, tip, T6, P6)
		var miss := ((B.P[tip] as Vector3) - T6).length()
		var l1 := absf(((B.P[ch[1]] - B.P[ch[0]]) as Vector3).length() - (B.p0[ch[1]] - B.p0[ch[0]]).length())
		var l2 := absf(((B.P[tip] - B.P[ch[1]]) as Vector3).length() - (B.p0[tip] - B.p0[ch[1]]).length())
		w_miss = maxf(w_miss, miss)
		w_len = maxf(w_len, maxf(l1, l2))
		per[tip] = maxf(per.get(tip, 0.0), miss)
		if bent:
			w_plane = maxf(w_plane, plane_off(B.P[ch[0]], T6, P6, B.P[ch[1]])[0])
			n_plane += 1
		if miss > 1e-4:
			print("     miss %.4f mm on %s (clamped %s)" % [miss * 1000.0, tip, r["clamped"]])
	ok(w_miss <= 1e-4 and w_len <= 1e-6 and w_plane <= 1.0, "6 CLOSED FORM: 200 random reachable targets, the body's FK puts the tip within %.5f mm (bar 0.1; per limb %s), bone lengths within %.4f um (bar 1 um), the elbow / knee within %.4f deg of the plane (%d bent limbs, bar 1)" % [w_miss * 1000.0, per.keys().map(func(k): return "%s %.5f" % [k, per[k] * 1000.0]), w_len * 1e6, w_plane, n_plane])
	# unreachable: straightens toward the target, the miss reported
	pose(B, ARMS)
	var far: Vector3 = (B.P["upperarm_l"] as Vector3) + Vector3(0.3, 0.2, 1.5)
	var ru := LimbIK.solve(B, "hand_l", far, (B.P["upperarm_l"] as Vector3) + Vector3(0, -1, 0))
	var reach := ((B.p0["lowerarm_l"] - B.p0["upperarm_l"]) as Vector3).length() + ((B.p0["hand_l"] - B.p0["lowerarm_l"]) as Vector3).length()
	var dirv := ((B.P["hand_l"] - B.P["upperarm_l"]) as Vector3).normalized().angle_to((far - B.P["upperarm_l"]).normalized())
	ok(absf(ru["miss"] - ((far - B.P["upperarm_l"]).length() - reach)) < 0.002 and rad_to_deg(dirv) < 0.5, "6 unreachable (%.2f m away, the arm %.3f m): straightened toward it, miss reported %.4f m = the shortfall, aimed within %.3f deg" % [(far - B.P["upperarm_l"]).length(), reach, ru["miss"], rad_to_deg(dirv)])

	print("IK PIN TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
