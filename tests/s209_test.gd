extends SceneTree
## s209 Make it stackable + s210 Label maker (Friday plan 209, 210). Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## 209: BUILDING card -> Draw shape Box (80 mm square) -> Pull it up to 80 mm -> Cut a hole -> Hollow inside (3 mm wall) -> Make it stackable.
##   1 the chip shows after the hollow; 2 one press = one undo step, still ONE solid; 3 the lip hangs under the floor: its outside
##   (measured from the mesh) = the rim's inside (measured from the mesh) - 2 x 0.3 mm within 0.02 mm, both ways, and the rim's inside is 74 mm
##   (80 - 2 x 3); 4 two copies, the second raised by the box's height (rim to rim): the kernel's common volume < 0.1 mm3, the lip stands >= 2 mm
##   inside the first rim; a control copy raised 1 mm less DOES collide (the check can fail); 5 the chip is gone after; 6 Undo takes the lip off.
## 210: Parts -> Type it page -> Label row: BOLTS, Make label: ONE solid, one undo step, 2 mm tag + 1 mm letters; BOLTSBOLTS is wider (about 2x);
##   the letters are in the volume and in the screenshot (pixels of the tag that are not the tag's flat colour); Cut in: one solid, lighter than the plain tag.
## shots: C:/Temp/claude/s209/

const SHOT_DIR := "C:/Temp/claude/s209"
const DIRT := "user://s209_test"
const KCad := preload("res://scripts/kcad.gd")

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


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0



## the built mesh vertices in mm
func verts() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out.append(v / Part.MM)
	return out


## [min x, max x, min z, max z] of the vertices whose y passes the test (and that lie strictly inside the box inside_of = x lo, x hi, z lo, z hi)
func extent(vs: PackedVector3Array, y_lo: float, y_hi: float, inside_of := Vector4(-1e9, 1e9, -1e9, 1e9)) -> Array:
	var r := [INF, -INF, INF, -INF]
	for p in vs:
		if p.y < y_lo or p.y > y_hi or p.x <= inside_of.x or p.x >= inside_of.y or p.z <= inside_of.z or p.z >= inside_of.w:
			continue
		r = [minf(r[0], p.x), maxf(r[1], p.x), minf(r[2], p.z), maxf(r[3], p.z)]
	return r


func lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## the share of pixels in the label's screen box that differ from the tag's flat colour (the median) by more than 0.05
func ink_share(img: Image) -> float:
	var bb: AABB = bbox()
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for cx in [bb.position.x, bb.end.x]:
		for cz in [bb.position.z, bb.end.z]:
			var s := scr(Vector3(cx, bb.end.y, cz) * Part.MM)
			lo = lo.min(s)
			hi = hi.max(s)
	var shrink := (hi - lo) * 0.12
	lo += shrink
	hi -= shrink
	var vals := []
	for y in range(int(lo.y), int(hi.y)):
		for x in range(int(lo.x), int(hi.x)):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				vals.append(lum(img.get_pixel(x, y)))
	if vals.size() < 100:
		return 0.0
	var sorted := vals.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2]
	var n := 0
	for v in vals:
		if absf(float(v) - med) > 0.05:
			n += 1
	return float(n) / vals.size()


