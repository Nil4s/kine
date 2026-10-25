## godot --path . --position 3000,3000 -s tests/walk_model3_test.gd   (WALK-THROUGH 3: EXPERT MODEL / SCULPT / SURFACE, round 3)
## A Blender user's tasks, through the UI only (real clicks, drags and keys): a table from a cube (S Z flat, E four legs down),
## bevel the top rim (Ctrl+B), knife (Shift+K), merge (M) and delete a face (X / Delete), a Mirror on X edited on one side
## and applied, the SURFACE page (unwrap, checker, a second material on some faces), export of the table (OBJ, GLB) and a
## re-import as a prop, and last SCULPT: Inflate and Draw with X symmetry, then Smooth.
## Screenshots go to C:/Temp/claude/walkmodel3/; the log to C:/Temp/claude/walkmodel3/log.txt.
## MEASURES, FIXES NOTHING: a failed goal is logged as failed and the walk goes on. A test runs on its own settings file.
extends SceneTree

const OUT := "C:/Temp/claude/walkmodel3/"

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
var base_n := 0        # vertex count when the table was first edited: extrudes append past it


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
		hm.relative = d / 6.0
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


## a click with modifier keys held (Alt+click picks an edge loop, Shift+click adds to the selection)
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


## a click on a button with these words inside one panel (not another panel's button of the same name)
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


## a real drag from p by d (the mouse down, moved in steps, let go)
func drag_at(p: Vector2, d: Vector2, what: String) -> void:
	clicks += 1
	await hover(p)
	say("   drag %s from %s by %s | under the pointer: %s" % [what, str(p), str(d), hit_name(p)])
	btn(true, p)
	await process_frame
	for i in 6:
		move(p + d * float(i + 1) / 6.0, d / 6.0)
		await process_frame
	btn(false, p + d)
	await idle(3)


## a right-button drag: orbits the camera (right / middle mouse orbit and pan on the model preview)
func orbit_drag(p: Vector2, d: Vector2) -> void:
	clicks += 1
	say("   orbit (right drag) from %s by %s" % [str(p), str(d)])
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)
	await process_frame
	for i in 8:
		var mm := InputEventMouseMotion.new()
		var q := p + d * float(i + 1) / 8.0
		mm.position = q
		mm.global_position = q
		mm.relative = d / 8.0
		mm.button_mask = MOUSE_BUTTON_MASK_RIGHT
		root.push_input(mm)
		await process_frame
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_RIGHT
	u.pressed = false
	u.position = p + d
	u.global_position = p + d
	root.push_input(u)
	await idle(6)


## a key press (down and up), with Ctrl / Shift when asked: the way a real key comes in
func key(k: Key, ctrl := false, shift := false, label := "") -> void:
	keys += 1
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = down
		root.push_input(ev)
		await process_frame
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


# ---- the mesh, as the test sees it (world positions through the view) ----

func nv() -> int:
	return kmed.mesh.vert_count()


func nf() -> int:
	return kmed.mesh.face_count()


func vw(i: int) -> Vector3:
	return kmed.view._to_world(i)


func face_center(fi: int) -> Vector3:
	var f: PackedInt32Array = kmed.mesh.faces[fi]
	var c := Vector3.ZERO
	for vi in f:
		c += vw(vi)
	return c / float(f.size())


func scr(wp: Vector3) -> Vector2:
	return m.cam.unproject_position(wp)


func face_spot(fi: int) -> Vector2:
	return scr(face_center(fi))


func on_screen(p: Vector2) -> bool:
	return m.get_viewport().get_visible_rect().has_point(p)


## the bounding box of the edit mesh in world metres: [min, max]
func bbox() -> Array:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for i in nv():
		var w: Vector3 = vw(i)
		mn = Vector3(minf(mn.x, w.x), minf(mn.y, w.y), minf(mn.z, w.z))
		mx = Vector3(maxf(mx.x, w.x), maxf(mx.y, w.y), maxf(mx.z, w.z))
	return [mn, mx]


## the visible face (facing the camera, on screen) that passes ok(fi, centre); the most camera-facing one
func pick_face(ok: Callable) -> int:
	var best := -1
	var bd := 0.0
	var cam_pos: Vector3 = m.cam.global_position
	for fi in nf():
		var c: Vector3 = face_center(fi)
		if m.cam.is_position_behind(c) or not on_screen(scr(c)):
			continue
		if not ok.call(fi, c):
			continue
		var n: Vector3 = (kmed.view.global_transform.basis * kmed.mesh.face_normals[fi]).normalized()
		var d: float = n.dot((cam_pos - c).normalized())
		if d > bd:
			bd = d
			best = fi
	return best


