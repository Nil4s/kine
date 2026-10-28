extends SceneTree
## godot --path . --position 4000,4000 -s tests/ehelp_test.gd     (EHELP: Easy Part first steps say what to press; scripts/easy_part.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280x720 from the start screen. Empty, then Draw shape + a floor drag + Pull it up = the first solid (3 presses after Empty).
## Bars (2b and 3 FAILED on the old code, run once before: "Pulled up 2.0 cm: use the slider to change it" and "Mirrored across the middle line" name no next button. Bar 1 passed on the old code too: the Empty line was already one line):
##   1 EMPTY  the words after Empty are one line and name the first press (Draw shape, then drag)
##   2 PULL   the words after Pull it up name the next button (Cut a hole, Round the edges, Mirror that, ...)
##   3 MIRROR the words after Mirror that name the next button (Repeat it, Cut a hole, Stick together, ...)
##   4 COUNT  the presses from Empty to the first solid are printed (no bar: a number for the report)

## Easy Part opens on a sword (part_ui.open_easy). A beginner building their own thing had no way to a clean floor: every walk test reset the part in code.
## Bars (1a FAILED on the old code: no Empty chip):
##   1 EMPTY  Easy Part opened from the start screen shows the sword; a click on Empty leaves a part with no steps and no body, one undo step, the chip lit
##   2 DRAW   then Draw shape + a floor drag + Pull it up is one body (the sword is gone)
##   3 UNDO   Undo back to the empty part, again back to the sword
const SHOT := "C:/Temp/claude/ehelp"
const DIRT := "user://ehelp_test"

var fails := 0
var presses := 0   # real presses (a click or a drag) counted from the Empty chip
const NEXT_AFTER_SOLID := ["Cut a hole", "Round the edges", "Mirror that", "Spin it round", "Repeat it", "Draw shape", "Blend two shapes", "Cut in two", "Colour", "Stick together"]
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



func named_next(said: String) -> bool:
	for k in NEXT_AFTER_SOLID:
		if said.contains(k):
			return true
	return false


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
	ok(chip != null and (chip as Button).is_visible_in_tree(), "0 EMPTY the Empty chip is shown")
	if chip == null:
		print("ehelp: %d fail" % fails)
		quit(1)
		return
	await click_ctl(chip)
	presses = 0   # counted from here: Draw shape, the drag, Pull it up
	await idle(10)
	var hl: Label = ep().hint_l
	ok(hl.get_line_count() == 1 and hl.text.contains("Draw shape") and hl.text.contains("drag"),
		"1 EMPTY one line that names the first press [%d lines: %s]" % [hl.get_line_count(), hl.text])
	await idle(60)
	await draw_floor(Vector3(-0.03, 0.0, -0.03), Vector3(0.03, 0.0, 0.03))
	presses += 2   # draw_floor: the Draw shape click + the drag
	await click_ctl(ep().make_btns["pull"])
	presses += 1
	await idle(10)
	var bb := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and bb.size.x < 80.0 and bb.size.y < 30.0, "2 SOLID one body after Empty, Draw shape, drag, Pull it up (%.0f x %.0f x %.0f mm)" % [bb.size.x, bb.size.y, bb.size.z])
	print("ehelp COUNT presses from Empty to the first solid: %d" % presses)
	var said: String = ep().hint_l.text
	ok(named_next(said), "2b PULL the words after Pull it up name the next button [%s]" % said)
	await shot("pull")
	await click_ctl(ep().make_btns["mirror"])
	await idle(10)
	said = ep().hint_l.text
	ok(named_next(said), "3 MIRROR the words after Mirror that name the next button [%s]" % said)
	await shot("mirror")
	print("ehelp: %d fail" % fails)
	quit(1 if fails > 0 else 0)
