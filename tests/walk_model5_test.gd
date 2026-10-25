## godot --path . --position 3000,3000 -s tests/walk_model5_test.gd   (WALK-THROUGH 5: EXPERT MODEL, round 5, a hobbyist who knows some Blender)
## Real keys and clicks only (root.push_input). Goals: 1 chair (loop cut, back rest, four legs), 2 mirror half a shape and apply,
## 3 subdivide then decimate (faces up then down), 4 knife across the front, 5 unwrap + UV editor, 6 delete a face and fill the hole,
## 7 separate a leg and join it back, 8 rename, save the mesh file and reopen it from the file.
## Screenshots to C:/Temp/claude/walkmodel5/ (NN_name.png); the log to C:/Temp/claude/walkmodel5/log.txt.
## MEASURES, FIXES NOTHING: a failed goal is logged as failed and the walk goes on. Runs 1280x720 pinned.
extends SceneTree


const OUT := "C:/Temp/claude/walkmodel5/"

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
	hist[s] = mesh_snapshot()   # the LAST idle at this count: a live tool (E drag) moves the mesh before its step is committed
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
func key(k: Key, ctrl := false, shift := false, label := "", alt := false) -> void:
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


## the face under a screen point, by the view's own ray: -1 when the point is off the mesh
func surface_hit(p: Vector2) -> bool:
	var hit = kmed.view.ray_face(m.cam.project_ray_origin(p), m.cam.project_ray_normal(p))
	return not (hit as Dictionary).is_empty() if hit is Dictionary else false


## true when a panel (a control that takes the mouse) is drawn over this screen spot: a click there would not reach the view
func ui_covers(p: Vector2) -> bool:
	for n in visible_nodes():
		if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE and (n as Control).get_global_rect().has_point(p):
			var r: Rect2 = (n as Control).get_global_rect()
			if r.size.x < 0.9 * m.get_viewport().get_visible_rect().size.x:   # the full-window roots are not panels
				return true
	return false


## diagnostics for goal 3: the cylinder's top-cap faces [in the mesh, behind the camera, off screen, facing away, visible]
func top_cap_report(f3: int, ymax: float) -> Array:
	var n_all := 0
	var n_behind := 0
	var n_off := 0
	var n_away := 0
	var n_vis := 0
	var cam_pos: Vector3 = m.cam.global_position
	for fi in range(f3, nf()):
		var c: Vector3 = face_center(fi)
		if c.y <= ymax - 0.01:
			continue
		n_all += 1
		if m.cam.is_position_behind(c):
			n_behind += 1
			continue
		if not on_screen(scr(c)):
			n_off += 1
			continue
		var n: Vector3 = (kmed.view.global_transform.basis * kmed.mesh.face_normals[fi]).normalized()
		if n.dot((cam_pos - c).normalized()) <= 0.0:
			n_away += 1
			continue
		n_vis += 1
	return [n_all, n_behind, n_off, n_away, n_vis, "cam y %.3f, dist %.2f" % [cam_pos.y, cam_pos.distance_to(vw(0))]]


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


## a fresh test cube: leaves the open one (Esc), then Test cube again (nothing is saved, so every goal starts from the same cube)
func fresh() -> void:
	if kmed != null and kmed.on:
		await key(KEY_ESCAPE, false, false, "Esc (leave the cube)")
	await click_text("MODEL")
	await click_text("Test cube")
	await idle(10)
	kmed = m.kmed


## the F3 search box (Blender's search key), then the words, then Enter runs the first row. false when F3 opened nothing
func sbox(q: String) -> bool:
	await key(KEY_F3, false, false, "F3 (search box)")
	var opened: bool = m.ui_cmd != null and m.ui_cmd.visible
	if not opened:
		say("   F3 did not open the search box")
		return false
	await type_text(q)
	var rws: Array = []
	for c in m.ui_cmd.shown:
		rws.append(String(c["name"]))
	say("   rows for %s: %s" % [q, str(rws.slice(0, 5))])
	await key(KEY_ENTER, false, false, "Enter (runs the first row)")
	return true


