extends SceneTree
## godot --path . --position 4000,4000 -s tests/p037bosschip_test.gd     (FRIDAY 37 BOSS CHIP: a screw on the floor takes a round post beside it, sized by the screw; scripts/easy_part.gd + scripts/build/part_templates.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card: a blank part on Part, Easy; no keyboard). Measured from the BUILT result (mesh vertices in mm,
## one body per solid), never from the code's own variables. The ISO head table below is the only expected value; the post is sized from it: outside = head + 4 mm,
## hole = the screw's size + 0.5 mm (the screw goes in), height = the screw's length. The post stands at X -18 mm (the nut is at +40, the washer at +18).
##   0 NEED      with no screw on the floor, the boss button says what to do first (a screw) and adds nothing (no undo step)
##   1 OFFER     M4 x 16 dropped, then ONE click on "Add its boss": ONE undo step, two solids; the screw is ISO M4 x 16; the post at X -18 mm is
##               11.0 mm outside, 4.5 mm hole, 16.0 mm high, on the floor
##   2 AGAIN     the boss button again: no undo step, says the boss is on the floor already
##   3 RESIZE    M6 x 30 picked after the boss: ONE undo step, the post follows: 14.0 outside, 6.5 hole, 30.0 high
##   4 UNDO      one Undo brings back the M4 x 16 post (measured again)
##   5 ALL 4     M3, M4, M5, M6 picked in turn at 16 mm: each ONE undo step, post sized to each screw
##   6 TOGETHER  the boss, then Add its nut and washer, then M5 x 20: four solids, the post still sized to M5 (12.5 outside, 5.5 hole, 20.0 high)
##   7 WORDS     no key name in the boss button, its tooltip, the hint or the status line
## Shots: C:/Temp/claude/p037bosschip/boss.png (the post on the floor), m6.png (M6 x 30 with its post)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p037bosschip"
const DIRT := "user://p037bosschip_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO 4762 socket head: [head diameter, head height] (mm) by the nominal size (the screw's shank is the nominal size)
const SCREW := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
## ISO 4032 nut: [across flats, thickness] (mm)
const NUT := {3: [5.5, 2.4], 4: [7.0, 3.2], 5: [8.0, 4.7], 6: [10.0, 5.2]}
const POST_X := -18.0   # mm: where the post stands on the floor (its centre, X)
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


func boss_btn() -> Button:
	return root.find_child("easypart_boss_add", true, false) as Button


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
		if float(b["cx"]) < 8.0 and absf(float(b["cx"])) < 8.0:
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


## "" when the solid at the post's place is a round post sized to the screw: outside head + 4, hole d + 0.5, height L, on the floor
func post_err(bs: Array, d: int, L: int) -> String:
	var p := solid_at(bs, POST_X)
	if p.is_empty():
		return "no post solid at X %.0f" % POST_X
	var out_d: float = float(SCREW[d][0]) + 4.0
	var hole: float = float(d) + 0.5
	var good := near(float(p["xw"]), out_d) and near(float(p["zw"]), out_d) and near(float(p["rmax"]) * 2.0, out_d)
	good = good and near(float(p["rmin"]) * 2.0, hole) and near(float(p["ymax"]) - float(p["ymin"]), float(L)) and near(float(p["ymin"]), 0.0)
	if good:
		return ""
	return "post outside %.2f hole %.2f high %.2f lowest %.2f centre %.2f" % [float(p["rmax"]) * 2.0, float(p["rmin"]) * 2.0, float(p["ymax"]) - float(p["ymin"]), float(p["ymin"]), float(p["cx"])]


