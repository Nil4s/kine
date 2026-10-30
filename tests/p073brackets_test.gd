extends SceneTree
## godot --path . --position 4000,4000 -s tests/p073brackets_test.gd     (FRIDAY 73: Brackets: an L-bracket, a T-bracket and a corner brace with screw holes, from the Easy Part Parts page (Brackets); scripts/easy_part.gd + scripts/build/part_templates.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card: a blank part on Part, Easy; no keyboard). Measured from the BUILT result (mesh vertices in mm,
## the kernel volume in mm3), never from the code's own variables. The expected numbers are the spec: a leg of 80 mm, a flange 30 mm wide, 5 mm thick,
## a 6 mm screw hole through each leg (2 holes per part).
##   expected L:      solid area 775 mm2 x 30 mm, minus 2 holes of pi x 3^2 x 5 mm  = 22967 mm3 ; box 80 x 80 x 30 mm
##   expected T:      same area and holes as the L                                  = 22967 mm3 ; box 80 x 80 x 30 mm ; a stem foot at X 37.5 and 42.5 mm, Y 0
##   expected corner: L area 775 + a 32 mm gusset (512 mm2) = 1287 mm2 x 30 mm, minus the 2 holes = 38327 mm3 ; box 80 x 80 x 30 mm
##   1 PARTS      the Brackets page opens three chips: L-bracket, T-bracket, Corner brace (each with an icon, all on screen at 1280 x 720)
##   2 L          L-bracket: ONE undo step, one solid, on the floor (lowest point 0 mm), box 80 x 80 x 30 mm, volume within 0.5 pct of 22967 mm3, no stem foot at X 37.5
##   3 T          T-bracket (after one Undo of the L): ONE undo step, one solid, box 80 x 80 x 30, volume within 0.5 pct of 22967, a stem foot at X 37.5 and 42.5 mm
##   4 CORNER     Corner brace: ONE undo step, one solid, box 80 x 80 x 30, volume within 0.5 pct of 38327 mm3 (the gusset is there)
##   5 UNDO       one Undo brings back the T-bracket's previous state (the corner brace goes away: the measured volume is the T's again)
##   6 WORDS      no key name in the Brackets chips, the hint or the status line
## Shots: C:/Temp/claude/p073brackets/brackets.png (the Brackets chips open), corner.png (the corner brace on the floor)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p073brackets"
const DIRT := "user://p073brackets_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
const BOX := Vector3(80.0, 80.0, 30.0)
const VOL_L := 22967.0
const VOL_CORNER := 38327.0
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


func chip(key: String) -> Button:
	return root.find_child("easypart_bracket_" + key, true, false) as Button


## the built result, read from the mesh (mm): the box of all vertices, the lowest point, and whether a vertex sits on the stem foot (Y 0, X 37.5 and 42.5)
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var foot := [false, false]
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
			if absf(p.y) <= 0.05:
				if absf(p.x - 37.5) <= 0.05:
					foot[0] = true
				if absf(p.x - 42.5) <= 0.05:
					foot[1] = true
	if faces.is_empty():
		return {}
	return {"box": hi - lo, "low": lo.y, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0)), "foot": foot[0] and foot[1]}


## "" when the built part is the bracket: one solid, on the floor, box 80 x 80 x 30 mm, volume within 0.5 pct of vol (mm3); else what it measured
func is_bracket(vol: float) -> String:
	var g := geom()
	if g.is_empty():
		return "no geometry"
	var b: Vector3 = g["box"]
	var good: bool = b.distance_to(BOX) <= 0.1 and absf(float(g["low"])) <= 0.05 and int(g["bodies"]) == 1
	good = good and absf(float(g["vol"]) - vol) <= 0.005 * vol
	if good:
		return ""
	return "box %.2f x %.2f x %.2f, lowest %.2f, %d solid, %.1f vs %.1f mm3" % [b.x, b.y, b.z, float(g["low"]), int(g["bodies"]), float(g["vol"]), vol]


func visible_chips() -> int:
	var n := 0
	for k in ["L", "T", "corner"]:
		var c := chip(k)
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
		print("FAIL: no KineCAD DLL, the brackets cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	# 1 PARTS: the Parts chip, then the Brackets category, opens the three bracket chips
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	if pb != null:
		await click_ctl(pb)
	var lib := root.find_child("easypart_lib_Brackets", true, false) as Button
	if lib != null:
		await click_ctl(lib)
	var before_ok := visible_chips()
	var off_screen := []
	var no_icon := []
	var words := {"L": "L-bracket", "T": "T-bracket", "corner": "Corner brace"}
	var words_ok := true
	for k in words:
		var c := chip(k)
		if c == null:
			off_screen.append("missing " + k)
			continue
		if not vp.encloses(Rect2(c.global_position, c.size)):
			off_screen.append(c.name)
		if c.icon == null:
			no_icon.append(c.name)
		if c.text != words[k]:
			words_ok = false
	ok(lib != null and before_ok == 3 and words_ok, "1 the Brackets page opens three chips: L-bracket, T-bracket, Corner brace (visible %d, texts %s)" % [before_ok, str(words_ok)])
	ok(off_screen.is_empty() and no_icon.is_empty(), "1 every bracket chip is on the 1280 x 720 screen %s and has an icon %s" % [str(off_screen), str(no_icon)])
	await shot("brackets")
	# 2 L: one undo step, one solid, box and volume measured
	var ub0: int = m.undo.size()
	await click_ctl(chip("L"))
	var e1 := is_bracket(VOL_L)
	var g1 := geom()
	var l_ok := e1 == "" and not bool(g1.get("foot", true))
	ok(l_ok and m.undo.size() == ub0 + 1, "2 L-bracket on the floor: one undo step (%d -> %d), no stem foot, built [%s]" % [ub0, m.undo.size(), e1])
	# 3 T: after the L, one step, the stem foot is there
	var ub1: int = m.undo.size()
	await click_ctl(chip("T"))
	var e2 := is_bracket(VOL_L)
	var g2 := geom()
	ok(e2 == "" and bool(g2.get("foot", false)) and m.undo.size() == ub1 + 1, "3 T-bracket after the L: one undo step (%d -> %d), a stem foot at X 37.5 and 42.5, built [%s]" % [ub1, m.undo.size(), e2])
	# 4 CORNER: one step, the gusset makes the volume bigger
	var ub2: int = m.undo.size()
	await click_ctl(chip("corner"))
	var e3 := is_bracket(VOL_CORNER)
	ok(e3 == "" and m.undo.size() == ub2 + 1, "4 Corner brace: one undo step (%d -> %d), built [%s]" % [ub2, m.undo.size(), e3])
	await shot("corner")
	# 5 UNDO: one Undo brings back the T-bracket (its volume is the T's again)
	m._undo()
	await idle(4)
	var e4 := is_bracket(VOL_L)
	ok(e4 == "" and bool(geom().get("foot", false)), "5 one Undo brings the T-bracket back [%s]" % e4)
	# 6 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for k in words:
		var c := chip(k)
		if c != null:
			texts.append(c.text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "6 no key name in the Brackets chips, hint or status %s" % str(hit))
	print("p073brackets: %d fail" % fails)
	quit(1 if fails > 0 else 0)