## how many faces use the edge a-b (1 = a rim edge of a hole)
func edge_uses(a: int, b: int) -> int:
	var c := 0
	for f in kmed.mesh.faces:
		var n: int = f.size()
		for i in n:
			var p: int = f[i]
			var q: int = f[(i + 1) % n]
			if (p == a and q == b) or (p == b and q == a):
				c += 1
	return c


func boundary_edges() -> int:
	var cnt := {}
	for f in kmed.mesh.faces:
		var n: int = f.size()
		for i in n:
			var a: int = f[i]
			var b: int = f[(i + 1) % n]
			var k := Vector2i(mini(a, b), maxi(a, b))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var c := 0
	for k in cnt:
		if cnt[k] == 1:
			c += 1
	return c


## how many vertices have no mirror partner across x = 0 (local), 1 mm tolerance
func unmatched_mirror() -> int:
	var vs: PackedVector3Array = kmed.mesh.verts
	var bad := 0
	for a in vs:
		var found := false
		for b in vs:
			if absf(a.x + b.x) < 0.001 and absf(a.y - b.y) < 0.001 and absf(a.z - b.z) < 0.001:
				found = true
				break
		if not found:
			bad += 1
	return bad


func _init() -> void:
	get_root().size = Vector2i(1280, 720)   # pinned: the walk reads the same 1280 x 720 screen every run
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if m.easy.on:
		say("   Easy was on at start: clicking Switch to Expert, as a user would")
		await click_text("Switch to Expert")
		await idle(10)
	await shot("00_start_expert")

	# ---- 1. CHAIR ----
	begin_goal("1 chair: loop cut the sides, extrude a back rest up from the top's rear faces, four legs")
	await fresh()
	var t1 := false
	var n1 := ""
	if kmed != null and kmed.on:
		var f0 := nf()
		var bb: Array = bbox()
		var cx: float = (bb[0].x + bb[1].x) * 0.5
		var cz: float = (bb[0].z + bb[1].z) * 0.5
		var hx: float = (bb[1].x - bb[0].x) * 0.5
		var hz: float = (bb[1].z - bb[0].z) * 0.5
		await key(KEY_R, true, false, "Ctrl+R (loop cut)")
		var side: int = pick_face(func(fi: int, c: Vector3) -> bool: return absf(c.x - cx) > hx * 0.8)
		if side >= 0:
			await click_at(face_spot(side), "loop cut on a side")
		var loop_ok := nf() > f0
		await shot("01_loopcut")
		await key(KEY_3, false, false, "3 (face mode)")
		bb = bbox()
		var ytop: float = bb[1].y
		var rear: Array = []
		for k in 2:
			var tf: int = pick_face(func(fi: int, c: Vector3) -> bool: return c.y > ytop - 0.02 and c.z < cz - hz * 0.3 and not rear.has(fi))
			if tf < 0:
				break
			rear.append(tf)
			await click_mod(face_spot(tf), "top rear face %d" % (k + 1), false, k > 0)
		var ymax0 := ytop
		var ymax1 := ytop
		if rear.size() > 0:
			var last_spot: Vector2 = face_spot(rear[rear.size() - 1])
			await key(KEY_E, false, false, "E (extrude the back rest)")
			await hover_by(last_spot, Vector2(0, -50))
			await click_at(last_spot + Vector2(0, -50), "confirm the back rest")
			ymax1 = bbox()[1].y
		var back_ok := rear.size() > 0 and ymax1 > ymax0 + 0.02
		await shot("02_back_rest")
		await orbit_drag(Vector2(960, 540), Vector2(0, 260))
		await key(KEY_3, false, false, "3 (face mode)")
		bb = bbox()
		cx = (bb[0].x + bb[1].x) * 0.5
		cz = (bb[0].z + bb[1].z) * 0.5
		hx = (bb[1].x - bb[0].x) * 0.5
		hz = (bb[1].z - bb[0].z) * 0.5
		var legs: Array = []
		for k in 4:
			var lf: int = pick_face(func(fi: int, c: Vector3) -> bool: return legs.has(fi) == false and c.y < bb[0].y + 0.02 and absf(c.x - cx) > hx * 0.5 and absf(c.z - cz) > hz * 0.5)
			if lf < 0:
				break
			legs.append(lf)
			await click_mod(face_spot(lf), "bottom corner face %d" % (k + 1), false, k > 0)
		var v_pre := nv()
		var ymin_pre: float = bb[0].y
		if legs.size() > 0:
			var sp: Vector2 = face_spot(legs[legs.size() - 1])
			await key(KEY_E, false, false, "E (legs)")
			await hover_by(sp, Vector2(0, 40))
			await click_at(sp + Vector2(0, 40), "confirm the legs")
		var ymin_now := 1e9
		for i in range(v_pre, nv()):
			ymin_now = minf(ymin_now, vw(i).y)
		var legs_ok := legs.size() == 4 and nv() > v_pre and ymin_now < ymin_pre - 0.01
		await shot("03_chair")
		t1 = loop_ok and back_ok and legs_ok
		n1 = "(loop cut %s; back rest up %s (top %.3f -> %.3f); legs picked %d of 4, down %s)" % [str(loop_ok), str(back_ok), ymax0, ymax1, legs.size(), str(legs_ok)]
	end_goal("1", t1, n1)

	# ---- 2. MIRROR: half a shape, Mirror modifier, apply ----
	begin_goal("2 mirror: delete the left half (x-ray box), Mirror modifier, Apply, check symmetry")
	await fresh()
	var t2 := false
	var n2 := ""
	if kmed != null and kmed.on:
		await key(KEY_1, false, false, "1 (vertex mode)")
		await key(KEY_X, false, false, "X (x-ray: the far side too)")
		var bb2: Array = bbox()
		var mid_world := Vector3((bb2[0].x + bb2[1].x) * 0.5, (bb2[0].y + bb2[1].y) * 0.5, (bb2[0].z + bb2[1].z) * 0.5)
		var edge_p := scr(mid_world + Vector3(-0.075, 0, 0))
		var tl := Vector2(1e9, 1e9)
		var br := Vector2(-1e9, -1e9)
		for i in nv():
			var q := scr(vw(i))
			tl = Vector2(minf(tl.x, q.x), minf(tl.y, q.y))
			br = Vector2(maxf(br.x, q.x), maxf(br.y, q.y))
		var p0 := Vector2(tl.x - 30, tl.y - 30)
		var p1 := Vector2(edge_p.x, br.y + 30)
		await key(KEY_B, false, false, "B (box select)")
		await drag_at(p0, p1 - p0, "the left half")
		var n_before := nv()
		await key(KEY_DELETE, false, false, "Del (delete the selection)")
		var left_gone := true
		for i in nv():
			if vw(i).x < mid_world.x - 0.02:
				left_gone = false
		await shot("04_half_left")
		say("   verts %d -> %d; no vertex left of the middle: %s" % [n_before, nv(), str(left_gone)])
		await key(KEY_X, false, false, "X (x-ray off)")
		await click_text("Modifiers")
		await idle(6)
		var picked_mirror: bool = await pick_option(find_option(kmed.mods.panel), "Mirror")
		await click_text("Add modifier")
		await shot("05_mirror_added")
		var applied: bool = await click_text("Apply Mirror", true)
		await idle(6)
		await shot("06_mirror_applied")
		var unm := unmatched_mirror()
		t2 = left_gone and picked_mirror and applied and unm == 0 and nv() > 0
		n2 = "(half deleted %s; Mirror picked %s; Apply %s; verts with no mirror partner %d)" % [str(left_gone), str(picked_mirror), str(applied), unm]
	end_goal("2", t2, n2)

	# ---- 3. SUBDIVIDE then DECIMATE: faces up then down ----
	begin_goal("3 subdivide (Ctrl+1, Apply), then decimate to half: faces up, then down")
	await fresh()
	var t3 := false
	var n3 := ""
	if kmed != null and kmed.on:
		var f_a := nf()
		await key(KEY_1, true, false, "Ctrl+1 (subdivide)")
		await click_text("Modifiers")
		await idle(6)
		var applied3: bool = await click_text("Apply Subdivide", true)
		await idle(10)
		var f_b := nf()
		await shot("07_subdivided")
		var dec: bool = await sbox("decimate to half")
		await idle(12)
		var f_c := nf()
		await shot("08_decimated")
		t3 = applied3 and f_b > f_a and f_c < f_b and dec
		n3 = "(faces %d -> %d -> %d; apply %s; decimate ran %s)" % [f_a, f_b, f_c, str(applied3), str(dec)]
	end_goal("3", t3, n3)

	# ---- 4. KNIFE: cut the front face in two ----
	begin_goal("4 knife: Shift+K, two clicks across the front face, Enter")
	await fresh()
	var t4 := false
	var n4 := ""
	if kmed != null and kmed.on:
		var bb4: Array = bbox()
		var fy: float = (bb4[0].y + bb4[1].y) * 0.5
		var fz: float = bb4[1].z
		var fx0: float = bb4[0].x
		var fx1: float = bb4[1].x
		var front: int = pick_face(func(fi: int, c: Vector3) -> bool: return absf(c.z - fz) < 0.02)
		var f_k0 := nf()
		if front >= 0:
			# the two points: spots on the front face that no panel covers (the Materials panel sits over the right edge)
			var spots: Array = []
			for fr in [0.25, 0.5, 0.75, 0.15]:
				var q := scr(Vector3(lerpf(fx0, fx1, fr), fy, fz))
				if not ui_covers(q) and on_screen(q):
					spots.append(q)
			var a: Vector2 = spots[0] if spots.size() >= 1 else scr(Vector3(fx0 + 0.02, fy, fz))
			var b: Vector2 = spots[1] if spots.size() >= 2 else scr(Vector3(fx1 - 0.02, fy + 0.05, fz))
			await key(KEY_K, false, true, "Shift+K (knife)")
			await hover(a)
			await click_at(a, "knife start, left edge of the front")
			await hover(b)
			await click_at(b, "knife end, right edge of the front")
			await key(KEY_ENTER, false, false, "Enter (confirm the cut)")
		else:
			say("   no visible front face")
		await shot("09_knife")
		var f_k1 := nf()
		t4 = front >= 0 and f_k1 > f_k0
		n4 = "(faces %d -> %d; status '%s')" % [f_k0, f_k1, str(m.ui_status.text)]
	end_goal("4", t4, n4)

	# ---- 5. UV: unwrap, UV editor, see the islands ----
	begin_goal("5 UV: unwrap the cube (U), open the UV editor (Shift+U), see the islands")
	await fresh()
	var t5 := false
	var n5 := ""
	if kmed != null and kmed.on:
		await key(KEY_U, false, false, "U (first press unwraps)")
		await key(KEY_U, false, false, "U (checker)")
		await key(KEY_U, false, true, "Shift+U (UV editor)")
		await idle(12)
		await shot("10_uv_editor")
		var has_uv: bool = kmed.mesh.has_attr(KMeshUV.UV)
		var uved_on: bool = kmed.uved != null
		t5 = has_uv and uved_on
		n5 = "(UV attr %s; UV editor panel built %s; status '%s')" % [str(has_uv), str(uved_on), str(m.ui_status.text)]
	end_goal("5", t5, n5)

	# ---- 6. DELETE a face, FILL the hole ----
	begin_goal("6 delete a face, then fill the hole (edge mode: Alt+click the rim, Alt+F)")
	await fresh()
	var t6 := false
	var n6 := ""
	if kmed != null and kmed.on:
		var f6 := nf()
		var b6 := boundary_edges()
		await key(KEY_3, false, false, "3 (face mode)")
		var fd: int = pick_face(func(fi: int, c: Vector3) -> bool: return true)
		if fd >= 0:
			await click_mod(face_spot(fd), "a visible face", false, false)
			await key(KEY_DELETE, false, false, "Del (delete the face)")
		var f6a := nf()
		var hole_open := boundary_edges()
		await key(KEY_2, false, false, "2 (edge mode)")
		var e6: Array = pick_edge(func(a: int, b: int, _mid: Vector3) -> bool: return edge_uses(a, b) == 1)
		if not e6.is_empty():
			await click_mod(e6[2], "a rim edge of the hole", true, false)
		await key(KEY_F, false, false, "Alt+F (fill the holes touching the selection)", true)
		await shot("11_hole_filled")
		var f6b := nf()
		t6 = fd >= 0 and hole_open > b6 and f6b == f6 and boundary_edges() == 0
		n6 = "(faces %d -> after delete %d -> after fill %d; open edges %d -> %d -> %d; rim edge picked %s)" % [f6, f6a, f6b, b6, hole_open, boundary_edges(), str(not e6.is_empty())]
	end_goal("6", t6, n6)

	# ---- 7. SEPARATE one part, JOIN it back ----
	begin_goal("7 separate one part, then join the parts back (search box: separate / join)")
	await fresh()
	var t7 := false
	var n7 := ""
	if kmed != null and kmed.on:
		await key(KEY_3, false, false, "3 (face mode)")
		var sf: int = pick_face(func(fi: int, c: Vector3) -> bool: return c.y < bbox()[0].y + 0.1)
		if sf >= 0:
			await click_mod(face_spot(sf), "a bottom face", false, false)
		var sep: bool = await sbox("separate the selection")
		await idle(6)
		var sep_st := str(m.ui_status.text)
		await shot("12_separated")
		await key(KEY_A, false, false, "A (select all)")
		var jn: bool = await sbox("join parts")
		await idle(6)
		var join_st := str(m.ui_status.text)
		await shot("13_joined")
		t7 = sep and jn and sep_st.findn("separ") >= 0 and join_st.findn("join") >= 0
		n7 = "(separate ran %s: '%s'; join ran %s: '%s')" % [str(sep), sep_st, str(jn), join_st]
	end_goal("7", t7, n7)

	# ---- 8. RENAME, SAVE the mesh file, REOPEN it ----
	begin_goal("8 rename the object, save the mesh file, reopen it from the file")
	await fresh()
	var t8 := false
	var n8 := ""
	if kmed != null and kmed.on:
		await key(KEY_F2, false, false, "F2 (rename, Blender's key)")
		var rename_box := false
		for n in visible_nodes():
			if n is LineEdit:
				rename_box = true
		say("   a text box opened by F2: %s" % str(rename_box))
		if rename_box:
			await type_text("walk5 chair")
			await key(KEY_ENTER, false, false, "Enter (keeps the name)")
		var saved: bool = await sbox("save mesh")
		await idle(10)
		var save_st := str(m.ui_status.text)
		await shot("14_saved")
		var reopened: bool = await sbox("open mesh")
		await idle(10)
		var open_st := str(m.ui_status.text)
		await shot("15_reopened")
		t8 = rename_box and saved and reopened and save_st.findn("saved") >= 0
		n8 = "(F2 box %s; save ran %s: '%s'; open ran %s: '%s')" % [str(rename_box), str(saved), save_st, str(reopened), open_st]
	end_goal("8", t8, n8)

	say("\n| # | Goal | Done | Actions | Notes |")
	say("|---|---|---|---|---|")
	for r in rows:
		say("| %s | %s | %s | %s | %s |" % r)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
