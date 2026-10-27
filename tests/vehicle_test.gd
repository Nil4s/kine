extends SceneTree
## godot --path . --position 4000,4000 -s tests/vehicle_test.gd     (B3 VEHICLE: scripts/vehicle.gd, scripts/easy_vehicle.gd; needs the CAD DLL; a window for the UI bars)
## Bars, written before measuring (every size in the Part records is mm; the numbers below are m and m3):
##   0 KCad is available (the DLL is there; without it nothing can be measured and the suite fails)
##   1 WHEEL     the wheel (r 0.30 m, 0.20 m wide, a revolve) has volume pi r^2 w = 0.056549 m3 within 1 %
##   2 BODY      (REDEFINED for 73229623: the body is a side profile extruded across the width, not a box) its volume is between 45 % and
##               80 % of L W H, and equals the extruded profiles' areas x widths within 1 % (the lower body and the glasshouse, the arch
##               half-discs taken out of the lower body)
##   3 STRAIGHT  a car driven 10 m on a straight path: every 0.5 m, each of the four wheels has turned s / r within 1 %
##               (10 / 0.3 = 33.33 rad at the end); the pivots read back the same angle; the car ends at (0, 0, 10) within 1 mm
##   4 CURVE     an S-shaped path: each wheel turns (smoothed arc length) / r within 1 %, and that arc is more than 5 % longer than
##               the chord (so the bar tells arc from chord)
##   5 GROUND    every wheel's centre is r above the ground (the tyre touches y = 0 within 1 um)
##   6 CLEAR     the four wheels and the body share no volume (KCad intersect volume = 0; all 4 body-wheel pairs and the 6 wheel pairs)
##   7 CONTROL   (REDEFINED for 73229623) a wheel moved 5 cm UP into the arch top DOES share volume with the body (> 0.00005 m3, a 10 mm
##               slice of the tyre above the arch): the intersect check can fail
##   8 WHEELBASE a wheelbase of 1.80 m (from 1.584 m; the baseline is pinned to 1584 mm, the old default: 73229623): the front axles and the back axles move 108 mm each (the change / 2), and the
##               front-to-back distance is the wheelbase within 1 mm
##  15 CABIN    the body's top 30 % of height (the cabin) is narrower and shorter than its bottom 30 % (the chassis)
##  16 ARCHES   each wheel centre is inside the body's length, and each tyre's top is above the chassis bottom
##  17 PAINT    the body is amber paint (red well above blue), not the default grey
##  --- the UI (a window, 1280 x 720, real mouse through root.push_input; the chooser's Vehicle card, Easy):
##   9 CARD      the Vehicle card is live (Easy and Expert start it), not greyed
##  10 SLIDER    a real drag of Wheelbase 158 -> 178 cm: the car's axles move by 0.10 m each within 1 mm; ONE undo step per release
##               (a second drag, Length, is a second step; undo takes back the last one only)
##  11 DRIVE     "Drive it": each wheel's angle = the distance rolled / r within 1 % at every frame; the car ends on the path's length;
##               on the curve the lowest point of each tyre is within 5 mm of y = 0 (contact)
##  12 WORDS     no key name in any text of the Vehicle screen (labels, buttons, tooltips, status): ctrl shift alt esc enter tab delete backspace F1..F12
##  13 LAYOUT    at 1280 x 720 the top bar, the panel, the drive and use buttons, and the status line overlap nothing and stay inside the window
##  14 USE       "Use in a scene": the car is a prop of the set (kind car:Vehicle), STAGE opens, ONE undo step
## Shots in C:/Temp/claude/vehicle/: the Easy panel (s0_easy.png) and mid-drive (s1_drive.png). Only user:// is written (and the shots).

