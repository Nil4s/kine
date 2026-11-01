extends SceneTree
## s051 (Friday plan 51, Kine's own): Array fill. Cut a hole > Fill the face: pick the hole shape (Round / Square / Hex), the size, the spacing and
## the edge margin, click a flat face, and the app computes how many holes fit and cuts them all through: ONE solid, ONE undo step.
## godot --path . --position 4000,4000 -s tests/s051_test.gd     (needs a window and the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720; a 100 x 60 x 3 mm plate from the Plate chip, a face click on its top):
##   COUNT    5 mm round holes, 10 mm spacing, 5 mm margin: the count = the analytic count (9 x 5 = 45, printed), read off the record AND the built mesh
##   MARGIN   every hole centre >= margin + radius (7.5 mm) from the face edge (stored centres), every vertex of every hole in the mesh >= margin from the edge
##   VOLUME   the volume drop = count x pi r^2 x 3 within 0.5 %, ONE solid, no kernel errors
##   STEPS    the fill = one undo step and no extra build step; one Undo click gives the single hole back; chips and sliders = one step each
##   HEX      Staggered: rows 0.866 x spacing apart, the staggered count (6 rows x 9 = 54), Hex holes (48) and Square (54), volume within 0.5 %
##   SMALL    a face too small for one hole: a plain message, no undo step, the record unchanged
## Shots in C:/Temp/claude/s051/ . Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s051"
const DIRT := "user://s051_test"


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
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## a fresh 100 x 60 x 3 mm plate from the Plate chip (Width, Length and Thickness sliders in cm), then Cut a hole (the single hole)
func fresh_plate(ep: EasyPart) -> void:
	m.S.part = {}   # start over: no part, no hole chips (the state the first plate was made from)
	ep.hole_base = {}
	ep.tweak = {}
	ep.fill_pick = false
	ep._rows_sig = ""
	ep.pu.sync()
	await idle(6)
	await click_ctl(ep.chips["plate"])
	await idle(3)
	for r in ep.rows:
		if String(r["key"]) == "width":
			(r["slider"] as HSlider).value = 10.0
		elif String(r["key"]) == "length":
			(r["slider"] as HSlider).value = 6.0
		elif String(r["key"]) == "thickness":
			(r["slider"] as HSlider).value = 0.3
	await idle(4)
	await click_ctl(ep.make_btns["hole"])
	await idle(4)


func set_fl(ep: EasyPart, key: String, v: float) -> void:
	for r in ep.fill_rows:
		if String(r["key"]) == key:
			(r["slider"] as HSlider).value = v
	await idle(4)


func hbtn(ep: EasyPart, nm: String) -> Button:
	return ep.hole_box.find_child("easypart_hole_" + nm, true, false) as Button


func fbtn(ep: EasyPart, nm: String) -> Button:
	return ep.hole_box.find_child("easypart_fillshape_" + nm, true, false) as Button


func vol_mm3() -> float:
	return float(Part.replay(m.S.part)["volume"]) * 1e9


## the sketch of the fill (the record)
func fill_sk(ep: EasyPart) -> Dictionary:
	return Part.feature(m.S.part, ep.hole_id)


func fill_count(ep: EasyPart) -> int:
	return int(fill_sk(ep).get("fill", {}).get("count", -1))


## the stored centres of a fill (plate mm: the Front plane's own x, y)
func stored_centres(ep: EasyPart) -> Array:
	var out: Array = []
	var shape := String(fill_sk(ep).get("fill", {}).get("shape", "round"))
	var ents: Array = fill_sk(ep)["ents"]
	if shape == "round":
		for e in ents:
			out.append(Part.v2(e["c"]))
	elif shape == "square":
		for e in ents:
			out.append((Part.v2(e["a"]) + Part.v2(e["b"])) * 0.5)
	else:
		var i := 0
		while i + 5 < ents.size():
			var s := Vector2.ZERO
			for k in 6:
				s += Part.v2(ents[i + k]["a"])
			out.append(s / 6.0)
			i += 6
	return out


