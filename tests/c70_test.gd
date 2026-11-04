extends SceneTree
## godot --headless --path . -s tests/c70_test.gd   (C70: involute Gear sketch entity + circular / linear pattern fused in ONE boolean; needs the CAD DLL)
## Bars, written and committed BEFORE the first run (mm; volumes m3):
##   1 FLANK   for 5 gears (module 2/30 teeth, 1/64, 2/12 shift +0.4, 3/12 at 25 deg shift 0.3, 1.5/100 at 14.5 deg shift -0.2): every flank vertex of the outline
##             above the fillet lies within 0.005 mm of the involute written here as Cartesian x = rb (cos t + t sin t), y = rb (sin t - t cos t) (mirrored, turned by
##             half-tooth angle + inv(pa)); and the chord MIDPOINTS lie within 0.005 mm of that curve (the sampling keeps the chord close).
##             The tooth thickness on the pitch circle, read off the outline, is module (pi/2 + 2 x tan pa) within 0.005 mm.
##             CONTROL: the same 2/30 outline built at 25 degrees against the 20 degree formula is off by more than 0.005 mm.
##   2 SPEED   the 64-tooth wheel (disc + ONE tooth + circular pattern + join + bore; the CH2 recipe) replays in under 2 s, 3 runs, each run a fresh feature list
##             (the thickness differs: no cache) and each started with the CPU load under 30 percent (polled; a run that cannot get the gate in 150 s is a FAIL).
##             CONTROL: the old one-by-one join (Part.bulk_fuse = false) takes over 2 s on the same wheel, so the bar can fail.
##   3 VOLUME  the pattern result volume equals the one-by-one path within 1e-9 relative on 3 parts: a 30-tooth wheel, a row of 12 overlapping bars (linear),
##             9 bars crossing at the middle (circular, copies overlap each other).  CONTROL: a wheel of 29 teeth differs from the 30 by more than 1e-9.
##   4 GEAR    the Gear tool (Shapes row > Gear): the dialog opens, shows pitch / tip / root diameters; Add gear puts the loop into the sketch as ONE undo step; the
##             loop extrudes to 1 solid whose volume is within 0.2 percent of the polygon area x thickness; an impossible number (6 teeth, 35 degrees, shift 1.5) disables Add gear.
##             Screenshots C:/Temp/claude/c70/*.png at 1280x720, looked at by eye.
##   5 PT_BR   the dialog's strings have non-empty msgstr in the .po (c31 holds the rest).
##   6 WATCHDOG the test quits itself at 600 s
const SHOT := "C:/Temp/claude/c70"
const PO := "res://data/i18n/pt_BR.po"
const PGEAR := preload("res://scripts/build/part_gear.gd")
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
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func begin(pu: PartUI) -> void:
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])


## the involute written independently of part_gear.gd: the left flank point of tooth 0 at radius r
func ref_flank(m_: float, z: int, pa_deg: float, x: float, r: float) -> Vector2:
	var pa := deg_to_rad(pa_deg)
	var rb := m_ * z * 0.5 * cos(pa)
	var t := sqrt(maxf((r / rb) * (r / rb) - 1.0, 0.0))
	var beta := (PI * 0.5 + 2.0 * x * tan(pa)) / z + (tan(pa) - pa)
	return Vector2(rb * (cos(t) + t * sin(t)), -rb * (sin(t) - t * cos(t))).rotated(beta)


