## godot --path . -s tests/charimp_test.gd     (GAP_AUDIT_1106 top 10 #2, lane L9; needs a window for the picture)
## RIGGED CHARACTER IMPORT (scripts/char_import.gd). Bars, written and committed BEFORE the first run; none is edited after.
## Every bar has a planted control that must FAIL (printed "control").
##   R1 ROUND TRIP  a Kine character exported to .glb (GltfExport: mannequin mesh + skin), imported by CharImport, mapped, and
##      posed with pose X: every skinned vertex within 1e-4 m of the original mannequin posed by Overlays.pose_skeleton
##      with the same pose (both skinned by CharImport.skin_points, plain LBS), and every vertex's weights EQUAL by bone name
##      (within 1e-4). Control: two thighs swapped in the map moves vertices by > 1e-4; two bones swapped in the weights table differ.
##   R2 AUTO-MAP   100 % of the hand truth table on each supported naming convention (Mixamo, UE4 / UE5 Mannequin, Rigify DEF-,
##      VRM 0.x J_Bip_, VRM 1.0 humanoid, Kine's own), no false joint (a twist, IK or end bone mapped). Control: a bone
##      renamed to a wrong-side name in the table is caught by the same comparison (the check can fail).
##   R2g GEOMETRY  the Kine skeleton with every bone renamed "xq_N" (no name matches) and its order shuffled: the map is >= 90 % of
##      the 22 main joints correct (the bar) or reports them unmapped; also Z-up. Control: the same renamed skeleton with the
##      legs removed is NOT mapped to a full body (it reports the joints missing: main < 22).
##   R3 POSE TRANSFER  Kine pose X on the import: each mapped joint's world rotation, read back from the imported skeleton and put
##      into Kine's frame, equals Kine's G within 0.5 deg; each mapped limb bone's direction within 0.5 deg of Kine's; on the
##      Kine export, on a long-legged character (Proportions baked into its file), and on an A-pose, 1.2 x Mixamo-named skeleton
##      (tests/fixtures/mixamo_rig.fbx). Control: the same read back with the left and right arm swapped in the map is > 0.5 deg off.
##   R4 BLEND SHAPES  a character with two shapes (puff, smile) written to .glb and imported: the names and every per-surface vertex
##      delta equal (1e-5). Control: one delta changed by 1 mm is caught.
##   R5 PROPORTIONS  the long-legged character's body dict gives a Kine body whose thigh, shank, upper arm and forearm lengths are
##      within 3 mm of the file's, and whose pelvis height at rest is within 1 cm; the default body is > 2 cm off on the thigh
##      (control). The Kine limits stay (clamp_ang the same on both bodies).
##   R6 SCENE KEY  to_key / from_key give the same map back (by bone name); a bone gone from the file is dropped, the rest stands.
##   R7 PICTURE  the imported long-legged character posed beside the Kine body in pose X, saved to user://zz_charimp/beside.png;
##      both figures present (pixels of each colour > 3000), the imported one taller than the Kine one. LOOK at it.
extends SceneTree

var fails := 0
const DIR := "user://zz_charimp"
const FIX := "res://tests/fixtures/mixamo_rig.fbx"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func ctl(c: bool, what: String) -> void:   # a planted control: it must FAIL its bar, so the bar here is "the check noticed"
	print(("ok   control: " if c else "FAIL control: ") + what)
	if not c:
		fails += 1


func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


## pose X: an asymmetric pose with every big joint moving
func _pose_x(b: Body) -> void:
	var a := {"upperarm_l": Vector3(55, 25, 15), "lowerarm_l": Vector3(70, 0, 0), "upperarm_r": Vector3(-35, -20, 10),
		"lowerarm_r": Vector3(50, 0, 0), "thigh_l": Vector3(45, 8, 0), "calf_l": Vector3(60, 0, 0), "thigh_r": Vector3(-20, -5, 6),
		"calf_r": Vector3(25, 0, 0), "spine_01": Vector3(10, 4, 5), "spine_02": Vector3(14, -6, 8), "head": Vector3(8, 15, 0),
		"hand_l": Vector3(10, 5, 0), "foot_l": Vector3(8, 0, 0)}
	for j in Body.ORDER:
		b.ang[j] = Vector3.ZERO
	for j in a:
		b.ang[j] = b.clamp_ang(j, a[j])
	b.offset = Vector3(0.05, -0.04, 0.02)
	b.fk()


