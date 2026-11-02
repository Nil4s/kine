## godot --path . -s tests/clips_test.gd [-- --shot=C:/x.png]     (GAP_ANALYSIS row 12; needs a window: the timeline)
## CLIPS PLACED AS STRIPS (scripts/clips.gd, scripts/clips_ui.gd; docs/research/NLA.md). The source is Nick's
## scenes/walk_bat.json, READ only; the target is a two-card scene built here with no weapon. Nothing is written outside
## user:// (never scenes/, poses/, data/).
##   1 a clip at start s (mask all, replace) plays the source's own pose at t - s: every joint within 0.01 deg, hips 0.1 mm
##   2 repeat 3, speed 2: length = 3 L / 2 exactly; cycle k and the source time at 8 times are the formula's exactly; the
##     end reads the source's last frame; one frame past it (extrapolation nothing) the body is the cards' bit for bit
##   3 blend in 0.4 s: at 0.1 s in the weight is 0.25 (ramp = (t - s) / bin) and every joint = below + 0.25 (clip - below)
##   4 a legs mask leaves every other joint bit for bit as the cards play it; the legs are the source's
##   5 a walk repeated 3 times: the pelvis at the same point of cycles 0, 1, 2 moves by the cycle's step each repeat (1 mm)
##   6 the file round trip (to_dict -> JSON -> from_dict: same clips, same frames), schema-shaped keys, mirror toggles
##   7 scenes with no clip play bit-identical to before (combo3 + walk_bat, 247 frames, the hash taken on the base commit);
##     a muted clip and a weight-0 clip leave the body bit for bit
##   8 in the app: place / remove are ONE undo step each, a drag on the bar moves it (one step), the strip is drawn
extends SceneTree

const BASE_HASH := "4b8adc1bf7de3875d588a7f5d51b75fd"   # re-baselined from caaff2e7fb3fea766505ed63b31cb573 (s255): 37457e51 (HANDS) added state key free_hand and 80bdf6ec (Blade turn) added wep_turn + wep_tilt to Body.state(); with those 3 keys erased the 247 frames hash to caaff2e7 exactly, so every joint angle and weapon value is bit-identical, only the dict shape grew. Earlier: tests/ hash of combo3 + walk_bat with no clips. Re-baselined from 4070ef4b97d86fefca43d335b5963ed2 (poser-ui-rounds c0ea5e4): 88eb4c1 (toe cap TOE_MTP_MAX 45 + _toe_guard) legitimately changed walk_bat, and only the ball_l/ball_r angles (47 of 106 frames; every other joint bit-identical, combo3 unchanged), then the guard blend was eased (lift 0-2 cm)
const SRC := "scenes/walk_bat.json"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## two cards, no weapon: the arms raised one way then the other, a long hold
func target() -> Scene:
	var R := body()
	R.wep_on = false
	R.set_ang("upperarm_r", Vector3(0, 0, 40))
	R.set_ang("thigh_l", Vector3(20, 0, 0))
	R.fk()
	var S := Scene.new()
	S.add("a", R.to_dict())
	R.set_ang("upperarm_l", Vector3(0, 0, -30))
	R.set_ang("spine_02", Vector3(10, 0, 0))
	R.fk()
	S.add("b", R.to_dict())
	S.cards[1]["move"] = 0.8
	S.cards[1]["hold"] = 12.0
	return S


func src_scene() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + SRC)))
	return S


