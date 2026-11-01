extends SceneTree
## godot --path . -s tests/s102_test.gd   (S102 X-ray + S104 Turntable: two view toggles beside the ViewCube menus; Part workspace, needs the CAD DLL)
## Bars (real clicks on the two buttons; measured from the pixels, the material and the camera):
##   1 BUTTONS   both toggles are on screen at 1280 x 720, off at the start, and cover no other button
##   2 XRAY      a 40 x 40 x 30 mm box with a blind hole (12 mm square, 15 deep): the pixel at the hole's screen position differs from X-ray off by
##               more than 0.05 (colour distance), the part's material alpha is < 1; hidden edges are drawn (edge node has lines)
##   3 RESTORE   X-ray off: the material is identical (albedo, alpha, transparency) to before, and the pixel is back to the same colour
##   4 TURN      turntable at 10 s/rev: the camera yaw advances 36 +- 3 deg over 1 s of frames; off: the yaw stops (< 0.5 deg in 0.5 s)
##   5 RECORD    the record JSON and the undo count are the same after all of it
## Shots: C:/Temp/claude/s102/off.png, xray.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s102"
const DIRT := "user://s102_test"
var pu: PartUI


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
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


var view_t := Vector3.ZERO


## the same camera for every picture (Easy's follow drifts it between frames): set it, let one frame pass, then read the screen
func shot(nm: String) -> Image:
	m._turn_to(90.0, 0.0, 0.12, view_t, false)
	await idle(2)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var im := root.get_texture().get_image()
	im.save_png("%s/%s.png" % [SHOT, nm])
	return im


## the mean colour of a 7 x 7 patch at a world point's screen position
func patch(im: Image, w: Vector3) -> Color:
	var sp: Vector2 = m.cam.unproject_position(w)
	var k := Vector2(im.get_size()) / m.get_viewport().get_visible_rect().size
	var c := Vector2i(int(sp.x * k.x), int(sp.y * k.y))
	var s := Color(0, 0, 0, 0)
	var n := 0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var q := c + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < im.get_width() and q.y < im.get_height():
				s += im.get_pixel(q.x, q.y)
				n += 1
	return s / float(maxi(n, 1))


func cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func mat_sig() -> String:
	var out := []
	var me: ArrayMesh = pu.part_mesh.mesh
	for s in me.get_surface_count():
		var mt := pu.part_mesh.get_surface_override_material(s) as StandardMaterial3D
		out.append([mt.albedo_color.to_html(true), mt.transparency, mt.roughness, mt.metallic] if mt != null else "none")
	return JSON.stringify(out)


func mat_alpha() -> float:
	var mt := pu.part_mesh.get_surface_override_material(0) as StandardMaterial3D
	return mt.albedo_color.a if mt != null else -1.0


