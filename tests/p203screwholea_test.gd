extends SceneTree
## P203 SCREW-HOLE AUTO-TOLERANCE BY PRINTER (Friday plan item 203, Kine's own idea: the hole knows the printer): a beginner from the BUILDING
## card makes a plate, cuts an M4 screw hole, and picks the printer with ONE chip on the Cut a hole panel: Printer: any -> resin -> FDM -> any.
## Resin prints small, so the hole is TIGHT (ISO 273 fine: M4 4.3 mm); FDM prints loose, so the hole is LOOSE (ISO 273 coarse: M4 4.8 mm);
## any = the ISO 273 medium hole that Kine always cut (M4 4.5 mm). The counterbore for the head does not change.
## Real clicks at 1280 x 720. Volume removed from the plate is measured from the built result (mm3) and compared with the sum of a clearance
## cylinder and a counterbore ring, computed here from the ISO 273 / ISO 4762 numbers, never from the code's variables.
## Bars (written before the code change):
##   P0 the printer chip is on the Cut a hole panel, says "any" at the start, and pressing it alone adds no undo step
##   P1 resin, then M4 screw: one body; the plate loses a 4.3 mm hole + 7 mm x 4 mm counterbore (volume within 3 %)
##   P2 the words after resin name the tight hole (4.3 mm) and the printer
##   P3 switch to FDM while M4 is the newest hole: the hole is REPLACED (undo count +1), now 4.8 mm, volume within 3 %, one body
##   P4 the words after FDM say loose (4.8 mm) and no jargon (sketch, extrude, boolean, feature, body, loft, cylinder)
##   P5 back to any, M4 is 4.5 mm again (volume within 3 %): the chip cycles back
##   P6 the printer chip and its panel stay inside the 1280 x 720 window (no part of the chip past the right or bottom edge)
## shots: C:/Temp/claude/p203screwholea/resin.png, fdm.png
const SHOT := "C:/Temp/claude/p203screwholea"
const DIRT := "user://p203screwholea_test"
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


## the volume a screw hole takes out of a plate T mm deep: a clearance cylinder through it + the counterbore ring for the head
func want_mm3(clear_mm: float, head_mm: float, head_h: float, T: float) -> float:
	var r := clear_mm / 2.0
	var R := head_mm / 2.0
	return PI * r * r * T + PI * (R * R - r * r) * head_h


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

	# the plate: a box on the grid (18 cm x 6 cm), Pull it up (2 cm)
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var v1 := vol_mm3(s1)
	var bb1: AABB = s1["aabb"]
	var T := bb1.size.z / Part.MM   # the plate's depth in mm, from the built result
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "plate: one body, volume %.0f mm3, depth %.1f mm" % [v1, T])

	# P0 Cut a hole: the printer chip is on the panel, says any, and pressing it alone adds no undo step
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var pb: Button = ep.hole_box.find_child("easypart_hole_printer", true, false) as Button
	var said0 := "" if pb == null else pb.text
	ok(pb != null and pb.is_visible_in_tree() and said0.to_lower().find("any") >= 0,
		"P0 after Cut a hole: the printer chip is on the screen and says any [%s]" % said0)
	var n0: int = m.undo.size()
	if pb != null:
		await click_ctl(pb)
	await idle(10)
	var n_pick: int = m.undo.size()
	ok(n_pick == n0, "P0b the printer chip alone adds no undo step (undo count %d -> %d)" % [n0, n_pick])
	if pb != null and pb.text.to_lower().find("resin") < 0:
		await click_ctl(pb)   # cycle any -> resin if the first press went elsewhere
	await idle(5)
	var t_res := "" if pb == null else pb.text

	# P1 + P2: resin, then M4 screw: tight hole 4.3 mm
	var n1: int = m.undo.size()
	if ep.hole_btns.has("screw4"):
		await click_ctl(ep.hole_btns["screw4"])
	await idle(10)
	var n2: int = m.undo.size()
	var s2 := solid()
	var v2 := vol_mm3(s2)
	var removed_r := v1 - v2
	var want_r := want_mm3(4.3, 7.0, 4.0, T)
	ok(int(s2["bodies"]) == 1 and absf(removed_r - want_r) < 0.03 * want_r,
		"P1 resin M4 screw: one body; plate lost %.1f mm3 (a 4.3 mm tight hole + 7 mm x 4 mm counterbore = %.1f mm3)" % [removed_r, want_r])
	var said := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(said.find("4.3") >= 0 and said.find("resin") >= 0 and n2 - n1 == 1,
		"P2 the words after resin name the tight 4.3 mm hole and the printer, one undo step: [%s] (chip '%s')" % [said, t_res])
	await shot("resin")

	# P3 + P4: switch the printer to FDM while M4 is the newest hole: the hole is replaced, loose 4.8 mm
	var n3: int = m.undo.size()
	if pb != null:
		await click_ctl(pb)
	await idle(10)
	var n4: int = m.undo.size()
	var s3 := solid()
	var v3 := vol_mm3(s3)
	var removed_f := v1 - v3
	var want_f := want_mm3(4.8, 7.0, 4.0, T)
	ok(int(s3["bodies"]) == 1 and absf(removed_f - want_f) < 0.03 * want_f and n4 - n3 == 1,
		"P3 FDM replaces the M4 hole: one body, one undo step; plate lost %.1f mm3 (a 4.8 mm loose hole + 7 mm x 4 mm = %.1f mm3)" % [removed_f, want_f])
	var words := String(ep.hint_l.text) + " " + String(ep.msg)
	var lab := []
	labels(ep.status, lab)
	words += " " + " ".join(lab)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(words.find("4.8") >= 0 and words.to_lower().find("fdm") >= 0 and jargon.is_empty() and (s3["errors"] as Dictionary).is_empty(),
		"P4 the words after FDM say loose 4.8 mm, no failed step, no jargon %s: [%s]" % [jargon, words])
	await shot("fdm")

	# P5: back to any: the medium 4.5 mm hole again
	if pb != null:
		await click_ctl(pb)
	await idle(10)
	var s4 := solid()
	var v4 := vol_mm3(s4)
	var removed_a := v1 - v4
	var want_a := want_mm3(4.5, 7.0, 4.0, T)
	ok(int(s4["bodies"]) == 1 and absf(removed_a - want_a) < 0.03 * want_a,
		"P5 any: the M4 hole is 4.5 mm again; plate lost %.1f mm3 (= %.1f mm3)" % [removed_a, want_a])

	# P6: the chip and its panel stay on the 1280 x 720 window
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var inside := pb != null and win.encloses(pb.get_global_rect()) and win.encloses(ep.hole_box.get_global_rect())
	ok(inside, "P6 the printer chip and the Cut a hole panel are inside 1280 x 720: chip %s, panel %s" % [pb.get_global_rect() if pb != null else "none", ep.hole_box.get_global_rect()])
	print("p203screwholea: %d fail" % fails)
	quit(1 if fails > 0 else 0)
