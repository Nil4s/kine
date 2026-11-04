extends SceneTree
## godot --path . -s tests/c57_test.gd     (C57: a slicer-like print estimate, not solid plastic; needs the CAD DLL)
## Row C57 of LEDGER_210 (Nick 11-03: "5 million to print, are we printing diamonds").
## REFERENCE NUMBERS (measured, not recalled): Bambu Studio's own CLI (C:/Program Files/Bambu Studio/bambu-studio.exe --slice) on its shipped
##   resources/model/3DBenchy.stl and a 20 mm cube STL, machine "Bambu Lab X1 Carbon 0.4 nozzle", process "0.20mm Standard @BBL X1C"
##   (2 walls, 4 top / 3 bottom layers, 20 % sparse infill), filament "Bambu PLA Basic @BBL X1C", the profiles of that install. G-code files:
##   C:/Users/Nick/tools/kine_workers/out/c57/ref/out_cube20 and out_3DBenchy (plate_1.gcode headers).
##     20 mm cube : "total estimated time: 10m 12s", filament length 1232.42 mm  -> x pi x 0.875^2 mm2 x 1.26 g/cm3 = 3.73 g
##     3DBenchy   : "total estimated time: 34m 9s",  filament length 3734.81 mm  -> 11.32 g
##   (the CLI prints weight 0.00 because it leaves the density at 0, so grams are computed from the length with the 1.75 mm filament and PLA Basic's 1.26)
##   Web numbers (MyMiniFactory Benchy 0.2 mm 10 % infill: 11 g, 158 min; MakerWorld cubes: 4-6 g, 16-28 min) are on other printers and agree on grams only.
## Bars (written before the first run):
##   1 CUBE    estimator at the profile's 20 % infill and Bambu PLA flow: grams and minutes each within 25 % of 3.73 g and 10.2 min
##   2 BENCHY  the same on the Benchy mesh read from the STL (volume, area): within 25 % of 11.32 g and 34.15 min
##   3 DEFAULT the default infill is 15 %: less plastic than at 20 %, and a solid part never costs more than its solid volume
##   4 HOUSE   a 10 m part (10000 x 10000 x 3000 mm): the export checklist says "bigger than the printer bed" and gives 1:10, 1:50 and 1:100 lines; the 1:100 cost
##             equals the estimate of the part scaled by hand; the Size line cost is at most 0.2 x the old solid cost (15 pct infill + a thin shell; the first draft of this bar said 100x, which is
##             impossible for a solid block at 15 pct infill: arithmetic error in the bar, corrected after the first run, the code was not changed)
##   5 SANITY  a part under 5 kg shows no sanity line; one over 5 kg shows it (a 200 x 200 x 100 block at 100 % scale printed at Ender is 0.6 kg: none; the house: yes)
##   6 WOOD    wood prices unchanged: a 600 mm board costs 0.6 x 14 = R$ 8.40 and its cost text is "about R$ 8,40" (wood_brl 8.4, pla_brl 0)
##   7 CONTROL the bars can fail: the old solid cost of the cube misses bar 1 by more than 25 %, and a plain stub estimate of zero fails it
##   8 SHOTS   1280x720 export dialog with the cube and with the house, saved to out/c57 and looked at
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c57"
const REF_CUBE := {"g": 3.73, "min": 10.2}
const REF_BENCHY := {"g": 11.32, "min": 34.15}
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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func within(v: float, ref: float) -> bool:
	return absf(v - ref) <= 0.25 * ref