## the screw and its post for size d, L: "" when there are two solids and both are right
func set_err(d: int, L: int) -> String:
	var bs := bodies()
	if bs.size() != 2:
		return "%d solids, want 2" % bs.size()
	var out := ""
	for x in [screw_err(bs, d, L), post_err(bs, d, L)]:
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
		print("FAIL: no KineCAD DLL, the boss cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	# 0 NEED: no screw on the floor: the boss button names the next step and adds nothing
	var ub0: int = m.undo.size()
	var bb := boss_btn()
	var pressed := await click_ctl(bb)
	var st0: String = String(ep.hint_l.text).to_lower()
	ok(bb != null and pressed and m.undo.size() == ub0 and st0.contains("screw") and st0.contains("first"), "0 no screw yet: the boss button is there and says to put a screw on the floor first, no undo step (%d -> %d, status \"%s\")" % [ub0, m.undo.size(), st0])
	# 1 OFFER: M4 x 16 dropped, then ONE click for its post
	await click_ctl(chip(4, 16))
	var bs1 := bodies()
	ok(bs1.size() == 1 and screw_err(bs1, 4, 16) == "", "1a the screw drops: one solid, ISO M4 x 16 [%s]" % screw_err(bs1, 4, 16))
	var bb1 := boss_btn()
	ok(bb1 != null and bb1.is_visible_in_tree() and bb1.text.to_lower().contains("boss"), "1b a button 'Add its boss' shows once a screw is on the floor (text \"%s\")" % (bb1.text if bb1 != null else "missing"))
	var ub1: int = m.undo.size()
	await click_ctl(bb1)
	var e1 := set_err(4, 16)
	ok(e1 == "" and m.undo.size() == ub1 + 1, "1c one click: ONE undo step (%d -> %d), two solids, post sized to M4 [%s]" % [ub1, m.undo.size(), e1])
	await shot("boss")
	# 2 AGAIN: a second click does nothing
	var ub2: int = m.undo.size()
	await click_ctl(boss_btn())
	ok(m.undo.size() == ub2 and String(ep.hint_l.text).to_lower().contains("already"), "2 boss already on the floor: no undo step (%d -> %d), status \"%s\"" % [ub2, m.undo.size(), ep.hint_l.text])
	# 3 RESIZE: M6 x 30 after the post: one undo step, the post follows
	var ub3: int = m.undo.size()
	await click_ctl(chip(6, 30))
	var e3 := set_err(6, 30)
	ok(e3 == "" and m.undo.size() == ub3 + 1, "3 M6 x 30 picked after placing: ONE undo step (%d -> %d), post follows [%s]" % [ub3, m.undo.size(), e3])
	await shot("m6")
	# 4 UNDO: one undo brings back M4 x 16 with its post
	m._undo()
	await idle(4)
	var e4 := set_err(4, 16)
	ok(e4 == "", "4 one Undo brings M4 x 16 back with its post [%s]" % e4)
	# 5 ALL 4: each size in turn at 16 mm, one undo step each, post sized to each
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
	ok(bad.is_empty() and steps_ok, "5 M3..M6 at 16 mm: the screw and its post sized to each, one undo step each %s" % str(bad))
	# 6 TOGETHER: the post, then the nut and washer, then M5 x 20: four solids, the post still follows
	await click_ctl(chip(4, 16))
	await click_ctl(boss_btn())
	await click_ctl(nut_btn())
	await click_ctl(chip(5, 20))
	var bs6 := bodies()
	var e6 := post_err(bs6, 5, 20)
	ok(bs6.size() == 4 and e6 == "" and screw_err(bs6, 5, 20) == "", "6 post, nut and washer, then M5 x 20: four solids, post still sized to M5 [%d solids; %s %s]" % [bs6.size(), e6, screw_err(bs6, 5, 20)])
	# 7 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	var bb7 := boss_btn()
	if bb7 != null:
		texts.append(bb7.text)
		texts.append(bb7.tooltip_text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(bb7 != null and hit.is_empty(), "7 no key name in the boss button, its tooltip, the hint or the status %s" % str(hit))
	print("p037bosschip: %d fail" % fails)
	quit(1 if fails > 0 else 0)
