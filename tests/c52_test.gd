extends SceneTree
## godot --path . --position 4000,4000 -s tests/c52_test.gd     (C52: complaints #343 + #336, Gear template: Gear pair / Rack and pinion mode switch)
## Bars (written before any number was read). Geometry is measured from the BUILT mesh (mm), never from the record:
##  1 GOLD     mode 0 (and a record with no mode key) gives the same features as origin for 4 parameter sets (hashes taken on origin f3f4c82a).
##             CONTROL: mode 1 on the same numbers gives a different hash
##  2 PITCH    Rack and pinion at the defaults (15 teeth, module 2, rack 100 mm): the rack's tooth pitch (tip centre to tip centre, from the mesh) equals the
##             pinion's circular pitch pi x module (module from the mesh: pinion hole radius / (0.12 x teeth)) within 0.5 %.  CONTROL: a rack built for module 3
##             fails the same check against a module 2 pinion
##  3 CENTRE   pinion centre to the rack's pitch line (rack tip height - module), from the mesh, equals pitch radius module x teeth / 2 within 0.5 %.
##             CONTROL: a rack 1.5 mm too low fails
##  4 BACKLASH on the pitch line, rack tooth thickness + pinion tooth thickness = pitch - 0.10 x module (the stated backlash), within 0.05 mm, and the gap is >= 0
##  5 ROLL     the pinion rolled over the rack (centre moves s, turns s / pitch radius) at 0.25 mm steps over 2 pitches: the overlap area of the mesh outlines
##             stays <= 0.10 mm2 at every step.  CONTROL: the rack outline grown 1.0 mm all round (first planted at 0.3 mm: the new rack has more room than that, so the control was widened) overlaps by more than 0.10 mm2
##  6 LENGTH   rack length typed 60 / 100 / 200 mm: tooth count = round(len / pitch) (10 / 16 / 32 at module 2, counted from the mesh), the rack is within one pitch
##             of the length typed
##  7 UI       real drags on Mode (0 -> 1): one undo step, two solids; Rack length dragged to 200: one undo step, 10 teeth; Ctrl+Z restores; the hint line
##             carries the gear scope line (what the tool does and does not do), no key names in it; screenshots C:/Temp/claude/c52/*.png
##  8 PT_BR    the .po (CRLF) has the 4 new msgids with non-empty msgstr
const SHOT := "C:/Temp/claude/c52"
const DIRT := "user://c52_test"
const PO := "res://data/i18n/pt_BR.po"
const GOLD := {"15,2,2,10": 2600603666, "8,1,1,3": 3960462769, "30,3,3,30": 3667595278, "12,2,3,7": 2760531673}
const GEARDRIVE := preload("res://scripts/gear_drive.gd")
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
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a slider knob position (screen px) for a value: the track runs between the centres of the two end grabbers
func knob_x(s: HSlider, v: float) -> Vector2:
	var r := s.get_global_rect()
	var t := (v - s.min_value) / maxf(s.max_value - s.min_value, 1e-6)
	return Vector2(r.position.x + 12.0 + t * (r.size.x - 24.0), r.get_center().y)


## a real drag of a template slider from its knob to value v
func slide_to(s: HSlider, v: float) -> void:
	var a := knob_x(s, s.value)
	await drag_screen(a, knob_x(s, v))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func row_of(ep, key: String) -> Dictionary:
	for r in ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	root.push_input(e, true)
	await idle(3)


## the built part in mm, from the mesh faces: x across, y up, z through the thickness; bodies = the solids the build made
func built() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			lo = lo.min(p)
			hi = hi.max(p)
	if faces.is_empty():
		return {"w": 0.0, "h": 0.0, "t": 0.0, "x0": 0.0, "bodies": 0}
	return {"w": hi.x - lo.x, "h": hi.y - lo.y, "t": hi.z - lo.z, "x0": lo.x, "bodies": int(pu().res.get("bodies", 0))}


func mesh_segs() -> Array:
	var all := PackedVector3Array()
	for f in Part.body_faces(m.S.part):
		all.append_array(f)
	return GEARDRIVE.outline_of(all)


