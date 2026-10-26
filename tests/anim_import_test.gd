## godot --headless --path . -s tests/anim_import_test.gd     (GAP_ANALYSIS row 26: animation from other skeletons)
## ANIMATION IMPORT (scripts/anim_import.gd; method docs/research/RETARGET.md).
##   1 GLB ROUND TRIP: a repo scene -> GltfExport (our own .glb) -> AnimImport -> every joint's world position within 1 cm
##     of the original at 10 times (the one-card-per-frame scene the retarget makes; the thinned cards are printed).
##   2 MIXAMO FBX: tests/fixtures/mixamo_rig.fbx (made by tests/fixtures/make_mixamo_fbx.py in Blender: Mixamo bone names,
##     an A-pose rest with spread legs, 1.2 x our size, its own bone axes). Every one of the 22 main bones mapped, the
##     end bone reported unmapped, the leg ratio 1/1.2, the rest difference found (arms 40 deg, legs 4), and the hands' and
##     feet's trajectories (Blender's own evaluated positions, / 1.2) within 2 cm at every frame. When Blender is on this
##     machine the fixture is ALSO made fresh into user:// and tested the same way (CI has no Blender: the committed file).
##   3 A BVH from another skeleton (our .bvh export with Mixamo joint names) goes through the retarget: within 1 cm.
##   4 Names: Mixamo, UE5, Godot humanoid, Blender, DAZ, Biped names classified; helpers (twist, IK, ends) refused.
##   5 THE COMMAND in the app (main, headless): the fixture becomes a NEW scene in scenes/_wip (removed after), opened, the
##     status line naming the match; a file with no skeleton is refused and writes nothing.
extends SceneTree

var fails := 0
const DIR := "user://zz_anim_import"
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const FIX_REF := "res://tests/fixtures/mixamo_rig_ref.json"
const BLENDER := "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## worst joint distance (m) between S0 and S1 over the times; [worst, where]
func worst_pos(S0: Scene, S1: Scene, B: Body, times: Array, joints: Array) -> Array:
	var w := 0.0
	var at := ""
	for t in times:
		S0.apply(B, t)
		var P0 := {}
		for j in joints:
			P0[j] = B.P[j]
		S1.apply(B, t)
		for j in joints:
			var e := (P0[j] as Vector3).distance_to(B.P[j])
			if e > w:
				w = e
				at = "%s at %.2f s" % [j, t]
	return [w, at]


