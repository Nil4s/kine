extends SceneTree
## S048 REPEAT IT: Around an axis or edge (item 48), Along a line (49), With growth (50). Easy Part, BUILDING card, 1280 x 720, real clicks on the Repeat it box.
## godot --path . --position 4000,4000 -s tests/s048_test.gd     (needs the CAD DLL)
## Pieces: the Around and Grow pieces are put in the record as a drawn shape + a Pull (the fixture: a shape on the FRONT plane has no
## click path in a plain window); the Along piece is drawn and pulled with real clicks. Every press under test is a real click.
## Bars (all measured from the built result: the kernel's solids, triangle bounds in mm, never the code's own variables):
##   A1 6 pegs round Z at r 30 (peg radius 5, 20 long): centres 60.0 deg apart within 0.1 and 30.0 from the axis within 0.1
##   A2 volume = 6 x one peg within 0.5 pct; the press is ONE undo step (undo count +1) and one Undo takes it back to the row
##   A3 pegs overlapping (r 20): ONE solid (bodies == 1), volume within 0.5 pct of six cylinders unioned by hand in the kernel
##   A4 Around Y on the same step: centres 60.0 deg apart round Y within 0.1
##   A5 Around edge: click a vertical edge of a 20 mm cube, 4 copies: centres 90.0 deg apart round that edge within 0.1, 14.14 mm from it
##   B1 a straight 100 mm Curvy line, spacing 25.0 mm: 5 pieces, consecutive centres 25.0 mm apart within 0.05; one undo step
##   C1 Grow by 20 pct, 4 pieces: piece k's bounds = piece 0 bounds x 1.2^k on X, Y and Z within 0.5 pct; one undo step
## Shots: C:/Temp/claude/s048/
const SHOT := "C:/Temp/claude/s048"
const DIRT := "user://s048_test"

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
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		for k in range(1, 9):
			await ev_move(a.lerp(b, k / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func ep():
	return m.bld.part.ep


func rec() -> Dictionary:
	return pu()._ensure()


func mm2scr(mm: Vector2) -> Vector2:
	var p := Vector2(432, 352)
	for i in 5:
		var g: Vector2 = ep()._ground(p, {}, false)
		var gx: Vector2 = ep()._ground(p + Vector2(4, 0), {}, false)
		var gy: Vector2 = ep()._ground(p + Vector2(0, 4), {}, false)
		var jx := (gx - g) / 4.0
		var jy := (gy - g) / 4.0
		var det := jx.x * jy.y - jy.x * jx.y
		var r := mm - g
		p += Vector2((r.x * jy.y - jy.x * r.y) / det, (jx.x * r.y - r.x * jx.y) / det)
	return p


## the bounds (mm) of every body of a record, in body order
func boxes(r: Dictionary) -> Array:
	var out := []
	for f in Part.body_faces(r, -1):
		var pts: PackedVector3Array = f
		if pts.size() == 0:
			continue
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		out.append(AABB(bb.position / Part.MM, bb.size / Part.MM))
	return out


## the same record with the newest pattern step's copies made as bodies of their own (op new): the placing is the same; it lets each copy be measured
func apart() -> Dictionary:
	var r: Dictionary = rec().duplicate(true)
	for f in r["features"]:
		if f["t"] == "pattern":
			f["op"] = "new"
	return r


func pattern() -> Dictionary:
	for f in rec()["features"]:
		if f["t"] == "pattern":
			return f
	return {}


func vol(r: Dictionary) -> float:
	return float(Part.replay(r)["volume"]) * 1e9


## a fixture piece: a shape on a plane, pulled dist mm, as two steps of one undo step
func put_piece(plane: String, ents: Array, dist: float) -> void:
	ep()._begin("fixture piece")
	var r := rec()
	var sk := Part.new_feature(r, "sketch", {"plane": plane, "ents": ents})
	r["features"].append(sk)
	r["features"].append(Part.new_feature(r, "extrude", {"sketch": sk["id"], "dist": dist, "op": "new"}))
	ep()._end()
	pu().sync()
	await idle(6)


## an empty part again (one undo step; the Repeat box forgets its step)
func clear_all() -> void:
	ep()._begin("clear")
	rec()["features"] = []
	ep()._end()
	ep().rep_id = ""
	pu().sync()
	await idle(8)


func ang_gaps(angs: Array) -> Array:
	angs.sort()
	var g := []
	for i in angs.size():
		var d: float = angs[(i + 1) % angs.size()] - angs[i]
		g.append(d + 360.0 if d < 0.0 else d)
	return g


func within(a: Array, want: float, tol: float) -> bool:
	for x in a:
		if absf(float(x) - want) > tol:
			return false
	return true


func fmt(a: Array) -> String:
	var s := []
	for x in a:
		s.append("%.3f" % float(x))
	return str(s)


func press_repeat() -> void:
	await click_ctl(ep().make_btns["repeat"])
	await idle(8)


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
	await idle(90)

	# ---------------- A: Around Z. A peg (radius 5, 20 long) on the front plane, 30 mm out from the Z line
	await put_piece("front", [{"k": "circle", "c": [30.0, 0.0], "r": 5.0}], 20.0)
	var one := vol(rec())
	await press_repeat()
	ok(ep().repeat_box.visible and ep().rep_btns["around_z"].is_visible_in_tree(), "0 the Repeat it box is open with the Around X / Y / Z / edge, Along line and Grow buttons")
	var n_before: int = m.undo.size()
	await click_ctl(ep().rep_btns["around_z"])
	await idle(10)
	await shot("01_around_z")
	var n_after: int = m.undo.size()
	var p := pattern()
	var bx := boxes(apart())
	var angs := []
	var rads := []
	for b in bx:
		var c: Vector3 = (b as AABB).get_center()
		angs.append(rad_to_deg(atan2(c.y, c.x)))
		rads.append(Vector2(c.x, c.y).length())
	var gaps := ang_gaps(angs)
	ok(bx.size() == 6 and within(gaps, 60.0, 0.1), "A1 six pegs round Z: centre gaps %s deg (want 60.0 +-0.1)" % fmt(gaps))
	ok(within(rads, 30.0, 0.1), "A1 every centre 30.0 mm from the Z line: %s" % fmt(rads))
	var v6 := vol(rec())
	ok(absf(v6 - 6.0 * one) <= 0.005 * 6.0 * one, "A2 volume %.1f mm3 = 6 x one peg %.1f mm3 (within 0.5 pct)" % [v6, one])
	ok(n_after == n_before + 1 and String(p.get("kind", "")) == "circular" and String(p.get("axis", "")) == "z", "A2 ONE undo step for the press (undo %d -> %d), kind %s axis %s" % [n_before, n_after, p.get("kind", ""), p.get("axis", "")])

	# A4 Around Y on the same step
	await click_ctl(ep().rep_btns["around_y"])
	await idle(10)
	await shot("02_around_y")
	var angs_y := []
	for b in boxes(apart()):
		var c2: Vector3 = (b as AABB).get_center()
		angs_y.append(rad_to_deg(atan2(c2.z, c2.x)))
	var gy := ang_gaps(angs_y)
	ok(angs_y.size() == 6 and within(gy, 60.0, 0.1), "A4 Around Y: centre gaps %s deg (want 60.0 +-0.1)" % fmt(gy))

	# one Undo takes the Around Y step back to Around Z; a second the Around Z step back to the row
	await click_ctl(ep().undo_btn)
	await idle(10)
	ok(String(pattern().get("axis", "")) == "z" and String(pattern().get("kind", "")) == "circular", "A2 one Undo: Around Y goes back to Around Z (axis %s)" % pattern().get("axis", ""))
	await click_ctl(ep().undo_btn)
	await idle(10)
	ok(String(pattern().get("kind", "")) == "linear" and m.undo.size() == n_before, "A2 one more Undo: back to the row (kind %s, undo depth %d = %d)" % [pattern().get("kind", ""), m.undo.size(), n_before])

	# A3 pegs that overlap fuse into ONE solid: radius 20 (neighbours 30 mm apart), compared with the same six cylinders unioned by hand
	await click_ctl(ep().rep_btns["around_z"])
	await idle(8)
	ep()._begin("fatter pegs")
	rec()["features"][0]["ents"][0]["r"] = 20.0
	ep()._end()
	pu().sync()
	await idle(10)
	await shot("03_fused")
	var res := Part.replay(rec())
	# the fused outline by hand: 6 circles of radius 20 whose centres sit 30 apart on a ring, minus the 6 lenses where neighbours overlap, times the length 20
	var lens := 2.0 * 400.0 * acos(30.0 / 40.0) - 15.0 * sqrt(1600.0 - 900.0)
	var ref := (6.0 * PI * 400.0 - 6.0 * lens) * 20.0
	var vf := float(res["volume"]) * 1e9
	ok(int(res["bodies"]) == 1 and absf(vf - ref) <= 0.005 * ref and vf < 6.0 * PI * 400.0 * 20.0 * 0.999,
		"A3 overlapping pegs: %d solid, volume %.1f mm3 vs the outline worked out by hand %.1f mm3 (and less than 6 separate: %.1f)" % [int(res["bodies"]), vf, ref, 6.0 * PI * 400.0 * 20.0])

	# ---------------- A5: Around edge on a 20 mm cube: a new part
	await clear_all()
	await put_piece("front", [{"k": "rect", "a": [0.0, 0.0], "b": [20.0, 20.0]}], 20.0)
	await press_repeat()
	await idle(10)
	await shot("04_cube")
	var cube := Part.replay(rec(), -1, {"edges": true, "keep": true})
	Part.release_kept(cube.get("ids", []))
	var pick := {}
	for e in cube.get("edges", []):
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		if absf(a.x - 0.020) < 1e-6 and absf(b.x - 0.020) < 1e-6 and absf(a.z - 0.020) < 1e-6 and absf(b.z - 0.020) < 1e-6 and absf(a.y - b.y) > 0.015:
			pass
		if maxf(a.x, b.x) < 0.0201 and absf(a.y - 0.020) < 1e-6 and absf(b.y - 0.020) < 1e-6 and absf(a.z - 0.020) < 1e-6 and absf(b.z - 0.020) < 1e-6 and absf(a.x - b.x) > 0.015:
			pick = e   # the top front edge of the first cube, along X (the view looks down, so a vertical edge is a dot on the screen)
	ok(not pick.is_empty(), "A5 the cube has a top front edge along X to pick")
	await click_ctl(ep().rep_btns["around_edge"])
	await idle(4)
	ok(ep().armed == "aredge", "A5 Around edge waits for a click on an edge (armed %s)" % ep().armed)
	if not pick.is_empty():
		var mid: Vector3 = ((pick["a"] as Vector3) + (pick["b"] as Vector3)) * 0.5
		var n_b2: int = m.undo.size()
		await click_at(m.cam.unproject_position(mid))
		await idle(10)
		await shot("05_around_edge")
		var pe := pattern()
		ok(m.undo.size() == n_b2 + 1 and String(pe.get("about", "")) == "edge", "A5 the click is ONE undo step (undo %d -> %d), about %s" % [n_b2, m.undo.size(), pe.get("about", "")])
		# four copies: the slider is at its first value 6; set it to 4 through the real slider row
		var cnt: HSlider = null
		for r in ep().rep_rows:
			if r["key"] == "count":
				cnt = r["slider"]
		cnt.value = 4.0
		await idle(10)
		ok(absf(float(pe["pivot"][1]) - 20.0) < 0.05 and absf(float(pe["pivot"][2]) - 20.0) < 0.05 and absf(float(pe["adir"][0])) > 0.999, "A5 the step holds the picked edge: pivot %s, direction %s" % [str(pe["pivot"]), str(pe["adir"])])
		var ang5 := []
		var rad5 := []
		for b in boxes(apart()):
			var c5: Vector3 = (b as AABB).get_center()
			ang5.append(rad_to_deg(atan2(c5.z - 20.0, c5.y - 20.0)))
			rad5.append(Vector2(c5.y - 20.0, c5.z - 20.0).length())
		var g5 := ang_gaps(ang5)
		ok(ang5.size() == 4 and within(g5, 90.0, 0.1) and within(rad5, 14.142, 0.1), "A5 four copies round that edge: gaps %s deg, 14.14 mm from it: %s" % [fmt(g5), fmt(rad5)])

	# ---------------- B: Along a straight 100 mm line, real clicks: a post of radius 5 at (0, -40), a Curvy line from its centre to (105, -40)
	await clear_all()
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_path([mm2scr(Vector2(0, -40)), mm2scr(Vector2(5, -40))])
	await idle(10)
	await click_ctl(ep().make_btns["pull"])
	await idle(20)
	var post := vol(rec())
	await click_ctl(ep().make_btns["curve"])
	await drag_path([mm2scr(Vector2(0, -40)), mm2scr(Vector2(105, -40))])
	await idle(10)
	await press_repeat()
	await shot("06_repeat_box")
	# the spacing 25.0 mm = the post's 10 mm + a Gap of 1.5 cm
	var gap: HSlider = null
	for r in ep().rep_rows:
		if r["key"] == "gap":
			gap = r["slider"]
	var n_b3: int = m.undo.size()
	await click_ctl(ep().rep_btns["along"])
	await idle(10)
	gap.value = 1.5
	await idle(12)
	await shot("07_along")
	var pa := pattern()
	var bb_a := boxes(apart())
	var xs := []
	for b in bb_a:
		xs.append((b as AABB).get_center())
	xs.sort_custom(func(a, b): return a.x < b.x)
	var sp := []
	for i in range(1, xs.size()):
		sp.append((xs[i] as Vector3).distance_to(xs[i - 1]))
	var okp := xs.size() == 5
	for d in sp:
		okp = okp and absf(float(d) - 25.0) <= 0.05
	ok(okp, "B1 along a 100 mm line: %d pieces, consecutive centres %s mm apart (want 25.0 +-0.05)" % [xs.size(), fmt(sp)])
	ok(absf(vol(rec()) - 5.0 * post) <= 0.005 * 5.0 * post and String(pa.get("kind", "")) == "path", "B1 volume %.1f mm3 = 5 x one post %.1f mm3, kind %s" % [vol(rec()), post, pa.get("kind", "")])
	await click_ctl(ep().undo_btn)
	await idle(8)
	await click_ctl(ep().undo_btn)
	await idle(8)
	ok(String(pattern().get("kind", "")) == "linear" and m.undo.size() == n_b3, "B1 Undo twice (the gap, the press): back to the row (kind %s, depth %d = %d)" % [pattern().get("kind", ""), m.undo.size(), n_b3])

	# ---------------- C: Grow by 20 pct on a fresh post (a round post: radius 5, 20 mm high) - the piece is the newest step
	await clear_all()
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_path([mm2scr(Vector2(0, -40)), mm2scr(Vector2(5, -40))])
	await idle(10)
	await click_ctl(ep().make_btns["pull"])
	await idle(20)
	await press_repeat()
	var n_b4: int = m.undo.size()
	await click_ctl(ep().rep_btns["grow"])
	await idle(10)
	var grow_row: HSlider = null
	for r in ep().rep_rows:
		if r["key"] == "grow":
			grow_row = r["slider"]
	ok(grow_row != null and (grow_row.get_parent() as Control).visible, "C0 Grow pressed: the Grow by slider shows (hint: %s)" % ep().hint_l.text)
	var n_a4: int = m.undo.size()
	grow_row.value = 20.0
	await idle(12)
	await shot("08_grow")
	var pg := pattern()
	var bg := boxes(apart())
	bg.sort_custom(func(a, b): return (a as AABB).size.x < (b as AABB).size.x)
	var good := bg.size() == 4 and String(pg.get("kind", "")) == "grow" and absf(float(pg.get("factor", 0.0)) - 1.2) < 1e-9
	var worst := 0.0
	var lines := []
	if bg.size() >= 1:
		var b0: AABB = bg[0]
		for k in bg.size():
			var bk: AABB = bg[k]
			var f := pow(1.2, k)
			for ax in 3:
				var rel := absf(bk.size[ax] / (b0.size[ax] * f) - 1.0)
				worst = maxf(worst, rel)
			lines.append("%.2fx%.2fx%.2f" % [bk.size.x, bk.size.y, bk.size.z])
	ok(good and worst <= 0.005, "C1 Grow by 20 pct: 4 pieces, sizes %s, worst deviation from base x 1.2^k %.3f pct (want <= 0.5)" % [str(lines), worst * 100.0])
	ok(n_a4 == n_b4 + 1, "C1 the Grow press is ONE undo step (undo %d -> %d)" % [n_b4, n_a4])
	await click_ctl(ep().undo_btn)
	await idle(8)
	await click_ctl(ep().undo_btn)
	await idle(8)
	ok(String(pattern().get("kind", "")) == "linear" and m.undo.size() == n_b4, "C1 Undo (the slider, the press): back to the row (kind %s, depth %d = %d)" % [pattern().get("kind", ""), m.undo.size(), n_b4])

	print("s048: %d fail" % fails)
	quit(1 if fails > 0 else 0)
