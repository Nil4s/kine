extends SceneTree
## P038 MAKE IT STRONGER (Friday plan item 38, Kine's own idea: the part says where it is thin and adds a rib there): a beginner from the
## BUILDING card makes a thin plate, then presses Make it stronger. Real clicks and drags at 1280 x 720.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box 12 x 8 cm) -> Pull it up (the plate, about 2 cm thick)
##   -> Make it stronger (in the Round the edges row) -> one rib on the top face, along the plate's long side
## A rib is 4 mm wide and 10 mm tall. Its volume and the growth of the built solid are measured from the built result (mm, mm3), and the
## long side of the plate is read from the built solid's bounding box before the press (never from the code).
## Bars (run on the code before this change: see the report):
##   P0 after the plate is pulled up, a Make it stronger button is on the screen (name easypart_stronger)
##   P1 after the press: one body, and the solid grows 10 mm along its thin side (within 0.5 mm)
##   P2 the rib's volume is 4 mm x the plate's long side x 10 mm (within 15 %)
##   P3 Make it stronger is ONE undo step, and Undo gives back the plate's volume (within 0.1 %)
##   P4 the words after the press say rib, and say what to do next (Rib height slider)
##   P5 no jargon (sketch, extrude, boolean, feature, body, loft, cylinder, plane) on the words
## shots: C:/Temp/claude/p038makeitstro/plate.png, rib.png
const SHOT := "C:/Temp/claude/p038makeitstro"
const DIRT := "user://p038makeitstro_test"
const RIB_W_MM := 4.0    # the rib's width (design number, the Make it stronger words)
const RIB_H_MM := 10.0   # the rib's height
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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the built solid's bounding box size in mm
func bb_mm(s: Dictionary) -> Vector3:
	return (s["aabb"] as AABB).size / Part.MM


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
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the plate: a box on the grid (12 cm x 8 cm), Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.06, 0.0, -0.04)), scr(Vector3(0.06, 0.0, 0.04))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var v1 := vol_mm3(s1)
	var bb1 := bb_mm(s1)
	var thin_axis := 0
	for a in 3:
		if bb1[a] < bb1[thin_axis]:
			thin_axis = a
	var long_axis := 0 if bb1.x >= bb1.z else 2
	var long_mm := bb1[long_axis]
	await shot("plate")
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "plate: one body, volume %.0f mm3, size %.1f x %.1f x %.1f mm" % [v1, bb1.x, bb1.y, bb1.z])

	# P0 the button is on the screen
	var sb = null   # the press is the button named easypart_stronger, found the way a tester sees it: under the Round row
	for c in ep.round_box.find_children("*", "", true, false):
		if c.name == "easypart_stronger":
			sb = c
	var on := sb != null and sb is Button and (sb as Button).is_visible_in_tree()
	ok(on, "P0 after Pull it up: a Make it stronger button is on the screen")
	if not on:
		print("p038makeitstro: %d fail" % (fails + 1))
		quit(1)
		return

	# P1 P3 one press: one body, the solid grows 10 mm along the thin side; one undo step
	var n0: int = m.undo.size()
	await click_ctl(sb)
	await idle(10)
	var n1: int = m.undo.size()
	var words := String(ep.hint_l.text) + " " + String(ep.msg)   # the words the press leaves (read before Undo changes them)
	var lab := []
	labels(ep.status, lab)
	words += " " + " ".join(lab)
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var bb2 := bb_mm(s2)
	var grow := bb2[thin_axis] - bb1[thin_axis]
	ok(int(s2["bodies"]) == 1 and absf(grow - RIB_H_MM) < 0.5, "P1 one body; the solid grew %.2f mm along its thin side (rib 10 mm)" % grow)
	await shot("rib")

	# P2 the rib's volume: 4 mm wide x the long side x 10 mm (the plate's long side from its built box)
	var want := RIB_W_MM * long_mm * RIB_H_MM
	var got := v2 - v1
	ok(absf(got - want) < 0.15 * want, "P2 rib volume %.0f mm3 (4 mm x %.1f mm x 10 mm = %.0f mm3)" % [got, long_mm, want])

	# P3 one undo step, and Undo gives the plate back
	ok(n1 - n0 == 1, "P3 Make it stronger is one undo step (undo count +%d)" % (n1 - n0))
	m._undo()
	await idle(10)
	var s3 := solid()
	ok(absf(vol_mm3(s3) - v1) < 0.001 * v1, "P3 Undo gives the plate back (%.0f mm3 vs %.0f mm3)" % [vol_mm3(s3), v1])
	await idle(10)

	# P4 P5 the words
	ok(words.to_lower().find("rib") >= 0 and words.to_lower().find("slider") >= 0, "P4 the words say rib and name the slider: [%s]" % words)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder", "plane"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty(), "P5 no jargon %s" % [jargon])
	print("p038makeitstro: %d fail" % fails)
	quit(1 if fails > 0 else 0)
