## godot --path . --position 3000,3000 -s tests/walk_model_test.gd   (WALK-THROUGH: MODEL / SCULPT / SURFACE, Expert mode)
## A person who knows a little Blender: every step is a real mouse click, drag or key press through the UI (main's own
## input path). Positions are the on-screen spots of the faces, edges and sphere points, as a person would click them.
## A screenshot after each step goes to C:/Temp/claude/walkmodel/. MEASURES, FIXES NOTHING: a failed goal is logged as failed.
## The log is printed and written to C:/Temp/claude/walkmodel/log.txt. A test runs on its own settings file (never poser.cfg).
extends SceneTree

const OUT := "C:/Temp/claude/walkmodel/"

var m: Node
var kmed
var ksc
var n_shot := 0
var lines: Array = []
var clicks := 0
var keys := 0
var t0 := 0
var goal := ""
var rows: Array = []   # one row per goal: [number, goal, done, actions, note]


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):   # INTERNAL children too (a dialog's button row is internal)
		walk(c, out)
	return out


func visible_nodes() -> Array:
	var out := []
	for n in walk(root, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in visible_nodes():
		if n is Button:
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		var t := text_of(b)
		if t == txt or (prefix and t.begins_with(txt)):
			return b
	return null


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		var t := text_of(b)
		if t != "":
			out.append(t)
	return str(out)


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


## the mouse moved by d with no button down, in steps (a live tool follows it: E / I, Ctrl+R)
func hover_by(p: Vector2, d: Vector2) -> void:
	for i in 6:
		var hm := InputEventMouseMotion.new()
		var q := p + d * float(i + 1) / 6.0
		hm.position = q
		hm.global_position = q
		root.push_input(hm)
		await process_frame
	await idle(3)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


## what is under the pointer at p (a panel over the view would take the click instead of the mesh)
func hit_name(p: Vector2) -> String:
	var h := root.get_viewport().gui_get_hovered_control()
	return "none (the view)" if h == null else str(h.name) + " (" + h.get_class() + ")"


## a real click at a spot on the screen (the view, or a button's centre when given one)
func click_at(p: Vector2, what: String) -> void:
	clicks += 1
	await hover(p)
	say("   click %s at %s | under the pointer: %s" % [what, str(p), hit_name(p)])
	btn(true, p)
	await process_frame
	btn(false, p)
	await idle(3)


## a click on a visible button with these words (the words a person reads on it)
func click_text(txt: String, prefix := false) -> bool:
	var b := find_btn(txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	clicks += 1
	say("   click button '%s'" % text_of(b))
	var c: Vector2 = b.get_global_rect().get_center()
	await hover(c)
	btn(true, c)
	await process_frame
	btn(false, c)
	await idle(3)
	return true


## a real drag from p by d (the mouse down, moved in steps, let go)
func drag_at(p: Vector2, d: Vector2, what: String) -> void:
	clicks += 1
	await hover(p)
	say("   drag %s from %s by %s | under the pointer: %s" % [what, str(p), str(d), hit_name(p)])
	btn(true, p)
	await process_frame
	for i in 6:
		move(p + d * (i + 1) / 6.0, d / 6.0)
		await process_frame
	btn(false, p + d)
	await idle(3)


## a key press (down and up), with Ctrl / Shift when asked: the way a real key comes in
func key(k: Key, ctrl := false, shift := false, label := "") -> void:
	keys += 1
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.pressed = true
	root.push_input(ev)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = k
	up.physical_keycode = k
	up.ctrl_pressed = ctrl
	up.shift_pressed = shift
	up.pressed = false
	root.push_input(up)
	await idle(3)
	say("   key %s" % label)


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s" % f)
	say("   status line: %s" % (str(m.ui_status.text) if m.ui_status != null else "-"))
	say("   visible buttons: %s" % btn_names())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	keys = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(num: String, ok: bool, note: String) -> void:
	say("== END %s: done=%s clicks=%d keys=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, keys, (Time.get_ticks_msec() - t0) / 1000.0, note])
	rows.append([num, goal, "yes" if ok else "NO", "%d clicks, %d keys" % [clicks, keys], note])


## the mesh's counts, as the test sees them (not as the app says them)
func counts() -> String:
	if kmed == null or kmed.mesh == null:
		return "no mesh"
	return "verts %d, faces %d, selected %d" % [kmed.mesh.vert_count(), kmed.mesh.face_count(), kmed.sel.count()]


func nv() -> int:
	return kmed.mesh.vert_count()


func nf() -> int:
	return kmed.mesh.face_count()


func ymax() -> float:
	var mx := -1.0e9
	for i in kmed.mesh.vert_count():
		mx = maxf(mx, kmed.view._to_world(i).y)
	return mx


func face_center(fi: int) -> Vector3:
	var f: PackedInt32Array = kmed.mesh.faces[fi]
	var c := Vector3.ZERO
	for vi in f:
		c += kmed.view._to_world(vi)
	return c / float(f.size())


## the camera-facing face: the one a person would click in the middle of the view
func front_face() -> int:
	var best := -1
	var bd := -2.0
	var cam_pos: Vector3 = m.cam.global_position
	for fi in kmed.mesh.face_count():
		var c := face_center(fi)
		var n: Vector3 = (kmed.view.global_transform.basis * kmed.mesh.face_normals[fi]).normalized()
		var d := n.dot((cam_pos - c).normalized())
		if d > bd and not m.cam.is_position_behind(c):
			bd = d
			best = fi
	return best


func scr(wp: Vector3) -> Vector2:
	return m.cam.unproject_position(wp)


func face_spot(fi: int) -> Vector2:
	return scr(face_center(fi))


## the middle of the edge between two corners of a face, on the screen
func edge_spot(fi: int, a: int, b: int) -> Vector2:
	var f: PackedInt32Array = kmed.mesh.faces[fi]
	return scr((kmed.view._to_world(f[a]) + kmed.view._to_world(f[b])) * 0.5)


## the sphere point facing the camera, on the screen
func sphere_spot() -> Vector2:
	var center: Vector3 = ksc.view.global_position
	var to_cam: Vector3 = (m.cam.global_position - center).normalized()
	var best := 0
	var bd := -2.0
	for i in ksc.mesh.vert_count():
		var d: float = (ksc.view._to_world(i) - center).normalized().dot(to_cam)
		if d > bd:
			bd = d
			best = i
	return scr(ksc.view._to_world(best))


func max_move(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var mx := 0.0
	for i in mini(a.size(), b.size()):
		mx = maxf(mx, a[i].distance_to(b[i]))
	return mx


func body_on_screen() -> bool:
	var c: Array = m.B.cap("pelvis")
	var at: Vector3 = (c[0] + c[1]) * 0.5
	var vp := m.get_viewport().get_visible_rect()
	return not m.cam.is_position_behind(at) and vp.has_point(m.cam.unproject_position(at))


func idle_frames_until_mesh(limit := 60) -> void:
	for i in limit:
		if kmed != null and kmed.on and kmed.view != null and kmed.view.is_inside_tree():
			return
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if m.easy.on:
		say("   Easy was on at start: clicking Switch to Expert, as a user would")
		await click_text("Switch to Expert")
		await idle(10)
	var body0: Dictionary = m.B.ang.duplicate(true)
	var cards0: int = m.S.cards.size()
	await shot("00_start_expert")

	# 1. OPEN MODEL, GET THE TEST CUBE
	begin_goal("1 open MODEL, get the test cube")
	await click_text("MODEL")
	await shot("01_model_page")
	await click_text("Test cube")
	await shot("02_test_cube")
	kmed = m.kmed
	end_goal("1", kmed != null and kmed.on, "(%s)" % counts())

	# 2. SELECT A FACE, E, DRAG UP
	begin_goal("2 select a face, extrude it up (E + drag)")
	var f0 := front_face()
	await key(KEY_3, false, false, "3 (face mode)")
	await click_at(face_spot(f0), "on the face")
	await shot("03_face_selected")
	var v_before := nv()
	var f_before := nf()
	await key(KEY_E, false, false, "E")
	var v_after_e := nv()
	var f_after_e := nf()
	var y_after_e := ymax()
	await shot("04_after_E")
	# E is live: the mouse moves the new face along its normal, a click confirms
	await hover_by(face_spot(f0), Vector2(0, -60))
	await shot("05_after_drag")
	var y_mid := ymax()
	await click_at(face_spot(f0) + Vector2(0, -60), "to confirm the extrude (where the mouse is now)")
	await shot("05b_confirmed")
	var moved := absf(ymax() - y_after_e)
	say("   extrusion: faces %d -> %d; the top at the mouse %.4f m above the cube's, after the click %.4f m" % [f_before, f_after_e, y_mid - y_after_e, moved])
	end_goal("2", f_after_e > f_before and moved > 0.05, "(faces %d -> %d; mouse 60 px up: the top %.1f cm up; counts now %s)" % [f_before, f_after_e, moved * 100.0, counts()])

	# 3. INSET A FACE
	begin_goal("3 inset a face (I)")
	var f1 := front_face()
	await click_at(face_spot(f1), "on the face")
	var f_pre_i := nf()
	await key(KEY_I, false, false, "I")
	await hover_by(face_spot(f1), Vector2(-30, 0))
	await click_at(face_spot(f1) + Vector2(-30, 0), "to confirm the inset (the mouse 30 px out from the face centre)")
	await shot("06_inset")
	end_goal("3", nf() > f_pre_i, "(faces %d -> %d)" % [f_pre_i, nf()])
	var c_inset := [nv(), nf()]   # geometry only: an undo clears the selection, so the selected count is not compared

	# 4. LOOP CUT (Ctrl+R, hover an edge, click)
	begin_goal("4 loop cut (Ctrl+R over an edge, click)")
	var f2 := front_face()
	var spot := edge_spot(f2, 0, 1)
	var f_pre_r := nf()
	await key(KEY_R, true, false, "Ctrl+R")
	await shot("07_loopcut_armed")
	await hover(spot)
	await idle(10)
	await shot("08_loopcut_hover")
	await click_at(spot, "on the edge to cut (one click)")
	await shot("09_loopcut_done")
	var c_loop := [nv(), nf()]
	end_goal("4", nf() > f_pre_r, "(faces %d -> %d)" % [f_pre_r, nf()])

	# 5. BEVEL AN EDGE (2 = edge mode, click an edge, Ctrl+B)
	begin_goal("5 bevel an edge (2, click an edge, Ctrl+B)")
	var f3 := front_face()
	await key(KEY_2, false, false, "2 (edge mode)")
	await click_at(edge_spot(f3, 1, 2), "on an edge")
	var v_pre_b := nv()
	await key(KEY_B, true, false, "Ctrl+B")
	await shot("10_bevel")
	end_goal("5", nv() > v_pre_b, "(verts %d -> %d)" % [v_pre_b, nv()])

	# 6. UNDO TWICE, REDO
	begin_goal("6 undo twice, redo (Ctrl+Z x2, then Ctrl+Shift+Z)")
	await key(KEY_Z, true, false, "Ctrl+Z")
	await shot("11_undo_1")
	await key(KEY_Z, true, false, "Ctrl+Z")
	await shot("12_undo_2")
	var after_undo := counts()
	var back_to_inset := [nv(), nf()] == c_inset
	say("   after two undos: %s | equals the state after the inset (verts, faces): %s" % [after_undo, str(back_to_inset)])
	await key(KEY_Z, true, true, "Ctrl+Shift+Z (Blender redo)")
	await shot("13_redo_shift")
	var after_redo_shift := counts()
	var redo_ok := [nv(), nf()] == c_loop
	if not redo_ok:
		say("   Ctrl+Shift+Z did not give the state after the loop cut (%s); trying Ctrl+Y" % after_redo_shift)
		await key(KEY_Y, true, false, "Ctrl+Y")
		await shot("14_redo_y")
		redo_ok = [nv(), nf()] == c_loop
	say("   after redo: %s | equals the state after the loop cut (verts, faces): %s" % [counts(), str(redo_ok)])
	end_goal("6", back_to_inset and redo_ok, "(after 2 undos %s; after redo %s; loop cut state verts %d faces %d)" % [after_undo, counts(), c_loop[0], c_loop[1]])

	# 7. SCULPT: one brush stroke on the sphere
	begin_goal("7 sculpt: one Draw stroke on the sphere")
	await click_text("SCULPT")
	await shot("15_sculpt_page")
	await click_text("Test sphere")
	await idle_frames_until_mesh()
	ksc = m.ksc
	await shot("16_test_sphere")
	var sp0: PackedVector3Array = PackedVector3Array()
	var sph_ok: bool = ksc != null and ksc.on
	if sph_ok:
		sp0 = ksc.mesh.verts.duplicate()
		await click_text("Draw")
		var s := sphere_spot()
		await drag_at(s, Vector2(70, 0), "across the sphere with the Draw brush")
		await shot("17_stroke")
		var disp := max_move(sp0, ksc.mesh.verts)
		say("   largest vertex move on the sphere: %.2f mm" % (disp * 1000.0))
		sph_ok = disp > 0.0005
	end_goal("7", sph_ok, "(sphere open: %s)" % str(ksc != null and ksc.on))

	# 8. SURFACE: UVs and a material
	begin_goal("8 surface: UVs and a material")
	await click_text("SURFACE")
	await shot("18_surface_page")
	await click_text("UV editor")
	await shot("19_uv_editor")
	var uv_on := false
	await click_text("Game UVs 2k")
	await shot("20_game_uvs")
	uv_on = kmed != null and kmed.mesh != null and kmed.mesh.has_attr(KMeshUV.UV)
	var mat_btn := ""
	if kmed != null and kmed.mat_panel != null:
		var mb: Array = []
		for n in walk(kmed.mat_panel, []):
			if n is Button and (n as Button).is_visible_in_tree():
				mb.append(text_of(n as Button))
		say("   material panel buttons: %s" % str(mb))
	var mats0: int = kmed.mesh.materials.size() if kmed != null and kmed.mesh != null else -1
	for pre in ["New", "Add", "+", "Make", "Create"]:
		var b := find_btn(pre, true)
		if b != null:
			mat_btn = text_of(b)
			break
	if mat_btn != "":
		await click_text(mat_btn)
		await shot("21_material")
	else:
		say("   no visible button to make or add a material on the mesh (the Materials panel and its buttons are listed above)")
		await shot("21_no_material_button")
	var mats1: int = kmed.mesh.materials.size() if kmed != null and kmed.mesh != null else -1
	say("   material slots on the mesh: %d -> %d | UVs on the mesh: %s" % [mats0, mats1, str(uv_on)])
	end_goal("8", uv_on and mats1 > mats0, "(UVs: %s; material slots %d -> %d; button used: '%s')" % [str(uv_on), mats0, mats1, mat_btn])

	# 9. BACK TO POSE: the body is as it was
	begin_goal("9 back to POSE: the body is as it was")
	await click_text("POSE")
	await shot("22_pose_again")
	var same_ang: bool = m.B.ang == body0
	var same_cards: bool = m.S.cards.size() == cards0
	var on_screen := body_on_screen()
	say("   body angles unchanged: %s | cards %d -> %d | body on screen: %s" % [str(same_ang), cards0, m.S.cards.size(), str(on_screen)])
	end_goal("9", same_ang and same_cards and on_screen, "(angles same: %s, cards same: %s, body on screen: %s)" % [str(same_ang), str(same_cards), str(on_screen)])

	say("\n| # | Goal | Done | Actions | Notes |")
	say("|---|---|---|---|---|")
	for r in rows:
		say("| %s | %s | %s | %s | %s |" % r)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
