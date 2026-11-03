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
##   5 UI        the four chips are inside the window and visible at both sizes; screenshots saved and looked at.
const Part := preload("res://scripts/build/part.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/c03"
var fails := 0
var m: Node


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
	await idle(3)


func chip(nm: String) -> Button:
	return m.bld.part.ep.find_child(nm, true, false) as Button


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
	await shot("newbody_" + tag)
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
	print("c03: %d fail" % fails)
	quit(1 if fails > 0 else 0)
