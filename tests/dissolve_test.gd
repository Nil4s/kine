extends SceneTree
## B05 merge / dissolve / delete. Bars: (1) dissolving one cube edge: 8 verts, 11 edges, 5 faces (one hexagon + four
## quads), still closed and clean; with clean_verts the two ends go too: 6 verts, 9 edges, 5 faces (2 tris, 3 quads);
## (2) dissolving the 2x2 corner region of a 3x3 grid: 15 verts, 20 edges, 6 faces with one octagon, the 12 border edges
## kept; the 8 faces around the centre are refused (their border is two loops); (3) dissolve verts: the grid's interior
## vert -> its 4 faces become one octagon (15 verts, 6 faces); a border vert of valence 3 -> one pentagon (15, 8); the
## valence-2 corner -> its quad becomes a triangle (15, 9); (4) merge by distance: a cube of 6 separate quads (24 verts)
## welds to 8 verts / 12 edges, closed; only the selected verts: 4 of the doubles; (5) merge at centre: the cube's top 4
## verts -> 5 verts, 5 faces (a pyramid), the vert at (0.5, 0.5, 1); merge at first keeps vert 4 at (0, 0, 1);
## (6) delete: a face leaves a hole (4 border edges, report says only "holes"); a vert takes its 3 faces (7 verts,
## 6 border edges); an edge its 2 faces; only_faces keeps the corner vert a face delete drops; (7) undo / redo of a
## dissolve through KMeshUndo; (8) a face attribute follows a dissolve (the joined face takes the first face's value); (9) the preview
## cube keys: Delete a face (4 border edges), Ctrl+Z, Ctrl+Delete 2 faces, M 2 verts -> one, 2 undo steps
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
func cube() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), CF)
func grid() -> KMesh:   # 3x3 quads, 4x4 verts: vert (x, y) = y * 4 + x
	var v := PackedVector3Array()
	for y in 4:
		for x in 4:
			v.append(Vector3(x, y, 0))
	var f := []
	for y in 3:
		for x in 3:
			var i := y * 4 + x
			f.append([i, i + 1, i + 5, i + 4])
	return KMesh.new().from_arrays(v, f)
func sizes(m: KMesh) -> Array:
	var s := m.faces.map(func(f): return (f as PackedInt32Array).size())
	s.sort()
	return s
func clean(m: KMesh) -> bool:
	return KMeshValidate.report(m)["ok"] and m.is_closed() and m.is_manifold()
func kinds(m: KMesh) -> Array:
	return (KMeshValidate.report(m)["problems"] as Array).map(func(p): return p["kind"])
func counts(m: KMesh) -> String:
	return "%d verts %d edges %d faces %s" % [m.vert_count(), m.edge_count(), m.face_count(), str(sizes(m))]
