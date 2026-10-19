## godot --headless --path . -s tests/constraints_test.gd     (GATES Round 51 CN1..CN3; scripts/constraints.gd)
## Bars, written before measuring (GATES.md "Round 51 (CN)"):
##   1 CHILD OF on a moving target (the left hand held to the right hand while the arms and the trunk move): at influence
##     1 the left wrist's world transform = target x stored offset within 1 mm and 0.5 deg at every step of a 240 Hz
##     sweep; anti-vacuity: unconstrained it is > 5 cm off. Influence 0: every frame bit-identical to no constraint.
##   2 NO POP: influence keyed 1 -> 0 over 6 frames: the wrist's frame-to-frame speed never exceeds 2x the largest speed
##     it has in the unconstrained playback; anti-vacuity: the same release over 1 frame exceeds it. RELEASE KEEPING THE
##     POSE (Constraints.release_keep): at the release frame the wrist is < 1 mm from where the constraint held it.
##   3 TRACK TO: for targets all round the head, whenever an independent brute-force search over legal neck + head angles
##     finds a pose aiming within 1 deg, the solve aims within 2 deg; when the best legal aim is > 3 deg off, a neck / head
##     angle sits AT its limit (0.5 deg); no joint past a limit on any frame. Two fighters: the hero's head tracks the
##     other fighter's head (posed from its own scene at its placement) within 2 deg.
##   4 FILE: "constraints" only when there is one; save -> load -> save equal, the schema validates it, the reload plays
##     within 0.05 mm; Scene.mirror_file: the mirrored owner (hand_r) plays at the mirrored place (x negated) within 1 mm.
##   5 NOTHING CHANGES WITHOUT ONE: every scene in scenes/ (read only) with muted / influence-0 constraints added plays
##     bit-identical to the scene as it is, every frame.
##   6 FLOOR: a body sunk 4 cm into the floor: the left foot's lowest sole point >= -0.5 mm at every 240 Hz step with the
##     floor constraint (anti-vacuity: < -2 cm without); frames where the foot is above the floor bit-identical (it pushes,
##     never pulls).
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


func pose(B: Body, angs: Dictionary, off := Vector3.ZERO) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = off
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


func trunk(d: Dictionary, bend: float, side: float, twist: float) -> Dictionary:
	var o := d.duplicate()
	for j in ["spine_01", "spine_02", "spine_03"]:
		o[j] = Vector3(bend, side, twist)
	return o


## two hands in front (holding a box), the arms and the trunk moving: 3 cards, 24 fps
func hold_scene(B: Body) -> Scene:
	var S := Scene.new()
	S.fps = 24
	S.add("a", pose(B, {"upperarm_r": Vector3(45, -50, 0), "lowerarm_r": Vector3(70, 0, 0), "upperarm_l": Vector3(45, -50, 0), "lowerarm_l": Vector3(70, 0, 0)}))
	S.add("b", pose(B, trunk({"upperarm_r": Vector3(62, -50, 0), "lowerarm_r": Vector3(52, 0, 0), "upperarm_l": Vector3(55, -45, 0), "lowerarm_l": Vector3(60, 0, 0)}, 5, 0, -14)))
	S.add("c", pose(B, trunk({"upperarm_r": Vector3(32, -52, 0), "lowerarm_r": Vector3(88, 0, 0), "upperarm_l": Vector3(35, -50, 0), "lowerarm_l": Vector3(80, 0, 0)}, 14, -5, 6)))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.2
	S.cards[1]["move"] = 1.4
	S.cards[1]["hold"] = 0.0
	S.cards[2]["move"] = 1.4
	S.cards[2]["hold"] = 0.4
	return S


func frames(S: Scene, hz: float) -> Array:
	var out := []
	var n := int(ceilf(S.length() * hz - 1e-6))
	for f in n + 1:
		out.append(minf(float(f) / hz, S.length()))
	return out


func snap(B: Body) -> String:
	return var_to_str(B.ang) + var_to_str(B.offset) + var_to_str(B.wep_xform())


func limit_worst(B: Body) -> float:
	var worst := 0.0
	for j in B.ang:
		var a: Vector3 = B.ang[j]
		var d: Vector3 = (B.clamp_ang(j, a) - a).abs()
		worst = maxf(worst, d[d.max_axis_index()])
	return worst


