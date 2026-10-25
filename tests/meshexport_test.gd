## godot --path . -s tests/meshexport_test.gd     (Expert MODEL walk-through round 2: Apply body with no edit, Export model)
## Bars, written before running on the old code:
##   1 APPLY WITH NO EDIT: the body mesh opened and Apply body pressed with nothing changed: the fighter keeps its meshes
##     (the same generation, the same vertex count; the old rebuild split the UV seams, 6994 -> 7330 verts)
##   2 APPLY AFTER AN EDIT still applies: one vertex moved 1 cm, Apply body: a new generation
##   3 EXPORT MODEL: the test cube open, Export model writes <exports>/test_cube.glb and .obj; the .glb loads (GLTFDocument)
##     with a mesh; the .obj has as many "v " lines as the cube's vertices or more (seams may split) and "f " lines
##   4 the status line names the folder
## The files this test writes are removed at the end.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body_verts(m: Node) -> int:
	var n := 0
	for j in m.pieces:
		var mi := m.pieces[j] as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				n += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)

	# 1 / 2 Apply body
	var v0 := body_verts(m)
	var g0: int = BaseBody.gen(m)
	BaseBody.start(m)
	await idle(3)
	BaseBody.apply_cmd(m)
	await idle(3)
	var v1 := body_verts(m)
	ok(BaseBody.gen(m) == g0 and v1 == v0, "1 Apply body with no edit: the fighter is unchanged (generation %d -> %d, verts %d -> %d)" % [g0, BaseBody.gen(m), v0, v1])
	var k: KMesh = m.kmed.mesh
	k.verts[0] = k.verts[0] + Vector3(0, 0.01, 0)
	BaseBody.apply_cmd(m)
	await idle(3)
	ok(BaseBody.gen(m) > g0, "2 Apply body after a 1 cm edit applies it (generation %d -> %d)" % [g0, BaseBody.gen(m)])
	m.kmed.stop()
	await idle(2)

	# 3 / 4 Export model
	m._kmesh_edit_start()
	await idle(3)
	var nv: int = m.kmed.mesh.vert_count()
	var dir := ProjectSettings.globalize_path(UserPaths.w("res://exports"))
	var glb := dir.path_join("test_cube.glb")
	var obj := dir.path_join("test_cube.obj")
	var had := [FileAccess.file_exists(glb), FileAccess.file_exists(obj)]
	var got: String = m._export_model()
	await idle(2)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var e := doc.append_from_file(glb, st) if FileAccess.file_exists(glb) else ERR_FILE_NOT_FOUND
	var nmesh := st.get_meshes().size() if e == OK else 0
	var vl := 0
	var fl := 0
	if FileAccess.file_exists(obj):
		for line in FileAccess.get_file_as_string(obj).split("\n"):
			if line.begins_with("v "):
				vl += 1
			elif line.begins_with("f "):
				fl += 1
	ok(got != "" and e == OK and nmesh >= 1, "3 Export model writes test_cube.glb, and it loads with %d mesh(es) (%s)" % [nmesh, error_string(e)])
	ok(vl >= nv and fl > 0, "3 the .obj has %d 'v' lines (cube %d verts) and %d faces" % [vl, nv, fl])
	ok(String(m.ui_status.text).contains(dir.get_file()) or String(m.ui_status.text).contains("exports"), "4 the status names the folder: %s" % m.ui_status.text)
	for i in 2:
		var p: String = [glb, obj][i]
		if not had[i] and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("MESHEXPORT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
