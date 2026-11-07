extends SceneTree
## P03 the last-op redo panel (scripts/kmesh_redo_panel.gd; ROADMAP_400 P03). After a mesh op on the model preview's 4x4 test
## cube (bevel, extrude, inset, subdivide) a small panel shows its parameters; changing one re-runs the op from the PRE-op
## state, replaces the result, stays ONE undo step, and closes on the next unrelated edit. Bars, written before the code:
## (A) for each of extrude (10 cm default -> 7 cm), inset (default -> 4 cm), bevel (2 cm -> 1.5 cm) and subdivide (1 -> 2 levels):
##     the op runs the way a user runs it, the panel is visible, the parameter is set by emitting value_changed on the panel's
##     real SpinBox, and the mesh (verts + faces, as bytes) is byte-identical to the same op done directly at the new value on a
##     fresh cube; and it differs from the first result (the panel did something)
## (B) five changes of one parameter (per op) leave exactly one more undo step than before the op; the last result equals the
##     direct op at the last value; Ctrl+Z (a real key) restores the pre-op mesh byte for byte, and the panel closes with it
## (C) an unrelated edit (a vertex nudge, one undo step): the panel is hidden after a frame, is_live() is false, emitting
##     value_changed on its SpinBox changes nothing (mesh bytes and step count the same), set_param() returns false
## (D) CONTROL, planted: a fake panel that re-runs ON TOP of the previous result (the stacking bug) is given the same sequence
##     as (A) for extrude; it MUST fail the byte-identical bar (and the real one must pass it, so the bar can tell them apart)
## (E) the panel is driven through its real controls only: the SpinBox objects found by name under the panel, value_changed emitted
var fails := 0
var mn: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func key(code: int, ctrl := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.physical_keycode = code
	k.ctrl_pressed = ctrl
	return k


## verts + faces as one byte string (every face with its length, so two splits of the same ints cannot match)
func bytes_of(m: KMesh) -> PackedByteArray:
	var b := m.verts.to_byte_array()
	for f in m.faces:
		b.append_array(PackedInt32Array([(f as PackedInt32Array).size()]).to_byte_array())
		b.append_array((f as PackedInt32Array).to_byte_array())
	return b


## a fresh test cube; the selection for `kind` (a top face, or a vertical cube edge for the bevel)
func fresh(kind: String):
	var ui = mn.kmed
	if ui != null and ui.on:
		ui.stop()
	mn._kmesh_edit_start()
	await process_frame
	await process_frame
	ui = mn.kmed
	ui.sel.clear()
	if kind == "bevel":
		var h: float = KMeshEditUI.SIDE * 0.5
		var pick := Vector2i(-1, -1)
		for e in ui.mesh.edges():
			var a: Vector3 = ui.mesh.verts[e.x]
			var b: Vector3 = ui.mesh.verts[e.y]
			if absf(a.x - h) < 1e-6 and absf(b.x - h) < 1e-6 and absf(a.z - h) < 1e-6 and absf(b.z - h) < 1e-6 and minf(a.y, b.y) < -h + 1e-6:
				pick = e
		ui.set_mode(KMeshSelect.EDGE)
		ui.sel.edges[pick] = true
	elif kind != "subdivide":
		ui.set_mode(KMeshSelect.FACE)
		for fi in ui.mesh.face_count():
			if absf(ui.mesh.face_center(fi).y - 0.3) < 1e-6:
				ui.sel.faces[fi] = true
				break
	return ui


## the way a user runs the op (the buttons / Ctrl+B / Ctrl+1 paths)
func run_op(ui, kind: String) -> void:
	match kind:
		"extrude", "inset":
			ui.quick(kind)
		"bevel":
			ui.input(key(KEY_B, true))
		"subdivide":
			ui.subdivide(1)


## the same op, done directly at the value (cm for lengths) on a fresh cube, no panel
func direct(ui, kind: String, v: float) -> void:
	match kind:
		"extrude":
			KMeshExtrude.extrude(ui.mesh, ui.sel, v / 100.0)
		"inset":
			KMeshExtrude.inset(ui.mesh, ui.sel, v / 100.0)
		"bevel":
			KMeshBevel.bevel(ui.mesh, ui.sel, v / 100.0, 1, 0.5)
		"subdivide":
			ui.subdivide(int(v))


func spin(ui, p: String) -> SpinBox:
	return ui.redo_panel.spin(p)


## the real control: the SpinBox shows the value and emits value_changed
func set_spin(ui, p: String, v: float) -> void:
	var s := spin(ui, p)
	s.set_value_no_signal(v)
	s.value_changed.emit(v)


const PARAM := {"extrude": "distance", "inset": "amount", "bevel": "width", "subdivide": "levels"}
const W2 := {"extrude": 7.0, "inset": 4.0, "bevel": 1.5, "subdivide": 2.0}
const SERIES := {"extrude": [3.0, 4.0, 5.5, 6.0, 8.0], "inset": [1.0, 2.0, 3.0, 5.0, 2.5], "bevel": [0.5, 1.0, 2.5, 3.0, 1.2], "subdivide": [2, 3, 1, 2, 1]}


func _init() -> void:
	mn = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await process_frame
	await process_frame
	var kinds := ["extrude", "inset", "bevel", "subdivide"]

	# (A) + (E)
	for kind in kinds:
		var ui = await fresh(kind)
		var pre := bytes_of(ui.mesh)
		run_op(ui, kind)
		var first := bytes_of(ui.mesh)
		var shown: bool = ui.redo_panel != null and ui.redo_panel.visible and spin(ui, PARAM[kind]) != null
		ok(first != pre and shown, "(A) %s: the op ran (mesh changed) and the redo panel shows its %s field" % [kind, PARAM[kind]])
		set_spin(ui, PARAM[kind], W2[kind])
		var got := bytes_of(ui.mesh)
		var ref = await fresh(kind)
		direct(ref, kind, W2[kind])
		var want := bytes_of(ref.mesh)
		ok(got == want and got != first, "(A) %s: %s -> %s through the SpinBox: byte-identical to doing it directly (%d bytes), differs from the first result" % [kind, PARAM[kind], str(W2[kind]), got.size()])

	# (B)
	for kind in kinds:
		var ui = await fresh(kind)
		var n0: int = ui.undo.steps.size()
		run_op(ui, kind)
		for v in SERIES[kind]:
			set_spin(ui, PARAM[kind], float(v))
		var n1: int = ui.undo.steps.size()
		var got := bytes_of(ui.mesh)
		var ref = await fresh(kind)
		direct(ref, kind, float(SERIES[kind][4]))
		ok(n1 == n0 + 1 and got == bytes_of(ref.mesh), "(B) %s: 5 changes leave %d undo step (before the op %d, now %d) and the last equals the direct op at %s" % [kind, n1 - n0, n0, n1, str(SERIES[kind][4])])
		ui = await fresh(kind)
		var pre := bytes_of(ui.mesh)
		run_op(ui, kind)
		for v in SERIES[kind]:
			set_spin(ui, PARAM[kind], float(v))
		ui.input(key(KEY_Z, true))
		await process_frame
		ok(bytes_of(ui.mesh) == pre and ui.undo.steps.size() == 0 and not ui.redo_panel.visible,
			"(B) %s: Ctrl+Z after 5 changes: pre-op mesh byte for byte, no steps left, panel closed" % kind)

	# (C)
	for kind in kinds:
		var ui = await fresh(kind)
		run_op(ui, kind)
		set_spin(ui, PARAM[kind], float(SERIES[kind][1]))
		ui.undo.begin(ui.mesh)
		ui.mesh.verts[0] += Vector3(0.01, 0.0, 0.0)   # an unrelated edit: one vertex nudged
		var st: Dictionary = ui.undo.commit("nudge")
		await process_frame
		await process_frame
		var after := bytes_of(ui.mesh)
		var steps: int = ui.undo.steps.size()
		var hidden: bool = not ui.redo_panel.visible and not ui.redo_panel.is_live()
		set_spin(ui, PARAM[kind], float(SERIES[kind][3]))
		var refused: bool = not ui.redo_panel.set_param(PARAM[kind], float(SERIES[kind][2]))
		ok(not st.is_empty() and hidden and refused and bytes_of(ui.mesh) == after and ui.undo.steps.size() == steps,
			"(C) %s: after an unrelated edit the panel is hidden, not live, the field and set_param change nothing (%d steps)" % [kind, steps])

	# (D) planted control: re-run on top of the previous result must fail the bar the real panel passes
	var ui_d = await fresh("extrude")
	run_op(ui_d, "extrude")                 # 10 cm
	var fake := FakeStackPanel.new()
	fake.rerun(ui_d, 7.0)                   # the stacking bug: 7 cm more on top of the 10 cm
	var fake_bytes := bytes_of(ui_d.mesh)
	var ref_d = await fresh("extrude")
	direct(ref_d, "extrude", 7.0)
	var want_d := bytes_of(ref_d.mesh)
	ok(fake_bytes != want_d, "(D) control: the stacking fake (re-runs on the previous result) FAILS the byte-identical bar (%d vs %d bytes)" % [fake_bytes.size(), want_d.size()])
	var ui_r = await fresh("extrude")
	run_op(ui_r, "extrude")
	set_spin(ui_r, "distance", 7.0)
	ok(bytes_of(ui_r.mesh) == want_d, "(D) control: the real panel passes the very same bar (the bar tells them apart)")

	if mn.kmed != null and mn.kmed.on:
		mn.kmed.stop()
	print("redopanel: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## the planted bug: re-run the extrude on whatever the mesh is now (no return to the pre-op state)
class FakeStackPanel:
	func rerun(ui, cm: float) -> void:
		ui.undo.begin(ui.mesh)
		KMeshExtrude.extrude(ui.mesh, ui.sel, cm / 100.0)
		ui.undo.commit("Extrude")