func box_rec(nm: String, w: float, d: float, h: float) -> Dictionary:
	var rec := Part.make(nm)
	var fs: Array = rec["features"]
	var s1 := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(w, d))])
	PartTemplates._ex(fs, s1, "extrude", h, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


## volume mm3, area mm2 of a binary STL
func stl_numbers(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.seek(80)
	var n := f.get_32()
	var vol := 0.0
	var area := 0.0
	for i in n:
		f.seek(84 + i * 50 + 12)
		var a := Vector3(f.get_float(), f.get_float(), f.get_float())
		var b := Vector3(f.get_float(), f.get_float(), f.get_float())
		var c := Vector3(f.get_float(), f.get_float(), f.get_float())
		vol += a.dot(b.cross(c)) / 6.0
		area += (b - a).cross(c - a).length() * 0.5
	return {"vol": absf(vol), "area": area, "tris": n}


func open_print(rec: Dictionary, shotname: String) -> String:
	m.S.part = rec
	pu._rec_sig = ""
	await idle(8)
	await click_ctl(root.find_child("easypart_export", true, false) as Button)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var pi := -1
	for i in ui.ui_target.item_count:
		if ui.ui_target.get_item_text(i).contains("3D printing"):
			pi = i
	ui.ui_target.select(pi)
	ui._on_target(pi)
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	for sc in [ui.opts_scroll]:
		if sc != null:   # the checklist is below the fold: bring it into view for the picture
			(sc as ScrollContainer).ensure_control_visible(ui.ui_checks)
			(sc as ScrollContainer).scroll_vertical = int((sc as ScrollContainer).get_v_scroll_bar().max_value)
	await idle(6)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [SHOT, shotname])
	var t := ui.ui_checks.text
	ui.dlg.hide()
	await idle(3)
	return t


func _init() -> void:
	var wd = create_timer(400.0)
	wd.timeout.connect(func():
		print("FAIL watchdog: c57 timed out")
		quit(1))
	# ---- 1-3 the estimator against the reference (pure numbers, no app)
	var bam: Dictionary = C57PrintEst.PRINTERS["Bambu PLA"]
	var cube := C57PrintEst.plastic(8000.0, 2400.0, float(bam["flow"]), 1.26, 0.20)
	var cmin: float = cube["seconds"] / 60.0
	ok(within(cube["grams"], REF_CUBE["g"]) and within(cmin, REF_CUBE["min"]), "1 cube: %.2f g (ref %.2f), %.1f min (ref %.1f), band 25 pct" % [cube["grams"], REF_CUBE["g"], cmin, REF_CUBE["min"]])
	var bn := stl_numbers("C:/Program Files/Bambu Studio/resources/model/3DBenchy.stl")
	if bn.is_empty():
		ok(false, "2 benchy: the STL is not installed here")
	else:
		var bz := C57PrintEst.plastic(bn["vol"], bn["area"], float(bam["flow"]), 1.26, 0.20)
		var bmin: float = bz["seconds"] / 60.0
		ok(within(bz["grams"], REF_BENCHY["g"]) and within(bmin, REF_BENCHY["min"]), "2 benchy (%d tris, %.0f mm3, %.0f mm2): %.2f g (ref %.2f), %.1f min (ref %.1f), band 25 pct" % [bn["tris"], bn["vol"], bn["area"], bz["grams"], REF_BENCHY["g"], bmin, REF_BENCHY["min"]])
	var c15 := C57PrintEst.plastic(8000.0, 2400.0, 4.5, 1.26)
	var thin := C57PrintEst.plastic(100.0, 5000.0, 4.5, 1.26)
	ok(C57PrintEst.INFILL == 0.15 and c15["grams"] < cube["grams"] and thin["cm3"] <= 0.1 + 1e-9, "3 default infill %.2f: cube %.2f g at 15 pct < %.2f g at 20 pct; a thin part (0.1 cm3 solid) uses %.3f cm3" % [C57PrintEst.INFILL, c15["grams"], cube["grams"], thin["cm3"]])
	# ---- app
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://zz_c57_scenes"))
	ss.dirs_override = ["user://zz_c57_scenes"]
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
	CutList.set_price("pla_brl_kg", 120.0)
	CutList.set_price("pine_brl_m", 14.0)
	# ---- 4 HOUSE (and the cube's shot)
	var ct := await open_print(box_rec("Cube", 20, 20, 20), "dialog_cube")
	print("cube checklist:\n" + ct)
	var cube_c := CutList.cost(m.S.part)
	var house := box_rec("House", 10000, 10000, 3000)
	var ht := await open_print(house, "dialog_house")
	print("house checklist:\n" + ht)
	var hc := CutList.cost(house)
	var ss2 := CutList.solids(house)
	var e100: Dictionary = {}
	var by_hand := C57PrintEst.plastic(float(ss2[0]["vol_cm3"]) * 1000.0 / 1.0e6, float(ss2[0]["area_mm2"]) / 1.0e4, 3.0, 1.24)
	var e := C57PrintEst.estimate(house, ss2, CutList.prices())
	for r in e["scaled"]:
		if int(r["n"]) == 100:
			e100 = r
	var solid_old := float(ss2[0]["vol_cm3"]) * 1.24 / 1000.0 * 120.0
	ok(ht.contains("bigger than the printer bed") and ht.contains("1:10:") and ht.contains("1:50:") and ht.contains("1:100:") and not e100.is_empty() and absf(float(e100["brl"]) - by_hand["grams"] / 1000.0 * 120.0) <= 0.005 and float(hc["brl"]) <= 0.2 * solid_old and String(hc["text"]).contains("too big for the bed"),
		"4 house: says bigger than the bed, lines 1:10 / 1:50 / 1:100 (%s), 1:100 cost %.2f vs by hand %.2f, Size line [%s], old solid cost %.0f vs %.0f" % [str(ht.contains("1:100:")), float(e100.get("brl", -1.0)), by_hand["grams"] / 1000.0 * 120.0, hc["text"], solid_old, hc["brl"]])
	# ---- 5 SANITY
	var small := ct
	var hs := ht.contains("over 5 kg")
	var mid := C57PrintEst.lines(box_rec("Block", 200, 200, 100))
	ok(not small.contains("over 5 kg") and not ("\n".join(mid)).contains("over 5 kg") and hs, "5 sanity: cube none, 0.6 kg block none, house shows it (%s)" % str(hs))
	# ---- 6 WOOD
	var wood := Part.make("Board")
	var fs: Array = wood["features"]
	var s1 := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(89, 38))])
	PartTemplates._ex(fs, s1, "extrude", 600.0, "new")
	wood["seq"] = fs.size()
	wood["kept"] = true
	wood["easy"] = {"t": "board"}
	var wc := CutList.cost(wood)
	ok(absf(float(wc["wood_brl"]) - 8.4) <= 0.001 and float(wc["pla_brl"]) == 0.0 and String(wc["text"]) == "about R$ 8,40", "6 wood: 600 mm board wood_brl %.3f pla %.3f text [%s]" % [wc["wood_brl"], wc["pla_brl"], wc["text"]])
	# ---- 7 CONTROL
	var old_cube_g := 8.0 * 1.24
	ok(not within(old_cube_g, REF_CUBE["g"]) and not within(0.0, REF_CUBE["g"]), "7 control: the old solid cube is %.2f g against %.2f (outside 25 pct), a zero estimate is outside too; cube Size line [%s]" % [old_cube_g, REF_CUBE["g"], cube_c.get("text", "")])
	print("c57: %d fail" % fails)
	quit(1 if fails > 0 else 0)
