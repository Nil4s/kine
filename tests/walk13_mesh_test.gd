## godot --path . -s tests/walk13_mesh_test.gd   (BEGINNER WALK-THROUGH, round 13: EXPERT mode, the mesh pages; real clicks and drags only)
## The six goals a hobbyist would try with today's mesh pages (MODEL, SCULPT, SURFACE):
##  0 start as a fresh install (Easy), "Switch to Expert" on the Easy bar (the only way to Expert a beginner sees);
##  1 MODEL: a hint says what to do first (within 2 s); "Body mesh" opens the body's mesh and it is shown;
##  2 box-select a chest region by a drag from empty space, G, move the mouse, click: the vertices move (max mm);
##  3 Undo (the top bar): the mesh is back exactly (< 0.01 mm);
##  4 SCULPT: "Test sphere", the "Draw" button, one stroke across it: vertices move; Undo restores;
##  5 SURFACE: "Library..." on the Materials panel, a skin preset: the body's colour in the picture changes;
##  6 MODEL "Apply body", Esc, POSE: drag the left elbow: the arm moves and the body edit is applied.
## Only what a beginner sees: buttons by their words, the view by a click or a drag at the part's screen point. Reads of state are
## for the checks and the numbers only. Prints "GOAL n: PASS|FRICTION - what happened (clicks k, s seconds)". Exits 0.
## Screenshots: C:/Temp/claude/w13/walk13_<n>.png.
extends SceneTree

const OUT := "C:/Temp/claude/w13/"

var video_dir := ""
var m: Node
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var notes: Array = []
var gbase := 0
var results: Array = []
var sel_rect := Rect2()   # goal 2's box select on the screen (the chest patch)


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):   # INTERNAL children too: a dialog's button row is internal
		walk(c, out)
	return out


## the visible CanvasItems under a node (the whole window when scope is the root)
func vis_under(scope: Node) -> Array:
	var out := []
	for n in walk(scope, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func labels_of(b: Button) -> Array:
	var out := [text_of(b)]
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return out


## the first visible button under scope that reads txt (prefix: begins with txt)
func btn_in(scope: Node, txt: String, prefix := false) -> Button:
	for n in vis_under(scope):
		if n is Button:
			for t in labels_of(n as Button):
				if t == txt or (prefix and String(t).begins_with(txt)):
					return n
	return null


## the first visible button under scope with a label that contains word (any case)
func btn_has(scope: Node, word: String) -> Button:
	for n in vis_under(scope):
		if n is Button:
			for t in labels_of(n as Button):
				if String(t).to_lower().contains(word.to_lower()):
					return n
	return null


func find_btn(txt: String, prefix := false) -> Button:
	return btn_in(root, txt, prefix)


func visible_words() -> String:
	var out := []
	for n in vis_under(root):
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return str(out)


func btn_names() -> String:
	var out := []
	for n in vis_under(root):
		if n is Button and text_of(n as Button) != "":
			out.append(text_of(n as Button))
	return str(out)


func mouse_btn(down: bool, p: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


func hit_name() -> String:
	var h := get_root().get_viewport().gui_get_hovered_control()
	return "none" if h == null else str(h.name) + " (" + h.get_class() + ")"


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var r := c.get_global_rect()
	var w := c.get_window()
	if w != null and w != get_root():
		r.position += Vector2(w.position)
	var p := r.get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name()])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return inside


## a click on the first visible button with these words (the words a beginner reads on it), anywhere or under scope
func click_text(txt: String, prefix := false, scope: Node = null) -> bool:
	var b: Button = btn_in(scope if scope != null else root, txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	clicks += 1
	say("   click '%s' (tooltip: '%s')" % [text_of(b), b.tooltip_text])
	return await click_ctl(b)


## a click on the first visible button whose words contain word
func click_has(word: String, scope: Node = null) -> bool:
	var b: Button = btn_has(scope if scope != null else root, word)
	if b == null:
		say("   NOT VISIBLE: no button with '%s' in its words" % word)
		return false
	clicks += 1
	say("   click '%s' (tooltip: '%s')" % [text_of(b), b.tooltip_text])
	return await click_ctl(b)


## a real press on a view point: down, up
func click_view(p: Vector2) -> void:
	clicks += 1
	await hover(p)
	say("   click in the view at %s (under the pointer: %s)" % [str(p), hit_name()])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(4)


## a real drag in the view: press at p, move in six steps by d, let go at p + d
func drag_view(p: Vector2, d: Vector2) -> void:
	clicks += 1
	await hover(p)
	say("   drag from %s by %s (under the pointer: %s)" % [str(p), str(d), hit_name()])
	var st := d / 6.0
	mouse_btn(true, p)
	await process_frame
	for k in 6:
		var q := p + st * float(k + 1)
		var mv := InputEventMouseMotion.new()
		mv.position = q
		mv.global_position = q
		mv.relative = st
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mv)
		await process_frame
	mouse_btn(false, p + d)
	await idle(4)


