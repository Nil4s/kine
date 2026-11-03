extends SceneTree
## godot --headless --path . -s tests/c48_test.gd     (C48 JOINTS LEAVE THE APP: complaints #314, #320; scripts/build/c48_joints.gd)
## Fixture: tests/hinge_test.gd's door (leaf 800 x 40 x 2000 mm = body 0, stop wall = body 1) with the hinge moved to pivot (800, 0, 0) mm, axis +z, limit 90.
## Bars, written before any number was read:
##  1 NODE    the built tree has ONE node with extras kine_joint; its position = (0.8, 0, 0) m within 1e-6; extras axis = (0, 0, 1); type revolute; limits +-90
##  2 SPLIT   the leaf mesh hangs under that node, in pivot-local metres (its box x runs -0.8 .. 0 within 1e-4); the stop wall is NOT under it
##  3 FILE    the written .glb has a JSON chunk whose nodes hold extras.kine_joint with axis [0,0,1], a node translation of 0.8 m on x, and 2 meshes
##  4 BLENDER Blender 4.5 imports the file; it finds the joint from the node's own extras; turning THAT node 30 deg about the stated axis around its origin:
##            the moving vertices match the closed form p + R (v - p) within 1e-5 m (CONTROL: the same vertices against a wrong axis miss by > 1e-3),
##            the moving piece moved > 0.05 m, the static piece moved < 1e-9 m, the node origin stayed within 1e-9, node origin = the stated pivot within 1e-5
##  5 URDF    one revolute joint named f5: origin 0.8 0 0, axis 0 0 1, limit +-pi/2 within 1e-5; a part with no hinge writes no URDF (ok false)
##  6 FRAMES  save_from_hinge then use_on_hinge on a second hinge (other pivot and axis): its o and axis equal the first's within 1e-9, its track/limit unchanged;
##            the frames survive Part.from_file(Part.to_file()); CONTROL: an empty name and a zero axis are refused
##  7 SAME    default export unchanged: the STL bytes of the part with its hinge equal those of the same part without the hinge step; ExportDialog.targets() is still 7
##  8 DIALOG  ExportDialog.target("joints") has the glb and urdf formats and its needs text lists what survives AND what does not (slide)
##  9 SECOND  a second hinge on the same body nests: two kine_joint nodes, the inner one under the outer, the mesh under the inner
const BLENDER := "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"
const OUT := "C:/Temp/claude/c48"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func door(extra_hinge := false) -> Dictionary:
	var rec := Part.make("C48 Door")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -20], "b": [800, 20]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 2000.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [-1600, 900], "b": [1600, 910]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 2000.0, "both": false, "op": "new"},
		{"t": "hinge", "id": "f5", "name": "Hinge1", "body": 0, "o": [800, 0, 0], "axis": [0, 0, 1], "track": [[0.0, 0.0], [3.0, 90.0]], "clear": []},
	]
	rec["seq"] = 5
	if extra_hinge:
		(rec["features"] as Array).append({"t": "hinge", "id": "f6", "name": "Hinge2", "body": 0, "o": [0, 0, 1000], "axis": [1, 0, 0], "track": [[0.0, 0.0], [2.0, 45.0]], "clear": [], "limit": 30.0})
		rec["seq"] = 6
	return rec


func joint_nodes(n: Node, acc: Array) -> Array:
	if n.has_meta("extras") and (n.get_meta("extras") as Dictionary).has("kine_joint"):
		acc.append(n)
	for c in n.get_children():
		joint_nodes(c, acc)
	return acc


func glb_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()
	f.get_32()
	f.get_32()
	var ln := f.get_32()
	f.get_32()
	var d: Variant = JSON.parse_string(f.get_buffer(ln).get_string_from_utf8())
	return d if d is Dictionary else {}


