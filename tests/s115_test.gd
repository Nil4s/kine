extends SceneTree
## godot --path . --position 4000,4000 -s tests/s115_test.gd     (Friday plan 115 STEP export + 112 "Ready to print?" check; scripts/build/step_export.gd, print_check.gd, export_dialog.gd; needs the CAD DLL)
## Real clicks at 1280 x 720 (BUILDING card, Easy Part, the Export button). Numbers are read from the written files / the checklist text the dialog shows.
##   115 STEP   a "CAD program (STEP)" target joins the dialog only while a Part is on screen (the 7 engine targets stay 7); its Export button writes <name>.step;
##              the file is re-imported through the kernel (KCad.import_step): volume within 0.1 pct and bbox within 0.01 mm of the part (the file says metres,
##              so the kernel's importer returns millimetres); one piece and two pieces; a hole's curved faces survive (the volume is exact, not a mesh)
##   112 READY  the checklist: 0.5 mm wall -> "1 wall thinner than 0.8 mm" (two walls -> 2); T overhang area within 5 pct of 2.00 cm2; a body lifted 5 mm -> floating;
##              a plain box -> all good; a piece resting on another is not floating
const KCad := preload("res://scripts/kcad.gd")
const DIR := "user://zz_s115"
const DIRT := "user://zz_s115_scenes"
const SHOTS := "C:/Temp/claude/s115"
var fails := 0
var m: Node
var pu: PartUI


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


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOTS, name])


## a front-plane box record: x 0..w, y (up) y0..y0+h, z 0..d
func box_rec(nm: String, w: float, h: float, d: float, y0 := 0.0) -> Dictionary:
	var rec := Part.make(nm)
	var fs: Array = rec["features"]
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, y0), Vector2(w, y0 + h))]), "extrude", d, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


## the same 20 x 10 x 10 box with a through slot (x from sx0 to sx1, y 2..8): the walls beside the slot are the thin ones
func slot_rec(nm: String, sx0: float, sx1: float) -> Dictionary:
	var rec := box_rec(nm, 20.0, 10.0, 10.0)
	var fs: Array = rec["features"]
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(sx0, 2), Vector2(sx1, 8))]), "extrude", 10.0, "cut")
	rec["seq"] = fs.size()
	return rec


func lines_text(rec: Dictionary) -> String:
	return "\n".join(MeshExport.check_lines(rec))


func show_rec(rec: Dictionary) -> void:
	m.S.part = rec
	pu._rec_sig = ""
	await idle(6)