func key(k: int, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e
func _init() -> void:
	# (1) cube edge 4-5: the top and the y = 0 side join
	var c := cube()
	var n := KMeshDissolve.dissolve_edges(c, [Vector2i(4, 5)])
	ok(n == 1 and c.vert_count() == 8 and c.edge_count() == 11 and c.face_count() == 5 and sizes(c) == [4, 4, 4, 4, 6] and clean(c), "(1) cube edge dissolved: %s, clean %s" % [counts(c), clean(c)])
	c = cube()
	KMeshDissolve.dissolve_edges(c, [Vector2i(4, 5)], true)
	ok(c.vert_count() == 6 and c.edge_count() == 9 and c.face_count() == 5 and sizes(c) == [3, 3, 4, 4, 4] and clean(c), "(1b) with clean_verts: %s" % counts(c))
	# (2) grid regions
	var g := grid()
	n = KMeshDissolve.dissolve_faces(g, [0, 1, 3, 4])
	ok(n == 3 and g.vert_count() == 15 and g.edge_count() == 20 and g.face_count() == 6 and sizes(g) == [4, 4, 4, 4, 4, 8] and g.boundary_edge_count() == 12 and kinds(g) == ["holes"], "(2) 2x2 of a 3x3 grid dissolved: %s, %d border edges, report %s" % [counts(g), g.boundary_edge_count(), str(kinds(g))])
	g = grid()
	n = KMeshDissolve.dissolve_faces(g, [0, 1, 2, 3, 5, 6, 7, 8])
	ok(n == 0 and g.face_count() == 9 and g.vert_count() == 16, "(2b) the ring of 8 round the centre is refused (two border loops): %s" % counts(g))
	# (3) dissolve verts
	g = grid()
	n = KMeshDissolve.dissolve_verts(g, [5])
	ok(n == 1 and g.vert_count() == 15 and g.face_count() == 6 and sizes(g) == [4, 4, 4, 4, 4, 8] and kinds(g) == ["holes"], "(3) interior vert: %s" % counts(g))
	g = grid()
	KMeshDissolve.dissolve_verts(g, [1])
	ok(g.vert_count() == 15 and g.face_count() == 8 and sizes(g) == [4, 4, 4, 4, 4, 4, 4, 5] and g.boundary_edge_count() == 11, "(3b) border vert of valence 3: %s, %d border edges" % [counts(g), g.boundary_edge_count()])
	g = grid()
	KMeshDissolve.dissolve_verts(g, [0])
	ok(g.vert_count() == 15 and g.face_count() == 9 and sizes(g) == [3, 4, 4, 4, 4, 4, 4, 4, 4] and kinds(g) == ["holes"], "(3c) valence-2 corner: %s" % counts(g))
	# (4) merge by distance on a cube of 6 loose quads
	var sv := PackedVector3Array()
	var sf := []
	for f in CF:
		var h := []
		for v in f:
			h.append(sv.size())
			sv.append(CV[v])
		sf.append(h)
	var s := KMesh.new().from_arrays(sv, sf)
	var before := "%d verts %d edges %d border edges" % [s.vert_count(), s.edge_count(), s.boundary_edge_count()]
	n = KMeshDissolve.merge_by_distance(s)
	ok(n == 16 and s.vert_count() == 8 and s.edge_count() == 12 and s.face_count() == 6 and clean(s), "(4) merge by distance: %s -> %s, %d went, clean %s" % [before, counts(s), n, clean(s)])
	s = KMesh.new().from_arrays(sv, sf)
	n = KMeshDissolve.merge_by_distance(s, KMeshDissolve.MERGE_DIST, [0, 1, 2, 3, 8, 9, 13, 16])   # bottom quad + its doubles round verts 0 / 1
	ok(n == 4 and s.vert_count() == 20, "(4b) only the selected verts: %d went, %d verts left" % [n, s.vert_count()])
	# (5) merge at centre / at first
	c = cube()
	var t := KMeshDissolve.merge(c, [4, 5, 6, 7], "centre")
	ok(c.vert_count() == 5 and c.face_count() == 5 and sizes(c) == [3, 3, 3, 3, 4] and c.verts[t].is_equal_approx(Vector3(0.5, 0.5, 1)) and clean(c), "(5) top merged at centre: %s, at %s" % [counts(c), str(c.verts[t])])
	c = cube()
	t = KMeshDissolve.merge(c, [4, 5, 6, 7], "first")
	ok(c.vert_count() == 5 and c.verts[t] == Vector3(0, 0, 1) and clean(c), "(5b) merged at first: %s, at %s" % [counts(c), str(c.verts[t])])
	# (6) delete
	c = cube()
	n = KMeshDissolve.delete(c, "faces", [1])
	ok(n == 1 and c.face_count() == 5 and c.vert_count() == 8 and c.boundary_edge_count() == 4 and kinds(c) == ["holes"], "(6) face deleted: %s, %d border edges, report %s" % [counts(c), c.boundary_edge_count(), str(kinds(c))])
	c = cube()
	n = KMeshDissolve.delete(c, "verts", [6])
	ok(n == 3 and c.vert_count() == 7 and c.face_count() == 3 and c.boundary_edge_count() == 6 and kinds(c) == ["holes"], "(6b) vert deleted: %s, %d border edges" % [counts(c), c.boundary_edge_count()])
	c = cube()
	n = KMeshDissolve.delete(c, "edges", [Vector2i(4, 5)])
	ok(n == 2 and c.vert_count() == 8 and c.face_count() == 4 and c.boundary_edge_count() == 6, "(6c) edge deleted: %s, %d border edges" % [counts(c), c.boundary_edge_count()])
	g = grid()
	KMeshDissolve.delete(g, "faces", [0])
	var g2 := grid()
	KMeshDissolve.delete(g2, "only_faces", [0])
	ok(g.vert_count() == 15 and g2.vert_count() == 16 and g2.face_count() == 8 and kinds(g2).has("loose"), "(6d) corner face: delete leaves %d verts, only faces %d (one loose)" % [g.vert_count(), g2.vert_count()])
	# (7) undo
	c = cube()
	var u := KMeshUndo.new()
	u.begin(c)
	KMeshDissolve.dissolve_edges(c, [Vector2i(4, 5)])
	var st := u.commit("dissolve edge")
	var after := counts(c)
	u.undo()
	var undone := counts(c)
	var back := clean(c) and c.face_count() == 6 and c.edge_count() == 12
	u.redo()
	ok(st.get("kind", "") == "topo" and back and c.face_count() == 5 and c.edge_count() == 11, "(7) undo: %s -> %s -> redo %s" % [after, undone, counts(c)])
	# (8) a face attribute through a dissolve
	c = cube()
	c.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	for i in 6:
		c.set_attr("mat", i, float(i))
	c.add_attr("w", KMesh.AD_VERT, TYPE_FLOAT, 0.0)
	for i in 8:
		c.set_attr("w", i, float(i) * 0.1)
	KMeshDissolve.dissolve_edges(c, [Vector2i(4, 5)])
	var mats := Array(c.attr_data("mat"))
	var ws := Array(c.attr_data("w"))
	ok(mats == [0.0, 1.0, 3.0, 4.0, 5.0] and ws.size() == 8 and is_equal_approx(ws[6], 0.6), "(8) face values after the dissolve %s, vert weights kept %d" % [str(mats), ws.size()])
	# (9) the keys on the model preview cube: Delete one face, Ctrl+Z, Ctrl+Delete two faces, M merges two neighbour verts into one
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	mn._kmesh_edit_start()
	var ui: KMeshEditUI = mn.kmed
	var f0: int = ui.mesh.face_count()
	var v0: int = ui.mesh.vert_count()
	ui.set_mode(KMeshSelect.FACE)
	ui.sel.faces[0] = true
	ui.input(key(KEY_DELETE))
	var f1: int = ui.mesh.face_count()
	var b1: int = ui.mesh.boundary_edge_count()
	ui.input(key(KEY_Z, true))
	var f2: int = ui.mesh.face_count()
	ui.sel.faces[0] = true
	ui.sel.faces[1] = true
	ui.input(key(KEY_DELETE, true))
	var f3: int = ui.mesh.face_count()
	ui.set_mode(KMeshSelect.VERT)
	ui.sel.verts[0] = true
	ui.sel.verts[1] = true
	ui.input(key(KEY_M))
	ok(f1 == f0 - 1 and b1 == 4 and f2 == f0 and f3 == f0 - 1 and ui.mesh.vert_count() == v0 - 1 and clean(ui.mesh) and ui.undo.steps.size() == 2, "(9) preview cube keys: %d faces, Delete -> %d (%d border edges), Ctrl+Z -> %d, Ctrl+Delete 2 -> %d, M -> %d verts (from %d), %d undo steps" % [f0, f1, b1, f2, f3, ui.mesh.vert_count(), v0, ui.undo.steps.size()])
	print("DISSOLVE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
