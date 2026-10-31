extends SceneTree
## godot --path . --position 4000,4000 -s tests/p061screwheads_test.gd     (P061SCREWHEADS: the Screws page's head chips: Socket, Button (ISO 7380), Flat (ISO 10642 countersunk); scripts/easy_part.gd + scripts/build/part_templates.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card: a blank part on Part, Easy; no keyboard). Measured from the BUILT result (mesh vertices in mm,
## the kernel volume and the body count), never from the code's own variables. The head tables below are the only expected values.
##   1 CHIPS      the Parts chip opens the screws; three head chips (Socket, Button, Flat) are on screen at 1280 x 720
##   2 BUTTON     M5 x 20 with the Button head picked first: ONE undo step, one solid, lowest point 0, head 9.5 mm across, 2.75 mm high (within 0.05),
##                length under the head 20.0 mm (within 0.05), shank 5.0 mm across
##   3 FLAT       the Flat head picked on the floor: ONE undo step, one solid, head 10.0 mm across (ISO 10642 dk max, within 0.05), total length 20.0
##                within 0.05 (the length includes the head), shank 5.0 across
##   4 UNDO       one Undo brings the Button head back (measured again)
##   5 SOCKET     the Socket head picked: M5 x 20 is the ISO 4762 head again (8.5 x 5.0), one solid (the socket is unchanged)
##   6 ALL        M3 M4 M5 M6 x 20 with each of the Button and Flat heads: each one solid, no failed step, measured to its table
##   7 SAME       the head already on the floor does nothing (no undo step)
##   8 WORDS      no key name in the head chips, the hint or the status line
## Shots: C:/Temp/claude/p061screwheads/parts.png (the Parts chips open with the head row), button.png (M5 x 20 button), flat.png (M5 x 20 flat)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p061screwheads"
const DIRT := "user://p061screwheads_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO 4762 socket head: [head diameter, head height] in mm (as tests/nscrew2_test.gd)
const ISO := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
## ISO 7380 button head: [head diameter dk, head height k] in mm (M5 9.5 x 2.75 from the standard's table)
const BUTTON := {3: [5.5, 1.65], 4: [7.0, 2.2], 5: [9.5, 2.75], 6: [12.0, 3.3]}
## ISO 10642 countersunk head: [dk max, k] in mm (M5 dk max 10.0; k = (dk - d) / 2, the 90 deg cone)
const FLAT := {3: [6.3, 1.65], 4: [8.4, 2.2], 5: [10.0, 2.5], 6: [12.0, 3.0]}
const HEADS := ["Socket", "Button", "Flat"]
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


## the size chips sit in the Screws page's scroll view: bring one into view before the click (the head row is above them)
func pick(d: int, L: int) -> void:
	var c := chip(d, L)
	var n: Node = c.get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n != null:
		(n as ScrollContainer).ensure_control_visible(c)
	await idle(3)
	await click_ctl(c)


func head_chip(i: int) -> Button:
	return root.find_child("easypart_head_" + HEADS[i].to_lower(), true, false) as Button


## the built result, read from the mesh (mm) and the body count: ymin / ymax the whole screw, d the shank across (the narrowest
## height), D the widest across, L the lowest height whose radius is past the shank (the length under the head), k = ymax - L
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
	# the shank's radius is the bottom ring's: a button head's dome ends in one point on the axis (radius 0), so the narrowest bin is no shank
	var rs := float(bins[int(roundf(ymin * 10.0))])
	var rmax := 0.0
	for k in bins:
		rmax = maxf(rmax, float(bins[k]))
	var lo := 1e9
	for k in bins:
		if float(bins[k]) > rs + 0.5:
			lo = minf(lo, float(k) / 10.0)
	return {"ymin": ymin, "ymax": ymax, "d": 2.0 * rs, "D": 2.0 * rmax, "L": lo, "k": ymax - lo,
		"bodies": int(pu.res.get("bodies", 0)), "errors": (pu.res.get("errors", {}) as Dictionary).size()}