## closed loops (PackedVector2Array, mm) from the unordered segments
func loops_of(segs: Array) -> Array:
	var nxt := {}
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ka := Vector2i(roundi(a.x * 100.0), roundi(a.y * 100.0))
		var kb := Vector2i(roundi(b.x * 100.0), roundi(b.y * 100.0))
		if not nxt.has(ka):
			nxt[ka] = []
		if not nxt.has(kb):
			nxt[kb] = []
		nxt[ka].append([kb, b])
		nxt[kb].append([ka, a])
	var used := {}
	var out := []
	for k0 in nxt:
		if used.has(k0):
			continue
		var loop := PackedVector2Array()
		var k: Vector2i = k0
		var prev := Vector2i(1 << 30, 1 << 30)
		var guard := 0
		while not used.has(k) and guard < 100000:
			guard += 1
			used[k] = true
			loop.append(Vector2(k.x, k.y) * 0.01)
			var step = null
			for e in nxt[k]:
				if e[0] != prev and not used.has(e[0]):
					step = e
					break
			if step == null:
				break
			prev = k
			k = step[0]
		if loop.size() >= 3:
			out.append(loop)
	return out


func area_of(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return absf(a) * 0.5


func bbox_of(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


## {"rack", "pinion", "hole"} loops of the built Rack and pinion
func parts_of() -> Dictionary:
	var ls := loops_of(mesh_segs())
	ls.sort_custom(func(a, b): return area_of(a) > area_of(b))
	var d := {}
	for l in ls:
		var bb := bbox_of(l)
		if not d.has("rack") and bb.size.x > 40.0:
			d["rack"] = l
		elif not d.has("pinion") and bb.size.x > 10.0 and absf(bb.get_center().x) < 2.0:
			d["pinion"] = l
		elif not d.has("hole") and bb.size.x <= 10.0 and bb.has_point(Vector2.ZERO):
			d["hole"] = l
	return d


func inside(p: PackedVector2Array, pt: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(pt, p)


## the rack's tooth centres (x) read off the tips (the loop's highest y), and that y
func rack_tips(rack: PackedVector2Array) -> Dictionary:
	var ymax := -1e9
	for v in rack:
		ymax = maxf(ymax, v.y)
	var xs := []
	for v in rack:
		if absf(v.y - ymax) < 0.01:
			xs.append(v.x)
	xs.sort()
	var cs := []
	for i in range(0, xs.size() - 1, 2):
		cs.append(0.5 * (xs[i] + xs[i + 1]))
	return {"y": ymax, "centres": cs}


func mean_pitch(cs: Array) -> float:
	if cs.size() < 2:
		return 0.0
	return (float(cs[cs.size() - 1]) - float(cs[0])) / float(cs.size() - 1)


## thickness (mm) of the rack tooth nearest x = 0 on the horizontal line y
func rack_tooth_at(rack: PackedVector2Array, y: float) -> float:
	var xs := []
	for i in rack.size():
		var a := rack[i]
		var b := rack[(i + 1) % rack.size()]
		if (a.y - y) * (b.y - y) < 0.0:
			xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
	xs.sort()
	var best := 1e9
	var w := 0.0
	for i in xs.size() - 1:
		var mid := 0.5 * (float(xs[i]) + float(xs[i + 1]))
		if inside(rack, Vector2(mid, y)) and absf(mid) < best:
			best = absf(mid)
			w = float(xs[i + 1]) - float(xs[i])
	return w


## the pinion tooth's arc thickness (mm) on the circle of radius r: the tooth nearest the bottom (the mesh point)
func pinion_tooth_on(pin: PackedVector2Array, r: float) -> float:
	var cr := []
	for i in pin.size():
		var a := pin[i]
		var b := pin[(i + 1) % pin.size()]
		var ra := a.length() - r
		var rb := b.length() - r
		if ra * rb < 0.0:
			var t := ra / (ra - rb)
			cr.append((a + (b - a) * t).angle())
	cr.sort()
	var best := 1e9
	var w := 0.0
	for i in cr.size():
		var a0: float = cr[i]
		var a1: float = cr[(i + 1) % cr.size()] + (TAU if i == cr.size() - 1 else 0.0)
		var mid := 0.5 * (a0 + a1)
		if inside(pin, Vector2.from_angle(mid) * r):
			var d := absf(wrapf(mid + PI * 0.5, -PI, PI))
			if d < best:
				best = d
				w = (a1 - a0) * r
	return w


func overlap_max(pin: PackedVector2Array, rack_loop: PackedVector2Array, rp: float, pitch: float) -> float:
	var worst := 0.0
	var s := 0.0
	while s <= 2.0 * pitch + 1e-6:
		var q := PackedVector2Array()
		for v in pin:
			q.append(v.rotated(-s / rp) + Vector2(s, 0.0))
		var tot := 0.0
		for poly in Geometry2D.intersect_polygons(q, rack_loop):
			tot += area_of(poly)
		worst = maxf(worst, tot)
		s += 0.25
	return worst


func measure_all(ep) -> Dictionary:
	var d := parts_of()
	if not (d.has("rack") and d.has("pinion") and d.has("hole")):
		print("loops missing: ", d.keys())
		return {}
	var hole_r := 0.0
	for v in d["hole"]:
		hole_r += v.length()
	hole_r /= float(d["hole"].size())
	var n := int(roundf(float(ep._rec()["easy"]["p"]["teeth"])))   # the tooth count typed (a count, not a size)
	var mod := hole_r / (0.12 * n)
	var rt := rack_tips(d["rack"])
	var pitch := mean_pitch(rt["centres"])
	var rp := mod * n * 0.5
	return {"mod": mod, "n": n, "pitch": pitch, "teeth": rt["centres"].size(), "ytip": rt["y"], "rp": rp, "rack": d["rack"], "pin": d["pinion"],
		"rack_w": bbox_of(d["rack"]).size.x}


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
	var wd := Timer.new()   # watchdog: 12 minutes
	wd.wait_time = 720.0
	wd.one_shot = true
	wd.timeout.connect(func():
		print("FAIL watchdog")
		quit(2))
	root.add_child(wd)
	wd.start()
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 1 GOLD
	var gold_ok := true
	for k in GOLD:
		var c: PackedStringArray = String(k).split(",")
		var p := {"teeth": float(c[0]), "ratio": float(c[1]), "module": float(c[2]), "thickness": float(c[3])}
		var h0 := str(PartTemplates.features_of("gearpair", p)).hash()
		var p0 := p.duplicate()
		p0["mode"] = 0.0
		p0["rack_len"] = 100.0
		var h1 := str(PartTemplates.features_of("gearpair", p0)).hash()
		var p1 := p0.duplicate()
		p1["mode"] = 1.0
		var h2 := str(PartTemplates.features_of("gearpair", p1)).hash()
		var good: bool = h0 == GOLD[k] and h1 == GOLD[k] and h2 != GOLD[k]
		gold_ok = gold_ok and good
		print("     gold ", k, " old-record ", h0, " mode0 ", h1, " mode1 ", h2, " want ", GOLD[k])
	ok(gold_ok, "1 GOLD: Gear pair output equals origin's for 4 parameter sets (mode 0 and no-mode record); mode 1 differs (control)")

	# BUILDING card -> Parts > Gears -> Gear pair
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
	var ep = pu().ep
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_libgroup_Moving parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_lib_Gears", true, false) as Control)
	await click_ctl(root.find_child("easypart_gearpair_pick", true, false) as Button)
	await idle(10)
	var b0 := built()
	ok(int(b0["bodies"]) == 2 and absf(float(b0["w"]) - 93.7) <= 0.5, "0 Gear pair still builds the p065 pair: %d solids, %.2f mm wide (want 93.7)" % [int(b0["bodies"]), float(b0["w"])])

	# 7 UI part 1: Mode dragged 0 -> 1
	var rm := row_of(ep, "mode")
	var sm: HSlider = rm.get("slider")
	var ub: int = m.undo.size()
	if sm != null:
		await slide_to(sm, 1.0)
	await idle(12)
	await shot("00_rack_pinion")
	var b1 := built()
	var mode_val := float(ep._rec()["easy"]["p"].get("mode", -1.0))
	ok(sm != null and mode_val == 1.0 and m.undo.size() == ub + 1 and int(b1["bodies"]) == 2,
		"7a Mode dragged to Rack and pinion: mode %s, one undo step (%d -> %d), %d solids" % [str(mode_val), ub, m.undo.size(), int(b1["bodies"])])
	ok(String(ep.hint_l.text).contains("straight spur teeth") and not String(ep.hint_l.text).to_lower().contains("ctrl"),
		"7b the hint line carries the gear scope line: [%s]" % ep.hint_l.text)

	# 2-5 geometry from the mesh at the defaults
	var g := measure_all(ep)
	var pit_pin := PI * float(g.get("mod", 0.0))
	var pit_err := absf(float(g.get("pitch", 0.0)) - pit_pin) / maxf(pit_pin, 1e-6)
	var ctl_pitch := absf(PI * 3.0 - PI * 2.0) / (PI * 2.0)
	ok(not g.is_empty() and pit_err <= 0.005 and ctl_pitch > 0.005,
		"2 PITCH: rack tooth pitch %.4f mm vs pinion circular pitch pi x %.4f = %.4f mm: error %.3f %% (bar 0.5 %%); control (module 3 rack) error %.1f %% is flagged" % [float(g.get("pitch", 0)), float(g.get("mod", 0)), pit_pin, pit_err * 100.0, ctl_pitch * 100.0])
	if g.is_empty():
		print("c52: geometry not measurable, stopping")
		quit(1)
		return
	var cd: float = float(g["ytip"]) - float(g["mod"])   # pitch line y of the rack (tip - addendum), pinion centre at 0
	var cd_err := absf(absf(cd) - float(g["rp"])) / float(g["rp"])
	var cd_ctl := absf(absf(cd - 1.5) - float(g["rp"])) / float(g["rp"])
	ok(cd_err <= 0.005 and cd_ctl > 0.005,
		"3 CENTRE: pinion centre to rack pitch line %.4f mm vs pitch radius %.4f mm: error %.3f %% (bar 0.5 %%); control (1.5 mm low) %.2f %% is flagged" % [absf(cd), float(g["rp"]), cd_err * 100.0, cd_ctl * 100.0])
	var s_r := rack_tooth_at(g["rack"], cd)
	var s_p := pinion_tooth_on(g["pin"], float(g["rp"]))
	var gap := pit_pin - s_r - s_p
	var want_gap := 0.10 * float(g["mod"])
	ok(gap >= 0.0 and absf(gap - want_gap) <= 0.05,
		"4 BACKLASH: pitch line: rack tooth %.3f + pinion tooth %.3f -> gap %.3f mm (stated 0.10 x module = %.3f, tol 0.05, gap >= 0)" % [s_r, s_p, gap, want_gap])
	var ov := overlap_max(g["pin"], g["rack"], float(g["rp"]), pit_pin)
	var fat: PackedVector2Array = Geometry2D.offset_polygon(g["rack"], 1.0)[0]
	var ov_ctl := overlap_max(g["pin"], fat, float(g["rp"]), pit_pin)
	ok(ov <= 0.10 and ov_ctl > 0.10,
		"5 ROLL: worst overlap over 2 pitches %.4f mm2 (bar 0.10); control (rack grown 1.0 mm) %.3f mm2 is flagged" % [ov, ov_ctl])

	# 6 LENGTH, by real drags of the rack length slider (also the UI part 2)
	var rl := row_of(ep, "rack_len")
	var sl: HSlider = rl.get("slider")
	var len_ok := sl != null
	var detail := ""
	for L in [60.0, 200.0, 100.0]:
		if sl != null:
			var ub2: int = m.undo.size()
			var par: Node = sl.get_parent()
			while par != null and not (par is ScrollContainer):
				par = par.get_parent()
			if par != null:
				(par as ScrollContainer).ensure_control_visible(sl)
				await idle(3)
			await slide_to(sl, L)
			await idle(12)
			var gg := measure_all(ep)
			var want_n := roundi(L / (PI * float(gg.get("mod", 2.0))))
			var good: bool = not gg.is_empty() and int(gg["teeth"]) == want_n and absf(float(gg["rack_w"]) - L) <= float(gg["pitch"]) * 0.5 + 0.05 and m.undo.size() == ub2 + 1 and int(built()["bodies"]) == 2
			len_ok = len_ok and good
			detail += " [%d mm: %d teeth (want %d), rack %.1f mm wide, undo +%d]" % [int(L), int(gg.get("teeth", -1)), want_n, float(gg.get("rack_w", 0)), m.undo.size() - ub2]
			if L == 200.0:
				await shot("01_rack_200")
	ok(len_ok, "6 LENGTH: typed 60 / 200 / 100 mm by real drags:" + detail)

	# 7 UI part 2: Ctrl+Z undoes the last length drag (100 -> 200); Mode back to Gear pair restores the pair
	var ub3: int = m.undo.size()
	await ctrl_z()
	var rl_after := float(ep._rec()["easy"]["p"]["rack_len"])
	ok(m.undo.size() == ub3 - 1 and rl_after == 200.0, "7c Ctrl+Z after the last length drag: rack_len %s (want 200), undo %d -> %d" % [str(rl_after), ub3, m.undo.size()])
	await slide_to(sm, 0.0)
	await idle(12)
	await shot("02_back_to_pair")
	var b4 := built()
	ok(int(b4["bodies"]) == 2 and absf(float(b4["w"]) - 93.7) <= 0.5, "7d Mode dragged back to Gear pair: %.2f mm wide (want 93.7), %d solids" % [float(b4["w"]), int(b4["bodies"])])

	# 8 PT_BR
	var po := FileAccess.get_file_as_string(PO)
	var need := ["Mode", "Rack length", "Rack and pinion", "Gears here: straight spur teeth"]
	var po_ok := po.contains("\r\n")
	for k in need:
		var i := po.find("msgid \"" + k)
		var j := po.find("msgstr \"", i)
		var e := po.find("\r\n", j)
		po_ok = po_ok and i >= 0 and j > i and e - j > 10
	ok(po_ok, "8 PT_BR: the 4 new msgids have a msgstr in the CRLF .po")

	print("c52: %d fail" % fails)
	quit(1 if fails > 0 else 0)
