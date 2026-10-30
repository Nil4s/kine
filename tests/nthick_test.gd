extends SceneTree
## NTHICK (Friday plan item 17; Nick: monkey-brain easy): a Thickness slider on a flat piece, from a thin plate to a thick block, that changes the
## thickness without redrawing the shape. Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: Draw shape (Round) -> drag an 120 x 100 mm box on the floor -> Pull it up (a flat plate) -> the slider reads Thickness with the words
##   Thin plate / Thick block -> a click on the track at its middle -> a drag to the thin end -> a drag to the thick end -> Ctrl+Z
## Bars (each one measured from the BUILT result in mm, never from the code's own variables, except the slider's own range and reading):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the newest step's slider is labelled Thickness, with the words Thin plate and Thick block (FAILS on the old code: it says How far)
##   2 the plate Pulled up stands 20 mm tall (its built height, aabb, mm)
##   3 a click on the Thickness track at its middle: the built height is the slider's middle in mm (+-2 mm)
##   4 that click adds exactly ONE undo step, and the sketch keeps its 4 corners (no redraw)
##   5 the plate's volume = its footprint area (shoelace over the sketch's corners, mm2) x its built height, within 3 %
##   6 a drag to the thin end: a thin plate, built height 2 mm (+-0.5 mm), ONE undo step, the sketch unchanged
##   7 a drag to the thick end: the built height is the block's 400 mm (+-2 mm), ONE undo step
##   8 Ctrl+Z takes the last drag back: the built height is the thin plate's 2 mm again, one step fewer
##   9 the words: the press that moved the Thickness says a line (non-empty msg)
## shots: C:/Temp/claude/nthick/
const SHOT_DIR := "C:/Temp/claude/nthick"
const DIRT := "user://nthick_test"

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
	await click_at(p)


func click_at(p: Vector2) -> void:
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
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## a floor point in mm (x right, y = -z) to the screen
func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the newest sketch of the record: its sides as [a, b] pairs in mm, or [] when it is not all straight lines
func sketch_sides(rec: Dictionary) -> Array:
	var last: Dictionary = {}
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "sketch":
			last = f
	var out := []
	for e in last.get("ents", []):
		if String(e.get("k", "")) == "rect":   # a Draw shape box is one rect: its four corners, as four sides
			var a := Vector2(e["a"][0], e["a"][1])
			var b := Vector2(e["b"][0], e["b"][1])
			var c := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
			for i in 4:
				out.append([c[i], c[(i + 1) % 4]])
		elif String(e.get("k", "")) == "line":
			out.append([Vector2(e["a"][0], e["a"][1]), Vector2(e["b"][0], e["b"][1])])
		else:
			return []
	return out


func shoelace(sides: Array) -> float:
	var s := 0.0
	for sd in sides:
		var p: Vector2 = sd[0]
		var q: Vector2 = sd[1]
		s += p.x * q.y - q.x * p.y
	return absf(s) * 0.5


## the built height in mm (the solid's bounding box, Y)
func built_h_mm() -> float:
	return (pu().res.get("aabb", AABB()) as AABB).size.y / Part.MM


