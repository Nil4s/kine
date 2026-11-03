extends SceneTree
## godot --path . -s tests/c43_test.gd     (C43: printer row in Export + the written file re-read as the preview; needs the CAD DLL)
## Bars (written before the first run). Part: a 20 x 10 x 5 mm box (volume 1000 mm3).
##   1 DEFAULT  no saved printer: opening the dialog leaves the part with no fit_mm / printer_preset; the Printer row is visible on 3D printing, shows item 0 (Any)
##   2 PICK     choosing Resin (real item_selected) gives fit_mm 0.1 and C20Fit.hinge_gap 0.1; Ender FDM gives 0.3 and 0.3; Resin gap < Ender gap
##   3 SAVED    the choice is in user://c43_printer.cfg as read by a fresh ConfigFile; Any clears it and takes the part's fit off
##   4 ADOPT    with Prusa PETG saved, a fresh part with no fit opened in the dialog gets fit_mm 0.2; a part with its own fit_mm 0.45 keeps 0.45
##   5 REREAD   export 3MF and STL: the re-read has the part's triangle count, size within 0.5 pct of 20 x 10 x 5 mm, volume within 0.5 pct of 1000 mm3, text says "matches the part";
##              the preview box is visible and holds a MeshInstance3D whose triangles equal the file's
##   6 CONTROL  compare() on a file with a triangle dropped (planted) answers match false and "does NOT match"; on bodies scaled 1.02 also false
##   7 SHOT     1280x720 screenshots of the dialog with the row and the preview, saved to out/c43 and looked at
const DIR := "user://zz_c43"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c43"
var fails := 0
var m: Node
var pu: PartUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func pick(ui: ExportDialog, i: int) -> void:
	var o: OptionButton = ui.ui_c43["opt"]
	o.select(i)
	o.item_selected.emit(i)
	await idle(2)


func saved_raw() -> String:
	var c := ConfigFile.new()
	if c.load("user://c43_printer.cfg") != OK:
		return ""
	return String(c.get_value("printer", "name", ""))


