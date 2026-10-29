extends SceneTree
## FEXPORT (Nick 2026-10-28: "free 3D building, like Fusion 360, make a part and export it"): a beginner from the real start screen at
## 1280x720, real clicks: the BUILDING card (one click) -> an empty Easy Part -> Draw shape, a drag on the grid, Pull it up -> the DELIVER
## tab -> Export... -> the export dialog lists the part -> OBJ and GLB written to user:// and read back. Sizes are checked in mm.
## Bars (run on the old code before the change; see the report for which failed):
##   0 the BUILDING card, one click: page BUILD, Easy Part on, no chooser
##   1 Draw shape, a drag, Pull it up: one body on the part
##   2a the Easy Part bar has an Export button; 2b it opens the export dialog (real clicks; a dead end on the old code)
##   2d the dialog opens on Only the selected object (the part)
##   3 the export dialog object list names the part (what the export will write)
##   4 OBJ (the dialog's What to export): the file exists in user, its f count > 0, its size equals the part size within 0.5 mm
##   5 GLB: the same, read back by GLTFDocument
##   6 the exported part is a real size: each axis between 1 mm and 5 m
## shots: C:/Temp/claude/fexport/*.png
const SHOT := "C:/Temp/claude/fexport"
const DIR := "user://zz_fexport"

var fails := 0
var m: Node


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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func find_visible_button(tip_start: String) -> Button:
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var tt := (n as Button).tooltip_text if n is Button else ""
		if n is Button and (n as Button).is_visible_in_tree() and (tt == tip_start or tt.begins_with(tip_start + "\n")):
			return n
		stack.append_array(n.get_children(true))
	return null


