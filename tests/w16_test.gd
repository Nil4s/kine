extends SceneTree
## godot --headless --path . -s tests/w16_test.gd     (W16 TEST PRINT: TOLERANCE / FIT STRIP; needs the CAD DLL)
## Bars (written before the first run):
##   1 CELLS   default strip: 5 pegs + 5 holes, clearances 0.1 .. 0.5 step 0.1 (0.1 Snug, 0.2 Slides, 0.4 Loose from the app's presets), each labelled with its value;
##             hole diameter - peg diameter = 2 x clearance (1e-9)
##   2 VOLUME  the kernel's volume of the peg body and of the hole body within 1 % of the closed form (plate + pegs - text, plate - holes - text)
##   3 STL     the exported STL/3MF is two bodies, each manifold (open 0, bad 0), signed volume of each within 1 % of the closed form, file on disk
##   4 TEXT    the engraving is real: body volume is smaller than the same strip's plate + pegs by at least half the text volume
##   5 RANGE   a changed range (0.05 .. 0.25 step 0.05) gives 5 cells and its own closed form within 1 %
##   6 CONTROL a planted wrong closed form (clearance 0.1 mm too small on the holes) fails the 1 % bar; an empty range is refused
const KCad := preload("res://scripts/kcad.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/w16"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-9)


func bodies_vol(b: Dictionary) -> Array:
	var r := Part.replay(b["rec"], -1, {"keep": true})
	var out := []
	for id in r.get("ids", []):
		out.append(KCad.volume(int(id)) * 1e9)
	for id in r.get("ids", []):
		KCad.release(int(id))
	return [out, r]