## the worst distance (mm) of tooth 0's left flank vertices and chord midpoints from the formula
func flank_err(ol: PackedVector2Array, m_: float, z: int, pa_deg: float, x: float) -> Dictionary:
	var pa := deg_to_rad(pa_deg)
	var rp := m_ * z * 0.5
	var rb := rp * cos(pa)
	var ra := rp + m_ * (1.0 + x)
	var rf := rp - m_ * (1.25 - x)
	var lo := maxf(rb, rf) + 0.6 * m_
	var sel := []
	for p in ol:
		var a := wrapf(p.angle(), -PI, PI)
		if a > 0.0 and a < PI / z and p.length() >= lo and p.length() < ra - 1e-6:
			sel.append(p)
	var worst_v := 0.0
	var worst_m := 0.0
	for i in sel.size():
		worst_v = maxf(worst_v, (sel[i] as Vector2).distance_to(ref_flank(m_, z, pa_deg, x, (sel[i] as Vector2).length())))
		if i > 0:
			var mid: Vector2 = (sel[i] + sel[i - 1]) * 0.5
			var r1: float = (sel[i - 1] as Vector2).length()
			var r2: float = (sel[i] as Vector2).length()
			var best := INF
			for j in 401:
				var q := ref_flank(m_, z, pa_deg, x, lerpf(minf(r1, r2) - 0.01, maxf(r1, r2) + 0.01, j / 400.0))
				best = minf(best, mid.distance_to(q))
			worst_m = maxf(worst_m, best)
	return {"n": sel.size(), "vert": worst_v, "mid": worst_m}


## the tooth thickness (mm) on the pitch circle of tooth 0, read off the outline
func pitch_thickness(ol: PackedVector2Array, rp: float, z: int) -> float:
	var ang := []
	for side in [1.0, -1.0]:
		var found := NAN
		for i in ol.size() - 1:
			var a: Vector2 = ol[i]
			var b: Vector2 = ol[i + 1]
			if absf(wrapf(a.angle(), -PI, PI)) > PI / z or absf(wrapf(b.angle(), -PI, PI)) > PI / z:
				continue
			if signf(a.y) != side and a.y != 0.0:
				continue
			if (a.length() - rp) * (b.length() - rp) <= 0.0 and a.length() != b.length():
				var f := (rp - a.length()) / (b.length() - a.length())
				found = absf(wrapf((a + (b - a) * f).angle(), -PI, PI))
				break
		ang.append(found)
	return (ang[0] + ang[1]) * rp


func cpu_load() -> float:
	var out := []
	OS.execute("powershell", ["-NoProfile", "-Command", "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average"], out)
	return float(String(out[0] if out.size() > 0 else "100").strip_edges())


## waits (polling) until the CPU is under 30 percent; false when it never is within 150 s
func gate() -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150000:
		var c := cpu_load()
		if c < 30.0:
			return true
		await create_timer(3.0).timeout
	return false


func wheel_rec(th: float, z := 64) -> Dictionary:
	var rec := Part.make("w")
	rec["features"] = PGEAR.wheel_feats(1.0, z, 20.0, 0.0, th, 4.0)
	return rec


func bars_rec(kind: String) -> Dictionary:
	var rec := Part.make("b")
	var fs: Array = []
	if kind == "linear":
		PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "rect", "a": [0.0, 0.0], "b": [10.0, 4.0]}]), "extrude", 6.0, "new")
		fs.append({"t": "pattern", "id": "f3", "name": "Pattern1", "body": 0, "kind": "linear", "count": 12, "dir": "x", "mm": 7.0, "op": "join"})
	else:
		PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "rect", "a": [-15.0, -3.0], "b": [15.0, 3.0]}]), "extrude", 6.0, "new")
		fs.append({"t": "pattern", "id": "f3", "name": "Pattern1", "body": 0, "kind": "circular", "count": 9, "axis": "z", "deg": 360.0, "op": "join"})
	rec["features"] = fs
	return rec


func vol(rec: Dictionary) -> float:
	var r: Dictionary = Part.replay(rec)
	return float(r["volume"]) if (r["errors"] as Dictionary).is_empty() else -1.0


func poly_area(ents: Array) -> float:
	var a := 0.0
	for e in ents:
		if String(e["k"]) == "line":
			var p: Array = e["a"]
			var q: Array = e["b"]
			a += float(p[0]) * float(q[1]) - float(q[0]) * float(p[1])
	return absf(a) * 0.5


