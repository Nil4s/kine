extends SceneTree
## P021DRAFTANGLE (Friday plan item 21: "Draft angle chip for moulded parts", "Easier to pull from a mould"): a beginner on the BUILDING card
## makes a box (Draw shape, Box, drag, Pull it up), then one click on the Draft angle chip: the four side walls lean 2 degrees in, the
## top and the bottom stay flat, one undo step takes it back. Every number is measured from the BUILT result (Part.replay with faces),
## never from the code's own variables.
##   D0 the BUILDING card, one click; Easy; a box pulled up (one body, 12 mm or more square)
##   D1 the Draft angle chip is there after Pull it up (visible, not greyed)
##   D2 one click on the chip (<= 1 click): one body, the newest step is a draft
##   D3 the four side walls lean: each outward normal is 1.5 to 2.5 degrees off upright (4 walls)
##   D4 the top is narrower than the bottom: the side inset is the height x tan(2 deg) within 10 pct (square footprint)
##   D5 the bottom face is still the full footprint (within 1 pct) and the top and bottom faces are flat (|n.y| > 0.99)
##   D6 one undo step (Ctrl+Z) takes the draft off: the walls are upright again (|n.y| < 0.001), undo count -1
##   D7 the words name the draft in plain words, no jargon
## shots: C:/Temp/claude/p021draftangle/*.png
const SHOT := "C:/Temp/claude/p021draftangle"
const DIRT := "user://p021draftangle_test"
const LO_DEG := 1.5
const HI_DEG := 2.5
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


## the side walls (upright, body 0): the faces whose normal is level (|n.y| under 0.9) and that are planar walls of the box
func walls(s: Dictionary, lean_lo: float, lean_hi: float) -> int:
	var n := 0
	for f in s.get("faces", []):
		var ny := absf(float((f["n"] as Vector3).y))
		if int(f["body"]) == 0 and ny >= lean_lo and ny <= lean_hi:
			n += 1
	return n


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
		"D0a BUILDING card, one click, a blank part, words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# D0b the box: Draw shape, Box chip, drag a box on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	ok(int(s0["bodies"]) == 1 and mm(bb0.size.y) >= 12.0 and mm(bb0.size.x) >= 12.0,
		"D0b the box: one body, %.1f x %.1f x %.1f mm" % [mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])
	await shot("box")

	# D1 the Draft angle chip is there, on, not greyed
	var dbtn: Button = ep.tilt_box.find_child("easypart_draft_angle", true, false) as Button
	var has_chip := dbtn != null and dbtn.is_visible_in_tree() and not dbtn.disabled
	ok(has_chip, "D1 the Draft angle chip is there after Pull it up (%s)" % has_chip)
	said.append(say_now(ep))
	await shot("chip")

	# D2 one click on the chip
	var c2 := clicks
	if has_chip:
		await click_ctl(dbtn)
	await idle(14)
	var s2 := solid()
	var n2 := clicks - c2
	var feats: Array = m.S.part.get("features", [])
	var last_t := String(feats[feats.size() - 1].get("t", "")) if not feats.is_empty() else ""
	ok(has_chip and int(s2["bodies"]) == 1 and last_t == "draft" and n2 <= 1,
		"D2 one click on Draft angle: %d body (want 1), newest step %s (want draft), %d clicks (<= 1)" % [int(s2["bodies"]), last_t, n2])
	said.append(say_now(ep))
	await shot("drafted")

	# D3 the four walls lean about 2 degrees off upright
	var lo := sin(deg_to_rad(LO_DEG))
	var hi := sin(deg_to_rad(HI_DEG))
	var nw := walls(s2, lo, hi)
	ok(nw == 4, "D3 the four side walls lean 1.5 to 2.5 degrees: %d of 4 walls" % nw)

	# D4 the top narrower than the bottom by the height x tan(2 deg)
	var top_a := -1.0
	var top_c := -1.0e9
	var bot_a := -1.0
	var bot_c := 1.0e9
	for f in s2.get("faces", []):
		if int(f["body"]) != 0:
			continue
		var ny := float((f["n"] as Vector3).y)
		if ny > 0.99 and float(f["c"].y) > top_c:
			top_c = float(f["c"].y)
			top_a = mm2(float(f["area"]))
		if ny < -0.99 and float(f["c"].y) < bot_c:
			bot_c = float(f["c"].y)
			bot_a = mm2(float(f["area"]))
	var bb2: AABB = s2["aabb"]
	var h := mm(bb2.size.y)
	var wb := sqrt(bot_a) if bot_a > 0.0 else 0.0
	var wt := sqrt(top_a) if top_a > 0.0 else 0.0
	var inset := (wb - wt) * 0.5
	var inset_want := h * tan(deg_to_rad(2.0))
	ok(top_a > 0.0 and bot_a > 0.0 and inset_want > 0.0 and absf(inset - inset_want) <= 0.1 * inset_want,
		"D4 the top is narrower: side inset %.3f mm (want %.3f mm = %.1f mm tall x tan 2 deg, within 10 pct)" % [inset, inset_want, h])

	# D5 the bottom face is the full footprint, both flat faces stay flat
	var foot := mm(bb2.size.x) * mm(bb2.size.z)
	var n_flat := 0
	for f in s2.get("faces", []):
		var ny := absf(float((f["n"] as Vector3).y))
		if int(f["body"]) == 0 and ny > 0.99:
			n_flat += 1
	ok(bot_a > 0.0 and absf(bot_a - foot) <= 0.01 * foot and n_flat == 2,
		"D5 the bottom is the full footprint (%.1f mm2 vs box %.1f mm2) and the top and bottom are flat (%d flat faces, want 2)" % [bot_a, foot, n_flat])
	await shot("drafted_side")

	# D6 one undo step takes the draft off: upright walls again
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
	var upright := walls(s6, 0.0, 0.001)
	ok(int(s6["bodies"]) == 1 and upright == 4 and m.undo.size() == ub6 - 1,
		"D6 Ctrl+Z takes the draft off: %d upright walls (want 4), undo %d -> %d" % [upright, ub6, m.undo.size()])

	# D7 the words
	var all_words := " | ".join(said).to_lower()
	var jargon := ["sketch", "extrude", "shell", "split", "boolean", "feature", "loft", "kernel", "taper"]
	var bad := ""
	for j in jargon:
		if all_words.find(j) >= 0:
			bad = j
	ok(bad == "" and all_words.find("draft") >= 0,
		"D7 the words name the draft in plain words, no jargon (%s)" % bad)

	print("P021DRAFTANGLE %d fails" % fails)
	quit(1 if fails > 0 else 0)
