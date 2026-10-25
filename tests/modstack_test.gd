## godot --path . -s tests/modstack_test.gd     (ROADMAP_400 A11 modifier stack; needs a window: pixels read back)
## Bars, written before measuring:
##   1 MIRROR: the +X half of a 0.6 m 2x2-per-side cube (17 verts, 12 faces, open at x = 0) mirrored on X with merge 1 mm
##     = 26 verts / 24 faces, closed, manifold, 0 border edges, every vertex on the full cube (max miss < 1e-6 m); merge off =
##     34 verts and 16 border edges (the seam open); seam verts pushed 0.5 mm off the plane: merge 1 mm merges them (26 verts,
##     the seam snapped to x = 0 within 1e-7), merge 0.1 mm does not (34)
##   2 SUBDIVIDE = KMeshSubdiv.subdivide (same 98 verts / 96 faces, same positions)
##   3 ORDER (REVISED after the first run: on the plain half cube both orders put the probe vertex at the same place, because
##     the cube is flat across the seam, where the crease and smooth rules agree; so the shape now has a ridge across the
##     seam: the top's centre vertex raised from 0.3 to 0.45 m): mirror -> subdiv = the full ridged cube subdivided (98 / 96,
##     max miss < 1e-6, closed), the peak at y = (Q + 2R + S) / 4 = 0.384375; subdiv -> mirror = 98 / 96, closed + manifold,
##     but the seam is a crease: the peak at y = (a + 6S + b) / 8 = 0.4125 (tol 1e-6 each; > 1 mm apart)
##   4 SOLIDIFY 2 cm, offset -1, on the 4x4 cube (98 / 96): 196 verts / 192 faces, closed; a face-centre vertex's twin is 2 cm
##     inside (within 0.1 mm); even off: a corner's twin is 2 / sqrt(3) = 1.155 cm from each side plane; even on: every twin is
##     2 cm from the plane of every face round its vertex (worst miss < 0.1 mm); an open 4x3 plane (20 / 12, 14 border edges)
##     gives 40 / 38 (rim on), closed + manifold, the two sheets 2 cm apart (within 0.1 mm)
##   5 ARRAY count 3, relative (1.5, 0, 0) + constant (0, 10 cm, 0) on the 0.6 m cube: 294 / 288, copy 2's vertex k = vertex k
##     + (1.8, 0.2, 0) within 1e-6
##   6 DISPLACE 5 cm: Y + no texture moves every vertex by exactly (0, 0.05, 0); normal + no texture moves each 5 cm along its
##     normal; noise: same seed = the same result, another seed differs, |d| <= 5 cm, mean |d| > 2 mm, > 20 distinct values
##   7 THE BASE IS UNTOUCHED by every evaluation above (verts, faces, stack equal to a copy taken before)
##   8 SAVE / LOAD: a 5-modifier stack (non-default params) round-trips through a .kmesh exactly, the loaded mesh evaluates to the
##     same verts; a stack with an unknown type fails to load with a message naming it; a file without a stack loads with []
##   9 UNDO: add = one "mods" step, undo empties the stack, redo brings it; apply (mirror on the half) = ONE step: 26 verts and
##     an empty stack, undo gives 17 verts and the mirror back; shape keys refuse the apply with a message
##  10 TIME (4 shared cores, other agents running): a 5,046-face cube (side 1 m, 29x29 per side) through mirror X -> solidify ->
##     array x2 -> displace (noise) = 40,368 faces in under 1500 ms; subdivide x1 -> displace = 20,184 faces in under 2500 ms
##  11 THE PREVIEW (main.tscn): the Modifiers panel shows with the test cube, inside the window, not over the Add primitive
##     panel; Add Array = one undo step, the base stays 98 / 96, the view's own surface hides and mod_surface draws 2 x 96 quads
##     (1,152 triangle corners); the count field set to 3 then 4 = one more step, 384 faces evaluated; mod_surface's box =
##     the cube plus 3 copies 0.6 m apart (x -0.3 .. 2.1 within 1e-5); PLACEMENT: the pixel at the projected centre of copy 1
##     differs (colour distance > 0.1) from the same pixel with the modifier ticked off; PICK stays on the base: a click there
##     selects nothing, a click on a base face selects it; a base edit (vertex 0 up 5 cm) shows in every copy; Ctrl+Z (a real
##     key) takes the edit back; Apply bakes 392 verts as one step and the view's own surface shows again; Ctrl+Z restores 98
##     verts and the stack; with five modifiers the panel still fits the window (the list scrolls past 60 % of its height);
##     Esc leaves and the panel goes
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the +X half of make_cube(0.6, 2): faces whose centre has x > 0, verts renumbered (17 / 12)
func half_cube() -> KMesh:
	var c := KMeshView.make_cube(0.6, 2)
	var ids := {}
	var vs := PackedVector3Array()
	var fs := []
	for fi in c.face_count():
		if c.face_center(fi).x <= 1e-6:
			continue
		var g := PackedInt32Array()
		for v in (c.faces[fi] as PackedInt32Array):
			if not ids.has(v):
				ids[v] = vs.size()
				vs.append(c.verts[v])
			g.append(ids[v])
		fs.append(g)
	return KMesh.new().from_arrays(vs, fs)