## the first visible button whose tooltip begins with prefix (an icon-only button has no words: its tooltip is its name)
func find_tip(prefix: String) -> Button:
	for n in vis_under(root):
		if n is Button and String((n as Button).tooltip_text).begins_with(prefix):
			return n
	return null


## the Undo button: by its tooltip, then a real click; a button with no words is noted as friction
func click_undo() -> bool:
	var ub := find_tip("Undo")
	if ub == null:
		note("no Undo button on screen (Ctrl+Z is the only way back)")
		await press_key_ctrl_z()
		await idle(10)
		return false
	clicks += 1
	# an arrow icon with no words is fine (Nick 10-25: "undo button i think is kind intuitive even for easy mode")
	say("   click the Undo button (tooltip: '%s')" % ub.tooltip_text.split("\n")[0])
	return await click_ctl(ub)


func press_key_ctrl_z() -> void:
	await press_key(KEY_Z, true)


## typing: each letter as a real key press with its character (a LineEdit reads the character)
func type_text(s: String) -> void:
	for i in s.length():
		var c := s.substr(i, 1)
		var kc: int = c.to_upper().unicode_at(0)
		var kd := InputEventKey.new()
		kd.keycode = kc as Key
		kd.physical_keycode = kc as Key
		kd.unicode = c.unicode_at(0)
		kd.pressed = true
		root.push_input(kd)
		await process_frame
		var ku := InputEventKey.new()
		ku.keycode = kc as Key
		ku.physical_keycode = kc as Key
		ku.unicode = c.unicode_at(0)
		ku.pressed = false
		root.push_input(ku)
		await process_frame


## the pointer moves in six steps by d with no button down (a grab that follows the mouse), then the caller clicks
func move_view(p: Vector2, d: Vector2) -> Vector2:
	var st := d / 6.0
	for k in 6:
		var q := p + st * float(k + 1)
		var mv := InputEventMouseMotion.new()
		mv.position = q
		mv.global_position = q
		mv.relative = st
		root.push_input(mv)
		await process_frame
	return p + d


## true when another control sits on the button's middle (a hover, no click): the beginner cannot press it there
func covered(c: Control) -> bool:
	var r := c.get_global_rect()
	var w := c.get_window()
	if w != null and w != get_root():
		r.position += Vector2(w.position)
	var p := r.get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the button '%s' at %s: the pointer there is on %s" % [text_of(c as Button) if c is Button else c.name, str(p), hit_name()])
	return not inside


func status_now() -> String:
	var s := ""
	if m.ui_status != null:
		s = m.ui_status.text
	return "status line: '%s'" % s


func press_key(kc: Key, ctrl := false) -> void:
	var kd := InputEventKey.new()
	kd.keycode = kc
	kd.physical_keycode = kc
	kd.ctrl_pressed = ctrl
	kd.pressed = true
	root.push_input(kd)
	await process_frame
	var ku := InputEventKey.new()
	ku.keycode = kc
	ku.physical_keycode = kc
	ku.ctrl_pressed = ctrl
	ku.pressed = false
	root.push_input(ku)
	await process_frame


