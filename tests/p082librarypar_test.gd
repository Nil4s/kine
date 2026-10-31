extends SceneTree
## P082 LIBRARY PARTS STAY PARAMETRIC (Friday plan item 82, Kine's own idea: a part from the library is still a recipe after it is placed,
## so a size change later rebuilds it, and the hole cut for it follows). Real clicks at 1280 x 720, from the BUILDING card.
##   Part 1 (a hole follows the screw): plate -> Cut a hole -> M4 screw -> Use in a scene -> Change the part -> M5 screw
##   Part 2 (a library screw keeps its size): Parts -> Screws -> M4 x 16 -> Add its nut and washer -> Use in a scene
##          -> Change the part -> M5 x 16 (the screw and its nut and washer follow)
## Every number is measured from the built result (mm3, mm, undo count, pressed chips). The expected numbers come from the ISO sizes
## written in this file (ISO 4762 head, ISO 4032 nut across flats, clearance holes), never from the code's own variables.
## Bars (written before the change; the code on the base has no hole or screw follow, so these fail there):
##   B0 after Change the part, the chip of the M4 hole the plate was cut with is pressed and the hole chips are on the screen
##   B1 M5 screw after Change the part: one body, the plate lost a 5.5 mm hole + 8.5 mm x 5 mm counterbore (volume within 3 %)
##   B2 M5 screw after Change the part is ONE undo step
##   A0 M4 x 16 screw with its nut and washer on the floor: the screw is 20 mm tall (16 mm shank + 4 mm head), one undo step per step
##   A1 M5 x 16 after Change the part: the screw is 21 mm tall (16 + 5), and the nut's far edge sits at 40 + 8 / sqrt(3) mm
##   A2 M5 x 16 is ONE undo step
## shots: C:/Temp/claude/p082librarypar/*.png
const SHOT := "C:/Temp/claude/p082librarypar"
const DIRT := "user://p082librarypar_test"
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


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## a plate T mm deep with a screw hole: clearance cylinder + counterbore ring for the head (ISO numbers from the screw's size)
func want_mm3(clear_mm: float, head_mm: float, head_h: float, T: float) -> float:
	var r := clear_mm / 2.0
	var R := head_mm / 2.0
	return PI * r * r * T + PI * (R * R - r * r) * head_h


## the Change the part button on STAGE (the part in the set comes back to Easy Part)
func change_btn() -> Button:
	return m.bld.stage_body.get_node_or_null("build_edit_in_build") as Button


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

	# ---- Part 1: a plate with an M4 screw hole, placed, then changed to M5
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var v1 := vol_mm3(solid())
	var T := (solid()["aabb"] as AABB).size.z / Part.MM
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	await click_ctl(ep.hole_btns["screw4"])
	await idle(10)
	await click_ctl(ep.use_scene_btn)   # Save and use in a scene: the plate is a prop of the set
	await idle(30)
	var eb := change_btn()
	ok(m.cur_page == "STAGE" and eb != null and eb.is_visible_in_tree(),
		"setup: the plate is in the scene (page %s, Change the part button %s)" % [m.cur_page, eb != null])
	if eb != null:
		await click_ctl(eb)
	await idle(20)
	ep = m.bld.part.ep
	var b0 := ep.hole_btns.get("screw4", null) as Button
	print("diag B0: page %s hole_base_empty %s pressed %s box_in_tree %s box_visible %s hole_mode %s on %s" % [m.cur_page, ep.hole_base.is_empty(), b0 != null and b0.button_pressed, ep.hole_box.is_visible_in_tree(), ep.hole_box.visible, ep.hole_mode, ep.active()])
	ok(m.cur_page == "BUILD" and ep.hole_base.is_empty() and b0 != null and b0.button_pressed and ep.hole_box.is_visible_in_tree(),
		"B0 after Change the part (page %s): the M4 hole chip is pressed and the hole chips are on the screen" % m.cur_page)
	await shot("p1_reopened")

	var n0: int = m.undo.size()
	await click_ctl(ep.hole_btns["screw5"])
	await idle(10)
	var s5 := solid()
	var removed5 := v1 - vol_mm3(s5)
	var want5 := want_mm3(5.5, 8.5, 5.0, T)
	ok(int(s5["bodies"]) == 1 and absf(removed5 - want5) < 0.03 * want5,
		"B1 M5 screw after Change the part: one body; plate lost %.1f mm3 (a 5.5 mm hole + 8.5 mm x 5 mm counterbore = %.1f mm3)" % [removed5, want5])
	ok(m.undo.size() - n0 == 1, "B2 M5 screw after Change the part is ONE undo step (undo count +%d)" % (m.undo.size() - n0))
	await shot("p1_m5")

	# ---- Part 2: a library screw (Parts -> Screws), its nut and washer, placed, then changed to M5
	await click_ctl(ep.parts_btn)
	await idle(5)
	await click_ctl(ep.screw_btns["4_16"])
	await idle(10)
	await click_ctl(ep.nw_btn)
	await idle(10)
	var sc4 := solid()
	var h4 := (sc4["aabb"] as AABB).size.y / Part.MM
	ok(absf(h4 - 20.0) < 0.1 and int(sc4["bodies"]) >= 1, "A0 M4 x 16 with its nut and washer: the screw is %.2f mm tall (16 + 4 = 20)" % h4)
	await click_ctl(ep.use_scene_btn)
	await idle(30)
	eb = change_btn()
	ok(m.cur_page == "STAGE" and eb != null and eb.is_visible_in_tree(),
		"setup 2: the screw is in the scene (page %s, Change the part button %s)" % [m.cur_page, eb != null])
	if eb != null:
		await click_ctl(eb)
	await idle(20)
	ep = m.bld.part.ep
	var n1: int = m.undo.size()
	await click_ctl(ep.screw_btns["5_16"])
	await idle(10)
	var sc5 := solid()
	var bb5: AABB = sc5["aabb"]
	var h5 := bb5.size.y / Part.MM
	var nut_far := bb5.end.x / Part.MM
	var want_nut := 40.0 + 8.0 / sqrt(3.0)
	ok(int(sc5["bodies"]) == int(sc4["bodies"]) and absf(h5 - 21.0) < 0.1,
		"A1 M5 x 16 after Change the part: the screw is %.2f mm tall (16 + 5 = 21 mm); M4 x 16 was %.2f mm (16 + 4 = 20)" % [h5, h4])
	ok(absf(nut_far - want_nut) < 0.1, "A1 the nut follows the size: its far edge at %.2f mm (40 + 8/sqrt3 = %.2f mm)" % [nut_far, want_nut])
	ok(m.undo.size() - n1 == 1, "A2 M5 x 16 is ONE undo step (undo count +%d)" % (m.undo.size() - n1))
	await shot("p2_m5")
	print("p082librarypar: %d fail" % fails)
	quit(1 if fails > 0 else 0)
