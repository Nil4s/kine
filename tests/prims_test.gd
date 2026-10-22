extends SceneTree
## godot --headless --path . -s tests/prims_test.gd     (ROADMAP_400 B09 primitives)
## Bars (stated before measuring):
##  1 exact counts at the defaults and at one other setting each: cube 6n^2+2 verts / 6n^2 faces, plane (nx+1)(nz+1) /
##    nx nz, UV sphere seg(rings-1)+2 / seg rings, ico 10*4^s+2 / 20*4^s, cylinder seg(hs+1) / seg hs+2, capsule
##    seg(2 rings+hs-1)+2 / seg(2 rings+hs), torus M N / M N
##  2 every closed one: manifold, closed (no border edge), Euler characteristic 2 (torus 0); the plane: manifold, open,
##    Euler 1, one border loop of 2(nx+nz) edges, every face normal +Y
##  3 outward: signed volume > 0 and within 4 % of the analytic volume at the defaults (12 % at the deliberately coarse
##    settings: 12x6 sphere, ico level 2, 16-segment capsules; cube exact to 1e-6); every face normal points away
##    from the centre (torus: from its tube's centre line)
##  4 KMeshValidate.report finds no problem on any closed one; quads where the shape allows (only the UV sphere / capsule
##    pole fans are triangles, the cylinder caps 2 n-gons)
##  5 the Model edit UI: Add cylinder puts it beside the test cube as ONE undo step; changing segments and radius rebuilds
##    it (counts follow) and still ONE step; Ctrl+Z (undo) gives the test cube back exactly (98 verts); after another edit
##    (a vertex move through KMeshUndo) the fields are no longer live; the panel sits inside the window
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func counts(km: KMesh) -> Vector2i:
	return Vector2i(km.vert_count(), km.face_count())


func face_kinds(km: KMesh) -> Dictionary:
	var d := {}
	for f in km.faces:
		var n := (f as PackedInt32Array).size()
		d[n] = int(d.get(n, 0)) + 1
	return d


## faces whose normal points toward the centre line (y axis for the solids of revolution, the tube circle for the torus)
func inward(km: KMesh, kind: String, major := 0.0) -> int:
	var bad := 0
	for fi in km.face_count():
		var c := km.face_center(fi)
		var axis := Vector3.ZERO
		if kind == "torus":
			var d := Vector3(c.x, 0.0, c.z)
			axis = d.normalized() * major if d.length() > 1e-9 else Vector3.ZERO
		var out := c - axis
		if km.face_normals[fi].dot(out) <= 0.0:
			bad += 1
	return bad


func check(kind: String, params: Dictionary, want: Vector2i, chi: int, tol := 0.04) -> void:
	var km := KMeshPrims.build(kind, params)
	var p := KMeshPrims.clean(kind, params)
	var got := counts(km)
	ok(got == want, "(1) %s %s: %s verts / faces (expect %s)" % [kind, str(p), str(got), str(want)])
	var vol := KMeshValidate._volume(km)
	var ana := KMeshPrims.analytic_volume(kind, p)
	var err := absf(vol - ana) / ana
	ok(km.is_manifold() and km.is_closed() and km.euler() == chi, "(2) %s manifold %s closed %s euler %d (expect %d)" % [kind, km.is_manifold(), km.is_closed(), km.euler(), chi])
	ok(vol > 0.0 and err < (1e-6 if kind == "cube" else tol), "(3) %s volume %.6f m^3 vs analytic %.6f (%.2f %% off, bar %.0f %%)" % [kind, vol, ana, err * 100.0, tol * 100.0])
	var bad := inward(km, kind, float(p.get("major_radius", 0.0)))
	ok(bad == 0, "(3) %s: %d of %d faces point inward" % [kind, bad, km.face_count()])
	var r := KMeshValidate.report(km)
	ok(r["ok"], "(4) %s validate: %s" % [kind, str((r["problems"] as Array).map(func(q): return q["kind"]))])
	print("     faces by side count: ", face_kinds(km))


