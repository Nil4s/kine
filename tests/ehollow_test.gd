extends SceneTree
## godot --path . --position 4000,4000 -s tests/ehollow_test.gd     (EHOLLOW: Easy Part's Cut a hole gets a HOLLOW INSIDE choice; scripts/easy_part.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from an empty Easy part: a round shape drawn on the floor (r 40 mm), pulled up to 80 mm, then Cut a hole.
## Bars (run once on the old code: 1, 2, 3 and 5 FAIL there, because the old Cut a hole has no Hollow inside chip):
##   1 HOLLOW  Hollow inside: one body, volume = outer - inner within 2 pct (inner = a 3 mm wall, open at the top: r-3 wide, h-3 deep)
##   2 OPEN    the top is open: a ray down the middle hits the INSIDE floor at y about 3 mm
##   3 WALL    the Wall slider to 6 mm: volume = outer - inner (6 mm wall) within 2 pct, more solid than at 3 mm (a thicker wall), and ONE undo step for the drag
##   4 THROUGH Through (the default after Cut a hole) still makes today's hole: a 10 mm radius cut, reaching h/2 + 10 mm up the 80 mm body (the floor hole's both-ways depth, as the old code), within 10 pct
##   5 REFUSE  a 2 mm body cannot take a 3 mm wall: Hollow inside says so in words ("too thin") and leaves no undo step
## Shot: C:/Temp/claude/ehollow/shot.png, the hollow cup seen from above at an angle (LOOK at it)
const SHOT := "C:/Temp/claude/ehollow"
const DIRT := "user://ehollow_test"

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


## a real drag: press at a, move in steps to b (held), release
func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of the slider knob to value v
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


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func undo_n() -> int:
	return m.undo.size()


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button   # null on the old code: no such chip


## an empty part, the camera above the floor
func fresh(pitch: float) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = pitch
	m.yaw = 20.0
	m._cam()
	await idle(60)


## Draw shape, Round, then a real drag from the floor centre out to r = 40 mm; then Pull it up to h cm (the slider)
func round_cup(h: float) -> void:
	await fresh(-40.0)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


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


## the highest y where a ray going DOWN at (x, z) hits a triangle (Moller-Trumbore), or NAN
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


## mm3: the cup's inside, open at the top, floor = wall
func inner_vol(r: float, h: float, wall: float) -> float:
	return PI * pow(r - wall, 2.0) * (h - wall)


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# 1 HOLLOW + 2 OPEN: an 80 mm cup, Cut a hole, Hollow inside
	await round_cup(8.0)
	var outer := vol()
	var bb := bbox()
	var r := bb.size.x * 0.5
	var h := bb.size.y
	ok(absf(r - 40.0) < 0.6 and absf(h - 80.0) < 0.6, "0 SETUP round r 40 mm, 80 mm tall (r %.2f, h %.2f) bodies %d" % [r, h, int(pu().res.get("bodies", 0))])
	await click_ctl(ep().make_btns["hole"])
	var ch_h := chip("easypart_hole_hollow")
	var ch_t := chip("easypart_hole_through")
	ok(ch_h != null and ch_t != null and ch_h.is_visible_in_tree() and ch_t.is_visible_in_tree(), "1a HOLLOW Cut a hole shows the Through and Hollow inside chips")
	if ch_h == null:
		ch_h = Button.new()   # the old code: the bars below fail without a chip
	await click_ctl(ch_h)
	await idle(3)
	var inner3 := inner_vol(r, h, 3.0)
	var want3 := outer - inner3
	var v3 := vol()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(v3 - want3) / want3 < 0.02,
		"1 HOLLOW one body, volume = outer - inner for a 3 mm wall within 2 pct: %.0f mm3 vs %.0f (outer %.0f, inner %.0f, bodies %d)" % [v3, want3, outer, inner3, int(pu().res.get("bodies", 0))])
	var ray_y := top_hit_y(bb.get_center().x * Part.MM, bb.get_center().z * Part.MM)   # the ray takes metres; the bbox is mm
	ok(not is_nan(ray_y) and absf(ray_y * 1000.0 - 3.0) < 0.5, "2 OPEN a ray down the middle hits the inside floor at y about 3 mm: %.2f mm" % (ray_y * 1000.0 if not is_nan(ray_y) else -1.0))
	await idle(3)
	m.pitch = -50.0
	m.yaw = 35.0
	ep().frame()
	await idle(60)
	await shot("shot")

	# 3 WALL: the slider to 6 mm, one undo step
	var wall_row := {}
	for rw in ep().rows:
		if String(rw["kind"]) == "tweak":
			wall_row = rw
	var u0 := undo_n()
	if wall_row.is_empty():
		ok(false, "3 WALL the Wall slider is there")
	else:
		await drag_slider(wall_row["slider"], 6.0)
		await idle(3)
		var inner6 := inner_vol(r, h, 6.0)
		var want6 := outer - inner6
		var v6 := vol()
		ok(absf(v6 - want6) / want6 < 0.02 and v6 > v3, "3 WALL slider to 6 mm: volume = outer - inner (6 mm) within 2 pct, MORE solid than at 3 mm: %.0f vs %.0f (3 mm: %.0f)" % [v6, want6, v3])
		ok(undo_n() - u0 == 1, "3b WALL the drag is ONE undo step (%d)" % (undo_n() - u0))

	# 4 THROUGH: the default hole
	await round_cup(8.0)
	outer = vol()
	await click_ctl(ep().make_btns["hole"])
	await idle(2)
	var drop := outer - vol()
	var want_t := PI * 10.0 * 10.0 * (80.0 / 2.0 + 10.0)   # today's floor hole: dist h+20 cut both ways = h/2+10 up from the floor
	ok(absf(drop - want_t) / want_t < 0.10 and int(pu().res.get("bodies", 0)) == 1,
		"4 THROUGH Cut a hole still makes the through hole: volume drop %.0f mm3 vs a 10 mm hole %.0f" % [drop, want_t])
	ok(ep().hint_l.text.contains("straight through"), "4b THROUGH the words say so [%s]" % ep().hint_l.text)

	# 5 REFUSE: a 2 mm body cannot take a 3 mm wall
	await round_cup(0.2)
	await click_ctl(ep().make_btns["hole"])
	await idle(2)
	var ch5 := chip("easypart_hole_hollow")
	if ch5 == null:
		ch5 = Button.new()
	var u5 := undo_n()
	var f5 := (m.S.part["features"] as Array).size()
	await click_ctl(ch5)
	await idle(3)
	ok(ep().hint_l.text.contains("too thin") and undo_n() == u5 and (m.S.part["features"] as Array).size() == f5,
		"5 REFUSE a too-thin body says so in words and leaves no undo step [%s] (undo %d -> %d)" % [ep().hint_l.text, u5, undo_n()])

	print("ehollow: %d fail" % fails)
	quit(1 if fails > 0 else 0)
