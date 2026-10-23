## godot --path . -s tests/lod_test.gd     (ROADMAP_400 F04, and F03's model-preview ops; bar 5 needs a window)
## LODs (scripts/kmesh_lod.gd) from F03's collapse (scripts/kmesh_decimate.gd). Bars, written before measuring:
##   1 LEVELS: a UV sphere (64 x 32, 3968 triangles) with a spherical UV map -> 4 levels at 100 / 50 / 25 / 12.5 %: each
##     level's triangle count within 2 % of its target; the error (Hausdorff to LOD0 / bbox diagonal) is 0 at LOD0 and
##     rises strictly level by level; every level KMeshValidate clean; every corner of every level carries a uv its
##     vertex had in LOD0
##   2 COUNTS: targets given as triangle counts (all, 2000, 800, 300) -> each within 2 %
##   3 KEPT WITH THE MESH: stored on the mesh, the levels go through KMesh.to_dict -> JSON -> save / load_file: 4
##     levels back, the same triangle counts and errors, LOD2's verts identical
##   4 GLB: write_glb -> one .glb whose JSON names exactly the meshes and nodes sphere_LOD0 .. sphere_LOD3, each mesh's
##     index count / 3 = its level's triangle count
##   5 MODEL PREVIEW (window, through MeshTools lines as a search pick runs them): on the test cube (96 quads = 192
##     triangles) "make LODs" -> 4 levels 192 / 96 / 48 / 24 (2 %); "next LOD" x 4 shows LOD1, LOD2, LOD3 (the view's
##     mesh has their triangle counts) then the edited mesh again; "export the LODs" writes a .glb with model_LOD0..3;
##     "decimate to half" = ONE undo step (192 -> 96 triangles, shape keys still one offset per vert), Ctrl+Z (a real key)
##     gives back 96 quads; "planar decimate" = ONE step, 96 -> 6 faces, Ctrl+Z -> 96
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func uv_sets(k: KMesh) -> Dictionary:
	var out := {}
	for fi in k.face_count():
		var f: PackedInt32Array = k.faces[fi]
		for i in f.size():
			var p: Vector3 = k.verts[f[i]]
			if not out.has(p):
				out[p] = {}
			out[p][k.get_attr("uv", k.face_he0[fi] + i)] = true
	return out


func uv_kept(k: KMesh, ref: Dictionary) -> bool:
	for fi in k.face_count():
		var f: PackedInt32Array = k.faces[fi]
		for i in f.size():
			var p: Vector3 = k.verts[f[i]]
			if not ref.has(p) or not (ref[p] as Dictionary).has(k.get_attr("uv", k.face_he0[fi] + i)):
				return false
	return true


## the JSON chunk of a .glb
func glb_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()   # magic
	f.get_32()   # version
	f.get_32()   # length
	var n := f.get_32()
	f.get_32()   # "JSON"
	var j = JSON.parse_string(f.get_buffer(n).get_string_from_utf8())
	return j if j is Dictionary else {}


## mesh name -> triangles (index count / 3 of its first primitive), and the node names
func glb_meshes(j: Dictionary) -> Dictionary:
	var out := {}
	for me in j.get("meshes", []):
		var acc: int = int(me["primitives"][0]["indices"])
		out[String(me.get("name", ""))] = int(j["accessors"][acc]["count"]) / 3
	return out


func tool_line(id: String) -> Dictionary:
	for t in MeshTools.TOOLS:
		if t["id"] == id:
			return t
	return {}


