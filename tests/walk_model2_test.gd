## godot --path . --position 3000,3000 -s tests/walk_model2_test.gd   (WALK-THROUGH 2: MODEL / SCULPT / SURFACE, round 2)
## The Blender user's next tasks: Mirror modifier, edge loop (Alt+click), S / G with proportional editing (O) and the wheel,
## Subdivide (Ctrl+1 or the Modifiers panel), sculpt Smooth and Grab then undo, UVs and a material on some faces, export,
## and the Body mesh edit through Apply body and POSE. Every step is a real click, drag, wheel or key through the UI.
## Screenshots after each step go to C:/Temp/claude/walkmodel2/; the log goes to C:/Temp/claude/walkmodel2/log.txt.
## MEASURES, FIXES NOTHING: a failed goal is logged as failed. A test runs on its own settings file (never poser.cfg).
extends SceneTree

const OUT := "C:/Temp/claude/walkmodel2/"

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
		hm.relative = d / 6.0   # a real mouse motion carries its step (the G / R / S modal moves by it)
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




## a real click with modifier keys held (Alt+click picks an edge loop, Shift+click adds to the selection)
func click_mod(p: Vector2, what: String, alt := false, shift := false, ctrl := false) -> void:
	clicks += 1
	await hover(p)
	say("   click %s at %s (alt %s, shift %s) | under the pointer: %s" % [what, str(p), str(alt), str(shift), hit_name(p)])
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		e.alt_pressed = alt
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)


## a key with Alt / Ctrl / Shift held as asked
func key_mod(k: Key, ctrl := false, shift := false, alt := false, label := "") -> void:
	keys += 1
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.alt_pressed = alt
		ev.pressed = down
		root.push_input(ev)
		await process_frame
	await idle(3)
	say("   key %s" % label)


## the mouse wheel over p, n notches (a live G / R / S reads it as the proportional radius)
func wheel(p: Vector2, up: bool, n := 1) -> void:
	for i in n:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.factor = 1.0
		e.position = p
		e.global_position = p
		root.push_input(e)
		await process_frame
		var r := InputEventMouseButton.new()
		r.button_index = e.button_index
		r.pressed = false
		r.factor = 1.0
		r.position = p
		r.global_position = p
		root.push_input(r)
		await process_frame
	await idle(3)
	say("   scroll wheel %s x%d at %s" % ["up" if up else "down", n, str(p)])


func option_items(ob: OptionButton) -> Array:
	var out := []
	for i in ob.item_count:
		out.append(ob.get_item_text(i))
	return out


func find_option(under: Node) -> OptionButton:
	for n in walk(under, []):
		if n is OptionButton and (n as OptionButton).is_visible_in_tree():
			return n
	return null


## opens a drop-down by a click, then clicks the choice with this text in its list
func pick_option(ob: OptionButton, item: String) -> bool:
	if ob == null:
		say("   NOT VISIBLE: no drop-down here")
		return false
	var idx := -1
	for i in ob.item_count:
		if ob.get_item_text(i) == item:
			idx = i
	if idx < 0:
		say("   NOT VISIBLE: no choice '%s' (choices: %s)" % [item, str(option_items(ob))])
		return false
	clicks += 1
	var c: Vector2 = ob.get_global_rect().get_center()
	await hover(c)
	say("   click the drop-down (shows '%s'; choices %s)" % [ob.get_item_text(ob.selected), str(option_items(ob))])
	btn(true, c)
	await process_frame
	btn(false, c)
	await idle(6)
	var pop: PopupMenu = ob.get_popup()
	if pop == null or not pop.visible:
		say("   the choice list did not open")
		return false
	var r := Rect2(Vector2(pop.position), Vector2(pop.size))
	var ih: float = r.size.y / float(maxi(pop.item_count, 1))
	var p := Vector2(r.position.x + r.size.x * 0.5, r.position.y + (idx + 0.5) * ih)
	clicks += 1
	await hover(p)
	say("   click '%s' in the list at %s | under the pointer: %s" % [item, str(p), hit_name(p)])
	btn(true, p)
	await process_frame
	btn(false, p)
	await idle(6)
	return true


