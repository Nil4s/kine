## godot --headless --path . -s tests/objexport_test.gd     (EXPORT DIALOG "What to export": the mesh objects in the scene)
## Bars, written before the change was run on the old code:
##   (a) with the body and the test cube in the scene, the export dialog lists the cube by name (ui_objects)
##   (b) "Only the selected object" with the cube selected writes a .glb with ONE mesh whose vertex count is the cube's
##       (read back by GLTFDocument, not by the exporter's code; the cube's count is its to_array_mesh surfaces)
##   (c) GUARD: "Everything" writes the same mesh count as the old writer (_export_glb called directly)
## (a) and (b) must FAIL on the old code (no choice, no list). Files go to user://zz_objexport and are removed at the end.
extends SceneTree

var fails := 0
const DIR := "user://zz_objexport"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## vertices across every surface of every mesh the GLB holds, and the mesh count (read back by Godot's GLTFDocument)
static func read_glb(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var e := doc.append_from_file(ProjectSettings.globalize_path(path), st)
	if e != OK:
		return {"ok": false, "meshes": 0, "verts": 0}
	var verts := 0
	for gm in st.get_meshes():
		var am: ArrayMesh = (gm as GLTFMesh).get_mesh().get_mesh()
		for s in am.get_surface_count():
			var a: Array = am.surface_get_arrays(s)
			verts += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return {"ok": true, "meshes": st.get_meshes().size(), "verts": verts}


static func _xf_to(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := n
	while c != null and c != top:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func clean(d: String) -> void:
	var g := ProjectSettings.globalize_path(d)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


func _init() -> void:
	clean(DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/new"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/old"))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	# the body is in the scene; the test cube is open in the model editor beside it
	m._kmesh_edit_start()
	await idle(3)
	var cube_verts := 0
	for s in m.kmed.mesh.to_array_mesh().get_surface_count():
		cube_verts += (m.kmed.mesh.to_array_mesh().surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	m._export_dialog_open()
	var ui = m.export_ui
	await idle(2)

	# (a) the dialog lists the cube by name
	var listed: bool = "ui_objects" in ui and String(ui.ui_objects.text).contains("test_cube")
	ok(listed, "(a) the export dialog lists the test cube by name (%s)" % ("the object list has test_cube" if listed else "no object list with test_cube"))

	# (b) only the selected object (the cube): one mesh, the cube's vertices
	if "ui_what" in ui:
		var got = ui.export_now("web", 0, DIR + "/new", 1)
		var rb: Dictionary = read_glb(String(got)) if got is String and String(got) != "" else {"ok": false, "meshes": 0, "verts": 0}
		ok(bool(rb["ok"]) and int(rb["meshes"]) == 1 and int(rb["verts"]) == cube_verts,
			"(b) only the cube: %d mesh, %d vertices (the cube has %d), file %s" % [int(rb["meshes"]), int(rb["verts"]), cube_verts, String(got).get_file()])
	else:
		ok(false, "(b) only the cube: no \"What to export\" choice in the dialog (the cube cannot be picked alone)")

	# (c) GUARD: Everything writes the same meshes as the old writer
	var old_path: String = m._export_glb(DIR + "/old")
	var got_all = ui.export_now("web", 0, DIR + "/new")
	var ra := read_glb(old_path)
	var rn := read_glb(String(got_all))
	ok(bool(ra["ok"]) and bool(rn["ok"]) and int(ra["meshes"]) == int(rn["meshes"]) and int(ra["verts"]) == int(rn["verts"]),
		"(c) GUARD: Everything writes the old writer's meshes (%d mesh, %d verts vs %d, %d)" % [int(rn["meshes"]), int(rn["verts"]), int(ra["meshes"]), int(ra["verts"])])

	# (d) the cube is written where it stands beside the body (KMeshEditUI.AT), not at the origin: its vertices' mean x
	var cx := 0.0
	if "ui_what" in ui:
		var gd = ui.export_now("web", 0, DIR + "/new", 1)
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if gd is String and doc.append_from_file(ProjectSettings.globalize_path(String(gd)), st) == OK:
			var sc: Node = doc.generate_scene(st)
			var mi: MeshInstance3D = sc.find_children("*", "MeshInstance3D", true, false)[0]
			var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var xf := _xf_to(mi, sc)
			for v in vs:
				cx += (xf * v).x
			cx /= maxf(1.0, vs.size())
			sc.free()
	var want_x: float = m.kmed.view.transform.origin.x
	ok(absf(cx - want_x) < 0.02, "(d) the cube is written where it stands: mean x %.3f m (the view's %.3f)" % [cx, want_x])

	# (e) two set pieces of the same kind: "only the selected" writes ONE of them (each piece has its own name)
	m.kmed.stop()
	await idle(2)
	m._prop_add("crate")
	m._prop_add("crate")
	await idle(2)
	m.sel_prop = 1
	var names: Array = m.scene_object_names()
	var ge = ui.export_now("web", 0, DIR + "/new", 1) if "ui_what" in ui else ""
	var re: Dictionary = read_glb(String(ge)) if ge is String and String(ge) != "" else {"ok": false, "meshes": 0, "verts": 0}
	ok(names.count(names[names.size() - 1]) == 1 and bool(re["ok"]) and int(re["meshes"]) == 1,
		"(e) two crates: names %s, only the selected one: %d mesh (file %s)" % [str(names), int(re["meshes"]), String(ge).get_file()])

	clean(DIR + "/new")
	clean(DIR + "/old")
	clean(DIR)
	print("objexport: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
