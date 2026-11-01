class_name ExportBudget
extends RefCounted
## Friday plan 157: "Decimate for export with a triangle budget". The Export dialog's "Triangle budget" (Full / 50 000 / 10 000 /
## 2 000): the file is written from a DECIMATED COPY of each mesh (KMeshDecimate.collapse, quadric error metrics); the mesh on screen
## is never touched (every function here works on copies and returns new arrays). The budget is the file's whole count, shared
## between the objects/surfaces in proportion to their triangles. Pure: no nodes.

const BUDGETS := [0, 50000, 10000, 2000]   # 0 = Full: the file is written as it is today
const LABELS := ["Full (no decimation)", "50 000 triangles", "10 000 triangles", "2 000 triangles"]

static var last := {"before": 0, "after": 0}   # the triangles of the last list given to apply_list: before and after


## triangles in a Mesh (all surfaces)
static func tris_of(mesh: Mesh) -> int:
	var n := 0
	if mesh == null:
		return 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null and not (idx as PackedInt32Array).is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## a decimated COPY of `mesh` with about `target` triangles (the same mesh when it already fits). Each surface is welded by position,
## collapsed to its share of the target and written back (its material kept); the original is not changed.
static func decimate_mesh(mesh: Mesh, target: int) -> Mesh:
	var total := tris_of(mesh)
	if mesh == null or target <= 0 or total <= target:
		return mesh
	var out := ArrayMesh.new()
	var ratio := float(target) / float(total)
	for s in mesh.get_surface_count():
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		var km := KMesh.new().from_array_mesh(am)
		var t0 := km.triangle_count()
		if t0 > 4:
			KMeshDecimate.collapse(km, 1.0, maxi(4, int(round(t0 * ratio))))
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, km.to_array_mesh().surface_get_arrays(0))
		var mat := mesh.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## a copy of a list of {"name", "mesh", "xf", ...} entries (what the OBJ / GLB writers take), each mesh decimated so the list holds
## about `budget` triangles. budget <= 0 or already under: the very same list. Sets `last`.
static func apply_list(entries: Array, budget: int) -> Array:
	var total := 0
	for e in entries:
		total += tris_of((e as Dictionary).get("mesh", null))
	last = {"before": total, "after": total}
	if budget <= 0 or total <= budget:
		return entries
	var out := []
	var after := 0
	for e in entries:
		var d: Dictionary = (e as Dictionary).duplicate()
		var mesh: Mesh = d.get("mesh", null)
		var share := int(round(float(budget) * tris_of(mesh) / float(total)))
		d["mesh"] = decimate_mesh(mesh, maxi(share, 4)) if mesh != null else null
		after += tris_of(d["mesh"])
		out.append(d)
	last = {"before": total, "after": after}
	return out


## a copy of print bodies ([{"v": PackedVector3Array, "t": PackedInt32Array, "name", "color"}], MeshExport) decimated to about
## `budget` triangles in all. Same list when it already fits. Sets `last`.
static func apply_bodies(bodies: Array, budget: int) -> Array:
	var total := 0
	for b in bodies:
		total += (b["t"] as PackedInt32Array).size() / 3
	last = {"before": total, "after": total}
	if budget <= 0 or total <= budget:
		return bodies
	var out := []
	var after := 0
	for b in bodies:
		var d: Dictionary = (b as Dictionary).duplicate()
		var t: PackedInt32Array = d["t"]
		var n := t.size() / 3
		var share := maxi(4, int(round(float(budget) * n / float(total))))
		if n > share:
			var faces: Array = []
			for i in n:
				faces.append(PackedInt32Array([t[3 * i], t[3 * i + 1], t[3 * i + 2]]))
			var km := KMesh.new().from_arrays(d["v"], faces)
			KMeshDecimate.collapse(km, 1.0, share)
			var nt := PackedInt32Array()
			for f in km.faces:
				var fa := f as PackedInt32Array
				for k in range(1, fa.size() - 1):
					nt.append(fa[0])
					nt.append(fa[k])
					nt.append(fa[k + 1])
			d["v"] = km.verts
			d["t"] = nt
		after += (d["t"] as PackedInt32Array).size() / 3
		out.append(d)
	last = {"before": total, "after": after}
	return out


## the words that say what the budget did ("" for Full or when nothing was cut)
static func words() -> String:
	if int(last["after"]) >= int(last["before"]):
		return ""
	return " (decimated for export: %d -> %d triangles; the model on screen is unchanged)" % [int(last["before"]), int(last["after"])]
