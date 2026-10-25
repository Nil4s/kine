## godot --path . -s tests/meshview_test.gd     (ROADMAP_400 A05 + A06; needs a window: real mouse / key events, pixels read back)
## "Model: edit a test cube (preview)": a 4x4-per-side cube (98 verts, 192 edges, 96 faces) on the stage, seen from the front
## (camera on the cube's axis, 2.4 m away). Bars, written before measuring:
##   1 FACE CLICK: in face mode a click at the projected centre of each of the 16 cells of the FRONT face selects exactly that
##     face (16 of 16) - never the cell behind it; Shift+click on a second cell gives 2, Shift+click on it again gives 1;
##     a click on empty space clears
##   2 VERT PICK: in vert mode a click 11 px from each of the 25 front verts picks exactly that vert (25 of 25, not the far
##     vert behind it); a click 20 px away from every vert (cell centre, 60+ px from the corners) picks none; edge mode (key 2,
##     a real key event): a click on the midpoint of each of the 40 front-face edges selects exactly that edge (40 of 40)
##   3 BOX: the left half of the screen from the front, vert mode: WITHOUT x-ray exactly 10 verts (2 front columns x 5 rows;
##     the side wall is edge-on and the far side hidden), WITH x-ray exactly 41 (x=-0.3 plane 25 + x=-0.15 ring 16); the lasso
##     of the same half gives the same counts; face mode: 8 faces without x-ray, 48 with
##   4 PLACEMENT (whole-body view, UI hidden, shot -> C:/Users/Nick/.claude/jobs/9afc22db/tmp/meshview.png): the view sits at
##     the stage position (1.0, 0.3, 0) within 1 mm and rests on the floor (lowest corner y = 0 within 1 mm), all 8 corners project
##     inside the frame, the pixel at its projected centre differs from the same pixel with the cube hidden, a selected
##     face's centre pixel differs from an unselected face's (colour distance > 0.1) and is bluer than it, a wire edge's pixel
##     is brighter than the face beside it (by > 0.1)
##   5 Esc leaves: the view is gone, the dev command can open it again
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI
var C := Vector3(1.0, 0.3, 0.0)   # the cube's centre (stage position)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.shift_pressed = shift
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func click(p: Vector2, shift := false) -> void:
	await mouse(p, true, shift)
	await mouse(p, false, shift)
	await idle(2)


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await process_frame
	e = InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = false
	root.push_input(e)
	await idle(2)


func drag(a: Vector2, b: Vector2) -> void:
	await mouse(a, true)
	for k in 6:
		var e := InputEventMouseMotion.new()
		e.position = a.lerp(b, (k + 1) / 6.0)
		e.global_position = e.position
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await mouse(b, false)
	await idle(2)


func world(v: int) -> Vector3:
	return ui.view.global_transform * ui.mesh.verts[v]


func scr(wp: Vector3) -> Vector2:
	return m.cam.unproject_position(wp)


func fc(fi: int) -> Vector2:
	return scr(ui.view.global_transform * ui.mesh.face_center(fi))


## faces whose outward normal is toward the camera (n . (cam - centre) > 0), as a plain geometric test
func front_faces() -> Array:
	var out := []
	for fi in ui.mesh.face_count():
		var wc: Vector3 = ui.view.global_transform * ui.mesh.face_center(fi)
		if ui.mesh.face_normals[fi].dot(m.cam.global_position - wc) > 1e-6:
			out.append(fi)
	return out


