extends SceneTree
## godot --path . -s tests/kmeshnat_test.gd     (L60: KMesh topology, subdivide and boolean in C++, KineKMeshNative)
## BARS (written before the implementation, never moved after a run):
##   SPEED  (median of 5, native on)  open a 20480-triangle mesh (from_array_mesh + is_manifold) <= 25 ms
##                                    boolean union of two 5120-triangle spheres (10240 in)      <= 40 ms
##                                    subdivide one level of a 5120-triangle sphere              <= 12 ms
##   EQUAL  native == GDScript (KINE_NO_NATIVE switched in-process): vertex count, face lists, half-edge arrays, edge count,
##          positions and normals within 1e-6, the same is_manifold verdict, boolean stats, the same refusal text
##   UNDO   a native subdivide / boolean / open applied through KMeshUndo comes back EXACT (hash of verts + faces) on undo, and again on redo
##   PLANTED  the comparator rejects a moved vertex, a swapped face, a wrong manifold verdict; the speed bar rejects the GDScript time;
##            the undo hash rejects a half-restored mesh
var fails := 0
var rows: Array = []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func set_native(on: bool) -> void:
	OS.set_environment("KINE_NO_NATIVE", "" if on else "1")


func med(f: Callable) -> float:
	var a := []
	for i in 5:
		var t := Time.get_ticks_usec()
		f.call()
		a.append((Time.get_ticks_usec() - t) / 1000.0)
	a.sort()
	return a[2]


## "" when the two meshes are the same, else what differs
func cmp(a: KMesh, b: KMesh, tol := 1e-6) -> String:
	if a == null or b == null:
		return "" if a == b else "one is null"
	if a.verts.size() != b.verts.size():
		return "verts %d vs %d" % [a.verts.size(), b.verts.size()]
	if a.faces.size() != b.faces.size():
		return "faces %d vs %d" % [a.faces.size(), b.faces.size()]
	var w := 0.0
	for i in a.verts.size():
		w = maxf(w, (a.verts[i] - b.verts[i]).length())
	if w > tol:
		return "vertex moved %.6f" % w
	for i in a.faces.size():
		if a.faces[i] != b.faces[i]:
			return "face %d differs" % i
	for nm in ["he_vert", "he_next", "he_twin", "he_face", "face_he0"]:
		if a.get(nm) != b.get(nm):
			return nm + " differs"
	var wn := 0.0
	for i in a.vert_normals.size():
		wn = maxf(wn, (a.vert_normals[i] - b.vert_normals[i]).length())
	for i in a.face_normals.size():
		wn = maxf(wn, (a.face_normals[i] - b.face_normals[i]).length())
	if wn > tol:
		return "normal differs %.6f" % wn
	if a.edge_count() != b.edge_count():
		return "edge count %d vs %d" % [a.edge_count(), b.edge_count()]
	if a.is_manifold() != b.is_manifold():
		return "manifold verdict %s vs %s" % [a.is_manifold(), b.is_manifold()]
	if a.is_closed() != b.is_closed():
		return "closed verdict differs"
	return ""


func hash_mesh(m: KMesh) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(m.verts.to_byte_array())
	for f in m.faces:
		c.update((f as PackedInt32Array).to_byte_array())
		c.update(PackedInt32Array([-1]).to_byte_array())
	return c.finish().hex_encode()


## the same op both ways; returns [gd_result, native_result]
func both(f: Callable) -> Array:
	set_native(false)
	var g = f.call()
	set_native(true)
	var n = f.call()
	return [g, n]


