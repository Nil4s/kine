extends SceneTree
## s016 (Friday plan 16): while the Wall slider moves, the Easy Part shows the part sliced in half (the cut face in a Tok
## colour, so a beginner SEES the wall); on release the part goes back to the full view. A beginner walk with real clicks and drags
## on the live Easy Part at 1280 x 720: a round cup (Pull it up), Cut a hole > Hollow inside, then the Wall slider held and released.
## Bars: see the ok lines (A0 whole part before, B looking is no undo step, C band width 2 -> 6 mm ratio 3.0, D release restores the view)
const SHOT := "C:/Temp/claude/s016"
const DIRT := "user://s016_test"
const CUT_COL := Color(1.0, 0.45, 0.62)   # Tok sg_phase (rose): the Easy view draws its amber dots in Tok heading, so the cut face takes a colour the view does not use
const FOV := 8.0
const DIST := 1.6
var fails := 0
var m: Node
var pu
var ep
var _sx := 0.0
var _sy := 0.0


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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func wall_slider() -> HSlider:
	for r in ep.rows:
		if String(r["kind"]) == "tweak" and r["slider"] is HSlider:
			return r["slider"]
	return null


func knob_x(s: HSlider, v: float) -> float:
	var r := s.get_global_rect()
	return r.position.x + 12.0 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - 24.0)


## a real press on the Wall knob, held; the caller moves it with hold_to and lets go with release_at
func press_knob(s: HSlider) -> void:
	_sy = s.get_global_rect().get_center().y
	_sx = knob_x(s, s.value)
	await ev_move(Vector2(_sx, _sy), false)
	await ev_mouse(Vector2(_sx, _sy), true)


func hold_to(s: HSlider, v: float) -> void:
	var x1 := knob_x(s, v)
	for i in range(1, 13):
		await ev_move(Vector2(lerpf(_sx, x1, i / 12.0), _sy))
	_sx = x1
	await idle(14)
	await landed()


## the slider's background preview has landed on the view (nothing running, nothing waiting, no number waiting to be written)
func landed() -> void:
	for i in 400:
		if pu._tess_run.is_empty() and pu._tess_next.is_empty() and not ep._dirty:
			break
		await process_frame
	await idle(4)


func release_at(_s: HSlider) -> void:
	await ev_mouse(Vector2(_sx, _sy), false)
	await idle(14)


## the free 3D view under the Easy buttons (window pixels): the cup is drawn here, and no panel is
const VIEW := Rect2i(0, 520, 1000, 330)
var cbox := Rect2i(0, 0, 0, 0)   # the cup's box on screen (window pixels), found from the cut face of the first held shot


func shot(nm: String) -> Image:
	await idle(2)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT)
	img.save_png("%s/%s.png" % [SHOT, nm])
	return img


func is_cap(c: Color) -> bool:
	return absf(c.r - CUT_COL.r) < 0.05 and absf(c.g - CUT_COL.g) < 0.05 and absf(c.b - CUT_COL.b) < 0.05


func cap_box(img: Image) -> Rect2i:
	var mn := Vector2i(100000, 100000)
	var mx := Vector2i(-1, -1)
	for y in range(VIEW.position.y, VIEW.end.y):
		for x in range(VIEW.position.x, VIEW.end.x):
			if is_cap(img.get_pixel(x, y)):
				mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
				mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
	if mx.x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(mn, mx - mn + Vector2i(1, 1))


func cap_count(img: Image) -> int:
	var n := 0
	for y in range(VIEW.position.y, VIEW.end.y):
		for x in range(VIEW.position.x, VIEW.end.x):
			if is_cap(img.get_pixel(x, y)):
				n += 1
	return n


## the share of colour C in pixel p, between the two colours A and C (an edge pixel is a blend of both)
func share(p: Color, a: Color, c: Color) -> float:
	var d := Vector3(c.r - a.r, c.g - a.g, c.b - a.b)
	var v := Vector3(p.r - a.r, p.g - a.g, p.b - a.b)
	return clampf(v.dot(d) / maxf(d.dot(d), 1e-6), 0.0, 1.0)


