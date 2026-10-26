extends SceneTree
## A12 Catmull-Clark subdivision with creases. Bars (stated before measuring): (1) cube level 1 = 26 verts / 24 faces,
## level 2 = 98 / 96, all quads; (2) the side-2 cube's corner (1,1,1) goes to (5/9, 5/9, 5/9) at level 1 (Catmull-Clark
## 1978: (Q + 2R + (n-3)S) / n with Q = 1/3, R = 2/3, n = 3), an edge point (1,1,0) to (3/4, 3/4, 0), a face point stays
## (1,0,0), tol 1e-6; (3) closed stays closed and manifold, Euler 2, at levels 1-3; (4) a fully creased cube (INF) keeps its
## 8 corners exactly and every vertex stays on the cube's surface; (5) semi-sharp: sharpness 1 at level 2 = a sharp level
## then a smooth one (tol 1e-6), and lies between all-smooth and all-sharp; the "crease" edge channel is read and goes
## down by 1; (6) a 4x4 plane: boundary vertices stay on the boundary, the 4 corners stay put, and the flat grid is
## reproduced exactly (vert "weight" = x and corner "uv" = (x, z) after subdividing, tol 1e-6); (7) n-gons: a pentagonal
## prism level 1 has as many quads as corners (5*2 + 4*5 = 30), closed and manifold; (8) a ~10k-face cube level 1 in under
## 3000 ms (4 shared cores) and the input mesh is untouched; (9) the Model command subdivides the test cube in one undo step
## and Ctrl+Z restores it.
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
const CV := [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
func cube() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), CF)
func near(m: KMesh, p: Vector3, tol := 1e-6) -> bool:
	for v in m.verts:
		if v.distance_to(p) < tol:
			return true
	return false
func all_quads(m: KMesh) -> bool:
	for f in m.faces:
		if (f as PackedInt32Array).size() != 4:
			return false
	return true
## the farthest any vertex of a is from the nearest of b (vertex order may differ between the two)
func max_diff(a: KMesh, b: KMesh) -> float:
	if a.vert_count() != b.vert_count():
		return INF
	var d := 0.0
	for p in a.verts:
		var best := INF
		for q in b.verts:
			best = minf(best, p.distance_to(q))
		d = maxf(d, best)
	return d
