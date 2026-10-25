extends SceneTree
## A09 mesh attributes. Bars (stated before measuring): (1) save/load on a 10k-vert grid is bit-exact for float, Vector2,
## Vector3 and Color on vert, corner, edge and face (16 channels); (2) undo of a topology edit restores every channel
## exactly (redo too), and an attribute-only edit is a light "attr" step that undoes exactly; (3) repair of a cube with a
## doubled vert keeps the FIRST vert's colour (and the corner/face channels follow the kept faces); (4) to_array_mesh
## carries colour (COLOR, tol 1/255) and uv (TEX_UV, tol 1e-3) for vert and for corner domains; (5) one float per vert
## adds < 10% to the save time of a 200k-vert grid.
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func grid(n: int) -> KMesh:
	var v := PackedVector3Array()
	var f := []
	for j in n + 1:
		for i in n + 1:
			v.append(Vector3(i, 0, j) * 0.01)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			f.append(PackedInt32Array([a, a + 1, a + n + 2, a + n + 1]))
	return KMesh.new().from_arrays(v, f)
func rv(t: int, rng: RandomNumberGenerator):
	match t:
		TYPE_VECTOR2:
			return Vector2(rng.randf(), rng.randf() * 7.0)
		TYPE_VECTOR3:
			return Vector3(rng.randf(), rng.randf_range(-3, 3), rng.randf())
		TYPE_COLOR:
			return Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
	return rng.randf_range(-100, 100)
func fill(m: KMesh, rng: RandomNumberGenerator) -> void:
	for dom in KMesh.AD_ALL:
		for t in KMesh.AT_ALL:
			var nm := "%s_%d" % [dom, t]
			m.add_attr(nm, dom, t, rv(t, rng))
			var d = m.attr_data(nm)
			for i in d.size():
				d[i] = rv(t, rng)
			m.set_attr_data(nm, d)
