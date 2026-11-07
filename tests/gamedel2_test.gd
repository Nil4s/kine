## godot --headless --path . -s tests/gamedel2_test.gd     (suite gamedel2:h)   GAME DELIVERY, the per-clip side: N083, N086, N087, N090 (+ N081/N082 into the export sidecar).
## Module: scripts/game_clip.gd (GameClip). Add-on: addons/kine_body_check/. Bars, written BEFORE the implementation, never moved after a run:
##  N083 PLAY RATE. Engine model: the engine moves the root at the clip's authored speed while the clip plays at rate r; a planted foot then slides
##   L*|1-r|/r over a plant, L = how far the foot travels relative to the root in the plant. Edges (m): lo = L/(L+SLIDE_BAR), hi = L/(L-SLIDE_BAR); SLIDE_BAR = 0.025 m
##   (rulebook FOOT SLIDE: 2.5 cm). The human side: peak joint speed (shoulder, knee, trunk) x r must stay under HumanLimits.SPEED.
##   a1 slide fixture (feet planted, hips creep 0.20 m out and back): L measured by the module = 0.20 +-0.005 (the test measures it again on its own).
##   a2 lo = 0.8889 +-0.01 and hi = 1.1429 +-0.01 (the closed form for L = 0.20).
##   a3 the slide at lo and at hi is the bar (+-0.5 mm); at 0.9*lo and 1.1*hi it is over the bar (the edges are where the bar is crossed).
##   a4 human edge: a fast shoulder swing: hi_human = 6520 / peak (+-2 %), the peak read by the test from B.ang at 60 Hz; the clip's hi = min(slide, human).
##   a5 the same swing over 10x the time: hi_human is the cap (>= 3.5) and the range still holds 1.0.
##   Control c1: a range that claims 0.5..2.0 for the slide fixture is outside the edges (slide at 2.0 over the bar).
##  N086 CONTACT CURVES. 60 fps, frames 0..round(length*60) inclusive. Lift fixture: foot_r planted all through, foot_l planted [0,0.4] and [1.35,1.7], lifted between.
##   b1 foot_l curve = FootPlant.weight_at (max over its plants) on every frame within 1e-6; 1.0 on every frame inside a plant range.
##   b2 independent physics: on every frame with weight 1 the ankle is <= 1 cm above that foot's lowest ankle in the clip; on frames 0.75..0.95 s (lifted) weight is 0 and
##      the ankle is >= 10 cm above.
##   b3 foot_r is 1.0 on all frames. Hand curves: the weapon fixture (bat in hand_r) hand_r = 1 on >= 95 % of frames, hand_l = 0 on all.
##   b4 AUTO (plants removed): the contact derived from the motion alone agrees with the plant curve (both read >= 0.5) on >= 90 % of the frames of the lift fixture.
##   b5 export: write_sidecar writes <name>.clip.json; read back, the foot_l curve equals the in-memory one within 0.001 and "fps" is 60.
##   Control c2: the foot_r curve used as foot_l's differs from the real foot_l curve on >= 20 frames (the bars can tell the feet apart).
##  N087 BODY-AWARE COMPRESSION. Fixture: dense 30 Hz keys for 3 s on upperarm_r, lowerarm_r, spine_02, thigh_r; a bat in hand_r. Tips: hand_l, hand_r, foot_l, foot_r, bat tip.
##   d1 compress(bar 0.005 m): the worst tip error, measured by the TEST at 240 Hz against the original keys, <= 0.005 m, at each of the 5 tips.
##   d2 the key count falls >= 50 % (before -> after).
##   d3 the reported worst equals the test's measure within 0.0002 m.
##   d4 the body-aware keys <= the uniform-degree reduction at the SAME tip bar (the best single tolerance in degrees, bisected the same way).
##   d5 first and last key of every joint kept; a joint absent from the keys stays absent.
##   Control c3: a uniform 5 deg tolerance (KeyReduce) has a tip error > 0.005 m by the same measure (the measure can fail a bad compression).
##  N090 RUNTIME CHECK (addons/kine_body_check/body_check.gd, no Kine class used in it; limits.json shipped beside it).
##   e1 the add-on files exist, body_check.gd mentions none of Body/Scene/PartKeys/FootPlant/GameClip (it runs in a game without Kine); limits.json has an entry for
##      every joint of Body.ORDER that has a range, with bend/side/twist.
##   e2 a Skeleton3D (upperarm_r, lowerarm_r, spine_02; rest = identity): a 170 deg elbow (limit 145) is flagged, naming lowerarm_r with excess >= 20 deg.
##   e3 BLEND: two layers each legal alone (80 deg elbow flex on top of 80 deg) summed past the limit are flagged; each alone is silent.
##   e4 a clean pose (30 deg elbow and shoulder, 5 deg spine) and the rest pose give 0 flags.
##   e5 twist: 120 deg of upperarm twist (limit 70) flags it; 40 deg does not.
##   e6 export: GameClip.write_addon(dir) copies the add-on; the copy's files equal the sources byte for byte.
##  N081/N082 into the export: the sidecar JSON has "cancel" equal to CancelWindows.to_json(direct) and "reactable" equal to Reactable.to_json(direct) on the same clip.
extends SceneTree

