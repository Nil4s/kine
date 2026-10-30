extends SceneTree
## godot --path . --position 4000,4000 -s tests/nscrew2_test.gd     (EASY PART: a Parts category of ISO 4762 socket head screws; scripts/easy_part.gd + scripts/build/part_templates.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card: a blank part on Part, Easy; no keyboard). Measured from the BUILT result (mesh vertices in mm,
## the kernel volume), never from the code own variables. The ISO table below is the only expected value (the standard head size and height).
##   1 PARTS      a Parts chip opens sixteen screw chips (M3 M4 M5 M6 x 10 16 20 30 mm), each with an icon, all on screen at 1280 x 720
##   2 DROP       M4 x 16: ONE undo step, one solid, on the floor (lowest point at 0 mm), head 7.0 mm across x 4.0 mm high, shank 4.0 mm across,
##                shank 16.0 mm long, volume within 1 pct of the kernel volume of the same shapes
##   3 RESIZE     M5 x 30 picked after placing: ONE undo step, still one solid, still the same steps in the record, head 8.5 x 5.0, shank 5.0 x 30.0
##   4 UNDO       one Undo brings back M4 x 16 (measured again)
##   5 SAME       picking the size already on the floor does nothing (no undo step)
##   6 ALL 16     every size, picked in turn: each ONE undo step and each measured to the ISO size
##   7 WORDS      no key name in the Parts chips, the hint or the status line
## Shots: C:/Temp/claude/nscrew2/parts.png (the Parts chips open), m5.png (M5 x 30 on the floor)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/nscrew2"
const DIRT := "user://nscrew2_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO 4762 socket head: [head diameter, head height] in mm, by the nominal size (the shank is the nominal size, plain)
const ISO := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
const LENS := [10, 16, 20, 30]
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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func chip(d: int, L: int) -> Button:
	return root.find_child("easypart_screw_M%d_%d" % [d, L], true, false) as Button


## the built result, read from the mesh (mm) and the kernel volume (mm3): the head is the part above the shank radius step
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var bins := {}
	var ymin := 1e9
	var ymax := -1e9
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
			var key := int(roundf(p.y * 10.0))
			bins[key] = maxf(float(bins.get(key, 0.0)), Vector2(p.x, p.z).length())
	if bins.is_empty():
		return {}
	var rs := 1e9
	var rmax := 0.0
	for k in bins:
		rs = minf(rs, float(bins[k]))
		rmax = maxf(rmax, float(bins[k]))
	var lo := 1e9
	for k in bins:
		if float(bins[k]) > rs + 0.5:
			lo = minf(lo, float(k) / 10.0)
	return {"ymin": ymin, "ymax": ymax, "d": 2.0 * rs, "D": 2.0 * rmax, "L": lo, "k": ymax - lo, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0))}


## "" when the built screw is the ISO size d x L (mm); else what it measured
func is_iso(d: int, L: int) -> String:
	var g := geom()
	if g.is_empty():
		return "no geometry"
	var D: float = ISO[d][0]
	var k: float = ISO[d][1]
	var vol := PI / 4.0 * (float(d * d) * float(L) + D * D * k)
	var good: bool = absf(float(g["d"]) - d) <= 0.1 and absf(float(g["D"]) - D) <= 0.1 and absf(float(g["k"]) - k) <= 0.1
	good = good and absf(float(g["L"]) - L) <= 0.1 and absf(float(g["ymin"])) <= 0.05 and int(g["bodies"]) == 1 and absf(float(g["vol"]) - vol) <= 0.01 * vol
	if good:
		return ""
	return "head %.2f x %.2f, shank %.2f x %.2f, shank top %.2f, lowest %.2f, %d solid, %.1f vs %.1f mm3" % [float(g["D"]), float(g["k"]), float(g["d"]), float(g["L"]), float(g["L"]), float(g["ymin"]), int(g["bodies"]), float(g["vol"]), vol]


func visible_chips() -> int:
	var n := 0
	for d in ISO:
		for L in LENS:
			var c := chip(d, L)
			if c != null and c.is_visible_in_tree():
				n += 1
	return n


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
		print("FAIL: no KineCAD DLL, the screws cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	# 1 PARTS: the category chip opens the sixteen screw chips
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	var before := visible_chips()
	if pb != null:
		await click_ctl(pb)
	var seen := visible_chips()
	var off_screen := []
	var no_icon := []
	var words_ok := true
	for d in ISO:
		for L in LENS:
			var c := chip(d, L)
			if c == null:
				continue
			if not vp.encloses(Rect2(c.global_position, c.size)):
				off_screen.append(c.name)
			if c.icon == null:
				no_icon.append(c.name)
			if c.text != "M%d x %d" % [d, L]:
				words_ok = false
	ok(pb != null and before == 0 and seen == 16 and words_ok, "1 the Parts chip opens 16 screw chips named M3..M6 x 10/16/20/30 (before %d, after %d, texts %s)" % [before, seen, str(words_ok)])
	ok(off_screen.is_empty() and no_icon.is_empty(), "1 every screw chip is on the 1280 x 720 screen %s and has an icon %s" % [str(off_screen), str(no_icon)])
	await shot("parts")
	# 2 DROP: M4 x 16, one undo step, measured
	var ub0: int = m.undo.size()
	await click_ctl(chip(4, 16))
	var e1 := is_iso(4, 16)
	var rec: Dictionary = m.S.part
	ok(e1 == "" and m.undo.size() == ub0 + 1 and String((rec.get("easy", {}) as Dictionary).get("t", "")) == "screw", "2 M4 x 16 dropped on the floor: one undo step (%d -> %d), built [%s]" % [ub0, m.undo.size(), e1])
	# 3 RESIZE: M5 x 30 after placing
	var nf0: int = (m.S.part.get("features", []) as Array).size()
	var ub1: int = m.undo.size()
	await click_ctl(chip(5, 30))
	var e2 := is_iso(5, 30)
	ok(e2 == "" and m.undo.size() == ub1 + 1 and (m.S.part.get("features", []) as Array).size() == nf0, "3 M5 x 30 picked after placing: one undo step (%d -> %d), same steps (%d), built [%s]" % [ub1, m.undo.size(), nf0, e2])
	await shot("m5")
	# 4 UNDO: one Undo brings M4 x 16 back
	m._undo()
	await idle(4)
	var e3 := is_iso(4, 16)
	ok(e3 == "", "4 one Undo brings M4 x 16 back [%s]" % e3)
	# 5 SAME: the size already on the floor does nothing
	var ub2: int = m.undo.size()
	await click_ctl(chip(4, 16))
	ok(m.undo.size() == ub2, "5 the size already on the floor: no undo step (%d -> %d)" % [ub2, m.undo.size()])
	# 6 ALL 16: each size in turn, one undo step each, measured to the ISO size
	var bad := []
	var steps_ok := true
	for d in ISO:
		for L in LENS:
			if d == 4 and L == 16:
				continue
			var u: int = m.undo.size()
			await click_ctl(chip(d, L))
			var e := is_iso(d, L)
			if e != "":
				bad.append("M%d x %d [%s]" % [d, L, e])
			if m.undo.size() != u + 1:
				steps_ok = false
	ok(bad.is_empty() and steps_ok, "6 all sixteen sizes: built to ISO 4762, one undo step each %s" % str(bad))
	# 7 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for d in ISO:
		for L in LENS:
			var c := chip(d, L)
			if c != null:
				texts.append(c.text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "7 no key name in the Parts chips, hint or status %s" % str(hit))
	print("nscrew2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
