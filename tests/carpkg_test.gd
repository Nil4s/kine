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
##  20 SEATSIDE  the seat from the middle: the 3D fighter's hip is at the offset on the chosen side (Left +, Right -), within 1 mm
##  21 DOOR      a 1600 mm wide body with the seat 500 mm out: the door check is red; the default 370 is clear
##  22 TOPFILL   the top view's outline is >= 60 % of its panel's width (drawn geometry, a 1150 px wide plan)
##  23 SCALE     the side and the top view draw at the same scale (their drawn lengths per mm within 1 %), top at the same x as the side
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
	more_bars()
	await seat_bars()
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


## the driver position, the floor, the feet and the 3D fighter (the bars added with the layout fix)
func more_bars() -> void:
	var want := {"City": 1000.0, "Hatch": 1150.0, "Sedan": 1200.0, "SUV": 1150.0, "Roadster": 1250.0}
	var bad := []
	for cls in want:
		var sp := CarPackage.start(cls)
		if absf(float(sp["hpt_x"]) - float(want[cls])) > 0.01:
			bad.append("%s %d" % [cls, int(sp["hpt_x"])])
	var rng := CarPackage.PARAMS[7]
	ok(bad.is_empty() and rng[0] == "hpt_x" and float(rng[4]) == 700.0 and float(rng[5]) == 1800.0, "16 SEAT the class seat from the front wheel: City 1000, Hatch 1150, Sedan 1200, SUV 1150, Roadster 1250 (range 700-1800) %s" % str(bad))
	var hp := CarPackage.start("Hatch")
	var dh := CarPackage.derive(hp)
	var hg := float(hp["clearance"]) + 150.0 + float(hp["hpt_h"])
	ok(absf(float(dh["hpt_ground"]) - hg) < 1e-6 and String(CarPackage.PARAMS[6][1]) == "Seat height above the floor", "17 SEAT HEIGHT H-point above ground = clearance %d + floor 150 + seat %d = %.0f mm (readout %.0f)" % [int(hp["clearance"]), int(hp["hpt_h"]), hg, float(dh["hpt_ground"])])
	var reach := 450.0 + sqrt(430.0 * 430.0 - (260.0 - 90.0) * (260.0 - 90.0))
	var front := float(dh["r"]) + 100.0
	var f1 := CarPackage.derive(hp)
	var f2 := hp.duplicate()
	f2["hpt_x"] = 1300.0
	var f2d := CarPackage.derive(f2)
	ok(absf(float(f1["heel"]) - (1150.0 - reach)) < 0.01 and absf(float(f1["feet_min"]) - front) < 0.01 and not bool(f1["feet_ok"]) and bool(f2d["feet_ok"]),
		"18 FEET heel point %.0f mm behind the front axle (seat 1150 - reach %.0f), needs %.0f: red at 1150, clear at 1300" % [float(f1["heel"]), reach, front])
	var p3 := CarPackage.build_3d(hp)
	var fi := p3.find_child("fighter", false, false) as Node3D
	var zf := float(hp["wheelbase"]) * 0.0005
	var hip_want := Vector3(0.0, hg * 0.001, zf - float(hp["hpt_x"]) * 0.001)
	var fwd := fi.transform.basis.z.normalized() if fi != null else Vector3.ZERO
	var th := p3.find_child("fighter_thigh", true, false) as Node3D
	var sh := p3.find_child("fighter_shin", true, false) as Node3D
	var front_ok := th != null and sh != null and th.position.z > 0.0 and sh.position.z > 0.0
	ok(fi != null and fwd.dot(Vector3(0.0, 0.0, 1.0)) > 0.9 and fi.position.distance_to(hip_want) <= 0.005 and front_ok,
		"19 FIGHTER faces the front: forward . package forward %.3f (> 0.9), hip %.4f m from the H-point (<= 0.005), knees and feet to the front axle" % [fwd.dot(Vector3(0.0, 0.0, 1.0)), fi.position.distance_to(hip_want) if fi != null else -1.0])
	p3.free()


