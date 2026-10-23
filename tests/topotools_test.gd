## godot --path . -s tests/topotools_test.gd     (ROADMAP_400 F06 + F08; needs a window for bar 6: pixels read back)
## TRIANGULATE / QUADRANGULATE + TOPOLOGY HEAT MAP (scripts/kmesh_topo.gd). Bars, written before measuring:
##   1 CUBE: a 1 m cube (8 verts, 6 quads) triangulates to exactly 12 triangles, 18 edges, closed, manifold, volume 1 m^3
##     (1e-9); every corner keeps its A09 corner attribute ("uv" = (source face, vertex): 36 of 36
##     corners right), every triangle its face attribute, the 12 old edges keep their "crease" and the 6 new diagonals take 0;
##     tris to quads gives back exactly 6 quads, 12 edges, each the same vertex set as an original face, uv still right
##   2 SEAM: one diagonal corner's uv changed: that pair is not joined (5 quads + 2 triangles left)
##   3 BEAUTY: a rhombus (diagonals 2 and 1) splits along the 1 m one; a concave dart quad takes its one inside diagonal
##     (area kept, 1e-9); beauty off splits the rhombus from corner 0
##   4 CONCAVE N-GON: an L-shaped hexagon (area 3 m^2) whose corner 0 is next to the reflex corner, tilted in 3D:
##     4 triangles, areas summing to the face's (1e-6: float32 verts; the face is 3 within 1e-5), every one wound like the face (normal . face normal > 0.99), centroids
##     inside the L; a naive fan from corner 0 would not (the area its triangles cover differs from 3 by > 0.5)
##   5 HEAT: a UV sphere (16 segments, 8 rings, triangle caps) flags exactly its 2 poles (pole 6+, 16 edges each), no
##     pole 3 / 5, 32 triangles, 0 n-gons, 0 stretched quads; the same sphere stretched 4 x tall has stretched quads
##     (> 0, aspect > 3); the 4 x 4 test cube flags exactly its 8 corners as pole 3; a 3 x 3 grid (open) flags nothing
##     (borders are not poles); the L face is 1 n-gon
##   6 OVERLAY (window): on the Model test cube H turns the heat map on: the legend is visible, inside the free view
##     (nav_clear_rect) and says "pole 3: 8"; Ctrl+T (a real key event) gives 192 triangles in ONE undo step; a triangle's
##     centroid pixel differs from the same pixel with the heat map off (colour distance > 0.1) and is yellower (r+g-2b
##     higher); before Ctrl+T a cube corner vertex's pixel is blue (b > r + 0.2); Alt+J gives back 96 quads; Ctrl+Z twice -> 192 -> 96 faces
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, ctrl := false, alt := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.alt_pressed = alt
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func volume(k: KMesh) -> float:
	return KMeshValidate._volume(k)


func tri_area(k: KMesh, f: PackedInt32Array) -> float:
	return KMeshValidate._area(k, f)


func uv_sphere(seg: int, rings: int, r := 1.0, ys := 1.0) -> KMesh:
	var vs := PackedVector3Array([Vector3(0, r * ys, 0)])
	for i in range(1, rings):
		var th := PI * i / rings
		for j in seg:
			var ph := TAU * j / seg
			vs.append(Vector3(r * sin(th) * cos(ph), r * cos(th) * ys, r * sin(th) * sin(ph)))
	vs.append(Vector3(0, -r * ys, 0))
	var bot := vs.size() - 1
	var at := func(i: int, j: int) -> int: return 1 + (i - 1) * seg + (j % seg)
	var fs := []
	for j in seg:
		fs.append([0, at.call(1, j + 1), at.call(1, j)])
		fs.append([bot, at.call(rings - 1, j), at.call(rings - 1, j + 1)])
	for i in range(1, rings - 1):
		for j in seg:
			fs.append([at.call(i, j), at.call(i, j + 1), at.call(i + 1, j + 1), at.call(i + 1, j)])
	return KMesh.new().from_arrays(vs, fs)


