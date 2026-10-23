class_name KMeshLOD
extends RefCounted
## F04 (docs/ROADMAP_400.md): LEVELS OF DETAIL from F03's collapse (scripts/kmesh_decimate.gd).
## build(m, targets): one level per target; a target <= 1.0 is a ratio of LOD0's triangle count, above 1 a triangle
##   count. LOD0 is the mesh as it is (a copy); each next level is collapsed from the level before it (chained, as
##   progressive meshes are), so a level is never finer than the one before. Each level keeps {"target", "tris",
##   "error" (the two-sided sampled Hausdorff distance to LOD0 as a fraction of LOD0's bounding-box diagonal), "mesh"}.
## KEPT WITH THE MESH: store() puts the levels on the KMesh (meta "lods"); KMesh.to_dict / from_dict carry them in the
##   .kmesh file ("lods": each level's own to_dict). A level is a full KMesh (UVs and every A09 attribute; no shape keys).
## PREVIEW: preview_next(ui) shows the next level in the model preview (LOD0 -> 1 -> 2 -> 3 -> 0); the mesh being
##   edited stays LOD0 (an edit or decimate shows LOD0 again).
## EXPORT: write_glb(m, path, base) writes one .glb with a node + mesh per level named <base>_LOD0 .. <base>_LODn (the
##   suffix Godot's importer and Unreal read as LOD levels), written by Godot's GLTFDocument like GltfExport (the scene
##   export holds the mannequin, not the model mesh, so the levels go in a .glb of their own).
## MODEL ops (MeshTools lines, no new keys): "lods" (make 100 / 50 / 25 / 12.5 %), "lod_next", "lod_export" (F03's
##   "decimate", "decimate_quarter", "decimate_planar" are KMeshDecimate.op).

const RATIOS := [1.0, 0.5, 0.25, 0.125]
const META := "lods"
const EXPORT_DIR := "user://exports"

static var last_error := ""


static func copy(m: KMesh) -> KMesh:
	return KMeshDecimate.copy(m)


## the levels for `targets` (see the header). lock_features: F03's lock (no border / seam vertex moves)
static func build(m: KMesh, targets: Array = RATIOS, lock_features := false) -> Array:
	var t0 := m.triangle_count()
	var lod0 := copy(m)
	var dg := KMeshDecimate.diag(lod0)
	var out := []
	var prev := lod0
	for i in targets.size():
		var tv := float(targets[i])
		var tgt := int(round(t0 * tv)) if tv <= 1.0 else int(tv)
		var lv: KMesh
		if i == 0 or tgt >= prev.triangle_count():
			lv = copy(prev) if i > 0 else lod0
		else:
			lv = copy(prev)
			KMeshDecimate.collapse(lv, 1.0, tgt, lock_features)
		var err: float = 0.0 if lv == lod0 else KMeshDecimate.distance(lv, lod0)["max"] / maxf(dg, 1e-12)
		out.append({"target": tgt, "tris": lv.triangle_count(), "error": err, "mesh": lv})
		prev = lv
	return out


## keep the levels on the mesh (and in its .kmesh file)
static func store(m: KMesh, lods: Array) -> void:
	if lods.is_empty():
		m.remove_meta(META)
	else:
		m.set_meta(META, lods)


static func levels(m: KMesh) -> Array:
	return m.get_meta(META, []) if m.has_meta(META) else []


## the levels as the .kmesh file holds them (KMesh.to_dict); [] = none
static func to_file(m: KMesh) -> Array:
	var out := []
	for l in levels(m):
		out.append({"target": l["target"], "tris": l["tris"], "error": l["error"], "mesh": (l["mesh"] as KMesh).to_dict()})
	return out


## read them back (KMesh.from_dict); a damaged level is dropped with the rest (the mesh itself still loads)
static func from_file(m: KMesh, d) -> void:
	if m.has_meta(META):
		m.remove_meta(META)
	if not d is Array:
		return
	var out := []
	for l in d:
		if not l is Dictionary or not (l as Dictionary).has("mesh"):
			return
		var lm := KMesh.new().from_dict(l["mesh"])
		if lm == null:
			return
		out.append({"target": int(l.get("target", 0)), "tris": int(l.get("tris", 0)), "error": float(l.get("error", 0.0)), "mesh": lm})
	store(m, out)