func _init() -> void:
	# ---- bar 1
	var s := KMeshPrims.uv_sphere(1.0, 64, 32)
	KMeshUV.project_sphere(s)
	var uv0 := uv_sets(s)
	var t0 := s.triangle_count()
	var us := Time.get_ticks_usec()
	var lods := KMeshLOD.build(s)
	var ms := (Time.get_ticks_usec() - us) / 1000.0
	var within := true
	var rising := true
	var clean := true
	var uvs := true
	var words := []
	for i in lods.size():
		var l: Dictionary = lods[i]
		within = within and absf(int(l["tris"]) - int(l["target"])) <= 0.02 * int(l["target"])
		if i > 0:
			rising = rising and float(l["error"]) > float(lods[i - 1]["error"])
		clean = clean and KMeshValidate.report(l["mesh"])["ok"]
		uvs = uvs and uv_kept(l["mesh"], uv0)
		words.append("LOD%d %d/%d err %.3f%%" % [i, l["tris"], l["target"], float(l["error"]) * 100.0])
	ok(t0 == 3968 and lods.size() == 4 and within, "bar 1: %d levels in %.0f ms, each within 2 %%: %s" % [lods.size(), ms, ", ".join(words)])
	ok(float(lods[0]["error"]) == 0.0 and rising, "bar 1: error 0 at LOD0, rising strictly: %s" % [lods.map(func(l): return snappedf(float(l["error"]), 0.00001))])
	ok(clean and uvs, "bar 1: every level clean %s, every corner's uv one its vertex had %s" % [clean, uvs])
	# ---- bar 2
	var l2 := KMeshLOD.build(s, [1.0, 2000, 800, 300])
	var w2 := l2.map(func(l): return "%d/%d" % [l["tris"], l["target"]])
	var in2 := l2.all(func(l): return absf(int(l["tris"]) - int(l["target"])) <= 0.02 * int(l["target"]))
	ok(l2.size() == 4 and in2 and int(l2[1]["target"]) == 2000, "bar 2: triangle-count targets: %s" % [w2])
	# ---- bar 3
	KMeshLOD.store(s, lods)
	var path := "user://zz_lod_test_%d.kmesh" % OS.get_process_id()
	var err := s.save(path)
	var back := KMesh.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var bl := KMeshLOD.levels(back) if back != null else []
	var same := bl.size() == 4
	if same:
		for i in 4:
			same = same and int(bl[i]["tris"]) == int(lods[i]["tris"]) and absf(float(bl[i]["error"]) - float(lods[i]["error"])) < 1e-9
		same = same and (bl[2]["mesh"] as KMesh).verts == (lods[2]["mesh"] as KMesh).verts
	ok(err == OK and same, "bar 3: saved (%s) and loaded: %d levels, counts %s" % [error_string(err), bl.size(), bl.map(func(l): return l["tris"])])
	# ---- bar 4
	var gp := ProjectSettings.globalize_path("user://zz_lod_test_%d.glb" % OS.get_process_id())
	var gerr := KMeshLOD.write_glb(s, gp, "sphere")
	var j := glb_json(gp)
	DirAccess.remove_absolute(gp)
	var gm := glb_meshes(j)
	var names := ["sphere_LOD0", "sphere_LOD1", "sphere_LOD2", "sphere_LOD3"]
	var nodes: Array = j.get("nodes", []).map(func(n): return String(n.get("name", "")))
	var counts_ok := gm.size() == 4
	for i in 4:
		counts_ok = counts_ok and gm.get(names[i], -1) == int(lods[i]["tris"])
	ok(gerr == OK and counts_ok and names.all(func(n): return nodes.has(n)), "bar 4: glb %s: meshes %s, nodes %s" % [error_string(gerr), gm, nodes])
	# ---- bar 5
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	MeshTools.run(tool_line("mesh_lods"), m)   # off the MODEL page: opens the test cube first
	await idle(3)
	var ui: KMeshEditUI = m.kmed
	var cl := KMeshLOD.levels(ui.mesh)
	var ct := cl.map(func(l): return int(l["tris"]))
	var c_in := cl.size() == 4 and cl.all(func(l): return absf(int(l["tris"]) - int(l["target"])) <= 0.02 * int(l["target"]))
	ok(ui.on and c_in and ct[0] == 192, "bar 5: make LODs on the test cube: %s ('%s')" % [ct, m.ui_status.text])
	var seen := []
	for i in 4:
		MeshTools.run(tool_line("mesh_lod_next"), m)
		await idle(2)
		seen.append(ui.view.mesh.triangle_count() if ui.view.mesh != ui.mesh else -1)
	ok(seen == [ct[1], ct[2], ct[3], -1], "bar 5: next LOD x 4 shows %s (-1 = the edited mesh) ('%s')" % [seen, m.ui_status.text])
	MeshTools.run(tool_line("mesh_lod_export"), m)
	var xp := ProjectSettings.globalize_path(KMeshLOD.EXPORT_DIR + "/model_lods.glb")
	var xm := glb_meshes(glb_json(xp))
	DirAccess.remove_absolute(xp)
	ok(xm.size() == 4 and ["model_LOD0", "model_LOD1", "model_LOD2", "model_LOD3"].all(func(n): return xm.has(n)), "bar 5: export: %s ('%s')" % [xm, m.ui_status.text])
	var u0: int = ui.undo.steps.size()
	MeshTools.run(tool_line("mesh_decimate"), m)
	await idle(2)
	var dt: int = ui.mesh.triangle_count()
	var sh_ok: bool = ui.mesh.shapes.is_empty() or (ui.mesh.shapes["basis"] as PackedVector3Array).size() == ui.mesh.vert_count()
	var u1: int = ui.undo.steps.size()
	await key(KEY_Z, true)
	var q := ui.mesh.faces.all(func(f): return (f as PackedInt32Array).size() == 4)
	ok(u1 == u0 + 1 and dt == 96 and sh_ok and ui.mesh.face_count() == 96 and q, "bar 5: decimate to half: %d undo step(s), %d triangles, shape keys fit %s; Ctrl+Z -> %d faces, quads %s ('%s')" % [u1 - u0, dt, sh_ok, ui.mesh.face_count(), q, m.ui_status.text])
	MeshTools.run(tool_line("mesh_decimate_planar"), m)
	await idle(2)
	var pf: int = ui.mesh.face_count()
	var u2: int = ui.undo.steps.size()
	await key(KEY_Z, true)
	ok(pf == 6 and u2 == u0 + 1 and ui.mesh.face_count() == 96, "bar 5: planar decimate: %d faces in 1 step (%d), Ctrl+Z -> %d" % [pf, u2 - u0, ui.mesh.face_count()])
	print("LOD ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