func _init() -> void:
	# ---- bar 1
	var c := KMeshView.make_cube(1.0, 1)
	c.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	c.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT)
	c.add_attr("crease", KMesh.AD_EDGE, TYPE_FLOAT)
	var orig := []
	for fi in c.face_count():
		var f: PackedInt32Array = c.faces[fi]
		c.set_attr("mat", fi, float(fi))
		var vs := f.duplicate()
		vs.sort()
		orig.append(vs)
		for i in f.size():
			c.set_attr("uv", c.face_he0[fi] + i, Vector2(fi, f[i]))
	var es: Array = c.edges()
	for ei in es.size():
		c.set_attr("crease", ei, 1.0 + es[ei].x * 10 + es[ei].y)
	var r := KMeshTopo.triangulate(c)
	var uv_ok := func(k: KMesh) -> int:
		var good := 0
		for fi in k.face_count():
			var f: PackedInt32Array = k.faces[fi]
			for i in f.size():
				if k.get_attr("uv", k.face_he0[fi] + i) == Vector2(k.get_attr("mat", fi), f[i]):
					good += 1
		return good
	var cr_keep := 0
	var cr_new := 0
	var es2: Array = c.edges()
	for ei in es2.size():
		var v: float = c.get_attr("crease", ei)
		if v == 1.0 + es2[ei].x * 10 + es2[ei].y:
			cr_keep += 1
		elif v == 0.0:
			cr_new += 1
	var g1: int = uv_ok.call(c)
	ok(c.face_count() == 12 and int(r["tris"]) == 12 and c.edge_count() == 18 and c.is_closed() and c.is_manifold() and absf(volume(c) - 1.0) < 1e-9,
		"bar 1: cube -> %d triangles (%d made), %d edges, closed %s, manifold %s, volume %.9f m^3" % [c.face_count(), int(r["tris"]), c.edge_count(), c.is_closed(), c.is_manifold(), volume(c)])
	ok(g1 == 36 and cr_keep == 12 and cr_new == 6, "bar 1: attributes carried: uv right on %d of 36 corners, %d old edges kept their crease, %d new diagonals at 0" % [g1, cr_keep, cr_new])
	var q := KMeshTopo.quadrangulate(c)
	var same := 0
	for fi in c.face_count():
		var vs := (c.faces[fi] as PackedInt32Array).duplicate()
		vs.sort()
		if orig.has(vs):
			same += 1
	var g2: int = uv_ok.call(c)
	ok(c.face_count() == 6 and int(q["quads"]) == 6 and int(q["left"]) == 0 and c.edge_count() == 12 and same == 6 and g2 == 24 and absf(volume(c) - 1.0) < 1e-9,
		"bar 1: back to %d quads (%d joined, %d triangles left), %d edges, %d of 6 match an original face, uv right on %d of 24, volume %.9f" % [c.face_count(), int(q["quads"]), int(q["left"]), c.edge_count(), same, g2, volume(c)])

	# ---- bar 2
	var s := KMeshView.make_cube(1.0, 1)
	s.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	KMeshTopo.triangulate(s)
	s.set_attr("uv", s.face_he0[0] + 0, Vector2(9, 9))   # corner 0 of triangle 0 is an end of its diagonal (fan from corner 0)
	var q2 := KMeshTopo.quadrangulate(s)
	ok(int(q2["quads"]) == 5 and int(q2["left"]) == 2, "bar 2: a uv seam on one diagonal keeps that pair apart: %d quads, %d triangles left" % [int(q2["quads"]), int(q2["left"])])
	var s2 := KMeshView.make_cube(1.0, 1)
	s2.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	KMeshTopo.triangulate(s2)
	s2.set_attr("uv", s2.face_he0[0] + 0, Vector2(9, 9))
	ok(int(KMeshTopo.quadrangulate(s2, null, KMeshTopo.FACE_LIMIT, KMeshTopo.SHAPE_LIMIT, false)["quads"]) == 6, "bar 2: with seams off the same mesh joins all 6")

	# ---- bar 3
	var rh := KMesh.new().from_arrays(PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, -0.5, 0), Vector3(1, 0, 0), Vector3(0, 0.5, 0)]), [[0, 1, 2, 3]])
	var rt := KMeshTopo.face_tris(rh, rh.faces[0])
	ok(rt == [[0, 1, 3], [1, 2, 3]], "bar 3: the rhombus splits along the 1 m diagonal (1-3), not the 2 m one: %s" % str(rt))
	ok(KMeshTopo.face_tris(rh, rh.faces[0], false) == [[0, 1, 2], [0, 2, 3]], "bar 3: beauty off: from corner 0")
	var dart := KMesh.new().from_arrays(PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(0, 2, 0), Vector3(0.5, 1, 0)]), [[0, 1, 2, 3]])
	var da0 := tri_area(dart, dart.faces[0])
	KMeshTopo.triangulate(dart)
	var da := 0.0
	var dpos := true
	for f in dart.faces:
		da += tri_area(dart, f)
		dpos = dpos and dart.face_normals[dart.faces.find(f)].z > 0.99
	ok(dart.face_count() == 2 and absf(da - da0) < 1e-9 and dpos, "bar 3: concave dart (area %.3f m^2) -> %d triangles, area %.9f, all facing +z %s, diagonal %s" % [da0, dart.face_count(), da, dpos, str(dart.faces)])

	# ---- bar 4
	var L2 := [Vector2(2, 1), Vector2(1, 1), Vector2(1, 2), Vector2(0, 2), Vector2(0, 0), Vector2(2, 0)]
	var basis := Basis(Vector3(1, 2, 0.5).normalized(), 0.7)
	var lv := PackedVector3Array()
	for p in L2:
		lv.append(basis * Vector3(p.x, p.y, 0) + Vector3(0.3, -0.2, 1.1))
	var lm := KMesh.new().from_arrays(lv, [[0, 1, 2, 3, 4, 5]])
	var ln := lm.face_normals[0]
	var lh := KMeshTopo.heat(lm)
	var la0 := tri_area(lm, lm.faces[0])
	var naive := 0.0
	for i in range(1, 5):
		naive += absf((L2[i] - L2[0]).cross(L2[i + 1] - L2[0])) * 0.5   # the area a naive fan covers (some of it outside)
	KMeshTopo.triangulate(lm)
	var la := 0.0
	var wound := 0
	var inside := 0
	var poly := PackedVector2Array(L2)
	for fi in lm.face_count():
		var f: PackedInt32Array = lm.faces[fi]
		la += tri_area(lm, f)
		if lm.face_normals[fi].dot(ln) > 0.99:
			wound += 1
		var cen: Vector3 = basis.inverse() * (lm.face_center(fi) - Vector3(0.3, -0.2, 1.1))
		if Geometry2D.is_point_in_polygon(Vector2(cen.x, cen.y), poly):
			inside += 1
	ok(lm.face_count() == 4 and absf(la0 - 3.0) < 1e-5 and absf(la - la0) < 1e-6 and wound == 4 and inside == 4 and absf(naive - 3.0) > 0.5,
		"bar 4: L hexagon (area %.9f m^2) -> %d triangles, area %.9f (diff %.12f), %d of 4 wound like the face, %d of 4 centroids inside; a fan from corner 0 covers %.3f m^2" % [la0, lm.face_count(), la, la - la0, wound, inside, naive])

	# ---- bar 5
	var sp := uv_sphere(16, 8)
	var h := KMeshTopo.heat(sp)
	var hc: Dictionary = h["counts"]
	var p6 := []
	for v in sp.vert_count():
		if h["vert"][v] == KMeshTopo.V_POLE6:
			p6.append([v, h["valence"][v]])
	ok(p6 == [[0, 16], [sp.vert_count() - 1, 16]] and hc["pole3"] == 0 and hc["pole5"] == 0 and hc["tri"] == 32 and hc["ngon"] == 0 and hc["stretch"] == 0,
		"bar 5: UV sphere (%d verts, %d faces): pole 6+ at %s, counts %s" % [sp.vert_count(), sp.face_count(), str(p6), str(hc)])
	var tall := uv_sphere(16, 8, 1.0, 4.0)
	var th := KMeshTopo.heat(tall)
	var worst := 0.0
	for fi in tall.face_count():
		if th["face"][fi] == KMeshTopo.F_STRETCH:
			worst = maxf(worst, KMeshTopo.quad_shape(tall, tall.faces[fi]).x)
	ok(int(th["counts"]["stretch"]) > 0 and worst > 3.0, "bar 5: 4 x tall sphere: %d stretched quads (worst aspect %.2f)" % [int(th["counts"]["stretch"]), worst])
	var cb := KMeshTopo.heat(KMeshView.make_cube(0.6, 4))
	ok(cb["counts"]["pole3"] == 8 and cb["counts"]["pole5"] == 0 and cb["counts"]["pole6"] == 0, "bar 5: 4 x 4 cube: counts %s" % str(cb["counts"]))
	var gv := PackedVector3Array()
	var gf := []
	for y in 4:
		for x in 4:
			gv.append(Vector3(x, y, 0))
	for y in 3:
		for x in 3:
			gf.append([y * 4 + x, y * 4 + x + 1, (y + 1) * 4 + x + 1, (y + 1) * 4 + x])
	var gh := KMeshTopo.heat(KMesh.new().from_arrays(gv, gf))
	var gsum := 0
	for k in gh["counts"]:
		gsum += int(gh["counts"][k])
	ok(gsum == 0, "bar 5: open 3 x 3 grid flags nothing: %s" % str(gh["counts"]))
	ok(lh["counts"]["ngon"] == 1, "bar 5: the L face is %d n-gon" % int(lh["counts"]["ngon"]))

	# ---- bar 6
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = m.kmed
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	await key(KEY_H)
	var lg: PanelContainer = ui.legend
	var cl: Rect2 = m.nav_clear_rect()
	var lr: Rect2 = lg.get_global_rect() if lg != null else Rect2()
	var p3txt: String = (lg.get_node("rows/pole3/words") as Label).text if lg != null else ""
	ok(lg != null and lg.visible and ui.view.show_heat and cl.encloses(lr) and lr.size.x > 40 and p3txt.begins_with("pole 3: 8"),
		"bar 6: H: legend visible %s at %s inside the free view %s, says '%s'" % [lg != null and lg.visible, lr, cl, p3txt])
	var corner := -1
	for v in ui.mesh.vert_count():
		if ui.mesh.verts[v].is_equal_approx(Vector3(-0.3, -0.3, 0.3)):
			corner = v
	var vcp: Vector2 = m.cam.unproject_position(ui.view.global_transform * ui.mesh.verts[corner])
	m.ui_root.visible = false
	var img_q := await shot()
	m.ui_root.visible = true
	var cv := img_q.get_pixelv(Vector2i(vcp))
	ok(cv.b > cv.r + 0.2, "bar 6: the corner vertex %d at %s is blue (pole 3): %s" % [corner, vcp, cv.to_html(false)])
	var u0: int = ui.undo.steps.size()
	await key(KEY_T, true)
	ok(ui.mesh.face_count() == 192 and int(ui.view.heat["counts"]["tri"]) == 192 and ui.undo.steps.size() == u0 + 1,
		"bar 6: Ctrl+T: %d faces, heat counts %d triangles, undo steps %d -> %d" % [ui.mesh.face_count(), int(ui.view.heat["counts"]["tri"]), u0, ui.undo.steps.size()])
	# a front triangle's centroid (the camera looks down -z at the +z face)
	var best := -1
	var bd := 1e9
	for fi in ui.mesh.face_count():
		if ui.mesh.face_normals[fi].z > 0.99:
			var d: float = ui.mesh.face_center(fi).distance_to(Vector3(0.05, 0.05, 0.3))
			if d < bd:
				bd = d
				best = fi
	var tcp: Vector2 = m.cam.unproject_position(ui.view.global_transform * ui.mesh.face_center(best))
	m.ui_root.visible = false
	var img_on := await shot()
	ui.view.show_heat = false
	ui.view.rebuild()
	var img_off := await shot()
	ui.view.show_heat = true
	ui.view.rebuild()
	m.ui_root.visible = true
	var con := img_on.get_pixelv(Vector2i(tcp))
	var cof := img_off.get_pixelv(Vector2i(tcp))
	var yel := func(k: Color) -> float: return k.r + k.g - 2.0 * k.b
	ok(dist(con, cof) > 0.1 and yel.call(con) > yel.call(cof), "bar 6: triangle %d centroid %s is %s with the heat map, %s without (distance %.2f, yellower %.2f > %.2f)" % [best, tcp, con.to_html(false), cof.to_html(false), dist(con, cof), yel.call(con), yel.call(cof)])
	var outp := OS.get_environment("TOPO_SHOT")
	if outp != "":
		img_on.save_png(outp)
		print("shot saved: ", outp)
	await key(KEY_J, false, true)
	var nq: int = ui.mesh.face_count()
	await key(KEY_Z, true)
	var nz1: int = ui.mesh.face_count()
	await key(KEY_Z, true)
	var nz2: int = ui.mesh.face_count()
	ok(nq == 96 and nz1 == 192 and nz2 == 96, "bar 6: Alt+J -> %d faces; Ctrl+Z -> %d, Ctrl+Z -> %d" % [nq, nz1, nz2])
	print("TOPOTOOLS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
