extends SceneTree
## godot --path . --position 4000,4000 -s tests/nnutwasher_test.gd     (EASY PART: a screw on the floor offers its nut and washer in one click; scripts/easy_part.gd + scripts/build/part_templates.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card: a blank part on Part, Easy; no keyboard). Measured from the BUILT result (mesh vertices in mm,
## one body per solid, the kernel volume), never from the code's own variables. The ISO tables below are the only expected values.
##   0 NEED      with no screw on the floor, the nut button says what to do first (a screw, then its nut) and adds nothing (no undo step)
##   1 OFFER     M4 x 16 dropped, then ONE click on "Add its nut and washer": ONE undo step, three solids; the screw is ISO M4 x 16, the nut ISO 4032
##               M4 (7.0 mm across flats, 3.2 mm thick, 4.0 mm bore, standing on the floor at X 40 mm), the washer ISO 7089 M4 (4.3 mm inside,
##               9.0 mm outside, 0.8 mm thick, on the floor at X 18 mm)
##   2 AGAIN     the nut button again: no undo step, says they are on the floor already
##   3 RESIZE    M6 x 30 picked after the nut: ONE undo step, still three solids, all three ISO M6 (nut 10.0 across flats, 5.2 thick, 6.0 bore;
##               washer 6.4 inside, 12.0 outside, 1.6 thick; screw 6.0 x 30.0 under a 10.0 x 6.0 head)
##   4 UNDO      one Undo brings back M4 x 16 with its nut and washer (measured again)
##   5 ALL 4     M3, M4, M5, M6 picked in turn at 16 mm: each ONE undo step, all three solids ISO to the size
##   6 WORDS     no key name in the nut button, its tooltip, the hint or the status line
## Shots: C:/Temp/claude/nnutwasher/nut.png (the nut and washer on the floor), m6.png (M6 x 30 with M6 nut and washer)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/nnutwasher"
const DIRT := "user://nnutwasher_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO 4762 socket head: [head diameter, head height] (mm) by the nominal size (the screw's shank is the nominal size)
const SCREW := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
## ISO 4032 nut: [across flats, thickness] (mm)
const NUT := {3: [5.5, 2.4], 4: [7.0, 3.2], 5: [8.0, 4.7], 6: [10.0, 5.2]}
## ISO 7089 washer: [inside diameter, outside diameter, thickness] (mm)
const WASH := {3: [3.2, 7.0, 0.5], 4: [4.3, 9.0, 0.8], 5: [5.3, 10.0, 1.0], 6: [6.4, 12.0, 1.6]}
const WASHER_X := 18.0   # mm: where the washer stands on the floor (its centre, X)
const NUT_X := 40.0      # mm: where the nut stands on the floor (its centre, X)
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


## a real click on a visible control; false (and nothing clicked) when the control is missing or hidden
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func chip(d: int, L: int) -> Button:
	return root.find_child("easypart_screw_M%d_%d" % [d, L], true, false) as Button


func nut_btn() -> Button:
	return root.find_child("easypart_nw_add", true, false) as Button


## the built solids, one per body (mm), sorted by centre X: the centre, the widths, the Y range, the radial range about its own axis
func bodies() -> Array:
	var out := []
	for f in Part.body_faces(m.S.part):
		var arr: PackedVector3Array = f
		if arr.is_empty():
			continue
		var xmin := 1e9
		var xmax := -1e9
		var zmin := 1e9
		var zmax := -1e9
		var ymin := 1e9
		var ymax := -1e9
		for v in arr:
			var p := v * 1000.0
			xmin = minf(xmin, p.x)
			xmax = maxf(xmax, p.x)
			zmin = minf(zmin, p.z)
			zmax = maxf(zmax, p.z)
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
		var cx := (xmin + xmax) * 0.5
		var cz := (zmin + zmax) * 0.5
		var rmin := 1e9
		var rmax := 0.0
		for v in arr:
			var p := v * 1000.0
			var r := Vector2(p.x - cx, p.z - cz).length()
			if r > 0.01:
				rmin = minf(rmin, r)
			rmax = maxf(rmax, r)
		out.append({"cx": cx, "cz": cz, "xw": xmax - xmin, "zw": zmax - zmin, "ymin": ymin, "ymax": ymax, "rmin": rmin, "rmax": rmax, "arr": arr})
	out.sort_custom(func(a, b): return float(a["cx"]) < float(b["cx"]))
	return out