func api_tests() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	ok(Part.available(), "CAD kernel present")
	var s := FitStrip.build()
	ok(bool(s["ok"]), "default strip builds: " + String(s["why"]))
	var cells: Array = s["cells"]
	var want := [0.1, 0.2, 0.3, 0.4, 0.5]
	var good := cells.size() == 5
	for i in cells.size():
		good = good and absf(float(cells[i]["c"]) - float(want[i])) < 1e-9 and absf(float(cells[i]["hole_d"]) - float(cells[i]["peg_d"]) - 2.0 * float(want[i])) < 1e-9 and String(cells[i]["label"]) == "%.1f" % float(want[i])
	ok(good, "1 five cells 0.1..0.5, hole_d - peg_d = 2c, labelled")
	ok(cells[0]["preset"] == "Snug" and cells[1]["preset"] == "Slides" and cells[3]["preset"] == "Loose" and cells[2]["preset"] == "", "1b presets from the app: 0.1 %s, 0.2 %s, 0.3 '%s', 0.4 %s" % [cells[0]["preset"], cells[1]["preset"], cells[2]["preset"], cells[3]["preset"]])
	var bv := bodies_vol(s)
	var vs: Array = bv[0]
	ok(vs.size() == 2 and (bv[1]["errors"] as Dictionary).is_empty(), "replay: 2 bodies, no errors %s" % str(bv[1]["errors"]))
	var ep: float = s["exp_peg_mm3"]
	var eh: float = s["exp_hole_mm3"]
	print("     kernel peg %.2f vs %.2f (%.4f %%), hole %.2f vs %.2f (%.4f %%)" % [vs[0], ep, 100.0 * rel(vs[0], ep), vs[1], eh, 100.0 * rel(vs[1], eh)])
	ok(rel(vs[0], ep) <= 0.01 and rel(vs[1], eh) <= 0.01, "2 kernel volumes within 1 % of closed form")
	var plain: float = s["length"] * FitStrip.PLATE_W * FitStrip.PLATE_T + 5.0 * PI * 16.0 * FitStrip.PEG_H
	var tv: float = s["text_area_peg"] * FitStrip.ENGRAVE
	ok(plain - vs[0] >= 0.5 * tv and tv > 5.0, "4 engraving removes material: plate+pegs %.2f - body %.2f = %.2f mm3 (text %.2f)" % [plain, vs[0], plain - vs[0], tv])
	# export
	for fmt in ["stl", "3mf"]:
		var ex := MeshExport.export_part(s["rec"], fmt, OUT)
		ok(bool(ex["ok"]) and FileAccess.file_exists(String(ex["path"])), "3 %s written: %s" % [fmt, str(ex["text"])])
	var bo := MeshExport.bodies_of(s["rec"])
	var bodies: Array = bo["bodies"]
	ok(bodies.size() == 2, "3 two bodies in the file")
	var sv := []
	for b in bodies:
		var ch := MeshExport.check(b)
		sv.append(MeshExport.signed_volume(b))
		ok(bool(ch["closed"]), "3 body manifold: open %d bad %d tris %d" % [ch["open"], ch["bad"], ch["tris"]])
	print("     mesh peg %.2f (%.4f %%), hole %.2f (%.4f %%)" % [sv[0], 100.0 * rel(sv[0], ep), sv[1], 100.0 * rel(sv[1], eh)])
	ok(rel(sv[0], ep) <= 0.01 and rel(sv[1], eh) <= 0.01, "3 STL mesh volumes within 1 % of closed form")
	# range
	var r := FitStrip.build(0.05, 0.25, 0.05)
	var rv := bodies_vol(r)
	ok((r["cells"] as Array).size() == 5 and rv[0].size() == 2 and rel(rv[0][0], r["exp_peg_mm3"]) <= 0.01 and rel(rv[0][1], r["exp_hole_mm3"]) <= 0.01, "5 range 0.05..0.25: %d cells, volumes %s vs [%.2f, %.2f]" % [(r["cells"] as Array).size(), str(rv[0]), r["exp_peg_mm3"], r["exp_hole_mm3"]])
	# control
	# the body volume is dominated by the plate, so the holes themselves are held to the bar too: volume removed by the holes = plate - body - text
	var plate: float = s["length"] * FitStrip.PLATE_W * FitStrip.PLATE_T
	var removed: float = plate - sv[1] - s["text_area_hole"] * FitStrip.ENGRAVE
	var cf := 0.0
	var planted := 0.0
	for c in s["cells"]:
		cf += PI * pow(4.0 + float(c["c"]), 2) * FitStrip.PLATE_T
		planted += PI * pow(4.0 + float(c["c"]) - 0.1, 2) * FitStrip.PLATE_T
	ok(rel(removed, cf) <= 0.01, "2b hole volume from the STL %.2f vs closed form %.2f (%.4f %%)" % [removed, cf, 100.0 * rel(removed, cf)])
	ok(rel(removed, planted) > 0.01, "6 control: closed form with every clearance 0.1 short is %.2f %% off the same mesh, fails the 1 %% bar" % (100.0 * rel(removed, planted)))
	ok(not bool(FitStrip.build(0.5, 0.1, 0.1)["ok"]) and not bool(FitStrip.build(0.1, 0.5, 0.0)["ok"]), "6 empty range / zero step refused")


var m: Node


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var sc: Node = c
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(3)
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func pu() -> PartUI:
	return m.bld.part


func shot(nm: String) -> void:
	await idle(4)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func open_group_of(c: Control) -> void:
	if c == null or c.is_visible_in_tree():
		return
	for g in root.find_children("easypart_libgroup_*", "Button", true, false):
		var fl := root.find_child("easypart_libchips_" + (g as Button).text, true, false)
		if fl != null and fl.is_ancestor_of(c):
			await click_ctl(g)
			return


func look_down() -> void:
	var bb: AABB = pu().res.get("aabb", AABB())
	m.pitch = -78.0
	m.dist = clampf(bb.size.x * 1.1, 0.05, 1.0)
	m.target = bb.get_center()
	m._cam()
	await idle(6)


