extends SceneTree
## P032SLOTASITSO (Friday plan item 32: "Slot (a long rounded hole) as its own shape chip"): a beginner on the BUILDING card opens Easy,
## one click on the Slot chip makes a plate with a long rounded hole cut right through it (one body, one undo step). A slider drag
## of Length stretches the hole and the plate with it (one undo step). Every number is measured from the BUILT result (pu.res: the
## bounding box and the volume), never from the code's own variables. The expected numbers below are written from the plain shape:
## plate = (Length + 40) x (Width + 40) x Thickness, hole = a stadium of Length x Width (straight part + two round ends), cut through.
##   S0 the BUILDING card, one click; Easy open (a blank part)
##   S1 the Slot chip is on the Easy panel (visible, not greyed)
##   S2 one click on Slot: one body, ONE undo step, the part is a slot (template "slot"), the words name it in plain words
##   S3 the built size: X and Z are the plate (160 x 60 mm at the default 120 x 20 mm hole, 1 mm), height is the thickness (8 mm, 0.5 mm)
##   S4 the volume is the plate less the hole, cut through (58.3 cm3 at the defaults, 2 pct): a blind hole would be more
##   S5 a real drag of the Length slider to 200 mm: ONE undo step, X grows to 240 mm (1 mm), volume matches the 200 mm slot (2 pct)
##   S6 the words in the panel and the hint say no jargon (sketch, extrude, arc, feature, boolean)
## shots: C:/Temp/claude/p032slotasitso/*.png
const SHOT := "C:/Temp/claude/p032slotasitso"
const DIRT := "user://p032slotasitso_test"
var fails := 0
var m: Node
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
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## a real press on the slider knob, a drag to value v through 24 mouse steps, a release
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Button:
		out.append((n as Button).text)
	if n is Label:
		out.append((n as Label).text)
	if n is Control:
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts(c, out)


## the built plate size (mm) and volume (cm3) from the replay's own bounding box and volume
func size_mm(pu) -> Vector3:
	var b: AABB = pu.res.get("aabb", AABB())
	return b.size / Part.MM


func vol_cm3(pu) -> float:
	return float(pu.res.get("volume", 0.0)) * 1e6


## the expected volume (cm3) of the slot at length L and width W, thickness T (mm): plate less a stadium hole cut through
func expect_cm3(L: float, W: float, T: float) -> float:
	var plate := (L + 40.0) * (W + 40.0) * T
	var stadium := (L - W) * W + PI * (W * 0.5) * (W * 0.5)
	return (plate - stadium * T) / 1000.0


## the screen y of the Empty chip (the title line), -1 when there is none
func empty_y(ep) -> float:
	if ep.empty_chip == null:
		return -1.0
	return (ep.empty_chip as Control).get_global_rect().position.y


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
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# S0 a blank part on Easy
	ok(m.cur_page == "BUILD" and pu.on and ep != null, "S0 BUILDING card, Easy open (page %s)" % m.cur_page)

	# S1 the Slot chip is on the panel, visible, not greyed
	var chip = ep.chips.get("slothole", null)
	ok(chip != null and (chip as Button).visible and not (chip as Button).disabled,
		"S1 the Slot chip is on the Easy panel, visible and not greyed (%s)" % ("missing" if chip == null else "there"))
	if chip == null:
		print("P032SLOTASITSO %d fails" % fails)
		quit(1)
		return

	# S1b the Slot chip sits on the title line beside Empty, so the chip row keeps its six-chip height (no second row under the grid)
	ok(chip != null and empty_y(ep) >= 0.0 and absf((chip as Control).get_global_rect().position.y - empty_y(ep)) <= 1.0,
		"S1b the Slot chip is on the title line, level with Empty")

	# S2 one click: one body, one undo step, a slot
	var ub: int = m.undo.size()
	await click_ctl(chip)
	var rec: Dictionary = m.S.part
	var easy: Dictionary = rec.get("easy", {})
	await shot("slot")
	ok(String(easy.get("t", "")) == "slothole" and int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub + 1 and (pu.res.get("errors", {}) as Dictionary).is_empty(),
		"S2 one click on Slot: one body, a slot, no failed step, ONE undo step (%d -> %d, bodies %d, template %s)" % [ub, m.undo.size(), int(pu.res.get("bodies", 0)), String(easy.get("t", ""))])

	# S3 the built size: X and Z are the plate, Y the thickness
	var sz := size_mm(pu)
	var d_def := expect_cm3(120.0, 20.0, 8.0)
	ok(absf(sz.x - 160.0) <= 1.0 and absf(sz.z - 60.0) <= 1.0 and absf(sz.y - 8.0) <= 0.5,
		"S3 the built plate: %.1f x %.1f x %.1f mm (160 x 60 x 8)" % [sz.x, sz.z, sz.y])

	# S4 the volume: the plate less the hole, cut through (blind would be more)
	var v0 := vol_cm3(pu)
	ok(absf(v0 - d_def) <= 0.02 * d_def,
		"S4 the volume is the plate less the hole: %.2f cm3 (expected %.2f, 2 pct)" % [v0, d_def])

	# S5 drag Length to 200 mm: one undo step, plate grows to 240 mm, volume matches
	# the template's sliders are in cm (the record keeps mm): Length 20 cm = 200 mm
	var len_s: HSlider = null
	for r in ep.rows:
		if String(r["key"]) == "length":
			len_s = r["slider"]
	var ub5: int = m.undo.size()
	if len_s != null:
		await drag_slider(len_s, 20.0)
	var sz5 := size_mm(pu)
	var v5 := vol_cm3(pu)
	var d_200 := expect_cm3(200.0, 20.0, 8.0)
	ok(len_s != null and absf(sz5.x - 240.0) <= 1.0 and absf(v5 - d_200) <= 0.02 * d_200 and m.undo.size() == ub5 + 1,
		"S5 Length to 200 mm: X %.1f mm (240), volume %.2f cm3 (expected %.2f), ONE undo step (%d -> %d)" % [sz5.x, v5, d_200, ub5, m.undo.size()])
	await shot("slot_long")

	# S6 the words, no jargon
	var out := []
	texts(ep, out)
	var all := " | ".join(out).to_lower() + " | " + String(ep.hint_l.text).to_lower() + " | " + String(ep.msg).to_lower()
	var bad := ""
	for j in ["sketch", "extrude", "arc", "feature", "boolean"]:
		if all.find(j) >= 0:
			bad = j
	ok(bad == "" and all.find("slot") >= 0, "S6 the words name the slot in plain words, no jargon (%s)" % bad)

	print("P032SLOTASITSO %d fails" % fails)
	quit(1 if fails > 0 else 0)