## the solid whose centre X is x (mm), or {} when there is none
func solid_at(bs: Array, x: float) -> Dictionary:
	for b in bs:
		if absf(float(b["cx"]) - x) <= 0.5:
			return b
	return {}


func near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.05


## "" when the screw standing at the origin is ISO M<d> x <L>; else what was measured
func screw_err(bs: Array, d: int, L: int) -> String:
	var s := {}
	for b in bs:
		if float(b["cx"]) < 8.0:
			s = b
	if s.is_empty():
		return "no screw solid"
	var shank_top := -1e9
	for v in (s["arr"] as PackedVector3Array):
		var p := v * 1000.0
		var r := Vector2(p.x, p.z).length()
		if r > 0.01 and r <= float(s["rmin"]) + 0.05:
			shank_top = maxf(shank_top, p.y)
	var D: float = SCREW[d][0]
	var k: float = SCREW[d][1]
	var good := near(float(s["rmin"]) * 2.0, d) and near(float(s["rmax"]) * 2.0, D) and near(shank_top, L) and near(float(s["ymax"]) - shank_top, k) and near(float(s["ymin"]), 0.0)
	if good:
		return ""
	return "screw d %.2f head %.2f shank top %.2f head %.2f lowest %.2f" % [float(s["rmin"]) * 2.0, float(s["rmax"]) * 2.0, shank_top, float(s["ymax"]) - shank_top, float(s["ymin"])]


## "" when the solid at the nut's place is ISO 4032 M<d> (across flats, thickness, bore, on the floor, centred at NUT_X)
func nut_err(bs: Array, d: int) -> String:
	var n := solid_at(bs, NUT_X)
	if n.is_empty():
		return "no nut solid at X %.0f" % NUT_X
	var s: float = NUT[d][0]
	var t: float = NUT[d][1]
	var good := near(float(n["zw"]), s) and near(float(n["ymax"]) - float(n["ymin"]), t) and near(float(n["rmin"]) * 2.0, d) and near(float(n["ymin"]), 0.0)
	good = good and near(float(n["cx"]), NUT_X) and near(float(n["xw"]), 2.0 * s / sqrt(3.0))
	if good:
		return ""
	return "nut across flats %.2f thick %.2f bore %.2f lowest %.2f centre %.2f" % [float(n["zw"]), float(n["ymax"]) - float(n["ymin"]), float(n["rmin"]) * 2.0, float(n["ymin"]), float(n["cx"])]


## "" when the solid at the washer's place is ISO 7089 M<d> (inside, outside, thickness, on the floor, centred at WASHER_X)
func washer_err(bs: Array, d: int) -> String:
	var w := solid_at(bs, WASHER_X)
	if w.is_empty():
		return "no washer solid at X %.0f" % WASHER_X
	var di: float = WASH[d][0]
	var dout: float = WASH[d][1]
	var t: float = WASH[d][2]
	var good := near(float(w["rmin"]) * 2.0, di) and near(float(w["rmax"]) * 2.0, dout) and near(float(w["ymax"]) - float(w["ymin"]), t)
	good = good and near(float(w["ymin"]), 0.0) and near(float(w["cx"]), WASHER_X)
	if good:
		return ""
	return "washer inside %.2f outside %.2f thick %.2f lowest %.2f centre %.2f" % [float(w["rmin"]) * 2.0, float(w["rmax"]) * 2.0, float(w["ymax"]) - float(w["ymin"]), float(w["ymin"]), float(w["cx"])]


