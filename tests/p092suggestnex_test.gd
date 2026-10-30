extends SceneTree
## P092SUGGESTNEX (Friday plan item 92: "Suggest next step chips after each action", after Pull it up: "Round the edges?", "Hollow it?"):
## a beginner on the BUILDING card makes a box (Draw shape, Box, drag, Pull it up). Two chips show under the new solid. One click on
## "Round the edges?" rounds its edges (one undo step). Undo, then one click on "Hollow it?" hollows it out open at the top with a 3 mm
## wall (one undo step). Every number is measured from the BUILT result (Part.replay with faces), never from the code's variables.
##   S0 the BUILDING card, one click; Easy; a box pulled up (one body, 12 mm or more square)
##   S1 both chips are there after Pull it up, plain words, not greyed: "Round the edges?" and "Hollow it?"
##   S2 one click on "Round the edges?" (<= 1 click): newest step is a round, one body, curved faces on the built solid (>= 4)
##   S3 one undo step (Ctrl+Z) takes the round off: no curved faces, undo count -1
##   S4 one click on "Hollow it?" (<= 1 click) after the undo: newest step is a shell, one body
##   S5 the hollow is open at the top: its cavity floor is within 10 pct of (box - 2 x 3 mm) square, and no flat top covers the footprint
##   S6 the floor sits 3 mm (within 0.5 mm) above the bottom: the hollow's bottom wall is the 3 mm wall
##   S7 one undo step takes the hollow off: newest step is no longer a shell, undo count -1
##   S8 the chips' words are plain (no jargon)
## shots: C:/Temp/claude/p092suggestnex/*.png
const SHOT := "C:/Temp/claude/p092suggestnex"
const DIRT := "user://p092suggestnex_test"
const WALL_MM := 3.0
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


func mm2(v: float) -> float:
	return v / (Part.MM * Part.MM)


## the newest step's kind ("" = none)
func newest() -> String:
	var feats: Array = m.S.part.get("features", [])
	return String(feats[feats.size() - 1].get("t", "")) if not feats.is_empty() else ""


## faces of body 0 whose normal is not along an axis: the rounded edges of a solid
func curved(s: Dictionary) -> int:
	var n := 0
	for f in s.get("faces", []):
		var nn: Vector3 = f["n"]
		if int(f["body"]) == 0 and maxf(absf(nn.x), maxf(absf(nn.y), absf(nn.z))) < 0.95:
			n += 1
	return n


