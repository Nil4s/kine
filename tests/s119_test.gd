extends SceneTree
## godot --path . --position 4000,4000 -s tests/s119_test.gd     (Friday plan 119 Send to slicer; scripts/build/slicer_send.gd, export_dialog.gd)
##   detect()      a fake Program Files tree (C:/Temp/claude/s119/fake_pf): the right names and paths, in order; decoy folders and a missing exe do not count;
##                 the registry text finds a slicer installed elsewhere; an empty tree finds nothing
##   send          the 3MF is written to user://exports, the launch is an argv array [exe, <that 3MF path>] (the launcher is a stub: no real slicer starts);
##                 the 3MF is re-read from disk and its volume matches the part's within 0.1 pct
##   dialog        real clicks: the Export dialog on 3D printing lists what was found and the Send to slicer button sends; with none found its text says so
const DIRT := "user://zz_s119_scenes"
const SHOTS := "C:/Temp/claude/s119"
const FAKE := "C:/Temp/claude/s119/fake_pf"
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




func tree_file(p: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("x")
	f.close()


## the 3MF's volume, re-read from the zip on disk: the sum of signed tetrahedra of every object (mm3)
func volume_3mf(path: String) -> float:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return -1.0
	var model := z.read_file("3D/3dmodel.model")
	z.close()
	var xp := XMLParser.new()
	xp.open_buffer(model)
	var vs := PackedVector3Array()
	var vol := 0.0
	while xp.read() != ERR_FILE_EOF:
		if xp.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match xp.get_node_name():
			"object":
				vs = PackedVector3Array()
			"vertex":
				vs.append(Vector3(float(xp.get_named_attribute_value("x")), float(xp.get_named_attribute_value("y")), float(xp.get_named_attribute_value("z"))))
			"triangle":
				var a := vs[int(xp.get_named_attribute_value("v1"))]
				var b := vs[int(xp.get_named_attribute_value("v2"))]
				var c := vs[int(xp.get_named_attribute_value("v3"))]
				vol += a.dot(b.cross(c)) / 6.0
	return vol


var stub_calls := []


func stub_launch(exe: String, args: Array) -> int:
	stub_calls.append({"exe": exe, "args": args})
	return 4242


func names_of(a: Array) -> Array:
	var n := []
	for f in a:
		n.append(String(f["name"]))
	return n


func _init() -> void:
	# ---------- DETECT on a fake tree (pure: needs no app)
	if DirAccess.dir_exists_absolute(FAKE):
		OS.execute("cmd", ["/c", "rmdir", "/s", "/q", FAKE.replace("/", "\\")])
	var pf := FAKE + "/Program Files"
	var pf86 := FAKE + "/Program Files (x86)"
	var emp := FAKE + "/empty_pf"
	DirAccess.make_dir_recursive_absolute(emp)
	tree_file(pf + "/Prusa3D/PrusaSlicer/prusa-slicer.exe")
	tree_file(pf + "/UltiMaker Cura 5.7.1/UltiMaker-Cura.exe")
	tree_file(pf + "/Bambu Studio/bambu-studio.exe")
	tree_file(pf + "/Git/git.exe")                       # not a slicer
	tree_file(pf + "/Orca Decoy/readme.txt")             # a folder that hints Orca but holds no slicer
	tree_file(pf86 + "/Elsewhere/notes.txt")
	var found := SlicerSend.detect([pf, pf86])
	var nm := names_of(found)
	ok(nm == ["UltiMaker Cura", "PrusaSlicer", "Bambu Studio"], "119 fake Program Files: found %s (want Cura, PrusaSlicer, Bambu Studio; the Orca decoy and Git do not count)" % str(nm))
	var paths_ok: bool = found.size() == 3 and found[0]["path"] == pf + "/UltiMaker Cura 5.7.1/UltiMaker-Cura.exe" and found[1]["path"] == pf + "/Prusa3D/PrusaSlicer/prusa-slicer.exe" and found[2]["path"] == pf + "/Bambu Studio/bambu-studio.exe"
	ok(paths_ok, "119 the paths are the exact exe files: %s" % str(found.map(func(f): return String(f["path"]).trim_prefix(FAKE))))
	var reg := "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OrcaSlicer\r\n    DisplayName    REG_SZ    OrcaSlicer\r\n    InstallLocation    REG_SZ    %s\r\n\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Other\r\n    DisplayName    REG_SZ    7-Zip\r\n    InstallLocation    REG_SZ    %s\r\n" % [(FAKE + "/Custom/Orca").replace("/", "\\"), (pf + "/Git").replace("/", "\\")]
	tree_file(FAKE + "/Custom/Orca/orca-slicer.exe")
	var rd := SlicerSend.reg_dirs_of(reg)
	ok(rd == [FAKE + "/Custom/Orca"], "119 registry text: install folders of slicers only %s" % str(rd))
	var f4 := SlicerSend.detect([pf, pf86], rd)
	var n4 := names_of(f4)
	ok(n4 == ["UltiMaker Cura", "PrusaSlicer", "Bambu Studio", "OrcaSlicer"] and String(f4[3]["path"]) == FAKE + "/Custom/Orca/orca-slicer.exe", "119 with the registry folder too: %s" % str(n4))
	var f5 := SlicerSend.detect([emp, FAKE + "/no_such_folder"], [])
	ok(f5.is_empty() and SlicerSend.found_text(f5).contains("No slicer found") and SlicerSend.none_text().contains("PrusaSlicer") and SlicerSend.none_text().contains("OrcaSlicer"), "119 an empty tree finds nothing: \"%s\"" % SlicerSend.none_text().left(120))

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
		print("FAIL: no KineCAD DLL, the export cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)

	# ---------- SEND (the stub launcher)
	var rec := box_rec("Slicer box", 20.0, 10.0, 5.0)
	var want_v := float(Part.replay(rec, -1, {})["volume"]) * 1.0e9
	var out3 := ProjectSettings.globalize_path("user://exports/Slicer_box.3mf")
	if FileAccess.file_exists(out3):
		DirAccess.remove_absolute(out3)
	var r := SlicerSend.send(rec, found[1], stub_launch)
	var got_v := volume_3mf(String(r["path"]))
	ok(bool(r["ok"]) and String(r["path"]) == out3 and FileAccess.file_exists(out3), "119 send: the 3MF is on disk at %s" % String(r["path"]))
	ok(stub_calls.size() == 1 and stub_calls[0]["exe"] == found[1]["path"] and stub_calls[0]["args"] == [out3],
		"119 the launch is argv: exe %s, args %s (the exact 3MF path)" % [str(stub_calls[0]["exe"]).get_file() if stub_calls.size() > 0 else "-", str(stub_calls[0]["args"]) if stub_calls.size() > 0 else "-"])
	ok(want_v > 0.0 and absf(got_v - want_v) <= want_v * 0.001 and absf(got_v - 1000.0) <= 1.0, "119 the 3MF re-read from disk has volume %.3f mm3, the part's is %.3f (within 0.1 pct; 20 x 10 x 5 = 1000)" % [got_v, want_v])
	var nos := SlicerSend.send(rec, {}, stub_launch)
	ok(not bool(nos["ok"]) and stub_calls.size() == 1 and String(nos["text"]).contains("No slicer found"), "119 no slicer chosen: nothing is launched, the words say so")
	var hrec := Part.make("Slicer hole")
	var hfs: Array = hrec["features"]
	PartTemplates._ex(hfs, PartTemplates._sk(hfs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))]), "extrude", 5.0, "new")
	PartTemplates._ex(hfs, PartTemplates._sk(hfs, "front", [{"k": "circle", "c": [10.0, 5.0], "r": 3.0}]), "extrude", 5.0, "cut")
	hrec["seq"] = hfs.size()
	hrec["kept"] = true
	var hr := SlicerSend.send(hrec, found[0], stub_launch)
	var hv := float(Part.replay(hrec, -1, {})["volume"]) * 1.0e9
	var hgot := volume_3mf(String(hr["path"]))
	ok(bool(hr["ok"]) and absf(hgot - hv) <= hv * 0.001, "119 a part with a round hole: 3MF volume %.3f vs %.3f mm3 (within 0.1 pct)" % [hgot, hv])

	# ---------- the dialog, real clicks
	await show_rec(rec)
	var eb := root.find_child("easypart_export", true, false) as Button
	ok(eb != null and eb.is_visible_in_tree(), "the Easy Part bar has an Export button on screen")
	if eb == null:
		print("s119: %d fail" % (fails + 1))
		quit(1)
		return
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	ui.slicers_override = []
	ui.slicer_launcher = Callable(self, "stub_launch")
	await reopen(eb)
	ok(ui.dlg.visible and ui.ui_target.get_item_text(ui.ui_target.selected).contains("3D printing") and ui.ui_slicer_box.visible and ui.ui_slicer_btn.disabled and ui.ui_slicer_txt.text.contains("No slicer found") and ui.ui_slicer_txt.text.contains("Bambu Studio"),
		"119 dialog, no slicer: the text says [%s], the button is off" % ui.ui_slicer_txt.text.left(140))
	await shot("no_slicer")
	ui.slicers_override = found
	await reopen(eb)
	ok(ui.ui_slicer_box.visible and not ui.ui_slicer_btn.disabled and ui.ui_slicer_opt.item_count == 3 and ui.ui_slicer_txt.text.contains("PrusaSlicer") and ui.ui_slicer_txt.text.contains("prusa-slicer.exe"),
		"119 dialog, three found: list of %d, text [%s]" % [ui.ui_slicer_opt.item_count, ui.ui_slicer_txt.text.left(120)])
	ui.ui_slicer_opt.select(2)
	stub_calls.clear()
	if FileAccess.file_exists(out3):
		DirAccess.remove_absolute(out3)
	await shot("slicers_found")
	ui.ui_slicer_btn.pressed.emit()   # an embedded dialog does not take pushed mouse events here (as s115 does for Export)
	await idle(3)
	ok(stub_calls.size() == 1 and stub_calls[0]["exe"] == found[2]["path"] and stub_calls[0]["args"] == [out3] and FileAccess.file_exists(out3) and absf(volume_3mf(out3) - want_v) <= want_v * 0.001,
		"119 clicking Send to slicer (Bambu Studio picked): %d launch, argv %s, 3MF volume %.3f" % [stub_calls.size(), str(stub_calls[0]["args"]) if stub_calls.size() > 0 else "-", volume_3mf(out3)])
	ui.ui_target.select(0)
	ui.ui_target.item_selected.emit(0)
	await idle(3)
	ok(not ui.ui_slicer_box.visible, "119 on the Unreal target the slicer row is hidden")
	ui.dlg.hide()
	print("s119: %d fail" % fails)
	quit(1 if fails > 0 else 0)
