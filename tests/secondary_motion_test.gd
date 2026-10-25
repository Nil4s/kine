## godot --headless --path . -s tests/secondary_motion_test.gd     (ROADMAP 26, SECONDARY MOTION; scripts/secondary_motion.gd)
## A window picture (a ponytail mid-swing over the scene, baked first): SECOND_SHOT=<path.png> with a window
##   godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/secondary_motion_test.gd
## Bars, written before measuring:
##   1 STEP, PENDULUM: a 1-segment ponytail (0.38 m, zeta 0.2) takes a smooth 10 cm step of its attach point. After the
##     step the angle overshoots (the first free extremum lags, the next one leads it) and settles (|angle| < 1e-3 rad by
##     11 s). The damping ratio measured from the log decrement of successive peaks is within 10 % of 0.2. The natural
##     frequency (from the peak spacing, damped to undamped) is within 5 % of sqrt(g / L) / 2 pi.
##   2 STEP, CHAIN (info): the same step on a 4-segment ponytail: the tip's damping ratio from its peaks is printed; the
##     first mode is the configured zeta by construction (mass-proportional damping), higher modes ring a little longer.
##   3 ROD: the oak bo's bending frequency from the sim's zero crossings after a strike-like pulse is within 5 % of the
##     cantilever formula f1 = (beta1 L)^2 / (2 pi L^2) sqrt(E I / rho A); its damping from the peaks is printed.
##   4 BAKE REPLAYS THE SIM: the ponytail and the bo baked over scenes/combo3.json. At 60 times between the keys the
##     replayed angles (linear between keys) are within 1 deg of the sim run on the same attach path at that substep.
##     Anti-vacuity: the baked keys move (some segment passes 1 deg).
##   5 FILE: to_file -> JSON -> from_file gives the same keys; a malformed item (unknown joint, no mass) is dropped; a scene
##     with no item has no "secondary" key; with items it has one and from_dict reads the items back; clone() copies it.
##   6 NOTHING WITHOUT ONE: every scene in scenes/ with no "secondary" key loads and saves without the key (old files
##     are unchanged by this feature).
##   7 MIRROR: mirror twice gives the same block (attach, offset, keys within 1e-9); one mirror gives the twin joint
##     (hand_r -> hand_l), the offset's x negated and, for an x-swinging chain, the keys negated.
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


func scene_of(path: String) -> Scene:
	var sc := Scene.new()
	sc.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return sc


## smooth step of the attach point along x: D metres from t0 over T seconds, on the SUB_HZ grid for `dur` seconds
func step_path(D: float, t0: float, T: float, dur: float) -> Array:
	var P := []
	var n := int(dur * SecondaryMotion.SUB_HZ)
	for s in n:
		var t := float(s) / float(SecondaryMotion.SUB_HZ)
		var u := clampf((t - t0) / T, 0.0, 1.0)
		P.append(Vector3(D * u * u * (3.0 - 2.0 * u), 0.0, 0.0))
	return P


## the extrema [t, value] of a signal sampled on the SUB_HZ grid from time t_from (local extrema, sign alternates)
func extrema(sig: Array, t_from: float) -> Array:
	var out := []
	var dt := 1.0 / float(SecondaryMotion.SUB_HZ)
	for s in range(1, sig.size() - 1):
		var t := float(s) * dt
		if t < t_from:
			continue
		var a: float = sig[s - 1]
		var b: float = sig[s]
		var c: float = sig[s + 1]
		if (b > a and b >= c) or (b < a and b <= c):
			out.append([t, b])
	return out


