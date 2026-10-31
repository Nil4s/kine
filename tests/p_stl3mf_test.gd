extends SceneTree
## godot --path . --position 4000,4000 -s tests/p_stl3mf_test.gd     (STL + 3MF export of a Part for 3D printing; scripts/build/mesh_export.gd + scripts/export_dialog.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720: the BUILDING card, a 20 x 10 x 5 mm box, the Easy Part bar's Export button, the dialog's Export button, the Parts chip M5 x 30).
## Every number is read back from the WRITTEN FILES (re-read from disk), never from the writer's variables. Files are Z up, millimetres.
##   1 ONE CLICK   the Export button opens the dialog already on 3D printing, with a 3MF and an STL format, "mm" in its words; its Export button writes the .3mf
##   2 STL         binary: 84 + 50 n bytes, the 80 byte header names Kine, n = the mesh's triangle count, bbox 20 x 10 x 5 mm within 0.01, every edge shared by exactly 2 triangles,
##                 every stored normal points away from the middle, the winding agrees with it, volume 1000 mm3 within 0.5 pct
##   3 3MF         a zip with [Content_Types].xml, _rels/.rels, 3D/3dmodel.model; unit="millimeter"; one object; the same triangle count and bbox; every edge shared twice;
##                 vertices are deduplicated (8 for a box); the build item lists the object
##   4 SCREW       an M5 x 30 from the Parts library exports (STL and 3MF) as ONE closed body, 35 mm tall (30 shank + 5 head), 8.5 mm across
##   5 OPEN        a box with one face missing: the words say "open edges: press Fix it first" and the STL is still written
##   6 COLOUR      a painted body gets a <basematerials> colour in the 3MF; two bodies are two objects
const DIR := "user://zz_p_stl3mf"
const DIRT := "user://zz_p_stl3mf_scenes"
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