func shot(n: int, what: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	var f := OUT + "walk13_%d.png" % n
	root.get_texture().get_image().save_png(f)
	say("   screenshot %s (%s) | page: %s | expert: %s" % [f, what, m.cur_page, str(not m.easy.on)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())
	say("   %s" % status_now())


func start_goal(n: int, s: String) -> void:
	goal = "GOAL %d" % n
	clicks = 0
	t0 = Time.get_ticks_msec()
	gbase = notes.size()
	say("\n== GOAL %d: %s ==" % [n, s])


func note(s: String) -> void:
	notes.append("[%s] %s" % [goal, s])
	say("   FRICTION: " + s)


func finish(n: int, ok: bool, what: String) -> void:
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var fr := (not ok) or notes.size() > gbase
	say("GOAL %d: %s - %s (clicks %d, %.1f s)" % [n, "PASS" if not fr else "FRICTION", what, clicks, secs])
	results.append([n, not fr, clicks, secs])


func wait_for_cond(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


## the clip / the edit settles: a few frames of nothing moving
func settle(limit := 60) -> void:
	await idle(limit)


# ---------------------------------------------------------------- the mesh pages

## the body or cube mesh the editor shows now (null when no mesh is open)
func kmesh() -> KMesh:
	if m.kmed != null and m.kmed.on and m.kmed.mesh != null:
		return m.kmed.mesh
	return null


func sphere_mesh() -> KMesh:
	if m.ksc != null and m.ksc.on and m.ksc.mesh != null:
		return m.ksc.mesh
	return null


## the largest move between two vertex lists, in mm (-1 when the counts differ)
func max_move_mm(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return -1.0
	var mx := 0.0
	for i in a.size():
		mx = maxf(mx, a[i].distance_to(b[i]))
	return mx * 1000.0


func count_moved(a: PackedVector3Array, b: PackedVector3Array, eps := 0.0005) -> int:
	if a.size() != b.size():
		return -1
	var n := 0
	for i in a.size():
		if a[i].distance_to(b[i]) > eps:
			n += 1
	return n


## the screen point of a point of a mesh view (the camera's projection of the view's world point)
func scr_of(v: Node3D, p: Vector3) -> Vector2:
	return m.cam.unproject_position(v.global_transform * p)


## the screen rectangle of all the vertices of a mesh in a view
func screen_box(v: Node3D, verts: PackedVector3Array) -> Rect2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in verts:
		var s := scr_of(v, p)
		mn = mn.min(s)
		mx = mx.max(s)
	return Rect2(mn, mx - mn)


func mean_of(verts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in verts:
		c += p
	return c / float(maxi(verts.size(), 1))


## the average colour of a 7 x 7 patch of the picture at a screen point
func px_avg(c: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var x := clampi(int(c.x) + dx, 0, img.get_width() - 1)
			var y := clampi(int(c.y) + dy, 0, img.get_height() - 1)
			acc += img.get_pixel(x, y)
			n += 1
	return Color(acc.r / n, acc.g / n, acc.b / n, 1.0)


## the albedo (base colour) of material slot i of the open mesh, read from its data (Color(-1, ...) when there is none)
func slot_albedo(i: int) -> Color:
	var k := kmesh()
	if k == null or i < 0 or i >= k.materials.size():
		return Color(-1, -1, -1, 1)
	var d: Dictionary = k.materials[i]
	for key in d:
		if String(key).contains("albedo") and d[key] is Color:
			return d[key]
	return Color(-1, -1, -1, 1)


func colour_gap(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


## the posing body: its part's screen point and capsule direction (as walk12)
func mid(part: String) -> Vector3:
	var c: Array = m.B.cap(part)
	return (c[0] + c[1]) * 0.5 if c.size() >= 2 else Vector3.ZERO


func scr(part: String) -> Vector2:
	return m.cam.unproject_position(mid(part))


func dir_of(part: String) -> Vector3:
	var c: Array = m.B.cap(part)
	if c.size() < 2:
		return Vector3.ZERO
	return ((c[1] as Vector3) - (c[0] as Vector3)).normalized()


func angle_between(a: Vector3, b: Vector3) -> float:
	if a.length() < 1e-6 or b.length() < 1e-6:
		return 0.0
	return rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0)))


## the visible page-bar button's name for a page, through the bar only (the ribbon has no page buttons)
func page_click(p: String) -> bool:
	return await click_text(p, false, m.ui_page_bar)


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	video_dir = ProjectSettings.globalize_path("user://walk13_out_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(video_dir)
	m.easy.home.video_root = video_dir
	say("start: Easy on at start: %s | page %s" % [str(m.easy.on), m.cur_page])
	say("start: buttons %s" % btn_names())

	# 0 + 1. SWITCH TO EXPERT, MODEL: THE HINT, THE BODY MESH
	start_goal(1, "Switch to Expert, MODEL: a hint says what to do first; Body mesh opens the body's mesh")
	var sw: bool = await click_has("Expert")
	await idle(15)
	say("   after 'Switch to Expert': Easy %s" % str(m.easy.on))
	if m.easy.on:
		note("the Easy bar's 'Switch to Expert' button did not switch to Expert (still Easy)")
	var on_model := await page_click("MODEL")
	var t1 := Time.get_ticks_msec()
	var hint_ms := -1.0
	while Time.get_ticks_msec() - t1 < 2000:
		if m.ui_mesh_hint_box != null and m.ui_mesh_hint_box.visible:
			hint_ms = float(Time.get_ticks_msec() - t1)
			break
		await process_frame
	var hint_txt := String(m.ui_mesh_hint.text) if m.ui_mesh_hint != null else ""
	say("   hint on MODEL: %s within %.0f ms | text '%s' | words: %s" % [str(hint_ms >= 0.0), hint_ms, hint_txt, visible_words()])
	if hint_ms < 0.0:
		note("no hint on MODEL within 2 s (words on screen: %s)" % visible_words())
	await shot(10, "MODEL, Expert, before the body mesh")
	var body_ok := await click_text("Body mesh")
	await idle(30)
	var k1 := kmesh()
	var nverts := k1.verts.size() if k1 != null else 0
	say("   body mesh open: %s | verts %d | hint still shown: %s | '%s'" % [str(k1 != null), nverts, str(m.ui_mesh_hint_box.visible), status_now()])
	if k1 == null:
		note("'Body mesh' did not open the body's mesh (%s)" % status_now())
	await shot(1, "MODEL, the body mesh open")
	finish(1, sw and on_model and hint_ms >= 0.0 and k1 != null and body_ok, "Expert %s; MODEL page %s; hint in %.0f ms; body mesh %s verts" % [str(not m.easy.on), str(on_model), hint_ms, str(nverts)])

	# 2. SELECT A REGION AND MOVE IT
	start_goal(2, "Box-select the chest by a drag, G, move the mouse, click: the vertices move")
	var before2: PackedVector3Array = kmesh().verts.duplicate() if kmesh() != null else PackedVector3Array()
	var v2: KMeshView = m.kmed.view if m.kmed != null else null
	var moved_mm := 0.0
	var moved_n := 0
	var sel_ok := false
	var screen_px := 0.0
	if v2 == null or before2.is_empty():
		note("no body mesh to select on (the MODEL page has no mesh open)")
	else:
		var box := screen_box(v2, before2)
		var chest_y := box.position.y + 0.30 * box.size.y
		var st := Vector2(box.position.x - 40.0, chest_y - 60.0)
		var en := Vector2(box.get_center().x + 50.0, chest_y + 40.0)
		sel_rect = Rect2(st, en - st)
		say("   body on screen %s | chest band at y %.0f" % [str(box), chest_y])
		await drag_view(st, en - st)   # a box select: the drag starts on empty space at the left of the body
		await idle(5)
		var nsel := 0
		if m.kmed.sel != null:
			nsel = m.kmed.sel.count() if m.kmed.sel.has_method("count") else -1
		say("   after the box drag: selection %s | '%s'" % [str(nsel), status_now()])
		sel_ok = true
		if find_btn("Move") == null:
			say("   no 'Move' button and no gizmo on the MODEL ribbon: the mesh is moved with G")
			await press_key(KEY_G)
		else:
			await idle(5)
			await click_text("Move")   # the MODEL ribbon's Move button: the same grab as G
		await idle(3)
		var cur := await move_view(box.get_center(), Vector2(90, 0))
		await idle(3)
		await click_view(cur)   # the click confirms the grab
		await settle(20)
		var after2 := kmesh().verts if kmesh() != null else PackedVector3Array()
		moved_mm = max_move_mm(before2, after2)
		moved_n = count_moved(before2, after2)
		# the screen travel of the moved verts (their centroid, px): a 90 px mouse drag should move them about 90 px on screen
		var c0 := Vector2.ZERO
		var c1 := Vector2.ZERO
		var nmv := 0
		for i in mini(before2.size(), after2.size()):
			if before2[i].distance_to(after2[i]) > 0.0005:
				c0 += scr_of(v2, before2[i])
				c1 += scr_of(v2, after2[i])
				nmv += 1
		if nmv > 0:
			screen_px = (c1 / float(nmv) - c0 / float(nmv)).length()
		say("   grab: max vertex move %.2f mm, vertices moved %d of %d, on screen %.1f px for the 90 px drag | '%s'" % [moved_mm, moved_n, before2.size(), screen_px, status_now()])
		if moved_n <= 0:
			note("the box-selected vertices did not move with G + mouse (%s)" % status_now())
	await shot(2, "the chest part moved")
	finish(2, sel_ok and moved_n > 0, "max vertex move %.2f mm; vertices moved %d; on screen %.1f px for 90 px of mouse" % [moved_mm, moved_n, screen_px])

	# 3. UNDO RESTORES THE MESH
	start_goal(3, "Undo (top bar): the mesh is back exactly")
	var after3_pre := kmesh().verts.duplicate() if kmesh() != null else PackedVector3Array()
	await click_undo()
	await settle(20)
	var back := kmesh().verts if kmesh() != null else PackedVector3Array()
	var back_mm := max_move_mm(before2, back)
	if back_mm < 0.0 or back_mm >= 0.01:
		note("the top-bar Undo did not take the mesh move back (its status: '%s'); only Ctrl+Z did" % status_now())
		await press_key_ctrl_z()
		await settle(20)
		back = kmesh().verts if kmesh() != null else PackedVector3Array()
		back_mm = max_move_mm(before2, back)
	say("   after Undo: max distance from the pre-move mesh %.4f mm (the move was %.2f mm) | '%s'" % [back_mm, moved_mm, status_now()])
	if back_mm < 0.0 or back_mm >= 0.01:
		note("Undo did not restore the mesh: %.4f mm from before the move" % back_mm)
	await shot(3, "after Undo")
	finish(3, back_mm >= 0.0 and back_mm < 0.01 and moved_mm > 0.5, "after Undo %.4f mm from the start (move was %.2f mm)" % [back_mm, moved_mm])

	# 4. SCULPT: A BRUSH BUTTON, ONE STROKE, UNDO
	start_goal(4, "SCULPT: Test sphere, the Draw button, one stroke across it; Undo")
	var on_sc := await page_click("SCULPT")
	await idle(15)
	var hint_sc := String(m.ui_mesh_hint.text) if m.ui_mesh_hint != null and m.ui_mesh_hint_box.visible else "(no hint)"
	say("   SCULPT hint: '%s'" % hint_sc)
	if hint_sc == "(no hint)":
		note("no hint on SCULPT with no sphere open")
	# the body's own sculpt (the ribbon's "Sculpt the body") when it is there: the stroke goes on the fighter's body mesh
	var body_sc := find_btn("Sculpt the body") != null
	var sph_ok := await click_text("Sculpt the body" if body_sc else "Test sphere")
	await idle(20)
	var brush_ok := await click_text("Draw")
	await idle(10)
	var sk := sphere_mesh()
	var sk_moved := -1
	var sk_mm := 0.0
	var outward := 0.0
	if sk == null:
		note("the Test sphere did not open on SCULPT (%s)" % status_now())
	else:
		var sb: PackedVector3Array = sk.verts.duplicate()
		var sview: KMeshView = m.ksc.view
		var sbox := screen_box(sview, sb)
		var cen := mean_of(sb)
		var cscr := sbox.get_center()
		var rx := sbox.size.x * 0.5
		if not body_sc:
			note("the sculpt target is the test sphere: SCULPT has no body and no chest (the stroke goes across the sphere)")
		if body_sc:   # the body: a short stroke across its middle (the sphere's left edge is empty space on the body)
			await drag_view(scr_of(sview, cen) + Vector2(-0.15 * rx, 0.0), Vector2(0.3 * rx, 0.0))
		else:
			await drag_view(cscr + Vector2(-0.6 * rx, 0.0), Vector2(1.2 * rx, 0.0))
		await idle(10)
		var sa: PackedVector3Array = sphere_mesh().verts if sphere_mesh() != null else PackedVector3Array()
		sk_mm = max_move_mm(sb, sa)
		sk_moved = count_moved(sb, sa)
		for i in mini(sb.size(), sa.size()):
			var d := sa[i] - sb[i]
			var rv := (sb[i] - cen).normalized()
			outward += d.dot(rv)
		say("   stroke: max move %.2f mm, vertices moved %d of %d, net outward %s | '%s'" % [sk_mm, sk_moved, sb.size(), "outward" if outward > 0.0 else "inward", status_now()])
		await shot(4, "after the sculpt stroke")
		await click_undo()
		await settle(20)
		var sback := sphere_mesh().verts if sphere_mesh() != null else PackedVector3Array()
		var sback_mm := max_move_mm(sb, sback)
		if sback_mm < 0.0 or sback_mm >= 0.01:
			note("the top-bar Undo did not take the stroke back (its status: '%s'); Ctrl+Z is the one that does" % status_now())
			await press_key_ctrl_z()
			await settle(20)
			sback = sphere_mesh().verts if sphere_mesh() != null else PackedVector3Array()
			sback_mm = max_move_mm(sb, sback)
		say("   after Undo: sphere %.4f mm from before the stroke" % sback_mm)
		if sback_mm < 0.0 or sback_mm >= 0.01:
			note("Undo did not restore the sphere: %.4f mm from before the stroke" % sback_mm)
		if body_sc:
			await press_key(KEY_ESCAPE)   # back to MODEL's body mesh (the Materials panel of goal 5 is the body's)
			await idle(15)
		finish(4, sph_ok and brush_ok and sk_moved >= 10 and sback_mm >= 0.0 and sback_mm < 0.01,
			"stroke moved %d verts (max %.2f mm, %s); Undo back within %.4f mm" % [sk_moved, sk_mm, "outward" if outward > 0.0 else "inward", sback_mm])
	if sk == null:
		finish(4, false, "no sphere opened")

	# 5. SURFACE: A SKIN MATERIAL WITH THE MOUSE
	start_goal(5, "SURFACE: Library... on the Materials panel, a skin preset: the body's colour changes")
	var on_sf := await page_click("SURFACE")
	await idle(20)
	var mp: Node = m.kmed.mat_panel if m.kmed != null else null
	var mat_shown: bool = mp != null and mp.is_visible_in_tree()
	say("   SURFACE page: Materials panel shown %s | words: %s" % [str(mat_shown), visible_words()])
	if not mat_shown:
		note("no Materials panel on SURFACE with the body open (the panel shows while a mesh is open)")
	var kv: KMeshView = m.kmed.view if m.kmed != null else null
	var body_pt := Vector2.ZERO
	if kv != null and kmesh() != null:
		var acc := Vector2.ZERO
		var na := 0
		for vp in kmesh().verts:
			var sp := scr_of(kv, vp)
			if sel_rect.has_point(sp):
				acc += sp
				na += 1
		body_pt = acc / float(maxi(na, 1))
		say("   colour sample on the box-selected patch: %d verts, centre %s" % [na, str(body_pt)])
	var c_before := Color(0, 0, 0)
	var c_after := Color(0, 0, 0)
	await idle(3)
	c_before = px_avg(body_pt)
	say("   body's colour in the picture before: %s at %s" % [str(c_before), str(body_pt)])
	var slots: int = mp.list.item_count if mp != null and mp.get("list") != null else -1
	say("   material slots on the body: %d" % slots)
	if slots == 0:
		note("the Materials panel's slot list is empty on the body: 'Library...' needs a slot, so the beginner must 'Add material' first")
		await click_text("Add material")
		await idle(15)
		if String(m.ui_status.text).contains("other faces went"):
			note("Add material with the box-selected faces split the body in two slots: '%s'" % m.ui_status.text)
	var slot_i: int = mp.cur if mp != null and mp.get("cur") != null else -1
	var alb0 := slot_albedo(slot_i)
	var lib_ok := await click_text("Library...")
	await idle(20)
	var lib_scope: Node = mp.lib_panel if mp != null and mp.get("lib_panel") != null else root
	say("   library panel shown: %s | words: %s" % [str(lib_scope.is_visible_in_tree()) if lib_scope != null else "no", visible_words()])
	var skin_ok := false
	if lib_ok and lib_scope != null and lib_scope != root:
		var se := lib_scope.find_child("matlib_search", true, false) as Control
		if se != null:
			await click_ctl(se)
			await type_text("skin")
			await idle(15)
		var gr := lib_scope.find_child("matlib_grid", true, false) as ItemList
		if gr != null and gr.item_count > 0:
			var pick := gr.item_count - 1   # the last skin preset (the first is the light one)
			for ii in gr.item_count:
				if gr.get_item_text(ii).to_lower().contains("dark"):
					pick = ii
					break
			var ir := gr.get_item_rect(pick)
			var gp := gr.get_global_rect().position + ir.get_center()
			say("   library: %d presets after 'skin': picked '%s' (the first is '%s')" % [gr.item_count, gr.get_item_text(pick), gr.get_item_text(0)])
			clicks += 1
			await hover(gp)
			mouse_btn(true, gp)
			await process_frame
			mouse_btn(false, gp)
			await idle(8)
			skin_ok = true
			var ap := btn_in(lib_scope, "Apply")
			if ap != null:
				await click_ctl(ap)
				await idle(10)
			else:
				note("no Apply button in the library")
		else:
			say("   library: no preset list items (%s)" % (str(gr.item_count) if gr != null else "no list"))
	await idle(10)
	c_after = px_avg(body_pt)
	var gap := colour_gap(c_before, c_after)
	var alb1 := slot_albedo(slot_i)
	var agap := colour_gap(alb0, alb1) if alb0.r >= 0.0 and alb1.r >= 0.0 else 0.0
	say("   slot %d albedo: %s -> %s (gap %.3f) | picture colour gap %.3f (the sample is on the selection tint) | '%s'" % [slot_i, str(alb0), str(alb1), agap, gap, status_now()])
	gap = maxf(gap, agap)
	if not skin_ok:
		note("no skin preset found in the Library (words: %s)" % visible_words())
	if gap < 0.03:
		note("the body's colour barely changed (gap %.3f) after the skin preset" % gap)
	await shot(5, "SURFACE, skin preset")
	finish(5, mat_shown and skin_ok and gap >= 0.03, "skin preset %s; colour gap %.3f (%s -> %s)" % [str(skin_ok), gap, str(c_before), str(c_after)])

	# 6. BACK TO POSE: THE EDITED BODY STILL POSES
	start_goal(6, "MODEL: Apply body, Esc, POSE: drag the left elbow: the arm moves, the body edit stays")
	var on_md := await page_click("MODEL")
	await idle(15)
	var ap_ok := await click_text("Apply body")
	await idle(20)
	say("   after Apply body: '%s'" % status_now())
	await press_key(KEY_ESCAPE)
	await idle(15)
	var on_pose := await page_click("POSE")
	await idle(60)
	var fighter_shown := false
	if m.pieces != null:
		for j in m.pieces:
			if (m.pieces[j] as MeshInstance3D).is_visible_in_tree():
				fighter_shown = true
	var applied: bool = BaseBody.gen(m) > 0
	say("   POSE: page %s | fighter shown %s | applied body (gen > 0) %s | words: %s" % [m.cur_page, str(fighter_shown), str(applied), visible_words()])
	var pl0 := dir_of("lowerarm_l")
	var ep := scr("lowerarm_l")
	await drag_view(ep, Vector2(-110, 0))
	await idle(10)
	var arm_turn := angle_between(pl0, dir_of("lowerarm_l"))
	say("   dragged the left forearm: turned %.1f deg | '%s'" % [arm_turn, status_now()])
	if arm_turn < 5.0:
		note("a drag of 110 px to the left did not bend the left forearm (%.1f deg; status: '%s'): the drag had to go the other way" % [arm_turn, status_now()])
		await drag_view(scr("lowerarm_l"), Vector2(110, 0))
		await idle(10)
		arm_turn = angle_between(pl0, dir_of("lowerarm_l"))
		say("   dragged the other way: forearm turned %.1f deg | '%s'" % [arm_turn, status_now()])
	if arm_turn < 5.0:
		note("the left forearm barely moved (%.1f deg) on POSE after the body edit" % arm_turn)
	if not applied:
		note("the edited body is not applied to the fighter (Apply body did nothing: %s)" % status_now())
	await shot(6, "POSE, arm dragged after the edit")
	finish(6, on_pose and fighter_shown and arm_turn >= 5.0 and applied, "arm turned %.1f deg; fighter shown %s; edit applied %s" % [arm_turn, str(fighter_shown), str(applied)])

	say("\nSUMMARY (goal | pass | clicks | seconds):")
	for r in results:
		say("  %d | %s | %d | %.1f" % [r[0], "PASS" if r[1] else "FRICTION", r[2], r[3]])
	var lf := FileAccess.open(OUT + "walk13_log.txt", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n")
	lf.close()
	TestFiles.cleanup()
	quit(0)
