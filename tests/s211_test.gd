extends SceneTree
## s211 DRAW ON A CURVED FACE (Nick 11-01): a press on a cylinder or a sphere with Draw armed puts the sketch on the TANGENT plane at the clicked point
## (origin = the surface point, normal = the surface normal, x = the cylinder's axis), centred on the click; Pull it up / Cut a hole grow from or into the curved surface.
## Bars (real clicks at 1280x720, measured from the built mesh and the kernel volume):
##   a  rod 10 mm along x, a 6 x 20 mm box drawn on its TOP at the middle, Pull it up 3 mm: ONE body, top at 5+3 = 8 mm (0.1), centred on the click (0.2), long side along the axis (0.5 deg)
##   b  the same on the rod's SIDE (+z): the box sticks out along +z, top at z = 8 mm
##   c  sphere 30 mm, a round (radius 6 mm) at its top, Cut a hole 4 mm: removed volume within 2 pct of the analytic cap-and-cylinder volume
##   e  each of draw / pull / cut is ONE undo step; the words "Drawing on the curved side: the shape sits flat where you clicked" are said
## shots: C:/Temp/claude/s211/ (rod_top.png the box on the rod, sphere_hole.png)
const SHOT := "C:/Temp/claude/s211"
const DIRT := "user://s211_test"
var fails := 0
var m: Node
var alt := true
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.alt_pressed = alt
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame
func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.alt_pressed = alt
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
func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)
func idle(n := 3) -> void:
	for i in n:
		await process_frame
func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)
func res() -> Dictionary:
	m.bld.part.sync()
	return m.bld.part.res
func mm3(v: float) -> float:
	return v / (Part.MM * Part.MM * Part.MM)
## every mesh vertex of the result (metres)
func verts() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = res().get("mesh")
	for s in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out
