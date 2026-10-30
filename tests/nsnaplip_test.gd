extends SceneTree
## NSNAPLIP (Friday plan item 20: "Snap-fit lip"): the same beginner walk as NLID (box, Cut a hole > Hollow with a lid), then the on/off chip
## "Snap-fit lip": a small ridge on the lid lip and a matching groove in the box wall. Every number is measured from the BUILT result (Part.replay
## with faces and props), never from the code's own variables.
##   S0 the box as in NLID (one body)
##   S1 Cut a hole, Hollow with a lid: two bodies, the Snap-fit lip chip is there and off
##   S2 one click on the chip: two bodies, the chip is on, <= 1 click
##   S3 the lid gains a ridge: its volume grows by a 1 mm ring 0.5 mm wide on the lip (within 5 pct)
##   S4 the box loses a groove: its volume drops by a 1 mm ring 0.5 mm deep in the wall (within 8 pct)
##   S5 the ridge and the groove are measured as faces: the groove floor 2.5 mm in from the outside, the ridge outside 2.7 mm
##   S6 one undo step (Ctrl+Z) takes the chip back off: the lid volume is the NLID lid again (within 0.5 pct), undo count -1
##   S7 the chip turns off again with one more click: the lid is the plain lid again (within 0.5 pct)
##   S8 the words name the snap in plain words, no jargon
## shots: C:/Temp/claude/nsnaplip/*.png

## then Cut a hole > Hollow with a lid. The result is two pieces: the box (hollowed out, open at the top, 5 mm shorter) and the lid (its top
## 5 mm as a solid plate on the same footprint, with a 3 mm lip that hangs inside the box, 0.2 mm off the walls). Every number is measured
## from the BUILT result (Part.replay with faces and props), never from the code's own variables.
##   N0 the BUILDING card, one click; Easy; Draw shape + Box chip + drag a box on the grid + Pull it up (one body)
##   N1 Cut a hole, then the Hollow with a lid chip (<= 2 clicks): two bodies
##   N2 the lid is 8 mm tall (5 mm plate + 3 mm lip) within 0.2 mm
##   N3 the box top is 5 mm under the lid's top (within 0.2 mm)
##   N4 the lid's volume = its plate (footprint x 5 mm) + its lip ring (1 mm wide, 3 mm tall), within 3 pct
##   N5 the lip sits inside the box: every lip point is at least 2.5 mm in from the outside
##   N6 the box is hollow: its volume is under 60 pct of the solid box
##   N7 one undo step (Ctrl+Z) takes it back to one body
##   N8 the words name the lid in plain words, no kernel jargon
## shots: C:/Temp/claude/nlid/open.png, lid.png
const SHOT := "C:/Temp/claude/nsnaplip"
const DIRT := "user://nsnaplip_test"
var fails := 0
var m: Node
var clicks := 0
var said := []


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
	clicks += 1
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
	return Part.replay(m.S.part, -1, {"faces": true, "props": true})


func mm(v: float) -> float:
	return v / Part.MM


