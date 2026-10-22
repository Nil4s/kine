## godot --path . -s tests/meshstats_test.gd     (ROADMAP_400 A14; needs a window: the status line is read back as drawn)
## Mesh stats in the status line. Bars, written before measuring:
##   1 CUBE (8 verts, 6 quads): 8 / 12 / 6 verts / edges / faces, 12 tris, 6 quads, 0 n-gons, 8 poles all 3-poles, closed
##     (0 boundary verts)
##   2 GRID 3 x 3 quads (open): 16 / 24 / 9, 18 tris, 0 poles (the 4 interior verts are valence 4; the 12 rim verts are not
##     poles), 12 boundary verts
##   3 N-GONS: a hexagonal prism: 12 / 18 / 8, 20 tris (2 hexagons x 4 + 6 quads x 2), 2 n-gons, 6 quads, 12 3-poles; a
##     pentagonal pyramid: 6 / 10 / 6, 8 tris, 5 tri faces + 1 n-gon, 5 3-poles + 1 5-pole (the apex); a loose vert is
##     counted as loose, not a pole
##   4 THE TEST CUBE (KMeshView.make_cube 0.6 m, 4 x 4 a side): 98 / 192 / 96, 192 tris, 8 3-poles, 0 5-poles
##   5 PLACEMENT: with "Model: edit a test cube" open, the status line's readout LABEL (m.ui_bar, what the user sees) starts
##     with the mesh line ("98 verts  192 edges ..."); the label is visible, inside the window, on the status line's band (above the scene panel, the
##     same row as the say-line); the mesh part of its text is narrower than the label (not cut by the ellipsis); shot
##     saved for a look
##   6 UPDATES: key A (a real key event) selects all -> the label reads "98 / 98 picked"; deleting a face (one edit,
##     rebuilt) -> 95 faces, 190 tris and 4 boundary verts... the label follows within 2 frames; Esc leaves -> the label
##     no longer starts with "98 verts"
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


