extends SceneTree
## s042 (Friday plan 42): Star / Gear outline / Heart / Arrow quick shapes behind ONE "More shapes" chip in the Draw shape row.
## Real clicks at 1280 x 720 from the BUILDING card: Draw shape, More shapes, the shape's chip, a drag on the grid, Pull it up, How far 1 cm.
## Every number is measured from the BUILT mesh (top-cap vertices in mm), never from the code's own variables.
##   L1-3 the shape row is not wider/taller with the chip than without it; the More shapes panel overlaps no other control
##   per shape: one solid 10 mm high, ONE undo step for the drawing, the steps list names it (Drew a star ...), Ctrl+Z steps back
##   star  80 mm box: 5 tips, outer 40 / inner 16 mm within 0.2
##   gear  80 mm box, Teeth slider clicked to 17: 17 tips, tip radius 40 mm within 0.2
##   heart 80 mm box: mirror deviation of the outline < 0.1 mm
##   arrow 80 x 60 box: the head's two wings meet the tip at 90 degrees within 1
## shots: C:/Temp/claude/s042/
const SHOT := "C:/Temp/claude/s042"
const DIRT := "user://s042_test"
const JARGON := ["sketch", "extrude", "fillet", "feature", "kernel", "shell", "loft", "boolean", "profile"]
var fails := 0
var m: Node


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part, -1, {"faces": true, "props": true})


func mm(v: float) -> float:
	return v / Part.MM


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the newest step's slider (How far, How round, Thickness...), or null
func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


func last_label() -> String:
	var sl := last_slider()
	if sl == null:
		return ""
	for c in sl.get_parent().find_children("*", "Label", true, false):
		var t := String((c as Label).text)
		if t == "How far" or t == "How round" or t == "Thickness":
			return t
	return ""


func step_buttons() -> Array:
	var box := find_named(m, "easypart_steps")
	if box == null:
		return []
	return box.find_children("*", "Button", true, false)


## the plain words of the step list: one string per step row (the row's button text), in order
func step_words() -> Array:
	var out := []
	for b in step_buttons():
		out.append(String((b as Button).text))
	return out


func grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


## a real click on the slider's track at value v (the grabber centre sits at v; the track's ends keep half a grabber in)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := grab_w(sl)
	var frac := (v - sl.min_value) / (sl.max_value - sl.min_value)
	var lx := g * 0.5 + frac * (sl.size.x - g)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


## the solid's total volume (mm3), from the built bodies
func vol_mm3(s: Dictionary) -> float:
	var tot := 0.0
	for v in s.get("volumes", []):
		tot += float(v)
	return tot / (Part.MM * Part.MM * Part.MM)


## the loss of the rounds on the top four edges of a W x D box (mm3): (1 - pi/4) r^2 x the top perimeter
func round_loss(W: float, D: float, r: float) -> float:
	return (1.0 - PI / 4.0) * r * r * (2.0 * W + 2.0 * D)


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(20)




