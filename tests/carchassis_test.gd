extends SceneTree
## godot --path . --position 4000,4000 -s tests/carchassis_test.gd     (VEHICLE, STEP 2 CHASSIS: scripts/car_chassis.gd, car_plan.gd, package_screen.gd; a window for the UI bars)
## Bars, written before measuring:
##   0 LOADS     the start chassis: 3 groups (sills, rails, crossmembers), mild steel; 3 size words; 3 materials
##   1 MASS      an 80 x 60 x 1.5 mild-steel member 1 m long: 7850 x 2 x 1.5 x (80 + 60 - 3) mm2 x 1 m = 3.226 kg (within 0.01)
##   2 INERTIA   I for 80 x 60 x 1.5 = (80 x 60^3 - 77 x 57^3) / 12 exactly (within 1 mm4; computed here, not typed)
##   3 RAILS     every class (5) x every tyre (7) x every rail size (3): the front rail's outer face inside the front tyre's inner face
##   4 WHEELBASE +100 mm wheelbase lengthens each sill by 100 mm (within 1 mm)
##   5 ALU       Aluminium cuts the structure mass by 7850 / 2700 for the same sections (within 1e-6 of the ratio)
##   6 SIZES     Light 60 x 40 x 1.2, Normal 80 x 60 x 1.5, Strong 100 x 80 x 2.0 (the sizes the chooser gives)
##   7 MEMBERS   11 members (2 sills, 2 front + 2 rear rails, 5 crossmembers); the 3D view has one box per member, the wheels stay
##  --- the UI (a window, 1280 x 720, real mouse through root.push_input):
##   8 STEPS     the step bar: "2 Chassis" is one click (chassis panel shown, package panel hidden); "1 Package" is one click back;
##               the package numbers are the same after the round trip
##   9 GREY      "4 Weight", "5 Body" are greyed (disabled); "3 Suspension" is live since d1071487 (the step that replaced the greyed tab)
##  10 UNDO      Easy size click = one undo step; the same size again = none; a typed section = one step
##  11 WORDS     no key name in any text of the chassis panel or the status line
##  12 LAYOUT    at 1280 x 720 the top bar, the layout, the 3D view, the chassis panel and the status line overlap nothing
##  13 SAVE      the file form (Vehicle.to_file -> JSON text -> Vehicle.from_file) keeps the chassis (mat, every section) and the package
## Shots in C:/Temp/claude/carbuild/: chassis_easy.png, chassis_3d.png.