var fails := 0
const STANCE := {"thigh_l": Vector3(-6, 0, 0), "calf_l": Vector3(38, 0, 0), "foot_l": Vector3(25, 0, 0), "thigh_r": Vector3(-6, 0, 0), "calf_r": Vector3(38, 0, 0), "foot_r": Vector3(25, 0, 0)}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(B: Body, angs: Dictionary, off: Vector3, bat := false) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = off
	B.wep_on = bat
	if bat:
		B.wep_hand = "hand_r"
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


func slide_scene(B: Body) -> Scene:
	var S := Scene.new()
	S.fps = 30
	S.pin = false
	S.on_floor = true
	S.add("stand", pose(B, STANCE, Vector3.ZERO))
	S.add("forward", pose(B, STANCE, Vector3(0.2, 0, 0)))
	S.add("back", pose(B, STANCE, Vector3.ZERO))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.4
	S.cards[1]["move"] = 2.5
	S.cards[1]["hold"] = 0.2
	S.cards[2]["move"] = 2.5
	S.cards[2]["hold"] = 0.4
	S.plants = [{"foot": "foot_l", "t0": 0.4, "t1": 5.9}, {"foot": "foot_r", "t0": 0.4, "t1": 5.9}]
	return S


func lift_scene(B: Body) -> Scene:
	var lifted := STANCE.duplicate()
	lifted["thigh_l"] = Vector3(-45, 0, 0)
	lifted["calf_l"] = Vector3(75, 0, 0)
	var S := Scene.new()
	S.fps = 30
	S.pin = false
	S.on_floor = true
	S.add("stand", pose(B, STANCE, Vector3.ZERO))
	S.add("lift", pose(B, lifted, Vector3.ZERO))
	S.add("down", pose(B, STANCE, Vector3.ZERO))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.4
	S.cards[1]["move"] = 0.3
	S.cards[1]["hold"] = 0.3
	S.cards[2]["move"] = 0.3
	S.cards[2]["hold"] = 0.4
	S.plants = [{"foot": "foot_r", "t0": 0.0, "t1": 1.7}, {"foot": "foot_l", "t0": 0.0, "t1": 0.4}, {"foot": "foot_l", "t0": 1.35, "t1": 1.7}]
	return S


func swing_scene(B: Body, secs: float) -> Scene:
	var S := Scene.new()
	S.fps = 30
	S.pin = false
	S.on_floor = true
	S.add("a", pose(B, STANCE, Vector3.ZERO))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = secs + 0.4
	S.part_keys = {"upperarm_r": [{"t": 0.0, "v": Vector3.ZERO}, {"t": 0.2, "v": Vector3.ZERO}, {"t": 0.2 + secs, "v": Vector3(100, 0, 0)}, {"t": secs + 0.4, "v": Vector3(100, 0, 0)}]}
	return S


func bat_scene(B: Body) -> Scene:
	var S := Scene.new()
	S.fps = 30
	S.pin = false
	S.on_floor = true
	S.add("a", pose(B, STANCE, Vector3.ZERO, true))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 3.0
	var pk := {}
	var spec := {"upperarm_r": [40.0, 0.8, 30.0], "lowerarm_r": [50.0, 1.1, 70.0], "spine_02": [6.0, 0.5, 6.0], "thigh_r": [20.0, 0.7, -10.0]}
	for j in spec:
		var keys := []
		for f in 91:
			var t := float(f) / 30.0
			keys.append({"t": t, "v": Vector3(float(spec[j][2]) + float(spec[j][0]) * sin(TAU * float(spec[j][1]) * t), 0.0, 0.0)})
		pk[j] = keys
	S.part_keys = pk
	return S


