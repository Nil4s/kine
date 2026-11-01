extends SceneTree
## godot --path . --position 4000,4000 -s tests/s023_test.gd   (FRIDAY PLAN 23 Pinch / Bulge a face + 109 Light / Dark for the Part page; needs the CAD DLL)
## Easy Part, real clicks at 1280 x 720. Every number is measured from the BUILT result (a vertical probe through the kernel mesh, the kernel volume) or from
## the colours the controls resolve to, never from the code's own variables.
##   23: a 40 x 40 x 20 box. Pinch / Bulge chip, click the top face: +0.5 raises the top centre by 0.2 x 40 x 0.5 = 4 mm (within 0.1), edges stay at 20 mm,
##       footprint stays 40 mm, one solid, volume grows (about 3200 mm3); slider -0.5 lowers it 4 mm, volume shrinks; slider 0 is the original exactly; one undo
##   109: Light / Dark in the "How many buttons?" popup: Light panel luminance > 0.7, every visible button's text contrast >= 4.5, the viewport pixels get lighter;
##       Dark is the original colours exactly after a round trip; the choice is in the settings file and a fresh start reads it
## Shots: C:/Temp/claude/s023/*.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s023"
const DIRT := "user://s023_test"
var pu: PartUI
var ep


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part, -1, {"faces": true})


## the top surface height (mm) at (x, z) mm: the highest point of the kernel mesh straight above that spot
func top_y(x: float, z: float) -> float:
	var best := -1e9
	for tris in Part.body_faces(m.S.part):
		var t: PackedVector3Array = tris
		for k in range(0, t.size() - 2, 3):
			var a := Vector2(t[k].x, t[k].z) / Part.MM
			var b := Vector2(t[k + 1].x, t[k + 1].z) / Part.MM
			var c := Vector2(t[k + 2].x, t[k + 2].z) / Part.MM
			var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
			if absf(d) < 1e-12:
				continue
			var l1 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (z - c.y)) / d
			var l2 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (z - c.y)) / d
			var l3 := 1.0 - l1 - l2
			if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6:
				best = maxf(best, (l1 * t[k].y + l2 * t[k + 1].y + l3 * t[k + 2].y) / Part.MM)
	return best


func vol_mm3() -> float:
	return float(solid()["volume"]) / (Part.MM * Part.MM * Part.MM)