func _init() -> void:
	check("cube", {}, Vector2i(8, 6), 2)
	check("cube", {"size": 2.0, "segments": 3}, Vector2i(56, 54), 2)
	check("uv_sphere", {}, Vector2i(32 * 15 + 2, 32 * 16), 2)
	check("uv_sphere", {"radius": 1.0, "segments": 12, "rings": 6}, Vector2i(12 * 5 + 2, 72), 2, 0.12)
	check("ico_sphere", {"subdivisions": 3}, Vector2i(642, 1280), 2)
	check("ico_sphere", {"subdivisions": 2}, Vector2i(162, 320), 2, 0.12)
	check("cylinder", {}, Vector2i(64, 34), 2)
	check("cylinder", {"segments": 24, "height_segments": 4, "depth": 1.5}, Vector2i(120, 98), 2)
	check("capsule", {}, Vector2i(32 * 16 + 2, 32 * 17), 2)
	check("capsule", {"segments": 16, "rings": 4, "height_segments": 3, "depth": 0.8}, Vector2i(16 * 10 + 2, 16 * 11), 2, 0.12)
	check("capsule", {"depth": 0.0, "segments": 16, "rings": 6}, Vector2i(16 * 11 + 2, 16 * 12), 2, 0.12)
	check("torus", {}, Vector2i(48 * 16, 48 * 16), 0)
	check("torus", {"major_segments": 64, "minor_segments": 24}, Vector2i(64 * 24, 64 * 24), 0)

	var fk := face_kinds(KMeshPrims.build("uv_sphere"))
	ok(fk.get(3, 0) == 64 and fk.get(4, 0) == 32 * 14 and fk.size() == 2, "(4) UV sphere: 64 pole triangles, the rest quads %s" % str(fk))
	fk = face_kinds(KMeshPrims.build("cylinder"))
	ok(fk.get(4, 0) == 32 and fk.get(32, 0) == 2 and fk.size() == 2, "(4) cylinder: 32 quads + 2 caps %s" % str(fk))
	fk = face_kinds(KMeshPrims.build("torus"))
	ok(fk.keys() == [4], "(4) torus: all quads %s" % str(fk))

	var pl := KMeshPrims.build("plane", {"size_x": 2.0, "size_z": 1.0, "segments_x": 4, "segments_z": 3})
	var up := 0
	for n in pl.face_normals:
		if n.dot(Vector3.UP) > 0.999:
			up += 1
	ok(counts(pl) == Vector2i(20, 12) and pl.is_manifold() and not pl.is_closed() and pl.euler() == 1 and pl.boundary_edge_count() == 14 and up == 12,
		"(1,2) plane 4x3: %s verts / faces (expect 20 / 12), open, euler %d, %d border edges (expect 14), %d of 12 faces up" % [str(counts(pl)), pl.euler(), pl.boundary_edge_count(), up])
	var pk := (KMeshValidate.report(pl)["problems"] as Array).map(func(q): return q["kind"])
	ok(pk == ["holes"], "(4) the plane's only report is its open border: %s" % str(pk))
	ok(KMeshPrims.build("nope") == null and KMeshPrims.clean("uv_sphere", {"segments": 1, "radius": -3})["segments"] == 3, "bad kind is null, params clamp to their range")

	# ---- 5: the Model edit UI
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m._kmesh_edit_start()
	await process_frame
	var ui = m.kmed
	var cube_v: PackedVector3Array = ui.mesh.verts.duplicate()
	var n0: int = ui.undo.steps.size()
	ok(ui.add_prim("cylinder", {"segments": 16}), "Add cylinder")
	var c1 := counts(ui.mesh)
	var lo := Vector3.INF
	for i in range(98, ui.mesh.vert_count()):
		lo = lo.min(ui.mesh.verts[i])
	ok(c1 == Vector2i(98 + 32, 96 + 18) and ui.undo.steps.size() == n0 + 1 and lo.x > 0.3 + 0.09 and absf(lo.y + 0.3) < 1e-6,
		"(5) added: %s (expect 130 / 114), one step (%d), beside the cube (min x %.3f m > 0.39, floor y %.3f m = -0.3)" % [str(c1), ui.undo.steps.size() - n0, lo.x, lo.y])
	ui._prim_fields["segments"].value = 24
	ui.set_prim_param("radius", 0.4)
	await process_frame
	var c2 := counts(ui.mesh)
	ok(c2 == Vector2i(98 + 48, 96 + 26) and ui.undo.steps.size() == n0 + 1 and ui.live["params"]["radius"] == 0.4 and ui.is_live(),
		"(5) live: segments 24 + radius 40 cm -> %s (expect 146 / 122), still one step (%d)" % [str(c2), ui.undo.steps.size() - n0])
	ui.undo.undo()
	ok(ui.mesh.verts == cube_v and ui.mesh.face_count() == 96 and not ui.is_live(), "(5) undo: the test cube back exactly (%d verts)" % ui.mesh.vert_count())
	ui.undo.redo()
	ok(counts(ui.mesh) == c2, "(5) redo brings the edited cylinder (%s)" % str(counts(ui.mesh)))
	ui.undo.begin(ui.mesh)
	ui.mesh.verts[0] += Vector3(0, 0.05, 0)
	ui.undo.commit("Move")
	ok(not ui.is_live() and not ui.set_prim_param("radius", 0.2) and counts(ui.mesh) == c2, "(5) after another edit the fields are not live (mesh unchanged %s)" % str(counts(ui.mesh)))
	var r: Rect2 = ui.prim_panel.get_global_rect()
	var win := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	ok(ui.prim_panel.visible and r.size.x > 40 and win.encloses(r), "(5) the panel %s sits inside the window %s" % [str(r), str(win.size)])
	ui.stop()
	ok(not ui.prim_panel.visible, "(5) the panel goes with the test cube")
	print("PRIMS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