func reopen(eb: Button) -> void:
	var ui: ExportDialog = m.export_ui
	if ui != null and ui.dlg != null and ui.dlg.visible:
		ui.dlg.hide()
	await idle(2)
	await click_ctl(eb)
	await idle(4)


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
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
		print("FAIL: no KineCAD DLL, the export cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)

	# ---------- 112 READY TO PRINT (numbers straight from the analysis and the words)
	var plain := box_rec("Plain box", 20.0, 5.0, 10.0)
	var pr := PrintCheck.analyse(MeshExport.bodies_of(plain)["bodies"])
	var pt := lines_text(plain)
	ok(int(pr["thin"]) == 0 and absf(float(pr["overhang_cm2"])) < 0.005 and int(pr["floating"]) == 0 and bool(pr["ok"]) and pt.contains("Ready to print: all good"),
		"112 plain box: all good (thin %d, overhang %.3f cm2, floating %d) [%s]" % [int(pr["thin"]), float(pr["overhang_cm2"]), int(pr["floating"]), String((pr["lines"] as Array)[0]).left(60)])

	var s1 := slot_rec("Thin one", 0.5, 17.0)
	var r1 := PrintCheck.analyse(MeshExport.bodies_of(s1)["bodies"])
	var t1 := lines_text(s1)
	ok(int(r1["thin"]) == 1 and t1.contains("1 wall thinner than 0.8 mm") and absf(float(r1["thinnest"]) - 0.5) <= 0.01 and not t1.contains("Ready to print: all good"),
		"112 box with one 0.5 mm wall: %d thin wall, thinnest %.3f mm, words [%s]" % [int(r1["thin"]), float(r1["thinnest"]), String((r1["lines"] as Array)[1]).left(50)])
	var s2 := slot_rec("Thin two", 0.5, 19.5)
	var r2 := PrintCheck.analyse(MeshExport.bodies_of(s2)["bodies"])
	ok(int(r2["thin"]) == 2 and lines_text(s2).contains("2 walls thinner than 0.8 mm"), "112 two 0.5 mm walls: %d thin walls, the words say \"2 walls thinner than 0.8 mm\"" % int(r2["thin"]))
	var s3 := slot_rec("Wall 1", 1.0, 19.0)
	var r3 := PrintCheck.analyse(MeshExport.bodies_of(s3)["bodies"])
	ok(int(r3["thin"]) == 0, "112 walls of exactly 1.0 mm are not thin (%d)" % int(r3["thin"]))

	var trec := Part.make("T shape")
	var tfs: Array = trec["features"]
	PartTemplates._ex(tfs, PartTemplates._sk(tfs, "front", PartTemplates._poly([Vector2(10, 0), Vector2(20, 0), Vector2(20, 20), Vector2(30, 20), Vector2(30, 30), Vector2(0, 30), Vector2(0, 20), Vector2(10, 20)])), "extrude", 10.0, "new")
	trec["seq"] = tfs.size()
	trec["kept"] = true
	var tr := PrintCheck.analyse(MeshExport.bodies_of(trec)["bodies"])
	var want_cm2 := 2.0   # two arm undersides, 10 x 10 mm each
	ok(absf(float(tr["overhang_cm2"]) - want_cm2) <= want_cm2 * 0.05 and lines_text(trec).contains("cm2 of faces point down") and int(tr["floating"]) == 0 and int(tr["thin"]) == 0,
		"112 T shape: overhang %.3f cm2 (want %.2f within 5 pct), floating %d, thin %d [%s]" % [float(tr["overhang_cm2"]), want_cm2, int(tr["floating"]), int(tr["thin"]), String((tr["lines"] as Array)[2]).left(60)])

	var lift := box_rec("Lifted", 20.0, 5.0, 10.0, 5.0)
	var lr := PrintCheck.analyse(MeshExport.bodies_of(lift)["bodies"])
	ok(int(lr["floating"]) == 1 and absf(float(lr["lowest"]) - 5.0) <= 0.01 and lines_text(lift).contains("1 piece floating"),
		"112 a body lifted 5 mm: %d floating, lowest %.3f mm [%s]" % [int(lr["floating"]), float(lr["lowest"]), String((lr["lines"] as Array)[3]).left(60)])
	# two bodies: one on the bed with a second sitting on it (not floating); then the second lifted a gap away (floating)
	var stack := box_rec("Stack", 20.0, 5.0, 10.0)
	var sfs: Array = stack["features"]
	PartTemplates._ex(sfs, PartTemplates._sk(sfs, "front", [PartTemplates._rect(Vector2(5, 5), Vector2(15, 10))]), "extrude", 10.0, "new")
	var kr := PrintCheck.analyse(MeshExport.bodies_of(stack)["bodies"])
	var gap := box_rec("Gap", 20.0, 5.0, 10.0)
	var gfs: Array = gap["features"]
	PartTemplates._ex(gfs, PartTemplates._sk(gfs, "front", [PartTemplates._rect(Vector2(5, 8), Vector2(15, 13))]), "extrude", 10.0, "new")
	var gr := PrintCheck.analyse(MeshExport.bodies_of(gap)["bodies"])
	ok(int((MeshExport.bodies_of(stack)["bodies"] as Array).size()) == 2 and int(kr["floating"]) == 0 and int(gr["floating"]) == 1 and absf(float(gr["lowest"]) - 8.0) <= 0.01 and float(kr["overhang_cm2"]) < 0.005,
		"112 two pieces: resting on the first = %d floating (overhang %.3f cm2), 3 mm above it = %d floating, lowest %.2f mm" % [int(kr["floating"]), float(kr["overhang_cm2"]), int(gr["floating"]), float(gr["lowest"])])

	# ---------- the dialog: real click on Export, the checklist the maker reads
	await show_rec(s2)
	var eb := root.find_child("easypart_export", true, false) as Button
	ok(eb != null and eb.is_visible_in_tree(), "the Easy Part bar has an Export button on screen")
	if eb == null:
		print("s115: %d fail" % (fails + 1))
		quit(1)
		return
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var dlg_open: bool = ui != null and ui.dlg != null and ui.dlg.visible
	var checks_txt: String = String(ui.ui_checks.text) if dlg_open else ""
	ok(dlg_open and ui.ui_target.get_item_text(ui.ui_target.selected).contains("3D printing") and checks_txt.contains("2 walls thinner than 0.8 mm") and checks_txt.contains("Ready to print?") and checks_txt.contains("overhangs:") and checks_txt.contains("floating:"),
		"112 the dialog opens on 3D printing and its checklist says [%s]" % checks_txt.replace("\n", " | ").left(230))
	await shot("print_checklist_thin")
	await show_rec(trec)
	await reopen(eb)
	ok(String(ui.ui_checks.text).contains("2.00 cm2"), "112 T shape in the dialog: the overhang area is in the checklist (%s)" % String(ui.ui_checks.text).get_slice("\n", 3).left(100))
	await shot("print_checklist_overhang")
	await show_rec(lift)
	await reopen(eb)
	ok(String(ui.ui_checks.text).contains("1 piece floating"), "112 lifted body in the dialog: \"1 piece floating\" is in the checklist")
	await show_rec(plain)
	await reopen(eb)
	ok(String(ui.ui_checks.text).contains("Ready to print: all good"), "112 plain box in the dialog: all good")
	await shot("print_checklist_good")

	# the existing exports are unchanged by the added lines
	var cl: Array = MeshExport.check_lines(plain)
	ok(String(cl[0]).begins_with("OK") and String(cl[0]).contains("closed"), "the closed-solid line is still first [%s]" % String(cl[0]).left(40))

	# ---------- 115 STEP
	ok(ExportDialog.targets().size() == 7, "115 the engine targets are still 7 (%d); STEP joins only while a Part is on screen" % ExportDialog.targets().size())
	# a 20 x 10 x 5 box with a 6 mm round hole through the 5 mm: curved faces must survive
	var hrec := Part.make("Step part")
	var hfs: Array = hrec["features"]
	PartTemplates._ex(hfs, PartTemplates._sk(hfs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))]), "extrude", 5.0, "new")
	PartTemplates._ex(hfs, PartTemplates._sk(hfs, "front", [{"k": "circle", "c": [10.0, 5.0], "r": 3.0}]), "extrude", 5.0, "cut")
	hrec["seq"] = hfs.size()
	hrec["kept"] = true
	await show_rec(hrec)
	await reopen(eb)
	var labels := []
	for i in ui.ui_target.item_count:
		labels.append(ui.ui_target.get_item_text(i))
	var si := labels.find("CAD program (STEP)")
	ok(si >= 0 and labels.size() == 9 and String(labels[labels.size() - 1]).contains("3D printing"), "115 a part on screen: the dialog lists %s" % str(labels.slice(7)))
	if si < 0:
		print("s115: %d fail" % (fails + 1))
		quit(1)
		return
	ui.ui_target.select(si)
	ui.ui_target.item_selected.emit(si)
	await idle(3)
	var fm_txt := String(ui.ui_format.get_item_text(0)) + " " + String(ui.ui_info.text) + " " + String(ui.ui_checks.text)
	ok(fm_txt.contains(".step") and fm_txt.contains("STEP") and String(ui.ui_checks.text).contains("exact solid"), "115 STEP picked: format and checklist say [%s]" % fm_txt.replace("\n", " | ").left(200))
	await shot("step_target")
	var res_dir := ProjectSettings.globalize_path("res://exports")
	var out_path := "%s/Step_part.step" % res_dir
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	ui.dlg.get_ok_button().pressed.emit()
	await idle(4)
	ok(FileAccess.file_exists(out_path), "115 the dialog's own Export button wrote %s" % out_path)
	var txt := FileAccess.get_file_as_string(out_path)
	ok(txt.begins_with("ISO-10303-21") and txt.contains("MANIFOLD_SOLID_BREP") and txt.contains("SI_UNIT($,.METRE.)") and not txt.contains("SI_UNIT(.MILLI.,.METRE.)") and txt.contains("CYLINDRICAL_SURFACE"),
		"115 the file is ISO-10303-21 with a MANIFOLD_SOLID_BREP, a CYLINDRICAL_SURFACE (the hole stays a true cylinder), unit METRE (%d bytes)" % txt.length())
	# re-import through the kernel and compare with the part's own volume and box
	var rp := Part.replay(hrec, -1, {})
	var vol_mm3 := float(rp["volume"]) * 1.0e9
	var id := KCad.import_step(out_path)
	var imp_v := KCad.volume(id) if id > 0 else -1.0
	var imp_box := AABB()
	if id > 0:
		var tm := KCad.tessellate(id, 0.01, 0.3)
		imp_box = tm.get_aabb() if tm != null else AABB()
	var expect_v := 20.0 * 10.0 * 5.0 - PI * 9.0 * 5.0
	ok(id > 0 and absf(imp_v - vol_mm3) <= vol_mm3 * 0.001 and absf(imp_v - expect_v) <= expect_v * 0.001,
		"115 re-imported volume %.3f mm3 vs the part's %.3f (within 0.1 pct) and the hand sum %.3f" % [imp_v, vol_mm3, expect_v])
	var sz := imp_box.size
	ok(id > 0 and absf(sz.x - 20.0) <= 0.01 and absf(sz.y - 10.0) <= 0.01 and absf(sz.z - 5.0) <= 0.01,
		"115 re-imported bbox %s mm vs 20 x 10 x 5 (within 0.01 mm)" % str(sz))
	if id > 0:
		KCad.release(id)
	# two pieces in one file
	var two := box_rec("Two pieces", 20.0, 5.0, 10.0)
	var tfs2: Array = two["features"]
	PartTemplates._ex(tfs2, PartTemplates._sk(tfs2, "front", [PartTemplates._rect(Vector2(30, 0), Vector2(40, 8))]), "extrude", 10.0, "new")
	var rs := StepExport.export_part(two, DIR)
	var id2 := KCad.import_step(String(rs["path"])) if bool(rs["ok"]) else 0
	var v2 := KCad.volume(id2) if id2 > 0 else -1.0
	var bb2 := AABB()
	if id2 > 0:
		bb2 = KCad.tessellate(id2, 0.01, 0.3).get_aabb()
	var want2 := 20.0 * 5.0 * 10.0 + 10.0 * 8.0 * 10.0
	ok(bool(rs["ok"]) and int(rs["bodies"]) == 2 and absf(v2 - want2) <= want2 * 0.001 and absf(bb2.size.x - 40.0) <= 0.01 and absf(bb2.size.y - 8.0) <= 0.01 and absf(bb2.size.z - 10.0) <= 0.01,
		"115 two pieces: one file, volume %.3f mm3 (want %.0f), bbox %s mm (40 x 8 x 10)" % [v2, want2, str(bb2.size)])
	if id2 > 0:
		KCad.release(id2)
	var empty := StepExport.export_part({}, DIR)
	ok(not bool(empty["ok"]) and String(empty["text"]).begins_with("NOT DONE"), "115 no part: NOT DONE in words (%s)" % String(empty["text"]).left(50))
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	ui.dlg.hide()
	print("s115: %d fail" % fails)
	quit(1 if fails > 0 else 0)
