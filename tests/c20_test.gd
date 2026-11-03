extends SceneTree
## godot --path . -s tests/c20_test.gd     (C20: print fit, complaints #32 hinge clearance, #33 tessellation tied to fit, #36 support anchors; needs the CAD DLL)
## BARS, written and committed BEFORE the first run. Everything is opt-in: Normal quality (0.1 mm) and the Hinge chip are unchanged.
##  HINGE (#32)
##   (1) for each printer preset i of C03Tools.PRESETS: hinge_rec(i).fit_mm == the preset's clear, the knuckle's bore sketch radius == 1.5 + clear (+-1e-6), 2 bodies
##   (2) at the fit tessellation, hinge_check: fused false, min_mm >= 0.7 x clear and <= clear + 0.05, for all 4 presets
##   (3) CONTROL (the check can fail): Resin (0.1) at the Coarse quality (0.5 mm): fused true and the line starts WARN
##   (4) DEFAULT UNCHANGED: PartTemplates.make("hinge") has no circle sketch and no rec.pip_hinge
##  TESSELLATION (#33)
##   (5) quality_for_fit: defl_mm == fit / 4 (+-1e-9) for the 4 presets, name "Fit"; {} for a part with no fit_mm
##   (6) a cylinder r 10 mm with fit 0.15: the chord error read from the exported mesh <= 0.0375 + 0.002; same part Resin 0.1: <= 0.025 + 0.002
##   (7) CONTROL: the same cylinder at Coarse (0.5 mm): chord error > 0.0375 (the bar can fail)
##   (8) the words: tess_words says "quarter" and the dialog info line carries it when the box is on
##   (9) DEFAULT: the dialog's box starts off and quality() is Normal 0.1 mm
##  ANCHORS (#36)
##   (10) a 1.5 mm post 6 mm tall on a plate with a 10 x 10 roof above it: exactly 1 warning, width 1.5 +- 0.05, line starts WARN and says "mm wide"
##   (11) CONTROL: the same with a 4 mm post: 0 warnings, landings > 0, line starts OK
##   (12) a roof over the bare plate: 0 warnings (wide ground); a part with no overhang: 0 warnings and landings 0
##   (13) the dialog checklist with the box on contains the anchor line; with the box off it contains none (default checklist unchanged)
##  UI: the Print-in-place hinge button and the dialog box are on screen inside 1280 x 720; shots in out/c20 (looked at)
var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c20"
const DIRT := "user://zz_c20_scenes"
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func box(lo: Vector3, hi: Vector3) -> Dictionary:
	var v := PackedVector3Array([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)])
	var t := PackedInt32Array([0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7])
	return {"v": v, "t": t}


func post_case(w: float) -> Array:
	var c := 15.0
	return [box(Vector3(0, 0, 0), Vector3(30, 30, 2)), box(Vector3(c - w / 2, c - w / 2, 2), Vector3(c + w / 2, c + w / 2, 8)), box(Vector3(10, 10, 12), Vector3(20, 20, 14))]


