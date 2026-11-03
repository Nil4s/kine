extends SceneTree
## godot --path . -s tests/c27_test.gd     (C27: support removal choice in the 3D-print export; needs the CAD DLL)
## Bars (written before the first run). Every number is read back from the WRITTEN .3mf.
##   1 DEFAULT  the default export (Slicer default) has no support metadata and its 3dmodel.model is byte-identical to model_xml(bodies, title) with no support argument
##   2 EASY     picking "Easy to remove" in the dialog (real option-button item_selected) and pressing the dialog's Export writes a 3mf whose metadata reads back
##              contact distance 0.3 and interface layers 3
##   3 STRONG   "Strong" reads back 0.1 and 0 ; Easy gap > Strong gap and Easy layers > Strong layers (the trade is real)
##   4 WORDS    the line under the picker names the trade: Easy says "snap off" and "rougher", Strong says "harder to remove"; one sentence each, under 200 chars
##   5 SCOPE    the picker is visible on 3MF and hidden on STL; STL export bytes are not changed by the choice
##   6 CONTROL  the metadata reader returns {} on the origin-style file (planted: a 3mf written with no support), so bars 2/3 can fail
##   7 SHOT     1280x720 screenshot of the dialog with the picker, saved to out/c27
const DIR := "user://zz_c27"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c27"
var fails := 0
var m: Node
var pu: PartUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_move(p: Vector2, held: bool) -> void:
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
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func model_text(path: String) -> String:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return ""
	var t := z.read_file("3D/3dmodel.model").get_string_from_utf8()
	z.close()
	return t


func pick(ui: ExportDialog, i: int) -> void:
	ui.ui_support.select(i)
	ui.ui_support.item_selected.emit(i)
	await idle(2)


func _init() -> void:
	var wd := get_root().create_timer(240.0)   # watchdog
	wd.timeout.connect(func():
		print("FAIL watchdog: c27 timed out")
		quit(1))
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
	var rec := Part.make("C27 box")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))])
	PartTemplates._ex(fs, sid, "extrude", 5.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	m.S.part = rec
	pu._rec_sig = ""
	await idle(8)
	var eb := root.find_child("easypart_export", true, false) as Button
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var gd := ProjectSettings.globalize_path(DIR)
	# 3MF format is the first one
	ui.ui_format.select(0)
	ui.ui_format.item_selected.emit(0)
	await idle(3)
	var path3 := gd + "/C27_box.3mf"
	# 1 DEFAULT
	DirAccess.remove_absolute(path3)
	ui.export_now("print", 0, DIR)
	var def_txt := model_text(path3)
	var bodies: Array = MeshExport.bodies_of(m.S.part)["bodies"]
	var ref_txt := MeshExport.model_xml(bodies, "C27 box")
	ok(def_txt != "" and def_txt == ref_txt and not def_txt.contains("support_material") and SupportPref.read_3mf(path3).is_empty(), "1 default export has no support metadata and equals the no-argument model xml (%d chars)" % def_txt.length())
	# 6 CONTROL
	ok(SupportPref.read_3mf(path3).is_empty() and not SupportPref.read_3mf(path3).has("support_material_contact_distance"), "6 control: a file written with no support reads back {} (what origin writes)")
	# 2 EASY, through the dialog
	await pick(ui, 1)
	var easy_line := ui.ui_support_info.text
	DirAccess.remove_absolute(path3)
	ui.export_now("print", 0, DIR)
	var e := SupportPref.read_3mf(path3)
	ok(is_equal_approx(float(e.get("support_material_contact_distance", "-1")), 0.3) and int(e.get("support_material_interface_layers", "-1")) == 3, "2 Easy reads back gap/layers = %s" % [e])
	await idle(3)
	root.get_viewport().get_texture().get_image().save_png(SHOT + "/dialog_easy.png")
	# 3 STRONG
	await pick(ui, 2)
	var strong_line := ui.ui_support_info.text
	DirAccess.remove_absolute(path3)
	ui.export_now("print", 0, DIR)
	var s := SupportPref.read_3mf(path3)
	ok(is_equal_approx(float(s.get("support_material_contact_distance", "-1")), 0.1) and int(s.get("support_material_interface_layers", "-1")) == 0, "3 Strong reads back %s" % [s])
	ok(float(e.get("support_material_contact_distance", "0")) > float(s.get("support_material_contact_distance", "9")) and int(e.get("support_material_interface_layers", "0")) > int(s.get("support_material_interface_layers", "9")), "3b Easy gap and layers exceed Strong's")
	# 4 WORDS
	ok(easy_line.contains("snap off") and easy_line.contains("rougher") and strong_line.contains("harder to remove") and easy_line.length() < 200 and strong_line.length() < 200, "4 the line states the trade: [%s] / [%s]" % [easy_line, strong_line])
	# 5 SCOPE
	await pick(ui, 0)
	var vis3: bool = ui.ui_support.is_visible_in_tree()
	DirAccess.remove_absolute(gd + "/C27_box.stl")
	ui.ui_format.select(1)
	ui.ui_format.item_selected.emit(1)
	await idle(3)
	var vis_stl: bool = ui.ui_support.is_visible_in_tree()
	ui.export_now("print", 1, DIR)
	var stl_a := FileAccess.get_sha256(gd + "/C27_box.stl")
	await pick(ui, 1)
	DirAccess.remove_absolute(gd + "/C27_box.stl")
	ui.export_now("print", 1, DIR)
	ok(vis3 and not vis_stl and stl_a != "" and stl_a == FileAccess.get_sha256(gd + "/C27_box.stl"), "5 picker visible on 3MF (%s), hidden on STL (%s), STL unchanged by the choice" % [vis3, not vis_stl])
	ui.ui_format.select(0)
	ui.ui_format.item_selected.emit(0)
	await pick(ui, 1)
	await idle(3)
	root.get_viewport().get_texture().get_image().save_png(SHOT + "/dialog_3mf.png")
	print("c27: %d fail" % fails)
	quit(1 if fails > 0 else 0)