func box_rec() -> Dictionary:
	var rec := Part.make("C43 box")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))])
	PartTemplates._ex(fs, sid, "extrude", 5.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func _init() -> void:
	var wd = create_timer(300.0)   # watchdog
	wd.timeout.connect(func():
		print("FAIL watchdog: c43 timed out")
		quit(1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://c43_printer.cfg"))
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "_scenes"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(SHOT)
	ss.dirs_override = [DIR + "_scenes"]
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
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	m.S.part = box_rec()
	pu._rec_sig = ""
	await idle(8)
	var eb := root.find_child("easypart_export", true, false) as Button
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var gd := ProjectSettings.globalize_path(DIR)
	# 1 DEFAULT
	var rowv: bool = ui.ui_c43["row"].is_visible_in_tree()
	ok(rowv and (ui.ui_c43["opt"] as OptionButton).selected == 0 and not m.S.part.has("fit_mm") and not m.S.part.has("printer_preset"), "1 default: row visible (%s), Any selected, part has no fit_mm / printer_preset" % rowv)
	root.get_viewport().get_texture().get_image().save_png(SHOT + "/dialog_row.png")
	# 2 PICK
	await pick(ui, 1)
	var g1 := C20Fit.hinge_gap(m.S.part)
	var f1 := float(m.S.part.get("fit_mm", -1))
	await pick(ui, 4)
	var g4 := C20Fit.hinge_gap(m.S.part)
	var f4 := float(m.S.part.get("fit_mm", -1))
	ok(is_equal_approx(f1, 0.1) and is_equal_approx(g1, 0.1) and is_equal_approx(f4, 0.3) and is_equal_approx(g4, 0.3) and g1 < g4, "2 Resin fit %.2f hinge %.2f ; Ender fit %.2f hinge %.2f" % [f1, g1, f4, g4])
	# 3 SAVED
	var s_ender := saved_raw()
	await pick(ui, 0)
	ok(s_ender == "Ender FDM" and saved_raw() == "" and not m.S.part.has("fit_mm"), "3 saved '%s', after Any '%s', fit_mm gone %s" % [s_ender, saved_raw(), not m.S.part.has("fit_mm")])
	# 4 ADOPT
	await pick(ui, 3)
	m.S.part = box_rec()
	ui.dlg.hide()
	ui.open()
	await idle(3)
	var adopted := float(m.S.part.get("fit_mm", -1))
	var own := box_rec()
	own["fit_mm"] = 0.45
	m.S.part = own
	ui.open()
	await idle(3)
	ok(is_equal_approx(adopted, 0.2) and is_equal_approx(float(m.S.part["fit_mm"]), 0.45), "4 adopt: fresh part took %.2f, own fit kept %.2f" % [adopted, float(m.S.part["fit_mm"])])
	m.S.part = box_rec()
	await pick(ui, 0)
	# 5 REREAD
	for fi in [0, 1]:
		var ext := "3mf" if fi == 0 else "stl"
		ui.ui_format.select(fi)
		ui.ui_format.item_selected.emit(fi)
		await idle(3)
		var path := gd + "/C43_box." + ext
		DirAccess.remove_absolute(path)
		ui.export_now("print", fi, DIR)
		await idle(4)
		var rr: Dictionary = ui.last_reread
		var got := C43Printer.reread(path, ext)
		var sz: Vector3 = got.get("size", Vector3.ZERO)
		var szok := absf(sz.x - 20.0) < 0.1 and absf(sz.y - 10.0) < 0.05 and absf(sz.z - 5.0) < 0.025
		var volok := absf(float(got.get("vol", 0.0)) - 1000.0) < 5.0
		var mi: MeshInstance3D = null
		for ch in (ui.ui_c43["sv"] as SubViewport).get_children():
			if ch is MeshInstance3D:
				mi = ch
		var mtris := 0
		if mi != null:
			mtris = (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		ok(bool(rr.get("match", false)) and String(rr.get("text", "")).contains("matches the part") and szok and volok and int(got.get("tris", -1)) == int(rr.get("tris_part", -2)) and (ui.ui_c43["box"] as Control).is_visible_in_tree() and mtris == int(got.get("tris", -3)),
			"5 %s re-read: tris file %s part %s, size %s, vol %.1f, preview tris %d, text [%s]" % [ext, got.get("tris"), rr.get("tris_part"), sz, float(got.get("vol", 0.0)), mtris, rr.get("text", "")])
		await idle(4)
		root.get_viewport().get_texture().get_image().save_png(SHOT + "/dialog_reread_" + ext + ".png")
	# 6 CONTROL
	var bodies: Array = MeshExport.bodies_of(m.S.part)["bodies"]
	var b0: Dictionary = bodies[0]
	var good := C43Printer.reread(gd + "/C43_box.stl", "stl")
	var cut: PackedVector3Array = (good["v"] as PackedVector3Array).slice(0, (good["v"] as PackedVector3Array).size() - 3)
	var bad_got := {"ok": true, "tris": cut.size() / 3, "v": cut, "size": good["size"], "vol": float(good["vol"]) * 0.9}
	var c1 := C43Printer.compare(bodies, bad_got)
	var big: Array = []
	for b in bodies:
		var vv: PackedVector3Array = (b["v"] as PackedVector3Array).duplicate()
		for i in vv.size():
			vv[i] = vv[i] * 1.02
		big.append({"v": vv, "t": b["t"]})
	var c2 := C43Printer.compare(big, good)
	ok(not bool(c1["match"]) and String(c1["text"]).contains("does NOT match") and not bool(c2["match"]) and bool(C43Printer.compare(bodies, good)["match"]), "6 control: dropped triangle -> %s, scaled 1.02 -> %s, true pair -> match" % [c1["match"], c2["match"]])
	b0.size()
	print("c43: %d fail" % fails)
	quit(1 if fails > 0 else 0)
