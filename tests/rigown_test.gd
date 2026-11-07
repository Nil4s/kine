## godot --path . -s tests/rigown_test.gd     (ROADMAP_400 track J "Rigging your own", lane L69 RIGOWN; scripts/custom_rig.gd)
## A non-human skeleton (a 30-bone quadruped with a tail, built procedurally HERE) imported from glTF and kept as its OWN rig
## (not mapped onto Manny), posed per bone with FK, keyed, played back, exported again; bone add / remove / reparent on it.
## Bars, written and committed BEFORE the implementation; none is edited after. Every bar has a planted control that must FAIL.
##   1 IMPORT   the fixture (written to .glb by Godot's exporter) read by CustomRig.load_glb: bone count 30, every name, every parent
##      (by name) and every rest transform (origin and basis, max abs element) within REST_BAR = 1e-4 of what was written.
##      Control: a rest with one element moved 2e-3 is seen by the same comparison.
##   2 OWN RIG  the rig is not human (is_human false, matched core joints < 8 of Body.ORDER), no mapping onto Manny is made
##      (rig has no "map" key), and capabilities() names what is switched off in words containing "human".
##   3 FK       posing tail_3 by 40 deg about X moves tail_5's world position by >= 5 cm and equals an INDEPENDENT chain product
##      within 1e-5; the bones above tail_3 stay put (1e-6). Control: the pose of an UNRELATED bone leaves tail_5 within 1e-6.
##   4 ROUND TRIP  keys at frames 0 / 10 / 20 on 12 bones (30 fps): export_glb, load_glb again, the key frames come back and the
##      pose at frames 0, 5, 10, 15, 20 equals the original's within ANG_BAR = 1e-3 rad on every bone. Control: one re-imported key
##      turned 0.01 rad is caught by the same measure; and the pose is not all identity (max angle > 0.3 rad).
##   5 GATE     a human-only tool called on this rig returns ok=false with "not a human rig" in its message, does not run the tool
##      (counter 0) and does not error. Control: on a Manny rig (Manny's own exported .glb) the same wrapper runs the tool once.
##   6 EDIT     add_bone tail_6 under tail_5: 31 bones, right parent, exported and re-imported with 31; remove_bone tail_3: its child
##      keeps its WORLD rest transform within 1e-5 and hangs on tail_2, the key rows of tail_3 are gone; reparent paw to another
##      leg keeps the world rest within 1e-5; a loop (a bone under its own child), a duplicate name and an unknown parent are
##      refused with a message and change nothing. Control: the removed bone is still found by name afterwards = fail.
##   7 MANNY    scenes/walk_bat.json applied at t = 0.5 gives a pose (every Body.ORDER joint position); after all the custom-rig work
##      above and after loading Manny's own .glb as a rig, the same pose is identical (max diff 0.0), and Manny's .glb is human.
extends SceneTree

const REST_BAR := 1e-4
const ANG_BAR := 1e-3
var fails := 0
var DIR := "user://rigown_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the fixture: name, parent name, local rest transform (rotated, non-trivial so an identity-only import cannot pass)
func fixture() -> Array:
	var rows := []
	var add := func(n: String, p: String, o: Vector3, eul: Vector3):
		rows.append({"name": n, "parent": p, "xf": Transform3D(Basis.from_euler(eul), o)})
	add.call("root", "", Vector3(0, 0.5, 0), Vector3(0.0, 0.0, 0.0))
	add.call("hips", "root", Vector3(0, 0.05, 0), Vector3(0.1, 0.0, 0.0))
	add.call("spine_1", "hips", Vector3(0, 0.0, 0.15), Vector3(-0.05, 0.02, 0.0))
	add.call("spine_2", "spine_1", Vector3(0, 0.0, 0.15), Vector3(0.04, 0.0, 0.03))
	add.call("spine_3", "spine_2", Vector3(0, 0.0, 0.15), Vector3(0.0, 0.05, 0.0))
	add.call("neck_1", "spine_3", Vector3(0, 0.03, 0.12), Vector3(0.3, 0.0, 0.0))
	add.call("neck_2", "neck_1", Vector3(0, 0.0, 0.1), Vector3(0.2, 0.0, 0.05))
	add.call("skull", "neck_2", Vector3(0, 0.0, 0.08), Vector3(-0.4, 0.0, 0.0))
	add.call("jaw", "skull", Vector3(0, -0.03, 0.06), Vector3(0.5, 0.0, 0.0))
	for leg in ["fl", "fr", "hl", "hr"]:
		var front: bool = leg.begins_with("f")
		var side := 1.0 if leg.ends_with("l") else -1.0
		var top := "spine_3" if front else "hips"
		add.call("leg_%s_upper" % leg, top, Vector3(0.08 * side, -0.05, 0.0), Vector3(1.4, 0.0, 0.1 * side))
		add.call("leg_%s_lower" % leg, "leg_%s_upper" % leg, Vector3(0, 0.0, 0.2), Vector3(-0.5 if front else 0.6, 0.0, 0.0))
		add.call("leg_%s_paw" % leg, "leg_%s_lower" % leg, Vector3(0, 0.0, 0.2), Vector3(0.4, 0.02, 0.0))
		add.call("leg_%s_toe" % leg, "leg_%s_paw" % leg, Vector3(0, 0.0, 0.06), Vector3(0.2, 0.0, 0.0))
	var prev := "hips"
	for i in range(1, 6):
		add.call("tail_%d" % i, prev, Vector3(0, 0.0, -0.1 if i == 1 else -0.08), Vector3(0.15 + 0.02 * i, 0.03, 0.0))
		prev = "tail_%d" % i
	return rows