func ui_tests() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://w16_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.S.part = {}
	pu().set_on(false)
	await idle(4)
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(30)
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		root.min_size = Vector2i(640, 360)
		DisplayServer.window_set_size(sz)
		root.size = sz
		root.content_scale_size = sz
		await idle(6)
		m.S.part = {}
		pu().upto = -1
		pu().sync()
		await idle(4)
		var tag := "%dx%d" % [sz.x, sz.y]
		var tb := root.find_child("easypart_lib_Type it", true, false) as Button
		if not (pu().ep != null and pu().ep.parts_open):
			await click_ctl(root.find_child("easypart_chip_parts", true, false) as Button)
			await idle(4)
		await open_group_of(tb)
		await click_ctl(tb)
		await idle(8)
		var go: Button = root.find_child("easypart_fitstrip_go", true, false) as Button
		ok(go != null and go.is_visible_in_tree(), "7a %s the Test print: fit strip button shows on Type it" % tag)
		if sz.x != 1024:
			for k in ["from", "to", "step"]:
				(root.find_child("easypart_fitstrip_" + k, true, false) as LineEdit).text = {"from": "0.1", "to": "0.5", "step": "0.1"}[k]
		ok((root.find_child("easypart_fitstrip_from", true, false) as LineEdit).text == "0.1" and (root.find_child("easypart_fitstrip_to", true, false) as LineEdit).text == "0.5" and (root.find_child("easypart_fitstrip_step", true, false) as LineEdit).text == "0.1", "7b %s defaults 0.1 / 0.5 / 0.1" % tag)
		var u0: int = m.undo.size()
		await click_ctl(go)
		await idle(25)
		var d := FitStrip.build()
		var vv := bodies_vol({"rec": m.S.part})
		ok(int(pu().res.get("bodies", 0)) == 2 and m.undo.size() == u0 + 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(), "7c %s a real click builds 2 bodies in ONE undo step (undo %d -> %d)" % [tag, u0, m.undo.size()])
		ok(vv[0].size() == 2 and rel(vv[0][0], d["exp_peg_mm3"]) <= 0.01 and rel(vv[0][1], d["exp_hole_mm3"]) <= 0.01, "7d %s volumes from the part on screen %s vs [%.2f, %.2f]" % [tag, str(vv[0]), d["exp_peg_mm3"], d["exp_hole_mm3"]])
		await look_down()
		await shot("strip_" + tag)
		# the strip itself, no panels over it: what a printed strip would read like
		var hid := []
		for ch in m.get_children():
			if ch is CanvasLayer and (ch as CanvasLayer).visible:
				(ch as CanvasLayer).visible = false
				hid.append(ch)
		await idle(6)
		var img := root.get_texture().get_image()
		img.save_png("%s/strip_clean_%s.png" % [OUT, tag])
		print("     clean shot %s: window %s, image %s" % [tag, str(root.size), str(img.get_size())])
		for ch in hid:
			(ch as CanvasLayer).visible = true
		if sz.x == 1024:
			# a typed range lands BESIDE what is already there, through the search box row (same button)
			(root.find_child("easypart_fitstrip_from", true, false) as LineEdit).text = "0.05"
			(root.find_child("easypart_fitstrip_to", true, false) as LineEdit).text = "0.25"
			(root.find_child("easypart_fitstrip_step", true, false) as LineEdit).text = "0.05"
			EasySearch.go(m, ["parts:", "lib:Type it", "fitstrip:go"])
			await idle(30)
			var b2 := bodies_vol({"rec": m.S.part})
			var r2 := FitStrip.build(0.05, 0.25, 0.05)
			ok(int(pu().res.get("bodies", 0)) == 4 and b2[0].size() == 4 and rel(b2[0][2], r2["exp_peg_mm3"]) <= 0.01 and rel(b2[0][3], r2["exp_hole_mm3"]) <= 0.01 and rel(b2[0][0], d["exp_peg_mm3"]) <= 0.01, "7e search-box row adds a 0.05..0.25 strip beside the first: bodies %d, volumes %s" % [pu().res.get("bodies", 0), str(b2[0])])
			await look_down()
			await shot("strip_two_" + tag)


func _init() -> void:
	api_tests()
	await ui_tests()
	print("W16 %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
