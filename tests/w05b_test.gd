extends SceneTree
## godot --path . --position 4000,4000 -s tests/w05b_test.gd     (W05b: the checklist triangle count, Split to fit, OBJ and GLB follow the chosen mesh quality)
## Bars, written before any number was seen. A cylinder r = 10 mm, 20 tall:
##   1 CHECKLIST  the triangle count in the dialog's checklist equals the written STL's, at Coarse and at Fine (and Fine > Coarse)
##   2 SPLIT      Split to fit (bed 15 x 15 x 40): the pieces' total triangles at Fine > at Coarse, and the cut still happens (>1 file)
##   3 OBJ / GLB  the part's OBJ and GLB (Only the selected object) at Fine have more triangles than at Coarse
##   4 NORMAL     OBJ at Normal has the very triangles it always had
## Controls: the old checklist call (no quality) at Fine does not equal the Fine file, so bar 1 can fail.
const DIR := "user://zz_w05b"
const DIRT := "user://zz_w05b_scenes"
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


func stl_n(path: String) -> int:
	return FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).decode_u32(80)


func check_tris(ui: ExportDialog) -> int:
	for l in ui.checks("print", "stl"):
		var s := String(l)
		var a := s.find("(")
		if s.contains(" triangles)") and a >= 0:
			return int(s.substr(a + 1))
	return -1


func obj_tris(path: String) -> int:
	var n := 0
	for l in FileAccess.get_file_as_string(ProjectSettings.globalize_path(path)).split(String.chr(10)):
		if l.begins_with("f "):
			n += maxi(1, l.strip_edges().split(" ").size() - 3)
	return n


func glb_tris(path: String) -> int:
	var d := GLTFDocument.new()
	var st := GLTFState.new()
	if d.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return -1
	var nd := d.generate_scene(st)
	var n := 0
	for c in nd.find_children("*", "MeshInstance3D", true, false):
		n += ExportBudget.tris_of((c as MeshInstance3D).mesh)
	nd.free()
	return n


func fi_of(ui: ExportDialog, id: String, run: String) -> int:
	var fs: Array = (ui.target(id)["formats"] as Array)
	for i in fs.size():
		if String((fs[i] as Dictionary)["run"]) == run:
			return i
	return -1


func pick(ui: ExportDialog, q: String) -> void:
	var i := MeshQuality.NAMES.find(q)
	ui.ui_q.select(i)
	ui.ui_q.item_selected.emit(i)
	await idle(2)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var ss: StartScreen = m.start_screen
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
	var rec := Part.make("Cyl")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [{"k": "circle", "c": Part.arr2(Vector2.ZERO), "r": 10.0}])
	PartTemplates._ex(fs, sid, "extrude", 20.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	m.S.part = rec
	pu._rec_sig = ""
	await idle(8)
	pu._rec_sig = ""
	pu._rebuild(true)
	await idle(4)
	await click_ctl(root.find_child("easypart_export", true, false) as Button)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	ok(ui != null and ui.dlg.visible, "the export dialog is open")
	var stl_i := fi_of(ui, "print", "stl")
	var T := {}
	for q in ["Coarse", "Normal", "Fine"]:
		await pick(ui, q)
		ui.split_fit = false
		var ck := check_tris(ui)
		var p := String(ui.export_now("print", stl_i, DIR))
		var n := stl_n(p)
		T[q] = {"ck": ck, "stl": n}
		ok(ck == n and n > 0, "1 %s: checklist says %d triangles, the STL holds %d" % [q, ck, n])
		var old := -1
		for l in MeshExport.check_lines(m.S.part):
			var s := String(l)
			if s.contains(" triangles)"):
				old = int(s.substr(s.find("(") + 1))
		T[q]["old"] = old
	ok(int(T["Fine"]["stl"]) > int(T["Coarse"]["stl"]), "1 Fine %d > Coarse %d" % [T["Fine"]["stl"], T["Coarse"]["stl"]])
	ok(int(T["Fine"]["old"]) != int(T["Fine"]["stl"]), "control: the old checklist (no quality) says %d at Fine, the file holds %d: bar 1 can fail" % [T["Fine"]["old"], T["Fine"]["stl"]])
	# 2 split
	ui.bed_mm = Vector3(15, 15, 40)
	ui.split_fit = true
	var sp := {}
	for q in ["Coarse", "Fine"]:
		await pick(ui, q)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/sp_" + q))
		var r := PrintSplit.export_part(m.S.part, "stl", ProjectSettings.globalize_path(DIR + "/sp_" + q), ui.bed_mm, ui.quality())
		var tot := 0
		for p2 in r["paths"]:
			tot += stl_n(String(p2))
		sp[q] = {"tot": tot, "files": (r["paths"] as Array).size(), "split": r["split"]}
		print("split ", q, " ", sp[q])
	ok(bool(sp["Coarse"]["split"]) and bool(sp["Fine"]["split"]) and int(sp["Coarse"]["files"]) > 1, "2 the part is cut at both qualities (%d / %d files)" % [sp["Coarse"]["files"], sp["Fine"]["files"]])
	ok(int(sp["Fine"]["tot"]) > int(sp["Coarse"]["tot"]) and int(sp["Coarse"]["tot"]) > 0, "2 Split to fit: Fine %d triangles > Coarse %d" % [sp["Fine"]["tot"], sp["Coarse"]["tot"]])
	ui.split_fit = false
	# 3 obj / glb
	print("fpo ", m.bld.part.on, " ", m.bld.part.part_mesh != null and m.bld.part.part_mesh.mesh != null, " ", m.scene_objects().map(func(o): return o["name"]))
	ui.ui_what.select(1)
	ui.ui_what.item_selected.emit(1)
	await idle(2)
	var oid := ""
	for t in ui._tg():
		for f in (t as Dictionary)["formats"]:
			if String((f as Dictionary)["run"]) == "obj" and oid == "":
				oid = String((t as Dictionary)["id"])
	var obj_i := fi_of(ui, oid, "obj")
	var glb_i := fi_of(ui, oid, "glb")
	var O := {}
	var G := {}
	for q in ["Coarse", "Normal", "Fine"]:
		await pick(ui, q)
		if q == "Fine":
			ok(ui.ui_q_row.is_visible_in_tree(), "3 the Mesh quality row shows for the part's OBJ / GLB")
		var po := String(ui.export_now(oid, obj_i, DIR + "/o_" + q, 1))
		var pg := String(ui.export_now(oid, glb_i, DIR + "/g_" + q, 1))
		O[q] = obj_tris(po)
		G[q] = glb_tris(pg)
		print("objglb ", q, " ", O[q], " ", G[q], " ", po, " ", pg)
	ok(int(O["Fine"]) > int(O["Coarse"]) and int(O["Coarse"]) > 0, "3 OBJ: Fine %d > Coarse %d triangles" % [O["Fine"], O["Coarse"]])
	ok(int(G["Fine"]) > int(G["Coarse"]) and int(G["Coarse"]) > 0, "3 GLB: Fine %d > Coarse %d triangles" % [G["Fine"], G["Coarse"]])
	var base := ExportBudget.tris_of(m._free_part_object().get("mesh"))
	ok(int(O["Normal"]) == base, "4 OBJ at Normal %d = the part's mesh as always %d" % [O["Normal"], base])
	root.size = Vector2i(1024, 600)
	root.content_scale_size = Vector2i(1024, 600)
	ui.dlg.popup_centered()
	await idle(6)
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/tools/kine_workers/out/w05b")
	root.get_texture().get_image().save_png("C:/Users/Nick/tools/kine_workers/out/w05b/w05b_1024x600.png")
	print("w05b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
