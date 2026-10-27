extends SceneTree
## godot --path . --position 4000,4000 -s tests/carsusp_test.gd     (VEHICLE, STEP 3 SUSPENSION: scripts/car_susp.gd, car_susp_plan.gd, package_screen.gd; a window for the UI bars)
## Bars, written before measuring:
##   0 LOADS     the start record (MacPherson strut, twist beam); 2 front and 2 rear choices; a junk record falls back to the start
##   1 CAMBER    a hand corner (contact patch (0, 770, 0), wheel centre (0, 762, 316)): camber = atan2(-8, 316) deg within 0.05
##   2 KPI SCRUB the hand corner of the brief (lower ball joint (0, 700, 200), top (-40, 650, 750), contact (0, 770, 0)): KPI = atan2(50, 550)
##               within 0.05 deg; scrub = 770 - ground point (718.18) = 51.82 mm within 0.05; caster = atan2(40, 550) within 0.05
##   3 RC FLAT   symmetric parallel equal arms (both horizontal): the roll centre is at ground level (0 within 1 mm)
##   4 RC CONVERGE converging arms (the upper arm rising outboard, the lines meet inboard at y = -1700): roll centre 62.35 mm within 1 and > 0
##   5 BOUNCE    all 4 choices x Bounce +80 and -80: every link keeps its length within 0.5 mm, the solver converges, the wheel centre
##               moves by the travel within 0.5 mm
##   6 RANGES    the MacPherson default (Hatch): camber, KPI, scrub, caster and roll centre are all inside the typical ranges (none red)
##   7 RED       a camber of -3 deg is outside -2..0 and gets a plain hint; a camber of -1 gets none
##   8 CLEAR     the clearance to the chassis at full bump or rebound is above 0 for all 4 choices (Hatch default)
##   9 NORM      a junk front choice falls back to MacPherson strut, a known one is kept
##  --- the UI (a window, 1280 x 720, signals and real clicks):
##  10 STEPS     the 3 Suspension step is live (not greyed): one click shows the suspension panel; 2 Chassis and 1 Package click back; the package and the chassis unchanged
##  11 GREY      5 Body stays greyed; 4 Weight is live since 8f2ab9f7 (redefined: it was greyed here)
##  12 UNDO      a front choice = one undo step; the same choice again = none; the rear = one step; Bounce = none
##  13 BOUNCE    Bounce +80 lifts the 3D front-left tyre by the travel (within 2 mm) and back at 0
##  14 WORDS     no key name in the suspension panel or the status line
##  15 LAYOUT    at 1280 x 720 the top bar, the drawings, the suspension panel and the status line overlap nothing
##  16 SAVE      the file form (Vehicle.to_file, JSON text, Vehicle.from_file) keeps the suspension choices, the package and the chassis
##  17 LINKS3D   every link and pivot of all 4 choices, both axles, both sides, at Bounce 0 and +80: the 3D node exists and both its ends are within 1 mm of the solved pivots
##  18 TRAVEL3D  Bounce +80: the front-left wheel mesh centre is 80 +- 1 mm higher than at 0 (relative to the body), and the links follow (ends within 1 mm)
##  19 PLAN FILL at 1280 x 720 the front view and the side view drawn geometry (top to bottom in px) are >= 70 % of each panel's height, one scale for both
## Shots in C:/Temp/claude/carbuild/: susp_front.png (the front and side views at Bounce 0), susp_3d.png (the 3D view at Bounce +80).

