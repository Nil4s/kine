extends SceneTree
## godot --path . --position 4000,4000 -s tests/carpkg_test.gd     (VEHICLE, STEP 1 PACKAGE + STEP 6 COMPARE: scripts/car_package.gd, car_plan.gd, package_screen.gd; a window for the UI bars)
## Bars, written before measuring:
##   0 LOADS     the pure parts load (CarPackage reads data/real_cars.json: 6 cars)
##   1 TYRE      "225/45R17" -> diameter 634.3 mm within 0.5 (rim 17 x 25.4 + 2 x 225 x 45 / 100)
##   2 HATCH     the Hatch class starts at the average wheelbase of its real cars (Golf 2636, Corolla 2640 -> 2638) within 1 %
##   3 GOLF      the Golf's numbers (wheelbase 2636, tracks 1549 / 1520, 225/45R17, nose and tail 825, clearance 140, roof 1455): the
##               nearest real car is "VW Golf 8 hatch" and 0 rows are red
##   4 RED       on Hatch, wheelbase 1800 makes the wheelbase row red, with the words "short for a hatchback"
##   5 APPROACH  clearance 140 / nose 850: approach = atan(140 / 850) within 0.1 deg (read back from the screen's readout)
##   6 HEADROOM  the roof up 50 mm moves the head clearance by exactly 50 mm (within 0.01)
##   7 WHEELS    the 3D wheels sit on their axle points (+-1 mm, x = +-track / 2, z = +-wheelbase / 2) and touch the ground line (their bottom is y = 0 within 1 um)
##   8 UNDO      one undo step per change (a number, the tyre, a class); a change that changes nothing is no step
##   9 TYPED     Expert: the wheelbase typed as 1800 and Enter is one undo step and sets 1800 mm
##  10 SAVE      the package is kept in the file form (Vehicle.to_file / from_file) with the same numbers
##  --- the UI (a window, 1280 x 720, real mouse through root.push_input; the Vehicle card, Easy and Expert):
##  11 CARD      the Vehicle card opens the package (Easy: sliders, Expert: typed boxes) on BUILD, the chooser closes
##  12 SLIDER    a real drag of the wheelbase: one undo step per release, the value moves with the slider
##  13 WORDS     no key name in any text of the package screen (labels, buttons, tooltips, status)
##  14 LAYOUT    at 1280 x 720 the top bar, the layout, the 3D view, the panel and the status line overlap nothing and stay inside the window
##  15 COMPARE   the Yours vs real cars tab lists the 8 measures, the nearest car, and a red row with a hint (Hatch, wheelbase short)
## Shots in C:/Temp/claude/carbuild/: package_easy.png, package_expert.png, compare.png.