func _init() -> void:
	var wd := Timer.new()   # watchdog: the whole test stops itself
	root.add_child(wd)
	wd.one_shot = true
	wd.timeout.connect(func():
		print("FAIL watchdog: the test ran past 240 s")
		quit(2))
	wd.start(240.0)
	run.call_deferred()


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not Part.available():
		print("c48: no CAD library, nothing to measure")
		quit(1)
		return
	var rec := door()
	var info := {}
	var tree := C48Joints.build(rec, info)
	ok(tree != null, "0 BUILD the door builds a joint tree (%s)" % str(info.get("why", "")))
	if tree == null:
		quit(1)
		return
	# 1 NODE
	var jn := joint_nodes(tree, [])
	var one := jn.size() == 1
	var ex: Dictionary = (jn[0].get_meta("extras") as Dictionary)["kine_joint"] if one else {}
	var pos: Vector3 = (jn[0] as Node3D).position if one else Vector3.INF
	ok(one and pos.distance_to(Vector3(0.8, 0, 0)) < 1e-6 and String(ex.get("type")) == "revolute" and absf(float(ex["upper_deg"]) - 90.0) < 1e-9 and absf(float(ex["lower_deg"]) + 90.0) < 1e-9
		and Vector3(ex["axis"][0], ex["axis"][1], ex["axis"][2]).distance_to(Vector3(0, 0, 1)) < 1e-9, "1 NODE joint nodes %d, origin %s, axis %s, limits %s..%s" % [jn.size(), str(pos), str(ex.get("axis")), str(ex.get("lower_deg")), str(ex.get("upper_deg"))])
	# 2 SPLIT
	var leaf: MeshInstance3D = jn[0].get_child(0) if one else null
	var box := leaf.mesh.get_aabb() if leaf != null else AABB()
	var wall_under := false
	for c in jn[0].get_children():
		if c.name == "Body_1":
			wall_under = true
	var wall_ok := false
	for c in tree.get_children():
		if c.name == "Body_1":
			wall_ok = true
	ok(leaf != null and absf(box.position.x + 0.8) < 1e-4 and absf(box.end.x) < 1e-4 and not wall_under and wall_ok, "2 SPLIT leaf box x %.5f .. %.5f (want -0.8 .. 0), wall under the hinge: %s, wall at the root: %s" % [box.position.x, box.end.x, str(wall_under), str(wall_ok)])
	tree.free()
	# 3 FILE
	var w := C48Joints.write_glb(rec, OUT)
	ok(bool(w["ok"]), "3a FILE written: %s" % str(w["text"]))
	var gj := glb_json(String(w["path"]))
	var found_axis := false
	var tx := false
	for nd in gj.get("nodes", []):
		var e = nd.get("extras", {})
		if e is Dictionary and e.has("kine_joint"):
			var a: Array = e["kine_joint"]["axis"]
			found_axis = absf(float(a[0])) < 1e-6 and absf(float(a[1])) < 1e-6 and absf(float(a[2]) - 1.0) < 1e-6
			var t: Array = nd.get("translation", [0, 0, 0])
			tx = absf(float(t[0]) - 0.8) < 1e-5 and absf(float(t[1])) < 1e-6 and absf(float(t[2])) < 1e-6
	ok(found_axis and tx and (gj.get("meshes", []) as Array).size() == 2, "3b FILE extras axis in the file: %s, node translation 0.8 m: %s, meshes %d" % [str(found_axis), str(tx), (gj.get("meshes", []) as Array).size()])
	# 4 BLENDER
	var jf := OUT + "/blender.json"
	DirAccess.remove_absolute(jf)
	var pid := OS.create_process(BLENDER, ["-b", "--factory-startup", "--python", ProjectSettings.globalize_path("res://tests/c48_blender.py"), "--", String(w["path"]), jf])
	var t0 := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 120000:
		await create_timer(0.5).timeout
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var bj: Variant = JSON.parse_string(FileAccess.get_file_as_string(jf)) if FileAccess.file_exists(jf) else null
	if bj is Dictionary and bool(bj.get("found", false)):
		var pw: Array = bj["pivot_world"]
		var pa: Array = bj["pivot_after"]
		var piv_ok := Vector3(pw[0], pw[1], pw[2]).distance_to(Vector3(0.8, 0, 0)) < 1e-5
		var stay := Vector3(pw[0], pw[1], pw[2]).distance_to(Vector3(pa[0], pa[1], pa[2])) < 1e-9
		print("     blender: err_ok %.3g err_wrong %.3g moved %.3f other %.3g moving verts %d, static meshes %d" % [bj["err_ok"], bj["err_wrong"], bj["moved"], bj["other_delta"], bj["n_moving"], bj["n_static"]])
		ok(float(bj["err_ok"]) < 1e-5 and float(bj["err_wrong"]) > 1e-3 and float(bj["moved"]) > 0.05 and float(bj["other_delta"]) < 1e-9 and stay and piv_ok and int(bj["n_static"]) == 1,
			"4 BLENDER stated-axis turn matches closed form (err %.3g), wrong axis misses (%.3g), static moved %.3g, origin stayed %s, origin = pivot %s" % [bj["err_ok"], bj["err_wrong"], bj["other_delta"], str(stay), str(piv_ok)])
	else:
		ok(false, "4 BLENDER no result from Blender: %s" % str(bj))
	# 5 URDF
	var u := C48Joints.write_urdf(rec, OUT)
	var ut := FileAccess.get_file_as_string(String(u["path"])) if bool(u["ok"]) else ""
	ok(ut.contains("type=\"revolute\"") and ut.contains("name=\"f5\"") and ut.contains("xyz=\"0.800000 0.000000 0.000000\"") and ut.contains("<axis xyz=\"0.000000 0.000000 1.000000\"/>")
		and ut.contains("lower=\"-1.570796\" upper=\"1.570796\""), "5a URDF one revolute joint with origin, axis and +-pi/2")
	var plain := door()
	plain["features"].pop_back()
	ok(not bool(C48Joints.write_urdf(plain, OUT)["ok"]), "5b URDF a part with no hinge writes no URDF")
	# 6 FRAMES
	var r6 := door(true)
	var e1 := C48Joints.save_from_hinge(r6, "f5", "door edge")
	var e2 := C48Joints.use_on_hinge(r6, "f6", "door edge")
	var h2: Dictionary = Part.feature(r6, "f6")
	var same := Vector3(h2["o"][0], h2["o"][1], h2["o"][2]).distance_to(Vector3(800, 0, 0)) < 1e-9 and Vector3(h2["axis"][0], h2["axis"][1], h2["axis"][2]).distance_to(Vector3(0, 0, 1)) < 1e-9
	var kept: bool = absf(float(h2["limit"]) - 30.0) < 1e-9 and (h2["track"] as Array).size() == 2 and absf(float(h2["track"][1][1]) - 45.0) < 1e-9
	var back := Part.from_file(Part.to_file(r6))
	ok(e1 == "" and e2 == "" and same and kept and C48Joints.frame_names(back) == ["door edge"] and not C48Joints.get_frame(back, "door edge").is_empty()
		and C48Joints.save_frame(r6, "  ", Vector3.ZERO, Vector3.UP) != "" and C48Joints.save_frame(r6, "x", Vector3.ZERO, Vector3.ZERO) != "" and C48Joints.use_on_hinge(r6, "f6", "nope") != "",
		"6 FRAMES second hinge took pivot+axis (%s), kept limit/track (%s), survive save/load, refusals work (%s / %s)" % [str(same), str(kept), e1, e2])
	# 7 SAME
	var with_h := door()
	var no_h := door()
	no_h["features"].pop_back()
	var a1 := MeshExport.export_part(with_h, "stl", OUT + "/same_a")
	var a2 := MeshExport.export_part(no_h, "stl", OUT + "/same_b")
	var same_bytes := bool(a1["ok"]) and bool(a2["ok"]) and FileAccess.get_file_as_bytes(String(a1["path"])) == FileAccess.get_file_as_bytes(String(a2["path"]))
	ok(same_bytes and ExportDialog.targets().size() == 7, "7 SAME STL bytes with and without the hinge step equal: %s; engine targets %d" % [str(same_bytes), ExportDialog.targets().size()])
	# 8 DIALOG
	var t := ExportDialog.target("joints")
	var fs: Array = t.get("formats", [])
	var needs := ExportDialog.needs_of(t)
	ok(fs.size() == 2 and String(fs[0]["run"]) == "joints_glb" and String(fs[1]["run"]) == "joints_urdf" and needs.contains("hinge") and needs.contains("slide joints") and needs.contains("Joint types that do not"),
		"8 DIALOG joints target: %d formats, the needs text lists what survives and what does not" % fs.size())
	# 9 SECOND
	var r9 := door(true)
	var t9 := C48Joints.build(r9, {})
	var j9 := joint_nodes(t9, [])
	var nested: bool = j9.size() == 2 and j9[1].get_parent() == j9[0] and j9[1].get_child(0) is MeshInstance3D
	ok(nested, "9 SECOND two hinges on one body nest (%d joint nodes, inner under outer, mesh under inner)" % j9.size())
	t9.free()
	print("c48: %d fail" % fails)
	quit(1 if fails > 0 else 0)
