extends SceneTree
## p070springswit (Friday plan item 70: Springs (compression) with turns + wire slider). A beginner from the BUILDING card: one click on
## the Spring chip in the Easy Part chips row, then real mouse drags on the Turns and Wire sliders, then Ctrl+Z.
## A compression spring: a coil of N turns (3..12) of wire (1..4 mm), mean coil radius 10 mm, coils 0.8 x wire apart (one solid).
## Measured from the BUILT mesh (mm), the kernel body count and the undo stack, never from the code's own variables.
## Bars (all FAIL on the old code: it has no Spring chip, so nothing below can be built):
##   0 the Spring chip is on the Easy Part chips row
##   1 one click on Spring: ONE undo step, ONE solid, 6 turns of 2 mm wire: height 10.0 mm (+- 0.2), width 22.0 mm (+- 0.2)
##   2 Turns slider is 3..12; a real drag to 10 turns: ONE undo step, height 16.4 mm (+- 0.2) = 9 x 1.6 + 2
##   3 Wire slider is 1..4; a real drag to 4 mm: ONE undo step, width 24.0 mm (+- 0.2) = 2 x (10 + 2), height 32.8 mm (+- 0.2) = 9 x 3.2 + 4
##   4 Ctrl+Z after the wire drag: the built spring is back to 2 mm wire (width 22.0 mm +- 0.2) and 10 turns (height 16.4 mm +- 0.2)
##   5 the words: no key name in the slider words, the hint or the status line
## shots: C:/Temp/claude/p070springswit/
const SHOT := "C:/Temp/claude/p070springswit"
const DIRT := "user://p070springswit_test"

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


func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a slider knob position (screen px) for a value: the track runs between the centres of the two end grabbers
func knob_x(s: HSlider, v: float) -> Vector2:
	var r := s.get_global_rect()
	var t := (v - s.min_value) / maxf(s.max_value - s.min_value, 1e-6)
	return Vector2(r.position.x + 12.0 + t * (r.size.x - 24.0), r.get_center().y)


func slide_to(s: HSlider, v: float) -> void:
	var a := knob_x(s, s.value)
	await drag_screen(a, knob_x(s, v))


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	root.push_input(e, true)
	await idle(3)
	var u := InputEventKey.new()
	u.keycode = KEY_Z
	u.physical_keycode = KEY_Z
	u.key_label = KEY_Z
	u.ctrl_pressed = true
	u.pressed = false
	root.push_input(u, true)
	await idle(10)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func row_of(ep, key: String) -> Dictionary:
	for r in ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


## the built size (mm) from the mesh: the height along Y (the spring stands on the floor), the width = 2 x the largest distance from the Y axis
func built() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var ymin := 1e9
	var ymax := -1e9
	var rmax := 0.0
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
			rmax = maxf(rmax, Vector2(p.x, p.z).length())
	if faces.is_empty():
		return {"h": 0.0, "w": 0.0, "bodies": 0}
	return {"h": ymax - ymin, "w": 2.0 * rmax, "bodies": int(pu().res.get("bodies", 0)), "lo": ymin}


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

	# 0 the BUILDING card, one click: an empty Easy Part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var ep = pu().ep
	var sp_chip: Button = ep.chips.get("spring") if ep.chips.has("spring") else null
	ok(sp_chip != null and sp_chip.is_visible_in_tree(), "0 the Spring chip is on the Easy Part chips row (chips: %s)" % str(ep.chips.keys()))

	# 1 one click on Spring: one undo step, one solid, 6 turns of 2 mm wire
	var ub0: int = m.undo.size()
	await click_ctl(sp_chip)
	await idle(10)
	var b1 := built()
	ok(m.undo.size() == ub0 + 1 and int(b1["bodies"]) == 1 and absf(float(b1["h"]) - 10.0) <= 0.2 and absf(float(b1["w"]) - 22.0) <= 0.2,
		"1 Spring: one undo step (%d -> %d), %d solid, height %.2f mm (want 10.0), width %.2f mm (want 22.0)" % [ub0, m.undo.size(), int(b1["bodies"]), float(b1["h"]), float(b1["w"])])
	await shot("00_spring")

	# 2 Turns: a real drag to 10 turns
	var rt := row_of(ep, "turns")
	var st: HSlider = rt.get("slider")
	var range_ok := st != null and absf(st.min_value - 3.0) < 0.01 and absf(st.max_value - 12.0) < 0.01
	var ub1: int = m.undo.size()
	if st != null:
		await slide_to(st, 10.0)
	await idle(10)
	await shot("01_turns")
	var b2 := built()
	ok(range_ok and m.undo.size() == ub1 + 1 and absf(float(b2["h"]) - 16.4) <= 0.2,
		"2 Turns slider 3..12, dragged to 10: one undo step (%d -> %d), height %.2f mm (want 16.4)" % [ub1, m.undo.size(), float(b2["h"])])

	# 3 Wire: a real drag to the right end, 4 mm
	var rw := row_of(ep, "wire")
	var sw: HSlider = rw.get("slider")
	var wrange_ok := sw != null and absf(sw.min_value - 1.0) < 0.01 and absf(sw.max_value - 4.0) < 0.01
	var ub2: int = m.undo.size()
	if sw != null:
		await slide_to(sw, sw.max_value)
	await idle(10)
	await shot("02_wire")
	var b3 := built()
	ok(wrange_ok and m.undo.size() == ub2 + 1 and absf(float(b3["w"]) - 24.0) <= 0.2 and absf(float(b3["h"]) - 32.8) <= 0.2,
		"3 Wire slider 1..4, dragged to 4 mm: one undo step (%d -> %d), width %.2f mm (want 24.0), height %.2f mm (want 32.8)" % [ub2, m.undo.size(), float(b3["w"]), float(b3["h"])])

	# 4 Ctrl+Z: the wire goes back to 2 mm, the turns stay at 10
	await ctrl_z()
	var b4 := built()
	ok(absf(float(b4["w"]) - 22.0) <= 0.2 and absf(float(b4["h"]) - 16.4) <= 0.2,
		"4 Ctrl+Z after the wire drag: width %.2f mm (want 22.0), height %.2f mm (want 16.4, 10 turns)" % [float(b4["w"]), float(b4["h"])])

	# 5 the words: no key name
	var bad_words := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
	var texts := [ep.hint_l.text, ep.status_l.text]
	var hit := []
	for t in texts:
		for w in bad_words:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "5 no key name in the words, the hint or the status line %s" % str(hit))

	print("p070springswit: %d fail" % fails)
	quit(1 if fails > 0 else 0)
