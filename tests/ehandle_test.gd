extends SceneTree
## godot --path . --position 4000,4000 -s tests/ehandle_test.gd     (EHANDLE: Cut a hole goes THROUGH the newest piece (a handle) along its pull; scripts/easy_part.gd; needs the CAD DLL and a window)
## Mug by real clicks (round r 40, Pull to 80, Cut a hole > Hollow inside), a closed Curvy loop on the side-on wall = a handle, Pulled both ways.
## Then Cut a hole (Through, the default). Real clicks and drags at 1280 x 720.
## Bars (bar 2 FAILED on the old code: the old hole is a vertical hole on the mug's front plane, so the handle stays a solid fin there):
##   1 HOLE    one body, no failed step
##   2 RAY     a ray along the pull direction through the handle loop's middle (mm 48.5, 42.5: the middle of the handle loop's box) passes through NO solid
##   3 WALL    the hole takes only the handle's material: the body's volume lost equals the handle's own loss (within 0.5 pct of the body)
##   4 UNDO    Cut a hole is one undo step
##   5 SLIDER  the hole slider changes the hole (volume changes)
##   6 FLOOR   on a plain floor body (round cup, no handle) Cut a hole still makes the vertical hole: its sketch is on the floor (plane top), a ray down the middle hits no solid
## Shot: C:/Temp/claude/ehandle/shot.png, the mug with a see-through handle at a 3/4 view (LOOK: you must see through the handle)

const SHOT := "C:/Temp/claude/ehandle"
const DIRT := "user://ehandle_test"
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


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


## an empty part, the camera above (pitch < 0) or below (pitch > 0) the floor
func fresh(pitch: float) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = pitch
	m.yaw = 20.0
	m._cam()
	await idle(60)


## the Draw shape button, then a real drag on the floor from world a to world b (metres, y = 0)
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


## Pull it up, then the slider to h cm (the default is 2 cm)
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)



