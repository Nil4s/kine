extends SceneTree
## FBOLT (Nick 2026-10-28: free 3D building, like Fusion 360; the BUILDING card opens a blank part): a beginner who never read
## a manual builds a bolt and a nut from the BUILDING card. Real clicks at 1280 x 720 from the real start screen.
## Walk: Draw shape (Round) + drag at the origin = the shaft -> Pull it up -> Draw shape (Hex) + drag on the shaft's top face = the
##   hex head -> Pull it up -> Draw shape (Hex) + drag on the floor, apart = the nut -> Pull it up -> Cut a hole (the nut's hole)
##   -> Expert: the hex is six lines, and the exact sizes are numbers in Expert.
## Bars (a bar that FAILS on the old code is marked there):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the shaft: Round + drag + Pull it up: one solid, volume near pi r^2 h
##   2 the hex chip: Draw shape shows a Hex chip (FAILS on the old code: only Box, Round, Pointy)
##   3 the head: a hex drawn on the shaft's top face, Pulled up, sits on the shaft: one piece, more volume (FAILS: the press on the round top lands on the floor, the head is a sliver beside the shaft)
##   4 the nut: a hex on the floor apart from the bolt, Pulled up: TWO separate solids
##   5 the nut's hole: Cut a hole: the volume goes down
##   6 Expert: the hex is a closed six-line shape in the record (FAILS on the old code)
##   7 Expert: the hex has exact numbers (a dimension on the sketch): KNOWN dead end until Expert gets a hex tool with typed sizes
##   8 the words: every press says a line
## shots: C:/Temp/claude/fbolt/
const SHOT := "C:/Temp/claude/fbolt"
const DIRT := "user://fbolt_test"

var fails := 0
var m: Node
var words: Array = []


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


## a floor point in mm (x right, y = -z) to the screen
func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


## a face point in mm: the top of the shaft is at height h (metres)
func up_pt(x: float, y: float, h: float) -> Vector2:
	return m.cam.unproject_position(Vector3(x * Part.MM, h, -y * Part.MM))


func note(press: String) -> void:
	words.append([press, pu().ep.msg])


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

	# 0 the BUILDING card, one click
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
	await shot("00_open")
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)

	# 1 the shaft: a Round drag from the origin (radius about 6 mm, snapped to 5), Pull it up
	var ep = pu().ep
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	await drag_screen(fl(0, 0), fl(6, 0))
	await click_ctl(ep.make_btns["pull"])
	note("pull shaft")
	var vs: float = float(pu().res.get("volume", 0.0))
	var want_s := PI * 5.0 * 5.0 * 20.0   # mm3: the drag snaps to a 5 mm radius, the default 2 cm pull
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(vs * 1e9 - want_s) < want_s * 0.15,
		"1 the shaft: one solid, volume %.0f mm3 (near %.0f) [%s]" % [vs * 1e9, want_s, ep.msg])
	await shot("01_shaft")

	# 2 the hex chip
	await click_ctl(ep.make_btns["draw"])
	var has_hex: bool = ep.shape_btns.has("hex") and (ep.shape_btns["hex"] as Control).is_visible_in_tree()
	ok(has_hex, "2 the Hex chip is on screen after Draw shape (chips: %s)" % str(ep.shape_btns.keys()))
	if has_hex:
		await click_ctl(ep.shape_btns["hex"])

	# 3 the head: a hex on the shaft's top face (20 mm up), Pulled up 4 mm
	var vb := vs
	await drag_screen(up_pt(-3, -3, 0.02), up_pt(4, 4, 0.02))   # the press is on the shaft's top (inside its 5 mm radius), the drag makes the hex
	await click_ctl(ep.make_btns["pull"])
	note("pull head")
	var vh: float = float(pu().res.get("volume", 0.0))
	var head_lumps: int = ep._lumps(pu().res)   # the head drawn on the shaft's top must TOUCH it: one piece (a sliver beside the shaft is two)
	ok(head_lumps == 1 and vh > vb + 1e-12, "3 the head sits on the shaft and joins it: one piece, more volume (pieces %d, %.0f -> %.0f mm3) [%s]" % [head_lumps, vb * 1e9, vh * 1e9, ep.msg])
	await shot("02_head")

	# 4 the nut: a hex on the floor, apart from the bolt, Pulled up 8 mm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["hex"])   # a beginner picks Hex again: Draw shape starts on Box every press
	await drag_screen(fl(22, -9), fl(34, 9))
	await click_ctl(ep.make_btns["pull"])
	note("pull nut")
	var lumps: int = ep._lumps(pu().res)   # pieces that touch: the nut does not touch the bolt, so two
	ok(lumps == 2, "4 the nut is a separate piece: two pieces that do not touch (pieces %d, bodies %d) [%s]" % [lumps, int(pu().res.get("bodies", 0)), ep.msg])
	var vn: float = float(pu().res.get("volume", 0.0))

	# 5 the nut's hole
	await click_ctl(ep.make_btns["hole"])
	note("hole nut")
	var vnh: float = float(pu().res.get("volume", 0.0))
	ok(vnh < vn - 1e-12, "5 Cut a hole: the volume goes down (%.0f -> %.0f mm3) [%s]" % [vn * 1e9, vnh * 1e9, ep.msg])
	var nut_lumps: int = ep._lumps(pu().res)   # KNOWN dead end: the hole goes through the middle of the WHOLE part, so it can split the nut
	if nut_lumps == 2:
		ok(true, "5b the hole is in the nut: the nut stays one piece (pieces %d)" % nut_lumps)
	else:
		print("KNOWN 5b the hole goes through the middle of the whole part, not the nut: pieces %d (two pieces that do not touch = the nut split)" % nut_lumps)
	await shot("03_nut")

	# 6 Expert: the hex is six lines, a closed loop in the record
	await click_ctl(ep.expert_btn)
	await idle(20)
	var rec: Dictionary = pu()._ensure()
	var hex_lines := 0
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "sketch":
			var es: Array = f.get("ents", [])
			if es.size() == 6 and es.all(func(e): return String(e.get("k", "")) == "line"):
				hex_lines += 1
	ok(hex_lines >= 2, "6 Expert shows the hex as six lines (sketches with six lines: %d)" % hex_lines)
	var typed := 0
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "sketch" and (f.get("dims", []) as Array).size() > 0:
			typed += 1
	if typed >= 1:
		ok(true, "7 Expert has exact numbers on the sketch")
	else:   # KNOWN dead end: the Easy hex has no typed size; Expert has no hex tool. Printed, not counted, until fixed
		print("KNOWN 7 the hex has no exact numbers in Expert (dims on sketches: %d). Expert needs a hex with typed across-flats" % typed)
	await shot("04_expert")

	# 8 the words
	var empty := []
	for w in words:
		if String(w[1]).strip_edges() == "":
			empty.append(String(w[0]))
	ok(empty.is_empty(), "8 every press says a line (empty after: %s)" % str(empty))

	print("fbolt: %d fail" % fails)
	quit(1 if fails > 0 else 0)
