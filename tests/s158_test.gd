extends SceneTree
## godot --path . -s tests/s158_test.gd     (Friday plan 158: texture paint with simple brushes, colour picker, stickers; needs a window: main)
## PATH: the MODEL page's mesh (the test cube; the body mesh is the same editor) in vertex-paint mode (scripts/kmesh_vpaint_ui.gd), which
## already existed (E04); new here: SOFTNESS slider, STICKERS (scripts/kmesh_sticker.gd), "denser" and "save" buttons. The paint is
## VERTEX COLOURS (one per face corner): saved in the .kmesh, exported as COLOR_0 in the GLB.
## Bars (real mouse drags / clicks on the panel's own buttons; colours read back from the mesh, pixels from the screenshot, the GLB re-read from disk):
##   1 STROKE   a hard round brush ~10 px wide dragged across the front face: >= 5 sample points on the path are within 0.05 of the chosen colour
##              (picked in the ColorPickerButton's popup), and 3 points 2 brush radii off the path are still white
##   2 UNDO     a second stroke elsewhere; one Ctrl+Z removes exactly that stroke and keeps the first
##   3 DROPPER  the panel's eyedropper button, then a click on a painted spot: the brush colour is that spot's colour within 0.02
##   4 STICKER  the star lands centred at the click within 1 brush radius; its pixels show in the screenshot (pixel diff, yellow pixels);
##              one undo step; a half red / half blue PNG turned 90 degrees puts the red below the blue (rotation works)
##   5 SAVED    the .kmesh written by the panel's save button re-read has the same painted corners; the exported GLB re-read has
##              the stroke colour and the sticker's yellow in COLOR_0
var fails := 0
var m: Node
const SHOTS := "C:/Temp/claude/s158"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.ctrl_pressed = ctrl
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func click(p: Vector2) -> void:
	await move(p, false)
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click(c.get_global_rect().get_center())


func drag(a: Vector2, b: Vector2) -> void:
	await move(a, false)
	await mouse(a, true)
	var n := int(a.distance_to(b) / 3.0)
	for i in range(1, n + 1):
		await move(a.lerp(b, float(i) / n))
	await mouse(b, false)
	await idle(2)