const SHOT := "C:/Temp/claude/carbuild"
const DIRT := "user://carsusp_test"
const CS := preload("res://scripts/car_susp.gd")
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
	link_bars()
	await ui_bars()
	print("carsusp: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _combos() -> Array:
	var out := []
	for f in CS.FRONT_OPTS:
		for r in CS.REAR_OPTS:
			out.append({"front": f, "rear": r})
	return out


func headless_bars() -> void:
	var st := CS.start()
	ok(String(st["front"]) == "MacPherson strut" and String(st["rear"]) == "Twist beam" and CS.FRONT_OPTS.size() == 2 and CS.REAR_OPTS.size() == 2,
		"0 LOADS start %s / %s; %d front, %d rear choices" % [st["front"], st["rear"], CS.FRONT_OPTS.size(), CS.REAR_OPTS.size()])
	# 1 CAMBER: hand corner, wheel top leaning in
	var C := Vector3(0.0, 770.0, 0.0)
	var W := Vector3(0.0, 762.0, 316.0)
	var want_cam := rad_to_deg(atan2(762.0 - 770.0, 316.0))
	var got_cam := CS.camber_deg(W, C)
	ok(absf(got_cam - want_cam) <= 0.05, "1 CAMBER hand corner: %.3f deg (atan2 %.3f, within 0.05)" % [got_cam, want_cam])
	# 2 KPI, SCRUB, CASTER from the hand corner
	var L := Vector3(0.0, 700.0, 200.0)
	var T := Vector3(-40.0, 650.0, 750.0)
	var want_kpi := rad_to_deg(atan2(50.0, 550.0))
	var ground_y := 700.0 + (-200.0 / 550.0) * (650.0 - 700.0)
	var want_scrub := 770.0 - ground_y
	var want_cast := rad_to_deg(atan2(40.0, 550.0))
	var got_kpi := CS.kpi_deg(L, T)
	var got_scrub := CS.scrub_mm(L, T, C)
	var got_cast := CS.caster_deg(L, T)
	ok(absf(got_kpi - want_kpi) <= 0.05 and absf(got_scrub - want_scrub) <= 0.05 and absf(got_cast - want_cast) <= 0.05,
		"2 KPI SCRUB CASTER: KPI %.3f (want %.3f), scrub %.3f mm (want %.3f, ground %.2f), caster %.3f (want %.3f)" % [got_kpi, want_kpi, got_scrub, want_scrub, ground_y, got_cast, want_cast])
	# 3 RC FLAT: parallel equal horizontal arms
	var po_flat := {"C": Vector3(0.0, 770.0, 0.0), "L": Vector3(0.0, 700.0, 200.0), "T": Vector3(0.0, 700.0, 500.0)}
	var arms_flat := {"lf": Vector3(150.0, 300.0, 200.0), "lr": Vector3(-150.0, 300.0, 200.0), "uf": Vector3(150.0, 300.0, 500.0), "ur": Vector3(-150.0, 300.0, 500.0), "strut": false}
	var rc_flat := CS.rc_height(po_flat, arms_flat)
	ok(absf(rc_flat) <= 1.0, "3 RC FLAT parallel equal arms: roll centre %.3f mm (0 within 1)" % rc_flat)
	# 4 RC CONVERGE: the upper arm rises outboard, the arms meet inboard
	var arms_conv := {"lf": Vector3(150.0, 300.0, 200.0), "lr": Vector3(-150.0, 300.0, 200.0), "uf": Vector3(150.0, 300.0, 450.0), "ur": Vector3(-150.0, 300.0, 450.0), "strut": false}
	var po_conv := {"C": C, "L": Vector3(0.0, 700.0, 200.0), "T": Vector3(0.0, 700.0, 500.0)}
	var rc_conv := CS.rc_height(po_conv, arms_conv)
	var want_rc := 770.0 * 200.0 / 2470.0
	ok(rc_conv > 0.0 and absf(rc_conv - want_rc) <= 1.0, "4 RC CONVERGE converging arms: roll centre %.2f mm (hand %.2f within 1, > 0)" % [rc_conv, want_rc])
	# 5 BOUNCE: links, convergence, travel
	var worst := 0.0
	var conv := true
	var travel_err := 0.0
	var p := CarPackage.start("Hatch")
	var c := CarChassis.start()
	for combo in _combos():
		var g := CS.geo(p, c, combo)
		for ax in ["front", "rear"]:
			var cn: Dictionary = g[ax]
			var st0 := CS.links(cn, CS.pose(cn, 0.0))
			for sg in [CS.TRAVEL, -CS.TRAVEL]:
				var po := CS.pose(cn, sg)
				conv = conv and bool(po["ok"])
				var lk := CS.links(cn, po)
				for i in lk.size():
					worst = maxf(worst, absf(float(lk[i]) - float(st0[i])))
				travel_err = maxf(travel_err, absf(((po["W"] as Vector3).z - (cn["W"] as Vector3).z) - sg))
	ok(worst <= 0.5 and conv and travel_err <= 0.5, "5 BOUNCE 4 choices x +-80: worst link change %.4f mm (within 0.5), all converged %s, wheel travel error %.4f mm (within 0.5)" % [worst, conv, travel_err])
	# 6 RANGES: the MacPherson default
	var rows := CS.checks(p, c, CS.start())
	var reds := []
	var txt := []
	for r in rows:
		txt.append("%s %.2f" % [r["key"], float(r["value"])])
		if bool(r["red"]):
			reds.append(String(r["key"]))
	ok(reds.is_empty() and rows.size() == 5, "6 RANGES MacPherson default on Hatch: %s; red: %s" % [", ".join(txt), str(reds)])
	# 7 RED: a camber outside the range gets a hint
	var h_red := CS.hint("camber", -3.0)
	ok(not CS.in_range("camber", -3.0) and h_red != "" and CS.hint("camber", -1.0) == "", "7 RED camber -3: hint %s; camber -1: no hint" % h_red)
	# 8 CLEAR: clearance at full bump / rebound for all choices
	var cl := INF
	for combo in _combos():
		cl = minf(cl, minf(CS.clearance(p, c, combo, CS.TRAVEL), CS.clearance(p, c, combo, -CS.TRAVEL)))
	ok(cl > 0.0, "8 CLEAR smallest gap to the chassis at full bump or rebound, all 4 choices: %.1f mm (above 0)" % cl)
	# 9 NORM
	ok(String(CS.norm({"front": "junk"})["front"]) == "MacPherson strut" and String(CS.norm({"front": "Double wishbone"})["front"]) == "Double wishbone", "9 NORM junk falls back, a known choice is kept")


## bars 17 and 18: the 3D links against the solved pivots (headless: the nodes are built, not shown)
func link_bars() -> void:
	var p := CarPackage.start("Hatch")
	var c := CarChassis.start()
	var wb := float(p["wheelbase"])
	var worst := 0.0
	var n_links := 0
	var n_ok := 0
	for combo in _combos():
		for sb in [0.0, CS.TRAVEL]:
			var sus: Node3D = CS.build_3d(p, c, combo, sb)
			var g := CS.geo(p, c, combo)
			for axle in ["front", "rear"]:
				var cn: Dictionary = g[axle]
				var po := CS.pose(cn, sb)
				for sd in [1.0, -1.0]:
					var side_name := "%s_%s" % [axle, "left" if sd > 0.0 else "right"]
					var node := sus.get_node_or_null(side_name)
					for li in CS.link_list(cn, po, sd):
						n_links += 1
						var mi: MeshInstance3D = node.get_node_or_null(String(li["name"])) if node != null else null
						if mi == null:
							continue
						var e := CS.ends(mi)
						var want_a := CS.to3(li["a"], wb)
						var want_b := CS.to3(li["b"], wb)
						var d := maxf((e[0] as Vector3).distance_to(want_a), (e[1] as Vector3).distance_to(want_b))
						worst = maxf(worst, d)
						if d <= 0.001:
							n_ok += 1
	ok(n_links > 0 and n_ok == n_links and worst <= 0.001, "17 LINKS3D %d links and pivots of 4 choices x both axles x both sides x Bounce 0 and +80: %d within 1 mm, worst end error %.4f mm" % [n_links, n_ok, worst * 1000.0])
	# 18: the front-left wheel centre rises by the travel
	var cb := CS.build_3d(p, c, CS.start(), 0.0)
	var ca := CS.build_3d(p, c, CS.start(), CS.TRAVEL)
	var dz := ((ca.get_node("front_left/tyre") as Node3D).position.y - (cb.get_node("front_left/tyre") as Node3D).position.y) * 1000.0
	var lk_ok := true
	for nm in ["link_lower_f", "link_strut", "link_knuckle"]:
		var a := CS.ends(cb.get_node("front_left/" + nm) as MeshInstance3D)
		var b := CS.ends(ca.get_node("front_left/" + nm) as MeshInstance3D)
		var moved := (a[0] as Vector3).distance_to(b[0] as Vector3) > 0.005 or (a[1] as Vector3).distance_to(b[1] as Vector3) > 0.005
		lk_ok = lk_ok and moved
	ok(absf(dz - CS.TRAVEL) <= 1.0 and lk_ok, "18 TRAVEL3D front-left wheel centre rises %.3f mm at +80 (80 within 1), the links move %s" % [dz, lk_ok])


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
	var b3: Button = ps.step_btns[3]
	var pk0 := JSON.stringify(ps.pkg())
	var ch0 := JSON.stringify(ps.chassis())
	# 10 STEPS: 2, then 3 (live), then 2 and 1 back; package and chassis unchanged
	await click_ctl(b2)
	await click_ctl(b3)
	var on3: bool = ps.step == 3 and ps.susp_panel.visible and not ps.chassis_panel.visible and not ps.panel.visible and b3.button_pressed and not b3.disabled
	await click_ctl(b2)
	await click_ctl(b1)
	var back1: bool = ps.step == 1 and ps.panel.visible and not ps.susp_panel.visible
	var same := pk0 == JSON.stringify(ps.pkg()) and ch0 == JSON.stringify(ps.chassis())
	ok(on3 and back1 and same, "10 STEPS 3 Suspension live: panel %s; back to 1 Package %s; package and chassis unchanged %s" % [on3, back1, same])
	# 11 GREY
	var g5: bool = (ps.step_btns[5] as Button).disabled and not (ps.step_btns[4] as Button).disabled   # 8f2ab9f7: 4 Weight is live, 5 Body stays greyed
	ok(g5 and String(b3.text) == "3 Suspension", "11 GREY 5 Body stays greyed; 4 Weight is live (8f2ab9f7): %s" % g5)
	await click_ctl(b3)
	# 12 UNDO: one step per choice; Bounce is none
	var u0: int = m.undo.size()
	ps.sp_front.item_selected.emit(1)
	await idle(2)
	var one: int = m.undo.size() - u0
	var front_is := String(ps.susp()["front"]) == "Double wishbone"
	ps.sp_front.item_selected.emit(1)
	await idle(2)
	var same_none: int = m.undo.size() - u0 - one
	ps.sp_rear.item_selected.emit(1)
	await idle(2)
	var rear_one: int = m.undo.size() - u0 - one - same_none
	ps.sp_bounce.value = 80.0
	await idle(2)
	var bounce_none: int = m.undo.size() - u0 - one - same_none - rear_one
	ok(one == 1 and front_is and same_none == 0 and rear_one == 1 and bounce_none == 0,
		"12 UNDO front to wishbone: %d step; again: %d; rear multilink: %d; Bounce: %d" % [one, same_none, rear_one, bounce_none])
	m._undo()
	await idle(2)
	m._undo()
	await idle(2)
	ok(String(ps.susp()["front"]) == "MacPherson strut" and String(ps.susp()["rear"]) == "Twist beam", "12b UNDO twice goes back to MacPherson and twist beam")
	ps.sp_front.item_selected.emit(1)
	await idle(2)
	ps.sp_rear.item_selected.emit(1)
	await idle(2)
	# 13 BOUNCE: the 3D front-left tyre moves with the travel
	ps.sp_bounce.value = 0.0
	await idle(2)
	ps.set_3d(true)
	await idle(3)
	var sus := ps.car3d.find_child("suspension3d", true, false) as Node3D
	var y0: float = (sus.get_node("front_left/tyre") as Node3D).position.y
	ps.sp_bounce.value = 80.0
	await idle(3)
	sus = ps.car3d.find_child("suspension3d", true, false) as Node3D
	var y80: float = (sus.get_node("front_left/tyre") as Node3D).position.y
	ps.sp_bounce.value = 0.0
	await idle(2)
	ok(absf((y80 - y0) - 0.08) <= 0.002, "13 BOUNCE the 3D front-left tyre lifts %.4f m at +80 (0.08 within 2 mm)" % (y80 - y0))
	ps.set_3d(false)
	await idle(2)
	# 14 WORDS
	var tx := []
	texts_under(ps.susp_panel, tx)
	tx.append(ps.status_l.text)
	var kk := ""
	for t in tx:
		kk = kk if kk != "" else key_in(String(t))
	ok(kk == "" and tx.size() > 20, "14 WORDS no key name in the suspension panel or status (%d texts, first key name %s)" % [tx.size(), kk])
	# 15 LAYOUT at 1280 x 720
	var vpr := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rs := {"bar": _rect(ps.get_node("package_bar")), "plan": _rect(ps.susp_plan), "susp": _rect(ps.susp_panel), "status": _rect(ps.status)}
	var clash := []
	for a in rs:
		if not vpr.encloses(rs[a]):
			clash.append("%s outside" % a)
		for b in rs:
			if a < b and rs[a].intersects(rs[b]):
				clash.append("%s/%s" % [a, b])
	ok(clash.is_empty(), "15 LAYOUT at 1280 x 720 suspension step: nothing overlaps, all in the window %s" % str(clash))
	ps.sp_front.item_selected.emit(0)
	ps.sp_rear.item_selected.emit(0)
	await idle(2)
	await shot("susp_front")
	# 19 PLAN FILL: the drawn geometry of both views, in px of the plan, against the plan's height
	var pl: CarSuspPlan = ps.susp_plan
	var ph := pl.size.y
	var fr := float(pl.ext["front"][1]) - float(pl.ext["front"][0])
	var sr := float(pl.ext["side"][1]) - float(pl.ext["side"][0])
	ok(fr >= 0.7 * ph and sr >= 0.7 * ph and absf(pl.size.y - 720.0) < 200.0,
		"19 PLAN FILL at 1280 x 720: front view %.0f %% of the panel height, side view %.0f %% (both >= 70 %%), one scale k %.3f px/mm" % [100.0 * fr / ph, 100.0 * sr / ph, pl.k])
	ps.set_3d(true)
	await idle(3)
	ps.sp_bounce.value = 80.0
	ps.frame_corner()
	await shot("susp_3d")
	ps.sp_bounce.value = 0.0
	ps.set_3d(false)
	await idle(2)
	ps.sp_front.item_selected.emit(1)
	ps.sp_rear.item_selected.emit(1)
	await idle(2)
	# 16 SAVE: the file text round trip (a non-default chassis too, so the chassis is really kept)
	ps.set_group_size("sills", "Strong")
	await idle(2)
	var txt2 := JSON.stringify(Vehicle.to_file(m.S.vehicle))
	var back := Vehicle.from_file(JSON.parse_string(txt2))
	var bs: Dictionary = back.get("susp", {})
	var keep := String(bs.get("front", "")) == String(ps.susp()["front"]) and String(bs.get("rear", "")) == String(ps.susp()["rear"])
	var pkg_ok := JSON.stringify(back.get("package", {})) == JSON.stringify(ps.pkg())
	var ch_ok := JSON.stringify(CarChassis.norm(back.get("chassis", {}))) == JSON.stringify(ps.chassis()) and String(ps.chassis()["g"]["sills"]["size"]) == "Strong"
	ok(keep and pkg_ok and ch_ok and String(bs.get("front", "")) == "Double wishbone", "16 SAVE file keeps the suspension (%s / %s), the package %s, the chassis %s" % [bs.get("front", ""), bs.get("rear", ""), pkg_ok, ch_ok])
	ps.close()
	await idle(2)
