extends SceneTree
## godot --path . --position 4000,4000 -s tests/p206threadgene_test.gd     (EASY PART: Parts > Screws, the threaded rod chips M8 M10 M12; scripts/easy_part.gd + scripts/build/part_templates.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card: a blank part on Part, Easy; no keyboard). Measured from the BUILT result (mesh vertices in mm,
## the kernel volume), never from the code's own variables. The expected values are the ISO coarse table and the print clearance written out below.
##   1 PARTS     the Screws page shows three rod chips (M8 rod, M10 rod, M12 rod), each with an icon, all on screen at 1280 x 720
##   2 DROP      M8 rod: ONE undo step, one solid, on the floor (lowest point at 0 mm), about 30 mm tall, outside 7.70 mm (8 minus 0.15 x 2),
##               root 2 x (4 - 0.6134 x 1.25) mm, 24 crests (pitch 1.25), volume within 1 pct of the analytic ring volume
##   3 RESIZE    M10 rod picked after placing: ONE undo step, still one solid, same number of steps, outside 9.85, 20 crests, root 2 x (5 - 0.6134 x 1.5)
##   4 M12       M12 rod: ONE undo step, 17 crests (pitch 1.75), outside 11.85, about 30 mm tall, volume within 1 pct
##   5 UNDO      one Undo brings the M10 rod back (measured again)
##   6 SAME      picking the size already on the floor does nothing (no undo step)
##   7 WORDS     no key name in the rod chips, the hint or the status line
## Shots: C:/Temp/claude/p206threadgene/rods.png (the Screws page), m8.png (M8 rod on the floor)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p206threadgene"
const DIRT := "user://p206threadgene_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO coarse threads: the pitch (mm) by the nominal size; the crest is 0.15 mm under nominal (print clearance); the root is the ISO basic depth 0.6134 P under nominal
const PITCH := {8: 1.25, 10: 1.5, 12: 1.75}
const CLEAR := 0.15
const LEN := 30.0
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


func rod_chip(d: int) -> Button:
	return root.find_child("easypart_rod_M%d" % d, true, false) as Button


## the built rod, read from the mesh (mm) and the kernel volume (mm3). Crests are the rings at the outside radius (the mesh's
## vertices at a height, most outside); the root is the least radius (the axis itself is left out).
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var bins := {}
	var ymin := 1e9
	var ymax := -1e9
	var rmin := 1e9
	var rmax := 0.0
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			var r := Vector2(p.x, p.z).length()
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
			rmax = maxf(rmax, r)
			if r > 0.05:
				rmin = minf(rmin, r)
			var key := int(roundf(p.y * 10.0))
			bins[key] = maxf(float(bins.get(key, 0.0)), r)
	if bins.is_empty():
		return {}
	var mid := (rmin + rmax) * 0.5
	var crests := 0
	for k in bins:
		if float(bins[k]) > mid:
			crests += 1
	return {"ymin": ymin, "ymax": ymax, "H": ymax - ymin, "D": 2.0 * rmax, "d": 2.0 * rmin, "crests": crests, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0)), "feats": (m.S.part.get("features", []) as Array).size()}


## the analytic volume of the ring thread: pi x H x (r^2 + r R + R^2) / 3, with H = n pitches. Expected numbers come from the table above only.
func expect_vol(d: int) -> float:
	var P: float = PITCH[d]
	var R := float(d) * 0.5 - CLEAR
	var r := float(d) * 0.5 - 0.6134 * P
	var H := roundf(LEN / P) * P
	return PI * H * (r * r + r * R + R * R) / 3.0


