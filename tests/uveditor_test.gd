## godot --path . -s tests/uveditor_test.gd     (ROADMAP_400 D01; needs a window: real key / mouse events, pixels read back)
## THE UV EDITOR PANEL (scripts/kmesh_uv_editor.gd) on the model preview's test cube. Bars (stated before measuring):
##   1 Shift+U (a real key event) opens the panel; the cube without UVs is unwrapped (6 islands) and the 3D view shows the
##     checker. PLACEMENT: the panel is inside the window and its rect does not overlap the "Add primitive" panel
##   2 MAPPING, measured on pixels (checker off): the orange 0..1 border's extreme pixels are where uv_to_px puts UV (0,0)
##     (left, bottom) and (1,1) (right, top), each within 1 px of the border pixels' centres; v is up (the (0,0) pixel row is below the (1,1) row)
##   3 ISLAND: L (real key) with the mouse inside face 0's UV polygon selects exactly the corners of face 0's island
##     (KMeshUV.topology, computed apart: 16 quads, 64 corners); a double-click there picks the same set; the selected
##     corners are drawn where uv_to_px puts them (the selection colour at >= 90 % of their pixels)
##   4 MOVE: G, typing 0.1, Enter (real keys) changes exactly those corners by (+0.1, 0) within 1e-6, every other corner
##     bit-for-bit unchanged, ONE undo step; the 3D checker follows: the view's surface UVs that changed are exactly the
##     island's 96 triangle corners, each by (0.1, 0)
##   5 MOUSE MOVE: G then the mouse 40 px right then a click moves the island by 40 / zoom in u (within 1e-4); Ctrl+Z (a real
##     key, through the model preview) puts it back bit for bit
##   6 ROTATE: R, 90, Enter turns every island corner about the island's bbox centre: |uv - (c + rot90(orig - c))| < 1e-5
##   7 UNDO + CANCEL: S, 2, Esc leaves the UVs bit-for-bit and adds no step; undo twice restores the UVs as unwrapped
##     bit for bit; Shift+U again closes the panel
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI
var ed: KMeshUVEditor


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, shift := false, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(1)


## local panel px -> viewport px
func vp(p: Vector2) -> Vector2:
	return ed.get_global_transform_with_canvas() * p