func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		for i in range(1, 9):
			await ev_move(a.lerp(b, i / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


## a round cup: a circle r 40 mm on the floor, pulled up h cm (made by clicks)
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


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button

## crossings of a ray from world point p (metres) along axis a (0 x, 1 y, 2 z) with the replay mesh (even = outside every solid)
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
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# THE MUG: round r 40, Pull to 80 mm, Cut a hole > Hollow inside (a 3 mm wall)
	await round_cup(8.0)
	await click_ctl(ep().make_btns["hole"])
	var chh := chip("easypart_hole_hollow")
	if chh != null:
		await click_ctl(chh)
	await idle(3)
	ok(int(pu().res.get("bodies", 0)) == 1 and errors_of(m.S.part) == 0, "0a SETUP the mug is one hollow body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# the camera side-on: the ViewCube FRONT face, a real click
	var cube: ViewCube = m.ui_cube
	var q := cube._quad(0)
	var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = cen
	cube._gui_input(ev)
	await idle(60)
	ok(ep()._side_on(), "0b SIDE the ViewCube FRONT click looks side-on (yaw %.1f, pitch %.1f)" % [float(m.yaw), float(m.pitch)])

	# THE HANDLE: a closed Curvy loop on the wall, bulging out to +X, Pulled both ways
	var loop := [[35.0, 15.0], [50.0, 20.0], [62.0, 42.0], [50.0, 60.0], [35.0, 70.0], [45.0, 42.0], [35.0, 15.0]]
	var pts := []
	for p in loop:
		pts.append(scr(Vector3(p[0] * 0.001, p[1] * 0.001, 0.0)))
	await click_ctl(ep().make_btns["curve"])
	await drag_path(pts)
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 1.0)
	await idle(3)
	var rh: Dictionary = m.S.part
	ok(int(pu().res.get("bodies", 0)) == 1 and errors_of(rh) == 0, "0c SETUP the handle is one body with the mug (bodies %d)" % int(pu().res.get("bodies", 0)))
	var rep0 := Part.replay(rh)
	var body0: float = float(rep0["volume"])

	# 1 HOLE: Cut a hole with its default Through chip (a real click on the MAKE button)
	var u0: int = m.undo.size()
	await click_ctl(ep().make_btns["hole"])
	await idle(3)
	var rc: Dictionary = m.S.part
	var rep1 := Part.replay(rc)
	ok(int(pu().res.get("bodies", 0)) == 1 and errors_of(rc) == 0, "1a HOLE one body, no failed step (bodies %d, errors %d)" % [int(pu().res.get("bodies", 0)), errors_of(rc)])
	var words := String(ep().msg)
	ok(words.contains("A hole through the new piece"), "1b WORDS [%s]" % words)

	# 2 RAY: the handle loop's middle (x 51, y 42 mm), straight along the pull (z): no solid on the ray
	var ray_p := Vector3(0.0485, 0.0425, 0.0)
	var nh := hits(rep1, ray_p, 2)
	ok(nh == 0, "2a RAY through the handle middle along the pull passes NO solid (crossings %d)" % nh)
	ok(hits(rep0, ray_p, 2) > 0, "2b RAY the same ray hits the handle before the hole (crossings %d)" % hits(rep0, ray_p, 2))

	# 3 WALL: the mug wall is untouched: the far wall (x -38.5 at y 40, x 38.5 at y 60, both out of the hole's reach) still shows its two faces
	var wall_a := hits(rep1, Vector3(-0.0385, 0.040, 0.0), 2)
	var wall_b := hits(rep1, Vector3(0.0385, 0.060, 0.0), 2)
	var wall_0a := hits(rep0, Vector3(-0.0385, 0.040, 0.0), 2)
	var wall_0b := hits(rep0, Vector3(0.0385, 0.060, 0.0), 2)
	var mm3 := Part.MM * Part.MM * Part.MM
	ok(wall_a == wall_0a and wall_b == wall_0b and wall_a > 0 and wall_b > 0, "3a WALL the mug wall is untouched: wall crossings %d/%d before, %d/%d after the hole (body lost %.0f mm3)" % [wall_0a, wall_0b, wall_a, wall_b, (body0 - float(rep1["volume"])) / mm3])

	# 4 UNDO: the hole is one undo step
	ok(m.undo.size() == u0 + 1, "4a UNDO Cut a hole is one undo step (%d -> %d)" % [u0, m.undo.size()])

	# 5 SLIDER: the hole slider changes the hole
	var v1 := vol()
	var moved := false
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 1.0)
			moved = true
	await idle(3)
	var v2 := vol()
	ok(moved and errors_of(m.S.part) == 0 and absf(v2 - v1) > 0.005 * v1, "5a SLIDER the hole slider changes the hole: %.0f -> %.0f mm3" % [v1, v2])

	m.pitch = -10.0
	m.yaw = 35.0
	m._cam()
	await shot("shot")
	m.pitch = -8.0
	m.yaw = 0.0
	m._cam()

	# 6 FLOOR: a plain round cup on the floor keeps the vertical hole
	await fresh(-40.0)
	await round_cup(8.0)
	await click_ctl(ep().make_btns["hole"])
	await idle(3)
	var rf: Dictionary = m.S.part
	var holes := 0
	var hole_plane := ""
	for f in rf["features"]:
		if String(f["t"]) == "sketch" and (f["ents"] as Array).size() > 0 and String((f["ents"] as Array)[0].get("k", "")) == "circle":
			holes += 1
			hole_plane = String(f.get("plane", ""))
	var rp := Part.replay(rf)
	ok(int(pu().res.get("bodies", 0)) == 1 and errors_of(rf) == 0 and holes == 2 and hole_plane == "top", "6a FLOOR the plain cup gets the vertical hole on the floor (plane %s, circle sketches %d)" % [hole_plane, holes])
	ok(hits(rp, Vector3(0.0, 0.05, 0.0), 1) == 0, "6b FLOOR a ray down the middle of the cup passes no solid")

	print("ehandle: %d fail" % fails)
	quit(1 if fails > 0 else 0)
