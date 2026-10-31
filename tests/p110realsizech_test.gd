extends SceneTree
## p110realsizech (Friday plan item 110, ★): a real-size check on Easy Part. The "For scale" button in the panel's foot opens three chips:
## Hand, Coin, Phone. A press lays that thing on the floor beside the part at its real size; a second press takes it away. It is a view
## aid: no record change, no undo step (opening and showing are not actions, like the Parts library).
## A beginner walk with real clicks from the BUILDING card (no keyboard). Measured from the BUILT result: the reference's mesh triangles in
## its world place (mm), the part's kernel faces (mm), the undo steps and the feature count, never from the code's own variables.
## Bars are written before the code. Bars that FAIL on the old code (no For scale button) are marked in the bar text.
##   1 CHIP      the For scale button sits in the panel's foot, on the 1280 x 720 screen, 34 px or taller; its three chips Hand, Coin, Phone show when it opens (FAILS on old code)
##   2 OPENS     opening For scale and then the three chips makes no undo step and adds no feature (opening is not an action)                                    (FAILS on old code)
##   3 COIN      Coin: one reference on the floor, 24.26 mm across (x and z), 1.75 mm thick, lowest point on the floor, 5 to 60 mm clear of the part            (FAILS on old code)
##   4 PHONE     Phone replaces the coin (one reference only): 147 x 71 x 8 mm (+- 1.5), on the floor, 5 to 60 mm clear of the part                              (FAILS on old code)
##   5 HAND      Hand: 170 to 195 mm long, 85 to 125 mm wide, at most 40 mm high, on the floor, 5 to 60 mm clear of the part                                      (FAILS on old code)
##   6 AWAY      Hand pressed again takes it away: no reference on screen, For scale stays open                                                                 (FAILS on old code)
##   7 NOEDIT    the whole walk (every press): the undo steps and the features and the built part's box (mm) are the same as before the walk                     (FAILS on old code)
##   8 SHUT      closing For scale takes a shown reference away too                                                                                            (FAILS on old code)
##   9 WORDS     no key name in the For scale words, the chip words, the hint or the status line
## Shots: C:/Temp/claude/p110realsizech/phone.png (the phone beside the sword), hand.png (the hand)
const SHOT := "C:/Temp/claude/p110realsizech"
const DIRT := "user://p110realsizech_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
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


func scale_btn() -> Button:
	return root.find_child("easypart_scale", true, false) as Button


func scale_chip(k: String) -> Button:
	return root.find_child("easypart_scale_" + k, true, false) as Button


## the reference nodes on screen (visible), by the node name the code gives them
func refs() -> Array:
	var out := []
	for n in root.find_children("EasyScaleRef", "Node3D", true, false):
		if (n as Node3D).is_visible_in_tree():
			out.append(n)
	return out


## the reference's box in mm, from its built mesh triangles in the world; {} when none is on screen
func ref_box() -> Dictionary:
	var rs := refs()
	if rs.size() != 1:
		return {}
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var tris := 0
	for mi in (rs[0] as Node).find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		for v in mm.mesh.get_faces():
			var p := (mm.global_transform * v) * 1000.0
			lo = lo.min(p)
			hi = hi.max(p)
			tris += 1
	if tris == 0:
		return {}
	return {"lo": lo, "hi": hi, "sz": hi - lo}


## the built part's box (mm) from the kernel faces the Easy view draws
func part_box() -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for f in Part.body_faces(m.S.part):
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x > hi.x:
		return {}
	return {"lo": lo, "hi": hi, "sz": hi - lo}


## the clear gap (mm) between two boxes: the largest separation along one axis (0 when they overlap on all three)
func gap_mm(a: Dictionary, b: Dictionary) -> float:
	var g := -1e9
	for ax in 3:
		g = maxf(g, float(a["lo"][ax]) - float(b["hi"][ax]))
		g = maxf(g, float(b["lo"][ax]) - float(a["hi"][ax]))
	return maxf(g, 0.0)


func features() -> int:
	return (m.S.part.get("features", []) as Array).size()


