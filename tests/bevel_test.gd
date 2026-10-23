extends SceneTree
## B03 bevel (scripts/kmesh_bevel.gd). Bars: on a unit cube, edge (1,0,0)-(1,1,0) bevelled 2 cm:
## (1) 1 segment: 10 verts, 7 faces (Blender's counts), closed, manifold, validate clean; the 4 new verts each exactly
##     2 cm from the old edge's line and in an old face plane (to 1 micron); volume 1 - w^2/2 (the chamfer prism);
## (2) 3 segments, round (0.5): 14 verts, 9 faces, clean; the end faces are 7-gons; the 4 profile verts on the quarter
##     arc of radius w round O = (1 - w, y, w), each within 0.1 mm (bar), 30 deg apart; volume 1 - w^2/4;
## (3) profile: the middle vert's distance from O rises 0.1 < 0.25 (= w / sqrt 2, on the straight chamfer) < 0.5 (= w)
##     < 0.75 < 1 (= w sqrt 2: the square corner);
## (4) all 12 edges: 1 segment 24 verts / 26 faces, 2 segments 48 / 38, both clean (3-edge corners closed by one face);
##     two edges meeting at a corner share one profile there, clean;
## (5) a whole cube edge on the 4x4 test cube (4 edges through valence-4 verts), 3 segments: clean, volume 1 - w^2/4;
## (6) an open-border edge is refused with the reason; too wide a bevel is clamped (no slide past an edge's middle), clean;
## (7) attributes follow and fit; undo is one topo step back exactly, redo re-applies;
## (8) the model preview: Ctrl+B bevels the selected edge (one step), ] adds a segment, Shift+] widens, Alt+[ flattens
##     the profile, each rebuilding the SAME step; Ctrl+Z puts the cube back; [ then belongs to the shape keys again;
##     the S box line "Model: bevel" (op:bevel) runs it too.
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
const W := 0.02
func cube() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), CF)
func clean(m: KMesh) -> bool:
	return m.is_closed() and m.is_manifold() and KMeshValidate.report(m)["ok"]
func kinds(m: KMesh) -> Array:
	return (KMeshValidate.report(m)["problems"] as Array).map(func(p): return "%s x%d" % [p["kind"], p["count"]])
## distance from p to the line of the edge x = 1, z = 0 (along y)
func dline(p: Vector3) -> float:
	return Vector2(p.x - 1.0, p.z).length()
## the verts of m that are not one of the cube's 8 corners
func new_verts(m: KMesh) -> Array:
	var out := []
	for p in m.verts:
		var old := false
		for c in CV:
			old = old or p.distance_to(c) < 1e-9
		if not old:
			out.append(p)
	return out
## the verts not on an old face plane (x = 1 or z = 0 near the edge): the profile's inner points
func inner(m: KMesh) -> Array:
	return new_verts(m).filter(func(p): return absf(p.x - 1.0) > 1e-6 and absf(p.z) > 1e-6)
func mid_dist(prof: float) -> float:
	var m := cube()
	KMeshBevel.bevel_edges(m, [Vector2i(1, 2)], W, 2, prof)
	var d := -1.0
	for p in inner(m):
		if absf(p.y) < 1e-9:
			d = Vector2(p.x - (1.0 - W), p.z - W).length()
	if prof >= 0.999:   # the square corner: the middle point is the old corner itself (on both planes)
		for p in m.verts:
			if p.distance_to(Vector3(1, 0, 0)) < 1e-6:
				d = Vector2(p.x - (1.0 - W), p.z - W).length()
	return d