func build_rec(sign: float) -> Dictionary:
	var rec := Part.make("S102")
	var sk := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [-20.0, 0.0], "b": [20.0, 40.0]}], "dims": []})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": 30.0 * sign, "both": false, "op": "new"}))
	var s2 := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [-6.0, 14.0], "b": [6.0, 26.0]}], "dims": []})
	rec["features"].append(s2)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": 15.0 * sign, "both": false, "op": "cut"}))
	return rec


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
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	# the box with a blind hole: try the extrude direction that leaves a hole (volume less than the full box)
	var want_v := 40.0 * 40.0 * 30.0 - 144.0 * 15.0
	m.S.part = build_rec(1.0)
	pu.upto = -1
	pu.sync()
	await idle(10)
	var v := float(pu.res.get("volume", 0.0)) * 1e9
	if absf(v - want_v) > 100.0:
		m.S.part = build_rec(-1.0)
		pu.upto = -1
		pu.sync()
		await idle(10)
		v = float(pu.res.get("volume", 0.0)) * 1e9
	print("diag on=%s mesh=%s bodies=%s feats=%d errs=%s vis=%s" % [pu.on, pu.part_mesh.mesh, pu.res.get("bodies"), (m.S.part.get("features", []) as Array).size(), str(pu.res.get("errors")), pu.part_mesh.visible])
	if pu.part_mesh.mesh == null:
		print("FAIL no mesh")
		print("s102: 1 fail")
		quit(1)
		return
	var bb: AABB = (pu.part_mesh.mesh as ArrayMesh).get_aabb()
	print("probe volume mm3 %.0f (box less hole %.0f) aabb %s" % [v, want_v, str(bb)])
	var side := 1.0 if bb.position.z > -0.001 else -1.0
	var hole_w := Vector3(0.0, 0.02, side * 0.0075)
	view_t = Vector3(0, 0.02, side * 0.015)
	m._turn_to(90.0, 0.0, 0.12, view_t, false)
	await idle(10)
	var rec_json0 := JSON.stringify(m.S.part)
	var undo0: int = m.undo.size()
	var xb := root.find_child("view_xray", true, false) as Button
	var tb := root.find_child("view_turntable", true, false) as Button
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var seen := xb != null and tb != null and xb.is_visible_in_tree() and tb.is_visible_in_tree()
	var inside := seen and win.encloses(xb.get_global_rect()) and win.encloses(tb.get_global_rect())
	var overlap := []
	if seen:
		for c in root.find_children("*", "BaseButton", true, false):
			var b := c as BaseButton
			if b == xb or b == tb or not b.is_visible_in_tree():
				continue
			if b.get_global_rect().intersects(xb.get_global_rect()) or b.get_global_rect().intersects(tb.get_global_rect()):
				overlap.append(b.name)
	ok(seen and inside and not xb.button_pressed and not tb.button_pressed and overlap.is_empty(), "1 both buttons on screen %s, off at the start, overlap %s" % [str(seen and inside), str(overlap)])
	if not seen:
		await shot("nobuttons")
		print("s102: %d fail" % fails)
		quit(1)
		return
	var sig0 := mat_sig()
	var al0 := mat_alpha()
	var im0 := await shot("off")
	var c0 := patch(im0, hole_w)
	await click_ctl(xb)
	var im1 := await shot("xray")
	var c1 := patch(im1, hole_w)
	var d := cdist(c0, c1)
	var tool_: PartViewTools = m.get_node("part_view_tools")
	var nl := 0
	if tool_.edges_mi != null and tool_.edges_mi.mesh != null:
		nl = (tool_.edges_mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 2
	ok(xb.button_pressed and d > 0.05 and mat_alpha() < 1.0 and al0 >= 0.999, "2 X-ray: pixel at the hole %s -> %s (distance %.3f > 0.05), part alpha %.2f -> %.2f" % [c0.to_html(), c1.to_html(), d, al0, mat_alpha()])
	ok(nl >= 24 and tool_.edges_mi.visible, "2b hidden edges drawn: %d edge lines (box 12 + hole 8 or more)" % nl)
	await click_ctl(xb)
	var im2 := await shot("off2")
	var c2 := patch(im2, hole_w)
	ok(not xb.button_pressed and mat_sig() == sig0 and cdist(c0, c2) < 0.25 * d and not tool_.edges_mi.visible, "3 X-ray off: material identical %s, pixel back to %.4f of the original (the X-ray change was %.3f; it must be under a quarter of it), edge lines hidden" % [str(mat_sig() == sig0), cdist(c0, c2), d])
	# 4 turntable
	await click_ctl(tb)
	var t0 := Time.get_ticks_msec()
	var y_a: float = m.yaw
	var fr := 0
	while Time.get_ticks_msec() - t0 < 1000:
		await process_frame
		fr += 1
	var el := float(Time.get_ticks_msec() - t0) / 1000.0
	var adv := fposmod(float(m.yaw) - y_a, 360.0)
	await shot("turn")
	ok(tb.button_pressed and absf(adv - 36.0) <= 3.0, "4 turntable on: yaw advanced %.1f deg in %.2f s (%d frames); wanted 36 +- 3" % [adv, el, fr])
	await click_ctl(tb)
	var y_b: float = m.yaw
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 500:
		await process_frame
	var still := absf(wrapf(float(m.yaw) - y_b, -180.0, 180.0))
	ok(not tb.button_pressed and still < 0.5, "4b turntable off: yaw moved %.3f deg in 0.5 s" % still)
	ok(JSON.stringify(m.S.part) == rec_json0 and m.undo.size() == undo0, "5 record JSON identical, undo count %d -> %d" % [undo0, m.undo.size()])
	print("s102: %d fail" % fails)
	quit(1 if fails > 0 else 0)
