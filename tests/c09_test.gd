extends SceneTree
## godot --headless --path . -s tests/c09_test.gd     (C09: export name template #381, FBX shot camera #702, lightmap UV2 #28)
## BARS, written before the numbers:
##  A NAMES   "{name}_{part}_{date}" with Run / arm / 2026-11-02 = "Run_arm_2026-11-02"; blank = the fallback (old name); "/" and ":" never survive.
##            CONTROL: the blank and the templated name differ (a writer that ignored the template fails).
##  B CAMERA  3 shot keys; the ASCII FBX read back: camera translation key 0 = pos within 0.1 mm; local +X rotated by the stored Euler (Rz Ry Rx)
##            = the view direction within 1e-4, at keys 0 and 2; FieldOfView = fov_h(f) within 0.001 deg; FocalLength curve 35,50,85; KeyTime *3 on all
##            7 camera curves; the bone curve count is the same with and without the camera; no camera keys = no "Model::Camera"; the binary file writes.
##            CONTROL: the UNTURNED Godot basis (-Z forward) puts +X off the view direction by more than 0.01.
##  C LIGHTMAP box + sphere: UV2 on every corner, all in [0,1], no two triangles overlap (SAT, strict), positions kept; an un-asked mesh has no UV2;
##            the written .glb has TEXCOORD_1 and the plain one has not. CONTROL: the overlap reader flags a planted layout.
var fails := 0
const DIR := "user://zz_c09"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func _tri_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for tri in [a, b]:
		for i in 3:
			var e: Vector2 = tri[(i + 1) % 3] - tri[i]
			var n := Vector2(-e.y, e.x).normalized() if e.length() > 1e-12 else Vector2.ZERO
			var amin := 1e30
			var amax := -1e30
			var bmin := 1e30
			var bmax := -1e30
			for p in a:
				amin = minf(amin, n.dot(p))
				amax = maxf(amax, n.dot(p))
			for p in b:
				bmin = minf(bmin, n.dot(p))
				bmax = maxf(bmax, n.dot(p))
			if amax - bmin <= 1e-6 or bmax - amin <= 1e-6:   # touching along a shared edge is not overlap
				return false
	return true


func _overlaps(uv: PackedVector2Array) -> int:
	var n := 0
	var nt := uv.size() / 3
	for i in nt:
		var a := uv.slice(i * 3, i * 3 + 3)
		if absf((a[1] - a[0]).cross(a[2] - a[0])) < 1e-12:
			continue   # a pole triangle of the sphere: zero area in 3D too, covers no texel
		for j in range(i + 1, nt):
			if _tri_overlap(a, uv.slice(j * 3, j * 3 + 3)):
				n += 1
	return n


