## godot --path . --position 3000,3000 -s tests/walk_model4_test.gd   (WALK-THROUGH 4: EXPERT MODEL / SCULPT / SURFACE, round 4)
## A hobbyist who knows a little Blender, using the Expert pages for the first time, with REAL clicks and keys only.
## 1 table (cube, S Z flat, E four legs), 2 bevel the top rim (Alt-click loop, Ctrl+B), 3 mug (Shift+A cylinder, inset the
## top, extrude it down, extrude a side out as a handle), 4 sculpt (Smooth one side of the sphere, Inflate a bump),
## 5 vertex paint (SURFACE, or the S box) and a material from the library, 6 undo 5 and redo 2 (the mesh is checked against
## the state recorded after each step), 7 export the table and use it as a prop on STAGE, 8 find a tool by typing its name
## into the S box. Screenshots go to C:/Temp/claude/walkmodel4/ (NN_name.png); the log to C:/Temp/claude/walkmodel4/log.txt.
## MEASURES, FIXES NOTHING: a failed goal is logged as failed and the walk goes on. A test runs on its own settings file.
extends SceneTree

const OUT := "C:/Temp/claude/walkmodel4/"

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
var _cp_obj = null     # the undo object the checkpoints belong to
var _cp_last := -1
var hist := {}         # undo step count -> the mesh vertices right after that step (set when the count grows)


func say(s: String) -> void:
	print(s)
	lines.append(s)


## every idle also records the undo history: a step's mesh is kept when the step count grows (goal 6 checks against it)
func idle(n := 4) -> void:
	checkpoint()
	for i in n:
		await process_frame


func checkpoint() -> void:
	if kmed == null or kmed.undo == null:
		return
	if kmed.undo != _cp_obj:
		_cp_obj = kmed.undo
		_cp_last = -1
		hist = {}
	var s: int = kmed.undo.steps.size()
	if s > _cp_last:
		hist[s] = mesh_snapshot()
	_cp_last = s


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


func label_visible(txt: String) -> bool:
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() == txt:
			return true
	return false


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
	if under == null:
		say("   NOT VISIBLE: no panel for '%s'" % txt)
		return false
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


