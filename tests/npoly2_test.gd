extends SceneTree
## NPOLY2 (Friday plan item 41; Nick: monkey-brain easy): a beginner makes a regular prism with a Sides slider from the BUILDING card.
## Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: Draw shape (Round) -> the Hex chip, and next to it a Sides slider (3 to 12) -> drag the slider to 5 -> Draw shape + drag on the
##   floor = a 5-sided shape -> Pull it up -> Draw shape + slider to 12 + drag apart on the floor -> Pull it up -> Ctrl+Z (the 12-gon goes)
## Bars (each one measured from the BUILT result in mm, never from the code's own variables, except the slider's own reading):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the Sides slider is on screen next to the Hex chip, labelled Sides in words, range 3 to 12 (FAILS on the old code: no slider)
##   2 the slider moved by a real click to 5 reads 5; the move adds NO undo step (FAILS on the old code: no slider)
##   3 a 5-sided shape drawn on the floor and Pulled up: ONE solid, its sketch is 5 straight closed sides, all equal (+-2 %) (FAILS on the old code)
##   4 the prism: volume = the 5-sided area (shoelace over the sketch's corners, mm2) x the height (mm), within 3 % (FAILS on the old code)
##   5 Draw shape and Pull it up add exactly 2 undo steps (FAILS on the old code)
##   6 the slider to 12 by a real click: a 12-sided sketch, all sides equal (+-2 %), Pulled up, two solids in all (FAILS on the old code)
##   7 Ctrl+Z (one step) takes the 12-sided Pull away: one solid, one step fewer, the 5-sided volume (FAILS on the old code)
##   8 the words: the press that Pulled the 12-sided prism says a line (non-empty msg)
## shots: C:/Temp/claude/npoly2/
const SHOT_DIR := "C:/Temp/claude/npoly2"
const DIRT := "user://npoly2_test"

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
		if String(e.get("k", "")) != "line":
			return []
		out.append([Vector2(e["a"][0], e["a"][1]), Vector2(e["b"][0], e["b"][1])])
	return out


func shoelace(sides: Array) -> float:
	var s := 0.0
	for sd in sides:
		var p: Vector2 = sd[0]
		var q: Vector2 = sd[1]
		s += p.x * q.y - q.x * p.y
	return absf(s) * 0.5


## the longest over the shortest side (1.0 = all sides equal)
func side_ratio(sides: Array) -> float:
	var lo := INF
	var hi := 0.0
	for sd in sides:
		var l: float = (sd[0] as Vector2).distance_to(sd[1])
		lo = minf(lo, l)
		hi = maxf(hi, l)
	return hi / lo if lo > 0.0 else INF


