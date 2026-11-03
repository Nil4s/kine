extends SceneTree
## godot --path . -s tests/c03_test.gd   (C03: complaints #235 Join / New body, #508 mirror across any plane, #323 printer tolerance presets)
## BARS, written before any number was seen (real clicks on the Easy chips, 1280 x 720 and 1920 x 1080):
##   1 JOIN/NEW  a face-touching pull is 1 body by default (control: unchanged default); with "Pull makes: New body" it is 2 bodies and the step's op is "new";
##               pressing the chip again with that pull newest flips it back to 1 body, op "join". Chip text reads Join / New body.
##   2 ANGLE     box x 20..40 (z +-5): "Mirror at an angle" (45 deg about the upright axis) doubles the volume (+-1 pct) and puts the copy at z 25..35
##               (aabb end z >= 0.034 m). Control: the plain right-plane mirror ends at z 0.005 and starts at x -0.04. The plane's deg set to 0 gives x start <= -0.039.
##   3 FACE      a plane step with "out" at 60 mm from the right plane: "Mirror in the face" puts the copy at x 80..100 (aabb end x >= 0.099); control: before it, end x = 0.04.
##   4 PRINTER   presses cycle Resin 0.1, Bambu PLA 0.15, Prusa PETG 0.2, Ender FDM 0.3, then Resin again; rec fit_mm follows (the value holes, lids and
##               fasteners read); each press is ONE undo step. Control: after two presses fit_mm is 0.15, not 0.3.
##   6 CLEAR     (added after the lead saw angle_1280.png) the chip panel's rect intersects NO other visible button, label, slider or panel at 1280 x 720 and
##               1920 x 1080, in the pull, angle and printer states. Control: the first placement (centred, 110 px above the bottom) intersects something
##               at one size at least, so the bar can fail.
##   7 PIECES    (added after batch 8: s214 Z3 clicked a piece the panel covered) in the s214 Repeat-it state (three cubes, Repeat it, Group, camera framed
##               as s214 frames it) the panel does not contain the screen point of any body's centre and does not touch the projected box of the pieces, at both
##               sizes; if no clear place is left the panel hides (that also passes). Control: the placement WITHOUT the piece avoidance (the old rule) puts the
##               panel over a body centre or the piece box at one size at least.
##   5 UI        the four chips are inside the window and visible at both sizes; screenshots saved and looked at.
const Part := preload("res://scripts/build/part.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/c03"
var fails := 0
var m: Node
var ctl_hits := 0
var ctl_cover := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


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


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func rect_sk(id: String, a: Array, b: Array) -> Dictionary:
	return {"t": "sketch", "id": id, "name": "S" + id, "plane": "front", "ents": [{"k": "rect", "a": a, "b": b}], "dims": []}


func ext(id: String, sk: String, op: String) -> Dictionary:
	return {"t": "extrude", "id": id, "name": "E" + id, "sketch": sk, "dist": 10.0, "both": true, "op": op}


func box_at(x0: float, x1: float) -> Array:
	return [rect_sk("f1", [x0, -10.0], [x1, 10.0]), ext("f2", "f1", "new")]


func shot(nm: String) -> void:
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func newest(kind: String) -> Dictionary:
	var fs: Array = m.S.part["features"]
	for i in range(fs.size() - 1, -1, -1):
		if String(fs[i]["t"]) == kind:
			return fs[i]
	return {}


func set_part(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = 20
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(16)   # the panel looks for a clear place every 12 frames: let it settle before a real click


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


func hits(box: Control) -> Array:
	var out: Array = []
	var win := Vector2(root.get_visible_rect().size)
	var stack: Array = [root]
	var mine := box.get_global_rect()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c == box:
				continue
			stack.append(c)
			if not (c is Control) or not (c as Control).is_visible_in_tree() or c.is_ancestor_of(box):
				continue
			if not (c is BaseButton or c is Label or c is Range or c is PanelContainer or c is LineEdit or c is RichTextLabel):
				continue
			if c is Label and (c as Label).text == "":
				continue
			var r := (c as Control).get_global_rect()
			if r.size.x < 2.0 or r.size.y < 2.0 or r.get_area() > 0.4 * win.x * win.y:
				continue
			if mine.intersects(r):
				out.append("%s %s" % [c.name, str(r)])
	return out


func three_cubes() -> Array:
	var out: Array = []
	var k := 1
	for x in [-60.0, 0.0, 60.0]:
		out.append(rect_sk("f%d" % k, [x - 10.0, -10.0], [x + 10.0, 10.0]))
		out.append(ext("f%d" % (k + 1), "f%d" % k, "new"))
		k += 2
	return out


func piece_bars(sz: Vector2i) -> void:
	var tag := str(sz.x)
	var pu: PartUI = m.bld.part
	var ep = pu.ep
	await set_part(three_cubes(), "Pieces")
	m.target = Vector3(0.1, 0.0, 0.0)   # s214's frame_right: the pieces small, on the right of the screen
	m.dist = 1.6
	m.pitch = 0.0
	m.yaw = 0.0
	m._cam()
	await idle(10)
	await click_ctl(ep.make_btns["repeat"])
	await click_ctl(ep.rep_btns["group"])
	await idle(40)
	var box := chip("easypart_mirror_angle").get_parent().get_parent() as Control
	var cs: Array = []
	for x in [-60.0, 0.0, 60.0]:
		cs.append(m.cam.unproject_position(Vector3(x * 0.001, 0.0, 0.0)))
	var ab: AABB = pu.res.get("aabb", AABB())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var q: Vector2 = m.cam.unproject_position(ab.position + ab.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
		lo = lo.min(q)
		hi = hi.max(q)
	var pbox := Rect2(lo, hi - lo)
	var bad := func() -> Array:
		var o: Array = []
		if not box.visible:
			return o
		var r := box.get_global_rect()
		for c in cs:
			if r.has_point(c):
				o.append("centre " + str(c))
		if r.intersects(pbox):
			o.append("piece box " + str(pbox))
		return o
	var c03 = load("res://scripts/easy_part_c03.gd")
	box.visible = true
	# the panel was put down earlier, over where the pieces now stand (the batch-8 failure: it sat there, still clear of every control)
	box.position = (cs[1] as Vector2) - box.size * 0.5
	box.set_meta("c03_placed", true)
	box.set_meta("c03_vs", (box.get_parent() as Control).size)
	# control: the panel where it was put down, no re-placement (the old rule never looked at pieces): the detector must fire
	var b0: Array = bad.call()
	print("  [%s 7 control: the old rule leaves the panel over the pieces: %d: %s]" % [tag, b0.size(), str(b0)])
	ctl_cover += b0.size()
	c03.place(box, ep)   # the new rule: it must move off the pieces (or hide)
	var b1: Array = bad.call()
	ok(b1.is_empty(), "%s 7: panel %s (visible %s) covers no body centre and not the piece box %s" % [tag, str(box.get_global_rect()), str(box.visible), str(b1)])
	await shot("pieces_" + tag)


func bars(sz: Vector2i) -> void:
	var tag := str(sz.x)
	var pu: PartUI = m.bld.part
	var ep = pu.ep
	root.content_scale_size = sz
	await idle(4)
	# 1 JOIN / NEW
	var feats := box_at(-40.0, 0.0)
	feats.append(rect_sk("f3", [-40.0, 10.0], [0.0, 30.0]))
	await set_part(feats.duplicate(true), "Join")
	var nb := chip("easypart_pull_newbody")
	ok(nb != null and nb.text == "Pull makes: Join", "%s 1: default reads Join [%s]" % [tag, nb.text if nb else "-"])
	await click_ctl(ep.make_btns["pull"])
	ok(int(pu.res.get("bodies", 0)) == 1, "%s 1 control: default pull joins: 1 body (%d)" % [tag, int(pu.res.get("bodies", 0))])
	await set_part(feats.duplicate(true), "New")
	await click_ctl(nb)
	ok(nb.text == "Pull makes: New body", "%s 1: chip reads New body [%s]" % [tag, nb.text])
	await click_ctl(ep.make_btns["pull"])
	ok(int(pu.res.get("bodies", 0)) == 2 and String(newest("extrude").get("op", "")) == "new", "%s 1: New body pull = 2 bodies, op new (%d, %s)" % [tag, int(pu.res.get("bodies", 0)), newest("extrude").get("op", "")])
	await idle(16)   # the panel may step off the new piece: let it settle before the next real click
	await shot("newbody_" + tag)
	var h3 := hits(chip("easypart_pull_newbody").get_parent().get_parent() as Control)
	ok(h3.is_empty(), "%s 6: pull state: the panel overlaps nothing %s" % [tag, str(h3)])
	await click_ctl(nb)
	ok(int(pu.res.get("bodies", 0)) == 1 and String(newest("extrude").get("op", "")) == "join" and nb.text == "Pull makes: Join", "%s 1: chip again flips the newest pull back to join (%d bodies)" % [tag, int(pu.res.get("bodies", 0))])
	# 2 ANGLE
	await set_part(box_at(20.0, 40.0), "Angle")
	var v0: float = float(Part.replay(m.S.part).get("volume", 0.0))
	var rr: Dictionary = m.S.part.duplicate(true)
	rr["features"].append(Part.new_feature(rr, "mirror", {"plane": "right", "op": "join"}))
	var ar: AABB = Part.replay(rr).get("aabb", AABB())
	ok(ar.end.z < 0.0055 and ar.position.x < -0.039, "%s 2 control: the plain right mirror stays at z <= 5 mm, x from -40 (end z %.4f, x %.4f)" % [tag, ar.end.z, ar.position.x])
	await click_ctl(chip("easypart_mirror_angle"))
	var ra: Dictionary = Part.replay(m.S.part)
	var va: float = float(ra.get("volume", 0.0))
	var aa: AABB = ra.get("aabb", AABB())
	ok(v0 > 0.0 and absf(va / v0 - 2.0) < 0.02, "%s 2: volume doubled (%.3f)" % [tag, va / v0 if v0 > 0.0 else -1.0])
	ok(aa.end.z >= 0.034, "%s 2: the copy stands at z 25..35 (end z %.4f)" % [tag, aa.end.z])
	await shot("angle_" + tag)
	var cb := chip("easypart_mirror_angle").get_parent().get_parent() as Control
	var h1 := hits(cb)
	ok(cb.visible and h1.is_empty(), "%s 6: angle state: the panel overlaps nothing %s" % [tag, str(h1)])
	var keep := cb.position
	var par := cb.get_parent() as Control
	cb.position = Vector2(par.size.x * 0.5 - cb.size.x * 0.5 - 90.0, par.size.y - cb.size.y - 110.0)
	var h0 := hits(cb)
	print("  [%s 6 control: first placement overlaps %d: %s]" % [tag, h0.size(), str(h0)])
	ctl_hits += h0.size()
	cb.position = keep
	newest("plane")["deg"] = 0.0
	var a0: AABB = Part.replay(m.S.part).get("aabb", AABB())
	ok(a0.position.x <= -0.039, "%s 2: angle 0 is the usual mirror (x start %.4f)" % [tag, a0.position.x])
	# 3 FACE
	var f3 := box_at(20.0, 40.0)
	f3.append({"t": "plane", "id": "f3", "name": "Plane1", "from": "right", "mm": 60.0, "out": 1})
	await set_part(f3, "Face")
	var b0: AABB = Part.replay(m.S.part).get("aabb", AABB())
	ok(b0.end.x < 0.0405, "%s 3 control: before the chip the part ends at x 40 (%.4f)" % [tag, b0.end.x])
	await click_ctl(chip("easypart_mirror_face"))
	var b1: AABB = Part.replay(m.S.part).get("aabb", AABB())
	ok(b1.end.x >= 0.099, "%s 3: the copy is across the face plane, to x 100 (%.4f)" % [tag, b1.end.x])
	# 4 PRINTER
	await set_part(box_at(20.0, 40.0), "Printer")
	var pb := chip("easypart_printer_preset")
	var want := [0.1, 0.15, 0.2, 0.3, 0.1]
	var names := ["Resin", "Bambu PLA", "Prusa PETG", "Ender FDM", "Resin"]
	for i in 5:
		var ub: int = m.undo.size()
		await click_ctl(pb)
		var r: Dictionary = m.S.part
		ok(absf(float(r.get("fit_mm", -1.0)) - float(want[i])) < 0.001 and String(r.get("printer_preset", "")) == names[i] and m.undo.size() == ub + 1, "%s 4: press %d -> %s %.2f mm, one undo step [%s]" % [tag, i + 1, names[i], want[i], pb.text])
		if i == 1:
			ok(absf(float(r["fit_mm"]) - 0.3) > 0.01, "%s 4 control: after two presses the fit is not Ender's 0.3" % tag)
			ok(absf(float(ep._fit_of(r)) - 0.15) < 0.001, "%s 4: the fit holes and lids read is 0.15" % tag)
	await shot("printer_" + tag)
	var h2 := hits(cb)
	ok(cb.visible and h2.is_empty(), "%s 6: printer state: the panel overlaps nothing %s" % [tag, str(h2)])
	# 5 UI
	for nm in ["easypart_pull_newbody", "easypart_mirror_angle", "easypart_mirror_face", "easypart_printer_preset"]:
		var c := chip(nm)
		var rc := c.get_global_rect()
		ok(c.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(sz)).encloses(rc), "%s 5: %s is on screen %s" % [tag, nm, str(rc)])


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: no window")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c03_test"))
	ss.dirs_override = ["user://c03_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	for sz in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await bars(sz)
		await piece_bars(sz)
	ok(ctl_cover > 0, "7 control: the old placement covered a piece (%d covers over both sizes)" % ctl_cover)
	ok(ctl_hits > 0, "6 control: the first placement intersected something (%d overlaps over both sizes)" % ctl_hits)
	print("c03: %d fail" % fails)
	quit(1 if fails > 0 else 0)