## the visible vertex that passes ok(i, world position); the nearest to the camera
func pick_vert(ok: Callable) -> int:
	var best := -1
	var bdist := 1e9
	var cam_pos: Vector3 = m.cam.global_position
	for i in nv():
		var w: Vector3 = vw(i)
		if m.cam.is_position_behind(w) or not on_screen(scr(w)):
			continue
		if not ok.call(i, w):
			continue
		var dd: float = cam_pos.distance_to(w)
		if dd < bdist:
			bdist = dd
			best = i
	return best


## the visible edge (a face's corner pair) that passes ok(a, b, midpoint); nearest the camera. [a, b, screen point] or []
func pick_edge(ok: Callable) -> Array:
	var best := []
	var bdist := 1e9
	var cam_pos: Vector3 = m.cam.global_position
	for fi in nf():
		var f: PackedInt32Array = kmed.mesh.faces[fi]
		for i in f.size():
			var a: int = f[i]
			var b: int = f[(i + 1) % f.size()]
			var mid: Vector3 = (vw(a) + vw(b)) * 0.5
			if m.cam.is_position_behind(mid) or not on_screen(scr(mid)):
				continue
			if not ok.call(a, b, mid):
				continue
			var dd: float = cam_pos.distance_to(mid)
			if dd < bdist:
				bdist = dd
				best = [a, b, scr(mid)]
	return best


func counts() -> String:
	return "verts %d, faces %d, selected %d" % [nv(), nf(), kmed.sel.count()]


func mesh_snapshot() -> PackedVector3Array:
	return kmed.mesh.verts.duplicate()


func moved_count(a: PackedVector3Array, b: PackedVector3Array) -> int:
	var n := 0
	for i in mini(a.size(), b.size()):
		if a[i].distance_to(b[i]) > 0.00005:
			n += 1
	return n


## how many vertices have a partner at their x-mirror image (within 1 mm) in the current mesh
func mirror_pairs() -> Array:   # in the mesh's own (local) space: the mirror modifier works on the local verts
	var n := nv()
	var hits := 0
	var pos: Array = []
	for i in n:
		pos.append(kmed.mesh.verts[i])
	for i in n:
		var r := Vector3(-pos[i].x, pos[i].y, pos[i].z)
		for j in n:
			if pos[j].distance_to(r) < 0.001:
				hits += 1
				break
	return [hits, n]


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