func tips(B: Body) -> Array:
	var o := []
	for n in ["hand_l", "hand_r", "foot_l", "foot_r"]:
		o.append(B.E[n])
	o.append(B.wep_point(B.wep_len) if B.wep_on else B.E["hand_r"])
	return o


## the test's own tip error (m) of part keys pk against the scene's keys, 240 Hz: per tip worst
func tip_err(S: Scene, B: Body, pk: Dictionary) -> Array:
	var C := S.clone()
	C.part_keys = pk.duplicate(true)
	var worst := [0.0, 0.0, 0.0, 0.0, 0.0]
	var n := int(round(S.length() * 240.0))
	for k in n + 1:
		var t := minf(float(k) / 240.0, S.length())
		S.apply(B, t)
		var a := tips(B)
		C.apply(B, t)
		var b := tips(B)
		for i in 5:
			worst[i] = maxf(worst[i], ((a[i] as Vector3) - (b[i] as Vector3)).length())
	return worst


func jmax(a: Array) -> float:
	var m := 0.0
	for x in a:
		m = maxf(m, float(x))
	return m


func frames_n(S: Scene) -> int:
	return int(round(S.length() * 60.0)) + 1


func _init() -> void:
	var B := body()
	var tmp := "user://gamedel2"
	DirAccess.make_dir_recursive_absolute(tmp)

	# ---------------- N083 PLAY RATE ----------------
	var S := slide_scene(B)
	var R := GameClip.rate_range(S, B, 60)
	var L_test := 0.0
	var a0 := Vector3.ZERO
	for k in int(S.length() * 60.0) + 1:
		var t := float(k) / 60.0
		if t < 0.4 or t > 5.9:
			continue
		S.apply(B, t)
		var rel: Vector3 = (B.P["foot_l"] as Vector3) - (B.P["pelvis"] as Vector3)
		rel.y = 0.0
		if a0 == Vector3.ZERO:
			a0 = rel
		L_test = maxf(L_test, (rel - a0).length())
	print("slide fixture: L module %.4f test %.4f, range %.4f .. %.4f (human cap %.2f)" % [float(R["stride_m"]), L_test, float(R["lo"]), float(R["hi"]), float(R["hi_human"])])
	ok(absf(float(R["stride_m"]) - 0.20) <= 0.005 and absf(L_test - 0.20) <= 0.005, "a1 foot travel relative to the root L = %.4f (test %.4f), want 0.20 +-0.005" % [float(R["stride_m"]), L_test])
	ok(absf(float(R["lo"]) - 0.8889) <= 0.01 and absf(float(R["hi"]) - 1.1429) <= 0.01, "a2 edges %.4f .. %.4f vs 0.8889 .. 1.1429 +-0.01" % [float(R["lo"]), float(R["hi"])])
	var bar := 0.025
	var s_lo := GameClip.slide_at(float(R["stride_m"]), float(R["lo"]))
	var s_hi := GameClip.slide_at(float(R["stride_m"]), float(R["hi"]))
	ok(absf(s_lo - bar) <= 0.0005 and absf(s_hi - bar) <= 0.0005, "a3 slide at the edges %.4f / %.4f m = the bar 0.025 +-0.0005" % [s_lo, s_hi])
	ok(GameClip.slide_at(0.2, 0.9 * float(R["lo"])) > bar and GameClip.slide_at(0.2, 1.1 * float(R["hi"])) > bar, "a3b past the edges the slide is over the bar")
	control(GameClip.slide_at(0.2, 2.0) <= bar, "c1 a claimed 0.5..2.0 range: the slide at 2.0 is %.3f m, over 0.025" % GameClip.slide_at(0.2, 2.0))
	var SW := swing_scene(B, 0.1)
	var RW := GameClip.rate_range(SW, B, 60)
	var peak := 0.0
	var prev := Vector3.ZERO
	for k in int(SW.length() * 60.0) + 1:
		SW.apply(B, float(k) / 60.0)
		var v: Vector3 = B.ang["upperarm_r"]
		if k > 0:
			peak = maxf(peak, (v - prev).length() * 60.0)
		prev = v
	var want_h := 6520.0 / peak
	print("fast swing: peak %.0f deg/s, hi_human module %.3f want %.3f, hi %.3f" % [peak, float(RW["hi_human"]), want_h, float(RW["hi"])])
	ok(absf(float(RW["hi_human"]) - want_h) <= 0.02 * want_h, "a4 hi_human %.3f = 6520/peak %.3f within 2 %%" % [float(RW["hi_human"]), want_h])
	ok(float(RW["hi"]) <= float(RW["hi_human"]) + 1e-9 and float(RW["hi"]) >= 1.0, "a4b hi = min(slide, human) and the clip is human at 1.0")
	var RS := GameClip.rate_range(swing_scene(B, 1.0), B, 60)
	ok(float(RS["hi_human"]) >= 3.5 and float(RS["lo"]) <= 1.0 and float(RS["hi"]) >= 1.0, "a5 the slow swing: hi_human %.2f (cap) and 1.0 is inside %.3f..%.3f" % [float(RS["hi_human"]), float(RS["lo"]), float(RS["hi"])])

	# ---------------- N086 CONTACT CURVES ----------------
	var SL := lift_scene(B)
	var C := GameClip.contacts(SL, B, 60)
	var n := frames_n(SL)
	ok(int(C["n"]) == n and (C["foot_l"] as Array).size() == n, "b0 %d frames at 60 fps (length %.2f s)" % [n, SL.length()])
	var worst_d := 0.0
	var in_range_min := 1.0
	var ymin := {"foot_l": 9.0, "foot_r": 9.0}
	for k in n:
		SL.apply(B, float(k) / 60.0)
		for ft in ymin:
			ymin[ft] = minf(float(ymin[ft]), (B.P[ft] as Vector3).y)
	var up_bad := 0
	var planted_bad := 0
	var cnt1 := 0
	for k in n:
		var t := float(k) / 60.0
		var w := 0.0
		for i in SL.plants.size():
			if String(SL.plants[i]["foot"]) == "foot_l":
				w = maxf(w, FootPlant.weight_at(SL.plants, i, t, 60))
		worst_d = maxf(worst_d, absf(w - float(C["foot_l"][k])))
		if (t >= 0.0 and t <= 0.4) or (t >= 1.35 and t <= 1.7):
			in_range_min = minf(in_range_min, float(C["foot_l"][k]))
		SL.apply(B, t)
		var h: float = (B.P["foot_l"] as Vector3).y - float(ymin["foot_l"])
		if float(C["foot_l"][k]) >= 0.999:
			cnt1 += 1
			if h > 0.01:
				planted_bad += 1
		if t >= 0.75 and t <= 0.95 and (float(C["foot_l"][k]) != 0.0 or h < 0.10):
			up_bad += 1
	print("foot_l: max |curve - FootPlant.weight_at| %.2e, min inside a plant %.3f, weight-1 frames %d (%d with ankle >1 cm up), lifted frames wrong %d" % [worst_d, in_range_min, cnt1, planted_bad, up_bad])
	ok(worst_d <= 1e-6 and in_range_min >= 0.9999999, "b1 foot_l curve = the plant weights and 1.0 inside both plants")
	ok(cnt1 >= 40 and planted_bad == 0 and up_bad == 0, "b2 weight 1 only where the ankle is down (%d frames, %d bad); lifted frames 0 with the ankle >= 10 cm up (%d bad)" % [cnt1, planted_bad, up_bad])
	var rmin := 1.0
	for k in n:
		rmin = minf(rmin, float(C["foot_r"][k]))
	ok(rmin >= 0.9999999, "b3a foot_r is 1.0 on all %d frames (min %.3f)" % [n, rmin])
	var SB := bat_scene(B)
	var CB := GameClip.contacts(SB, B, 60)
	var hr := 0
	var hl := 0
	for k in frames_n(SB):
		if float(CB["hand_r"][k]) >= 0.5:
			hr += 1
		if float(CB["hand_l"][k]) > 0.0:
			hl += 1
	ok(float(hr) >= 0.95 * float(frames_n(SB)) and hl == 0, "b3b the bat hand_r holds on %d of %d frames, hand_l touches on %d" % [hr, frames_n(SB), hl])
	var SA := lift_scene(B)
	SA.plants = []
	var CA := GameClip.contacts(SA, B, 60)
	var agree := 0
	for k in n:
		if (float(CA["foot_l"][k]) >= 0.5) == (float(C["foot_l"][k]) >= 0.5):
			agree += 1
	print("auto contact agrees with the plant curve on %d of %d frames" % [agree, n])
	ok(float(agree) >= 0.9 * float(n), "b4 auto contact (no plants) agrees on %.0f %% of frames (>= 90)" % (100.0 * agree / n))
	var jp := GameClip.write_sidecar(SL, B, tmp, "zz_gamedel2", 60)
	var J = JSON.parse_string(FileAccess.get_file_as_string(jp)) if FileAccess.file_exists(jp) else {}
	var jdiff := 999.0
	if J is Dictionary and J.has("contacts"):
		jdiff = 0.0
		for k in n:
			jdiff = maxf(jdiff, absf(float(J["contacts"]["foot_l"][k]) - float(C["foot_l"][k])))
	ok(J is Dictionary and J.has("contacts") and int(J["contacts"]["fps"]) == 60 and jdiff <= 0.001, "b5 sidecar %s round-trips the foot_l curve (max diff %.5f)" % [jp.get_file(), jdiff])
	var diffs := 0
	for k in n:
		if absf(float(C["foot_r"][k]) - float(C["foot_l"][k])) > 0.5:
			diffs += 1
	control(diffs < 20, "c2 foot_r's curve as foot_l's differs on %d frames" % diffs)
	# N081 / N082 into the export sidecar
	var cw_direct := CancelWindows.to_json(CancelWindows.analyze(SL, B, 60))
	var rx_direct := Reactable.to_json(Reactable.of_scene(SL, B, 60))
	ok(J is Dictionary and J.has("cancel") and JSON.stringify(J["cancel"]) == JSON.stringify(JSON.parse_string(JSON.stringify(cw_direct))), "n081 the sidecar's cancel windows equal CancelWindows.to_json on the same clip")
	ok(J is Dictionary and J.has("reactable") and JSON.stringify(J["reactable"]) == JSON.stringify(JSON.parse_string(JSON.stringify(rx_direct))), "n082 the sidecar's reactable equals Reactable.to_json on the same clip")
	ok(J is Dictionary and J.has("rate") and float(J["rate"]["lo"]) > 0.0 and float(J["rate"]["hi"]) >= float(J["rate"]["lo"]), "n083x the sidecar carries the play-rate range")

	# ---------------- N087 COMPRESSION ----------------
	var SC := bat_scene(B)
	SC.apply(B, 0.5)
	ok(B.wep_on, "d0 the bat fixture holds the bat on playback (the weapon tip is measured)")
	var BAR := 0.005
	var res := GameClip.compress(SC, B, BAR)
	var errs := tip_err(SC, B, res["pk"])
	print("compress: keys %d -> %d, tip errors (cm) %s, module worst %.4f m, k=%.3f" % [int(res["before"]), int(res["after"]), str(errs.map(func(x): return snappedf(float(x) * 100.0, 0.001))), float(res["worst_m"]), float(res["k"])])
	ok(jmax(errs) <= BAR, "d1 worst tip error %.4f m <= %.3f at hands, feet and bat tip (test, 240 Hz)" % [jmax(errs), BAR])
	var red := 100.0 * (1.0 - float(res["after"]) / float(res["before"]))
	ok(red >= 50.0, "d2 key reduction %.1f %% >= 50" % red)
	ok(absf(float(res["worst_m"]) - jmax(errs)) <= 0.0002, "d3 reported worst %.4f m vs test %.4f m within 0.2 mm" % [float(res["worst_m"]), jmax(errs)])
	var uni := GameClip.compress_uniform(SC, B, BAR)
	print("uniform degrees: %d keys (tol %.3f deg) vs body-aware %d" % [int(uni["after"]), float(uni["k"]), int(res["after"])])
	ok(int(res["after"]) <= int(uni["after"]), "d4 body-aware keeps %d keys <= uniform-degree %d at the same tip bar" % [int(res["after"]), int(uni["after"])])
	var ends := true
	for j in SC.part_keys:
		var o: Array = SC.part_keys[j]
		var r: Array = res["pk"][j]
		ends = ends and is_equal_approx(float(r[0]["t"]), float(o[0]["t"])) and is_equal_approx(float(r[r.size() - 1]["t"]), float(o[o.size() - 1]["t"]))
	ok(ends and (res["pk"] as Dictionary).size() == SC.part_keys.size(), "d5 first and last key of all %d joints kept" % SC.part_keys.size())
	var bad := KeyReduce.reduce(SC.part_keys, 5.0)
	var be := jmax(tip_err(SC, B, bad["pk"]))
	control(be <= BAR, "c3 uniform 5 deg: tip error %.4f m over the bar" % be)

	# ---------------- N090 RUNTIME CHECK ----------------
	var dir := "res://addons/kine_body_check"
	var src := FileAccess.get_file_as_string(dir + "/body_check.gd") if FileAccess.file_exists(dir + "/body_check.gd") else ""
	var leaks := []
	for w in ["Body.", "Scene.", "PartKeys", "FootPlant", "GameClip", "KeyReduce"]:
		if src.contains(w):
			leaks.append(w)
	var LJ = JSON.parse_string(FileAccess.get_file_as_string(dir + "/limits.json")) if FileAccess.file_exists(dir + "/limits.json") else {}
	var miss := []
	if LJ is Dictionary:
		for j in Body.ORDER:
			if B.lim.has(j) and not (LJ.has(j) and LJ[j].has("bend") and LJ[j].has("side") and LJ[j].has("twist")):
				miss.append(j)
	ok(src != "" and leaks.is_empty() and LJ is Dictionary and LJ.size() > 20 and miss.is_empty(), "e1 add-on present, free of Kine classes %s, limits.json %d joints, missing %s" % [str(leaks), (LJ as Dictionary).size() if LJ is Dictionary else 0, str(miss.slice(0, 4))])
	var chk = load(dir + "/body_check.gd").new() if src != "" else null
	if chk == null:
		ok(false, "e2-e5 the add-on cannot load")
	else:
		chk.load_limits(dir + "/limits.json")
		var sk := Skeleton3D.new()
		for nm in ["upperarm_r", "lowerarm_r", "spine_02"]:
			sk.add_bone(nm)
			sk.set_bone_rest(sk.get_bone_count() - 1, Transform3D.IDENTITY)
		sk.reset_bone_poses()
		var X := Vector3.RIGHT
		var Y := Vector3.UP
		sk.set_bone_pose_rotation(1, Quaternion(X, deg_to_rad(170.0)))
		var f2: Array = chk.check(sk)
		ok(f2.size() == 1 and String(f2[0]["bone"]) == "lowerarm_r" and float(f2[0]["excess_deg"]) >= 20.0, "e2 170 deg elbow flagged: %s" % str(f2))
		sk.set_bone_pose_rotation(1, Quaternion(X, deg_to_rad(80.0)))
		var one: Array = chk.check(sk)
		sk.set_bone_pose_rotation(1, Quaternion(X, deg_to_rad(80.0)) * Quaternion(X, deg_to_rad(80.0)))
		var both: Array = chk.check(sk)
		ok(one.is_empty() and both.size() == 1 and String(both[0]["bone"]) == "lowerarm_r", "e3 80 deg alone silent (%d flags), 80+80 blended flagged (%d)" % [one.size(), both.size()])
		sk.reset_bone_poses()
		var clean0: Array = chk.check(sk)
		sk.set_bone_pose_rotation(1, Quaternion(X, deg_to_rad(30.0)))
		sk.set_bone_pose_rotation(0, Quaternion(X, deg_to_rad(30.0)))
		sk.set_bone_pose_rotation(2, Quaternion(X, deg_to_rad(5.0)))
		var clean1: Array = chk.check(sk)
		ok(clean0.is_empty() and clean1.is_empty(), "e4 rest pose and a clean pose give %d / %d flags" % [clean0.size(), clean1.size()])
		sk.reset_bone_poses()
		sk.set_bone_pose_rotation(0, Quaternion(Y, deg_to_rad(120.0)))
		var tw: Array = chk.check(sk)
		sk.set_bone_pose_rotation(0, Quaternion(Y, deg_to_rad(40.0)))
		var tw2: Array = chk.check(sk)
		ok(tw.size() == 1 and String(tw[0]["bone"]) == "upperarm_r" and tw2.is_empty(), "e5 120 deg twist flagged (%d), 40 deg silent (%d)" % [tw.size(), tw2.size()])
		sk.free()
	var outd := tmp + "/addon_copy"
	GameClip.write_addon(outd)
	var same := true
	for f in ["body_check.gd", "limits.json"]:
		var a := FileAccess.get_file_as_bytes(dir + "/" + f)
		var b := FileAccess.get_file_as_bytes(outd + "/addons/kine_body_check/" + f) if FileAccess.file_exists(outd + "/addons/kine_body_check/" + f) else PackedByteArray()
		same = same and a.size() > 0 and a == b
	ok(same, "e6 write_addon copies the add-on under <dir>/addons/kine_body_check byte for byte")

	print("gamedel2: %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