const SHOT := "C:/Temp/claude/carbuild"
const DIRT := "user://carchassis_test"
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
	print("carchassis: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _rail_ok(p: Dictionary, c: Dictionary) -> bool:
	var tf := float(p["track_f"])
	var tw := float(CarPackage.derive(p)["tyre_w"])
	for mm in CarChassis.members(p, c):
		if String(mm["id"]).begins_with("rail_front"):
			var outer := maxf(absf((mm["lo"] as Vector3).x), absf((mm["hi"] as Vector3).x))
			if outer >= tf * 0.5 - tw * 0.5:
				return false
	return true


func headless_bars() -> void:
	var st := CarChassis.start()
	ok((st["g"] as Dictionary).size() == 3 and String(st["mat"]) == "Mild steel" and CarChassis.MATS.size() == 3 and CarChassis.SIZE_WORDS.size() == 3,
		"0 LOADS start: %d groups, %s; %d materials; %d size words" % [(st["g"] as Dictionary).size(), st["mat"], CarChassis.MATS.size(), CarChassis.SIZE_WORDS.size()])
	var m1 := CarChassis.box_mass(80.0, 60.0, 1.5, 7850.0, 1000.0)
	var want1 := 7850.0 * 2.0 * 1.5 * (80.0 + 60.0 - 3.0) * 1000.0 * 1e-9
	ok(absf(m1 - 3.226) <= 0.01 and absf(m1 - want1) < 1e-9, "1 MASS 80 x 60 x 1.5, 1 m, mild steel: %.4f kg (3.226 within 0.01)" % m1)
	var i_want := (80.0 * pow(60.0, 3.0) - 77.0 * pow(57.0, 3.0)) / 12.0
	var i_got := CarChassis.inertia(80.0, 60.0, 1.5)
	ok(absf(i_got - i_want) <= 1.0, "2 INERTIA 80 x 60 x 1.5: I = %.2f mm4 (exact %.2f within 1). Note: the brief's 251,846 is not this formula's value" % [i_got, i_want])
	var bad := []
	for cls in CarPackage.CLASSES:
		for t in CarPackage.TYRES:
			for word in CarChassis.SIZE_WORDS:
				var p := CarPackage.start(cls[0])
				p["tyre"] = t
				var c := CarChassis.start()
				c["g"]["rails"] = CarChassis.sec_of_word(word)
				if not _rail_ok(p, c):
					bad.append("%s %s %s" % [cls[0], t, word])
	ok(bad.is_empty(), "3 RAILS front rails inside the front tyres' inner faces for 5 classes x 7 tyres x 3 sizes: %s" % str(bad.slice(0, 3)))
	var p0 := CarPackage.start("Hatch")
	var p1 := p0.duplicate()
	p1["wheelbase"] = float(p0["wheelbase"]) + 100.0
	var s0 := 0.0
	var s1 := 0.0
	for mm in CarChassis.members(p0, st):
		if String(mm["id"]).begins_with("sill"):
			s0 = float(mm["len"])
	for mm in CarChassis.members(p1, st):
		if String(mm["id"]).begins_with("sill"):
			s1 = float(mm["len"])
	ok(absf((s1 - s0) - 100.0) <= 1.0, "4 WHEELBASE +100 mm: sill %.1f -> %.1f mm (+%.1f, within 1)" % [s0, s1, s1 - s0])
	# 4b the sills run between the wheel openings: no sill reaches into a tyre's length (front tyre ends at nose + r, rear starts at nose + wb - r)
	var into := []
	var rr := float(CarPackage.derive(p0)["r"])
	var fo := float(p0["front_oh"])
	for mm in CarChassis.members(p0, st):
		if String(mm["id"]).begins_with("sill") and ((mm["lo"] as Vector3).z < fo + rr or (mm["hi"] as Vector3).z > fo + float(p0["wheelbase"]) - rr):
			into.append("%s %.0f..%.0f" % [mm["id"], (mm["lo"] as Vector3).z, (mm["hi"] as Vector3).z])
	ok(into.is_empty(), "4b SILLS between the wheel openings %.0f..%.0f mm from the nose (into a tyre: %s)" % [fo + rr, fo + float(p0["wheelbase"]) - rr, into])
	var steel := CarChassis.totals(p0, st)
	var alu_c := st.duplicate(true)
	alu_c["mat"] = "Aluminium"
	var alu := CarChassis.totals(p0, alu_c)
	var ratio := float(steel["mass"]) / float(alu["mass"])
	ok(absf(ratio - 7850.0 / 2700.0) <= 1e-6, "5 ALU structure %.1f kg steel, %.1f kg aluminium: ratio %.6f (7850 / 2700 = %.6f)" % [float(steel["mass"]), float(alu["mass"]), ratio, 7850.0 / 2700.0])
	var sz := true
	for w in CarChassis.SIZE_WORDS:
		var s: Array = CarChassis.SIZES[w]
		var want: Array = {"Light": [60.0, 40.0, 1.2], "Normal": [80.0, 60.0, 1.5], "Strong": [100.0, 80.0, 2.0]}[w]
		sz = sz and s == want
	ok(sz, "6 SIZES Light 60 x 40 x 1.2, Normal 80 x 60 x 1.5, Strong 100 x 80 x 2.0")
	var mem := CarChassis.members(p0, st)
	var cnt := {}
	for mm in mem:
		cnt[mm["group"]] = int(cnt.get(mm["group"], 0)) + 1
	var l3 := CarChassis.build_3d(p0, st)
	var boxes := 0
	for ch in (l3.find_child("chassis", true, false) as Node3D).get_children():
		boxes += 1 if String(ch.name).begins_with("member_") else 0
	var wheels := l3.find_child("wheel_fl", true, false) != null
	ok(mem.size() == 11 and int(cnt["cross"]) == 5 and int(cnt["rails"]) == 4 and int(cnt["sills"]) == 2 and boxes == 11 and wheels,
		"7 MEMBERS %d members (sills %d, rails %d, crossmembers %d), 3D boxes %d, wheels kept %s" % [mem.size(), cnt["sills"], cnt["rails"], cnt["cross"], boxes, str(wheels)])
	l3.free()


func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect())


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
	if m.ui_toast != null:
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
	await click_ctl(bc.btns["vehicle"]["easy"])
	await idle(6)
	var ps: PackageScreen = bc._car_screen
	var b1: Button = ps.step_btns[1]
	var b2: Button = ps.step_btns[2]
	# 8 STEPS: 2 Chassis by one click, back by one click; the package numbers the same after the round trip
	var pk0 := JSON.stringify(ps.pkg())
	await click_ctl(b2)
	var on2: bool = ps.step == 2 and ps.chassis_panel.visible and not ps.panel.visible and b2.button_pressed
	var pk_mid := JSON.stringify(ps.pkg())
	await click_ctl(b1)
	var on1: bool = ps.step == 1 and ps.panel.visible and not ps.chassis_panel.visible
	ok(on2 and on1 and pk0 == JSON.stringify(ps.pkg()) and pk0 == pk_mid, "8 STEPS 2 Chassis: chassis panel %s; 1 Package back: package panel %s; package unchanged %s" % [on2, on1, pk0 == JSON.stringify(ps.pkg())])
	# 9 GREY
	var g3: bool = (ps.step_btns[3] as Button).visible and not (ps.step_btns[3] as Button).disabled   # d1071487 made 3 Suspension live (was: greyed)
	var g45: bool = (ps.step_btns[4] as Button).disabled and (ps.step_btns[5] as Button).disabled
	ok(g3 and g45 and String(ps.step_btns[3].text) == "3 Suspension" and String(ps.step_btns[4].text) == "4 Weight" and String(ps.step_btns[5].text) == "5 Body",
		"9 GREY 3 Suspension is live (%s); 4 Weight, 5 Body are greyed (disabled): %s" % [g3, g45])
	await click_ctl(b2)
	# 10 UNDO: an Easy size click, the same again, then a typed section
	var u0: int = m.undo.size()
	await click_ctl(ps.ch_rows["sills"]["btns"]["Strong"])
	var s_one: int = m.undo.size() - u0
	var sills_strong := String(ps.chassis()["g"]["sills"]["size"]) == "Strong"
	await click_ctl(ps.ch_rows["sills"]["btns"]["Strong"])
	var s_two: int = m.undo.size() - u0 - s_one
	var e: LineEdit = ps.ch_rows["rails"]["edits"][0]
	e.text = "90"
	e.text_submitted.emit("90")
	await idle(2)
	var typed_ok := float(ps.chassis()["g"]["rails"]["w"]) == 90.0 and String(ps.chassis()["g"]["rails"]["size"]) == "Custom"
	var s_typed: int = m.undo.size() - u0 - s_one - s_two
	ok(s_one == 1 and s_two == 0 and sills_strong and typed_ok and s_typed == 1,
		"10 UNDO Strong sills: %d step; again: %d; typed rail width 90 (Custom): %s, %d step" % [s_one, s_two, typed_ok, s_typed])
	m._undo()
	await idle(2)
	ok(String(ps.chassis()["g"]["rails"]["size"]) == "Normal", "10b UNDO takes back the typed rail (back to Normal)")
	m._redo()
	await idle(2)
	# 11 WORDS (texts of the chassis panel and the status line)
	var tx := []
	texts_under(ps.chassis_panel, tx)
	tx.append(ps.status_l.text)
	var kk := ""
	for t in tx:
		kk = kk if kk != "" else key_in(String(t))
	ok(kk == "" and tx.size() > 20, "11 WORDS no key name in the chassis panel or status (%d texts, first key name '%s')" % [tx.size(), kk])
	# 12 LAYOUT at 1280 x 720
	var vpr := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rs := {"bar": _rect(ps.get_node("package_bar")), "plan": _rect(ps.plan), "chassis": _rect(ps.chassis_panel), "status": _rect(ps.status)}
	var clash := []
	for a in rs:
		if not vpr.encloses(rs[a]):
			clash.append("%s outside" % a)
		for b in rs:
			if a < b and rs[a].intersects(rs[b]):
				clash.append("%s/%s" % [a, b])
	ok(clash.is_empty(), "12 LAYOUT at 1280 x 720 chassis step: nothing overlaps, all in the window %s" % str(clash))
	# the Easy shot
	await shot("chassis_easy")
	await click_ctl(ps.view_btn)
	await idle(3)
	await shot("chassis_3d")
	await click_ctl(ps.view_btn)
	await idle(2)
	# 13 SAVE: the file text round trip
	var txt := JSON.stringify(Vehicle.to_file(m.S.vehicle))
	var back := Vehicle.from_file(JSON.parse_string(txt))
	var same := JSON.stringify(back.get("chassis", {})) == JSON.stringify(CarChassis.norm(m.S.vehicle.get("chassis", {}))) and JSON.stringify(back.get("package", {})) == JSON.stringify(ps.pkg())
	ok(same and String(back["chassis"]["mat"]) == String(ps.chassis()["mat"]), "13 SAVE the file text keeps the chassis (sills %s, rails %s) and the package" % [String(back["chassis"]["g"]["sills"]["size"]), String(back["chassis"]["g"]["rails"]["size"])])
	ps.close()
	await idle(2)