## each corner is the next side's start
func closed(sides: Array) -> bool:
	if sides.is_empty():
		return false
	for i in sides.size():
		if (sides[i][1] as Vector2).distance_to(sides[(i + 1) % sides.size()][0]) > 0.01:
			return false
	return true


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

	# 1 Draw shape: the Sides slider sits next to the Hex chip, labelled in words
	await click_ctl(ep.make_btns["draw"])
	var sl: HSlider = find_named(ep.shape_box, "easypart_sides") as HSlider
	var hex_btn: Control = ep.shape_btns.get("hex") as Control
	var beside_hex := sl != null and sl.is_visible_in_tree() and hex_btn != null and sl.get_global_rect().position.x >= hex_btn.get_global_rect().end.x - 1.0
	var lbl_ok := false
	if sl != null:
		for c in sl.get_parent().get_children():
			if c is Label and String((c as Label).text).to_lower().contains("sides"):
				lbl_ok = true
	ok(beside_hex and lbl_ok and sl != null and sl.min_value == 3 and sl.max_value == 12,
		"1 a Sides slider (3 to 12) sits next to the Hex chip, labelled Sides in words (slider %s)" % ("none" if sl == null else "%s to %s" % [sl.min_value, sl.max_value]))
	await shot("01_sides")

	# 2 the slider by a real click at 5: the track fraction 2/9, the grabber's half kept clear
	var u_before_slide: int = m.undo.size()
	if sl != null:
		var gw := _grab_w(sl)
		var r := sl.get_global_rect()
		await click_at(Vector2(r.position.x + gw * 0.5 + (r.size.x - gw) * (2.0 / 9.0), r.get_center().y))
	var u_after_slide: int = m.undo.size()
	ok(sl != null and int(sl.value) == 5 and u_after_slide == u_before_slide,
		"2 the Sides slider clicked to 5 reads 5, and the move adds no undo step (reads %s, undo %d -> %d)" % [str(sl.value) if sl != null else "none", u_before_slide, u_after_slide])

	# 3 a 5-sided shape on the floor, Pulled up
	var u0: int = m.undo.size()
	await drag_screen(fl(-20, -20), fl(20, 20))
	await click_ctl(ep.make_btns["pull"])
	var rec: Dictionary = pu()._ensure()
	var s5 := sketch_sides(rec)
	var bodies5 := int(pu().res.get("bodies", 0))
	ok(s5.size() == 5 and closed(s5) and side_ratio(s5) <= 1.02 and bodies5 == 1,
		"3 a 5-sided shape Pulled up: one solid, five straight closed sides, equal (sides %d, ratio %.3f, solids %d) [%s]" % [s5.size(), side_ratio(s5), bodies5, ep.msg])
	await shot("02_five")

	# 4 the prism: volume = shoelace area x height, in mm
	var vol5: float = float(pu().res.get("volume", 0.0)) * 1e9
	var h5: float = (pu().res.get("aabb", AABB()) as AABB).size.y / Part.MM
	var want5 := shoelace(s5) * h5
	ok(s5.size() == 5 and want5 > 0.0 and absf(vol5 - want5) <= want5 * 0.03,
		"4 the prism's volume %.0f mm3 = its 5-sided area %.0f mm2 x height %.1f mm = %.0f mm3 (within 3 %%)" % [vol5, shoelace(s5), h5, want5])

	# 5 undo steps: Draw shape and Pull it up are one step each
	ok(m.undo.size() == u0 + 2, "5 Draw shape and Pull it up add exactly 2 undo steps (undo %d -> %d)" % [u0, m.undo.size()])

	# 6 the slider to 12 by a real click, a 12-sided prism drawn apart and Pulled up
	await click_ctl(ep.make_btns["draw"])
	sl = find_named(ep.shape_box, "easypart_sides") as HSlider
	if sl != null:
		var gw2 := _grab_w(sl)
		var r2 := sl.get_global_rect()
		await click_at(Vector2(r2.end.x - gw2 * 0.5, r2.get_center().y))
	await drag_screen(fl(50, -20), fl(70, 20))
	await click_ctl(ep.make_btns["pull"])
	rec = pu()._ensure()
	var s12 := sketch_sides(rec)
	var bodies12 := int(pu().res.get("bodies", 0))
	ok(s12.size() == 12 and closed(s12) and side_ratio(s12) <= 1.02 and bodies12 == 2,
		"6 the slider at 12: a 12-sided prism with equal sides, apart from the first (sides %d, ratio %.3f, solids %d) [%s]" % [s12.size(), side_ratio(s12), bodies12, ep.msg])
	await shot("03_twelve")

	# 8 the words: the press that made the 12-sided prism says a line (Undo clears the Easy sentence on purpose: it names the undo in the toast)
	ok(String(ep.msg) != "", "8 the press that Pulled the 12-sided prism says a line in words (%s)" % ep.msg)

	# 7 Ctrl+Z (one step) takes the 12-sided Pull away: one solid left at the 5-sided prism's volume, one step fewer
	var n_before := (rec.get("features", []) as Array).size()
	await ctrl_z()
	rec = pu()._ensure()
	var after := sketch_sides(rec)
	var vol_after: float = float(pu().res.get("volume", 0.0)) * 1e9
	var bodies_after := int(pu().res.get("bodies", 0))
	ok(bodies_after == 1 and absf(vol_after - vol5) <= vol5 * 0.01 and (rec.get("features", []) as Array).size() == n_before - 1,
		"7 Ctrl+Z takes the 12-sided Pull away (solids %d, volume %.0f mm3 near %.0f, steps %d -> %d)" % [bodies_after, vol_after, vol5, n_before, (rec.get("features", []) as Array).size()])
	await shot("04_undone")

	print("NPOLY2 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0
