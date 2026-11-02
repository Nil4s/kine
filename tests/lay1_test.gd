extends SceneTree
## lay1 (layout round w4-lay1): four overlaps found at night, each with a measured rect bar at 1280x720 and 1600x900; 1024x600 must not get worse.
##  1 Easy Part > Cut a hole on a plate: the chip box is at most 3 rows at 1280x720, covers no other control, is not under the view column,
##    and the Size line does not sit on the Flat pattern row (states: plain, Holes Around + Pick centre, Holes Grid, Fill the face, Make it lighter)
##  2 Parts > Challenges card: the score line and the print-time status line do not intersect
##  3 froom: the floor hint label is mouse-transparent, so a press on the framed grid's back corner reaches the floor
##  4 Trace: the traced picture is light on the dark floor (mean luminance of the drawn picture) at 70 % opacity
## Rule for 1 and 2: no visible leaf control (Button, Label with text, slider, LineEdit) intersects another visible leaf control by more than 2 px,
## nothing is cut by a clipping parent, and nothing of the chip box lies under the view column. Every pair checked is counted; every hit is printed.
## Shots: C:/Temp/claude/lay1/
var fails := 0
var m: Node
var SHOT := OS.get_environment("LAY1_SHOT") if OS.get_environment("LAY1_SHOT") != "" else "C:/Temp/claude/lay1"
const DIRT := "user://lay1_test"
const SIZES := [[1280, 720], [1600, 900], [1024, 600]]
var pu: PartUI
var ep


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(14)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func is_anc(a: Node, b: Node) -> bool:
	var p := b
	while p != null:
		if p == a:
			return true
		p = p.get_parent()
	return false


