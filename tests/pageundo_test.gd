## godot --path . -s tests/pageundo_test.gd     (ROADMAP_400 P12: ONE UNDO HISTORY ACROSS PAGES; needs a window: main is booted)
## Before this, Ctrl+Z took back the pose steps (Main.undo) on every page except a mesh page, which took its own KMeshUndo
## (sculpt sphere and model cube each their own list): a sculpt stroke, a pose key and a mesh op were three lists, and Ctrl+Z
## on one page never reached the other two in the order they were made. Bars (stated before the implementation):
##   1 the three edits leave three different states (sculpt verts, the keyed cards, the cube mesh) and the page is MODEL
##   2 real Ctrl+Z #1 takes back the MESH OP: the cube's verts and faces are byte-identical to before it; the active page is MODEL;
##     the pose key and the sculpt stroke are still there
##   3 Ctrl+Z #2 takes back the POSE KEY: body + cards byte-identical to before the key; the page is now ANIMATE; the stroke is still there
##   4 Ctrl+Z #3 takes back the SCULPT STROKE: the sphere's verts byte-identical to before; the page is now SCULPT
##   5 Ctrl+Shift+Z redoes in reverse: stroke (page SCULPT), then pose key (ANIMATE), then Ctrl+Y the mesh op (MODEL), each byte-identical
##     to the state just after the original edit
##   6 the active page follows the step: asserted at every undo and redo above (the page after each key press)
##   7 a new edit after an undo clears the redo, ACROSS pages: undo the mesh op, key another pose, then Ctrl+Y does nothing
##     (the cube stays as it was before the op, the page stays) and Ctrl+Z walks back the new key, then the stroke
##   P planted control: the byte comparison used above must say DIFFERENT for a one-vertex 1e-6 tamper and for the unsculpted vs the
##     sculpted sphere (a comparison that cannot fail proves nothing)
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)


func key(k: int, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func vbytes(v: PackedVector3Array) -> PackedByteArray:
	return v.to_byte_array()


func mesh_sig(mm) -> PackedByteArray:
	return vbytes(mm.verts) + var_to_bytes(mm.faces)


## everything a pose step must bring back: the body and the cards
func pose_sig() -> PackedByteArray:
	return (JSON.stringify(m.B.state()) + JSON.stringify(m.S.cards)).to_utf8_buffer()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	await idle(4)
	# --- 1 the three edits, on three pages
	m._sculpt_start()
	await idle(3)
	var ks = m.ksc
	var wc: Vector3 = ks.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cs: Vector2 = m.cam.unproject_position(wc)
	var s0 := vbytes(ks.mesh.verts)
	await drag(cs + Vector2(-30, 0), cs + Vector2(30, 0))
	var s1 := vbytes(ks.mesh.verts)
	m._page_set("ANIMATE")
	await idle(3)
	m.auto_key = true
	var p0 := pose_sig()
	var ncards0: int = m.S.cards.size()
	m._do(func():
		m.B.ang["upperarm_r"] = Vector3(0.0, 0.0, 0.9)
		m.B.fk())
	await idle(2)
	var p1 := pose_sig()
	m._kmesh_edit_start()
	await idle(3)
	var kd = m.kmed
	var c0 := mesh_sig(kd.mesh)
	kd.subdivide(1)
	await idle(2)
	var c1 := mesh_sig(kd.mesh)
	ok(s0 != s1 and p0 != p1 and c0 != c1 and m.cur_page == "MODEL",
		"(1) three edits: stroke %s, pose key %s (%d -> %d cards), mesh op %s; page %s" % [s0 != s1, p0 != p1, ncards0, m.S.cards.size(), c0 != c1, m.cur_page])
	# --- 2..4 Ctrl+Z x3
	await key(KEY_Z, true)
	ok(mesh_sig(kd.mesh) == c0 and m.cur_page == "MODEL" and pose_sig() == p1 and vbytes(ks.mesh.verts) == s1,
		"(2) Ctrl+Z #1: the cube is byte-identical to before the op (%s), page %s, key and stroke still there (%s, %s)" % [mesh_sig(kd.mesh) == c0, m.cur_page, pose_sig() == p1, vbytes(ks.mesh.verts) == s1])
	await key(KEY_Z, true)
	ok(pose_sig() == p0 and m.cur_page == "ANIMATE" and vbytes(ks.mesh.verts) == s1 and mesh_sig(kd.mesh) == c0,
		"(3) Ctrl+Z #2: body + cards byte-identical to before the key (%s), page %s, stroke still there (%s)" % [pose_sig() == p0, m.cur_page, vbytes(ks.mesh.verts) == s1])
	await key(KEY_Z, true)
	ok(vbytes(ks.mesh.verts) == s0 and m.cur_page == "SCULPT" and pose_sig() == p0,
		"(4) Ctrl+Z #3: the sphere is byte-identical to before the stroke (%s), page %s" % [vbytes(ks.mesh.verts) == s0, m.cur_page])
	# --- 5, 6 redo in reverse order
	await key(KEY_Z, true, true)
	var r1 = vbytes(ks.mesh.verts) == s1 and m.cur_page == "SCULPT" and pose_sig() == p0
	await key(KEY_Z, true, true)
	var r2 = pose_sig() == p1 and m.cur_page == "ANIMATE" and mesh_sig(kd.mesh) == c0
	await key(KEY_Y, true)
	var r3 = mesh_sig(kd.mesh) == c1 and m.cur_page == "MODEL" and pose_sig() == p1 and vbytes(ks.mesh.verts) == s1
	ok(r1 and r2 and r3, "(5/6) Ctrl+Shift+Z: stroke back, page SCULPT %s; again: key back, page ANIMATE %s; Ctrl+Y: mesh op back, page MODEL %s" % [r1, r2, r3])
	# --- 7 a new edit after an undo clears the redo across pages
	await key(KEY_Z, true)   # the mesh op
	m._page_set("ANIMATE")
	await idle(2)
	m._do(func():
		m.B.ang["upperarm_l"] = Vector3(0.0, 0.0, -0.7)
		m.B.fk())
	await idle(2)
	var p2 := pose_sig()
	await key(KEY_Y, true)
	var stayed = mesh_sig(kd.mesh) == c0 and m.cur_page == "ANIMATE" and pose_sig() == p2 and kd.undo.redos.is_empty()
	await key(KEY_Z, true)
	var back_key = pose_sig() == p1 and m.cur_page == "ANIMATE"
	await key(KEY_Z, true)
	var back_pose = pose_sig() == p0
	await key(KEY_Z, true)
	var back_stroke = vbytes(ks.mesh.verts) == s0 and m.cur_page == "SCULPT"
	ok(stayed and back_key and back_pose and back_stroke,
		"(7) new edit after undo: Ctrl+Y does nothing %s; Ctrl+Z walks the new key %s, the old key %s, the stroke %s" % [stayed, back_key, back_pose, back_stroke])
	# --- P planted control
	var tam = ks.mesh.verts.duplicate()
	tam[5] += Vector3(1e-6, 0, 0)
	ok(vbytes(tam) != vbytes(ks.mesh.verts) and s0 != s1 and p0 != p1 and c0 != c1,
		"(P) planted: a 1e-6 tamper is detected by the byte comparison, and the before / after states all differ")
	print("pageundo: %d fail" % fails)
	quit(1 if fails > 0 else 0)