func write_fixture(rows: Array, path: String) -> Error:
	var root := Node3D.new()
	root.name = "creature"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	for r in rows:
		var i := sk.get_bone_count()
		sk.add_bone(r["name"])
		if r["parent"] != "":
			sk.set_bone_parent(i, sk.find_bone(r["parent"]))
		sk.set_bone_rest(i, r["xf"])
		sk.set_bone_pose_position(i, (r["xf"] as Transform3D).origin)
		sk.set_bone_pose_rotation(i, (r["xf"] as Transform3D).basis.get_rotation_quaternion())
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	root.add_child(mi)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.1, 0.5, 0), Vector3(0.1, 0.5, 0), Vector3(0, 0.7, 0)]
	for k in 3:
		st.set_bones(PackedInt32Array([0, 1, 2, 3]))
		st.set_weights(PackedFloat32Array([0.25, 0.25, 0.25, 0.25]))
		st.add_vertex(pts[k])
	mi.mesh = st.commit()
	mi.skin = sk.create_skin_from_rest_transforms()
	mi.skeleton = mi.get_path_to(sk)
	return GltfExport._write(root, path)


func pose_hash(B: Body) -> Array:
	var out := []
	for j in Body.ORDER:
		out.append(B.P[j])
	return out


func max_diff(a: Array, b: Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, (a[i] - b[i]).length())
	return m


