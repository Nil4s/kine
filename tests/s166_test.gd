extends SceneTree
## godot --path . --position 4000,4000 -s tests/s166_test.gd   (EASY PART: Friday 43 "Trace" a picture into a sketch, Friday 166 "Draw to search" in the Parts library;
## scripts/easy_part_trace.gd, easy_part_sketch.gd, build/outline_tools.gd, build/part_catalog.gd; needs the CAD DLL)
## Bars (real clicks and real mouse drags at 1280 x 720; numbers read from the built result):
##   43  a black 80 x 40 mm rectangle with a 20 mm hole, traced at width 80: sketch bbox 80.0 x 40.0 within 0.5 mm; pulled up 10 mm its volume is
##       (80*40 - pi*10^2)*10 within 2 pct; ONE undo step; the top of the picture is the sketch's +y; a circle photo gives a closed round outline (spread < 2 pct)
##   166 a drawn circle puts a round part, a drawn hexagon a hex nut, a drawn L an L-bracket in the top 3 (the ranked lists are printed);
##       a turned and shrunk L still finds it; a second search builds no part (the silhouettes are cached); a result chip drops its part (one undo step)
## Shots: C:/Temp/claude/s166/trace.png, traced.png, search_l.png, search_hex.png, search_placed.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s166"
const DIRT := "user://s166_test"
const ROUND := ["washer_m5", "wheel", "castor", "gear", "bearing_608", "bearing_625", "foot", "knob", "clip"]
var pu: PartUI
var ep


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func nd(n: String) -> Node:
	return root.find_child(n, true, false)


## a REAL drag over a list of canvas-local points
func drag(canvas: Control, pts: Array) -> void:
	var o := canvas.get_global_rect().position
	await ev_move(o + pts[0], false)
	await ev_mouse(o + pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(o + pts[i])
	await ev_mouse(o + pts[pts.size() - 1], false)
	await idle(2)


func poly_pts(corners: Array, per_edge := 12, jitter := 1.2) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 166
	var out: Array = []
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		for k in per_edge:
			out.append(a.lerp(b, float(k) / per_edge) + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter)))
	return out


