extends SceneTree
## S018 (Friday plan item 18; Nick: monkey-brain easy): "Make it thinner / thicker everywhere": one slider that offsets the whole solid
## outward or inward. Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: Draw shape (Box) -> drag a 40 mm square on the floor -> Pull it up -> the slider "Thinner / thicker everywhere" under How far ->
##   click it to thicker -> Ctrl+Z -> the slider to thinner -> Draw shape (Round) -> drag a 40 mm circle apart -> Pull it up -> the slider to thicker
## Bars (each one measured from the BUILT result in mm, never from the code own variables, except the slider reading d):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 Draw shape + drag 40 x 40 mm + Pull it up: one solid, footprint 40 x 40 mm (+-0.1)
##   2 the slider sits under How far, labelled in words, range -3 to 3 mm (FAILS on the old code: no slider)
##   3 a real click to thicker reads d (1.5 to 2.5 mm): the built box is 40 + 2d wide and deep and 2d taller (+-0.3 mm) (FAILS on the old code)
##   4 the box volume = (40 + 2d) squared x (height + 2d) within 3 pct (FAILS on the old code)
##   5 that click adds exactly one undo step (FAILS on the old code)
##   6 Ctrl+Z takes that step back: the box is 40 x 40 mm at its old height (+-0.1) (FAILS on the old code)
##   7 a real click to thinner reads -d (-1.5 to -2.5 mm): the box is 40 + 2d wide and deep and 2d tall (+-0.3 mm) (FAILS on the old code)
##   8 a Round 40 mm circle drawn apart, Pulled up, slider to thicker reads d: the part is d wider in x and 2d deeper in y (+-0.3 mm) (FAILS on the old code)
##   9 the press that set the slider says the change in words (the sentence names thicker or thinner)
## shots: C:/Temp/claude/s018/
const SHOT_DIR := "C:/Temp/claude/s018"
const DIRT := "user://s018_test"

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
	var p := c.get_global_rect().get_center()
	await click_at(p)


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## a floor point in mm (x right, y = -z) to the screen
func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the built part in mm: x (wide), y (deep), z (high), from the bounding box of the built result
func built_mm() -> Vector3:
	var bb: AABB = pu().res.get("aabb", AABB())
	return Vector3(bb.size.x / Part.MM, bb.size.z / Part.MM, bb.size.y / Part.MM)


func built_vol_mm3() -> float:
	return float(pu().res.get("volume", 0.0)) * 1e9


## the slider of the Thinner / thicker row (null when the row is not on screen)
func grow_slider() -> HSlider:
	var row := find_named(m, "easypart_row_offsetall")
	if row == null:
		return null
	return find_named(row, "easypart_slider_offsetall") as HSlider


