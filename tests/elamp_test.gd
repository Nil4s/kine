extends SceneTree
## godot --path . --position 4000,4000 -s tests/elamp_test.gd     (ELAMP: a lamp from the ewalk6 walk; scripts/easy_part.gd; needs the CAD DLL and a window)
## A beginner from the REAL start screen (Home, the building card, Part, Easy). Real clicks and drags at 1280 x 720 only.
##   STICK  ViewCube TOP, a Box drawn small on the floor, Pulled 40 cm (the slider's top): the lamp stick
##   SHADE  ViewCube FRONT (side-on), a closed Curvy shade profile: its foot sits on the stick top (400 mm), its top at 520 mm, Spin it round
## Bars (each FAILED on the old code, see the report):
##   LAMP1  the stick stands 400 mm tall (sanity for the walk)
##   LAMP2  the shade drawn above the stick spins at the height it was drawn: the lamp is 520 mm tall
##   LAMP3  the shade is joined to the stick: one body, no errors
##   LAMP4  the shade is not pushed down to the floor: its lowest point is at the stick top, 400 mm
## Shots: C:/Temp/claude/elamp/lamp.png

const SHOT := "C:/Temp/claude/elamp"
const DIRT := "user://elamp_test"
var fails := 0
var m: Node
var log_lines: Array = []


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, btn := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true, btn := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = btn
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


## a real drag of the slider knob to value v (the row's own units)
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


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func words() -> String:
	return String(ep().msg)


func nbodies() -> int:
	return int(pu().res.get("bodies", 0))


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


func aabb_mm() -> AABB:
	var bb: AABB = pu().res.get("aabb", AABB())
	return AABB(bb.position / Part.MM, bb.size / Part.MM)


func slider_rows() -> Array:
	var out := []
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			out.append(r["slider"])
	return out


func note(step: String, press: String) -> void:
	await idle(3)
	var bb := aabb_mm()
	var line := "%s | %s | words [%s] | bodies %d | errors %d | y %.0f..%.0f mm" % [step, press, words(), nbodies(), errors_of(m.S.part), bb.position.y, bb.end.y]
	print(line)
	log_lines.append(line)


