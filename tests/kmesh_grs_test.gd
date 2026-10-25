## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/kmesh_grs_test.gd   (round 2 walk, goals 2, 3, 4, 8)
## G / R / S in the MODEL preview with the Blender-keys layer OFF, the Alt+click edge loop, and Ctrl+1 subdivision.
## Bars, stated before measuring, through real key and mouse events (root.push_input) on the 4x4 test cube, layer off
## (the settings file is this test's own: blk.on is false by default):
##  (A) G, the mouse moved 60 px in six steps, a left click: the selected vertex moved (> 1 cm), NO other vertex moved
##      (proportional off), ONE undo step
##  (B) O on, G, the same 60 px drag, a wheel step up during G (the radius grows), a click: the selected vertex moved, its
##      neighbours moved too but each by less than the selected one; ONE undo step
##  (C) Alt+click on a top edge selects its edge LOOP (more than 4 edges); S, the mouse moved 60 px, a click: the loop's
##      spread about its mean grew by 1.3 (+- 0.02), the other verts did not move; ONE undo step
##  (D) R, 60 px, a click: the selected verts turned (some moved), every pair's distance kept (+- 1e-5); ONE undo step
##  (E) G then 60 px then Esc: the vertex array is bit-exact the one before, no undo step is kept; R, 60 px, Esc: the same
##  (F) Ctrl+1: a Subdivide modifier at level 1 is added (one step), the evaluated mesh has 4x the faces of the base, the
##      status line names it; the base mesh is unchanged
##  (G) POSE (the model preview off): G is still the second hand (its status words), and blk.active stays ""
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


func send(e: InputEvent) -> void:
	root.push_input(e)
	await process_frame