func cyl_chord(q: Dictionary, fit: float) -> float:
	var rec := Part.make("Cyl")
	rec["fit_mm"] = fit
	var fs: Array = rec["features"]
	PartTemplates._ex(fs, PartTemplates._sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": 10.0}]), "extrude", 10.0, "new")
	rec["seq"] = fs.size()
	var bo := MeshExport.bodies_of(rec, q)
	var bb: Array = bo["bodies"]
	if bb.is_empty():
		return -1.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in (bb[0]["v"] as PackedVector3Array):
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var c := (lo + hi) * 0.5
	return C20Fit.chord_error_mm(bb, c.x, c.y, 10.0)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	var C03 := load("res://scripts/build/c03_tools.gd")
	# HINGE
	var all_ok := true
	var all_fit := true
	var det := ""
	for i in C03.PRESETS.size():
		var clear := float(C03.PRESETS[i]["clear"])
		var rec := C20Fit.hinge_rec(i)
		var fs: Array = rec["features"]
		var bore := -1.0
		for f in fs:
			if String(f["t"]) == "sketch" and (f["ents"] as Array).size() == 1:
				bore = float((f["ents"] as Array)[0]["r"])   # the last circle read is the pin; keep the second sketch's
		bore = float(((fs[2] as Dictionary)["ents"] as Array)[0]["r"])   # f1 sketch, f2 extrude, f3 sketch (bore)
		var bo := MeshExport.bodies_of(rec, C20Fit.quality_for_fit(rec))
		if not (absf(float(rec["fit_mm"]) - clear) < 1e-9 and absf(bore - (1.5 + clear)) < 1e-6 and (bo["bodies"] as Array).size() == 2):
			all_ok = false
		var hc := C20Fit.hinge_check(rec, C20Fit.quality_for_fit(rec))
		det += " %s: min %.3f/%.2f" % [C03.PRESETS[i]["name"], hc["min_mm"], clear]
		if bool(hc["fused"]) or float(hc["min_mm"]) < 0.7 * clear or float(hc["min_mm"]) > clear + 0.05:
			all_fit = false
	ok(all_ok, "1 hinge gap = the preset's clearance, bore = pin + clearance, two bodies, for all 4 presets")
	ok(all_fit, "2 at the fit tessellation the knuckles do not fuse [%s]" % det)
	var r0 := C20Fit.hinge_rec(0)
	var hc0 := C20Fit.hinge_check(r0, MeshQuality.of("Coarse"))
	ok(bool(hc0["fused"]) and String(hc0["line"]).begins_with("WARN"), "3 CONTROL: Resin 0.1 at Coarse: fused %s, min %.3f [%s]" % [str(hc0["fused"]), hc0["min_mm"], String(hc0["line"]).left(60)])
	var hd := PartTemplates.make("hinge")
	var has_circle := false
	for f in hd["features"]:
		if String(f["t"]) == "sketch":
			for e in f["ents"]:
				if String(e.get("k", "")) == "circle":
					has_circle = true
	ok(not has_circle and not hd.has("pip_hinge"), "4 the Hinge chip's record is unchanged (no circle, no pip_hinge)")
	# TESSELLATION
	var qok := true
	for i in C03.PRESETS.size():
		var rr := Part.make("x")
		rr["fit_mm"] = float(C03.PRESETS[i]["clear"])
		var q := C20Fit.quality_for_fit(rr)
		if absf(float(q["defl_mm"]) - float(rr["fit_mm"]) / 4.0) > 1e-9 or String(q["name"]) != "Fit":
			qok = false
	ok(qok and C20Fit.quality_for_fit(Part.make("y")).is_empty(), "5 quality_for_fit: deflection = fit / 4, named Fit; empty with no fit")
	var e15 := cyl_chord(C20Fit.quality_for_fit({"fit_mm": 0.15}), 0.15)
	var e10 := cyl_chord(C20Fit.quality_for_fit({"fit_mm": 0.1}), 0.1)
	var eC := cyl_chord(MeshQuality.of("Coarse"), 0.15)
	var eN := cyl_chord({}, 0.15)
	ok(e15 >= 0.0 and e15 <= 0.0375 + 0.002 and e10 >= 0.0 and e10 <= 0.025 + 0.002, "6 chord error: fit 0.15 -> %.4f (<= 0.0375), fit 0.1 -> %.4f (<= 0.025); default Normal reads %.4f" % [e15, e10, eN])
	ok(eC > 0.0375, "7 CONTROL: Coarse chord error %.4f > 0.0375" % eC)
	ok(C20Fit.tess_words({"defl_mm": 0.0375}, 100, 0.03).contains("quarter"), "8a tess_words says quarter")
	# anchors
	var an := C20Fit.anchor_check(post_case(1.5))
	var w0 := float(an["warn"][0]["width_mm"]) if (an["warn"] as Array).size() > 0 else -1.0
	ok((an["warn"] as Array).size() == 1 and absf(w0 - 1.5) <= 0.05 and String(an["lines"][0]).begins_with("WARN") and String(an["lines"][0]).contains("mm wide"), "10 1.5 mm post: %d warning(s), width %.2f, [%s]" % [(an["warn"] as Array).size(), w0, String(an["lines"][0]).left(70)])
	var an4 := C20Fit.anchor_check(post_case(4.0))
	ok((an4["warn"] as Array).is_empty() and int(an4["landings"]) > 0 and String(an4["lines"][0]).begins_with("OK"), "11 CONTROL 4 mm post: %d warnings, %d landings, [%s]" % [(an4["warn"] as Array).size(), int(an4["landings"]), String(an4["lines"][0]).left(50)])
	var roof := [box(Vector3(0, 0, 0), Vector3(30, 30, 2)), box(Vector3(10, 10, 12), Vector3(20, 20, 14))]
	var anr := C20Fit.anchor_check(roof)
	var ann := C20Fit.anchor_check([box(Vector3(0, 0, 0), Vector3(10, 10, 5))])
	ok((anr["warn"] as Array).is_empty() and (ann["warn"] as Array).is_empty() and int(ann["landings"]) == 0, "12 roof over bare plate: %d warnings; plain box: %d warnings, %d landings" % [(anr["warn"] as Array).size(), (ann["warn"] as Array).size(), int(ann["landings"])])
	# UI
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	ss._cards["building"].pressed.emit()
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	var pu: PartUI = m.bld.part
	pu.part_btn.pressed.emit()
	await idle(3)
	pu.easy_open_btn.pressed.emit()
	await idle(4)
	(root.find_child("easypart_chip_parts", true, false) as Button).pressed.emit()
	await idle(3)
	var hb := root.find_child("easypart_hinge_pick", true, false) as Button
	var lib: Dictionary = m.bld.part.easy.lib_btns if m.bld.part.get("easy") != null else {}
	var ep = m.bld.part.easy
	ep.lib_cat = "Hinges"
	ep._screw_sync()
	await idle(3)
	var pb := root.find_child("easypart_pip_hinge", true, false) as Button
	ok(pb != null and pb.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(pb.get_global_rect()), "UI the Print-in-place hinge button is on screen: %s" % (str(pb.get_global_rect()) if pb != null else "missing"))
	root.get_viewport().get_texture().get_image().save_png(SHOT + "/hinges_page.png")
	pb.pressed.emit()
	await idle(6)
	ok(bool(m.S.part.get("pip_hinge", false)) and float(m.S.part.get("fit_mm", 0.0)) > 0.0, "UI pressing it makes a pip_hinge part with fit %.2f" % float(m.S.part.get("fit_mm", 0.0)))
	m.S.part["fit_mm"] = 0.15
	var eb := root.find_child("easypart_export", true, false) as Button
	eb.pressed.emit()
	await idle(4)
	var ui: ExportDialog = m.export_ui
	ok(ui != null and ui.ui_fit != null and not ui.ui_fit.button_pressed and absf(float(ui.quality()["defl_mm"]) - 0.1) < 1e-9 and String(ui.quality()["name"]) == "Normal", "9 the box starts off; quality() is Normal 0.1")
	var off_lines := "\n".join(ui.checks("print", "stl"))
	ui.ui_fit.button_pressed = true
	await idle(4)
	var on_lines := "\n".join(ui.checks("print", "stl"))
	ok(absf(float(ui.quality()["defl_mm"]) - 0.0375) < 1e-9 and ui.ui_q_info.text.contains("quarter"), "8b box on: quality 0.0375, info [%s]" % ui.ui_q_info.text.left(90))
	ok(not off_lines.contains("knuckles") and on_lines.contains("knuckles"), "13 checklist: knuckle line only with the box on")
	ok(ui.ui_fit.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(ui.ui_fit.get_global_rect()), "UI the box is on screen: %s" % str(ui.ui_fit.get_global_rect()))
	root.get_viewport().get_texture().get_image().save_png(SHOT + "/export_dialog.png")
	print("c20: %d fail" % fails)
	quit(1 if fails > 0 else 0)