func save_log() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	var f := FileAccess.open(SHOT + "/lamp.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


## the Empty chip: the clean floor between things
func empty_part(why: String) -> void:
	var c := chip("easypart_chip_empty")
	if c != null and c.is_visible_in_tree():
		await click_ctl(c)
	await note("empty", "Empty chip (%s)" % why)


## a real click on a ViewCube face (quad i: 0 FRONT, 1 RIGHT, 2 TOP, 3 BACK, 4 LEFT, 5 BOTTOM)
func turn_cube(i: int) -> void:
	var cube: ViewCube = m.ui_cube
	var q := cube._quad(i)
	var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = cen
	cube._gui_input(ev)
	await idle(60)
	await note("view", "ViewCube face %d click" % i)

## a real click on a ViewCube corner (a 3/4 view): 85 percent of the way from the cube middle to the corner d
func turn_corner(d: Vector3) -> void:
	var cube: ViewCube = m.ui_cube
	var mid := Vector2(cube.SIZE * 0.5, cube.SIZE * 0.5)
	var corner: Vector3 = cube._proj(d)
	var p := mid + (Vector2(corner.x, corner.y) - mid) * 0.85
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	cube._gui_input(ev)
	await idle(60)
	await note("view", "ViewCube corner click")


## real wheel notches over the view (down = zoom out), at the middle of the window
func wheel_out(n: int) -> void:
	for i in n:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = Vector2(640, 360)
		e.global_position = Vector2(640, 360)
		root.push_input(e, true)
		await process_frame
	await idle(60)


## the heights (mm) where a ray straight down x mm off the middle meets the replayed mesh, sorted
func down_hits(xmm: float) -> Array:
	var mesh: ArrayMesh = pu().res.get("mesh")
	var out := []
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arr: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	var from := Vector3(xmm, 1000.0, 0.3)   # MM, off the seam (a ray ON a triangle edge can miss)
	var n: int = (ix.size() if ix != null else vs.size()) / 3
	for t in n:
		var a: Vector3 = vs[ix[3 * t]] if ix != null else vs[3 * t]
		var b: Vector3 = vs[ix[3 * t + 1]] if ix != null else vs[3 * t + 1]
		var c: Vector3 = vs[ix[3 * t + 2]] if ix != null else vs[3 * t + 2]
		var h = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, a / Part.MM, b / Part.MM, c / Part.MM)
		if h != null:
			out.append((h as Vector3).y)
	out.sort()
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
	if not ss.visible:
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
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)
	await empty_part("start of the walk")

	# STICK: a box drawn small on the floor from the top view, Pulled 40 cm
	await turn_cube(2)
	await click_ctl(ep().shape_btns["box"])
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(m.cam.unproject_position(Vector3(-0.02, 0.0, -0.02)), m.cam.unproject_position(Vector3(0.02, 0.0, 0.02)))
	await note("stick", "stick drawn on the floor (top view)")
	await click_ctl(ep().make_btns["pull"])
	await note("stick", "Pull it up (stick)")
	for s in slider_rows():
		await drag_slider(s, 40.0)
	await note("stick", "stick slider 40 cm")
	var stick_top := aabb_mm().end.y
	ok(absf(stick_top - 400.0) < 5.0, "LAMP1 the stick stands 400 mm tall: top %.1f mm" % stick_top)

	# SHADE: a closed Curvy profile on the middle line, its foot on the stick top centre (400 mm), rising to 520 mm
	await turn_corner(Vector3(-1.0, 1.0, 1.0))   # from the top view the FRONT face is a sliver: a 3/4 view first
	await turn_cube(0)
	await idle(120)   # the view eases to the front: a press before it settles maps the profile through the old view
	await wheel_out(12)   # the stick is 40 cm: zoom out so the shade above it is in the view
	await click_ctl(ep().make_btns["curve"])
	var shade := [[0.0, 520.0], [40.0, 520.0], [58.0, 490.0], [60.0, 460.0], [48.0, 430.0], [30.0, 410.0], [20.0, 400.0], [0.0, 400.0], [0.0, 520.0]]   # starts in the air above the stick (a press on the top face makes a flat face plane)
	var sp := []
	for p in shade:
		sp.append(m.cam.unproject_position(Vector3(p[0] * 0.001, p[1] * 0.001, 0.0)))
	log_lines.append("   cam %s rot %s pts %s" % [str(m.cam.global_position), str(m.cam.global_rotation_degrees), str(sp)])
	await drag_path(sp)
	log_lines.append("   sketch after drag %s" % JSON.stringify(m.S.part["features"].back()))
	log_lines.append("   press on screen: %s" % str(sp))
	await note("shade", "Curvy shade profile drawn above the stick (closed on the middle line)")
	await click_ctl(ep().make_btns["spin"])
	await note("shade", "Spin it round")
	await turn_cube(0)
	await shot("lamp")
	var bb := aabb_mm()
	var bodies := nbodies()
	var errs := errors_of(m.S.part)
	ok(absf(bb.end.y - 520.0) < 5.0, "LAMP2 the shade drawn above the stick spins at the height it was drawn: the lamp is 520 mm tall (top %.1f mm)" % bb.end.y)
	ok(bodies == 1 and errs == 0, "LAMP3 the shade is joined to the stick: one body, no errors (bodies %d, errors %d)" % [bodies, errs])
	var under := down_hits(30.0)   # the shade alone: a ray down 30 mm off the middle misses the stick and hits the shade underside (410 mm)
	var under_ok := false
	for h in under:
		if absf(float(h) - 410.0) < 5.0:
			under_ok = true
	ok(under_ok, "LAMP4 the shade is not pushed down to the floor: its underside 30 mm off the middle is 410 mm (hits %s)" % str(under))

	log_lines.append("   features %s" % JSON.stringify(m.S.part["features"]))
	log_lines.append("   replay aabb %s bodies %d" % [str(pu().res.get("aabb", AABB())), nbodies()])
	save_log()
	print("elamp: %d fail" % fails)
	quit(1 if fails > 0 else 0)
