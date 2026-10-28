extends SceneTree
## godot --path . --position 4000,4000 -s tests/erepeat_test.gd     (EREPEAT: Easy Part's Repeat it has a Corners chip: the newest piece goes to the four corners of the body it touches; scripts/easy_part.gd + scripts/build/part.gd; needs the CAD DLL and a window)
## A chair's legs by real clicks at 1280 x 720 from the start screen, the Empty chip: a seat, one leg drawn under it, Repeat it, Corners.
## Bars (1a and later FAILED on the old code: no Corners chip, so the press had nothing to click):
##   1 SEAT    Empty leaves no steps; a 100 mm square on the floor pulled up 20 mm: one body
##   2 LEG     a leg drawn on the underside of the seat, pulled down 150 mm: one body, box min y -150 mm
##   3 PRESSES Repeat it then Corners: two presses (4 or fewer), the Corners press is ONE undo step
##   4 CORNERS four legs, one body, no failed step; the box is the seat 100 x 100 mm, legs down to -150 mm; the volume is the seat + 4 legs (1 pct)
##   5 UNDO    undo the Corners step gives the one leg back (two bodies), no failed step
## Shot: C:/Temp/claude/erepeat/chair.png, a 3/4 view of the finished chair (LOOK at it: a chair or a stool)
const SHOT := "C:/Temp/claude/erepeat"
const DIRT := "user://erepeat_test"

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


func last_of(rec: Dictionary, t: String) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			out = f
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
	await click_ctl(ep().empty_chip)
	await idle(4)
	ok(Part.count_of(m.S.part, "sketch") == 0 and Part.count_of(m.S.part, "extrude") == 0 and int(pu().res.get("bodies", 0)) == 0, "0 EMPTY the Empty chip leaves no steps and no body")
	m.pitch = -25.0
	m.yaw = 30.0
	m._cam()
	await idle(40)

	# 1 SEAT: a 100 mm square on the floor, pulled up 20 mm
	await draw_floor(Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	var vseat := vol()
	var bs := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bs.size.x - 100.0) < 0.5 and absf(bs.size.z - 100.0) < 0.5 and absf(bs.end.y - 20.0) < 0.5,
		"1 SEAT one body, 100 x 100 mm, 20 mm up: %s" % bs)

	# 2 LEG: a leg on the underside of the seat (the camera from below), pulled down 150 mm
	m.pitch = 35.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(-0.045, 0.0, -0.045)), scr(Vector3(-0.03, 0.0, -0.03)))
	await pull(15.0)
	var bl := bbox()
	var vleg := vol() - vseat
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bl.position.y + 150.0) < 0.5 and vleg > 0.0,
		"2 LEG one leg under the seat, one body, box min y %.1f (want -150), leg volume %.0f mm3" % [bl.position.y, vleg])
	if not ep().rep_btns.has("corners"):
		ok(false, "4 CORNERS the Repeat it row has no Corners chip")
		print("erepeat: %d fail" % (fails + 1))
		quit(1)
		return

	# 3 PRESSES: Repeat it, then Corners
	var p0 := 0
	var ub1: int = m.undo.size()
	await click_ctl(ep().make_btns["repeat"])
	p0 += 1
	var ub2: int = m.undo.size()
	await click_ctl(ep().rep_btns["corners"])
	p0 += 1
	var ub3: int = m.undo.size()
	ok(p0 <= 4 and ub3 == ub2 + 1 and ub2 == ub1 + 1, "3 PRESSES Repeat it, then Corners: %d presses, the Corners press is ONE undo step (%d -> %d)" % [p0, ub2, ub3])

	# 4 CORNERS: four legs at the corners, one body, no failed step
	var pt := last_of(m.S.part, "pattern")
	var r: Dictionary = pu().res
	var b4 := bbox()
	var v4 := vol()
	ok(String(pt.get("kind", "")) == "corners" and (r.get("errors", {}) as Dictionary).is_empty() and int(r.get("bodies", 0)) == 1,
		"4a CORNERS four legs in one body, no failed step: kind %s, bodies %d, errors %s" % [String(pt.get("kind", "")), int(r.get("bodies", 0)), str(r.get("errors", {}))])
	ok(absf(b4.size.x - 100.0) < 0.5 and absf(b4.size.z - 100.0) < 0.5 and absf(b4.position.y + 150.0) < 0.5,
		"4b CORNERS box is the seat 100 x 100 mm and the legs go down to -150: %s" % b4)
	var want := vseat + 4.0 * vleg
	ok(absf(v4 - want) < 0.01 * want, "4c CORNERS volume is the seat + 4 legs: %.0f mm3 (want %.0f)" % [v4, want])
	m.target = Vector3(0.0, -0.08, 0.0)   # the shot: the chair framed in the clear view, a 3/4 view from a little below
	m.dist = 0.42
	m.pitch = 12.0
	m.yaw = 35.0
	m._cam()
	await idle(60)
	await shot("chair")

	# 5 UNDO: the Corners step goes back to one leg
	m._undo()
	await idle(3)
	var r5: Dictionary = pu().res
	ok(String(last_of(m.S.part, "pattern").get("kind", "")) != "corners" and int(r5.get("bodies", 0)) >= 1 and m.undo.size() == ub2,
		"5 UNDO the Corners step is taken back (kind now %s)" % String(last_of(m.S.part, "pattern").get("kind", "")))

	print("erepeat: %d fail" % fails)
	quit(1 if fails > 0 else 0)