func _props(text: String, model: String, prop: String) -> Vector3:
	var i := text.find("Model::" + model)
	var j := text.find("\"%s\", \"%s\", \"\", \"A\"," % [prop, prop], i)
	var line := text.substr(j, text.find("\n", j) - j)
	var p := line.split("\"A\",")[1].split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _json_of(path: String) -> String:
	var b := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))
	return b.slice(20, 20 + b.decode_u32(12)).get_string_from_utf8()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var dt := {"year": 2026, "month": 11, "day": 2, "hour": 9, "minute": 5}
	var nm := ExportNames.expand("{name}_{part}_{date}", {"name": "Run", "part": "arm"}, "old", dt)
	ok(nm == "Run_arm_2026-11-02", "A1 template -> '%s'" % nm)
	ok(ExportNames.expand("", {"name": "Run"}, "old", dt) == "old", "A2 blank = old name")
	var bad := ExportNames.expand("a/b:{name}", {"name": "Run"}, "old", dt)
	ok(not ("/" in bad or ":" in bad), "A3 no path characters survive ('%s')" % bad)
	ok(ExportNames.expand("{name}_{time}", {"name": "R"}, "old", dt) == "R_0905", "A4 {time}")
	ok(nm != ExportNames.expand("", {}, "old", dt), "A5 control: templated differs from the old name")
	# B
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var keys := [{"t": 0.0, "pos": Vector3(1, 1.5, 4), "aim": Vector3(0, 1, 0), "f": 35.0},
		{"t": 0.5, "pos": Vector3(-2, 1.2, 3), "aim": Vector3(0, 1, 0), "f": 50.0},
		{"t": 1.0, "pos": Vector3(-3, 2.0, -2), "aim": Vector3(0, 1.1, 0), "f": 85.0}]
	var base := FbxExport.write(S, B, DIR + "/nocam.fbx", false, Transform3D.IDENTITY, "", true)
	var withc := FbxExport.write(S, B, DIR + "/cam.fbx", false, Transform3D.IDENTITY, "", true, keys)
	var bin := FbxExport.write(S, B, DIR + "/cam_bin.fbx", false, Transform3D.IDENTITY, "", false, keys)
	ok(base["err"] == OK and withc["err"] == OK and bin["err"] == OK, "B0 files written (binary %d bytes)" % bin["size"])
	var t: String = withc["text"]
	ok(not ("Model::Camera" in String(base["text"])), "B1 no camera keys = no camera in the file")
	ok(base["curves"] == withc["curves"], "B2 bone curve count unchanged (%d)" % base["curves"])
	var p0 := _props(t, "Camera", "Lcl Translation") / 100.0
	ok(p0.distance_to(keys[0]["pos"]) < 1e-4, "B3 key 0 position %s vs %s" % [p0, keys[0]["pos"]])
	var e0 := _props(t, "Camera", "Lcl Rotation")
	var R := Basis.from_euler(Vector3(deg_to_rad(e0.x), deg_to_rad(e0.y), deg_to_rad(e0.z)), EULER_ORDER_ZYX)
	var want: Vector3 = (keys[0]["aim"] - keys[0]["pos"]).normalized()
	var err0 := (R * Vector3.RIGHT).distance_to(want)
	ok(err0 < 1e-4, "B4 key 0 view direction error %.6f" % err0)
	var kt3 := 0
	var pos := t.find("Model::Camera")
	while true:
		var q := t.find("KeyTime: *3 {", pos)
		if q < 0:
			break
		kt3 += 1
		pos = q + 5
	ok(kt3 == 7, "B5 KeyTime *3 on all 7 camera curves (%d)" % kt3)
	var fo := t.find("P: \"FieldOfView\"")
	var fov_line := t.substr(fo, t.find("\n", fo) - fo).split("\"A\",")[1]
	ok(absf(float(fov_line) - ShotCam.fov_h(35.0)) < 1e-3, "B6 FieldOfView %s vs %.4f" % [fov_line, ShotCam.fov_h(35.0)])
	ok("a: 35.000000000,50.000000000,85.000000000" in t, "B7 FocalLength curve 35,50,85")
	var vals := []
	var cur := t.find("AnimCurveNode::R\"", t.find("Model::Camera"))
	for ax in 3:
		cur = t.find("KeyValueFloat: *3 {", cur + 5)
		var ln := t.substr(cur, t.find("}", cur) - cur).split("a: ")[1].strip_edges().split(",")
		vals.append(float(ln[2]))
	var R2 := Basis.from_euler(Vector3(deg_to_rad(vals[0]), deg_to_rad(vals[1]), deg_to_rad(vals[2])), EULER_ORDER_ZYX)
	var want2: Vector3 = (keys[2]["aim"] - keys[2]["pos"]).normalized()
	var err2 := (R2 * Vector3.RIGHT).distance_to(want2)
	ok(err2 < 1e-4, "B8 key 2 view direction error %.6f" % err2)
	var godot_err := (ShotCam.xf(keys[0]["pos"], keys[0]["aim"]).basis * Vector3.RIGHT).distance_to(want)
	ok(godot_err > 0.01, "B9 control: the unturned Godot basis misses by %.3f" % godot_err)
	# C
	var objs := []
	var sph := SphereMesh.new()
	sph.radial_segments = 16
	sph.rings = 8
	for m in [BoxMesh.new(), sph]:
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.get_mesh_arrays())
		objs.append({"name": "o%d" % objs.size(), "mesh": am, "xf": Transform3D.IDENTITY})
	for o in objs:
		var src: ArrayMesh = o["mesh"]
		ok(not LightmapUV.has_uv2(src), "C0 %s: no UV2 unless asked" % o["name"])
		var r := LightmapUV.generate(src)
		var arr: Array = (r["mesh"] as ArrayMesh).surface_get_arrays(0)
		var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var sa := src.surface_get_arrays(0)
		var nt: int = (sa[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		ok(u2.size() == nt * 3, "C1 %s: UV2 on every corner (%d, tris %d, charts %d)" % [o["name"], u2.size(), nt, r["charts"]])
		var inside := true
		for p in u2:
			if p.x < 0 or p.y < 0 or p.x > 1 or p.y > 1:
				inside = false
		ok(inside, "C2 %s: all in 0..1" % o["name"])
		var degen := 0
		for i in nt:
			if absf((u2[i*3+1]-u2[i*3]).cross(u2[i*3+2]-u2[i*3])) < 1e-12:
				degen += 1
		print("degenerate UV2 tris: ", degen)
		var ov := _overlaps(u2)
		ok(ov == 0, "C3 %s: overlapping triangle pairs = %d" % [o["name"], ov])
		var ps := {}
		for p in (sa[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			ps[Vector3i((p * 1000).round())] = true
		var same := true
		for p in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if not ps.has(Vector3i((p * 1000).round())):
				same = false
		ok(same, "C4 %s: positions kept" % o["name"])
		var planted := PackedVector2Array()
		var tri3 := [Vector2(0.1, 0.1), Vector2(0.4, 0.1), Vector2(0.1, 0.4)]
		for i in u2.size():
			planted.append(tri3[i % 3])
		ok(_overlaps(planted) > 0, "C5 control: the overlap reader flags a planted layout")
	var path := DIR + "/lm.glb"
	ok(GltfExport.write_meshes(LightmapUV.apply_list(objs), path) == OK, "C6 .glb with UV2 written")
	var bytes := _json_of(path)
	var ai := bytes.find("attributes")
	print("glb attrs: ", bytes.substr(ai, 200))
	ok("TEXCOORD_1" in bytes, "C7 the .glb has TEXCOORD_1")
	GltfExport.write_meshes(objs, DIR + "/plain.glb")
	var pb := _json_of(DIR + "/plain.glb")
	ok(not ("TEXCOORD_1" in pb), "C8 control: the plain export has no TEXCOORD_1")
	var ctl := ExportNames.controls()
	ok(ctl.find_child("le_name_template", true, false) != null and ctl.find_child("chk_fbx_camera", true, false) != null and ctl.find_child("chk_lightmap_uv", true, false) != null, "D1 dialog controls exist")
	ctl.free()
	print("c09: %d fail" % fails)
	quit(1 if fails else 0)
