extends SceneTree
## NLIBPAGE (Friday plan item 60): the Easy Part 'Parts' button opens a library page by category: Screws, Nuts, Washers, Gears, Hinges,
## Bearings, Springs, Handles, Wheels, Brackets. Screws opens the screw sizes, Gears the Gear part; the other eight say 'coming soon'.
## A beginner walk with real clicks on the live Easy Part, from the BUILDING card (no keyboard). Measured from the BUILT result (mesh mm,
## item counts, undo steps), never from the code's own variables. Bars are written before the code; the bars that FAIL on the old code
## (no library page: the Parts chip opened the screw grid straight away) are marked in the bar text.
##   1 PAGE      the Parts chip opens a page with ten category chips, named and worded exactly, all on the 1280 x 720 screen, each 34 px or taller, each with an icon   (FAILS on old code)
##   2 OPENS     opening the page and all ten categories makes no undo step (opening is not an action)                                                              (FAILS on old code)
##   3 SOON      Nuts, Washers, Hinges, Bearings, Springs, Handles, Wheels, Brackets each say 'coming soon' and name the next step (Screws), and build nothing   (FAILS on old code)
##   4 SHOWS     Screws shows the sixteen screw chips; Gears shows the Gear chip and hides 'coming soon'                                                             (FAILS on old code)
##   5 GEAR      Gears, then the Gear chip: ONE undo step, one solid, tip diameter 64 mm (+- 0.6, teeth 30 x module 2 + 2 x module, measured from the mesh)     (FAILS on old code)
##   6 SCREW     Screws, then M4 x 16: ONE undo step, one solid, built to ISO 4762 (head 7.0 x 4.0, shank 4.0 x 16.0 mm, volume within 1 pct)                       (FAILS on old code)
##   7 WORDS     no key name in the library words, the 'coming soon' line, the hint or the status line
## Shots: C:/Temp/claude/nlibpage/page.png (the library page), soon.png (Hinges), gear.png (the Gear on the floor)
const SHOT := "C:/Temp/claude/nlibpage"
const DIRT := "user://nlibpage_test"
const CATS := ["Screws", "Nuts", "Washers", "Gears", "Hinges", "Bearings", "Springs", "Handles", "Wheels", "Brackets"]
const SOON := ["Nuts", "Washers", "Hinges", "Bearings", "Springs", "Handles", "Wheels", "Brackets"]
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO 4762 socket head: [head diameter, head height] in mm, by the nominal size (the shank is the nominal size, plain)
const ISO := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
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


func chip(d: int, L: int) -> Button:
	return root.find_child("easypart_screw_M%d_%d" % [d, L], true, false) as Button


func gear_chip() -> Button:
	return root.find_child("easypart_chip_gear", true, false) as Button


func screw_count_visible() -> int:
	var n := 0
	for d in ISO:
		for L in [10, 16, 20, 30]:
			var c := chip(d, L)
			if c != null and c.is_visible_in_tree():
				n += 1
	return n