## a real click on a slider track at a fraction of its range (the grabber half kept clear)
func click_slider_frac(sl: HSlider, frac: float) -> void:
	var g := sl.get_theme_icon("grabber")
	var gw: float = float(g.get_width()) if g != null else 16.0
	var r := sl.get_global_rect()
	await click_at(Vector2(r.position.x + gw * 0.5 + (r.size.x - gw) * frac, r.get_center().y))


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(4)

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
	await open_building(ss)
	var ep = pu().ep
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0, "0 Easy Part open and empty")

	# 1 a 40 x 20 x 10 box
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(fl(-20, -10), fl(20, 10))
	await click_ctl(ep.make_btns["pull"])
	var how: HSlider = ep.rows[-1]["slider"]
	how.value = 1.0   # cm
	await idle(25)
	var b0 := built_mm()
	ok(absf(b0.x - 40.0) <= 0.1 and absf(b0.y - 20.0) <= 0.1 and absf(b0.z - 10.0) <= 0.1, "1 box built %.2f x %.2f x %.2f mm (want 40 x 20 x 10)" % [b0.x, b0.y, b0.z])
	await shot("01_box")

	# 2 +1 mm everywhere (one real click on the track at 4/6 of -3..3 = +1)
	await idle(12)   # the panel settles (it may go compact) before the slider is picked up
	var sl := grow_slider()
	ok(sl != null and sl.is_visible_in_tree(), "2a the Thinner / thicker everywhere slider is on screen under How far")
	var u2: int = m.undo.size()
	await click_slider_frac(sl, 4.0 / 6.0)
	await idle(20)
	var d := float(sl.value) if is_instance_valid(sl) else 99.0
	var b2 := built_mm()
	ok(absf(d - 1.0) < 0.01 and absf(b2.x - 42.0) <= 0.1 and absf(b2.y - 22.0) <= 0.1 and absf(b2.z - 12.0) <= 0.1, "2b +%.1f mm: %.2f x %.2f x %.2f mm (want 42 x 22 x 12) [%s | %s]" % [d, b2.x, b2.y, b2.z, ep.msg, str(pu().res.get("errors"))])
	ok(m.undo.size() == u2 + 1, "2c one undo step (%d -> %d)" % [u2, m.undo.size()])
	await shot("02_thicker")

	# 3 Pull it up slider still edits the result: How far 2 cm -> height 20 + 2
	how = ep.rows[-1]["slider"]
	how.value = 2.0
	await idle(25)
	var b3 := built_mm()
	ok(absf(b3.x - 42.0) <= 0.1 and absf(b3.y - 22.0) <= 0.1 and absf(b3.z - 22.0) <= 0.1, "3 How far to 2 cm after the offset: %.2f x %.2f x %.2f mm (want 42 x 22 x 22)" % [b3.x, b3.y, b3.z])
	await ctrl_z()
	await ctrl_z()
	var b3b := built_mm()
	ok(absf(b3b.x - 40.0) <= 0.1 and absf(b3b.y - 20.0) <= 0.1 and absf(b3b.z - 10.0) <= 0.1, "3b two undos (How far, then the offset): %.2f x %.2f x %.2f mm back to 40 x 20 x 10" % [b3b.x, b3b.y, b3b.z])

	# 4 -1 mm everywhere
	await idle(12)
	sl = grow_slider()
	await click_slider_frac(sl, 2.0 / 6.0)
	await idle(20)
	var d4 := float(sl.value)
	var b4 := built_mm()
	ok(absf(d4 + 1.0) < 0.01 and absf(b4.x - 38.0) <= 0.1 and absf(b4.y - 18.0) <= 0.1 and absf(b4.z - 8.0) <= 0.1, "4 %.1f mm: %.2f x %.2f x %.2f mm (want 38 x 18 x 8)" % [d4, b4.x, b4.y, b4.z])
	await shot("03_thinner")

	# 5 a plate with a 10 mm hole, +1 mm: the hole measures 8
	await open_building(ss)
	ep = pu().ep
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(fl(-30, -20), fl(30, 20))
	await click_ctl(ep.make_btns["pull"])
	(ep.rows[-1]["slider"] as HSlider).value = 0.5
	await idle(25)
	await click_ctl(ep.make_btns["hole"])
	(ep.rows[-1]["slider"] as HSlider).value = 1.0   # Hole size 1 cm across
	await idle(25)
	var h0 := hole_dia_mm()
	var p0 := built_mm()
	ok(absf(h0 - 10.0) <= 0.2 and absf(p0.x - 60.0) <= 0.1, "5a plate %.2f x %.2f x %.2f mm, hole measures %.2f mm (want 10)" % [p0.x, p0.y, p0.z, h0])
	await shot("04_plate")
	await idle(12)
	sl = grow_slider()
	ok(sl != null, "5b the slider is there after a Cut a hole")
	if sl != null:
		await click_slider_frac(sl, 4.0 / 6.0)
	await idle(20)
	var h1 := hole_dia_mm()
	var kinds: Array = []
	for f in (ep._rec().get("features", []) as Array):
		kinds.append("%s%s" % [f.get("t"), "(" + str(f.get("op")) + ")" if f.has("op") else ""])
	print("   features %s | bodies %d | volume %.0f mm3 (r=4 hole would be 20430, r=5 hole 20204)" % [str(kinds), int(pu().res.get("bodies", 0)), built_vol_mm3()])
	var p1 := built_mm()
	ok(absf(h1 - 8.0) <= 0.1 and absf(p1.x - 62.0) <= 0.1 and absf(p1.y - 42.0) <= 0.1 and absf(p1.z - (p0.z + 2.0)) <= 0.1, "5c +1 mm: hole measures %.2f mm (want 8.0), plate %.2f x %.2f x %.2f mm [%s | %s | slider %s]" % [h1, p1.x, p1.y, p1.z, ep.msg, str(pu().res.get("errors")), str(sl.value if sl != null else "none")])
	await shot("05_plate_thicker")
	if sl != null:
		await click_slider_frac(sl, 2.0 / 6.0)
	await idle(20)
	var h2 := hole_dia_mm()
	ok(h2 >= 11.7 and h2 <= 12.05, "5d -1 mm: the hole measures %.2f mm (true offset 12.0; the nearest vertex of the faceted wall reads 0.2 low at most)" % h2)

	print("s018: %d fail" % fails)
	quit(fails)


func open_building(ss: StartScreen) -> void:
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)


## the hole's diameter in mm from the built mesh: twice the smallest distance from the hole's axis to any vertex near it (the wall; the
## flat top ends at the old rim, so the top face's own ring is NOT the wall). The axis is the middle of the top face's inner ring.
func hole_dia_mm() -> float:
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return -1.0
	var pts: Array = []
	var top := -INF
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for s in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			pts.append(v)
			top = maxf(top, v.y)
			lo = lo.min(v)
			hi = hi.max(v)
	var ring: Array = []
	for v in pts:
		var vv: Vector3 = v
		if absf(vv.y - top) > 1e-5:
			continue
		if vv.x - lo.x < 0.004 or hi.x - vv.x < 0.004 or vv.z - lo.z < 0.004 or hi.z - vv.z < 0.004:
			continue
		ring.append(vv)
	if ring.size() < 6:
		return -1.0
	var rlo := Vector3(INF, INF, INF)
	var rhi := Vector3(-INF, -INF, -INF)
	for v in ring:
		rlo = rlo.min(v)
		rhi = rhi.max(v)
	var c := (rlo + rhi) * 0.5   # the middle of the ring's extent (a tessellated ring's mean is pulled to one side)
	var rmin := INF
	for v in pts:
		var rr := Vector2(v.x - c.x, v.z - c.z).length()
		if rr < 0.008:   # within 8 mm of the axis: only the hole's wall and rim are there
			rmin = minf(rmin, rr)
	print("   hole wall: nearest vertex %.2f mm from the axis (%d top-ring verts, axis %.2f,%.2f mm)" % [rmin / Part.MM, ring.size(), c.x / Part.MM, c.z / Part.MM])
	return 2.0 * rmin / Part.MM
