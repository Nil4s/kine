extends SceneTree
## p118fingerjoin (Friday plan item 118: Finger joints for laser-cut boxes): a beginner from the BUILDING card with real clicks at 1280 x 720:
## Draw shape + Box chip + drag a box + Pull it up, then Cut a hole > Finger joints. The box gets a comb of notches along its top edge.
## Every number is measured from the BUILT result (Part.replay with faces and props), never from the code's own variables.
## The finger rule (3 mm, a notch a third of the height deep) is the one the beginner is told; the notch count is read back from the volume.
##   F0 the BUILDING card, one click; Easy; a box pulled up: one body
##   F1 Cut a hole shows the Finger joints chip; one press = one body, at most 2 clicks
##   F2 the notches are there: the volume taken out is n notches of 3 mm x a third of the height x the depth, n read back within 0.5
##   F3 the notch count is the comb's: n = floor(width / 6 mm) (within 1), and the box keeps its full height (the tabs reach the top)
##   F4 one undo step (Ctrl+Z) takes the chip back to the hole step before it: one body, the same volume as then
##   F5 the words say Finger joints and notch in plain words, no kernel jargon
## shots: C:/Temp/claude/p118fingerjoin/notch.png
const SHOT := "C:/Temp/claude/p118fingerjoin"
const DIRT := "user://p118fingerjoin_test"
const FINGER := 3.0   # mm: the finger the beginner is told about (the rule under test)
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
		"F0a BUILDING card, one click, a blank part, words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 50.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# F0 the box: Draw shape, Box chip, drag a box on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	var v0 := float(s0["volume"])
	ok(int(s0["bodies"]) == 1 and mm(bb0.size.x) >= 24.0,
		"F0b the box: one body, %.1f x %.1f x %.1f mm" % [mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])
	said.append(say_now(ep))

	# F1 Cut a hole, then Finger joints
	var c1 := clicks
	var ub1: int = m.undo.size()
	await click_ctl(ep.make_btns["hole"])   # Cut a hole first cuts the default round hole; the chip then REPLACES that step (one undo step)
	var has_chip: bool = ep.hole_btns.has("fingers")
	var ub_hole: int = m.undo.size()
	var v_hole := float(solid()["volume"])
	if has_chip:
		await click_ctl(ep.hole_btns["fingers"])
	await idle(12)
	var s1 := solid()
	var n1 := clicks - c1
	var v1 := float(s1["volume"])
	var bb1: AABB = s1["aabb"]
	ok(has_chip and int(s1["bodies"]) == 1 and v1 < v0 - 1e-6 and n1 <= 2,
		"F1 Cut a hole, Finger joints: chip %s, %d body, volume %.0f -> %.0f mm3, %d clicks (<= 2)" % [has_chip, int(s1["bodies"]), v0 / pow(Part.MM, 3.0), v1 / pow(Part.MM, 3.0), n1])
	var f1_words := say_now(ep).to_lower()   # the words right after the chip press (F5 reads these)
	said.append(say_now(ep))
	await shot("notch")

	# F2 the notch count, read back from the volume taken out: each notch is 3 mm wide, a third of the height deep, through the depth
	var W := mm(bb1.size.x)
	var H := mm(bb1.size.y)
	var Dz := mm(bb1.size.z)
	var notch_v := FINGER * (H / 3.0) * Dz
	var n_meas := (v0 - v1) / Part.MM / Part.MM / Part.MM / notch_v
	var n_want := floorf(W / (2.0 * FINGER))
	ok(absf(n_meas - n_want) <= 0.5 and n_want >= 2.0,
		"F2 the notches: %.2f read back from the volume, %d expected for %.1f mm wide" % [n_meas, int(n_want), W])

	# F3 the tabs keep the full height: the top of the box did not move
	var top_same := absf(mm(bb1.end.y) - mm(bb0.end.y)) <= 0.2
	ok(top_same and int(s1["bodies"]) == 1,
		"F3 the tabs reach the top: box top %.2f mm before, %.2f mm after" % [mm(bb0.end.y), mm(bb1.end.y)])

	# F4 one undo step takes the chip back: the notches go, and the round hole that Cut a hole made is back (the step before the chip)
	var ub4: int = m.undo.size()
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.physical_keycode = KEY_Z
	k.key_label = KEY_Z
	k.pressed = true
	k.ctrl_pressed = true
	root.push_input(k, true)
	await idle(20)
	var s4 := solid()
	var v4 := float(s4["volume"])
	ok(int(s4["bodies"]) == 1 and absf(v4 - v_hole) <= 1e-6 * maxf(v_hole, 1.0) and m.undo.size() == ub4 - 1 and ub4 == ub_hole + 1,
		"F4 one undo step takes the chip back: volume %.0f (the hole step %.0f), undo %d -> %d -> %d" % [v4 / pow(Part.MM, 3.0), v_hole / pow(Part.MM, 3.0), ub_hole, ub4, m.undo.size()])

	# F5 the words
	var words := f1_words
	var jargon := ["sketch", "extrude", "shell", "split", "boolean", "feature", "kernel"]
	var bad := ""
	for j in jargon:
		if words.find(j) >= 0:
			bad = j
	ok(bad == "" and words.find("finger") >= 0 and words.find("notch") >= 0,
		"F5 the words name the finger joints and notches in plain words, no jargon (%s)" % bad)
	said.append(say_now(ep))

	print("P118FINGERJOIN %d fails" % fails)
	quit(1 if fails > 0 else 0)
