extends SceneTree
## godot --path . --position 4000,4000 -s tests/eseat_test.gd     (ESEAT: the three Easy Part dead ends found by the ewalk5 beginner walk; scripts/easy_part.gd; needs the CAD DLL and a window)
## A beginner from the REAL start screen (Home, the building card, Part, Easy). Real clicks and drags at 1280 x 720 only. The Empty chip between things.
##   CHAIR  four legs drawn from the TOP view (each Pulled 40 cm, every press must draw), an orbit drag, a Box seat drawn on the leg tops, Pulled 4 cm up
##   ROOF   a Box on the floor Pulled 30 cm, ViewCube FRONT (side-on), a Pointy drawn UPRIGHT above the box top, Pulled 30 cm: a roof on the box
##   BOWL   ViewCube FRONT, a Curvy cup profile closed ON the middle line: the words say Spin it round; Spin it round: one hollow body
## Bars (each FAILED on the old code, see the report):
##   SEAT1  the seat pulled 4 cm stands on the leg tops: 440 mm tall
##   SEAT2  the seat pull goes UP (a positive distance), not into the body
##   LEG1   every leg drawn on the grid takes a shape on the first press
##   ROOF1  the upright Pointy above the box is a roof: one body, 600 mm tall, no errors
##   ROOF2  the roof sits on the box: the solid's lowest point is on the floor and the box top is at 300 mm
##   BOWL1  a closed Curvy profile on the middle line: the words say Spin it round
##   BOWL2  Spin it round makes one cup, 56 mm tall, hollow (a ray down the middle hits only the bottom)
##   BOWL3  a Curvy line that crosses the middle line: the words say Spin it round
## Shots: C:/Temp/claude/eseat/chair.png, house.png (3/4 view), bowl.png

const SHOT := "C:/Temp/claude/eseat"
const DIRT := "user://eseat_test"
var fails := 0
var m: Node
var log_lines: Array = []
var leg_dead := 0   # legs whose first press did not draw (a dead end found on the walk)


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


## a real right-drag: turns the view round (orbit), dx right, dy down
func orbit_drag(dx: float, dy: float) -> void:
	var a := Vector2(640, 360)
	var b := a + Vector2(dx, dy)
	await ev_move(a, false)
	await ev_mouse(a, true, MOUSE_BUTTON_RIGHT)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true, MOUSE_BUTTON_MASK_RIGHT)
	await ev_mouse(b, false, MOUSE_BUTTON_RIGHT)
	await idle(90)   # the orbit eases: a beginner's next press comes once the view has settled


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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


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


func height_mm() -> float:
	var bb: AABB = pu().res.get("aabb", AABB())
	return bb.size.y / Part.MM


## one line of the walk log: the press, the words it showed, the body count, the errors, the size
func note(step: String, press: String) -> void:
	await idle(3)
	var sl := ""
	for s in slider_rows():
		sl += " slider[%.1f..%.1f now %.1f]" % [s.min_value, s.max_value, s.value]
	var line := "%s | %s | words [%s] | bodies %d | errors %d | height %.0f mm%s" % [step, press, words(), nbodies(), errors_of(m.S.part), height_mm(), sl]
	print(line)
	log_lines.append(line)


