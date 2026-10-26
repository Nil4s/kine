extends SceneTree
## The extrude / inset flow (walk-through 4, friction 7: "a hobbyist pressing Extrude gets nothing until a drag and a click").
## Bars, on the model preview's 4x4 test cube (side 0.6, top face at y = 0.3), driven through the real ribbon buttons
## (MODEL page, scripts/expert_pages.gd) and real mouse events (root.push_input) into KMeshEditUI:
## (a) Extrude button, one top face picked: the faces lift at once: 4 verts more, exactly one undo step, the new top
##     0.10 m (+-0.01) above the old one, the new part selected
## (b) Inset button, one top face picked: 4 faces more (the rim), exactly one undo step, the mesh valid
## (c) E, a drag of 80 px up, then the mouse button released (no click): the drag is confirmed (no drag left running),
##     exactly one undo step kept, the top moved
## (d) E, a drag of 60 px up, Esc: verts and faces as before, undo steps unchanged (no step kept)
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.physical_keycode = code
	return k


func mbtn(p: Vector2, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	return e


func motion(p: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = p
	return e


## a real drag of the mouse from p by d, in six motions
func move_by(p: Vector2, d: Vector2) -> void:
	for i in 6:
		root.push_input(motion(p + d * float(i + 1) / 6.0), true)


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


## a fresh test cube with the top face fi picked in face mode (the way a click picks it)
func fresh(mn, fi_pick := 0) -> int:
	if mn.kmed != null and mn.kmed.on:
		mn.kmed.stop()
	mn._kmesh_edit_start()
	await process_frame
	await process_frame
	var ui = mn.kmed
	var fi: int = top_faces(ui)[fi_pick]
	ui.input(key(KEY_3))
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.faces[fi] = true
	ui.view.mark_dirty()
	return fi


## the MODEL ribbon's button with this label
func ribbon_button(mn, label: String) -> Button:
	for c in mn.ui_ribbon["MODEL"].get_children():
		if c is Button and (c as Button).text == label:
			return c
	return null


func _init() -> void:
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	await process_frame

	# (a) Extrude button on one picked top face
	var fa: int = await fresh(mn)
	var ui = mn.kmed
	var v0: int = ui.mesh.vert_count()
	var steps0: int = ui.undo.steps.size()
	var btn := ribbon_button(mn, "Extrude")
	if btn == null:
		ok(false, "(a) the MODEL ribbon has an Extrude button")
	else:
		btn.pressed.emit()
	var v1: int = ui.mesh.vert_count()
	var rise: float = top_y(ui) - 0.3
	var sel_n: int = ui.sel.count()
	ok(v1 == v0 + 4 and absf(rise - 0.10) <= 0.01 and ui.undo.steps.size() == steps0 + 1 and sel_n > 0 and KMeshDragOp.active(ui) == null,
		"(a) Extrude button, one top face: verts %d -> %d (+4), the top %.1f cm up (0.10 m), undo steps %d -> %d, %d selected (status: %s)" % [v0, v1, rise * 100.0, steps0, ui.undo.steps.size(), sel_n, mn.ui_status.text.left(70)])

	if KMeshDragOp.active(ui) != null:
		ui.input(key(KEY_ESCAPE))   # a drag left running by a failed check above is cancelled, so the next check starts clean

	# (b) Inset button on one picked top face
	var fb: int = await fresh(mn, 1)
	ui = mn.kmed
	var f0: int = ui.mesh.face_count()
	steps0 = ui.undo.steps.size()
	btn = ribbon_button(mn, "Inset")
	if btn == null:
		ok(false, "(b) the MODEL ribbon has an Inset button")
	else:
		btn.pressed.emit()
	var f1: int = ui.mesh.face_count()
	ok(f1 == f0 + 4 and ui.undo.steps.size() == steps0 + 1 and KMeshValidate.report(ui.mesh)["ok"] and KMeshDragOp.active(ui) == null,
		"(b) Inset button, one top face: faces %d -> %d (+4, the rim), undo steps %d -> %d, mesh valid: %s" % [f0, f1, steps0, ui.undo.steps.size(), str(KMeshValidate.report(ui.mesh)["ok"])])

	if KMeshDragOp.active(ui) != null:
		ui.input(key(KEY_ESCAPE))

	# (c) E, a drag 80 px up, the mouse button released (no click): confirmed
	var fc: int = await fresh(mn)
	ui = mn.kmed
	var s_c := spot(ui, fc)
	root.push_input(motion(s_c), true)
	steps0 = ui.undo.steps.size()
	ui.input(key(KEY_E))
	move_by(s_c, Vector2(0, -80))
	var top_before_release := top_y(ui)
	root.push_input(mbtn(s_c + Vector2(0, -80), false), true)
	ok(KMeshDragOp.active(ui) == null and ui.undo.steps.size() == steps0 + 1 and top_y(ui) - 0.3 > 0.05,
		"(c) E, drag 80 px up, mouse released (no click): the drag ends (active: %s), undo steps %d, the top %.1f cm up (at release %.1f cm)" % [str(KMeshDragOp.active(ui) != null), ui.undo.steps.size(), (top_y(ui) - 0.3) * 100.0, (top_before_release - 0.3) * 100.0])

	if KMeshDragOp.active(ui) != null:
		ui.input(key(KEY_ESCAPE))

	# (d) E, a drag 60 px up, Esc: nothing changed, no step kept
	var fd: int = await fresh(mn)
	ui = mn.kmed
	var s_d := spot(ui, fd)
	root.push_input(motion(s_d), true)
	var v_d: PackedVector3Array = ui.mesh.verts.duplicate()
	var f_d: Array = ui.mesh.faces.duplicate()
	steps0 = ui.undo.steps.size()
	var redo0: int = ui.undo.redos.size()
	ui.input(key(KEY_E))
	move_by(s_d, Vector2(0, -60))
	ui.input(key(KEY_ESCAPE))
	var same_v: bool = ui.mesh.verts == v_d
	var same_f: bool = KMeshUndo._same_faces(ui.mesh.faces, f_d)
	ok(same_v and same_f and ui.undo.steps.size() == steps0 and ui.undo.redos.size() == redo0 and KMeshDragOp.active(ui) == null,
		"(d) E, drag 60 px up, Esc: verts %s, faces %s, undo steps %d -> %d, redo %d -> %d" % [str(same_v), str(same_f), steps0, ui.undo.steps.size(), redo0, ui.undo.redos.size()])

	ui.stop()
	print("extrudeflow: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