func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func contrast(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func bg_of(c: Control) -> Color:
	var sb := c.get_theme_stylebox("panel") if c is PanelContainer else c.get_theme_stylebox("normal")
	return (sb as StyleBoxFlat).bg_color if sb is StyleBoxFlat else Color(0, 0, 0, 0)


## every PanelContainer / Button under the Easy Part boxes: its path and fill colour (to compare a round trip)
func fills() -> Dictionary:
	var out := {}
	for c in ep.bar.get_parent().get_children():
		if not String(c.name).to_lower().begins_with("easypart"):
			continue
		for n in [c] + c.find_children("*", "Control", true, false):
			if n is PanelContainer or n is Button:
				var sb := (n as Control).get_theme_stylebox("panel") if n is PanelContainer else (n as Control).get_theme_stylebox("normal")
				if sb is StyleBoxFlat:
					out[str(n.get_path())] = (sb as StyleBoxFlat).bg_color
	return out


func pixel_lum() -> float:
	var img := root.get_texture().get_image()
	var s := 0.0
	var n := 0
	for p in [Vector2i(40, 200), Vector2i(60, 420), Vector2i(300, 330), Vector2i(120, 560)]:
		var c := img.get_pixelv(p)
		s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		n += 1
	return s / n


func open_popup() -> void:
	if ep.level_box.visible:
		return
	await click_ctl(ep.easy_btn)
	await idle(4)


func _init() -> void:
	# a restart: the settings file of this run already says Light (as if the last session ended on Light); the app that boots must read it
	var pre := ConfigFile.new()
	pre.set_value("look", "theme", "light")
	pre.set_value("look", "light", true)
	pre.save("user://poser_test_%d.cfg" % OS.get_process_id())
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	ok(not Tok.dark and m.theme_pref == "light", "B8 a fresh start with Light saved boots Light (Tok.dark %s, pref %s)" % [str(Tok.dark), m.theme_pref])
	m._set_light(false)   # the rest of the run starts from the shipped Dark look
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
	pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	ep = pu.ep
	# the 40 x 20 x 40 box (x, y up, z), built as steps in the record
	var rec: Dictionary = m.S.part
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [-20.0, -20.0], "b": [20.0, 20.0]}], "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": 20.0, "both": false, "op": "join", "into": 0})
	rec["features"].append(ex)
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	ep.tweak = {}
	ep._rows_sync()
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = -50.0
	m.yaw = 20.0
	m.dist = 0.2
	m._cam()
	await idle(40)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	var v0 := vol_mm3()
	ok(int(s0["bodies"]) == 1 and absf(bb0.size.x / Part.MM - 40.0) < 0.01 and absf(bb0.size.y / Part.MM - 20.0) < 0.01 and absf(bb0.size.z / Part.MM - 40.0) < 0.01,
		"A0 the box is 40 x 20 x 40 mm, one solid (%.2f x %.2f x %.2f, volume %.1f)" % [bb0.size.x / Part.MM, bb0.size.y / Part.MM, bb0.size.z / Part.MM, v0])
	var top0 := top_y(0.0, 0.0)
	ok(absf(top0 - 20.0) < 0.001, "A0 the probe reads the top at %.4f mm" % top0)
	var dark_fills := fills()
	await shot("dark_box")

	# A1 the chip
	var bb := root.find_child("easypart_bulge", true, false) as Button
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	ok(bb != null and bb.is_visible_in_tree() and vp.encloses(Rect2(bb.global_position, bb.size)), "A1 the Pinch / Bulge a face chip is on screen at 1280 x 720 (%s)" % (str(bb.get_global_rect()) if bb != null else "missing"))
	var u0: int = m.undo.size()
	await click_ctl(bb)
	await click_at(scr(Vector3(0.0, 0.020, 0.0)))
	await idle(12)
	var feats: Array = m.S.part.get("features", [])
	var last_t := String(feats[-1].get("t", ""))
	var s1 := solid()
	var c1 := top_y(0.0, 0.0)
	var rim := [top_y(19.95, 0.0), top_y(-19.95, 0.0), top_y(0.0, 19.95), top_y(0.0, -19.95)]
	var rim_ok := true
	for r in rim:
		rim_ok = rim_ok and absf(r - 20.0) < 0.1
	var v1 := vol_mm3()
	var bb1: AABB = s1["aabb"]
	ok(last_t == "bulge" and m.undo.size() == u0 + 1, "A2 one click on the top face: the newest step is %s, undo steps %d -> %d (one)" % [last_t, u0, m.undo.size()])
	ok(int(s1["bodies"]) == 1 and absf(c1 - 24.0) < 0.1, "A3 bulge +0.5: one solid, top centre %.3f mm (expected 24.000 +- 0.1)" % c1)
	ok(rim_ok, "A4 the edges stay at 20 mm: %s" % str(rim))
	ok(absf(bb1.size.x / Part.MM - 40.0) < 0.01 and absf(bb1.size.z / Part.MM - 40.0) < 0.01, "A4 footprint stays 40 x 40 (%.3f x %.3f)" % [bb1.size.x / Part.MM, bb1.size.z / Part.MM])
	ok(v1 > v0 + 100.0 and absf((v1 - v0) - 3200.0) < 640.0, "A5 volume grows by %.1f mm3 (> 0; a 4 mm dome of this shape is about 3200)" % (v1 - v0))
	await shot("bulge_half")
	# slider
	var sl := root.find_child("easypart_slider_last", true, false) as HSlider
	ok(sl != null and sl.min_value == -1.0 and sl.max_value == 1.0 and absf(sl.value - 0.5) < 0.001, "A6 the Pinch / Bulge slider runs -1 .. 1 and sits at 0.5 (%s)" % (str([sl.min_value, sl.max_value, sl.value]) if sl != null else "missing"))
	var u1: int = m.undo.size()
	sl.value = -0.5
	await idle(20)
	var c2 := top_y(0.0, 0.0)
	var v2 := vol_mm3()
	var rim2 := [top_y(19.95, 0.0), top_y(0.0, -19.95)]
	ok(int(solid()["bodies"]) == 1 and absf(c2 - 16.0) < 0.1, "A7 pinch -0.5: one solid, top centre %.3f mm (expected 16.000 +- 0.1), undo steps +%d" % [c2, m.undo.size() - u1])
	ok(v2 < v0 - 100.0 and absf(rim2[0] - 20.0) < 0.1 and absf(rim2[1] - 20.0) < 0.1, "A7 volume shrinks by %.1f mm3, edges still %s" % [v0 - v2, str(rim2)])
	await shot("pinch_half")
	sl.value = 1.0
	await idle(20)
	var c3 := top_y(0.0, 0.0)
	ok(absf(c3 - 28.0) < 0.1, "A8 bulge +1: top centre %.3f mm (expected 28.000 +- 0.1)" % c3)
	sl.value = 0.0
	await idle(20)
	var c4 := top_y(0.0, 0.0)
	var v4 := vol_mm3()
	var rim4 := [top_y(19.95, 0.0), top_y(5.0, 7.0), top_y(-12.0, 3.0)]
	ok(absf(c4 - 20.0) < 0.001 and absf(v4 - v0) < 0.01 and absf(rim4[0] - 20.0) < 0.001 and absf(rim4[1] - 20.0) < 0.001, "A9 0 is the original: top %.5f, volume %.4f vs %.4f, elsewhere %s" % [c4, v4, v0, str(rim4)])
	for i in 5:
		m._undo()
		await idle(6)
	var nf: int = (m.S.part.get("features", []) as Array).size()
	ok(absf(top_y(0.0, 0.0) - 20.0) < 0.001 and nf == 2, "A10 undo takes the bulge back: top %.4f, %d steps" % [top_y(0.0, 0.0), nf])

	# ---- 109 Light / Dark ----
	var lum_dark_px := pixel_lum()
	await open_popup()
	var lb := root.find_child("easypart_theme_light", true, false) as Button
	var db := root.find_child("easypart_theme_dark", true, false) as Button
	ok(lb != null and db != null and ep.level_box.visible and lb.is_visible_in_tree() and Tok.dark, "B0 the Easy popup shows Dark and Light (Dark now)")
	await shot("popup_dark")
	await click_ctl(lb)
	await idle(10)
	ok(not Tok.dark and lb.button_pressed and not db.button_pressed, "B1 Light pressed: the palette is light")
	await idle(20)
	var pan_l := lum(bg_of(ep.panel))
	var steps_l := lum(bg_of(ep.steps_box))
	var flat_l := lum(bg_of(ep.flat_box))
	ok(pan_l > 0.7 and steps_l > 0.7 and flat_l > 0.7, "B2 Light: panel luminance %.3f, step list %.3f, printing box %.3f (all > 0.7)" % [pan_l, steps_l, flat_l])
	var worst := 99.0
	var worst_n := ""
	var nb := 0
	for c in ep.bar.get_parent().get_children():
		if not String(c.name).to_lower().begins_with("easypart"):
			continue
		for n in c.find_children("*", "Button", true, false):
			var b := n as Button
			if not b.is_visible_in_tree() or b.disabled:
				continue
			if b.has_theme_color_override("font_color") and lum(bg_of(b)) < 0.7:
				continue   # a colour chip keeps its own dark-on-colour text
			var cr := contrast(b.get_theme_color("font_color"), bg_of(b))
			nb += 1
			if cr < worst:
				worst = cr
				worst_n = String(b.name)
	ok(nb > 5 and worst >= 4.5, "B3 Light: %d visible buttons, lowest text contrast %.2f:1 (%s), want >= 4.5" % [nb, worst, worst_n])
	var px := pixel_lum()
	ok(px > lum_dark_px + 0.15, "B4 the viewport background is lighter: pixels %.3f (Dark %.3f)" % [px, lum_dark_px])
	await shot("light_box")
	await click_ctl(root.find_child("easypart_bulge", true, false))
	await click_at(scr(Vector3(0.0, 0.020, 0.0)))
	await idle(14)
	await shot("light_bulge")
	m._undo()
	await idle(6)
	var cf := ConfigFile.new()
	var lerr := cf.load(m.settings)
	ok(lerr == OK and bool(cf.get_value("look", "light", false)) and String(cf.get_value("look", "theme", "")) == "light", "B5 the choice is in the settings file (%s)" % str([cf.get_value("look", "theme", "?"), cf.get_value("look", "light", "?")]))
	await open_popup()
	await click_ctl(root.find_child("easypart_theme_dark", true, false))
	await idle(20)
	var back := fills()
	var diff := []
	for k in dark_fills:
		if back.has(k) and not (back[k] as Color).is_equal_approx(dark_fills[k]):
			diff.append(k)
	ok(Tok.dark and diff.is_empty() and back.size() >= dark_fills.size() - 2, "B6 Dark again: %d boxes/buttons, %d differ from the first Dark look %s" % [back.size(), diff.size(), str(diff.slice(0, 3))])
	var lit := root.find_child("easypart_printing", true, false) as Control
	ok(bg_of(lit).is_equal_approx(Color(0.1, 0.11, 0.14, 0.92)) and bg_of(ep.panel).is_equal_approx(Color(0.1, 0.11, 0.14, 0.95)), "B7 Dark is the shipped look: printing box %s, panel %s" % [str(bg_of(lit)), str(bg_of(ep.panel))])
	await shot("dark_again")
	print("s023: %d fail" % fails)
	quit(1 if fails > 0 else 0)