func _init() -> void:
	# (1)
	var c := cube()
	var r := KMeshBevel.bevel_edges(c, [Vector2i(1, 2)], W, 1)
	var nv := new_verts(c)
	var worst := 0.0
	var onplane := true
	for p in nv:
		worst = maxf(worst, absf(dline(p) - W))
		onplane = onplane and (absf(p.x - 1.0) < 1e-6 or absf(p.z) < 1e-6) and (absf(p.y) < 1e-9 or absf(p.y - 1.0) < 1e-9)
	var vol := KMeshValidate._volume(c)
	ok(r["error"] == "" and c.vert_count() == 10 and c.face_count() == 7 and clean(c) and nv.size() == 4 and worst < 1e-6 and onplane and absf(vol - (1.0 - W * W / 2.0)) < 1e-6,
		"(1) 1 segment: %d verts %d faces (bar 10 / 7), clean %s %s, %d new verts, worst distance error from the edge %.9f m (bar 1e-6), in the old planes %s, volume %.8f (bar %.8f)" % [c.vert_count(), c.face_count(), clean(c), str(kinds(c)), nv.size(), worst, onplane, vol, 1.0 - W * W / 2.0])
	# (2)
	var c3 := cube()
	var r3 := KMeshBevel.bevel_edges(c3, [Vector2i(1, 2)], W, 3, 0.5)
	var arc := 0.0
	var ins := inner(c3)
	var angs := []
	for p in ins:
		arc = maxf(arc, absf(Vector2(p.x - (1.0 - W), p.z - W).length() - W))
		if absf(p.y) < 1e-9:
			angs.append(rad_to_deg(atan2(p.x - (1.0 - W), -(p.z - W))))
	angs.sort()
	var bw := 0.0
	for p in new_verts(c3):
		if not ins.has(p):
			bw = maxf(bw, absf(dline(p) - W))
	var ngon := 0
	for f in c3.faces:
		ngon += 1 if (f as PackedInt32Array).size() == 7 else 0
	var v3 := KMeshValidate._volume(c3)
	ok(r3["error"] == "" and c3.vert_count() == 14 and c3.face_count() == 9 and clean(c3) and ins.size() == 4 and arc < 1e-4 and bw < 1e-6 and ngon == 2 and (r3["faces"] as Array).size() == 3,
		"(2) 3 segments round: %d verts %d faces (bar 14 / 9), clean %s, %d profile verts, worst off the arc %.3f mm (bar 0.1 mm), boundary verts off by %.9f m, %d end 7-gons, %d bevel faces selected" % [c3.vert_count(), c3.face_count(), clean(c3), ins.size(), arc * 1000.0, bw, ngon, (r3["faces"] as Array).size()])
	ok(angs.size() == 2 and absf(angs[0] - 30.0) < 0.01 and absf(angs[1] - 60.0) < 0.01 and absf(v3 - (1.0 - W * W / 4.0)) < 1e-6,
		"(2b) profile verts at %s deg round O (bar 30, 60: evenly spaced), volume %.8f (bar %.8f)" % [str(angs.map(func(a): return snappedf(a, 0.001))), v3, 1.0 - W * W / 4.0])
	# (3)
	var ds := [0.1, 0.25, 0.5, 0.75, 1.0].map(func(pf): return mid_dist(pf))
	var rising := true
	for i in range(1, ds.size()):
		rising = rising and ds[i] > ds[i - 1] + 1e-6
	ok(rising and absf(ds[1] - W / sqrt(2.0)) < 1e-6 and absf(ds[2] - W) < 1e-6 and absf(ds[4] - W * sqrt(2.0)) < 1e-6,
		"(3) middle vert from O, profiles 0.1 / 0.25 / 0.5 / 0.75 / 1: %s mm (bars: rising; 0.25 = %.4f chamfer, 0.5 = %.4f arc, 1 = %.4f corner)" % [str(ds.map(func(d): return snappedf(d * 1000.0, 0.0001))), W / sqrt(2.0) * 1000.0, W * 1000.0, W * sqrt(2.0) * 1000.0])
	# (4)
	var all1 := cube()
	KMeshBevel.bevel_edges(all1, all1.edges(), W, 1)
	var all2 := cube()
	KMeshBevel.bevel_edges(all2, all2.edges(), W, 2)
	var two := cube()
	KMeshBevel.bevel_edges(two, [Vector2i(1, 2), Vector2i(2, 6)], W, 3)
	ok(all1.vert_count() == 24 and all1.face_count() == 26 and clean(all1) and all2.vert_count() == 48 and all2.face_count() == 38 and clean(all2) and clean(two),
		"(4) all 12 edges: 1 seg %d / %d (bar 24 / 26) clean %s; 2 seg %d / %d (bar 48 / 38) clean %s %s; two edges at a corner, 3 seg: %d / %d clean %s %s" % [all1.vert_count(), all1.face_count(), clean(all1), all2.vert_count(), all2.face_count(), clean(all2), str(kinds(all2)), two.vert_count(), two.face_count(), clean(two), str(kinds(two))])
	# (5)
	var g := KMeshView.make_cube(1.0, 4)
	var ge := g.edges().filter(func(e): return absf(g.verts[e.x].x - 0.5) < 1e-9 and absf(g.verts[e.y].x - 0.5) < 1e-9 and absf(g.verts[e.x].z - 0.5) < 1e-9 and absf(g.verts[e.y].z - 0.5) < 1e-9)
	var g0 := g.face_count()
	var rg := KMeshBevel.bevel_edges(g, ge, W, 3)
	var gv := KMeshValidate._volume(g)
	ok(ge.size() == 4 and rg["error"] == "" and clean(g) and g.face_count() == g0 + 12 and absf(gv - (1.0 - W * W / 4.0)) < 1e-6,
		"(5) a whole cube edge on the 4x4 cube (%d edges), 3 segments: +%d faces (bar 12), clean %s %s, volume %.8f (bar %.8f)" % [ge.size(), g.face_count() - g0, clean(g), str(kinds(g)), gv, 1.0 - W * W / 4.0])
	# (6)
	var pl := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0)]), [[0,1,2,3]])
	var bad := KMeshBevel.bevel_edges(pl, [Vector2i(1, 2)], W)
	var wide := cube()
	var rw := KMeshBevel.bevel_edges(wide, wide.edges(), 0.8, 1)
	ok(bad["error"] != "" and pl.face_count() == 1 and rw["clamped"] and float(rw["width"]) <= 0.5 and clean(wide),
		"(6) open border refused (%s); 80 cm on a 1 m cube clamped to %s, clean %s %s" % [bad["error"], Units.len(float(rw["width"])), clean(wide), str(kinds(wide))])
	# (7)
	var at := cube()
	at.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	at.add_attr("col", KMesh.AD_VERT, TYPE_COLOR, Color.WHITE)
	at.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2, Vector2.ZERO)
	at.set_attr("mat", 4, 7.0)
	at.set_attr("col", 1, Color.RED)
	var at_v := at.verts.duplicate()
	var at_f := at.faces.duplicate()
	var at_a := at.attr_snapshot()
	var u := KMeshUndo.new()
	u.begin(at)
	var ra := KMeshBevel.bevel_edges(at, [Vector2i(1, 2)], W, 3)
	var st := u.commit("Bevel")
	var a_ok := (at.attr_data("uv") as PackedVector2Array).size() == at.half_edge_count() and (at.attr_data("col") as PackedColorArray).size() == at.vert_count()
	var red := 0
	for vi in at.vert_count():
		if at.verts[vi].y < 1e-9 and at.verts[vi].x > 0.9 and at.verts[vi].z < 0.1:
			red += 1 if at.get_attr("col", vi) == Color.RED else 0
	a_ok = a_ok and red == 4 and is_equal_approx(at.get_attr("mat", 4), 7.0)
	ok(a_ok, "(7a) attributes: sizes fit, the 4 verts that replace corner 1 keep its red (%d), the side face keeps mat 7" % red)
	u.undo()
	var back := at.verts == at_v and at.faces == at_f
	for k in at_a:
		back = back and at.attrs[k]["data"] == at_a[k]["data"]
	u.redo()
	ok(st.get("kind", "") == "topo" and u.steps.size() == 1 and back and at.vert_count() == 14 and clean(at) and ra["error"] == "",
		"(7b) one %s step; undo back exactly %s; redo %d verts again" % [st.get("kind", "?"), back, at.vert_count()])
	# (8) the model preview
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	mn._kmesh_edit_start()
	await process_frame
	var ui = mn.kmed
	var m: KMesh = ui.mesh
	var f0: int = m.face_count()
	var v0: int = m.vert_count()
	var h: float = KMeshEditUI.SIDE * 0.5
	var pick := Vector2i(-1, -1)
	for e in m.edges():
		var a: Vector3 = m.verts[e.x]
		var b: Vector3 = m.verts[e.y]
		if absf(a.x - h) < 1e-6 and absf(b.x - h) < 1e-6 and absf(a.z - h) < 1e-6 and absf(b.z - h) < 1e-6 and minf(a.y, b.y) < -h + 1e-6:
			pick = e   # the cube-edge segment at a corner (one end valence 3, the other valence 4)
	ui.set_mode(KMeshSelect.EDGE)
	ui.sel.edges[pick] = true
	var n0: int = ui.undo.steps.size()
	var kb := InputEventKey.new()
	kb.pressed = true
	kb.ctrl_pressed = true
	kb.keycode = KEY_B
	var used: bool = ui.input(kb)
	var f1: int = m.face_count()
	var said1: String = mn.ui_status.text
	var kr := InputEventKey.new()
	kr.pressed = true
	kr.keycode = KEY_BRACKETRIGHT
	ui.input(kr)
	var f2: int = m.face_count()
	kr.shift_pressed = true
	ui.input(kr)
	var lv: Dictionary = KMeshBevel.live_of(ui)
	var kl := InputEventKey.new()
	kl.pressed = true
	kl.alt_pressed = true
	kl.keycode = KEY_BRACKETLEFT
	ui.input(kl)
	lv = KMeshBevel.live_of(ui)
	var one: bool = ui.undo.steps.size() == n0 + 1
	var cl := clean(m)
	var wmax := 0.0
	for vi in range(0, m.vert_count()):
		var p: Vector3 = m.verts[vi]
		if absf(p.y + h) < 1e-6 and (absf(p.x - h) < 1e-6) != (absf(p.z - h) < 1e-6) and (p.x > h - 0.03 and p.z > h - 0.03):
			wmax = maxf(wmax, Vector2(p.x - h, p.z - h).length())
	ok(used and pick.x != -1 and f1 == f0 + 1 + 1 and f2 == f1 + 1 and one and cl and absf(float(lv.get("width", 0.0)) - 0.025) < 1e-9 and int(lv.get("segments", 0)) == 2 and absf(float(lv.get("profile", 0.0)) - 0.45) < 1e-9 and absf(wmax - 0.025) < 1e-6,
		"(8a) Ctrl+B: %d -> %d faces (bar +2: the strip + the valence-4 end's corner face), ] -> %d (2 segments), Shift+] width %s, Alt+[ profile %.2f; undo steps %d -> %d (bar one), clean %s, new edge %s from the old (bar 2.5 cm); said: %s" % [f0, f1, f2, Units.len(float(lv.get("width", 0.0))), float(lv.get("profile", 0.0)), n0, ui.undo.steps.size(), cl, Units.len(wmax), said1.left(90)])
	var kz := InputEventKey.new()
	kz.pressed = true
	kz.ctrl_pressed = true
	kz.keycode = KEY_Z
	ui.input(kz)
	var back_ok: bool = m.face_count() == f0 and m.vert_count() == v0 and ui.undo.steps.size() == n0 and KMeshBevel.live_of(ui).is_empty()
	var kl2 := InputEventKey.new()
	kl2.pressed = true
	kl2.keycode = KEY_BRACKETLEFT
	var bev_took: bool = KMeshBevel.key(ui, kl2)
	ok(back_ok and not bev_took and clean(m), "(8b) Ctrl+Z: %d faces %d verts again (bar %d / %d), not live, [ left to the shape keys %s" % [m.face_count(), m.vert_count(), f0, v0, not bev_took])
	ui.set_mode(KMeshSelect.EDGE)
	ui.sel.edges[pick] = true
	var t: Dictionary = MeshTools.TOOLS.filter(func(x): return x["id"] == "mesh_bevel")[0]
	MeshTools.run(t, mn)
	ok(t["do"] == "op:bevel" and m.face_count() == f0 + 2 and ui.undo.steps.size() == n0 + 1 and String(mn.ui_status.text).contains("bevelled"),
		"(8c) the S box line '%s' (%s, key %s): %d faces; said: %s" % [t["label"], t["do"], t["keys"], m.face_count(), String(mn.ui_status.text).left(60)])
	ui.stop()
	print("bevel: %d failures" % fails)
	quit(1 if fails > 0 else 0)
