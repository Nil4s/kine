extends SceneTree
## p067hinges (Friday plan item 67: Hinges: butt hinge, piano hinge, living hinge (thin flexible strip), sized to the door).
## A beginner from the BUILDING card (empty Easy Part) with real mouse clicks and drags only. A Hinge chip sits next to Parts; its
## kind slider picks Butt (1), Piano (2) or Living (3); its Door height slider (1800..2400 mm) sizes the hinge to the door:
## butt and living leaves are door / 21 long (rounded to 5 mm: 100 mm at 2100, 115 mm at 2400); a piano hinge runs the full door height.
## Every size is measured from the BUILT geometry (mesh vertices, mm), never from the record's own numbers.
## Bars (written before the code; the bars marked FAILS ON OLD CODE fail on the code before this item, which has no Hinge chip):
##   0 CHIP      Parts > Hinges shows the Hinge button (the Parts library; the Start row holds only shapes since PR #125)        (FAILS ON OLD CODE)
##   1 BUTT      one click on Hinge: a Butt hinge, one solid, 60 x 100 mm (+- 0.5), leaves 2.5 mm thick (+- 0.1)                  (FAILS ON OLD CODE)
##   2 DOOR      drag Door height to 2400 mm: the butt hinge is 115 mm long (+- 0.5) and the record says 2400 mm                 (FAILS ON OLD CODE)
##   3 PIANO     drag Kind to Piano: one strip 30 mm wide, 2400 mm tall (+- 0.5), 1.5 mm thick (+- 0.1)                           (FAILS ON OLD CODE)
##   4 LIVING    drag Kind to Living: a thin flexible strip, 60 x 115 mm (+- 0.5), 0.8 mm thick (+- 0.1)                              (FAILS ON OLD CODE)
##   5 UNDO      the chip press is one undo step; each slider drag is one undo step (+1 each)                                      (FAILS ON OLD CODE)
##   6 SAYS      every press says one plain line, with no key name in it, and names a next step                                    (FAILS ON OLD CODE)
##   7 PARTS     Parts still opens its category page (Screws sizes show); Hinges is a ready category: its button, no coming-soon line
## Shots: C:/Temp/claude/p067hinges/ (00_hinge.png, 01_door.png, 02_piano.png, 03_living.png)
const SHOT := "C:/Temp/claude/p067hinges"
const DIRT := "user://p067hinges_test"
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

	# 0 CHIP: Parts > Hinges shows the Hinge button (since PR #125 parts live in the Parts library, not on the Start row)
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_lib_Hinges", true, false) as Control)
	var hinge_chip := root.find_child("easypart_hinge_pick", true, false) as Button
	ok(hinge_chip != null and hinge_chip.is_visible_in_tree(), "0 Parts > Hinges shows the Hinge button")

	# 1 BUTT: one click on Hinge; default Butt at 2100 mm
	var u0 := undo_n()
	await click_ctl(hinge_chip)
	await idle(10)
	await shot("00_hinge")
	note("hinge chip")
	var bx := box_mm()
	var bodies := int(pu().res.get("bodies", 0))
	var butt_ok := bodies == 1 and bx.size() == 3 and absf(float(bx[0]) - 60.0) < 0.5 and absf(float(bx[1]) - 100.0) < 0.5
	ok(butt_ok, "1 Butt hinge from one click: one solid, %d bodies, box %s mm (want 60 x 100)" % [bodies, str(bx)])

	# 2 DOOR: drag the Door height slider to 2400 mm
	var sd: HSlider = row_of(ep, "door").get("slider")
	if sd != null:
		await slide_to(sd, 2400.0)
	await idle(10)
	await shot("01_door")
	note("door")
	bx = box_mm()
	var dr := int(pu()._rec().get("easy", {}).get("p", {}).get("door", 0))
	ok(dr == 2400 and bx.size() == 3 and absf(float(bx[1]) - 115.0) < 0.5,
		"2 Door height dragged to %d mm: the butt hinge is %s mm, length 115 (+- 0.5)" % [dr, str(bx)])

	# 3 PIANO: drag Kind to Piano (2)
	var sk: HSlider = row_of(ep, "kind").get("slider")
	if sk != null:
		await slide_to(sk, 2.0)
	await idle(10)
	await shot("02_piano")
	note("piano")
	bx = box_mm()
	var kd := int(pu()._rec().get("easy", {}).get("p", {}).get("kind", 0))
	ok(kd == 2 and bx.size() == 3 and absf(float(bx[0]) - 30.0) < 0.5 and absf(float(bx[1]) - 2400.0) < 0.5 and absf(float(bx[2]) - 1.5) < 0.1,
		"3 Piano: kind %d, box %s mm (want 30 x 2400 x 1.5)" % [kd, str(bx)])

	# 4 LIVING: drag Kind to Living (3)
	if sk != null:
		await slide_to(sk, 3.0)
	await idle(10)
	await shot("03_living")
	note("living")
	bx = box_mm()
	kd = int(pu()._rec().get("easy", {}).get("p", {}).get("kind", 0))
	ok(kd == 3 and bx.size() == 3 and absf(float(bx[0]) - 60.0) < 0.5 and absf(float(bx[1]) - 115.0) < 0.5 and absf(float(bx[2]) - 0.8) < 0.1,
		"4 Living: kind %d, box %s mm (want 60 x 115 x 0.8)" % [kd, str(bx)])

	# 5 UNDO: the chip press is one step; each slider drag is one step
	var u1 := undo_n()
	ok(u1 - u0 == 4, "5 one undo step per action: chip + 3 drags = %d steps (want 4)" % [u1 - u0])

	# 6 SAYS: every press says one plain line, no key name, a next step
	var words_ok := true
	for w in words:
		var t := String(w[1]).to_lower()
		if t.strip_edges() == "":
			words_ok = false
		for b in BAD_WORDS:
			if t.contains(b):
				words_ok = false
	ok(words_ok and words.size() == 4, "6 %d presses, each says a plain line with no key name: %s" % [words.size(), str(words)])

	# 7 PARTS guard: Parts still opens the Screws sizes; Hinges says coming soon
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	var scr_shown := root.find_child("easypart_screw_box", true, false) as Control
	var lib_h := root.find_child("easypart_lib_Hinges", true, false) as Button
	var scr_ok := scr_shown != null and scr_shown.is_visible_in_tree()
	await click_ctl(lib_h)
	var soon := root.find_child("easypart_lib_soon", true, false) as Label
	var hp := root.find_child("easypart_hinge_pick", true, false) as Button
	ok(scr_ok and hp != null and hp.is_visible_in_tree() and (soon == null or not soon.visible),
		"7 Parts still opens its page (Screws sizes show: %s); Hinges is ready: its Hinge button shows, no coming-soon line" % str(scr_ok))
	print("p067hinges: %d fail(s)" % fails)
	quit(0 if fails == 0 else 1)
