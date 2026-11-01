extends SceneTree
## godot --path . --position 4000,4000 -s tests/s063_test.gd     (Friday plan 63 FASTEN THESE TWO: two plates picked in Stick together, Fasten these two picks the screw size, length and hole places; scripts/build/part_fasten.gd; needs the CAD DLL)
## Two 40 x 20 x 5 plates, the second lying on the first and shifted 20 mm (a 20 x 20 mm overlap). Real clicks: Stick together, the top plate, the bottom plate, Fasten these two.
## Every number is measured from the BUILT meshes (Part.body_faces / the replay's volumes) and the page written to disk:
##   1 BUTTON  the rule is printed in the panel and Fasten these two shows with the two picks
##   2 SIZE    M3 (plates 5 mm), a 10 mm screw (5 + 5), two screws (head 5.5 mm, 13 mm from tip to the head's top)
##   3 HOLES   two 3.4 mm holes in the first plate, two 2.5 mm pilots in the second; centres >= 6 mm from every edge of the overlap
##   4 AXIS    each screw's axis (tip and head centres) through both hole centres within 0.05 mm
##   5 UNDO    one undo step; undo takes it all back (2 bodies), redo brings it back
##   6 SHEET   the instruction sheet lists "2x M3 x 10"
##   7 APART   plates that do not touch: refused in words, no undo step
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s063"
const DIRT := "user://s063_test"


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
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func body_box(faces: Array, i: int) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in faces[i]:
		var q: Vector2 = m.cam.unproject_position(w)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


## a point inside body i's screen box that the ray hits on body i (not over the Easy panel)
func inside_pt(faces: Array, i: int) -> Vector2:
	var ep = m.bld.part.ep
	var pu = m.bld.part
	var r := body_box(faces, i)
	for fy in [0.5, 0.35, 0.65, 0.25, 0.75]:
		for fx in [0.2, 0.3, 0.5, 0.7, 0.8, 0.4, 0.6]:
			var p: Vector2 = r.position + r.size * Vector2(fx, fy)
			var hit: Dictionary = pu._ray_hit(p, faces)
			if not hit.is_empty() and int(hit["body"]) == i and not ep._over_ui(p):
				return p
	return Vector2(-1, -1)