## the damping ratio from successive extrema (log decrement), and the damped period from their spacing (2 x half period)
func measure(ex: Array) -> Dictionary:
	var dl := []
	# the log decrement of one full period: successive extrema alternate in sign, so the same-sign pair is two apart
	for k in range(0, mini(ex.size() - 2, 4)):
		dl.append(log(absf(float(ex[k][1])) / absf(float(ex[k + 2][1]))))
	var d := 0.0
	for x in dl:
		d += x
	d /= float(dl.size())
	var zeta := d / sqrt(4.0 * PI * PI + d * d)
	var td := 0.0
	var m := mini(ex.size() - 1, 4)
	for k in m:
		td += 2.0 * (float(ex[k + 1][0]) - float(ex[k][0]))
	td /= float(m)
	return {"zeta": zeta, "wd": TAU / td, "wn": (TAU / td) / sqrt(1.0 - zeta * zeta), "n": ex.size()}


func _init() -> void:
	var B := body()

	# 1 STEP, PENDULUM
	var pend := SecondaryMotion.preset("ponytail")
	pend["n"] = 1
	var ang1 := SecondaryMotion.run(pend, step_path(0.10, 0.5, 0.1, 11.0))
	var sig1 := []
	for a in ang1:
		sig1.append((a as PackedFloat64Array)[0])
	var ex1 := extrema(sig1, 0.7)
	var m1 := measure(ex1)
	print("   pendulum extrema (t, angle): %s" % str(ex1.slice(0, 4)))
	var wf := sqrt(SecondaryMotion.GRAV / float(pend["len"]))
	var end1 := absf(float(sig1[sig1.size() - 1]))
	print("   pendulum: %d extrema after the step, zeta %.4f (configured 0.2), wn %.4f rad/s (sqrt(g/L) = %.4f)" % [m1["n"], m1["zeta"], m1["wn"], wf])
	ok(ex1.size() >= 4 and float(ex1[0][1]) > 0.0 and float(ex1[1][1]) < 0.0 and absf(float(ex1[0][1])) > absf(float(ex1[1][1])),
		"1a overshoot: the response crosses zero and the first peak past it is the largest (then the next, the other way, smaller)")
	ok(absf(float(m1["zeta"]) - 0.2) <= 0.02, "1b damping ratio from the peaks %.4f within 10 %% of 0.2" % float(m1["zeta"]))
	ok(absf(float(m1["wn"]) - wf) / wf <= 0.05, "1c natural frequency %.4f rad/s within 5 %% of sqrt(g/L) %.4f" % [float(m1["wn"]), wf])
	ok(end1 < 1e-3, "1d settles: |angle| %.6f rad at 11 s, under 0.001" % end1)

	# 2 STEP, CHAIN (info)
	var chain := SecondaryMotion.preset("ponytail")
	var ang4 := SecondaryMotion.run(chain, step_path(0.10, 0.5, 0.1, 11.0))
	var sig4 := []
	for a in ang4:
		sig4.append((a as PackedFloat64Array)[3])
	var m4 := measure(extrema(sig4, 0.7))
	print("   chain (info): 4 segments, tip zeta from the peaks %.4f (configured 0.2), wn %.4f rad/s" % [m4["zeta"], m4["wn"]])
	ok(absf(float(sig4[sig4.size() - 1])) < 1e-3, "2a the 4-segment chain settles at 11 s")

	# 3 ROD
	var bo := SecondaryMotion.preset("bo")
	var f1 := SecondaryMotion.rod_hz(bo)
	var pulse := step_path(0.05, 0.2, 0.05, 9.0)
	var angb := SecondaryMotion.run(bo, pulse)
	var nb := int(bo["n"])
	var sigb := []
	for a in angb:
		sigb.append((a as PackedFloat64Array)[nb - 1])
	# the frequency: successive upward zero crossings after the pulse
	var zc := []
	var dt := 1.0 / float(SecondaryMotion.SUB_HZ)
	for s in range(1, sigb.size()):
		var t := float(s) * dt
		if t > 0.4 and float(sigb[s - 1]) < 0.0 and float(sigb[s]) >= 0.0:
			zc.append(t)
	var fz := 0.0
	if zc.size() >= 3:
		fz = float(zc.size() - 1) / (float(zc[zc.size() - 1]) - float(zc[0]))
	var mb := measure(extrema(sigb, 0.4))
	print("   bo: formula f1 %.4f Hz, zero crossings %.4f Hz (%d), zeta from the peaks %.4f (configured 0.02)" % [f1, fz, zc.size(), mb["zeta"]])
	ok(zc.size() >= 10 and absf(fz - f1) / f1 <= 0.05, "3a the bo rings at its formula frequency: %.4f Hz vs %.4f Hz (5 %%)" % [fz, f1])

	# 4 BAKE REPLAYS THE SIM (combo3)
	var S := scene_of("res://scenes/combo3.json")
	var sec := {"items": [SecondaryMotion.preset("ponytail"), SecondaryMotion.preset("bo")]}
	var baked := SecondaryMotion.bake_scene(S, B, sec)
	var fps := S.fps
	var L := S.length()
	var nf := maxi(int(ceil(L * float(fps) - 1e-6)), 1) + 1
	var frames := []
	for i in 2:
		frames.append([])
	for k in nf:
		var t := minf(float(k) / float(fps), L)
		S.apply(B, t)
		for i in 2:
			(frames[i] as Array).append(SecondaryMotion.attach_point(B, baked["items"][i]))
	var worst := 0.0
	var moved := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2:
		var item: Dictionary = baked["items"][i]
		var ref := SecondaryMotion.run(item, SecondaryMotion.path240(frames[i], fps))
		for q in 60:
			var t := rng.randf_range(0.02, L - 0.02)
			# the sim at t itself: linear between the two substeps around it (the substep is 4 ms; the segments move
			# up to several hundred deg a second at a hard head snap, so a snapped time would measure that, not the bake)
			var x := t * float(SecondaryMotion.SUB_HZ)
			var s0 := clampi(int(floor(x)), 0, ref.size() - 2)
			var fr := clampf(x - float(s0), 0.0, 1.0)
			var th_sim := PackedFloat64Array()
			th_sim.resize(int(item["n"]))
			for j in int(item["n"]):
				th_sim[j] = lerpf(float((ref[s0] as PackedFloat64Array)[j]), float((ref[s0 + 1] as PackedFloat64Array)[j]), fr)
			var th := SecondaryMotion.replay(baked, item, t)
			var r := SecondaryMotion.rel(th_sim)
			var rr := SecondaryMotion.rel(th)
			for j in int(item["n"]):
				worst = maxf(worst, absf(rad_to_deg(float(r[j]) - float(rr[j]))))
				moved = maxf(moved, absf(rad_to_deg(float(r[j]))))
	print("   bake: worst replay error %.4f deg over 120 times; largest keyed angle %.2f deg" % [worst, moved])
	ok(worst <= 1.0, "4a baked keys replay the sim within 1 deg (worst %.4f)" % worst)
	ok(moved >= 1.0, "4b anti-vacuity: the keys move (largest %.2f deg)" % moved)

	# 5 FILE
	var js := JSON.stringify(SecondaryMotion.to_file(baked))
	var back := SecondaryMotion.from_file(JSON.parse_string(js))
	ok(JSON.stringify(back) == js, "5a to_file -> JSON -> from_file gives the same block")
	var bad := SecondaryMotion.from_file({"items": [
		{"name": "x", "kind": "chain", "attach": "nope", "off": [0, 0, 0], "sway": "x", "n": 2, "len": 0.3, "zeta": 0.2, "mass": 0.01},
		{"name": "y", "kind": "chain", "attach": "head", "off": [0, 0, 0], "sway": "x", "n": 2, "len": 0.3, "zeta": 0.2},
		{"name": "z", "kind": "rod", "attach": "hand_r", "off": [0, 0, 0], "sway": "x", "n": 6, "len": 1.8, "zeta": 0.02, "E": 1e10, "d": 0.025, "rho": 750.0}]})
	ok(bad.get("items", []).size() == 1 and String(bad["items"][0]["name"]) == "z",
		"5b a bad joint and a chain with no mass are dropped on load; the good rod stays")
	var S0 := scene_of("res://scenes/combo3.json")
	ok(not S0.to_dict(B, false).has("secondary"), "5c a scene with no item has no 'secondary' key")
	S0.secondary = baked
	var d0 := S0.to_dict(B, false)
	ok(d0.has("secondary"), "5d a scene with items writes 'secondary'")
	var S1 := Scene.new()
	S1.from_dict(JSON.parse_string(JSON.stringify(d0)))
	ok(S1.secondary.get("items", []).size() == 2 and S1.clone().secondary.get("keys", {}).size() == baked["keys"].size(),
		"5e from_dict reads the items and keys back; clone() copies them")

	# 6 NOTHING WITHOUT ONE
	var files := DirAccess.get_files_at("res://scenes")
	var n_old := 0
	var n_bad := 0
	for f in files:
		if not f.ends_with(".json"):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f))
		if not raw is Dictionary or raw.has("secondary"):
			continue
		n_old += 1
		var sc := Scene.new()
		sc.from_dict(raw)
		if sc.to_dict(B, false).has("secondary") or not sc.secondary.is_empty():
			n_bad += 1
	ok(n_old > 0 and n_bad == 0, "6 every scene without a 'secondary' key (%d files) loads with no secondary block" % n_old)

	# 7 MIRROR
	var m2 := SecondaryMotion.mirror_file(SecondaryMotion.mirror_file(baked))
	var same := JSON.stringify(m2["items"]) == JSON.stringify(baked["items"])
	var sk := 0.0
	for j in baked["keys"]:
		for p in range(baked["keys"][j].size()):
			sk = maxf(sk, absf(float(m2["keys"][j][p][1]) - float(baked["keys"][j][p][1])))
	ok(same and sk <= 1e-9, "7a mirror twice gives the same block (keys within %.9f deg)" % sk)
	var m1b := SecondaryMotion.mirror_file(baked)
	var bo_m: Dictionary = m1b["items"][1]
	var pony_m: Dictionary = m1b["items"][0]
	ok(String(bo_m["attach"]) == "hand_l" and absf(float(bo_m["off"][0])) < 1e-12 and String(pony_m["attach"]) == "head",
		"7b one mirror: the bo moves to hand_l, a head chain stays on the head")
	var kk := 0
	for p in range(baked["keys"]["ponytail_1"].size()):
		if absf(float(baked["keys"]["ponytail_1"][p][1])) > absf(float(baked["keys"]["ponytail_1"][kk][1])):
			kk = p
	var kp0 := float(baked["keys"]["ponytail_1"][kk][1])
	var kp1 := float(m1b["keys"]["ponytail_1"][kk][1])
	ok(absf(kp0 + kp1) < 1e-9 and absf(kp0) > 1e-6, "7c a chain swinging along x has its angles negated by one mirror (%.4f -> %.4f)" % [kp0, kp1])

	print("secondary_motion: %d failures" % fails)

	var shot := OS.get_environment("SECOND_SHOT")
	if shot != "":
		await _shot(shot)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## the picture: the ponytail baked over combo3, the playhead at its largest swing, the view saved to shot
func _shot(shot: String) -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playing = false
	m._sec_add("ponytail")
	var keys: Dictionary = m.S.secondary["keys"]
	var ks: Array = keys["ponytail_1"]
	var best_t := 0.0
	var best := -1.0
	for p in ks:
		if float(p[0]) > 0.5 and absf(float(p[1])) > best:
			best = absf(float(p[1]))
			best_t = float(p[0])
	m.playhead = best_t
	m._ps().apply(m.B, best_t)
	# the camera on the head, from the front: the ponytail sways along x, so the front shows it
	m._turn_to(10.0, -4.0, 1.1, (m.B.P["head"] as Vector3) + Vector3(0.0, 0.05, 0.0), false)
	m._refresh()
	for i in 3:
		await process_frame
	DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
	await process_frame
	root.get_texture().get_image().save_png(shot)
	print("   picture at %.2f s (ponytail_1 %.1f deg) -> %s" % [best_t, best, shot])