## the OBJ's own f lines (text), its size (the importer's bounds, metres)
static func obj_info(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	var f := 0
	for line in txt.split("\n"):
		if line.begins_with("f "):
			f += 1
	var meshes := ObjIO.import_file(path)
	var box := AABB()
	for i in meshes.size():
		var am: ArrayMesh = meshes[i]["mesh"]
		box = am.get_aabb() if i == 0 else box.merge(am.get_aabb())
	return {"f": f, "size": box.size}


static func glb_info(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return {"ok": false, "f": 0, "size": Vector3.ZERO}
	var f := 0
	var box := AABB()
	var first := true
	for gm in st.get_meshes():
		var am: ArrayMesh = (gm as GLTFMesh).get_mesh().get_mesh()
		f += ObjIO.counts(am).x
		box = am.get_aabb() if first else box.merge(am.get_aabb())
		first = false
	return {"ok": true, "f": f, "size": box.size}


func clean(d: String) -> void:
	var g := ProjectSettings.globalize_path(d)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


func _bar_button(t: String) -> Button:
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text.strip_edges() == t:
			return n
		stack.append_array(n.get_children(true))
	return null


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func _init() -> void:
	clean(DIR)
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	ss.dirs_override = [DIR]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open,
		"0 BUILDING card, one click -> Easy Part on, page BUILD, no chooser (page %s)" % m.cur_page)
	await shot("open")

	# 1 Draw shape, a drag on the grid, Pull it up
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.05, 0.0, -0.04)), scr(Vector3(0.05, 0.0, 0.04)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	var bodies := int(pu().res.get("bodies", 0))
	ok(bodies == 1, "1 Draw shape, a drag, Pull it up: one body (bodies %d)" % bodies)
	await shot("part")
	var pmesh: ArrayMesh = pu().part_mesh.mesh as ArrayMesh if pu().part_mesh != null else null
	var psize := pmesh.get_aabb().size if pmesh != null else Vector3.ZERO
	print("part mesh: %s m (%s mm)" % [str(psize), str(psize / Part.MM)])

	# 2 Export from the part itself: a beginner on the Easy Part bar looks for Export (a real click on it). Dead end: the Easy bar
	# hides the page tabs, so the DELIVER tab is not on screen while Easy Part is on. The fallback (Expert, DELIVER, Export...) is
	# walked after, so the bars below still measure the file.
	var ebtn := _bar_button("Export")
	ok(ebtn != null, "2a the Easy Part bar has an Export button (visible)")
	var ui = m.export_ui
	if ebtn != null:
		await click_ctl(ebtn)
		await idle(4)
	var dlg_open: bool = ui != null and ui.dlg != null and ui.dlg.visible
	if not dlg_open:
		ui = m.export_ui
		dlg_open = ui != null and ui.dlg != null and ui.dlg.visible
	ok(dlg_open, "2b the Export button opens the export dialog (a real click)")
	if not dlg_open:
		await click_ctl(pu().ep.expert_btn)
		await idle(8)
		var dtab: Button = m.ui_page_btns["DELIVER"]
		ok(dtab.is_visible_in_tree(), "2c (fallback) after Expert the DELIVER tab is on screen")
		await click_ctl(dtab)
		await idle(6)
		var ex := find_visible_button("Export...")
		if ex != null:
			await click_ctl(ex)
		await idle(4)
		ui = m.export_ui
		dlg_open = ui != null and ui.dlg != null and ui.dlg.visible
	await shot("export_dialog")
	var what_sel: int = ui.ui_what.selected if dlg_open else 0
	ok(what_sel == 1, "2d the dialog opens on Only the selected object (the part), not Everything (what %d: %s)" % [what_sel, ui.ui_what.get_item_text(what_sel) if dlg_open else ""])
	if not dlg_open:
		print("fexport: %d FAIL" % fails)
		clean(DIR)
		quit(1)
		return

	# 3 the object list names the part
	var pname := String(m.S.part.get("name", ""))
	var objs_txt := String(ui.ui_objects.text)
	ok(pname != "" and objs_txt.find(pname) >= 0, "3 the export dialog lists the part \"%s\" (list: %s)" % [pname, objs_txt.get_slice(".", 0)])

	# KNOWN dead ends (printed, not counted: fixes not made in this change)
	var dflt := String(ui.ui_target.get_item_text(ui.ui_target.selected))
	var chk := String(ui.ui_checks.text)
	print("KNOWN dead end: the dialog opens on target \"%s\" (the default); a static part there says no animation yet: %s" % [dflt, "yes" if chk.find("no animation") >= 0 else "not seen"])
	print("KNOWN dead end: the object list says \"body\" (a fighter nobody made) beside the part: %s" % [str(String(ui.ui_objects.text).contains("body"))])

	# 4 / 5 the files (web target)
	var web_ti := -1
	for i in ExportDialog.targets().size():
		if String((ExportDialog.targets()[i] as Dictionary)["id"]) == "web":
			web_ti = i
	ui.ui_target.select(web_ti)
	ui._on_target(web_ti)
	await idle(2)
	var obj_fi := -1
	for i in ui.ui_format.item_count:
		if ui.ui_format.get_item_text(i).contains(".obj"):
			obj_fi = i
	var got_o = ui.export_now("web", obj_fi, DIR, what_sel) if obj_fi >= 0 else ""
	var po := String(got_o) if got_o is String else ""
	var oi := obj_info(po) if po != "" else {"f": 0, "size": Vector3.ZERO}
	var osz_ok: bool = po != "" and (oi["size"] as Vector3).distance_to(psize) < 0.0005
	ok(po != "" and FileAccess.file_exists(ProjectSettings.globalize_path(po)) and int(oi["f"]) > 0 and osz_ok,
		"4 OBJ written (%s): %d f, size %s mm (the part: %s mm)" % [po.get_file(), int(oi["f"]), str((oi["size"] as Vector3) / Part.MM), str(psize / Part.MM)])

	var got_g = ui.export_now("web", 0, DIR, what_sel)
	var pg := String(got_g) if got_g is String else ""
	var gi := glb_info(pg) if pg != "" else {"ok": false, "f": 0, "size": Vector3.ZERO}
	var gsz_ok: bool = bool(gi["ok"]) and (gi["size"] as Vector3).distance_to(psize) < 0.0005
	print("KNOWN dead end: OBJ is named %s, the GLB %s (the OBJ replaces the space)" % [po.get_file(), pg.get_file()])
	ok(bool(gi["ok"]) and int(gi["f"]) > 0 and gsz_ok,
		"5 GLB written (%s): %d f, size %s mm (the part: %s mm)" % [pg.get_file(), int(gi["f"]), str((gi["size"] as Vector3) / Part.MM), str(psize / Part.MM)])

	# 6 a real size
	var s := (oi["size"] as Vector3)
	var real: bool = s.x >= 0.001 and s.y >= 0.001 and s.z >= 0.001 and s.x <= 5.0 and s.y <= 5.0 and s.z <= 5.0
	ok(real, "6 the exported part is a real size in mm (%s mm)" % str(s / Part.MM))

	clean(DIR)
	print("fexport: %d FAIL" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