func key(k: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func has(s: Dictionary, want: Dictionary) -> bool:
	for k in want:
		if s[k] != want[k]:
			return false
	return true


func grid(n: int) -> KMesh:
	var vs := PackedVector3Array()
	for j in n + 1:
		for i in n + 1:
			vs.append(Vector3(i, 0, j))
	var fs: Array = []
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			fs.append([a, a + n + 1, a + n + 2, a + 1])
	return KMesh.new().from_arrays(vs, fs)


func prism(n: int) -> KMesh:
	var vs := PackedVector3Array()
	for y in 2:
		for i in n:
			vs.append(Vector3(cos(TAU * i / n), y, sin(TAU * i / n)))
	var bot := []
	var top := []
	for i in n:
		bot.append(n - 1 - i)
		top.append(n + i)
	var fs: Array = [bot, top]
	for i in n:
		var j := (i + 1) % n
		fs.append([i, j, n + j, n + i])
	return KMesh.new().from_arrays(vs, fs)


func _init() -> void:
	# ---- bars 1-4: the pure counts
	var cv := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
	var cf := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
	var s := KMeshStats.of(KMesh.new().from_arrays(PackedVector3Array(cv), cf))
	print("  cube: ", s)
	ok(has(s, {"verts": 8, "edges": 12, "faces": 6, "tris": 12, "quads": 6, "ngons": 0, "poles": 8, "poles3": 8, "poles5": 0, "boundary": 0}),
		"bar 1 cube: %d / %d / %d, %d tris, %d 3-poles %d 5-poles (expect 8 / 12 / 6, 12, 8, 0)" % [s["verts"], s["edges"], s["faces"], s["tris"], s["poles3"], s["poles5"]])
	s = KMeshStats.of(grid(3))
	ok(has(s, {"verts": 16, "edges": 24, "faces": 9, "tris": 18, "quads": 9, "poles": 0, "boundary": 12}),
		"bar 2 grid 3x3: %d / %d / %d, %d tris, %d poles, %d boundary (expect 16 / 24 / 9, 18, 0, 12)" % [s["verts"], s["edges"], s["faces"], s["tris"], s["poles"], s["boundary"]])
	s = KMeshStats.of(prism(6))
	ok(has(s, {"verts": 12, "edges": 18, "faces": 8, "tris": 20, "quads": 6, "ngons": 2, "poles3": 12, "poles5": 0}),
		"bar 3 hexagonal prism: %d / %d / %d, %d tris, %d n-gons, %d quads, %d 3-poles (expect 12 / 18 / 8, 20, 2, 6, 12)" % [s["verts"], s["edges"], s["faces"], s["tris"], s["ngons"], s["quads"], s["poles3"]])
	var pv := PackedVector3Array()
	for i in 5:
		pv.append(Vector3(cos(TAU * i / 5), 0, sin(TAU * i / 5)))
	pv.append(Vector3(0, 1, 0))
	pv.append(Vector3(4, 4, 4))   # 6: loose
	var pf: Array = [[0, 1, 2, 3, 4]]
	for i in 5:
		pf.append([(i + 1) % 5, i, 5])
	s = KMeshStats.of(KMesh.new().from_arrays(pv, pf))
	ok(has(s, {"verts": 7, "edges": 10, "faces": 6, "tris": 8, "tri_faces": 5, "ngons": 1, "poles3": 5, "poles5": 1, "loose": 1}),
		"bar 3 pentagonal pyramid + a loose vert: %d / %d / %d, %d tris, %d tri faces, %d n-gon, poles %d (3) %d (5+), %d loose (expect 7 / 10 / 6, 8, 5, 1, 5, 1, 1)" % [s["verts"], s["edges"], s["faces"], s["tris"], s["tri_faces"], s["ngons"], s["poles3"], s["poles5"], s["loose"]])
	s = KMeshStats.of(KMeshView.make_cube(0.6, 4))
	ok(has(s, {"verts": 98, "edges": 192, "faces": 96, "tris": 192, "poles3": 8, "poles5": 0}),
		"bar 4 test cube 4x4: %d / %d / %d, %d tris, poles %d (3) %d (5+) (expect 98 / 192 / 96, 192, 8, 0)" % [s["verts"], s["edges"], s["faces"], s["tris"], s["poles3"], s["poles5"]])

	# ---- bar 5: on the status line
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(4)
	var bar: Label = m.ui_bar
	var t := bar.text
	var part := t.get_slice("   |   ", 0)
	print("  bar: ", t)
	ok(t.begins_with("98 verts  192 edges  96 faces  192 tris") and part.contains("poles 8 / 0 (3 / 5+)") and part.contains("0 / 98 picked"),
		"bar 5 the readout label reads the test cube: '%s'" % part)
	var r := bar.get_global_rect()
	var win := root.get_visible_rect()
	var st: Label = m.ui_status
	var band: float = win.size.y - m.bottom_h - 6 - m.LINE_H
	var fw := bar.get_theme_font("font").get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, bar.get_theme_font_size("font_size")).x
	print("  label %s in %s, band y %.0f..%.0f, the mesh part %.0f px wide, say-line %s" % [r, win.size, band, win.size.y - m.bottom_h - 6, fw, st.get_global_rect()])
	ok(bar.is_visible_in_tree() and win.encloses(r) and r.size.x > 0 and absf(r.position.y - band) < 2.0 and absf(r.end.y - (win.size.y - m.bottom_h - 6)) < 2.0,
		"bar 5 the label is visible, inside the window, on the status line's band (%s)" % r)
	ok(fw <= r.size.x, "bar 5 the mesh part (%.0f px) fits the label (%.0f px): not cut by the ellipsis" % [fw, r.size.x])
	ok(r.position.x >= st.get_global_rect().end.x - 1.0 or not st.visible, "bar 5 the readout sits right of the say-line, not under it")
	await idle(3)
	await RenderingServer.frame_post_draw
	var shot := "user://meshstats.png"
	root.get_texture().get_image().save_png(shot)
	print("  shot -> ", ProjectSettings.globalize_path(shot))

	# ---- bar 6: follows edits
	await key(KEY_A)
	t = bar.text
	ok(t.get_slice("   |   ", 0).ends_with("98 / 98 picked"), "bar 6 key A: '%s'" % t.get_slice("   |   ", 0).get_slice("·", 3).strip_edges())
	var km: KMesh = m.kmed.mesh
	km.faces.remove_at(0)
	km.rebuild()
	m.kmed.view.mark_dirty()
	await idle(2)
	s = KMeshStats.of(km)
	t = bar.text
	ok(s["faces"] == 95 and s["tris"] == 190 and s["boundary"] == 4 and t.begins_with("98 verts  192 edges  95 faces  190 tris"),
		"bar 6 a face deleted: %d faces %d tris %d boundary verts, the label '%s'" % [s["faces"], s["tris"], s["boundary"], t.get_slice("   |   ", 0)])
	await key(KEY_ESCAPE)
	await idle(2)
	ok(not m.kmed.on and not bar.text.begins_with("98 verts"), "bar 6 Esc leaves: the readout is the pose's again ('%s')" % bar.text.get_slice("   |   ", 0))
	print("MESH STATS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