## one .glb, a mesh per level named <base>_LOD<i>; OK or the error (last_error says why)
static func write_glb(m: KMesh, path: String, base := "kmesh") -> Error:
	last_error = ""
	var lods := levels(m)
	if lods.is_empty():
		last_error = "the mesh has no LODs: make them first (\"Model: make LODs\")"
		return ERR_DOES_NOT_EXIST
	var root := Node3D.new()
	root.name = base
	for i in lods.size():
		var mi := MeshInstance3D.new()
		mi.name = "%s_LOD%d" % [base, i]
		var am := (lods[i]["mesh"] as KMesh).to_array_mesh()
		am.resource_name = mi.name
		mi.mesh = am
		root.add_child(mi)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	root.free()
	if err != OK:
		last_error = "the glTF writer refused the levels (%s)" % error_string(err)
		return err
	# the writer makes names unique across the FILE (node "x_LOD0" + mesh "x_LOD0" -> mesh "x_LOD02"): the mesh of
	# level i is named exactly as its node, which is what Godot's importer and Unreal read
	var ms := st.get_meshes()
	for i in mini(ms.size(), lods.size()):
		(ms[i] as GLTFMesh).resource_name = "%s_LOD%d" % [base, i]
		(ms[i] as GLTFMesh).original_name = "%s_LOD%d" % [base, i]
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	err = doc.write_to_filesystem(st, abs)
	if err != OK:
		last_error = "could not write %s (%s)" % [abs, error_string(err)]
	return err


# ---------------------------------------------------------------- the model preview's ops

## show LOD0 (the mesh being edited) again if a level is shown
static func preview_off(ui) -> void:
	if ui.view != null and ui.view.mesh != ui.mesh:
		ui.view.set_mesh(ui.mesh, ui.sel)
		ui.view.rebuild()
	ui.set_meta("lod_at", 0)


## the next level in the preview; returns its index (0 = the mesh itself)
static func preview_next(ui) -> int:
	var lods := levels(ui.mesh)
	if lods.is_empty():
		return -1
	var cur: int = int(ui.get_meta("lod_at", 0)) if ui.view.mesh != ui.mesh else 0   # an edit shows LOD0 again
	var at: int = (cur + 1) % lods.size()
	ui.set_meta("lod_at", at)
	if at == 0:
		preview_off(ui)
		return 0
	var lm: KMesh = lods[at]["mesh"]
	ui.view.set_mesh(lm, KMeshSelect.new(lm, ui.sel.mode))
	ui.view.rebuild()
	return at


## MeshTools.op for "lod*": does it, returns what to say
static func op(name: String, m) -> String:
	var ui = m.kmed
	if ui == null or ui.mesh == null:
		return ""
	match name:
		"lods":
			preview_off(ui)
			var lods := build(ui.mesh)
			store(ui.mesh, lods)
			var parts := []
			for i in lods.size():
				parts.append("LOD%d %d tris (error %.2f%%)" % [i, int(lods[i]["tris"]), float(lods[i]["error"]) * 100.0])
			return "Model: %d LODs made: %s. \"Model: next LOD\" previews them, \"Model: export the LODs\" writes a .glb" % [lods.size(), ", ".join(parts)]
		"lod_next":
			var at := preview_next(ui)
			if at < 0:
				return "Model: no LODs yet: make them first (\"Model: make LODs\")"
			var lv: Dictionary = levels(ui.mesh)[at]
			return "Model: showing LOD%d: %d triangles%s" % [at, int(lv["tris"]), " (the mesh you edit)" if at == 0 else " (preview; edits go to LOD0)"]
		"lod_export":
			var path := EXPORT_DIR + "/model_lods.glb"
			var err := write_glb(ui.mesh, path, "model")
			if err != OK:
				return "Model: LOD export failed: %s" % (last_error if last_error != "" else error_string(err))
			return "Model: wrote %d LODs (model_LOD0 .. model_LOD%d) to %s" % [levels(ui.mesh).size(), levels(ui.mesh).size() - 1, ProjectSettings.globalize_path(path)]
	return ""
