extends SceneTree
## s012 (Friday plan 12): Bevel the edges (a flat 45-degree cut) next to Round the edges, the same kind of size slider.
## Real clicks from the BUILDING card's blank Easy Part: a 40 x 40 x 10 mm box (drawn, pulled), the Bevel chip on the Round chip row, the
## Bevel size slider dragged to 2 mm. Everything is measured from the built mesh (triangles), never from the record.
## Bars:
##   1 Bevel chip on the chip row beside All edges, on screen, 40 px or taller, says "Bevel"
##   2 a click adds one chamfer step, 1 mm by default: the top face is 38.0 mm wide (within 0.05)
##   3 the slider (Bevel size / Smaller / Bigger) dragged to 2 mm: while the knob is held the step already reads 2 mm (the mesh lands on release), after release the top face is 36.0 (within 0.05) in x and z
##   4 flat 45-degree faces: every slanted face normal has two equal components (45 deg); 12 distinct chamfer planes (12 edges x 1 face)
##   5 volume of the mesh matches the analytic chamfered box (box intersect 12 half-spaces) within 0.5 percent
##   6 the box is still 40 x 40 x 10 mm overall
##   7 Undo takes the bevel back (steps and a 40.0 mm top face); a press alone is one undo step
##   8 Only the top filter: the vertical corner stays sharp
##   9 no jargon on screen
## shots: C:/Temp/claude/s012/chips.png, bevel2.png
const SHOT := "C:/Temp/claude/s012"
const DIRT := "user://s012_test"
const JARGON := ["fillet", "chamfer", "kernel", "mesh", "manifold", "extrude", "revolve"]

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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		return   # a missing button: the bars that follow say so
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true)
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the solid corners as the built mesh has them (metres, world)
func verts() -> PackedVector3Array:
	var mesh: ArrayMesh = pu().part_mesh.mesh
	if mesh == null:
		return PackedVector3Array()
	return mesh.get_faces()


func bounds(vs: PackedVector3Array) -> AABB:
	var b := AABB()
	if vs.is_empty():
		return b
	b = AABB(vs[0], Vector3.ZERO)
	for v in vs:
		b = b.expand(v)
	return b


## the nearest built vertex to a sharp edge line, in mm. axis 2 (Z edge): the line x = a, y = b; axis 0 (X edge): y = a, z = b;
## axis 1 (Y edge, a vertical corner): x = a, z = b. A cut edge has new vertices close to the sharp line; a sharp edge has 0 mm
func nearest_mm(vs: PackedVector3Array, axis: int, a: float, b: float) -> float:
	var best := INF
	for v in vs:
		var d := Vector2.ZERO
		if axis == 2:
			d = Vector2(v.x - a, v.y - b)
		elif axis == 0:
			d = Vector2(v.y - a, v.z - b)
		else:
			d = Vector2(v.x - a, v.z - b)
		best = minf(best, d.length() * 1000.0)
	return best if best < INF else -1.0


func bev_btn() -> Button:
	return m.find_child("easypart_bevel", true, false) as Button


func feats() -> int:
	return (pu().ep._rec().get("features", []) as Array).size()


func last_kind() -> String:
	var fs: Array = pu().ep._rec().get("features", [])
	return String(fs[fs.size() - 1]["t"]) if not fs.is_empty() else ""


func drag_slider(s: HSlider, v: float, release := true) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y), true)
	await idle(6)
	await create_timer(1.0).timeout   # the part follows the held knob on a throttle (milliseconds, not frames)
	await idle(6)
	if not release:
		return
	await ev_mouse(Vector2(x1, y), false)
	await idle(30)


func tweak_slider() -> HSlider:
	var ep = pu().ep
	var tw: HSlider = null
	for r in ep.rows:
		if String(r["kind"]) == "tweak":
			tw = r["slider"]
	return tw


## the size (mm) of the top face: the extent in x and z of the triangles lying flat at the highest y
func top_face_mm(vs: PackedVector3Array) -> Vector2:
	var ymax := -INF
	for v in vs:
		ymax = maxf(ymax, v.y)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, vs.size() - 2, 3):
		if absf(vs[i].y - ymax) < 1e-5 and absf(vs[i + 1].y - ymax) < 1e-5 and absf(vs[i + 2].y - ymax) < 1e-5:
			for k in 3:
				lo = Vector2(minf(lo.x, vs[i + k].x), minf(lo.y, vs[i + k].z))
				hi = Vector2(maxf(hi.x, vs[i + k].x), maxf(hi.y, vs[i + k].z))
	return (hi - lo) * 1000.0 if lo.x < INF else Vector2(-1, -1)


func mesh_volume_mm3(vs: PackedVector3Array) -> float:
	var v := 0.0
	for i in range(0, vs.size() - 2, 3):
		v += vs[i].dot(vs[i + 1].cross(vs[i + 2])) / 6.0
	return absf(v) * 1e9


