extends SceneTree
## godot --path . --position 4000,4000 -s tests/eempty_test.gd     (EEMPTY: Easy Part's "Empty" chip; scripts/easy_part.gd; needs the CAD DLL and a window)
## Easy Part opens on a sword (part_ui.open_easy). A beginner building their own thing had no way to a clean floor: every walk test reset the part in code.
## Bars (1a FAILED on the old code: no Empty chip):
##   1 EMPTY  Easy Part opened from the start screen shows the sword; a click on Empty leaves a part with no steps and no body, one undo step, the chip lit
##   2 DRAW   then Draw shape + a floor drag + Pull it up is one body (the sword is gone)
##   3 UNDO   Undo back to the empty part, again back to the sword
const SHOT := "C:/Temp/claude/eempty"
const DIRT := "user://eempty_test"

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
	# Nick 2026-10-28: free 3D building, no forced house. The BUILDING card now opens a blank part on Part; this bar opens the
	# Part itself from BUILD, as it did before, so it starts from the same state (Part off, no part) it always did
	pu().set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.S.part = {}
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(30)
	var n0: int = (m.S.part.get("features", []) as Array).size()
	ok(n0 > 0 and int(pu().res.get("bodies", 0)) >= 1, "0 OPEN Easy Part opens on a template (%d steps)" % n0)
	var chip = ep().get("empty_chip")
	ok(chip != null and (chip as Button).is_visible_in_tree(), "1a EMPTY the Empty chip is shown")
	if chip == null:
		print("eempty: %d fail" % fails)
		quit(1)
		return
	var u0: int = m.undo.size()
	await click_ctl(chip)
	await idle(10)
	ok((m.S.part.get("features", []) as Array).is_empty() and int(pu().res.get("bodies", 0)) == 0, "1b EMPTY no steps, no body (%d steps)" % (m.S.part.get("features", []) as Array).size())
	ok(m.undo.size() == u0 + 1, "1c EMPTY one undo step (%d -> %d)" % [u0, m.undo.size()])
	ok((chip as Button).button_pressed and ep().hint_l.text.begins_with("Empty"), "1d EMPTY the chip is lit, the words say what to do [%s]" % ep().hint_l.text)
	await idle(60)
	await draw_floor(Vector3(-0.03, 0.0, -0.03), Vector3(0.03, 0.0, 0.03))
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	var bb := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and bb.size.x < 80.0 and bb.size.y < 30.0, "2 DRAW one body, only the new box (%.0f x %.0f x %.0f mm)" % [bb.size.x, bb.size.y, bb.size.z])
	ok(not (chip as Button).button_pressed, "2b DRAW the Empty chip goes dark once there is a step")
	await shot("shot")
	for i in 2:
		m._undo()
		await idle(6)
	ok((m.S.part.get("features", []) as Array).is_empty(), "3a UNDO two undos: back to the empty part")
	m._undo()
	await idle(6)
	ok((m.S.part.get("features", []) as Array).size() == n0, "3b UNDO one more: back to the template (%d steps)" % (m.S.part.get("features", []) as Array).size())
	print("eempty: %d fail" % fails)
	quit(1 if fails > 0 else 0)
