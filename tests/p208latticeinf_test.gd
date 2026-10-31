extends SceneTree
## p208latticeinf (Friday plan item 208; Nick: light and strong; Kine's own idea): Lattice inside a hollow part. Hollow inside a box, then
## one click on "Lattice inside" fills the hollow with a light lattice of thin bars (a grid per layer, layers stacked up the box). The Gap
## slider sets how far apart the bars are. Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Draw shape Box, a square on the floor (80 mm) -> Pull it up to 80 mm -> Cut a hole -> Hollow inside (chip)
##   -> Lattice inside (button) -> the Gap slider dragged from 10 to 20 mm
## Bars (each one measured from the BUILT result in mm and m3: the replay volume and mesh rays, never the code's own variables).
## The expected numbers come from the box and the bars' own rule (bars 2 mm thick, the walls 3 mm, a layer every Gap mm, a bar every Gap mm):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the square Pulled up: one solid, 80 x 80 x 80 mm within 2 pct
##   2 Hollow inside: one body, the volume = outer - inner (3 mm wall, open top) = 90508 mm3 within 2 pct
##   3 Lattice inside (the button, shown only after Hollow inside): one press = one undo step, the volume grows (more material) and the
##     step's own row is a Gap slider (its label reads Gap)
##   4 Gap 10 mm: the added volume = 7 layers x (2 x 7 bars x 74 mm x 2 x 2 mm2 - 49 crossings x 8 mm3) = 26264 mm3 within 3 pct
##   5 a ray down a Gap bar (x 10 mm, z 5 mm in from the corner) from above hits the top layer's bar top at 71 mm height: 19 mm from the start (+-1.5)
##   6 the Lattice button is hidden now (it only shows on a fresh hollow): the press adds nothing twice
##   7 Gap dragged to 20 mm: the added volume = 3 layers x (2 x 3 x 74 x 4 - 9 x 8) = 5112 mm3 (within 3 pct), so the part is lighter than at 10 mm
##   8 the Gap drag is exactly 1 undo step
##   9 the step's words in the step list say lattice (EasyPart.step_words of the newest step)
## shots: C:/Temp/claude/p208latticeinf/