## sorted sides (mm), so the test does not care which way the thing lies
func sides(sz: Vector3) -> Array:
	var a := [sz.x, sz.y, sz.z]
	a.sort()
	return a


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
		print("FAIL: no KineCAD DLL, the real-size check cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var ub0: int = m.undo.size()
	var f0 := features()
	var pb0 := part_box()

	# 1 CHIP: the For scale button in the foot, the three chips after it opens
	var sb := scale_btn()
	var off := []
	var small := []
	var opened := await click_ctl(sb)
	var chip_names := []
	for k in ["hand", "coin", "phone"]:
		var c := scale_chip(k)
		if c == null or not c.is_visible_in_tree():
			chip_names.append("missing " + k)
			continue
		if not vp.encloses(Rect2(c.global_position, c.size)):
			off.append(k)
		if c.size.y < 34.0:
			small.append("%s %.0f px" % [k, c.size.y])
	var words := [scale_chip("hand"), scale_chip("coin"), scale_chip("phone")]
	var txt := []
	for c in words:
		if c != null:
			txt.append(c.text)
	ok(sb != null and opened and sb.text == "For scale" and vp.encloses(Rect2(sb.global_position, sb.size)) and chip_names.is_empty() and txt == ["Hand", "Coin", "Phone"] and off.is_empty() and small.is_empty(), "1 the For scale button is on the 1280 x 720 screen; Hand, Coin, Phone show on it, on screen and 34 px or taller (off %s, short %s, missing %s, words %s)" % [str(off), str(small), str(chip_names), str(txt)])
	await shot("chips")

	# 2 OPENS: opening the box costs no undo step and no feature
	ok(m.undo.size() == ub0 and features() == f0, "2 opening For scale: no undo step (%d -> %d), no feature added (%d -> %d)" % [ub0, m.undo.size(), f0, features()])

	# 3 COIN: a coin on the floor beside the part at real size
	await click_ctl(scale_chip("coin"))
	var cb := ref_box()
	var pb := part_box()
	var cs := sides(cb["sz"]) if not cb.is_empty() else []
	var cgap := gap_mm(cb, pb) if not cb.is_empty() and not pb.is_empty() else -1.0
	var coin_ok: bool = cs.size() == 3 and absf(float(cs[1]) - 24.26) <= 0.5 and absf(float(cs[0]) - 1.75) <= 0.3 and absf(float(cs[2]) - 24.26) <= 0.5
	ok(coin_ok and not cb.is_empty() and absf(float(cb["lo"].y)) <= 0.5 and cgap >= 5.0 and cgap <= 60.0, "3 coin: one reference on screen, sides %s mm (24.26 across, 1.75 thick), lowest %.2f mm, %.1f mm clear of the part" % [str(cs), float(cb["lo"].y) if not cb.is_empty() else -1.0, cgap])

	# 4 PHONE: the phone replaces the coin
	await click_ctl(scale_chip("phone"))
	var hb := ref_box()
	var ps := sides(hb["sz"]) if not hb.is_empty() else []
	var pgap := gap_mm(hb, pb) if not hb.is_empty() and not pb.is_empty() else -1.0
	var phone_ok: bool = ps.size() == 3 and absf(float(ps[0]) - 8.0) <= 1.5 and absf(float(ps[1]) - 71.0) <= 1.5 and absf(float(ps[2]) - 147.0) <= 1.5
	ok(phone_ok and not hb.is_empty() and absf(float(hb["lo"].y)) <= 0.5 and pgap >= 5.0 and pgap <= 60.0, "4 phone: one reference on screen (the coin is gone), sides %s mm (8 x 71 x 147), lowest %.2f mm, %.1f mm clear of the part" % [str(ps), float(hb["lo"].y) if not hb.is_empty() else -1.0, pgap])
	await shot("phone")

	# 5 HAND: a hand lying on the floor, about 18 cm long
	await click_ctl(scale_chip("hand"))
	var nb := ref_box()
	var ns := sides(nb["sz"]) if not nb.is_empty() else []
	var ngap := gap_mm(nb, pb) if not nb.is_empty() and not pb.is_empty() else -1.0
	var hand_ok: bool = ns.size() == 3 and float(ns[2]) >= 170.0 and float(ns[2]) <= 195.0 and float(ns[1]) >= 85.0 and float(ns[1]) <= 125.0 and float(ns[0]) <= 40.0
	ok(hand_ok and not nb.is_empty() and absf(float(nb["lo"].y)) <= 0.5 and ngap >= 5.0 and ngap <= 60.0, "5 hand: one reference on screen, sides %s mm (170-195 long, 85-125 wide, 40 high at most), lowest %.2f mm, %.1f mm clear of the part" % [str(ns), float(nb["lo"].y) if not nb.is_empty() else -1.0, ngap])
	await shot("hand")

	# 6 AWAY: the same chip again takes it away; For scale stays open
	await click_ctl(scale_chip("hand"))
	ok(refs().is_empty() and scale_chip("hand").button_pressed == false and sb.button_pressed and scale_box_open(), "6 Hand pressed again: no reference on screen, For scale still open")

	# 8 SHUT: a shown reference goes when For scale shuts
	await click_ctl(scale_chip("coin"))
	var shown_before := refs().size()
	await click_ctl(sb)
	ok(shown_before == 1 and refs().is_empty() and not scale_box_open(), "8 closing For scale takes the shown coin away (%d shown before, %d after)" % [shown_before, refs().size()])

	# 7 NOEDIT: the whole walk changed no record, no undo step, and the built part's box is the same
	var pb1 := part_box()
	var same_box := not pb0.is_empty() and not pb1.is_empty() and (pb0["sz"] as Vector3).is_equal_approx(pb1["sz"] as Vector3) and (pb0["lo"] as Vector3).is_equal_approx(pb1["lo"] as Vector3)
	ok(m.undo.size() == ub0 and features() == f0 and same_box, "7 the whole walk: undo steps %d -> %d, features %d -> %d, the built part's box %s -> %s mm" % [ub0, m.undo.size(), f0, features(), str(pb0.get("sz", "none")), str(pb1.get("sz", "none"))])

	# 9 WORDS: no key name in the new words
	var bad := []
	var texts := [sb.text, sb.tooltip_text, ep.hint_l.text, ep.status_l.text]
	for c in ["hand", "coin", "phone"]:
		texts.append(scale_chip(c).text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				bad.append("%s in [%s]" % [w, t])
	ok(bad.is_empty(), "9 no key name in the For scale words, the chips, the hint or the status line %s" % str(bad))

	print("p110realsizech: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)


func scale_box_open() -> bool:
	var sbx := root.find_child("easypart_scale_box", true, false) as Control
	return sbx != null and sbx.is_visible_in_tree()