func mesh_snapshot() -> PackedVector3Array:
	return kmed.mesh.verts.duplicate()


func moved_count(a: PackedVector3Array, b: PackedVector3Array) -> int:
	var n := 0
	for i in mini(a.size(), b.size()):
		if a[i].distance_to(b[i]) > 0.00005:
			n += 1
	return n


## how many of these base vertices have their mirror image (x flipped) in the evaluated mesh
func mirror_hits(base: PackedVector3Array, ev: PackedVector3Array, idxs: Array) -> int:
	var hit := 0
	for i in idxs:
		var r := Vector3(-base[i].x, base[i].y, base[i].z)
		for v in ev:
			if v.distance_to(r) < 0.0015:
				hit += 1
				break
	return hit


func export_files_since(dir: String, t: int) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		var full := dir + "/" + f
		if FileAccess.get_modified_time(full) * 1000 >= t - 2000:
			out.append("%s (%d bytes)" % [full, FileAccess.get_file_as_bytes(full).size()])
	return out


func _mat_btns() -> Array:
	var out := []
	if kmed == null or kmed.mat_panel == null:
		return out
	for n in walk(kmed.mat_panel, []):
		if n is Button and (n as Button).is_visible_in_tree():
			out.append(text_of(n as Button))
	return out


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
	await shot("00_start_expert")

	# 1. MIRROR MODIFIER
	begin_goal("1 Mirror modifier: edit one side, see both halves")
	await click_text("MODEL")
	await click_text("Test cube")
	kmed = m.kmed
	await idle(10)
	var mir_ok := false
	var mir_note := ""
	if kmed != null and kmed.on:
		await click_text("Modifiers")
		await shot("mirror_panel_open")
		var ob := find_option(kmed.mods.panel)
		if await pick_option(ob, "Mirror"):
			await click_in(kmed.mods.panel, "Add modifier")
			await shot("mirror_added")
			var base_before := mesh_snapshot()
			var ev0: int = kmed.mods.evaluated.vert_count() if kmed.mods.evaluated != null else -1
			say("   base verts %d; evaluated (with mirror) verts %d" % [base_before.size(), ev0])
			var f1 := front_face()
			await key(KEY_3, false, false, "3 (face mode)")
			await click_at(face_spot(f1), "on the face (the side the user edits)")
			await key(KEY_E, false, false, "E")
			await hover_by(face_spot(f1), Vector2(0, -60))
			await click_at(face_spot(f1) + Vector2(0, -60), "to confirm the extrude")
			await shot("mirror_after_edit")
			var base_after := mesh_snapshot()
			var moved_idx := []
			for i in mini(base_before.size(), base_after.size()):
				if base_before[i].distance_to(base_after[i]) > 0.00005:
					moved_idx.append(i)
			var ev_now: PackedVector3Array = kmed.mods.evaluated.verts.duplicate() if kmed.mods.evaluated != null else PackedVector3Array()
			var hits := mirror_hits(base_after, ev_now, moved_idx)
			mir_ok = moved_idx.size() > 0 and hits == moved_idx.size()
			mir_note = "moved %d base verts; their mirror images in the evaluated mesh: %d; evaluated verts %d" % [moved_idx.size(), hits, ev_now.size()]
		else:
			mir_note = "no Mirror choice in the Modifiers panel"
	else:
		mir_note = "the test cube did not open"
	end_goal("1", mir_ok, "(%s)" % mir_note)

	# 2. EDGE LOOP (Alt+click) AND SCALE (S + drag)
	begin_goal("2 edge loop: Alt+click, then S + drag")
	await key(KEY_2, false, false, "2 (edge mode)")
	var fe := front_face()
	var espot := edge_spot(fe, 0, 1)
	await click_mod(espot, "on an edge, with Alt held", true)
	var sel_after_alt: int = kmed.sel.count()
	await shot("loop_alt_click")
	say("   selected after Alt+click: %d (a loop round the cube would be 4 or more edges)" % sel_after_alt)
	var pre_s := mesh_snapshot()
	await key(KEY_S, false, false, "S")
	await hover_by(espot, Vector2(-50, 0))
	await click_at(espot + Vector2(-50, 0), "to confirm the scale (mouse 50 px out)")
	await shot("loop_scaled")
	var s_moved := moved_count(pre_s, mesh_snapshot())
	say("   vertices moved by the scale: %d" % s_moved)
	end_goal("2", sel_after_alt > 2 and s_moved > 0, "(selected after Alt+click %d; vertices moved by S: %d)" % [sel_after_alt, s_moved])

	# 3. GRAB A VERTEX WITH PROPORTIONAL EDITING, WHEEL FOR RADIUS
	begin_goal("3 grab a vertex (G + drag) with proportional editing (O), wheel for radius")
	await key(KEY_1, false, false, "1 (vertex mode)")
	await key(KEY_O, false, false, "O (proportional on)")
	var vi: int = kmed.mesh.faces[front_face()][0]
	var vspot := scr(kmed.view._to_world(vi))
	await click_at(vspot, "on a vertex")
	var pre_g := mesh_snapshot()
	await key(KEY_G, false, false, "G")
	await hover_by(vspot, Vector2(0, -40))
	await wheel(vspot + Vector2(0, -40), true, 2)
	await hover_by(vspot + Vector2(0, -40), Vector2(0, -20))
	await shot("prop_grab_live")
	await click_at(vspot + Vector2(0, -60), "to confirm the grab")
	await shot("prop_grab_done")
	var g_moved := moved_count(pre_g, mesh_snapshot())
	say("   vertices moved by the grab: %d (one = no falloff; more = proportional)" % g_moved)
	end_goal("3", g_moved > 1, "(vertices moved: %d; wheel used: yes)" % g_moved)

	# 4. SUBDIVIDE: Ctrl+1 first, then the Modifiers panel (Subdivide, Apply)
	begin_goal("4 subdivide the cube (Ctrl+1 or a Subdivision modifier) and apply it")
	var f_pre := nf()
	var v_pre := nv()
	await key_mod(KEY_1, true, false, false, "Ctrl+1")
	await shot("subdiv_ctrl1")
	var ctrl1_did := nf() != f_pre
	say("   after Ctrl+1: verts %d -> %d, faces %d -> %d" % [v_pre, nv(), f_pre, nf()])
	var sub_note := "Ctrl+1 changed the mesh: %s" % str(ctrl1_did)
	if not ctrl1_did and String(m.ui_status.text).contains("added Subdivide"):   # Ctrl+1 put a Subdivide on the stack: the user applies it
		await click_text("Modifiers")
		var f_mod1 := nf()
		await click_text("Apply Subdivide")
		await shot("subdiv_applied")
		sub_note += "; Ctrl+1 added a Subdivide modifier, 'Apply Subdivide' pressed: faces %d -> %d, verts %d -> %d" % [f_mod1, nf(), v_pre, nv()]
	elif not ctrl1_did:
		await click_text("Modifiers")
		var ob4 := find_option(kmed.mods.panel)
		if await pick_option(ob4, "Subdivide"):
			await click_in(kmed.mods.panel, "Add modifier")
			await shot("subdiv_added")
			var f_mod := nf()
			await click_text("Apply Subdivide")
			await shot("subdiv_applied")
			sub_note += "; Subdivide added and Apply pressed: faces %d -> %d, verts %d -> %d" % [f_mod, nf(), v_pre, nv()]
		else:
			sub_note += "; no Subdivide choice in the Modifiers panel"
	end_goal("4", nf() > f_pre, "(%s)" % sub_note)

	# 5. SCULPT: Smooth stroke, Grab stroke, undo both
	begin_goal("5 sculpt: Smooth stroke, Grab stroke, undo both")
	await click_text("SCULPT")
	await click_text("Test sphere")
	await idle_frames_until_mesh()
	ksc = m.ksc
	var sc_ok: bool = ksc != null and ksc.on
	if sc_ok:
		var sp_start: PackedVector3Array = ksc.mesh.verts.duplicate()
		await click_text("Smooth")
		await drag_at(sphere_spot(), Vector2(70, 0), "across the sphere with Smooth")
		await shot("smooth_stroke")
		var d_smooth := max_move(sp_start, ksc.mesh.verts)
		say("   largest move after Smooth on the untouched sphere: %.3f mm" % (d_smooth * 1000.0))
		var sp_smooth: PackedVector3Array = ksc.mesh.verts.duplicate()
		await click_text("Grab")
		await drag_at(sphere_spot(), Vector2(0, -70), "across the sphere with Grab")
		await shot("grab_stroke")
		var d_grab := max_move(sp_smooth, ksc.mesh.verts)
		say("   largest move after Grab: %.3f mm" % (d_grab * 1000.0))
		await key_mod(KEY_Z, true, false, false, "Ctrl+Z (undo the Grab)")
		await shot("sculpt_undo_1")
		var after1 := max_move(sp_smooth, ksc.mesh.verts)
		await key_mod(KEY_Z, true, false, false, "Ctrl+Z (undo the Smooth)")
		await shot("sculpt_undo_2")
		var after2 := max_move(sp_start, ksc.mesh.verts)
		say("   after undo 1: distance from the post-Smooth state %.3f mm; after undo 2: distance from the start %.3f mm" % [after1 * 1000.0, after2 * 1000.0])
		sc_ok = d_smooth > 0.0 and d_grab > 0.0 and after2 < 0.00001
		end_goal("5", sc_ok, "(smooth moved %.3f mm, grab %.3f mm; after two undos back to start: %s)" % [d_smooth * 1000.0, d_grab * 1000.0, str(after2 < 0.00001)])
	else:
		end_goal("5", false, "(the test sphere did not open)")

	# 6. SURFACE: unwrap, then a material on some faces only
	begin_goal("6 surface: unwrap the cube, material on some faces only")
	await click_text("MODEL")
	await click_text("Test cube")
	await idle(6)
	await click_text("SURFACE")
	await shot("surface_page")
	await click_text("Game UVs 2k")
	await shot("uv_unwrapped")
	var uv_ok: bool = kmed != null and kmed.mesh != null and kmed.mesh.has_attr(KMeshUV.UV)
	say("   UVs on the cube: %s" % str(uv_ok))
	await key(KEY_3, false, false, "3 (face mode)")
	var fa := front_face()
	await click_at(face_spot(fa), "on a face")
	var fb := -1
	for fi in kmed.mesh.face_count():
		if fi != fa and face_center(fi).distance_to(face_center(fa)) > 0.05:
			fb = fi
			break
	if fb >= 0:
		await click_mod(face_spot(fb), "on a second face, Shift held", false, true)
	var mats0: int = kmed.mesh.materials.size()
	var mat_btn := ""
	for pre in ["New", "Add", "+", "Make", "Create"]:
		var bb := find_btn(pre, true)
		if bb != null:
			mat_btn = text_of(bb)
			break
	say("   material panel buttons: %s" % str(_mat_btns()))
	if mat_btn != "":
		await click_text(mat_btn)
		await shot("material_made")
	var as_btn := find_btn("Assign")
	if as_btn != null:
		await click_text("Assign")
		await shot("material_assigned")
	else:
		say("   NOT VISIBLE: no Assign button")
	var on_slot := 0
	var slot_counts := KMeshMaterial.counts(kmed.mesh)
	if slot_counts.size() > 1:
		on_slot = nf() - slot_counts[0]   # faces off the default slot 0 (the new slot is last)
	say("   material slots %d -> %d; faces per slot %s; faces off slot 0: %d (of %d faces)" % [mats0, kmed.mesh.materials.size(), str(slot_counts), on_slot, nf()])
	end_goal("6", uv_ok and as_btn != null and on_slot > 0 and on_slot < nf(), "(UVs %s; material slots %d -> %d; faces on slot 1 %d of %d; Assign visible: %s)" % [str(uv_ok), mats0, kmed.mesh.materials.size(), on_slot, nf(), str(as_btn != null)])

	# 7. EXPORT the model
	begin_goal("7 export the model (OBJ / GLB) and find the file")
	var t_exp := Time.get_ticks_msec()
	await click_text("DELIVER")
	await shot("export_page")
	await click_text("Export...")
	await shot("export_dialog")
	say("   visible buttons now: %s" % btn_names())
	var found_fmt := []
	for b in visible_buttons():
		var tt := text_of(b)
		if tt.findn("OBJ") >= 0 or tt.findn("GLB") >= 0 or tt.findn("glTF") >= 0:
			found_fmt.append(tt)
	say("   OBJ / GLB buttons: %s" % str(found_fmt))
	var exp_note := "no OBJ / GLB choice on the Export dialog"
	if not found_fmt.is_empty():
		await click_text(found_fmt[0])
		await shot("export_format")
		exp_note = "picked '%s'" % found_fmt[0]
	if find_btn("Export") != null:
		await click_text("Export")
		await shot("export_done")
	var new_files := export_files_since("res://exports", t_exp)
	say("   new files in res://exports since the click: %s" % str(new_files))
	end_goal("7", not new_files.is_empty(), "(%s; files: %s)" % [exp_note, str(new_files)])

	# 8. BODY MESH: move a vertex, Apply body, POSE shows it
	begin_goal("8 Body mesh: move a vertex, Apply body, POSE shows it")
	await click_text("POSE")
	await shot("pose_before_body")
	await click_text("MODEL")
	await click_text("Body mesh")
	await idle(20)
	await shot("body_mesh_open")
	var bo: bool = kmed != null and kmed.on and kmed.mesh != null and kmed.mesh.vert_count() > 0
	var body_moved := 0
	if bo:
		await key(KEY_1, false, false, "1 (vertex mode)")
		var fb8 := front_face()
		var vb: int = kmed.mesh.faces[fb8][0]
		var vs := scr(kmed.view._to_world(vb))
		var pre8 := mesh_snapshot()
		await click_at(vs, "on a vertex of the body")
		await key(KEY_G, false, false, "G")
		await hover_by(vs, Vector2(0, -30))
		await click_at(vs + Vector2(0, -30), "to confirm the grab")
		body_moved = moved_count(pre8, mesh_snapshot())
		await shot("body_edited")
		await click_text("Apply body")
		await shot("body_applied")
	await click_text("POSE")
	await idle(10)
	await shot("pose_after_body")
	say("   body mesh verts moved: %d | body on screen: %s | body angles unchanged (no pose was changed): %s" % [body_moved, str(body_on_screen()), str(m.B.ang == body0)])
	end_goal("8", bo and body_moved > 0 and body_on_screen(), "(verts moved %d; Apply body pressed; POSE reached, body on screen: %s; posing by hand not tested)" % [body_moved, str(body_on_screen())])

	say("\n| # | Goal | Done | Actions | Notes |")
	say("|---|---|---|---|---|")
	for r in rows:
		say("| %s | %s | %s | %s | %s |" % r)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)


## a click on a button with these words inside one panel (the Modifiers panel's Add, not the Materials panel's)
func click_in(under: Node, txt: String) -> bool:
	for n in walk(under, []):
		if n is Button and (n as Button).is_visible_in_tree() and text_of(n as Button) == txt:
			var c: Vector2 = (n as Button).get_global_rect().get_center()
			clicks += 1
			await hover(c)
			say("   click button '%s' in the panel" % txt)
			btn(true, c)
			await process_frame
			btn(false, c)
			await idle(3)
			return true
	say("   NOT VISIBLE: no '%s' in that panel" % txt)
	return false