## typed letters (the S box's search line takes them as text): one key down / up per character, with its unicode
func type_text(s: String) -> void:
	for c in s:
		keys += 1
		var code: int = c.to_upper().unicode_at(0)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code as Key
			ev.physical_keycode = code as Key
			ev.unicode = c.unicode_at(0)
			ev.pressed = down
			root.push_input(ev)
			await process_frame
	await idle(4)
	say("   typed '%s'" % s)


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
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	say("== END %s: done=%s clicks=%d keys=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, keys, secs, note])
	rows.append([num, goal, "yes" if ok else "NO", "%d clicks, %d keys, %.0f s" % [clicks, keys, secs], note])


func option_items(ob: OptionButton) -> Array:
	var out := []
	for i in ob.item_count:
		out.append(ob.get_item_text(i))
	return out


func find_option(under: Node) -> OptionButton:
	if under == null:
		return null
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


## painted corners: the vertex-colour channel's entries that are not white (the paint writes them)
func painted_count() -> int:
	var n := 0
	for k in kmed.mesh.attrs:
		var d = kmed.mesh.attrs[k].get("data")
		if d is PackedColorArray:
			for c in d:
				if not (c as Color).is_equal_approx(Color(1, 1, 1, 1)):
					n += 1
	return n


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
		say("   height before %.3f m, after S Z 0.4: %.3f m" % [h_before, bb1[1].y - bb1[0].y])
		await shot("02_table_flat")
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
			# the user's own route: the mouse stays where the last face was clicked, E is pressed there, and the hand
			# moves 40 px down the screen (the drag's start point is the pointer's; the old walk jumped it to face 1)
			var last_spot: Vector2 = face_spot(picked[picked.size() - 1])
			await key(KEY_E, false, false, "E (extrude)")
			await hover_by(last_spot, Vector2(0, 40))
			await shot("05_extrude_live")
			await click_at(last_spot + Vector2(0, 40), "to confirm the extrude")
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

	# ---- 2. BEVEL the table top's edges: Alt-click the top rim loop, Ctrl+B ----
	begin_goal("2 bevel the table top's edges: Alt-click the rim loop, Ctrl+B")
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
			say("   selected after the loop: %d" % kmed.sel.count())
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

	# ---- 3. MUG: Shift+A cylinder, inset its top, extrude the inset down (hollow), extrude a side out (handle) ----
	begin_goal("3 mug: Shift+A cylinder, inset the top, extrude it down, extrude a side out as a handle")
	var t3_ok := false
	var t3_note := ""
	if kmed != null and kmed.on:
		var v3: int = nv()
		var f3: int = nf()
		await key(KEY_A, false, true, "Shift+A (add primitive)")
		await shot("09_prim_panel")
		var ob3 := find_option(kmed.prim_panel)
		var cyl := ""
		if ob3 != null:
			for i in ob3.item_count:
				if ob3.get_item_text(i).findn("ylind") >= 0:
					cyl = ob3.get_item_text(i)
		var got_cyl: bool = cyl != "" and await pick_option(ob3, cyl)
		await click_in(kmed.prim_panel, "Add")
		await shot("10_cylinder_added")
		var ymax := -1e9
		var ymin := 1e9
		for i in range(v3, nv()):
			ymax = maxf(ymax, vw(i).y)
			ymin = minf(ymin, vw(i).y)
		var mug_on: bool = nv() > v3 and on_screen(scr((vw(v3) + vw(nv() - 1)) * 0.5))
		say("   cylinder verts %d-%d (y %.3f..%.3f m); its middle on screen: %s" % [v3, nv() - 1, ymin, ymax, str(mug_on)])
		var top_fi: int = pick_face(func(fi: int, c: Vector3) -> bool: return fi >= f3 and c.y > ymax - 0.01)
		if top_fi >= 0 and got_cyl:
			var tsp: Vector2 = face_spot(top_fi)
			await click_at(tsp, "the cylinder's top face")
			await key(KEY_I, false, false, "I (inset)")
			await hover_by(tsp, Vector2(30, 0))
			await click_at(tsp + Vector2(30, 0), "to confirm the inset")
			await shot("11_inset_top")
			var inner: int = pick_face(func(fi: int, c: Vector3) -> bool: return fi >= f3 and c.y > ymax - 0.01 and c.distance_to(face_center(top_fi)) < 0.2)
			var v_ins: int = nv()
			if inner >= 0:
				await click_at(face_spot(inner), "the inset (inner) top face")
				await key(KEY_E, false, false, "E (extrude the inner face down: hollow)")
				await hover_by(face_spot(inner), Vector2(0, 60))
				await click_at(face_spot(inner) + Vector2(0, 60), "to confirm the extrude")
			await shot("12_hollow")
			say("   after the hollow: verts %d -> %d" % [v_ins, nv()])
			var side: int = pick_face(func(fi: int, c: Vector3) -> bool:
				return fi >= f3 and c.y < ymax - 0.1 and c.y > ymin + 0.1 and absf(kmed.mesh.face_normals[fi].y) < 0.3)
			var f_h: int = nf()
			if side >= 0:
				await click_at(face_spot(side), "a side face of the mug")
				await key(KEY_E, false, false, "E (extrude the side: the handle)")
				await hover_by(face_spot(side), Vector2(70, 0))
				await click_at(face_spot(side) + Vector2(70, 0), "to confirm the handle")
			await shot("13_handle")
			say("   faces %d -> %d after the handle" % [f_h, nf()])
			t3_ok = got_cyl and nv() > v3 and v_ins > v3 and nf() > f_h
			t3_note = "(cylinder %s; inset+hollow verts %d -> %d; handle faces %d -> %d; mug on screen: %s)" % [str(got_cyl), v3, nv(), f_h, nf(), str(mug_on)]
		else:
			t3_note = "cylinder %s; no top face of the cylinder on screen" % str(got_cyl)
	else:
		t3_note = "no edit mesh"
	end_goal("3", t3_ok, t3_note)

	# ---- 4. SCULPT: Smooth one side of a sphere, then Inflate a bump ----
	begin_goal("4 sculpt: Smooth one side of a sphere, then Inflate a bump")
	var t4_ok := false
	var t4_note := ""
	await click_text("SCULPT")
	await idle(6)
	await click_text("Test sphere")
	await idle(10)
	ksc = m.ksc
	if ksc != null and ksc.on:
		await shot("14_sphere_open")
		var sc0: PackedVector3Array = ksc.mesh.verts.duplicate()
		await click_text("Smooth")
		var sp4: Vector2 = sphere_spot()
		await drag_at(sp4 + Vector2(-70, 0), Vector2(50, 0), "over the left side with Smooth")
		await shot("15_smoothed")
		var n_sm := moved_count(sc0, ksc.mesh.verts)
		var sc1: PackedVector3Array = ksc.mesh.verts.duplicate()
		await click_text("Inflate")
		var sp5: Vector2 = sphere_spot()
		await drag_at(sp5 + Vector2(20, -10), Vector2(0, -50), "over one spot with Inflate (a bump)")
		await shot("16_bump")
		var n_inf := moved_count(sc1, ksc.mesh.verts)
		t4_ok = n_inf >= 3
		t4_note = "(verts moved: Smooth %d, Inflate %d; Smooth on a plain sphere moves few verts, read the numbers)" % [n_sm, n_inf]
	else:
		t4_note = "(the test sphere did not open)"
	end_goal("4", t4_ok, t4_note)

	# ---- 5. PAINT the mug a colour (SURFACE, or the S box), then a material from the library ----
	begin_goal("5 paint the mug a colour (SURFACE, or the S box), then a material from the library")
	var t5_ok := false
	var t5_note := ""
	if kmed != null and kmed.on:
		await click_text("SURFACE")
		await shot("17_surface_page")
		var paint_here: bool = find_btn("Vertex paint", true) != null or find_btn("Paint", true) != null
		say("   a paint button on SURFACE: %s" % str(paint_here))
		if not paint_here:
			say("   no paint button on SURFACE: opening the S box and typing 'vertex paint'")
			await key(KEY_S, false, false, "S (the S box)")
			await type_text("vertex paint")
			await shot("18_s_box_paint")
			await key(KEY_ENTER, false, false, "Enter (the first row)")
		await shot("19_paint_on")
		var pv0 := painted_count()
		var mug_fi: int = pick_face(func(fi: int, c: Vector3) -> bool: return fi >= base_n and c.y > 0.0)
		if mug_fi < 0:
			mug_fi = pick_face(func(fi: int, c: Vector3) -> bool: return true)
		var pp: Vector2 = face_spot(mug_fi) if mug_fi >= 0 else Vector2(960, 540)
		await drag_at(pp + Vector2(-60, 0), Vector2(120, 0), "across the mug with the paint brush")
		await shot("20_painted")
		var pv1 := painted_count()
		say("   painted corners %d -> %d (paint panel shown: %s)" % [pv0, pv1, str(label_visible("Vertex paint"))])
		var mat0 := str(kmed.mesh.materials[0]) if kmed.mesh.materials.size() > 0 else "none"
		var lib_ok: bool = await click_in(kmed.mat_panel, "Library...")
		await shot("21_library_open")
		var pick_name := ""
		if lib_ok and kmed.mat_panel.lib_panel != null:
			for b in visible_buttons():
				var bt := text_of(b)
				if bt != "" and not ["x", "Apply", "Library...", "Save current slot to library"].has(bt) and kmed.mat_panel.lib_panel.is_ancestor_of(b):
					pick_name = bt
					break
		if pick_name != "":
			await click_text(pick_name)
			await click_in(kmed.mat_panel.lib_panel, "Apply")
		await shot("22_material_applied")
		var mat1 := str(kmed.mesh.materials[0]) if kmed.mesh.materials.size() > 0 else "none"
		say("   library: opened %s, picked '%s'; slot 0 material changed: %s" % [str(lib_ok), pick_name, str(mat0 != mat1)])
		t5_ok = pv1 > pv0 and lib_ok and pick_name != "" and mat0 != mat1
		t5_note = "(painted corners %d -> %d; library opened %s; picked '%s'; material changed %s)" % [pv0, pv1, str(lib_ok), pick_name, str(mat0 != mat1)]
	else:
		t5_note = "no edit mesh"
	end_goal("5", t5_ok, t5_note)

	# ---- 6. UNDO 5 steps, REDO 2: the mesh must equal the recorded state at each point ----
	begin_goal("6 undo 5 steps (Ctrl+Z), redo 2 (Ctrl+Y); the mesh equals what it was then")
	var t6_ok := false
	var t6_note := ""
	if kmed != null and kmed.on:
		checkpoint()
		var top: int = kmed.undo.steps.size()
		var want5 = hist.get(top - 5)
		var want3 = hist.get(top - 3)
		say("   undo steps now: %d (recorded state counts: %s)" % [top, str(hist.keys())])
		for i in 5:
			await key(KEY_Z, true, false, "Ctrl+Z (undo %d)" % (i + 1))
		await shot("23_undone_5")
		var ok5: bool = want5 != null and kmed.undo.steps.size() == top - 5 and mesh_snapshot() == want5
		say("   after 5 undos: steps %d (want %d), mesh equals the recorded state: %s" % [kmed.undo.steps.size(), top - 5, str(ok5)])
		for i in 2:
			await key(KEY_Y, true, false, "Ctrl+Y (redo %d)" % (i + 1))
		await shot("24_redone_2")
		var ok2: bool = want3 != null and kmed.undo.steps.size() == top - 3 and mesh_snapshot() == want3
		say("   after 2 redos: steps %d (want %d), mesh equals the recorded state: %s" % [kmed.undo.steps.size(), top - 3, str(ok2)])
		t6_ok = ok5 and ok2
		t6_note = "(steps %d; after undo 5: %s; after redo 2: %s; recorded states present: %s / %s)" % [top, str(ok5), str(ok2), str(want5 != null), str(want3 != null)]
	else:
		t6_note = "no edit mesh"
	end_goal("6", t6_ok, t6_note)

	# ---- 7. EXPORT the table (OBJ, GLB) and use it as a prop on STAGE ----
	begin_goal("7 export the table (OBJ, GLB), use it as a prop, find it in STAGE > Library > My models")
	var t7_ok := false
	var t7_note := ""
	var t_exp := Time.get_ticks_msec()
	await click_text("DELIVER")
	await idle(10)
	await shot("25_deliver_page")
	var got_export: bool = await click_text("Export model (GLB / OBJ)")
	if got_export:
		await shot("26_export_dialog")
		var fmt_btns: Array = []
		for b in visible_buttons():
			var tt := text_of(b)
			if tt.findn("OBJ") >= 0 or tt.findn("GLB") >= 0 or tt.findn("glTF") >= 0:
				fmt_btns.append(tt)
		say("   OBJ / GLB buttons: %s" % str(fmt_btns))
		for fmt in ["OBJ", "GLB"]:
			var fb: Button = null
			for b in visible_buttons():
				if text_of(b).findn(fmt) >= 0:
					fb = b
					break
			if fb != null:
				await click_text(text_of(fb))
				if await click_text("Export"):
					await shot("27_export_%s" % fmt)
			else:
				say("   no %s choice in the dialog" % fmt)
	made_exports = export_files_since("res://exports", t_exp)
	say("   new files in res://exports since the click: %s" % str(made_exports))
	await click_text("DELIVER")
	await idle(6)
	var used: bool = await click_text("Use as a prop")
	await idle(12)
	await shot("28_use_as_prop")
	say("   status after 'Use as a prop': %s" % str(m.ui_status.text))
	await click_text("STAGE")
	await idle(6)
	var lib := find_btn("Library")
	say("   'Library' button on STAGE: %s" % str(lib != null))
	if lib != null and await click_text("Library"):
		await shot("29_library_open")
		if await click_text("My models", true):
			await shot("30_my_models")
	var kind := "my test_cube"
	var in_reg: bool = used and Props.has_kind(kind)
	if in_reg:
		var kd: Dictionary = Props.kind_of(kind)
		Props.EXTRA.erase(kind)
		say("   prop registered: %s" % str(kd.get("label", "")))
	t7_ok = got_export and not made_exports.is_empty() and in_reg
	t7_note = "(export pressed %s; new files %s; Use as a prop pressed %s; prop registered %s; note: the edit mesh holds the table AND the mug, so the export has both)" % [str(got_export), str(made_exports), str(used), str(in_reg)]
	end_goal("7", t7_ok, t7_note)

	# ---- 8. FIND a tool by typing its name into the S box ----
	begin_goal("8 find a tool by its name: S box, type 'inset', Enter")
	var t8_ok := false
	var t8_note := ""
	await key(KEY_S, false, false, "S (the S box)")
	await shot("31_s_box_open")
	var box_open: bool = m.ui_cmd != null and m.ui_cmd.visible
	await type_text("inset")
	await shot("32_s_box_inset")
	var row_hit := false
	if box_open:
		for n in walk(m.ui_cmd, []):
			if n is Label and (n as Label).text.findn("nset") >= 0 and (n as Label).is_visible_in_tree():
				row_hit = true
	var st0 := str(m.ui_status.text)
	await key(KEY_ENTER, false, false, "Enter (runs the first row)")
	await shot("33_s_box_ran")
	var closed: bool = m.ui_cmd == null or not m.ui_cmd.visible
	say("   box open %s; a row names Inset %s; closed after Enter %s; status before '%s' after '%s'" % [str(box_open), str(row_hit), str(closed), st0, str(m.ui_status.text)])
	t8_ok = box_open and row_hit and closed
	t8_note = "(box opened %s; a row named Inset %s; closed after Enter %s)" % [str(box_open), str(row_hit), str(closed)]
	end_goal("8", t8_ok, t8_note)

	say("\n| # | Goal | Done | Actions | Notes |")
	say("|---|---|---|---|---|")
	for r in rows:
		say("| %s | %s | %s | %s | %s |" % r)
	for p in made_exports:   # the exports this run wrote into res://exports: removed (the run's own files, inside the worktree)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			say("removed the run's export " + p)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
