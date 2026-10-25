## godot --path . -s tests/ouch_test.gd     (N064 OUCH METER, scripts/ouch_meter.gd; needs a window: main's input path and skin)
## While a joint is dragged it glows ok / warn / fail by comfortable vs max range, with a readout by the cursor.
## The drag is started by REAL mouse events into main._unhandled_input (a press on the part: dragging == "joint", sel == the part);
## the sweep then sets the joint's angle 1 deg at a time with B.set_ang (the table clamps it, as a drag's own edit would) and
## runs main._refresh(), the same per-frame path a mouse move ends in. BARS, written before measuring:
##  (1) ELBOW 0 -> 150 deg (right lowerarm bend; the table clamps at 145): green, yellow and red are all seen; the first yellow
##      angle is within 1 deg of LUBA's 120 (Kee & Karwowski 2001, via NTP 674: elbow flexion > 120 scores 5); the first red is
##      within 1 deg of the table's 145; green at 0 (a straight elbow is the bone's stop at rest, not a strain). Each frame the
##      skin's look table holds the zone's token colour on lowerarm_r (SkinPick state, RedSpots' FILL / RIM), and the readout
##      says "right elbow", the angle, the comfortable bar 120 and "max 145"
##  (2) HIP, knee straight (right thigh bend 0 -> 120, calf 0): red first within 1 deg of N028's hamstring bar 90 (NOT the table's
##      120), yellow first within 1 deg of 0.7 x 120 = 84 (COMFORT_FRAC: HEURISTIC); the readout names "knee straight" and the
##      hamstrings. Knee bent 60: no red below 119 (the coupling has let go; red only at the table's 120)
##  (3) TOGGLE OFF: the same elbow sweep lights nothing (ouch.lit empty, no readout, lowerarm_r keeps the pick look), the POSE
##      toolbar's "Ouch meter" button flips it, and the setting is saved in the settings file (pose / ouch_meter) both ways
##  (4) DRAG ONLY: a real mouse drag of the forearm lights it at every move; after the release nothing is lit and the readout hides
##  (5) COST: OuchMeter.apply (judge + look + readout) per frame, over every frame of (1) and (2): median < 0.5 ms and 95th
##      percentile < 0.5 ms (its own Time.get_ticks_usec clock)
##  (6) THEME: ok / warn / fail text over the readout's box (say_bg over the world) is >= 4.5:1 (WCAG AA) in both palettes, and the
##      readout's colour follows a palette switch (light on, a frame, then put back)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _ev_btn(pos: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	return e


func _ev_move(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func _find(m: Node, part: String, at: Vector2) -> Vector2:
	for r in [0, 4, 8, 12, 18, 24, 32, 44]:
		for k in 16:
			var p: Vector2 = at + Vector2.from_angle(TAU * k / 16.0) * r
			if m._pick(p) == part:
				return p
	return Vector2(NAN, NAN)


func _screen_of(m: Node, part: String) -> Vector2:
	var c: Array = m.B.cap(part)
	return m.cam.unproject_position(((c[0] as Vector3) + (c[1] as Vector3)) * 0.5)


func _pose_zero(m: Node) -> void:
	var B: Body = m.B
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	m._refresh()


## press on part (a real press: main starts its joint drag); true when the press picked it
func _press(m: Node, part: String) -> bool:
	var at := _find(m, part, _screen_of(m, part))
	if is_nan(at.x):
		return false
	m._unhandled_input(_ev_btn(at, true))
	return m.sel == part and m.dragging == "joint"


func _release(m: Node) -> void:
	m._unhandled_input(_ev_btn(Vector2(10, 10), false))


func percentile(a: Array, q: float) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(round(q * (b.size() - 1))), 0, b.size() - 1)])


## sweep joint j's bend over [a0..a1] by 1 deg during the drag: [{a (the clamped angle), zone, text, look}]
func sweep(m: Node, j: String, a0: int, a1: int, cost: Array) -> Array:
	var B: Body = m.B
	var out := []
	for a in range(a0, a1 + 1):
		var v: Vector3 = B.ang[j]
		B.set_ang(j, Vector3(a, v.y, v.z))
		B.fk()
		m._refresh()
		cost.append(m.ouch.last_us)
		var st: Dictionary = m.skp.get("_state") if m.skp.get("_state") != null else {}
		out.append({"a": (B.ang[j] as Vector3).x, "asked": a, "zone": String(m.ouch.lit.get(j, "")), "text": m.ouch.readout_text(),
			"look": st.get(j, [])})
	return out


