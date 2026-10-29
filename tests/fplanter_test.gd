extends SceneTree
## godot --path . --position 4000,4000 -s tests/fplanter_test.gd     (FPLANTER: a plant pot with a saucer, free building; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen: the BUILDING card opens a blank Easy Part; the pot is a round shape drawn on
## the floor and pulled up to 10 cm, Cut a hole > Hollow inside (3 mm wall, open at the top), then a drain hole through the floor (Cut a hole
## again); the saucer is a second round shape drawn beside the pot and pulled up (default 2 cm): a separate piece.
## Bars (the run on the code before the change is recorded in the report):
##   0 CARD    the BUILDING card, one click: page BUILD, Easy Part on, the part is empty
##   1 BODY    Draw shape, Round, a drag of r 40 mm, Pull it up, 10 cm slider: one solid, 80 mm wide and 100 mm tall (within 6 pct)
##   2 HOLLOW  Cut a hole > Hollow inside: volume = outer - inner (3 mm wall, open at the top) within 3 pct
##   3 OPEN    a ray down the middle lands on the inside floor at about 3 mm (the top is open, the floor is closed)
##   4 DRAIN   Cut a hole after the hollow: a ray down the middle hits NOTHING (the hole goes through the floor); 2 cm out it still hits at 3 mm
##   5 TAPER   the pot narrows toward its floor: the top radius is at least 10 pct wider than the bottom radius
##   6 SAUCER  a second Draw shape (Round) beside the pot, Pull it up (default 2 cm): two solids; the saucer is 110 to 130 mm wide, 15 to 25 mm tall
##   7 ONE     the hollow press and the drain press are one undo step each
##   8 WORDS   no sketch / extrude / fillet / boolean / loft / revolve words on screen
## shots: C:/Temp/claude/fplanter/card.png, body.png, hollow.png, drain.png, saucer.png (LOOK at them)
const SHOT := "C:/Temp/claude/fplanter"
const DIRT := "user://fplanter_test"

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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of a slider knob to value v (the slider's own units)
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
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


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func bodies() -> int:
	return int(pu().res.get("bodies", 0))


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func undo_n() -> int:
	return m.undo.size()


## the mesh's triangles in world metres
func world_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi: MeshInstance3D = pu().part_mesh
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


## the highest y (metres) where a ray going DOWN at (x, z) hits a triangle, or NAN (nothing below = a hole)
func top_hit_y(x: float, z: float) -> float:
	var tris := world_tris()
	var o := Vector3(x, 1.0, z)
	var d := Vector3.DOWN
	var best := NAN
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var e1 := tris[k + 1] - a
		var e2 := tris[k + 2] - a
		var p := d.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-12:
			continue
		var s := o - a
		var u := s.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var v := d.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var tt := e2.dot(q) / det
		if tt < 0.0:
			continue
		var y := o.y + d.y * tt
		if is_nan(best) or y > best:
			best = y
	return best


## the outer radius (mm) of the mesh at height h (mm above the floor): the farthest point from the middle line where the mesh
## crosses the plane y = h (edge crossings; a straight wall has only its two rings as vertices, so the crossings are the test)
func radius_at(h_mm: float) -> float:
	var h := h_mm / 1000.0
	var best := 0.0
	var tris := world_tris()
	for k in range(0, tris.size() - 2, 3):
		for e in [[0, 1], [1, 2], [2, 0]]:
			var a := tris[k + e[0]]
			var b := tris[k + e[1]]
			if absf(a.y - b.y) < 1e-9 or (a.y - h) * (b.y - h) > 0.0:
				continue
			var p := a.lerp(b, (h - a.y) / (b.y - a.y))
			best = maxf(best, Vector2(p.x, p.z).length())
	return best * 1000.0


func bad_words(texts: Array) -> Array:
	var out := []
	for t in texts:
		var l := String(t).to_lower()
		for w in ["sketch", "extrude", "fillet", "boolean", "loft", "revolve"]:
			if l.find(w) >= 0:
				out.append(String(t))
				break
	return out


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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var feats: Array = m.S.part.get("features", [])
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and feats.is_empty(),
		"0 BUILDING card, one click: page BUILD, Easy Part on, the part is empty (page %s, steps %d)" % [m.cur_page, feats.size()])
	await shot("card")

	# the camera: the floor from above at an angle
	m.target = Vector3.ZERO
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 BODY: Draw shape, Round, a drag of r 40 mm from the floor centre, Pull it up, 10 cm
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	var u0 := undo_n()
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 10.0)
	await idle(3)
	var bb := bbox()
	var r_base := radius_at(8.0)
	ok(bodies() == 1 and absf(bb.size.y - 100.0) <= 6.0 and absf(r_base - 40.0) <= 3.0,
		"1 BODY one solid, 100 mm tall, 80 mm across at the floor (bodies %d, height %.1f mm, floor radius %.1f mm)" % [bodies(), bb.size.y, r_base])
	await shot("body")

	# 1b TAPER SLIDER: a beginner drags Taper (under How far) to -8 degrees: the top is wider than the floor (the test drags it)
	var taper_row = ep().get("taper_row")   # null on the old code (no Taper row)
	if taper_row is Dictionary and not (taper_row as Dictionary).is_empty():
		await drag_slider(taper_row["slider"], -8.0)
	await idle(3)
	var tan8 := tan(deg_to_rad(8.0))

	# 2 HOLLOW: Cut a hole, then the Hollow inside chip (a frustum shell: outer minus the inside, 3 mm wall, open at the top)
	await click_ctl(ep().make_btns["hole"])
	var ch_h: Button = root.find_child("easypart_hole_hollow", true, false) as Button
	if ch_h != null:
		await click_ctl(ch_h)
	await idle(5)
	var r0 := 40.0
	var r1 := 40.0 + 100.0 * tan8
	var outer := PI * 100.0 * (r0 * r0 + r0 * r1 + r1 * r1) / 3.0
	var c0 := 40.0 + 3.0 * tan8 - 3.03
	var c1 := r1 - 3.03
	var inner := PI * 97.0 * (c0 * c0 + c0 * c1 + c1 * c1) / 3.0
	var v := vol()
	ok(ch_h != null and absf(v - (outer - inner)) <= 0.03 * (outer - inner),
		"2 HOLLOW Hollow inside: volume %.0f mm3, want about %.0f (outer - inner)" % [v, outer - inner])

	# 3 OPEN: a ray down the middle lands on the inside floor at about 3 mm
	var fy := top_hit_y(0.0, 0.0)
	ok(not is_nan(fy) and absf(fy - 0.003) <= 0.0015, "3 OPEN the middle ray lands on the inside floor at about 3 mm (y %.4f m)" % fy)
	await shot("hollow")

	# 4 DRAIN: Cut a hole again (the newest hole goes through the middle, down through the floor)
	var u1 := undo_n()
	await click_ctl(ep().make_btns["hole"])
	await idle(5)
	var dy := top_hit_y(0.0, 0.0)
	var edge := top_hit_y(0.02, 0.0)
	ok(is_nan(dy) and not is_nan(edge) and absf(edge - 0.003) <= 0.0015,
		"4 DRAIN the middle ray finds nothing, the floor 2 cm out is still 3 mm (middle %s, edge %.4f)" % [str(dy), edge])
	await shot("drain")

	# 5 TAPER: the pot narrows toward its floor
	var r_bot := radius_at(10.0)
	var r_top := radius_at(90.0)
	ok(r_top >= r_bot * 1.10, "5 TAPER the top is wider than the floor by 10 pct (top %.1f mm, floor %.1f mm)" % [r_top, r_bot])

	# 6 SAUCER: a second round shape beside the pot (its middle 12 cm out), r 60 mm, pulled up (default 2 cm): a separate piece
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.12, 0.0, 0.0)), scr(Vector3(0.18, 0.0, 0.0)))
	await click_ctl(ep().make_btns["pull"])
	await idle(5)
	var lumps: int = ep()._lumps(pu().res)
	var s_mid := top_hit_y(0.12, 0.0)
	var s_edge := top_hit_y(0.17, 0.0)
	var s_out := top_hit_y(0.19, 0.0)
	ok(lumps == 2 and absf(s_mid - 0.02) <= 0.002 and absf(s_edge - 0.02) <= 0.002 and is_nan(s_out),
		"6 SAUCER two separate pieces (%d), its top at 2 cm (middle %.4f m, 5 cm out %.4f m), nothing 7 cm out" % [lumps, s_mid, s_edge])
	await shot("saucer")

	# 7 ONE: the hollow press and the drain press are one undo step each
	ok(u1 - u0 >= 2 and undo_n() > u1, "7 ONE undo steps grow by one per press (undo %d, %d, %d)" % [u0, u1, undo_n()])

	# 8 WORDS
	var texts: Array = []
	texts_under(m, texts)
	var bw := bad_words(texts)
	ok(bw.is_empty(), "8 WORDS no sketch / extrude / fillet / boolean / loft / revolve on screen %s" % [bw])

	print("fplanter: %d fail" % fails)
	quit(1 if fails > 0 else 0)