func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	# (1) round trip
	var m := grid(100)
	fill(m, rng)
	var path := "user://kmesh_attrs_test.kmesh"
	var e := m.save(path)
	var g := KMesh.load_file(path)
	var exact := g != null and e == OK and g.list_attrs().size() == 16
	var bad := ""
	if exact:
		for k in m.list_attrs():
			var a = m.attr_data(k)
			var b = g.attr_data(k) if g.has_attr(k) else null
			if b == null or a.size() != b.size() or a != b or g.attr_info(k)["domain"] != m.attr_info(k)["domain"] or g.attr_info(k)["type"] != m.attr_info(k)["type"] or g.attr_info(k)["default"] != m.attr_info(k)["default"]:
				exact = false
				bad += k + " "
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok(exact, "(1) %d verts, 16 channels (4 types x 4 domains) round-trip bit-exact %s" % [m.vert_count(), bad])
	# (2) undo
	var c := grid(6)
	c.add_attr("mask", KMesh.AD_VERT, TYPE_FLOAT, 0.25)
	c.add_attr("col", KMesh.AD_CORNER, TYPE_COLOR, Color.RED)
	c.add_attr("crease", KMesh.AD_EDGE, TYPE_FLOAT, 0.0)
	c.add_attr("tag", KMesh.AD_FACE, TYPE_VECTOR2, Vector2(1, 2))
	for i in c.vert_count():
		c.set_attr("mask", i, float(i) * 0.5)
	var snap := c.attr_snapshot()
	var U := KMeshUndo.new()
	U.begin(c)
	var fs := c.faces.duplicate()
	fs.remove_at(3)
	c.from_arrays(c.verts, fs)
	U.commit("delete face")
	var shrunk: bool = c.attr_data("col").size() == 35 * 4
	U.undo()
	var same := true
	for k in snap:
		same = same and c.attr_data(k) == snap[k]["data"]
	ok(shrunk and same and c.attr_data("col").size() == 144, "(2a) topo edit refits channels (corner 144 -> 140), undo restores all 4 exactly (%s)" % same)
	U.redo()
	ok(c.face_count() == 35 and c.attr_data("col").size() == 140 and c.attr_data("tag").size() == 35, "(2b) redo: 35 faces, corner channel 140, face channel 35")
	U.undo()
	var n0 := U.steps.size()
	U.begin(c)
	c.set_attr("mask", 5, 9.0)
	c.add_attr("extra", KMesh.AD_FACE, TYPE_FLOAT, 3.0)
	var st := U.commit("paint")
	ok(st.get("kind", "") == "attr" and U.steps.size() == n0 + 1 and int(st["bytes"]) < 4000, "(2c) attr-only edit is a light 'attr' step (%d bytes)" % int(st.get("bytes", -1)))
	U.undo()
	ok(c.get_attr("mask", 5) == 2.5 and not c.has_attr("extra"), "(2d) attr step undone: mask[5]=%s, added channel gone" % str(c.get_attr("mask", 5)))
	U.redo()
	ok(c.get_attr("mask", 5) == 9.0 and c.has_attr("extra"), "(2e) attr step redone")
	# (3) repair: cube with a doubled vert
	var cv := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)])
	var cf := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
	cv.append(cv[0])   # vert 8 sits on vert 0
	cf[2] = [8, 1, 5, 4]
	var cube := KMesh.new().from_arrays(cv, cf)
	cube.add_attr("color", KMesh.AD_VERT, TYPE_COLOR, Color.WHITE)
	cube.set_attr("color", 0, Color.RED)
	cube.set_attr("color", 8, Color.BLUE)
	cube.set_attr("color", 6, Color.GREEN)
	cube.add_attr("cc", KMesh.AD_CORNER, TYPE_FLOAT, 0.0)
	for i in cube.domain_count("corner"):
		cube.set_attr("cc", i, float(i))
	cube.add_attr("fid", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	for i in 6:
		cube.set_attr("fid", i, float(i) + 10.0)
	var done := KMeshValidate.repair(cube)
	var corner_ok: bool = cube.attr_data("cc").size() == 24 and cube.get_attr("cc", 8) == 8.0 and cube.get_attr("cc", 11) == 11.0
	ok(cube.vert_count() == 8 and done.get("doubled", 0) == 1 and cube.get_attr("color", 0) == Color.RED and cube.get_attr("color", 6) == Color.GREEN and cube.attr_data("color").size() == 8,
		"(3a) repair: 9 -> %d verts, vert 0 keeps RED (not the doubled BLUE), vert 6 still GREEN" % cube.vert_count())
	ok(corner_ok and cube.attr_data("fid").size() == 6 and cube.get_attr("fid", 5) == 15.0, "(3b) corner and face channels follow the faces (cc[8]=%s, fid[5]=%s, %d corners)" % [str(cube.get_attr("cc", 8)), str(cube.get_attr("fid", 5)), cube.attr_data("cc").size()])
	# (4) to_array_mesh
	var q := grid(3)
	q.add_attr("color", KMesh.AD_VERT, TYPE_COLOR)
	q.add_attr("uv", KMesh.AD_VERT, TYPE_VECTOR2)
	for i in q.vert_count():
		q.set_attr("color", i, Color(float(i) / 16.0, 1.0 - float(i) / 16.0, 0.5, 1.0))
		q.set_attr("uv", i, Vector2(float(i % 4) / 3.0, float(i / 4) / 3.0))
	var am := q.to_array_mesh()
	var arr := am.surface_get_arrays(0)
	var worst_c := 0.0
	var worst_u := 0.0
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var have := cols.size() == pos.size() and uvs.size() == pos.size()
	if have:
		for o in pos.size():
			var src := -1
			for v in q.vert_count():
				if q.verts[v].distance_to(pos[o]) < 1e-6:
					src = v
			var want_c: Color = q.get_attr("color", src)
			worst_c = maxf(worst_c, maxf(absf(cols[o].r - want_c.r), maxf(absf(cols[o].g - want_c.g), absf(cols[o].b - want_c.b))))
			worst_u = maxf(worst_u, uvs[o].distance_to(q.get_attr("uv", src)))
	ok(have and worst_c <= 1.0 / 255.0 + 1e-6 and worst_u < 1e-3, "(4a) vert channels -> COLOR / TEX_UV: worst colour err %.5f (tol %.5f), uv %.6f" % [worst_c, 1.0 / 255.0, worst_u])
	# corner uv: a seam splits the vertex
	var sq := KMesh.new().from_arrays(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(2, 0, 0), Vector3(2, 0, 1)]),
		[PackedInt32Array([0, 1, 2, 3]), PackedInt32Array([1, 4, 5, 2])])
	sq.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	var uvc := [Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0, 1), Vector2(0.6, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0.6, 1)]   # shared verts 1 and 2 get a different uv per face
	for i in 8:
		sq.set_attr("uv", i, uvc[i])
	var a2 := sq.to_array_mesh().surface_get_arrays(0)
	var p2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	var u2: PackedVector2Array = a2[Mesh.ARRAY_TEX_UV]
	var split_ok := p2.size() == 8 and u2.size() == 8
	var seam := 0
	if split_ok:
		for o in 8:
			if p2[o].is_equal_approx(Vector3(1, 0, 0)) and (u2[o].is_equal_approx(Vector2(0.5, 0)) or u2[o].is_equal_approx(Vector2(0.6, 0))):
				seam += 1
	ok(split_ok and seam == 2, "(4b) corner uv: seam vert splits into 2 output verts (%d verts, %d at the seam) each with its own uv" % [p2.size(), seam])
	# (5) save time, 200k grid
	var big := grid(446)
	var t_without := 1e12
	var t_with := 1e12
	var bp := "user://kmesh_attrs_big.kmesh"
	big.add_attr("mask", KMesh.AD_VERT, TYPE_FLOAT, 0.0)
	var md = big.attr_data("mask")
	for i in md.size():
		md[i] = float(i % 17) * 0.0625   # a painted weight map: few distinct values, as real masks are
	big.set_attr_data("mask", md)
	var with_attrs := big.attrs
	# interleaved A/B, minimum of 4 each: other processes load this machine, and a drift would otherwise land on one arm
	for rep in 4:
		for arm in 2:
			big.attrs = with_attrs if arm == 1 else {}
			var t0 := Time.get_ticks_usec()
			big.save(bp)
			var dt := float(Time.get_ticks_usec() - t0) / 1000.0
			if arm == 1:
				t_with = minf(t_with, dt)
			else:
				t_without = minf(t_without, dt)
	big.attrs = with_attrs
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bp))
	ok(t_with < t_without * 1.10, "(5) %d verts: save %.0f ms -> %.0f ms with 1 float/vert (+%.1f%%, bar 10)" % [big.vert_count(), t_without, t_with, (t_with / t_without - 1.0) * 100.0])
	print("KMESH ATTRS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
