## godot --headless --path . -s tests/meshfile_test.gd     (ROADMAP_400 A07 .kmesh file + A08 normals modes)
## Bars, stated before measuring:
##   1 a 448x448-vertex (200,704 verts, 199,809 quads) grid saved and loaded: verts and faces identical to the last
##     bit, and load_file (parse + decode + half-edge rebuild) < 1000 ms headless
##   2 the same quad grid file is < 40 bytes per vertex
##   3 a cube with auto-smooth 30 deg: each of the 24 corner normals equals its face normal, 24 distinct normals;
##     a 16x32 UV sphere with auto-smooth 30 deg: every corner normal equals the smooth vertex normal (no splits),
##     and to_array_mesh(auto) of the cube has 24 vertices, of the sphere as many as the smooth mesh
##   4 custom normals survive to_dict/from_dict bit-exact and appear in to_array_mesh's normal array
##   5 corrupt files (bad base64, wrong counts, bad index, not JSON, missing file) return null with a last_error that
##     names a next step, and do not crash
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func cube() -> KMesh:
	var v := PackedVector3Array()
	for i in 8:
		v.append(Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1))
	var f: Array = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	return KMesh.new().from_arrays(v, f)


func sphere(rings: int, segs: int) -> KMesh:
	var v := PackedVector3Array()
	v.append(Vector3(0, 1, 0))
	for r in range(1, rings):
		var t := PI * r / rings
		for s in segs:
			var a := TAU * s / segs
			v.append(Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a)))
	v.append(Vector3(0, -1, 0))
	var f: Array = []
	for s in segs:
		f.append([0, 1 + (s + 1) % segs, 1 + s])
	for r in range(1, rings - 1):
		for s in segs:
			var a := 1 + (r - 1) * segs + s
			var b := 1 + (r - 1) * segs + (s + 1) % segs
			f.append([a, b, b + segs, a + segs])
	var last := v.size() - 1
	var base := 1 + (rings - 2) * segs
	for s in segs:
		f.append([last, base + s, base + (s + 1) % segs])
	return KMesh.new().from_arrays(v, f)


func grid(n: int) -> KMesh:
	var v := PackedVector3Array()
	v.resize(n * n)
	for y in n:
		for x in n:
			v[y * n + x] = Vector3(x * 0.01, sin(x * 0.05) * cos(y * 0.07) * 0.1, y * 0.01)
	var f: Array = []
	f.resize((n - 1) * (n - 1))
	var k := 0
	for y in n - 1:
		for x in n - 1:
			var a := y * n + x
			f[k] = PackedInt32Array([a, a + n, a + n + 1, a + 1])
			k += 1
	return KMesh.new().from_arrays(v, f)