## the farthest any vertex of a is from the nearest of b (vertex order may differ)
func max_miss(a: KMesh, b: KMesh) -> float:
	var d := 0.0
	for p in a.verts:
		var best := INF
		for q in b.verts:
			best = minf(best, p.distance_to(q))
		d = maxf(d, best)
	return d


func nearest(m: KMesh, p: Vector3) -> Vector3:
	var best := Vector3.INF
	for q in m.verts:
		if q.distance_to(p) < best.distance_to(p):
			best = q
	return best


func cnt(m: KMesh) -> Vector2i:
	return Vector2i(m.vert_count(), m.face_count())


func _init() -> void:
	await idle(1)
	# ---- 1 mirror
	var half := half_cube()
	var full := KMeshView.make_cube(0.6, 2)
	var h_v := half.verts.duplicate()
	var h_f := half.faces.duplicate()
	ok(cnt(half) == Vector2i(17, 12) and half.boundary_edge_count() == 8, "the half cube: %s verts / faces, %d border edges (expect 17 / 12, 8)" % [cnt(half), half.boundary_edge_count()])
	var mm := KMeshModifiers.mirror(half, 0, true, 0.001)
	ok(cnt(mm) == Vector2i(26, 24) and mm.is_closed() and mm.is_manifold() and mm.boundary_edge_count() == 0 and max_miss(mm, full) < 1e-6,
		"(1) mirror X merge 1 mm: %s (expect 26 / 24), closed %s, manifold %s, %d border edges, max miss to the full cube %.9f m" % [cnt(mm), mm.is_closed(), mm.is_manifold(), mm.boundary_edge_count(), max_miss(mm, full)])
	var mo := KMeshModifiers.mirror(half, 0, false)
	ok(cnt(mo) == Vector2i(34, 24) and mo.boundary_edge_count() == 16, "(1) merge off: %s (expect 34 / 24), %d border edges (expect 16: the seam open)" % [cnt(mo), mo.boundary_edge_count()])
	var off := KMesh.new().from_arrays(half.verts, half.faces)
	for v in off.vert_count():
		if absf(off.verts[v].x) < 1e-9:
			off.verts[v].x = 0.0005
	off.rebuild()
	var m1 := KMeshModifiers.mirror(off, 0, true, 0.001)
	var m01 := KMeshModifiers.mirror(off, 0, true, 0.0001)
	var seam_x := 0.0
	for v in m1.verts:
		if absf(v.x) < 0.01:
			seam_x = maxf(seam_x, absf(v.x))
	ok(m1.vert_count() == 26 and seam_x < 1e-7 and m1.is_closed() and m01.vert_count() == 34,
		"(1) seam 0.5 mm off the plane: merge 1 mm -> %d verts, seam |x| %.9f m (snapped), closed %s; merge 0.1 mm -> %d (not merged)" % [m1.vert_count(), seam_x, m1.is_closed(), m01.vert_count()])

	# ---- 2 subdivide
	var sd := KMeshModifiers.evaluate(full, [{"type": "subdiv", "levels": 1}])
	var sd0 := KMeshSubdiv.subdivide(full, 1)
	ok(cnt(sd) == Vector2i(98, 96) and sd.verts == sd0.verts, "(2) subdivide x1 = KMeshSubdiv: %s, positions identical %s" % [cnt(sd), sd.verts == sd0.verts])

	# ---- 3 order: a ridge across the seam (the top's centre vertex (0, 0.3, 0) raised to 0.45 m), so the surface curves
	# across the mirror plane (a flat cube cannot show the order: there the crease and smooth rules agree on the seam)
	var peak := Vector3(0, 0.45, 0)
	var ph := half_cube()
	var pf := KMeshView.make_cube(0.6, 2)
	for k in [ph, pf]:
		for v in (k as KMesh).vert_count():
			if k.verts[v].distance_to(Vector3(0, 0.3, 0)) < 1e-6:
				k.verts[v] = peak
		(k as KMesh).rebuild()
	var A := KMeshModifiers.evaluate(ph, [{"type": "mirror"}, {"type": "subdiv"}])
	var B := KMeshModifiers.evaluate(ph, [{"type": "subdiv"}, {"type": "mirror"}])
	var sdp := KMeshSubdiv.subdivide(pf, 1)
	var pa := nearest(A, Vector3(0, 0.4, 0))
	var pb := nearest(B, Vector3(0, 0.4, 0))
	ok(cnt(A) == Vector2i(98, 96) and max_miss(A, sdp) < 1e-6 and A.is_closed() and absf(pa.y - 0.384375) < 1e-6,
		"(3) mirror -> subdiv = the full ridged cube subdivided: %s, max miss %.9f m, closed %s; the peak at %s (smooth rule (Q + 2R + S) / 4: expect y 0.384375)" % [cnt(A), max_miss(A, sdp), A.is_closed(), pa])
	ok(cnt(B) == Vector2i(98, 96) and B.is_closed() and B.is_manifold() and pb.distance_to(Vector3(0, 0.4125, 0)) < 1e-6 and pa.distance_to(pb) > 0.001,
		"(3) subdiv -> mirror: %s, closed %s, manifold %s; the peak at %s (crease rule (a + 6S + b) / 8: expect y 0.4125), %.2f mm from mirror -> subdiv" % [cnt(B), B.is_closed(), B.is_manifold(), pb, pa.distance_to(pb) * 1000.0])

	# ---- 4 solidify
	var cube := KMeshView.make_cube(0.6, 4)
	var c_v := cube.verts.duplicate()
	var c_f := cube.faces.duplicate()
	var t := 0.02
	var so := KMeshModifiers.solidify(cube, t, -1.0, false)
	var fcv := -1   # the +X face's centre vertex (0.3, 0, 0)
	var cor := -1   # the corner (0.3, 0.3, 0.3)
	for v in cube.vert_count():
		if cube.verts[v].distance_to(Vector3(0.3, 0, 0)) < 1e-6:
			fcv = v
		if cube.verts[v].distance_to(Vector3(0.3, 0.3, 0.3)) < 1e-6:
			cor = v
	var nv := cube.vert_count()
	var flat_t := 0.3 - so.verts[fcv + nv].x
	var cor_d := 0.3 - so.verts[cor + nv].x
	ok(cnt(so) == Vector2i(196, 192) and so.is_closed() and absf(flat_t - t) < 1e-4 and absf(cor_d - t / sqrt(3.0)) < 1e-4,
		"(4) solidify 2 cm: %s (expect 196 / 192), closed %s; face-centre twin %.4f cm inside (expect 2), corner twin %.4f cm from each side (expect %.4f)" % [cnt(so), so.is_closed(), flat_t * 100, cor_d * 100, t / sqrt(3.0) * 100])
	var se := KMeshModifiers.solidify(cube, t, -1.0, true)
	var worst := 0.0
	for v in nv:
		for fi in cube.vert_faces(v):
			var n := cube.face_normals[fi]
			var d := n.dot(cube.verts[v] - se.verts[v + nv])
			worst = maxf(worst, absf(d - t))
	ok(worst < 1e-4 and cnt(se) == Vector2i(196, 192), "(4) even: every twin 2 cm from the plane of every face round its vertex, worst miss %.4f mm (bar 0.1 mm)" % (worst * 1000))
	var pl := KMeshPrims.plane(0.4, 0.3, 4, 3)
	var sp := KMeshModifiers.solidify(pl, t, -1.0, false, true)
	var gap := 0.0
	for v in pl.vert_count():
		gap = maxf(gap, absf(pl.verts[v].distance_to(sp.verts[v + pl.vert_count()]) - t))
	ok(cnt(pl) == Vector2i(20, 12) and pl.boundary_edge_count() == 14 and cnt(sp) == Vector2i(40, 38) and sp.is_closed() and sp.is_manifold() and gap < 1e-4,
		"(4) the 4x3 plane: %s -> %s (expect 40 / 38), closed %s, manifold %s, sheets 2 cm apart (worst miss %.4f mm)" % [cnt(pl), cnt(sp), sp.is_closed(), sp.is_manifold(), gap * 1000])

	# ---- 5 array
	var ar := KMeshModifiers.evaluate(cube, [{"type": "array", "count": 3, "rel_x": 1.5, "off_y": 0.1}])
	var amiss := 0.0
	for v in nv:
		amiss = maxf(amiss, ar.verts[2 * nv + v].distance_to(cube.verts[v] + Vector3(1.8, 0.2, 0)))
	ok(cnt(ar) == Vector2i(294, 288) and amiss < 1e-6, "(5) array x3, relative 1.5 + 10 cm up: %s (expect 294 / 288), copy 2 offset miss %.9f m (expect (1.8, 0.2, 0))" % [cnt(ar), amiss])

	# ---- 6 displace
	var dy := KMeshModifiers.evaluate(cube, [{"type": "displace", "strength": 0.05, "direction": 2, "texture": 0}])
	var dmiss := 0.0
	var nmiss := 0.0
	var dn := KMeshModifiers.evaluate(cube, [{"type": "displace", "strength": 0.05, "direction": 0, "texture": 0}])
	for v in nv:
		dmiss = maxf(dmiss, dy.verts[v].distance_to(cube.verts[v] + Vector3(0, 0.05, 0)))
		nmiss = maxf(nmiss, dn.verts[v].distance_to(cube.verts[v] + cube.vert_normals[v] * 0.05))
	ok(cnt(dy) == Vector2i(98, 96) and dmiss < 1e-6 and nmiss < 1e-6, "(6) displace 5 cm: along Y miss %.9f m, along the normal miss %.9f m, %s" % [dmiss, nmiss, cnt(dy)])
	var nz := [{"type": "displace", "strength": 0.05, "texture": 1, "noise_size": 0.2, "seed": 7}]
	var d1 := KMeshModifiers.evaluate(cube, nz)
	var d2 := KMeshModifiers.evaluate(cube, nz)
	var d3 := KMeshModifiers.evaluate(cube, [{"type": "displace", "strength": 0.05, "texture": 1, "noise_size": 0.2, "seed": 8}])
	var dmax := 0.0
	var dsum := 0.0
	var distinct := {}
	for v in nv:
		var dd := d1.verts[v].distance_to(cube.verts[v])
		dmax = maxf(dmax, dd)
		dsum += dd
		distinct[snappedf(dd, 1e-5)] = true
	ok(d1.verts == d2.verts and d1.verts != d3.verts and dmax <= 0.05 + 1e-6 and dsum / nv > 0.002 and distinct.size() > 20,
		"(6) noise: seed 7 twice equal %s, seed 8 differs %s, max |d| %.2f cm (<= 5), mean %.2f mm (> 2), %d distinct" % [d1.verts == d2.verts, d1.verts != d3.verts, dmax * 100, dsum / nv * 1000, distinct.size()])

	# ---- 7 base untouched
	ok(half.verts == h_v and half.faces == h_f and half.modifiers.is_empty() and cube.verts == c_v and cube.faces == c_f and cube.modifiers.is_empty(),
		"(7) the bases are untouched by every evaluation (half %s, cube %s)" % [cnt(half), cnt(cube)])

	# ---- 8 save / load
	var sm := KMeshView.make_cube(0.6, 4)
	KMeshModifiers.add(sm, "mirror", {"axis": 2, "merge_dist": 0.002})
	KMeshModifiers.add(sm, "subdiv", {"levels": 2, "on": false})
	KMeshModifiers.add(sm, "solidify", {"thickness": 0.013, "even": true})
	KMeshModifiers.add(sm, "array", {"count": 4, "rel_x": 0.0, "off_z": 0.7})
	KMeshModifiers.add(sm, "displace", {"strength": -0.02, "texture": 1, "seed": 42})
	var path := "user://modstack_test.kmesh"
	var e := sm.save(path)
	var ld := KMesh.load_file(path)
	var same_stack := ld != null and ld.modifiers == sm.modifiers and ld.modifiers.size() == 5
	var ev_same := same_stack and KMeshModifiers.evaluate(ld).verts == KMeshModifiers.evaluate(sm).verts
	ok(e == OK and same_stack and ev_same and ld.modifiers[1]["on"] == false and is_equal_approx(ld.modifiers[2]["thickness"], 0.013),
		"(8) .kmesh round trip: stack of %d equal %s, evaluates the same %s" % [ld.modifiers.size() if ld != null else -1, same_stack, ev_same])
	var dct := sm.to_dict()
	dct["modifiers"] = [{"type": "warp"}]
	var bad := KMesh.new().from_dict(JSON.parse_string(JSON.stringify(dct)))
	var bad_msg := KMesh.last_error
	var plain := KMesh.new().from_dict(JSON.parse_string(JSON.stringify(KMeshView.make_cube(0.6, 4).to_dict())))
	ok(bad == null and bad_msg.contains("warp") and plain != null and plain.modifiers.is_empty(),
		"(8) unknown type refused: '%s'; a file without a stack loads with %s" % [bad_msg, str(plain.modifiers) if plain != null else "null"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# ---- 9 undo
	var um := half_cube()
	var undo := KMeshUndo.new()
	undo.begin(um)
	KMeshModifiers.add(um, "mirror")
	var st := undo.commit("Add mirror")
	ok(st.get("kind", "") == "mods" and undo.steps.size() == 1 and um.modifiers.size() == 1, "(9) add = one '%s' step (%d)" % [st.get("kind", ""), undo.steps.size()])
	undo.undo()
	var after_undo := um.modifiers.size()
	undo.redo()
	ok(after_undo == 0 and um.modifiers.size() == 1 and um.modifiers[0]["type"] == "mirror", "(9) undo empties the stack (%d), redo brings the mirror back (%d)" % [after_undo, um.modifiers.size()])
	undo.begin(um)
	var err := KMeshModifiers.apply_mod(um, 0)
	undo.commit("Apply mirror")
	var baked := cnt(um)
	var baked_closed := um.is_closed()
	var nsteps := undo.steps.size()
	undo.undo()
	ok(err == "" and baked == Vector2i(26, 24) and baked_closed and um.modifiers.is_empty() == false and cnt(um) == Vector2i(17, 12) and nsteps == 2,
		"(9) apply = one step (%d steps): baked %s closed %s; undo -> %s with the stack %s" % [nsteps, baked, baked_closed, cnt(um), str(um.modifiers.map(func(x): return x["type"]))])
	var sk := half_cube()
	KMeshShapes.add_from_current(sk, "Key 1")
	KMeshModifiers.add(sk, "mirror")
	var e2 := KMeshModifiers.apply_mod(sk, 0)
	ok(e2.contains("shape keys") and cnt(sk) == Vector2i(17, 12) and sk.modifiers.size() == 1, "(9) shape keys refuse the apply: '%s'" % e2)

	# ---- 10 time
	var big := KMeshView.make_cube(1.0, 29)
	var t0 := Time.get_ticks_msec()
	var r1 := KMeshModifiers.evaluate(big, [{"type": "mirror"}, {"type": "solidify"}, {"type": "array"}, {"type": "displace", "texture": 1}])
	var ms1 := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var r2 := KMeshModifiers.evaluate(big, [{"type": "subdiv"}, {"type": "displace", "texture": 1}])
	var ms2 := Time.get_ticks_msec() - t0
	ok(big.face_count() == 5046 and r1.face_count() == 40368 and ms1 < 1500, "(10) 5,046-face cube: mirror -> solidify -> array x2 -> displace = %d faces in %d ms (bar 1500)" % [r1.face_count(), ms1])
	ok(r2.face_count() == 20184 and ms2 < 2500, "(10) subdivide x1 -> displace = %d faces in %d ms (bar 2500)" % [r2.face_count(), ms2])

	await preview()
	print("MODSTACK ", "PASS" if fails == 0 else "FAIL %d" % fails)
	# ---- round 2 bar: the stack rows say what their buttons do, the Add buttons name the thing added
	var mstk = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mstk)
	await idle(6)
	mstk.tour_step = -1
	if mstk.ui_tour != null:
		mstk.ui_tour.visible = false
	mstk._kmesh_edit_start()
	await idle(3)
	mstk.kmed.mods.add(KMeshModifiers.TYPES[0])
	await idle(2)
	var ap = mstk.kmed.mods.panel.find_child("mod_0_apply", true, false)
	var ad = mstk.kmed.mods.panel.find_child("btn_mod_add", true, false)
	var am = mstk.kmed.mat_panel.find_child("btn_mat_add_material", true, false)
	var at := String(ap.text) if ap != null else "(none)"
	ok(at == "Apply " + KMeshModifiers.NAMES[KMeshModifiers.TYPES[0]] and ad != null and ad.text == "Add modifier" and am != null and am.text == "Add material",
		"R2 modifier row button reads '%s' (bar 'Apply %s'); Add buttons read '%s' / '%s' (bar 'Add modifier' / 'Add material')" % [at, KMeshModifiers.NAMES[KMeshModifiers.TYPES[0]], String(ad.text) if ad != null else "(none)", String(am.text) if am != null else "(none)"])
	mstk.queue_free()
	await idle(2)

	quit(1 if fails else 0)


func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func cdist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


## ---- 11 the model preview
func preview() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = m.kmed
	var mu := ui.mods
	var r: Rect2 = mu.panel.get_global_rect()
	var win := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	ok(mu.panel.visible and r.size.x > 40 and win.encloses(r) and not r.intersects(ui.prim_panel.get_global_rect()),
		"(11) the Modifiers panel %s is inside the window %s, clear of the Add primitive panel %s" % [r, win.size, ui.prim_panel.get_global_rect()])
	var n0 := ui.undo.steps.size()
	var base_v := ui.mesh.verts.duplicate()
	var i := mu.add("array")
	await idle(2)
	var corners: int = mu.surf.mesh.surface_get_array_len(0) if mu.surf.mesh != null and mu.surf.mesh.get_surface_count() > 0 else 0
	ok(i == 0 and ui.undo.steps.size() == n0 + 1 and cnt(ui.mesh) == Vector2i(98, 96) and ui.mesh.verts == base_v and not ui.view._surf.visible and mu.surf.visible and corners == 1152,
		"(11) Add Array: one step (%d), base %s untouched, own surface hidden %s, mod_surface %d triangle corners (expect 1152)" % [ui.undo.steps.size() - n0, cnt(ui.mesh), not ui.view._surf.visible, corners])
	var cf := mu._list.find_child("mod_0_count", true, false) as SpinBox
	cf.value = 3
	cf.value = 4
	await idle(2)
	var bb: AABB = mu.surf.get_aabb()
	ok(cf != null and ui.undo.steps.size() == n0 + 2 and mu.evaluated.face_count() == 384 and absf(bb.position.x + 0.3) < 1e-5 and absf(bb.end.x - 2.1) < 1e-5,
		"(11) count field 3 then 4: one more step (%d steps since the add), %d faces evaluated (expect 384), mod_surface x %.4f .. %.4f (expect -0.3 .. 2.1)" % [ui.undo.steps.size() - n0 - 1, mu.evaluated.face_count(), bb.position.x, bb.end.x])
	# placement: the camera in front, looking at the base and copy 1
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 3.2, wc + Vector3(0.6, 0.1, 0), false)
	await idle(4)
	var copy1: Vector2 = m.cam.unproject_position(wc + Vector3(0.6, 0.0, 0.3))
	var basec: Vector2 = m.cam.unproject_position(wc + Vector3(-0.075, -0.075, 0.3))
	var img_on := await shot()
	mu.toggle(0)
	var img_off := await shot()
	var c_on := img_on.get_pixelv(Vector2i(copy1))
	var c_off := img_off.get_pixelv(Vector2i(copy1))
	ok(win.has_point(copy1) and cdist(c_on, c_off) > 0.1, "(11) placement: copy 1's centre %s is drawn (%s) and empty with the modifier off (%s), distance %.3f (bar 0.1)" % [copy1, c_on, c_off, cdist(c_on, c_off)])
	mu.toggle(0)
	await idle(2)
	ui.set_mode(KMeshSelect.FACE)
	ui.sel.clear()
	var hit_copy := ui.view.click(m.cam, copy1)
	var n_copy := ui.sel.count()
	var hit_base := ui.view.click(m.cam, basec)
	ok(not hit_copy and n_copy == 0 and hit_base and ui.sel.faces.size() == 1, "(11) pick stays on the base: a click on the copy selects %d, a click on the base selects %d face" % [n_copy, ui.sel.faces.size()])
	ui.sel.clear()
	ui.undo.begin(ui.mesh)
	ui.mesh.verts[0] += Vector3(0, 0.05, 0)
	ui.mesh._compute_normals()
	ui.undo.commit("Move")
	ui.view.rebuild()
	var follow := true
	for k in 4:
		follow = follow and mu.evaluated.verts[98 * k].distance_to(base_v[0] + Vector3(0.6 * k, 0.05, 0)) < 1e-6
	ok(follow, "(11) a base edit (vertex 0 up 5 cm) shows in all 4 copies")
	await key(KEY_Z, true)
	await idle(2)
	ok(ui.mesh.verts == base_v and mu.evaluated.verts[0] == base_v[0] and mu.evaluated.face_count() == 384, "(11) Ctrl+Z (a real key) takes the edit back, the evaluated surface follows")
	var sn := ui.undo.steps.size()
	var applied := mu.apply(0)
	await idle(2)
	ok(applied and cnt(ui.mesh) == Vector2i(392, 384) and ui.mesh.modifiers.is_empty() and ui.undo.steps.size() == sn + 1 and ui.view._surf.visible and not mu.surf.visible,
		"(11) Apply: base %s (expect 392 / 384) as one step (%d), stack empty, own surface back %s" % [cnt(ui.mesh), ui.undo.steps.size() - sn, ui.view._surf.visible])
	await key(KEY_Z, true)
	await idle(2)
	ok(cnt(ui.mesh) == Vector2i(98, 96) and ui.mesh.modifiers.size() == 1 and mu._list.get_child_count() == 1 and mu.evaluated != null and mu.evaluated.face_count() == 384,
		"(11) Ctrl+Z: base %s, stack back (%d, %d rows), evaluated %d faces" % [cnt(ui.mesh), ui.mesh.modifiers.size(), mu._list.get_child_count(), mu.evaluated.face_count() if mu.evaluated != null else -1])
	var said := MeshTools.op("modifiers", m)
	ok(said.contains("Array x4"), "(11) the S box line says the stack: %s" % said)
	for t in ["mirror", "solidify", "displace", "subdiv"]:
		mu.add(t)
	await idle(3)
	var r5: Rect2 = mu.panel.get_global_rect()
	ok(mu._list.get_child_count() == 5 and win.encloses(r5) and r5.size.y <= win.size.y * 0.75, "(11) five modifiers: the panel %s still fits the window (the list scrolls)" % r5)
	await key(KEY_ESCAPE)
	ok(not ui.on and not mu.panel.visible, "(11) Esc leaves, the panel goes")
