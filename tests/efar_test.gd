extends SceneTree
## godot --path . --position 4000,4000 -s tests/efar_test.gd     (EFAR: Easy Part's far-floor presses and the MAKE row; scripts/easy_part.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 only.
## Bars:
##   1 WORDS  a drag that starts on the words pill (the far floor shows under it) with Draw shape armed draws the box (FAILED on the old code: _over_ui counted the words pill, the press did nothing)
##   2 CURVE  the same press with Curvy line armed draws a curve
##   3 WANDER a press that starts on Mirror, the pointer goes off the button and back, released on it: Mirror does NOT run (FAILED on the old code: the button fired on release)
##   4 TAP    a plain click on Mirror with a solid there still mirrors: "Mirrored across the middle line"
##   5 GRID   a drag from the grid that releases on Mirror does not mirror
## Shot: C:/Temp/claude/efar/far_leg.png
const SHOT := "C:/Temp/claude/efar"
const DIRT := "user://efar_test"

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



func solid() -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	await idle(3)
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(Vector2(500, 420), Vector2(600, 500))
	await click_ctl(ep().make_btns["pull"])
	await idle(3)


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
	var e = ep()

	# 1 WORDS: a press on the words pill (through its middle) with Draw shape armed draws a box on the floor
	await fresh(-30.0)
	await click_ctl(e.make_btns["draw"])
	var hr: Rect2 = (e.hint as Control).get_global_rect()
	var a := Vector2(hr.position.x + 60.0, hr.get_center().y)
	ok(hr.has_point(a) and bool(e.hint.visible), "1a WORDS the press point is on the words pill (%s in %s)" % [str(a), str(hr)])
	var n0: int = Part.count_of(m.S.part, "sketch")
	await drag_screen(a, a + Vector2(40, 30))
	await idle(2)
	ok(Part.count_of(m.S.part, "sketch") == n0 + 1, "1b WORDS a box drawn from the words pill's press: sketches %d -> %d, words \"%s\"" % [n0, Part.count_of(m.S.part, "sketch"), e.msg])
	await shot("far_leg")

	# 2 CURVE: the same press with Curvy line
	await fresh(-30.0)
	await click_ctl(e.make_btns["curve"])
	hr = (e.hint as Control).get_global_rect()
	a = Vector2(hr.position.x + 60.0, hr.get_center().y)
	n0 = Part.count_of(m.S.part, "sketch")
	await drag_screen(a, a + Vector2(40, 30))
	await idle(2)
	ok(Part.count_of(m.S.part, "sketch") == n0 + 1, "2 CURVE a curve drawn from the words pill's press: sketches %d -> %d" % [n0, Part.count_of(m.S.part, "sketch")])

	# 3 WANDER: a press on Mirror, the pointer goes off the button and back, released on Mirror: no mirror
	await solid()
	var mc: Vector2 = (e.make_btns["mirror"] as Button).get_global_rect().get_center()
	var f0: int = (m.S.part["features"] as Array).size()
	await ev_move(mc, false)
	await ev_mouse(mc, true)
	await ev_move(mc + Vector2(0, 200))
	await ev_move(mc + Vector2(60, 200))
	await ev_move(mc)
	await ev_mouse(mc, false)
	await idle(3)
	ok((m.S.part["features"] as Array).size() == f0 and String(e.msg).find("Mirrored") < 0, "3 WANDER a press that went off Mirror and back is no click: features %d -> %d, words \"%s\"" % [f0, (m.S.part["features"] as Array).size(), e.msg])

	# 4 TAP: a plain click on Mirror mirrors the solid
	await solid()
	f0 = (m.S.part["features"] as Array).size()
	await click_ctl(e.make_btns["mirror"])
	ok((m.S.part["features"] as Array).size() == f0 + 1 and String(e.msg).begins_with("Mirrored"), "4 TAP a click on Mirror mirrors: features %d -> %d, words \"%s\"" % [f0, (m.S.part["features"] as Array).size(), e.msg])

	# 5 GRID: a drag from the grid that releases on Mirror is no click
	await solid()
	f0 = (m.S.part["features"] as Array).size()
	await drag_screen(Vector2(700, 440), mc)
	await idle(3)
	ok((m.S.part["features"] as Array).size() == f0 and String(e.msg).find("Mirrored") < 0, "5 GRID a grid drag that ends on Mirror does not mirror: features %d -> %d" % [f0, (m.S.part["features"] as Array).size()])

	print("efar: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
