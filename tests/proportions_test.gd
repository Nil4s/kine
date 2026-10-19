## godot --headless --path . -s tests/proportions_test.gd     (round 51, GATES PR: character proportions)
## Sources: docs/research/PROPORTIONS.md (ANSUR II 2012, Drillis & Contini 1966 via Winter, de Leva 1996, Croskey 1922).
## Bars, written before measuring (scenes/ is read only; files go to user://zz_proportions/ and are deleted):
##   1 BONES + STATURE: for 5th woman, 50th man, 95th man every bone |p0[j] - p0[parent]| = the default's x s(parent)
##     and every capsule radius = default x s(j), within 0.1 mm; the mannequin's bones (posed through
##     Overlays.pose_skeleton, a bent pose) on Body.P within 0.1 mm; the stature measured on the MESH (CPU skinning of
##     every vertex at rest: top - bottom) within 5 mm of the requested. At the 50th man: upper arm, forearm, hand,
##     thigh, shank, foot as fractions of stature = Drillis & Contini within the table's 3 decimals (0.0005); trunk and
##     head printed (this mannequin's ankle is 0.057 H high vs the table's 0.039: the trunk takes the difference).
##   2 REACH: a target at 98 % of the scaled arm (shoulder -> wrist) is reached, miss < 3 mm; at 105 % the miss is
##     > 3 mm; 5th woman and 95th man, left and right.
##   3 COM: standing, arms at the sides, Balance.com height / stature within 1 % (relative) of Croskey 1922 (men 0.5618,
##     women 0.5544) at the 50th man and 50th woman.
##   4 EXPORTS: a scene with a 5th-woman body: the BVH OFFSETs and the read-back glb's bone rest positions equal the
##     scaled skeleton within 0.1 mm; the USD restTransforms the same.
##   5 NO "body" KEY: combo3 as loaded writes no "body"; going to a preset and back to {} leaves state() at 5 playheads,
##     the BVH and USD text and the glb bytes identical to before.
##   6 RETARGET: combo3 to the 5th woman and the 95th man: every card keeps every angle exactly and its lowest sole
##     within 5 mm of the height it had; a pinned hand (IK) stays on its world target within 1 mm where reachable;
##     through main: "Body: 95th percentile man" is one undo step and Ctrl+Z gives back the cards, the scene's body and
##     the body's skeleton exactly.
extends SceneTree

var fails := 0
const DIR := "user://zz_proportions"
const SKEL := "res://data/skeleton.json"
const LIMS := "res://data/body_limits.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fresh(body := {}) -> Body:
	var b := Body.new()
	b.load_files(SKEL, LIMS)
	b.set_proportions(body)
	return b


func combo() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	return S