func _ang_deg(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg((a * b.inverse()).normalized().get_angle()) if absf(a.dot(b)) < 0.999999 else 0.0


func _export(S: Scene, B: Body, path: String) -> String:
	var ap := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(ap.get_base_dir())
	var err := GltfExport.write(S, B, path)
	return ap if err == OK else ""


## ---- R3 helper: the world joint rotations read back from the imported skeleton, in Kine's frame
func _readback(ch: Dictionary, mapping: Dictionary, ft: Dictionary, B: Body, swap := false) -> Array:
	var wr := CharImport.world_rots(ch)
	var C: Quaternion = ft["C"]
	var worst_g := 0.0
	var worst_d := 0.0
	var mp: Dictionary = mapping["map"]
	var rest: Array = ch["src"]["rest"]
	var kids := CharImport._kids_of(ch["src"]["parent"])
	for j in mp:
		var jj: String = j
		if swap and j.contains("arm"):
			jj = j.substr(0, j.length() - 2) + ("_r" if j.ends_with("_l") else "_l")
		var b: int = mp[j]
		var D: Quaternion = C * ((wr[b] as Quaternion) * (ft["rq"][b] as Quaternion).inverse()) * C.inverse()
		var G: Quaternion = (D * (ft["roff"][jj] as Quaternion)).normalized()
		worst_g = maxf(worst_g, _ang_deg(G, B.G[jj]))
	# limb directions: bone -> its mapped child, source side (posed positions from the skeleton) vs Kine's E - P
	var sk: Skeleton3D = ch["sk"]
	var bq: Transform3D = ch["src"]["base"]
	for j in ["upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r", "thigh_l", "calf_l", "thigh_r", "calf_r", "spine_01", "spine_02"]:
		var ch2 := String(Body.CHILD.get(j, ""))
		if ch2 == "" or not mp.has(j) or not mp.has(ch2):
			continue
		var a: Vector3 = bq * (sk.get_bone_global_pose(mp[j]).origin)
		var c: Vector3 = bq * (sk.get_bone_global_pose(mp[ch2]).origin)
		var jj2: String = j
		if swap and j.contains("arm"):
			jj2 = j.substr(0, j.length() - 2) + ("_r" if j.ends_with("_l") else "_l")
		var dk: Vector3 = (B.E[jj2] as Vector3) - (B.P[jj2] as Vector3)
		var ds: Vector3 = C * (c - a)
		worst_d = maxf(worst_d, rad_to_deg(dk.angle_to(ds)))
	return [worst_g, worst_d]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := _body()
	var S := Scene.new()
	S.add("rest", {})
	# ================================================================= R1 round trip
	var gp := _export(S, B, DIR + "/kine.glb")
	ok(gp != "", "R1 the Kine character is exported to .glb")
	var ch := CharImport.load_character(gp)
	ok(ch["ok"], "R1 imported: %s (%s)" % [ch["text"] if ch["ok"] else ch["why"], gp.get_file()])
	if not ch["ok"]:
		print("charimp: %d fail" % fails)
		quit(1)
		return
	var src: Dictionary = ch["src"]
	var mapping := CharImport.map_bones(src)
	ok(int(mapping["main"]) == 22, "R1 all 22 main joints mapped (%s)" % CharImport.report(src, mapping))
	var ft := CharImport.fit(src, mapping, B)
	ok(ft["ok"], "R1 fit")
	_pose_x(B)
	CharImport.pose(ch, mapping, ft, B)
	var orig: Node3D = (load(Overlays.body_file()) as PackedScene).instantiate()
	var osk: Skeleton3D = orig.find_children("*", "Skeleton3D", true, false)[0]
	var idx := {}
	for j in Body.ORDER:
		idx[j] = osk.find_bone("Head" if j == "head" else j)
	Overlays.pose_skeleton(osk, idx, B)
	var obase := AnimImport._scene_xf(osk, orig)
	var ibase: Transform3D = src["base"]
	var omesh: MeshInstance3D = null
	for mi in orig.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			omesh = mi
	var imesh: MeshInstance3D = ch["meshes"][0]
	var P0 := CharImport.skin_points(osk, omesh)
	var P1 := CharImport.skin_points(ch["sk"], imesh)
	var worst := 0.0
	var nvert := 0
	ok(P0.size() == P1.size(), "R1 same surface count (%d / %d)" % [P0.size(), P1.size()])
	for si in mini(P0.size(), P1.size()):
		ok((P0[si] as PackedVector3Array).size() == (P1[si] as PackedVector3Array).size(), "R1 surface %d: same vertex count (%d)" % [si, (P0[si] as PackedVector3Array).size()])
		for i in mini((P0[si] as PackedVector3Array).size(), (P1[si] as PackedVector3Array).size()):
			worst = maxf(worst, (obase * (P0[si] as PackedVector3Array)[i]).distance_to(ibase * (P1[si] as PackedVector3Array)[i]))
			nvert += 1
	ok(worst <= 1e-4 and nvert > 1000, "R1 %d posed vertices: worst distance %.2e m (bar 1e-4)" % [nvert, worst])
	# the weights
	var W0 := CharImport.weights_of(osk, omesh)
	var W1 := CharImport.weights_of(ch["sk"], imesh)
	var wworst := 0.0
	for si in mini(W0.size(), W1.size()):
		for i in mini((W0[si] as Array).size(), (W1[si] as Array).size()):
			var a: Dictionary = W0[si][i]
			var b: Dictionary = W1[si][i]
			for k in a:
				wworst = maxf(wworst, absf(float(a[k]) - float(b.get(k, 0.0))))
			for k in b:
				if not a.has(k):
					wworst = maxf(wworst, float(b[k]))
	ok(wworst <= 1e-4, "R1 weights equal by bone name: worst %.2e (bar 1e-4)" % wworst)
	# controls
	var swapped := mapping.duplicate(true)
	var t1: int = swapped["map"]["thigh_l"]
	swapped["map"]["thigh_l"] = swapped["map"]["thigh_r"]
	swapped["map"]["thigh_r"] = t1
	CharImport.pose(ch, swapped, ft, B)
	var Ps := CharImport.skin_points(ch["sk"], imesh)
	var sw := 0.0
	for si in mini(P0.size(), Ps.size()):
		for i in (P0[si] as PackedVector3Array).size():
			sw = maxf(sw, (obase * (P0[si] as PackedVector3Array)[i]).distance_to(ibase * (Ps[si] as PackedVector3Array)[i]))
	ctl(sw > 1e-4, "R1 one bone swapped in the map moves vertices by %.3f m" % sw)
	var wsw := 0.0
	for si in mini(W0.size(), W1.size()):
		for i in (W0[si] as Array).size():
			var a2: Dictionary = (W0[si][i] as Dictionary).duplicate()
			if a2.has("thigh_l") or a2.has("thigh_r"):   # the table with thigh_l / thigh_r swapped
				var t: Variant = a2.get("thigh_l", 0.0)
				a2["thigh_l"] = a2.get("thigh_r", 0.0)
				a2["thigh_r"] = t
			for k in a2:
				wsw = maxf(wsw, absf(float(a2[k]) - float((W1[si][i] as Dictionary).get(k, 0.0))))
	ctl(wsw > 1e-4, "R1 two bones swapped in the weights table differ by %.3f" % wsw)
	CharImport.pose(ch, mapping, ft, B)

	# ================================================================= R2 auto-map truth tables
	_r2_names(B)
	_r2_geometry(B, src)

	# ================================================================= R3 pose transfer
	var rb := _readback(ch, mapping, ft, B)
	ok(rb[0] <= 0.5 and rb[1] <= 0.5, "R3 Kine export: world joint rotations %.3f deg, limb directions %.3f deg (bar 0.5)" % [rb[0], rb[1]])
	var rsw := _readback(ch, mapping, ft, B, true)
	ctl(rsw[0] > 0.5 or rsw[1] > 0.5, "R3 arms swapped in the read-back: %.1f deg / %.1f deg" % [rsw[0], rsw[1]])
	# a long-legged character: the proportions are baked into the file by GltfExport (PR2)
	var body_long := {"stature": 1.9, "scale": {"thigh": 1.25, "shank": 1.2, "upper_arm": 0.85, "forearm": 0.9}}
	var SL := Scene.new()
	SL.body = Proportions.clean(body_long)
	SL.add("rest", {})
	var BL := _body()
	BL.set_proportions(SL.body)
	var lp := _export(SL, BL, DIR + "/long.glb")
	var chl := CharImport.load_character(lp)
	ok(chl["ok"], "R3 long-legged character imported (%s)" % (chl["text"] if chl["ok"] else chl["why"]))
	var srcl: Dictionary = chl["src"]
	var mapl := CharImport.map_bones(srcl)
	var Bd := _body()   # the default body drives the import: the proportions differ, the rest bone directions do not
	var ftl := CharImport.fit(srcl, mapl, Bd)
	ok(mapl["main"] == 22 and ftl["ok"], "R3 long-legged: 22 joints, leg ratio %.3f" % ftl["ratio"])
	_pose_x(Bd)
	CharImport.pose(chl, mapl, ftl, Bd)
	var rbl := _readback(chl, mapl, ftl, Bd)
	ok(rbl[0] <= 0.5 and rbl[1] <= 0.5, "R3 long-legged: rotations %.3f deg, directions %.3f deg (bar 0.5)" % [rbl[0], rbl[1]])
	# A-pose, 1.2 x, Mixamo names: the fixture has no mesh, so the skeleton alone (the pose code needs only the skeleton)
	_r3_fixture()

	# ================================================================= R4 blend shapes
	_r4_shapes(B, S)

	# ================================================================= R5 proportions
	var bd := CharImport.body_dict(srcl, mapl, Bd)
	var Bc := _body()
	Bc.set_proportions(bd)
	var rest_c := _rest_lengths(Bc)
	var rest_f := _file_lengths(srcl, mapl)
	var rest_d := _rest_lengths(_body())
	var wl := 0.0
	for k in ["thigh", "shank", "upper_arm", "forearm"]:
		wl = maxf(wl, absf(float(rest_c[k]) - float(rest_f[k])))
	ok(wl <= 0.003, "R5 fitted body segments within 3 mm of the file's: worst %.4f m (thigh %.3f vs %.3f)" % [wl, rest_c["thigh"], rest_f["thigh"]])
	var Bz := _body()
	Bz.set_proportions(bd)
	Bz.fk()
	var pel_file: float = ((srcl["rest"] as Array)[mapl["map"]["pelvis"]] as Transform3D).origin.y
	ok(absf((Bz.P["pelvis"] as Vector3).y - pel_file) <= 0.01, "R5 pelvis at rest %.3f m vs the file's %.3f m (bar 1 cm)" % [(Bz.P["pelvis"] as Vector3).y, pel_file])
	ctl(absf(float(rest_d["thigh"]) - float(rest_f["thigh"])) > 0.02, "R5 the default body's thigh is %.3f m off the file's" % absf(float(rest_d["thigh"]) - float(rest_f["thigh"])))
	var lim_same := true
	for j in ["upperarm_l", "calf_r", "head", "thigh_l"]:
		var v := Vector3(200, 100, 100)
		lim_same = lim_same and Bc.clamp_ang(j, v).is_equal_approx(_body().clamp_ang(j, v))
	ok(lim_same, "R5 Kine's joint limits are the same on the fitted body")

	# ================================================================= R6 scene key
	var key := CharImport.to_key(ch, mapping)
	var back := CharImport.from_key(src, JSON.parse_string(JSON.stringify(key)))
	var same := back["map"].size() == mapping["map"].size()
	for j in mapping["map"]:
		same = same and back["map"].get(j, -1) == mapping["map"][j]
	ok(same, "R6 the map kept by bone name comes back whole (%d pairs)" % back["map"].size())
	var key2: Dictionary = JSON.parse_string(JSON.stringify(key))
	key2["pairs"]["hand_l"] = "no_such_bone_in_the_file"
	var back2 := CharImport.from_key(src, key2)
	ok(not back2["map"].has("hand_l") and back2["map"].size() == mapping["map"].size() - 1, "R6 a bone gone from the file is dropped, the rest stands")

	# ================================================================= R7 the picture
	await _r7_picture(chl, mapl, ftl, bd)
	print("charimp: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _rest_lengths(b: Body) -> Dictionary:
	b.fk()
	var keep := b.state()
	for j in Body.ORDER:
		b.ang[j] = Vector3.ZERO
	b.offset = Vector3.ZERO
	b.fk()
	var out := {"thigh": ((b.P["calf_l"] - b.P["thigh_l"]) as Vector3).length(), "shank": ((b.P["foot_l"] - b.P["calf_l"]) as Vector3).length(),
		"upper_arm": ((b.P["lowerarm_l"] - b.P["upperarm_l"]) as Vector3).length(), "forearm": ((b.P["hand_l"] - b.P["lowerarm_l"]) as Vector3).length()}
	b.set_state(keep)
	return out


func _file_lengths(s: Dictionary, m: Dictionary) -> Dictionary:
	var mp: Dictionary = m["map"]
	var r: Array = s["rest"]
	var d := func(a: String, b: String) -> float: return ((r[mp[a]] as Transform3D).origin).distance_to((r[mp[b]] as Transform3D).origin)
	return {"thigh": d.call("thigh_l", "calf_l"), "shank": d.call("calf_l", "foot_l"), "upper_arm": d.call("upperarm_l", "lowerarm_l"), "forearm": d.call("lowerarm_l", "hand_l")}


## ---- R2: synthetic skeletons, one per naming convention, from Kine's own joints
## each convention: a Callable joint -> file name; extras: [name, parent joint, position offset] bones that must stay unmapped
func _conv_src(B: Body, nm: Callable, extras: Array, spine_chain := 0) -> Array:
	var names := []
	var parent := []
	var rest := []
	var at := {}
	var truth := {}
	var add := func(name: String, pj: String, pos: Vector3, joint: String):
		at[name] = names.size()
		names.append(name)
		parent.append(at[pj] if pj != "" and at.has(pj) else -1)
		rest.append(Transform3D(Basis(), pos))
		if joint != "":
			truth[joint] = name
	for j in Body.ORDER:
		var pj: String = B.parent[j]
		add.call(nm.call(j), nm.call(pj) if pj != "" else "", B.p0[j], j)
	for e in extras:
		var pn: String = e[1]
		add.call(e[0], pn, (rest[at[pn]] as Transform3D).origin + (e[2] as Vector3), "")
	return [{"names": names, "parent": parent, "rest": rest, "base": Transform3D.IDENTITY}, truth]


func _check_table(label: String, src: Dictionary, truth: Dictionary, planted := false) -> bool:
	var mp := CharImport.map_bones(src)
	var wrong := []
	for j in truth:
		var got: int = mp["map"].get(j, -1)
		if got < 0 or src["names"][got] != truth[j]:
			wrong.append(j)
	var false_pos := []
	for j in mp["map"]:
		if not truth.has(j):
			false_pos.append(j)
	if not planted:
		ok(wrong.is_empty() and false_pos.is_empty(), "R2 %s: %d of %d truth rows right%s%s (method %s)" % [label, truth.size() - wrong.size(), truth.size(),
			"" if wrong.is_empty() else ", wrong: " + ",".join(PackedStringArray(wrong.slice(0, 6))), "" if false_pos.is_empty() else ", false: " + ",".join(PackedStringArray(false_pos)), mp["method"]])
	return wrong.is_empty() and false_pos.is_empty()


func _r2_names(B: Body) -> void:
	var fing := func(j: String) -> Array:   # "index_02_l" -> ["index", 2, "_l"]
		var p := j.split("_")
		return [p[0], int(p[1]), "_" + p[2]]
	# Mixamo
	var mx := func(j: String) -> String:
		var base := {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2", "neck_01": "Neck", "head": "Head"}
		if base.has(j):
			return "mixamorig:" + base[j]
		var sd := "Left" if j.ends_with("_l") else "Right"
		var st := j.substr(0, j.length() - 2)
		var sm := {"clavicle": "Shoulder", "upperarm": "Arm", "lowerarm": "ForeArm", "hand": "Hand", "thigh": "UpLeg", "calf": "Leg", "foot": "Foot", "ball": "ToeBase"}
		if sm.has(st):
			return "mixamorig:" + sd + sm[st]
		var f: Array = fing.call(j)
		return "mixamorig:%sHand%s%d" % [sd, String(f[0]).capitalize(), f[1]]
	var r: Array = _conv_src(B, mx, [["mixamorig:HeadTop_End", "head", Vector3(0, 0.2, 0)], ["mixamorig:LeftEye", "head", Vector3(0.03, 0.05, 0.08)]])
	_check_table("Mixamo", r[0], r[1])
	# UE4 / UE5 Mannequin: Kine's own names, plus twist and IK bones, a root, and (UE5) two more spine bones and a second neck
	var ue := func(j: String) -> String: return j
	var r2: Array = _conv_src(B, ue, [["ik_foot_root", "pelvis", Vector3(0, -0.9, 0)], ["upperarm_twist_01_l", "upperarm_l", Vector3(0.1, 0, 0)],
		["lowerarm_twist_01_r", "lowerarm_r", Vector3(-0.1, 0, 0)], ["calf_twist_01_l", "calf_l", Vector3(0, -0.1, 0)], ["ik_hand_gun", "hand_r", Vector3(0, 0, 0.1)]])
	_check_table("UE4 Mannequin (Kine's own names + twist, IK)", r2[0], r2[1])
	# UE5: spine_01..05 and neck_01, neck_02 (the map takes the first, the middle and the last spine bone)
	var names5 := []
	var parent5 := []
	var rest5 := []
	var truth5 := {}
	var at5 := {}
	for j in Body.ORDER:
		if j == "spine_03":
			continue
		var nmj: String = j
		var pj: String = B.parent[j]
		if j == "spine_02":
			pass
		at5[j] = names5.size()
		names5.append(nmj)
		parent5.append(-1 if pj == "" else at5[pj if pj != "spine_03" else "spine_02"])
		rest5.append(Transform3D(Basis(), B.p0[j]))
	# spine_02 -> add spine_03, spine_04, spine_05 as a chain from spine_02 up to where spine_03 was
	var top: Vector3 = B.p0["spine_03"]
	var low: Vector3 = B.p0["spine_02"]
	var chain_names := ["spine_03", "spine_04", "spine_05"]
	var prev := "spine_02"
	for k in 3:
		var nme: String = chain_names[k]
		at5[nme] = names5.size()
		names5.append(nme)
		parent5.append(at5[prev])
		rest5.append(Transform3D(Basis(), low.lerp(top, float(k + 1) / 3.0)))
		prev = nme
	# the clavicles and the neck hang from spine_05: re-parent them
	for j in ["clavicle_l", "clavicle_r", "neck_01"]:
		parent5[at5[j]] = at5["spine_05"]
	for j in Body.ORDER:
		if j != "spine_03":
			truth5[j] = j
	truth5["spine_02"] = "spine_03"   # five spine bones: first, middle (third), last
	truth5["spine_03"] = "spine_05"
	_check_table("UE5 Mannequin (5 spine bones)", {"names": names5, "parent": parent5, "rest": rest5, "base": Transform3D.IDENTITY}, truth5)
	# Rigify (DEF- bones): spine, spine.001..003, neck .004 (+ .005), head .006; DEF-upper_arm.L(.001 = twist) ...
	var rg := func(j: String) -> String:
		var sp := {"pelvis": "DEF-spine", "spine_01": "DEF-spine.001", "spine_02": "DEF-spine.002", "spine_03": "DEF-spine.003", "neck_01": "DEF-spine.004", "head": "DEF-spine.006"}
		if sp.has(j):
			return sp[j]
		var sd := ".L" if j.ends_with("_l") else ".R"
		var st := j.substr(0, j.length() - 2)
		var sm := {"clavicle": "DEF-shoulder", "upperarm": "DEF-upper_arm", "lowerarm": "DEF-forearm", "hand": "DEF-hand", "thigh": "DEF-thigh", "calf": "DEF-shin", "foot": "DEF-foot", "ball": "DEF-toe"}
		if sm.has(st):
			return sm[st] + sd
		var f: Array = fing.call(j)
		return ("DEF-thumb.%02d%s" % [f[1], sd]) if f[0] == "thumb" else ("DEF-f_%s.%02d%s" % [f[0], f[1], sd])
	var r3: Array = _conv_src(B, rg, [["DEF-spine.005", "DEF-spine.004", Vector3(0, 0.05, 0)], ["DEF-upper_arm.L.001", "DEF-upper_arm.L", Vector3(0.1, 0, 0)],
		["DEF-thigh.R.001", "DEF-thigh.R", Vector3(0, -0.1, 0)], ["DEF-pelvis.L", "DEF-spine", Vector3(0.05, 0, 0)], ["DEF-breast.L", "DEF-spine.003", Vector3(0.05, 0, 0.1)]])
	_check_table("Rigify DEF-", r3[0], r3[1])
	# VRM 0.x
	var v0 := func(j: String) -> String:
		var base := {"pelvis": "J_Bip_C_Hips", "spine_01": "J_Bip_C_Spine", "spine_02": "J_Bip_C_Chest", "spine_03": "J_Bip_C_UpperChest", "neck_01": "J_Bip_C_Neck", "head": "J_Bip_C_Head"}
		if base.has(j):
			return base[j]
		var sd := "J_Bip_L_" if j.ends_with("_l") else "J_Bip_R_"
		var st := j.substr(0, j.length() - 2)
		var sm := {"clavicle": "Shoulder", "upperarm": "UpperArm", "lowerarm": "LowerArm", "hand": "Hand", "thigh": "UpperLeg", "calf": "LowerLeg", "foot": "Foot", "ball": "ToeBase"}
		if sm.has(st):
			return sd + sm[st]
		var f: Array = fing.call(j)
		return "%s%s%d" % [sd, String(f[0]).capitalize(), f[1]]
	var r4: Array = _conv_src(B, v0, [["J_Sec_Hair1_01", "J_Bip_C_Head", Vector3(0, 0.1, -0.05)], ["J_Adj_L_FaceEye", "J_Bip_C_Head", Vector3(0.03, 0.05, 0.08)]])
	_check_table("VRM 0.x J_Bip_", r4[0], r4[1])
	# VRM 1.0 humanoid names
	var v1 := func(j: String) -> String:
		var base := {"pelvis": "hips", "spine_01": "spine", "spine_02": "chest", "spine_03": "upperChest", "neck_01": "neck", "head": "head"}
		if base.has(j):
			return base[j]
		var sd := "left" if j.ends_with("_l") else "right"
		var st := j.substr(0, j.length() - 2)
		var sm := {"clavicle": "Shoulder", "upperarm": "UpperArm", "lowerarm": "LowerArm", "hand": "Hand", "thigh": "UpperLeg", "calf": "LowerLeg", "foot": "Foot", "ball": "Toes"}
		if sm.has(st):
			return sd + sm[st]
		var f: Array = fing.call(j)
		var words := ["Metacarpal", "Proximal", "Distal"] if f[0] == "thumb" else ["Proximal", "Intermediate", "Distal"]
		return sd + ("Little" if f[0] == "pinky" else String(f[0]).capitalize()) + words[f[1] - 1]
	var r5: Array = _conv_src(B, v1, [["leftEye", "head", Vector3(0.03, 0.05, 0.08)], ["jaw", "head", Vector3(0, -0.05, 0.05)]])
	_check_table("VRM 1.0 humanoid", r5[0], r5[1])
	# control: the Mixamo table with the left hand's row pointed at the right hand's bone must be caught by the same check
	var bad: Dictionary = (r[1] as Dictionary).duplicate()
	bad["hand_l"] = bad["hand_r"]
	ctl(not _check_table("planted", r[0], bad, true), "R2 a wrong-side row in the truth table is caught")


## geometry: the real Kine skeleton, every name replaced, the order shuffled; then Z-up; then legless
func _r2_geometry(B: Body, src: Dictionary) -> void:
	var truth := {}
	var mapping := CharImport.map_bones(src)
	for j in AnimImport.MAIN:
		truth[j] = String(src["names"][mapping["map"][j]])
	var rn := _scramble(src, false, [])
	var m := CharImport.map_bones(rn[0])
	var right := 0
	for j in AnimImport.MAIN:
		var got: int = m["map"].get(j, -1)
		if got >= 0 and rn[1][truth[j]] == rn[0]["names"][got]:
			right += 1
	ok(right >= 20 and m["method"] == "geometry", "R2g renamed + shuffled: %d of 22 main joints right by geometry (bar 90 pct = 20), method %s; %s" % [right, m["method"], CharImport.report(rn[0], m)])
	var rz := _scramble(src, true, [])
	var mz := CharImport.map_bones(rz[0])
	var rightz := 0
	for j in AnimImport.MAIN:
		var got2: int = mz["map"].get(j, -1)
		if got2 >= 0 and rz[1][truth[j]] == rz[0]["names"][got2]:
			rightz += 1
	ok(rightz >= 20, "R2g the same, Z-up: %d of 22 right" % rightz)
	var legs := []
	for nm in src["names"]:
		var low := String(nm).to_lower()
		if low.begins_with("thigh") or low.begins_with("calf") or low.begins_with("foot") or low.begins_with("ball"):
			legs.append(nm)
	var rl := _scramble(src, false, legs)
	var ml := CharImport.map_bones(rl[0])
	ctl(int(ml["main"]) < 22 and int((ml["missing"] as Array).size()) > 0, "R2g legless skeleton is not mapped to a full body: %d main, %s" % [ml["main"], CharImport.report(rl[0], ml)])


## [src with names "xq_N", in a shuffled parent-first order, optionally Z-up and without `drop` bones (and their children); {old name: new name}]
func _scramble(src: Dictionary, zup: bool, drop: Array) -> Array:
	var n: int = src["names"].size()
	var gone := {}
	for i in n:
		var p: int = src["parent"][i]
		if src["names"][i] in drop or (p >= 0 and gone.has(p)):
			gone[i] = true
	var order := []
	var done := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var left := []
	for i in n:
		if not gone.has(i):
			left.append(i)
	while not left.is_empty():
		var ready := left.filter(func(i): return int(src["parent"][i]) < 0 or done.has(int(src["parent"][i])))
		var pick: int = ready[rng.randi() % ready.size()]
		order.append(pick)
		done[pick] = true
		left.erase(pick)
	var newi := {}
	for k in order.size():
		newi[order[k]] = k
	var names := []
	var parent := []
	var rest := []
	var map_old := {}
	var rx := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO) if zup else Transform3D.IDENTITY
	for k in order.size():
		var i: int = order[k]
		names.append("xq_%d" % (k * 7 + 3))
		map_old[src["names"][i]] = names[-1]
		var p: int = src["parent"][i]
		parent.append(newi[p] if p >= 0 else -1)
		rest.append(rx * (src["rest"][i] as Transform3D))
	return [{"names": names, "parent": parent, "rest": rest, "base": Transform3D.IDENTITY}, map_old]


## ---- R3 on the A-pose Mixamo fixture (skeleton only)
func _r3_fixture() -> void:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(FIX), st) != OK:
		ok(false, "R3 fixture could not be read")
		return
	var rt := doc.generate_scene(st)
	var sk: Skeleton3D = rt.find_children("*", "Skeleton3D", true, false)[0]
	var fsrc := CharImport.src_of(sk, rt)
	var ch := {"sk": sk, "src": fsrc}
	var Bk := _body()
	var m := CharImport.map_bones(fsrc)
	var ft := CharImport.fit(fsrc, m, Bk)
	ok(m["main"] == 22 and ft["ok"], "R3 A-pose Mixamo fixture: 22 joints, leg ratio %.3f (1/1.2 = 0.833), arm rest difference %.1f deg" % [ft["ratio"], ft["rest_deg"].get("upperarm_l", -1.0)])
	_pose_x(Bk)
	CharImport.pose(ch, m, ft, Bk)
	var rb := _readback(ch, m, ft, Bk)
	ok(rb[0] <= 0.5 and rb[1] <= 0.5, "R3 A-pose, 1.2 x, Mixamo names: rotations %.3f deg, directions %.3f deg (bar 0.5)" % [rb[0], rb[1]])
	var rs := _readback(ch, m, ft, Bk, true)
	ctl(rs[0] > 0.5 or rs[1] > 0.5, "R3 arms swapped on the fixture: %.1f / %.1f deg" % [rs[0], rs[1]])
	rt.free()


## ---- R4
func _r4_shapes(B: Body, S: Scene) -> void:
	var man := GltfExport.build(S, B, "shapes", true)
	var mi: MeshInstance3D = null
	for m in man.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).skin != null:
			mi = m
	var om := mi.mesh as ArrayMesh
	var nm := ArrayMesh.new()
	var deltas := {"puff": [], "smile": []}
	var shapes_bs := []
	for si in om.get_surface_count():
		var arr := om.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pf := PackedVector3Array()
		var sm := PackedVector3Array()
		for i in vs.size():
			pf.append(ns[i] * 0.03)
			sm.append(Vector3(sin(vs[i].x * 9.0) * 0.004, 0.003 * vs[i].y, cos(vs[i].z * 7.0) * 0.002))
		deltas["puff"].append(pf)
		deltas["smile"].append(sm)
	nm.add_blend_shape("puff")
	nm.add_blend_shape("smile")
	nm.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for si in om.get_surface_count():
		var arr2 := om.surface_get_arrays(si)
		var bsl := []
		for key in ["puff", "smile"]:
			var ba := []
			ba.resize(Mesh.ARRAY_MAX)
			ba[Mesh.ARRAY_VERTEX] = deltas[key][si]
			ba[Mesh.ARRAY_NORMAL] = PackedVector3Array((arr2[Mesh.ARRAY_NORMAL] as PackedVector3Array).size())
			bsl.append(ba)
		nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2, bsl)
		nm.surface_set_material(si, om.surface_get_material(si))
	mi.mesh = nm
	var path := ProjectSettings.globalize_path(DIR + "/shapes.glb")
	var err := GltfExport._write(man, DIR + "/shapes.glb")
	ok(err == OK, "R4 the character with two shapes is written")
	var ch := CharImport.load_character(path)
	ok(ch["ok"], "R4 imported: %s" % (ch["text"] if ch["ok"] else ch["why"]))
	if not ch["ok"]:
		return
	var got := CharImport.shapes_of(ch["meshes"][0])
	ok(got.has("puff") and got.has("smile") and got.size() == 2, "R4 shape names kept: %s" % ",".join(PackedStringArray(got.keys())))
	var worst := 0.0
	for key in ["puff", "smile"]:
		if not got.has(key):
			continue
		for si in deltas[key].size():
			var a: PackedVector3Array = deltas[key][si]
			var b: PackedVector3Array = got[key][si]
			if a.size() != b.size():
				worst = INF
				continue
			for i in a.size():
				worst = maxf(worst, a[i].distance_to(b[i]))
	ok(worst <= 1e-5, "R4 every vertex delta equal: worst %.2e m (bar 1e-5)" % worst)
	var tw := 0.0
	var bb: PackedVector3Array = (got["smile"][0] as PackedVector3Array).duplicate()
	bb[10] += Vector3(0, 0.001, 0)
	tw = (deltas["smile"][0] as PackedVector3Array)[10].distance_to(bb[10])
	ctl(tw > 1e-5, "R4 one delta changed by 1 mm is caught (%.4f m)" % tw)
	man.free()