func make_label(txt: String, cut: bool) -> void:
	var ed: LineEdit = root.find_child("easypart_label_edit", true, false)
	var md: Button = root.find_child("easypart_label_mode", true, false)
	var go: Button = root.find_child("easypart_label_go", true, false)
	ed.text = txt
	if md.button_pressed != cut:
		await click_ctl(md)
	await click_ctl(go)
	await idle(120)


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
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# a hollow box: 80 mm square pulled up 80 mm, hollow with the 3 mm wall
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.04)), scr(Vector3(0.04, 0.0, 0.04)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 8.0)
	await click_ctl(ep().make_btns["hole"])
	var hollow_chip: Button = root.find_child("easypart_hole_hollow", true, false) as Button
	if hollow_chip != null:
		await click_ctl(hollow_chip)
	var stack_chip: Button = root.find_child("easypart_hole_stack", true, false) as Button
	var bb0: AABB = bbox()
	ok(hollow_chip != null and int(pu().res.get("bodies", 0)) == 1 and absf(bb0.size.x - 80.0) <= 1.6 and absf(bb0.size.y - 80.0) <= 1.6,
		"0 a hollow box, one solid, %.1f x %.1f x %.1f mm" % [bb0.size.x, bb0.size.y, bb0.size.z])
	ok(stack_chip != null and stack_chip.is_visible_in_tree(), "1 the Make it stackable chip shows after Hollow inside")
	await shot("01_hollow_chip")
	var H: float = bb0.end.y - bb0.position.y
	var y0: float = bb0.position.y

	# 2 one press, one undo step, still one solid
	var u0: int = m.undo.size()
	var vol_before: float = vol()
	if stack_chip != null and stack_chip.is_visible_in_tree():
		await click_ctl(stack_chip)
	await idle(10)
	var bb1: AABB = bbox()
	ok(m.undo.size() == u0 + 1 and int(pu().res.get("bodies", 0)) == 1 and vol() > vol_before and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"2 Make it stackable: ONE undo step (%d -> %d), one solid, heavier %.0f -> %.0f mm3" % [u0, m.undo.size(), vol_before, vol()])
	await shot("02_stackable")

	# 3 the lip's outside = the rim's inside - 0.6 mm, both ways, read from the mesh
	var vs := verts()
	var lip_ext := extent(vs, -1e9, y0 - 0.01)
	var rim_ext := extent(vs, bb1.end.y - 0.05, bb1.end.y + 0.05, Vector4(bb1.position.x + 0.05, bb1.end.x - 0.05, bb1.position.z + 0.05, bb1.end.z - 0.05))
	var lip_w: float = lip_ext[1] - lip_ext[0]
	var lip_d: float = lip_ext[3] - lip_ext[2]
	var rim_w: float = rim_ext[1] - rim_ext[0]
	var rim_d: float = rim_ext[3] - rim_ext[2]
	var lip_h: float = y0 - bb1.position.y
	ok(absf(lip_w - (rim_w - 0.6)) <= 0.02 and absf(lip_d - (rim_d - 0.6)) <= 0.02,
		"3 lip outside %.3f x %.3f mm = rim inside %.3f x %.3f minus 0.6 (within 0.02)" % [lip_w, lip_d, rim_w, rim_d])
	ok(absf(rim_w - 74.0) <= 0.3 and absf(rim_d - 74.0) <= 0.3 and lip_h >= 2.0, "3 the rim's inside is 74 mm (80 - 2 x 3 mm wall): %.2f x %.2f; the lip is %.2f mm tall" % [rim_w, rim_d, lip_h])

	# 4 two copies, the second raised by the box's height: no common volume, the lip stands inside the rim
	var res := Part.replay(m.S.part, -1, {"keep": true})
	var ids: Array = res["ids"]
	var a: int = ids[0]
	var b: int = KCad.translate(a, Vector3(0.0, H * Part.MM, 0.0))
	var com: int = KCad.intersect(a, b)
	var common_mm3: float = (KCad.volume(com) if com != 0 else 0.0) / (Part.MM * Part.MM * Part.MM)
	var rim_top: float = bb1.end.y
	var lowest2: float = bb1.position.y + H
	var overlap: float = rim_top - lowest2
	ok(common_mm3 < 0.1 and overlap >= 2.0, "4 two copies, the second raised by %.1f mm: common volume %.4f mm3 (< 0.1), the lip stands %.2f mm inside the rim (>= 2)" % [H, common_mm3, overlap])
	var b2: int = KCad.translate(a, Vector3(0.0, (H - 1.0) * Part.MM, 0.0))
	var com2: int = KCad.intersect(a, b2)
	var common2: float = (KCad.volume(com2) if com2 != 0 else 0.0) / (Part.MM * Part.MM * Part.MM)
	ok(common2 > 1.0, "4 control: the second copy raised 1 mm less DOES touch (common %.1f mm3), so the check can fail" % common2)
	for id in [a, b, b2, com, com2]:
		if int(id) != 0:
			KCad.release(int(id))

	# 5 the chip is gone after, 6 Undo takes the lip off
	ok(stack_chip != null and not stack_chip.is_visible_in_tree(), "5 the chip is hidden after the lip (no second lip)")
	m._undo()
	await idle(10)
	var bb2: AABB = bbox()
	ok(absf(bb2.position.y - y0) <= 0.05 and absf(vol() - vol_before) <= 1.0, "6 one Undo takes the lip off (lowest %.2f, volume %.0f)" % [bb2.position.y, vol()])

	# 210 LABEL: Parts -> Type it page -> the Label row
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	if pb != null:
		await click_ctl(pb)
	var tb := root.find_child("easypart_lib_Type it", true, false) as Button
	if tb != null:
		await click_ctl(tb)
	var row := root.find_child("easypart_label_row", true, false) as Control
	ok(row != null and row.is_visible_in_tree(), "7 the Label row shows on the Parts > Type it page")
	var u1: int = m.undo.size()
	await make_label("BOLTS", false)
	var bb5: AABB = bbox()
	var v5: float = vol()
	var plate5: float = bb5.size.x * bb5.size.z * 2.0
	ok(int(pu().res.get("bodies", 0)) == 1 and m.undo.size() == u1 + 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
		"8 BOLTS: ONE solid, one undo step (%d -> %d), %.1f x %.1f x %.1f mm" % [u1, m.undo.size(), bb5.size.x, bb5.size.z, bb5.size.y])
	ok(absf(bb5.size.y - 3.0) <= 0.05 and v5 - plate5 > 20.0 and v5 - plate5 < 0.6 * plate5,
		"8 a 2 mm tag with 1 mm letters: height %.2f mm, letters add %.0f mm3 over the plain tag %.0f" % [bb5.size.y, v5 - plate5, plate5])
	var top_pts := 0
	for p in verts():
		if absf(p.y - bb5.end.y) < 0.02:
			top_pts += 1
	ok(top_pts >= 60, "8 the letters' tops: %d mesh points at the top height" % top_pts)
	await idle(10)
	var share5 := ink_share(root.get_texture().get_image())
	await shot("03_bolts")
	ok(share5 >= 0.04, "9 the text shows in the screenshot: %.1f pct of the tag's pixels are not its flat colour (>= 4)" % (share5 * 100.0))
	await make_label("BOLTSBOLTS", false)
	var bb10: AABB = bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and bb10.size.x > bb5.size.x * 1.6 and bb10.size.x < bb5.size.x * 2.1,
		"10 BOLTSBOLTS: one solid, width %.1f vs BOLTS %.1f mm (grows with the text, 1.6 to 2.1 x)" % [bb10.size.x, bb5.size.x])
	await shot("04_bolts_long")
	await make_label("BOLTS", true)
	var bbc: AABB = bbox()
	var vc: float = vol()
	var platec: float = bbc.size.x * bbc.size.z * 3.0
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bbc.size.y - 3.0) <= 0.05 and platec - vc > 20.0 and platec - vc < 0.5 * platec and absf(bbc.size.x - bb5.size.x) <= 0.2,
		"11 BOLTS cut in: one solid, 3 mm tag, letters cut away %.0f mm3 of %.0f, same width %.1f" % [platec - vc, platec, bbc.size.x])
	await idle(10)
	var sharec := ink_share(root.get_texture().get_image())
	await shot("05_bolts_cut")
	ok(sharec >= 0.04, "12 the cut-in text shows in the screenshot: %.1f pct (>= 4)" % (sharec * 100.0))
	print("s209: %d fail" % fails)
	quit(1 if fails > 0 else 0)