func _init() -> void:
	var c := cube()
	var l1 := KMeshSubdiv.subdivide(c, 1)
	var l2 := KMeshSubdiv.subdivide(c, 2)
	ok(l1.vert_count() == 26 and l1.face_count() == 24 and l2.vert_count() == 98 and l2.face_count() == 96 and all_quads(l2),
		"(1) cube: level 1 %d verts / %d faces, level 2 %d / %d, all quads" % [l1.vert_count(), l1.face_count(), l2.vert_count(), l2.face_count()])
	var k := 5.0 / 9.0
	ok(l1.verts[6].distance_to(Vector3(k, k, k)) < 1e-6 and near(l1, Vector3(0.75, 0.75, 0)) and near(l1, Vector3(1, 0, 0)) and near(l1, Vector3(-k, -k, -k)),
		"(2) corner (1,1,1) -> %s (5/9 = %.6f), edge point (0.75, 0.75, 0) and face point (1, 0, 0) found" % [str(l1.verts[6]), k])
	var closed := true
	var info := ""
	for lv in [1, 2, 3]:
		var s := KMeshSubdiv.subdivide(c, lv)
		closed = closed and s.is_closed() and s.is_manifold() and s.euler() == 2
		info += "L%d %d faces closed %s manifold %s euler %d; " % [lv, s.face_count(), s.is_closed(), s.is_manifold(), s.euler()]
	ok(closed, "(3) " + info)
	var sh := KMeshSubdiv.subdivide(c, 2, INF)
	var corners := true
	for p in CV:
		corners = corners and near(sh, p, 1e-9)
	var on_box := true
	for v in sh.verts:
		on_box = on_box and absf(maxf(absf(v.x), maxf(absf(v.y), absf(v.z))) - 1.0) < 1e-6
	ok(corners and on_box and sh.is_closed(), "(4) fully creased cube level 2: 8 corners kept %s, all %d verts on the cube %s" % [corners, sh.vert_count(), on_box])
	var semi := KMeshSubdiv.subdivide(c, 2, 1.0)
	var two := KMeshSubdiv.subdivide(KMeshSubdiv.subdivide(c, 1, INF), 1, 0.0)
	var cr := cube()
	cr.add_attr("crease", KMesh.AD_EDGE, TYPE_FLOAT, 1.0)
	var via := KMeshSubdiv.subdivide(cr, 1)
	var cmax := 0.0
	for x in via.attr_data("crease"):
		cmax = maxf(cmax, x)
	var r_semi := semi.verts[6].length()
	var r_sm := l2.verts[6].length()
	var r_sh := sh.verts[6].length()
	ok(max_diff(semi, two) < 1e-6 and r_sm < r_semi and r_semi < r_sh and max_diff(KMeshSubdiv.subdivide(cr, 2), semi) < 1e-6 and cmax == 0.0 and via.attr_data("crease").size() == via.edge_count(),
		"(5) sharpness 1 at level 2 = sharp then smooth (diff %.9f); corner radius smooth %.4f < semi %.4f < sharp %.4f; crease channel read, children %.1f" % [max_diff(semi, two), r_sm, r_semi, r_sh, cmax])
	var n := 4
	var pv := PackedVector3Array()
	var pf: Array = []
	for j in n + 1:
		for i in n + 1:
			pv.append(Vector3(i, 0, j))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			pf.append([a, a + n + 1, a + n + 2, a + 1])
	var pl := KMesh.new().from_arrays(pv, pf)
	pl.add_attr("weight", KMesh.AD_VERT, TYPE_FLOAT, 0.0)
	pl.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2, Vector2.ZERO)
	pl.add_attr("tag", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	for i in pv.size():
		pl.set_attr("weight", i, pv[i].x)
	for f in pl.face_count():
		pl.set_attr("tag", f, float(f))
		for i in 4:
			var p := pv[pl.faces[f][i]]
			pl.set_attr("uv", pl.face_he0[f] + i, Vector2(p.x, p.z))
	var ps := KMeshSubdiv.subdivide(pl, 2)
	var on_b := true
	for i in pv.size():
		var p := pv[i]
		if p.x == 0 or p.z == 0 or p.x == n or p.z == n:
			var q := ps.verts[i]
			on_b = on_b and (absf(q.x) < 1e-6 or absf(q.z) < 1e-6 or absf(q.x - n) < 1e-6 or absf(q.z - n) < 1e-6)
	for h in ps.he_twin.size():
		if ps.he_twin[h] == -1:
			var q := ps.verts[ps.he_vert[h]]
			on_b = on_b and (absf(q.x) < 1e-6 or absf(q.z) < 1e-6 or absf(q.x - n) < 1e-6 or absf(q.z - n) < 1e-6)
	var cs: bool = ps.verts[0] == pv[0] and ps.verts[n] == pv[n] and ps.verts[n * (n + 1)] == pv[n * (n + 1)] and ps.verts[pv.size() - 1] == pv[pv.size() - 1]
	var lin := 0.0
	for i in ps.vert_count():
		lin = maxf(lin, absf(ps.get_attr("weight", i) - ps.verts[i].x) + absf(ps.verts[i].y))
	for f in ps.face_count():
		for i in 4:
			var p := ps.verts[ps.faces[f][i]]
			lin = maxf(lin, (ps.get_attr("uv", ps.face_he0[f] + i) as Vector2).distance_to(Vector2(p.x, p.z)))
	var tag_ok: bool = ps.attr_data("tag").size() == ps.face_count() and ps.get_attr("tag", 16 * 5) == 5.0
	ok(on_b and cs and lin < 1e-6 and tag_ok and ps.boundary_edge_count() == 4 * n * 4,
		"(6) plane level 2: boundary stays on the boundary %s (%d boundary edges), corners put %s, weight / uv linear (err %.9f), face tag inherited %s" % [on_b, ps.boundary_edge_count(), cs, lin, tag_ok])
	var gv := PackedVector3Array()
	for z in [0.0, 1.0]:
		for i in 5:
			gv.append(Vector3(cos(TAU * i / 5.0), z, sin(TAU * i / 5.0)))
	var gf: Array = [[4, 3, 2, 1, 0], [5, 6, 7, 8, 9]]
	for i in 5:
		var j := (i + 1) % 5
		gf.append([i, j, j + 5, i + 5])
	var pr := KMesh.new().from_arrays(gv, gf)
	var p1 := KMeshSubdiv.subdivide(pr, 1)
	ok(pr.is_closed() and p1.face_count() == 30 and all_quads(p1) and p1.is_closed() and p1.is_manifold() and p1.euler() == 2,
		"(7) pentagonal prism level 1: %d quads, closed %s manifold %s" % [p1.face_count(), p1.is_closed(), p1.is_manifold()])
	var big := KMeshView.make_cube(1.0, 41)
	var before := big.verts.duplicate()
	var t0 := Time.get_ticks_msec()
	var bs := KMeshSubdiv.subdivide(big, 1)
	var ms := Time.get_ticks_msec() - t0
	ok(ms < 3000 and bs.face_count() == big.face_count() * 4 and bs.is_closed() and big.verts == before,
		"(8) %d faces -> %d in %d ms, input untouched %s" % [big.face_count(), bs.face_count(), ms, big.verts == before])
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._kmesh_subdivide()
	var f1: int = m.kmed.mesh.face_count()
	var steps: int = m.kmed.undo.steps.size()
	var cl: bool = m.kmed.mesh.is_closed()
	var z := InputEventKey.new()
	z.keycode = KEY_Z
	z.ctrl_pressed = true
	z.pressed = true
	var used: bool = m.kmed.input(z)
	var f0: int = m.kmed.mesh.face_count()
	await process_frame
	ok(f1 == 96 * 4 and cl and steps == 1 and used and f0 == 96, "(9) Model: subdivide the test cube: 96 -> %d faces (closed %s) in %d undo step, Ctrl+Z back to %d" % [f1, cl, steps, f0])
	print("SUBDIV ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