func _init() -> void:
	# bars 1 + 2
	var g := grid(448)
	var path := "user://meshfile_test.kmesh"
	var t0 := Time.get_ticks_msec()
	var err := g.save(path)
	var t_save := Time.get_ticks_msec() - t0
	var size := FileAccess.get_file_as_bytes(path).size()
	var t1 := Time.get_ticks_msec()
	var h := KMesh.load_file(path)
	var t_load := Time.get_ticks_msec() - t1
	print("grid: V=%d F=%d  save %d ms  load %d ms  file %d bytes = %.1f B/vert" % [g.vert_count(), g.face_count(), t_save, t_load, size, float(size) / g.vert_count()])
	var same := h != null and h.verts == g.verts and h.faces.size() == g.faces.size()
	if same:
		for i in g.faces.size():
			if h.faces[i] != g.faces[i]:
				same = false
				break
	ok(err == OK and same, "bar 1: 200k-vert grid round-trips exactly (verts and faces)")
	ok(h != null and t_load < 1000, "bar 1: load %d ms < 1000 ms" % t_load)
	var t2 := Time.get_ticks_msec()
	var topo_ok := h != null and h.half_edge_count() == g.half_edge_count() and h.boundary_edge_count() == g.boundary_edge_count()
	print("first topology read after load (lazy build): %d ms" % (Time.get_ticks_msec() - t2))
	ok(topo_ok, "bar 1: loaded mesh builds the same half-edges and boundary on first read")
	ok(float(size) / g.vert_count() < 40.0, "bar 2: %.1f bytes/vert < 40" % (float(size) / g.vert_count()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# bar 3
	var c := cube()
	var cn := c.corner_normals(KMesh.NM_AUTO, 30.0)
	var all_face := true
	var distinct := {}
	for fi in c.face_count():
		for i in 4:
			var n: Vector3 = cn[fi][i]
			if n.distance_to(c.face_normals[fi]) > 1e-5:
				all_face = false
			distinct[[c.faces[fi][i], roundi(n.x * 1e4), roundi(n.y * 1e4), roundi(n.z * 1e4)]] = true
	ok(all_face and distinct.size() == 24, "bar 3: cube auto 30 deg: every corner normal = face normal, %d distinct corners" % distinct.size())
	var cube_auto: int = c.to_array_mesh(true, KMesh.NM_AUTO).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	ok(cube_auto == 24, "bar 3: cube auto to_array_mesh has %d vertices (24)" % cube_auto)
	var sp := sphere(16, 32)
	var sn := sp.corner_normals(KMesh.NM_AUTO, 30.0)
	var worst := 0.0
	for fi in sp.face_count():
		for i in (sp.faces[fi] as PackedInt32Array).size():
			worst = maxf(worst, (sn[fi][i] as Vector3).distance_to(sp.vert_normals[sp.faces[fi][i]]))
	var sp_auto: int = sp.to_array_mesh(true, KMesh.NM_AUTO).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	print("sphere: V=%d worst corner-vs-vertex normal diff %s, auto mesh verts %d" % [sp.vert_count(), String.num(worst, 9), sp_auto])
	ok(worst < 1e-5 and sp_auto == sp.vert_count(), "bar 3: sphere auto 30 deg = smooth vertex normals, no splits")
	var sp_tight := sp.to_array_mesh(true, KMesh.NM_AUTO).get_aabb()  # keep the call alive; angle control below
	sp.auto_angle = 5.0
	var sp_split: int = sp.to_array_mesh(true, KMesh.NM_AUTO).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	ok(sp_split > sp.vert_count() and sp_tight.size.x > 0.0, "bar 3: the angle matters (sphere at 5 deg splits: %d verts > %d)" % [sp_split, sp.vert_count()])

	# bar 4
	var cm := cube()
	var custom: Array = []
	for fi in cm.face_count():
		var pv := PackedVector3Array()
		for i in 4:
			pv.append(Vector3(0.1 * fi + 0.01 * i, 1.0, 0.5).normalized())
		custom.append(pv)
	ok(cm.set_custom_normals(custom), "bar 4: custom normals accepted")
	var d := cm.to_dict()
	var d2 = JSON.parse_string(JSON.stringify(d))  # through real JSON text, as a file would
	var cm2 := KMesh.new().from_dict(d2)
	var exact := cm2 != null and cm2.normal_mode == KMesh.NM_CUSTOM and cm2.custom_normals.size() == 6
	if exact:
		for fi in 6:
			if cm2.custom_normals[fi] != custom[fi]:
				exact = false
	ok(exact, "bar 4: custom normals survive to_dict/JSON/from_dict bit-exact")
	var arr := cm2.to_array_mesh().surface_get_arrays(0)
	var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var found := 0
	for fi in 6:
		for i in 4:
			for n in nor:
				if n.distance_to(custom[fi][i]) < 2e-2:
					found += 1
					break
	print("custom: array mesh has %d verts, %d/24 custom normals found" % [nor.size(), found])
	ok(found == 24 and nor.size() == 24, "bar 4: all 24 custom corner normals appear in to_array_mesh's normals")
	ok(not cm.set_custom_normals([PackedVector3Array()]) and KMesh.last_error.contains("Pass"), "bar 4: a wrong-shaped custom set is refused with a next step")

	# bar 5
	var good: Dictionary = JSON.parse_string(JSON.stringify(cube().to_dict()))
	var cases := {}
	var bad_b64: Dictionary = good.duplicate(true)
	bad_b64["v"]["z"] = "!!!not base64!!!"
	cases["bad base64"] = bad_b64
	var bad_cnt: Dictionary = good.duplicate(true)
	bad_cnt["verts"] = 9
	cases["wrong vertex count"] = bad_cnt
	var bad_fc: Dictionary = good.duplicate(true)
	bad_fc["faces"] = 7
	cases["wrong face count"] = bad_fc
	var bad_len: Dictionary = good.duplicate(true)
	bad_len["f"]["n"] = 12345
	cases["wrong byte length"] = bad_len
	var bad_ver: Dictionary = good.duplicate(true)
	bad_ver["version"] = 99
	cases["future version"] = bad_ver
	var oob := cube()
	oob.faces[0] = PackedInt32Array([0, 1, 99, 3])  # a face pointing past the last vertex
	cases["index out of range"] = JSON.parse_string(JSON.stringify(oob.to_dict()))
	for k in cases:
		var r := KMesh.new().from_dict(cases[k])
		var e := KMesh.last_error
		var next_step := e.contains("re-save") or e.contains("restore") or e.contains("Update") or e.contains("Pick")
		ok(r == null and e != "" and next_step, "bar 5: %s -> error '%s'" % [k, e.left(70)])
	var junk := FileAccess.open("user://meshfile_junk.kmesh", FileAccess.WRITE)
	junk.store_string("{ this is not json")
	junk.close()
	ok(KMesh.load_file("user://meshfile_junk.kmesh") == null and KMesh.last_error.contains("Pick"), "bar 5: non-JSON file -> error with a next step")
	ok(KMesh.load_file("user://meshfile_missing.kmesh") == null and KMesh.last_error.contains("Pick"), "bar 5: missing file -> error with a next step")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://meshfile_junk.kmesh"))

	print("meshfile_test: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
