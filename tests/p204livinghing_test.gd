extends SceneTree
## p204livinghing (Friday plan item 204: Living hinge pattern generator: a flexible plywood or plastic strip cut with slots, so it bends).
## A beginner from the BUILDING card (empty Easy Part) with real mouse clicks and drags only. Parts > Hinges has a "Living cuts" button;
## one click builds a plate 60 mm wide (the slots run across it and stop 10 mm short of its right edge: that spine keeps it in one piece).
## Sliders: Length (mm, 100..600, default 300), Slot spacing (mm, 4..20, default 8), Thickness (mm, 3..12, default 6).
## Slot i is 2 mm wide (the kerf) and starts at 10 + i x spacing mm; the count is floor((Length - 22) / spacing) + 1.
## Every number is measured from the BUILT mesh (vertices, mm), never from the record's own numbers:
##   the left edge's distinct heights (y) are 2 x slots + 2 (each slot opens the edge twice); pitch = the spacing between slot starts.
## Bars (written before the code; the ones marked FAILS ON OLD CODE fail on the code before this item, which has no Living cuts button):
##   0 CHIP     Parts > Hinges shows the Living cuts button                                                   (FAILS ON OLD CODE)
##   1 BUILD    one click: one solid, box 60 x 300 x 6 mm (+- 0.5; thickness +- 0.1)                         (FAILS ON OLD CODE)
##   2 SLOTS    default: 35 slots = 72 heights on the left edge (+- 0), pitch 8.0 mm (+- 0.1), kerf 2.0 (+- 0.1)  (FAILS ON OLD CODE)
##   3 SPACING  drag Slot spacing to 12 mm: 24 slots = 50 heights, pitch 12.0 (+- 0.1)                       (FAILS ON OLD CODE)
##   4 LENGTH   drag Length to 400 mm: 32 slots = 66 heights, box 60 x 400 mm (+- 0.5), still one solid       (FAILS ON OLD CODE)
##   5 THICK    drag Thickness to 4 mm: box thickness 4.0 (+- 0.1), still one solid                           (FAILS ON OLD CODE)
##   6 UNDO     the chip press is one undo step; each slider drag is one undo step (chip + 3 drags = 4)       (FAILS ON OLD CODE)
##   7 SAYS     every press says one plain line, with no key name in it, and names a next step
##   8 TEAR     slot spacing 4 mm with thickness 4 mm (spacing < 2 x thickness): the line says the slots may tear and names Slot spacing  (FAILS ON OLD CODE)
##   9 PARTS    Parts still opens its category page (Screws sizes show); Hinges still shows the Hinge button       (guard, passes on old code)
## Shots: C:/Temp/claude/p204livinghing/ (00_livecut.png, 01_spacing.png, 02_length.png, 03_tear.png)
const SHOT := "C:/Temp/claude/p204livinghing"
const DIRT := "user://p204livinghing_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
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


func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a slider knob position (screen px) for a value: the track runs between the centres of the two end grabbers
func knob_x(s: HSlider, v: float) -> Vector2:
	var r := s.get_global_rect()
	var t := (v - s.min_value) / maxf(s.max_value - s.min_value, 1e-6)
	return Vector2(r.position.x + 12.0 + t * (r.size.x - 24.0), r.get_center().y)


func slide_to(s: HSlider, v: float) -> void:
	var a := knob_x(s, s.value)
	await drag_screen(a, knob_x(s, v))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func note(press: String) -> void:
	words.append([press, pu().ep.msg])


func row_of(ep, key: String) -> Dictionary:
	for r in ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


## the built mesh's box in mm: [size_x, size_y, size_z]
func box_mm() -> Array:
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return []
	var sz := mesh.get_aabb().size * 1000.0
	return [sz.x, sz.y, sz.z]


## the built vertices in mm, as Vector3 (world frame of the part)
func verts_mm() -> Array:
	var out := []
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(Vector3(v) * 1000.0)
	return out


## the distinct heights (mm, from the plate's bottom, rounded to 0.01) of the vertices on the plate's left edge
func left_heights() -> Array:
	var vs := verts_mm()
	if vs.is_empty():
		return []
	var mnx := INF
	var mny := INF
	for v in vs:
		mnx = minf(mnx, v.x)
		mny = minf(mny, v.y)
	var seen := {}
	for v in vs:
		if absf(v.x - mnx) < 0.05:
			seen[snappedf(v.y - mny, 0.01)] = true
	var ys := seen.keys()
	ys.sort()
	return ys


## the slot pitch (mm) from the first two slot starts on the left edge: heights [0, s0, e0, s1, ...] -> s1 - s0
func pitch_mm(ys: Array) -> float:
	if ys.size() < 4:
		return -1.0
	return float(ys[3]) - float(ys[1])


func kerf_mm(ys: Array) -> float:
	if ys.size() < 3:
		return -1.0
	return float(ys[2]) - float(ys[1])


