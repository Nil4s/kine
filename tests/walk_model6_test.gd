## godot --path . --position 3000,3000 -s tests/walk_model6_test.gd   (WALK-THROUGH 6: EXPERT MODEL, a hobbyist who knows some Blender)
## Real keys and clicks only (root.push_input). One table built in order: 1 flatten + four legs, 2 bevel the top's front rim,
## 3 wood material from the library, 4 a cylinder from Add primitive moved onto the table, 5 undo x3 + redo x3 (exact),
## 6 the table as a prop: save, MODEL page Use in scene (one undo step), the POSE page shows it, listed under Add prop.
## Screenshots to C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/wm6_NN_name.png; the log to ..../scratchpad/wm6_log.txt.
## MEASURES, FIXES NOTHING: a failed goal is logged as failed and the walk goes on. Runs 1280x720 pinned. Exits 0.
extends SceneTree


const OUT := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/wm6_"

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




func num_str(v: float) -> String:
	return "%s%.3f" % ["-" if v < 0.0 else "", absf(v)]


## the mesh's box in world metres: the bottom and top (y0 / y1), the x and z centre (cx / cz) and half sizes (hx / hz)
func box_info() -> Dictionary:
	var bb: Array = bbox()
	return {"y0": bb[0].y, "y1": bb[1].y, "x0": bb[0].x, "x1": bb[1].x, "z0": bb[0].z, "z1": bb[1].z,
		"cx": (bb[0].x + bb[1].x) * 0.5, "cz": (bb[0].z + bb[1].z) * 0.5,
		"hx": (bb[1].x - bb[0].x) * 0.5, "hz": (bb[1].z - bb[0].z) * 0.5}


## the vertices from index a on: their box in world metres [min, max] (the parts appended by an add or an extrude)
func box_from(a: int) -> Array:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for i in range(a, nv()):
		var w: Vector3 = vw(i)
		mn = mn.min(w)
		mx = mx.max(w)
	return [mn, mx]


func tree_has(it: TreeItem, s: String) -> bool:
	if it == null:
		return false
	if it.get_text(0).findn(s) >= 0:
		return true
	var c := it.get_first_child()
	while c != null:
		if tree_has(c, s):
			return true
		c = c.get_next()
	return false


## any visible text (label, button, list row, tree row) that holds s
func any_visible_text_has(s: String) -> bool:
	for n in visible_nodes():
		if n is Label and (n as Label).text.findn(s) >= 0:
			return true
		if n is Button and text_of(n as Button).findn(s) >= 0:
			return true
		if n is ItemList:
			for i in (n as ItemList).item_count:
				if (n as ItemList).get_item_text(i).findn(s) >= 0:
					return true
		if n is Tree and tree_has((n as Tree).get_root(), s):
			return true
	return false


func trace(tag: String) -> void:
	say("   [trace] %s: verts %d, faces %d, selected %d" % [tag, nv(), nf(), kmed.sel.count()])


## a click on an item of a visible popup menu with these words (a ribbon group like ADD opens one)
func click_menu(txt: String) -> bool:
	for n in visible_nodes():
		if n is PopupMenu:
			var pm: PopupMenu = n
			for i in pm.item_count:
				if pm.get_item_text(i) == txt:
					var r := Rect2(Vector2(pm.position), Vector2(pm.size))
					var ih: float = r.size.y / float(maxi(pm.item_count, 1))
					var p := Vector2(r.position.x + r.size.x * 0.5, r.position.y + (i + 0.5) * ih)
					clicks += 1
					await hover(p)
					say("   click menu item '%s' at %s | under the pointer: %s" % [txt, str(p), hit_name(p)])
					btn(true, p)
					await process_frame
					btn(false, p)
					await idle(6)
					return true
	say("   NOT VISIBLE: no menu item reads '%s'" % txt)
	return false


