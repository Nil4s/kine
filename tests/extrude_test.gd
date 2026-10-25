extends SceneTree
## B02 extrude + B03 inset / bridge (scripts/kmesh_extrude.gd). Bars: (1) one face of a unit cube extruded 0.5 m: 12 verts,
## 10 faces, closed, manifold, validate clean, the cap exactly 0.5 m up (volume 1.5 m^3); (2) region extrude of 2 adjacent
## faces: 6 new verts, 6 walls (the shared edge gets none), still clean; (3) individual extrude of the same 2: 8 new verts,
## 8 walls (two back to back on the shared edge); (4) inset of one face: 12 / 10, every inner edge exactly t from its old
## edge (to 1 micron: Vector3 is float32); region inset of 2 faces: 6 new verts, each exactly t inside the region's outline; (5) bridge the facing caps of
## two 8-sided cylinders (the second's ring numbered from another vertex): caps deleted, 8 new quads, every quad's side
## edges straight along the axis (no twist), one closed clean tube of volume 3 x the octagon; (6) edge extrude on a border
## continues the plane outward; vertex extrude of 2 verts = 1 quad, a lone vert is refused with the reason; (7) attributes
## follow (vert colour copied, walls take their face's value, the cap edge its source edge's); (8) undo puts the mesh and
## attributes back exactly, redo re-applies; (9) the selection-driven entry selects the lifted face.
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
## the two top faces of a 2x2-per-side cube (side 1, top at y = +0.5) that share an edge, x in [-0.5, 0.5], z in [-0.5, 0]
func top_pair(m: KMesh) -> Array:
	var out := []
	for fi in m.faces.size():
		var c := m.face_center(fi)
		if absf(c.y - 0.5) < 1e-6 and c.z < 0.0:
			out.append(fi)
	return out
## distance from p to the segment a-b
func seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)
## an 8-sided cylinder, radius 0.5, along y from y0 to y1, its ring numbered from vertex `rot`
func cyl(vs: PackedVector3Array, fs: Array, y0: float, y1: float, rot: int) -> void:
	var b := vs.size()
	for y in [y0, y1]:
		for i in 8:
			var a := TAU * float((i + rot) % 8) / 8.0
			vs.append(Vector3(0.5 * cos(a), y, -0.5 * sin(a)))
	var bot := []
	var top := []
	for i in 8:
		var j := (i + 1) % 8
		fs.append([b + i, b + j, b + 8 + j, b + 8 + i])
		bot.append(b + 7 - i)
		top.append(b + 8 + i)
	fs.append(bot)
	fs.append(top)
