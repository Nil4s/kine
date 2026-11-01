extends SceneTree
## godot --path . --position 4000,4000 -s tests/s055_test.gd   (EASY PART, Friday plan 55 + 56: the Measure chip in the view column; needs the CAD DLL)
## Bars (real clicks at 1280 x 720 on a 40 x 30 x 20 mm box set in the record, camera turned by the view; read from the readout text and value):
##   1 CHIP      Measure is a chip in the view column, on screen, not over another control
##   2 X EDGE    two clicks on the two top-front corners read 40.0 mm within 0.1 (label "40.0 mm")
##   3 DIAGONAL  two clicks on opposite corners read sqrt(40^2+30^2+20^2) = 53.85 within 0.1
##   4 RIGHT     a click inside the top face and one inside the side face read 90.0 deg within 0.1 (label "90.0 deg")
##   5 CHAMFER   a 30 deg sloping face of a second part vs its top face reads 30 (or 150) within 0.5
##   6 UNTOUCHED the record and the undo count are the same after all the measuring
##   7 ESC       Esc leaves the mode (chip off, readouts gone), still no record / undo change
## Shots: C:/Temp/claude/s055/measure.png, chamfer.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s055"
const DIRT := "user://s055_test"
var pu: PartUI
var ep


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func box_rec() -> Dictionary:
	var rec := Part.make("Box")
	var fs: Array = []
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(40, 30))]), "extrude", 20.0, "new")
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


## a 40 wide, 30 high, 20 deep part whose left top corner is cut away by a face 30 deg off the top
func wedge_rec() -> Dictionary:
	var rec := Part.make("Wedge")
	var fs: Array = []
	var t := 15.0 * tan(deg_to_rad(30.0))
	var pts := [Vector2(0, 0), Vector2(40, 0), Vector2(40, 30), Vector2(15, 30), Vector2(0, 30.0 - t)]
	var ents: Array = []
	for i in pts.size():
		ents.append({"k": "line", "a": Part.arr2(pts[i]), "b": Part.arr2(pts[(i + 1) % pts.size()])})
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", ents), "extrude", 20.0, "new")
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


func put(rec: Dictionary, sx: float, sz: float) -> void:
	m.S.part = rec
	pu.sync()
	await idle(6)
	ep.frame()
	await idle(30)
	var c := Vector3(0.02, 0.015, 0.01)
	for yaw in [35.0, -35.0, 145.0, -145.0]:
		m._turn_to(yaw, -30.0, 0.1, c, false)
		await idle(6)
		var pose: Array = ep._frame_pose(AABB(Vector3.ZERO, Vector3(0.04, 0.03, 0.02)), 1.0)
		if not pose.is_empty():
			m._turn_to(yaw, -30.0, float(pose[1]), pose[0], false)
			await idle(6)
		var d: Vector3 = m.cam.global_position - c
		if signf(d.x) == sx and signf(d.z) == sz:
			break
	await idle(30)


func scr(mm: Vector3) -> Vector2:
	return m.cam.unproject_position(mm * 0.001)


func click_mm(mm: Vector3) -> void:
	var p := scr(mm)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func last_v() -> float:
	return float(ep.meas.out.back()["v"]) if not ep.meas.out.is_empty() else -999.0


func last_t() -> String:
	return String(ep.meas.out.back()["txt"]) if not ep.meas.out.is_empty() else "(none)"


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
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	await put(box_rec(), 1.0, 1.0)
	var rec0 := JSON.stringify(m.S.part)
	var u0: int = m.undo.size()
	# 1 CHIP
	var chip := root.find_child("easypart_view_measure", true, false) as Button
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var over := []
	if chip != null:
		for c in root.find_children("*", "BaseButton", true, false):
			var b := c as BaseButton
			if b != chip and b.is_visible_in_tree() and b.get_global_rect().intersects(chip.get_global_rect()):
				over.append(b.name)
	ok(chip != null and chip.is_visible_in_tree() and vp.encloses(chip.get_global_rect()) and over.is_empty(), "1 the Measure chip is in the view column, on screen, over nothing %s" % str(over))
	await click_ctl(chip)
	ok(ep.meas.on, "1b a real click on the chip turns Measure on")
	# 2 X EDGE
	await click_mm(Vector3(0, 30, 20))
	await click_mm(Vector3(40, 30, 20))
	var v2 := last_v()
	ok(absf(v2 - 40.0) <= 0.1 and last_t() == "40.0 mm", "2 corner to corner along X reads %.3f (label %s)" % [v2, last_t()])
	# 3 DIAGONAL
	await click_mm(Vector3(0, 0, 20))
	await click_mm(Vector3(40, 30, 0))
	var v3 := last_v()
	var want := sqrt(40.0 * 40.0 + 30.0 * 30.0 + 20.0 * 20.0)
	ok(absf(v3 - want) <= 0.1 and last_t() == "%.1f mm" % v3, "3 space diagonal reads %.3f (want %.3f; label %s)" % [v3, want, last_t()])
	await shot("measure")
	# 4 RIGHT ANGLE
	await click_mm(Vector3(20, 30, 10))
	await click_mm(Vector3(40, 15, 10))
	var v4 := last_v()
	ok(absf(v4 - 90.0) <= 0.1 and last_t() == "90.0 deg", "4 top vs side face reads %.3f deg (label %s)" % [v4, last_t()])
	ok(ep.meas.out.size() == 3, "4b three readouts are on the view (%d)" % ep.meas.out.size())
	# 6 untouched (box)
	ok(JSON.stringify(m.S.part) == rec0 and m.undo.size() == u0, "6 the record is the same and the undo count stays %d (now %d)" % [u0, m.undo.size()])
	# 5 CHAMFER: a second part, Measure still on
	await put(wedge_rec(), -1.0, 1.0)
	var rec1 := JSON.stringify(m.S.part)
	var u1: int = m.undo.size()
	await click_mm(Vector3(28, 30, 10))
	var t := 15.0 * tan(deg_to_rad(30.0))
	await click_mm(Vector3(7.5, 30.0 - t * 0.5, 10))
	var v5 := last_v()
	ok((absf(v5 - 30.0) <= 0.5 or absf(v5 - 150.0) <= 0.5) and last_t().ends_with(" deg"), "5 30 deg chamfer face vs top reads %.3f deg (label %s)" % [v5, last_t()])
	await shot("chamfer")
	ok(JSON.stringify(m.S.part) == rec1 and m.undo.size() == u1, "6b record and undo unchanged on the chamfer part (undo %d)" % m.undo.size())
	# 7 ESC
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e, true)
	await idle(4)
	ok(not ep.meas.on and not chip.button_pressed and ep.meas.out.is_empty() and not ep.meas.ov.visible, "7 Esc leaves Measure: mode %s, chip %s, readouts %d" % [ep.meas.on, chip.button_pressed, ep.meas.out.size()])
	ok(JSON.stringify(m.S.part) == rec1 and m.undo.size() == u1, "7b still no record / undo change")
	print("s055: %d fail" % fails)
	quit(1 if fails > 0 else 0)