func math_bars() -> void:
	var sets := [[2.0, 30, 20.0, 0.0], [1.0, 64, 20.0, 0.0], [2.0, 12, 20.0, 0.4], [3.0, 12, 25.0, 0.3], [1.5, 100, 14.5, -0.2]]
	for s in sets:
		var ol := PGEAR.outline(s[0], s[1], s[2], s[3])
		var e := flank_err(ol, s[0], s[1], s[2], s[3])
		ok(ol.size() > 0 and e["n"] >= 4 and e["vert"] <= 0.005 and e["mid"] <= 0.005,
			"1 gear m%s z%d pa%s x%s: %d flank vertices, vertex error %.5f mm, chord midpoint error %.5f mm (bar 0.005)" % [s[0], s[1], s[2], s[3], e["n"], e["vert"], e["mid"]])
		var th := pitch_thickness(ol, s[0] * s[1] * 0.5, s[1])
		var want: float = s[0] * (PI * 0.5 + 2.0 * s[3] * tan(deg_to_rad(s[2])))
		ok(absf(th - want) <= 0.005, "1 pitch thickness m%s z%d: %.4f mm, closed form %.4f" % [s[0], s[1], th, want])
	var bad := flank_err(PGEAR.outline(2.0, 30, 25.0, 0.0), 2.0, 30, 20.0, 0.0)
	ok(bad["vert"] > 0.005, "1 control: a 25 degree gear against the 20 degree formula is off by %.4f mm (> 0.005)" % bad["vert"])


func speed_bars() -> void:
	for run in 3:
		var g: bool = await gate()
		ok(g, "2 run %d: CPU under 30 percent at the start" % run)
		var rec := wheel_rec(5.0 + 0.013 * (run + 1))
		var t := Time.get_ticks_msec()
		var r: Dictionary = Part.replay(rec)
		var dt := (Time.get_ticks_msec() - t) / 1000.0
		ok((r["errors"] as Dictionary).is_empty() and int(r["bodies"]) == 1, "2 run %d: wheel replays, errors %s bodies %d" % [run, r["errors"], int(r["bodies"])])
		ok(dt < 2.0, "2 run %d: 64-tooth wheel replay %.2f s (bar < 2 s)" % [run, dt])
	await gate()
	Part.bulk_fuse = false
	var t2 := Time.get_ticks_msec()
	Part.replay(wheel_rec(5.5))
	var dt2 := (Time.get_ticks_msec() - t2) / 1000.0
	Part.bulk_fuse = true
	ok(dt2 > 2.0, "2 control: the old one-by-one join takes %.2f s (> 2 s, so the bar can fail)" % dt2)


func feats_of(nm: String) -> Array:
	if nm == "wheel30":
		return PGEAR.wheel_feats(2.0, 30, 20.0, 0.0, 5.0, 6.0)
	return bars_rec(nm)["features"]


func volume_bars() -> void:
	for nm in ["wheel30", "linear", "circular"]:
		var rec_a := Part.make(nm)
		var rec_b := Part.make(nm)
		rec_a["features"] = feats_of(nm)
		rec_b["features"] = feats_of(nm)
		Part.bulk_fuse = true
		var va := vol(rec_a)
		Part.bulk_fuse = false
		var vb := vol(rec_b)
		Part.bulk_fuse = true
		ok(va > 0.0 and vb > 0.0 and absf(va - vb) / vb <= 1e-9, "3 %s: one boolean %.9f mm3, one by one %.9f mm3, relative %s (bar 1e-9)" % [nm, va * 1e9, vb * 1e9, str(absf(va - vb) / maxf(vb, 1e-30))])
	var r30 := Part.make("a")
	r30["features"] = PGEAR.wheel_feats(2.0, 30, 20.0, 0.0, 5.0, 6.0)
	var r29 := Part.make("a")
	r29["features"] = PGEAR.wheel_feats(2.0, 29, 20.0, 0.0, 5.0, 6.0)
	var v30 := vol(r30)
	ok(absf(vol(r29) - v30) / v30 > 1e-9, "3 control: 29 teeth differ from 30 by more than 1e-9")