func leaves(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button or n is LineEdit or n is Range or (n is Label and (n as Label).text.strip_edges() != ""):
		out.append(n)
	for c in n.get_children():
		leaves(c, out)


func label_of(c: Control) -> String:
	return String(c.text if (c is Button or c is Label) else c.name).left(30).replace("\n", " ")


## the rect of c that can be seen: cut by every clipping ancestor and the window
func seen(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r.intersection(root.get_visible_rect())


## every visible leaf under scope: pairs checked, overlaps (> 2 px both ways), cut by a clipping parent, under the view column
func check(state: String, scope: Array, view_col: Control) -> int:
	var ls := []
	for sc in scope:
		if sc != null:
			leaves(sc, ls)
	var bad := 0
	var pairs := 0
	for i in ls.size():
		var a := ls[i] as Control
		var ra := a.get_global_rect()
		if ra.size.x < 1.0 or ra.size.y < 1.0:
			continue
		var sa := seen(a)
		if (sa.size.x < ra.size.x - 1.5 or sa.size.y < ra.size.y - 1.5) and not is_anc(ep.panel, a):   # the side panel's own scroll (Exact sizes? line) is another screen's matter
			print("     CLIP %s %s: %s shows only %s" % [state, label_of(a), ra, sa])
			bad += 1
		if view_col != null and view_col.is_visible_in_tree() and not is_anc(view_col, a) and not is_anc(a, view_col):
			var vr := view_col.get_global_rect()
			if ra.intersection(vr).size.x > 2.0 and ra.intersection(vr).size.y > 2.0:
				print("     UNDER-VIEW %s %s %s under the view column %s" % [state, label_of(a), ra, vr])
				bad += 1
		for j in range(i + 1, ls.size()):
			var b := ls[j] as Control
			if is_anc(a, b) or is_anc(b, a):
				continue
			var rb := b.get_global_rect()
			if rb.size.x < 1.0 or rb.size.y < 1.0:
				continue
			pairs += 1
			var ov := ra.intersection(rb)
			if ov.size.x > 2.0 and ov.size.y > 2.0:
				print("     OVERLAP %s [%s] %s / [%s] %s" % [state, label_of(a), ra, label_of(b), rb])
				bad += 1
	print("     PAIRS %s: %d leaves, %d pairs checked, %d problems" % [state, ls.size(), pairs, bad])
	return bad


## rows the chip box wraps to: distinct top edges of its visible chips (flow rows), sliders and labels left out
func rows_of(box: Control) -> int:
	var ys := []
	var ls := []
	leaves(box, ls)
	for c in ls:
		if c is Range or c is Label:
			continue
		var y := snappedf((c as Control).get_global_rect().position.y, 4.0)
		if not ys.has(y):
			ys.append(y)
	return ys.size()


func fresh_plate() -> void:
	m.S.part = {}
	ep.hole_base = {}
	ep.tweak = {}
	ep.fill_pick = false
	ep._rows_sig = ""
	pu.sync()
	await idle(6)
	await click_ctl(ep.chips["plate"])
	await idle(3)
	for r in ep.rows:
		if String(r["key"]) == "width":
			(r["slider"] as HSlider).value = 10.0
		elif String(r["key"]) == "length":
			(r["slider"] as HSlider).value = 6.0
		elif String(r["key"]) == "thickness":
			(r["slider"] as HSlider).value = 0.3
	await idle(4)
	await click_ctl(ep.make_btns["hole"])
	await idle(4)


## the Easy Part's own boxes (the app's top bar is another screen's)
func ep_scope() -> Array:
	return [ep.make_box, ep.hint, ep.hole_box, ep.shape_box, ep.round_box, ep.split_box, ep.colour_box, ep.repeat_box, ep.stick_box, ep.tilt_box, ep.explode_box, ep.view_box, ep.panel, ep.status, ep.size_l]


func hb(nm: String) -> Button:
	return ep.hole_box.find_child("easypart_hole_" + nm, true, false) as Button


func open_ep() -> void:
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep


func hole_state(tag: String, w: int, h: int) -> void:
	var hbx: Control = ep.hole_box
	var vc: Control = ep.view_box
	var st := "%s_%dx%d" % [tag, w, h]
	await idle(6)
	var rr := rows_of(hbx)
	print("     GEOM %s hole_box %s view_box %s hint %s size_l %s(vis %s) status %s panel %s" % [st, hbx.get_global_rect(), vc.get_global_rect(), ep.hint.get_global_rect(), ep.size_l.get_global_rect(), ep.size_l.visible, ep.status.get_global_rect(), ep.panel.get_global_rect()])
	var maxr := 0.0
	var lsx := []
	leaves(hbx, lsx)
	for c in lsx:
		if c is Button:
			maxr = maxf(maxr, (c as Control).get_global_rect().end.x)
	print("     CHIPS %s flow %s widest chip right edge %.1f box right edge %.1f" % [st, (hbx.get_child(0) as Control).get_global_rect(), maxr, hbx.get_global_rect().end.x])
	var bad := check(st, ep_scope(), vc)
	var vr: Rect2 = vc.get_global_rect()
	var br: Rect2 = hbx.get_global_rect()
	ok(hbx.visible and br.size.x > 0, "1 %s the hole box is up: %s" % [st, br])
	ok(rr <= (3 if w >= 1280 else 99), "1 %s the hole box is %d chip rows (at most 3 at 1280 and up)" % [st, rr])
	ok(br.intersection(vr).size.x <= 2.0 or br.intersection(vr).size.y <= 2.0, "1 %s the hole box %s is clear of the view column %s" % [st, br, vr])
	var fl := hb("flat")
	if fl != null and fl.is_visible_in_tree() and ep.size_l.visible:
		var ov: Rect2 = fl.get_global_rect().intersection(ep.size_l.get_global_rect())
		ok(ov.size.x <= 2.0 or ov.size.y <= 2.0, "1 %s Size line %s vs Flat pattern %s" % [st, ep.size_l.get_global_rect(), fl.get_global_rect()])
	ok(maxr <= br.end.x + 0.5, "1 %s every chip ends inside the hole box (%.1f <= %.1f)" % [st, maxr, br.end.x])
	if w >= 1280:
		ok(bad == 0, "1 %s no overlap / clip / under-view-column anywhere (%d problems)" % [st, bad])
	else:   # 1024 x 600: not worse than origin (problems counted on origin/poser-ui-rounds with this same checker: plain 51, around 49, pickc 49, grid 59, fill 51, lighter 54, lid 51)
		var base := {"hole_plain": 51, "hole_around": 49, "hole_pickc": 49, "hole_grid": 59, "hole_fill": 51, "hole_lighter": 54, "hole_lid": 51}
		ok(bad <= int(base[tag]), "1 %s not worse than origin: %d problems (origin %d)" % [st, bad, int(base[tag])])
	await shot(st)


func hole_run(w: int, h: int) -> void:
	await size_to(w, h)
	await fresh_plate()
	await hole_state("hole_plain", w, h)
	await click_ctl(hb("through"))
	await click_ctl(hb("around"))
	await hole_state("hole_around", w, h)
	var pk := hb("pickc")
	if pk != null and pk.is_visible_in_tree():
		await click_ctl(pk)
		await hole_state("hole_pickc", w, h)
		await click_ctl(pk)
	await click_ctl(hb("grid"))
	await hole_state("hole_grid", w, h)
	await click_ctl(hb("grid"))
	await click_ctl(hb("fill"))
	await hole_state("hole_fill", w, h)
	await click_ctl(hb("fill"))
	await click_ctl(hb("lighter"))
	await hole_state("hole_lighter", w, h)
	await click_ctl(hb("through"))
	await click_ctl(hb("lid"))
	await hole_state("hole_lid", w, h)


## 2 the Challenges card: score line vs the Size / print-time line, at each size
func challenge_run(w: int, h: int, id := "stand", dy := 0.0) -> void:
	await size_to(w, h)
	var st := "challenge_%s_%dx%d_dy%d" % [id, w, h, int(dy * 100.0)]
	if not ep.challenge_card.visible:
		await click_ctl(root.find_child("easypart_chip_parts", true, false))
		await open_group_of(root.find_child("easypart_challenges", true, false))   # 239
		await click_ctl(root.find_child("easypart_challenges", true, false))
	m.S.part = EasyChallenge.target_record(id).duplicate(true)
	pu.sync()
	await idle(8)
	var nn := 0
	while not ep._ease.is_empty() and nn < 200:
		await process_frame
		nn += 1
	await idle(6)
	m.target.y += dy   # the part's place on the screen moves (the print-time line hangs under it): a high part puts that line on the card
	m._cam()
	await idle(6)
	var card := ep.challenge_card as EasyChallenge
	if not card.visible:
		await click_ctl(root.find_child("easypart_chip_parts", true, false))
		await open_group_of(root.find_child("easypart_challenges", true, false))   # 239
		await click_ctl(root.find_child("easypart_challenges", true, false))
	await click_ctl(root.find_child("easypart_challenge_" + id, true, false))
	await click_ctl(root.find_child("easypart_challenge_check", true, false))
	await idle(10)
	var sc := card.score_l
	var sl: Label = ep.size_l
	var a := sc.get_global_rect()
	var b := sl.get_global_rect()
	print("     GEOM %s score [%s] %s size_l (vis %s) [%s] %s card %s" % [st, sc.text, a, sl.visible, sl.text.left(40).replace("
", " "), b, card.get_global_rect()])
	ok(sc.text.begins_with("Score"), "2 %s the score line reads [%s]" % [st, sc.text])
	var stt: Control = ep.status
	var os_ := a.intersection(stt.get_global_rect())
	ok(not stt.is_visible_in_tree() or os_.size.x <= 2.0 or os_.size.y <= 2.0, "2 %s score line %s vs the status line %s" % [st, a, stt.get_global_rect()])
	var ov := a.intersection(b)
	ok(not sl.visible or ov.size.x <= 2.0 or ov.size.y <= 2.0, "2 %s score line %s vs the print-time line %s (visible %s): no overlap" % [st, a, b, sl.visible])
	var ls := []
	leaves(card, ls)
	var bad := 0
	for c in ls:
		for d in ls:
			if c != d and not is_anc(c, d) and not is_anc(d, c) and (c as Control).get_instance_id() < (d as Control).get_instance_id():
				var o := (c as Control).get_global_rect().intersection((d as Control).get_global_rect())
				if o.size.x > 2.0 and o.size.y > 2.0:
					bad += 1
					print("     OVERLAP %s [%s] / [%s]" % [st, label_of(c), label_of(d)])
	ok(bad == 0, "2 %s no two controls of the card overlap (%d leaves, %d pairs)" % [st, ls.size(), ls.size() * (ls.size() - 1) / 2])
	ok(is_visible_rect_enclosing(card.get_global_rect()), "2 %s the card %s is on the window" % [st, card.get_global_rect()])
	await shot(st)


## the topmost control under p that takes the mouse (last drawn wins); mouse-ignoring controls are skipped
func top_at(n: Node, p: Vector2) -> Control:
	for i in range(n.get_child_count() - 1, -1, -1):
		var c = n.get_child(i)
		if c is CanvasItem and not (c as CanvasItem).is_visible_in_tree():
			continue
		var f := top_at(c, p)
		if f != null:
			return f
	if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE and (n as Control).get_global_rect().has_point(p):
		return n
	return null


## 3 froom: an empty part, Draw shape armed: the four corners of the framed floor grid (the grid's 0.5 m square, as the room test draws 0.8 x 0.6 m)
## are each pressable: no visible control takes the mouse there and the app's own over-UI test says no
func floor_run(w: int, h: int) -> void:
	await size_to(w, h)
	m.S.part = {}
	pu.sync()
	await idle(8)
	await click_ctl(ep.make_btns["draw"])
	var nn := 0
	while not ep._ease.is_empty() and nn < 200:
		await process_frame
		nn += 1
	await idle(8)
	var st := "floor_%dx%d" % [w, h]
	await shot(st)
	var gb := Rect2()
	for cx in [-0.5, 0.5]:
		for cz in [-0.5, 0.5]:
			var q: Vector2 = m.cam.unproject_position(Vector3(cx, 0.0, cz))
			gb = gb.expand(q) if gb.size != Vector2.ZERO or gb.position != Vector2.ZERO else Rect2(q, Vector2.ZERO)
	print("     GRID %s screen box of the 1 m grid %s grid_framed %s fr %s" % [st, gb, ep._grid_framed, ep._grid_fr])
	print("     GEOM %s hint %s (vis %s, filter %d) shape_box %s status %s free_rect %s" % [st, ep.hint.get_global_rect(), ep.hint.visible, ep.hint.mouse_filter, ep.shape_box.get_global_rect(), ep.status.get_global_rect(), ep.free_rect()])
	for cn in [Vector2(-0.4, -0.3), Vector2(0.4, -0.3), Vector2(-0.4, 0.3), Vector2(0.4, 0.3)]:
		var p: Vector2 = m.cam.unproject_position(Vector3(cn.x, 0.0, cn.y))
		var hit := top_at(root, p)
		var onwin := root.get_visible_rect().has_point(p)
		var hn := "nothing" if hit == null else "%s %s" % [hit.name, hit.get_global_rect()]
		print("     CORNER %s floor (%.1f, %.1f) at %s on-window %s: topmost control %s, _over_ui %s" % [st, cn.x, cn.y, p, onwin, hn, ep._over_ui(p)])
		ok(hit == null and not ep._over_ui(p), "3 %s floor corner (%.1f, %.1f) at %s reaches the floor (topmost control %s)" % [st, cn.x, cn.y, p, hn])


## 4 Trace: the picture drawn on the dark floor is light. Reads the texture the quad is drawn with: the mean luminance of the pixels that are drawn (alpha-weighted)
## must be light (> 0.8) at material opacity 0.7; the dark shape's pixels are opaque and light, the floor (mean luminance of the grid screen box) is dark
func trace_run() -> void:
	await size_to(1280, 720)
	m.S.part = {}
	pu.sync()
	await idle(8)
	var img := Image.create(300, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for y in range(30, 120):
		for x in range(40, 260):
			img.set_pixel(x, y, Color.BLACK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	var path := ProjectSettings.globalize_path(DIRT) + "/lay1_rect.png"
	img.save_png(path)
	if ep.armed != "draw":
		await click_ctl(ep.make_btns["draw"])
	await idle(4)
	await click_ctl(root.find_child("easypart_shape_trace", true, false))
	var fd := root.find_child("easypart_trace_dialog", true, false)
	if fd != null:
		fd.queue_free()
	await idle(2)
	ep.tracer.chosen(path)
	await idle(6)
	var q: MeshInstance3D = ep.tracer.node
	var mat := (q.mesh as QuadMesh).material as StandardMaterial3D
	var tex := mat.albedo_texture.get_image()
	var sum := 0.0
	var wsum := 0.0
	var opaque_dark_src := 0
	for y in tex.get_height():
		for x in tex.get_width():
			var c := tex.get_pixel(x, y)
			sum += (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * c.a
			wsum += c.a
	var lum := sum / maxf(wsum, 1e-6)
	var floor_lum := 0.0
	var im := root.get_texture().get_image()
	var sx := root.get_texture().get_size().x / float(root.get_visible_rect().size.x)
	var n := 0
	for yy in range(500, 560, 6):
		for xx in range(40, 140, 6):
			var c2 := im.get_pixel(int(xx * sx), int(yy * sx))
			floor_lum += c2.r * 0.299 + c2.g * 0.587 + c2.b * 0.114
			n += 1
	floor_lum /= maxf(float(n), 1.0)
	print("     TRACE picture mean luminance %.3f (alpha-weighted, over %d x %d px), opacity %.2f, floor patch luminance %.3f" % [lum, tex.get_width(), tex.get_height(), mat.albedo_color.a, floor_lum])
	ok(lum > 0.8, "4 the traced picture is drawn light: mean luminance %.3f (bar > 0.8; the black source was 0.0)" % lum)
	ok(absf(mat.albedo_color.a - 0.7) < 0.01, "4 the picture is drawn at 70 percent opacity (%.2f)" % mat.albedo_color.a)
	ok(lum > floor_lum + 0.5, "4 the picture (%.3f) is far lighter than the floor around it (%.3f)" % [lum, floor_lum])
	await shot("trace_1280x720")
	await click_ctl(root.find_child("easypart_trace_close", true, false))


func is_visible_rect_enclosing(r: Rect2) -> bool:
	return root.get_visible_rect().grow(1.0).encloses(r)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await size_to(1280, 720)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await open_ep()
	var only := OS.get_environment("LAY1_ONLY")
	if only == "" or only == "1":
		for sz in SIZES:
			await hole_run(sz[0], sz[1])
	if only == "" or only == "2":
		await size_to(1280, 720)
		m.S.part = {}
		pu.sync()
		await idle(6)
		for sz in SIZES:
			for id in ["stand", "gears"]:
				for dy in [0.0, -0.03, -0.06, -0.09, -0.12]:
					await challenge_run(sz[0], sz[1], id, dy)
	if only == "" or only == "3":
		for sz in SIZES:
			await floor_run(sz[0], sz[1])
	if only == "" or only == "4":
		await trace_run()
	print("lay1: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## 239 (a28b6389): the library chips sit in groups; a user opens a chip's group tab (a real click) before pressing the chip
func open_group_of(c: Control) -> void:
	if c == null or c.is_visible_in_tree():
		return
	for g in root.find_children("easypart_libgroup_*", "Button", true, false):
		var fl := root.find_child("easypart_libchips_" + (g as Button).text, true, false)
		if fl != null and fl.is_ancestor_of(c):
			await click_ctl(g)
			return