## the holes found on the BUILT mesh: the vertices on the top face (z = the plate's top) that are not on the plate's outline, joined into holes
## (single linkage: two vertices closer than `link` mm are one hole). Each: {"c": the middle of its vertices, "n": vertices, "edge": the closest any
## vertex comes to the plate's outline in mm}
func mesh_holes(link: float) -> Array:
	var r := Part.replay(m.S.part)
	var bb: AABB = r["aabb"]
	var top := bb.end.z / Part.MM
	var x0 := bb.position.x / Part.MM
	var x1 := bb.end.x / Part.MM
	var y0 := bb.position.y / Part.MM
	var y1 := bb.end.y / Part.MM
	var verts: PackedVector3Array = (r["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var seen := {}
	var pts: Array = []
	for v in verts:
		var q := v / Part.MM
		if absf(q.z - top) > 0.01:
			continue
		if absf(q.x - x0) < 0.01 or absf(q.x - x1) < 0.01 or absf(q.y - y0) < 0.01 or absf(q.y - y1) < 0.01:
			continue
		var k := Vector2i(roundi(q.x * 100.0), roundi(q.y * 100.0))
		if seen.has(k):
			continue
		seen[k] = true
		pts.append(Vector2(q.x, q.y))
	var parent := range(pts.size())
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if (pts[i] as Vector2).distance_to(pts[j]) < link:
				parent[find.call(i)] = find.call(j)
	var groups := {}
	for i in pts.size():
		var rt: int = find.call(i)
		if not groups.has(rt):
			groups[rt] = []
		(groups[rt] as Array).append(pts[i])
	var out: Array = []
	for g in groups.values():
		var s := Vector2.ZERO
		var edge := INF
		for p in g:
			s += p
			edge = minf(edge, minf(minf((p as Vector2).x - x0, x1 - (p as Vector2).x), minf((p as Vector2).y - y0, y1 - (p as Vector2).y)))
		out.append({"c": s / float(g.size()), "n": g.size(), "edge": edge})
	return out


## the analytic count on a W x H face: holes reach rx / ry from their middle, margin mg, spacing s
func analytic(W: float, H: float, rx: float, ry: float, mg: float, s: float, stag: bool) -> int:
	var ux := W - 2.0 * (mg + rx)
	var uy := H - 2.0 * (mg + ry)
	if ux < 0.0 or uy < 0.0:
		return 0
	if stag:
		var rows := int(floor(uy / (s * 0.8660254) + 1e-9)) + 1
		var per := (int(floor((ux - s * 0.5) / s + 1e-9)) + 1) if ux >= s * 0.5 else 1
		return rows * per
	return (int(floor(ux / s + 1e-9)) + 1) * (int(floor(uy / s + 1e-9)) + 1)


## a screen point whose press lands well inside the plate's top face (the app's own face pick, scanned over the free view; the plate is moved,
## camera only, to the open area at the lower left)
func find_face_point(ep: EasyPart, move_cam: bool) -> Vector2:
	if move_cam:
		ep.frame()
		await idle(40)
		var cen3: Vector3 = (Part.replay(m.S.part)["aabb"] as AABB).get_center()
		var want_px := Vector2(340.0, 590.0)
		m.dist = float(m.dist) * 0.55
		m._cam()
		await idle(4)
		for it in 3:
			var s0: Vector2 = m.cam.unproject_position(cen3)
			var ppx: float = 2.0 * float(m.dist) * tan(deg_to_rad(m.cam.fov * 0.5)) / 720.0
			var bas: Basis = m.cam.global_basis
			m.target += bas.x * (-(want_px.x - s0.x) * ppx) + bas.y * ((want_px.y - s0.y) * ppx)
			m._cam()
			await idle(4)
		await idle(20)
	var covers: Array = [ep.hole_box, ep.panel, ep.steps_box]
	var best := Vector2(-1, -1)
	var best_d := 1e9
	var yy := 300.0
	while yy < 700.0:
		var xx := 6.0
		while xx < 780.0:
			var covered := false
			for cv in covers:
				if (cv as Control).visible and (cv as Control).get_global_rect().has_point(Vector2(xx, yy)):
					covered = true
			if not covered:
				var fc: Dictionary = ep._face_hit_at(Vector2(xx, yy))
				if fc.has("hit") and String(fc.get("base", "")) == "front" and int(fc.get("out", 0)) == 1:
					var q: Vector3 = (fc["hit"] as Vector3) / Part.MM
					var dd := Vector2(q.x, q.y).distance_to(Vector2(50, 30))
					if q.x > 15.0 and q.x < 85.0 and q.y > 15.0 and q.y < 45.0 and dd < best_d:
						best_d = dd
						best = Vector2(xx, yy)
			xx += 4.0
		yy += 4.0
	return best


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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var T := 3.0   # plate thickness mm
	var R := 2.5   # hole radius mm (5 mm round holes)

	# ---- the plate and the single hole
	await fresh_plate(ep)
	var one_v := vol_mm3()   # the Cut a hole press already made a single hole: that is the step the fill replaces
	var bb0: AABB = Part.replay(m.S.part)["aabb"]
	ok(absf(bb0.size.x / Part.MM - 100.0) < 0.01 and absf(bb0.size.y / Part.MM - 60.0) < 0.01 and absf(bb0.size.z / Part.MM - T) < 0.01,
		"0 PLATE: %.2f x %.2f x %.2f mm (want 100 x 60 x 3)" % [bb0.size.x / Part.MM, bb0.size.y / Part.MM, bb0.size.z / Part.MM])
	var feats_hole: int = m.S.part["features"].size()
	# the plate without the hole: Undo is not used; the base record the chips rebuild from
	var plate_v := float(Part.replay(ep.hole_base)["volume"]) * 1e9
	var fb := hbtn(ep, "fill")
	ok(fb != null and fb.is_visible_in_tree(), "1 CHIP: the Fill the face chip is on the Cut a hole panel")
	var sp := await find_face_point(ep, true)
	ok(sp.x >= 0.0, "1 FACE: a point on the plate's top face to click was found at %s" % str(sp))

	# ---- ROUND, grid: 5 mm holes, 10 mm apart, 5 mm margin
	var u0: int = m.undo.size()
	await click_ctl(fb)
	ok(m.undo.size() == u0 and ep.fill_pick and ep.fill_box.visible, "2 ARM: Fill the face asks for a face (no step yet, undo %d -> %d), the shape chips and sliders show" % [u0, m.undo.size()])
	ok(ep.fill_shape == "round" and ep.fill_size == 5.0 and ep.fill_gap == 10.0 and ep.fill_margin == 5.0, "2 DEFAULTS: round, 5 mm, 10 mm apart, 5 mm margin")
	await shot("armed")
	await click_ctl_at(sp)
	await idle(6)
	var sk := fill_sk(ep)
	ok(String(sk.get("t", "")) == "sketch" and sk.has("fill"), "2 FILLED: the newest hole step is the fill (%s)" % ep.msg)
	var want := analytic(100.0, 60.0, R, R, 5.0, 10.0, false)
	var got := fill_count(ep)
	var cs := stored_centres(ep)
	var mh := mesh_holes(3.0)
	print("COUNT round grid: app %d, stored %d, mesh %d, analytic %d (usable %.1f x %.1f mm: 9 columns x 5 rows)" % [got, cs.size(), mh.size(), want, 100.0 - 2.0 * (5.0 + R), 60.0 - 2.0 * (5.0 + R)])
	ok(want == 45 and got == want and cs.size() == want and mh.size() == want, "2 COUNT: the app cut %d holes, stored centres %d, holes counted on the built mesh %d; analytic count %d" % [got, cs.size(), mh.size(), want])
	var worst_c := INF
	for c in cs:
		var q: Vector2 = c
		worst_c = minf(worst_c, minf(minf(q.x, 100.0 - q.x), minf(q.y, 60.0 - q.y)))
	var worst_m := INF
	for h in mh:
		worst_m = minf(worst_m, float(h["edge"]))
	ok(worst_c >= 5.0 + R - 0.001, "2 MARGIN CENTRES: the closest centre is %.4f mm from the face edge (want >= margin + radius = %.1f; the 9 x 5 grid is centred, so it keeps 2.5 mm of slack)" % [worst_c, 5.0 + R])
	ok(worst_m >= 5.0 - 0.02, "2 MARGIN MESH: the closest any hole's edge comes to the face edge on the built mesh is %.3f mm (want >= the 5 mm margin)" % worst_m)
	var r1 := Part.replay(m.S.part)
	var drop := plate_v - vol_mm3()
	var wantv := float(want) * PI * R * R * T
	ok(int(r1["bodies"]) == 1 and r1["errors"].is_empty() and absf(drop - wantv) < wantv * 0.005, "2 VOLUME: ONE solid, the volume drop is %.1f mm3 (want %d x pi x %.1f^2 x %.0f = %.1f within 0.5 %%, off by %.3f %%)" % [drop, want, R, T, wantv, 100.0 * absf(drop - wantv) / wantv])
	ok(m.undo.size() == u0 + 1 and m.S.part["features"].size() == feats_hole, "2 ONE STEP: the fill is one undo step (%d -> %d) and no extra build step (%d steps stay %d)" % [u0, m.undo.size(), feats_hole, m.S.part["features"].size()])
	var gx := {}
	var gy := {}
	for c in cs:
		gx[snappedf((c as Vector2).x, 0.01)] = true
		gy[snappedf((c as Vector2).y, 0.01)] = true
	ok(gx.size() == 9 and gy.size() == 5, "2 LAYOUT: %d columns x %d rows (want 9 x 5)" % [gx.size(), gy.size()])
	await shot("round")
	var inside := win.encloses(ep.hole_box.get_global_rect()) and win.encloses(ep.panel.get_global_rect())
	ok(inside, "2 FITS: the Cut a hole panel %s and the Easy panel %s are inside 1280 x 720" % [ep.hole_box.get_global_rect(), ep.panel.get_global_rect()])

	# ---- one Undo gives the single hole back
	await click_ctl(ep.undo_btn)
	await idle(5)
	ok(absf(vol_mm3() - one_v) < 1e-6 and m.undo.size() == u0, "3 UNDO: one Undo click takes the fill back to the single hole (volume %.3f mm3 = %.3f, undo %d)" % [vol_mm3(), one_v, m.undo.size()])
	await click_ctl(ep.redo_btn)
	await idle(5)
	ok(int(Part.replay(m.S.part)["bodies"]) == 1 and absf((plate_v - vol_mm3()) - wantv) < wantv * 0.005, "3 REDO: one Redo gives the 45 holes back")

	# ---- spacing slider: one step
	var us: int = m.undo.size()
	await set_fl(ep, "fl_gap", 12.0)
	var want12 := analytic(100.0, 60.0, R, R, 5.0, 12.0, false)
	var got12 := fill_count(ep)
	ok(m.undo.size() == us + 1 and got12 == want12 and stored_centres(ep).size() == want12, "4 SPACING: 12 mm apart is one undo step and %d holes (analytic %d)" % [got12, want12])
	var drop12 := plate_v - vol_mm3()
	ok(absf(drop12 - float(want12) * PI * R * R * T) < float(want12) * PI * R * R * T * 0.005, "4 SPACING VOLUME: %.1f mm3 (want %.1f)" % [drop12, float(want12) * PI * R * R * T])
	await set_fl(ep, "fl_gap", 10.0)

	# ---- STAGGERED round, then HEX and SQUARE
	var ust: int = m.undo.size()
	await shot("before_stag")
	print("STAG chip rect %s, box %s" % [fbtn(ep, "stag").get_global_rect(), ep.hole_box.get_global_rect()])
	await click_ctl(fbtn(ep, "stag"))
	await idle(4)
	var want_st := analytic(100.0, 60.0, R, R, 5.0, 10.0, true)
	var got_st := fill_count(ep)
	var mh_st := mesh_holes(3.0)
	print("COUNT round staggered: app %d, mesh %d, analytic %d (6 rows of 9)" % [got_st, mh_st.size(), want_st])
	var ys := {}
	for c in stored_centres(ep):
		ys[snappedf((c as Vector2).y, 0.001)] = true
	var yk: Array = ys.keys()
	yk.sort()
	var dys_ok := yk.size() >= 2
	for i in range(1, yk.size()):
		dys_ok = dys_ok and absf(float(yk[i]) - float(yk[i - 1]) - 8.660254) < 0.01
	var wv_st := float(want_st) * PI * R * R * T
	ok(want_st == 54 and got_st == want_st and mh_st.size() == want_st and m.undo.size() == ust + 1, "5 STAGGERED COUNT: %d holes (mesh %d, analytic %d), one undo step" % [got_st, mh_st.size(), want_st])
	ok(dys_ok and yk.size() == 6, "5 STAGGERED ROWS: %d rows, %.3f mm apart (want 6 rows, spacing x 0.866 = 8.660)" % [yk.size(), float(yk[1]) - float(yk[0]) if yk.size() > 1 else 0.0])
	ok(int(Part.replay(m.S.part)["bodies"]) == 1 and absf((plate_v - vol_mm3()) - wv_st) < wv_st * 0.005, "5 STAGGERED VOLUME: drop %.1f mm3 (want %.1f within 0.5 %%)" % [plate_v - vol_mm3(), wv_st])
	var wst := INF
	for h in mh_st:
		wst = minf(wst, float(h["edge"]))
	ok(wst >= 5.0 - 0.02, "5 STAGGERED MARGIN: the closest hole edge on the mesh is %.3f mm from the face edge (want >= 5)" % wst)
	await shot("staggered")

	var uh: int = m.undo.size()
	await click_ctl(fbtn(ep, "hex"))
	await idle(5)
	var Rh := 5.0 / sqrt(3.0)
	var want_hex := analytic(100.0, 60.0, Rh, 2.5, 5.0, 10.0, true)
	var got_hex := fill_count(ep)
	var hex_area := 5.0 * 5.0 * sqrt(3.0) * 0.5
	var wv_hex := float(want_hex) * hex_area * T
	var mh_hex := mesh_holes(3.8)
	var whx := INF
	for h in mh_hex:
		whx = minf(whx, float(h["edge"]))
	print("COUNT hex staggered: app %d, mesh %d, analytic %d" % [got_hex, mh_hex.size(), want_hex])
	ok(want_hex == 48 and got_hex == want_hex and mh_hex.size() == want_hex and m.undo.size() == uh + 1, "6 HEX COUNT: %d hex holes (mesh %d, analytic %d), one undo step" % [got_hex, mh_hex.size(), want_hex])
	ok(int(Part.replay(m.S.part)["bodies"]) == 1 and absf((plate_v - vol_mm3()) - wv_hex) < wv_hex * 0.005, "6 HEX VOLUME: drop %.1f mm3 (want %d x %.3f x 3 = %.1f within 0.5 %%)" % [plate_v - vol_mm3(), want_hex, hex_area, wv_hex])
	ok(whx >= 5.0 - 0.02, "6 HEX MARGIN: the closest corner of any hex on the mesh is %.3f mm from the face edge (want >= 5)" % whx)
	await shot("hex")

	var usq: int = m.undo.size()
	await click_ctl(fbtn(ep, "square"))
	await idle(5)
	var want_sq := analytic(100.0, 60.0, 2.5, 2.5, 5.0, 10.0, true)
	var got_sq := fill_count(ep)
	var wv_sq := float(want_sq) * 25.0 * T
	ok(got_sq == want_sq and m.undo.size() == usq + 1 and int(Part.replay(m.S.part)["bodies"]) == 1 and absf((plate_v - vol_mm3()) - wv_sq) < wv_sq * 0.005,
		"7 SQUARE: %d square holes staggered (analytic %d), one undo step, drop %.1f mm3 (want %.1f)" % [got_sq, want_sq, plate_v - vol_mm3(), wv_sq])
	await click_ctl(fbtn(ep, "stag"))
	await idle(5)
	var want_sg := analytic(100.0, 60.0, 2.5, 2.5, 5.0, 10.0, false)
	var wv_sg := float(want_sg) * 25.0 * T
	ok(fill_count(ep) == want_sg and absf((plate_v - vol_mm3()) - wv_sg) < wv_sg * 0.005, "7 SQUARE GRID: Staggered off gives %d square holes in a grid (analytic %d), drop %.1f mm3 (want %.1f)" % [fill_count(ep), want_sg, plate_v - vol_mm3(), wv_sg])
	await shot("square")

	# ---- Through puts one hole back (the fill is replaced, not stacked)
	await click_ctl(hbtn(ep, "through"))
	await idle(5)
	ok(absf(vol_mm3() - one_v) < 1e-6 and m.S.part["features"].size() == feats_hole, "8 THROUGH: Through puts the single hole back (volume %.3f mm3 = %.3f)" % [vol_mm3(), one_v])

	# ---- a face too small for one hole: a plain message, no step
	await fresh_plate(ep)
	await idle(4)
	await click_ctl(hbtn(ep, "fill"))
	await set_fl(ep, "fl_margin", 50.0)
	var sp2 := await find_face_point(ep, false)
	if sp2.x < 0.0:
		sp2 = await find_face_point(ep, true)
	var before_json := JSON.stringify(m.S.part)
	var u_small: int = m.undo.size()
	await click_ctl_at(sp2)
	await idle(5)
	ok(m.undo.size() == u_small and JSON.stringify(m.S.part) == before_json and ep.msg.to_lower().contains("too small"), "9 TOO SMALL: a 50 mm margin leaves no room for a 5 mm hole on 100 x 60: no undo step (%d -> %d), the record is unchanged, the message is: %s" % [u_small, m.undo.size(), ep.msg])
	await shot("toosmall")

	print("s051: %d fail" % fails)
	quit(1 if fails > 0 else 0)
