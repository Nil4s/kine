## godot --path . -s tests/kmeshmeasure_test.gd     (ROADMAP_400 B20; needs a window: the ruler and its label are read back as pixels)
## Measure tool on a KMesh (scripts/kmesh_measure.gd). Bars, written before measuring:
##   1 VOLUME: a 1 m cube (8 verts) and a 1 m cube of 4x4 quads per side (98 verts) are each 1 000 000 cm³ (1000 L) within
##     0.01 cm³; a 0.6 m cube moved 5 m off the origin is 216 000 cm³ within 1 cm³ (its verts are stored 32-bit: 5.6 m is
##     off by ~2e-7 m; summed in 64-bit from the 32-bit Vector3 maths it was 4 cm³ out)
##   2 AREA: one 0.25 m cell of the 4x4 cube is 625 cm² exactly (1e-6), 4 of them 2500, the whole cube 60 000; a 3-4-5
##     triangle 6 m² = 60 000 cm²; through the selection (face mode, 4 faces) the readout says "2500.0 cm²"
##   3 ANGLE: a cube corner 90°, an equilateral triangle 60° (to 1e-5°: sqrt 3 / 2 is stored 32-bit), (1,0,0)-(0,0,0)-(1,1,0)
##     45°, a straight line 180° (to 1e-9°); 3 picked verts at a cube corner (apex the 2nd picked) read "90.0°"
##   4 DISTANCE: opposite corners of the 1 m cube 173.2 cm (sqrt 3 m); 2 picked verts on one edge of the 4x4 cube = 25.0 cm
##   5 MASS: the 1 m steel cube is 7850 kg (EN 1991-1-1), oak 700 kg; a 10 cm steel cube 7.850 kg (1e-6: 0.1 m stored 32-bit); the readout carries the kg
##   6 REFUSAL: the cube with its top deleted gives no volume and the reason names the hole ("open", boundary edges count: 4); the
##     inside-out cube is refused as inside out; a 3-face edge as not manifold; no mass is given for any of them
##   7 PLACEMENT (the app's test cube, seen from the front, 2 opposite corners of the front face picked (84.9 cm), T pressed): the label rect lies inside the
##     window by its margin, its corner is within LABEL_GAP + 1 px of the projected ruler middle, the pixel at the ruler's
##     middle (a point on the line) differs from the same pixel with measure off (> 0.1), the label's centre pixel too;
##     an anchor far off-screen (and one behind the camera) still puts the label fully inside the window. T again: gone.
##     Shot -> user://kmeshmeasure.png
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		e.shift_pressed = shift
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func cube(faces := CF, off := Vector3.ZERO, side := 1.0) -> KMesh:
	var v := PackedVector3Array()
	for p in CV:
		v.append(p * side + off)
	return KMesh.new().from_arrays(v, faces)