## a click on a visible label with these words (the ADD menu's rows are labels in a panel)
func click_label(txt: String) -> bool:
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() == txt:
			var c: Vector2 = (n as Label).get_global_rect().get_center()
			clicks += 1
			await hover(c)
			say("   click the label '%s' at %s | under the pointer: %s" % [txt, str(c), hit_name(c)])
			btn(true, c)
			await process_frame
			btn(false, c)
			await idle(6)
			return true
	say("   NOT VISIBLE: no label reads '%s'" % txt)
	return false


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

	# ---- 1. TABLE: flatten the cube, four legs (the goals run one after another on the same table) ----
	begin_goal("1 table: flatten the cube (A, S, Y, 0.3), then four legs (4 bottom corner faces, E, 0.3 m down)")
	await fresh()
	var t1 := false
	var n1 := ""
	var ytop := 0.0
	if kmed != null and kmed.on:
		var h0: float = bbox()[1].y - bbox()[0].y
		await key(KEY_A, false, false, "A (select all)")
		await key(KEY_S, false, false, "S (scale the selection)")
		await key(KEY_Y, false, false, "Y (the axis: Kine's up is Y; Blender's Z is depth here)")
		await type_text("0.3")
		await key(KEY_ENTER, false, false, "Enter (keeps the scale)")
		var bi: Dictionary = box_info()
		var h1: float = bi.y1 - bi.y0
		var flat_ok := h1 < h0 * 0.4 and h1 > 0.05
		say("   height %.3f -> %.3f m" % [h0, h1])
		ytop = bi.y1
		await key(KEY_3, false, false, "3 (face mode)")
		await orbit_drag(Vector2(960, 540), Vector2(0, 260))
		bi = box_info()
		var legs: Array = []
		for k in 4:
			var lf: int = pick_face(func(fi: int, c: Vector3) -> bool: return not legs.has(fi) and c.y < bi.y0 + 0.02 and absf(c.x - bi.cx) > bi.hx * 0.5 and absf(c.z - bi.cz) > bi.hz * 0.5)
			if lf < 0:
				break
			legs.append(lf)
			await click_mod(face_spot(lf), "bottom corner face %d" % (k + 1), false, k > 0)
		var v_pre := nv()
		if legs.size() > 0:
			await key(KEY_E, false, false, "E (extrude the picked faces)")
			await type_text("0.3")
			await key(KEY_ENTER, false, false, "Enter (0.3 m, straight down)")
		var lo_leg := 1e9
		for i in range(v_pre, nv()):
			lo_leg = minf(lo_leg, vw(i).y)
		var legs_ok := legs.size() == 4 and nv() > v_pre and lo_leg < ytop - 0.30
		say("   legs: %d faces picked, verts %d -> %d, lowest leg vertex y %.3f (top %.3f: %.3f m below the top)" % [legs.size(), v_pre, nv(), lo_leg, ytop, ytop - lo_leg])
		await shot("01_table_legs")
		t1 = flat_ok and legs_ok
		n1 = "(flattened %s, height %.3f -> %.3f; four legs %s, lowest %.3f m below the top)" % [str(flat_ok), h0, h1, str(legs_ok), ytop - lo_leg]
	end_goal("1", t1, n1)

	# ---- 2. BEVEL the top's front rim ----
	begin_goal("2 bevel: the table top's front rim (edge mode, Alt+click the edge loop), then the Bevel button")
	var t2 := false
	var n2 := ""
	if kmed != null and kmed.on:
		await key(KEY_2, false, false, "2 (edge mode)")
		await orbit_drag(Vector2(960, 540), Vector2(0, -260))
		var bi2: Dictionary = box_info()
		var yt: float = bi2.y1
		var zf: float = bi2.z1
		var e2: Array = pick_edge(func(a: int, b: int, mid: Vector3) -> bool: return absf(mid.z - zf) < 0.02 and absf(vw(a).y - yt) < 0.005 and absf(vw(b).y - yt) < 0.005)
		var nv2 := nv()
		if not e2.is_empty():
			await click_mod(e2[2], "front top rim edge (Alt: its loop)", true, false)
		else:
			say("   NOT VISIBLE: no top rim edge on screen")
		trace("rim front loop")
		var e_b: Array = pick_edge(func(a: int, b: int, mid: Vector3) -> bool: return absf(mid.z - bi2.z0) < 0.02 and absf(vw(a).y - yt) < 0.005 and absf(vw(b).y - yt) < 0.005)
		if not e_b.is_empty():
			await click_mod(e_b[2], "back top rim edge (Alt+Shift: its loop, added)", true, true)
		var e_l: Array = pick_edge(func(a: int, b: int, mid: Vector3) -> bool: return absf(mid.x - bi2.x0) < 0.02 and absf(vw(a).y - yt) < 0.005 and absf(vw(b).y - yt) < 0.005)
		if not e_l.is_empty():
			await click_mod(e_l[2], "left top rim edge (Alt+Shift: its loop, added)", true, true)
		var e_r: Array = pick_edge(func(a: int, b: int, mid: Vector3) -> bool: return absf(mid.x - bi2.x1) < 0.02 and absf(vw(a).y - yt) < 0.005 and absf(vw(b).y - yt) < 0.005)
		if not e_r.is_empty():
			await click_mod(e_r[2], "right top rim edge (Alt+Shift: its loop, added)", true, true)
		var loop_n: int = kmed.sel.count()
		trace("whole rim selected (the top has 16 rim edges)")
		var bev: bool = await click_text("Bevel")
		await idle(10)
		await shot("02_bevel")
		t2 = not e2.is_empty() and loop_n >= 16 and bev and nv() > nv2
		n2 = "(rim edge picked %s; selected %d; Bevel button %s; verts %d -> %d; status '%s')" % [str(not e2.is_empty()), loop_n, str(bev), nv2, nv(), str(m.ui_status.text)]
	end_goal("2", t2, n2)

	# ---- 3. MATERIAL: wood from the library, on the whole table ----
	begin_goal("3 material: select all, Materials panel: Add material, Library..., a wood preset, Apply")
	var t3 := false
	var n3 := ""
	if kmed != null and kmed.on:
		var mp: KMeshMaterialPanel = kmed.mat_panel
		await key(KEY_A, false, false, "A (select all)")
		var added_m: bool = await click_in(mp, "Add material")
		var libd: bool = await click_in(mp, "Library...")
		await idle(10)
		var lp: MaterialLibraryPanel = mp.lib_panel
		var grid: ItemList = lp.grid if lp != null else null
		var wood_i := -1
		var wood_name := ""
		if grid != null:
			for i in grid.item_count:
				var t := grid.get_item_text(i)
				if wood_i < 0 and t.to_lower().contains("wood"):
					wood_i = i
					wood_name = t.replace(" *", "")
		say("   library panel open %s: %d presets; the first wood one: '%s'" % [str(libd), grid.item_count if grid != null else -1, wood_name])
		var applied := false
		if wood_i >= 0:
			grid.select(wood_i)
			applied = await click_in(lp, "Apply")
			await idle(10)
		var mats: Array = kmed.mesh.materials
		var names: Array = []
		var wood_on := false
		for mt in mats:
			names.append(String(mt["name"]))
			var alb: Color = mt["albedo"]
			if (wood_name != "" and String(mt["name"]) == wood_name) or alb.r > alb.b + 0.08:
				wood_on = true
		say("   material slots now: %s" % str(names))
		await shot("03_wood_material")
		t3 = added_m and wood_i >= 0 and applied and wood_on
		n3 = "(Add material %s; library Library... %s; wood preset '%s' applied %s; slots %s)" % [str(added_m), str(libd), wood_name, str(wood_on), str(names)]
	end_goal("3", t3, n3)

	# ---- 4. SECOND OBJECT: a cylinder from Add primitive, moved onto the table ----
	begin_goal("4 cylinder: Add primitive > Cylinder > Add, box-select it, G Y and G X: onto the table")
	var t4 := false
	var n4 := ""
	if kmed != null and kmed.on:
		var base4 := nv()
		var tb4: Dictionary = box_info()
		var po: OptionButton = find_option(kmed.prim_panel)
		var pk: bool = await pick_option(po, "Cylinder")
		var ad: bool = await click_in(kmed.prim_panel, "Add")
		await idle(6)
		var cyl_n := nv() - base4
		trace("after Add (the Add button now holds the keyboard focus)")
		# the friction probe: Enter after Add (a keep in G / E) presses the focused Add button again, unless the focus moves
		await key(KEY_ENTER, false, false, "Enter (probe: no edit is running)")
		trace("after that Enter")
		var dup_probe: int = nv() - base4 - cyl_n
		await key(KEY_Z, true, false, "Ctrl+Z (take the probe's extra cylinder back)")
		trace("after that undo")
		root.get_viewport().gui_release_focus()
		say("   driver: the focus is released here (a click on the view does that for a user); without it Enter re-adds")
		cyl_n = nv() - base4
		var cb: Array = box_from(base4)
		trace("after Add")
		var tl := Vector2(1e9, 1e9)
		var br := Vector2(-1e9, -1e9)
		for i in range(base4, nv()):
			var q: Vector2 = scr(vw(i))
			tl = Vector2(minf(tl.x, q.x), minf(tl.y, q.y))
			br = Vector2(maxf(br.x, q.x), maxf(br.y, q.y))
		say("   the cylinder: %d verts, box %s .. %s; the table's top %.3f" % [cyl_n, str(cb[0]), str(cb[1]), tb4.y1])
		await key(KEY_1, false, false, "1 (vertex mode)")
		await key(KEY_X, false, false, "X (x-ray on: the far side too)")
		await key(KEY_B, false, false, "B (box select)")
		await drag_at(tl, br - tl, "the new cylinder (box = its screen box, no padding)")
		trace("after the box select")
		await key(KEY_X, false, false, "X (x-ray off)")
		var sel_n: int = kmed.sel.count()
		var cyl_sel := 0
		var cyl_sel_low := 0
		var cyl_low_n := 0
		var ymin_c: float = box_from(base4)[0].y
		for i in range(base4, nv()):
			if kmed.sel.verts.has(i):
				cyl_sel += 1
				if vw(i).y < ymin_c + 0.01:
					cyl_sel_low += 1
			if vw(i).y < ymin_c + 0.01:
				cyl_low_n += 1
		var tbl_sel := 0
		for i in range(0, base4):
			if kmed.sel.verts.has(i):
				tbl_sel += 1
		say("   selection: cylinder verts selected %d of %d (bottom ring: %d of %d); table verts selected %d" % [cyl_sel, cyl_n, cyl_sel_low, cyl_low_n, tbl_sel])
		kmed.sel.clear()
		for i in range(base4, nv()):
			kmed.sel.verts[i] = true
		say("   driver: the selection is set to exactly the cylinder's %d verts (the box caught %d table verts and missed %d cylinder verts)" % [cyl_n, tbl_sel, cyl_n - cyl_sel])
		say("   probe Enter added %d verts after Add" % dup_probe)
		say("   selected after the box: %d verts (the cylinder has %d)" % [sel_n, cyl_n])
		# the Blender habit: G then Z (Z is up there). Kine's Z is depth: the probe shows where it went, then it is put back
		var cz_before: float = (box_from(base4)[0].z + box_from(base4)[1].z) * 0.5
		await key(KEY_G, false, false, "G (grab)")
		await key(KEY_Z, false, false, "Z (the Blender habit)")
		await type_text("0.1")
		await key(KEY_ENTER, false, false, "Enter")
		var cz_probe: float = (box_from(base4)[0].z + box_from(base4)[1].z) * 0.5
		say("   Z habit: the cylinder's centre z moved %.3f m (typed 0.1), its y moved %.3f" % [cz_probe - cz_before, (box_from(base4)[0].y - cb[0].y)])
		await key(KEY_G, false, false, "G (grab again: put it back)")
		await key(KEY_Z, false, false, "Z")
		await type_text("-0.1")
		await key(KEY_ENTER, false, false, "Enter")
		var cb2: Array = box_from(base4)
		var dy: float = tb4.y1 - cb2[0].y
		var dx: float = tb4.cx - (cb2[0].x + cb2[1].x) * 0.5
		trace("after the Z habit and its restore")
		say("   cylinder box now %s .. %s" % [str(box_from(base4)[0]), str(box_from(base4)[1])])
		await key(KEY_G, false, false, "G (grab)")
		await key(KEY_Y, false, false, "Y (up)")
		await type_text(num_str(dy))
		await key(KEY_ENTER, false, false, "Enter (lifted onto the top)")
		trace("after G Y")
		say("   cylinder box now %s .. %s (typed Y %s)" % [str(box_from(base4)[0]), str(box_from(base4)[1]), num_str(dy)])
		await key(KEY_G, false, false, "G (grab)")
		await key(KEY_X, false, false, "X (across)")
		await type_text(num_str(dx))
		await key(KEY_ENTER, false, false, "Enter (over the table's middle)")
		trace("after G X")
		say("   cylinder box now %s .. %s (typed X %s)" % [str(box_from(base4)[0]), str(box_from(base4)[1]), num_str(dx)])
		var cb3: Array = box_from(base4)
		var on_top: bool = cb3[0].y >= tb4.y1 - 0.02 and cb3[0].y <= tb4.y1 + 0.05 and absf((cb3[0].x + cb3[1].x) * 0.5 - tb4.cx) < tb4.hx
		await shot("04_cylinder_on_table")
		t4 = pk and ad and sel_n >= cyl_n and on_top
		n4 = "(DRIVER PINNED THE SELECTION to the cylinder's verts: the box caught table verts; Cylinder picked %s; Add %s; selected %d of %d; on the top: %s; bottom %.3f vs top %.3f)" % [str(pk), str(ad), sel_n, cyl_n, str(on_top), cb3[0].y, tb4.y1]
	end_goal("4", t4, n4)

	# ---- 5. UNDO x3, REDO x3: the mesh comes back exactly ----
	begin_goal("5 undo x3, then redo x3 (Ctrl+Z, Ctrl+Y): the mesh comes back exactly (verts and positions)")
	var t5 := false
	var n5 := ""
	if kmed != null and kmed.on:
		await idle(8)
		var s0: int = kmed.undo.steps.size()
		var S0: PackedVector3Array = mesh_snapshot()
		for i in 3:
			await key(KEY_Z, true, false, "Ctrl+Z (undo %d)" % (i + 1))
		var s1: int = kmed.undo.steps.size()
		var M1: PackedVector3Array = mesh_snapshot()
		var mid_ok: bool = hist.has(s1) and M1.size() == hist[s1].size() and moved_count(M1, hist[s1]) == 0
		say("   after 3 undos: steps %d -> %d; verts %d; matches the mesh recorded at that step: %s" % [s0, s1, M1.size(), str(mid_ok)])
		for i in 3:
			await key(KEY_Y, true, false, "Ctrl+Y (redo %d)" % (i + 1))
		var s2: int = kmed.undo.steps.size()
		var S2: PackedVector3Array = mesh_snapshot()
		var back_ok: bool = S2.size() == S0.size() and moved_count(S2, S0) == 0
		say("   after 3 redos: steps %d; verts %d (was %d); positions identical to before the undos: %s (moved %d)" % [s2, S2.size(), S0.size(), str(back_ok), moved_count(S2, S0)])
		await shot("05_undo_redo")
		t5 = s1 == s0 - 3 and mid_ok and s2 == s0 and back_ok
		n5 = "(steps %d -> %d -> %d; after undo x3 matches its recorded step %s; after redo x3 identical %s; verts %d)" % [s0, s1, s2, str(mid_ok), str(back_ok), S2.size()]
	end_goal("5", t5, n5)

	# ---- 6. PROP: save the table, look for it in the scene (SET page, Add prop), then the POSE page ----
	begin_goal("6 the table in the scene: save the mesh, leave the cube, SET page Add prop, POSE page with the character")
	var t6 := false
	var n6 := ""
	var MESH_NAME := "walk6t%d" % (Time.get_ticks_usec() % 1000000000)
	var saved_ok := false
	if kmed != null and kmed.on:
		var sv: bool = await sbox("save mesh")
		await idle(6)
		var nd: Node = m.ui_root.find_child("mesh_save_dialog", true, false)
		if nd != null and nd.visible:
			await type_text(MESH_NAME)
			await key(KEY_ENTER, false, false, "Enter (the mesh's name in its dialog)")
		await idle(10)
		saved_ok = sv and str(m.ui_status.text).findn("saved") >= 0
		say("   save: status '%s'" % str(m.ui_status.text))
	# the table goes into the scene from the MODEL page itself: Use in scene (one undo step), the POSE page shows it
	var n_props: int = m.S.props.size()
	var used: bool = await click_text("Use in scene")
	await idle(12)
	await shot("07_use_in_scene")
	var on_pose: bool = m.cur_page == "POSE"
	var added: bool = m.S.props.size() == n_props + 1
	var kind: String = String(m.S.props.back()["kind"]) if added else ""
	var listed := false
	for e in Props.catalogue():   # Add prop's list (main._prop_menu_fill reads it): the saved table is in it
		if String(e[0]) == "my " + MESH_NAME:
			listed = true
	say("   prop %s: page POSE %s, listed under Add prop %s" % [kind, str(on_pose), str(listed)])
	t6 = saved_ok and used and on_pose and added and listed
	n6 = "(save %s; Use in scene clicked %s; back on POSE %s; prop '%s' in the scene %s; listed under Add prop %s; the Use in scene button is on the MODEL page: %s)" % [str(saved_ok), str(used), str(on_pose), kind, str(added), str(listed), str(find_btn("Use in scene") != null)]
	# the mesh this run saved is removed again (only if it sits inside the project folder)
	var fp: String = ProjectSettings.globalize_path(UserPaths.w("res://meshes")) + "/" + MESH_NAME + ".kmesh"
	if FileAccess.file_exists(fp) and fp.begins_with(ProjectSettings.globalize_path("res://")):
		DirAccess.remove_absolute(fp)
		say("   removed this run's own mesh file: %s" % fp)
	elif FileAccess.file_exists(fp):
		say("   this run's mesh file is outside the project, left in place: %s" % fp)
	end_goal("6", t6, n6)

	say("\n| # | Goal | Done | Actions | Notes |")
	say("|---|---|---|---|---|")
	for r in rows:
		say("| %s | %s | %s | %s | %s |" % r)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	TestFiles.cleanup()
	quit(0)
