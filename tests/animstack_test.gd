## godot --headless --path . -s tests/animstack_test.gd     (L79: ROADMAP_400 L02 animation layers with bone masks, L01 NLA strips polish)
## Builds on Scene.layers (add / over, weight, mute) and Scene.clips (strips: bin / bout, speed, repeat, mute); adds a per-layer
## bone MASK ("mask" name or "bones" list), a per-strip blend CURVE ("curve"), and the agent tool `anim_stack` (scripts/anim_stack.gd).
## Base scene: two cards, no weapon (so no grip re-solve touches the arms), played at 24 times.
##   1 ADD +10 deg on spine_01 adds exactly (10,0,0) over the base at every time (<= 1e-4); nothing else moves (0.0)
##   2 OVERRIDE masked to arm_r: every bone outside the right arm equals the base (0.0), the arm_r joint reaches the layer angle;
##     control: the same layer with mask all DOES move other bones (> 1 deg); bones list ["spine_02"] drives only that bone
##   3 layer weight 0.5 on a zero joint = halfway quaternion slerp (1e-4 deg)
##   4 MUTE a layer / a strip restores the base byte for byte (var_to_str equal, 24 times); control: unmuted differs
##   5 STRIP scale 2 doubles the duration (1e-9); outside the strip nothing plays; repeat 3 of a cyclic source: the pose at both
##     loop boundaries is equal within 1e-4 (control: a non-cyclic source jumps > 1 deg there)
##   6 BLEND-IN over 15 frames is monotone for every curve (linear / smooth / ease_in / ease_out), 0 at the start, 1 at bin;
##     bout is monotone down; linear is the old formula bit for bit; smooth(0.5)=0.5, ease_in(0.5) < 0.5 < ease_out(0.5);
##     an unknown curve falls back to linear
##   7 EACH EDIT IS ONE UNDO STEP: layer_add, layer_set, clip_add, clip_set, layer_mute, clip_remove each push exactly 1, and
##     undoing them in turn brings the lists back exactly
##   8 SAVE / RELOAD keeps layers (mask, bones) and strips (curve) and plays bit for bit the same
##   9 OLD SCENES: a scene with no layers / strips writes none of the new keys; walk_bat.json plays pose diff 0.0 against itself
##     reloaded; a layer with no "mask" and a clip with no "curve" play exactly as mask all / curve linear (0.0) and write no key
##   10 the tool is listed (agent_tools MCP_EXTRA, poser_mcp.py, poser_cli.gd) and bad input is refused with a reason
extends SceneTree

var fails := 0
const SRC_CYC := "scenes/zz_animstack_cyc.json"
const SRC_OPEN := "scenes/walk_bat.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func base_scene() -> Scene:
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
	S.cards[1]["hold"] = 1.0
	return S


## a cyclic source (a, b, a) and a file for it
func write_cyc() -> void:
	var R := body()
	R.wep_on = false
	R.set_ang("upperarm_r", Vector3(0, 0, 40))
	R.fk()
	var S := Scene.new()
	S.add("a", R.to_dict())
	R.set_ang("upperarm_r", Vector3(0, 0, -20))
	R.set_ang("spine_02", Vector3(12, 0, 0))
	R.fk()
	S.add("b", R.to_dict())
	R.set_ang("upperarm_r", Vector3(0, 0, 40))
	R.set_ang("spine_02", Vector3(0, 0, 0))
	R.fk()
	S.add("a2", R.to_dict())
	S.cards[1]["move"] = 0.5
	S.cards[2]["move"] = 0.5
	S.cards[2]["hold"] = 0.0
	var f := FileAccess.open("res://" + SRC_CYC, FileAccess.WRITE)
	f.store_string(JSON.stringify(S.to_dict(R)))
	f.close()


func times(S: Scene, n: int) -> Array:
	var out := []
	for i in n:
		out.append(S.length() * i / float(n - 1))
	return out


