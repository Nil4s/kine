## godot --headless --path . -s tests/deliverwalk_test.gd   (DELIVER walk: the chair part and a posed fighter, as OBJ and GLB)
## Bars (written before the change was run on the old code):
##   (a) the chair set piece, picked and written as OBJ (export dialog, format Wavefront OBJ, Only the selected object): its
##       file holds the chair own vertices (v lines) and triangles (f lines), and re-imports (ObjIO) at the chair real size
##   (b) the chair as GLB (Only the selected object): read back by GLTFDocument, the vertices, triangles and size match the chair
##   (c) the posed fighter as OBJ (Everything, at the playhead): v lines == the body vertices, f lines == its triangles,
##       re-imports at the body size (within 2 mm per axis)
##   (d) GUARD: the GLB Everything still writes the old writer bytes (_export_glb called directly)
## Real clicks: the DELIVER page tab and the Export... button. Scripted: the chair set piece (_prop_add), the dialog format and
## What to export choices (OptionButton select), and the write goes to user:// (export_now), never res://exports.
## The files are removed at the end.
extends SceneTree

var fails := 0
const DIR := "user://zz_deliverwalk"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


## a real click at the centre of a visible control
func click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame
	btn(true, p)
	await process_frame
	btn(false, p)
	await idle(4)


## the ribbon buttons are icon-only: a visible button by its tooltip (the command name the ribbon shows)
func find_visible_button(tip_start: String) -> Button:
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var tt := (n as Button).tooltip_text if n is Button else ""
		if n is Button and (n as Button).is_visible_in_tree() and (tt == tip_start or tt.begins_with(tip_start + "\n")):
			return n
		stack.append_array(n.get_children(true))
	return null