func tap(code: Key, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.pressed = down
		await send(e)
	await idle(2)


func mbtn(p: Vector2, b := MOUSE_BUTTON_LEFT, pressed := true, alt := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.position = p
	e.alt_pressed = alt
	return e


## a real drag: six motions, each with its own relative, the way the OS sends them
func drag(d: Vector2) -> void:
	var p := Vector2(480, 320)
	for i in 6:
		var e := InputEventMouseMotion.new()
		e.relative = d / 6.0
		e.position = p + d * float(i + 1) / 6.0
		await send(e)
	await idle(1)


func click() -> void:
	await send(mbtn(Vector2(480, 320)))
	await send(mbtn(Vector2(480, 320), MOUSE_BUTTON_LEFT, false))
	await idle(2)


func wheel_up() -> void:
	await send(mbtn(Vector2(480, 320), MOUSE_BUTTON_WHEEL_UP, true))
	await send(mbtn(Vector2(480, 320), MOUSE_BUTTON_WHEEL_UP, false))
	await idle(2)


func fresh() -> void:
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()
	m._kmesh_edit_start()
	await idle(3)


## the top-face vertex nearest the middle of the cube's top (y = 0.3 in the cube's own frame)
func top_vert(ui) -> int:
	var best := -1
	var bd := 1.0e9
	for i in ui.mesh.verts.size():
		var v: Vector3 = ui.mesh.verts[i]
		if absf(v.y - 0.3) > 1e-6:
			continue
		var d := Vector2(v.x, v.z).length()
		if d < bd and d > 0.01:
			bd = d
			best = i
	return best


func select_verts(ui, vs: Array) -> void:
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.VERT)
	for v in vs:
		ui.sel.verts[v] = true
	ui.view.mark_dirty()


func max_move(a: PackedVector3Array, b: PackedVector3Array, idx: Array) -> float:
	var mx := 0.0
	for i in idx:
		mx = maxf(mx, a[i].distance_to(b[i]))
	return mx


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.settings.begins_with("user://poser_test_"), "0 own config (%s)" % m.settings)
	ok(not m.blk.on, "0a the Blender-keys layer is OFF (its default)")

	# (A) G + 60 px + click: the selected vertex moves, nothing else
	await fresh()
	var ui = m.kmed
	ok(ui.on and ui.showing and not ui.prop.on, "A0 the test cube is open, O is off")
	var vi := top_vert(ui)
	select_verts(ui, [vi])
	var before: PackedVector3Array = ui.mesh.verts.duplicate()
	var s0: int = ui.undo.steps.size()
	await tap(KEY_G)
	ok(m.blk.active == "G", "A1 G starts the grab on the model preview with the layer off (active=%s)" % m.blk.active)
	await drag(Vector2(60, 0))
	await click()
	var moved_sel: float = before[vi].distance_to(ui.mesh.verts[vi])
	var others := []
	for i in ui.mesh.verts.size():
		if i != vi:
			others.append(i)
	var moved_other := max_move(before, ui.mesh.verts, others)
	ok(moved_sel > 0.01 and moved_other == 0.0,
		"(A) G + 60 px + click: the vertex moved %.1f cm, the other %d verts moved %.6f m (must be 0)" % [moved_sel * 100.0, others.size(), moved_other])
	ok(ui.undo.steps.size() == s0 + 1, "(A) one undo step (%d -> %d)" % [s0, ui.undo.steps.size()])

	# (B) O on: neighbours move, less than the selected vertex; the wheel sizes the radius during G
	await fresh()
	ui = m.kmed
	vi = top_vert(ui)
	select_verts(ui, [vi])
	await tap(KEY_O)
	ok(ui.prop.on, "B0 O turns proportional editing on")
	before = ui.mesh.verts.duplicate()
	s0 = ui.undo.steps.size()
	var r0: float = ui.prop.radius
	await tap(KEY_G)
	await drag(Vector2(60, 0))
	await wheel_up()
	var r1: float = ui.prop.radius
	await click()
	var nbi: Array = Array(ui.mesh.vert_neighbors(vi))
	var d_sel: float = before[vi].distance_to(ui.mesh.verts[vi])
	var d_nb := max_move(before, ui.mesh.verts, nbi)
	ok(d_sel > 0.01 and d_nb > 1e-4 and d_nb < d_sel,
		"(B) O on: selected moved %.1f cm, its neighbours at most %.2f cm (less)" % [d_sel * 100.0, d_nb * 100.0])
	ok(r1 > r0 + 1e-6, "(B) the wheel during G grows the radius (%.3f -> %.3f m)" % [r0, r1])
	ok(ui.undo.steps.size() == s0 + 1, "(B) one undo step")

	# (C) Alt+click an INTERIOR top edge (not on the cube's rim: a rim edge's loop stops at the corners after 4 edges):
	# its loop runs round the cube; S + 60 px scales it. Proportional is switched off (it was on for (B)).
	await fresh()
	ui = m.kmed
	if ui.prop.on:
		await tap(KEY_O)
	var cam: Camera3D = m.cam
	var edge_p := Vector2.ZERO
	var edge_ok := false
	for fi in ui.mesh.face_count():
		if absf(ui.mesh.face_center(fi).y - 0.3) > 1e-6 or edge_ok:
			continue
		var fv: PackedInt32Array = ui.mesh.faces[fi]
		for i in fv.size():
			var a: int = fv[i]
			var b: int = fv[(i + 1) % fv.size()]
			var pa: Vector3 = ui.mesh.verts[a]
			var pb: Vector3 = ui.mesh.verts[b]
			if absf(pa.y - 0.3) > 1e-6 or absf(pb.y - 0.3) > 1e-6:
				continue
			if maxf(maxf(absf(pa.x), absf(pb.x)), maxf(absf(pa.z), absf(pb.z))) > 0.25:
				continue   # a rim edge: its neighbours sit on the cube's edge
			var wa: Vector3 = ui.view.global_transform * ((pa + pb) * 0.5)
			if cam.is_position_behind(wa):
				continue
			var sp: Vector2 = cam.unproject_position(wa)
			var h: Dictionary = ui.view.pick(cam, sp)
			if not h.is_empty() and (h["edge"] as Vector2i) == KMeshSelect.ekey(a, b):
				edge_p = sp
				edge_ok = true
				break
	ok(edge_ok, "C0 an interior top edge is under the mouse at %s" % str(edge_p))
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.EDGE)
	ui.view.mark_dirty()
	await send(mbtn(edge_p, MOUSE_BUTTON_LEFT, true, true))
	await send(mbtn(edge_p, MOUSE_BUTTON_LEFT, false, true))
	await idle(2)
	var loop_edges: int = ui.sel.edges.size()
	var loop_verts := {}
	for k in ui.sel.edges.keys():
		loop_verts[(k as Vector2i).x] = true
		loop_verts[(k as Vector2i).y] = true
	ok(loop_edges > 4, "(C) Alt+click on one edge selects its LOOP: %d edges (one edge would be 1, a rim loop 4)" % loop_edges)
	var lv: Array = loop_verts.keys()
	before = ui.mesh.verts.duplicate()
	var mean := Vector3.ZERO
	for v in lv:
		mean += before[v]
	mean /= float(lv.size())
	var spread0 := 0.0
	for v in lv:
		spread0 += before[v].distance_to(mean)
	s0 = ui.undo.steps.size()
	await tap(KEY_S)
	ok(m.blk.active == "S", "C1 S starts the scale on the model preview with the layer off (active=%s)" % m.blk.active)
	await drag(Vector2(60, 0))
	await click()
	var mean1 := Vector3.ZERO
	for v in lv:
		mean1 += ui.mesh.verts[v]
	mean1 /= float(lv.size())
	var spread1 := 0.0
	for v in lv:
		spread1 += ui.mesh.verts[v].distance_to(mean1)
	var others_moved := 0.0
	for i in ui.mesh.verts.size():
		if not loop_verts.has(i):
			others_moved = maxf(others_moved, before[i].distance_to(ui.mesh.verts[i]))
	var ratio := spread1 / maxf(spread0, 1e-9)
	ok(absf(ratio - 1.3) <= 0.02 and others_moved == 0.0,
		"(C) S + 60 px + click: the loop scaled x%.3f (want 1.3), the other verts moved %.6f (want 0)" % [ratio, others_moved])
	ok(ui.undo.steps.size() == s0 + 1, "(C) one undo step")

	# (D) R + 60 px + click: the selected verts turn, every distance among them kept
	await fresh()
	ui = m.kmed
	var fi0 := -1
	for fi in ui.mesh.face_count():
		if absf(ui.mesh.face_center(fi).y - 0.3) < 1e-6:
			fi0 = fi
			break
	var quad: Array = Array(ui.mesh.faces[fi0])
	select_verts(ui, quad)
	before = ui.mesh.verts.duplicate()
	s0 = ui.undo.steps.size()
	await tap(KEY_R)
	ok(m.blk.active == "R", "D1 R starts the rotate with the layer off (active=%s)" % m.blk.active)
	await drag(Vector2(60, 0))
	await click()
	var turned := max_move(before, ui.mesh.verts, quad)
	var dist_ok := true
	for i in quad:
		for j in quad:
			var d0: float = before[i].distance_to(before[j])
			var d1: float = ui.mesh.verts[i].distance_to(ui.mesh.verts[j])
			if absf(d0 - d1) > 1e-5:
				dist_ok = false
	ok(turned > 0.01 and dist_ok, "(D) R + 60 px + click: the face's verts turned %.1f cm, the distances among them kept (%s)" % [turned * 100.0, str(dist_ok)])
	ok(ui.undo.steps.size() == s0 + 1, "(D) one undo step")

	# (E) Esc restores exactly, for G and for R
	await fresh()
	ui = m.kmed
	vi = top_vert(ui)
	select_verts(ui, [vi])
	before = ui.mesh.verts.duplicate()
	s0 = ui.undo.steps.size()
	await tap(KEY_G)
	await drag(Vector2(60, 0))
	await tap(KEY_ESCAPE)
	ok(ui.mesh.verts == before and ui.undo.steps.size() == s0 and m.blk.active == "",
		"(E) G, 60 px, Esc: the verts are bit-exact the old ones, no step kept")
	await tap(KEY_R)
	await drag(Vector2(60, 0))
	await tap(KEY_ESCAPE)
	ok(ui.mesh.verts == before and ui.undo.steps.size() == s0 and m.blk.active == "",
		"(E) R, 60 px, Esc: the same")

	# (F) Ctrl+1: a Subdivide modifier at level 1, one step, the status names it, the base untouched
	await fresh()
	ui = m.kmed
	var nf0: int = ui.mesh.face_count()
	var mods0: int = ui.mesh.modifiers.size()
	s0 = ui.undo.steps.size()
	await tap(KEY_1, true)
	var added: Dictionary = ui.mesh.modifiers[-1] if ui.mesh.modifiers.size() > 0 else {}
	var evald: KMesh = KMeshModifiers.evaluate(ui.mesh)
	ok(ui.mesh.modifiers.size() == mods0 + 1 and String(added.get("type", "")) == "subdiv" and int(added.get("levels", 0)) == 1,
		"(F) Ctrl+1 adds a Subdivide modifier at level 1 (stack %d -> %d)" % [mods0, ui.mesh.modifiers.size()])
	ok(evald.face_count() == 4 * nf0 and ui.mesh.face_count() == nf0,
		"(F) the result has %d faces (4 x %d), the base still %d" % [evald.face_count(), nf0, ui.mesh.face_count()])
	ok("subdiv" in m.ui_status.text.to_lower(), "(F) the status says what it did (%s)" % m.ui_status.text.left(90))
	ok(ui.undo.steps.size() == s0 + 1, "(F) one undo step")

	# (F2) Ctrl+1 under a longer stack (walk-through round 2): the Modifiers panel opens with the new row's "Apply Subdivide"
	# inside the list's visible area (it was below the scroll edge, so the click hit nothing), and pressing it bakes it
	await fresh()
	ui = m.kmed
	for t in ["mirror", "solidify", "array"]:
		KMeshModifiers.add(ui.mesh, t)
	await tap(KEY_1, true)
	ui.mods.open()
	await idle(6)
	var k_new: int = ui.mesh.modifiers.size() - 1
	var ap := ui.mods.panel.find_child("mod_%d_apply" % k_new, true, false) as Button
	var sc := ui.mods.panel.find_child("mod_scroll", true, false) as ScrollContainer
	var shown := ap != null and sc != null and sc.get_global_rect().encloses(ap.get_global_rect())
	ok(ap != null and ap.text == "Apply Subdivide" and shown, "(F2) the new row's '%s' is inside the list's visible area: %s" % [ap.text if ap != null else "?", str(shown)])
	var nf1: int = ui.mesh.face_count()
	if ap != null:
		var cp := ap.get_global_rect().get_center()
		var mv := InputEventMouseMotion.new()
		mv.position = cp
		await send(mv)
		await send(mbtn(cp))
		await send(mbtn(cp, MOUSE_BUTTON_LEFT, false))
		await idle(4)
	ok(ui.mesh.face_count() > nf1, "(F2) a real click on it bakes the Subdivide (%d -> %d faces)" % [nf1, ui.mesh.face_count()])
	ui.mods.close()

	# (G) POSE: with the model preview off, G is the second hand (no grab)
	ui.stop()
	await idle(2)
	await tap(KEY_G)
	ok("second hand" in m.ui_status.text and m.blk.active == "", "(G) POSE: G is still the second hand (%s)" % m.ui_status.text.left(70))
	await tap(KEY_G)

	# (H) Alt+click AFTER an extrude AND with a Mirror modifier on: the loop through an interior top edge is >= 4 edges
	# (the walk's cube: a front face extruded, Mirror added; one edge was selected instead of its loop)
	await fresh()
	ui = m.kmed
	var zf := -1
	var zmax := -1.0e9
	for fi in ui.mesh.face_count():
		var fc: Vector3 = ui.mesh.face_center(fi)
		if fc.z > zmax:
			zmax = fc.z
			zf = fi
	var nf_h0: int = ui.mesh.face_count()
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.faces[zf] = true
	ui.undo.begin(ui.mesh)
	KMeshExtrude.extrude(ui.mesh, ui.sel, 0.2)
	ui.undo.commit("Extrude")
	ui.sel.clear()
	KMeshModifiers.add(ui.mesh, "mirror")
	ui.view.mark_dirty()
	await idle(4)
	ok(ui.mesh.face_count() > nf_h0 and ui.mesh.modifiers.size() == 1, "(H0) an extrude (faces %d -> %d) and a Mirror on the stack" % [nf_h0, ui.mesh.face_count()])
	var hcam: Camera3D = m.cam
	var hedge := Vector2.ZERO
	var hfound := false
	for fi in ui.mesh.face_count():
		if absf(ui.mesh.face_center(fi).y - 0.3) > 1e-6 or hfound:
			continue
		var hfv: PackedInt32Array = ui.mesh.faces[fi]
		for i in hfv.size():
			var ha: int = hfv[i]
			var hb: int = hfv[(i + 1) % hfv.size()]
			var hpa: Vector3 = ui.mesh.verts[ha]
			var hpb: Vector3 = ui.mesh.verts[hb]
			if maxf(maxf(absf(hpa.x), absf(hpb.x)), maxf(absf(hpa.z), absf(hpb.z))) > 0.25:
				continue   # a rim edge, as in (C)
			var hw: Vector3 = ui.view.global_transform * ((hpa + hpb) * 0.5)
			if hcam.is_position_behind(hw):
				continue
			var hsp: Vector2 = hcam.unproject_position(hw)
			var hh: Dictionary = ui.view.pick(hcam, hsp)
			if not hh.is_empty() and (hh["edge"] as Vector2i) == KMeshSelect.ekey(ha, hb):
				hedge = hsp
				hfound = true
				break
	ok(hfound, "(H0) an interior top edge is under the mouse at %s" % str(hedge))
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.EDGE)
	ui.view.mark_dirty()
	await idle(2)
	await send(mbtn(hedge, MOUSE_BUTTON_LEFT, true, true))
	await send(mbtn(hedge, MOUSE_BUTTON_LEFT, false, true))
	await idle(2)
	var h_loop: int = ui.sel.edges.size()
	ok(h_loop >= 4, "(H) Alt+click after the extrude and with Mirror on selects the loop: %d edges (want >= 4)" % h_loop)

	print("kmesh_grs: %d failures" % fails)
	quit(1 if fails > 0 else 0)