## the wall band: in the rows across the middle of the cut face, the first run of cut-colour pixels (the left wall) plus the share of the two
## blended edge pixels beside it (sub-pixel); mean over the rows. In the 1280 x 720 layout's pixels (the window is 1600 x 900). -1 = none
func band_px(img: Image) -> float:
	var r := cap_box(img)
	if r.size.y < 10:
		return -1.0
	var ws := []
	for y in range(int(r.position.y + r.size.y * 0.35), int(r.position.y + r.size.y * 0.65)):
		var x0 := -1
		var x1 := -1
		for x in range(r.position.x, r.end.x):
			if is_cap(img.get_pixel(x, y)):
				if x0 < 0:
					x0 = x
				x1 = x
			elif x0 >= 0:
				break
		if x0 < 3 or x1 < 0:
			continue
		var w := float(x1 - x0 + 1)
		w += share(img.get_pixel(x0 - 1, y), img.get_pixel(x0 - 3, y), CUT_COL)
		w += share(img.get_pixel(x1 + 1, y), img.get_pixel(x1 + 3, y), CUT_COL)
		ws.append(w)
	if ws.size() < 5:
		return -1.0
	var sum := 0.0
	for w in ws:
		sum += float(w)
	return sum / ws.size() * 1280.0 / float(img.get_width())


## pixels of the cup's box that differ between two shots
func diff_px(a: Image, b: Image) -> int:
	var r := cbox.grow(12)
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06:
				n += 1
	return n


