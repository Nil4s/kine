## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/refplanes_test.gd    (ROADMAP_400 B21)
## REFERENCE IMAGES ON PLANES in the model preview (scripts/kmesh_refplanes.gd, kmesh_refplanes_ui.gd). The picture is
## made here (256 x 128 px: orange, a green dot at (16, 20), a blue dot at (240, 100), 8 x 8 px each); real mouse clicks
## and key presses are pushed into the window. Bars (stated before measuring):
##  1 LOAD: the picture dropped on the window (main._on_drop) while the preview is open is ONE plane, its node under the
##    mesh's view, its stored hash = the file's SHA-256, the panel shows
##  2 TYPED HEIGHT: "180" typed into the panel's Height field + Enter: the plane's WORLD height (its node's top edge to its
##    bottom edge) is 1.800 m within 0.1 mm (it was the cube's 0.6 m before: the number can move); "1.8 m" and "180 cm"
##    parse to the same; "abc" is refused and changes nothing
##  3 TWO POINTS (opacity 100 %): the dots' centroids found in a screenshot, the Two points button clicked, the two dots
##    clicked, "50" typed + Enter: the dots' real distance on the plane (world) is 0.500 m within 0.5 %
##  4 OPACITY 30 % (the slider): a pixel of the orange inside the plane, away from the mesh, against the same pixel with the
##    plane hidden (the background B): within 3/255 per channel of 0.3 C + 0.7 B blended in linear light (the renderer's
##    blend; the plain sRGB mix is printed too). Instrument: at 100 % the same pixel is C within 3/255
##  5 FLIP (the checkbox, a real click): the green dot's centroid moves to the mirror x about the plane's centre (2 px)
##  6 ONLY IN ITS VIEW (the checkbox): the front plane is hidden from the side view (camera down -X) and from a 35 deg
##    view (0 picture pixels there, against >= 500 with the box off: the count can move), shown in the front view
##  7 PICKS GO THROUGH: in front view a click on a cube vertex that is drawn over the plane picks that vertex; with the
##    plane pushed IN FRONT of the cube (offset depth +80 cm; the pixel at the vertex is the picture's now) the same click
##    still picks the vertex and nothing else
##  8 LOCK: with Lock on, a typed height and an offset change nothing (the fields are greyed)
##  9 SAVE / REOPEN: the mesh saved as .kmesh, read back, opened in the preview again: one plane with the same path, hash,
##    axis, opacity, flags, and its node's transform within 1e-6; the .kmesh grows < 2 KB with the plane (no pixels)
## 10 PLACEMENT: the panel is on screen, inside the window and the clear view, not over the Add primitive panel, the
##    Materials panel or the Modifiers panel; all its controls lie inside it; screenshot env REFPLANES_SHOT
extends SceneTree

const DIR := "user://refplanes_test"
const C := Color8(230, 120, 40)
var fails := 0
var m: Node
var ui
var rp


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(code: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni if down else 0
		e.pressed = down
		root.push_input(e)
		await process_frame


func type_in(le: LineEdit, s: String) -> void:
	await click(le.get_global_rect().get_center())
	le.select_all()
	await key(KEY_BACKSPACE)
	for ch in s:
		await key(KEY_A, ch.unicode_at(0))
	await key(KEY_ENTER)
	await idle(2)


func click(p: Vector2, shift := false) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = p
		e.global_position = p
		e.button_index = MOUSE_BUTTON_LEFT
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(2)
	await RenderingServer.frame_post_draw
	return m.get_viewport().get_texture().get_image()


func node() -> MeshInstance3D:
	return rp.nodes[0] if rp.nodes.size() > 0 else null


func plane_pt(uvpx: Vector2) -> Vector3:   # a picture pixel -> world
	var e: Dictionary = rp.planes()[0]
	return ui.view.global_transform * KMeshRefPlanes.uv_to_local(e, uvpx / Vector2(256, 128))


## centroid of the pixels near a pure colour, in a rect
func centroid(img: Image, want: Color, r: Rect2i) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) < 0.25:
				s += Vector2(x + 0.5, y + 0.5)
				n += 1
	return s / n if n >= 6 else Vector2(-1, -1)


