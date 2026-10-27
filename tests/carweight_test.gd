extends SceneTree
## godot --path . --position 4000,4000 -s tests/carweight_test.gd     (VEHICLE, STEP 4 WEIGHT AND BALANCE: scripts/car_weight.gd, car_weight_plan.gd, package_screen.gd; a window for the UI bars)
## Bars, written before measuring:
##   0 LOADS     5 drive layouts; every placeable part has a name, a mass and a note in data/car_parts.json (the masses are estimates)
##   1 AXLE 50   two 100 kg point masses at the front axle and at the rear axle: front share 50 / 50 exactly (0.0001)
##   2 AXLE 75   a 100 kg mass at 1/4 wheelbase behind the front axle: 75 kg front, 25 kg rear, +-0.1 %
##   3 CORNERS   the car as built (default layout, 2 passengers, 40 kg cargo): the four corner loads add to the total within 0.01 kg
##   4 CG STACK  a hand stack 100 kg at z 500, 200 kg at z 900, 300 kg at z 300: CG height 533.33 mm within 0.1 mm
##   5 FUEL      fill 0 -> 50 L adds 37.0 kg (0.74 kg/L) within 0.01
##   6 PRESETS   the engine's default place per layout: FWD and RWD ahead of the front axle; Mid between the seats and the rear axle; Rear behind the rear axle
##   7 DRIVER    no body mass: the driver is 75 kg; a junk record falls back to the start and a fuel fill is clamped to the tank
##   8 COMPARE   the front share and the total mass against the real Hatch cars (1300 and 1350 kg, 0.61 and 0.60): a 0.9 front share is red; the default total is red too, with the hint that the body panels (step 5) are not in the total yet
##   9 DRAG PURE moving the engine forward 100 mm raises the front share (and lowers the rear)
##  10 TYRE      a 225/45R17 tyre and rim: 6.7e-5 x 225 x 634 + 6 kg
##  11 SAVE PURE the file form (Vehicle.to_file / from_file) keeps the weight record, the layout, the fuel, the passengers and a moved part
##  12 3D PURE   build_3d gives a node with the CG sphere and one block per placeable part
##  --- the UI (a window, 1280 x 720, signals and real mouse events):
##  13 STEPS     4 Weight is live (not greyed): one click shows the weight panel; 5 Body stays greyed; 1 and 2 still switch
##  14 LAYOUT    a drive layout change = one undo step; the same layout again = none; the parts go to the layout's places
##  15 FUEL      the fuel slider 0 -> 50 L: one undo step, the total mass rises by 37.0 kg
##  16 DRAG      a real mouse drag of the engine 100 mm forward on the side view: one undo step, the front share rises, Undo puts it back
##  17 TOPDRAG   a real drag of the battery across on the top view: one undo step, its lateral place moves
##  18 SAVE UI   the saved record (Vehicle.to_file) reopened keeps the moved engine and the fuel
##  19 3D UI     See it in 3D: the weight blocks and the CG sphere are in the 3D tree
##  20 LAYOUT1280 at 1280 x 720 the top bar, the drawings, the weight panel and the status line overlap nothing and sit in the window
##  21 WORDS     no key name in the weight panel or the status line
## Shots in C:/Temp/claude/carbuild/: weight_easy.png (the drawings with the parts and the readouts), weight_3d.png (the 3D view).

