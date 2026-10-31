extends SceneTree
## godot --path . --position 4000,4000 -s tests/s116_test.gd     (SVG + DXF of a flat face for laser cutting; scripts/build/laser_export.gd + scripts/export_dialog.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720: BUILDING card, the Easy Part bar's Export button, the dialog's Export button). A 100 x 50 x 5 mm plate with a 20 mm hole.
## Every number is read back from the WRITTEN FILES (re-read from disk and parsed), never from the writer's variables.
##   1 DIALOG  the dialog has a Laser cutting target (the seven engine targets are still seven) with SVG and DXF formats and a Face list, all "mm"
##   2 SVG     width/height in mm, viewBox in mm, outer path bbox 100 x 50 within 0.01, ONE inner loop with area pi*10^2 within 1 pct, centred
##   3 DXF     R12 header with $INSUNITS 4; the same bbox from its LINEs, one CIRCLE r = 10 within 0.01 at the centre
##   4 FACES   Front of the plate is 100 x 5 mm with no hole; Bottom is the plate with the hole again
##   5 CURVED  a cylinder lying down: its Top is not flat and the words say so, no file; its largest flat face is a round end written as one circle
const DIR := "user://zz_s116"
const DIRT := "user://zz_s116_scenes"
const SHOT := "C:/Temp/claude/s116"
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