func pose(S: Scene, t: float) -> Dictionary:
	var B := body()
	S.apply(B, t)
	return {"ang": B.ang.duplicate(), "off": B.offset}


func worst_other(a: Dictionary, b: Dictionary, skip: Array) -> float:
	var w := 0.0
	for j in a["ang"]:
		if j in skip:
			continue
		w = maxf(w, ((a["ang"][j] as Vector3) - (b["ang"][j] as Vector3)).length())
	return w


func worst_all(a: Dictionary, b: Dictionary) -> float:
	return maxf(worst_other(a, b, []), ((a["off"] as Vector3) - (b["off"] as Vector3)).length())


func _init() -> void:
	write_cyc()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	var S := base_scene()
	S.name = "zz_animstack"
	m.S = S
	m._rebuild_cards()
	var L := S.length()
	var T := times(S, 24)
	var base := []
	for t in T:
		base.append(pose(S, t))
	var base_mid := pose(base_scene(), L * 0.5)

	# 1 additive
	var r1: Dictionary = AnimStack.serve(m, {"op": "layer_add", "name": "lean", "mode": "add", "v": {"spine_01": [10, 0, 0]}})
	var w1 := 0.0
	var oth1 := 0.0
	for k in T.size():
		var p := pose(S, T[k])
		w1 = maxf(w1, ((p["ang"]["spine_01"] as Vector3) - (base[k]["ang"]["spine_01"] as Vector3) - Vector3(10, 0, 0)).length())
		oth1 = maxf(oth1, worst_other(p, base[k], ["spine_01"]))
	ok(r1.get("ok", false) and w1 < 1e-4 and oth1 == 0.0, "1 add +10 deg spine_01: worst error to base+10 = %.7f deg (bar 1e-4), other bones off by %.7f (bar 0.0)" % [w1, oth1])

	# 2 override masked
	var v2 := {"upperarm_r": [30, 0, 10], "upperarm_l": [50, 0, 0], "spine_02": [25, 0, 0], "thigh_l": [5, 0, 0]}
	AnimStack.serve(m, {"op": "layer_set", "index": 0, "mode": "over", "v": v2, "mask": "arm_r"})
	var oth2 := 0.0
	var reach := 0.0
	for k in T.size():
		var p := pose(S, T[k])
		oth2 = maxf(oth2, worst_other(p, base[k], ["upperarm_r", "lowerarm_r", "hand_r", "clavicle_r"]))
		reach = maxf(reach, ((p["ang"]["upperarm_r"] as Vector3) - (S.layers[0]["v"]["upperarm_r"] as Vector3)).length())
	ok(oth2 == 0.0 and reach < 1e-3, "2 override masked arm_r: bones outside the right arm off by %.7f (bar 0.0), upperarm_r reaches the layer to %.5f deg" % [oth2, reach])
	AnimStack.serve(m, {"op": "layer_set", "index": 0, "mask": "all"})
	var ctl := worst_other(pose(S, L * 0.5), base_mid, ["upperarm_r"])
	ok(ctl > 1.0, "2c control: mask all moves other bones too (%.2f deg > 1, the planted check can fail)" % ctl)
	AnimStack.serve(m, {"op": "layer_set", "index": 0, "mask": "all", "bones": ["spine_02"]})
	var pb := pose(S, L * 0.5)
	var d2 := ((pb["ang"]["spine_02"] as Vector3) - (base_mid["ang"]["spine_02"] as Vector3)).length()
	ok(worst_other(pb, base_mid, ["spine_02"]) == 0.0 and d2 > 1.0, "2d bones [spine_02] drives only that bone (others off by %.7f, it moved %.2f deg)" % [worst_other(pb, base_mid, ["spine_02"]), d2])

	# 3 weight 0.5 = slerp
	AnimStack.serve(m, {"op": "layer_set", "index": 0, "mode": "over", "v": {"spine_01": [20, 0, 0]}, "mask": "all", "bones": [], "w": 0.5})
	var got := (pose(S, L * 0.3)["ang"]["spine_01"] as Vector3)
	var q := Quaternion().slerp(Quaternion(Vector3.RIGHT, deg_to_rad(20.0)), 0.5)
	var want := rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))
	ok(absf(got.x - want) < 1e-4 and absf(got.y) < 1e-4 and absf(got.z) < 1e-4, "3 weight 0.5 override: spine_01 = %.6f deg, slerp halfway = %.6f (bar 1e-4)" % [got.x, want])

	# 4 mute
	AnimStack.serve(m, {"op": "layer_set", "index": 0, "w": 1.0, "mute": true})
	AnimStack.serve(m, {"op": "clip_add", "src": SRC_CYC, "start": 0.0, "type": "add", "mute": true})
	var same := true
	for k in T.size():
		same = same and var_to_str(pose(S, T[k])) == var_to_str(base[k])
	AnimStack.serve(m, {"op": "layer_mute", "index": 0, "mute": false})
	AnimStack.serve(m, {"op": "clip_mute", "index": 0, "mute": false})
	var diff4 := worst_all(pose(S, L * 0.5), base_mid)
	ok(same and diff4 > 0.5, "4 muted layer + muted strip: base byte for byte at 24 times %s; control unmuted differs by %.2f deg" % [same, diff4])
	AnimStack.serve(m, {"op": "clip_remove", "index": 0})
	AnimStack.serve(m, {"op": "layer_remove", "index": 0})
	ok(S.layers.is_empty() and S.clips.is_empty(), "4b layers and strips removed")

	# 5 strip scale / repeat
	var e := Clips.source(SRC_CYC)
	var Ls := float(e["len"])
	var c1 := Clips.make(SRC_CYC, 0.5, {})
	var c2 := Clips.make(SRC_CYC, 0.5, {"speed": 0.5})
	AnimStack.serve(m, {"op": "clip_add", "src": SRC_CYC, "start": 0.5, "scale": 2.0, "repeat": 3, "extra": "nothing"})
	var cs: Dictionary = S.clips[0]
	var d1 := Clips.length_of(c1, Ls)
	var dsc := Clips.length_of(c2, Ls)
	ok(absf(dsc - 2.0 * d1) < 1e-9 and absf(Clips.length_of(cs, Ls) - 3.0 * 2.0 * Ls) < 1e-9 and absf(float(cs["speed"]) - 0.5) < 1e-9, "5 scale 2 doubles the duration: %.4f s vs %.4f s; tool scale 2 x repeat 3 = %.4f s (L %.3f)" % [dsc, d1, Clips.length_of(cs, Ls), Ls])
	var Dd := Clips.length_of(cs, Ls)
	var out_ok := Clips.at(cs, Ls, 0.5 + Dd + 0.01).is_empty() and Clips.at(cs, Ls, 0.4).is_empty() and not Clips.at(cs, Ls, 0.5 + Dd * 0.5).is_empty()
	var seam := 0.0
	var seam_m := 0.0
	for k in [1, 2]:
		var tb: float = 0.5 + Dd * k / 3.0
		var pa := pose(S, tb - 1e-7)
		var pz := pose(S, tb + 1e-7)
		seam = maxf(seam, worst_other(pa, pz, []))
		seam_m = maxf(seam_m, ((pa["off"] as Vector3) - (pz["off"] as Vector3)).length())
	var S2 := base_scene()
	S2.clips = [Clips.make(SRC_OPEN, 0.0, {"repeat": 3})]
	var eo := Clips.source(SRC_OPEN)
	var tb2 := float(eo["len"])
	var jump := worst_other(pose(S2, tb2 - 1e-5), pose(S2, tb2 + 1e-5), [])
	ok(out_ok and seam < 1e-4 and seam_m < 1e-4 and jump > 1.0, "5b repeat 3: outside the strip nothing %s; loop boundaries differ by %.7f deg and %.7f m of hips (bars 1e-4 each); control non-cyclic source jumps %.2f deg" % [out_ok, seam, seam_m, jump])

	# 6 blend curves
	var mono := true
	var ends := true
	var n := 15
	for cv in ["linear", "smooth", "ease_in", "ease_out"]:
		var c := Clips.make(SRC_CYC, 1.0, {"bin": 0.5, "bout": 0.5, "curve": cv})
		var prev := -1.0
		for f in n + 1:
			var wv := float(Clips.at(c, Ls, 1.0 + 0.5 * f / float(n))["w"])
			mono = mono and wv >= prev - 1e-12
			prev = wv
		var w0 := float(Clips.at(c, Ls, 1.0)["w"])
		var w1b := float(Clips.at(c, Ls, 1.5)["w"])
		ends = ends and absf(w0) < 1e-9 and absf(w1b - 1.0) < 1e-9
		var prevo := 2.0
		var E := 1.0 + Clips.length_of(c, Ls)
		for f in n + 1:
			var wo := float(Clips.at(c, Ls, E - 0.5 + 0.5 * f / float(n))["w"])
			mono = mono and wo <= prevo + 1e-12
			prevo = wo
	var lin := Clips.make(SRC_CYC, 1.0, {"bin": 0.4})
	var lin_old := true
	for f in 9:
		var t := 1.0 + 0.05 * f
		lin_old = lin_old and float(Clips.at(lin, Ls, t)["w"]) == clampf((t - 1.0) / 0.4, 0.0, 1.0)
	var mid := func(cv: String) -> float: return float(Clips.at(Clips.make(SRC_CYC, 0.0, {"bin": 1.0, "curve": cv}), Ls, 0.5)["w"])
	var shape: bool = absf(mid.call("smooth") - 0.5) < 1e-9 and mid.call("ease_in") < 0.45 and mid.call("ease_out") > 0.55
	var bogus: bool = Clips.make(SRC_CYC, 0.0, {"curve": "wobble"}).get("curve", "linear") == "linear"
	ok(mono and ends and lin_old and shape and bogus, "6 blend-in/out over %d frames monotone for 4 curves %s, ends 0 and 1 %s, linear = old formula %s, shapes %s, unknown curve -> linear %s" % [n, mono, ends, lin_old, shape, bogus])

	# 7 undo: one step each
	S.clips = []
	S.layers = []
	m.undo.clear()
	var snaps := []
	var steps := [
		{"op": "layer_add", "name": "a", "mode": "add", "v": {"spine_01": [5, 0, 0]}},
		{"op": "layer_set", "index": 0, "w": 0.5, "mask": "upper"},
		{"op": "clip_add", "src": SRC_CYC, "start": 0.2, "curve": "smooth", "bin": 0.3},
		{"op": "clip_set", "index": 0, "scale": 1.5, "repeat": 2},
		{"op": "layer_mute", "index": 0, "mute": true},
		{"op": "clip_remove", "index": 0}]
	var one := true
	for st in steps:
		snaps.append(var_to_str([S.layers, S.clips]))
		var u0: int = m.undo.size()
		var r: Dictionary = AnimStack.serve(m, st)
		one = one and r.get("ok", false) and m.undo.size() - u0 == 1
	var back := true
	for k in range(steps.size() - 1, -1, -1):
		m._undo()
		back = back and var_to_str([S.layers, S.clips]) == snaps[k]
	ok(one and back, "7 six edits each exactly 1 undo step %s; six undos restore the lists exactly %s" % [one, back])

	# 8 save / reload
	AnimStack.serve(m, {"op": "layer_add", "name": "arm", "mode": "over", "w": 0.7, "v": {"upperarm_r": [20, 0, 0], "spine_01": [4, 0, 0]}, "mask": "arm_r"})
	AnimStack.serve(m, {"op": "layer_add", "name": "chosen", "mode": "add", "v": {"spine_01": [3, 0, 0], "spine_02": [2, 0, 0]}, "bones": ["spine_02"]})
	AnimStack.serve(m, {"op": "clip_add", "src": SRC_CYC, "start": 0.3, "curve": "ease_out", "bin": 0.4, "bout": 0.2, "scale": 2.0, "repeat": 2, "mute": false})
	var B0 := body()
	var d := S.to_dict(B0)
	var S3 := Scene.new()
	S3.from_dict(JSON.parse_string(JSON.stringify(d)))
	var rt := true
	for t in T:
		rt = rt and var_to_str(pose(S, t)) == var_to_str(pose(S3, t))
	var keep: bool = S3.layers.size() == 2 and S3.layers[0]["mask"] == "arm_r" and (S3.layers[1]["bones"] as Array) == ["spine_02"] and S3.clips.size() == 1 and S3.clips[0]["curve"] == "ease_out"
	ok(rt and keep, "8 save -> reload keeps layers (mask, bones) and the strip (curve) %s and plays bit for bit the same %s" % [keep, rt])

	# 9 old scenes unchanged
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + SRC_OPEN)))
	var W2 := Scene.new()
	W2.from_dict(JSON.parse_string(JSON.stringify(W.to_dict(B0))))
	var o9 := 0.0
	for t in times(W, 12):
		o9 = maxf(o9, worst_all(pose(W, t), pose(W2, t)))
	var dd := W.to_dict(B0)
	var nokeys: bool = not dd.has("layers") and not dd.has("clips")
	var P := base_scene()
	P.layers = [{"name": "x", "mode": "over", "w": 0.6, "wk": [], "mute": false, "solo": false, "lock": false, "v": {"spine_01": Vector3(9, 0, 0)}}]
	P.clips = [Clips.make(SRC_CYC, 0.2, {"bin": 0.3})]
	var Q := base_scene()
	Q.layers = [Scene.layer_from_file(Scene.layer_to_file(P.layers[0]))]
	Q.layers[0]["mask"] = "all"
	Q.clips = [Clips.make(SRC_CYC, 0.2, {"bin": 0.3, "curve": "linear"})]
	var o9b := 0.0
	for t in times(P, 12):
		o9b = maxf(o9b, worst_all(pose(P, t), pose(Q, t)))
	var lf := Scene.layer_to_file(P.layers[0])
	var nolk: bool = not lf.has("mask") and not lf.has("bones") and not (Clips.to_file(P.clips)[0] as Dictionary).has("curve")
	ok(o9 == 0.0 and nokeys and o9b == 0.0 and nolk, "9 old scenes: walk_bat reload pose diff %.7f (bar 0.0), no new keys written %s; default mask/curve play as explicit all/linear diff %.7f (bar 0.0), keys omitted %s" % [o9, nokeys, o9b, nolk])

	# 10 listed + refusals
	var src_at := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var src_mcp := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var src_cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	var listed := src_at.contains("\"anim_stack\"") and src_mcp.contains("anim_stack") and src_cli.contains("anim_stack")
	var bad1: Dictionary = AnimStack.serve(m, {"op": "layer_set", "index": 99})
	var bad2: Dictionary = AnimStack.serve(m, {"op": "nonsense"})
	var bad3: Dictionary = AnimStack.serve(m, {"op": "clip_add", "src": "scenes/no_such_file.json"})
	var bad4: Dictionary = AnimStack.serve(m, {"op": "layer_add", "mask": "tail"})
	var ls: Dictionary = AnimStack.serve(m, {"op": "list"})
	var refused: bool = not bad1.get("ok", true) and not bad2.get("ok", true) and not bad3.get("ok", true) and not bad4.get("ok", true) and String(bad4.get("error", "")).length() > 10
	ok(listed and refused and ls.get("ok", false) and (ls["result"]["layers"] as Array).size() == S.layers.size(), "10 tool listed in agent_tools / MCP / CLI %s; bad index, op, source and mask refused with a reason %s; list returns the %d layers" % [listed, refused, S.layers.size()])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + SRC_CYC))
	print("ANIMSTACK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