func circle_pts(c: Vector2, r: float, n := 70) -> Array:
	var corners: Array = []
	for i in n:
		corners.append(c + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	return poly_pts(corners, 1, 1.2)


func save_png(img: Image, nm: String) -> String:
	var dir := ProjectSettings.globalize_path(DIRT)
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir + "/" + nm
	img.save_png(p)
	return p


## bbox of a sketch's line entities
func ents_bbox(ents: Array) -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for e in ents:
		for k in ["a", "b"]:
			var v := Vector2(float(e[k][0]), float(e[k][1]))
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return Rect2(lo, hi - lo)


## every sketch of the part, as one "sketch" (the kernel takes holes a level at a time, so a hole is a sketch of its own)
func last_sketch() -> Dictionary:
	var ents: Array = []
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "sketch":
			ents.append_array(f["ents"])
	return {"ents": ents} if not ents.is_empty() else {}


func ranked(label: String) -> Array:
	var r: Array = ep.sketcher.results
	var s := ""
	for x in r:
		s += "%s %.3f (%s)  " % [x["name"], float(x["score"]), x["view"]]
	print("RANK %s: %s" % [label, s])
	var all := PartCatalog.search(ep.sketcher.stroke, 40)
	var s2 := ""
	for x in all:
		s2 += "%s %.3f; " % [x["id"], float(x["score"])]
	print("ALL %s: %s" % [label, s2])
	return r


func ids_of(r: Array, n := 3) -> Array:
	var o := []
	for i in mini(n, r.size()):
		o.append(String(r[i]["id"]))
	return o


func any_in(a: Array, b: Array) -> bool:
	for x in a:
		if x in b:
			return true
	return false


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
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# ---------------- 43: the pictures
	var rect_img := Image.create(800, 400, false, Image.FORMAT_RGBA8)   # 10 px per mm: 80 x 40 mm
	rect_img.fill(Color.BLACK)
	for y in 400:
		for x in 800:
			if Vector2(x + 0.5 - 400.0, y + 0.5 - 200.0).length() <= 100.0:   # the 20 mm hole
				rect_img.set_pixel(x, y, Color.WHITE)
	var rect_path := save_png(rect_img, "rect_hole.png")
	var circ_img := Image.create(420, 420, false, Image.FORMAT_RGBA8)   # a "photo": grey paper, a dark disc with a soft edge
	circ_img.fill(Color(0.86, 0.86, 0.84))
	for y in 420:
		for x in 420:
			var d := Vector2(x + 0.5 - 210.0, y + 0.5 - 210.0).length()
			var t := clampf((150.0 - d) / 2.0 + 0.5, 0.0, 1.0)
			var g := lerpf(0.86, 0.12, t)
			circ_img.set_pixel(x, y, Color(g, g, g * 0.97))
	var circ_path := save_png(circ_img, "circle_photo.png")
	var top_img := Image.create(300, 200, false, Image.FORMAT_RGBA8)   # dark only in the TOP half
	top_img.fill(Color.WHITE)
	for y in 100:
		for x in range(40, 260):
			top_img.set_pixel(x, y, Color.BLACK)
	var top_path := save_png(top_img, "top_half.png")

	await click_ctl(nd("easypart_make_draw") as Button)
	var tb := nd("easypart_shape_trace") as Button
	ok(tb != null and tb.is_visible_in_tree() and vp.encloses(Rect2(tb.global_position, tb.size)), "43 the Trace chip is in the Draw shape row, on screen")
	if tb != null:
		await click_ctl(tb)
	ok(nd("easypart_trace_dialog") != null, "43 pressing Trace opens a file dialog")
	var fd := nd("easypart_trace_dialog")
	if fd != null:
		fd.queue_free()
	await idle(2)
	ep.tracer.chosen(rect_path)
	await idle(3)
	var wb := nd("easypart_trace_width") as SpinBox
	wb.value = 80.0
	await idle(3)
	var nodeq: MeshInstance3D = ep.tracer.node
	var qs: Vector2 = (nodeq.mesh as QuadMesh).size if nodeq != null else Vector2.ZERO
	ok(nodeq != null and absf(qs.x * 1000.0 - 80.0) < 0.01 and absf(qs.y * 1000.0 - 40.0) < 0.01 and absf(nodeq.global_position.y) < 0.001, "43 the picture lies on the floor 80.0 x 40.0 mm (quad %.2f x %.2f mm)" % [qs.x * 1000.0, qs.y * 1000.0])
	await shot("trace")
	print("trace info: ", ep.tracer.info.text)
	var gb := nd("easypart_trace_go") as Button
	var go_ok := gb != null and gb.is_visible_in_tree() and vp.encloses(Rect2(gb.global_position, gb.size))
	ok(go_ok, "43 the width box and Trace it are on screen")
	var ub: int = m.undo.size()
	await click_ctl(gb)
	await idle(4)
	print("trace info after: ", ep.tracer.info.text)
	var sk := last_sketch()
	var bb := ents_bbox(sk.get("ents", []))
	ok(not sk.is_empty() and absf(bb.size.x - 80.0) <= 0.5 and absf(bb.size.y - 40.0) <= 0.5, "43 the traced sketch is %.2f x %.2f mm (bar 80.0 x 40.0 within 0.5), %d line(s)" % [bb.size.x, bb.size.y, (sk.get("ents", []) as Array).size()])
	var vol := float(pu.res.get("volume", 0.0)) * 1e9
	var want := (80.0 * 40.0 - PI * 100.0) * 10.0
	ok(absf(vol - want) <= 0.02 * want and int(pu.res.get("bodies", 0)) == 1, "43 pulled up 10 mm the volume is %.0f mm3 (bar %.0f within 2 pct): the hole is a hole (%d solid)" % [vol, want, int(pu.res.get("bodies", 0))])
	ok(m.undo.size() == ub + 1, "43 Trace it is ONE undo step (%d -> %d)" % [ub, m.undo.size()])
	await shot("traced")
	var tp_r := (nd("easypart_trace") as Control).get_global_rect()
	var st_r := (nd("easypart_panel") as Control).get_global_rect()
	ok(not tp_r.intersects(st_r) and vp.encloses(tp_r) and not tp_r.intersects((nd("easypart_make") as Control).get_global_rect()), "43 the Trace box (%s) is clear of the Easy panel (%s) and the make row" % [str(tp_r), str(st_r)])
	m._undo()
	await idle(4)
	ok((m.S.part.get("features", []) as Array).is_empty(), "43 one Undo takes the traced shape back")
	# the top of the picture is the sketch's +y
	ep.tracer.show_image(Image.load_from_file(top_path))
	await idle(2)
	wb.value = 60.0
	await idle(2)
	await click_ctl(nd("easypart_trace_go") as Button)
	await idle(4)
	var tbx := ents_bbox(last_sketch().get("ents", []))
	ok(tbx.position.y >= -0.6 and absf(tbx.position.y + tbx.size.y - 20.0) < 0.6 and absf(tbx.size.x - 44.0) < 0.6, "43 dark in the TOP half of the picture: sketch y runs %.2f to %.2f (bar 0 to 20, top of the picture is +y), x span %.2f (bar 44)" % [tbx.position.y, tbx.position.y + tbx.size.y, tbx.size.x])
	m._undo()
	await idle(4)
	# a circle photo
	ep.tracer.show_image(Image.load_from_file(circ_path))
	await idle(2)
	wb.value = 60.0
	await idle(2)
	await click_ctl(nd("easypart_trace_go") as Button)
	await idle(4)
	var cs := last_sketch()
	var ce: Array = cs.get("ents", [])
	var cbb := ents_bbox(ce)
	var cen := cbb.get_center()
	var rmin := 1e9
	var rmax := 0.0
	var rsum := 0.0
	var closed := true
	for i in ce.size():
		var a := Vector2(float(ce[i]["a"][0]), float(ce[i]["a"][1]))
		var r := a.distance_to(cen)
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
		rsum += r
		var b := Vector2(float(ce[i]["b"][0]), float(ce[i]["b"][1]))
		var nx := Vector2(float(ce[(i + 1) % ce.size()]["a"][0]), float(ce[(i + 1) % ce.size()]["a"][1]))
		if b.distance_to(nx) > 1e-6:
			closed = false
	var rmean := rsum / maxf(ce.size(), 1)
	var spread := (rmax - rmin) / maxf(rmean, 1e-9)
	ok(ce.size() >= 8 and closed and spread < 0.02, "43 the circle photo: a closed outline of %d corners, radius %.2f..%.2f mm, spread %.2f pct (bar < 2)" % [ce.size(), rmin, rmax, spread * 100.0])
	ok(absf(rmean - 150.0 * 60.0 / 420.0) < 0.6, "43 and its radius is %.2f mm (150 px of a 420 px, 60 mm picture = %.2f)" % [rmean, 150.0 * 60.0 / 420.0])
	m._undo()
	await idle(4)
	ep.tracer.close()
	await idle(2)

	# ---------------- 166: Draw to search
	m.S.part = {}
	await idle(2)
	await click_ctl(nd("easypart_chip_parts") as Button)
	var sc := nd("easypart_lib_sketch") as Button
	ok(sc != null and sc.is_visible_in_tree() and vp.encloses(Rect2(sc.global_position, sc.size)), "166 the Draw to search chip is on the Parts library page, on screen")
	await click_ctl(sc)
	var cv := nd("easypart_sketch_canvas") as Control
	ok(cv != null and cv.is_visible_in_tree() and vp.encloses(cv.get_global_rect()), "166 the drawing box is on screen")
	var wt := 0
	while not PartCatalog.ready() and wt < 600:
		await idle(5)
		wt += 5
	print("catalog ready after %d frames, %d builds" % [wt, PartCatalog.builds])
	var S := cv.size.x
	var u := S / 250.0
	var c0 := Vector2(S, S) * 0.5
	var b0: int = PartCatalog.builds
	var t0 := Time.get_ticks_msec()
	await drag(cv, circle_pts(c0, 90.0 * u))
	var t1 := Time.get_ticks_msec()
	var r1 := ranked("circle")
	var built_first: int = PartCatalog.builds - b0
	print("first search: %d parts built, %d ms" % [built_first, t1 - t0])
	ok(r1.size() == 6 and any_in(ids_of(r1), ROUND), "166 a drawn circle: a round part in the top 3 %s" % str(ids_of(r1)))
	ok(r1.size() == 6 and float(r1[0]["score"]) <= float(r1[5]["score"]) and (nd("easypart_sketch_res_5") as Button).is_visible_in_tree(), "166 six results are shown, best first, with their scores")
	var hex_c: Array = []
	for k in 6:
		hex_c.append(c0 + Vector2(cos(PI / 3.0 * k + 0.35), sin(PI / 3.0 * k + 0.35)) * 95.0 * u)
	var b1: int = PartCatalog.builds
	await drag(cv, poly_pts(hex_c, 12, 1.2 * u))
	var r2 := ranked("hexagon")
	ok(r2.size() == 6 and any_in(ids_of(r2), ["nut_m5", "nut_m6"]), "166 a drawn hexagon: a hex nut in the top 3 %s" % str(ids_of(r2)))
	ok(PartCatalog.builds == b1, "166 the second search built no part (silhouettes cached: %d builds in the first)" % built_first)
	await shot("search_hex")
	var L_c := [Vector2(40, 30) * u, Vector2(95, 30) * u, Vector2(95, 150) * u, Vector2(215, 150) * u, Vector2(215, 205) * u, Vector2(40, 205) * u]
	await drag(cv, poly_pts(L_c, 12, 1.2 * u))
	var r3 := ranked("L")
	ok(r3.size() == 6 and "bracket_l" in ids_of(r3), "166 a drawn L: the L-bracket in the top 3 %s" % str(ids_of(r3)))
	await shot("search_l")
	var L_small: Array = []
	for p in L_c:
		var q: Vector2 = (p - c0) * 0.55
		L_small.append(c0 + Vector2(-q.y, q.x))   # turned 90 degrees, 55 pct size
	await drag(cv, poly_pts(L_small, 10, 0.8))
	var r4 := ranked("L turned+small")
	ok(r4.size() == 6 and "bracket_l" in ids_of(r4), "166 an L turned 90 degrees at 55 pct size still finds the L-bracket %s" % str(ids_of(r4)))
	# a result chip puts the part on the floor
	await drag(cv, poly_pts(L_c, 12, 1.2 * u))
	var r5: Array = ep.sketcher.results
	var bi := -1
	for i in r5.size():
		if String(r5[i]["id"]) == "bracket_l":
			bi = i
	var ub2: int = m.undo.size()
	if bi >= 0:
		await click_ctl(nd("easypart_sketch_res_%d" % bi) as Button)
	await idle(4)
	ok(bi >= 0 and m.undo.size() == ub2 + 1 and String((m.S.part.get("easy", {}) as Dictionary).get("t", "")) == "bracket" and (pu.res.get("errors", {}) as Dictionary).is_empty(), "166 the L-bracket chip drops it on the floor: one undo step (%d -> %d), built" % [ub2, m.undo.size()])
	await shot("search_placed")
	var panel_r := (nd("easypart_panel") as Control).get_global_rect()
	var sk_r := (nd("easypart_sketch") as Control).get_global_rect()
	var mk_r := (nd("easypart_make") as Control).get_global_rect()
	var hint_r := (nd("easypart_hint") as Control).get_global_rect()
	var stat_r := (nd("easypart_status") as Control).get_global_rect()
	ok(not sk_r.intersects(stat_r), "166 the box (%s) does not cover the status line (%s)" % [str(sk_r), str(stat_r)])
	ok(not sk_r.intersects(mk_r) and not sk_r.intersects(hint_r), "166 the box does not cover the make row (%s) or the hint line (%s)" % [str(mk_r), str(hint_r)])
	ok(not sk_r.intersects(panel_r) and vp.encloses(sk_r), "166 the box (%s) is clear of the Easy panel (%s) and on screen" % [str(sk_r), str(panel_r)])
	print("s166: %d fail" % fails)
	quit()