func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot(hide_ui := false) -> Image:
	if hide_ui:
		m.ui_root.visible = false
	await idle(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if hide_ui:
		m.ui_root.visible = true
	return img


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


## the colour the mesh has under screen point p (nearest corner of the face there), or null off the mesh
func colour_at(pu, p: Vector2):
	var s: Dictionary = pu.surface_at(m.cam, p)
	if s.is_empty():
		return null
	return KMeshVPaint.sample(pu.mesh, s["face"], pu._local(s["point"]))


func painted_corners(k: KMesh) -> int:
	var d: PackedColorArray = k.attr_data(KMeshVPaint.CH)
	var n := 0
	for c in d:
		if dist(c, Color.WHITE) > 0.02:
			n += 1
	return n


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var line: Dictionary = {}
	for t in MeshTools.TOOLS:
		if t["id"] == "mesh_vpaint":
			line = t
	MeshTools.run(line, m)
	await idle(4)
	var pu := KMeshVPaintUI.of(m)
	var ui = m.kmed
	ok(ui != null and ui.on and pu.on and pu.panel.visible, "(0) paint mode is on (panel shown %s)" % pu.panel.visible)
	# the panel's own "denser" button, four real clicks: 4 x 4 quads a side -> 64 x 64 (a 0.94 cm cell)
	var f0: int = ui.mesh.face_count()
	for i in 4:
		await click_ctl(pu._w["denser"])
	var shape_ok := true
	for v in ui.mesh.verts:
		shape_ok = shape_ok and maxf(absf(v.x), maxf(absf(v.y), absf(v.z))) <= 0.3 + 1e-4
	ok(ui.mesh.face_count() == f0 * 256 and shape_ok and KMeshVPaint.usable(ui.mesh),
		"(0b) denser x4: faces %d -> %d, still inside the 0.6 m cube %s" % [f0, ui.mesh.face_count(), shape_ok])
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var P := func(o: Vector3) -> Vector2: return cam.unproject_position(wc + o)
	var ppm: float = P.call(Vector3(0.1, 0, 0.3)).distance_to(P.call(Vector3(-0.1, 0, 0.3))) / 0.2
	# brush: hard (softness 0 on the slider), radius about 5 px = 10 px wide
	var rad_mm := maxi(5, roundi(5.0 / ppm * 1000.0))
	pu._w["radius"].value = rad_mm
	pu._w["softness"].value = 0
	pu._w["strength"].value = 100
	var r_px: float = rad_mm / 1000.0 * ppm
	ok(is_equal_approx(pu.softness, 0.0) and absf(pu.radius - rad_mm / 1000.0) < 1e-6 and r_px > 3.0 and r_px < 8.0,
		"(1a) sliders: softness %.2f, radius %d mm = %.1f px (stroke %.1f px wide); %.0f px per metre" % [pu.softness, rad_mm, r_px, r_px * 2.0, ppm])
	# colour picker: click the button (popup opens), then pick a colour in the picker
	var chosen := Color(0.15, 0.7, 0.25, 1.0)
	var cp: ColorPickerButton = pu._w["color"]
	await click_ctl(cp)
	var popup_open := cp.get_popup().visible
	await shot()
	(await shot()).save_png(SHOTS + "/1_picker_popup.png")
	cp.get_picker().color = chosen
	cp.get_picker().color_changed.emit(chosen)   # the picker widget reports a pick
	await idle(3)
	ok(popup_open and dist(pu.color, chosen) < 0.01, "(1b) the colour picker popup opens (%s) and the brush colour is now %s" % [popup_open, pu.color])
	cp.get_popup().hide()
	await idle(3)
	# stroke 1 across the front face
	var A: Vector2 = P.call(Vector3(-0.2, 0.12, 0.3))
	var B: Vector2 = P.call(Vector3(0.2, 0.12, 0.3))
	var steps0: int = ui.undo.steps.size()
	var white0 := painted_corners(ui.mesh)
	var img0 := await shot(true)
	await drag(A, B)
	var on_path := 0
	var worst := 0.0
	for k in 7:
		var c = colour_at(pu, A.lerp(B, 0.1 + 0.1333 * k))
		if c != null:
			var dd := dist(c, chosen)
			worst = maxf(worst, dd)
			if dd <= 0.05:
				on_path += 1
	var off := 0
	for k in [0.2, 0.5, 0.8]:
		var c = colour_at(pu, A.lerp(B, k) + Vector2(0, 2.0 * r_px))
		if c != null and dist(c, Color.WHITE) < 0.05:
			off += 1
	ok(on_path >= 5 and off == 3 and ui.undo.steps.size() == steps0 + 1 and white0 == 0,
		"(1) stroke: %d of 7 path points within 0.05 of %s (worst %.3f); %d of 3 points 2 radii (%.0f px) off the path still white; one undo step %s" % [on_path, chosen, worst, off, 2.0 * r_px, ui.undo.steps.size() == steps0 + 1])
	# screenshot: the stroke is a green band about 10 px wide
	await idle(10)
	var img1 := await shot(true)
	img1.save_png(SHOTS + "/1b_stroke.png")
	var shot_sc := float(img1.get_width()) / root.get_visible_rect().size.x   # the screenshot is larger than the UI's coordinates
	var mid := A.lerp(B, 0.5) * shot_sc
	var band := 0
	for dy in range(-20, 21):
		var q := Vector2i((mid + Vector2(0, dy)).round())
		var hit_row := false
		for dx in range(-3, 4):   # the vertex dots drawn on the surface leave gaps: a row counts when any of 7 pixels turned green
			var p1 := img1.get_pixel(q.x + dx, q.y)
			var p0 := img0.get_pixel(q.x + dx, q.y)
			if dist(p0, p1) > 0.08 and p1.g > p1.r + 0.03:
				hit_row = true
		if hit_row:
			band += 1
	band = roundi(band / shot_sc)
	ok(band >= 6 and band <= 24, "(1c) in the screenshot the stroke is a green band %d px wide across the path (brush %.0f px; shot scale %.2f, pixel at the path %s)" % [band, r_px * 2.0, shot_sc, img1.get_pixelv(Vector2i(mid.round()))])
	# 2 UNDO: second stroke (red), one Ctrl+Z removes only it
	pu.color = Color(0.9, 0.1, 0.1, 1.0)
	var A2: Vector2 = P.call(Vector3(-0.2, -0.12, 0.3))
	var B2: Vector2 = P.call(Vector3(0.2, -0.12, 0.3))
	await drag(A2, B2)
	var red_there = colour_at(pu, A2.lerp(B2, 0.5))
	var n2: int = ui.undo.steps.size()
	await key(KEY_Z, true)
	var after = colour_at(pu, A2.lerp(B2, 0.5))
	var keep = colour_at(pu, A.lerp(B, 0.5))
	ok(red_there != null and dist(red_there, Color(0.9, 0.1, 0.1)) < 0.05 and dist(after, Color.WHITE) < 0.02 and dist(keep, chosen) < 0.05 and ui.undo.steps.size() == n2 - 1,
		"(2) second stroke painted %s; Ctrl+Z: it is white again %s, the first stroke stays %s, steps %d -> %d" % [red_there, after, keep, n2, ui.undo.steps.size()])
	# 3 EYEDROPPER via the panel button
	pu.color = Color(0.3, 0.3, 0.3, 1.0)
	pu._sync_panel()
	await click_ctl(pu._w["eyedropper"])
	var armed: bool = pu.dropper
	await click(A.lerp(B, 0.35))
	var steps_after: int = ui.undo.steps.size()
	ok(armed and dist(pu.color, chosen) < 0.02 and steps_after == n2 - 1 and not pu.dropper,
		"(3) eyedropper button + click on the stroke: brush colour %s vs painted %s (diff %.4f), no undo step added" % [pu.color, chosen, dist(pu.color, chosen)])
	# 4 STICKER: arm with the panel button, size 200 mm, click the lower front face
	await click_ctl(pu._w["sticker_on"])
	pu._w["sticker_size"].value = 200
	pu._w["sticker_rot"].value = 0
	await idle(2)
	var C: Vector2 = P.call(Vector3(0.0, -0.05, 0.3))
	var hit: Dictionary = pu.surface_at(cam, C)
	var before_img := await shot(true)
	var pre: PackedColorArray = (ui.mesh.attr_data(KMeshVPaint.CH) as PackedColorArray).duplicate()
	var n3: int = ui.undo.steps.size()
	await click(C)
	var post: PackedColorArray = ui.mesh.attr_data(KMeshVPaint.CH)
	var acc := Vector3.ZERO
	var cnt := 0
	var fi := 0
	var cvs := {}
	for f in ui.mesh.faces.size():
		var fp: PackedInt32Array = ui.mesh.faces[f]
		for i in fp.size():
			var ci: int = ui.mesh.face_he0[f] + i
			if dist(pre[ci], post[ci]) > 0.02 and ui.mesh.verts[fp[i]].z > 0.29:
				acc += ui.mesh.verts[fp[i]]
				cnt += 1
	var cen := acc / maxf(cnt, 1)
	var hit_local: Vector3 = pu._local(hit["point"])
	var off_m := Vector2(cen.x - hit_local.x, cen.y - hit_local.y).length()
	var after_img := await shot(true)
	after_img.save_png(SHOTS + "/2_sticker.png")
	var changed := 0
	var yellow := 0
	for y in range(0, after_img.get_height(), 1):
		for x in range(0, after_img.get_width(), 1):
			var a := before_img.get_pixel(x, y)
			var b := after_img.get_pixel(x, y)
			if dist(a, b) > 0.15:
				changed += 1
			if b.r > 0.7 and b.g > 0.55 and b.b < 0.45:
				yellow += 1
	ok(cnt > 150 and off_m <= pu.radius and ui.undo.steps.size() == n3 + 1,
		"(4a) star sticker: %d corners coloured, centre %.1f mm from the click (limit: brush radius %.0f mm), one undo step %s" % [cnt, off_m * 1000.0, pu.radius * 1000.0, ui.undo.steps.size() == n3 + 1])
	ok(changed > 1500 and yellow > 800,
		"(4b) screenshot pixel diff: %d pixels changed (> 0.15), %d yellow star pixels" % [changed, yellow])
	await key(KEY_Z, true)
	var cleared: bool = painted_corners(ui.mesh) == painted_corners_expected(pre)
	ok(cleared and ui.undo.steps.size() == n3, "(4c) Ctrl+Z takes the sticker back: painted corners %d = before %d" % [painted_corners(ui.mesh), painted_corners_expected(pre)])
	# PNG sticker, half red (left) / half blue (right), turned 90 degrees: red must end up BELOW blue
	var png := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			png.set_pixel(x, y, Color(0.9, 0.05, 0.05, 1) if x < 32 else Color(0.05, 0.1, 0.9, 1))
	var ppath := ProjectSettings.globalize_path("user://s158_sticker.png")
	png.save_png(ppath)
	var loaded: bool = pu.use_png(ppath)
	pu._w["sticker_size"].value = 160
	pu._w["sticker_rot"].value = 90
	await idle(2)
	var C2: Vector2 = P.call(Vector3(0.0, -0.02, 0.3))
	var pre2: PackedColorArray = (ui.mesh.attr_data(KMeshVPaint.CH) as PackedColorArray).duplicate()
	await click(C2)
	var post2: PackedColorArray = ui.mesh.attr_data(KMeshVPaint.CH)
	var ry := 0.0
	var rn := 0
	var by := 0.0
	var bn := 0
	for f in ui.mesh.faces.size():
		var fp2: PackedInt32Array = ui.mesh.faces[f]
		for i in fp2.size():
			var ci2: int = ui.mesh.face_he0[f] + i
			if dist(pre2[ci2], post2[ci2]) > 0.02 and ui.mesh.verts[fp2[i]].z > 0.29:
				var c: Color = post2[ci2]
				if c.r > 0.6 and c.b < 0.3:
					ry += ui.mesh.verts[fp2[i]].y
					rn += 1
				elif c.b > 0.6 and c.r < 0.3:
					by += ui.mesh.verts[fp2[i]].y
					bn += 1
	ok(loaded and rn > 50 and bn > 50 and ry / maxf(rn, 1) < by / maxf(bn, 1) - 0.03,
		"(4d) PNG sticker turned 90 deg: red corners %d at mean y %.3f, blue %d at mean y %.3f (red below blue by %.1f mm)" % [rn, ry / maxf(rn, 1), bn, by / maxf(bn, 1), (by / maxf(bn, 1) - ry / maxf(rn, 1)) * 1000.0])
	# put a star back so the saved / exported result has a sticker too
	pu._w["sticker_name"].select(0)
	pu._panel_set(0, "sticker_name")
	pu._w["sticker_rot"].value = 0
	pu._w["sticker_size"].value = 140
	var C3: Vector2 = P.call(Vector3(0.0, -0.15, 0.3))
	await click(C3)
	await click_ctl(pu._w["sticker_on"])
	ok(not pu.sticker_on, "(4e) the Sticker button toggles the mode off")
	(await shot()).save_png(SHOTS + "/3_final.png")
	# 5 SAVED + GLB
	var live := painted_corners(ui.mesh)
	await click_ctl(pu._w["save"])
	var kp := ProjectSettings.globalize_path(UserPaths.w("res://exports")) + "/painted_model.kmesh"
	var k2 := KMesh.load_file(kp)
	var same := k2 != null and k2.has_attr(KMeshVPaint.CH) and painted_corners(k2) == live
	ok(same and live > 300, "(5a) saved .kmesh re-read: %d painted corners = live %d (%s)" % [painted_corners(k2) if k2 != null else -1, live, kp])
	var gp: String = m._export_model()
	var green := 0
	var yel := 0
	var total := 0
	if gp != "" and FileAccess.file_exists(gp):
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(gp, st) == OK:
			var sc := doc.generate_scene(st)
			for n in sc.find_children("*", "MeshInstance3D", true, false):
				var mesh := (n as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(s)
					var cols = arr[Mesh.ARRAY_COLOR]
					if cols != null:
						for c in cols:
							total += 1
							if dist(c, chosen) < 0.05:
								green += 1
							elif c.r > 0.9 and c.g > 0.7 and c.g < 0.95 and c.b < 0.25:
								yel += 1
			sc.free()
	var live_green := 0
	var lcm := KMeshVPaint.corner_map(ui.mesh)
	for v in ui.mesh.verts.size():
		if dist(KMeshVPaint.vert_color(ui.mesh, v, lcm), chosen) < 0.05:
			live_green += 1
	ok(total > 0 and live_green > 30 and green >= int(0.8 * live_green) and yel > 20, "(5b) GLB re-read (%s): %d colours, %d are the stroke green (%s; the live mesh has %d such verts), %d are the sticker's star yellow" % [gp.get_file(), total, green, chosen, live_green, yel])
	print("s158: %d fail" % fails)
	quit(1 if fails else 0)


func painted_corners_expected(d: PackedColorArray) -> int:
	var n := 0
	for c in d:
		if dist(c, Color.WHITE) > 0.02:
			n += 1
	return n