func labels(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


## C4: the wall of the built mesh at mid height: a ray from the middle of the cup, level, out through the wall; every triangle it
## crosses gives a distance (mm). The inner wall and the outer wall are the last two crossings: the wall is their gap
func built_wall_mm(shown := false) -> float:
	var res := Part.replay(m.S.part)
	var mesh: ArrayMesh = pu.part_mesh.mesh if shown else res.get("mesh")
	if mesh == null:
		return -1.0
	var bb: AABB = mesh.get_aabb()
	var ymid := bb.position.y + bb.size.y * 0.5
	var c := Vector3(bb.position.x + bb.size.x * 0.5, ymid, bb.position.z + bb.size.z * 0.5)
	var d := Vector3(cos(0.37), 0.0, sin(0.37)) * (bb.size.x + bb.size.z)
	var dists := []
	for sf in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(sf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		var n := verts.size() if idx == null else (idx as PackedInt32Array).size()
		for t in range(0, n - 2, 3):
			var a: Vector3 = verts[t] if idx == null else verts[(idx as PackedInt32Array)[t]]
			var b: Vector3 = verts[t + 1] if idx == null else verts[(idx as PackedInt32Array)[t + 1]]
			var q: Vector3 = verts[t + 2] if idx == null else verts[(idx as PackedInt32Array)[t + 2]]
			var hit: Variant = Geometry3D.segment_intersects_triangle(c, c + d, a, b, q)
			if hit != null:
				dists.append(snappedf((hit as Vector3).distance_to(c) / Part.MM, 0.01))
	dists.sort()
	var uniq := []
	for x in dists:
		if uniq.is_empty() or absf(float(x) - float(uniq[-1])) > 0.02:
			uniq.append(x)
	if uniq.size() < 2:
		return -1.0
	return float(uniq[-1]) - float(uniq[-2])


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
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = -35.0   # a view from above (main.gd _cam: a positive pitch looks from under the floor, where the floor hides the part)
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# the cup: a round body, pulled up; then Cut a hole, Hollow inside
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_pts([scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await click_ctl(ep.make_btns["hole"])
	await click_ctl(ep.hole_btns["hollow"])
	await idle(20)
	var s := wall_slider()
	var made: bool = s != null and String(ep.tweak.get("label", "")) == "Wall" and int(Part.replay(m.S.part)["bodies"]) == 1
	ok(made, "C0 the walk: a hollow cup with a Wall slider on the live Easy Part (slider %s, bodies %d)" % [s != null, int(Part.replay(m.S.part)["bodies"])])
	if not made:
		print("s016: %d fail" % (fails + 1))
		quit(1)
		return

	m.pitch = -12.0   # now look at the cup from the side and a little above
	m.yaw = 0.0
	m.cam.fov = FOV   # a long lens and the camera close in: the cup fills the free space under the buttons
	m.dist = DIST
	m._cam()
	await idle(60)
	var u0: int = m.undo.size()
	var before := await shot("before")
	ok(cap_count(before) <= 20, "A0 before the press the whole part shows, no cut face: %d cut-colour px (<= 20)" % cap_count(before))
	await press_knob(s)
	await idle(10)
	var look := await shot("look_only")
	cbox = cap_box(look)
	ok(cap_count(look) > 300, "B1 pressing the Wall knob shows the cut: %d cut-colour px (> 300), cup box %s" % [cap_count(look), str(cbox)])
	await release_at(s)
	ok(m.undo.size() == u0, "B2 merely looking (press and let go, no move) is no undo step: %d -> %d" % [u0, m.undo.size()])
	await create_timer(2.5).timeout
	await idle(10)
	var rest0 := await shot("rest")
	await press_knob(s)
	await hold_to(s, 2.0)
	var words := []
	labels(ep.status, words)
	words.append(String(ep.hint_l.text))
	words.append(String(ep.msg))
	var said := " ".join(words).to_lower()
	var img2 := await shot("held2")
	var b2 := band_px(img2)
	await hold_to(s, 6.0)
	var img6 := await shot("held6")
	var b6 := band_px(img6)
	var ratio := b6 / b2 if b2 > 0.0 else 0.0
	ok(b2 > 0.0 and absf(ratio - 3.0) <= 0.45, "C1 wall 2 -> 6 mm: band width %.1f px -> %.1f px (1280 x 720 layout px), ratio %.2f (3.0 within 15 percent)" % [b2, b6, ratio])
	var cb6 := cap_box(img6)
	var cy := cb6.position.y + cb6.size.y / 2
	var bx := -1
	for x in range(cb6.position.x, cb6.end.x):
		if is_cap(img6.get_pixel(x, cy)):
			bx = x
			break
	var cap_c: Color = img6.get_pixel(bx, cy) if bx >= 0 else Color.BLACK
	var near: Color = img6.get_pixel(clampi(bx + int(b6 * 1.25) + 8, 0, 1599), cy) if bx >= 0 else Color.BLACK
	var dist := absf(cap_c.r - near.r) + absf(cap_c.g - near.g) + absf(cap_c.b - near.b)
	var fl: Color = img6.get_pixel(clampi(bx - 8, 0, 1599), cy)
	var dfl := absf(cap_c.r - fl.r) + absf(cap_c.g - fl.g) + absf(cap_c.b - fl.b)
	ok(bx >= 0 and dist >= 0.4 and dfl >= 0.4, "C2 the band stands out: colour distance %.2f from the part beside it, %.2f from the floor (both >= 0.4)" % [dist, dfl])
	ok(said.find("cut in half") >= 0, "C3 words while held say the part is cut in half: [%s]" % said)
	await hold_to(s, 3.0)
	await release_at(s)
	var soon := await shot("soon_after")
	ok(cap_count(soon) > 300, "D1 just after the release the cut stays: %d cut-colour px (> 300)" % cap_count(soon))
	await create_timer(2.5).timeout
	await idle(15)
	var after := await shot("released")
	ok(cap_count(after) <= 20, "D2 2.5 s after the release no cut face is left: %d px (<= 20)" % cap_count(after))
	var dd := diff_px(rest0, after)
	var area := cbox.grow(12).get_area()
	ok(dd <= int(area * 0.005), "D3 the view is the whole part again, same as before the drag (wall back at 3 mm): %d of %d px differ (<= 0.5 percent)" % [dd, area])
	var dh := diff_px(after, img6)
	ok(dh > 500, "D4 the held view and the released view differ: %d px (> 500)" % dh)
	var wall := built_wall_mm()
	ok(absf(wall - 3.0) <= 0.3, "D5 the built wall is 3.0 mm within 0.3 mm (measured on the mesh at mid height): %.2f mm" % wall)
	var du: int = m.undo.size() - u0
	ok(du == 0, "D6 the 3 -> 2 -> 6 -> 3 drag ended where it began: no undo step, and looking added none: %d steps" % du)
	await press_knob(s)
	await hold_to(s, 5.0)
	await release_at(s)
	ok(m.undo.size() == u0 + 1, "D7 a drag that really changes the wall (3 -> 5 mm) is ONE undo step: %d steps" % (m.undo.size() - u0))
	print("s016: %d fail" % fails)
	quit(1 if fails > 0 else 0)