const SHOT := "C:/Temp/claude/carbuild"
const DIRT := "user://carpkg_test"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	headless_bars()
	await ui_bars()
	print("carpkg: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func headless_bars() -> void:
	ok(CarPackage.cars().size() == 6, "0 LOADS data/real_cars.json: %d real cars (the file has 6: Golf, Corolla, Civic, RAV4, MX-5, Fiat 500)" % CarPackage.cars().size())
	var t := CarPackage.tyre("225/45R17")
	ok(bool(t["ok"]) and absf(float(t["diameter"]) - 634.3) <= 0.5, "1 TYRE 225/45R17 -> diameter %.2f mm (634.3 within 0.5)" % float(t["diameter"]))
	var hp := CarPackage.start("Hatch")
	var avg_wb := (2636.0 + 2640.0) * 0.5
	ok(absf(float(hp["wheelbase"]) - avg_wb) <= 0.01 * avg_wb, "2 HATCH the Hatch start wheelbase %.0f mm (average %.0f, within 1 %%)" % [float(hp["wheelbase"]), avg_wb])
	var golf := {"wheelbase": 2636.0, "track_f": 1549.0, "track_r": 1520.0, "front_oh": 825.0, "rear_oh": 825.0, "clearance": 140.0,
		"hpt_h": 260.0, "hpt_x": 380.0, "seat_a": 25.0, "roof": 1455.0, "tyre": "225/45R17", "class": "Hatch"}
	var gd := CarPackage.derive(golf)
	var gnear := CarPackage.nearest(golf, gd)
	var gred := 0
	for r in CarPackage.rows(golf):
		gred += 1 if r["red"] else 0
	ok(String(gnear.get("name", "")) == "VW Golf 8 hatch" and gred == 0, "3 GOLF nearest '%s', red rows %d (want VW Golf 8 hatch, 0)" % [gnear.get("name", ""), gred])
	var short := hp.duplicate()
	short["wheelbase"] = 1800.0
	var wb_row := {}
	for r in CarPackage.rows(short):
		if r["key"] == "wheelbase":
			wb_row = r
	ok(bool(wb_row.get("red", false)) and String(wb_row.get("hint", "")).contains("short for a hatchback"), "4 RED wheelbase 1800 on Hatch: red, hint '%s'" % wb_row.get("hint", ""))
	var ap := CarPackage.derive({"wheelbase": 2636.0, "track_f": 1500.0, "track_r": 1500.0, "front_oh": 850.0, "rear_oh": 850.0, "clearance": 140.0, "hpt_h": 260.0, "hpt_x": 380.0, "seat_a": 25.0, "roof": 1450.0, "tyre": "225/45R17"})
	ok(absf(float(ap["approach"]) - rad_to_deg(atan(140.0 / 850.0))) <= 0.1, "5 APPROACH %.3f deg, atan(140/850) = %.3f (within 0.1)" % [float(ap["approach"]), rad_to_deg(atan(140.0 / 850.0))])
	var p3 := CarPackage.build_3d(golf)
	var wb := 2.636
	var tf := 1.549
	var r := float(gd["r"]) * 0.001
	var want := {"wheel_fl": Vector3(-tf * 0.5, r, wb * 0.5), "wheel_fr": Vector3(tf * 0.5, r, wb * 0.5), "wheel_rl": Vector3(-1.520 * 0.5, r, -wb * 0.5), "wheel_rr": Vector3(1.520 * 0.5, r, -wb * 0.5)}
	var worst := 0.0
	var touch := 0.0
	for k in want:
		var w3: Node3D = p3.find_child(k, false, false)
		if w3 == null:
			worst = 1.0
			continue
		worst = maxf(worst, (w3.position - want[k]).length() * 1000.0)
		var cyl := w3.mesh as CylinderMesh
		touch = maxf(touch, absf(w3.position.y - cyl.top_radius))
	var gl := p3.find_child("ground_line", false, false) as MeshInstance3D
	var top_y := gl.position.y + (gl.mesh as BoxMesh).size.y * 0.5
	ok(worst <= 1.0 and touch < 1e-6 and absf(top_y) < 1e-6, "7 WHEELS the four wheels within %.3f mm of their axle points; bottoms within %.6f m of y = 0, ground line top at %.6f m" % [worst, touch, top_y])
	p3.free()


func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect())


func drag_to(c: Control, frac: float) -> void:
	var sl := c as HSlider
	var r := sl.get_global_rect()
	var p0 := Vector2(r.position.x + (sl.value - sl.min_value) / (sl.max_value - sl.min_value) * r.size.x, r.get_center().y)
	var p1 := Vector2(r.position.x + frac * r.size.x, r.get_center().y)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	await ev_move(p1, true)
	await ev_mouse(p1, false)
	await idle(3)


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