func export_files_since(dir: String, t: int) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		var full := dir + "/" + f
		if FileAccess.get_modified_time(full) * 1000 >= t - 2000:
			out.append(full)
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
	await shot("00_start_expert")
	var made_exports: Array = []

	# ---- 1. TABLE: cube, S Z flat, four legs by extrude ----
	begin_goal("1 table: cube -> S Z flat -> select 4 bottom corner faces -> E four legs down")
	await click_text("MODEL")
	await click_text("Test cube")
	await idle(10)
	kmed = m.kmed
	var t1_ok := false
	var t1_note := ""
	if kmed != null and kmed.on:
		await shot("01_cube_open")
		await key(KEY_A, false, false, "A (select all)")
		var h_before: float = bbox()[1].y - bbox()[0].y
		await key(KEY_S, false, false, "S (scale)")
		await key(KEY_Z, false, false, "Z (along Z only)")
		await key(KEY_0, false, false, "0")
		await key(KEY_PERIOD, false, false, ".")
		await key(KEY_4, false, false, "4")
		await key(KEY_ENTER, false, false, "Enter (scale 0.4 on Z)")
		var bb1: Array = bbox()
		say("   height before %.3f m, after S Z 0.4: %.3f m (footprint %.3f x %.3f m)" % [h_before, bb1[1].y - bb1[0].y, bb1[1].x - bb1[0].x, bb1[1].z - bb1[0].z])
		await shot("02_table_flat")
		# the table's underside faces the camera only from below: orbit the view (right drag) so the bottom can be clicked
		await orbit_drag(Vector2(960, 540), Vector2(0, 260))
		await shot("03_orbited_below")
		await key(KEY_3, false, false, "3 (face mode)")
		var bb: Array = bbox()
		var cx: float = (bb[0].x + bb[1].x) * 0.5
		var cz: float = (bb[0].z + bb[1].z) * 0.5
		var hx: float = (bb[1].x - bb[0].x) * 0.5
		var hz: float = (bb[1].z - bb[0].z) * 0.5
		var picked: Array = []
		for k in 4:
			var fc: int = pick_face(func(fi: int, c: Vector3) -> bool:
				return picked.has(fi) == false and c.y < bb[0].y + 0.02 and absf(c.x - cx) > hx * 0.5 and absf(c.z - cz) > hz * 0.5)
			if fc < 0:
				say("   no visible bottom corner face left (picked %d of 4)" % picked.size())
				break
			picked.append(fc)
			await click_mod(face_spot(fc), "bottom corner face %d" % (k + 1), false, k > 0)
		say("   bottom corner faces picked: %s | selected now: %d" % [str(picked), kmed.sel.count()])
		await shot("04_four_corner_faces")
		var v_pre: int = nv()
		var ymin_pre: float = bb[0].y
		if picked.size() > 0:
			await key(KEY_E, false, false, "E (extrude)")
			var sp: Vector2 = face_spot(picked[0])
			await hover_by(sp, Vector2(0, 40))
			await shot("05_extrude_live")
			await click_at(sp + Vector2(0, 40), "to confirm the extrude")
		await shot("06_legs")
		var added: int = nv() - v_pre
		var ymin_now := 1e9
		for i in range(v_pre, nv()):
			ymin_now = minf(ymin_now, vw(i).y)
		say("   verts %d -> %d (new %d); lowest new vert y %.3f m vs floor-side min %.3f m" % [v_pre, nv(), added, ymin_now, ymin_pre])
		base_n = v_pre
		t1_ok = picked.size() == 4 and added > 0 and ymin_now < ymin_pre - 0.01
		t1_note = "(corner faces picked %d of 4; new verts %d; legs go down: %s)" % [picked.size(), added, str(ymin_now < ymin_pre - 0.01)]
	else:
		t1_note = "the test cube did not open"
	end_goal("1", t1_ok, t1_note)

	# ---- 2. BEVEL the top rim (Ctrl+B) ----
	begin_goal("2 bevel the top edges: Ctrl+B")
	var t2_ok := false
	var t2_note := ""
	if kmed != null and kmed.on:
		await key(KEY_2, false, false, "2 (edge mode)")
		var bb2: Array = bbox()
		var cx2: float = (bb2[0].x + bb2[1].x) * 0.5
		var cz2: float = (bb2[0].z + bb2[1].z) * 0.5
		var rim := pick_edge(func(a: int, b: int, mid: Vector3) -> bool:
			return vw(a).y > bb2[1].y - 0.01 and vw(b).y > bb2[1].y - 0.01 and (absf(mid.z - cz2) > (bb2[1].z - bb2[0].z) * 0.4 or absf(mid.x - cx2) > (bb2[1].x - bb2[0].x) * 0.4))
		if rim.size() == 3:
			await click_mod(rim[2], "a top rim edge, Alt held (edge loop)", true)
			await shot("07_rim_loop")
			say("   selected after the loop: %d edges/verts" % kmed.sel.count())
			var f_b: int = nf()
			await key(KEY_B, true, false, "Ctrl+B (bevel)")
			await shot("08_bevel")
			var f_a: int = nf()
			say("   faces %d -> %d after Ctrl+B" % [f_b, f_a])
			t2_ok = f_a > f_b
			t2_note = "(loop selected: %d; faces %d -> %d)" % [kmed.sel.count(), f_b, f_a]
		else:
			t2_note = "no top rim edge on screen"
	else:
		t2_note = "no edit mesh"
	end_goal("2", t2_ok, t2_note)

	# ---- 3. KNIFE (Shift+K) across a face ----
	begin_goal("3 knife: Shift+K, two clicks across a face, Enter")
	var t3_ok := false
	var t3_note := ""
	if kmed != null and kmed.on:
		await key(KEY_3, false, false, "3 (face mode)")
		var kf: int = pick_face(func(fi: int, c: Vector3) -> bool: return true)
		if kf >= 0:
			var c0: Vector2 = face_spot(kf)
			var v_k: int = nv()
			await key(KEY_K, false, true, "Shift+K (knife)")
			await click_at(c0 + Vector2(-60, -25), "knife point 1 on the face")
			await click_at(c0 + Vector2(60, 25), "knife point 2 on the face")
			await shot("09_knife_points")
			await key(KEY_ENTER, false, false, "Enter (cut)")
			await shot("10_knife_cut")
			say("   verts %d -> %d after the knife" % [v_k, nv()])
			t3_ok = nv() > v_k
			t3_note = "(verts %d -> %d)" % [v_k, nv()]
		else:
			t3_note = "no face on screen"
	else:
		t3_note = "no edit mesh"
	end_goal("3", t3_ok, t3_note)

	# ---- 4. MERGE two verts (M), DELETE a face (X, then Delete) ----
	begin_goal("4 merge two vertices (M), delete a face (X)")
	var t4_ok := false
	var t4_note := ""
	if kmed != null and kmed.on:
		await key(KEY_1, false, false, "1 (vertex mode)")
		var fm: int = pick_face(func(fi: int, c: Vector3) -> bool: return true)
		var va: int = kmed.mesh.faces[fm][0]
		var vb: int = kmed.mesh.faces[fm][1]
		await click_at(scr(vw(va)), "vertex A")
		await click_mod(scr(vw(vb)), "vertex B, Shift held", false, true)
		say("   selected: %d" % kmed.sel.count())
		var v_m: int = nv()
		await key(KEY_M, false, false, "M (merge)")
		await shot("11_merged")
		var v_m2: int = nv()
		say("   verts %d -> %d after M" % [v_m, v_m2])
		await key(KEY_3, false, false, "3 (face mode)")
		var fd: int = pick_face(func(fi: int, c: Vector3) -> bool: return true)
		var f_d: int = nf()
		if fd >= 0:
			await click_at(face_spot(fd), "a face to delete")
			await key(KEY_X, false, false, "X (the Blender delete key)")
			say("   after X: x-ray is %s, faces still %d" % [str(kmed.xray), nf()])
			await key(KEY_X, false, false, "X again (back to x-ray off)")
			await key(KEY_DELETE, false, false, "Delete (the selected face)")
			await shot("12_face_deleted")
			say("   faces %d -> %d after Delete" % [f_d, nf()])
			t4_ok = v_m2 == v_m - 1 and nf() < f_d
			t4_note = "(merge verts %d -> %d; delete faces %d -> %d)" % [v_m, v_m2, f_d, nf()]
		else:
			t4_note = "no face on screen to delete"
	else:
		t4_note = "no edit mesh"
	end_goal("4", t4_ok, t4_note)

	# ---- 5. MIRROR on X: edit one side, Apply ----
	begin_goal("5 Mirror on X: add it, edit one side, Apply, both sides real")
	var t5_ok := false
	var t5_note := ""
	if kmed != null and kmed.on:
		await click_text("Modifiers")
		var ob := find_option(kmed.mods.panel)
		if await pick_option(ob, "Mirror"):
			await click_in(kmed.mods.panel, "Add modifier")
			await shot("13_mirror_added")
			await key(KEY_3, false, false, "3 (face mode)")
			var fe: int = pick_face(func(fi: int, c: Vector3) -> bool: return true)
			var vc_before: int = nv()
			if fe >= 0:
				await click_at(face_spot(fe), "a face on the side you edit")
				await key(KEY_E, false, false, "E")
				await hover_by(face_spot(fe), Vector2(0, -50))
				await click_at(face_spot(fe) + Vector2(0, -50), "to confirm the extrude")
			await shot("14_mirror_one_side_edited")
			var pr_before: Array = mirror_pairs()
			await click_in(kmed.mods.panel, "Apply Mirror")
			await shot("15_mirror_applied")
			var pr: Array = mirror_pairs()
			say("   before Apply: %d of %d verts have a mirror partner; after Apply: %d of %d (verts %d -> %d)" % [pr_before[0], pr_before[1], pr[0], pr[1], vc_before, nv()])
			t5_ok = pr[0] == pr[1] and nv() > vc_before
			t5_note = "(after Apply %d of %d verts have a mirror partner; verts %d -> %d; mirror plane at x = 0 m, the table sits at x = 1 m)" % [pr[0], pr[1], vc_before, nv()]
		else:
			t5_note = "no Mirror in the Modifiers drop-down"
	else:
		t5_note = "no edit mesh"
	end_goal("5", t5_ok, t5_note)

	# ---- 6. SURFACE: unwrap, checker, second material on some faces ----
	begin_goal("6 surface: unwrap (U), checker, a second material on some faces")
	var t6_ok := false
	var t6_note := ""
	if kmed != null and kmed.on:
		await click_text("SURFACE")
		await shot("16_surface_page")
		await click_text("UV editor")
		await shot("17_uv_editor")
		var seam_btn := find_btn("Mark seam", true)
		var seam_btn2 := find_btn("Seam", true)
		say("   seam buttons on the SURFACE page: %s" % str([seam_btn != null, seam_btn2 != null]))
		await key(KEY_U, false, false, "U (first press: unwrap)")
		await shot("18_unwrapped")
		await key(KEY_U, false, false, "U (checker)")
		await shot("19_checker")
		var mats0: int = kmed.mesh.materials.size()
		await click_in(kmed.mat_panel, "Add material")
		await click_in(kmed.mat_panel, "Add material")
		await shot("20_two_materials")
		await key(KEY_3, false, false, "3 (face mode)")
		var s_picked: Array = []
		for k in 2:
			var fs: int = pick_face(func(fi: int, c: Vector3) -> bool: return not s_picked.has(fi))
			if fs >= 0:
				s_picked.append(fs)
				await click_mod(face_spot(fs), "face for material 2", false, k > 0)
		var assigned: bool = await click_in(kmed.mat_panel, "Assign")
		await shot("21_material_assigned")
		var slot_counts: PackedInt32Array = KMeshMaterial.counts(kmed.mesh)
		var off0 := 0
		for k in slot_counts.size():
			if k != 0:
				off0 += slot_counts[k]
		say("   material slots %d -> %d; faces per slot %s; faces off slot 0: %d of %d; mat buttons: %s" % [mats0, kmed.mesh.materials.size(), str(slot_counts), off0, nf(), str(_mat_btns())])
		t6_ok = kmed.mesh.materials.size() > mats0 and off0 > 0 and off0 < nf() and assigned
		t6_note = "(faces picked for slot 2: %d; Assign pressed: %s; faces off slot 0: %d of %d; seam tool: %s)" % [s_picked.size(), str(assigned), off0, nf(), str(seam_btn != null or seam_btn2 != null)]
	else:
		t6_note = "no edit mesh"
	end_goal("6", t6_ok, t6_note)

	# ---- 7. EXPORT the table: OBJ and GLB ----
	begin_goal("7 export the table as OBJ and GLB")
	var t7_ok := false
	var t7_note := ""
	var t_exp := Time.get_ticks_msec()
	await click_text("DELIVER")
	await idle(10)
	await shot("22_deliver_page")
	say("   edit mesh still on after DELIVER: %s" % str(kmed != null and kmed.on))
	if await click_text("Export model (GLB / OBJ)"):
		await shot("23_export_dialog")
		var fmt_btns: Array = []
		for b in visible_buttons():
			var tt := text_of(b)
			if tt.findn("OBJ") >= 0 or tt.findn("GLB") >= 0 or tt.findn("glTF") >= 0:
				fmt_btns.append(tt)
		say("   OBJ / GLB buttons: %s" % str(fmt_btns))
		var got := []
		for fmt in ["OBJ", "GLB"]:
			var fb: Button = null
			for b in visible_buttons():
				if text_of(b).findn(fmt) >= 0:
					fb = b
					break
			if fb != null:
				await click_text(text_of(fb))
				await shot("24_export_%s_chosen" % fmt)
				if await click_text("Export"):
					await shot("25_export_%s_done" % fmt)
			else:
				say("   no %s choice in the dialog" % fmt)
		var new_files := export_files_since("res://exports", t_exp)
		say("   new files in res://exports since the click: %s" % str(new_files))
		made_exports = new_files
		t7_ok = not new_files.is_empty()
		t7_note = "(new files: %s; OBJ/GLB choices: %s)" % [str(new_files), str(fmt_btns)]
	else:
		t7_note = "no Export... on DELIVER"
	end_goal("7", t7_ok, t7_note)

	# ---- 8. RE-IMPORT the GLB as a prop (Object library > My models) and check its size ----
	begin_goal("8 re-import the GLB as a prop (Library > My models), check its size")
	var t8_ok := false
	var t8_note := ""
	await click_text("STAGE")
	await shot("26_stage_page")
	var lib := find_btn("Object library", true)
	say("   'Object library' button on STAGE: %s" % str(lib != null))
	if lib != null:
		await click_text("Object library", true)
		await shot("27_library_open")
		if await click_text("My models"):
			await shot("28_my_models")
	t8_note = "(Object library button found: %s; My models opened: see shots 27 / 28; the driver does not drop a file, so the re-import is not proven here)" % str(lib != null)
	end_goal("8", false, t8_note)

	say("\n| # | Goal | Done | Actions | Notes |")
	say("|---|---|---|---|---|")
	for r in rows:
		say("| %s | %s | %s | %s | %s |" % r)
	for p in made_exports:   # the exports this run wrote: removed at the end (the run's own files only)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			say("removed the run's export " + p)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