func press_ctrl_z() -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.physical_keycode = KEY_Z
	k.key_label = KEY_Z
	k.pressed = true
	k.ctrl_pressed = true
	root.push_input(k, true)
	await idle(20)


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
		"S0a BUILDING card, one click, a blank part, words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# S0b the box: Draw shape, Box chip, drag a 40 mm box on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	ok(int(s0["bodies"]) == 1 and mm(bb0.size.y) >= 12.0 and mm(bb0.size.x) >= 12.0,
		"S0b the box: one body, %.1f x %.1f x %.1f mm" % [mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])
	await shot("box")

	# S1 both chips after Pull it up: visible, plain words, not greyed
	var rbtn: Button = ep.tilt_box.find_child("easypart_suggest_round", true, false) as Button
	var hbtn: Button = ep.tilt_box.find_child("easypart_suggest_hollow", true, false) as Button
	var r_ok := rbtn != null and rbtn.is_visible_in_tree() and not rbtn.disabled and rbtn.text == "Round the edges?"
	var h_ok := hbtn != null and hbtn.is_visible_in_tree() and not hbtn.disabled and hbtn.text == "Hollow it?"
	ok(r_ok and h_ok, "S1 the chips are there after Pull it up: Round the edges? (%s), Hollow it? (%s)" % [r_ok, h_ok])
	said.append(say_now(ep))
	await shot("chips")

	# S2 one click on Round the edges?
	var c2 := clicks
	if r_ok:
		await click_ctl(rbtn)
	await idle(14)
	var s2 := solid()
	var n2 := clicks - c2
	var cu2 := curved(s2)
	ok(r_ok and newest() == "fillet" and int(s2["bodies"]) == 1 and cu2 >= 4 and n2 <= 1,
		"S2 one click on Round the edges?: newest step %s (want fillet), %d body, %d curved faces (>= 4), %d clicks" % [newest(), int(s2["bodies"]), cu2, n2])
	said.append(say_now(ep))
	await shot("rounded")

	# S3 one undo step takes the round off
	var ub3: int = m.undo.size()
	await press_ctrl_z()
	var s3 := solid()
	ok(int(s3["bodies"]) == 1 and curved(s3) == 0 and m.undo.size() == ub3 - 1,
		"S3 Ctrl+Z takes the round off: %d curved faces (want 0), undo %d -> %d" % [curved(s3), ub3, m.undo.size()])

	# S4 one click on Hollow it? (the chips are back after the undo)
	var hbtn2: Button = ep.tilt_box.find_child("easypart_suggest_hollow", true, false) as Button
	var h4 := hbtn2 != null and hbtn2.is_visible_in_tree() and not hbtn2.disabled
	var c4 := clicks
	if h4:
		await click_ctl(hbtn2)
	await idle(14)
	var s4 := solid()
	var n4 := clicks - c4
	ok(h4 and newest() == "shell" and int(s4["bodies"]) == 1 and n4 <= 1,
		"S4 one click on Hollow it?: newest step %s (want shell), %d body, %d clicks (<= 1)" % [newest(), int(s4["bodies"]), n4])
	said.append(say_now(ep))
	await shot("hollow")

	# S5 open at the top: the cavity floor is (box - 2 walls) square, and no flat top covers the whole footprint
	var bb5: AABB = s4["aabb"]
	var top_y := bb5.position.y + bb5.size.y
	var foot := mm(bb5.size.x) * mm(bb5.size.z)
	var inner := (mm(bb5.size.x) - 2.0 * WALL_MM) * (mm(bb5.size.z) - 2.0 * WALL_MM)
	var floor_a := -1.0
	var floor_y := 1.0e9
	var full_top := 0
	for f in s4.get("faces", []):
		if int(f["body"]) != 0:
			continue
		var ny := float((f["n"] as Vector3).y)
		if ny > 0.99 and float(f["c"].y) < top_y - 0.5 * Part.MM * 1.0 and float(f["c"].y) < floor_y:
			floor_y = float(f["c"].y)
			floor_a = mm2(float(f["area"]))
		if ny > 0.99 and mm2(float(f["area"])) >= 0.9 * foot:
			full_top += 1
	var floor_ok := floor_a > 0.0 and absf(floor_a - inner) <= 0.1 * inner
	ok(floor_ok and full_top == 0,
		"S5 open at the top: cavity floor %.1f mm2 (want %.1f mm2 = box less two 3 mm walls, within 10 pct), full flat tops %d (want 0)" % [floor_a, inner, full_top])

	# S6 the bottom wall is 3 mm: the floor sits 3 mm above the bottom
	var bottom_gap := mm(floor_y - bb5.position.y)
	ok(floor_a > 0.0 and absf(bottom_gap - WALL_MM) <= 0.5,
		"S6 the floor is %.2f mm above the bottom (want %.1f mm within 0.5)" % [bottom_gap, WALL_MM])
	await shot("hollow_side")

	# S7 one undo step takes the hollow off
	var ub7: int = m.undo.size()
	await press_ctrl_z()
	var s7 := solid()
	var nt7 := newest()
	ok(int(s7["bodies"]) == 1 and nt7 != "shell" and m.undo.size() == ub7 - 1,
		"S7 Ctrl+Z takes the hollow off: newest step %s (not shell), undo %d -> %d" % [nt7, ub7, m.undo.size()])

	# S8 the words
	var all_words := " | ".join(said).to_lower() + " | " + rbtn.text.to_lower() + " | " + hbtn.text.to_lower()
	var jargon := ["sketch", "extrude", "shell", "split", "boolean", "feature", "loft", "kernel", "taper", "fillet"]
	var bad := ""
	for j in jargon:
		if all_words.find(j) >= 0:
			bad = j
	ok(bad == "" and all_words.find("round the edges?") >= 0 and all_words.find("hollow it?") >= 0,
		"S8 the chips use plain words, no jargon (%s)" % bad)

	print("P092SUGGESTNEX %d fails" % fails)
	quit(1 if fails > 0 else 0)