func first(rows: Array, zone: String) -> float:
	for r in rows:
		if r["zone"] == zone:
			return float(r["a"])
	return NAN


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.playing = false
	m.B.wep_on = false
	m.smart_drag = false
	m.keep_balance = false
	m.symmetry = false
	var B: Body = m.B
	var cost := []
	ok(m.ouch.on, "0 the ouch meter is on by default (test settings file: %s)" % m.settings)
	_pose_zero(m)

	# (1) the elbow
	var pressed := _press(m, "lowerarm_r")
	ok(pressed, "1 a press on the right forearm starts a joint drag (sel %s, dragging '%s')" % [m.sel, m.dragging])
	var el := sweep(m, "lowerarm_r", 0, 150, cost)
	var y1 := first(el, "warn")
	var r1 := first(el, "fail")
	var zones := {}
	var look_ok := true
	var bad_look := ""
	for r in el:
		zones[r["zone"]] = true
		var lk: Array = r["look"]
		var want := OuchMeter.look(r["zone"]) if r["zone"] != "" else []
		if r["zone"] == "" or lk.is_empty() or not (lk[0] as Color).is_equal_approx(want[0]) or absf(float(lk[1]) - float(want[1])) > 1e-6:
			look_ok = false
			if bad_look == "":
				bad_look = "at %.0f: zone '%s' look %s" % [r["a"], r["zone"], lk]
	ok(zones.has("ok") and zones.has("warn") and zones.has("fail") and el[0]["zone"] == "ok",
		"1 elbow 0->150: zones seen %s, at 0 deg '%s' (green)" % [zones.keys(), el[0]["zone"]])
	ok(absf(y1 - 120.0) <= 1.0 and absf(r1 - 145.0) <= 1.0,
		"1 elbow: first yellow at %.1f deg (LUBA 120 +-1), first red at %.1f deg (table 145 +-1); the drag clamps at %.1f" % [y1, r1, el[-1]["a"]])
	ok(look_ok, "1 every frame the skin's look on lowerarm_r is the zone's token at RedSpots' FILL / RIM %s" % bad_look)
	var t130: String = el[130]["text"]
	ok(t130.begins_with("right elbow 130°") and t130.contains("past comfortable (120°)") and t130.contains("max 145°"),
		"1 readout at 130: \"%s\"" % t130)
	print("     readouts: \"%s\" | \"%s\"" % [el[60]["text"], el[-1]["text"]])
	_release(m)

	# (2) the hip, knee straight then bent
	_pose_zero(m)
	pressed = _press(m, "thigh_r")
	ok(pressed, "2 a press on the right thigh starts a joint drag (sel %s)" % m.sel)
	var hp := sweep(m, "thigh_r", 0, 120, cost)
	var y2 := first(hp, "warn")
	var r2 := first(hp, "fail")
	ok(absf(r2 - 90.0) <= 1.0, "2 hip, knee straight: first red at %.1f deg (N028 hamstring bar 90 +-1, not the table's 120)" % r2)
	ok(absf(y2 - 84.0) <= 1.0, "2 hip, knee straight: first yellow at %.1f deg (0.7 x 120 = 84 +-1, HEURISTIC)" % y2)
	var t95: String = hp[95]["text"]
	ok(t95.contains("knee straight") and t95.contains("hamstrings") and t95.contains("90°") and t95.contains("max 120°"),
		"2 readout at 95: \"%s\"" % t95)
	_release(m)
	_pose_zero(m)
	B.set_ang("calf_r", Vector3(60, 0, 0))
	B.fk()
	m._refresh()
	pressed = _press(m, "thigh_r")
	var hb := sweep(m, "thigh_r", 0, 120, cost)
	var r3 := first(hb, "fail")
	ok(pressed and r3 >= 119.0, "2 hip, knee bent 60: first red at %.1f deg (the table's 120: the hamstrings let go)" % r3)
	print("     readout bent at 100: \"%s\"" % hb[100]["text"])
	_release(m)

	# (3) the toggle
	var btn: Button = null
	for b in m.ui_ribbon["POSE"].get_children():
		if b is Button and m.label_of(b) == "Ouch meter":
			btn = b
	ok(btn != null, "3 the POSE toolbar has an 'Ouch meter' toggle")
	if btn != null:
		btn.pressed.emit()
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(not m.ouch.on and cf.get_value("pose", "ouch_meter", true) == false, "3 the toggle turns it off and saves it (%s)" % cf.get_value("pose", "ouch_meter", "unset"))
	_pose_zero(m)
	pressed = _press(m, "lowerarm_r")
	var off := sweep(m, "lowerarm_r", 0, 150, [])
	var lit_any := false
	var txt_any := false
	var pick_kept := true
	var want_sel: Array = m._look_of("sel")
	for r in off:
		lit_any = lit_any or r["zone"] != ""
		txt_any = txt_any or r["text"] != ""
		var lk: Array = r["look"]
		pick_kept = pick_kept and not lk.is_empty() and (lk[0] as Color).is_equal_approx(want_sel[0])
	ok(pressed and not lit_any and not txt_any and pick_kept, "3 toggle off: nothing lit %s, no readout %s, the forearm keeps the pick look %s" % [not lit_any, not txt_any, pick_kept])
	_release(m)
	if btn != null:
		btn.pressed.emit()
	cf = ConfigFile.new()
	cf.load(m.settings)
	ok(m.ouch.on and cf.get_value("pose", "ouch_meter", false) == true, "3 pressed again: on and saved")

	# (4) a real mouse drag: lit at every move, nothing after the release
	_pose_zero(m)
	var at := _find(m, "lowerarm_r", _screen_of(m, "lowerarm_r"))
	m._unhandled_input(_ev_btn(at, true))
	var lit_moves := 0
	var prev := at
	for k in 12:
		var pos := at + Vector2(0, -6.0 * (k + 1))
		m._unhandled_input(_ev_move(pos, pos - prev))
		prev = pos
		m._refresh()
		if not m.ouch.lit.is_empty() and m.ouch.readout_text() != "":
			lit_moves += 1
	m._unhandled_input(_ev_btn(prev, false))
	m._refresh()
	ok(lit_moves == 12 and m.ouch.lit.is_empty() and m.ouch.readout_text() == "",
		"4 a real drag: lit at %d / 12 moves; after the release lit %s, readout '%s'" % [lit_moves, m.ouch.lit, m.ouch.readout_text()])

	# (5) cost
	var med := percentile(cost, 0.5)
	var p95 := percentile(cost, 0.95)
	ok(cost.size() > 300 and med < 500.0 and p95 < 500.0, "5 cost per drag frame over %d frames: median %.0f us, 95th %.0f us, max %.0f us (bar 500 us)" % [cost.size(), med, p95, percentile(cost, 1.0)])

	# (6) theme
	var worst := INF
	var worst_what := ""
	for dk in [true, false]:
		Tok.set_dark(dk)
		var box: Color = Tok.c("say_bg")
		var bg := Tok.c("world").lerp(Color(box.r, box.g, box.b), box.a)
		for z in OuchMeter.ZONES:
			var r := Tok.contrast(Tok.c(z), bg)
			if r < worst:
				worst = r
				worst_what = "%s on %s" % [z, "dark" if dk else "light"]
	Tok.set_dark(true)
	ok(worst >= 4.5, "6 ok / warn / fail text on the readout box: lowest contrast %.2f:1 (%s), bar 4.5" % [worst, worst_what])
	_pose_zero(m)
	_press(m, "lowerarm_r")
	B.set_ang("lowerarm_r", Vector3(130, 0, 0))
	B.fk()
	Tok.set_dark(false)
	m._refresh()
	var lc: Color = m.ouch._label.get_theme_color("font_color")
	var follows := lc.is_equal_approx(Tok.c("warn"))
	Tok.set_dark(true)
	m._refresh()
	follows = follows and (m.ouch._label.get_theme_color("font_color") as Color).is_equal_approx(Tok.c("warn"))
	ok(follows, "6 the readout's colour follows the palette (light warn, then dark warn)")
	_release(m)

	print("ouch: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