func put(feats: Array) -> void:
	var pu = m.bld.part
	var rec: Dictionary = pu._ensure()
	rec["features"] = []
	rec["seq"] = 0
	for f in feats:
		var nf := Part.new_feature(rec, String(f["t"]), f["fields"])
		rec["features"].append(nf)
	pu.upto = -1
	pu.sync()
	pu.ep._rows_sync()
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
	var pu = m.bld.part
	var ep = pu.ep
	ok(pu.on and pu.easy, "0 Easy Part is on (page %s)" % m.cur_page)

	# ---- a: the rod along x, a box on its top
	put([
		{"t": "sketch", "fields": {"plane": "right", "ents": [{"k": "circle", "c": [0.0, 0.0], "r": 5.0}], "dims": []}},
		{"t": "extrude", "fields": {"sketch": "f1", "dist": 100.0, "both": false, "op": "new"}},
	])
	var r0 := res()
	ok(int(r0.get("bodies", 0)) == 1 and absf(float(r0["aabb"].size.x) * 1000.0 - 100.0) < 0.5, "a0 the rod: 1 body, %.1f mm long" % (float(r0["aabb"].size.x) * 1000.0))
	m.target = Vector3(0.05, 0.0, 0.0)
	m.pitch = -80.0
	m.yaw = 0.0
	m.dist = 0.12
	m._cam()
	await idle(40)
	var click := Vector3(0.05, 0.005, 0.0)
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	var say_ok := false
	await ev_move(scr(click), false)
	await ev_mouse(scr(click), true)
	say_ok = ep.hint_l.text.contains("Drawing on the curved side: the shape sits flat where you clicked")
	var square_seen: bool = not ep._draft.is_empty() and bool(ep._draft.get("curved", false))
	await ev_move(scr(Vector3(0.056, 0.005, 0.003)))
	await ev_move(scr(Vector3(0.060, 0.005, 0.003)))
	await shot("rod_drawing")
	await ev_mouse(scr(Vector3(0.060, 0.005, 0.003)), false)
	await idle(3)
	await click_ctl(ep.make_btns["draw"])
	var ud: int = m.undo.size() - ub
	var pl_f := Part.feature(ep._rec(), "f3")
	ok(say_ok and square_seen, "a1 the words are said and the draft is on the curved face (said: %s, draft curved: %s) [%s]" % [say_ok, square_seen, ep.hint_l.text])
	ok(String(pl_f.get("from", "")) == "tan" and absf(float(pl_f["surf"]["r"]) - 5.0) < 0.01, "a2 the plane is a tangent plane fitted to a rod of radius %s mm (feature %s)" % [str(pl_f.get("surf", {}).get("r", "?")), JSON.stringify(pl_f)])
	var ub2: int = m.undo.size()
	await click_ctl(ep.make_btns["pull"])
	ep._set_value({"kind": "x"}, 0.3, true)
	await idle(6)
	var r1 := res()
	var vs := verts()
	var hi := PackedVector3Array()
	for v in vs:
		if v.y > 0.0052:
			hi.append(v)
	var top := 0.0
	var lo := Vector3(INF, INF, INF)
	var up := Vector3(-INF, -INF, -INF)
	for v in hi:
		top = maxf(top, v.y)
		lo = lo.min(v)
		up = up.max(v)
	var ctr := (lo + up) * 0.5
	# the long edge of the top face: from a top corner to the nearest other corner that is the long side away
	var tv := PackedVector3Array()
	for v in hi:
		var dup := false
		for w in tv:
			if w.distance_to(v) < 1e-6:
				dup = true
		if v.y > top - 0.0001 and not dup:
			tv.append(v)
	var ang := 90.0
	if tv.size() >= 4:
		var ds: Array = []
		for k in range(1, tv.size()):
			ds.append(tv[0].distance_to(tv[k]))
		ds.sort()
		var long_d: float = ds[1]
		for k in range(1, tv.size()):
			if absf(tv[0].distance_to(tv[k]) - long_d) < 0.0002:
				var d := (tv[k] - tv[0]).normalized()
				ang = rad_to_deg(acos(clampf(absf(d.x), 0.0, 1.0)))
	ok(int(r1.get("bodies", 0)) == 1 and (r1.get("errors", {}) as Dictionary).is_empty(), "a3 Pull it up: ONE body (bodies %d, errors %s) [%s]" % [int(r1.get("bodies", 0)), r1.get("errors", {}), ep.hint_l.text])
	ok(absf(top * 1000.0 - 8.0) < 0.1, "a4 the box top is %.3f mm above the axis (want 8.0 +-0.1)" % (top * 1000.0))
	ok(Vector2(ctr.x - 0.05, ctr.z).length() * 1000.0 < 0.2, "a5 centred on the click: off by %.3f mm (centre x %.2f z %.2f mm)" % [Vector2(ctr.x - 0.05, ctr.z).length() * 1000.0, ctr.x * 1000.0, ctr.z * 1000.0])
	ok(ang < 0.5 and (up.x - lo.x) > (up.z - lo.z), "a6 long side along the rod axis within %.2f deg (box %.1f x %.1f mm)" % [ang, (up.x - lo.x) * 1000.0, (up.z - lo.z) * 1000.0])
	ok(ud == 1 and m.undo.size() - ub2 == 1, "a7 ONE undo step for the drawing (%d) and ONE for the pull (%d)" % [ud, m.undo.size() - ub2])
	await shot("rod_top")

	# ---- b: the rod's side (+z)
	put([
		{"t": "sketch", "fields": {"plane": "right", "ents": [{"k": "circle", "c": [0.0, 0.0], "r": 5.0}], "dims": []}},
		{"t": "extrude", "fields": {"sketch": "f1", "dist": 100.0, "both": false, "op": "new"}},
	])
	m.pitch = 0.0
	m._cam()
	await idle(30)
	click = Vector3(0.05, 0.0, 0.005)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(click), scr(Vector3(0.056, 0.003, 0.005)), scr(Vector3(0.060, 0.003, 0.005))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	ep._set_value({"kind": "x"}, 0.3, true)
	await idle(6)
	var r2 := res()
	var zt := 0.0
	var zlo := Vector3(INF, INF, INF)
	var zup := Vector3(-INF, -INF, -INF)
	for v in verts():
		if v.z > 0.0052:
			zt = maxf(zt, v.z)
			zlo = zlo.min(v)
			zup = zup.max(v)
	var zc := (zlo + zup) * 0.5
	ok(int(r2.get("bodies", 0)) == 1 and absf(zt * 1000.0 - 8.0) < 0.1 and Vector2(zc.x - 0.05, zc.y).length() * 1000.0 < 0.2 and (zup.x - zlo.x) > (zup.y - zlo.y),
		"b the side box: ONE body (%d), top at z = %.3f mm, centred off by %.3f mm, %.1f x %.1f mm (long along x)" % [int(r2.get("bodies", 0)), zt * 1000.0, Vector2(zc.x - 0.05, zc.y).length() * 1000.0, (zup.x - zlo.x) * 1000.0, (zup.y - zlo.y) * 1000.0])
	await shot("rod_side")

	# ---- c: a sphere of 30 mm, a round at its top, Cut a hole 4 mm
	put([
		{"t": "sketch", "fields": {"plane": "front", "ents": [{"k": "arc", "a": [0.0, 0.0], "m": [15.0, 15.0], "b": [30.0, 0.0]}, {"k": "line", "a": [30.0, 0.0], "b": [0.0, 0.0]}], "dims": []}},
		{"t": "revolve", "fields": {"sketch": "f1", "axis": "x", "deg": 360.0, "op": "new"}},
	])
	var r3 := res()
	var v_sph := mm3(float(r3.get("volume", 0.0)))
	ok(int(r3.get("bodies", 0)) == 1 and absf(v_sph - 4.0 / 3.0 * PI * 3375.0) < 0.01 * 14137.0, "c0 the ball: 1 body, %.0f mm3 (want %.0f)" % [v_sph, 4.0 / 3.0 * PI * 3375.0])
	m.target = Vector3(0.015, 0.0, 0.0)
	m.pitch = -80.0
	m.dist = 0.1
	m._cam()
	await idle(30)
	click = Vector3(0.0155, sqrt(225.0 - 0.25) / 1000.0, 0.0)   # the ball is spun about x: its top is on the equator, clear of both poles (a cut tool round a pole upsets the kernel)
	var ub3: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(click), scr(Vector3(0.0185, 0.015, 0.0)), scr(Vector3(0.0215, 0.015, 0.0))])
	await click_ctl(ep.make_btns["draw"])
	var ud3: int = m.undo.size() - ub3
	var v_before := mm3(float(res().get("volume", 0.0)))
	var pf3 := Part.feature(ep._rec(), "f3")
	var ub4: int = m.undo.size()
	await click_ctl(ep.make_btns["hole"])
	ep._set_value({"kind": "x"}, 0.4, true)
	await idle(6)
	var r4 := res()
	var removed := v_before - mm3(float(r4.get("volume", 0.0)))
	# the analytic volume from the record's own plane and circle: the part of the 15 mm ball inside the cylinder (radius r, axis = the plane normal)
	# between the tangent plane and 4 mm below it; summed over a fine grid of the circle, each ray's chord through the ball clipped to 0..4 mm
	var pr := Part.tangent_plane(Part.feature(ep._rec(), "f3"))
	var rc := float(Part.feature(ep._rec(), "f4")["ents"][0]["r"])
	var want := 0.0
	var cen := Vector3(15.0, 0.0, 0.0)
	var o3: Vector3 = (pr["o"] as Vector3) / Part.MM
	var nn: Vector3 = pr["n"]
	var gn := 300
	var cell := (2.0 * rc / gn) * (2.0 * rc / gn)
	for iu in gn:
		for iv in gn:
			var u := -rc + (iu + 0.5) * 2.0 * rc / gn
			var v := -rc + (iv + 0.5) * 2.0 * rc / gn
			if u * u + v * v > rc * rc:
				continue
			var p0: Vector3 = o3 + (pr["x"] as Vector3) * u + (pr["y"] as Vector3) * v   # on the plane; the ray goes along -n
			var oc := p0 - cen
			var bq := oc.dot(-nn)
			var disc := bq * bq - (oc.length_squared() - 225.0)
			if disc <= 0.0:
				continue
			var t0 := maxf(-bq - sqrt(disc), 0.0)
			var t1 := minf(-bq + sqrt(disc), 4.0)
			want += maxf(t1 - t0, 0.0) * cell
	ok(String(pf3.get("from", "")) == "tan" and absf(float(pf3["surf"]["r"]) - 15.0) < 0.05, "c1 the plane is a tangent plane on a ball of radius %s mm" % str(pf3.get("surf", {}).get("r", "?")))
	ok(int(r4.get("bodies", 0)) == 1 and absf(removed - want) <= 0.02 * want, "c2 Cut a hole 4 mm: removed %.1f mm3, analytic %.1f mm3 (%.2f pct), bodies %d, errors %s [%s]" % [removed, want, 100.0 * (removed - want) / want, int(r4.get("bodies", 0)), r4.get("errors", {}), ep.hint_l.text])
	ok(ud3 == 1 and m.undo.size() - ub4 == 1, "c3 ONE undo step for the drawing (%d) and ONE for the cut (%d)" % [ud3, m.undo.size() - ub4])
	await shot("sphere_hole")
	print("s211: %d fail" % fails)
	quit(1 if fails > 0 else 0)
