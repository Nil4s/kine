extends SceneTree
## godot --path . --position 4000,4000 -s tests/edoor_test.gd     (EDOOR: Cut a hole cuts the DRAWN SHAPE through the wall; scripts/easy_part.gd; needs the CAD DLL and a window)
## A beginner house by real clicks at 1280 x 720: the Empty chip, a box drawn on the floor and pulled 8 cm, Cut a hole > Hollow inside (a 3 mm wall),
## the ViewCube FRONT face, Draw shape (Box) on the front face: a rectangle of about 24 x 44 mm (the size is read back from the sketch). Then Cut a hole.
## Bars (bar 2 FAILED on the old code: the old Cut a hole made a round hole through the middle of the house, both walls):
##   1 HOLE    one body, no failed step, the newest step is a cut
##   2 RAY     a ray along the z axis through the middle of the door (x 0, y 28 mm) crosses the BACK wall only (2 faces): the front wall has the opening
##   3 WALL    the volume lost is the drawn rectangle x the 3 mm wall, within 10 pct
##   4 UNDO    Cut a hole is one undo step; one undo takes it away and the drawn door stays
##   5 SLIDER  the depth slider: 8 cm goes through the back wall too (volume drops)
## Shot: C:/Temp/claude/edoor/house.png (the house, a 3/4 view, the door open in the front wall)

const SHOT := "C:/Temp/claude/edoor"
const DIRT := "user://edoor_test"
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


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


func feats() -> Array:
	return m.S.part.get("features", []) as Array


## Pull it up, then the slider to h cm
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


func tweak_row_slider() -> HSlider:
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			return r["slider"]
	return null


## crossings of the infinite line through world point p (metres) along axis a (0 x, 1 y, 2 z) with the replay mesh
func hits(res: Dictionary, p: Vector3, a: int) -> int:
	var mesh: ArrayMesh = res.get("mesh")
	if mesh == null:
		return 0
	var o2: int = [1, 2, 0][a]
	var o3: int = [2, 0, 1][a]
	var q := Vector2(p[o2], p[o3])
	var n := 0
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		var cnt := vs.size() if ix == null else (ix as PackedInt32Array).size()
		for t in range(0, cnt - 2, 3):
			var i0: int = t if ix == null else int(ix[t])
			var i1: int = t + 1 if ix == null else int(ix[t + 1])
			var i2: int = t + 2 if ix == null else int(ix[t + 2])
			var a2 := Vector2(vs[i0][o2], vs[i0][o3])
			var b2 := Vector2(vs[i1][o2], vs[i1][o3])
			var c2 := Vector2(vs[i2][o2], vs[i2][o3])
			var d1 := (b2.x - a2.x) * (q.y - a2.y) - (b2.y - a2.y) * (q.x - a2.x)
			var d2 := (c2.x - b2.x) * (q.y - b2.y) - (c2.y - b2.y) * (q.x - b2.x)
			var d3 := (a2.x - c2.x) * (q.y - c2.y) - (a2.y - c2.y) * (q.x - c2.x)
			if (d1 < 0.0 or d2 < 0.0 or d3 < 0.0) and (d1 > 0.0 or d2 > 0.0 or d3 > 0.0):
				continue
			n += 1
	return n


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
	m.S.part = {}
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(30)
	var chip = ep().get("empty_chip")
	if chip == null:
		print("FAIL: no Empty chip")
		quit(1)
		return
	await click_ctl(chip)
	await idle(10)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# THE HOUSE: a box 80 x 60 mm on the floor, pulled 8 cm, Cut a hole > Hollow inside (a 3 mm wall, open at the top)
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.03)), scr(Vector3(0.04, 0.0, 0.03)))
	await pull(8.0)
	await click_ctl(ep().make_btns["hole"])
	var chh := root.find_child("easypart_hole_hollow", true, false) as Button
	if chh != null:
		await click_ctl(chh)
	await idle(3)
	ok(int(pu().res.get("bodies", 0)) == 1 and errors_of(m.S.part) == 0, "0a SETUP the house is one hollow body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# the ViewCube FRONT face: a real click (the front wall faces the camera)
	var cube: ViewCube = m.ui_cube
	var q := cube._quad(0)
	var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = cen
	cube._gui_input(ev)
	await idle(60)

	# THE DOOR: Draw shape (Box) on the front face (z 30 mm), a 24 x 44 mm rectangle low on the wall
	var n_before := feats().size()
	var v_before := vol()
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.012, 0.006, 0.03)), scr(Vector3(0.012, 0.050, 0.03)))
	ok(feats().size() == n_before + 2, "0b DRAW the face sketch is a plane plus a sketch (%d -> %d steps)" % [n_before, feats().size()])
	var u0: int = m.undo.size()
	var n_drawn := feats().size()

	# CUT A HOLE: the drawn shape is cut through the front wall
	await click_ctl(ep().make_btns["hole"])
	await idle(3)
	var res: Dictionary = pu().res
	var lost := v_before - vol()
	var rs: Dictionary = feats()[n_drawn - 1]
	var ra: Array = rs["ents"][0]["a"]
	var rb: Array = rs["ents"][0]["b"]
	var door := absf(float(rb[0]) - float(ra[0])) * absf(float(rb[1]) - float(ra[1])) * 3.0   # the drawn rectangle (mm) x the wall
	print("door rect mm %.1f x %.1f" % [absf(float(rb[0]) - float(ra[0])), absf(float(rb[1]) - float(ra[1]))])
	ok(int(res.get("bodies", 0)) == 1 and errors_of(m.S.part) == 0 and feats().size() == n_drawn + 1 and String((feats().back() as Dictionary)["t"]) == "extrude",
		"1 HOLE one body, no failed step, the newest step is a cut (bodies %d, errors %d)" % [int(res.get("bodies", 0)), errors_of(m.S.part)])
	var ray := hits(res, Vector3(0.0, 0.028, 0.0), 2)
	ok(ray == 2, "2 RAY a ray along z through the middle of the door crosses the back wall only (%d faces, 4 before the door)" % ray)
	ok(absf(lost - door) <= 0.10 * door, "3 WALL the volume lost is the drawn rectangle x 3 mm wall (lost %.0f, expected %.0f mm3)" % [lost, door])
	ok(m.undo.size() == u0 + 1, "4a UNDO Cut a hole is one undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle(10)
	ok(feats().size() == n_drawn and absf(vol() - v_before) < 1.0, "4b UNDO one undo takes the cut away, the drawn door stays (steps %d, volume %.0f -> %.0f)" % [n_drawn, v_before, vol()])
	await click_ctl(ep().make_btns["hole"])
	await idle(3)
	var v_cut := vol()
	ok(absf(v_cut - (v_before - door)) <= 0.10 * door, "4c REDO Cut a hole again makes the same door (volume %.0f)" % v_cut)

	# THE DEPTH SLIDER: 8 cm goes through the back wall too
	var sl := tweak_row_slider()
	if sl != null:
		await drag_slider(sl, 8.0)
	await idle(3)
	ok(sl != null and vol() < v_cut - 1.0, "5 SLIDER 8 cm goes through the back wall too (volume %.0f -> %.0f)" % [v_cut, vol()])
	if sl != null:
		await drag_slider(sl, 0.35)   # back to the wall (3 mm + the 0.5 mm overshoot) for the shot: the door, not the open back
	m.yaw = 35.0
	m.pitch = -25.0
	m._cam()
	await shot("house")
	print("edoor: %d fail" % fails)
	quit(fails)