const KCad := preload("res://scripts/kcad.gd")
const SHOT := "C:/Temp/claude/vehicle"
const DIRT := "user://vehicle_test"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func near(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= rel * absf(b)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	ok(KCad.available(), "0 KCad is available (the CAD DLL is in native/bin/)")
	if not KCad.available():
		quit(1)
		return
	headless_bars()
	await ui_bars()
	print("vehicle: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func headless_bars() -> void:
	var car := PartTemplates.make("car")
	var wh := PartTemplates.make("wheel")
	var cp: Dictionary = car["easy"]["p"]
	var wp: Dictionary = wh["easy"]["p"]
	var r := float(wp["radius"]) * Part.MM
	var w := float(wp["width"]) * Part.MM

	# 1 wheel volume
	var wv := Part.replay(wh)["volume"] as float
	var wanted := PI * r * r * w
	ok(near(wv, wanted, 0.01), "1 WHEEL volume %.6f m3, pi r^2 w = %.6f (within 1 %%)" % [wv, wanted])

	# 2 body volume (redefined, 73229623): the body is extruded side profiles: the lower body (full width, its arch half-discs out)
	# and the glasshouse (CAB_W of the width); the volume is 45-80 % of L W H and equals those profiles' areas x widths within 1 %
	var bv := Part.replay(car)["volume"] as float
	var bw := float(cp["body_length"]) * float(cp["body_width"]) * float(cp["body_height"]) * Part.MM * Part.MM * Part.MM
	var sks := {}
	for f in car["features"]:
		if f["t"] == "sketch":
			sks[f["id"]] = f
	var prof_v := 0.0
	for f in car["features"]:
		if f["t"] != "extrude" or f["op"] == "cut":
			continue
		var area := sk_area(sks[f["sketch"]]["ents"])
		var wide := float(f["dist"]) * Part.MM
		if f["op"] == "new":   # the lower body: less the two arch half-discs (the circles of the cut sketches, centred on the sills)
			for g in car["features"]:
				if g["t"] == "extrude" and g["op"] == "cut":
					for e in sks[g["sketch"]]["ents"]:
						area -= PI * float(e["r"]) * float(e["r"]) * 0.5
		prof_v += area * Part.MM * Part.MM * wide
	ok(near(bv, prof_v, 0.01) and bv > 0.45 * bw and bv < 0.8 * bw, "2 BODY volume %.4f m3 = the profiles' area x width %.4f m3 (within 1 %%), %.0f %% of L W H = %.4f m3 (45-80 %%)" % [bv, prof_v, 100.0 * bv / bw, bw])

	var lay := Vehicle.layout(cp, wp)

	# 3 straight 10 m
	var straight := PathWalk.curve([Vector3(0, 0, 0), Vector3(0, 0, 10)])
	var root := Vehicle.build_node(car, wh)
	var pivots: Array = root.get_meta("wheels")
	var worst := 0.0
	var pivot_ok := true
	var s := 0.0
	while s <= 10.0 + 1e-6:
		var a := Vehicle.drive(root, straight, s)
		var want := s / r
		worst = maxf(worst, absf(a - want) / maxf(want, 1e-9))
		for pv in pivots:
			pivot_ok = pivot_ok and absf(-(pv as Node3D).rotation.x - want) <= 0.01 * maxf(want, 1e-9) + 1e-9
		s += 0.5
	var end_ok := root.position.distance_to(Vector3(0, 0, 10)) < 0.001
	ok(worst <= 0.01 and pivot_ok, "3 STRAIGHT 10 m: each wheel turns s / r (33.33 rad at the end), worst error %.4f %% of the angle, pivots agree" % (worst * 100.0))
	ok(end_ok and near(float(straight["len"]), 10.0, 0.001), "3 STRAIGHT the car ends at (0, 0, 10) within 1 mm (path %.4f m)" % float(straight["len"]))

	# 4 curve
	var curve := PathWalk.curve([Vector3(0, 0, 0), Vector3(0, 0, 4), Vector3(3, 0, 6), Vector3(3, 0, 10)])
	var L: float = curve["len"]
	var chord := Vector3(3, 0, 10).length()
	var a2 := Vehicle.drive(root, curve, L)
	ok(near(a2, L / r, 0.01) and L > chord * 1.05, "4 CURVE: each wheel turns %.4f rad = arc %.4f m / r (chord %.4f m, arc %.1f %% longer)" % [a2, L, chord, (L / chord - 1.0) * 100.0])

	# 5 ground
	var ground_ok := true
	for p in lay["wheels"]:
		ground_ok = ground_ok and absf((p as Vector3).y - r) < 1e-6
	ok(ground_ok, "5 GROUND: every wheel centre is r = %.3f m above the ground" % r)

	# 6 clearance: all pairs
	var ids := []
	var body := Vehicle.solid_at(car, lay["body"])
	ids.append(body)
	for p in lay["wheels"]:
		ids.append(Vehicle.solid_at(wh, p))
	var worst_v := 0.0
	var pairs := 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			worst_v = maxf(worst_v, Vehicle.overlap(ids[i], ids[j]))
			pairs += 1
	ok(pairs == 10 and worst_v == 0.0, "6 CLEAR: %d body/wheel pairs share no volume (worst %.6f m3)" % [pairs, worst_v])

	# 7 control (redefined, 73229623): a wheel moved 5 cm UP into the arch top must overlap the body (the arch is 40 mm above the tyre)
	var into := lay["wheels"][1] as Vector3
	into.y += 0.05
	var inside := Vehicle.solid_at(wh, into)
	var bad := Vehicle.overlap(body, inside)
	ok(bad > 0.00005, "7 CONTROL: a wheel 5 cm up into the arch top shares %.6f m3 (must be > 0.00005: a 10 mm slice of the tyre above the arch)" % bad)
	for id in ids:
		KCad.release(id)
	KCad.release(inside)
	root.free()

	# 8 wheelbase: 1.80 m from 1.584 m moves each axle pair by 108 mm (216 mm of wheelbase, half each way). The baseline is the old
	# default 1584 mm (73229623 moved the default to 2500 mm; the bar's numbers are unchanged)
	var cp1 := cp.duplicate()
	cp1["wheelbase"] = 1584.0
	var lay1 := Vehicle.layout(cp1, wp)
	var cp2 := cp1.duplicate()
	cp2["wheelbase"] = 1800.0
	var lay2 := Vehicle.layout(cp2, wp)
	var d_front: float = (lay2["wheels"][0] as Vector3).z - (lay1["wheels"][0] as Vector3).z
	var d_back: float = (lay2["wheels"][2] as Vector3).z - (lay1["wheels"][2] as Vector3).z
	var sep: float = (lay2["wheels"][0] as Vector3).z - (lay2["wheels"][2] as Vector3).z
	ok(absf(d_front - 0.108) < 0.001 and absf(d_back + 0.108) < 0.001 and absf(sep - 1.8) < 0.001,
		"8 WHEELBASE 1.80 m: front axles +%.1f mm, back axles %.1f mm, front-to-back %.1f mm" % [d_front * 1000.0, d_back * 1000.0, sep * 1000.0])

	# 15 CABIN: the body mesh's top 30 % of height (the cabin) is narrower and shorter than its bottom 30 % (the chassis)
	var bm: Mesh = Part.replay(car)["mesh"]
	var bvs := PackedVector3Array()
	for si in bm.get_surface_count():
		bvs.append_array(bm.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var ylo := INF
	var yhi := -INF
	for v in bvs:
		ylo = minf(ylo, v.y)
		yhi = maxf(yhi, v.y)
	var cab := _xz_span(bvs, yhi - 0.3 * (yhi - ylo), INF)
	var chs := _xz_span(bvs, -INF, ylo + 0.3 * (yhi - ylo))
	ok(cab.x < 0.9 * chs.x and cab.y < 0.6 * chs.y, "15 CABIN top 30 %% of the body: %.0f x %.0f mm, bottom 30 %%: %.0f x %.0f mm (width x length; the cabin must be narrower and shorter)" % [cab.x * 1000.0, cab.y * 1000.0, chs.x * 1000.0, chs.y * 1000.0])

	# 16 ARCHES: each wheel centre is inside the body's length, and each tyre's top is above the chassis bottom (the body's underside)
	var lay4 := Vehicle.layout(cp, wp)
	var in_len := true
	var top_ok := true
	for p in lay4["wheels"]:
		in_len = in_len and absf((p as Vector3).z) < float(cp["body_length"]) * Part.MM * 0.5
		top_ok = top_ok and (p as Vector3).y + r > (lay4["body"] as Vector3).y
	ok(in_len and top_ok, "16 ARCHES each wheel centre is inside the body's length and each tyre's top (%.0f mm) is above the chassis bottom (%.0f mm)" % [(r * 2.0) * 1000.0, (lay4["body"] as Vector3).y * 1000.0])

	# 17 PAINT: the body is painted (not the default grey): its body colour is amber (red well above blue) and its glass is dark
	var bnode := Vehicle.build_node(car, wh)
	var bmat := (bnode.get_node("body") as MeshInstance3D).material_override as ShaderMaterial
	var paint := Color(bmat.get_shader_parameter("body_color")) if bmat != null else Color()
	ok(bmat != null and paint.r - paint.b > 0.5 and paint.r > 0.5, "17 PAINT the body is amber paint (r %.2f g %.2f b %.2f), not the default grey" % [paint.r, paint.g, paint.b])
	bnode.free()


# ---------------------------------------------------------------- the UI (windowed)

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


## every text a Vehicle screen shows: labels, buttons, tooltips
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
	for k in EasyVehicle.BAD_WORDS:
		if low.contains(k) or low.contains(" " + k):
			return k
	return ""


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## RETIRED by 46d24c49 (w4-carpkg, Nick's standing OK for replaced designs): the Vehicle card no longer opens the ready-made car body
## (EasyVehicle). UI bars 9-14 assert that screen (is_car, the car's sliders, Drive it, the car in the set), so they do not run here.
## The package screen and its card bars are in tests/carpkg_test.gd (11, 12, 13, 14, 15).
const RETIRED_UI := true

func ui_bars() -> void:
	if RETIRED_UI:
		print("vehicle: UI bars 9-14 retired by 46d24c49 (see tests/carpkg_test.gd)")
		return
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

	# 9 CARD
	var vb: Button = bc.btns["vehicle"]["easy"]
	ok(bc.why_not("vehicle") == "" and (bc.cards["vehicle"] as CanvasItem).modulate.a == 1.0, "9 CARD the Vehicle card is live (why_not empty, not dimmed)")
	await click_ctl(vb)
	await idle(6)
	var ev = bc._car_screen   # retired 46d24c49: untyped (the card's screen is the package now)
	ok(ev != null and ev.visible and ev.is_car(), "9 CARD Easy opens the car screen with a car (S.part car %s, wheel %s)" % [ev != null and ev.is_car(), not m.S.vehicle.is_empty()])
	await shot("s0_easy")

	# 10 SLIDER: Wheelbase 158 -> 178 cm by a real drag: one undo step, the axles move 0.10 m each
	var sl: HSlider = ev.find_child("easyvehicle_slider_wheelbase", true, false)
	PartTemplates.retemplate(ev.car(), {"wheelbase": 1584.0})   # the bar starts at 158.4 cm (the default is 250 cm now: 73229623)
	ev._rebuild_view()
	ev._sync()
	var front0 := _front_z(ev)
	var u0: int = m.undo.size()
	var frac := (178.0 - sl.min_value) / (sl.max_value - sl.min_value)
	await drag_to(sl, frac)
	var front1 := _front_z(ev)
	var steps1: int = m.undo.size() - u0
	var moved := (sl.value - 158.4) * 0.005   # the wheelbase grows by the slider's change: each axle moves half of it
	ok(sl.value > 175.0 and absf((front1 - front0) - moved) < 0.001 and steps1 == 1, "10 SLIDER wheelbase 158.4 -> %.1f cm: each axle moved %.1f mm (half the change, within 1 mm) in %d undo step" % [sl.value, (front1 - front0) * 1000.0, steps1])
	var lsl: HSlider = ev.find_child("easyvehicle_slider_body_length", true, false)
	var before_len := float(m.S.part["easy"]["p"]["body_length"])
	var u1: int = m.undo.size()
	await drag_to(lsl, 0.3)   # the length starts at 400 cm (the default now), so the second drag goes down
	ok(m.undo.size() - u1 == 1, "10 SLIDER a second release is a second undo step (%d)" % (m.undo.size() - u1))
	m._undo()
	await idle(4)
	ok(absf(float(m.S.part["easy"]["p"]["body_length"]) - before_len) < 0.5 , "10 SLIDER undo takes back the last release only (length %.0f mm, was %.0f)" % [float(m.S.part["easy"]["p"]["body_length"]), before_len])

	# 11 DRIVE
	await click_ctl(ev.drive_btn)
	var t0 := Time.get_ticks_msec()
	var worst_angle := 0.0
	var worst_gap := 0.0
	var frames := 0
	var mid_shot := false
	while ev.driving and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		frames += 1
		var root3: Node3D = ev.car_root
		var want: float = ev.drive_s / float(root3.get_meta("r"))
		var pv: Array = root3.get_meta("wheels")
		for p in pv:
			var got := -(p as Node3D).rotation.x
			worst_angle = maxf(worst_angle, absf(got - want) / maxf(want, 1e-9))
			worst_gap = maxf(worst_gap, absf(root3.position.y + (p as Node3D).position.y - float(root3.get_meta("r"))))
		if not mid_shot and ev.drive_s > 8.0:
			mid_shot = true
			await shot("s1_drive")
	var r_end := float(ev.car_root.get_meta("r"))
	var end_want: float = float(ev.path["len"]) / r_end
	var end_ok := true
	for p in ev.car_root.get_meta("wheels"):
		end_ok = end_ok and near(-(p as Node3D).rotation.x, end_want, 0.01)
	ok(frames > 20 and worst_angle <= 0.01 and end_ok, "11 DRIVE each wheel turns distance / r within 1 %% at every frame (%d frames, worst %.4f %%), at the end %.2f rad = %.2f m / r" % [frames, worst_angle * 100.0, end_want, float(ev.path["len"])])
	ok(worst_gap < 0.005, "11 DRIVE contact: the lowest point of each tyre is within 5 mm of the ground (worst %.2f mm)" % (worst_gap * 1000.0))

	# 12 WORDS
	var tx := []
	texts_under(ev, tx)
	var kk := ""
	for t in tx:
		kk = kk if kk != "" else key_in(String(t))
	ok(kk == "" and tx.size() > 12, "12 WORDS no key name in the Vehicle screen's texts (%d texts, first key name '%s')" % [tx.size(), kk])

	# 13 LAYOUT at 1280 x 720
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rs := {"bar": _rect(ev.get_node("easyvehicle_bar")), "panel": _rect(ev.panel), "status": _rect(ev.status)}
	var clash := []
	for a in rs:
		if not vp.encloses(rs[a]):
			clash.append("%s outside" % a)
		for b in rs:
			if a < b and rs[a].intersects(rs[b]):
				clash.append("%s/%s" % [a, b])
	for k in ["drive", "use"]:   # the two buttons sit inside the panel and inside the window
		var br := _rect(ev.drive_btn if k == "drive" else ev.use_btn)
		if not rs["panel"].encloses(br) or not vp.encloses(br):
			clash.append("%s button outside the panel" % k)
	ok(clash.is_empty(), "13 LAYOUT at 1280 x 720 nothing overlaps and all stays in the window: %s" % str(clash))

	# 14 USE in a scene
	var u2: int = m.undo.size()
	await click_ctl(ev.use_btn)
	await idle(6)
	var has_car := false
	for p in m.S.props:
		has_car = has_car or String(p["kind"]) == "car:Vehicle"
	ok(has_car and m.cur_page == "STAGE" and m.undo.size() == u2 + 1 and not ev.visible, "14 USE the car is a prop of the set, STAGE opens, one undo step (page %s)" % m.cur_page)


## the area (mm2) of a closed sketch made of lines and 3-point arcs: the arcs sampled, then the shoelace formula (73229623)
func sk_area(ents: Array) -> float:
	var pts := PackedVector2Array()
	for e in ents:
		var a := Vector2(float(e["a"][0]), float(e["a"][1]))
		pts.append(a)
		if e["k"] == "arc":
			pts.append_array(arc_pts(a, Vector2(float(e["m"][0]), float(e["m"][1])), Vector2(float(e["b"][0]), float(e["b"][1]))))
	var s := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		s += p.x * q.y - q.x * p.y
	return absf(s) * 0.5


## the points strictly between a and b on the circle through a, m, b (the arc that passes m)
func arc_pts(a: Vector2, m: Vector2, b: Vector2) -> PackedVector2Array:
	var d := 2.0 * (a.x * (m.y - b.y) + m.x * (b.y - a.y) + b.x * (a.y - m.y))
	var a2 := a.length_squared()
	var m2 := m.length_squared()
	var b2 := b.length_squared()
	var c := Vector2((a2 * (m.y - b.y) + m2 * (b.y - a.y) + b2 * (a.y - m.y)) / d, (a2 * (b.x - m.x) + m2 * (a.x - b.x) + b2 * (m.x - a.x)) / d)
	var rad := (a - c).length()
	var ta := (a - c).angle()
	var full := fposmod((b - c).angle() - ta, TAU)
	var mid := fposmod((m - c).angle() - ta, TAU)
	if mid > full:
		full -= TAU
	var out := PackedVector2Array()
	for i in range(1, 16):
		var t := ta + full * float(i) / 16.0
		out.append(c + Vector2(cos(t), sin(t)) * rad)
	return out


## the x and z extents (m) of the points whose height is in [lo, hi]: Vector2(x span, z span)
func _xz_span(pts: PackedVector3Array, lo: float, hi: float) -> Vector2:
	var a := Vector2(INF, INF)
	var b := Vector2(-INF, -INF)
	for v in pts:
		if v.y >= lo and v.y <= hi:
			a = a.min(Vector2(v.x, v.z))
			b = b.max(Vector2(v.x, v.z))
	return b - a


func _front_z(ev) -> float:
	var pv: Array = ev.car_root.get_meta("wheels")
	return (pv[0] as Node3D).position.z