func save_log() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	var f := FileAccess.open(SHOT + "/walk.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


func slider_rows() -> Array:
	var out := []
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			out.append(r["slider"])
	return out


## the Empty chip: the clean floor between things (a real click; logged if it cannot be reached)
func empty_part(why: String) -> void:
	var c := chip("easypart_chip_empty")
	if c == null or not c.is_visible_in_tree():
		await note("empty", "Empty chip NOT reachable (%s)" % why)
		return
	await click_ctl(c)
	await note("empty", "Empty chip (%s)" % why)


## Pull it up, then the slider to h cm (the default is 2 cm)
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	await note("pull", "Pull it up")
	for s in slider_rows():
		await drag_slider(s, h)
	await note("pull", "slider to %.1f" % h)


## a real click on a ViewCube face (quad i: 0 FRONT, 1 RIGHT, 2 TOP, 3 BACK, 4 LEFT, 5 BOTTOM)
func turn_cube(i: int) -> void:
	var cube: ViewCube = m.ui_cube
	var q := cube._quad(i)
	var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
	await cube_click(cen)
	await note("view", "ViewCube face %d click" % i)


## a real click on a ViewCube corner (a 3/4 view): 85 percent of the way from the cube middle to the corner d
func turn_corner(d: Vector3) -> void:
	var cube: ViewCube = m.ui_cube
	var mid := Vector2(cube.SIZE * 0.5, cube.SIZE * 0.5)
	var corner: Vector3 = cube._proj(d)
	var p := mid + (Vector2(corner.x, corner.y) - mid) * 0.85
	await cube_click(p)
	await note("view", "ViewCube corner %s click" % str(d))


func cube_click(p: Vector2) -> void:
	var cube: ViewCube = m.ui_cube
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	cube._gui_input(ev)
	await idle(60)


## one leg: a closed square 4 cm on the floor at (lx, lz) metres, drawn from the view, pulled up 40 cm
func leg(lx: float, lz: float) -> void:
	await click_ctl(ep().make_btns["draw"])
	var a := scr(Vector3(lx - 0.02, 0.0, lz - 0.02))
	var b := scr(Vector3(lx + 0.02, 0.0, lz + 0.02))
	log_lines.append("   press %s to %s over_ui %s" % [str(a), str(b), str(ep()._over_ui(a))])
	await drag_screen(a, b)
	await note("legs", "leg drawn at (%.2f, %.2f)" % [lx, lz])
	if not words().contains("Shape drawn"):
		log_lines.append("   DBG refused press %s over controls: %s" % [str(a), str(stopped_at(a))])
		# a dead end: the press did not draw, so a beginner turns the view and tries again
		leg_dead += 1
		await turn_corner(Vector3(-1.0, 1.0, 1.0))
		await click_ctl(ep().make_btns["draw"])
		a = scr(Vector3(lx - 0.02, 0.0, lz - 0.02))
		b = scr(Vector3(lx + 0.02, 0.0, lz + 0.02))
		log_lines.append("   retry press %s to %s over_ui %s" % [str(a), str(b), str(ep()._over_ui(a))])
		await drag_screen(a, b)
		await note("legs", "leg drawn again at (%.2f, %.2f) from the corner view" % [lx, lz])
	await click_ctl(ep().make_btns["pull"])
	await note("legs", "Pull it up (leg)")
	for s in slider_rows():
		await drag_slider(s, 40.0)
	await note("legs", "leg slider 40 cm")


## the heights (mm) where a ray straight down the middle (0.5 mm off the axis) meets the replayed mesh, sorted
func down_hits() -> Array:
	var mesh: ArrayMesh = pu().res.get("mesh")
	var out := []
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arr: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	var from := Vector3(0.5, 1000.0, 0.3)   # in MM, 0.5 mm off the axis, off the seam (a ray ON a triangle edge can miss). MM, not metres: Godot's
	                                        # ray_intersects_triangle drops a triangle whose determinant is under 1e-5, i.e. every mm-sized one in metres
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


func stopped_at(p: Vector2) -> Array:
	var out := []
	for c in root.find_children("*", "Control", true, false):
		var cc := c as Control
		if cc.is_visible_in_tree() and cc.mouse_filter == Control.MOUSE_FILTER_STOP and cc.get_global_rect().has_point(p):
			out.append("%s(%s)" % [cc.name, cc.get_class()])
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
	log_lines.append("start: start screen visible %s" % str(ss.visible))
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
	await empty_part("start of the walk")

	# ---------------------------------------------------------------- CHAIR
	await turn_cube(2)
	await click_ctl(ep().shape_btns["box"])
	await note("legs", "Box chip for the legs")
	for lp in [[-0.18, 0.18], [0.18, 0.18], [0.18, -0.18], [-0.18, -0.18]]:
		await leg(lp[0], lp[1])
	var legs_ok := leg_dead == 0
	await orbit_drag(0.0, 60.0)
	await note("view", "orbit drag (right, down 60 px)")
	await click_ctl(ep().shape_btns["box"])
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.2, 0.40, 0.2)), scr(Vector3(0.2, 0.40, -0.2)))  # a press on the leg top corner (a beginner's press)
	await note("seat", "seat drawn on the leg tops")
	log_lines.append("   seat sketch %s | body aabb %s" % [JSON.stringify(m.S.part["features"].back()), str(pu().res.get("aabb", AABB()))])
	var seat_ok := words().contains("Shape drawn")
	if not seat_ok:
		await click_ctl(ep().make_btns["draw"])
		await drag_screen(scr(Vector3(0.2, 0.40, -0.2)), scr(Vector3(-0.2, 0.40, 0.2)))
		await note("seat", "seat drawn on the leg tops (second try, from the other corner)")
		seat_ok = words().contains("Shape drawn")
	await click_ctl(ep().make_btns["pull"])
	await note("seat", "Pull it up (seat)")
	for s in slider_rows():
		await drag_slider(s, 4.0)
	await note("seat", "seat slider 4 cm")
	var seat_h := height_mm()
	var seat_dist := 0.0
	for f in m.S.part["features"]:
		if String(f["t"]) == "extrude":
			seat_dist = float(f.get("dist", 0.0))
	log_lines.append("   seat extrude dist after the pull: %.2f mm" % seat_dist)
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(0.1, 0.44, -0.1)), scr(Vector3(-0.15, 0.44, -0.15)))
	await note("back", "back drawn on the seat top (near the back edge)")
	log_lines.append("   back sketch %s" % JSON.stringify(m.S.part["features"].back()))
	await click_ctl(ep().make_btns["pull"])
	await note("back", "Pull it up (back)")
	for s in slider_rows():
		await drag_slider(s, 35.0)
	await note("back", "back slider 35 cm")
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await shot("chair")
	var chair_bodies := nbodies()
	var chair_errs := errors_of(m.S.part)
	var chair_h := height_mm()
	ok(legs_ok, "LEG1 every leg drawn on the grid takes a shape on the first press from the top view: %d leg(s) refused" % leg_dead)
	ok(seat_ok, "SEAT0 the seat drawn on the leg tops after the orbit takes a shape (words [%s])" % words())
	ok(absf(seat_h - 440.0) < 5.0, "SEAT1 a seat pulled 4 cm up from the leg tops stands on them: 440 mm after the seat (400 legs + 40): height %.0f mm" % seat_h)
	ok(seat_dist > 0.0, "SEAT2 the seat pull goes UP from the leg tops (positive distance), not into the body: dist %.1f mm" % seat_dist)
	ok(chair_bodies == 1 and chair_errs == 0 and absf(chair_h - 790.0) < 10.0, "CHAIR1 the chair is one body, 790 mm tall (legs 400, seat 40, back 350): bodies %d, errors %d, height %.0f mm" % [chair_bodies, chair_errs, chair_h])

	# ---------------------------------------------------------------- ROOF
	await empty_part("between chair and house")
	await turn_cube(2)
	await click_ctl(ep().shape_btns["box"])
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.2, 0.0, -0.15)), scr(Vector3(0.2, 0.0, 0.15)))
	await note("house", "box drawn on the floor")
	await pull(30.0)
	await turn_corner(Vector3(-1.0, 1.0, 1.0))   # from the top view the FRONT face is a sliver on the cube: a 3/4 view first
	await turn_cube(0)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["pointy"])
	await note("house", "Draw shape, Pointy")
	# the roof: a Pointy UPRIGHT (side-on), its base on the box top (30 cm), its point up in the air
	await drag_screen(scr(Vector3(-0.2, 0.30, 0.0)), scr(Vector3(0.2, 0.60, 0.0)))   # on the upright plane through the middle (z = 0)
	await note("house", "Pointy drawn from the box top corner up (side-on, FRONT)")
	log_lines.append("   roof sketch %s" % JSON.stringify(m.S.part["features"].back()))
	var roof_ok := words().contains("Shape drawn")
	await click_ctl(ep().make_btns["pull"])
	await note("house", "Pull it up (roof)")
	for s in slider_rows():
		await drag_slider(s, 30.0)
	await note("house", "roof slider 30 cm")
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await shot("house")
	var roof_h := height_mm()
	var roof_bodies := nbodies()
	var roof_errs := errors_of(m.S.part)
	var roof_low := float(pu().res.get("aabb", AABB()).position.y) / Part.MM
	ok(roof_ok and roof_bodies == 1 and roof_errs == 0 and absf(roof_h - 600.0) < 10.0, "ROOF1 the upright Pointy above the box top is a roof: one body, 600 mm tall (box 300 + roof 300), no errors: drawn %s, bodies %d, errors %d, height %.0f mm, words [%s]" % [str(roof_ok), roof_bodies, roof_errs, roof_h, words()])
	ok(roof_bodies == 1 and absf(roof_low) < 1.0, "ROOF2 the roof sits on the box: the solid stands on the floor (lowest point %.1f mm) and is joined (bodies %d)" % [roof_low, roof_bodies])

	# ---------------------------------------------------------------- BOWL
	await empty_part("between house and bowl")
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await turn_cube(0)
	await click_ctl(ep().make_btns["curve"])
	# a cup: the wall closed on the middle line (ebowl's profile), 56 mm tall, hollow inside
	var bowl := [[0.0, 0.0], [18.0, 0.5], [32.0, 6.0], [40.0, 20.0], [40.0, 40.0], [36.0, 56.0], [33.0, 56.0], [34.0, 40.0], [33.0, 20.0], [26.0, 8.0], [14.0, 4.0], [0.0, 4.0], [0.0, 0.0]]
	var bp := []
	for p in bowl:
		bp.append(scr(Vector3(p[0] * 0.001, p[1] * 0.001, 0.0)))
	await drag_path(bp)
	await note("bowl", "Curvy profile of a bowl (closed on the middle line)")
	var bowl_words := words()
	ok(bowl_words.contains("Spin it round"), "BOWL1 a closed Curvy profile on the middle line: the words say Spin it round (words [%s])" % bowl_words)
	await click_ctl(ep().make_btns["spin"])
	await note("bowl", "Spin it round")
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await shot("bowl")
	var bowl_bodies := nbodies()
	var bowl_errs := errors_of(m.S.part)
	var bowl_h := height_mm()
	var hits := down_hits()
	var top := 0.0 if hits.is_empty() else float(hits.back())
	ok(bowl_bodies == 1 and bowl_errs == 0 and absf(bowl_h - 56.0) < 4.0 and hits.size() >= 1 and top < 10.0, "BOWL2 the cup is one body, 56 mm tall and hollow (a ray down the middle hits only the bottom): bodies %d, errors %d, height %.0f mm, hits %s" % [bowl_bodies, bowl_errs, bowl_h, str(hits)])
	# a Curvy line that CROSSES the middle line (an open loop from x = -8 mm to x = 40 mm)
	await empty_part("bowl crossing probe")
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await turn_cube(0)
	await click_ctl(ep().make_btns["curve"])
	var cross := [[-8.0, 5.0], [10.0, 12.0], [25.0, 25.0], [40.0, 45.0]]
	var cp := []
	for p in cross:
		cp.append(scr(Vector3(p[0] * 0.001, p[1] * 0.001, 0.0)))
	await drag_path(cp)
	await note("bowl", "Curvy line crossing the middle line (open)")
	ok(words().contains("Spin it round"), "BOWL3 a Curvy line that crosses the middle line: the words say Spin it round (words [%s])" % words())

	save_log()
	print("eseat: %d fail" % fails)
	quit(1 if fails > 0 else 0)