## ---- R7 the picture
func _r7_picture(chl: Dictionary, mapl: Dictionary, ftl: Dictionary, bd: Dictionary) -> void:
	var win := root
	var holder := Node3D.new()
	win.add_child(holder)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.86, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	holder.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	holder.add_child(sun)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(0, 1.0, 4.2)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 3)
	floor_m.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.58, 0.55)
	floor_m.material_override = fm
	holder.add_child(floor_m)
	var mat_k := StandardMaterial3D.new()
	mat_k.albedo_color = Color(0.85, 0.35, 0.2)
	var mat_i := StandardMaterial3D.new()
	mat_i.albedo_color = Color(0.2, 0.45, 0.85)
	# Kine body, default proportions, left of centre
	var Bk := _body()
	_pose_x(Bk)
	var kine := Overlays.mannequin(holder, mat_k)
	(kine[0] as Node3D).position = Vector3(-0.9, 0, 0)
	Overlays.pose_skeleton(kine[1], kine[2], Bk)
	# the import, on a Kine body with ITS proportions, right of centre
	var Bc := _body()
	Bc.set_proportions(bd)
	_pose_x(Bc)
	var ch := chl
	var rt: Node3D = ch["root"]
	holder.add_child(rt)
	rt.position = Vector3(0.9, 0, 0)
	for mi in ch["meshes"]:
		(mi as MeshInstance3D).material_override = mat_i
	var ft := CharImport.fit(ch["src"], mapl, Bc)
	CharImport.pose(ch, mapl, ft, Bc)
	await process_frame
	await process_frame
	await process_frame
	var img := win.get_viewport().get_texture().get_image()
	var p := ProjectSettings.globalize_path(DIR + "/beside.png")
	var serr := img.save_png(p)
	ok(serr == OK, "R7 picture saved: %s (%dx%d)" % [p, img.get_width(), img.get_height()])
	var red := 0
	var blue := 0
	var rmin := 99999
	var bmin := 99999
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > c.b + 0.12 and c.r > 0.35 and c.g < c.r:
				red += 1
				rmin = mini(rmin, y)
			elif c.b > c.r + 0.1 and c.b > 0.35:
				blue += 1
				bmin = mini(bmin, y)
	ok(red > 3000 and blue > 3000, "R7 both figures drawn: Kine %d px, import %d px" % [red, blue])
	ok(bmin < rmin, "R7 the long-legged import stands taller (top at y=%d vs the Kine body's y=%d)" % [bmin, rmin])