func count_near(img: Image, want: Color) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) < 0.08:
				n += 1
	return n


func make_png() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	img.fill(C)
	img.fill_rect(Rect2i(12, 16, 8, 8), Color(0, 1, 0))
	img.fill_rect(Rect2i(236, 96, 8, 8), Color(0, 0, 1))
	var p := ProjectSettings.globalize_path(DIR + "/ref_front.png")
	img.save_png(p)
	return p


## the same entry after a JSON round trip: strings and flags equal, numbers within 1e-9 (the .kmesh writes 15 digits)
func same_entry(a: Dictionary, b: Dictionary) -> bool:
	if a.keys().size() != b.keys().size():
		return false
	for k in a:
		if not b.has(k):
			return false
		var x = a[k]
		var y = b[k]
		if x is Array:
			if not y is Array or (x as Array).size() != (y as Array).size():
				return false
			for i in (x as Array).size():
				if absf(float(x[i]) - float(y[i])) > 1e-9:
					return false
		elif x is float or x is int:
			if absf(float(x) - float(y)) > 1e-9:
				return false
		elif x != y:
			return false
	return true


func lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func srgb(c: float) -> float:
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.settings.begins_with("user://poser_test_"), "0 own config (%s)" % m.settings)
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	rp = ui.refp
	m._turn_to(0.0, 0.0, 3.2, Vector3(1.0, 0.35, 0.0), false)   # front, looking down -Z at the cube
	await idle(3)
	var cam: Camera3D = m.cam
	var png := make_png()
	var plain_bytes := JSON.stringify(ui.mesh.to_dict()).length()

	# 1 load by drop
	m._on_drop(PackedStringArray([png]))
	await idle(4)
	var l: Array = rp.planes()
	ok(l.size() == 1 and node() != null and node().get_parent() == ui.view and l[0]["hash"] == FileAccess.get_sha256(png) and l[0]["hash"].length() == 64 and rp.panel.visible,
		"1 dropped: %d plane, node under the view %s, hash %s, panel %s" % [l.size(), node() != null and node().get_parent() == ui.view, String(l[0]["hash"]).left(12) if l.size() > 0 else "-", rp.panel.visible])
	if l.size() != 1:
		print("REFPLANES: cannot go on")
		TestFiles.cleanup()
		quit(1)
		return
	var e: Dictionary = l[0]
	var wh := func() -> float:
		var gt := node().global_transform
		return (gt * Vector3(0, 0.5, 0)).distance_to(gt * Vector3(0, -0.5, 0))
	var h0: float = wh.call()

	# 2 typed height
	await type_in(rp._h, "180")
	var h1: float = wh.call()
	ok(absf(h1 - 1.8) < 1e-4 and absf(h0 - 1.8) > 0.1, "2a typed 180: world height %.6f m (bar 1.8 within 1e-4; it was %.4f)" % [h1, h0])
	ok(absf(KMeshRefPlanes.parse_len("1.8 m") - 1.8) < 1e-9 and absf(KMeshRefPlanes.parse_len("180 cm") - 1.8) < 1e-9 and is_nan(KMeshRefPlanes.parse_len("abc")), "2b '1.8 m' and '180 cm' parse the same, 'abc' does not")
	await type_in(rp._h, "abc")
	ok(absf(float(wh.call()) - 1.8) < 1e-6, "2c 'abc' refused: height still %.4f" % float(wh.call()))
	await type_in(rp._h, "60")
	ok(absf(float(wh.call()) - 0.6) < 1e-4, "2d back to 60 cm (%.5f)" % float(wh.call()))

	# 3 two points at 100 %
	rp._op.value = 100
	await idle(3)
	var img: Image = await shot()
	var g0 := centroid(img, Color(0, 1, 0), Rect2i(0, 0, img.get_width(), img.get_height()))
	var b0 := centroid(img, Color(0, 0, 1), Rect2i(0, 0, img.get_width(), img.get_height()))
	print("     dots on screen: green %s (want %s), blue %s (want %s)" % [g0, cam.unproject_position(plane_pt(Vector2(16, 20))), b0, cam.unproject_position(plane_pt(Vector2(240, 100)))])
	await click(rp._two_bt.get_global_rect().get_center())
	ok(rp.armed, "3a Two points armed by its button")
	await click(g0)
	await click(b0)
	ok(rp.two.size() == 2 and not rp.armed and ui.sel.count() == 0, "3b two clicks marked on the picture (%d), none went to the mesh (%d selected)" % [rp.two.size(), ui.sel.count()])
	await type_in(rp._dist, "50")
	var dd := plane_pt(Vector2(16, 20)).distance_to(plane_pt(Vector2(240, 100)))
	ok(absf(dd - 0.5) / 0.5 < 0.005, "3c the dots are %.5f m apart on the plane (bar 0.5 within 0.5 %%: %.3f %%), height %.4f m" % [dd, absf(dd - 0.5) / 0.5 * 100.0, float(wh.call())])
	await type_in(rp._h, "60")   # big again: the plane reaches past the cube on both sides

	# 4 opacity 30 %: a pixel of orange left of the cube
	var probe := cam.unproject_position(plane_pt(Vector2(226, 40))).round()
	var pi := Vector2i(probe)
	img = await shot()
	var c100 := img.get_pixelv(pi)
	node().visible = false
	rp.set_process(false)
	img = await shot()
	var bg := img.get_pixelv(pi)
	node().visible = true
	rp.set_process(true)
	await click(rp._op.get_global_rect().position + Vector2(rp._op.size.x * 0.3, rp._op.size.y * 0.5))   # the slider at 30 %
	print("     the slider clicked at 30 %% of its width: opacity %.3f%s" % [float(e["opacity"]), "" if absf(float(e["opacity"]) - 0.3) <= 0.005 else " (set to 30 by value)"])
	if absf(float(e["opacity"]) - 0.3) > 0.005:
		rp._op.value = 30
	await idle(2)
	img = await shot()
	var c30 := img.get_pixelv(pi)
	var want := Color(srgb(0.3 * lin(C.r) + 0.7 * lin(bg.r)), srgb(0.3 * lin(C.g) + 0.7 * lin(bg.g)), srgb(0.3 * lin(C.b) + 0.7 * lin(bg.b)))
	var naive := C * 0.3 + bg * 0.7
	var d100 := maxf(maxf(absf(c100.r - C.r), absf(c100.g - C.g)), absf(c100.b - C.b)) * 255.0
	var d30 := maxf(maxf(absf(c30.r - want.r), absf(c30.g - want.g)), absf(c30.b - want.b)) * 255.0
	print("     pixel %s: C %s, background %s, at 100 %% %s, at 30 %% %s; linear-light 30/70 %s, plain sRGB mix %s; opacity %.3f" % [pi, C.to_html(false), bg.to_html(false), c100.to_html(false), c30.to_html(false), want.to_html(false), naive.to_html(false), float(e["opacity"])])
	ok(d100 <= 3.0, "4a instrument: at 100 %% the pixel is the picture's colour (%.2f/255 off)" % d100)
	ok(absf(float(e["opacity"]) - 0.3) < 0.005 and d30 <= 3.0, "4b at 30 %% the pixel is 0.3 C + 0.7 B in linear light within %.2f/255 (bar 3)" % d30)

	# 5 flip
	rp._op.value = 100
	await idle(2)
	img = await shot()
	var gA := centroid(img, Color(0, 1, 0), Rect2i(0, 0, img.get_width(), img.get_height()))
	var cx := cam.unproject_position(node().global_transform.origin).x
	await click(rp._flip.get_global_rect().get_center())
	img = await shot()
	var gB := centroid(img, Color(0, 1, 0), Rect2i(0, 0, img.get_width(), img.get_height()))
	print("     green before %s, after flip %s, plane centre x %.1f" % [gA, gB, cx])
	ok(bool(e["flip"]) and absf((gA.x + gB.x) * 0.5 - cx) < 2.0 and absf(gA.y - gB.y) < 2.0 and absf(gA.x - gB.x) > 50.0, "5 flipped: the dot's x mirrored about the centre (%.2f px off)" % absf((gA.x + gB.x) * 0.5 - cx))
	await click(rp._flip.get_global_rect().get_center())

	# 6 only in its view
	m._turn_to(35.0, -10.0, 3.2, Vector3(1.0, 0.35, 0.0), false)
	await idle(3)
	var n_off := count_near(await shot(), C)
	await click(rp._only.get_global_rect().get_center())
	var n_on := count_near(await shot(), C)
	var vis35: bool = node().visible
	m._view(5)
	await idle(3)
	var vis_side: bool = node().visible
	m._turn_to(0.0, 0.0, 3.2, Vector3(1.0, 0.35, 0.0), false)
	await idle(3)
	var vis_front: bool = node().visible
	ok(bool(e["only_view"]) and not vis_side and not vis35 and vis_front and n_on == 0 and n_off >= 500,
		"6 only in its view: hidden from the side (%s) and at 35 deg (%s; %d picture pixels, %d with the box off), shown in front (%s)" % [not vis_side, not vis35, n_on, n_off, vis_front])
	await click(rp._only.get_global_rect().get_center())

	# 7 picks go through
	ui.set_mode(KMeshSelect.VERT)
	await idle(2)
	var pr := Rect2(cam.unproject_position(plane_pt(Vector2(0, 0))), Vector2.ZERO).expand(cam.unproject_position(plane_pt(Vector2(256, 128))))
	var tv := -1
	var tp := Vector2.ZERO
	for v in ui.mesh.verts.size():
		var w: Vector3 = ui.view.global_transform * ui.mesh.verts[v]
		if w.z < 0.29 or not ui.view.point_visible(cam, w):
			continue
		var s := cam.unproject_position(w)
		if pr.grow(-10).has_point(s) and (tv < 0 or s.distance_to(pr.get_center()) < tp.distance_to(pr.get_center())):
			tv = v
			tp = s
	tp += Vector2(2.3, -1.7)   # a hand's click is never exactly on the vertex (a ray through a shared corner can slip between its triangles)
	ui.sel.clear()
	await click(tp)
	var a1: Array = ui.sel.verts.keys()
	rp.set_offset(Vector3(0, 0, 80))
	await idle(2)
	var pz: float = node().global_transform.origin.z
	img = await shot()
	var at_v := img.get_pixelv(Vector2i(tp))
	ui.sel.clear()
	await click(tp)
	var a2: Array = ui.sel.verts.keys()
	ok(tv >= 0 and a1 == [tv], "7a plane behind: a click on vertex %d at %s inside the plane %s picks it (%s)" % [tv, tp, pr, a1])
	ok(pz > 0.31 and absf(at_v.r - C.r) + absf(at_v.g - C.g) + absf(at_v.b - C.b) < 0.08 and a2 == [tv],
		"7b plane in front (z %.2f, the pixel there %s is the picture's): the same click still picks vertex %s" % [pz, at_v.to_html(false), a2])
	rp.set_offset(Vector3.ZERO)

	# 8 lock
	await click(rp._lock.get_global_rect().get_center())
	var hl: float = e["height"]
	var ol: Array = (e["offset"] as Array).duplicate()
	rp.set_height_text("300")
	rp.set_offset(Vector3(10, 10, 10))
	ok(bool(e["lock"]) and e["height"] == hl and e["offset"] == ol and not rp._h.editable and rp._two_bt.disabled, "8 locked: height and offset unchanged, fields greyed")
	await click(rp._lock.get_global_rect().get_center())
	rp.set_opacity(45)
	rp.set_flag("only_view", true)
	m._turn_to(0.0, 0.0, 3.2, Vector3(1.0, 0.35, 0.0), false)
	await idle(3)

	# 10 placement (the panel as a user sees it)
	var vr := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var pnr: Rect2 = rp.panel.get_global_rect()
	var cl: Rect2 = m.nav_clear_rect()
	var others := {"Add primitive": ui.prim_panel, "Materials": ui.mat_panel, "Modifiers": ui.mods.panel if ui.mods.get("panel") != null else null}
	var over := []
	for k in others:
		var c: Control = others[k]
		if c != null and c.is_visible_in_tree() and c.get_global_rect().intersects(pnr):
			over.append("%s %s" % [k, c.get_global_rect()])
	var inside := true
	for c in [rp._list, rp._axis, rp._op, rp._h, rp._dist, rp._two_bt, rp._flip, rp._lock, rp._only] + rp._off:
		if not pnr.grow(0.5).encloses((c as Control).get_global_rect()):
			inside = false
	ok(rp.panel.is_visible_in_tree() and vr.encloses(pnr) and cl.grow(1.0).encloses(pnr) and pnr.size.x > 150, "10a the panel %s is inside the window %s and the clear view %s" % [pnr, vr, cl])
	ok(over.is_empty() and inside, "10b over no other panel (%s), every control inside it (%s)" % [over, inside])
	var sp := OS.get_environment("REFPLANES_SHOT")
	(await shot()).save_png(sp if sp != "" else DIR + "/refplanes.png")

	# 9 save / reopen
	var before: Dictionary = (rp.planes()[0] as Dictionary).duplicate(true)
	var xf0: Transform3D = node().global_transform
	var path := DIR + "/with_planes.kmesh"
	ok(ui.mesh.save(path) == OK, "9a saved")
	var txt := FileAccess.get_file_as_string(path)
	var grow := txt.length() - plain_bytes
	var back := KMesh.load_file(path)
	var after: Array = KMeshRefPlanes.list(back) if back != null else []
	var same := after.size() == 1 and same_entry(before, after[0])
	if after.size() == 1 and not same:
		print("     before ", before, "
     after  ", after[0])
	ok(back != null and same and txt.contains(png.get_file()) and grow < 2048,
		"9b read back: %d plane, same entry within 1e-9 %s, the file grew %d bytes (bar < 2048: no pixels)" % [after.size(), same, grow])
	ui.source = func(): return {"mesh": back}
	ui.stop()
	await idle(3)
	ui.start()
	m._turn_to(0.0, 0.0, 3.2, Vector3(1.0, 0.35, 0.0), false)
	await idle(4)
	var xf1: Transform3D = node().global_transform if node() != null else Transform3D()
	var dx := 0.0
	for k in 4:
		dx = maxf(dx, (xf1 * [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)][k]).distance_to(xf0 * [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)][k]))
	var mt: StandardMaterial3D = node().material_override if node() != null else null
	ok(rp.nodes.size() == 1 and dx < 1e-6 and mt != null and mt.albedo_texture != null and absf(mt.albedo_color.a - 0.45) < 1e-6 and node().visible,
		"9c reopened in the preview: 1 plane, corners within %s m, its picture loaded, 45 %% opaque, shown in front" % str(dx))
	var junk := KMesh.new()
	KMeshRefPlanes.from_file(junk, [{"path": "x.png", "height": NAN, "opacity": 7, "axis": "nope"}, 3, {"path": ""}])
	var jl := KMeshRefPlanes.list(junk)
	ok(jl.size() == 1 and jl[0]["height"] == 1.0 and jl[0]["opacity"] == 1.0 and jl[0]["axis"] == "front", "9d a damaged list is cleaned, never a crash")

	ui.stop()
	await idle(3)
	ok(not rp.panel.visible, "10c leaving the preview hides the panel")
	print("REFPLANES: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