func _init() -> void:
	# (1)
	var c := cube()
	var r := KMeshExtrude.extrude_faces(c, [1], 0.5)
	var capz := true
	for v in (c.faces[1] as PackedInt32Array):
		capz = capz and absf(c.verts[v].z - 1.5) < 1e-9
	var vol := KMeshValidate._volume(c)
	ok(c.vert_count() == 12 and c.face_count() == 10 and clean(c) and capz and absf(vol - 1.5) < 1e-9 and r["faces"] == [1],
		"(1) cube face extruded: %d verts %d faces, closed %s manifold %s, validate %s, cap at z=%.4f m, volume %.4f m^3" % [c.vert_count(), c.face_count(), c.is_closed(), c.is_manifold(), str(kinds(c)), c.verts[c.faces[1][0]].z, vol])
	# (2) region
	var g := KMeshView.make_cube(1.0, 2)
	var v0 := g.vert_count()
	var f0 := g.face_count()
	var e0 := g.edge_count()
	var pair := top_pair(g)
	KMeshExtrude.extrude_faces(g, pair, 0.25)
	var walls := g.face_count() - f0
	var inner_wall := 0
	for fi in range(f0, g.face_count()):
		var cc := g.face_center(fi)
		if absf(cc.x) < 1e-6 and cc.y > 0.5:   # a wall standing on the shared edge (x = 0, above the top)
			inner_wall += 1
	ok(pair.size() == 2 and g.vert_count() - v0 == 6 and walls == 6 and inner_wall == 0 and clean(g) and absf(KMeshValidate._volume(g) - 1.125) < 1e-9,
		"(2) region extrude of 2 faces: +%d verts, %d walls, %d on the shared edge, +%d edges, clean %s, volume %.4f m^3" % [g.vert_count() - v0, walls, inner_wall, g.edge_count() - e0, clean(g), KMeshValidate._volume(g)])
	# (3) individual
	var gi := KMeshView.make_cube(1.0, 2)
	KMeshExtrude.extrude_faces(gi, top_pair(gi), 0.25, true)
	var iw := 0
	for fi in range(f0, gi.face_count()):
		var cc := gi.face_center(fi)
		if absf(cc.x) < 1e-6 and cc.y > 0.5:
			iw += 1
	var dbl := (KMeshValidate.report(gi)["problems"] as Array).filter(func(p): return p["kind"] == "doubled")
	ok(gi.vert_count() - v0 == 8 and gi.face_count() - f0 == 8 and iw == 2 and gi.is_closed() and gi.is_manifold(),
		"(3) individual extrude of the same 2: +%d verts, %d walls, %d back to back on the shared edge, closed %s manifold %s (their tops coincide: %d doubled)" % [gi.vert_count() - v0, gi.face_count() - f0, iw, gi.is_closed(), gi.is_manifold(), dbl[0]["count"] if dbl.size() else 0])
	# (4) inset
	var ic := cube()
	var t := 0.1
	KMeshExtrude.inset_faces(ic, [1], t)
	var inf: PackedInt32Array = ic.faces[1]
	var of: PackedInt32Array = PackedInt32Array(CF[1])
	var worst := 0.0
	for i in 4:
		var a := ic.verts[inf[i]]
		var b := ic.verts[inf[(i + 1) % 4]]
		var oa := ic.verts[of[i]]
		var ob := ic.verts[of[(i + 1) % 4]]
		# the inner edge's two ends are both t from the old edge's LINE (seg on the extended line)
		var dir := (ob - oa).normalized()
		for p in [a, b]:
			worst = maxf(worst, absf(((p - oa) - dir * (p - oa).dot(dir)).length() - t))
	ok(ic.vert_count() == 12 and ic.face_count() == 10 and clean(ic) and worst < 1e-6 and absf(KMeshValidate._volume(ic) - 1.0) < 1e-6,
		"(4a) inset one face by %s: %d verts %d faces, clean %s, worst inner-edge distance error %.9f m" % [Units.len(t), ic.vert_count(), ic.face_count(), clean(ic), worst])
	var gr := KMeshView.make_cube(1.0, 2)
	var oldn := gr.vert_count()
	KMeshExtrude.inset_faces(gr, top_pair(gr), t)
	var rw := 0.0
	for vi in range(oldn, gr.vert_count()):
		var p := gr.verts[vi]
		var d := minf(minf(p.x + 0.5, 0.5 - p.x), minf(p.z + 0.5, 0.0 - p.z))
		rw = maxf(rw, absf(d - t) + absf(p.y - 0.5))
	ok(gr.vert_count() - oldn == 6 and gr.face_count() - f0 == 6 and clean(gr) and rw < 1e-6,
		"(4b) region inset of 2 faces: +%d verts, +%d faces, clean %s, worst outline distance error %.9f m" % [gr.vert_count() - oldn, gr.face_count() - f0, clean(gr), rw])
	# (5) bridge
	var bv := PackedVector3Array()
	var bf: Array = []
	cyl(bv, bf, 0.0, 1.0, 0)
	cyl(bv, bf, 2.0, 3.0, 3)
	var bm := KMesh.new().from_arrays(bv, bf)
	var es := []
	for i in 8:
		es.append(KMeshSelect.ekey(8 + i, 8 + (i + 1) % 8))    # top ring of the first
		es.append(KMeshSelect.ekey(16 + i, 16 + (i + 1) % 8))  # bottom ring of the second
	var br := KMeshExtrude.bridge_loops(bm, es)
	var straight := 0
	for fi in br["faces"]:
		var q: PackedInt32Array = bm.faces[fi]
		var s1 := Vector2(bm.verts[q[1]].x - bm.verts[q[2]].x, bm.verts[q[1]].z - bm.verts[q[2]].z).length()
		var s2 := Vector2(bm.verts[q[0]].x - bm.verts[q[3]].x, bm.verts[q[0]].z - bm.verts[q[3]].z).length()
		straight += 1 if s1 < 1e-9 and s2 < 1e-9 else 0
	var oct := 2.0 * sqrt(2.0) * 0.25
	var bvol := KMeshValidate._volume(bm)
	ok(br["error"] == "" and (br["faces"] as Array).size() == 8 and straight == 8 and bm.face_count() == 26 and clean(bm) and absf(bvol - 3.0 * oct) < 1e-6,
		"(5) bridge two 8-loops: %d new quads (%d untwisted), %d faces, clean %s %s, volume %.4f m^3 (3 x octagon %.4f) %s" % [(br["faces"] as Array).size(), straight, bm.face_count(), clean(bm), str(kinds(bm)), bvol, 3.0 * oct, br["error"]])
	var bad := KMeshExtrude.bridge_loops(cube(), [Vector2i(0, 1), Vector2i(1, 2)])
	ok(bad["error"] != "", "(5b) open edges refused: %s" % bad["error"])
	# (6) edges and verts
	var pl := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0)]), [[0,1,2,3]])
	var er := KMeshExtrude.extrude_edges(pl, [Vector2i(1, 2)], 0.5)
	var e_ok := pl.face_count() == 2 and pl.is_manifold() and pl.boundary_edge_count() == 6
	for v in er["verts"]:
		e_ok = e_ok and absf(pl.verts[v].x - 1.5) < 1e-9 and absf(pl.verts[v].z) < 1e-9
	e_ok = e_ok and pl.face_normals[1].dot(Vector3(0, 0, 1)) > 0.999
	ok(e_ok and (er["edges"] as Array).size() == 1, "(6a) border edge extruded outward in the plane: %d faces, new verts at x=%.3f m, new face normal z %.3f" % [pl.face_count(), pl.verts[er["verts"][0]].x, pl.face_normals[1].z])
	var pv := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0)]), [[0,1,2,3]])
	var vr := KMeshExtrude.extrude_verts(pv, [1, 2], 0.5)
	var lone := KMeshExtrude.extrude_verts(pv, [0], 0.5)
	ok(pv.face_count() == 2 and (vr["verts"] as Array).size() == 2 and lone["error"] != "" and int(lone["skipped"]) == 1,
		"(6b) 2 verts -> 1 quad (%d faces); a lone vert refused: %s" % [pv.face_count(), lone["error"]])
	# (7) attributes
	var at := cube()
	at.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	at.add_attr("col", KMesh.AD_VERT, TYPE_COLOR, Color.WHITE)
	at.add_attr("crease", KMesh.AD_EDGE, TYPE_FLOAT, 0.0)
	at.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2, Vector2.ZERO)
	at.set_attr("mat", 1, 7.0)
	for v in 8:
		at.set_attr("col", v, Color(float(v) / 8.0, 0, 0))
	at.set_attr("crease", at.edge_index(4, 5), 1.0)
	for i in 4:
		at.set_attr("uv", at.face_he0[1] + i, Vector2(i, 1))
	var at_v := at.verts.duplicate()
	var at_f := at.faces.duplicate()
	var at_a := at.attr_snapshot()
	var u := KMeshUndo.new()
	u.begin(at)
	KMeshExtrude.extrude_faces(at, [1], 0.5)
	var st := u.commit("Extrude")
	var a_ok := true
	for fi in range(6, 10):
		a_ok = a_ok and is_equal_approx(at.get_attr("mat", fi), 7.0)
	for vi in range(8, 12):
		var srcv := -1
		for k in 8:
			if is_equal_approx(at.verts[vi].x, CV[k].x) and is_equal_approx(at.verts[vi].y, CV[k].y) and CV[k].z == 1.0:
				srcv = k
		a_ok = a_ok and srcv >= 0 and at.get_attr("col", vi) == Color(float(srcv) / 8.0, 0, 0)
	var capf: PackedInt32Array = at.faces[1]
	var cap_edge := at.edge_index(capf[0], capf[1])
	var uv_ok: bool = at.get_attr("uv", at.face_he0[1] + 2) == Vector2(2, 1)
	a_ok = a_ok and is_equal_approx(at.get_attr("crease", cap_edge), 1.0) and is_equal_approx(at.get_attr("crease", at.edge_index(4, 5)), 1.0) and uv_ok
	var sizes_ok := (at.attr_data("crease") as PackedFloat32Array).size() == at.edge_count() and (at.attr_data("uv") as PackedVector2Array).size() == at.half_edge_count()
	ok(a_ok and sizes_ok, "(7) attributes follow: walls mat 7, copies keep their colour, cap edge crease 1, corner uv kept, sizes fit %s" % sizes_ok)
	# (8) undo
	u.undo()
	var back := at.verts == at_v and at.faces == at_f and at.attrs.size() == at_a.size()
	for k in at_a:
		back = back and at.attrs[k]["data"] == at_a[k]["data"]
	ok(st.get("kind", "") == "topo" and back and at.vert_count() == 8 and clean(at), "(8a) undo: one %s step, mesh and %d attributes back exactly %s" % [st.get("kind", "?"), at_a.size(), back])
	u.redo()
	ok(at.vert_count() == 12 and at.face_count() == 10 and is_equal_approx(at.get_attr("mat", 7), 7.0), "(8b) redo: %d verts %d faces again" % [at.vert_count(), at.face_count()])
	# (9) selection-driven
	var sm := cube()
	var sel := KMeshSelect.new(sm, KMeshSelect.FACE)
	sel.faces[1] = true
	KMeshExtrude.extrude(sm, sel, 0.5)
	var s_ok := sel.mode == KMeshSelect.FACE and sel.faces.keys() == [1] and sm.face_count() == 10
	KMeshExtrude.inset(sm, sel, 0.1)
	s_ok = s_ok and sm.face_count() == 14 and sel.faces.keys() == [1] and clean(sm)
	ok(s_ok, "(9) extrude then inset from the selection: %d faces, selected %s, clean %s" % [sm.face_count(), str(sel.faces.keys()), clean(sm)])
	# (10) the model preview's keys: E extrudes the picked face, I insets it, Ctrl+Z takes each back
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	mn._kmesh_edit_start()
	await process_frame
	var ui = mn.kmed
	var nf0: int = ui.mesh.face_count()
	ui.set_mode(KMeshSelect.FACE)
	ui.sel.faces[0] = true
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_E
	var used_e: bool = ui.input(ke)
	_type_amount(ui, KMeshEditUI.EXTRUDE_D)   # E is a live drag since 97f6e52: the amount is typed and Enter confirms
	var nf1: int = ui.mesh.face_count()
	var lift: float = ui.mesh.verts[ui.mesh.faces[0][0]].distance_to(ui.mesh.verts[ui.mesh.faces[nf0][0]])
	ke.keycode = KEY_I
	ui.input(ke)
	_type_amount(ui, KMeshEditUI.INSET_D)
	var nf2: int = ui.mesh.face_count()
	var kz := InputEventKey.new()
	kz.pressed = true
	kz.ctrl_pressed = true
	kz.keycode = KEY_Z
	ui.input(kz)
	ui.input(kz)
	ok(used_e and nf1 == nf0 + 4 and nf2 == nf1 + 4 and ui.mesh.face_count() == nf0 and ui.sel.mode == KMeshSelect.FACE and clean(ui.mesh) and absf(lift - KMeshEditUI.EXTRUDE_D) < 1e-6,
		"(10) preview keys: E %d -> %d faces (lifted %s), I -> %d, Ctrl+Z twice -> %d, clean %s; status: %s" % [nf0, nf1, Units.len(lift), nf2, ui.mesh.face_count(), clean(ui.mesh), mn.ui_status.text.left(70)])
	ui.stop()
	print("extrude: %d failures" % fails)
	quit(1 if fails > 0 else 0)


## the E / I drag's typed amount: its digits, then Enter (KMeshDragOp.handle)
func _type_amount(ui, amt: float) -> void:
	for ch in ("%.3f" % amt):
		var e := InputEventKey.new()
		e.pressed = true
		e.keycode = KEY_PERIOD if ch == "." else (KEY_0 + int(ch))
		ui.input(e)
	var en := InputEventKey.new()
	en.pressed = true
	en.keycode = KEY_ENTER
	ui.input(en)
