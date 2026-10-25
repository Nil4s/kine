## godot --headless --path . -s tests/engine_export_test.gd     (ROADMAP item 9: "Export for Unreal 5 / Unity / Godot")
## For each preset (ue5, unity, godot) the scene is written to user://zz_engines/ and READ BACK with Godot's GLTFDocument
## (not by the exporter's code). Checks:
##  (1) UE5: the root bone's translation track equals the scene's pelvis horizontal displacement since frame 0, within
##      1 mm, at 10 times; the pelvis, carried by the root's rest and the root track, has no horizontal drift (1 mm).
##  (2) Unity / Godot: the pelvis carries the travel itself (no root bone move): the same displacement, within 1 mm.
##  (3) Up and scale as the file says (glTF: metres, +Y up, the front to +Z): the mannequin reads 1.5-2.0 m tall, the head
##      above the pelvis above the foot, the toes to +Z.
##  (4) The pre-flight lists every check, each "OK ..." or "WRONG ...", and it is printed BEFORE the file exists.
extends SceneTree

var fails := 0
const DIR := "user://zz_engines"
const SCENE := "combo3"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _bone(sk: Skeleton3D, nm: String) -> int:
	var i := sk.find_bone(nm)
	if i < 0 and nm == "head":
		i = sk.find_bone("Head")
	return i


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % SCENE)))
	var L := S.length()
	var fps := float(S.fps)
	var times := []
	# 10 times ON key frames (a key every frame at fps): between keys the engine interpolates linearly, which is not the
	# scene's own curve, so the comparison is made where the file holds the exact value
	var nk := int(ceil(L * fps - 1e-6))
	for i in 10:
		times.append(minf(float(((i + 1) * nk) / 11) / fps, L))

	# the scene's own pelvis displacement since frame 0 (horizontal), at each test time
	var P0 := Vector3.ZERO
	S.apply(B, 0.0)
	P0 = B.P["pelvis"]
	var want := []
	var travel := 0.0
	for t in times:
		S.apply(B, t)
		var D: Vector3 = B.P["pelvis"] - P0
		want.append(Vector3(D.x, 0.0, D.z))
		travel = maxf(travel, Vector2(D.x, D.z).length())
	ok(travel > 0.05, "scene %s travels %.3f m sideways (a test needs travel over 5 cm)" % [SCENE, travel])
	var keep := B.state()

	for id in ["ue5", "unity", "godot"]:
		var p := EngineExport.preset(id)
		var path := "%s/%s" % [DIR, EngineExport.file_name(SCENE, id)]
		var abs := ProjectSettings.globalize_path(path)
		# (4) the report runs before the file exists
		var seen := []
		var report := func(lines): seen.append(FileAccess.file_exists(abs)); seen.append(lines.size())
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
		var r: Dictionary = EngineExport.export(S, B, id, DIR, report)
		B.set_state(keep)
		ok(r["err"] == OK, "%s: written to %s (err %d)" % [id, path, r["err"]])
		ok(seen.size() == 2 and seen[0] == false, "%s: the pre-flight report came BEFORE the file was written" % id)
		var lines: Array = r["lines"]
		var want_n := 8 if id == "ue5" else 7
		ok(lines.size() == want_n, "%s: %d checks printed (want %d)" % [id, lines.size(), want_n])
		for l in lines:
			print("    " + String(l))
			ok((l as String).begins_with("OK") or (l as String).begins_with("WRONG"), "%s: line tagged OK or WRONG" % id)
		if id == "ue5":
			var has_wrong := false
			for l in lines:
				has_wrong = has_wrong or (l as String).begins_with("WRONG")
			ok(not has_wrong, "ue5: no WRONG line for this scene")

		# READ BACK
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		ok(doc.append_from_file(abs, st) == OK, "%s: GLTFDocument reads it back" % id)
		var back: Node3D = doc.generate_scene(st)
		root.add_child(back)
		var sk: Skeleton3D = back.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = back.find_children("*", "AnimationPlayer", true, false)[0]
		var A: Animation = ap.get_animation(SCENE)
		ok(A != null, "%s: the animation is named after the scene (%s)" % [id, SCENE])
		var ptr := -1
		var rtr := -1
		for i in A.get_track_count():
			var tp := String(A.track_get_path(i))
			if tp.ends_with(":pelvis") and A.track_get_type(i) == Animation.TYPE_POSITION_3D:
				ptr = i
			if tp.ends_with(":root") and A.track_get_type(i) == Animation.TYPE_POSITION_3D:
				rtr = i
		ok(ptr >= 0, "%s: a pelvis position track" % id)
		if id == "ue5":
			ok(rtr >= 0, "ue5: a root bone position track (root motion)")
		else:
			ok(rtr < 0, "%s: no root motion track (the pelvis carries the travel)" % id)
		var rest_root := Basis.IDENTITY
		if sk.find_bone("root") >= 0:
			rest_root = sk.get_bone_rest(sk.find_bone("root")).basis
		var worst_move := 0.0
		var worst_root := 0.0
		for i in times.size():
			var t: float = times[i]
			var pel: Vector3 = A.position_track_interpolate(ptr, t)
			var mv := Vector3.ZERO
			if rtr >= 0:
				mv = A.position_track_interpolate(rtr, t)
			# the travel the file carries: the root track (ue5) plus the pelvis's own horizontal place, in the armature
			var place := rest_root * pel + mv
			var h0 := rest_root * (A.position_track_interpolate(ptr, 0.0)) + (A.position_track_interpolate(rtr, 0.0) if rtr >= 0 else Vector3.ZERO)
			var carried := Vector3(place.x - h0.x, 0.0, place.z - h0.z)
			if id == "ue5":
				var dr: Vector3 = mv - want[i]
				worst_root = maxf(worst_root, Vector2(dr.x, dr.z).length())
				worst_move = maxf(worst_move, Vector2(dr.x, dr.z).length())
			else:
				var dc: Vector3 = carried - want[i]
				worst_move = maxf(worst_move, Vector2(dc.x, dc.z).length())
		if id == "ue5":
			ok(worst_root < 0.001, "ue5: root track = scene pelvis horizontal travel at 10 times, worst %.3f mm" % (worst_root * 1000.0))
			# the pelvis itself: its horizontal place (root rest and root track added) does not move
			# the pelvis's own track: its place relative to the root (root rest applied) does not move sideways
			var worst_pel := 0.0
			var base_pel := rest_root * (A.position_track_interpolate(ptr, 0.0))
			for t in times:
				var pel2: Vector3 = rest_root * A.position_track_interpolate(ptr, t)
				worst_pel = maxf(worst_pel, Vector2(pel2.x - base_pel.x, pel2.z - base_pel.z).length())
			ok(worst_pel < 0.001, "ue5: the pelvis has no horizontal drift on its own track (worst %.3f mm)" % (worst_pel * 1000.0))
		else:
			ok(worst_move < 0.001, "%s: the pelvis carries the scene's travel, worst %.3f mm" % [id, worst_move * 1000.0])

		# (3) up, scale and facing as the file says
		var hd := sk.get_bone_global_rest(_bone(sk, "head")).origin
		var pv := sk.get_bone_global_rest(sk.find_bone("pelvis")).origin
		var ft := sk.get_bone_global_rest(sk.find_bone("foot_l")).origin
		var bl := sk.get_bone_global_rest(sk.find_bone("ball_l")).origin
		ok(hd.y > pv.y and pv.y > ft.y + 0.3, "%s: standing, Y up in the file: head %.2f, pelvis %.2f, foot %.2f m" % [id, hd.y, pv.y, ft.y])
		ok(bl.z > ft.z, "%s: toes to +Z (the glTF front): ball %.2f vs foot %.2f" % [id, bl.z, ft.z])
		var H := 0.0
		for mi in back.find_children("*", "MeshInstance3D", true, false):
			H = maxf(H, (mi as MeshInstance3D).get_aabb().size.y)
		ok(H >= 1.5 and H <= 2.0, "%s: mannequin height in the file %.2f m (metres)" % [id, H])
		back.queue_free()

	# the pre-flight alone, with the same numbers (no writing)
	for id in ["ue5"]:
		var pre := EngineExport.preflight(S, B, id, SCENE)
		ok(pre.size() == 8, "preflight(ue5) returns 8 lines (%d)" % pre.size())
	B.set_state(keep)

	# clean up
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	print("ENGINE EXPORT: %d failed, travel %.3f m" % [fails, travel])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