## the top cap of the solid: unique (x, z) of the vertices at the highest y, in mm
func cap_pts() -> Array:
	var res: Dictionary = solid()
	var mesh: ArrayMesh = res["mesh"]
	var vs := PackedVector3Array()
	for si in mesh.get_surface_count():
		vs.append_array(mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	var ymax := -INF
	for v in vs:
		ymax = maxf(ymax, v.y)
	var out := []
	for v in vs:
		if absf(v.y - ymax) < 1e-5:
			var q := Vector2(mm(v.x), mm(v.z))
			var dup := false
			for o in out:
				if (o as Vector2).distance_to(q) < 0.01:
					dup = true
					break
			if not dup:
				out.append(q)
	return out


func centre_of(pts: Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / float(pts.size())


## [angle, radius] of the outline points sorted by angle round c
func radii_by_angle(pts: Array, c: Vector2) -> Array:
	var items := []
	for p in pts:
		items.append([((p as Vector2) - c).angle(), ((p as Vector2) - c).length()])
	items.sort_custom(func(a, b): return a[0] < b[0])
	return items


## runs of consecutive (round the circle) items whose radius is above lim
func runs_above(items: Array, lim: float) -> int:
	var n := items.size()
	var start := -1
	for i in n:
		if float(items[i][1]) <= lim:
			start = i
			break
	if start < 0:
		return 1
	var runs := 0
	var prev := false
	for k in range(1, n + 1):
		var hi := float(items[(start + k) % n][1]) > lim
		if hi and not prev:
			runs += 1
		prev = hi
	return runs


func local_maxima(items: Array) -> int:
	var n := items.size()
	var c := 0
	for i in n:
		var r := float(items[i][1])
		if r > float(items[(i + n - 1) % n][1]) + 1e-6 and r > float(items[(i + 1) % n][1]) + 1e-6:
			c += 1
	return c


func leaf_overlap(a: Control, bs: Array) -> String:
	var ra := a.get_global_rect()
	for b in bs:
		if b == null or not (b as Control).is_visible_in_tree() or b == a:
			continue
		if ra.intersection((b as Control).get_global_rect()).get_area() > 4.0:
			return String(b.name)
	return ""


func draw_quick(ep, sh: String, hw: float, hh: float, teeth := 0) -> Dictionary:
	if ep.armed != "draw":
		await click_ctl(ep.make_btns["draw"])
	if not ep.quick_box.visible:
		await click_ctl(ep.quick_chip)
	if teeth > 0:
		var sl: HSlider = find_named(ep.quick_box, "easypart_quick_teeth")
		await slide_to(sl, float(teeth))
	await click_ctl(ep.quick_btns[sh])
	await idle(3)
	var u0: int = m.undo.size()
	await drag_pts([scr(Vector3(-hw, 0.0, -hh)), scr(Vector3(hw, 0.0, hh))])
	var drew: int = m.undo.size() - u0
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await slide_to(last_slider(), 1.0)
	return {"undo": drew}


## a blank record for the next shape (the earlier shape is cleared; the app's own start-over)
func fresh_part(ep) -> void:
	m.S.part["features"] = []
	m.S.part["seq"] = 0
	ep.pu.upto = -1
	ep.pu.sync()
	ep._rows_sync()
	await idle(10)

func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and note_words.find("Easy") >= 0,
		"S0a BUILDING card, one click, a blank part, words name Easy (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)


	# L the row with and without the chip
	await click_ctl(ep.make_btns["draw"])
	await idle(6)
	var sb: Control = ep.shape_box
	ep.quick_chip.visible = false
	ep.layout(ep._cl)
	await idle(6)
	var r0 := sb.get_global_rect()
	ep.quick_chip.visible = true
	ep.layout(ep._cl)
	await idle(6)
	var r1 := sb.get_global_rect()
	ok(r1.size.x <= r0.size.x + 0.5 and r1.size.y <= r0.size.y + 0.5 and r1.position.is_equal_approx(r0.position),
		"L1 the shape row with the More shapes chip is %s, without it %s (not wider, not taller)" % [str(r1.size), str(r0.size)])
	var in_view: bool = Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(ep.quick_chip.get_global_rect())
	var inside: bool = ep.quick_chip.get_global_rect().end.x <= sb.get_global_rect().end.x + 0.5
	ok(in_view and inside, "L2 the More shapes chip %s is inside the row %s and the window" % [str(ep.quick_chip.get_global_rect()), str(sb.get_global_rect())])
	await click_ctl(ep.quick_chip)
	await idle(4)
	var vb_hit: bool = ep.quick_chip.get_global_rect().intersection(ep.view_box.get_global_rect()).get_area() > 4.0
	ok(not vb_hit, "L2b the More chip is not under the view column (chip %s, view column %s)" % [str(ep.quick_chip.get_global_rect()), str(ep.view_box.get_global_rect())])
	var qb: Control = ep.quick_box
	var others: Array = [ep.make_box, ep.hint, ep.panel, ep.view_box, ep.status, sb]
	var hit: String = leaf_overlap(qb, others)
	ok(qb.visible and hit == "" and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(qb.get_global_rect()),
		"L3 the More shapes panel %s is open, in the window, and overlaps no other control (hit [%s])" % [str(qb.get_global_rect()), hit])
	await shot("more_shapes")

	var cases := [["star", 0.04, 0.04, 0], ["gear", 0.04, 0.04, 17], ["heart", 0.04, 0.04, 0], ["arrow", 0.04, 0.03, 0]]
	for cs in cases:
		var sh := String(cs[0])
		await fresh_part(ep)
		var d: Dictionary = await draw_quick(ep, sh, float(cs[1]), float(cs[2]), int(cs[3]))
		var s := solid()
		var bb: AABB = s["aabb"]
		ok(int(s["bodies"]) == 1 and absf(mm(bb.size.y) - 10.0) <= 0.3,
			"%s built: %d solid, %.2f mm high (want 1 solid, 10 +-0.3)" % [sh, int(s["bodies"]), mm(bb.size.y)])
		ok(int(d["undo"]) == 1, "%s the drawing is ONE undo step (%d)" % [sh, int(d["undo"])])
		var pts := cap_pts()
		var c := centre_of(pts)
		var items := radii_by_angle(pts, c)
		match sh:
			"star":
				var rmax := 0.0
				var rmin := INF
				var outer := 0
				var inner := 0
				for it in items:
					rmax = maxf(rmax, float(it[1]))
					rmin = minf(rmin, float(it[1]))
					if absf(float(it[1]) - 40.0) <= 0.2:
						outer += 1
					if absf(float(it[1]) - 16.0) <= 0.2:
						inner += 1
				ok(items.size() == 10 and local_maxima(items) == 5 and outer == 5 and inner == 5,
					"star: %d outline points, %d tips, %d at outer 40 mm, %d at inner 16 mm (radii %.2f / %.2f, 0.2 mm)" % [items.size(), local_maxima(items), outer, inner, rmax, rmin])
			"gear":
				var rmax2 := 0.0
				for it in items:
					rmax2 = maxf(rmax2, float(it[1]))
				var tips := runs_above(items, rmax2 * 0.9)
				ok(tips == 17 and absf(rmax2 - 40.0) <= 0.2,
					"gear: Teeth slider at 17 -> %d tips, tip radius %.2f mm (want 17, 40 +-0.2)" % [tips, rmax2])
			"heart":
				var lo := INF
				var hi := -INF
				for p in pts:
					lo = minf(lo, (p as Vector2).x)
					hi = maxf(hi, (p as Vector2).x)
				var mid := (lo + hi) * 0.5
				var dev := 0.0
				for p in pts:
					var mp := Vector2(2.0 * mid - (p as Vector2).x, (p as Vector2).y)
					var best := INF
					for q in pts:
						best = minf(best, mp.distance_to(q))
					dev = maxf(dev, best)
				ok(dev < 0.1 and hi - lo > 40.0 and pts.size() >= 30,
					"heart: mirror deviation %.4f mm over %d outline points, %.1f mm wide (want < 0.1)" % [dev, pts.size(), hi - lo])
			"arrow":
				var tip := Vector2(-INF, 0.0)
				for p in pts:
					if (p as Vector2).x > tip.x:
						tip = p
				var w1 := Vector2.ZERO
				var w2 := Vector2.ZERO
				var m1 := 0.0
				var m2 := 0.0
				for p in pts:
					var dz := (p as Vector2).y - tip.y
					if dz > m1:
						m1 = dz
						w1 = p
					if -dz > m2:
						m2 = -dz
						w2 = p
				var ang := rad_to_deg((w1 - tip).angle_to(w2 - tip))
				ok(absf(absf(ang) - 90.0) <= 1.0 and absf(m1 - 30.0) <= 0.2 and absf(m2 - 30.0) <= 0.2,
					"arrow: head angle %.3f degrees at the tip (want 90 +-1), wings %.2f / %.2f mm off the axis (want 30)" % [absf(ang), m1, m2])
		var named := false
		var want := String({"star": "drew a star", "gear": "drew a gear outline", "heart": "drew a heart", "arrow": "drew an arrow"}[sh])
		for w in step_words():
			if String(w).to_lower().find(want) >= 0:
				named = true
		ok(named, "%s the Your steps list names it: %s (list %s)" % [sh, want, str(step_words())])
		await shot(sh)
		var n0: int = m.undo.size()
		await ctrl_z()
		await ctrl_z()
		ok(m.undo.size() < n0, "%s Ctrl+Z steps back (undo %d -> %d)" % [sh, n0, m.undo.size()])

	print("s042: %d fail" % fails)
	quit(1 if fails > 0 else 0)