const SHOT := "C:/Temp/claude/carbuild"
const DIRT := "user://carweight_test"
const CW := preload("res://scripts/car_weight.gd")
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
	print("carweight: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## a point mass item for the pure bars
func pt(kg: float, x: float, y := 0.0, z := 500.0) -> Dictionary:
	return {"id": "t", "name": "test", "kind": "part", "kg": kg, "x": x, "y": y, "z": z, "placeable": false, "w": 0.0, "h": 0.0}


func headless_bars() -> void:
	var p := CarPackage.start("Hatch")
	var c := CarChassis.start()
	var su := CarSusp.start()
	var w0 := CW.start(p)
	# 0 LOADS
	var parts_ok: bool = CW.data().has("parts") and CW.data()["parts"].has("engine") and CW.data()["parts"].has("seat")
	var notes_ok := true
	for k in (CW.data()["parts"] as Dictionary).keys():
		if String((CW.data()["parts"] as Dictionary)[k].get("note", "")) == "":
			notes_ok = false
	ok(CW.LAYOUTS.size() == 5 and parts_ok and notes_ok and String(CW.data().get("note", "")).contains("ESTIMATE"),
		"0 LOADS %d layouts; every part has a note (%s); the file says ESTIMATE" % [CW.LAYOUTS.size(), notes_ok])
	# 1 AXLE 50
	var wb := float(p["wheelbase"])
	var s1 := CW.analyse([pt(100.0, 0.0), pt(100.0, wb)], p)
	ok(absf(float(s1["front_split"]) - 0.5) <= 0.0001 and absf(float(s1["front"]) - 100.0) <= 0.0001,
		"1 AXLE 50 front share %.5f (50 %%), front %.3f kg" % [float(s1["front_split"]), float(s1["front"])])
	# 2 AXLE 75
	var s2 := CW.analyse([pt(100.0, wb * 0.25)], p)
	ok(absf(float(s2["front"]) - 75.0) <= 0.075 and absf(float(s2["rear"]) - 25.0) <= 0.025,
		"2 AXLE 75 1/4 wheelbase behind the front: front %.3f kg, rear %.3f kg (75 / 25 within 0.1 %%)" % [float(s2["front"]), float(s2["rear"])])
	# 3 CORNERS: the car as built
	var w3 := CW.start(p)
	w3["pax"] = 2
	w3["cargo_kg"] = 40.0
	var s3 := CW.summary(p, c, su, w3)
	var cn: Dictionary = s3["corners"]
	var csum: float = float(cn["fl"]) + float(cn["fr"]) + float(cn["rl"]) + float(cn["rr"])
	ok(absf(csum - float(s3["total"])) <= 0.01, "3 CORNERS four corners %.3f kg = total %.3f kg (within 0.01)" % [csum, float(s3["total"])])
	# 4 CG STACK
	var s4 := CW.analyse([pt(100.0, 0.0, 0.0, 500.0), pt(200.0, 0.0, 0.0, 900.0), pt(300.0, 0.0, 0.0, 300.0)], p)
	ok(absf(float(s4["cg_z"]) - 533.3333) <= 0.1, "4 CG STACK CG %.4f mm (533.33 by hand, within 0.1 mm)" % float(s4["cg_z"]))
	# 5 FUEL
	var wf0 := CW.start(p)
	wf0["fuel_l"] = 0.0
	var wf1 := CW.start(p)
	wf1["fuel_l"] = 50.0
	var dfuel := float(CW.summary(p, c, su, wf1)["total"]) - float(CW.summary(p, c, su, wf0)["total"])
	ok(absf(dfuel - 37.0) <= 0.01, "5 FUEL 0 -> 50 L adds %.3f kg (37.0 within 0.01)" % dfuel)
	# 6 PRESETS
	var pres := {}
	var hx := float(p["hpt_x"])
	for lay in CW.LAYOUTS:
		var w6 := CW.start(p)
		w6["layout"] = lay
		pres[lay] = float(CW.default_pos(p, w6, "engine").x)
	var fr_ok: bool = float(pres["Front engine FWD"]) < 0.0 and float(pres["Front engine RWD"]) < 0.0
	var mid_ok: bool = float(pres["Mid engine"]) > hx and float(pres["Mid engine"]) < wb
	var rear_ok: bool = float(pres["Rear engine"]) > wb
	ok(fr_ok and mid_ok and rear_ok, "6 PRESETS engine lon: FWD %.0f, RWD %.0f (ahead of the front axle); Mid %.0f (seats %.0f .. rear axle %.0f); Rear %.0f (behind the rear axle)" % [
		float(pres["Front engine FWD"]), float(pres["Front engine RWD"]), float(pres["Mid engine"]), hx, wb, float(pres["Rear engine"])])
	# 7 DRIVER
	var drv := 0.0
	for it in CW.items(p, c, su, w0):
		if String(it["id"]) == "driver":
			drv = float(it["kg"])
	var junk := CW.norm("junk", p)
	var clamp := CW.norm({"fuel_l": 999.0, "pax": 9}, p)
	ok(absf(drv - 75.0) <= 0.001 and JSON.stringify(junk) == JSON.stringify(CW.start(p)) and float(clamp["fuel_l"]) <= CW.fuel_cap("Hatch") and int(clamp["pax"]) == 4,
		"7 DRIVER %.1f kg; a junk record is the start; fuel 999 L clamped to %.0f, passengers 9 to 4" % [drv, float(clamp["fuel_l"])])
	# 8 COMPARE
	var rows_def := CW.compare(p, CW.summary(p, c, su, w0))
	var fake := CW.summary(p, c, su, w0)
	fake["front_split"] = 0.9
	var rows_red := CW.compare(p, fake)
	var red_split := false
	var mass_hint := ""
	for r in rows_red:
		if r["key"] == "front_split":
			red_split = bool(r["red"])
	for r in rows_def:
		if r["key"] == "mass":
			mass_hint = String(r["hint"])
	ok(red_split and bool(rows_def[1]["red"]) and mass_hint.contains("body panels"), "8 COMPARE a 0.9 front share is red; the default total (%.0f kg, no body panels yet: step 5) is red with the hint: %s" % [float(rows_def[1]["yours"]), mass_hint])
	# 9 DRAG PURE
	var pb := [pt(150.0, -400.0, 0.0, 500.0), pt(1000.0, 800.0, 0.0, 300.0)]
	var pf := [pt(150.0, -500.0, 0.0, 500.0), pt(1000.0, 800.0, 0.0, 300.0)]
	var fb := float(CW.analyse(pb, p)["front_split"])
	var fa := float(CW.analyse(pf, p)["front_split"])
	ok(fa > fb and float(CW.analyse(pf, p)["rear"]) < float(CW.analyse(pb, p)["rear"]), "9 DRAG PURE engine 100 mm forward: front share %.4f -> %.4f" % [fb, fa])
	# 10 TYRE
	var tk := CW.tyre_kg(p)
	var want_t := 0.000067 * 225.0 * (17.0 * 25.4 + 2.0 * 225.0 * 0.45) + 6.0
	ok(absf(tk - want_t) <= 0.0001, "10 TYRE 225/45R17 tyre and rim %.3f kg (formula %.3f)" % [tk, want_t])
	# 11 SAVE PURE
	var w11 := CW.start(p)
	w11["layout"] = "Mid engine"
	w11["fuel_l"] = 30.0
	w11["pax"] = 3
	w11["at"] = {"engine": [1500.0, 0.0, 400.0]}
	var txt := JSON.stringify(Vehicle.to_file({"package": p, "chassis": c, "susp": su, "weight": w11}))
	var back := Vehicle.from_file(JSON.parse_string(txt))
	var bw: Dictionary = back.get("weight", {})
	ok(JSON.stringify(bw) == JSON.stringify(CW.norm(w11, p)) and String(bw.get("layout", "")) == "Mid engine" and float(bw.get("fuel_l", 0.0)) == 30.0,
		"11 SAVE PURE the weight record survives the file: layout %s, fuel %.0f, passengers %d, engine at %s" % [bw.get("layout", ""), float(bw.get("fuel_l", 0.0)), int(bw.get("pax", 0)), str(bw.get("at", {}))])
	# 12 3D PURE
	var n3 := CW.build_3d(p, c, su, w0)
	var blocks := 0
	for ch in n3.get_children():
		if String(ch.name).begins_with("part_"):
			blocks += 1
	ok(n3.find_child("cg", false, false) != null and blocks >= 5, "12 3D PURE the CG sphere and %d part blocks" % blocks)
	n3.free()


func _rect(ctl: Control) -> Rect2:
	return Rect2(ctl.get_global_rect())


func ev_mouse(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(pos: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	await ev_move(pos, false)
	await ev_mouse(pos, true)
	await ev_mouse(pos, false)
	await idle(3)


func texts_under(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
		out.append((n as Button).tooltip_text)
	if n is Control and (n as Control).tooltip_text != "":
		out.append((n as Control).tooltip_text)
	for ch in n.get_children():
		texts_under(ch, out)


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
	var b4: Button = ps.step_btns[4]
	var b5: Button = ps.step_btns[5]
	# 13 STEPS
	await click_ctl(b4)
	var on4: bool = ps.step == 4 and ps.weight_panel.visible and not ps.susp_panel.visible and b4.button_pressed and not b4.disabled
	await click_ctl(b2)
	await click_ctl(b4)
	ok(on4 and b5.disabled and ps.step == 4 and String(b4.text) == "4 Weight", "13 STEPS 4 Weight live: panel %s; 5 Body greyed %s; 2 and back to 4 work" % [on4, b5.disabled])
	# 14 LAYOUT
	var u0: int = m.undo.size()
	ps.wt_layout.item_selected.emit(1)
	await idle(2)
	var one: int = m.undo.size() - u0
	var rl := String(ps.weight()["layout"]) == "Front engine RWD"
	ps.wt_layout.item_selected.emit(1)
	await idle(2)
	var none: int = m.undo.size() - u0 - one
	ok(one == 1 and rl and none == 0, "14 LAYOUT a layout change: %d step (RWD %s); the same again: %d" % [one, rl, none])
	ps.wt_layout.item_selected.emit(0)
	await idle(2)
	# 15 FUEL: 0 -> 50 L by the slider, one step; the total up 37 kg
	var fsl: HSlider = ps.wt_sl["fuel"]
	ps._wt_commit("Fuel 0", _set_fuel(ps, 0.0))
	await idle(2)
	var t0 := _total(ps)
	var u1: int = m.undo.size()
	fsl.drag_started.emit()
	fsl.value = 50.0
	fsl.drag_ended.emit(true)
	await idle(3)
	var fuel_steps: int = m.undo.size() - u1
	var t1 := _total(ps)
	ok(fuel_steps == 1 and absf((t1 - t0) - 37.0) <= 0.01, "15 FUEL 0 -> 50 L: %d step, the total up %.3f kg (37.0)" % [fuel_steps, t1 - t0])
	# 16 DRAG the engine 100 mm forward on the side view
	ps.set_3d(false)
	await idle(2)
	var pl: CarWeightPlan = ps.weight_plan
	var eng := _block(pl, "engine", 0)
	var f0 := float(CW.analyse(CW.items(ps.pkg(), ps.chassis(), ps.susp(), ps.weight()), ps.pkg())["front_split"])
	var u2: int = m.undo.size()
	var from := eng.get_center()
	var dpx := -100.0 * pl.mm_px
	await ev_move(from, false)
	await ev_mouse(from, true)
	for i in 6:
		await ev_move(from + Vector2(dpx * float(i + 1) / 6.0, 0.0), true)
	await ev_mouse(from + Vector2(dpx, 0.0), false)
	await idle(3)
	var drag_steps: int = m.undo.size() - u2
	var ex := float(ps.weight()["at"].get("engine", [0.0])[0]) if ps.weight()["at"].has("engine") else 0.0
	var f1 := float(CW.analyse(CW.items(ps.pkg(), ps.chassis(), ps.susp(), ps.weight()), ps.pkg())["front_split"])
	ok(drag_steps == 1 and absf(ex - (-400.0 - 100.0)) <= 0.001 and f1 > f0, "16 DRAG engine 100 mm forward: %d step; engine lon %.0f; front share %.4f -> %.4f" % [drag_steps, ex, f0, f1])
	m._undo()
	await idle(3)
	var back_ok: bool = not ps.weight()["at"].has("engine")
	ok(back_ok, "16b UNDO the drag goes back to the layout's place")
	# 17 TOPDRAG: the battery across on the top view
	var bat := _block(pl, "battery", 1)
	var y0 := float(ps.weight()["at"].get("battery", [0.0, 0.0, 0.0])[1]) if ps.weight()["at"].has("battery") else -300.0
	var u3: int = m.undo.size()
	var tf := bat.get_center()
	await ev_move(tf, false)
	await ev_mouse(tf, true)
	for i in 4:
		await ev_move(tf + Vector2(0.0, 200.0 * pl.mm_px * float(i + 1) / 4.0), true)
	await ev_mouse(tf + Vector2(0.0, 200.0 * pl.mm_px), false)
	await idle(3)
	var top_steps: int = m.undo.size() - u3
	var y1 := float(ps.weight()["at"].get("battery", [0.0, 0.0, 0.0])[1]) if ps.weight()["at"].has("battery") else 0.0
	ok(top_steps == 1 and y1 != y0, "17 TOPDRAG the battery across: %d step, lateral %.0f -> %.0f mm" % [top_steps, y0, y1])
	# 18 SAVE UI
	var txt := JSON.stringify(Vehicle.to_file(m.S.vehicle))
	var back := Vehicle.from_file(JSON.parse_string(txt))
	var bw: Dictionary = back.get("weight", {})
	ok(JSON.stringify(bw) == JSON.stringify(ps.weight()) and bw.get("at", {}).has("battery") and float(bw.get("fuel_l", 0.0)) == 50.0,
		"18 SAVE UI the file keeps the moved battery and 50 L of fuel")
	# 19 3D UI
	ps.set_3d(true)
	await idle(3)
	var w3d := ps.car3d.find_child("weight3d", true, false)
	var cg := ps.car3d.find_child("cg", true, false)
	ok(w3d != null and cg != null, "19 3D UI the weight blocks and the CG sphere are in the 3D tree")
	ps.frame()
	await shot("weight_3d")
	ps.set_3d(false)
	await idle(3)
	# 20 LAYOUT1280
	var vpr := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rs := {"bar": _rect(ps.get_node("package_bar")), "plan": _rect(ps.weight_plan), "weight": _rect(ps.weight_panel), "status": _rect(ps.status)}
	var clash := []
	for a in rs:
		if not vpr.encloses(rs[a]):
			clash.append("%s outside" % a)
		for b in rs:
			if a < b and rs[a].intersects(rs[b]):
				clash.append("%s/%s" % [a, b])
	ok(clash.is_empty(), "20 LAYOUT1280 at 1280 x 720 weight step: nothing overlaps, all in the window %s" % str(clash))
	await shot("weight_easy")
	# 21 WORDS
	var tx := []
	texts_under(ps.weight_panel, tx)
	tx.append(ps.status_l.text)
	var kk := ""
	for t in tx:
		kk = kk if kk != "" else key_in(String(t))
	ok(kk == "" and tx.size() > 20, "21 WORDS no key name in the weight panel or the status (%d texts, first key name %s)" % [tx.size(), kk])
	ps.close()
	await idle(2)


func _set_fuel(ps: PackageScreen, v: float) -> Dictionary:
	var rec: Dictionary = ps.weight()
	rec["fuel_l"] = v
	return rec


func _total(ps: PackageScreen) -> float:
	return float(CW.summary(ps.pkg(), ps.chassis(), ps.susp(), ps.weight())["total"])


## the drawn block of a part on a view (0 side, 1 top), from the plan's last draw
func _block(pl: CarWeightPlan, id: String, view: int) -> Rect2:
	for b in pl.blocks:
		if String(b["id"]) == id and int(b["view"]) == view:
			var r: Rect2 = b["rect"]
			return Rect2(pl.global_position + r.position, r.size)   # global, for the mouse events
	return Rect2()



