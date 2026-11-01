extends SceneTree
## godot --path . --position 4000,4000 -s tests/s047_test.gd     (EASY PART, Friday plan 47: MIRROR WHILE DRAWING; needs the CAD DLL)
## A beginner from the BUILDING card, real mouse clicks at 1280 x 720 on the live Easy Part. Draw shape, the Mirror chip (Mirror X), three clicks
## on the right of the middle line, the last one clicked again to finish; Pull it up 10 mm. Every bar is measured from the BUILT result
## (the saved sketch's points in mm, the solid's bbox and kernel volume, screenshot pixels), never from the code's own variables.
##   0 CHIP     the Mirror chip is on the Draw shape row, says Mirror: off, one click makes it Mirror X and picks the Line
##   1 LIVE     after two clicks, the mirror of each clicked point shows on screen (the pixels there changed from the picture before the click)
##   2 OUTLINE  3 points clicked on one side with Mirror X = ONE sketch of 6 lines, a closed loop of 6 distinct points
##   3 SYMM     each point's mirror (x -> -x, same y) is a point of the outline, within 0.01 mm
##   4 UNDO     the whole drawing is ONE undo step
##   5 BBOX     pulled up 10 mm: the solid's bbox is centred on the mirror line (x) within 0.01 mm, and 10 mm high (within 0.05)
##   6 VOLUME   the kernel volume = 2 x the half's area x 10 mm, within 0.5 pct (the half's area from its own polygon here)
##   7 OFF      Mirror off (two more clicks on the chip): a Line drag draws ONE straight line as before
##   8 CROSS    Mirror X, a click on the other side of the middle line is refused in words (no point added)
##   9 Y        Mirror Y: three clicks on the front side of the middle line give a 6-point outline symmetric about y = 0 (y -> -y)
## Shots: C:/Temp/claude/s047/live.png (two clicks, the mirror half showing), done.png (pulled up)
const SHOT := "C:/Temp/claude/s047"
const DIRT := "user://s047_test"

var fails := 0
var m: Node
var pu: PartUI


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


## one real click on the grid
func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i], true)
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


## the screen pixel of a floor point (mm)
func scr(q: Vector2) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), q))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func newest_sketch() -> Dictionary:
	var fs: Array = m.S.part.get("features", [])
	for i in range(fs.size() - 1, -1, -1):
		if String(fs[i].get("t", "")) == "sketch":
			return fs[i]
	return {}


func n_sketches() -> int:
	var n := 0
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "sketch":
			n += 1
	return n


## the corner points of a sketch of lines (start of each line), and whether the lines form one closed loop in order
func loop_of(sk: Dictionary) -> Dictionary:
	var ents: Array = sk.get("ents", [])
	var pts: Array = []
	var closed := not ents.is_empty()
	for i in ents.size():
		var e: Dictionary = ents[i]
		if String(e.get("k", "")) != "line":
			closed = false
			continue
		var a := Vector2(e["a"][0], e["a"][1])
		pts.append(a)
		var nx: Dictionary = ents[(i + 1) % ents.size()]
		if String(nx.get("k", "")) == "line" and Vector2(e["b"][0], e["b"][1]).distance_to(Vector2(nx["a"][0], nx["a"][1])) > 0.01:
			closed = false
	return {"pts": pts, "closed": closed}


func has_pt(pts: Array, q: Vector2) -> bool:
	for p in pts:
		if (p as Vector2).distance_to(q) <= 0.01:
			return true
	return false


func symmetric(pts: Array, mode: String) -> bool:
	for p in pts:
		var q: Vector2 = Vector2(-p.x, p.y) if mode == "x" else Vector2(p.x, -p.y)
		if not has_pt(pts, q):
			return false
	return true


func distinct(pts: Array) -> int:
	var n := 0
	for i in pts.size():
		var dup := false
		for j in i:
			if (pts[i] as Vector2).distance_to(pts[j]) <= 0.01:
				dup = true
		if not dup:
			n += 1
	return n