func _init() -> void:
	var M := KMeshMeasure
	# 1 volume
	var c1 := cube()
	var c4 := KMeshView.make_cube(1.0, 4)
	var cf := cube(CF, Vector3(5, 5, 5), 0.6)
	var v1: Dictionary = M.volume(c1)
	var v4: Dictionary = M.volume(c4)
	var vf: Dictionary = M.volume(cf)
	ok(v1["ok"] and absf(v1["m3"] * M.CM3 - 1e6) < 0.01 and v4["ok"] and absf(v4["m3"] * M.CM3 - 1e6) < 0.01 and absf(vf["m3"] * M.CM3 - 216000.0) < 1.0,
		"(1) volume: 1 m cube %s, 4x4 cube %s, 0.6 m cube off the origin %s" % [M.fmt_vol(v1["m3"]), M.fmt_vol(v4["m3"]), M.fmt_vol(vf["m3"])])
	# 2 area
	var cell := M.face_area(c4, 0) * M.CM2
	var four := M.area(c4, [0, 1, 2, 3]) * M.CM2
	var all := M.area(c4) * M.CM2
	var tri := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(3,0,0), Vector3(0,4,0)]), [[0, 1, 2]])
	var ta := M.area(tri) * M.CM2
	var ms := KMeshMeasure.new()
	var s4 := KMeshSelect.new(c4, KMeshSelect.FACE)
	for fi in 4:
		s4.faces[fi] = true
	var ra := ms.measure(c4, s4)
	ok(absf(cell - 625.0) < 1e-6 and absf(four - 2500.0) < 1e-6 and absf(all - 60000.0) < 1e-6 and absf(ta - 60000.0) < 1e-6 and ra["kind"] == "area" and (ra["text"] as String).begins_with("2500.0 cm²"),
		"(2) area: cell %.6f cm², 4 cells %.6f, cube %.6f, 3-4-5 triangle %.6f; readout '%s'" % [cell, four, all, ta, ra["text"]])
	# 3 angle
	var a90 := M.angle(Vector3(1,0,0), Vector3.ZERO, Vector3(0,0,1))
	var a60 := M.angle(Vector3(1,0,0), Vector3.ZERO, Vector3(0.5, sqrt(3.0) / 2.0, 0))
	var a45 := M.angle(Vector3(1,0,0), Vector3.ZERO, Vector3(1,1,0))
	var a180 := M.angle(Vector3(1,0,0), Vector3.ZERO, Vector3(-2,0,0))
	var s3 := KMeshSelect.new(c1, KMeshSelect.VERT)
	for v in [1, 0, 4]:
		s3.verts[v] = true
	var rg := ms.measure(c1, s3)
	ok(absf(a90 - 90.0) < 1e-9 and absf(a60 - 60.0) < 1e-5 and absf(a45 - 45.0) < 1e-9 and absf(a180 - 180.0) < 1e-9 and rg["kind"] == "angle" and (rg["text"] as String).begins_with("90.0°"),
		"(3) angle: %.12f / %.12f / %.12f / %.12f°; picked corner '%s'" % [a90, a60, a45, a180, rg["text"]])
	# 4 distance
	var d := M.distance(CV[0], CV[6]) * M.CM
	var e0: Vector2i = c4.edges()[0]
	var s2 := KMeshSelect.new(c4, KMeshSelect.VERT)
	s2.verts[e0.x] = true
	s2.verts[e0.y] = true
	var rd := ms.measure(c4, s2)
	ok(absf(d - sqrt(3.0) * 100.0) < 1e-9 and absf(rd["value"] * M.CM - 25.0) < 1e-9 and rd["text"] == "25.0 cm", "(4) distance: corner to corner %.4f cm, one edge '%s'" % [d, rd["text"]])
	# 5 mass
	ms.set_material("steel")
	var rs := ms.measure(c1, KMeshSelect.new(c1))
	var steel: float = rs.get("kg", -1.0)
	ms.set_material("oak")
	var oak: float = ms.measure(c1, null).get("kg", -1.0)
	ms.set_material("steel")
	var small: float = ms.measure(cube(CF, Vector3.ZERO, 0.1), null).get("kg", -1.0)
	ok(absf(steel - 7850.0) < 1e-6 and absf(oak - 700.0) < 1e-6 and absf(small - 7.85) < 1e-6 and (rs["text"] as String).contains("7850.0 kg as steel"),
		"(5) mass: 1 m steel %.3f kg, oak %.3f kg, 10 cm steel %.6f kg; readout '%s' (%s)" % [steel, oak, small, rs["text"], M.MATERIALS["steel"]["src"]])
	# 6 refusal
	var open := cube([CF[0], CF[2], CF[3], CF[4], CF[5]])   # the z = 1 face deleted
	var ro := ms.measure(open, null)
	var rev := []
	for g in CF:
		var h: Array = g.duplicate()
		h.reverse()
		rev.append(h)
	var vio: Dictionary = M.volume(cube(rev))
	var nm := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0), Vector3(0,-1,0), Vector3(0,0,1)]), [[0,1,2], [1,0,3], [0,1,4]])
	var vnm: Dictionary = M.volume(nm)
	ok(not ro["ok"] and (ro["why"] as String).contains("open") and (ro["why"] as String).contains("boundary edges count: 4") and not ro.has("kg") and not vio["ok"] and (vio["why"] as String).contains("inside out") and not vnm["ok"] and (vnm["why"] as String).contains("not manifold"),
		"(6) refused: open '%s'; reversed '%s'; 3-face edge '%s'" % [ro["why"], vio["why"], vnm["why"]])
	ms.free()

	# 7 placement in the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	var cam: Camera3D = m.cam
	# the two front verts farthest apart on the front face's diagonal: most toward the camera, then min / max x+y
	var to_cam := (cam.global_position - wc).normalized()
	var front := []
	var best := -INF
	for v in ui.mesh.vert_count():
		best = maxf(best, (ui.mesh.verts[v] as Vector3).dot(to_cam))
	for v in ui.mesh.vert_count():
		if (ui.mesh.verts[v] as Vector3).dot(to_cam) > best - 0.05:   # the front plane (the next ring in is 0.15 m back)
			front.append(v)
	var va: int = front[0]
	var vb: int = front[0]
	for a in front:
		for b in front:
			if ui.mesh.verts[a].distance_to(ui.mesh.verts[b]) > ui.mesh.verts[va].distance_to(ui.mesh.verts[vb]) + 1e-6:
				va = a
				vb = b
	ui.sel.set_mode(KMeshSelect.VERT)
	ui.sel.clear()
	var img_off := await shot()
	ui.sel.verts[va] = true
	ui.sel.verts[vb] = true
	ui.view.mark_dirty()
	await key(KEY_T)
	var img := await shot()
	img.save_png("user://kmeshmeasure.png")
	var mid_w: Vector3 = ui.view.global_transform * ((ui.mesh.verts[va] + ui.mesh.verts[vb]) * 0.5)
	var mid := cam.unproject_position(mid_w)
	var meas: KMeshMeasure = ui.meas
	var font := ThemeDB.fallback_font
	var txt: String = meas.result.get("text", "") if meas != null else ""
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KMeshMeasure.FONT_SIZE) + Vector2(12, 8)
	var scr := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	var lr := KMeshMeasure.label_rect(cam, mid_w, sz, root.get_visible_rect())
	var inner := root.get_visible_rect().grow(-KMeshMeasure.LABEL_MARGIN + 0.01)
	var corner := lr.position + Vector2(0, lr.size.y)   # bottom-left sits LABEL_GAP right of and above the middle
	var near := corner.distance_to(mid + Vector2(KMeshMeasure.LABEL_GAP, -KMeshMeasure.LABEL_GAP)) <= 1.0
	# the ruler pixel: a point a little off the exact middle so the label box (above-right) does not cover it
	var on_line := cam.unproject_position(ui.view.global_transform * ui.mesh.verts[va].lerp(ui.mesh.verts[vb], 0.4))
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var px := func(im: Image, p: Vector2) -> Color:
		var q := Vector2i((p * k).round()).clamp(Vector2i.ZERO, im.get_size() - Vector2i.ONE)
		return im.get_pixelv(q)
	var dl := 0.0   # the line is 1 px wide: the most any pixel of the 3x3 around the point moved
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			dl = maxf(dl, dist(px.call(img, on_line + Vector2(dx, dy)), px.call(img_off, on_line + Vector2(dx, dy))))
	var dlab := dist(px.call(img, lr.get_center()), px.call(img_off, lr.get_center()))
	ok(meas != null and txt == "84.9 cm" and inner.encloses(lr) and near and dl > 0.1 and dlab > 0.1,
		"(7) label '%s' at %s (ruler middle %s, near %s, inside %s); ruler pixel moved %.2f, label pixel %.2f" % [txt, str(lr), str(mid), near, inner.encloses(lr), dl, dlab])
	var far := KMeshMeasure.label_rect(cam, wc + cam.global_transform.basis.x * 50.0, sz, root.get_visible_rect())
	var behind := KMeshMeasure.label_rect(cam, cam.global_position + cam.global_transform.basis.z * 3.0, sz, root.get_visible_rect())
	ok(inner.encloses(far) and inner.encloses(behind), "(7) off-screen anchor kept inside: far right %s, behind the camera %s" % [str(far), str(behind)])
	await key(KEY_T)
	ok(ui.meas == null, "(7) M again turns the measure off")
	print("  shot: ", ProjectSettings.globalize_path("user://kmeshmeasure.png"), "  (", scr.size, ")")
	print("KMESH MEASURE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