func texts_under(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
		out.append((n as Button).tooltip_text)
	if n is Control and (n as Control).tooltip_text != "":
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts_under(c, out)


func key_in(t: String) -> String:
	var low := " " + t.to_lower() + " "
	for k in PackageScreen.BAD_WORDS:
		if low.contains(k) or low.contains(" " + k):
			return k
	return ""


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func ui_bars() -> void:
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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	var bc: BuildChoose = m.build_choose
	bc.show_chooser()
	await idle(4)

	# 11 CARD: Easy opens the package with sliders; the chooser closes
	var vb: Button = bc.btns["vehicle"]["easy"]
	await click_ctl(vb)
	await idle(6)
	var ps: PackageScreen = bc._car_screen
	ok(ps != null and ps.visible and ps.easy and not bc.open and not ps.pkg().is_empty() and (ps.rows["wheelbase"]["slider"] as HSlider).visible, "11 CARD Vehicle Easy opens the package with sliders (chooser closed %s, page %s)" % [not bc.open, m.cur_page])
	await shot("package_easy")

	# 8 UNDO + 12 SLIDER: a real drag of the wheelbase: one undo step, the value moves
	var u0: int = m.undo.size()
	var sl: HSlider = ps.rows["wheelbase"]["slider"]
	var before := float(ps.pkg()["wheelbase"])
	await drag_to(sl, 0.9)
	var steps: int = m.undo.size() - u0
	var after := float(ps.pkg()["wheelbase"])
	ok(steps == 1 and absf(after - sl.value) < 0.01 and absf(after - before) > 50.0, "12 SLIDER wheelbase %.0f -> %.0f mm by a drag: %d undo step" % [before, after, steps])
	m._undo()
	await idle(3)
	ok(absf(float(ps.pkg()["wheelbase"]) - before) < 0.01, "8 UNDO one undo takes back the drag (wheelbase %.0f, was %.0f)" % [float(ps.pkg()["wheelbase"]), before])
	ps.set_class("Hatch")
	var u1: int = m.undo.size()
	ps.set_param("roof", float(ps.pkg()["roof"]) + 50.0)
	ps.set_param("roof", float(ps.pkg()["roof"]))   # the same value again: no step
	ok(m.undo.size() - u1 == 1, "8 UNDO a change is one step and a no-change is none (%d steps)" % (m.undo.size() - u1))

	# 3 + 4 + 15 with the screen: the Golf's numbers, then the wheelbase 1800 on Hatch
	ps.set_class("Hatch")
	ps.set_param("wheelbase", 2635.0)
	ps.set_param("wheelbase", 2635.0)
	ps.set_param("track_f", 1550.0)
	ps.set_param("track_r", 1520.0)
	ps.set_param("front_oh", 825.0)
	ps.set_param("rear_oh", 825.0)
	ps.set_param("clearance", 140.0)
	ps.set_param("roof", 1455.0)
	ps._set_tyre("225/45R17")
	var nm := String(CarPackage.nearest(ps.pkg(), CarPackage.derive(ps.pkg())).get("name", ""))
	var reds := 0
	for r in ps.compare_rows():
		reds += 1 if r["red"] else 0
	ok(nm == "VW Golf 8 hatch" and reds == 0, "3 GOLF on the screen: nearest '%s', red rows %d (want VW Golf 8 hatch, 0)" % [nm, reds])
	ps.set_param("wheelbase", 1800.0)
	var wr := ps.find_child("package_cmp_wheelbase", true, false)
	var hint := ps.find_child("package_hint_wheelbase", true, false) as Label
	ok(wr != null and bool(wr.get_meta("red")) and hint != null and hint.text.contains("short for a hatchback"), "4 RED on the screen the wheelbase row is red: '%s'" % (hint.text if hint != null else "no hint"))
	ps.set_param("wheelbase", 2635.0)
	ps.set_param("track_f", 1550.0)

	# 5 approach through the screen: clearance 140, nose 850
	ps.set_param("clearance", 140.0)
	ps.set_param("front_oh", 850.0)
	var ap_txt: String = (ps.readouts["approach"] as Label).text
	var ap := float(ap_txt.split(" ")[-2])
	ok(absf(ap - rad_to_deg(atan(140.0 / 850.0))) <= 0.1, "5 APPROACH readout %.2f deg (atan(140/850) = %.2f, within 0.1)" % [ap, rad_to_deg(atan(140.0 / 850.0))])
	ps.set_param("front_oh", 825.0)

	# 6 head room moves with the roof, 1:1
	ps.set_param("roof", 1400.0)
	var h0 := CarPackage.derive(ps.pkg())["head"] as float
	ps.set_param("roof", 1450.0)
	var h1 := CarPackage.derive(ps.pkg())["head"] as float
	ok(absf((h1 - h0) - 50.0) <= 0.01, "6 HEADROOM the roof up 50 mm: head room up %.2f mm" % (h1 - h0))

	# 7 the 3D view follows the numbers: the wheels in the view are on their axles
	var w3: Node3D = ps.car3d.find_child("wheel_fl", false, false)
	var expect_z := float(ps.pkg()["wheelbase"]) * 0.0005
	ok(w3 != null and absf(w3.position.z - expect_z) < 0.001 and absf(w3.position.y - float(CarPackage.derive(ps.pkg())["r"]) * 0.001) < 0.001, "7 WHEELS in the view: front left at z %.4f m (axle %.4f), touching" % [w3.position.z if w3 != null else -1.0, expect_z])

	# 9 TYPED (Expert): the box is typed, Enter takes it: one step
	ps.open(false)
	await idle(3)
	var ed: LineEdit = ps.rows["wheelbase"]["edit"]
	var u2: int = m.undo.size()
	ok(ed.visible and not (ps.rows["wheelbase"]["slider"] as HSlider).visible and ps.tyre_edit.visible, "9 TYPED Expert shows typed boxes, not sliders")
	ed.text = "1800"
	ed.text_submitted.emit("1800")
	await idle(2)
	ok(absf(float(ps.pkg()["wheelbase"]) - 1800.0) < 0.01 and m.undo.size() - u2 == 1, "9 TYPED wheelbase typed 1800 + Enter: %.0f mm, %d undo step" % [float(ps.pkg()["wheelbase"]), m.undo.size() - u2])
	await shot("package_expert")
	ps.set_param("wheelbase", 2635.0)
	ps.open(true)
	await idle(3)

	# 13 WORDS
	var tx := []
	texts_under(ps, tx)
	var kk := ""
	for t in tx:
		kk = kk if kk != "" else key_in(String(t))
	ok(kk == "" and tx.size() > 30, "13 WORDS no key name on the package screen (%d texts, first key name '%s')" % [tx.size(), kk])

	# 14 LAYOUT at 1280 x 720
	var vpr := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rs := {"bar": _rect(ps.get_node("package_bar")), "plan": _rect(ps.plan), "view": _rect(ps.view), "panel": _rect(ps.panel), "status": _rect(ps.status)}
	var clash := []
	for a in rs:
		if not vpr.encloses(rs[a]):
			clash.append("%s outside" % a)
		for b in rs:
			if a < b and rs[a].intersects(rs[b]):
				clash.append("%s/%s" % [a, b])
	ok(clash.is_empty(), "14 LAYOUT at 1280 x 720 nothing overlaps and all stays in the window: %s" % str(clash))

	# 15 COMPARE: the tab, the Hatch with a short wheelbase
	ps.set_param("wheelbase", 1800.0)
	await click_ctl(ps.tab_cmp)
	await idle(3)
	var cmp_red := 0
	for r in ps.compare_rows():
		cmp_red += 1 if r["red"] else 0
	ok(ps.sec_cmp.visible and ps.cmp_box.get_child_count() >= 9 and cmp_red >= 1, "15 COMPARE the tab lists the measures (%d rows, %d red), nearest in the header" % [ps.cmp_box.get_child_count() - 1, cmp_red])
	await shot("compare")
	ps.set_param("wheelbase", 2635.0)

	# 10 SAVE: the file form keeps the package
	var f := Vehicle.to_file(m.S.vehicle)
	var back := Vehicle.from_file(f)
	ok(back.has("package") and absf(float(back["package"]["wheelbase"]) - float(ps.pkg()["wheelbase"])) < 0.01 and String(back["package"]["class"]) == "Hatch", "10 SAVE the package survives the file form (class %s)" % String(back.get("package", {}).get("class", "")))
	ps.close()
	await idle(2)
	ok(not ps.visible and m.cur_page == "BUILD", "11 CARD Back to BUILD closes the package (page %s)" % m.cur_page)