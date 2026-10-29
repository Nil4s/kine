extends SceneTree
## FLAMP4 (Nick 2026-10-28: free 3D building, like Fusion 360; the BUILDING card opens a blank part): a beginner from the REAL
## start screen builds a floor lamp with real clicks and drags at 1280 x 720, never having read a manual.
##   BASE   ViewCube TOP: Draw shape (round) on the floor, centre to edge 60 mm, Pull it up 3 cm = the heavy round base
##   POLE   the round drawn on the base top face (centre to edge 12 mm), Pull it up 40 cm = the tall pole, joined to the base
##   SHADE  ViewCube FRONT: a closed Curvy shade profile sitting on the pole top, Spin it round = the cone shade
##   TILT   the shade tilted 20 degrees: the Tilt it chip under the newest solid (per piece: the spun shade leans about its middle
##          before it joins the lamp's one body). First written as a dead end (no Tilt step, F4 red); the fix turned F4 into this bar.
## Bars (F0 to F3 and F5 passed at the first commit; F4 FAILED = dead end, no Tilt step; F4 now asserts the fixed Tilt it):
##   F0 the BUILDING card, one click: page BUILD, a blank Easy part, no chooser
##   F1 the base: one body, a real volume, 115..125 mm across, top at 30 mm (+-3 mm)
##   F2 the pole stands on the base: still one body, top at 430 mm (+-8 mm)
##   F3 the shade: spun round, joined to the pole: one body, no errors, top at 490 mm (+-8 mm)
##   F4 Tilt it: Easy Part has a Tilt step that tilts the shade 20 degrees
##   F5 no failed step and no jargon on the status words
## shots: C:/Temp/claude/flamp4/base.png, pole.png, shade.png, tilt.png, lamp.png
const SHOT := "C:/Temp/claude/flamp4"
const DIRT := "user://flamp4_test"
var fails := 0
var m: Node
var log_lines: Array = []


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


func errors_n() -> int:
	return Part.replay(m.S.part)["errors"].size()


func aabb_mm() -> AABB:
	var bb: AABB = pu().res.get("aabb", AABB())
	return AABB(bb.position / Part.MM, bb.size / Part.MM)


func vol_mm3() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func slider_rows() -> Array:
	var out := []
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			out.append(r["slider"])
	return out


func note(step: String, press: String) -> void:
	await idle(3)
	var bb := aabb_mm()
	var line := "%s | %s | words [%s] | bodies %d | errors %d | y %.0f..%.0f mm | x %.0f..%.0f mm" % [step, press, words(), nbodies(), errors_n(), bb.position.y, bb.end.y, bb.position.x, bb.end.x]
	print(line)
	log_lines.append(line)


func save_log() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	var f := FileAccess.open(SHOT + "/lamp.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()


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
	await click_ctl(ss._cards["building"])   # a beginner clicks the card itself
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	if not pu().easy:
		await click_ctl(pu().easy_open_btn)   # the Easy button the words name, if the card did not open it
		await idle(10)
	await shot("open")
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and pu().on and not chooser_open,
		"F0 BUILDING card, one click -> a blank Easy part on page BUILD, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await note("start", "BUILDING card")

	# BASE: a round on the floor (top view), centre to edge 60 mm, pulled up 3 cm
	await turn_cube(2)
	await idle(120)   # the view eases to the top first
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	var c0: Vector2 = m.cam.unproject_position(Vector3(0.0, 0.0, 0.0))
	var e0: Vector2 = m.cam.unproject_position(Vector3(0.06, 0.0, 0.0))
	await drag_path([c0, e0])
	await note("base", "round drawn on the floor (60 mm)")
	await click_ctl(ep().make_btns["draw"])   # Draw shape off, as the words ask
	await click_ctl(ep().make_btns["pull"])
	for s in slider_rows():
		await drag_slider(s, 3.0)
	await note("base", "Pull it up 3 cm")
	await shot("base")
	var bb1 := aabb_mm()
	ok(nbodies() == 1 and vol_mm3() > 1000.0 and bb1.size.x > 115.0 and bb1.size.x < 125.0 and absf(bb1.end.y - 30.0) < 3.0,
		"F1 the base: one body, volume %.0f mm3, %.0f mm across, top %.1f mm" % [vol_mm3(), bb1.size.x, bb1.end.y])

	# POLE: a round on the base top face (3/4 view), centre to edge 12 mm, pulled up 40 cm
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await wheel_out(4)
	var top_y: float = bb1.end.y * 0.001
	var pc: Vector2 = m.cam.unproject_position(Vector3(0.0, top_y, 0.0))
	var pe: Vector2 = m.cam.unproject_position(Vector3(0.012, top_y, 0.0))
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_path([pc, pe])
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().make_btns["pull"])
	for s in slider_rows():
		await drag_slider(s, 40.0)
	await note("pole", "Pull it up 40 cm (pole)")
	await shot("pole")
	var bb2 := aabb_mm()
	ok(nbodies() == 1 and errors_n() == 0 and absf(bb2.end.y - 430.0) < 8.0,
		"F2 the pole stands on the base: one body, top %.1f mm (want 430)" % bb2.end.y)

	# SHADE: side-on (front) closed Curvy profile on the middle line, its foot on the pole top, then Spin it round
	await turn_cube(0)
	await idle(120)   # the view eases to the front first
	await wheel_out(6)
	await click_ctl(ep().make_btns["curve"])
	var shade := [[0.0, 490.0], [14.0, 488.0], [32.0, 462.0], [40.0, 440.0], [24.0, 427.0], [0.0, 427.0], [0.0, 490.0]]
	var sp := []
	for p in shade:
		sp.append(m.cam.unproject_position(Vector3(p[0] * 0.001, p[1] * 0.001, 0.0)))
	await drag_path(sp)
	await note("shade", "Curvy shade drawn on the pole top")
	await click_ctl(ep().make_btns["spin"])
	await note("shade", "Spin it round")
	await turn_cube(0)
	await shot("shade")
	var bb3 := aabb_mm()
	ok(nbodies() == 1 and errors_n() == 0 and absf(bb3.end.y - 490.0) < 8.0,
		"F3 the shade spun round, joined to the pole: one body, errors %d, top %.1f mm (want 490)" % [errors_n(), bb3.end.y])

	# TILT: the beginner looks for a way to tilt the shade 20 degrees (Easy Part: the Tilt it chip under the newest solid)
	var has_tilt: bool = ep().tilt_btn != null and ep().tilt_btn.is_visible_in_tree()
	if has_tilt:
		await click_ctl(ep().tilt_btn)
	await note("tilt", "Tilt it 20 degrees")
	await shot("tilt")
	var last: Dictionary = m.S.part["features"][-1]
	var tilted: bool = String(last.get("t", "")) == "revolve" and absf(float(last.get("tilt", 0.0)) - 20.0) < 0.001
	ok(has_tilt and tilted and errors_n() == 0 and nbodies() == 1,
		"F4 Tilt it: the Tilt it chip tilts the shade 20 degrees (chip shown: %s, shade tilt %s, one body, errors %d)" % [str(has_tilt), str(last.get("tilt", 0.0)), errors_n()])
	var jargon := []
	for w in ["sketch", "extrude", "revolve", "loft", "boolean", "feature", "body"]:
		if words().to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty() and errors_n() == 0, "F5 no failed step and no jargon on the words %s: [%s]" % [jargon, words()])
	await turn_corner(Vector3(-1.0, 1.0, 1.0))
	await shot("lamp")
	save_log()
	print("flamp4: %d fail" % fails)
	quit(1 if fails > 0 else 0)