func vert_front(v: int) -> bool:
	for fi in ui.mesh.vert_faces(v):
		var wc: Vector3 = ui.view.global_transform * ui.mesh.face_center(fi)
		if ui.mesh.face_normals[fi].dot(m.cam.global_position - wc) > 1e-6:
			return true
	return false


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	ok(ui.on and ui.view != null and ui.mesh.vert_count() == 98 and ui.mesh.face_count() == 96 and ui.mesh.edge_count() == 192 and ui.mesh.is_closed(),
		"the dev command opens the cube: %d verts, %d faces, %d edges, closed %s (expect 98 / 96 / 192 / true)" % [ui.mesh.vert_count(), ui.mesh.face_count(), ui.mesh.edge_count(), ui.mesh.is_closed()])

	# the camera on the cube's axis, 2.4 m away, looking at its centre
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)   # a little low in the frame: the top row of cells is clear of the ribbon
	await idle(4)
	var off: Vector3 = m.cam.global_position - wc
	var ax := 0
	for i in 3:
		if absf(off[i]) > absf(off[ax]):
			ax = i
	var onaxis := true
	for i in 3:
		if i != ax and i != 1 and absf(off[i]) > 1e-3:   # (y is the 0.12 m the view is lifted by; it stays below the top face, 0.3 m)
			onaxis = false
	print("camera offset from the cube: %s (axis %d, on axis %s)" % [off, ax, onaxis])
	ok(onaxis, "the front camera sits on the cube's axis")
	var fronts := front_faces()
	var cfront := scr(wc + Vector3(0, 0, 0.3))   # the front face's centre (the camera looks down -z, the view does not sit at the screen centre)
	var cx := cfront.x   # the front plane's x = 0 column: the split line (nearer verts shift more off-axis than far ones)
	print("front faces: %d, centre of the cube on screen: %s of %s" % [fronts.size(), scr(wc), root.get_visible_rect().size])
	ok(fronts.size() == 16, "from the front exactly 16 faces face the camera (%d)" % fronts.size())

	# ---- bar 1
	await key(KEY_3)
	ok(ui.sel.mode == KMeshSelect.FACE, "key 3 (a real key event) is face mode")
	var good := 0
	for fi in fronts:
		await click(fc(fi))
		if ui.sel.faces.size() == 1 and ui.sel.faces.has(fi):
			good += 1
		else:
			print("  bar 1 miss: face %d at %s selected %s" % [fi, fc(fi), ui.sel.faces.keys()])
	ok(good == 16, "bar 1: a click at the projected centre of each front cell selects exactly that face: %d of 16" % good)
	await click(fc(fronts[0]))
	await click(fc(fronts[5]), true)
	var two: int = ui.sel.faces.size()
	await click(fc(fronts[5]), true)
	var one: int = ui.sel.faces.size()
	ok(two == 2 and one == 1 and ui.sel.faces.has(fronts[0]), "Shift+click adds (%d, expect 2), Shift+click again toggles it off (%d, expect 1)" % [two, one])
	await click(scr(wc + Vector3(0.8, 0, 0)))
	ok(ui.sel.faces.is_empty(), "a click on empty space clears (%d selected)" % ui.sel.faces.size())

	# ---- bar 2
	await key(KEY_1)
	ok(ui.sel.mode == KMeshSelect.VERT, "key 1 is vert mode")
	var fverts := {}
	for fi in fronts:
		for v in ui.mesh.faces[fi]:
			fverts[v] = true
	var vgood := 0
	for v in fverts:
		var sv := scr(world(v))
		var inward := (cfront - sv)
		inward = inward.normalized() * 11.0 if inward.length() > 1.0 else Vector2(11, 0)   # toward the face's centre: stays on the face
		await click(sv + inward)
		if ui.sel.verts.size() == 1 and ui.sel.verts.has(v):
			vgood += 1
	ok(fverts.size() == 25 and vgood == 25, "bar 2: a click 11 px from each of the %d front verts picks exactly it: %d of 25" % [fverts.size(), vgood])
	var none_ok := 0
	for fi in fronts.slice(0, 6):
		await click(fc(fi))
		if ui.sel.verts.is_empty():
			none_ok += 1
	ok(none_ok == 6, "a click in a cell centre, > 12 px from every corner, picks no vert: %d of 6" % none_ok)
	var cell_px := scr(world(ui.mesh.faces[fronts[0]][0])).distance_to(scr(world(ui.mesh.faces[fronts[0]][1])))
	print("cell side on screen: %.1f px" % cell_px)
	await key(KEY_2)
	ok(ui.sel.mode == KMeshSelect.EDGE, "key 2 is edge mode")
	var fedges := {}
	for fi in fronts:
		for e in ui.sel.face_edges(fi):
			fedges[e] = true
	var egood := 0
	for e in fedges:
		var em := (scr(world(e.x)) + scr(world(e.y))) * 0.5
		await click(em + (cfront - em).normalized() * 1.5 if em.distance_to(cfront) > 2.0 else em)
		if ui.sel.edges.size() == 1 and ui.sel.edges.has(e):
			egood += 1
	ok(fedges.size() == 40 and egood == 40, "an edge-midpoint click selects exactly that edge: %d of %d front-face edges (expect 40 of 40)" % [egood, fedges.size()])

	# ---- bar 3
	var H: float = root.get_visible_rect().size.y
	var left := Rect2(480, 170, cx - 2.0 - 480, 520)   # clear of the panels, taller than the cube
	await key(KEY_1)
	ui.sel.clear()
	var n_no := ui.view.select_box(m.cam, left, false)
	var exp_no := 0
	var exp_x := 0
	for v in ui.mesh.vert_count():
		if left.has_point(scr(world(v))):
			exp_x += 1
			if vert_front(v):
				exp_no += 1
	var n_x := ui.view.select_box(m.cam, left, true)
	ok(n_no == 10 and exp_no == 10, "bar 3: box over the left half, no x-ray: %d verts (oracle %d, expect 10)" % [n_no, exp_no])
	ok(n_x == 41 and exp_x == 41, "bar 3: same box with x-ray: %d verts (oracle %d, expect 41)" % [n_x, exp_x])
	var tri := PackedVector2Array([left.position, Vector2(left.end.x, left.position.y), left.end, Vector2(left.position.x, left.end.y)])
	var l_no := ui.view.select_lasso(m.cam, tri, false)
	var l_x := ui.view.select_lasso(m.cam, tri, true)
	ok(l_no == 10 and l_x == 41, "lasso of the same half: %d without x-ray, %d with (expect 10 / 41)" % [l_no, l_x])
	# the same through real events: B, drag a box; X toggles x-ray
	ui.sel.clear()
	await key(KEY_B)
	await drag(left.position, left.end)
	var ev_no: int = ui.sel.verts.size()
	await key(KEY_X)
	await key(KEY_B)
	await drag(left.position, left.end)
	var ev_x: int = ui.sel.verts.size()
	ok(ui.xray and ev_no == 10 and ev_x == 41, "B + drag + X through real events: %d then %d with x-ray on (expect 10 / 41)" % [ev_no, ev_x])
	await key(KEY_X)
	ui.sel.set_mode(KMeshSelect.FACE)
	var f_no := ui.view.select_box(m.cam, left, false)
	var f_x := ui.view.select_box(m.cam, left, true)
	ok(f_no == 8 and f_x == 48, "face mode, same box: %d faces without x-ray, %d with (expect 8 / 48)" % [f_no, f_x])

	# ---- bar 4: the whole-body view
	ui.sel.clear()
	m._turn_to(30.0, -10.0, 4.6, Vector3(0.5, 0.95, 0.1), false)
	await idle(4)
	var fr := front_faces()
	# the most camera-facing face and the cell next to its centre
	var best := -1
	var bd := -2.0
	for fi in fr:
		var wcn: Vector3 = ui.view.global_transform * ui.mesh.face_center(fi)
		var d: float = ui.mesh.face_normals[fi].dot((m.cam.global_position - wcn).normalized())
		if d > bd:
			bd = d
			best = fi
	var nrm: Vector3 = ui.mesh.face_normals[best]
	var same := []
	for fi in ui.mesh.face_count():
		if ui.mesh.face_normals[fi].dot(nrm) > 0.99:
			same.append(fi)
	same.sort_custom(func(a, b): return ui.mesh.face_center(a).distance_to(ui.mesh.face_center(best)) < ui.mesh.face_center(b).distance_to(ui.mesh.face_center(best)))
	var fsel: int = same[0]
	var funs: int = same[3]   # a cell two steps away on the same big face
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.faces[fsel] = true
	ui.view.mark_dirty()
	# the wire edge: an edge of the big face, between two unselected cells, not touching fsel
	var wedge := Vector2i(-1, -1)
	for e in ui.mesh.edges():
		var ef := ui.sel.edge_faces(e.x, e.y)
		if ef.size() == 2 and same.has(ef[0]) and same.has(ef[1]) and ef[0] != fsel and ef[1] != fsel and ef[0] != funs and ef[1] != funs:
			var mid: Vector3 = (ui.mesh.verts[e.x] + ui.mesh.verts[e.y]) * 0.5
			if mid.distance_to(ui.mesh.face_center(fsel)) > 0.2:
				wedge = e
				break
	m.ui_root.visible = false
	var img_with := await shot()
	var wpos: Vector3 = ui.view.global_position
	ok(wpos.distance_to(m.stage_root.global_transform * C) < 1e-3, "placement: the view is at the stage position %s (got %s)" % [m.stage_root.global_transform * C, wpos])
	var lowest := 1e9
	var inframe := true
	var W: float = root.get_visible_rect().size.x
	for i in 8:
		var cw: Vector3 = wpos + Vector3(0.3 if i & 1 else -0.3, 0.3 if i & 2 else -0.3, 0.3 if i & 4 else -0.3)
		lowest = minf(lowest, cw.y)
		var sp := scr(cw)
		if sp.x < 0 or sp.y < 0 or sp.x > W or sp.y > H:
			inframe = false
	ok(absf(lowest) < 1e-3 and inframe, "placement: rests on the floor (lowest corner y %.4f) and all 8 corners are in the frame" % lowest)
	var pc := scr(wpos)
	ui.view.visible = false
	var img_without := await shot()
	ui.view.visible = true
	var cpx := Vector2i(int(pc.x), int(pc.y))
	ok(dist(img_with.get_pixel(cpx.x, cpx.y), img_without.get_pixel(cpx.x, cpx.y)) > 0.05, "placement: the pixel at the cube's projected centre %s is %s with it, %s without" % [cpx, img_with.get_pixel(cpx.x, cpx.y).to_html(false), img_without.get_pixel(cpx.x, cpx.y).to_html(false)])
	var ps := fc(fsel)
	var pu := fc(funs)
	var csel := img_with.get_pixel(int(ps.x), int(ps.y))
	var cun := img_with.get_pixel(int(pu.x), int(pu.y))
	ok(dist(csel, cun) > 0.1 and (csel.b - csel.r) > (cun.b - cun.r), "placement: selected face centre %s is %s, unselected %s is %s (distance %.2f, bluer)" % [ps, csel.to_html(false), pu, cun.to_html(false), dist(csel, cun)])
	var wl := -1.0
	if wedge.x >= 0:
		var wm := scr((world(wedge.x) + world(wedge.y)) * 0.5)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				wl = maxf(wl, img_with.get_pixel(int(wm.x) + dx, int(wm.y) + dy).get_luminance())
	ok(wedge.x >= 0 and wl > cun.get_luminance() + 0.1, "placement: a wire edge's pixel (max of 3x3) luminance %.2f vs the face beside it %.2f (bar: +0.1)" % [wl, cun.get_luminance()])
	img_with.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/meshview.png")
	print("shot saved: cube at screen %s, selected face %d at %s, unselected %d at %s, wire edge %s" % [pc, fsel, ps, funs, pu, wedge])
	m.ui_root.visible = true

	# ---- bar 5
	await key(KEY_ESCAPE)
	await idle(3)
	var gone := not ui.on and m.stage_root.get_node_or_null("kmesh_view") == null
	ok(gone, "bar 5: Esc leaves; the view is gone from the stage")
	m._kmesh_edit_start()
	await idle(2)
	ok(ui.on and m.stage_root.get_node_or_null("kmesh_view") != null, "the dev command opens it again")

	print("RESULT: ", "FAIL (%d)" % fails if fails > 0 else "PASS")
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