## the mannequin's highest and lowest vertex as skinned now (every surface of every piece)
func mesh_extent(man: Node3D, sk: Skeleton3D) -> Vector2:
	var lo := INF
	var hi := -INF
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin == null:
			continue
		var bb := []
		for k in m.skin.get_bind_count():
			var b := m.skin.get_bind_bone(k)
			bb.append(b if b >= 0 else sk.find_bone(m.skin.get_bind_name(k)))
		var xs := []
		for k in bb.size():
			xs.append(sk.get_bone_global_pose(bb[k]) * m.skin.get_bind_pose(k))
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bo.size() / vs.size()
			for v in vs.size():
				var p := Vector3.ZERO
				for q in per:
					if w[v * per + q] > 0.0:
						p += (xs[bo[v * per + q]] as Transform3D) * vs[v] * w[v * per + q]
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
		break   # the first mesh is the whole body (the pieces are copies of it)
	return Vector2(lo, hi)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var D := fresh()
	var presets := {"female_5": Proportions.preset("female_5"), "male_50": Proportions.preset("male_50"), "male_95": Proportions.preset("male_95")}

	# ---- (1) bones, capsules, mannequin, stature, fractions
	for pn in presets:
		var B := fresh(presets[pn])
		var worst_b := 0.0
		var worst_r := 0.0
		for j in Body.ORDER:
			var pj: String = B.parent[j]
			if pj != "":
				var want: float = ((D.p0[j] as Vector3) - (D.p0[pj] as Vector3)).length() * float(B.seg_s[pj])
				worst_b = maxf(worst_b, absf(((B.p0[j] as Vector3) - (B.p0[pj] as Vector3)).length() - want))
			worst_r = maxf(worst_r, absf(float(B.rad[j]) - float(D.rad[j]) * float(B.seg_s[j])))
			var cl: float = ((D.cap0[j][1] as Vector3) - (D.cap0[j][0] as Vector3)).length() * float(B.seg_s[j])
			worst_r = maxf(worst_r, absf(((B.cap0[j][1] as Vector3) - (B.cap0[j][0] as Vector3)).length() - cl))
		ok(worst_b < 1e-4, "1 %s: every bone = default x its segment's scale, worst %.4f mm" % [pn, worst_b * 1000.0])
		ok(worst_r < 1e-4, "1 %s: every capsule (radius, length) = default x scale, worst %.4f mm" % [pn, worst_r * 1000.0])
		var mq := Overlays.mannequin(root, StandardMaterial3D.new())
		var sk: Skeleton3D = mq[1]
		var idx: Dictionary = mq[2]
		Overlays.pose_skeleton(sk, idx, B)
		await process_frame   # the skeleton's global poses settle on a frame (read straight after, a few came back stale)
		var ext := mesh_extent(mq[0], sk)
		var st: float = presets[pn]["stature"]
		ok(absf(ext.y - ext.x - st) < 0.005, "1 %s: stature on the skinned mesh %.4f m (top %.4f, sole %.4f) vs %.4f asked: %.1f mm" % [pn, ext.y - ext.x, ext.y, ext.x, st, (ext.y - ext.x - st) * 1000.0])
		B.ang["upperarm_r"] = Vector3(40, -60, 20)
		B.ang["lowerarm_r"] = Vector3(70, 0, 0)
		B.ang["thigh_l"] = Vector3(50, 10, 0)
		B.ang["spine_02"] = Vector3(15, 5, 10)
		B.fk()
		Overlays.pose_skeleton(sk, idx, B)
		await process_frame
		var worst_m := 0.0
		var wj := ""
		for j in Body.ORDER:
			if idx[j] >= 0:
				var dm := (sk.get_bone_global_pose(idx[j]).origin - (B.P[j] as Vector3)).length()
				if dm > worst_m:
					worst_m = dm
					wj = j
		ok(worst_m < 1e-4, "1 %s: mannequin bones on Body.P in a bent pose, worst %.4f mm (%s)" % [pn, worst_m * 1000.0, wj])
		(mq[0] as Node).free()
		if pn == "male_50":
			var L := Proportions.lengths(B)
			var row := []
			for s in ["upper_arm", "forearm", "hand", "thigh", "shank", "foot"]:
				var f: float = float(L[s]) / float(L["stature"])
				row.append("%s %.4f (table %.3f)" % [s, f, Proportions.DRILLIS[s]])
				ok(absf(f - float(Proportions.DRILLIS[s])) <= 0.0005, "1 male_50: %s / stature %.4f vs Drillis & Contini %.3f" % [s, f, Proportions.DRILLIS[s]])
			print("     trunk (shoulder - hip) %.4f (table 0.288), head + neck %.4f (table 0.182), shoulder height %.4f (table 0.818), hip %.4f (table 0.530)" % [
				float(L["trunk"]) / float(L["stature"]), float(L["head"]) / float(L["stature"]), 1.0 - float(L["head"]) / float(L["stature"]),
				(B.p0["thigh_l"] as Vector3).y / float(L["stature"])])

	# ---- (2) reach at 98 % / 105 % of the scaled arm
	for pn in ["female_5", "male_95"]:
		for sd in ["_l", "_r"]:
			var B := fresh(presets[pn])
			var arm: float = ((B.p0["lowerarm" + sd] - B.p0["upperarm" + sd]) as Vector3).length() + ((B.p0["hand" + sd] - B.p0["lowerarm" + sd]) as Vector3).length()
			var out := 1.0 if sd == "_l" else -1.0
			var dir := Vector3(out * cos(deg_to_rad(30.0)), 0.0, sin(deg_to_rad(30.0)))
			var sh: Vector3 = B.P["upperarm" + sd]
			var m98 := B.reach("hand" + sd, sh + dir * arm * 0.98)
			var B2 := fresh(presets[pn])
			var m105 := B2.reach("hand" + sd, sh + dir * arm * 1.05)
			ok(m98 < 0.003, "2 %s%s: arm %.4f m, target at 98 %% reached, miss %.3f mm" % [pn, sd, arm, m98 * 1000.0])
			ok(m105 > 0.003, "2 %s%s: target at 105 %% not reached, miss %.1f mm (5 %% of the arm %.1f mm)" % [pn, sd, m105 * 1000.0, arm * 50.0])

	# ---- (3) COM height in standing, arms at the sides
	var croskey := {"male_50": 0.5618, "female_50": 0.5544}
	for pn in croskey:
		var B := fresh(Proportions.preset(pn))
		B.ang["upperarm_l"] = Vector3(0, -90, 0)
		B.ang["upperarm_r"] = Vector3(0, -90, 0)
		B.fk()
		var c := Balance.com(B)
		var st: float = B.body["stature"]
		var f: float = (c.y - Proportions.heel(B, "_l").y) / st
		ok(absf(f / float(croskey[pn]) - 1.0) <= 0.01, "3 %s: COM height %.4f m / stature %.3f = %.4f vs Croskey 1922 %.4f (%.2f %%)" % [pn, c.y, st, f, croskey[pn], (f / float(croskey[pn]) - 1.0) * 100.0])

	# ---- (4) exports carry the scaled skeleton
	var S4 := combo()
	S4.body = presets["female_5"]
	var B4 := fresh()
	var bv: String = BvhExport.text(S4, B4)[0]
	var BF := fresh(presets["female_5"])
	var offs := []
	for line in bv.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("OFFSET"):
			var p := t.split(" ", false)
			offs.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
		if t.begins_with("MOTION"):
			break
	# the BVH's joints in its own order: read the hierarchy's names in step with the OFFSETs
	var names := []
	for line in bv.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("ROOT ") or t.begins_with("JOINT "):
			names.append(t.split(" ", false)[1])
		elif t.begins_with("End Site"):
			names.append("")
		if t.begins_with("MOTION"):
			break
	var worst_bvh := 0.0
	var nb := 0
	for i in mini(names.size(), offs.size()):
		var j: String = names[i]
		if j == "" or not BF.parent.has(j) or BF.parent[j] == "":
			continue
		var want: Vector3 = (BF.p0[j] as Vector3) - (BF.p0[BF.parent[j]] as Vector3)
		var o: Vector3 = offs[i]
		var scale := 100.0 if o.length() > want.length() * 10.0 else 1.0   # cm or m, as the file says
		worst_bvh = maxf(worst_bvh, (o / scale - want).length())
		nb += 1
	ok(nb >= 40 and worst_bvh < 1e-4, "4 BVH: %d OFFSETs vs the scaled skeleton, worst %.4f mm" % [nb, worst_bvh * 1000.0])
	var gp := DIR + "/zz_pr.glb"
	var err := GltfExport.write(S4, fresh(), gp)
	var doc := GLTFDocument.new()
	var gs := GLTFState.new()
	var worst_glb := INF
	if err == OK and doc.append_from_file(ProjectSettings.globalize_path(gp), gs) == OK:
		var back: Node3D = doc.generate_scene(gs)
		root.add_child(back)
		var sk: Skeleton3D = back.find_children("*", "Skeleton3D", true, false)[0]
		worst_glb = 0.0
		var n := 0
		for j in Body.ORDER:
			var bi := sk.find_bone(j)
			if bi < 0:
				bi = sk.find_bone("Head" if j == "head" else j)
			if bi >= 0:
				worst_glb = maxf(worst_glb, (sk.get_bone_global_rest(bi).origin - (BF.p0[j] as Vector3)).length())
				n += 1
		ok(n >= 50, "4 glb: %d bones read back" % n)
		var ext := mesh_extent(back, sk)
		ok(absf(ext.y - ext.x - float(presets["female_5"]["stature"])) < 0.005, "4 glb: the baked mesh read back at rest is %.4f m tall (asked %.3f)" % [ext.y - ext.x, presets["female_5"]["stature"]])
		back.free()
	ok(worst_glb < 1e-4, "4 glb: bone rest positions read back vs the scaled skeleton, worst %.4f mm" % (worst_glb * 1000.0))
	var usd: String = UsdExport.text(S4, fresh())[0]
	var rest_line := ""
	for line in usd.split("\n"):
		if line.contains("restTransforms"):
			rest_line = line
	var worst_usd := 0.0
	var k := 0
	var rows := rest_line.split("(1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (", false)
	for r in range(1, rows.size()):
		var nums := rows[r].split(",", false)
		var v := Vector3(float(nums[0]), float(nums[1]), float(nums[2]))
		var j: String = Body.ORDER[r - 1]
		var want: Vector3 = BF.p0[j] if BF.parent[j] == "" else (BF.p0[j] as Vector3) - (BF.p0[BF.parent[j]] as Vector3)
		worst_usd = maxf(worst_usd, (v - want).length())
		k += 1
	ok(k == Body.ORDER.size() and worst_usd < 1e-4, "4 USD: %d restTransforms vs the scaled skeleton, worst %.4f mm" % [k, worst_usd * 1000.0])

	# ---- (5) no body key: nothing changes
	var S5 := combo()
	var B5 := fresh()
	ok(not S5.to_dict(B5).has("body") and S5.body.is_empty() and B5.seg_s.is_empty(), "5 combo3 as loaded: no \"body\" key written, default skeleton")
	var L5 := S5.length()
	var ts := [0.0, 0.37, L5 * 0.5, L5 * 0.81, L5]
	var before := []
	for t in ts:
		S5.apply(B5, t)
		before.append(var_to_str(B5.state()))
	var bvh0: String = BvhExport.text(S5, B5)[0]
	var usd0: String = UsdExport.text(S5, B5)[0]
	GltfExport.write(S5, B5, DIR + "/zz_same.glb")   # one path: the file's name is the animation's name inside it
	var g0 := FileAccess.get_file_as_bytes(DIR + "/zz_same.glb")
	S5.body = presets["male_95"]
	S5.apply(B5, 1.0)
	ok(not B5.seg_s.is_empty(), "5 (control) the body really changed to the preset")
	S5.body = {}
	var same := true
	for i in ts.size():
		S5.apply(B5, ts[i])
		same = same and var_to_str(B5.state()) == before[i]
	ok(same, "5 state() at 5 playheads identical after a preset and back")
	ok(BvhExport.text(S5, B5)[0] == bvh0, "5 BVH text identical (%d chars)" % bvh0.length())
	ok(UsdExport.text(S5, B5)[0] == usd0, "5 USD text identical (%d chars)" % usd0.length())
	GltfExport.write(S5, B5, DIR + "/zz_same.glb")
	ok(FileAccess.get_file_as_bytes(DIR + "/zz_same.glb") == g0, "5 glb bytes identical (%d bytes)" % g0.size())

	# ---- (6) retarget
	for pn in ["female_5", "male_95"]:
		var S6 := combo()
		var B0 := fresh()
		var lo0 := []
		var ang0 := []
		for c in S6.cards:
			var f := Moves._flat(c["pose"])
			Scene.put(B0, f)
			lo0.append(B0.sole_low() + 0.0)
			ang0.append(var_to_str(f["ang"]))
		Proportions.retarget(S6, fresh(), presets[pn])
		var BN := fresh(presets[pn])
		var worst_f := 0.0
		var same_a := true
		for i in S6.cards.size():
			var f := Moves._flat(S6.cards[i]["pose"])
			same_a = same_a and var_to_str(f["ang"]) == ang0[i]
			Scene.put(BN, f)
			worst_f = maxf(worst_f, absf(BN.sole_low() - float(lo0[i])))
		ok(same_a, "6 %s: every card keeps every joint angle exactly (%d cards)" % [pn, S6.cards.size()])
		ok(worst_f < 0.005, "6 %s: the lowest sole at every card where it was, worst %.3f mm" % [pn, worst_f * 1000.0])
		ok(S6.body == Proportions.clean(presets[pn]), "6 %s: the scene carries the body" % pn)
	# IK: pin the right hand on the default body, retarget, the hand stays on its world target where reachable
	var S7 := combo()
	var B7 := fresh()
	var tp := S7.length() * 0.5
	S7.apply(B7, tp)
	LimbIK.pin(S7, B7, "hand_r", tp)
	S7.apply(B7, tp)
	var target: Vector3 = B7.P["hand_r"]
	for pn in ["female_5", "male_95"]:
		var Sx := S7.clone()
		Proportions.retarget(Sx, fresh(), presets[pn])
		var Bx := fresh()
		Sx.apply(Bx, tp)
		var arm: float = ((Bx.p0["lowerarm_r"] - Bx.p0["upperarm_r"]) as Vector3).length() + ((Bx.p0["hand_r"] - Bx.p0["lowerarm_r"]) as Vector3).length()
		var dist: float = (target - (Bx.P["upperarm_r"] as Vector3)).length()
		var miss: float = ((Bx.P["hand_r"] as Vector3) - target).length()
		if dist < arm * 0.98:
			ok(miss < 0.001, "6 IK %s: the pinned hand on its world target, miss %.3f mm (target %.0f %% of the arm)" % [pn, miss * 1000.0, dist / arm * 100.0])
		else:
			print("     6 IK %s: target %.0f %% of the arm, out of reach: miss %.1f mm (not barred)" % [pn, dist / arm * 100.0, miss * 1000.0])
	# through main: one undo step
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.0
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	var cards0 := JSON.stringify(m.S.cards)
	var st0 := var_to_str(m.B.state())
	var p00 := var_to_str(m.B.p0)
	var cmd := {}
	for c in m._commands():
		if c["name"] == "Body: 95th percentile man":
			cmd = c
	cmd["run"].call()
	await process_frame
	ok(m.undo.size() == 1 and m.S.body.get("preset", "") == "male_95" and not m.B.seg_s.is_empty(), "6 main: 'Body: 95th percentile man' = %d undo step, scene and body changed" % m.undo.size())
	ok(JSON.stringify(m.S.cards) != cards0, "6 main: the cards were retargeted")
	var top: float = Proportions.head_top(m.B).y
	m._undo()
	await process_frame
	ok(JSON.stringify(m.S.cards) == cards0 and m.S.body.is_empty() and var_to_str(m.B.state()) == st0 and var_to_str(m.B.p0) == p00,
		"6 main: Ctrl+Z gives back the cards, the scene's body and the skeleton exactly")
	m._redo()
	await process_frame
	ok(m.S.body.get("preset", "") == "male_95" and absf(Proportions.head_top(m.B).y - top) < 1e-9, "6 main: Ctrl+Y puts the 95th man back")
	m.free()

	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	print("proportions: %d FAIL" % fails if fails > 0 else "proportions: all ok")
	quit(fails)