func ps_has(msgid: String) -> bool:
	var f := FileAccess.open(PO, FileAccess.READ)
	var t := f.get_as_text()
	var key := "msgid \"%s\"\r\nmsgstr \"" % msgid
	var i := t.find(key)
	if i < 0:
		return false
	return t.substr(i + key.length(), 1) != "\""


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c70_test"))
	ss.dirs_override = ["user://c70_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on and pu.shp != null and pu.shp.gear_ui != null, "4 Part workspace on, the gear tool built")
	var n0: int = m.undo.size()
	await begin(pu)
	await click_ctl(pu.shp.toggle)
	var gb: Button = pu.shp.gear_ui.btn
	ok(gb.is_visible_in_tree(), "4 the Gear button is in the open Shapes row")
	await click_ctl(gb)
	var card: Control = pu.shp.gear_ui.card
	ok(card.visible, "4 the Gear button opens the dialog")
	pu.shp.gear_ui.spins["z"].value = 24
	pu.shp.gear_ui.spins["m"].value = 2.0
	pu.shp.gear_ui.spins["bore"].value = 10.0
	await idle(3)
	var info: String = pu.shp.gear_ui.info.text
	ok(info.contains("48.00") and info.contains("52.00") and info.contains("43.00"), "4 the dialog says the diameters: %s" % info)
	await shot("gear_dialog")
	await click_ctl(pu.shp.gear_ui.add_btn)
	var ents: Array = pu._sk()["ents"]
	var loop := ents.filter(func(e): return String(e["k"]) == "line")
	ok(loop.size() > 100, "4 Add gear puts a loop of %d line entities into the sketch" % loop.size())
	var area := poly_area(loop) - PI * 25.0
	pu.shp.gear_ui.set_open(false)
	await shot("gear_sketch")
	var ents_copy := ents.duplicate(true)
	await click_ctl(pu.finish_btn)
	ok(m.undo.size() == n0 + 1, "4 ONE undo step for the gear (%d)" % (m.undo.size() - n0))
	pu.shp.gear_ui.spins["z"].value = 6
	pu.shp.gear_ui.spins["pa"].value = 35.0
	pu.shp.gear_ui.spins["x"].value = 1.5
	await idle(2)
	ok(pu.shp.gear_ui.add_btn.disabled, "4 6 teeth, 35 degrees, shift 1.5: Add gear is disabled (%s)" % pu.shp.gear_ui.info.text)
	var ext := Part.make("g")
	var fs: Array = []
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", ents_copy), "extrude", 8.0, "new")
	ext["features"] = fs
	var r: Dictionary = Part.replay(ext)
	var want := area * 8.0 * 1e-9
	ok((r["errors"] as Dictionary).is_empty() and int(r["bodies"]) == 1 and absf(float(r["volume"]) - want) / want < 0.002,
		"4 extruded gear: errors %s, %d body, volume %.3f mm3 vs polygon area x 8 = %.3f" % [r["errors"], int(r["bodies"]), float(r["volume"]) * 1e9, want * 1e9])
	for id in ["Involute gear", "Module (mm)", "Teeth", "Pressure angle", "Profile shift", "Root fillet (mm)", "Centre X (mm)", "Centre Y (mm)", "Bore diameter (mm)", "Add gear", "Close"]:
		ok(ps_has(id), "5 pt_BR has \"%s\"" % id)
	pu.shp.gear_ui.spins["z"].value = 24
	pu.shp.gear_ui.spins["pa"].value = 20.0
	pu.shp.gear_ui.spins["x"].value = 0.0
	pu.shp.gear_ui.set_open(true)
	await shot("gear_final")


func _init() -> void:
	var wd := create_timer(600.0)
	wd.timeout.connect(func():
		print("FAIL watchdog: 600 s")
		quit(2))
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	math_bars()
	await speed_bars()
	volume_bars()
	await ui_bars()
	print("c70: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
