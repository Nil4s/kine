extends SceneTree
## NLID (Nick, Friday plan item 19: "Hollow with a lid"): a beginner from the REAL start screen builds a box with real clicks at 1280 x 720,
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
const SHOT := "C:/Temp/claude/nlid"
const DIRT := "user://nlid_test"
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

	# N0 the box: Draw shape, Box chip, drag a box on the grid, Pull it up
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

	# N1 Cut a hole, then Hollow with a lid
	m.pitch = 50.0
	m._cam()
	await idle(40)
	var c1 := clicks
	await click_ctl(ep.make_btns["hole"])
	var has_chip: bool = ep.hole_btns.has("lid")
	var ub_chip: int = m.undo.size()
	if has_chip:
		await click_ctl(ep.hole_btns["lid"])
	await idle(12)
	var s1 := solid()
	var n1 := clicks - c1
	ok(has_chip and int(s1["bodies"]) == 2 and n1 <= 2,
		"N1 Cut a hole, Hollow with a lid: chip there %s, %d bodies (want 2), %d clicks (<= 2)" % [has_chip, int(s1["bodies"]), n1])
	said.append(say_now(ep))
	var lid_words := say_now(ep).to_lower()   # the words right after the lid press (N8 reads these)
	await shot("lid")

	var faces: Array = s1.get("faces", [])
	var nb := int(s1["bodies"])
	var lid := -1
	var top_y := -1.0e9
	for i in nb:   # the lid is the piece that reaches the highest face
		for f in faces:
			if int(f["body"]) == i and float(f["c"].y) > top_y:
				top_y = float(f["c"].y)
				lid = i
	var box := 1 - lid if nb == 2 else -1
	var lo_y := INF
	var hi_y := -INF
	var lo_x := INF
	var hi_x := -INF
	var lo_z := INF
	var hi_z := -INF
	for f in faces:
		if int(f["body"]) != lid:
			continue
		var c: Vector3 = f["c"]
		lo_y = minf(lo_y, c.y)
		hi_y = maxf(hi_y, c.y)
		lo_x = minf(lo_x, c.x)
		hi_x = maxf(hi_x, c.x)
		lo_z = minf(lo_z, c.z)
		hi_z = maxf(hi_z, c.z)
	var lid_h := mm(hi_y - lo_y)
	var W := mm(hi_x - lo_x)
	var D := mm(hi_z - lo_z)
	var box_top := -INF
	for f in faces:
		if int(f["body"]) == box:
			box_top = maxf(box_top, float(f["c"].y))
	var total_top := mm(float(s1["aabb"].end.y))
	# N2 the lid is 8 mm tall
	ok(nb == 2 and absf(lid_h - 8.0) <= 0.2,
		"N2 the lid is 8 mm tall (5 plate + 3 lip): %.2f mm" % lid_h)
	# N3 the box top is 5 mm under the lid's top
	ok(nb == 2 and absf(mm(box_top) - (total_top - 5.0)) <= 0.2,
		"N3 the box top is 5 mm under the lid's top: box top %.2f, lid top %.2f mm" % [mm(box_top), total_top])
	# N4 the lid volume = plate + lip ring
	var lid_v := 0.0
	var box_v := 0.0
	if nb == 2:
		lid_v = float(s1["volumes"][lid]) / (Part.MM * Part.MM * Part.MM)
		box_v = float(s1["volumes"][box]) / (Part.MM * Part.MM * Part.MM)
	var ring := (W - 6.4) * (D - 6.4) - (W - 8.4) * (D - 8.4)
	var want_v := W * D * 5.0 + 3.0 * ring
	ok(nb == 2 and absf(lid_v - want_v) <= 0.03 * want_v,
		"N4 the lid volume %.0f mm3 = plate + lip ring %.0f mm3 (within 3 pct; footprint %.2f x %.2f mm)" % [lid_v, want_v, W, D])
	# N5 the lip sits inside the box
	var inside := true
	var n_lip := 0
	var cx := (lo_x + hi_x) * 0.5
	var cz := (lo_z + hi_z) * 0.5
	for f in faces:
		if int(f["body"]) != lid:
			continue
		var c: Vector3 = f["c"]
		if c.y < box_top - 0.0005:
			n_lip += 1
			if mm(absf(c.x - cx)) > W * 0.5 - 2.5 or mm(absf(c.z - cz)) > D * 0.5 - 2.5:
				inside = false
	ok(nb == 2 and n_lip > 0 and inside, "N5 the lip sits inside the box: %d lip faces, all 2.5 mm in from the outside" % n_lip)
	# N6 the box is hollow
	var solid_box_v := W * D * (mm(box_top) - mm(float(s1["aabb"].position.y)))
	ok(nb == 2 and box_v < 0.6 * solid_box_v,
		"N6 the box is hollow: %.0f mm3 of %.0f solid (under 60 pct)" % [box_v, solid_box_v])

	# N7 one undo step back to one body
	var ub7: int = m.undo.size()
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.physical_keycode = KEY_Z
	k.key_label = KEY_Z
	k.pressed = true
	k.ctrl_pressed = true
	root.push_input(k, true)
	await idle(20)
	var s7 := solid()
	ok(int(s7["bodies"]) == 1 and m.undo.size() == ub7 - 1 and ub7 == ub_chip + 1,
		"N7 the lid chip is one undo step, Ctrl+Z goes back to one body (%d bodies, undo %d -> %d -> %d)" % [int(s7["bodies"]), ub_chip, ub7, m.undo.size()])

	# N8 the words
	var words := lid_words
	var jargon := ["sketch", "extrude", "shell", "split", "boolean", "feature", "loft", "kernel"]
	var bad := ""
	for j in jargon:
		if words.find(j) >= 0:
			bad = j
	ok(bad == "" and words.find("lid") >= 0, "N8 the words name the lid in plain words, no jargon (%s)" % bad)
	said.append(say_now(ep))

	print("NLID %d fails" % fails)
	quit(1 if fails > 0 else 0)