func offset_xf(c: Dictionary) -> Transform3D:
	return Transform3D(Basis(c["offset"]["rot"]), c["offset"]["pos"])


func _init() -> void:
	var B := body()
	var lim_w := 0.0

	# ------------------------------------------------ 1 CHILD OF on a moving target
	var S0 := hold_scene(B)
	var S := hold_scene(B)
	S.apply(B, 0.0)
	var c := Constraints.add_child_of(S, B, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	var O := offset_xf(c)
	var wp := 0.0
	var wr := 0.0
	var wf := 0.0
	var wrep := ""
	var drift := 0.0
	var B0 := body()
	for t in frames(S, 240.0):
		S.apply(B, t)
		var want: Transform3D = Constraints.owner_xf(B, "hand_r") * O
		wp = maxf(wp, ((B.P["hand_l"] as Vector3) - want.origin).length())
		var e := rad_to_deg((B.G["hand_l"] as Quaternion).angle_to(want.basis.get_rotation_quaternion()))
		if e > wr:
			wr = e
			wf = t
			wrep = "%s; hand %s" % [S.cons_last, B.ang["hand_l"]]
		lim_w = maxf(lim_w, limit_worst(B))
		S0.apply(B0, t)
		var want0: Transform3D = Constraints.owner_xf(B0, "hand_r") * O
		drift = maxf(drift, ((B0.P["hand_l"] as Vector3) - want0.origin).length())
	print("     at the worst turn the pass said: " + wrep)
	ok(wp <= 0.001 and wr <= 0.5, "1 CHILD OF: at 240 Hz (%d steps) the held left wrist = right hand x offset within %.4f mm and %.4f deg (worst turn at %.3f s; bars 1 mm, 0.5 deg)" % [frames(S, 240.0).size(), wp * 1000.0, wr, wf])
	ok(drift > 0.05, "1 anti-vacuity: unconstrained the left wrist is up to %.1f cm off that place (bar > 5 cm)" % (drift * 100.0))
	var Sz := hold_scene(B)
	Sz.cons = [S.cons[0].duplicate(true)]
	Sz.cons[0]["w"] = 0.0
	var same := true
	var Ba := body()
	var Bb := body()
	for t in frames(S, 24.0):
		S0.apply(Ba, t)
		Sz.apply(Bb, t)
		if snap(Ba) != snap(Bb) or not Sz.cons_last.is_empty():
			same = false
	ok(same, "1 influence 0: every frame bit-identical to the unconstrained playback")

	# ------------------------------------------------ 2 NO POP
	var fr24 := frames(S, 24.0)
	var vmax := 0.0
	var vat := 0.0
	var prev := Vector3.INF
	for t in fr24:
		S0.apply(B, t)
		if prev != Vector3.INF and ((B.P["hand_l"] as Vector3) - prev).length() > vmax:
			vmax = ((B.P["hand_l"] as Vector3) - prev).length()
			vat = t
		prev = B.P["hand_l"]
	print("     the unconstrained wrist's largest step %.2f mm ends at %.3f s" % [vmax * 1000.0, vat])
	var t1 := 1.0
	var speeds := []
	var vwin := 0.0
	for n in [6, 1]:
		var Sf := hold_scene(B)
		Sf.cons = [S.cons[0].duplicate(true)]
		Sf.cons[0]["wk"] = [[t1, 1.0], [t1 + float(n) / Sf.fps, 0.0]]
		var vm := 0.0
		prev = Vector3.INF
		for t in fr24:
			Sf.apply(B, t)
			if prev != Vector3.INF:
				vm = maxf(vm, ((B.P["hand_l"] as Vector3) - prev).length())
				if t > t1 and t <= t1 + float(n + 1) / Sf.fps:
					vwin = maxf(vwin, ((B.P["hand_l"] as Vector3) - prev).length())
			prev = B.P["hand_l"]
			lim_w = maxf(lim_w, limit_worst(B))
		print("     released over %d frame(s) at %.2f s: the largest step during the release %.2f mm" % [n, t1, vwin * 1000.0])
		vwin = 0.0
		speeds.append(vm)
	ok(speeds[0] <= 2.0 * vmax, "2 NO POP: influence 1 -> 0 over 6 frames: the wrist moves at most %.2f mm a frame (bar 2 x %.2f = %.2f mm, the unconstrained playback's largest)" % [speeds[0] * 1000.0, vmax * 1000.0, 2.0 * vmax * 1000.0])
	ok(speeds[1] > 2.0 * vmax, "2 anti-vacuity: the same release over 1 frame moves it %.2f mm in a frame" % (speeds[1] * 1000.0))
	var Sr := hold_scene(B)
	Sr.cons = [S.cons[0].duplicate(true)]
	var t_r: float = Sr.times()[1][1]
	var rk := Constraints.release_keep(Sr, B, 0, t_r)
	Sr.apply(B, t_r)
	var at_r: Vector3 = B.P["hand_l"]
	S.apply(B, t_r)
	var held: Vector3 = B.P["hand_l"]
	var w_after := Constraints.weight(Sr.cons[0], t_r + 0.2)
	vmaxs_release(Sr, B, fr24)
	ok(rk.get("ok", false) and (at_r - held).length() < 0.001 and w_after == 0.0, "2 RELEASE KEEPING THE POSE at card 2 (%.3f s): the wrist %.4f mm from where the constraint held it (bar 1 mm), influence after it %.1f, card residual %.4f deg; largest step over the scene %.2f mm (unconstrained %.2f)" % [t_r, (at_r - held).length() * 1000.0, w_after, float(rk.get("residual", INF)), _rel_v * 1000.0, vmax * 1000.0])

	# ------------------------------------------------ 3 TRACK TO
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var St := hold_scene(B)
	var n_in := 0
	var n_out := 0
	var n_mid := 0
	var worst_in := 0.0
	var bad_out := []
	for i in 36:
		var yaw := deg_to_rad(float(i) * 10.0)
		var el := rng.randf_range(-0.6, 0.9)
		var tgt := Vector3(sin(yaw) * 1.5, 1.6 + el, cos(yaw) * 1.5)
		var tt := float(i % 3) * 0.7
		St.cons = []
		St.cons.append({"type": "track_to", "owner": "head", "target": {"kind": "point", "at": tgt}, "w": 1.0, "wk": []})
		St.cons[0]["mute"] = true
		St.apply(B, tt)   # the animated pose: what the brute force starts from
		var best := brute(B, tgt, rng)
		St.cons[0].erase("mute")
		St.apply(B, tt)
		lim_w = maxf(lim_w, limit_worst(B))
		var err := LookAt.amplitude(B, tgt)
		var at_lim: bool = not B.at_limit("neck_01").is_empty() or not B.at_limit("head").is_empty()
		if best <= 1.0:
			n_in += 1
			worst_in = maxf(worst_in, err)
		elif best > 3.0:
			n_out += 1
			if not at_lim:
				bad_out.append("yaw %d: best %.1f, ours %.1f" % [i * 10, best, err])
		else:
			n_mid += 1
	ok(n_in >= 5 and worst_in <= 2.0, "3 TRACK TO: %d targets inside the neck's range (brute force <= 1 deg): the head aims within %.3f deg at worst (bar 2)" % [n_in, worst_in])
	ok(n_out >= 5 and bad_out.is_empty(), "3 outside (%d targets, brute force > 3 deg; %d between 1 and 3 not graded): a neck / head angle at its limit every time %s" % [n_out, n_mid, bad_out])
	# two fighters: the hero's head on the other fighter's head, at 24 fps over the scene
	var H := hold_scene(B)
	var other := hold_scene(B)
	H.actors = [{"name": "B", "xf": {"pos": [0.3, 1.6], "yaw": 180.0}, "scene": other}]
	Constraints.link(H)
	H.cons = [{"type": "track_to", "owner": "head", "target": {"kind": "actor", "actor": 1, "part": "head"}, "w": 1.0, "wk": []}]
	var Bo := body()
	var w2 := 0.0
	var X := Constraints.actor_xf(H.actors[0]["xf"])
	for t in fr24:
		H.apply(B, t)
		other.apply(Bo, t)
		var oh: Vector3 = X * (Bo.P["head"] as Vector3)
		w2 = maxf(w2, LookAt.amplitude(B, oh))
		lim_w = maxf(lim_w, limit_worst(B))
	ok(w2 <= 2.0, "3 two fighters: the hero's head tracks the other fighter's head within %.3f deg at every frame (bar 2)" % w2)

	# ------------------------------------------------ 6 FLOOR
	var Sf0 := Scene.new()
	Sf0.fps = 24
	Sf0.on_floor = false
	Sf0.add("stand", pose(B, {"thigh_l": Vector3(10, 0, 0), "calf_l": Vector3(20, 0, 0), "foot_l": Vector3(-10, 0, 0)}))
	Sf0.add("sunk", pose(B, {"thigh_l": Vector3(10, 0, 0), "calf_l": Vector3(20, 0, 0), "foot_l": Vector3(-10, 0, 0)}, Vector3(0, -0.04, 0)))
	Sf0.add("up", pose(B, {"thigh_l": Vector3(10, 0, 0), "calf_l": Vector3(20, 0, 0), "foot_l": Vector3(-10, 0, 0)}, Vector3(0, 0.0, 0)))
	Sf0.cards[1]["move"] = 0.5
	Sf0.cards[2]["move"] = 0.5
	var Sf := Sf0.clone()
	Constraints.add_floor(Sf, "foot_l")
	var low_c := INF
	var low_p := INF
	var above_same := true
	var n_above := 0
	for t in frames(Sf, 240.0):
		Sf0.apply(Ba, t)
		Sf.apply(Bb, t)
		low_p = minf(low_p, Ba.foot_sole_low("_l"))
		low_c = minf(low_c, Bb.foot_sole_low("_l"))
		lim_w = maxf(lim_w, limit_worst(Bb))
		if Ba.foot_sole_low("_l") >= 0.0:
			n_above += 1
			above_same = above_same and snap(Ba) == snap(Bb)
	ok(low_c >= -0.0005, "6 FLOOR: the left foot's lowest sole point never below %.3f mm at 240 Hz (bar -0.5 mm)" % (low_c * 1000.0))
	ok(low_p < -0.02, "6 anti-vacuity: without it the foot goes %.1f mm under" % (low_p * 1000.0))
	ok(n_above > 10 and above_same, "6 above the floor (%d steps) the pose is bit-identical to no constraint: %s" % [n_above, above_same])

	# ------------------------------------------------ 4 FILE + MIRROR
	var Sd := hold_scene(B)
	var plain: Dictionary = Sd.to_dict(B)
	Sd.cons = S.cons.duplicate(true)
	Sd.cons.append({"type": "track_to", "owner": "head", "target": {"kind": "point", "at": Vector3(0.2, 1.6, 1.5)}, "w": 1.0, "wk": [[0.0, 0.0], [0.5, 1.0]]})
	Sd.cons.append({"type": "floor", "owner": "foot_r", "height": 0.0, "w": 1.0, "wk": []})
	var d1: Dictionary = JSON.parse_string(JSON.stringify(Sd.to_dict(B)))
	var Sl := Scene.new()
	Sl.from_dict(d1)
	var d2: Dictionary = JSON.parse_string(JSON.stringify(Sl.to_dict(B)))
	var errs := Validate.data(d1)
	var rt := 0.0
	for t in fr24:
		Sd.apply(Ba, t)
		Sl.apply(Bb, t)
		for j in ["hand_l", "head", "foot_r"]:
			rt = maxf(rt, ((Ba.P[j] as Vector3) - (Bb.P[j] as Vector3)).length())
	ok(not plain.has("constraints") and d1.has("constraints") and JSON.stringify(d1["constraints"]) == JSON.stringify(d2["constraints"]) and errs.is_empty() and rt <= 0.00005,
		"4 FILE: none without (%s); 3 saved, save -> load -> save equal: %s; schema errors %s; the reload plays within %.5f mm (bar 0.05)" % [plain.has("constraints"), JSON.stringify(d1["constraints"]) == JSON.stringify(d2["constraints"]), errs, rt * 1000.0])
	var Sm1 := hold_scene(B)
	Sm1.cons = S.cons.duplicate(true)
	var M := body()
	var dm := Scene.mirror_file(JSON.parse_string(JSON.stringify(Sm1.to_dict(B))), M)
	var Sm := Scene.new()
	Sm.from_dict(dm)
	var mw := 0.0
	for t in fr24:
		Sm1.apply(Ba, t)
		Sm.apply(Bb, t)
		var a: Vector3 = Ba.P["hand_l"]
		mw = maxf(mw, (Vector3(-a.x, a.y, a.z) - (Bb.P["hand_r"] as Vector3)).length())
	ok(Sm.cons.size() == 1 and Sm.cons[0]["owner"] == "hand_r" and Sm.cons[0]["target"]["part"] == "hand_l" and mw <= 0.001,
		"4 MIRROR: owner %s, target %s; the mirrored right wrist plays at the original left one's x-negated place within %.4f mm (bar 1 mm)" % [Sm.cons[0]["owner"], Sm.cons[0]["target"], mw * 1000.0])

	# ------------------------------------------------ 5 NOTHING CHANGES WITHOUT ONE
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
		if not Sa.cons.is_empty():
			differ.append(fn + " (already has constraints)")
		Sb.cons = [{"type": "child_of", "owner": "hand_l", "target": {"kind": "part", "part": "hand_r"}, "offset": {"pos": Vector3(0.3, 0, 0), "rot": Quaternion.IDENTITY}, "w": 1.0, "wk": [], "mute": true},
			{"type": "track_to", "owner": "head", "target": {"kind": "point", "at": Vector3(1, 1.6, 1)}, "w": 0.0, "wk": []},
			{"type": "floor", "owner": "foot_l", "height": 0.3, "w": 1.0, "wk": [[0.0, 0.0]]}]
		var B1 := body()
		var B2 := body()
		for t in frames(Sa, float(Sa.fps)):
			Sa.apply(B1, t)
			Sb.apply(B2, t)
			nfr += 1
			if snap(B1) != snap(B2):
				differ.append("%s at %.3f s" % [fn, t])
				break
		nsc += 1
	ok(nsc >= 5 and differ.is_empty(), "5 every scene in scenes/ (%d, %d frames) plays bit-identical with muted / influence-0 constraints added (differ: %s)" % [nsc, nfr, differ])

	ok(lim_w <= 1e-4, "LIMITS: no joint past its limits on any frame of 1, 2, 3, 6 (the most any angle sits outside: %.6f deg)" % lim_w)
	print("CONSTRAINTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


var _rel_v := 0.0


func vmaxs_release(Sr: Scene, B: Body, fr: Array) -> void:
	var prev := Vector3.INF
	_rel_v = 0.0
	for t in fr:
		Sr.apply(B, t)
		if prev != Vector3.INF:
			_rel_v = maxf(_rel_v, ((B.P["hand_l"] as Vector3) - prev).length())
		prev = B.P["hand_l"]


## the best aim (deg) any legal neck + head angles give at this target, by search: 6000 random legal sets, then a local
## search from the best (steps 4 -> 0.25 deg on each of the 6 angles, kept inside the limits). B is put back after
func brute(B: Body, tgt: Vector3, rng: RandomNumberGenerator) -> float:
	var keep := {"neck_01": B.ang["neck_01"], "head": B.ang["head"]}
	var was_fast := B.fast
	B.fast = true
	var js := ["neck_01", "head"]
	var best := INF
	var bv := [B.ang["neck_01"], B.ang["head"]]
	for i in 6000:
		var v := []
		for j in js:
			var L: Dictionary = B.lim[j]
			v.append(Vector3(rng.randf_range(L["bend"].x, L["bend"].y), rng.randf_range(L["side"].x, L["side"].y), rng.randf_range(L["twist"].x, L["twist"].y)))
		B.ang["neck_01"] = v[0]
		B.ang["head"] = v[1]
		B.fk_sub("neck_01")
		var e := LookAt.amplitude(B, tgt)
		if e < best:
			best = e
			bv = v
	var step := 4.0
	while step >= 0.25:
		var moved := true
		while moved:
			moved = false
			for k in 6:
				for sg in [-1.0, 1.0]:
					var v: Array = [bv[0], bv[1]]
					var x: Vector3 = v[k / 3]
					x[k % 3] += sg * step
					v[k / 3] = B.clamp_ang(js[k / 3], x)
					B.ang["neck_01"] = v[0]
					B.ang["head"] = v[1]
					B.fk_sub("neck_01")
					var e := LookAt.amplitude(B, tgt)
					if e < best - 1e-6:
						best = e
						bv = v
						moved = true
		step *= 0.5
	B.ang["neck_01"] = keep["neck_01"]
	B.ang["head"] = keep["head"]
	B.fk()
	B.fast = was_fast
	return best
