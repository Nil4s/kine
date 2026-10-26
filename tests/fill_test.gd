extends SceneTree
## B06 fill / grid fill / make face (scripts/kmesh_fill.gd). Bars: (1) a unit cube with its top face deleted: F on the 4
## hole verts closes it back to 8 verts / 6 faces, closed, manifold, validate clean, volume 1 m^3, the new face's normal
## . the old one > 0.99 and its centre where the old face's was; the same on the preview's 4x4 test cube (from a KMeshSelect,
## verts given in a scrambled order) and from a closed edge loop in edge mode; (2) 2 verts on one quad -> an edge: the quad
## split in 2 triangles, both facing +z; 2 verts with no shared face, or already joined, are refused with the reason;
## (3) 4 loose verts picked in a scrambled order -> one convex quad (every corner turns the same way) facing away from the
## mesh; 4 verts of an existing face are refused; (4) Alt+F across 2 holes (top and bottom of a cube deleted, one vert of
## each selected): +2 faces, clean, volume 1; triangulated: +4 triangles, clean, volume 1; ear clip of a concave L
## (6 verts): 4 triangles, total area exactly 3, every one facing the L's normal; (5) Ctrl+F grid fill of the 16-vert hole
## left by deleting a 4x4 side of a cube: 16 quads, 9 new verts, every quad 0.0625 m^2 (no zero-area face), flat on
## the side, clean, volume 1; span 2: 12 quads, 5 new verts, clean; a 16-sided cylinder's cap: 16 quads, smallest area
## > 0, volume = the 16-gon x height; an odd (3-vert) border refused; (6) attributes kept and undo / redo one "topo" step;
## (7) the preview keys: Delete a face, F closes it, Ctrl+Z, Alt+F, Ctrl+Z, Ctrl+F; one undo step each; the S box row.
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
func cube() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), CF)
func clean(m: KMesh) -> bool:
	return m.is_closed() and m.is_manifold() and KMeshValidate.report(m)["ok"]
func kinds(m: KMesh) -> Array:
	return (KMeshValidate.report(m)["problems"] as Array).map(func(p): return "%s x%d" % [p["kind"], p["count"]])
func area(m: KMesh, fi: int) -> float:
	return m._newell(fi).length() * 0.5
func vol(m: KMesh) -> float:
	return KMeshValidate._volume(m)