## the built result, read from the mesh (mm) and the kernel volume (mm3)
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var bins := {}
	var ymin := 1e9
	var rmax := 0.0
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			ymin = minf(ymin, p.y)
			var r := Vector2(p.x, p.z).length()
			rmax = maxf(rmax, r)
			var key := int(roundf(p.y * 10.0))
			bins[key] = maxf(float(bins.get(key, 0.0)), r)
	if bins.is_empty():
		return {}
	var rs := 1e9
	var ymax := -1e9
	for k in bins:
		rs = minf(rs, float(bins[k]))
		ymax = maxf(ymax, float(k) / 10.0)
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
	return "head %.2f x %.2f, shank %.2f x %.2f, lowest %.2f, %d solid, %.1f vs %.1f mm3" % [float(g["D"]), float(g["k"]), float(g["d"]), float(g["L"]), float(g["ymin"]), int(g["bodies"]), float(g["vol"]), vol]


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
		print("FAIL: no KineCAD DLL, the library cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# 1 PAGE: the Parts chip opens the page with ten category chips
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	var names_ok := []
	var off := []
	var small := []
	var no_icon := []
	for c in CATS:
		var b := lib(c)
		if b == null:
			names_ok.append("missing " + c)
			continue
		if b.text != c:
			names_ok.append("%s says [%s]" % [c, b.text])
		if not vp.encloses(Rect2(b.global_position, b.size)):
			off.append(c)
		if b.size.y < 34.0:
			small.append("%s %.0f px" % [c, b.size.y])
		if b.icon == null:
			no_icon.append(c)
	var shown := 0
	for c in CATS:
		var b := lib(c)
		if b != null and b.is_visible_in_tree():
			shown += 1
	ok(pb != null and shown == 10 and names_ok.is_empty(), "1 the Parts chip opens a page with 10 category chips shown %d/10, names %s" % [shown, str(names_ok)])
	ok(off.is_empty() and small.is_empty() and no_icon.is_empty(), "1 every category chip is on the 1280 x 720 screen %s, 34 px or taller %s, with an icon %s" % [str(off), str(small), str(no_icon)])
	await shot("page")

	# 2 OPENS: the whole walk over the categories makes no undo step
	var ub0: int = m.undo.size()
	for c in CATS:
		await click_ctl(lib(c))
	ok(m.undo.size() == ub0, "2 opening all ten categories: no undo step (%d -> %d)" % [ub0, m.undo.size()])

	# 3 SOON: the eight empty categories say coming soon, name the next step, build nothing
	var soon_bad := []
	var ub1: int = m.undo.size()
	for c in SOON:
		await click_ctl(lib(c))
		var sl := soon_label()
		var txt := sl.text if sl != null else ""
		var status := String(ep.status_l.text)
		if sl == null or not sl.is_visible_in_tree() or not txt.to_lower().contains("coming soon"):
			soon_bad.append("%s label [%s]" % [c, txt])
		elif not (txt + " " + status).contains("Screws"):
			soon_bad.append("%s names no next step [%s]" % [c, status])
	ok(soon_bad.is_empty() and m.undo.size() == ub1, "3 the eight empty categories say 'coming soon' and name the next step, no build (undo %d -> %d) %s" % [ub1, m.undo.size(), str(soon_bad)])
	await shot("soon")

	# 4 SHOWS: Screws opens the sixteen screw sizes; Gears the Gear chip and no 'coming soon'
	await click_ctl(lib("Screws"))
	var scr := screw_count_visible()
	await click_ctl(lib("Gears"))
	var gc := gear_chip()
	var gshown := gc != null and gc.is_visible_in_tree()
	var sl2 := soon_label()
	var soon_hidden := sl2 == null or not sl2.is_visible_in_tree()
	ok(scr == 16 and gshown and soon_hidden, "4 Screws shows 16 size chips (%d), Gears shows the Gear chip (%s) and hides 'coming soon' (%s)" % [scr, str(gshown), str(soon_hidden)])

	# 5 GEAR: the Gear chip builds one gear, one undo step, tip diameter 64 mm
	var ub2: int = m.undo.size()
	await click_ctl(gc)
	var g := geom()
	var gear_ok := not g.is_empty() and int(g["bodies"]) == 1 and absf(float(g["D"]) - 64.0) <= 0.6
	ok(gear_ok and m.undo.size() == ub2 + 1, "5 Gear: one undo step (%d -> %d), one solid, tip diameter %.2f mm (want 64 +- 0.6)" % [ub2, m.undo.size(), float(g.get("D", 0.0))])
	await shot("gear")

	# 6 SCREW: Screws, M4 x 16: one undo step, built to ISO
	await click_ctl(lib("Screws"))
	var ub3: int = m.undo.size()
	await click_ctl(chip(4, 16))
	var e := is_iso(4, 16)
	ok(e == "" and m.undo.size() == ub3 + 1, "6 Screws, M4 x 16: one undo step (%d -> %d), built to ISO [%s]" % [ub3, m.undo.size(), e])

	# 7 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for c in CATS:
		var b := lib(c)
		if b != null:
			texts.append(b.text)
	var sl3 := soon_label()
	if sl3 != null:
		texts.append(sl3.text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "7 no key name in the library words, 'coming soon', hint or status %s" % str(hit))
	print("nlibpage: %d fail" % fails)
	quit(1 if fails > 0 else 0)