const SHOT_DIR := "C:/Temp/claude/p208latticeinf"
const DIRT := "user://p208latticeinf_test"

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
	await click_at(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var gw := _grab_w(s)
	var y := r.get_center().y
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


func ep():
	return pu().ep


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the built bounding box in mm
func bbox() -> AABB:
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


## the built mesh's triangles in world metres
func world_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi: MeshInstance3D = pu().part_mesh
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


## the NEAREST hit distance (mm) of a ray from o (metres) along unit d through the built mesh (Moller-Trumbore), or NAN when nothing is hit
func ray_first(o: Vector3, d: Vector3) -> float:
	var tris := world_tris()
	var best := INF
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var e1 := tris[k + 1] - a
		var e2 := tris[k + 2] - a
		var p := d.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-12:
			continue
		var s := o - a
		var u := s.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var v := d.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var tt := e2.dot(q) / det
		if tt > 1e-6 and tt < best:
			best = tt
	return best / Part.MM if best < INF else NAN


## the lattice's added volume (mm3) for a Gap of g mm in an 80 mm box with 3 mm walls: layers and bars every g mm, 2 mm bars
## (the expected numbers are the spec written out, not read from the code)
func lattice_added(g: float) -> float:
	var s := 2.0
	var inner := 74.0
	var n := 0
	var j := 1
	while float(j) * g < 80.0 - g * 0.5:
		n += 1
		j += 1
	var layers := 0
	var k := 1
	while float(k) * g < 80.0 - g * 0.5:
		layers += 1
		k += 1
	return float(layers) * (2.0 * float(n) * inner * s * s - float(n * n) * s * s * s)


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


func gap_row() -> HSlider:
	for r in ep().rows:
		if String(r.get("label", "")) == "Gap":
			return r["slider"] as HSlider
	return null


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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)

	# 1 a box: Draw shape (Box), a square on the floor, Pulled up to 80 mm by the slider
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.04)), scr(Vector3(0.04, 0.0, 0.04)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 8.0)
	var bb: AABB = bbox()
	var bodies: int = int(pu().res.get("bodies", 0))
	ok(bodies == 1 and absf(bb.size.x - 80.0) <= 1.6 and absf(bb.size.y - 80.0) <= 1.6 and absf(bb.size.z - 80.0) <= 1.6,
		"1 the square Pulled up: one solid, %.1f x %.1f x %.1f mm (solids %d)" % [bb.size.x, bb.size.y, bb.size.z, bodies])

	# 2 Cut a hole, then Hollow inside: outer - inner, the 3 mm wall, open at the top
	await click_ctl(ep().make_btns["hole"])
	var hollow_chip: Button = root.find_child("easypart_hole_hollow", true, false) as Button
	if hollow_chip != null:
		await click_ctl(hollow_chip)
	var v2: float = vol()
	var want2: float = 80.0 * 80.0 * 80.0 - 74.0 * 74.0 * 77.0
	ok(hollow_chip != null and int(pu().res.get("bodies", 0)) == 1 and absf(v2 - want2) <= want2 * 0.02,
		"2 Hollow inside: one body, volume %.0f mm3 = outer - inner (3 mm wall, open top) %.0f mm3 (within 2 pct)" % [v2, want2])
	await shot("01_hollow")

	# 3 Lattice inside: the button after the hollow, one press = one undo step, the part gets heavier and the step is a Gap slider
	var lat_btn: Button = root.find_child("easypart_hole_lattice", true, false) as Button
	var u_before: int = m.undo.size()
	var vol_hollow: float = vol()
	if lat_btn != null and lat_btn.visible:
		await click_ctl(lat_btn)
	var u_after: int = m.undo.size()
	var v3: float = vol()
	var gap_s: HSlider = gap_row()
	ok(lat_btn != null and gap_s != null and v3 > vol_hollow and u_after == u_before + 1 and int(pu().res.get("bodies", 0)) == 1,
		"3 Lattice inside: one undo step (%d -> %d), a Gap slider row, the part gets heavier %.0f -> %.0f mm3" % [u_before, u_after, vol_hollow, v3])
	await shot("02_lattice10")

	# 4 Gap 10 mm: the added volume is the spec's count (7 layers, 7 bars each way, the crossings counted once)
	var want4: float = lattice_added(10.0)
	ok(absf((v3 - vol_hollow) - want4) <= want4 * 0.03,
		"4 Gap 10 mm: added %.0f mm3 = 7 layers x (14 bars x 74 mm x 4 mm2 - 49 crossings x 8 mm3) %.0f mm3 (within 3 pct)" % [v3 - vol_hollow, want4])

	# 5 a ray down a Gap bar (x 10 mm, z 5 mm in from the corner) hits the top layer's bar at 71 mm height: 19 mm from a start at 90 mm
	var o5 := Vector3(bb.position.x + 10.0, bb.end.y + 10.0, bb.position.z + 5.0) * Part.MM
	var d5: float = ray_first(o5, Vector3.DOWN)
	ok(absf(d5 - 19.0) <= 1.5, "5 a ray down a Gap bar from above hits the top layer's bar at %.1f mm from the start (want 19)" % d5)

	# 6 the Lattice button is gone now (a second press would stack a second lattice): a press does nothing
	var vis_now: bool = lat_btn != null and lat_btn.is_visible_in_tree()
	ok(not vis_now, "6 the Lattice button is hidden after the lattice (no second lattice on top)")

	# 7 Gap dragged to 20 mm: fewer bars, so the part is lighter: the added volume is 3 layers x (6 bars x 74 x 4 - 9 x 8) = 5112 mm3
	var u_g: int = m.undo.size()
	if gap_s != null:
		await drag_slider(gap_s, 20.0)
	var u_g2: int = m.undo.size()
	var v7: float = vol()
	var want7: float = lattice_added(20.0)
	ok(gap_s != null and absf((v7 - vol_hollow) - want7) <= want7 * 0.03 and v7 < v3,
		"7 Gap 20 mm: added %.0f mm3 = 3 layers x (6 x 74 x 4 - 9 x 8) %.0f mm3 (within 3 pct), lighter than at 10 mm (%.0f < %.0f)" % [v7 - vol_hollow, want7, v7, v3])
	await shot("03_lattice20")

	# 8 the Gap drag is one undo step
	ok(u_g2 == u_g + 1, "8 the Gap drag adds exactly 1 undo step (undo %d -> %d)" % [u_g, u_g2])

	# 9 the step list words say lattice
	var newest: Dictionary = m.S.part["features"][-1]
	var words: String = String(ep().step_words(newest)).to_lower()
	ok(words.contains("lattice"), "9 the step's words say lattice (%s)" % words)

	print("P208LATTICEINF TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