func xf_diff(a: Transform3D, b: Transform3D) -> float:
	var m := (a.origin - b.origin).abs().max_value()
	for i in 3:
		m = maxf(m, (a.basis[i] - b.basis[i]).abs().max_value())
	return m


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var G := ProjectSettings.globalize_path(DIR)

	# Manny baseline (bar 7) BEFORE any custom-rig work
	var B := Body.new()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	S.apply(B, 0.5)
	var base := pose_hash(B)

	# ---- 1 IMPORT
	var rows := fixture()
	var fpath := G + "/quad.glb"
	var werr := write_fixture(rows, fpath)
	ok(werr == OK and FileAccess.file_exists(fpath), "1 fixture written: %d bones, %s" % [rows.size(), error_string(werr)])
	var rig: Dictionary = CustomRig.load_glb(fpath)
	ok(rig.get("ok", false), "1 load_glb ok: %s" % rig.get("why", ""))
	var names: Array = rig.get("names", [])
	ok(rows.size() == 30 and names.size() == 30, "1 bone count 30 -> %d" % names.size())
	var worst := 0.0
	var bad_par := []
	var bad_name := []
	for r in rows:
		var i := names.find(r["name"])
		if i < 0:
			bad_name.append(r["name"])
			continue
		var pn: String = "" if rig["parent"][i] < 0 else names[rig["parent"][i]]
		if pn != r["parent"]:
			bad_par.append(r["name"])
		worst = maxf(worst, xf_diff(rig["rest"][i], r["xf"]))
	ok(bad_name.is_empty() and bad_par.is_empty(), "1 names missing %s, parents wrong %s" % [bad_name, bad_par])
	ok(worst <= REST_BAR, "1 rest transforms max element diff %.8f (bar %.8f)" % [worst, REST_BAR])
	var moved: Transform3D = rows[10]["xf"]
	moved.origin.x += 2e-3
	ok(xf_diff(moved, rows[10]["xf"]) > REST_BAR, "1 control: a rest moved 2e-3 is seen")

	# ---- 2 OWN RIG
	ok(not CustomRig.is_human(rig) and not rig.has("map") and int(rig.get("core_matched", 99)) < 8, "2 not human, no Manny map, core matched %s of %d" % [rig.get("core_matched"), Body.ORDER.size()])
	var cap: String = CustomRig.capabilities(rig)
	ok(cap.to_lower().contains("human") and cap.length() > 20, "2 capabilities say what is off: %s" % cap.left(140))

	# ---- 3 FK
	var tail3 := names.find("tail_3")
	var before: Array = CustomRig.globals(rig, rig.get("pose", {}))
	var t5 := names.find("tail_5")
	var p5_rest: Vector3 = before[t5].origin
	var up_rest := []
	for nm in ["root", "hips", "tail_1", "tail_2"]:
		up_rest.append(before[names.find(nm)].origin)
	CustomRig.set_pose(rig, "tail_3", Quaternion(Vector3.RIGHT, deg_to_rad(40.0)))
	var after: Array = CustomRig.globals(rig, rig["pose"])
	var p5: Vector3 = after[t5].origin
	var chain := Transform3D.IDENTITY
	for nm in ["root", "hips", "tail_1", "tail_2", "tail_3", "tail_4", "tail_5"]:
		var i := names.find(nm)
		var loc: Transform3D = rig["rest"][i]
		if nm == "tail_3":
			loc = Transform3D(loc.basis * Basis(Quaternion(Vector3.RIGHT, deg_to_rad(40.0))), loc.origin)
		chain = chain * loc
	ok(tail3 >= 0 and p5.distance_to(p5_rest) >= 0.05, "3 tail_5 moved %.4f m by a 40 deg tail_3 (bar >= 0.05)" % p5.distance_to(p5_rest))
	ok(p5.distance_to(chain.origin) <= 1e-5, "3 FK equals the independent chain product: %.8f" % p5.distance_to(chain.origin))
	var up_move := 0.0
	var k := 0
	for nm in ["root", "hips", "tail_1", "tail_2"]:
		up_move = maxf(up_move, after[names.find(nm)].origin.distance_to(up_rest[k]))
		k += 1
	ok(up_move <= 1e-6, "3 bones above tail_3 stay: %.8f" % up_move)
	var rig_c: Dictionary = CustomRig.load_glb(fpath)
	CustomRig.set_pose(rig_c, "jaw", Quaternion(Vector3.RIGHT, 0.5))
	var gc: Array = CustomRig.globals(rig_c, rig_c["pose"])
	ok(gc[t5].origin.distance_to(p5_rest) <= 1e-6, "3 control: posing the jaw leaves tail_5 (%.8f)" % gc[t5].origin.distance_to(p5_rest))
	CustomRig.set_pose(rig, "tail_3", Quaternion.IDENTITY)   # back to rest for the round trip

	# ---- 4 ROUND TRIP
	var keyed := ["hips", "spine_2", "neck_1", "jaw", "leg_fl_upper", "leg_fr_lower", "leg_hl_upper", "leg_hr_paw", "tail_1", "tail_3", "tail_5", "skull"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 69
	for fr in [0, 10, 20]:
		for nm in keyed:
			var ax := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			CustomRig.set_pose(rig, nm, Quaternion(ax, rng.randf_range(0.0, 0.9)))
		CustomRig.key(rig, fr)
	var gpath := G + "/quad_anim.glb"
	var eerr: Error = CustomRig.export_glb(rig, gpath, 30.0)
	ok(eerr == OK and FileAccess.file_exists(gpath), "4 export_glb: %s" % error_string(eerr))
	var rig2: Dictionary = CustomRig.load_glb(gpath)
	ok(rig2.get("ok", false) and (rig2["names"] as Array).size() == 30, "4 re-import ok, %d bones" % (rig2.get("names", []) as Array).size())
	var kf: Array = CustomRig.key_frames(rig2)
	ok(kf == [0, 10, 20], "4 key frames back: %s" % [kf])
	var worst_a := 0.0
	var mx_pose := 0.0
	for fr in [0, 5, 10, 15, 20]:
		var p1: Dictionary = CustomRig.pose_at(rig, fr)
		var p2: Dictionary = CustomRig.pose_at(rig2, fr)
		for nm in names:
			var q1: Quaternion = p1.get(nm, Quaternion.IDENTITY)
			var q2: Quaternion = p2.get(nm, Quaternion.IDENTITY)
			worst_a = maxf(worst_a, q1.angle_to(q2))
			mx_pose = maxf(mx_pose, q1.angle_to(Quaternion.IDENTITY))
	ok(worst_a <= ANG_BAR, "4 pose round trip worst %.6f rad (bar %.4f)" % [worst_a, ANG_BAR])
	ok(mx_pose > 0.3, "4 control: the pose is not identity (max %.3f rad)" % mx_pose)
	var q_bad: Quaternion = (CustomRig.pose_at(rig2, 10)["tail_3"] as Quaternion) * Quaternion(Vector3.UP, 0.01)
	ok((CustomRig.pose_at(rig, 10)["tail_3"] as Quaternion).angle_to(q_bad) > ANG_BAR, "4 control: a key turned 0.01 rad is caught")

	# ---- 5 GATE
	var counter := [0]
	var tool := func(_r):
		counter[0] += 1
		return {"ok": true}
	var res: Dictionary = CustomRig.run_human_only(rig, "body_limits", tool)
	ok(not res.get("ok", true) and String(res.get("why", "")).contains("not a human rig") and counter[0] == 0, "5 planted tool on the quadruped: %s (ran %d)" % [res.get("why", ""), counter[0]])
	var res_pre: Dictionary = CustomRig.human_tool(rig, "precheck")
	ok(not res_pre.get("ok", true) and String(res_pre.get("why", "")).contains("not a human rig"), "5 precheck on the quadruped: %s" % res_pre.get("why", ""))
	var mpath := G + "/manny.glb"
	var me: Error = GltfExport.write(S, B, mpath, false)
	var mrig: Dictionary = CustomRig.load_glb(mpath)
	var res_m: Dictionary = CustomRig.run_human_only(mrig, "body_limits", tool)
	ok(me == OK and mrig.get("ok", false) and CustomRig.is_human(mrig) and counter[0] == 1 and res_m.get("ok", false), "5 control: Manny rig is human (%s core matched), tool ran %d" % [mrig.get("core_matched"), counter[0]])

	# ---- 6 EDIT
	var re: Dictionary = CustomRig.load_glb(gpath)
	var r1: String = CustomRig.add_bone(re, "tail_6", "tail_5", Transform3D(Basis(), Vector3(0, 0, -0.08)))
	ok(r1 == "" and (re["names"] as Array).size() == 31 and (re["names"] as Array)[re["parent"][re["names"].find("tail_6")]] == "tail_5", "6 add tail_6: %s -> %d bones" % [r1, (re["names"] as Array).size()])
	var hpath := G + "/quad_31.glb"
	var he: Error = CustomRig.export_glb(re, hpath, 30.0)
	var re2: Dictionary = CustomRig.load_glb(hpath)
	ok(he == OK and (re2.get("names", []) as Array).size() == 31 and (re2.get("names", []) as Array).has("tail_6"), "6 31 bones survive export / import")
	var wb: Array = CustomRig.globals(re, {})
	var w_t4: Transform3D = wb[re["names"].find("tail_4")]
	var w_paw: Transform3D = wb[re["names"].find("leg_hl_paw")]
	var r2: String = CustomRig.remove_bone(re, "tail_3")
	var wa: Array = CustomRig.globals(re, {})
	var i4: int = re["names"].find("tail_4")
	ok(r2 == "" and re["names"][re["parent"][i4]] == "tail_2" and xf_diff(wa[i4], w_t4) <= 1e-5, "6 remove tail_3: tail_4 on tail_2, world rest kept %.8f" % xf_diff(wa[i4], w_t4))
	ok(not (re["names"] as Array).has("tail_3") and not CustomRig.has_key_rows(re, "tail_3"), "6 removed bone gone and its key rows too")
	var r3: String = CustomRig.reparent(re, "leg_hl_paw", "leg_hr_lower")
	var wr: Array = CustomRig.globals(re, {})
	var ip: int = re["names"].find("leg_hl_paw")
	ok(r3 == "" and re["names"][re["parent"][ip]] == "leg_hr_lower" and xf_diff(wr[ip], w_paw) <= 1e-5, "6 reparent paw: world rest kept %.8f" % xf_diff(wr[ip], w_paw))
	var n_before: int = re["names"].size()
	var r_loop: String = CustomRig.reparent(re, "tail_1", "tail_5")
	var r_dup: String = CustomRig.add_bone(re, "tail_2", "tail_1", Transform3D.IDENTITY)
	var r_unk: String = CustomRig.add_bone(re, "wing_1", "no_such_bone", Transform3D.IDENTITY)
	ok(r_loop != "" and r_dup != "" and r_unk != "" and re["names"].size() == n_before and re["names"][re["parent"][re["names"].find("tail_1")]] == "hips", "6 loop / duplicate / unknown refused with words and nothing changed: [%s] [%s] [%s]" % [r_loop.left(40), r_dup.left(40), r_unk.left(40)])
	ok(not (re["names"] as Array).has("tail_3"), "6 control: tail_3 is not found after removal")

	# ---- 7 MANNY
	var B2 := Body.new()
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	S2.apply(B2, 0.5)
	var d7 := max_diff(base, pose_hash(B2))
	S.apply(B, 0.5)
	var d7b := max_diff(base, pose_hash(B))
	ok(d7 == 0.0 and d7b == 0.0, "7 walk_bat pose at 0.5 s identical after the custom-rig work: fresh body %.8f, same body %.8f" % [d7, d7b])
	ok(CustomRig.is_human(mrig), "7 Manny's own .glb is a human rig")

	for f in DirAccess.get_files_at(G):
		DirAccess.remove_absolute(G + "/" + f)
	DirAccess.remove_absolute(G)
	print("     %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RIGOWN %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