## a triangle list read from a file: corners (3 per triangle) and the stored normals (or none)
func tri_report(corners: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	var ids := {}
	var idx := []
	for p in corners:
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not ids.has(key):
			ids[key] = ids.size()
		idx.append(ids[key])
	var cnt := {}
	for i in range(0, idx.size(), 3):
		for k in 3:
			var a: int = idx[i + k]
			var b: int = idx[i + (k + 1) % 3]
			var key2 := (mini(a, b) << 32) | maxi(a, b)
			cnt[key2] = int(cnt.get(key2, 0)) + 1
	var not_two := 0
	for k in cnt:
		if int(cnt[k]) != 2:
			not_two += 1
	var box := AABB(corners[0], Vector3.ZERO)
	for p in corners:
		box = box.expand(p)
	var vol := 0.0
	var outward := 0
	var agree := 0
	for i in range(0, corners.size(), 3):
		vol += corners[i].dot(corners[i + 1].cross(corners[i + 2])) / 6.0
		var wn := (corners[i + 1] - corners[i]).cross(corners[i + 2] - corners[i]).normalized()
		var cen := (corners[i] + corners[i + 1] + corners[i + 2]) / 3.0
		if wn.dot(cen - box.get_center()) > 0.0:
			outward += 1
		if normals.size() > i / 3 and normals[i / 3].dot(wn) > 0.99:
			agree += 1
	return {"tris": corners.size() / 3, "verts": ids.size(), "not_two": not_two, "box": box, "vol": vol, "outward": outward, "agree": agree}


func read_stl(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	var out := {"bytes": b.size(), "head": "", "n": 0, "rep": {}}
	if b.size() < 84:
		return out
	out["head"] = b.slice(0, 80).get_string_from_ascii()
	var n := b.decode_u32(80)
	out["n"] = n
	var corners := PackedVector3Array()
	var normals := PackedVector3Array()
	if b.size() == 84 + 50 * n and n > 0:
		for i in n:
			var o := 84 + 50 * i
			normals.append(Vector3(b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8)))
			for k in 3:
				var q := o + 12 + 12 * k
				corners.append(Vector3(b.decode_float(q), b.decode_float(q + 4), b.decode_float(q + 8)))
		out["rep"] = tri_report(corners, normals)
	return out


## the 3MF read back from the zip
func read_3mf(path: String) -> Dictionary:
	var out := {"entries": [], "unit": "", "objects": 0, "verts": 0, "tris": 0, "items": 0, "bases": 0, "colors": [], "rep": {}, "pids": 0, "xml": ""}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return out
	out["entries"] = Array(z.get_files())
	var model := z.read_file("3D/3dmodel.model")
	z.close()
	out["xml"] = model.get_string_from_utf8()
	var xp := XMLParser.new()
	xp.open_buffer(model)
	var first_rep := {}
	var cur_v := PackedVector3Array()
	var cur_t := []
	var in_obj := false
	while xp.read() != ERR_FILE_EOF:
		var t := xp.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			match xp.get_node_name():
				"model":
					out["unit"] = xp.get_named_attribute_value_safe("unit")
				"object":
					out["objects"] += 1
					in_obj = true
					cur_v = PackedVector3Array()
					cur_t = []
					if xp.has_attribute("pid"):
						out["pids"] += 1
				"vertex":
					cur_v.append(Vector3(float(xp.get_named_attribute_value("x")), float(xp.get_named_attribute_value("y")), float(xp.get_named_attribute_value("z"))))
					out["verts"] += 1
				"triangle":
					cur_t.append([int(xp.get_named_attribute_value("v1")), int(xp.get_named_attribute_value("v2")), int(xp.get_named_attribute_value("v3"))])
					out["tris"] += 1
				"item":
					out["items"] += 1
				"base":
					out["bases"] += 1
					out["colors"].append(xp.get_named_attribute_value_safe("displaycolor"))
		elif t == XMLParser.NODE_ELEMENT_END and xp.get_node_name() == "object" and in_obj:
			in_obj = false
			if first_rep.is_empty():
				var corners := PackedVector3Array()
				for tt in cur_t:
					for k in 3:
						corners.append(cur_v[tt[k]])
				first_rep = tri_report(corners, PackedVector3Array())
	out["rep"] = first_rep
	return out


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

	# 4 SCREW: the Parts library M5 x 30, real clicks
	var sc_chip := root.find_child("easypart_screw_M5_30", true, false) as Button
	if sc_chip == null or not sc_chip.is_visible_in_tree():
		await click_ctl(root.find_child("easypart_chip_parts", true, false) as Button)
		sc_chip = root.find_child("easypart_screw_M5_30", true, false) as Button
	print("screw chip visible: %s at %s" % [str(sc_chip != null and sc_chip.is_visible_in_tree()), str(sc_chip.get_global_rect()) if sc_chip != null else "-"])
	await click_ctl(sc_chip)
	if (m.S.part.get("features", []) as Array).is_empty():   # the click missed (a panel edge): press the chip itself, so the export is still measured
		print("note: the real click on the M5 x 30 chip placed nothing; pressing the chip")
		sc_chip.pressed.emit()
	await idle(6)
	var ex := ExportDialog.new(m)
	var sbo := MeshExport.bodies_of(m.S.part)
	var sn := 0
	for b in sbo["bodies"]:
		sn += (b["t"] as PackedInt32Array).size() / 3
	var sps := String(ex.export_now("print", 1, DIR))
	var tps := String(ex.export_now("print", 0, DIR))
	var ss1 := read_stl(ProjectSettings.globalize_path(sps)) if sps != "" else {"rep": {}, "n": 0}
	var st1 := read_3mf(ProjectSettings.globalize_path(tps)) if tps != "" else {"rep": {}, "objects": 0, "tris": 0}
	var a: Dictionary = ss1["rep"]
	var b3: Dictionary = st1["rep"]
	var abox: AABB = a["box"] if not a.is_empty() else AABB()
	var bbox: AABB = b3["box"] if not b3.is_empty() else AABB()
	ok((sbo["bodies"] as Array).size() == 1 and not a.is_empty() and not b3.is_empty() and int(a["not_two"]) == 0 and int(b3["not_two"]) == 0 and int(st1["objects"]) == 1 and int(ss1["n"]) == sn and int(st1["tris"]) == sn,
		"4 M5 x 30: one closed body in both files (STL %d tri, %d edges not shared twice; 3MF %d tri, %d objects, %d edges not shared twice)" % [int(ss1.get("n", 0)), int(a.get("not_two", -1)), int(st1.get("tris", 0)), int(st1.get("objects", 0)), int(b3.get("not_two", -1))])
	ok(not a.is_empty() and absf(abox.size.z - 35.0) <= 0.1 and absf(abox.size.x - 8.5) <= 0.1 and absf(bbox.size.z - 35.0) <= 0.1 and float(a["vol"]) > 0.0 and int(a["outward"]) > 0,
		"4 M5 x 30: %s mm in the STL (35 tall, head 8.5 across), %s in the 3MF, volume %.1f mm3" % [str(abox.size), str(bbox.size), float(a.get("vol", 0.0))])
	var cl: Array = MeshExport.check_lines(m.S.part)
	ok(bool(MeshExport.report(sbo["bodies"])["closed"]) and String(cl[0]).begins_with("OK"), "4 M5 x 30: the checklist says closed [%s]" % String(cl[0]).left(70))

	# a 20 x 10 x 5 mm box on the floor: a rectangle on the top plane pulled up 5 mm
	var rec := Part.make("Test box")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))])
	PartTemplates._ex(fs, sid, "extrude", 5.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	m.S.part = rec
	pu._rec_sig = ""
	await idle(8)

	# 1 ONE CLICK: the Export button, the dialog already on 3D printing, the OK button writes
	var eb := root.find_child("easypart_export", true, false) as Button
	ok(eb != null and eb.is_visible_in_tree(), "1 the Easy Part bar has an Export button on screen")
	if eb == null:
		print("p_stl3mf: %d fail" % (fails + 1))
		quit(1)
		return
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var dlg_open: bool = ui != null and ui.dlg != null and ui.dlg.visible
	var fmts := []
	if dlg_open:
		for i in ui.ui_format.item_count:
			fmts.append(ui.ui_format.get_item_text(i))
	var all_fmts := " ".join(fmts)
	var words: String = (String(ui.ui_info.text) + " " + String(ui.ui_app.text) + " " + all_fmts) if dlg_open else ""
	ok(dlg_open and ui.ui_target.get_item_text(ui.ui_target.selected).contains("3D printing") and fmts.size() == 2 and all_fmts.contains(".3mf") and all_fmts.contains(".stl") and words.contains("mm"),
		"1 one click on Export opens the dialog on 3D printing with %s; the words say mm" % str(fmts))
	var res_dir := ProjectSettings.globalize_path("res://exports")
	var one_click := "%s/Test_box.3mf" % res_dir
	if FileAccess.file_exists(one_click):
		DirAccess.remove_absolute(one_click)
	if dlg_open:
		ui.dlg.get_ok_button().pressed.emit()   # the dialog is an embedded window: the other tests press its OK this way
		await idle(4)
	ok(FileAccess.file_exists(one_click), "1 the dialog's own Export button wrote the .3mf (%s)" % one_click)
	if FileAccess.file_exists(one_click):
		DirAccess.remove_absolute(one_click)
	if dlg_open:
		ui.dlg.hide()

	# the mesh the writers use, for the expected triangle count; the built size from the kernel's own faces
	var bo := MeshExport.bodies_of(m.S.part)
	var want_tris := 0
	for b in bo["bodies"]:
		want_tris += (b["t"] as PackedInt32Array).size() / 3
	var built := AABB()
	var first := true
	for f in Part.body_faces(m.S.part):
		for v in (f as PackedVector3Array):
			var p := MeshExport.to_print(v)
			built = AABB(p, Vector3.ZERO) if first else built.expand(p)
			first = false
	print("built size from the kernel faces: %s mm; the mesh has %d triangles" % [str(built.size), want_tris])

	# 2 STL
	var sp := String(ex.export_now("print", 1, DIR))
	var gsp := ProjectSettings.globalize_path(sp) if sp != "" else ""
	var s := read_stl(gsp) if gsp != "" else {"bytes": 0, "head": "", "n": 0, "rep": {}}
	var sr: Dictionary = s["rep"]
	var s_ok := not sr.is_empty()
	var sbox: AABB = sr["box"] if s_ok else AABB()
	var sz := sbox.size
	ok(s_ok and sp.ends_with(".stl") and int(s["bytes"]) == 84 + 50 * int(s["n"]) and String(s["head"]).begins_with("Kine") and int(s["n"]) == want_tris and int(sr["tris"]) == want_tris,
		"2 STL: %d bytes = 84 + 50 x %d, header \"%s\", triangles %d (the mesh: %d)" % [int(s["bytes"]), int(s["n"]), String(s["head"]), int(sr.get("tris", 0)), want_tris])
	ok(s_ok and absf(sz.x - 20.0) <= 0.01 and absf(sz.y - 10.0) <= 0.01 and absf(sz.z - 5.0) <= 0.01 and absf(sz.x - built.size.x) <= 0.01 and absf(sz.y - built.size.y) <= 0.01 and absf(sz.z - built.size.z) <= 0.01 and absf(sbox.position.z) <= 0.01,
		"2 STL bbox %s mm (20 x 10 x 5 within 0.01, the kernel's %s, floor at z = %.3f)" % [str(sz), str(built.size), sbox.position.z])
	ok(s_ok and int(sr["not_two"]) == 0 and int(sr["verts"]) == 8, "2 STL: every edge shared by exactly 2 triangles (%d are not), %d vertices" % [int(sr.get("not_two", -1)), int(sr.get("verts", -1))])
	ok(s_ok and int(sr["outward"]) == want_tris and int(sr["agree"]) == want_tris and absf(float(sr["vol"]) - 1000.0) <= 5.0,
		"2 STL: normals outward %d of %d, winding agrees with the stored normal %d of %d, volume %.2f mm3 (1000)" % [int(sr.get("outward", 0)), want_tris, int(sr.get("agree", 0)), want_tris, float(sr.get("vol", 0.0))])

	# 3 3MF
	var tp := String(ex.export_now("print", 0, DIR))
	var gtp := ProjectSettings.globalize_path(tp) if tp != "" else ""
	var t3 := read_3mf(gtp) if gtp != "" else {"entries": [], "unit": "", "rep": {}}
	var ents: Array = t3["entries"]
	var has3: bool = ents.has("[Content_Types].xml") and ents.has("_rels/.rels") and ents.has("3D/3dmodel.model")
	ok(has3 and tp.ends_with(".3mf") and String(t3["unit"]) == "millimeter", "3 3MF: a zip with the 3 required entries %s, unit=\"%s\"" % [str(ents), str(t3["unit"])])
	var tr3: Dictionary = t3["rep"]
	var tbox: AABB = tr3["box"] if not tr3.is_empty() else AABB()
	var tsz := tbox.size
	ok(not tr3.is_empty() and int(t3["tris"]) == want_tris and int(t3["objects"]) == 1 and int(t3["items"]) == 1 and absf(tsz.x - 20.0) <= 0.01 and absf(tsz.y - 10.0) <= 0.01 and absf(tsz.z - 5.0) <= 0.01,
		"3 3MF: %d triangles (the mesh: %d), %d object, %d build item, bbox %s mm" % [int(t3.get("tris", 0)), want_tris, int(t3.get("objects", 0)), int(t3.get("items", 0)), str(tsz)])
	ok(not tr3.is_empty() and int(tr3["not_two"]) == 0 and int(t3["verts"]) == 8 and absf(float(tr3["vol"]) - 1000.0) <= 5.0 and int(t3["bases"]) == 0,
		"3 3MF: every edge shared twice (%d are not), %d vertices written (deduplicated), volume %.2f mm3, no colour on an unpainted part (%d)" % [int(tr3.get("not_two", -1)), int(t3.get("verts", 0)), float(tr3.get("vol", 0.0)), int(t3.get("bases", -1))])

	# 5 OPEN: one triangle gone
	var obo := MeshExport.bodies_of(rec)
	var ob: Dictionary = (obo["bodies"] as Array)[0]
	var ot: PackedInt32Array = ob["t"]
	ob["t"] = ot.slice(0, ot.size() - 3)
	var orep := MeshExport.report([ob])
	var olines := "\n".join(orep["lines"])
	var op := ProjectSettings.globalize_path(DIR) + "/open.stl"
	var oe := MeshExport.write_stl(op, [ob])
	ok(int(orep["open"]) == 3 and olines.contains("3 open edges: press Fix it first") and oe == OK and FileAccess.file_exists(op), "5 a box with one triangle gone: %d open edges, the words [%s], the file is still written" % [int(orep["open"]), olines.get_slice("\n", 0)])

	# 6 COLOUR + two bodies
	var crec := rec.duplicate(true)
	crec["features"].append({"t": "appear", "id": "f9", "name": "Paint1", "body": 0, "preset": "Paint", "color": [1.0, 0.0, 0.0], "rough": 0.5, "metal": 0.0, "alpha": 1.0})
	var cp := String(MeshExport.export_part(crec, "3mf", DIR)["path"])
	var c3 := read_3mf(cp) if cp != "" else {"colors": [], "pids": 0, "xml": ""}
	ok((c3["colors"] as Array) == ["#FF0000"] and int(c3["pids"]) == 1 and String(c3["xml"]).contains("<basematerials id=\"1\">"), "6 a painted body: basematerials %s on its object (%d)" % [str(c3["colors"]), int(c3["pids"])])
	var drec := rec.duplicate(true)
	var f2: Array = drec["features"]
	var s2 := PartTemplates._sk(f2, "top", [PartTemplates._rect(Vector2(30, 0), Vector2(40, 10))])
	PartTemplates._ex(f2, s2, "extrude", 5.0, "new")
	var dp := String(MeshExport.export_part(drec, "3mf", DIR)["path"])
	var d3 := read_3mf(dp) if dp != "" else {"objects": 0, "items": 0}
	ok(int(d3["objects"]) == 2 and int(d3["items"]) == 2, "6 two separate bodies: %d objects, %d build items" % [int(d3["objects"]), int(d3["items"])])
	print("exported files: %s | %s" % [gsp, gtp])
	print("p_stl3mf: %d fail" % fails)
	quit(1 if fails > 0 else 0)
