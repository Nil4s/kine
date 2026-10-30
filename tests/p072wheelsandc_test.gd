extends SceneTree
## p072wheelsandc (Friday plan item 72): Wheels and castors with axle hole. The Parts library's Wheels category opens two chips:
## Wheel (80 mm across, 20 mm wide, 8 mm axle hole) and Castor (50 mm across, 16 mm wide, 6 mm axle hole). A beginner walk with real
## clicks on the live Easy Part, from the BUILDING card (no keyboard). Measured from the BUILT result (mesh mm, item counts, undo steps,
## kernel volume), never from the code's own variables. Bars are written before the code; the bars that FAIL on the old code (Wheels said
## 'coming soon', no wheel chips) are marked in the bar text. The wheel's axle runs along world X: width along X, across in Y and Z.
##   0 BUILDING card, one click -> Easy Part on                                                                                 (passes on old code: a guard)
##   1 PAGE      Parts, then Wheels: two chips 'Wheel' and 'Castor' show, on the 1280 x 720 screen, 34 px or taller; no 'coming soon'   (FAILS on old code)
##   2 WHEEL     Wheel: ONE undo step, one solid, 80 mm across (+- 0.6), 20 mm wide (+- 0.3), axle hole 8 mm (+- 0.2), volume within 1 pct of pi W (R2 - h2)  (FAILS on old code)
##   3 CASTOR    Castor (the wheel on the floor is replaced): ONE undo step, one solid, 50 mm across (+- 0.6), 16 mm wide (+- 0.3), axle hole 6 mm (+- 0.2), volume within 1 pct   (FAILS on old code)
##   4 UNDO      Undo: the 80 mm Wheel is back, one solid, its own numbers                                                        (FAILS on old code)
##   5 WORDS     no key name in the chip words, the hint or the status line                                                       (passes on old code: a guard, the words are checked on the new screen)
## Shots: C:/Temp/claude/p072wheelsandc/*.png
const SHOT := "C:/Temp/claude/p072wheelsandc"
const DIRT := "user://p072wheelsandc_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## the two wheels: [across mm, width mm, axle hole mm]
const WHEEL := {"wheel": [80.0, 20.0, 8.0], "castor": [50.0, 16.0, 6.0]}
var fails := 0
var m: Node
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


## a real click on a visible control; a missing control is reported by the bar that needs it (no crash)
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


func lib(cat: String) -> Button:
	return root.find_child("easypart_lib_" + cat, true, false) as Button


func soon_label() -> Label:
	return root.find_child("easypart_lib_soon", true, false) as Label


func wheel_chip(k: String) -> Button:
	return root.find_child("easypart_wheel_" + k, true, false) as Button


## the built wheel, read from the mesh (mm): the width is the extent along X (the axle), the across is twice the largest radius
## round the axle line (X), the axle hole is twice the smallest radius of any vertex round that line; the volume is the kernel's (mm3)
func wheel_geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var xlo := 1e9
	var xhi := -1e9
	var rmax := 0.0
	var rmin := 1e9
	var n := 0
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			n += 1
			xlo = minf(xlo, p.x)
			xhi = maxf(xhi, p.x)
			var r := Vector2(p.y, p.z).length()
			rmax = maxf(rmax, r)
			rmin = minf(rmin, r)
	if n == 0:
		return {}
	return {"width": xhi - xlo, "across": 2.0 * rmax, "hole": 2.0 * rmin, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0))}


## "" when the built wheel is the k size (mm, mm, mm), one solid, volume within 1 pct of the axle wheel's volume; else what it measured
func is_wheel(k: String) -> String:
	var g := wheel_geom()
	if g.is_empty():
		return "no geometry"
	var s: Array = WHEEL[k]
	var R: float = s[0] * 0.5
	var W: float = s[1]
	var h: float = s[2] * 0.5
	var vol := PI * W * (R * R - h * h)
	var good: bool = absf(float(g["across"]) - s[0]) <= 0.6 and absf(float(g["width"]) - s[1]) <= 0.3 and absf(float(g["hole"]) - s[2]) <= 0.2
	good = good and int(g["bodies"]) == 1 and absf(float(g["vol"]) - vol) <= 0.01 * vol
	if good:
		return ""
	return "across %.2f, width %.2f, axle hole %.2f, %d solid, %.1f vs %.1f mm3" % [float(g["across"]), float(g["width"]), float(g["hole"]), int(g["bodies"]), float(g["vol"]), vol]


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
		print("FAIL: no KineCAD DLL, the wheels cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# 0 BUILDING card -> Easy Part on
	ok(ep != null and pu.ep != null, "0 the BUILDING card, one click: Easy Part is on")

	# 1 PAGE: Parts, then Wheels: the two chips show
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Button)
	await click_ctl(lib("Wheels"))
	var shown := []
	var off := []
	var small := []
	for k in ["wheel", "castor"]:
		var b := wheel_chip(k)
		if b != null and b.is_visible_in_tree():
			shown.append(k)
			if not vp.encloses(Rect2(b.global_position, b.size)):
				off.append(k)
			if b.size.y < 34.0:
				small.append("%s %.0f px" % [k, b.size.y])
	var sl := soon_label()
	var soon_hidden := sl == null or not sl.is_visible_in_tree()
	ok(shown.size() == 2 and off.is_empty() and small.is_empty() and soon_hidden, "1 Wheels shows the Wheel and Castor chips (%s), on the 1280 x 720 screen %s, 34 px or taller %s, no 'coming soon' (%s)" % [str(shown), str(off), str(small), str(soon_hidden)])
	await shot("page")

	# 2 WHEEL: one undo step, one solid, 80 across, 20 wide, 8 mm axle hole
	var ub0: int = m.undo.size()
	await click_ctl(wheel_chip("wheel"))
	var e := is_wheel("wheel")
	ok(e == "" and m.undo.size() == ub0 + 1, "2 Wheel: one undo step (%d -> %d), built to 80 x 20 mm with an 8 mm axle hole [%s]" % [ub0, m.undo.size(), e])
	await shot("wheel")

	# 3 CASTOR: replaces the wheel: one undo step, 50 across, 16 wide, 6 mm axle hole
	var ub1: int = m.undo.size()
	await click_ctl(wheel_chip("castor"))
	var e2 := is_wheel("castor")
	ok(e2 == "" and m.undo.size() == ub1 + 1, "3 Castor: one undo step (%d -> %d), built to 50 x 16 mm with a 6 mm axle hole [%s]" % [ub1, m.undo.size(), e2])
	await shot("castor")

	# 4 UNDO: the Wheel comes back, as it was built
	await click_ctl(ep.undo_btn)
	var e3 := is_wheel("wheel")
	ok(e3 == "", "4 Undo brings the 80 mm Wheel back, one solid, its own numbers [%s]" % e3)

	# 5 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for k in ["wheel", "castor"]:
		var b := wheel_chip(k)
		if b != null:
			texts.append(b.text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "5 no key name in the chip words, the hint or the status %s" % str(hit))
	print("p072wheelsandc: %d fail" % fails)
	quit(1 if fails > 0 else 0)
