extends SceneTree
## p207knurlingon (Friday plan item 207, Kine's own idea): a knurled grip, a round handle with flutes along it. Easy Part > Parts > Handles
## has a "Knurled grip" row (24, 32, 40 mm); one click puts it on the floor, its "Grip texture" slider sets how deep the flutes cut (mm).
## Real clicks at 1280 x 720 from the real start screen, on the live Easy Part. Every number is measured from the BUILT mesh (the bottom ring
## of the solid, metres -> mm), never from the code's own variables.
##   S0 Parts, then the Handles category: the Knurled grip row shows its three sizes, all on screen (1280 x 720)
##   S1 a click on 32 mm: one solid, built height 120 mm (+-1), across X and Z 32 mm (+-0.5)
##   S2 the flutes, counted on the built bottom ring: 26..30 crests (pi x 32 / 3.5 mm = 28.7), each crest about 3.6 mm apart (3.0..4.2 mm)
##   S3 the default Grip texture 0.6 mm: the ring's radius runs 0.6 mm from crest to root (+-0.1)
##   S4 the Grip texture slider dragged to 1.2 mm by a click on its track: the ring runs 1.2 mm (+-0.1), ONE undo step
##   S5 Ctrl+Z takes it back: 0.6 mm again
##   S6 a click on 24 mm (on the floor already): across X 24 mm (+-0.5), 18..22 crests, ONE undo step
## shots: C:/Temp/claude/p207knurlingon/grip.png
const SHOT := "C:/Temp/claude/p207knurlingon"
const DIRT := "user://p207knurlingon_test"
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


## real mouse-wheel scrolling of the panel that holds c, until c's centre is inside it (up first, then down)
func into_view(c: Control) -> void:
	var sc := scroll_of(c)
	if sc == null:
		return
	for i in 40:
		if sc.get_global_rect().has_point(c.get_global_rect().get_center()):
			return
		await wheel_at(sc.get_global_rect().get_center(), i >= 20)


## a real mouse-wheel tick over p (the panel scrolls); down = false scrolls up
func wheel_at(p: Vector2, down := true) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e, true)
	await idle(3)


## the ScrollContainer that holds control c, or null
func scroll_of(c: Control) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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


## a real click on the slider's track at value v (the grabber centre sits at v; the track's ends keep half a grabber in)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := 16.0
	var gt := sl.get_theme_icon("grabber")
	if gt != null:
		g = float(gt.get_width())
	var frac := (v - sl.min_value) / (sl.max_value - sl.min_value)
	var lx := g * 0.5 + frac * (sl.size.x - g)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