func fbx_case(label: String, fbx: String, ref_path: String, B: Body) -> void:
	var src := AnimImport.load_source(fbx)
	ok(src["ok"], "%s: read (%s): %d bones, \"%s\", %d frames at %d fps" % [label, src.get("why", ""), (src.get("names", []) as Array).size(), src.get("clip", ""), (src.get("frames", []) as Array).size(), src.get("fps", 0)])
	if not src["ok"]:
		return
	var m := AnimImport.map_bones(src)
	var miss: Array = AnimImport.MAIN.filter(func(j): return not m["map"].has(j))
	ok(m["main"] == 22 and miss.is_empty(), "%s: every main bone mapped: %d of 22 (missing %s; spine by %s)" % [label, m["main"], miss, m["how"].get("spine_02", "-")])
	ok((m["unmapped"] as Array).size() == 1 and String(m["unmapped"][0]).ends_with("HeadTop_End"), "%s: unmapped reported: %s" % [label, m["unmapped"]])
	var ok_names := true
	for j in m["map"]:
		var want: String = {"pelvis": "Hips", "upperarm_l": "LeftArm", "lowerarm_r": "RightForeArm", "thigh_l": "LeftUpLeg", "calf_r": "RightLeg", "ball_l": "LeftToeBase", "clavicle_r": "RightShoulder", "spine_01": "Spine", "spine_03": "Spine2"}.get(j, "")
		if want != "" and not String(src["names"][m["map"][j]]).ends_with("_" + want) and not String(src["names"][m["map"][j]]).ends_with(":" + want):
			ok_names = false
			print("     %s -> %s (wanted %s)" % [j, src["names"][m["map"][j]], want])
	ok(ok_names, "%s: Hips -> pelvis, LeftArm -> upperarm_l, RightLeg -> calf_r, Spine2 -> spine_03 ... (9 named pairs)" % label)
	var rt := AnimImport.retarget(src, m, B, "zz_mixamo")
	ok(rt["ok"], "%s: retarget: %s" % [label, rt.get("text", rt.get("why", ""))])
	if not rt["ok"]:
		return
	var rd: Dictionary = rt["rest_deg"]
	ok(absf(float(rt["ratio"]) - 1.0 / 1.2) < 1e-3, "%s: root motion scale = leg ratio %.4f (rig is 1.2 x ours: %.4f)" % [label, rt["ratio"], 1.0 / 1.2])
	ok(absf(float(rd.get("upperarm_l", 0.0)) - 40.0) < 0.5 and absf(float(rd.get("upperarm_r", 0.0)) - 40.0) < 0.5 and absf(float(rd.get("thigh_l", 0.0)) - 4.0) < 0.5 and float(rd.get("spine_02", 9.0)) < 0.5,
		"%s: rest difference found: upper arms %.1f / %.1f deg (A-pose 40), thigh %.1f (spread 4), spine %.1f" % [label, rd.get("upperarm_l", -1), rd.get("upperarm_r", -1), rd.get("thigh_l", -1), rd.get("spine_02", -1)])
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref_path))
	var sc: float = ref["S"]
	var S: Scene = rt["scene"]
	var worst := {}
	var all_w := 0.0
	var heads: Array = ref["heads"]
	for f in heads.size():
		S.apply(B, f / float(ref["fps"]))
		for j in heads[f]:
			var h: Array = heads[f][j]
			var e := (B.P[j] as Vector3).distance_to(Vector3(h[0], h[2], -h[1]) / sc)   # Blender (x, y, z) = ours (x, -z, y)
			all_w = maxf(all_w, e)
			if j in ["hand_l", "hand_r", "foot_l", "foot_r"]:
				worst[j] = maxf(worst.get(j, 0.0), e)
	var wmax: float = worst.values().max()
	ok(worst.size() == 4 and wmax < 0.02, "%s: hands and feet within 2 cm of Blender's / 1.2 over %d frames: hand_l %.2f, hand_r %.2f, foot_l %.2f, foot_r %.2f cm (every joint: %.2f cm)" % [label, heads.size(),
		worst.get("hand_l", 9) * 100, worst.get("hand_r", 9) * 100, worst.get("foot_l", 9) * 100, worst.get("foot_r", 9) * 100, all_w * 100])
	# the travel really is there (not a rig standing still that passes trivially)
	S.apply(B, 0.0)
	var p0: Vector3 = B.P["pelvis"]
	S.apply(B, S.length())
	ok((B.P["pelvis"] as Vector3).distance_to(p0) > 0.3, "%s: the hips travel %.2f m (0.40 x 1.2 / 1.2 in the file)" % [label, (B.P["pelvis"] as Vector3).distance_to(p0)])


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var t0 := Time.get_ticks_msec()

	# ---- 1 GLB round trip
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var glb := DIR + "/zz_combo3.glb"
	var err := GltfExport.write(S, B, glb)
	ok(err == OK, "1 combo3 exported to .glb (%s)" % error_string(err))
	var src := AnimImport.load_source(ProjectSettings.globalize_path(glb))
	ok(src["ok"], "1 .glb read back: %s %d bones, %d frames at %d fps" % [src.get("why", ""), (src.get("names", []) as Array).size(), (src.get("frames", []) as Array).size(), src.get("fps", 0)])
	if src["ok"]:
		var m := AnimImport.map_bones(src)
		ok(m["main"] == 22 and (m["missing"] as Array).is_empty(), "1 every Kine joint found by name: %d of 22 main, missing %s; not used: %s" % [m["main"], m["missing"], m["unmapped"]])
		var rt := AnimImport.retarget(src, m, B, "zz_rt")
		ok(rt["ok"] and absf(float(rt["ratio"]) - 1.0) < 1e-4, "1 retarget: %s" % rt.get("text", rt.get("why", "")))
		if rt["ok"]:
			var L := S.length()
			var times := []
			for k in 10:
				times.append(minf(round(L * k / 9.0 * S.fps) / S.fps, L))   # 10 times on the file's frames
			var w := worst_pos(S, rt["scene"], B, times, Body.ORDER)
			ok(w[0] < 0.01, "1 all 52 joints within 1 cm at 10 times: worst %.3f cm (%s)" % [w[0] * 100.0, w[1]])
			# the KEY REDUCTION: even spacing (VideoImport.thin, ~6 a second) + the worst-blended frames (AnimImport.refine),
			# checked at EVERY frame (the in-betweens are the cards' own blend now)
			var D: Scene = rt["scene"]
			var every := VideoImport.every_for(D.fps)
			var even := VideoImport.thin(D, every)
			var T := VideoImport.thin(D, every, AnimImport.refine(D, every))
			var all_t := []
			for k in D.cards.size():
				all_t.append(minf(k / float(S.fps), L))
			var we := worst_pos(S, even, B, all_t, AnimImport.MAIN)
			var wt := worst_pos(S, T, B, all_t, AnimImport.MAIN)
			ok(wt[0] < 0.01 and T.cards.size() < D.cards.size(), "1 key reduction: %d cards for %d frames, the 22 main joints within 1 cm at every frame: worst %.2f cm (%s); the even spacing alone (%d cards): %.1f cm" % [
				T.cards.size(), D.cards.size(), wt[0] * 100.0, wt[1], even.cards.size(), we[0] * 100.0])
			var cr := AnimImport.cards(rt["scene"], B)
			var w2 := worst_pos(S, cr[0], B, times, Body.ORDER)
			print("     the command's cards (%d; MocapClean's foot lock only on a FOOT SLIDE): worst %.2f cm at the 10 times (%s); %s" % [(cr[0] as Scene).cards.size(), w2[0] * 100.0, w2[1], cr[1]["text"]])

	# ---- 2 Mixamo FBX: the committed fixture, and a fresh one when Blender is here
	fbx_case("2 fixture", ProjectSettings.globalize_path(FIX), FIX_REF, B)
	if FileAccess.file_exists(BLENDER):
		var out := ProjectSettings.globalize_path(DIR + "/zz_fresh.fbx")
		var refo := ProjectSettings.globalize_path(DIR + "/zz_fresh_ref.json")
		var log := []
		var code := OS.execute(BLENDER, PackedStringArray(["-b", "--factory-startup", "--python", ProjectSettings.globalize_path("res://tests/fixtures/make_mixamo_fbx.py"), "--",
			ProjectSettings.globalize_path("res://data/skeleton.json"), out, refo]), log, true)
		ok(code == 0 and FileAccess.file_exists(out), "2 Blender made a fresh fixture (exit %d)" % code)
		if FileAccess.file_exists(out):
			fbx_case("2 fresh", out, refo, B)
	else:
		print("     Blender is not on this machine: the committed fixture only")

	# ---- 3 a .bvh from another skeleton (Mixamo joint names) goes through the retarget
	var tx: Array = BvhExport.text(S, B)
	var bt: String = tx[0]
	var ren := {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2", "neck_01": "Neck", "head": "Head"}
	for sd in [["_l", "Left"], ["_r", "Right"]]:
		for p in [["clavicle", "Shoulder"], ["upperarm", "Arm"], ["lowerarm", "ForeArm"], ["hand", "Hand"], ["thigh", "UpLeg"], ["calf", "Leg"], ["foot", "Foot"], ["ball", "ToeBase"]]:
			ren[p[0] + sd[0]] = sd[1] + p[1]
	var lines := bt.split("\n")
	for i in lines.size():
		for k in ["ROOT ", "JOINT "]:
			var at := lines[i].find(k)
			if at >= 0:
				var jn := lines[i].substr(at + k.length()).strip_edges()
				if ren.has(jn):
					lines[i] = lines[i].substr(0, at + k.length()) + "mixamorig:" + ren[jn]
	var bvh_path := ProjectSettings.globalize_path(DIR + "/zz_mixamo_names.bvh")
	var fa := FileAccess.open(bvh_path, FileAccess.WRITE)
	fa.store_string("\n".join(lines))
	fa.close()
	ok(not AnimImport.is_kine_bvh(bvh_path), "3 a .bvh with Mixamo names is not taken as ours")
	var bsrc := AnimImport.load_source(bvh_path)
	if bsrc["ok"]:
		var bm := AnimImport.map_bones(bsrc)
		var brt := AnimImport.retarget(bsrc, bm, B, "zz_bvh")
		if brt["ok"]:
			var times2 := []
			for k in 10:
				times2.append(minf(round(S.length() * k / 9.0 * S.fps) / S.fps, S.length()))
			var wb := worst_pos(S, brt["scene"], B, times2, AnimImport.MAIN)
			ok(bm["main"] == 22 and wb[0] < 0.01, "3 .bvh retargeted: %d of 22 main bones, the 22 main joints within 1 cm at 10 times: worst %.3f cm (%s)" % [bm["main"], wb[0] * 100.0, wb[1]])
		else:
			ok(false, "3 .bvh retarget: %s" % brt["why"])
	else:
		ok(false, "3 .bvh read: %s" % bsrc["why"])

	# ---- 4 names
	var cases := {"mixamorig:LeftForeArm": "lowerarm_l", "mixamorig_RightUpLeg": "thigh_r", "mixamorig:LeftHandIndex2": "index_02_l",
		"upperarm_l": "upperarm_l", "calf_r": "calf_r", "middle_03_r": "middle_03_l".replace("_l", "_r"), "ball_l": "ball_l",
		"LeftUpperArm": "upperarm_l", "RightLowerLeg": "calf_r", "LeftToes": "ball_l", "RightThumbMetacarpal": "thumb_01_r", "LeftIndexDistal": "index_03_l",
		"upper_arm.L": "upperarm_l", "forearm.R": "lowerarm_r", "shin.L": "calf_l", "thigh.R": "thigh_r", "DEF-hand.L": "hand_l",
		"lShldrBend": "upperarm_l", "rForearmBend": "lowerarm_r", "lShin": "calf_l", "rCollar": "clavicle_r",
		"Bip01 L Thigh": "thigh_l", "Bip01 R Calf": "calf_r", "Bip01 L Forearm": "lowerarm_l",
		"upperarm_twist_01_l": "", "ik_hand_r": "", "mixamorig:HeadTop_End": "", "mixamorig:LeftToe_End": "", "index_metacarpal_l": "", "root": "", "lShldrTwist": ""}
	var bad := []
	for n in cases:
		var c := AnimImport.classify(n)
		var got: String = "" if c.is_empty() else (String(c[1]) + String(c[0]) if c[0] != "" else String(c[1]))
		if got != cases[n]:
			bad.append("%s -> %s (want %s)" % [n, got, cases[n]])
	ok(bad.is_empty(), "4 %d bone names classified across Mixamo, UE, Godot, Blender, DAZ, Biped; helpers refused%s" % [cases.size(), "" if bad.is_empty() else ": " + ", ".join(PackedStringArray(bad))])

	# ---- 5 the command in the app
	var mm: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mm)
	await process_frame
	var copy := ProjectSettings.globalize_path(DIR + "/zz_anim_import_rig.fbx")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(FIX), copy)
	var made: String = mm._import_anim(copy)
	var says: String = mm.ui_status.text
	ok(made.begins_with("res://scenes/_wip/zz_anim_import_rig") and FileAccess.file_exists(made) and mm.S.cards.size() > 5 and mm.scene_path == made,
		"5 the command made %s, opened it with %d cards" % [made, mm.S.cards.size()])
	ok(says.contains("22 of 22 main bones"), "5 the status line names the match: %s" % says.left(200))
	if made != "" and FileAccess.file_exists(made):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(made))
	ok(not FileAccess.file_exists(made), "5 the test's scene removed")
	var before := DirAccess.get_files_at("res://scenes/_wip").size()
	var junk := ProjectSettings.globalize_path(DIR + "/zz_not_an_fbx.fbx")
	var fj := FileAccess.open(junk, FileAccess.WRITE)
	fj.store_string("hello: not a 3D file at all")
	fj.close()
	var none: String = mm._import_anim(junk)
	ok(none == "" and DirAccess.get_files_at("res://scenes/_wip").size() == before and mm.ui_status.text.contains("Try another"),
		"5 a broken file is refused, nothing written: %s" % mm.ui_status.text.left(160))
	mm.queue_free()
	await process_frame

	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("     %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("ANIM IMPORT %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(fails)