func mouse_to(p_local: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = vp(p_local)
	e.global_position = e.position
	root.push_input(e)
	await idle(2)


func click(p_local: Vector2, dbl := false) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = vp(p_local)
		e.global_position = e.position
		e.pressed = down
		e.double_click = dbl and down
		root.push_input(e)
		await process_frame
	await idle(1)


func shot() -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func near(a: Color, b: Color, t := 0.12) -> bool:
	return absf(a.r - b.r) < t and absf(a.g - b.g) < t and absf(a.b - b.b) < t


func surf_uvs() -> PackedVector2Array:
	var am: ArrayMesh = ui.view._surf.mesh
	return am.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed

	# ---- 1
	await key(KEY_U, true)
	ed = ui.uved
	var top := KMeshUV.topology(ui.mesh)
	ok(ed != null and ed.visible and ui.mesh.has_attr(KMeshUV.UV) and top["islands"] == 6 and ui.view.shading == "uv_checker",
		"1: Shift+U opens the UV editor (%s), the cube unwrapped into %d islands, 3D shading '%s'" % [ed != null and ed.visible, top["islands"], ui.view.shading])
	var pr: Rect2 = ed.get_global_rect()
	var pp: Rect2 = ui.prim_panel.get_global_rect()
	var win := root.get_visible_rect()
	ok(ui.prim_panel.is_visible_in_tree() and not pr.intersects(pp) and win.encloses(pr),
		"1: PLACEMENT: panel %s, primitives panel %s (no overlap), window %s" % [pr, pp, win.size])
	var uv0: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV).duplicate()
	var steps0 := ui.undo.steps.size()

	# ---- 2
	ed.show_checker = false
	var img := await shot()
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	var a := vp(Vector2.ZERO)
	var b := vp(ed.size)
	for y in range(int(a.y), int(b.y)):
		for x in range(int(a.x), int(b.x)):
			if near(img.get_pixel(x, y), KMeshUVEditor.UNIT_COL):
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	var p00 := vp(ed.uv_to_px(Vector2(0, 0)))
	var p11 := vp(ed.uv_to_px(Vector2(1, 1)))
	# the 1 px border is centred on the mapped line: compare with the centres of its extreme pixels
	var e00 := maxf(absf(p00.x - (lo.x + 0.5)), absf(p00.y - (hi.y + 0.5)))
	var e11 := maxf(absf(p11.x - (hi.x + 0.5)), absf(p11.y - (lo.y + 0.5)))
	ok(hi.x > 0 and e00 <= 1.0 and e11 <= 1.0 and p00.y > p11.y,
		"2: UV (0,0) -> px %s, border bottom-left pixel (%d, %d) (off %.2f px); (1,1) -> %s, top-right pixel (%d, %d) (off %.2f px); v up" % [p00, lo.x, hi.y, e00, p11, hi.x, lo.y, e11])
	ed.show_checker = true

	# ---- 3
	var want := {}
	for h in ui.mesh.half_edge_count():
		if top["island"][ui.mesh.he_face[h]] == top["island"][0]:
			want[h] = true
	var c0 := Vector2.ZERO
	var n0 := (ui.mesh.faces[0] as PackedInt32Array).size()
	for i in n0:
		c0 += uv0[ui.mesh.face_he0[0] + i] / n0
	await mouse_to(ed.uv_to_px(c0))
	await key(KEY_L)
	var got := ed.selected_corners()
	var same := got.size() == want.size()
	for h in got:
		same = same and want.has(h)
	ok(same and got.size() == 64, "3: L picks face 0's island: %d corners selected, %d in the island (bar: the same set, 64)" % [got.size(), want.size()])
	ed.sel.fill(0)
	await click(ed.uv_to_px(c0))
	await click(ed.uv_to_px(c0), true)
	var got2 := ed.selected_corners()
	ok(got2 == got, "3: a double-click there picks the same %d corners" % got2.size())
	var img3 := await shot()
	var hit := 0
	for h in got:
		var q := vp(ed.uv_to_px(uv0[h]))
		hit += 1 if near(img3.get_pixel(int(q.x), int(q.y)), Tok.c("pick_sel"), 0.2) else 0
	ok(hit >= int(0.9 * got.size()), "3: the selected corners are drawn at their mapped pixels: %d / %d" % [hit, got.size()])

	# ---- 4
	var s3d0 := surf_uvs()
	await key(KEY_G)
	await key(KEY_0)
	await key(KEY_PERIOD)
	await key(KEY_1)
	var rd := ed.readout()
	await key(KEY_ENTER)
	var uv1: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV)
	var worst := 0.0
	var others_same := true
	for h in uv1.size():
		if want.has(h):
			worst = maxf(worst, (uv1[h] - uv0[h] - Vector2(0.1, 0)).length())
		elif uv1[h] != uv0[h]:
			others_same = false
	ok(worst < 1e-6 and others_same and ui.undo.steps.size() == steps0 + 1 and ed.mode == "",
		"4: G 0.1 Enter: island corners off (+0.1, 0) by at most %.9f, others unchanged %s, undo steps %d -> %d; readout '%s'" % [worst, others_same, steps0, ui.undo.steps.size(), rd])
	await idle(3)
	var s3d1 := surf_uvs()
	var nchg := 0
	var w3 := 0.0
	for i in s3d1.size():
		if s3d1[i] != s3d0[i]:
			nchg += 1
			w3 = maxf(w3, (s3d1[i] - s3d0[i] - Vector2(0.1, 0)).length())
	ok(nchg == 96 and w3 < 1e-6, "4: the 3D checker follows: %d surface UVs changed (bar 96), each by (0.1, 0) within %.9f" % [nchg, w3])

	# ---- 5
	var before5: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV).duplicate()
	var at := ed.uv_to_px(c0 + Vector2(0.1, 0))
	await mouse_to(at)
	await key(KEY_G)
	await mouse_to(at + Vector2(40, 0))
	await click(at + Vector2(40, 0))
	var uv5: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV)
	var du := 40.0 / ed.zoom
	var w5 := 0.0
	for h in want:
		w5 = maxf(w5, (uv5[h] - before5[h] - Vector2(du, 0)).length())
	ok(w5 < 1e-4 and ui.undo.steps.size() == steps0 + 2, "5: G + mouse 40 px right + click: moved by %.5f in u, off by %.9f; steps %d" % [du, w5, ui.undo.steps.size()])
	await key(KEY_Z, false, true)
	ok(ui.mesh.attr_data(KMeshUV.UV) == before5 and ui.undo.steps.size() == steps0 + 1, "5: Ctrl+Z (through the model preview) puts it back bit for bit")

	# ---- 6
	var before6: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV).duplicate()
	var bb := Rect2(before6[got[0]], Vector2.ZERO)
	for h in got:
		bb = bb.expand(before6[h])
	var cc := bb.get_center()
	await key(KEY_R)
	await key(KEY_9)
	await key(KEY_0)
	await key(KEY_ENTER)
	var uv6: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV)
	var w6 := 0.0
	var o6 := true
	for h in uv6.size():
		if want.has(h):
			var q := before6[h] - cc
			w6 = maxf(w6, (uv6[h] - (cc + Vector2(-q.y, q.x))).length())
		elif uv6[h] != before6[h]:
			o6 = false
	ok(w6 < 1e-5 and o6 and ui.undo.steps.size() == steps0 + 2, "6: R 90 Enter about the island centre %s: worst error %.9f (bar 1e-5), others unchanged %s" % [cc, w6, o6])

	# ---- 7
	var before7: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV).duplicate()
	await key(KEY_S)
	await key(KEY_2)
	var mid: bool = ui.mesh.attr_data(KMeshUV.UV) != before7
	await key(KEY_ESCAPE)
	ok(mid and ui.mesh.attr_data(KMeshUV.UV) == before7 and ui.undo.steps.size() == steps0 + 2 and ed.mode == "",
		"7: S 2 scales live (%s), Esc puts it back bit for bit, no step added (%d)" % [mid, ui.undo.steps.size()])
	ui.undo.undo()
	ui.undo.undo()
	ok(ui.mesh.attr_data(KMeshUV.UV) == uv0 and ui.undo.steps.size() == steps0, "7: undo twice restores the unwrapped UVs bit for bit")
	await mouse_to(Vector2(-200, 200))
	await key(KEY_U, true)
	ok(not ed.visible, "7: Shift+U again closes the panel")

	print("RESULT: ", "FAIL (%d)" % fails if fails > 0 else "PASS")
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
