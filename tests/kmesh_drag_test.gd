extends SceneTree
## E / I as a live drag, and loop cut by a click (walk-through 05_04, 06_05, 09_08; scripts/kmesh_drag_op.gd,
## scripts/kmesh_cut_tool.gd). Bars, stated before measuring, on the model preview's 4x4 test cube (side 0.6, cell 0.15,
## top face at y = 0.3 in the cube's own frame), driven by real mouse motions and clicks through KMeshEditUI.input:
## (A) E on a top face, the mouse moved 60 px up in steps, a left click: the top moved more than 5 cm along its normal;
##     the same with 30 px moves it less (the distance follows the mouse, two moves give two distances)
## (B) E, the mouse moved 60 px up, Esc: verts and faces identical to before, the undo steps and the redo list the same
## (C) I on a top face, the mouse moved 30 px out from its centre, a click: the inset is not 2 cm (the inner face's side
##     gives the inset: (0.15 - side) / 2), and it is more than 0
## (D) Ctrl+R, the mouse over a top edge, a left click: the faces grow by one ring (16 quads), the loop is cut at once
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func key(code: int, ctrl := false, shift := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.physical_keycode = code
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


## a real drag of the mouse from p by d, in six motions (what the walk does)
func move_by(ui, p: Vector2, d: Vector2) -> void:
	for i in 6:
		ui.input(motion(p + d * float(i + 1) / 6.0))


## the top faces (y = 0.3) that face the camera, biggest on screen first
func top_faces(ui) -> Array:
	var cam: Camera3D = ui.m.cam
	var view: KMeshView = ui.view
	var out := []
	for fi in ui.mesh.face_count():
		if absf(ui.mesh.face_center(fi).y - 0.3) > 1e-6:
			continue
		if not view.point_visible(cam, view.global_transform * ui.mesh.face_center(fi)):
			continue
		var sq := PackedVector2Array()
		for v in (ui.mesh.faces[fi] as PackedInt32Array):
			sq.append(cam.unproject_position(view.global_transform * ui.mesh.verts[v]))
		out.append([absf((sq[2] - sq[0]).cross(sq[3] - sq[1])) * 0.5, fi])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out.map(func(x): return x[1])


func spot(ui, fi: int) -> Vector2:
	return ui.m.cam.unproject_position(ui.view.global_transform * ui.mesh.face_center(fi))


func top_y(ui) -> float:
	var mx := -1.0e9
	for v in ui.mesh.verts:
		mx = maxf(mx, v.y)
	return mx


## a fresh test cube, the top face fi selected in face mode
func fresh(mn, ui, fi_pick := 0) -> int:
	if ui != null and ui.on:
		ui.stop()
	mn._kmesh_edit_start()
	await process_frame
	await process_frame
	ui = mn.kmed
	var fi: int = top_faces(ui)[fi_pick]
	ui.input(key(KEY_3))
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.faces[fi] = true
	ui.view.mark_dirty()
	return fi


func _init() -> void:
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	await process_frame
	var ui = mn.kmed
	# (A) E + a real mouse move up, then a click: the distance follows the mouse
	var dist := {}
	for px in [60.0, 30.0]:
		var fi: int = await fresh(mn, ui)
		ui = mn.kmed
		var s := spot(ui, fi)
		ui.input(motion(s))
		ui.input(key(KEY_E))
		move_by(ui, s, Vector2(0, -px))
		ui.input(mbtn(s + Vector2(0, -px)))
		ui.input(mbtn(s + Vector2(0, -px), MOUSE_BUTTON_LEFT, false))
		dist[px] = top_y(ui) - 0.3
	var d60: float = dist[60.0]
	var d30: float = dist[30.0]
	ok(d60 > 0.05 and d30 > 0.0 and d60 > d30 + 0.005,
		"(A) E + mouse 60 px up + click: the top moved %.1f cm (> 5 cm); 30 px: %.1f cm; the distance follows the mouse (status: %s)" % [d60 * 100.0, d30 * 100.0, mn.ui_status.text.left(70)])

	# (B) E + mouse + Esc: nothing changed, no undo step
	var fb: int = await fresh(mn, ui)
	ui = mn.kmed
	var s_b := spot(ui, fb)
	ui.input(motion(s_b))
	var v0: PackedVector3Array = ui.mesh.verts.duplicate()
	var f0: Array = ui.mesh.faces.duplicate()
	var steps0: int = ui.undo.steps.size()
	var redo0: int = ui.undo.redos.size()
	ui.input(key(KEY_E))
	move_by(ui, s_b, Vector2(0, -60))
	ui.input(key(KEY_ESCAPE))
	var same_v: bool = ui.mesh.verts == v0
	var same_f: bool = KMeshUndo._same_faces(ui.mesh.faces, f0)
	ok(same_v and same_f and ui.undo.steps.size() == steps0 and ui.undo.redos.size() == redo0 and ui.on,
		"(B) E, mouse 60 px up, Esc: verts %s, faces %s, undo steps %d -> %d, redo %d -> %d (status: %s)" % [str(same_v), str(same_f), steps0, ui.undo.steps.size(), redo0, ui.undo.redos.size(), mn.ui_status.text.left(60)])

	# (C) I + a real mouse move out from the face centre, then a click
	var fc: int = await fresh(mn, ui)
	ui = mn.kmed
	var s_c := spot(ui, fc)
	ui.input(motion(s_c))
	ui.input(key(KEY_I))
	move_by(ui, s_c, Vector2(-30, 0))
	ui.input(mbtn(s_c + Vector2(-30, 0)))
	ui.input(mbtn(s_c + Vector2(-30, 0), MOUSE_BUTTON_LEFT, false))
	var f_in: PackedInt32Array = ui.mesh.faces[fc]
	var side: float = (ui.mesh.verts[f_in[0]] - ui.mesh.verts[f_in[1]]).length()
	var inset_m: float = (0.15 - side) * 0.5
	ok(inset_m > 0.001 and absf(inset_m - 0.02) > 0.003,
		"(C) I, mouse 30 px out, click: the inset is %.1f cm (not 2 cm; the inner side %.1f cm)" % [inset_m * 100.0, side * 100.0])

	# (D) Ctrl+R, hover a top edge, a left click: one ring cut at once
	var fd: int = await fresh(mn, ui)
	ui = mn.kmed
	ui.sel.clear()
	ui.view.mark_dirty()
	var fcd: PackedInt32Array = ui.mesh.faces[fd]
	var e_mid: Vector2 = ui.m.cam.unproject_position(ui.view.global_transform * ui.mesh.verts[fcd[0]].lerp(ui.mesh.verts[fcd[1]], 0.5))
	var nf0: int = ui.mesh.face_count()
	ui.input(key(KEY_R, true))
	ui.input(motion(e_mid))
	ui.input(mbtn(e_mid))
	ui.input(mbtn(e_mid, MOUSE_BUTTON_LEFT, false))
	ok(ui.mesh.face_count() == nf0 + 16 and KMeshValidate.report(ui.mesh)["ok"],
		"(D) Ctrl+R, hover, left click: faces %d -> %d (a ring is 16 quads)" % [nf0, ui.mesh.face_count()])

	ui.stop()
	print("kmesh_drag: %d failures" % fails)
	quit(1 if fails > 0 else 0)
