## godot --headless --path . -s tests/fbx_export_test.gd     (ROADMAP 78: FBX export)
## Writes scenes/combo3 as FBX (FbxExport) and as .glb (GltfExport, the reference) into user://zz_fbx, records the BODY's
## own local rotations (Body.gltf_local) and pelvis position at 3 frames for 3 bones, and hands the three to
## tests/py/fbx_check.py, a reader of its own that parses the FBX text (python -I). The bars, stated before the numbers:
##   bones: the FBX's LimbNode names and order are the glb's skin joints, the parents match, the head is "head";
##   keys: every curve has one key per frame, and the frame count is the glb's own (not this test's);
##   rotation: the 3 bones at 3 frames, read back from the FBX curves, within 0.01 deg of the body's local rotation;
##   pelvis: its position (cm curves / 100) within 0.1 mm of the body's.
## The Blender check (tests/py/fbx_blender_check.py) is separate: it needs Blender and is run by hand (docs/EXPORT.md).
extends SceneTree

var fails := 0
const DIR := "user://zz_fbx"
const BONES := ["pelvis", "spine_01", "upperarm_l"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var L := S.length()
	var fps := float(S.fps)
	var nfr := int(ceil(L * fps - 1e-6)) + 1
	var fbx := "%s/combo3.fbx" % DIR
	var glb := "%s/combo3.glb" % DIR
	var keep := B.state()
	var r := FbxExport.write(S, B, fbx)
	ok(r["err"] == OK, "1 the .fbx is written (err %d, %d bones, %d curves, %d keys per curve)" % [r["err"], (r["bones"] as PackedStringArray).size(), r["curves"], r["keys"]])
	var eg := GltfExport.write(S, B, glb)
	ok(eg == OK, "2 the reference .glb is written (err %d)" % eg)
	# the body's own numbers at 3 frames: first, middle, last (the glb's sample times, k / fps capped at the length)
	var frames := [0, nfr / 2, nfr - 1]
	var samples := []
	for k in frames:
		var t := minf(k / fps, L)
		S.apply(B, t)
		for j in BONES:
			var q := B.gltf_local(j)
			var s := {"bone": j, "frame": k, "t": t, "q": [q.x, q.y, q.z, q.w], "p": null}
			if j == "pelvis":
				var p := B.gltf_pelvis_pos()
				s["p"] = [p.x, p.y, p.z]
			samples.append(s)
	B.set_state(keep)
	var exp_path := "%s/expected.json" % DIR
	var f := FileAccess.open(ProjectSettings.globalize_path(exp_path), FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": fps, "frames": nfr, "length": L, "samples": samples}, "\t"))
	f.close()
	var py := ProjectSettings.globalize_path("res://tests/py/fbx_check.py")
	var out: Array = []
	var code := OS.execute("python", PackedStringArray(["-I", py, ProjectSettings.globalize_path(fbx), ProjectSettings.globalize_path(glb), ProjectSettings.globalize_path(exp_path)]), out, true)
	for o in out:
		for line in String(o).split("\n"):
			if line.strip_edges() != "":
				print(line)
	ok(code == 0, "3 tests/py/fbx_check.py (python -I) reads the FBX back and passes every check above (exit %d)" % code)
	print("FBX EXPORT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