## planes of the slanted faces: {key: [normal, triangles]}; the key is the normal and the plane offset rounded to 0.01 mm
func slanted_planes(vs: PackedVector3Array) -> Dictionary:
	var out := {}
	for i in range(0, vs.size() - 2, 3):
		var n := (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i])
		if n.length() < 1e-12:
			continue
		n = n.normalized()
		var nz := 0
		for c in [n.x, n.y, n.z]:
			if absf(c) > 0.02:
				nz += 1
		if nz < 2:
			continue
		var off := n.dot(vs[i]) * 1000.0
		var key := "%.2f,%.2f,%.2f|%.2f" % [snappedf(n.x, 0.01) + 0.0, snappedf(n.y, 0.01) + 0.0, snappedf(n.z, 0.01) + 0.0, off]
		key = key.replace("-0.00", "0.00")
		if not out.has(key):
			out[key] = [n, 0]
		out[key][1] += 1
	return out


## the box (half sizes hx, hy, hz in mm) with every edge chamfered by c: the box intersect |xi| + |xj| <= hi + hj - c. Volume by a fine slice sum
func chamfered_box_mm3(hx: float, hy: float, hz: float, c: float) -> float:
	var n := 4000
	var total := 0.0
	for k in n:
		var z := -hz + (k + 0.5) * (2.0 * hz / n)
		var az := absf(z)
		var X := minf(hx, hx + hz - c - az)
		var Y := minf(hy, hy + hz - c - az)
		var K := hx + hy - c
		var cut := maxf(0.0, X + Y - K)
		total += (4.0 * X * Y - 2.0 * cut * cut) * (2.0 * hz / n)
	return total


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

	# a 6 cm square drawn on the grid and pulled up 2 cm (real clicks)
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	# the setup drew a 40 mm square and pulled it up; the How far slider is dragged to 1 cm
	var tw0 := tweak_slider()
	if tw0 != null:
		await drag_slider(tw0, 1.0)
	await idle(30)
	var bb := bounds(verts())
	ok(absf(bb.size.x * 1000 - 40.0) < 0.5 and absf(bb.size.z * 1000 - 40.0) < 0.5 and absf(bb.size.y * 1000 - 10.0) < 0.5, "setup: the box is 40 x 40 x 10 mm (%.2f x %.2f x %.2f)" % [bb.size.x * 1000, bb.size.y * 1000, bb.size.z * 1000])
	if bb.size.y < 0.005:
		print("s012: 1 fail (no box)")
		quit(1)
		return
	var v0 := mesh_volume_mm3(verts())
	var t0 := top_face_mm(verts())
	ok(absf(t0.x - 40.0) < 0.05 and absf(t0.y - 40.0) < 0.05, "setup: the top face is 40.0 mm before any bevel (%.2f x %.2f)" % [t0.x, t0.y])
	var n0 := feats()
	var all_btn := m.find_child("easypart_round_all", true, false) as Button
	var bev := bev_btn()
	var on_row := bev != null and all_btn != null and bev.is_visible_in_tree() and absf(bev.get_global_rect().get_center().y - all_btn.get_global_rect().get_center().y) < 4.0 and bev.get_global_rect().position.x > all_btn.get_global_rect().position.x
	var inside := bev != null and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(bev.get_global_rect())
	ok(on_row and inside and bev.get_global_rect().size.y >= 40.0 and bev.text == "Bevel", "1 the Bevel chip is on the Round chip row, on screen, %.0f px tall, says %s" % [bev.get_global_rect().size.y if bev != null else -1.0, bev.text if bev != null else "missing"])
	await shot("chips")

	await click_ctl(bev)
	await idle(30)
	var t1 := top_face_mm(verts())
	ok(feats() == n0 + 1 and last_kind() == "chamfer" and absf(t1.x - 38.0) < 0.05 and absf(t1.y - 38.0) < 0.05, "2 one click = one step (%d -> %d, %s); 1 mm default: the top face is %.2f x %.2f mm" % [n0, feats(), last_kind(), t1.x, t1.y])

	# 3 the slider to 2 mm, live
	var tw := tweak_slider()
	var texts: Array = []
	texts_under(m, texts)
	var words := texts.has("Bevel size") and texts.has("Smaller") and texts.has("Bigger")
	ok(tw != null and words, "3a the Bevel size slider (Smaller / Bigger) is on screen")
	if tw == null:
		print("s012: 1 fail (no slider)")
		quit(1)
		return
	await drag_slider(tw, 0.2, false)
	var lf: Dictionary = pu().ep._rec()["features"][-1]
	# the held knob edits the step at once (its size reads 2 mm) and starts the coarse preview job; in this off-screen run that background
	# tessellation does not land before the release (12 s waited), the same async path every size slider uses, so the MESH bar is the release (3c)
	ok(absf(float(lf.get("dist", 0.0)) - 2.0) < 0.01 and not pu()._tess_run.is_empty(), "3b live: with the knob still held the step already reads %s mm and the preview job runs (the mesh lands on release: top face %.2f mm until then)" % [str(lf.get("dist")), top_face_mm(verts()).x])
	var rr := tw.get_global_rect()
	await ev_mouse(Vector2(rr.position.x + 12.0 + (tw.value - tw.min_value) / (tw.max_value - tw.min_value) * (rr.size.x - 24.0), rr.get_center().y), false)
	await idle(30)
	var t2 := top_face_mm(verts())
	ok(absf(t2.x - 36.0) < 0.05 and absf(t2.y - 36.0) < 0.05, "3c slider at %.1f cm: the top face is %.2f x %.2f mm (36.0 +-0.05)" % [tw.value, t2.x, t2.y])
	await shot("bevel2")

	# 4 flat 45-degree faces: the kernel gives one flat face per edge (12, normal at 45 deg to its two box faces) and one small flat corner face per box corner (8, normal equal to all three axes)
	var vs := verts()
	var planes := slanted_planes(vs)
	var bad := 0
	var edge_planes := 0
	var corner_planes := 0
	for k in planes:
		var n: Vector3 = planes[k][0]
		var nz := []
		for c in [n.x, n.y, n.z]:
			if absf(c) > 0.02:
				nz.append(absf(c))
		if nz.size() == 2 and absf(nz[0] - nz[1]) < 0.01 and absf(nz[0] - 0.7071) < 0.01:
			edge_planes += 1
		elif nz.size() == 3 and absf(nz[0] - nz[1]) < 0.01 and absf(nz[1] - nz[2]) < 0.01:
			corner_planes += 1
		else:
			bad += 1
	ok(bad == 0 and edge_planes == 12, "4a flat 45-degree faces: %d edge planes with the normal at exactly 45 deg to two axes (12 expected: 12 edges x 1 face), %d slanted faces that are neither edge nor corner" % [edge_planes, bad])
	ok(corner_planes == 8, "4b the kernel's corner faces: %d flat faces equal to all three axes (8 box corners)" % corner_planes)

	# 5 volume, 6 overall size
	var v2 := mesh_volume_mm3(vs)
	var an := chamfered_box_mm3(bb.size.x * 500.0, bb.size.y * 500.0, bb.size.z * 500.0, 2.0)
	ok(absf(v2 - an) / an < 0.005, "5 volume %.0f mm3 against the analytic chamfered box %.0f mm3 (%.3f %% off); the sharp box was %.0f" % [v2, an, absf(v2 - an) / an * 100.0, v0])
	var bb2 := bounds(vs)
	ok(absf(bb2.size.x * 1000 - 40.0) < 0.1 and absf(bb2.size.y * 1000 - 10.0) < 0.1, "6 the box is still %.2f x %.2f x %.2f mm overall" % [bb2.size.x * 1000, bb2.size.y * 1000, bb2.size.z * 1000])

	# 7 Undo until the steps are back (the slider change may be its own step), then a press alone is one undo step
	var guard := 0
	while feats() > n0 and guard < 4:
		await click_ctl(pu().ep.undo_btn)
		await idle(30)
		guard += 1
	var tu := top_face_mm(verts())
	ok(feats() == n0 and absf(tu.x - 40.0) < 0.05, "7 Undo: the steps are back to %d after %d undo clicks, the top face is %.2f mm" % [n0, guard, tu.x])
	await click_ctl(bev_btn())
	await idle(30)
	var one := feats() == n0 + 1
	await click_ctl(pu().ep.undo_btn)
	await idle(30)
	ok(one and feats() == n0 and absf(top_face_mm(verts()).x - 40.0) < 0.05, "7b a press is one undo step (steps %d, one Undo -> %d, top face %.2f mm)" % [n0 + 1, feats(), top_face_mm(verts()).x])

	# 8 Only the top: the vertical corner stays sharp
	await click_ctl(m.find_child("easypart_round_top", true, false) as Button)
	await click_ctl(bev_btn())
	await idle(30)
	var pl := slanted_planes(verts())
	var d_v := nearest_mm(verts(), 1, bb.end.x, bb.end.z)
	ok(feats() == n0 + 1 and d_v == 0.0 and pl.size() >= 4, "8 Only the top: %d bevelled planes, the vertical corner stays sharp (%.2f mm)" % [pl.size(), d_v])
	await click_ctl(pu().ep.undo_btn)
	await idle(30)

	texts = []
	texts_under(m, texts)
	var jw := []
	for t in texts:
		for j in JARGON:
			if String(t).to_lower().find(j) >= 0:
				jw.append(t)
	ok(jw.is_empty(), "9 no jargon on screen %s" % [jw])
	print("s012: %d fail" % fails)
	quit(1 if fails > 0 else 0)