## points of a path d="M x y L x y ... Z"
func path_pts(d: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var toks := d.replace("M", " ").replace("L", " ").replace("Z", " ").split(" ", false)
	for i in range(0, toks.size() - 1, 2):
		out.append(Vector2(float(toks[i]), float(toks[i + 1])))
	return out


func area_of(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].x * p[(i + 1) % p.size()].y - p[(i + 1) % p.size()].x * p[i].y
	return absf(s) * 0.5


func box_of(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


func read_svg(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var out := {"w": "", "h": "", "vb": "", "paths": []}
	var xp := XMLParser.new()
	xp.open_buffer(txt.to_utf8_buffer())
	while xp.read() != ERR_FILE_EOF:
		if xp.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match xp.get_node_name():
			"svg":
				out["w"] = xp.get_named_attribute_value_safe("width")
				out["h"] = xp.get_named_attribute_value_safe("height")
				out["vb"] = xp.get_named_attribute_value_safe("viewBox")
			"path":
				out["paths"].append({"id": xp.get_named_attribute_value_safe("id"), "pts": path_pts(xp.get_named_attribute_value_safe("d"))})
	return out


## the DXF's group-code/value pairs -> header words, LINEs and CIRCLEs
func read_dxf(path: String) -> Dictionary:
	var rows := FileAccess.get_file_as_string(path).split("\n")
	var out := {"acad": "", "units": "", "lines": [], "circles": [], "eof": false}
	var ents := []
	var i := 0
	var cur := {}
	var prev_var := ""
	while i + 1 < rows.size():
		var code := int(rows[i].strip_edges())
		var val := rows[i + 1].strip_edges()
		i += 2
		if code == 9:
			prev_var = val
		elif code == 1 and prev_var == "$ACADVER":
			out["acad"] = val
		elif code == 70 and prev_var == "$INSUNITS":
			out["units"] = val
			prev_var = ""
		if code == 0:
			if not cur.is_empty():
				ents.append(cur)
			cur = {"type": val}
			if val == "EOF":
				out["eof"] = true
		else:
			cur[code] = val
	for e in ents:
		if e["type"] == "LINE":
			out["lines"].append([Vector2(float(e[10]), float(e[20])), Vector2(float(e[11]), float(e[21]))])
		elif e["type"] == "CIRCLE":
			out["circles"].append([Vector2(float(e[10]), float(e[20])), float(e[40])])
	return out


func plate() -> Dictionary:
	var rec := Part.make("Plate")
	var fs: Array = rec["features"]
	var s1 := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(100, 50))])
	PartTemplates._ex(fs, s1, "extrude", 5.0, "new")
	var s2 := PartTemplates._sk(fs, "top", [{"k": "circle", "c": [50.0, 25.0], "r": 10.0}])
	PartTemplates._ex(fs, s2, "extrude", 20.0, "cut", true)
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


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
	m.S.part = plate()
	pu._rec_sig = ""
	await idle(8)

	# 1 DIALOG
	var eb := root.find_child("easypart_export", true, false) as Button
	if eb == null or not eb.is_visible_in_tree():
		print("FAIL 1 no Export button")
		print("s116: %d fail" % (fails + 1))
		quit(1)
		return
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var li := -1
	for i in ui.ui_target.item_count:
		if ui.ui_target.get_item_text(i).contains("Laser"):
			li = i
	# integ96: 7 engine targets + Laser cutting + CAD program (STEP, s115) + 3D printing = 10
	ok(ExportDialog.targets().size() == 7 and li >= 0 and ui.ui_target.item_count == 10 and ui.ui_target.get_item_text(ui.ui_target.selected).contains("3D printing"),
		"1 seven engine targets, the list with a part is %d (Laser cutting at %d), the Export button still lands on 3D printing" % [ui.ui_target.item_count, li])
	ui.ui_target.select(li)
	ui._on_target(li)
	await idle(3)
	var fmts := []
	for i in ui.ui_format.item_count:
		fmts.append(ui.ui_format.get_item_text(i))
	var words := " ".join(fmts) + " " + ui.ui_info.text + " " + ui.ui_app.text
	ok(ui.ui_face_row.visible and ui.ui_face.item_count >= 6 and fmts.size() == 2 and words.contains(".svg") and words.contains(".dxf") and words.contains("millimetres"),
		"1 Laser cutting shows the Face list (%d choices) and formats %s, the words say millimetres" % [ui.ui_face.item_count, str(fmts)])
	await shot("dialog_laser")
	var one := ProjectSettings.globalize_path("res://exports") + "/Plate_Largest_flat_face.svg"
	if FileAccess.file_exists(one):
		DirAccess.remove_absolute(one)
	ui.dlg.get_ok_button().pressed.emit()
	await idle(4)
	ok(FileAccess.file_exists(one), "1 the dialog's own Export button wrote %s" % one)
	if FileAccess.file_exists(one):
		DirAccess.remove_absolute(one)
	ui.dlg.hide()
	var ex := ExportDialog.new(m)

	# 2 SVG (the Top face)
	var sp := String(ex.export_now("laser", 0, DIR, 1))
	var g := ProjectSettings.globalize_path(sp) if sp != "" else ""
	var sv := read_svg(g) if g != "" else {"w": "", "h": "", "vb": "", "paths": []}
	var ps: Array = sv["paths"]
	ok(String(sv["w"]) == "100.0000mm" and String(sv["h"]) == "50.0000mm" and String(sv["vb"]) == "0 0 100.0000 50.0000", "2 SVG size %s x %s, viewBox \"%s\"" % [sv["w"], sv["h"], sv["vb"]])
	var ob := Rect2()
	var holes := 0
	var harea := 0.0
	var hbox := Rect2()
	for p in ps:
		if String(p["id"]) == "outer":
			ob = box_of(p["pts"])
		else:
			holes += 1
			harea = area_of(p["pts"])
			hbox = box_of(p["pts"])
	ok(ps.size() == 2 and absf(ob.size.x - 100.0) <= 0.01 and absf(ob.size.y - 50.0) <= 0.01, "2 SVG outer path bbox %s mm (100 x 50 within 0.01), %d paths" % [str(ob.size), ps.size()])
	ok(holes == 1 and absf(harea - PI * 100.0) <= PI, "2 SVG: %d inner loop, area %.2f mm2 (pi x 10^2 = %.2f, within 1 pct)" % [holes, harea, PI * 100.0])
	ok(hbox.get_center().distance_to(Vector2(50, 25)) <= 0.05, "2 SVG hole centre %s (50, 25)" % str(hbox.get_center()))

	# 3 DXF
	var dp := String(ex.export_now("laser", 1, DIR, 1))
	var dx := read_dxf(ProjectSettings.globalize_path(dp)) if dp != "" else {"acad": "", "units": "", "lines": [], "circles": [], "eof": false}
	ok(String(dx["acad"]) == "AC1009" and String(dx["units"]) == "4" and bool(dx["eof"]), "3 DXF header: version %s (R12), $INSUNITS %s (mm), ends with EOF" % [dx["acad"], dx["units"]])
	var pts := PackedVector2Array()
	for l in dx["lines"]:
		pts.append(l[0])
		pts.append(l[1])
	var db := box_of(pts) if pts.size() > 0 else Rect2()
	ok(dx["lines"].size() == 4 and absf(db.size.x - 100.0) <= 0.01 and absf(db.size.y - 50.0) <= 0.01, "3 DXF: %d LINEs, bbox %s mm (100 x 50 within 0.01)" % [dx["lines"].size(), str(db.size)])
	var cc: Array = dx["circles"]
	ok(cc.size() == 1 and absf(float(cc[0][1]) - 10.0) <= 0.01 and absf(PI * float(cc[0][1]) * float(cc[0][1]) - PI * 100.0) <= PI and (cc[0][0] as Vector2).distance_to(Vector2(50, 25)) <= 0.05,
		"3 DXF: %d CIRCLE, r = %s at %s (r 10 at 50, 25)" % [cc.size(), str(cc[0][1]) if cc.size() > 0 else "-", str(cc[0][0]) if cc.size() > 0 else "-"])

	# 4 FACES
	var fp := String(ex.export_now("laser", 0, DIR, 3))   # Front
	var fv := read_svg(ProjectSettings.globalize_path(fp)) if fp != "" else {"paths": []}
	var fb := box_of(fv["paths"][0]["pts"]) if fv["paths"].size() > 0 else Rect2()
	ok(fv["paths"].size() == 1 and absf(fb.size.x - 100.0) <= 0.01 and absf(fb.size.y - 5.0) <= 0.01, "4 Front: %d path, %s mm (100 x 5, no hole)" % [fv["paths"].size(), str(fb.size)])
	var bp := String(ex.export_now("laser", 0, DIR, 2))   # Bottom
	var bv := read_svg(ProjectSettings.globalize_path(bp)) if bp != "" else {"paths": []}
	var bb := box_of(bv["paths"][0]["pts"]) if bv["paths"].size() > 0 else Rect2()
	ok(bv["paths"].size() == 2 and absf(bb.size.x - 100.0) <= 0.01 and absf(bb.size.y - 50.0) <= 0.01, "4 Bottom: %d paths, %s mm (the plate and its hole)" % [bv["paths"].size(), str(bb.size)])

	# 5 CURVED: a cylinder lying down (the front plane's normal is the printer's y)
	var rec := Part.make("Roller")
	var fs: Array = rec["features"]
	var s1 := PartTemplates._sk(fs, "front", [{"k": "circle", "c": [0.0, 10.0], "r": 10.0}])
	PartTemplates._ex(fs, s1, "extrude", 30.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	m.S.part = rec
	pu._rec_sig = ""
	await idle(8)
	var ol_top := LaserExport.outline(rec, 1)
	var ol_big := LaserExport.outline(rec, 0)
	var tp := String(ex.export_now("laser", 0, DIR, 1))
	var tsay := String(ol_top["why"])
	ok(not bool(ol_top["ok"]) and tp == "" and tsay.contains("not flat") and tsay.contains("top"), "5 Roller top: [%s], no file written" % tsay)
	var rr := -1.0
	if bool(ol_big["ok"]) and (ol_big["loops"] as Array).size() == 1:
		rr = float((ol_big["loops"][0]["circle"] as Dictionary).get("r", -1.0))
	ok(rr > 0.0 and absf(rr - 10.0) <= 0.01, "5 Roller largest flat face: a round end, one circle r = %s" % str(rr))
	var rp := String(ex.export_now("laser", 1, DIR, 0))
	var rd := read_dxf(ProjectSettings.globalize_path(rp)) if rp != "" else {"circles": [], "lines": []}
	ok(rd["circles"].size() == 1 and rd["lines"].size() == 0 and absf(float(rd["circles"][0][1]) - 10.0) <= 0.01, "5 the round end in a DXF: %d CIRCLE, %d LINEs" % [rd["circles"].size(), rd["lines"].size()])
	var ck := LaserExport.check_lines(rec, 1)
	ok(String(ck[0]).begins_with("WARN") and String(ck[0]).contains("not flat"), "5 the dialog checklist says [%s]" % String(ck[0]).left(90))

	# screenshot of the dialog on a curved Top, then on the plate
	await click_ctl(root.find_child("easypart_export", true, false) as Button)
	await idle(4)
	ui.ui_target.select(li)
	ui._on_target(li)
	ui.ui_face.select(1)
	ui._refresh()
	await shot("dialog_curved_top")
	ui.dlg.hide()
	print("exported: %s | %s" % [g, ProjectSettings.globalize_path(dp)])
	print("s116: %d fail" % fails)
	quit(1 if fails > 0 else 0)