## polygon area by the shoelace sum
func area(poly: Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func bbox() -> AABB:
	var b: AABB = pu.res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


## how much the colour at screen pixel p differs between two pictures (0 to 3), looking at the 7 x 7 pixels around it (the worst one)
func pix_change(a: Image, b: Image, p: Vector2) -> float:
	var sc := Vector2(a.get_width(), a.get_height()) / Vector2(root.content_scale_size)
	var c := Vector2i((p * sc).round())
	var worst := 0.0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= a.get_width() or q.y >= a.get_height():
				continue
			var ca := a.get_pixelv(q)
			var cb := b.get_pixelv(q)
			worst = maxf(worst, absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b))
	return worst


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
	pu = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	m.target = Vector3.ZERO
	m.pitch = -60.0
	m.yaw = 0.0
	m._cam()
	await idle(40)

	# 0 CHIP
	await click_ctl(ep.make_btns["draw"])
	var mb: Button = ep.mirror_btn
	ok(mb != null and mb.is_visible_in_tree() and mb.text == "Mirror: off", "0a CHIP the Draw shape row has a Mirror chip that says Mirror: off (%s)" % [mb.text if mb != null else "none"])
	var seen := not ep._over_ui(mb.get_global_rect().get_center()) or mb.is_visible_in_tree()
	await click_ctl(mb)
	ok(mb.text == "Mirror X" and mb.button_pressed and ep.shape == "line" and (ep.shape_btns["line"] as Button).button_pressed, "0b CHIP one click: Mirror X, lit, and the Line is picked (text %s, shape %s)" % [mb.text, ep.shape])

	# 1 the clicks. Half drawn on the right of the middle line (x > 0): A (20,-30), B (60,0), C (20,30), in mm
	var A := Vector2(20, -30)
	var B := Vector2(60, 0)
	var C := Vector2(20, 30)
	var sk0 := n_sketches()
	var ub: int = m.undo.size()
	await shot("before")
	var img0: Image = root.get_texture().get_image()
	await click_at(scr(A))
	await click_at(scr(B))
	await idle(3)
	await shot("live")
	var img1: Image = root.get_texture().get_image()
	var mA := scr(Vector2(-A.x, A.y))
	var mB := scr(Vector2(-B.x, B.y))
	var cA := pix_change(img0, img1, mA)
	var cB := pix_change(img0, img1, mB)
	ok(cA > 0.5 and cB > 0.5, "1 LIVE after two clicks the mirror of each point shows on screen (pixel change at the mirror of A %.2f, of B %.2f; want > 0.5)" % [cA, cB])
	ok(n_sketches() == sk0, "1b nothing is written while the points are being clicked (sketches %d -> %d)" % [sk0, n_sketches()])
	await click_at(scr(C))
	await click_at(scr(C))   # the last point again: done
	await idle(3)
	var sk := newest_sketch()
	var lp := loop_of(sk)
	var pts: Array = lp["pts"]
	ok(n_sketches() == sk0 + 1 and (sk.get("ents", []) as Array).size() == 6 and bool(lp["closed"]) and distinct(pts) == 6, "2 OUTLINE three clicks with Mirror X: ONE sketch of 6 lines, a closed loop of %d distinct points (lines %d, closed %s)" % [distinct(pts), (sk.get("ents", []) as Array).size(), str(lp["closed"])])
	ok(symmetric(pts, "x") and has_pt(pts, A) and has_pt(pts, B) and has_pt(pts, C), "3 SYMM each point's mirror is a point of the outline within 0.01 mm, and the clicked points are on the grid as clicked (%s)" % str(pts))
	ok(m.undo.size() == ub + 1, "4 UNDO the whole drawing is ONE undo step (%d -> %d)" % [ub, m.undo.size()])

	# 5 and 6 pull up 10 mm
	await click_ctl(ep.make_btns["pull"])
	for r in ep.rows:
		if String(r["kind"]) == "tweak":
			var s: HSlider = r["slider"]
			var rr := s.get_global_rect()
			var y := rr.get_center().y
			var gw := 24.0
			var p0 := Vector2(rr.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (rr.size.x - gw), y)
			var x1 := rr.position.x + gw * 0.5 + (1.0 - s.min_value) / (s.max_value - s.min_value) * (rr.size.x - gw)
			await ev_move(p0, false)
			await ev_mouse(p0, true)
			for i in range(1, 25):
				await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
			await ev_mouse(Vector2(x1, y), false)
			await idle(3)
	await idle(4)
	var bb := bbox()
	var cx := bb.position.x + bb.size.x * 0.5
	ok(absf(cx) <= 0.01 and absf(bb.size.y - 10.0) <= 0.05, "5 BBOX pulled up 10 mm: the bbox is centred on the mirror line (centre x %.4f mm, want 0 +-0.01) and %.3f mm high" % [cx, bb.size.y])
	var half_poly := [Vector2(0, -30), Vector2(20, -30), Vector2(60, 0), Vector2(20, 30), Vector2(0, 30)]
	var want: float = 2.0 * area(half_poly) * 10.0
	var vol: float = float(pu.res.get("volume", 0.0)) / pow(Part.MM, 3.0)
	ok(absf(vol - want) <= want * 0.005, "6 VOLUME the kernel volume is %.1f mm3, 2 x half area %.1f x 10 mm = %.1f (within 0.5 pct)" % [vol, area(half_poly), want])
	m.pitch = -50.0
	m._cam()
	await shot("done")

	# 7 Mirror off: a Line drag draws ONE straight line
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(mb)   # Mirror Y
	await click_ctl(mb)   # off
	ok(mb.text == "Mirror: off" and not mb.button_pressed, "7a CHIP two more clicks put Mirror back to off (%s)" % mb.text)
	await click_ctl(ep.shape_btns["line"])
	var s7 := n_sketches()
	var u7: int = m.undo.size()
	await drag_pts([scr(Vector2(-90, 60)), scr(Vector2(-60, 60)), scr(Vector2(-30, 60))])
	var sk7 := newest_sketch()
	var k7 := []
	for e in sk7.get("ents", []):
		k7.append(String(e.get("k", "")))
	ok(n_sketches() == s7 + 1 and k7 == ["line"] and m.undo.size() == u7 + 1, "7 OFF Mirror off draws a Line by dragging as before: one sketch of [line], one undo step (kinds %s, undo %d -> %d)" % [str(k7), u7, m.undo.size()])

	# 8 CROSS: Mirror X, a click on the other side is refused
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(mb)   # Mirror X
	var s8 := n_sketches()
	await click_at(scr(Vector2(30, -60)))
	await click_at(scr(Vector2(-30, -60)))
	var said := String(ep.msg)
	ok(ep._draft.has("vx") and (ep._draft["vx"] as Array).size() == 1 and said.contains("across the middle line"), "8 CROSS a click across the middle line is refused in words, no point added (points %d; says: %s)" % [(ep._draft["vx"] as Array).size() if ep._draft.has("vx") else -1, said])
	await ev_move(Vector2(5, 5), false)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc, true)
	await idle(3)
	ok(ep._draft.is_empty() and n_sketches() == s8, "8b Escape cancels the half-drawn mirrored Line, nothing written")

	# 9 Y: three clicks on the front side of the middle line, mirrored front-back
	if ep.armed != "draw":
		await click_ctl(ep.make_btns["draw"])
	if mb.text == "Mirror X":
		await click_ctl(mb)
	ok(mb.text == "Mirror Y", "9a CHIP the next click is Mirror Y (%s)" % mb.text)
	var P1 := Vector2(-40, -20)
	var P2 := Vector2(0, -50)
	var P3 := Vector2(40, -20)
	var s9 := n_sketches()
	await click_at(scr(P1))
	await click_at(scr(P2))
	await click_at(scr(P3))
	await click_at(scr(P3))
	await idle(3)
	var sk9 := newest_sketch()
	var l9 := loop_of(sk9)
	ok(n_sketches() == s9 + 1 and (sk9.get("ents", []) as Array).size() == 6 and bool(l9["closed"]) and distinct(l9["pts"]) == 6 and symmetric(l9["pts"], "y"), "9 Y Mirror Y: a closed 6-point outline symmetric about y = 0 (points %s)" % str(l9["pts"]))
	await shot("y")

	print("s047: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