func worst_deg(a: Body, b: Body, joints: Array) -> float:
	var w := 0.0
	for j in joints:
		var d: Vector3 = Scene._d(b.ang[j], a.ang[j], j)
		w = maxf(w, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return w


func same(a: Body, b: Body, joints: Array) -> bool:
	for j in joints:
		if a.ang[j] != b.ang[j]:
			return false
	return true


func _init() -> void:
	var B := body()
	var R := body()   # the reference: the source (or the cards alone) played by hand
	var src := src_scene()
	var L := src.length()
	var e := Clips.source(SRC)
	ok(not e.is_empty() and absf(float(e["len"]) - L) < 1e-9, "0 the source loads by reference: %s, L = %.3f s" % [SRC, L])
	var all := Body.ORDER
	var legs := Clips.mask_joints("legs")
	var rest := all.filter(func(j): return not j in legs)

	# 1
	var S := target()
	var s0 := 0.7
	S.clips = [Clips.make(SRC, s0)]
	var w1 := 0.0
	var o1 := 0.0
	for t in [0.7, 1.0, 1.9, 2.55, 3.3, s0 + L]:
		S.apply(B, t)
		src.apply(R, t - s0)
		w1 = maxf(w1, worst_deg(B, R, all))
		o1 = maxf(o1, (B.offset - R.offset).length())
	ok(w1 < 0.01 and o1 < 1e-4, "1 a clip at s = %.1f plays the source at t - s: worst joint %.6f deg (< 0.01), hips %.6f mm" % [s0, w1, o1 * 1000.0])

	# 2
	var c2 := Clips.make(SRC, 0.5, {"repeat": 3, "speed": 2.0})
	ok(Clips.length_of(c2, L) == L * 3.0 / 2.0, "2 repeat 3 speed 2: the strip lasts L x 3 / 2 = %.4f s exactly" % (L * 1.5))
	var bad2 := []
	for f in [0.0, 0.1, 0.33, 0.334, 0.5, 0.66, 0.67, 1.0 - 1e-6]:   # fractions of the strip (each third is one cycle)
		var t: float = 0.5 + f * L * 1.5
		var a := Clips.at(c2, L, t)
		var u: float = (t - 0.5) * 2.0
		var k := mini(int(floor(u / L)), 2)
		if int(a["k"]) != k or absf(float(a["lt"]) - (u - k * L)) > 1e-9:
			bad2.append([f, a])
	var aend := Clips.at(c2, L, 0.5 + L * 1.5)
	ok(bad2.is_empty() and int(aend["k"]) == 2 and absf(float(aend["lt"]) - L) < 1e-9 and Clips.at(c2, L, 0.5 + L * 1.5 + 1e-4).is_empty(),
		"2 cycle and source time = the formula at 8 times %s; the end reads cycle 2 at lt = L; past it nothing" % ("" if bad2.is_empty() else str(bad2)))
	S.clips = [c2]
	var t2 := 0.5 + (L + 0.6) / 2.0   # cycle 1, the source at 0.6 s
	S.apply(B, t2)
	src.apply(R, 0.6)
	var step: Vector3 = Clips.root_step(e, false)
	ok(worst_deg(B, R, all) < 0.01 and (B.offset - (R.offset + step)).length() < 1e-4,
		"2 speed 2 in cycle 1 at t = %.3f plays the source at 0.6 s: %.6f deg, hips %.4f mm off source + one step" % [t2, worst_deg(B, R, all), (B.offset - (R.offset + step)).length() * 1000.0])
	var tpast := 0.5 + L * 1.5 + 1.0 / 30.0
	S.apply(B, tpast)
	var S0 := target()
	S0.apply(R, tpast)
	ok(same(B, R, all) and B.offset == R.offset, "2 one frame past the end (extrapolation nothing): the cards' pose bit for bit")

	# 3
	S.clips = [Clips.make(SRC, 0.7, {"bin": 0.4})]
	var t3 := 0.8
	var a3 := Clips.at(S.clips[0], L, t3)
	S.apply(B, t3)
	S0.apply(R, t3)
	var below := {}
	for j in all:
		below[j] = R.ang[j]
	var ob := R.offset
	src.apply(R, t3 - 0.7)
	var w3 := 0.0
	for j in all:
		var want: Vector3 = (below[j] as Vector3) + Scene._d(below[j], R.ang[j], j) * 0.25
		want = R.clamp_ang(j, want)
		var d: Vector3 = Scene._d(want, B.ang[j], j)
		w3 = maxf(w3, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	var o3 := (B.offset - ob.lerp(R.offset, 0.25)).length()
	ok(absf(float(a3["w"]) - 0.25) < 1e-9 and w3 < 0.01 and o3 < 1e-4,
		"3 blend in 0.4 s, 0.1 s in: weight %.6f (= 0.1 / 0.4), every joint = below + 0.25 (clip - below) within %.6f deg, hips %.4f mm" % [a3["w"], w3, o3 * 1000.0])
	var ramp := [0.7, 0.75, 0.9, 1.1, 1.3].map(func(t): return snappedf(float(Clips.at(S.clips[0], L, t)["w"]), 0.0001))
	ok(ramp == [0.0, 0.125, 0.5, 1.0, 1.0], "3 the ramp at 0, 0.05, 0.2, 0.4, 0.6 s in: %s (linear, Blender's)" % [ramp])

	# 4
	S.clips = [Clips.make(SRC, 0.0, {"mask": "legs"})]
	var bad4 := 0
	var wl := 0.0
	for t in [0.3, 1.1, 2.0, 2.9]:
		S.apply(B, t)
		S0.apply(R, t)
		if not same(B, R, rest):
			bad4 += 1
		src.apply(R, t)
		wl = maxf(wl, worst_deg(B, R, legs))
	ok(bad4 == 0, "4 legs mask: the %d other joints (arms, spine, head, fingers) bit for bit as the cards play them at 4 times" % rest.size())
	ok(wl < 0.01, "4 legs mask: the %d leg joints are the walk's within %.6f deg" % [legs.size(), wl])

	# 5
	S.clips = [Clips.make(SRC, 0.0, {"repeat": 3})]
	var x := 0.37 * L
	var P := []
	for k in 3:
		S.apply(B, k * L + x)
		P.append(B.P["pelvis"])
	var d01: Vector3 = P[1] - P[0]
	var d12: Vector3 = P[2] - P[1]
	ok(step.length() > 0.5 and (d01 - step).length() < 0.001 and (d12 - step).length() < 0.001,
		"5 a walk repeated 3 times: the pelvis advances by the cycle's step (%.3f m) each repeat: %.4f / %.4f mm off" % [step.length(), (d01 - step).length() * 1000.0, (d12 - step).length() * 1000.0])

	# 6
	S.clips = [Clips.make(SRC, 0.25, {"repeat": 2, "speed": 1.25, "bin": 0.2, "bout": 0.3, "type": "add", "mask": "arm_l", "extra": "hold", "w": 0.7})]
	var d := S.to_dict(B, false)
	var txt := JSON.stringify(d)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(txt))
	var fr_ok := true
	for t in [0.1, 0.9, 2.2, 6.0]:
		S.apply(B, t)
		S2.apply(R, t)
		fr_ok = fr_ok and same(B, R, all) and B.offset == R.offset
	ok(var_to_str(S2.clips) == var_to_str(S.clips) and fr_ok and JSON.stringify(S2.to_dict(B, false)) == txt,
		"6 file round trip: the same clips, the same frames at 4 times, the file written again byte-identical")
	var keys_ok: bool = (d["clips"][0] as Dictionary).keys().all(func(k): return k in ["src", "start", "repeat", "speed", "bin", "bout", "type", "mask", "extra", "w", "mirror", "mute"])
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/scene.schema.json"))
	var sp: Dictionary = schema.get("$defs", {}).get("scene", {}).get("properties", {}).get("clips", {}).get("items", {}).get("properties", {})
	ok(keys_ok and sp.keys().size() == 13 and Scene.MIRROR_SCENE.has("clips"), "6 every clip key is in the schema (%d) and on Mirror's list" % sp.size())
	var mf := Clips.mirror_file(d["clips"])
	ok(mf[0]["mirror"] == true and mf[0]["mask"] == "arm_r" and Clips.mirror_file(mf) == d["clips"], "6 mirror: the source plays mirrored, arm_l -> arm_r, twice = the original")
	S.clips = [Clips.make(SRC, 0.0, {"mirror": true})]
	S.apply(B, 1.3)
	src.apply(R, 1.3)
	R.mirror_pose()
	ok(worst_deg(B, R, all) < 0.01, "6 a mirrored clip plays the source's pose mirrored: %.6f deg" % worst_deg(B, R, all))

	# 7
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	var n := 0
	for p in ["res://scenes/combo3.json", "res://scenes/walk_bat.json"]:
		var Sx := Scene.new()
		Sx.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
		var f := 0
		while f / 30.0 <= Sx.length():
			Sx.apply(B, f / 30.0)
			h.update(var_to_str(B.state()).to_utf8_buffer())
			f += 1
			n += 1
	var got := h.finish().hex_encode()
	ok(got == BASE_HASH, "7 scenes with no clip: %d frames hash %s, the base commit's %s" % [n, got, BASE_HASH])
	var quiet := true
	for cm in [Clips.make(SRC, 0.0, {"mute": true}), Clips.make(SRC, 0.0, {"w": 0.0})]:
		S.clips = [cm]
		for t in [0.4, 1.7]:
			S.apply(B, t)
			S0.apply(R, t)
			quiet = quiet and same(B, R, all) and B.offset == R.offset
	ok(quiet, "7 a muted clip and a weight-0 clip leave the body bit for bit")

	# 9 clips are played from worker threads too (dummy / fighters measure, pose bake): four threads posing the same
	# walk through the shared scratch bodies give each the serial answer (undo_audit crashed on this race)
	var ser := []
	var times_t := [0.3, 0.9, 1.5, 2.1]
	var Sc := target()
	Sc.clips = [Clips.make(SRC, 0.0, {"mask": "legs"})]
	for t in times_t:
		Sc.apply(B, t)
		ser.append(str(B.ang))
	var outs := [[], [], [], []]
	var tasks := []
	for w in 4:
		var sc := Sc.clone()
		var o: Array = outs[w]
		tasks.append(WorkerThreadPool.add_task(func():
			var WB := body()
			for rep in 12:
				for t in times_t:
					sc.apply(WB, t)
					if rep == 11:
						o.append(str(WB.ang))))
	for tk in tasks:
		WorkerThreadPool.wait_for_task_completion(tk)
	var race_ok := true
	for w in 4:
		race_ok = race_ok and (outs[w] as Array) == ser
	ok(race_ok, "9 four threads playing a clip at once each get the serial answer (bar: 4 of 4 equal)")

	await app_part()
	print("CLIPS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


# 8
func app_part() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.S = target()
	m.scene_path = ""
	m._rebuild_cards()
	m._card_pick(0)
	m.playhead = 0.4
	m.undo.clear()
	var ids: Array = m._commands().map(func(c): return c["id"])
	ok(["clip_place_a_scene_here...", "clip_place_a_move_here...", "clip_edit_the_picked_clip...", "clip_remove_the_picked_clip"].all(func(i): return i in ids),
		"8 the four commands are in the registry")
	var u0: int = m.undo.size()
	var k: int = m.clips_ui.place(SRC, m.playhead, {"repeat": 2, "mask": "legs", "bin": 0.3})
	var k2: int = m.clips_ui.place("moves/bo_guard.json", 2.0, {"mask": "arms", "bin": 0.2, "bout": 0.2})
	ok(k == 0 and k2 == 1 and m.S.clips.size() == 2 and m.undo.size() == u0 + 2, "8 placing a scene and a move: one undo step each (%d)" % (m.undo.size() - u0))
	m._undo()
	ok(m.S.clips.size() == 1, "8 Ctrl+Z takes the move clip back")
	m._redo()
	ok(m.S.clips.size() == 2, "8 Ctrl+Y puts it back")
	for i in 3:
		await process_frame
	var tl: Timeline = m.ui_timeline
	var r: Rect2 = tl.clip_rect(0)
	ok(tl.clip_px() > 0.0 and r.size.x > 20.0 and tl.clip_at(r.get_center()) == 0, "8 the strips are drawn as bars under the cards (%.0f px rows, bar %.0f px wide)" % [tl.clip_px(), r.size.x])
	var s_before := float(m.S.clips[0]["start"])
	var u1: int = m.undo.size()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = r.get_center()
	tl._gui_input(press)
	for dx in [10.0, 30.0, 60.0]:
		var mv := InputEventMouseMotion.new()
		mv.position = r.get_center() + Vector2(dx, 0)
		tl._gui_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = r.get_center() + Vector2(60, 0)
	tl._gui_input(rel)
	var want := snappedf(s_before + 60.0 / tl.pps(), Timeline.SNAP)
	ok(absf(float(m.S.clips[0]["start"]) - want) < 1e-6 and m.undo.size() == u1 + 1, "8 dragging the bar 60 px moves it %.2f -> %.2f s: ONE undo step (%d)" % [s_before, m.S.clips[0]["start"], m.undo.size() - u1])
	m._undo()
	ok(float(m.S.clips[0]["start"]) == s_before, "8 Ctrl+Z puts the strip back at %.2f s" % s_before)
	m.clips_ui.sel = 1
	m.clips_ui.remove()
	ok(m.S.clips.size() == 1, "8 remove the picked clip")
	m._undo()
	ok(m.S.clips.size() == 2, "8 Ctrl+Z brings it back")
	m.clips_ui.sel = 0
	m.playhead = 2.3
	m._press(KEY_2)   # his right side: the walking legs under the raised arms
	m.S.apply(m.B, m.playhead)
	m._refresh()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.save_png(a.substr(7))
			print("     shot: %s" % a.substr(7))
	m.queue_free()
	await process_frame