## the bottom ring of the built solid, read off the mesh: the crest count (distinct outline vertices that
## reach over the mean radius, going round the axis), the radius range (mm) and the X / Z size (mm)
func ring(s: Dictionary) -> Dictionary:
	var out := {"n": 0, "rmin": 0.0, "rmax": 0.0, "x": 0.0, "z": 0.0, "y": 0.0}
	var mesh: Mesh = s.get("mesh") as Mesh
	if mesh == null:
		return out
	var bb: AABB = s["aabb"]
	var cx := bb.get_center().x
	var cz := bb.get_center().z
	var y0 := bb.position.y
	out["x"] = mm(bb.size.x)
	out["z"] = mm(bb.size.z)
	out["y"] = mm(bb.size.y)
	var seen := {}
	var pts: Array = []   # Vector3(angle, r, 0) in mm and radians
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		for v in arr[Mesh.ARRAY_VERTEX]:
			var vv: Vector3 = v
			if absf(vv.y - y0) > 0.0005:   # 0.5 mm: the bottom cap only
				continue
			var x := vv.x - cx
			var z := vv.z - cz
			var key := "%d,%d" % [roundi(x * 1e5), roundi(z * 1e5)]
			if seen.has(key):
				continue
			seen[key] = true
			var r := Vector2(x, z).length()
			if r < 1e-4:   # the cap's centre, not on the outline
				continue
			pts.append(Vector2(atan2(z, x), mm(r)))
	if pts.is_empty():
		return out
	pts.sort_custom(func(a, b): return a.x < b.x)
	var rmin := INF
	var rmax := -INF
	for p in pts:
		rmin = minf(rmin, p.y)
		rmax = maxf(rmax, p.y)
	var mean := (rmin + rmax) * 0.5
	var n := 0
	for i in pts.size():
		var a: float = pts[i - 1].y
		var b: float = pts[i].y
		if a < mean and b >= mean:
			n += 1
	out["n"] = n
	out["rmin"] = rmin
	out["rmax"] = rmax
	return out


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
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open,
		"S-1 BUILDING card, one click (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(30)

	# S0 Parts, then Handles: the Knurled grip row and its three sizes, on screen
	await click_ctl(ep.parts_btn)
	await click_ctl(ep.lib_btns["Handles"])
	await idle(10)
	# the Knurled grip row is the 4th row of the Handles grid, below the fold of the scrolling panel: a beginner scrolls it (real wheel)
	var sc := scroll_of(ep.handle_btns["grip_32"] as Control)
	for i in 14:
		if sc == null or sc.get_global_rect().has_point((ep.handle_btns["grip_32"] as Control).get_global_rect().get_center()):
			break
		await wheel_at(sc.get_global_rect().get_center())
	var row_ok := sc != null
	var lowest := 0.0
	for s in [24, 32, 40]:
		var b: Button = ep.handle_btns.get("grip_%d" % s) as Button
		if b == null or sc == null or not sc.get_global_rect().has_point(b.get_global_rect().get_center()):
			row_ok = false
		else:
			lowest = maxf(lowest, b.get_global_rect().end.y)
	var named := find_named(m, "easypart_handle_box")
	var has_name := named != null and named.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == "Knurled grip")
	ok(row_ok and has_name and lowest <= 720.0,
		"S0 Parts > Handles: after a wheel scroll the Knurled grip row shows 24, 32, 40 mm, on screen (lowest button at y %.0f of 720)" % lowest)

	# S1 a click on 32 mm: one solid, 120 mm tall, 32 mm across
	var ub1: int = m.undo.size()
	await click_ctl(ep.handle_btns["grip_32"])
	await idle(10)
	var s1 := solid()
	var r1 := ring(s1)
	ok(int(s1["bodies"]) == 1 and absf(float(r1["y"]) - 120.0) <= 1.0 and absf(float(r1["x"]) - 32.0) <= 0.5 and absf(float(r1["z"]) - 32.0) <= 0.5,
		"S1 a click on 32 mm: %d body, built height %.2f mm (want 120 +-1), across X %.2f and Z %.2f mm (want 32 +-0.5)" % [int(s1["bodies"]), float(r1["y"]), float(r1["x"]), float(r1["z"])])
	await shot("grip")

	# S2 the flutes, counted on the built bottom ring
	var circ_spacing := 2.0 * PI * float(r1["rmax"]) / maxf(float(r1["n"]), 1.0)
	ok(int(r1["n"]) >= 26 and int(r1["n"]) <= 30 and circ_spacing >= 3.0 and circ_spacing <= 4.2,
		"S2 the flutes on the built ring: %d crests (want 26..30), about %.2f mm apart (want 3.0..4.2)" % [int(r1["n"]), circ_spacing])

	# S3 the default texture 0.6 mm: the ring runs 0.6 mm from crest to root
	var depth1 := float(r1["rmax"]) - float(r1["rmin"])
	ok(absf(depth1 - 0.6) <= 0.1,
		"S3 the default Grip texture: the ring runs %.2f mm from crest to root (want 0.6 +-0.1)" % depth1)

	# S4 the Grip texture slider to 1.2 mm by a click on its track
	var tex_sl := find_named(m, "easypart_slider_texture") as HSlider
	if tex_sl != null:
		await into_view(tex_sl)
	var ub4: int = m.undo.size()
	await slide_to(tex_sl, 1.2)
	var r4 := ring(solid())
	var depth4 := float(r4["rmax"]) - float(r4["rmin"])
	ok(tex_sl != null and absf(depth4 - 1.2) <= 0.1 and m.undo.size() == ub4 + 1,
		"S4 Grip texture to 1.2 mm: the ring runs %.2f mm (want 1.2 +-0.1), undo %d -> %d (one step)" % [depth4, ub4, m.undo.size()])

	# S5 Ctrl+Z takes it back to 0.6 mm
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(20)
	var r5 := ring(solid())
	var depth5 := float(r5["rmax"]) - float(r5["rmin"])
	ok(absf(depth5 - 0.6) <= 0.1,
		"S5 Ctrl+Z: the ring runs %.2f mm again (want 0.6 +-0.1)" % depth5)

	# S6 24 mm, on the floor already: a click on the size changes the width, one undo step
	var ub6: int = m.undo.size()
	await click_ctl(ep.handle_btns["grip_24"])
	await idle(10)
	var r6 := ring(solid())
	ok(absf(float(r6["x"]) - 24.0) <= 0.5 and int(r6["n"]) >= 18 and int(r6["n"]) <= 22 and m.undo.size() == ub6 + 1,
		"S6 a click on 24 mm: across X %.2f mm (want 24 +-0.5), %d crests (want 18..22), undo %d -> %d" % [float(r6["x"]), int(r6["n"]), ub6, m.undo.size()])

	print("P207KNURLINGON %d fails" % fails)
	quit(1 if fails > 0 else 0)