func _init() -> void:
	# (1a) unit cube, top face deleted, F on its verts
	var c := cube()
	var old_n: Vector3 = c.face_normals[1]
	var old_c := c.face_center(1)
	KMeshDissolve.delete(c, "only_faces", [1])
	var holed := not c.is_closed() and c.boundary_edge_count() == 4
	var r := KMeshFill.make_face(c, [6, 4, 7, 5])
	var nf: int = r["faces"][0] if r["error"] == "" else 0
	var dn: float = c.face_normals[nf].dot(old_n)
	var dc := c.face_center(nf).distance_to(old_c)
	ok(holed and r["error"] == "" and c.vert_count() == 8 and c.face_count() == 6 and clean(c) and dn > 0.99 and dc < 1e-6 and absf(vol(c) - 1.0) < 1e-9,
		"(1a) cube top deleted (%d border edges), F: %d verts %d faces, clean %s %s, normal . old %.4f, centre off by %.9f m, volume %.4f m^3 %s" % [4 if holed else -1, c.vert_count(), c.face_count(), clean(c), str(kinds(c)), dn, dc, vol(c), r["error"]])
	# (1b) the preview's test cube (4x4 per side), a face deleted, F from a KMeshSelect
	var t := KMeshView.make_cube(0.6, 4)
	var nf0 := t.face_count()
	var tf := 37
	var t_n: Vector3 = t.face_normals[tf]
	var t_c := t.face_center(tf)
	var hole_v: Array = Array(t.faces[tf] as PackedInt32Array)
	KMeshDissolve.delete(t, "only_faces", [tf])
	var ts := KMeshSelect.new(t, KMeshSelect.VERT)
	for v in [hole_v[2], hole_v[0], hole_v[3], hole_v[1]]:
		ts.verts[v] = true
	var tr := KMeshFill.fill(t, ts, "face")
	var tn: int = tr["faces"][0] if tr["error"] == "" else 0
	ok(tr["error"] == "" and t.face_count() == nf0 and clean(t) and t.face_normals[tn].dot(t_n) > 0.99 and t.face_center(tn).distance_to(t_c) < 1e-6 and absf(vol(t) - 0.216) < 1e-6,
		"(1b) test cube face %d deleted, F on its 4 verts: %d faces (was %d), clean %s %s, normal . old %.4f, centre off %.9f m, volume %.4f m^3" % [tf, t.face_count(), nf0, clean(t), str(kinds(t)), t.face_normals[tn].dot(t_n), t.face_center(tn).distance_to(t_c), vol(t)])
	# (1c) from a closed edge loop (edge mode)
	var ce := cube()
	KMeshDissolve.delete(ce, "only_faces", [0])
	var es := KMeshSelect.new(ce, KMeshSelect.EDGE)
	for e in [Vector2i(0, 3), Vector2i(2, 3), Vector2i(1, 2), Vector2i(0, 1)]:
		es.edges[e] = true
	var er := KMeshFill.fill(ce, es, "face")
	ok(er["error"] == "" and clean(ce) and ce.face_normals[er["faces"][0]].dot(Vector3(0, 0, -1)) > 0.99 and es.mode == KMeshSelect.EDGE and es.edges.size() == 4,
		"(1c) edge loop of the deleted bottom, F: clean %s, normal z %.4f, 4 edges selected %s %s" % [clean(ce), ce.face_normals[er["faces"][0]].z if er["error"] == "" else 0.0, es.edges.size() == 4, er["error"]])
	# (2) 2 verts -> an edge
	var pl := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(3,0,0), Vector3(4,0,0), Vector3(4,1,0)]), [[0,1,2,3], [4,5,6]])
	var pr := KMeshFill.make_face(pl, [0, 2])
	var both := pl.face_count() == 3 and pl.face_normals[0].z > 0.999 and pl.face_normals[2].z > 0.999 and (pl.faces[0] as PackedInt32Array).size() == 3
	var no_face := KMeshFill.make_face(pl, [1, 4])
	var joined := KMeshFill.make_face(pl, [0, 1])
	ok(pr["error"] == "" and both and pl.edge_index(0, 2) != -1 and pl.is_manifold() and no_face["error"] != "" and joined["error"] != "" and pl.face_count() == 3,
		"(2) 2 verts on a quad: %d faces, edge 0-2 made %s, normals z %.3f %.3f; refused: \"%s\" / \"%s\"" % [pl.face_count(), pl.edge_index(0, 2) != -1, pl.face_normals[0].z, pl.face_normals[2].z, no_face["error"], joined["error"]])
	# (3) loose verts, scrambled order -> a convex quad facing away from the mesh
	var lv := PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)])
	var lm := KMesh.new().from_arrays(lv, [[0,3,2,1]])
	var lr := KMeshFill.make_face(lm, [7, 5, 4, 6])
	var conv := true
	var lf: PackedInt32Array = lm.faces[lr["faces"][0]] if lr["error"] == "" else PackedInt32Array()
	for i in lf.size():
		var a := lm.verts[lf[i]]
		var b := lm.verts[lf[(i + 1) % 4]]
		var d := lm.verts[lf[(i + 2) % 4]]
		conv = conv and (b - a).cross(d - b).dot(Vector3(0, 0, 1)) > 0.99
	var dup := KMeshFill.make_face(cube(), [0, 1, 2, 3])
	ok(lr["error"] == "" and lf.size() == 4 and conv and dup["error"] != "",
		"(3) 4 loose verts picked 7 5 4 6: face %s convex %s facing +z; an existing face refused: \"%s\"" % [str(lf), conv, dup["error"]])
	# (4) Alt+F across 2 holes, n-gon and triangulated; ear clip of a concave L
	var h2 := cube()
	KMeshDissolve.delete(h2, "only_faces", [0, 1])
	var h2t := cube()
	KMeshDissolve.delete(h2t, "only_faces", [0, 1])
	var hr := KMeshFill.fill_holes(h2, [0, 6])
	var htr := KMeshFill.fill_holes(h2t, [0, 6], true)
	var tri_all := true
	for fi in htr["faces"]:
		tri_all = tri_all and (h2t.faces[fi] as PackedInt32Array).size() == 3
	ok(int(hr.get("holes", 0)) == 2 and (hr["faces"] as Array).size() == 2 and clean(h2) and absf(vol(h2) - 1.0) < 1e-9
		and (htr["faces"] as Array).size() == 4 and tri_all and clean(h2t) and absf(vol(h2t) - 1.0) < 1e-9,
		"(4a) Alt+F across 2 holes: +%d faces, clean %s, volume %.4f; triangulated: +%d triangles, clean %s %s, volume %.4f" % [(hr["faces"] as Array).size(), clean(h2), vol(h2), (htr["faces"] as Array).size(), clean(h2t), str(kinds(h2t)), vol(h2t)])
	var L := PackedVector3Array([Vector3(0,0,0), Vector3(2,0,0), Vector3(2,1,0), Vector3(1,1,0), Vector3(1,2,0), Vector3(0,2,0)])
	var tris := KMeshFill.ear_clip(L, [0, 1, 2, 3, 4, 5])
	var tarea := 0.0
	var up := true
	for tt in tris:
		var cr: Vector3 = (L[tt[1]] - L[tt[0]]).cross(L[tt[2]] - L[tt[0]])
		tarea += cr.length() * 0.5
		up = up and cr.z > 0.0
	ok(tris.size() == 4 and absf(tarea - 3.0) < 1e-9 and up, "(4b) ear clip of a concave L: %d triangles, area %.6f m^2 (L = 3), all facing +z %s" % [tris.size(), tarea, up])
	# (5) grid fill of a 16-vert hole
	var g := KMeshView.make_cube(1.0, 4)
	var side := []
	for fi in g.face_count():
		if absf(g.face_center(fi).y - 0.5) < 1e-6:
			side.append(fi)
	KMeshDissolve.delete(g, "faces", side)   # "faces": the side's 9 inner verts go too (only_faces would leave them loose)
	var gh: Array = KMeshValidate._holes(g)
	var gv0 := g.vert_count()
	var gf0 := g.face_count()
	var gr := KMeshFill.grid_fill(g, [gh[0][0]])
	var quads := 0
	var amin := INF
	var amax := 0.0
	var flat := true
	for fi in gr["faces"]:
		quads += 1 if (g.faces[fi] as PackedInt32Array).size() == 4 else 0
		amin = minf(amin, area(g, fi))
		amax = maxf(amax, area(g, fi))
		flat = flat and g.face_normals[fi].dot(Vector3.UP) > 0.9999
	ok(side.size() == 16 and gh.size() == 1 and (gh[0] as Array).size() == 16 and (gr["faces"] as Array).size() == 16 and quads == 16 and g.vert_count() - gv0 == 9
		and absf(amin - 0.0625) < 1e-6 and absf(amax - 0.0625) < 1e-6 and flat and clean(g) and absf(vol(g) - 1.0) < 1e-6,
		"(5a) grid fill of a %d-vert hole: %d faces (%d quads, was %d), +%d verts, area %.6f..%.6f m^2, flat facing +y %s, clean %s %s, volume %.6f" % [(gh[0] as Array).size(), (gr["faces"] as Array).size(), quads, gf0, g.vert_count() - gv0, amin, amax, flat, clean(g), str(kinds(g)), vol(g)])
	var g2 := KMeshView.make_cube(1.0, 4)
	KMeshDissolve.delete(g2, "faces", side)
	var gv2 := g2.vert_count()
	var gr2 := KMeshFill.grid_fill(g2, [KMeshValidate._holes(g2)[0][0]], 2)
	var amin2 := INF
	for fi in gr2["faces"]:
		amin2 = minf(amin2, area(g2, fi))
	ok((gr2["faces"] as Array).size() == 12 and g2.vert_count() - gv2 == 5 and amin2 > 1e-3 and clean(g2),
		"(5b) grid fill span 2: %d quads, +%d verts, smallest %.4f m^2, clean %s %s" % [(gr2["faces"] as Array).size(), g2.vert_count() - gv2, amin2, clean(g2), str(kinds(g2))])
	var cv := PackedVector3Array()
	var cf: Array = []
	for y in [0.0, 1.0]:
		for i in 16:
			var a := TAU * i / 16.0
			cv.append(Vector3(0.5 * cos(a), y, -0.5 * sin(a)))
	var bot := []
	for i in 16:
		cf.append([i, (i + 1) % 16, 16 + (i + 1) % 16, 16 + i])
		bot.append(15 - i)
	cf.append(bot)
	var cy := KMesh.new().from_arrays(cv, cf)
	var cr3 := KMeshFill.grid_fill(cy, [16])
	var cmin := INF
	for fi in cr3["faces"]:
		cmin = minf(cmin, area(cy, fi))
	var poly := 0.5 * 16 * 0.25 * sin(TAU / 16.0)
	ok((cr3["faces"] as Array).size() == 16 and cmin > 0.01 and clean(cy) and absf(vol(cy) - poly) < 1e-6,
		"(5c) grid fill of a 16-sided cylinder's open top: %d quads, smallest %.4f m^2, clean %s %s, volume %.6f (16-gon x 1 m = %.6f)" % [(cr3["faces"] as Array).size(), cmin, clean(cy), str(kinds(cy)), vol(cy), poly])
	var tet := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)]), [[0,2,1], [0,1,3], [1,2,3]])
	var odd := KMeshFill.grid_fill(tet, [0])
	ok(odd["error"] != "" and tet.face_count() == 3, "(5d) a 3-vert border refused: \"%s\"" % odd["error"])
	# (6) attributes and undo
	var at := cube()
	at.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	at.set_attr("mat", 2, 5.0)
	KMeshDissolve.delete(at, "only_faces", [1])
	var mat_before = at.get_attr("mat", 1)   # the old face 2, renumbered to 1 by the delete
	var bv := at.verts.duplicate()
	var bf := at.faces.duplicate()
	var u := KMeshUndo.new()
	u.begin(at)
	KMeshFill.make_face(at, [4, 5, 6, 7])
	var st := u.commit("Make face")
	var kept: bool = is_equal_approx(at.get_attr("mat", 1), mat_before) and is_equal_approx(at.get_attr("mat", 5), 0.0) and (at.attr_data("mat") as PackedFloat32Array).size() == 6
	u.undo()
	var back := at.verts == bv and at.faces == bf and at.face_count() == 5
	u.redo()
	ok(st.get("kind", "") == "topo" and kept and back and at.face_count() == 6 and clean(at),
		"(6) one %s step; mat kept %s (new face default 0), undo back %s, redo %d faces clean %s" % [st.get("kind", "?"), kept, back, at.face_count(), clean(at)])
	# (7) the model preview's keys
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	mn._kmesh_edit_start()
	await process_frame
	var ui = mn.kmed
	var f0: int = ui.mesh.face_count()
	ui.set_mode(KMeshSelect.FACE)
	ui.sel.faces[0] = true
	var kd := InputEventKey.new()
	kd.pressed = true
	kd.keycode = KEY_DELETE
	ui.input(kd)
	var after_del: int = ui.mesh.face_count()
	var s0: int = ui.undo.steps.size()
	var pick_hole := func() -> void:
		ui.set_mode(KMeshSelect.VERT)
		ui.sel.clear()
		for v in KMeshValidate._holes(ui.mesh)[0]:
			ui.sel.verts[v] = true
	pick_hole.call()
	var kf := InputEventKey.new()
	kf.pressed = true
	kf.keycode = KEY_F
	var used: bool = ui.input(kf)
	var after_f: int = ui.mesh.face_count()
	var clean_f := clean(ui.mesh)
	var kz := InputEventKey.new()
	kz.pressed = true
	kz.ctrl_pressed = true
	kz.keycode = KEY_Z
	ui.input(kz)
	var after_z: int = ui.mesh.face_count()
	pick_hole.call()
	kf.alt_pressed = true
	ui.input(kf)
	var after_alt: int = ui.mesh.face_count()
	var clean_alt := clean(ui.mesh)
	ui.input(kz)
	pick_hole.call()
	kf.alt_pressed = false
	kf.ctrl_pressed = true
	ui.input(kf)
	var after_ctrl: int = ui.mesh.face_count()
	var clean_ctrl := clean(ui.mesh)
	var steps: int = ui.undo.steps.size() - s0
	var row: Dictionary = MeshTools.TOOLS.filter(func(x): return x["id"] == "mesh_fill")[0]
	ok(used and after_del == f0 - 1 and after_f == f0 and clean_f and after_z == f0 - 1 and after_alt == f0 and clean_alt and after_ctrl == f0 and clean_ctrl and steps == 1
		and MeshTools.why({"tool": row, "host": mn}) == "",
		"(7) preview keys: Delete %d -> %d faces, F -> %d clean %s, Ctrl+Z -> %d, Alt+F -> %d clean %s, Ctrl+Z, Ctrl+F -> %d clean %s, net undo steps %d; S box row live %s; status: %s" % [f0, after_del, after_f, clean_f, after_z, after_alt, clean_alt, after_ctrl, clean_ctrl, steps, MeshTools.why({"tool": row, "host": mn}) == "", mn.ui_status.text.left(80)])
	ui.stop()
	print("fill: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
