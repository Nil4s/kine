extends SceneTree
## P069 BEARINGS (Friday plan item 69): the Easy Part Parts page gets a real Bearings category (608, 625, 688: a bore, an outside
## diameter and a width, ISO 15 numbers) and 'Make a seat for it' cuts a seat for the bearing on the floor: a holder block with a
## pocket the bearing's outside diameter (+ 0.2 mm clearance) deep as its width, the bearing standing beside it.
## A beginner walk with real clicks on the live Easy Part, from the BUILDING card (no keyboard). Measured from the BUILT result (mesh mm,
## volume mm3, solid count, undo steps, control sizes), never from the code's own variables. Bars were written BEFORE the code; the run on
## the code before this change is in the item's report (every bar with 'Bearings' in it FAILS there: the category said coming soon).
##   1 PAGE      the Bearings chip is ready (no 'coming soon'), opens three chips 608 / 625 / 688, each 34 px or taller, on the 1280 x 720 screen, each with an icon
##   2 REFUSE    Make a seat for it with nothing on the floor: no undo step, and the words name Bearings as the next step
##   3 608       press 608: ONE undo step, one solid, bore 8.0, outside 22.0, width 7.0 mm (+- 0.1), volume within 1 pct of pi/4 (22^2 - 8^2) 7 mm
##   4 625 688   press 625 then 688 (each ONE undo step): 625 = bore 5 / outside 16 / width 5; 688 = bore 8 / outside 16 / width 5 (+- 0.1, 1 pct volume)
##   5 SEAT      608 on the floor, Make a seat for it: ONE undo step, two solids; holder 34.0 x 34.0 x 13.0 mm (+- 0.1), its pocket opening 11.1 mm radius
##               (+- 0.1, the smallest radius of the top face), the total volume within 1 pct of holder - pocket + bearing; the bearing still 22.0 x 7.0 mm
##   6 WORDS     no key name in the bearing words, the seat button, the hint or the status line
## Shots: C:/Temp/claude/p069bearingswi/page.png (the page), seat.png (the seat on the floor)
const SHOT := "C:/Temp/claude/p069bearingswi"
const DIRT := "user://p069bearingswi_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## the three bearings: [chip, bore, outside diameter, width] in mm (deep groove ball bearings, ISO 15: 608 = 8 x 22 x 7, 625 = 5 x 16 x 5, 688 = 8 x 16 x 5)
const BEARINGS := [["608", 8.0, 22.0, 7.0], ["625", 5.0, 16.0, 5.0], ["688", 8.0, 16.0, 5.0]]
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


func bear_chip(code: String) -> Button:
	return root.find_child("easypart_bear_" + code, true, false) as Button


func seat_btn() -> Button:
	return root.find_child("easypart_bear_seat", true, false) as Button


func soon_label() -> Label:
	return root.find_child("easypart_lib_soon", true, false) as Label


## the built result read from the mesh (mm): every vertex's distance from the Y axis, the height range, and the kernel volume (mm3)
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var verts: Array = []
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			verts.append(v * 1000.0)
	if verts.is_empty():
		return {}
	return {"verts": verts, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0))}


## the bearing standing alone on the floor: [bore, outside, width] in mm, measured from its vertices
func ring_size(g: Dictionary, cx := 0.0) -> Array:
	var rmin := 1e9
	var rmax := 0.0
	var ymin := 1e9
	var ymax := -1e9
	for p in g["verts"]:
		var r := Vector2(p.x - cx, p.z).length()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	return [2.0 * rmin, 2.0 * rmax, ymax - ymin]