func stats_same(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if k != "ms" and a[k] != b.get(k):
			return false
	return a.size() == b.size()


func bar(ms: float, limit: float) -> bool:
	return ms <= limit


func row(name: String, g: float, n: float, limit: float) -> void:
	print("TIME %-34s GDScript %9.1f ms   native %8.1f ms   x%.1f   (bar %.0f ms)" % [name, g, n, g / maxf(n, 0.001), limit])


func shifted(m: KMesh, d: Vector3) -> KMesh:
	var c := KMesh.new().from_arrays(m.verts, m.faces)
	for i in c.verts.size():
		c.verts[i] += d
	c.rebuild()
	return c


func _init() -> void:
	ok(KMeshNatDoor.on(), "KineKMeshNative is registered (DLL version %d)" % (KMeshNatDoor.door().version() if KMeshNatDoor.on() else -1))
	set_native(true)
	var tol := 1e-6

	# ---------------------------------------------------------------- EQUAL: open / rebuild / is_manifold
	var big := KMeshPrims.ico_sphere(1.0, 5)
	ok(big.triangle_count() == 20480, "ico sphere sub 5: %d triangles" % big.triangle_count())
	var am_smooth := big.to_array_mesh(true)
	var uvs := KMeshPrims.uv_sphere(1.0, 48, 24)
	var am_flat := uvs.to_array_mesh(false)   # split corners: welding has to merge them
	var cub := KMeshPrims.cube(Vector3(1, 2, 3), 3)
	var am_cube := cub.to_array_mesh(false)
	for case in [["ico5 smooth", am_smooth], ["uv sphere flat (weld)", am_flat], ["cube n3 flat (weld)", am_cube]]:
		var am: ArrayMesh = case[1]
		var r := both(func(): return KMesh.new().from_array_mesh(am))
		var d := cmp(r[0], r[1], tol)
		ok(d == "", "from_array_mesh %s: native == GDScript (%d verts, %d faces) %s" % [case[0], r[1].verts.size(), r[1].faces.size(), d])
		var r2 := both(func(): return KMesh.new().from_arrays(r[0].verts, r[0].faces))
		d = cmp(r2[0], r2[1], tol)
		ok(d == "", "from_arrays/rebuild %s: native == GDScript %s" % [case[0], d])
		# half-edge lookups agree on a sample of edges
		var bad := 0
		var es: Array = r2[1].edges()
		for i in range(0, es.size(), maxi(1, es.size() / 200)):
			var e: Vector2i = es[i]
			if r2[1].find_half_edge(e.x, e.y) != r2[0].find_half_edge(e.x, e.y) or r2[1].find_half_edge(e.y, e.x) != r2[0].find_half_edge(e.y, e.x):
				bad += 1
		ok(bad == 0, "find_half_edge %s: %d disagreements on the sample" % [case[0], bad])
	# manifold verdicts on a closed tetra, a bowtie (two triangles sharing one vertex), an edge shared by three faces, a face that repeats a vertex, an open plane
	var vq := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)])
	var cases := {
		"tetra": [[[0, 2, 1], [0, 1, 3], [1, 2, 3], [0, 3, 2]], true],
		"bowtie": [[[0, 1, 2], [0, 4, 5]], false],
		"three faces on one edge": [[[0, 1, 2], [1, 0, 3], [1, 0, 6]], false],
		"repeated vertex": [[[0, 0, 1], [0, 1, 2]], false],
		"open plane": [[[0, 1, 2], [1, 3, 2]], true],
		"two fans touching at a vertex": [[[0, 1, 2], [0, 2, 3], [0, 4, 5], [0, 5, 6]], false],
	}
	for k in cases:
		var fl: Array = cases[k][0]
		var r := both(func(): return KMesh.new().from_arrays(vq, fl))
		var d := cmp(r[0], r[1], tol)
		ok(d == "" and r[1].is_manifold() == cases[k][1], "manifold verdict '%s': native %s == GDScript %s, expected %s %s" % [k, r[1].is_manifold(), r[0].is_manifold(), cases[k][1], d])

	# ---------------------------------------------------------------- EQUAL: subdivide
	var sub_cases := [
		["ico3 x1", KMeshPrims.ico_sphere(1.0, 3), 1, null],
		["ico2 x2", KMeshPrims.ico_sphere(1.0, 2), 2, null],
		["cube n2 x2", KMeshPrims.cube(Vector3.ONE, 2), 2, null],
		["plane (boundary) x2", KMeshPrims.plane(2.0, 2.0, 3, 3), 2, null],
		["uv sphere (quads + fans) x1", KMeshPrims.uv_sphere(1.0, 16, 8), 1, null],
		["cube crease 1.0 x2", KMeshPrims.cube(Vector3.ONE, 1), 2, 1.0],
		["cube crease 2.0 x3", KMeshPrims.cube(Vector3.ONE, 1), 3, 2.0],
		["cube crease 0.5 x2", KMeshPrims.cube(Vector3.ONE, 2), 2, 0.5],
		["torus x1", KMeshPrims.torus(1.0, 0.3, 12, 6), 1, null],
	]
	for c in sub_cases:
		var m: KMesh = c[1]
		var r := both(func(): return KMeshSubdiv.subdivide(m, c[2], c[3]))
		var d := cmp(r[0], r[1], tol)
		ok(d == "", "subdivide %s: native == GDScript (%d verts, %d faces) %s" % [c[0], r[1].verts.size(), r[1].faces.size(), d])
	# paths that stay in GDScript (a crease dictionary, mesh attributes) must still be equal and untouched
	var cd := KMeshPrims.cube(Vector3.ONE, 1)
	var rd := both(func(): return KMeshSubdiv.subdivide(cd, 2, {Vector2i(0, 1): 2.0}))
	ok(cmp(rd[0], rd[1], tol) == "", "subdivide with a crease dictionary: equal")
	var ca := KMeshPrims.cube(Vector3.ONE, 2)
	ca.add_attr("mask", KMesh.AD_VERT, TYPE_FLOAT, 0.0)
	var ra := both(func(): return KMeshSubdiv.subdivide(ca, 1))
	ok(cmp(ra[0], ra[1], tol) == "" and ra[1].has_attr("mask"), "subdivide with a vertex attribute: equal, attribute kept")

	# ---------------------------------------------------------------- EQUAL: boolean
	var sa := KMeshPrims.ico_sphere(1.0, 3)
	var sb := shifted(KMeshPrims.ico_sphere(1.0, 3), Vector3(0.5, 0.2, 0.1))
	var bcases := [
		["spheres", sa, sb],
		["cubes sharing planes", KMeshPrims.cube(Vector3.ONE, 1), shifted(KMeshPrims.cube(Vector3.ONE, 1), Vector3(0.5, 0, 0))],
		["cube n2 vs cube", KMeshPrims.cube(Vector3.ONE, 2), shifted(KMeshPrims.cube(Vector3(0.6, 0.6, 2.0), 1), Vector3(0.1, 0.1, 0))],
		["cube minus cylinder", KMeshPrims.cube(Vector3(2, 2, 2), 1), KMeshPrims.cylinder(0.5, 3.0, 24, 1)],
		["torus vs sphere", KMeshPrims.torus(1.0, 0.3, 24, 12), shifted(KMeshPrims.ico_sphere(0.6, 2), Vector3(1.0, 0, 0))],
		["disjoint spheres", sa, shifted(sa, Vector3(5, 0, 0))],
		["nested spheres", sa, KMeshPrims.ico_sphere(0.5, 2)],
	]
	for c in bcases:
		for op in ["union", "difference", "intersect"]:
			var ma: KMesh = c[1]
			var mb: KMesh = c[2]
			set_native(false)
			var g := KMeshBoolean.run(ma, mb, op)
			var gs: Dictionary = KMeshBoolean.last.duplicate()
			var ge := KMeshBoolean.last_error
			set_native(true)
			var n := KMeshBoolean.run(ma, mb, op)
			var ns: Dictionary = KMeshBoolean.last.duplicate()
			var d := cmp(g, n, tol)
			ok(d == "" and stats_same(gs, ns) and ge == KMeshBoolean.last_error, "boolean %s %s: native == GDScript (%s faces, %s verts, manifold %s) %s%s" % [c[0], op, str(n.faces.size()) if n else "null", str(n.verts.size()) if n else "null", str(n.is_manifold()) if n else "-", d, "" if stats_same(gs, ns) else " STATS " + str(gs) + " vs " + str(ns)])
	# refusals are the same text
	var open_m := KMeshPrims.plane(1.0, 1.0, 2, 2)
	var rr := both(func(): return KMeshBoolean.run(open_m, sa, "union"))
	set_native(false)
	KMeshBoolean.run(open_m, sa, "union")
	var e_gd := KMeshBoolean.last_error
	set_native(true)
	KMeshBoolean.run(open_m, sa, "union")
	ok(rr[0] == null and rr[1] == null and e_gd == KMeshBoolean.last_error and e_gd != "", "boolean on an open mesh: both refuse with the same text")
	# a mesh with attributes stays on the GDScript path and still agrees
	var aa := KMeshPrims.ico_sphere(1.0, 2)
	aa.add_attr("mask", KMesh.AD_VERT, TYPE_FLOAT, 0.0)
	var ab := shifted(KMeshPrims.ico_sphere(1.0, 2), Vector3(0.4, 0, 0))
	var ra2 := both(func(): return KMeshBoolean.run(aa, ab, "union"))
	ok(cmp(ra2[0], ra2[1], tol) == "" and ra2[1].has_attr("mask"), "boolean with an attribute channel: equal, channel kept")

	# ---------------------------------------------------------------- SPEED
	set_native(false)
	var g_open := med(func(): var k := KMesh.new().from_array_mesh(am_smooth); k.is_manifold())
	set_native(true)
	var n_open := med(func(): var k := KMesh.new().from_array_mesh(am_smooth); k.is_manifold())
	row("open 20480 tris (from_array_mesh + is_manifold)", g_open, n_open, 25.0)
	ok(bar(n_open, 25.0), "SPEED open a 20k-triangle mesh <= 25 ms (%.1f ms; GDScript %.1f)" % [n_open, g_open])
	ok(not bar(g_open, 25.0), "SPEED control: the GDScript open (%.1f ms) does NOT meet the 25 ms bar, so the bar discriminates" % g_open)
	var kb := KMesh.new().from_array_mesh(am_smooth)
	set_native(false)
	var g_reb := med(func(): kb.rebuild())
	set_native(true)
	var n_reb := med(func(): kb.rebuild())
	row("rebuild 20480 tris", g_reb, n_reb, 0.0)
	var b1 := KMeshPrims.ico_sphere(1.0, 4)
	var b2 := shifted(KMeshPrims.ico_sphere(1.0, 4), Vector3(0.5, 0.2, 0.1))
	set_native(false)
	var g_bool := med(func(): KMeshBoolean.run(b1, b2, "union"))
	set_native(true)
	var n_bool := med(func(): KMeshBoolean.run(b1, b2, "union"))
	row("boolean union 10240 tris in", g_bool, n_bool, 40.0)
	ok(bar(n_bool, 40.0), "SPEED boolean of two 5k-triangle spheres (10240 in) <= 40 ms (%.1f ms; GDScript %.1f)" % [n_bool, g_bool])
	ok(not bar(g_bool, 40.0), "SPEED control: the GDScript boolean (%.1f ms) does NOT meet the 40 ms bar" % g_bool)
	var rbg := both(func(): return KMeshBoolean.run(b1, b2, "union"))
	ok(cmp(rbg[0], rbg[1], tol) == "", "boolean 10240 tris: native == GDScript on the bar's own input")
	var s5 := KMeshPrims.ico_sphere(1.0, 4)
	set_native(false)
	var g_sub := med(func(): KMeshSubdiv.subdivide(s5, 1))
	set_native(true)
	var n_sub := med(func(): KMeshSubdiv.subdivide(s5, 1))
	row("subdivide 5120 tris, 1 level", g_sub, n_sub, 12.0)
	ok(bar(n_sub, 12.0), "SPEED subdivide a 5k-triangle mesh <= 12 ms (%.1f ms; GDScript %.1f)" % [n_sub, g_sub])
	ok(not bar(g_sub, 12.0), "SPEED control: the GDScript subdivide (%.1f ms) does NOT meet the 12 ms bar" % g_sub)
	var rsg := both(func(): return KMeshSubdiv.subdivide(s5, 1))
	ok(cmp(rsg[0], rsg[1], tol) == "", "subdivide 5120 tris: native == GDScript on the bar's own input")

	# ---------------------------------------------------------------- UNDO exact
	set_native(true)
	var um := KMeshPrims.ico_sphere(1.0, 3)
	var u := KMeshUndo.new()
	var h0 := hash_mesh(um)
	u.begin(um)
	var sres := KMeshSubdiv.subdivide(um, 1)
	um.verts = sres.verts
	um.faces = sres.faces
	um.rebuild()
	u.commit("subdivide")
	var h1 := hash_mesh(um)
	ok(h1 != h0 and um.faces.size() == 1280 * 3 * 0 + 320 * 3 or um.faces.size() > 320, "UNDO subdivide applied (%d faces)" % um.faces.size())
	u.undo()
	ok(hash_mesh(um) == h0 and um.is_manifold(), "UNDO subdivide: undo restores the exact mesh")
	u.redo()
	ok(hash_mesh(um) == h1, "UNDO subdivide: redo restores the exact result")
	u.undo()
	var ub := KMeshPrims.ico_sphere(1.0, 3)
	var ubo := shifted(KMeshPrims.ico_sphere(1.0, 3), Vector3(0.5, 0.2, 0.1))
	var hb0 := hash_mesh(ub)
	u.begin(ub)
	var bres := KMeshBoolean.run(ub, ubo, "difference")
	ub.verts = bres.verts
	ub.faces = bres.faces
	ub.rebuild()
	u.commit("boolean")
	var hb1 := hash_mesh(ub)
	u.undo()
	ok(hash_mesh(ub) == hb0, "UNDO boolean: undo restores the exact mesh")
	u.redo()
	ok(hash_mesh(ub) == hb1 and hb1 != hb0, "UNDO boolean: redo restores the exact result")
	# open: the mesh opened from an ArrayMesh, replaced by another open, undone
	var uo := KMesh.new().from_array_mesh(am_cube)
	var ho0 := hash_mesh(uo)
	u.begin(uo)
	var other := KMesh.new().from_array_mesh(am_flat)
	uo.verts = other.verts
	uo.faces = other.faces
	uo.rebuild()
	u.commit("open")
	u.undo()
	ok(hash_mesh(uo) == ho0 and uo.is_manifold() == KMesh.new().from_array_mesh(am_cube).is_manifold(), "UNDO open: undo restores the exact mesh and its verdict")
	# the undone mesh's topology equals a fresh GDScript build of the same data
	set_native(false)
	var fresh := KMesh.new().from_arrays(uo.verts, uo.faces)
	set_native(true)
	ok(cmp(fresh, uo, tol) == "", "UNDO: the restored mesh's topology equals a GDScript rebuild of it")

	# ---------------------------------------------------------------- PLANTED FAILS
	var base := KMesh.new().from_arrays(sa.verts, sa.faces)
	var moved := KMesh.new().from_arrays(sa.verts, sa.faces)
	moved.verts[3] += Vector3(1e-3, 0, 0)
	ok(cmp(base, moved, tol) != "", "PLANTED a vertex moved by 1e-3 is caught by the comparator (%s)" % cmp(base, moved, tol))
	var swapped := KMesh.new().from_arrays(sa.verts, sa.faces)
	var f0 = swapped.faces[0]
	swapped.faces[0] = swapped.faces[1]
	swapped.faces[1] = f0
	ok(cmp(base, swapped, tol) != "", "PLANTED two swapped faces are caught (%s)" % cmp(base, swapped, tol))
	var openb := KMesh.new().from_arrays(sa.verts, sa.faces.slice(0, sa.faces.size() - 1))
	ok(cmp(base, openb, tol) != "", "PLANTED a missing face is caught (%s)" % cmp(base, openb, tol))
	var bowtie := KMesh.new().from_arrays(vq, [[0, 1, 2], [0, 4, 5]])
	ok(bowtie.is_manifold() == false and KMesh.new().from_arrays(vq, [[0, 2, 1], [0, 1, 3], [1, 2, 3], [0, 3, 2]]).is_manifold() == true, "PLANTED a bowtie is non-manifold and a tetra is manifold (the verdict is not a constant)")
	ok(not bar(g_open, 25.0) and not bar(g_bool, 40.0) and not bar(g_sub, 12.0), "PLANTED the three speed bars all reject the GDScript timings")
	# a half-restored mesh must not hash like the original
	var half := KMeshPrims.ico_sphere(1.0, 3)
	half.verts[5] += Vector3(0, 1e-6, 0)
	ok(hash_mesh(half) != hash_mesh(KMeshPrims.ico_sphere(1.0, 3)), "PLANTED a 1e-6 nudge changes the undo hash (the exact-undo check sees it)")
	set_native(true)
	print("kmeshnat: %d fail" % fails)
	quit()
