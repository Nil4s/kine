extends SceneTree
## godot --path . --position 4000,4000 -s tests/etable_test.gd     (ETABLE: a top drawn from the TOP view on the leg tops stands ON the legs; scripts/easy_part.gd; needs the CAD DLL and a window)
## A beginner from the REAL start screen (Home, the building card, Part, Easy). Real clicks and drags at 1280 x 720 only.
##   TABLE  one Box leg on the floor, Pulled 40 cm, Repeat it > Corners, ViewCube TOP, a Box drawn from a press ON a leg top
##          (the top of the leg at 400 mm), Pulled 4 cm: the top stands on the legs
## Bars (ETABLE2-4 FAILED on the old code: the top was pulled INTO the legs, the height stayed 400 mm):
##   ETABLE1  one body, no errors, one leg and its repeats
##   ETABLE2  the top drawn from the leg-top press takes a shape on the first press
##   ETABLE3  the top's pull goes UP (a positive distance), not into the legs
##   ETABLE4  the top stands on the four legs: 440 mm tall

const SHOT := "C:/Temp/claude/etable"
const DIRT := "user://etable_test"
var fails := 0
var m: Node
var log_lines: Array = []
var top_stuck := false
var shade_apart := false
var lamp_h := 0.0
var lamp_n := 0
var blade_first := true
var use_stage := false
var refused := []
var dead := []   # every dead end: "press | words | what the beginner did next"


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


## a named control (a real click on it); logged as a dead end when it cannot be reached
func click_named(nm: String, why: String) -> bool:
	var c := root.find_child(nm, true, false) as Control
	if c == null or not c.is_visible_in_tree():
		dead.append("%s | %s | control %s NOT reachable" % [why, words(), nm])
		await note("dead", "%s NOT reachable (%s)" % [nm, why])
		return false
	await click_ctl(c)
	return true


func make(key: String) -> void:
	await click_ctl(ep().make_btns[key])
	await note("make", "%s chip" % key)


func shape(key: String) -> void:
	await click_ctl(ep().shape_btns[key])


## a drawn shape: the press is logged, and a refused press is a dead end (the words it gave)
func draw(a: Vector3, b: Vector3, what: String) -> bool:
	await click_ctl(ep().make_btns["draw"])
	var pa := scr(a)
	var pb := scr(b)
	await drag_screen(pa, pb)
	await note("draw", what)
	var got := words().contains("Shape drawn")
	if not got:
		refused.append(what)
		dead.append("%s | words [%s] | press %s to %s" % [what, words(), str(pa), str(pb)])
	return got


func pull_cm(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	await note("pull", "Pull it up")
	for s in slider_rows():
		await drag_slider(s, h)
	await note("pull", "slider %.1f cm" % h)


func feats(t: String) -> int:
	var n := 0
	for f in m.S.part["features"]:
		if String(f["t"]) == t:
			n += 1
	return n


func empty_start(why: String) -> void:
	await empty_part(why)


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

	# ---------------------------------------------------------------- TABLE
	await empty_part("start of the table")
	await turn_cube(2)
	shape("box")
	var leg_ok := await draw(Vector3(-0.20, 0, 0.18), Vector3(-0.16, 0, 0.22), "table: first leg drawn on the floor (Box)")
	await pull_cm(40.0)
	await make("repeat")
	await click_named("easypart_rep_corners", "table: Repeat it > Corners")
	await note("table", "Corners chip pressed")
	var legs_n := feats("pattern")
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await turn_cube(2)
	# the top: a press on the leg top (the leg is x -0.20..-0.16, z 0.18..0.22, 400 mm tall), dragged across the table
	var top_ok := await draw(Vector3(-0.18, 0.40, 0.20), Vector3(0.18, 0.40, -0.20), "table: top drawn from the top view, pressed on the leg top")
	var top_dist := 0.0
	for f in m.S.part["features"]:
		if String(f["t"]) == "extrude":
			top_dist = float(f.get("dist", 0.0))
	await pull_cm(4.0)
	for f in m.S.part["features"]:
		if String(f["t"]) == "extrude":
			top_dist = float(f.get("dist", 0.0))
	var t_bodies := nbodies()
	var t_errs := errors_of(m.S.part)
	var t_h := height_mm()
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await shot("table")
	ok(leg_ok and legs_n >= 1 and t_bodies == 1 and t_errs == 0, "ETABLE1 a table: one leg drawn, Repeat it > Corners, a top drawn on the leg top: one body, no errors (bodies %d, errors %d, repeats %d)" % [t_bodies, t_errs, legs_n])
	ok(top_ok, "ETABLE2 a top drawn from the top view, pressed on a leg top, takes a shape on the first press (words [%s])" % words())
	ok(top_dist > 0.0, "ETABLE3 the top pull goes UP from the leg tops (positive distance), not into the legs: dist %.1f mm" % top_dist)
	ok(absf(t_h - 440.0) < 10.0, "ETABLE4 the top stands on the four legs: 440 mm tall (400 legs + 40 top; height %.0f mm)" % t_h)
	save_log()
	print("etable: %d fail" % fails)
	quit(1 if fails > 0 else 0)
