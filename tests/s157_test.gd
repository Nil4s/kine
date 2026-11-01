extends SceneTree
## godot --path . -s tests/s157_test.gd     (Friday plans 157 + 154; needs a window: main, real clicks and keys)
## 157: Export dialog "Triangle budget" (Full / 50 000 / 10 000 / 2 000) on a 13 872-triangle sculpt sphere (r 0.3 m).
##   - 2 000 budget, .glb re-read from disk with GLTFDocument: <= 2000 triangles, volume within 3 pct of the full mesh, bbox within 1 pct
##   - the same budget as .obj (faces counted in the file) <= 2000
##   - Full writes the full count (13 872)
##   - the on-screen mesh is the same after the export (triangle count and vertex positions)
##   - the STL road (MeshExport bodies + ExportBudget.apply_bodies + write_stl) re-read: triangle count in the header <= 1000
## 154: Sculpt page Remesh slider (real click on the slider): lighter (-1) halves the triangles within 10 pct and keeps the volume within 2 pct;
##   smoother (+1) raises the count; each is ONE undo step (Ctrl+Z gives back exactly the old count)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s157"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func click_at(p: Vector2) -> void:
	await mouse(p, true)
	await mouse(p, false)
	await idle(3)


func ctrl_z() -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_Z
		e.physical_keycode = KEY_Z
		e.ctrl_pressed = true
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot(nm: String) -> void:
	await idle(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## volume (abs, divergence theorem) of a KMesh
func vol_k(k: KMesh) -> float:
	var v := 0.0
	for f in k.faces:
		var fa := f as PackedInt32Array
		for i in range(1, fa.size() - 1):
			v += k.verts[fa[0]].dot(k.verts[fa[i]].cross(k.verts[fa[i + 1]])) / 6.0
	return absf(v)


## triangles, volume, bbox size of a Node tree's meshes
func measure_node(n: Node) -> Dictionary:
	var tris := 0
	var vol := 0.0
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var stack := [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ix = arr[Mesh.ARRAY_INDEX]
				var idx: PackedInt32Array = ix if ix != null else PackedInt32Array()
				for i in range(0, idx.size(), 3):
					var a := mi.transform * vs[idx[i]]
					var b := mi.transform * vs[idx[i + 1]]
					var d := mi.transform * vs[idx[i + 2]]
					vol += a.dot(b.cross(d)) / 6.0
					tris += 1
				for p in vs:
					lo = lo.min(mi.transform * p)
					hi = hi.max(mi.transform * p)
	return {"tris": tris, "vol": absf(vol), "size": hi - lo}


func read_glb(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return {}
	var sc := doc.generate_scene(st)
	var r := measure_node(sc)
	sc.free()
	return r


func bbox_k(k: KMesh) -> Vector3:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for p in k.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	return hi - lo


func run_export(ui: ExportDialog, run_name: String, budget_i: int) -> String:
	var ti := -1
	var fi := -1
	var tg := ui._tg()
	for i in tg.size():
		for j in (tg[i]["formats"] as Array).size():
			if String(tg[i]["formats"][j]["run"]) == run_name and ti < 0:
				ti = i
				fi = j
	ui.ui_target.select(ti)
	ui._on_target(ti)
	ui.ui_format.select(fi)
	ui._on_format(fi)
	ui.ui_what.select(1)
	ui.ui_budget.select(budget_i)
	ui._refresh()
	var d := UserPaths.w("res://exports")
	var p := "%s/sculpt_sphere.%s" % [d, run_name]
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if run_name == "glb" and budget_i == 3:
		await shot("export_dialog")   # the dialog open with the Triangle budget row
	ui.dlg.get_ok_button().pressed.emit()   # the dialog's own Export button
	await idle(2)
	return p


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._sculpt_start()
	await idle(3)
	var ksc: KMeshSculptUI = m.ksc
	var s := KMeshSculptUI.make_sphere(0.3, 34)
	ksc.mesh.from_arrays(s.verts, s.faces)
	KMeshMask.ensure(ksc.mesh)
	ksc.view.set_mesh(ksc.mesh)
	ksc.view.rebuild()
	ksc.tint.refresh(true)
	await idle(2)
	var full_tris := ksc.mesh.triangle_count()
	var full_vol := vol_k(ksc.mesh)
	var full_bb := bbox_k(ksc.mesh)
	ok(full_tris > 13000 and full_tris < 14500, "the sculpt sphere has %d triangles (13.8k class)" % full_tris)
	var verts0 := ksc.mesh.verts.duplicate()

	# ---------------- 157 export
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	await idle(2)
	ok(ui.ui_budget != null and ui.ui_budget.item_count == 4, "the dialog has a Triangle budget with 4 choices")
	ok(m.scene_object_names().has("sculpt_sphere") and m.selected_object_name() == "sculpt_sphere", "the sculpt sphere is a mesh object, and the selected one")
	var p2 := await run_export(ui, "glb", 3)
	var g2 := read_glb(p2)
	var bb2: Vector3 = g2.get("size", Vector3.ZERO)
	ok(not g2.is_empty() and int(g2["tris"]) <= 2000 and int(g2["tris"]) > 500, ".glb at the 2 000 budget: %d triangles re-read from the file (<= 2000)" % int(g2.get("tris", -1)))
	var vr := absf(float(g2.get("vol", 0.0)) / full_vol - 1.0)
	ok(vr <= 0.03, "volume within 3 pct of the full mesh (%.2f pct off)" % (vr * 100.0))
	var br := maxf(absf(bb2.x / full_bb.x - 1.0), maxf(absf(bb2.y / full_bb.y - 1.0), absf(bb2.z / full_bb.z - 1.0)))
	ok(br <= 0.01, "bbox within 1 pct (%.2f pct worst axis; %s vs %s)" % [br * 100.0, bb2, full_bb])
	ok(ksc.mesh.triangle_count() == full_tris and ksc.mesh.verts == verts0, "the export did not change the on-screen mesh (%d triangles before and after, vertices equal)" % ksc.mesh.triangle_count())
	var pf := await run_export(ui, "glb", 0)
	var gf := read_glb(pf)
	ok(not gf.is_empty() and int(gf["tris"]) == full_tris, "Full budget writes the full count (%d of %d)" % [int(gf.get("tris", -1)), full_tris])
	var po := await run_export(ui, "obj", 3)
	var ft := FileAccess.get_file_as_string(po)
	var nf := 0
	for ln in ft.split("\n"):
		if ln.begins_with("f "):
			nf += 1
	ok(nf > 0 and nf <= 2000, ".obj at the 2 000 budget: %d faces in the file (<= 2000)" % nf)
	ok(ksc.mesh.triangle_count() == full_tris, "still %d triangles on screen after three exports" % ksc.mesh.triangle_count())
	# STL road (the 3D printing writers take bodies; a part needs the CAD kernel, so a body of the sphere is given straight)
	var soup := PackedVector3Array()
	var am := ksc.mesh.to_array_mesh()
	var arr := am.surface_get_arrays(0)
	for ix in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
		soup.append((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)[ix])
	var body := MeshExport.weld(soup)
	body["name"] = "sphere"
	var small := ExportBudget.apply_bodies([body], 1000)
	var sp := "user://s157.stl"
	MeshExport.write_stl(sp, small)
	var fa := FileAccess.open(sp, FileAccess.READ)
	fa.seek(80)
	var stl_n := fa.get_32()
	fa.close()
	ok(stl_n > 300 and stl_n <= 1000, ".stl at a 1 000 budget: %d triangles in the file header (<= 1000; full %d)" % [stl_n, (body["t"] as PackedInt32Array).size() / 3])
	ui.dlg.hide()

	# ---------------- 154 remesh slider
	var sl := ksc.remesh_sl
	ok(sl != null and sl.is_visible_in_tree(), "the Remesh slider is on the Sculpt page")
	await shot("sculpt_remesh_slider")
	var base_vol := vol_k(ksc.mesh)
	var r := sl.get_global_rect()
	var gw := 16.0
	var xm1 := r.position.x + gw * 0.5 + (r.size.x - gw) * 0.25   # value -1 of -2..2
	await click_at(Vector2(xm1, r.get_center().y))
	var light := ksc.mesh.triangle_count()
	ok(absf(float(light) / (full_tris * 0.5) - 1.0) <= 0.10, "lighter halves the triangles within 10 pct: %d -> %d (half = %d)" % [full_tris, light, full_tris / 2])
	var lv := absf(vol_k(ksc.mesh) / base_vol - 1.0)
	ok(lv <= 0.02, "lighter keeps the volume within 2 pct (%.2f pct off)" % (lv * 100.0))
	ok(sl.value == 0.0, "the slider is back at 0 after the rebuild")
	await shot("sculpt_remesh_lighter")
	await ctrl_z()
	ok(ksc.mesh.triangle_count() == full_tris, "ONE Ctrl+Z gives the %d triangles back (%d)" % [full_tris, ksc.mesh.triangle_count()])
	var xp1 := r.position.x + gw * 0.5 + (r.size.x - gw) * 0.75   # value +1
	await click_at(Vector2(xp1, r.get_center().y))
	var smooth := ksc.mesh.triangle_count()
	ok(smooth > full_tris * 1.5, "smoother raises the count: %d -> %d" % [full_tris, smooth])
	await ctrl_z()
	ok(ksc.mesh.triangle_count() == full_tris, "ONE Ctrl+Z gives the %d triangles back again (%d)" % [full_tris, ksc.mesh.triangle_count()])
	print("s157: %d fail" % fails)
	quit()