func say_now(ep) -> String:
	return String(ep.hint_l.text) + " | " + String(ep.msg)


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
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and note_words.find("Easy") >= 0,
		"N0a BUILDING card, one click, a blank part, words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await shot("open")

	# S0 the box: Draw shape, Box chip, drag a box on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	ok(int(s0["bodies"]) == 1 and mm(bb0.size.y) >= 12.0 and mm(bb0.size.x) >= 12.0,
		"N0b the box: one body, %.1f x %.1f x %.1f mm" % [mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])
	said.append(say_now(ep))

	# S1 Cut a hole, then Hollow with a lid (the plain lid, snap chip off)
	m.pitch = 50.0
	m._cam()
	await idle(40)
	await click_ctl(ep.make_btns["hole"])
	var has_lid: bool = ep.hole_btns.has("lid")
	if has_lid:
		await click_ctl(ep.hole_btns["lid"])
	await idle(12)
	var s1 := solid()
	var snap_btn: Button = ep.hole_box.find_child("easypart_hole_snap", true, false) as Button
	var has_snap := snap_btn != null and snap_btn.visible and not snap_btn.button_pressed
	ok(has_lid and int(s1["bodies"]) == 2 and has_snap,
		"S1 Cut a hole, Hollow with a lid: %d bodies (want 2), the Snap-fit lip chip is there and off (%s)" % [int(s1["bodies"]), has_snap])
	said.append(say_now(ep))
	await shot("lid_plain")

	# the lid = the piece that reaches the highest face; the box = the other
	var faces1: Array = s1.get("faces", [])
	var nb1 := int(s1["bodies"])
	var lid1 := -1
	var top1 := -1.0e9
	for i in nb1:
		for f in faces1:
			if int(f["body"]) == i and float(f["c"].y) > top1:
				top1 = float(f["c"].y)
				lid1 = i
	var box1 := 1 - lid1 if nb1 == 2 else -1
	var lid_v0 := float(s1["volumes"][lid1]) / (Part.MM * Part.MM * Part.MM) if nb1 == 2 else 0.0
	var box_v0 := float(s1["volumes"][box1]) / (Part.MM * Part.MM * Part.MM) if nb1 == 2 else 0.0
	var lo_x0 := INF
	var lo_z0 := INF
	var hi_x0 := -INF
	var hi_z0 := -INF
	var top_mm := mm(float(s1["aabb"].end.y))
	for f in faces1:
		if int(f["body"]) != box1:
			continue
		lo_x0 = minf(lo_x0, f["c"].x)
		hi_x0 = maxf(hi_x0, f["c"].x)
		lo_z0 = minf(lo_z0, f["c"].z)
		hi_z0 = maxf(hi_z0, f["c"].z)
	var W := mm(hi_x0 - lo_x0)
	var D := mm(hi_z0 - lo_z0)

	# S2 one click on the Snap-fit lip chip
	var c2 := clicks
	if snap_btn != null and snap_btn.visible:
		await click_ctl(snap_btn)
	await idle(14)
	var s2 := solid()
	var n2 := clicks - c2
	var snap_on := snap_btn != null and snap_btn.button_pressed
	ok(int(s2["bodies"]) == 2 and snap_on and n2 <= 1,
		"S2 one click on Snap-fit lip: %d bodies (want 2), chip on %s, %d clicks (<= 1)" % [int(s2["bodies"]), snap_on, n2])
	said.append(say_now(ep))
	await shot("lid_snap")

	var faces2: Array = s2.get("faces", [])
	var nb2 := int(s2["bodies"])
	var lid2 := -1
	var top2 := -1.0e9
	for i in nb2:
		for f in faces2:
			if int(f["body"]) == i and float(f["c"].y) > top2:
				top2 = float(f["c"].y)
				lid2 = i
	var box2 := 1 - lid2 if nb2 == 2 else -1
	var lid_v1 := float(s2["volumes"][lid2]) / (Part.MM * Part.MM * Part.MM) if nb2 == 2 else 0.0
	var box_v1 := float(s2["volumes"][box2]) / (Part.MM * Part.MM * Part.MM) if nb2 == 2 else 0.0

	# S3 the ridge: a 1 mm tall ring, 0.5 mm wide, outside the lip (2.7 .. 3.2 mm in from the outside)
	var ridge_want := (W - 5.4) * (D - 5.4) * 1.0 - (W - 6.4) * (D - 6.4) * 1.0
	var ridge_got := lid_v1 - lid_v0
	ok(nb2 == 2 and ridge_want > 0.0 and absf(ridge_got - ridge_want) <= 0.05 * ridge_want,
		"S3 the lid gains a ridge: %.0f mm3 added (want %.0f mm3, within 5 pct; footprint %.2f x %.2f mm)" % [ridge_got, ridge_want, W, D])

	# S4 the groove: a 1 mm tall ring, 0.5 mm deep in the wall (2.5 .. 3.0 mm in from the outside)
	var groove_want := (W - 5.0) * (D - 5.0) * 1.0 - (W - 6.0) * (D - 6.0) * 1.0
	var groove_got := box_v0 - box_v1
	ok(nb2 == 2 and groove_want > 0.0 and absf(groove_got - groove_want) <= 0.08 * groove_want,
		"S4 the box loses a groove: %.0f mm3 gone (want %.0f mm3, within 8 pct)" % [groove_got, groove_want])

	# S5 the faces: the groove floor at 2.5 mm in, the ridge's outside at 2.7 mm in, both at the band's height (top - 6.5 mm)
	var band_y := top_mm - 5.0 - 1.5
	var groove_face := false
	var ridge_face := false
	for f in faces2:
		var c: Vector3 = f["c"]
		var dy := absf(mm(c.y) - band_y)
		if dy > 0.3:
			continue
		if int(f["body"]) == box2 and absf(mm(c.x - lo_x0) - 2.5) <= 0.05:
			groove_face = true
		if int(f["body"]) == lid2 and absf(mm(c.x - lo_x0) - 2.7) <= 0.05:
			ridge_face = true
	ok(nb2 == 2 and groove_face and ridge_face,
		"S5 groove floor 2.5 mm in and ridge outside 2.7 mm in, at the lip's height (groove %s, ridge %s)" % [groove_face, ridge_face])

	# S6 one undo step takes the chip back off: the plain lid again
	var ub6: int = m.undo.size()
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.physical_keycode = KEY_Z
	k.key_label = KEY_Z
	k.pressed = true
	k.ctrl_pressed = true
	root.push_input(k, true)
	await idle(20)
	var s6 := solid()
	var v6 := float(s6["volumes"][lid1]) / (Part.MM * Part.MM * Part.MM) if int(s6["bodies"]) == 2 else -1.0
	ok(int(s6["bodies"]) == 2 and absf(v6 - lid_v0) <= 0.005 * lid_v0 and m.undo.size() == ub6 - 1,
		"S6 Ctrl+Z takes the snap off: lid %.0f mm3 (plain lid %.0f), undo %d -> %d" % [v6, lid_v0, ub6, m.undo.size()])

	# S7 the chip on again, then off with one click: the plain lid again
	if snap_btn != null and snap_btn.visible:
		await click_ctl(snap_btn)
		await idle(10)
		await click_ctl(snap_btn)
		await idle(14)
	var s7 := solid()
	var v7 := float(s7["volumes"][lid1]) / (Part.MM * Part.MM * Part.MM) if int(s7["bodies"]) == 2 else -1.0
	ok(int(s7["bodies"]) == 2 and absf(v7 - lid_v0) <= 0.005 * lid_v0 and not snap_btn.button_pressed,
		"S7 the chip off again: lid %.0f mm3 (plain lid %.0f), chip off %s" % [v7, lid_v0, not snap_btn.button_pressed])

	# S8 the words
	var all_words := " | ".join(said).to_lower()
	var jargon := ["sketch", "extrude", "shell", "split", "boolean", "feature", "loft", "kernel"]
	var bad := ""
	for j in jargon:
		if all_words.find(j) >= 0:
			bad = j
	ok(bad == "" and all_words.find("snap") >= 0 and all_words.find("lid") >= 0,
		"S8 the words name the snap in plain words, no jargon (%s)" % bad)

	print("NSNAPLIP %d fails" % fails)
	quit(1 if fails > 0 else 0)