func set_part(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = feats.size()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(3)


func box_mm(tris) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for w in tris:
		lo = lo.min(w)
		hi = hi.max(w)
	lo = lo / Part.MM
	hi = hi / Part.MM
	return [lo, hi, hi - lo]


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func plates(shift_x: float) -> Array:
	return [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "top", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [40.0, 20.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 5.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f3", "name": "Plane1", "from": "top", "mm": 5.0},
		{"t": "sketch", "id": "f4", "name": "Sketch2", "plane": "f3", "ents": [{"k": "rect", "a": [shift_x, 0.0], "b": [shift_x + 40.0, 20.0]}], "dims": []},
		{"t": "extrude", "id": "f5", "name": "Extrude2", "sketch": "f4", "dist": 5.0, "both": false, "op": "new"}]


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the holes of a plate: the vertices that are not on the plate's outside box edge, clustered by X: [{c: Vector2 (x, z) mm, d: diameter mm}]
func holes_of(tris, bx: Array) -> Array:
	var lo: Vector3 = bx[0]
	var hi: Vector3 = bx[1]
	var cl := {}
	for w in tris:
		var q: Vector3 = w / Part.MM
		var edge := absf(q.x - lo.x) < 0.01 or absf(q.x - hi.x) < 0.01 or absf(q.z - lo.z) < 0.01 or absf(q.z - hi.z) < 0.01
		if not edge:
			var key := int(floor(q.x / 4.0))
			if not cl.has(key):
				cl[key] = []
			cl[key].append(Vector2(q.x, q.z))
	var keys := cl.keys()
	keys.sort()
	var groups: Array = []
	for k in keys:
		if not groups.is_empty() and int(k) - int(groups[-1]["last"]) <= 1:
			groups[-1]["pts"].append_array(cl[k])
			groups[-1]["last"] = k
		else:
			groups.append({"pts": (cl[k] as Array).duplicate(), "last": k})
	var out := []
	for g in groups:
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for q in g["pts"]:
			mn = mn.min(q)
			mx = mx.max(q)
		var c := (mn + mx) * 0.5
		var r := 0.0
		for q in g["pts"]:
			r += (q as Vector2).distance_to(c)
		out.append({"c": c, "d": 2.0 * r / float((g["pts"] as Array).size())})
	return out


## the centre (x, z, mm) of the vertices of a body that lie in a Y band
func band_centre(tris, y0: float, y1: float) -> Vector2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for w in tris:
		var q: Vector3 = w / Part.MM
		if q.y >= y0 and q.y <= y1:
			mn = mn.min(Vector2(q.x, q.z))
			mx = mx.max(Vector2(q.x, q.z))
	return (mn + mx) * 0.5


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	PartSheet.dir = DIRT + "/sheets"
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, Fasten these two cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	await set_part(plates(20.0), "Fasten")
	var faces: Array = Part.body_faces(m.S.part, -1)
	ok(faces.size() == 2, "0 two plates (bodies %d)" % faces.size())
	m.target = Vector3(0.03, 0.005, -0.01)
	m.pitch = 55.0
	m.yaw = 20.0
	m._cam()
	await idle(20)
	faces = Part.body_faces(m.S.part, -1)

	# 1 BUTTON: the top plate (body 1) first, then the bottom one (body 0)
	await click_ctl(ep.make_btns["stick"])
	var pa := Vector2(-1, -1)
	var pb := Vector2(-1, -1)
	for attempt in 4:   # under load the camera can still be easing: pick again from where the plates are now
		await idle(30)
		faces = Part.body_faces(m.S.part, -1)
		pa = inside_pt(faces, 1)
		pb = inside_pt(faces, 0)
		await click_at(pa)
		await click_at(pb)
		if ep.stick_picks.size() == 2:
			break
		await click_ctl(ep.make_btns["stick"])   # off and on again clears the picks
		await click_ctl(ep.make_btns["stick"])
	ok(pa.x >= 0.0 and pb.x >= 0.0 and ep.stick_picks.size() == 2, "1 both plates can be clicked (%s, %s)" % [pa, pb])
	var fb: Button = ep.fasten_btn
	var rule := find_named(m, "easypart_fasten_rule") as Label
	ok(fb != null and fb.is_visible_in_tree() and rule != null and rule.is_visible_in_tree() and rule.text.contains("M3 under 6 mm"),
		"1 two plates picked: Fasten these two shows, with the size rule printed beside it")
	await shot("picked")

	# 2..4 FASTEN
	var ub0: int = m.undo.size()
	await click_ctl(fb)
	await idle(4)
	faces = Part.body_faces(m.S.part, -1)
	ok(m.undo.size() == ub0 + 1, "5 one undo step for the fastening (undo steps %d -> %d), msg '%s'" % [ub0, m.undo.size(), String(ep.msg)])
	ok(faces.size() == 4, "2 four bodies: two plates and two screws (bodies %d)" % faces.size())
	if faces.size() != 4:
		print("s063: %d fail" % fails)
		quit(1)
		return
	var bxa := box_mm(faces[0])
	var bxb := box_mm(faces[1])
	ok(near(bxa[2].x, 40.0, 0.05) and near(bxa[2].y, 5.0, 0.05) and near(bxb[2].x, 40.0, 0.05) and near(bxb[2].y, 5.0, 0.05), "2 the plates are still 40 x 5 mm (%s, %s)" % [bxa[2], bxb[2]])
	for si in [2, 3]:
		var bs := box_mm(faces[si])
		var sz: Vector3 = bs[2]
		ok(near(sz.x, 5.5, 0.1) and near(sz.z, 5.5, 0.1) and near(sz.y, 13.0, 0.05) and near(bs[0].y, 0.0, 0.05),
			"2 screw %d is M3 x 10: head %.2f mm across, %.2f mm tip to head top, tip at Y %.2f" % [si - 1, sz.x, sz.y, bs[0].y])
	var hole_a := holes_of(faces[1], bxb)   # the first plate clicked is the top plate (body 1)
	var hole_b := holes_of(faces[0], bxa)
	ok(hole_a.size() == 2 and hole_b.size() == 2, "3 two holes in each plate (%d, %d)" % [hole_a.size(), hole_b.size()])
	if hole_a.size() == 2 and hole_b.size() == 2:
		for h in hole_a:
			ok(near(h["d"], 3.4, 0.08), "3 clearance hole in the first plate is %.2f mm (want 3.4)" % h["d"])
		for h in hole_b:
			ok(near(h["d"], 2.5, 0.08), "3 pilot hole in the second plate is %.2f mm (want 2.5)" % h["d"])
		for h in hole_a + hole_b:
			var c: Vector2 = h["c"]
			var edge := minf(minf(c.x - 20.0, 40.0 - c.x), minf(c.y + 20.0, 0.0 - c.y))   # the overlap: X 20..40, Z -20..0
			ok(edge >= 6.0 - 0.05, "3 hole centre (%.2f, %.2f) is %.2f mm from the nearest edge of the overlap (>= 6)" % [c.x, c.y, edge])
		for k in 2:
			var sc: Vector2 = band_centre(faces[2 + k], 0.0, 0.2)
			var sh: Vector2 = band_centre(faces[2 + k], 12.8, 13.0)
			var best := INF
			for h in hole_a:
				best = minf(best, sc.distance_to(h["c"]))
			var best2 := INF
			for h in hole_b:
				best2 = minf(best2, sc.distance_to(h["c"]))
			ok(best < 0.05 and best2 < 0.05 and sc.distance_to(sh) < 0.05, "4 screw %d axis: tip %.3f mm from its hole in the first plate, %.3f from the pilot, head %.3f off the tip's line" % [k + 1, best, best2, sc.distance_to(sh)])
	var vols: Array = Part.replay(m.S.part)["volumes"]
	var va := float(vols[1]) / pow(Part.MM, 3.0)
	var vb := float(vols[0]) / pow(Part.MM, 3.0)
	var want_a := 40.0 * 20.0 * 5.0 - 2.0 * PI * 1.7 * 1.7 * 5.0
	var want_b := 40.0 * 20.0 * 5.0 - 2.0 * PI * 1.25 * 1.25 * 5.0
	ok(absf(va - want_a) < want_a * 0.01 and absf(vb - want_b) < want_b * 0.01, "2 volumes: first plate %.0f (want %.0f), second plate %.0f (want %.0f) mm3" % [va, want_a, vb, want_b])
	await shot("fastened")

	# 6 SHEET
	var sheet_btn := find_named(m, "easypart_sheet") as Button
	m.last_shell = ""
	if sheet_btn != null:
		await click_ctl(sheet_btn)
		await idle(60)
	var html := FileAccess.get_file_as_string(String(m.last_shell)) if String(m.last_shell) != "" else ""
	ok(html.contains("2x M3 x 10"), "6 the instruction sheet lists 2x M3 x 10 (page %d bytes)" % html.length())

	# 5 UNDO
	m._undo()
	await idle(3)
	var n_undo := Part.body_faces(m.S.part, -1).size()
	ok(n_undo == 2, "5 one undo takes the screws and holes off (bodies %d)" % n_undo)
	m._redo()
	await idle(3)
	ok(Part.body_faces(m.S.part, -1).size() == 4, "5 redo brings them back (bodies %d)" % Part.body_faces(m.S.part, -1).size())

	# 7 APART
	await set_part(plates(80.0), "Apart")
	m.target = Vector3(0.06, 0.005, -0.01)
	m._cam()
	await idle(20)
	faces = Part.body_faces(m.S.part, -1)
	if ep.armed != "stick":
		await click_ctl(ep.make_btns["stick"])
	await idle(30)
	faces = Part.body_faces(m.S.part, -1)
	await click_at(inside_pt(faces, 0))
	await click_at(inside_pt(faces, 1))
	var ub1: int = m.undo.size()
	fb = ep.fasten_btn
	if fb != null and fb.is_visible_in_tree():
		await click_ctl(fb)
	ok(m.undo.size() == ub1 and Part.body_faces(m.S.part, -1).size() == 2, "7 plates apart: refused in words (msg '%s'), no undo step, nothing added" % String(ep.msg))

	print("s063: %d fail" % fails)
	quit(1 if fails > 0 else 0)