## "" when the built screw has head h (0 Socket, 1 Button, 2 Flat) of size d and length L, to the tables; else what it measured
func check(h: int, d: int, L: int) -> String:
	var g := geom()
	if g.is_empty():
		return "no geometry"
	var hd: Array = ISO[d] if h == 0 else (BUTTON[d] if h == 1 else FLAT[d])
	var good: bool = absf(float(g["d"]) - d) <= 0.05 and absf(float(g["D"]) - float(hd[0])) <= 0.05
	good = good and int(g["bodies"]) == 1 and int(g["errors"]) == 0 and absf(float(g["ymin"])) <= 0.05
	if h == 2:
		good = good and absf(float(g["ymax"]) - L) <= 0.05
	else:
		good = good and absf(float(g["L"]) - L) <= 0.05 and absf(float(g["k"]) - float(hd[1])) <= 0.05
	if good:
		return ""
	return "head %.2f x %.2f, shank %.2f, under-head %.2f, top %.2f, lowest %.2f, %d solid, %d failed" % [float(g["D"]), float(g["k"]), float(g["d"]), float(g["L"]), float(g["ymax"]), float(g["ymin"]), int(g["bodies"]), int(g["errors"])]


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
	await idle(12)   # the start screen lays its cards out a few frames late when two runs share the GPU: a click too early hit Model
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
	# 1 CHIPS: the Parts chip opens the screws, the three head chips are on screen
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	if pb != null:
		await click_ctl(pb)
	var heads_ok := true
	var heads_off := []
	for i in HEADS.size():
		var hc := head_chip(i)
		if hc == null or not hc.is_visible_in_tree() or hc.text != HEADS[i]:
			heads_ok = false
		elif not vp.encloses(Rect2(hc.global_position, hc.size)):
			heads_off.append(hc.name)
	var sizes_ok := chip(5, 20) != null and chip(5, 20).is_visible_in_tree()
	ok(pb != null and heads_ok and heads_off.is_empty() and sizes_ok, "1 the Parts chip opens the screws with three head chips Socket, Button, Flat on the 1280 x 720 screen %s" % str(heads_off))
	await shot("parts")
	# 2 BUTTON: the Button head picked before the drop, then M5 x 20
	await click_ctl(head_chip(1))
	var ub0: int = m.undo.size()
	await pick(5, 20)
	var e1 := check(1, 5, 20)
	ok(e1 == "" and m.undo.size() == ub0 + 1, "2 M5 x 20 button head: one undo step (%d -> %d), built [%s]" % [ub0, m.undo.size(), e1])
	await shot("button")
	# 3 FLAT: the Flat head picked on the floor: rebuilt, one undo step
	var ub1: int = m.undo.size()
	await click_ctl(head_chip(2))
	var e2 := check(2, 5, 20)
	ok(e2 == "" and m.undo.size() == ub1 + 1, "3 Flat picked on the floor: one undo step (%d -> %d), built [%s]" % [ub1, m.undo.size(), e2])
	await shot("flat")
	# 4 UNDO: one Undo brings the button head back
	m._undo()
	await idle(4)
	var e3 := check(1, 5, 20)
	ok(e3 == "", "4 one Undo brings the button head back [%s]" % e3)
	# 5 SOCKET: the Socket head, the ISO 4762 screw again
	await click_ctl(head_chip(0))
	var e4 := check(0, 5, 20)
	ok(e4 == "", "5 Socket head: M5 x 20 is the ISO 4762 screw again (8.5 x 5.0), one solid [%s]" % e4)
	# 6 ALL: M3..M6 x 20 with each head: one solid, no failed step, to its table
	var bad := []
	var steps_ok := true
	for h in [1, 2]:
		await click_ctl(head_chip(h))
		for d in [3, 4, 5, 6]:
			var u: int = m.undo.size()
			await pick(d, 20)
			var e := check(h, d, 20)
			if e != "":
				bad.append("%s M%d x 20 [%s]" % [HEADS[h], d, e])
			if m.undo.size() != u + 1:
				steps_ok = false
	ok(bad.is_empty() and steps_ok, "6 M3 M4 M5 M6 x 20 with the Button and Flat heads: each one solid, built to its table, one undo step each %s" % str(bad))
	# 7 SAME: the head already on the floor does nothing
	var ub2: int = m.undo.size()
	await click_ctl(head_chip(2))
	ok(m.undo.size() == ub2, "7 the head already on the floor: no undo step (%d -> %d)" % [ub2, m.undo.size()])
	# 8 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for i in HEADS.size():
		texts.append(head_chip(i).text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "8 no key name in the head chips, the hint or the status %s" % str(hit))
	print("p061screwheads: %d fail" % fails)
	quit(1 if fails > 0 else 0)
