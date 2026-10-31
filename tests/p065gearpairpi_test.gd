extends SceneTree
## p065gearpairpi (Friday plan item 65: Gear pair: pick a ratio (2:1) -> two gears placed meshing at the right distance). A beginner from the
## BUILDING card: Parts > Gears shows a Gear pair button; one click drops two gears on the floor, the small one at the origin and the big one
## (teeth = small teeth x ratio) placed so their pitch circles touch: the centre distance is module x (small + big) / 2, so the teeth
## interleave. Sliders by real drags: Ratio (1..3 : 1) and Thickness (3..30 mm).
## Kine's own idea (★): the beginner never types a distance. The big gear is turned half a tooth so a tooth of one fills a gap of the other,
## and the two solids do not touch (bodies stay 2 at every ratio).
## Every size below is measured from the BUILT mesh (mm), never from the record or the code's variables.
## Geometry the bars expect (defaults: Small teeth 15, Teeth size 2 (module 2), Ratio 2 : 1, Thickness 10 mm): the small gear (15 teeth,
## 34 mm across) at x = 0, the big gear (30 teeth, 64 mm across) at x = 45 mm (module x (15 + 30) / 2). The part is 93.7 mm wide (x from
## -16.8 to 76.9), 64.0 mm tall, 10 mm thick. At ratio 3 : 1 the big gear has 45 teeth (94 mm across, centre at 60 mm): 123.8 mm wide.
## Bars (run on the old code first: the old code has no Gear pair button, so bars 0 to 4 FAIL there):
##   0 Parts > Gears shows the Gear pair button
##   1 one click: one undo step, two solids, width 93.7 mm (+- 0.5), height 64.0 mm (+- 0.5)
##   2 Ratio slider 1..3, dragged to 3 : 1: one undo step, two solids, width 123.8 mm (+- 0.5)
##   3 Ctrl+Z after the ratio drag: width 93.7 mm again (+- 0.5)
##   4 Thickness dragged to 20 mm: the built part is 20.0 mm thick (+- 0.3), still two solids
##   5 the words: no key name in the words, the hint or the status line
## shots: C:/Temp/claude/p065gearpairpi/shots/
const SHOT := "C:/Temp/claude/p065gearpairpi/shots"
const DIRT := "user://p065gearpairpi_test"
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


## a real drag of a template slider from its knob to value v
func slide_to(s: HSlider, v: float) -> void:
	var a := knob_x(s, s.value)
	await drag_screen(a, knob_x(s, v))


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


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	root.push_input(e, true)
	await idle(3)


## the built part in mm, from the mesh faces: x across, y up, z through the thickness; bodies = the solids the build made
func built() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			lo = lo.min(p)
			hi = hi.max(p)
	if faces.is_empty():
		return {"w": 0.0, "h": 0.0, "t": 0.0, "x0": 0.0, "bodies": 0}
	return {"w": hi.x - lo.x, "h": hi.y - lo.y, "t": hi.z - lo.z, "x0": lo.x, "bodies": int(pu().res.get("bodies", 0))}


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

	# 0 the BUILDING card, one click: an empty Easy Part; Parts > Gears shows the Gear pair button
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
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_lib_Gears", true, false) as Control)
	var gp_chip := root.find_child("easypart_gearpair_pick", true, false) as Button
	ok(gp_chip != null and gp_chip.is_visible_in_tree(), "0 Parts > Gears shows the Gear pair button")

	# 1 one click: one undo step, two solids, 93.7 mm wide, 64.0 mm tall
	var ub0: int = m.undo.size()
	if gp_chip != null:
		await click_ctl(gp_chip)
	await idle(10)
	await shot("00_gearpair")
	var b1 := built()
	ok(m.undo.size() == ub0 + 1 and int(b1["bodies"]) == 2 and absf(float(b1["w"]) - 93.7) <= 0.5 and absf(float(b1["h"]) - 64.0) <= 0.5,
		"1 Gear pair: one undo step (%d -> %d), %d solids, width %.2f mm (want 93.7), height %.2f mm (want 64.0) [%s]" % [ub0, m.undo.size(), int(b1["bodies"]), float(b1["w"]), float(b1["h"]), ep.msg])

	# 2 Ratio: a real drag from 2 : 1 to 3 : 1; the big gear grows to 45 teeth, the part is 123.8 mm wide, still two solids
	var rr := row_of(ep, "ratio")
	var sr: HSlider = rr.get("slider")
	var ratio_ok := sr != null and absf(sr.min_value - 1.0) < 0.01 and absf(sr.max_value - 3.0) < 0.01
	var ub2: int = m.undo.size()
	if sr != null:
		await slide_to(sr, 3.0)
	await idle(10)
	await shot("01_ratio")
	var b2 := built()
	ok(ratio_ok and m.undo.size() == ub2 + 1 and int(b2["bodies"]) == 2 and absf(float(b2["w"]) - 123.8) <= 0.5,
		"2 Ratio 1..3, dragged to 3 : 1: one undo step, %d solids, width %.2f mm (want 123.8)" % [int(b2["bodies"]), float(b2["w"])])

	# 3 Ctrl+Z after the ratio drag: 2 : 1 again, 93.7 mm wide
	await ctrl_z()
	var b3 := built()
	ok(absf(float(b3["w"]) - 93.7) <= 0.5, "3 Ctrl+Z after the ratio drag: width %.2f mm (want 93.7)" % float(b3["w"]))

	# 4 Thickness: a real drag to 20 mm; the built part is 20 mm thick, still two solids
	var rt := row_of(ep, "thickness")
	var stk: HSlider = rt.get("slider")
	var ub4: int = m.undo.size()
	if stk != null:
		await slide_to(stk, 20.0)
	await idle(10)
	await shot("02_thick")
	var b4 := built()
	ok(stk != null and m.undo.size() == ub4 + 1 and absf(float(b4["t"]) - 20.0) <= 0.3 and int(b4["bodies"]) == 2,
		"4 Thickness dragged to 20: one undo step, the built part is %.2f mm thick (want 20.00), %d solids" % [float(b4["t"]), int(b4["bodies"])])

	# 5 the words: no key name
	var bad_words := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
	var texts := [ep.hint_l.text, ep.status_l.text]
	var hit := []
	for t in texts:
		for w in bad_words:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "5 no key name in the words, the hint or the status line %s" % str(hit))

	print("p065gearpairpi: %d fail" % fails)
	quit(1 if fails > 0 else 0)