## the vertices, triangles and size of one OBJ file: its own v and f lines (read as text, not by the importer)
static func obj_lines(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	var v := 0
	var f := 0
	for line in txt.split("\n"):
		if line.begins_with("v "):
			v += 1
		elif line.begins_with("f "):
			f += 1
	var meshes := ObjIO.import_file(path)
	var box := AABB()
	var tris := 0
	for i in meshes.size():
		var am: ArrayMesh = meshes[i]["mesh"]
		box = am.get_aabb() if i == 0 else box.merge(am.get_aabb())
		tris += ObjIO.counts(am).x
	return {"v": v, "f": f, "tris": tris, "size": box.size, "groups": meshes.size()}


## the vertices, triangles and size of one GLB file, read back by the GLTFDocument of Godot
static func glb_counts(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return {"ok": false, "verts": 0, "tris": 0, "size": Vector3.ZERO, "meshes": 0}
	var verts := 0
	var tris := 0
	var box := AABB()
	var first := true
	for gm in st.get_meshes():
		var am: ArrayMesh = (gm as GLTFMesh).get_mesh().get_mesh()
		var c := ObjIO.counts(am)
		verts += c.y
		tris += c.x
		box = am.get_aabb() if first else box.merge(am.get_aabb())
		first = false
	return {"ok": true, "verts": verts, "tris": tris, "size": box.size, "meshes": st.get_meshes().size()}


## the vertices, triangles and size of in-memory meshes (the scene objects, by name)
static func mem_counts(objs: Array) -> Dictionary:
	var verts := 0
	var tris := 0
	var box := AABB()
	for i in objs.size():
		var am: ArrayMesh = objs[i]["mesh"]
		var c := ObjIO.counts(am)
		verts += c.y
		tris += c.x
		box = am.get_aabb() if i == 0 else box.merge(am.get_aabb())
	return {"verts": verts, "tris": tris, "size": box.size}


func clean(d: String) -> void:
	var g := ProjectSettings.globalize_path(d)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


func _init() -> void:
	clean(DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/old"))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(1280, 720)   # pinned 1280 x 720 (as walk6): the screen every run reads
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(6)
	m.easy.set_on(false, false)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._prop_add("chair")   # the chair set piece, in front of the body
	await idle(3)
	m.sel_prop = m.S.props.size() - 1

	# real clicks: the DELIVER tab, then Export...
	await click(m.ui_page_btns["DELIVER"])
	var ex := find_visible_button("Export...")
	ok(ex != null, "DELIVER page: the Export... button is on screen")
	if ex != null:
		await click(ex)
	await idle(3)
	var ui = m.export_ui
	ok(ui != null and ui.dlg != null and ui.dlg.visible, "Export... (a real click) opens the export dialog")
	if ui == null or ui.dlg == null:
		print("deliverwalk: %d FAIL" % (fails + 1))
		quit(1)
		return
	# the Web target (its format list has the glTF and, from this change, the OBJ); the dialog's own target menu, chosen
	var web_ti := -1
	for i in ExportDialog.targets().size():
		if String((ExportDialog.targets()[i] as Dictionary)["id"]) == "web":
			web_ti = i
	ui.ui_target.select(web_ti)
	ui._on_target(web_ti)
	await idle(2)

	var body_mem := {}
	var chair_mem := {}
	for o in m.scene_objects():
		if String(o["name"]) == "body":
			body_mem = mem_counts([o])
		if String(o["name"]) == "chair":
			chair_mem = mem_counts([o])
	print("in memory: body %s, chair %s" % [str(body_mem), str(chair_mem)])

	# (a) the chair as OBJ: the dialog format, the one selected object
	var obj_fi := -1
	for i in ui.ui_format.item_count:
		if ui.ui_format.get_item_text(i).contains(".obj"):
			obj_fi = i
	ok(obj_fi >= 0, "the export dialog offers a Wavefront OBJ format for the web target")
	if obj_fi >= 0:
		ui.ui_format.select(obj_fi)
		ui.ui_what.select(1)
		var pa = ui.export_now("web", obj_fi, DIR, 1)
		var got_a := String(pa) if pa is String else ""
		var ra := obj_lines(got_a) if got_a != "" else {"v": 0, "f": 0, "tris": 0, "size": Vector3.ZERO, "groups": 0}
		var sz_ok: bool = got_a != "" and (ra["size"] as Vector3).distance_to(chair_mem["size"]) < 0.002
		ok(got_a.get_file() == "chair.obj" and int(ra["v"]) == int(chair_mem["verts"]) and int(ra["f"]) == int(chair_mem["tris"]) and sz_ok,
			"(a) the chair as OBJ (%s): %d v, %d f, size %s (the chair: %d verts, %d tris, size %s)" % [got_a.get_file(), int(ra["v"]), int(ra["f"]), str(ra["size"]), int(chair_mem["verts"]), int(chair_mem["tris"]), str(chair_mem["size"])])

	# (b) the chair as GLB, the same one object
	ui.ui_format.select(0)
	ui.ui_what.select(1)
	var pb = ui.export_now("web", 0, DIR, 1)
	var got_b := String(pb) if pb is String else ""
	var rb := glb_counts(got_b) if got_b != "" else {"ok": false, "verts": 0, "tris": 0, "size": Vector3.ZERO}
	ok(bool(rb["ok"]) and int(rb["verts"]) == int(chair_mem["verts"]) and int(rb["tris"]) == int(chair_mem["tris"]) and (rb["size"] as Vector3).distance_to(chair_mem["size"]) < 0.002,
		"(b) the chair as GLB (%s): %d verts, %d tris, size %s (the chair: %d, %d, %s)" % [got_b.get_file(), int(rb["verts"]), int(rb["tris"]), str(rb["size"]), int(chair_mem["verts"]), int(chair_mem["tris"]), str(chair_mem["size"])])

	# (c) the posed fighter as OBJ (Everything, at the playhead): the body is measured here, after the frames have settled,
	# the same moment the file is written
	await idle(6)
	body_mem = {}
	for o in m.scene_objects():
		if String(o["name"]) == "body":
			body_mem = mem_counts([o])
	var fi_c := obj_fi if obj_fi >= 0 else 0
	ui.ui_format.select(fi_c)
	ui.ui_what.select(0)
	var pc = ui.export_now("web", fi_c, DIR, 0)
	var got_c := String(pc) if pc is String else ""
	var rc := obj_lines(got_c) if got_c != "" else {"v": 0, "f": 0, "tris": 0, "size": Vector3.ZERO}
	var bsz_ok: bool = got_c != "" and (rc["size"] as Vector3).distance_to(body_mem["size"]) < 0.002
	ok(int(rc["v"]) == int(body_mem["verts"]) and int(rc["f"]) == int(body_mem["tris"]) and bsz_ok,
		"(c) the posed fighter as OBJ (%s): %d v, %d f, size %s (the body: %d verts, %d tris, size %s)" % [got_c.get_file(), int(rc["v"]), int(rc["f"]), str(rc["size"]), int(body_mem["verts"]), int(body_mem["tris"]), str(body_mem["size"])])

	# (d) GUARD: Everything as GLB is the old writer file, byte for byte
	var old_path: String = m._export_glb(DIR + "/old")
	var got_d = ui.export_now("web", 0, DIR)
	ok(String(got_d) != "" and FileAccess.get_sha256(ProjectSettings.globalize_path(old_path)) == FileAccess.get_sha256(ProjectSettings.globalize_path(String(got_d))),
		"(d) GUARD: Everything as GLB is the old writer bytes")

	clean(DIR + "/old")
	clean(DIR)
	print("deliverwalk: %d FAIL" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
