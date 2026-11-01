extends SceneTree
## s081: Cut list from boards (plan 81) + Cost readout in BRL (plan 58). godot --path . -s tests/s081_test.gd (needs the CAD DLL)
## 3 wood boards (600x89x38 twice, 900x89x38 once), painted with the Colour > Wood chip (real clicks), then the Export dialog's Cut list target and its Export button.
##   1 LIST   2 rows, counts 2 and 1, total 2.1 board-metres within 0.001 (from the built solids)
##   2 CSV    the file the dialog wrote, re-read from disk: same rows, counts and total
##   3 COST   a 20 cm3 PLA part: the Size line says "about R$ 2,98" within R$ 0,01 of 20*1.24/1000*120
##   4 PRICE  changing the PLA price in the dialog's Prices row (240) doubles the readout (R$ 5,95)
const DIR := "user://zz_s081"
const DIRT := "user://zz_s081_scenes"
const SHOT := "C:/Temp/claude/s081"
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
	DirAccess.make_dir_recursive_absolute(SHOT)
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, name])




func boards3() -> Dictionary:
	var rec := Part.make("Shelf")
	var fs: Array = rec["features"]
	var x := 0.0
	for L in [600.0, 600.0, 900.0]:
		var s1 := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(x, 0), Vector2(x + 89.0, 38.0))])
		PartTemplates._ex(fs, s1, "extrude", L, "new")
		x += 100.0
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func block() -> Dictionary:
	var rec := Part.make("Block")
	var fs: Array = rec["features"]
	var s1 := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(40, 25))])
	PartTemplates._ex(fs, s1, "extrude", 20.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


## "R$ 2,98" in a text -> 2.98; -1 when absent
func brl_in(t: String) -> float:
	var re := RegEx.new()
	re.compile("R\\$ ([0-9.]+),([0-9]{2})")
	var r := re.search(t)
	if r == null:
		return -1.0
	return float(r.get_string(1).replace(".", "") + "." + r.get_string(2))


func read_csv(path: String) -> Dictionary:
	var rows := []
	var total := -1.0
	var tcount := -1
	var first := true
	for ln in FileAccess.get_file_as_string(path).split("\n", false):
		if first:
			first = false
			continue
		var c := ln.split(",")
		if c[0] == "TOTAL":
			total = float(c[5])
			tcount = int(c[4])
		else:
			rows.append({"name": c[0], "len": int(c[1]), "w": int(c[2]), "t": int(c[3]), "n": int(c[4]), "m": float(c[5])})
	return {"rows": rows, "total": total, "tcount": tcount}


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
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	CutList.set_price("pla_brl_kg", 120.0)
	CutList.set_price("pine_brl_m", 14.0)
	m.S.part = boards3()
	pu._rec_sig = ""
	pu.sync()
	await idle(8)
	var ep = pu.ep
	await click_ctl(ep.make_btns["colour"])
	var wb: Button = ep.colour_box.find_child("easypart_colour_wood", true, false) as Button
	var vbr: Rect2 = ep.view_box.get_global_rect()
	ok(wb.is_visible_in_tree() and not wb.get_global_rect().intersects(vbr) and root.get_visible_rect().encloses(wb.get_global_rect()), "0b the Wood chip %s is on the screen and clear of the view column %s" % [str(wb.get_global_rect()), str(vbr)])
	await click_ctl(wb)
	await idle(6)
	ok(wb != null and int(pu.res.get("bodies", 0)) == 3, "0 three solids built (%d) and painted with the Wood chip" % int(pu.res.get("bodies", 0)))

	# 1 LIST
	var bl := CutList.boards(m.S.part)
	var rows: Array = bl["rows"]
	var cnts := []
	for r in rows:
		cnts.append(int(r["count"]))
	var ok1 := rows.size() == 2 and cnts == [2, 1] and absf(float(bl["total_m"]) - 2.1) <= 0.001
	if ok1:
		ok1 = int(rows[0]["length"]) == 600 and int(rows[0]["width"]) == 89 and int(rows[0]["thickness"]) == 38 and int(rows[1]["length"]) == 900
	ok(ok1, "1 cut list: %d rows, counts %s, rows %s, total %.4f m (want 2 rows, [2, 1], 600x89x38 then 900, 2.1 +- 0.001)" % [rows.size(), str(cnts), str(rows), float(bl["total_m"])])

	# 2 CSV through the dialog
	var eb := root.find_child("easypart_export", true, false) as Button
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var ci := -1
	for i in ui.ui_target.item_count:
		if ui.ui_target.get_item_text(i).contains("Cut list"):
			ci = i
	ok(ci >= 0, "2 the Export dialog has a Cut list target (index %d of %d)" % [ci, ui.ui_target.item_count])
	if ci < 0:
		print("s081: %d fail" % fails)
		quit(1)
		return
	ui.ui_target.select(ci)
	ui._on_target(ci)
	await idle(3)
	var chk := ui.ui_checks.text
	await shot("dialog_cutlist")
	var path := ProjectSettings.globalize_path("res://exports") + "/Shelf_cutlist.csv"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	ui.dlg.get_ok_button().pressed.emit()
	await idle(4)
	var fok := FileAccess.file_exists(path)
	var cv := read_csv(path) if fok else {"rows": [], "total": -1.0, "tcount": -1}
	var cr: Array = cv["rows"]
	var ok2 := fok and cr.size() == 2 and absf(float(cv["total"]) - 2.1) <= 0.001 and int(cv["tcount"]) == 3
	if ok2:
		ok2 = int(cr[0]["n"]) == 2 and int(cr[1]["n"]) == 1 and int(cr[0]["len"]) == 600 and int(cr[1]["len"]) == 900 and absf(float(cr[0]["m"]) - 1.2) <= 0.001
	ok(ok2, "2 CSV re-read from disk (%s): %d rows %s, total %.4f, boards %d; checklist: %s" % [path, cr.size(), str(cr), float(cv["total"]), int(cv["tcount"]), chk.replace("\n", " | ")])
	if fok:
		DirAccess.remove_absolute(path)
	ui.dlg.hide()
	await idle(3)

	# 3 COST: a 20 cm3 PLA block
	m.S.part = block()
	pu._rec_sig = ""
	pu.sync()
	await idle(10)
	var txt: String = ep.size_l.text
	var want := 20.0 * 1.24 / 1000.0 * 120.0
	var got := brl_in(txt)
	ok(got >= 0.0 and absf(got - want) <= 0.01 and txt.contains("about R$ 2,98"), "3 20 cm3 PLA: the Size line says [%s] -> R$ %.2f (want %.3f within 0.01, Brazilian comma); visible %s" % [txt, got, want, str(ep.size_l.visible)])
	await shot("cost_pla")

	# 4 PRICE: change PLA to 240 in the dialog's Prices row
	await click_ctl(root.find_child("easypart_export", true, false) as Button)
	await idle(3)
	var ui2: ExportDialog = m.export_ui
	var pidx := -1
	for i in ui2.ui_target.item_count:
		if ui2.ui_target.get_item_text(i).contains("3D printing"):
			pidx = i
	ui2.ui_target.select(pidx)
	ui2._on_target(pidx)
	await idle(3)
	var sb := ui2.ui_price_row.find_child("export_price_pla_brl_kg", true, false) as SpinBox
	var shown := ui2.ui_price_row.is_visible_in_tree()
	await shot("dialog_prices")
	if sb != null:
		sb.value = 240.0
	await idle(2)
	ui2.dlg.hide()
	await idle(10)
	var got2 := brl_in(String(ep.size_l.text))
	var saved := FileAccess.get_file_as_string(CutList.PRICES_FILE).contains("240")
	ok(shown and sb != null and absf(got2 - 2.0 * want) <= 0.01 and saved, "4 price 120 -> 240 in the dialog: readout %.2f (want %.3f), Prices row shown (%s), kept in %s (%s)" % [got2, 2.0 * want, str(shown), CutList.PRICES_FILE, str(saved)])
	await shot("cost_pla_240")
	CutList.set_price("pla_brl_kg", 120.0)
	print("s081: %d fail" % fails)
	quit(1 if fails > 0 else 0)
