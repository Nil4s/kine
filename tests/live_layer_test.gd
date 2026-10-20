extends SceneTree
## LIVE LAYER (scripts/live_layer.gd): walk_bat's landmarks stream as the webcam would (tools/live_pose.py --replay) while
## combo3 is open (read only: nothing is saved). Layering the ARMS from 0.50 s:
##   1 while recording, the legs are the clip's pose at the clip's clock and the arms are the webcam's
##   2 stop writes part keys on the 8 arm joints only, from 0.50 s, one every 1/15 s, inside the clip; the cards are untouched
##   3 the clip sampled at a key time: arms = the key, every other joint = the card blend exactly
##   4 one undo step; Ctrl+Z gives the part keys back exactly
##   5 apply() keeps a joint's keys outside the new span and replaces those inside it
const WALK := "res://scenes/walk_bat.json"   # READ ONLY
const FPS := 30.0
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/live_layer.png"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var dir := "user://live_layer_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var Bs := Body.new()
	Bs.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string(WALK)))
	var frames := []
	for i in int(W.length() * FPS) + 1:
		W.apply(Bs, minf(i / FPS, W.length()))
		Bs.fk()
		var w := []
		for p in VideoImport.landmarks_of(Bs):
			w.append([snappedf(p.x, 0.0001), snappedf(-p.y, 0.0001), snappedf(-p.z, 0.0001)])
		frames.append({"t": snappedf(i / FPS, 0.0001), "world": w})
	var replay := dir + "src.json"
	FileAccess.open(replay, FileAccess.WRITE).store_string(JSON.stringify({"fps": FPS, "frames": frames}))

	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	await idle()
	var S: Scene = m.S
	var cards0 := JSON.stringify(S.cards)
	var pk0 := (S.part_keys as Dictionary).duplicate(true)
	m.live.python = m.video_python
	var why: String = m.live.start_replay(ProjectSettings.globalize_path(LivePuppet.TOOL), ProjectSettings.globalize_path(replay))
	ok(why == "", "the replay tracker starts (%s)" % why)
	var t_end := Time.get_ticks_msec() + 20000
	while m.live.frames_posed < 3 and Time.get_ticks_msec() < t_end:
		await idle(1)
	ok(m.live.frames_posed >= 3, "the body follows the replay (%d frames posed)" % m.live.frames_posed)

	m.playhead = 0.5
	var u0: int = m.undo.size()
	m._live_layer("arms")
	ok(m.live.recording and m.live_layer.size() == 8, "layering the arms: recording, %d joints" % m.live_layer.size())
	# (1) mid-take: legs = the clip at the clip's clock, arms = the webcam's fit
	var t_mid := Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < t_mid:
		await idle(1)
	var Bc := Body.new()
	Bc.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply(Bc, m.playhead)
	var leg_err := 0.0
	for j in ["thigh_l", "calf_l", "thigh_r", "calf_r", "spine_02"]:
		leg_err = maxf(leg_err, ((m.B.ang[j] as Vector3) - (Bc.ang[j] as Vector3)).length())
	var arm_diff := 0.0
	for j in ["upperarm_l", "upperarm_r", "lowerarm_l"]:
		arm_diff = maxf(arm_diff, ((m.B.ang[j] as Vector3) - (Bc.ang[j] as Vector3)).length())
	ok(leg_err < 0.01, "(1) while recording, the unlayered joints are the clip at %.2f s (worst %.4f deg)" % [m.playhead, leg_err])
	ok(arm_diff > 5.0, "(1) the arms are the webcam's, not the clip's (they differ by up to %.1f deg)" % arm_diff)
	var t_stop := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < t_stop:
		await idle(1)
	var keys: Dictionary = m._live_layer_stop()
	await idle()

	# (2)
	var added := []
	for j in S.part_keys:
		if not pk0.has(j) or JSON.stringify(S.part_keys[j]) != JSON.stringify(pk0[j]):
			added.append(j)
	added.sort()
	var want: Array = (LiveLayer.GROUPS["arms"] as Array).duplicate()
	want.sort()
	ok(added == want, "(2) part keys on the 8 arm joints only (%s)" % [added])
	var ks: Array = S.part_keys.get("upperarm_r", [])
	var spaced := ks.size() >= 10
	for i in range(1, ks.size() - 1):
		spaced = spaced and absf(float(ks[i]["t"]) - float(ks[i - 1]["t"]) - LiveLayer.DT) < 0.001
	ok(not ks.is_empty() and absf(float(ks[0]["t"]) - 0.5) < 0.001 and float(ks[-1]["t"]) <= S.length() + 1e-6 and spaced,
		"(2) %d keys from %.3f s to %.3f s, every 1/15 s, inside the clip (%.2f s)" % [ks.size(), float(ks[0]["t"]) if not ks.is_empty() else -1.0, float(ks[-1]["t"]) if not ks.is_empty() else -1.0, S.length()])
	ok(JSON.stringify(S.cards) == cards0, "(2) the cards are untouched")

	# (3)
	var tk := float(ks[ks.size() / 2]["t"])
	var Bk := Body.new()
	Bk.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply_true(Bk, tk)
	var pk1 := (S.part_keys as Dictionary).duplicate(true)
	S.part_keys = pk0.duplicate(true)
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply_true(B0, tk)
	S.part_keys = pk1
	var lim := Body.new()
	lim.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var lim_v: Vector3 = lim.clamp_ang("upperarm_r", ks[ks.size() / 2]["v"])
	print("       key %s  played %s  key within the limits %s" % [ks[ks.size() / 2]["v"], Bk.ang["upperarm_r"], lim_v])
	var arm_err := ((Bk.ang["upperarm_r"] as Vector3) - lim_v).length()
	var rest_err := 0.0
	for j in Body.BODY:
		if not want.has(j):
			rest_err = maxf(rest_err, ((Bk.ang[j] as Vector3) - (B0.ang[j] as Vector3)).length())
	ok(arm_err < 0.01 and rest_err < 0.001, "(3) at %.3f s the arm is its key (%.4f deg off) and every other joint the card blend (worst %.4f deg)" % [tk, arm_err, rest_err])

	# screenshot: the layered clip at that key, side-on, whole body (the webcam off first: a live puppet poses the body itself)
	m.live.stop()
	await idle(6)
	m.playhead = tk
	m._ps().apply(m.B, tk)
	m.yaw = 60.0
	m.dist = 5.0
	m.pitch = -8.0
	m.target = Vector3(m.B.P["pelvis"].x, 0.85, m.B.P["pelvis"].z)
	m._cam()
	m._refresh()
	await idle(4)
	root.get_texture().get_image().save_png(SHOT)
	var app_err := ((m.B.ang["upperarm_r"] as Vector3) - lim_v).length()
	ok(app_err < 0.01, "(3) the app plays the layered arm at %.3f s (%.4f deg off its key)" % [tk, app_err])

	# (4)
	ok(m.undo.size() == u0 + 1, "(4) one undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.part_keys) == JSON.stringify(pk0) and JSON.stringify(m.S.cards) == cards0, "(4) Ctrl+Z gives the part keys and cards back exactly")

	# (5)
	var T := Scene.new()
	T.part_keys = {"head": [{"t": 0.1, "v": Vector3(1, 0, 0)}, {"t": 0.6, "v": Vector3(2, 0, 0)}, {"t": 2.0, "v": Vector3(3, 0, 0)}]}
	LiveLayer.apply(T, {"head": [{"t": 0.5, "v": Vector3(9, 0, 0)}, {"t": 1.0, "v": Vector3(9, 0, 0)}]})
	var ts := []
	for k in T.part_keys["head"]:
		ts.append(float(k["t"]))
	ok(ts == [0.1, 0.5, 1.0, 2.0], "(5) apply keeps keys outside the span and replaces those inside (%s)" % [ts])

	# (6) a TWO-HANDED weapon clip (bo_spin, read only): walk_bat's arms layered on; the second hand stays on the staff
	var Bo := Scene.new()
	Bo.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/bo_spin.json")))
	var Bb := Body.new()
	Bb.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var base_g := 0.0
	var tb := 0.0
	while tb <= Bo.length():
		Bo.apply_true(Bb, tb)
		if Bb.wep_on and Bb.grip:
			base_g = maxf(base_g, Bb.grip_miss())
		tb += 0.05
	print("       bo_spin unlayered: worst second-hand miss %.1f cm" % (base_g * 100.0))
	var Bg0 := Body.new()
	Bg0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var take := []
	for i in int(minf(W.length(), Bo.length()) * FPS):
		W.apply(Bs, i / FPS)
		var ang := {}
		for j in Body.BODY:
			ang[j] = Bs.ang[j]
		take.append({"t": 1000.0 + i / FPS, "ang": ang})
	var bo_keys := LiveLayer.keys_from_take(take, LiveLayer.GROUPS["arms"], 0.0, Bo.length())
	LiveLayer.apply(Bo, bo_keys)
	var t_bake := Time.get_ticks_msec()
	var n_re := LiveLayer.bake_grip(Bo, Bg0, bo_keys)
	print("       bake_grip: %d key times re-made in %d ms" % [n_re, Time.get_ticks_msec() - t_bake])
	var Bg := Body.new()
	Bg.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var worst_turn := 0.0
	var worst_g := 0.0
	var worst_off := 0.0
	var n_g := 0
	var n_in := 0
	var tt := 0.0
	while tt <= Bo.length():
		Bo.apply_true(Bg, tt)
		if Bg.wep_on and Bg.grip:
			n_g += 1
			worst_g = maxf(worst_g, Bg.grip_miss())
			if Bg.grip_miss() <= base_g + 0.002:
				n_in += 1
			var o6 := "hand_l" if Bg.wep_hand == "hand_r" else "hand_r"
			var pk6: Dictionary = Bo.part_keys
			Bo.part_keys = {}
			Bo.apply_true(Bb, tt)
			Bo.part_keys = pk6
			var r0 := ((Bb.wep_xform()[1] as Quaternion).inverse() * (Bb.G[o6] as Quaternion)).normalized()
			var r1 := ((Bg.wep_xform()[1] as Quaternion).inverse() * (Bg.G[o6] as Quaternion)).normalized()
			worst_turn = maxf(worst_turn, rad_to_deg(r0.angle_to(r1)))
		tt += 0.05
	var Bw := Body.new()
	Bw.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var off_hand := ""
	tt = 0.0
	while tt <= Bo.length():
		var smp: Dictionary = Bo.sample(tt)
		Scene.put(Bw, smp)
		if Bw.wep_on and Bw.grip:
			worst_off = maxf(worst_off, Bw.grip_miss())
		tt += 0.05
	ok(n_g >= 8 and n_in * 4 >= n_g * 3 and worst_off > 0.05,
		"(6) two-handed bo_spin, the arms layered: the second hand on the staff (within the clip's own %.1f cm) at %d of %d times, worst %.1f cm; without the regrip %.1f cm off" % [base_g * 100.0, n_in, n_g, worst_g * 100.0, worst_off * 100.0])
	var t_us := Time.get_ticks_usec()
	for k in 60:
		Bo.apply_true(Bg, 2.15)
	var per_ms := (Time.get_ticks_usec() - t_us) / 60000.0
	ok(per_ms < 8.0, "(6) a regripped frame costs %.2f ms (under 8 ms)" % per_ms)
	m.S = Bo
	m.playhead = 2.15
	m._ps().apply(m.B, 2.15)
	m.yaw = 30.0
	m.target = Vector3(m.B.P["pelvis"].x, 0.9, m.B.P["pelvis"].z)
	m._cam()
	m._refresh()
	await idle(4)
	root.get_texture().get_image().save_png(SHOT.replace(".png", "_bo.png"))
	# close on the hands: the clip as it was, then the layered take, same camera
	var hands_at: Vector3 = (m.B.P["hand_l"] + m.B.P["hand_r"]) * 0.5
	for pass_i in 2:
		var pk_s: Dictionary = Bo.part_keys
		if pass_i == 0:
			Bo.part_keys = {}
		m._ps().apply(m.B, 2.15)
		m.yaw = 15.0
		m.pitch = -5.0
		m.dist = 1.6
		m.target = hands_at
		m._cam()
		m._refresh()
		await idle(4)
		root.get_texture().get_image().save_png(SHOT.replace(".png", "_hands_%s.png" % ["clip", "layered"][pass_i]))
		Bo.part_keys = pk_s
	ok(worst_turn < 25.0, "(6) the second hand wraps the staff as the clip holds it: its turn round the staff within %.0f deg of the clip's (bar 25; before the fix 86-146, flipped)" % worst_turn)
	var rep := LiveLayer.grip_report(Bo, Bg)
	ok(int(rep["n"]) == n_g and int(rep["off"]) == n_g - n_in, "(6) the app counts the times the second hand cannot reach (%d of %d)" % [rep["off"], rep["n"]])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(replay))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	print("LIVE LAYER ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