func undo_n() -> int:
	return m.undo.size()


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

	# the BUILDING card, one click: an empty Easy Part
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
	var ep = pu().ep

	# 0 CHIP: Parts > Hinges shows the Living cuts button
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_lib_Hinges", true, false) as Control)
	var cut_btn := root.find_child("easypart_livecut_pick", true, false) as Button
	ok(cut_btn != null and cut_btn.is_visible_in_tree(), "0 Parts > Hinges shows the Living cuts button")

	# 1 BUILD: one click; one solid, 60 x 300 x 6 mm
	var u0 := undo_n()
	await click_ctl(cut_btn)
	await idle(10)
	await shot("00_livecut")
	note("living cuts")
	var bx := box_mm()
	var bodies := int(pu().res.get("bodies", 0))
	var ys := left_heights()
	ok(bodies == 1 and bx.size() == 3 and absf(float(bx[0]) - 60.0) < 0.5 and absf(float(bx[1]) - 300.0) < 0.5 and absf(float(bx[2]) - 6.0) < 0.1,
		"1 one click: %d solid(s), box %s mm (want 60 x 300 x 6)" % [bodies, str(bx)])

	# 2 SLOTS: default spacing 8 mm: 35 slots = 72 heights on the left edge
	ok(ys.size() == 72 and absf(pitch_mm(ys) - 8.0) < 0.1 and absf(kerf_mm(ys) - 2.0) < 0.1,
		"2 default: %d heights on the left edge (want 72 = 35 slots), pitch %.2f mm (want 8.0), kerf %.2f mm (want 2.0)" % [ys.size(), pitch_mm(ys), kerf_mm(ys)])

	# 3 SPACING: drag Slot spacing to 12 mm: 24 slots = 50 heights
	var sg: HSlider = row_of(ep, "gap").get("slider")
	if sg != null:
		await slide_to(sg, 12.0)
	await idle(10)
	await shot("01_spacing")
	note("spacing")
	ys = left_heights()
	ok(ys.size() == 50 and absf(pitch_mm(ys) - 12.0) < 0.1,
		"3 spacing 12: %d heights (want 50 = 24 slots), pitch %.2f mm (want 12.0)" % [ys.size(), pitch_mm(ys)])

	# 4 LENGTH: drag Length to 400 mm: 32 slots = 66 heights, box 60 x 400, one solid
	var sl: HSlider = row_of(ep, "length").get("slider")
	if sl != null:
		await slide_to(sl, 400.0)
	await idle(10)
	await shot("02_length")
	note("length")
	bx = box_mm()
	bodies = int(pu().res.get("bodies", 0))
	ys = left_heights()
	ok(ys.size() == 66 and bodies == 1 and absf(float(bx[0]) - 60.0) < 0.5 and absf(float(bx[1]) - 400.0) < 0.5,
		"4 length 400: %d heights (want 66), %d solid, box %s mm (want 60 x 400)" % [ys.size(), bodies, str(bx)])

	# 5 THICK: drag Thickness to 4 mm
	var st: HSlider = row_of(ep, "thickness").get("slider")
	if st != null:
		await slide_to(st, 4.0)
	await idle(10)
	note("thickness")
	bx = box_mm()
	bodies = int(pu().res.get("bodies", 0))
	ok(bodies == 1 and bx.size() == 3 and absf(float(bx[2]) - 4.0) < 0.1,
		"5 thickness 4: %d solid, box %s mm (want thickness 4.0)" % [bodies, str(bx)])

	# 6 UNDO: the chip press + 3 drags = 4 steps
	var u1 := undo_n()
	ok(u1 - u0 == 4, "6 one undo step per action: chip + 3 drags = %d steps (want 4)" % [u1 - u0])

	# 7 SAYS: every press says one plain line, no key name, a next step
	var words_ok := true
	for w in words:
		var t := String(w[1]).to_lower()
		if t.strip_edges() == "":
			words_ok = false
		for b in BAD_WORDS:
			if t.contains(b):
				words_ok = false
	ok(words_ok and words.size() == 4, "7 %d presses, each says a plain line with no key name: %s" % [words.size(), str(words)])

	# 8 TEAR: spacing 4 mm with thickness 4 mm (4 < 2 x 4): the line says the slots may tear and names Slot spacing
	if sg != null:
		await slide_to(sg, 4.0)
	await idle(10)
	await shot("03_tear")
	note("tear")
	var tear_msg := String(pu().ep.msg).to_lower()
	ok(tear_msg.contains("tear") and tear_msg.contains("slot spacing"),
		"8 spacing 4 with thickness 4: the line says it may tear and names Slot spacing: '%s'" % tear_msg)

	# 9 PARTS guard: Parts still opens the Screws sizes; Hinges still shows the Hinge button
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	var scr_shown := root.find_child("easypart_screw_box", true, false) as Control
	var scr_ok := scr_shown != null and scr_shown.is_visible_in_tree()
	await click_ctl(root.find_child("easypart_lib_Hinges", true, false) as Button)
	var hp := root.find_child("easypart_hinge_pick", true, false) as Button
	var cp := root.find_child("easypart_livecut_pick", true, false) as Button
	ok(scr_ok and hp != null and hp.is_visible_in_tree() and cp != null and cp.is_visible_in_tree(),
		"9 Parts still opens its page (Screws sizes show: %s); Hinges shows the Hinge and Living cuts buttons" % str(scr_ok))
	print("p204livinghing: %d fail(s)" % fails)
	quit(0 if fails == 0 else 1)