## the seat from the middle, the door check, the top view's fill and the one scale of the two views (the drawn geometry)
func seat_bars() -> void:
	var hp := CarPackage.start("Hatch")
	var off := float(hp["seat_off"])
	var L := CarPackage.build_3d(hp)
	var fi := L.find_child("fighter", true, false) as Node3D
	var sb := L.find_child("fighter_seat", true, false) as Node3D
	var hipx := fi.position.x + sb.position.x if sb != null else INF
	var rp := hp.duplicate()
	rp["drive"] = "Right"
	var R := CarPackage.build_3d(rp)
	var rsb := R.find_child("fighter_seat", true, false) as Node3D
	var rfi := R.find_child("fighter", true, false) as Node3D
	var rhipx := rfi.position.x + rsb.position.x if rsb != null else INF
	ok(absf(hipx - off * 0.001) <= 0.001 and absf(rhipx + off * 0.001) <= 0.001 and absf(float(CarPackage.derive(hp)["hip_y"]) - off) < 0.001 and absf(float(CarPackage.derive(rp)["hip_y"]) + off) < 0.001,
		"20 SEATSIDE hip %.1f mm Left (want +%d), %.1f mm Right (want -%d), within 1 mm" % [hipx * 1000.0, int(off), rhipx * 1000.0, int(off)])
	L.free()
	R.free()
	var wide := hp.duplicate()
	wide["track_f"] = 1375.0
	wide["track_r"] = 1375.0
	wide["seat_off"] = 500.0
	var wd := CarPackage.derive(wide)
	var dok := CarPackage.derive(hp)
	ok(absf(float(wd["width"]) - 1600.0) < 0.01 and not bool(wd["door_ok"]) and bool(dok["door_ok"]),
		"21 DOOR body %d mm, seat 500: door room %d mm (needs 100): red; the default 370 clear (room %d mm)" % [int(wd["width"]), int(wd["door_gap"]), int(dok["door_gap"])])
	var plan := CarPlan.new()
	plan.name = "carpkg_test_plan"
	plan.position = Vector2(0.0, 0.0)
	plan.size = Vector2(1150.0, 760.0)
	root.add_child(plan)
	plan.set_points(hp)
	await idle(4)
	var top_body := plan.outline[1][0] as PackedVector2Array
	var side_box := plan.outline[0][1] as PackedVector2Array
	var top_len := top_body[1].x - top_body[0].x
	var panel_w := plan.top_r.size.x
	var side_len := side_box[1].x - side_box[0].x
	var Lmm := float(CarPackage.derive(hp)["length"])
	var fill := top_len / panel_w
	ok(fill >= 0.6, "22 TOPFILL top outline %.0f px of a %.0f px panel: %.0f %% (>= 60 %%)" % [top_len, panel_w, fill * 100.0])
	var sc_side := side_len / Lmm
	var sc_top := top_len / Lmm
	ok(absf(sc_side - sc_top) <= 0.01 * sc_top and absf(side_box[0].x - top_body[0].x) < 0.5,
		"23 SCALE side %.4f px/mm, top %.4f px/mm (within 1 %%), nose x side %.1f top %.1f" % [sc_side, sc_top, side_box[0].x, top_body[0].x])
	plan.free()


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
	if m.ui_toast != null:   # the undo toast is not in the shots: taken down before the save
		m.ui_toast.visible = false
	await idle(2)
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
	# 6b the roof is measured from the ground, so the head is too: the car up 20 mm off the ground lifts the head 20 mm
	var c0 := float(ps.pkg()["clearance"])
	ps.set_param("clearance", c0 + 20.0)
	var h2 := CarPackage.derive(ps.pkg())["head"] as float
	ps.set_param("clearance", c0)
	ok(absf((h1 - h2) - 20.0) <= 0.01, "6b HEADROOM the car 20 mm higher off the ground: head room down %.2f mm (20)" % (h1 - h2))
	ok(h1 >= 0.0 and h1 <= 150.0, "6c HEADROOM the hatch with a 1450 roof leaves %.0f mm over the seated head (real C hatches: 0-150)" % h1)

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

	# 20 LABELS: every label of the layout is placed (fits), inside its panel, clear of the others and of the outline; the dimension
	# labels also stay out of the body (the annotations H-point and head room sit inside the cabin)
	var plan: CarPlan = ps.plan
	var lbad := []
	for i in plan.labels.size():
		var l1: Dictionary = plan.labels[i]
		var r1: Rect2 = l1["rect"]
		var pi := int(l1["panel"])
		var pn: Rect2 = plan.side_r if pi == 0 else plan.top_r
		var tn := String(l1["text"])
		if not bool(l1["fits"]) or not pn.encloses(r1):
			lbad.append("%s outside its panel" % tn)
		for j in range(i + 1, plan.labels.size()):
			var l2: Dictionary = plan.labels[j]
			if int(l2["panel"]) == pi and r1.intersects(l2["rect"]):
				lbad.append("%s / %s" % [tn, String(l2["text"])])
		for pl in plan.outline[pi]:
			if CarPlan.line_hits(r1, pl):
				lbad.append("%s on the outline" % tn)
				break
		if not tn.begins_with("H-point") and not tn.begins_with("head room"):
			for so in plan.solids[pi]:
				if CarPlan.solid_hits(r1, so):
					lbad.append("%s in the body" % tn)
					break
	ok(lbad.is_empty() and plan.labels.size() >= 14, "20 LABELS %d labels, all placed, inside their panel, none on another or the outline: %s" % [plan.labels.size(), str(lbad.slice(0, 4))])

	# 10 SAVE: the file form keeps the package
	var f := Vehicle.to_file(m.S.vehicle)
	var back := Vehicle.from_file(f)
	ok(back.has("package") and absf(float(back["package"]["wheelbase"]) - float(ps.pkg()["wheelbase"])) < 0.01 and String(back["package"]["class"]) == "Hatch", "10 SAVE the package survives the file form (class %s)" % String(back.get("package", {}).get("class", "")))
	ps.close()
	await idle(2)
	ok(not ps.visible and m.cur_page == "BUILD", "11 CARD Back to BUILD closes the package (page %s)" % m.cur_page)