## the seat with its bearing beside it: the holder is the vertices at x < 25 mm, the bearing those at x > 25 mm
func holder_size(g: Dictionary) -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var rtop := 1e9   # the smallest radius of the holder's top face (y = 0): the pocket's opening
	var bear := []
	for p in g["verts"]:
		if p.x < 25.0:
			lo = lo.min(p)
			hi = hi.max(p)
			if absf(p.y) < 0.05:
				rtop = minf(rtop, Vector2(p.x, p.z).length())
		else:
			bear.append(p)
	var bsz := [0.0, 0.0, 0.0]
	if not bear.is_empty():
		var bx := 0.0
		for p in bear:
			bx += p.x / float(bear.size())   # the bearing's own centre (the mean of its vertices: a ring is symmetric about it)
		var rmin := 1e9
		var rmax := 0.0
		var ymin := 1e9
		var ymax := -1e9
		for p in bear:
			var r := Vector2(p.x - bx, p.z).length()
			rmin = minf(rmin, r)
			rmax = maxf(rmax, r)
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
		bsz = [2.0 * rmin, 2.0 * rmax, ymax - ymin]
	return {"w": hi.x - lo.x, "d": hi.z - lo.z, "h": hi.y - lo.y, "top": rtop, "bear": bsz}


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

	# 1 PAGE: Bearings is ready, its three chips show, each 34 px or taller, on the screen, each with an icon
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Button)
	await click_ctl(lib("Bearings"))
	var shown := 0
	var off := []
	var small := []
	var no_icon := []
	var named := []
	for b in BEARINGS:
		var c: Button = bear_chip(b[0])
		if c == null or not c.is_visible_in_tree():
			continue
		shown += 1
		if not vp.encloses(Rect2(c.global_position, c.size)):
			off.append(b[0])
		if c.size.y < 34.0:
			small.append("%s %.0f px" % [b[0], c.size.y])
		if c.icon == null:
			no_icon.append(b[0])
	var sl := soon_label()
	var soon_shown := sl != null and sl.is_visible_in_tree()
	ok(shown == 3 and not soon_shown and off.is_empty() and small.is_empty() and no_icon.is_empty() and named.is_empty(), "1 Bearings opens 608, 625, 688 (%d of 3 shown), 'coming soon' hidden (%s), off screen %s, under 34 px %s, no icon %s" % [shown, str(soon_shown), str(off), str(small), str(no_icon)])
	await shot("page")

	# 2 REFUSE: Make a seat for it with nothing on the floor: no undo step, and the words name Bearings
	var ub0: int = m.undo.size()
	await click_ctl(seat_btn())
	var said := String(ep.hint_l.text).to_lower()   # the words of a press go to the hint line (the status line shows the built part)
	ok(m.undo.size() == ub0 and said.contains("bearing"), "2 Make a seat for it with nothing on the floor: no undo step (%d -> %d), it names Bearings [%s]" % [ub0, m.undo.size(), String(ep.hint_l.text)])

	# 3 608: one undo step, one solid, the 608 size from the mesh
	var ub1: int = m.undo.size()
	await click_ctl(bear_chip("608"))
	var g := geom()
	var sz := ring_size(g) if not g.is_empty() else [0.0, 0.0, 0.0]
	var want := BEARINGS[0]
	var vol_want := PI / 4.0 * (float(want[2]) * float(want[2]) - float(want[1]) * float(want[1])) * float(want[3])
	var good608 := not g.is_empty() and int(g["bodies"]) == 1 and absf(float(sz[0]) - want[1]) <= 0.1 and absf(float(sz[1]) - want[2]) <= 0.1 and absf(float(sz[2]) - want[3]) <= 0.1 and absf(float(g.get("vol", 0.0)) - vol_want) <= 0.01 * vol_want
	ok(good608 and m.undo.size() == ub1 + 1, "3 608: one undo step (%d -> %d), %d solid, bore %.2f, outside %.2f, width %.2f mm (want 8 / 22 / 7 +- 0.1), %.1f mm3 vs %.1f" % [ub1, m.undo.size(), int(g.get("bodies", 0)), float(sz[0]), float(sz[1]), float(sz[2]), float(g.get("vol", 0.0)), vol_want])
	await shot("bearing")

	# 4 625 and 688: each one undo step, each its own size
	var ub2: int = m.undo.size()
	var sizes_bad := []
	for i in [1, 2]:
		var b: Array = BEARINGS[i]
		var before_n: int = m.undo.size()
		await click_ctl(bear_chip(b[0]))
		var g2 := geom()
		var s2 := ring_size(g2) if not g2.is_empty() else [0.0, 0.0, 0.0]
		var vw := PI / 4.0 * (float(b[2]) * float(b[2]) - float(b[1]) * float(b[1])) * float(b[3])
		if not (not g2.is_empty() and int(g2["bodies"]) == 1 and absf(float(s2[0]) - b[1]) <= 0.1 and absf(float(s2[1]) - b[2]) <= 0.1 and absf(float(s2[2]) - b[3]) <= 0.1 and absf(float(g2.get("vol", 0.0)) - vw) <= 0.01 * vw and m.undo.size() == before_n + 1):
			sizes_bad.append("%s bore %.2f outside %.2f width %.2f undo %d -> %d" % [b[0], float(s2[0]), float(s2[1]), float(s2[2]), before_n, m.undo.size()])
	ok(sizes_bad.is_empty() and m.undo.size() == ub2 + 2, "4 625 then 688: each one undo step, bore / outside / width and volume as the bearing (want 5/16/5 and 8/16/5 +- 0.1) %s" % str(sizes_bad))

	# 5 SEAT: 608 on the floor, Make a seat for it: one undo step, two solids, the holder and pocket from the mesh
	await click_ctl(bear_chip("608"))
	var ub3: int = m.undo.size()
	await click_ctl(seat_btn())
	var g3 := geom()
	var seat_msg := ""
	if not g3.is_empty():
		var hs := holder_size(g3)
		var bs: Array = hs["bear"]
		var hole_r := 11.1
		var vol_holder := 34.0 * 34.0 * 13.0 - PI * hole_r * hole_r * 7.0
		var vol_want3 := vol_holder + PI / 4.0 * (22.0 * 22.0 - 8.0 * 8.0) * 7.0
		var seat_ok := int(g3["bodies"]) == 2 and absf(float(hs["w"]) - 34.0) <= 0.1 and absf(float(hs["d"]) - 34.0) <= 0.1 and absf(float(hs["h"]) - 13.0) <= 0.1 and absf(float(hs["top"]) - hole_r) <= 0.1
		seat_ok = seat_ok and absf(float(bs[0]) - 8.0) <= 0.1 and absf(float(bs[1]) - 22.0) <= 0.1 and absf(float(bs[2]) - 7.0) <= 0.1
		seat_ok = seat_ok and absf(float(g3["vol"]) - vol_want3) <= 0.01 * vol_want3
		seat_msg = "%d solids, holder %.2f x %.2f x %.2f mm, pocket radius %.2f mm (want 34 x 34 x 13, 11.1), bearing bore %.2f outside %.2f width %.2f, %.1f mm3 vs %.1f" % [int(g3["bodies"]), float(hs["w"]), float(hs["d"]), float(hs["h"]), float(hs["top"]), float(bs[0]), float(bs[1]), float(bs[2]), float(g3["vol"]), vol_want3]
		ok(seat_ok and m.undo.size() == ub3 + 1, "5 Make a seat for it: one undo step (%d -> %d), %s" % [ub3, m.undo.size(), seat_msg])
	else:
		ok(false, "5 Make a seat for it: no built result (undo %d -> %d)" % [ub3, m.undo.size()])
	await shot("seat")

	# 6 WORDS: no key name in the bearing words, the seat button, the hint or the status line
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for b in BEARINGS:
		var c := bear_chip(b[0])
		if c != null:
			texts.append(c.text)
	var sb := seat_btn()
	if sb != null:
		texts.append(sb.text)
		texts.append(sb.tooltip_text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "6 no key name in the bearing words, the seat button, the hint or the status %s" % str(hit))
	print("p069bearingswi: %d fail" % fails)
	quit(1 if fails > 0 else 0)