## the newest step's slider, and whether its label and both words are on it
func thick_row() -> Array:
	var sl := find_named(m, "easypart_slider_last") as HSlider
	if sl == null:
		return [null, false]
	var box := sl.get_parent()
	var lbl := false
	for c in box.find_children("*", "Label", true, false):
		if String((c as Label).text) == "Thickness":
			lbl = true
	var words := find_named(box, "easypart_words_last")
	var w_ok := false
	if words != null:
		var txt := []
		for c in words.get_children():
			txt.append(String((c as Label).text))
		w_ok = "Thin plate" in txt and "Thick block" in txt
	return [sl, lbl and w_ok]


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(4)


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
	var ep = pu().ep

	# 1 a flat plate: Draw shape, an 120 x 100 mm box on the floor, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(fl(-60, -50), fl(60, 50))
	await click_ctl(ep.make_btns["pull"])
	var rec: Dictionary = pu()._ensure()
	var sk := sketch_sides(rec)
	var h0 := built_h_mm()
	var tr: Array = thick_row()
	var sl: HSlider = tr[0]
	ok(sl != null and bool(tr[1]), "1 the newest step's slider is labelled Thickness, words Thin plate / Thick block (slider %s)" % ("none" if sl == null else "found"))
	await shot("01_plate")

	# 2 the plate stands 20 mm tall
	ok(absf(h0 - 20.0) <= 0.5 and sk.size() == 4 and int(pu().res.get("bodies", 0)) == 1,
		"2 the plate Pulled up stands 20 mm tall (built %.1f mm, sides %d)" % [h0, sk.size()])

	# 3 a click on the Thickness track at its middle: the built height = the slider's middle in mm
	var ua: int = m.undo.size()
	var mid_mm := 0.0
	if sl != null:
		var gw := _grab_w(sl)
		var r := sl.get_global_rect()
		var f := 0.5
		await click_at(Vector2(r.position.x + gw * 0.5 + (r.size.x - gw) * f, r.get_center().y))
		mid_mm = (sl.min_value + f * (sl.max_value - sl.min_value)) * 10.0
	var h1 := built_h_mm()
	ok(sl != null and absf(h1 - mid_mm) <= 2.0 and mid_mm > 100.0,
		"3 a click at the middle of the Thickness track: the built plate is %.1f mm (the middle of the range = %.1f mm)" % [h1, mid_mm])

	# 4 that click: one undo step, and the same 4 corners (no redraw)
	var sk1 := sketch_sides(pu()._ensure())
	ok(m.undo.size() == ua + 1 and sk1 == sk,
		"4 the click adds ONE undo step and does not redraw the shape (undo %d -> %d, corners same %s)" % [ua, m.undo.size(), str(sk1 == sk)])

	# 5 the volume: footprint area x built height, in mm3
	var vol: float = float(pu().res.get("volume", 0.0)) * 1e9
	var want := shoelace(sk1) * h1
	ok(want > 0.0 and absf(vol - want) <= want * 0.03,
		"5 the plate's volume %.0f mm3 = footprint %.0f mm2 x built height %.1f mm = %.0f mm3 (within 3 pct)" % [vol, shoelace(sk1), h1, want])

	# 6 a drag to the thin end: a thin plate, 2 mm, ONE undo step, same corners
	var ub: int = m.undo.size()
	if sl != null:
		var gw2 := _grab_w(sl)
		var r2 := sl.get_global_rect()
		var cx := r2.position.x + gw2 * 0.5 + (r2.size.x - gw2) * 0.5
		await drag_screen(Vector2(cx, r2.get_center().y), Vector2(r2.position.x - 40.0, r2.get_center().y))
	var h2 := built_h_mm()
	var sk2 := sketch_sides(pu()._ensure())
	ok(absf(h2 - 2.0) <= 0.5 and m.undo.size() == ub + 1 and sk2 == sk,
		"6 a drag to the thin end: a thin plate of %.1f mm (2 mm), ONE undo step (undo %d -> %d), corners same %s" % [h2, ub, m.undo.size(), str(sk2 == sk)])
	await shot("02_thin")

	# 7 a drag to the thick end: a block of 400 mm
	var uc: int = m.undo.size()
	if sl != null:
		var r3 := sl.get_global_rect()
		var gw3 := _grab_w(sl)
		var cx3 := r3.position.x + gw3 * 0.5
		await drag_screen(Vector2(cx3, r3.get_center().y), Vector2(r3.end.x + 40.0, r3.get_center().y))
	var h3 := built_h_mm()
	var msg7 := String(ep.msg)
	ok(absf(h3 - 400.0) <= 2.0 and m.undo.size() == uc + 1,
		"7 a drag to the thick end: a thick block of %.1f mm (400 mm), ONE undo step (undo %d -> %d)" % [h3, uc, m.undo.size()])
	await shot("03_thick")

	# 9 the words: the press that moved the Thickness says a line (read right after that drag)
	ok(msg7 != "", "9 the press that moved the Thickness says a line in words (%s)" % msg7)

	# 8 Ctrl+Z takes the last drag back
	await ctrl_z()
	var h4 := built_h_mm()
	ok(absf(h4 - h2) <= 0.5 and m.undo.size() == uc,
		"8 Ctrl+Z takes the last drag back: the plate is %.1f mm again, one step fewer (undo %d -> %d)" % [h4, uc + 1, m.undo.size()])

	await shot("04_undone")

	print("NTHICK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0