## "" when the built rod is the size d (mm); else what it measured
func is_rod(d: int) -> String:
	var g := geom()
	if g.is_empty():
		return "no geometry"
	var P: float = PITCH[d]
	var n := int(roundf(LEN / P))
	var D := float(d) - 2.0 * CLEAR
	var dr := 2.0 * (float(d) * 0.5 - 0.6134 * P)
	var good: bool = absf(float(g["D"]) - D) <= 0.05 and absf(float(g["d"]) - dr) <= 0.05 and int(g["crests"]) == n
	good = good and absf(float(g["H"]) - float(n) * P) <= 0.05 and absf(float(g["ymin"])) <= 0.05 and int(g["bodies"]) == 1
	good = good and absf(float(g["vol"]) - expect_vol(d)) <= 0.01 * expect_vol(d)
	if good:
		return ""
	return "outside %.2f, root %.2f, %d crests, %.2f tall, lowest %.2f, %d solid, %.1f vs %.1f mm3" % [float(g["D"]), float(g["d"]), int(g["crests"]), float(g["H"]), float(g["ymin"]), int(g["bodies"]), float(g["vol"]), expect_vol(d)]


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
		print("FAIL: no KineCAD DLL, the rods cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	# 1 PARTS: Parts, then the Screws page: three rod chips
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	if pb != null:
		await click_ctl(pb)
	var sc := root.find_child("easypart_lib_Screws", true, false) as Button
	if sc != null:
		await click_ctl(sc)
	var off_screen := []
	var no_icon := []
	var texts_ok := true
	var shown := 0
	for d in PITCH:
		var c := rod_chip(d)
		if c == null or not c.is_visible_in_tree():
			off_screen.append("missing M%d rod" % d)
			continue
		shown += 1
		if not vp.encloses(Rect2(c.global_position, c.size)):
			off_screen.append(c.name)
		if c.icon == null:
			no_icon.append(c.name)
		if c.text != "M%d rod" % d:
			texts_ok = false
	ok(sc != null and pb != null and shown == 3 and texts_ok, "1 the Screws page shows three rod chips: M8 rod, M10 rod, M12 rod (shown %d, texts %s)" % [shown, str(texts_ok)])
	ok(off_screen.is_empty() and no_icon.is_empty(), "1 every rod chip is on the 1280 x 720 screen %s and has an icon %s" % [str(off_screen), str(no_icon)])
	await shot("rods")
	# 2 DROP: M8 rod, one undo step, measured
	var ub0: int = m.undo.size()
	await click_ctl(rod_chip(8))
	var e1 := is_rod(8)
	var rec: Dictionary = m.S.part
	ok(e1 == "" and m.undo.size() == ub0 + 1 and String((rec.get("easy", {}) as Dictionary).get("t", "")) == "rod", "2 M8 rod dropped on the floor: one undo step (%d -> %d), built [%s]" % [ub0, m.undo.size(), e1])
	await shot("m8")
	# 3 RESIZE: M10 rod after placing, same steps
	var nf0: int = (m.S.part.get("features", []) as Array).size()
	var ub1: int = m.undo.size()
	await click_ctl(rod_chip(10))
	var e2 := is_rod(10)
	ok(e2 == "" and m.undo.size() == ub1 + 1 and (m.S.part.get("features", []) as Array).size() == nf0, "3 M10 rod picked after placing: one undo step (%d -> %d), same steps (%d), built [%s]" % [ub1, m.undo.size(), nf0, e2])
	# 4 M12: one undo step, measured
	var ub2: int = m.undo.size()
	await click_ctl(rod_chip(12))
	var e3 := is_rod(12)
	ok(e3 == "" and m.undo.size() == ub2 + 1, "4 M12 rod: one undo step (%d -> %d), built [%s]" % [ub2, m.undo.size(), e3])
	# 5 UNDO: one Undo brings the M10 rod back
	m._undo()
	await idle(4)
	var e4 := is_rod(10)
	ok(e4 == "", "5 one Undo brings the M10 rod back [%s]" % e4)
	# 6 SAME: the size already on the floor does nothing
	var ub3: int = m.undo.size()
	await click_ctl(rod_chip(10))
	ok(m.undo.size() == ub3, "6 the size already on the floor: no undo step (%d -> %d)" % [ub3, m.undo.size()])
	# 7 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for d in PITCH:
		var c := rod_chip(d)
		if c != null:
			texts.append(c.text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "7 no key name in the rod chips, hint or status %s" % str(hit))
	print("p206threadgene: %d fail" % fails)
	quit(1 if fails > 0 else 0)
