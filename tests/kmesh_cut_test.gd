extends SceneTree
## B04 loop cut + slide, knife, edge split (scripts/kmesh_cut.gd, the keys in scripts/kmesh_cut_tool.gd). Bars, stated
## before measuring, on the model preview's 4x4 test cube (side 0.6: 98 verts, 192 edges, 96 faces):
## (1) one loop cut through a top edge: exactly one ring: 16 ring edges, closed, +16 verts / +32 edges / +16 faces
##     (114 / 224 / 112), closed, manifold, validate clean; every new vert is the midpoint of its ring edge (1 micron)
## (2) slide 0.5: every new vert at 0.75 of the way along its ring edge p->q (toward the hovered edge's second vert),
##     on the edge (off it < 1 micron); 3 cuts at slide 0: +48 verts at 1/4, 2/4, 3/4; still clean
## (3) a ring stops at a triangle: 2 quads + a triangle: 3 ring edges cut, the triangle becomes a 4-gon, 10 verts,
##     5 faces, manifold, no flipped / degenerate / non-manifold
## (4) knife across one quad of a unit cube (edge midpoint to opposite edge midpoint): 8 -> 10 verts, 6 -> 7 faces, the
##     two halves 4-gons, the cut verts ON the original edges at their midpoints (< 1 micron), validate clean
## (5) knife across 4 top quads of the test cube (border edge to border edge at z = 0.05): +5 verts, +4 faces, every
##     new vert at y = 0.3, z = 0.05 and on an original edge; clean. The same cut started and ended INSIDE the end
##     faces: those ends are dropped: +3 verts, +2 faces, clean
## (6) edge split of the 16-edge loop round the cube's middle: +16 verts, the only problems 16 doubled + 2 holes (the
##     two halves apart), manifold; split of 2 joined interior top edges: +1 vert (only the middle one is cut twice)
## (7) attributes follow: a loop cut's new faces keep their face's "mat"; (8) undo: each op one topo step, undo puts
##     the verts and faces back exactly
## (9) the preview's keys: Ctrl+R + hover: the hovered edge is under the mouse (< 12 px), the drawn loop's screen points
##     sit on the screen projection of the verts the cut then makes (< 1 px); wheel = 2 cuts; click, slide, click:
##     +32 verts; Ctrl+Z back to 98. Shift+K two clicks on top edges + Enter: +1 face. V on a selected loop: +16 verts.
##     MeshTools rows: Ctrl+R / Shift+K / V do their key; Esc cancels a running loop cut with nothing changed
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
func cube() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), CF)
func tcube() -> KMesh:
	return KMeshView.make_cube(0.6, 4)
func clean(m: KMesh) -> bool:
	return m.is_closed() and m.is_manifold() and KMeshValidate.report(m)["ok"]
func kinds(m: KMesh) -> Array:
	return (KMeshValidate.report(m)["problems"] as Array).map(func(p): return "%s x%d" % [p["kind"], p["count"]])
func counts(m: KMesh) -> String:
	return "%d/%d/%d" % [m.vert_count(), m.edge_count(), m.face_count()]
## the edge of the test cube's top (y = 0.3) from (x0, z0) to (x1, z1)
func vat(m: KMesh, p: Vector3) -> int:
	for i in m.verts.size():
		if m.verts[i].distance_to(p) < 1e-6:
			return i
	return -1
## the top face of the test cube holding point p (x, z)
func top_face(m: KMesh, x: float, z: float) -> int:
	for fi in m.faces.size():
		var c := m.face_center(fi)
		if absf(c.y - 0.3) < 1e-6 and absf(c.x - x) < 0.075 + 1e-6 and absf(c.z - z) < 0.075 + 1e-6 and absf(c.x - x) < 0.0751 and absf(c.z - z) < 0.0751:
			var f: PackedInt32Array = m.faces[fi]
			var lo := Vector2(INF, INF)
			var hi := -lo
			for v in f:
				lo = lo.min(Vector2(m.verts[v].x, m.verts[v].z))
				hi = hi.max(Vector2(m.verts[v].x, m.verts[v].z))
			if x >= lo.x - 1e-9 and x <= hi.x + 1e-9 and z >= lo.y - 1e-9 and z <= hi.y + 1e-9:
				return fi
	return -1
func seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)
## worst |fraction - want| of new verts along their ring edges, and worst distance off the edge
func frac_err(m0: KMesh, r: Dictionary, m: KMesh, n: int, want: Array) -> Vector2:
	var worst := Vector2.ZERO
	var es: Array = r["ring_edges"]
	var nv := m0.vert_count()
	for i in es.size():
		var e: Vector2i = es[i]
		var a := m0.verts[e.x]
		var b := m0.verts[e.y]
		for k in n:
			var p := m.verts[nv + i * n + k]
			var t := (p - a).dot(b - a) / (b - a).length_squared()
			worst.x = maxf(worst.x, absf(t - float(want[k])))
			worst.y = maxf(worst.y, seg(p, a, b))
	return worst
func key(code: int, ctrl := false, shift := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	return k
func mbtn(p: Vector2, b := MOUSE_BUTTON_LEFT, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.position = p
	return e
func motion(p: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = p
	return e

func _init() -> void:
	# (1) one loop cut
	var c := tcube()
	var c0 := counts(c)
	var a := vat(c, Vector3(-0.15, 0.3, -0.3))
	var b := vat(c, Vector3(-0.15, 0.3, -0.15))
	var r0 := KMeshCut.ring(c, a, b)
	var base := tcube()
	var r := KMeshCut.loop_cut(c, a, b, 1, 0.0)
	r["ring_edges"] = r0["edges"]
	var fe := frac_err(base, r, c, 1, [0.5])
	ok(c0 == "98/192/96" and r["error"] == "" and int(r["ring"]) == 16 and r["closed"] and counts(c) == "114/224/112" and clean(c) and fe.x < 1e-6 and fe.y < 1e-6 and (r["edges"] as Array).size() == 16,
		"(1) loop cut on the 4x4 cube: %s -> %s verts/edges/faces, ring %d edges closed %s, %d new loop edges, clean %s %s, worst midpoint error %.9f, off-edge %.9f m" % [c0, counts(c), int(r["ring"]), r["closed"], (r["edges"] as Array).size(), clean(c), str(kinds(c)), fe.x, fe.y])
	# (2) slide
	var s := tcube()
	var rs := KMeshCut.loop_cut(s, a, b, 1, 0.5)
	rs["ring_edges"] = r0["edges"]
	var fs := frac_err(base, rs, s, 1, [0.75])
	var hov := -1
	for i in (r0["edges"] as Array).size():
		if r0["edges"][i] == Vector2i(a, b):
			hov = i
	var toward_b := s.verts[98 + hov].distance_to(s.verts[b]) < s.verts[98 + hov].distance_to(s.verts[a])
	ok(fs.x < 1e-6 and fs.y < 1e-6 and clean(s) and toward_b and counts(s) == "114/224/112",
		"(2a) slide 0.5: every new vert at 0.75 along p->q (worst error %.9f, off the edge %.9f m), the hovered edge's at %.4f m from b of %.4f (toward b %s), clean %s" % [fs.x, fs.y, s.verts[98 + hov].distance_to(s.verts[b]), s.verts[a].distance_to(s.verts[b]), toward_b, clean(s)])
	var s3 := tcube()
	var r3 := KMeshCut.loop_cut(s3, a, b, 3, 0.0)
	r3["ring_edges"] = r0["edges"]
	var f3 := frac_err(base, r3, s3, 3, [0.25, 0.5, 0.75])
	ok(s3.vert_count() == 98 + 48 and s3.face_count() == 96 + 48 and clean(s3) and f3.x < 1e-6,
		"(2b) 3 cuts: %s, new verts at 1/4 2/4 3/4 (worst %.9f), clean %s" % [counts(s3), f3.x, clean(s3)])
	# (3) a triangle stops the ring
	var tv := PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(0,1,0), Vector3(1,1,0), Vector3(2,1,0), Vector3(3,0.5,0)])
	var tm := KMesh.new().from_arrays(tv, [[0,1,4,3], [1,2,5,4], [2,6,5]])
	var rt := KMeshCut.loop_cut(tm, 0, 3)
	var bad := (KMeshValidate.report(tm)["problems"] as Array).filter(func(p): return p["kind"] != "holes")
	ok(rt["error"] == "" and int(rt["ring"]) == 3 and not rt["closed"] and tm.vert_count() == 10 and tm.face_count() == 5 and (tm.faces[2] as PackedInt32Array).size() == 4 and tm.is_manifold() and bad.is_empty(),
		"(3) ring stops at a triangle: %d ring edges, %d verts %d faces, the triangle now %d-gon, manifold %s, problems besides the open border %s" % [int(rt["ring"]), tm.vert_count(), tm.face_count(), (tm.faces[2] as PackedInt32Array).size(), tm.is_manifold(), str(bad.map(func(p): return p["kind"]))])
	var lone := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)]), [[0,1,2]])
	var rl := KMeshCut.loop_cut(lone, 0, 1)
	ok(rl["error"] != "" and lone.vert_count() == 3, "(3b) no quad beside the edge: refused, mesh unchanged: %s" % rl["error"])
	# (4) knife across one quad
	var k := cube()
	var rk := KMeshCut.knife(k, [{"face": 1, "point": Vector3(0.5, 0, 1)}, {"face": 1, "point": Vector3(0.5, 1, 1)}])
	var on_e := 0.0
	var vk := []
	for v in range(8, k.vert_count()):
		vk.append(k.verts[v])
	on_e = maxf(seg(k.verts[8], CV[4], CV[5]), seg(k.verts[9], CV[6], CV[7])) if k.vert_count() == 10 else 1.0
	var mid_e := maxf(k.verts[8].distance_to(Vector3(0.5, 0, 1)), k.verts[9].distance_to(Vector3(0.5, 1, 1))) if k.vert_count() == 10 else 1.0
	var halves := [(k.faces[1] as PackedInt32Array).size(), (k.faces[k.face_count() - 1] as PackedInt32Array).size()]
	ok(rk["error"] == "" and k.vert_count() == 10 and k.face_count() == 7 and halves == [4, 4] and on_e < 1e-6 and mid_e < 1e-6 and clean(k),
		"(4) knife across one quad: %d verts %d faces, halves %s-gons, cut verts %s off their edges by %.9f m (from the midpoints %.9f), clean %s %s" % [k.vert_count(), k.face_count(), str(halves), str(vk), on_e, mid_e, clean(k), str(kinds(k))])
	# (5) knife across 4 top quads
	var kc := tcube()
	var p0 := Vector3(-0.3, 0.3, 0.05)
	var p1 := Vector3(0.3, 0.3, 0.05)
	var f0 := top_face(kc, -0.29, 0.05)
	var f1 := top_face(kc, 0.29, 0.05)
	var old := tcube()
	var r5 := KMeshCut.knife(kc, [{"face": f0, "point": p0}, {"face": f1, "point": p1}])
	var w5 := 0.0
	for v in range(98, kc.vert_count()):
		var p := kc.verts[v]
		var best := INF
		for e in old.edges():
			best = minf(best, seg(p, old.verts[e.x], old.verts[e.y]))
		w5 = maxf(w5, best + absf(p.y - 0.3) + absf(p.z - 0.05))
	ok(f0 >= 0 and f1 >= 0 and r5["error"] == "" and kc.vert_count() == 103 and kc.face_count() == 100 and int(r5["chords"]) == 4 and w5 < 1e-6 and clean(kc),
		"(5a) knife border to border across the top: +%d verts, +%d faces (%d splits), worst off (edge + y + z) %.9f m, clean %s %s" % [kc.vert_count() - 98, kc.face_count() - 96, int(r5.get("chords", 0)), w5, clean(kc), str(kinds(kc))])
	var ki := tcube()
	var r5b := KMeshCut.knife(ki, [{"face": top_face(ki, -0.25, 0.05), "point": Vector3(-0.25, 0.3, 0.05)}, {"face": top_face(ki, 0.25, 0.05), "point": Vector3(0.25, 0.3, 0.05)}])
	ok(r5b["error"] == "" and ki.vert_count() == 101 and ki.face_count() == 98 and clean(ki),
		"(5b) the same cut from inside a face to inside a face: ends dropped, +%d verts, +%d faces, clean %s" % [ki.vert_count() - 98, ki.face_count() - 96, clean(ki)])
	# (6) edge split
	var sp := tcube()
	var ss := KMeshSelect.new(sp, KMeshSelect.EDGE)
	var la := vat(sp, Vector3(-0.15, 0.0, -0.3))
	var lb := vat(sp, Vector3(0.0, 0.0, -0.3))
	ss.select_loop(la, lb)
	var nloop := ss.edges.size()
	var r6 := KMeshCut.edge_split(sp, ss.edges.keys())
	var probs := {}
	for p in (KMeshValidate.report(sp)["problems"] as Array):
		probs[p["kind"]] = int(p["count"])
	ok(nloop == 16 and (r6["verts"] as Array).size() == 16 and sp.vert_count() == 114 and probs == {"doubled": 16, "holes": 2} and sp.is_manifold() and sp.face_count() == 96,
		"(6a) edge split of the %d-edge middle loop: %d -> %d verts, problems %s, manifold %s" % [nloop, 98, sp.vert_count(), str(probs), sp.is_manifold()])
	var s2 := tcube()
	var m0 := vat(s2, Vector3(-0.15, 0.3, 0.0))
	var m1 := vat(s2, Vector3(0.0, 0.3, 0.0))
	var m2 := vat(s2, Vector3(0.15, 0.3, 0.0))
	var r6b := KMeshCut.edge_split(s2, [Vector2i(m0, m1), Vector2i(m1, m2)])
	var p2 := {}
	for p in (KMeshValidate.report(s2)["problems"] as Array):
		p2[p["kind"]] = int(p["count"])
	ok(r6b["error"] == "" and s2.vert_count() == 99 and s2.is_manifold() and p2 == {"doubled": 1, "holes": 1},
		"(6b) split of 2 joined interior edges: +%d vert (the middle one), problems %s (a slit), manifold %s" % [s2.vert_count() - 98, str(p2), s2.is_manifold()])
	# (7) attributes
	var at := tcube()
	at.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	for fi in at.face_count():
		at.set_attr("mat", fi, float(fi))
	var ra := KMeshCut.loop_cut(at, a, b)
	var a_ok := (at.attr_data("mat") as PackedFloat32Array).size() == at.face_count()
	for fi in ra["faces"]:
		var cc := at.face_center(fi)
		var src := -1
		for g in base.face_count():
			var gf: PackedInt32Array = base.faces[g]
			var lo := Vector3.INF
			var hi := -Vector3.INF
			for v in gf:
				lo = lo.min(base.verts[v])
				hi = hi.max(base.verts[v])
			if AABB(lo, hi - lo).grow(1e-6).has_point(cc):
				src = g
		a_ok = a_ok and src >= 0 and is_equal_approx(at.get_attr("mat", fi), float(src))
	ok(a_ok, "(7) attributes: each of the %d cut faces keeps the 'mat' of the face it was cut from" % (ra["faces"] as Array).size())
	# (8) undo
	var u := KMeshUndo.new()
	var um := tcube()
	var uv := um.verts.duplicate()
	var uf := um.faces.duplicate()
	var steps := []
	u.begin(um)
	KMeshCut.loop_cut(um, a, b, 2, 0.3)
	steps.append(u.commit("Loop cut"))
	u.begin(um)
	KMeshCut.knife(um, [{"face": top_face(um, -0.29, 0.2), "point": Vector3(-0.3, 0.3, 0.2)}, {"face": top_face(um, 0.29, 0.2), "point": Vector3(0.3, 0.3, 0.2)}])
	steps.append(u.commit("Knife"))
	u.begin(um)
	KMeshCut.edge_split(um, [Vector2i(m0, m1), Vector2i(m1, m2)])
	steps.append(u.commit("Edge split"))
	var grew := um.vert_count()
	u.undo()
	u.undo()
	u.undo()
	var back := um.verts == uv and KMeshUndo._same_faces(um.faces, uf)
	ok(steps.all(func(st): return st.get("kind", "") == "topo") and u.steps.is_empty() and back and grew > 98 + 32,
		"(8) undo: 3 ops = 3 topo steps (%s), the mesh at %d verts, 3 undos put it back exactly %s" % [str(steps.map(func(st): return st.get("kind", "?"))), grew, back])
	# (9) the preview's keys
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	mn._kmesh_edit_start()
	await process_frame
	await process_frame
	var ui = mn.kmed
	var cam: Camera3D = mn.cam
	var view: KMeshView = ui.view
	# a top face facing the camera: the mouse just inside its first edge
	var mouse := Vector2.ZERO
	var want := Vector2i(-1, -1)
	for fi in ui.mesh.face_count():
		if absf(ui.mesh.face_center(fi).y - 0.3) > 1e-6:
			continue
		var cw: Vector3 = view.global_transform * ui.mesh.face_center(fi)
		if not view.point_visible(cam, cw):
			continue
		var f: PackedInt32Array = ui.mesh.faces[fi]
		var em: Vector3 = view.global_transform * ui.mesh.verts[f[0]].lerp(ui.mesh.verts[f[1]], 0.5)
		mouse = cam.unproject_position(em).lerp(cam.unproject_position(cw), 0.1)
		if view.pick(cam, mouse, 1e9).get("face", -1) == fi:
			want = Vector2i(f[0], f[1])
			break
	ui.input(key(KEY_R, true))
	var tool := KMeshCutTool.of(ui)
	ui.input(motion(mouse))
	var ea: Vector2 = cam.unproject_position(view.global_transform * ui.mesh.verts[tool.edge.x])
	var eb: Vector2 = cam.unproject_position(view.global_transform * ui.mesh.verts[tool.edge.y])
	var under := KMeshSelect.ekey(tool.edge.x, tool.edge.y) == KMeshSelect.ekey(want.x, want.y)
	var px := view._seg_dist(mouse, ea, eb)
	ok(want.x >= 0 and tool.mode == "loop" and under and px < 12.0 and (tool.preview["lines"] as Array).size() == 1,
		"(9a) Ctrl+R, hover: the edge %s under the mouse (%.1f px from it), preview %d loop of %d points; status: %s" % [str(tool.edge), px, (tool.preview["lines"] as Array).size(), (tool.preview["lines"][0] as PackedVector3Array).size() if tool.preview.has("lines") else 0, mn.ui_status.text.left(60)])
	ui.input(mbtn(mouse, MOUSE_BUTTON_WHEEL_UP))
	var sh := mbtn(mouse)   # a plain click cuts now; Shift+click starts the slide
	sh.shift_pressed = true
	ui.input(sh)
	ui.input(mbtn(mouse, MOUSE_BUTTON_LEFT, false))
	var slide_to := ea.lerp(eb, 0.75)   # 3/4 along the hovered edge on screen -> slide 0.5
	ui.input(motion(slide_to))
	var drawn: Array = []
	for pl in tool.preview["lines"]:
		drawn.append_array(tool.screen_line(pl))
	var cuts_was := tool.cuts
	var sl := tool.slide
	var nv0: int = ui.mesh.vert_count()
	ui.input(mbtn(slide_to))
	var made := []
	for v in range(nv0, ui.mesh.vert_count()):
		var sp2: Variant = view._screen(cam, view.global_transform * ui.mesh.verts[v])
		if sp2 != null:
			made.append(sp2)
	var worst_px := 0.0
	for d in drawn:
		if d == null:
			continue
		var best := INF
		for q in made:
			best = minf(best, (d as Vector2).distance_to(q))
		worst_px = maxf(worst_px, best)
	ok(cuts_was == 2 and absf(sl - 0.5) < 0.02 and ui.mesh.vert_count() == 98 + 32 and drawn.size() == 32 and worst_px < 1.0 and clean(ui.mesh) and ui.sel.edges.size() == 32 and tool.mode == "",
		"(9b) wheel -> %d cuts, slide %.3f, click: %d verts (+%d), the drawn loop sits on the made verts (worst %.3f px of %d points), %d new edges selected, clean %s; status: %s" % [cuts_was, sl, ui.mesh.vert_count(), ui.mesh.vert_count() - 98, worst_px, drawn.size(), ui.sel.edges.size(), clean(ui.mesh), mn.ui_status.text.left(70)])
	ui.input(key(KEY_Z, true))
	var undone: int = ui.mesh.vert_count()
	# knife: two clicks near the opposite edges of the face that is biggest on screen
	var kf := -1
	var big := 0.0
	for fi in ui.mesh.face_count():
		var fc: Vector3 = view.global_transform * ui.mesh.face_center(fi)
		if not view.point_visible(cam, fc):
			continue
		var sq := PackedVector2Array()
		for v in (ui.mesh.faces[fi] as PackedInt32Array):
			sq.append(cam.unproject_position(view.global_transform * ui.mesh.verts[v]))
		var area := absf((sq[2] - sq[0]).cross(sq[3] - sq[1])) * 0.5
		if area > big:
			big = area
			kf = fi
	var kq: PackedInt32Array = ui.mesh.faces[kf]
	var k0: Vector2 = cam.unproject_position(view.global_transform * ui.mesh.verts[kq[0]].lerp(ui.mesh.verts[kq[1]], 0.5))
	var k1: Vector2 = cam.unproject_position(view.global_transform * ui.mesh.verts[kq[2]].lerp(ui.mesh.verts[kq[3]], 0.5))
	var kc0 := cam.unproject_position(view.global_transform * ui.mesh.face_center(kf))
	var nf0: int = ui.mesh.face_count()
	ui.input(key(KEY_K, false, true))
	var kmode := tool.mode
	ui.input(mbtn(k0.lerp(kc0, 0.02)))
	ui.input(mbtn(k1.lerp(kc0, 0.02)))
	var npts := tool.pts.size()
	ui.input(key(KEY_ENTER))
	var kmid := 0.0 if ui.mesh.vert_count() == 100 else 1.0
	var kn: Vector3 = ui.mesh.face_normals[kf]
	for v in range(98, ui.mesh.vert_count()):
		kmid = maxf(kmid, minf(ui.mesh.verts[v].distance_to(ui.mesh.verts[kq[0]].lerp(ui.mesh.verts[kq[1]], 0.5)), ui.mesh.verts[v].distance_to(ui.mesh.verts[kq[2]].lerp(ui.mesh.verts[kq[3]], 0.5))) + absf((ui.mesh.verts[v] - ui.mesh.verts[kq[0]]).dot(kn)))
	ok(undone == 98 and kmid < 0.005 and kmode == "knife" and npts == 2 and ui.mesh.face_count() == nf0 + 1 and ui.mesh.vert_count() == 100 and clean(ui.mesh),
		"(9c) Ctrl+Z -> %d verts; Shift+K, 2 clicks near the edges (snapped on), Enter: %d -> %d faces, %d verts (face %d, %.0f px^2 on screen; the cut verts %.4f m from the edge midpoints, in its plane), clean %s; status: %s" % [undone, nf0, ui.mesh.face_count(), ui.mesh.vert_count(), kf, big, kmid, clean(ui.mesh), mn.ui_status.text.left(70)])
	ui.input(key(KEY_Z, true))
	# V on a selected loop
	ui.sel.clear()
	ui.sel.select_loop(la, lb)
	ui.input(key(KEY_V))
	var v_ok: bool = ui.mesh.vert_count() == 114 and ui.mesh.is_manifold()
	ui.input(key(KEY_Z, true))
	ok(v_ok and ui.mesh.vert_count() == 98, "(9d) V on the middle loop: 98 -> 114 verts, Ctrl+Z -> %d; status: %s" % [ui.mesh.vert_count(), mn.ui_status.text.left(60)])
	# the search rows run the keys; Esc cancels with nothing changed
	var rows := {}
	for t in MeshTools.TOOLS:
		rows[t["id"]] = t
	MeshTools.run(rows["mesh_loopcut"], mn)
	var via_r := tool.mode
	ui.input(key(KEY_ESCAPE))
	MeshTools.run(rows["mesh_knife"], mn)
	var via_k := tool.mode
	ui.input(key(KEY_ESCAPE))
	ok(via_r == "loop" and via_k == "knife" and tool.mode == "" and ui.on and ui.mesh.vert_count() == 98 and rows["mesh_knife"]["keys"] == "Shift+K" and rows.has("mesh_edge_split"),
		"(9e) search rows: loop cut -> '%s', knife (%s) -> '%s'; Esc cancels, the cube stays open, %d verts" % [via_r, rows["mesh_knife"]["keys"], via_k, ui.mesh.vert_count()])
	ui.stop()
	print("kmesh_cut: %d failures" % fails)
	quit(1 if fails > 0 else 0)