## the whole set for size d, L: "" when the screw, nut and washer are all ISO and there are three solids
func set_err(d: int, L: int) -> String:
	var bs := bodies()
	if bs.size() != 3:
		return "%d solids, want 3" % bs.size()
	var out := ""
	for x in [screw_err(bs, d, L), nut_err(bs, d), washer_err(bs, d)]:
		out += ("" if x == "" else x + "; ")
	return out


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
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the nut and washer cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	# 0 NEED: no screw on the floor: the nut button names the next step and adds nothing
	var ub0: int = m.undo.size()
	var nb := nut_btn()
	var pressed := await click_ctl(nb)
	var st0: String = String(ep.hint_l.text).to_lower()   # the words of the last press show on the hint line (the status line counts solids)
	ok(nb != null and pressed and m.undo.size() == ub0 and st0.contains("screw") and st0.contains("first"), "0 no screw yet: the nut button is there and says to put a screw on the floor first, no undo step (%d -> %d, status \"%s\")" % [ub0, m.undo.size(), st0])
	# 1 OFFER: M4 x 16 dropped, then ONE click for its nut and washer
	await click_ctl(chip(4, 16))
	var bs1 := bodies()
	ok(bs1.size() == 1 and screw_err(bs1, 4, 16) == "", "1a the screw drops: one solid, ISO M4 x 16 [%s]" % screw_err(bs1, 4, 16))
	var nb1 := nut_btn()
	ok(nb1 != null and nb1.is_visible_in_tree() and nb1.text.to_lower().contains("nut") and nb1.text.to_lower().contains("washer"), "1b a button 'Add its nut and washer' shows once a screw is on the floor (text \"%s\")" % (nb1.text if nb1 != null else "missing"))
	var ub1: int = m.undo.size()
	await click_ctl(nb1)
	var e1 := set_err(4, 16)
	ok(e1 == "" and m.undo.size() == ub1 + 1, "1c one click: ONE undo step (%d -> %d), three solids, ISO M4 [%s]" % [ub1, m.undo.size(), e1])
	await shot("nut")
	# 2 AGAIN: a second click does nothing
	var ub2: int = m.undo.size()
	await click_ctl(nut_btn())
	ok(m.undo.size() == ub2 and String(ep.hint_l.text).to_lower().contains("already"), "2 nut and washer already on the floor: no undo step (%d -> %d), status \"%s\"" % [ub2, m.undo.size(), ep.hint_l.text])
	# 3 RESIZE: M6 x 30 after the nut: one undo step, all three follow
	var ub3: int = m.undo.size()
	await click_ctl(chip(6, 30))
	var e3 := set_err(6, 30)
	ok(e3 == "" and m.undo.size() == ub3 + 1, "3 M6 x 30 picked after placing: ONE undo step (%d -> %d), ISO M6 nut and washer too [%s]" % [ub3, m.undo.size(), e3])
	await shot("m6")
	# 4 UNDO: one undo brings back M4 x 16 with its nut and washer
	m._undo()
	await idle(4)
	var e4 := set_err(4, 16)
	ok(e4 == "", "4 one Undo brings M4 x 16 back with its nut and washer [%s]" % e4)
	# 5 ALL 4: each size in turn at 16 mm, one undo step each, all three ISO
	var bad := []
	var steps_ok := true
	for d in [3, 4, 5, 6]:
		var u: int = m.undo.size()
		await click_ctl(chip(d, 16))
		var e := set_err(d, 16)
		if e != "":
			bad.append("M%d [%s]" % [d, e])
		if m.undo.size() != u + 1:
			steps_ok = false
	ok(bad.is_empty() and steps_ok, "5 M3..M6 at 16 mm: the screw, nut and washer all ISO, one undo step each %s" % str(bad))
	# 6 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	var nb6 := nut_btn()
	if nb6 != null:
		texts.append(nb6.text)
		texts.append(nb6.tooltip_text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(nb6 != null and hit.is_empty(), "6 no key name in the nut button, its tooltip, the hint or the status %s" % str(hit))
	print("nnutwasher: %d fail" % fails)
	quit(1 if fails > 0 else 0)
