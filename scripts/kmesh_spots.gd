class_name KMeshSpots
extends RefCounted
## C05 (complaint #311, "translucency to find the bad spot"): KMeshValidate.report as SPOTS you can see and jump to.
## spots(mesh) turns each problem into a finding (the shape scripts/model_checks.gd uses: kind, title, next, mode, items,
## count) whose items are the exact verts / edges / faces at fault; marker_mesh() draws them as red crosses that ignore
## depth, so they show THROUGH the surface; see_through() makes the surface translucent so the spot behind it shows too.
## The panel (scripts/kmesh_spots_ui.gd) lists them with a Jump button. Read-only: nothing here edits a mesh.

const SEL_VERT := 0
const SEL_EDGE := 1
const SEL_FACE := 2
const CROSS := 0.012   # m: half-size of a marker cross
const SEE_THROUGH := 0.65   # the surface's transparency while on


static func spots(mesh: KMesh) -> Array:
	var out := []
	if mesh == null:
		return out
	var r := KMeshValidate.report(mesh)
	for p in r["problems"]:
		var k: String = p["kind"]
		var items: Array = p["items"]
		var mode := SEL_VERT
		match k:
			"doubled", "loose":
				mode = SEL_VERT
			"degenerate":
				mode = SEL_FACE
			"non_manifold":
				mode = SEL_EDGE
				items = items.map(func(e): return Vector2i(mini(e[0], e[1]), maxi(e[0], e[1])))
			"holes":
				mode = SEL_VERT
				var vs := {}
				for l in items:
					for v in l:
						vs[v] = true
				items = vs.keys()
			"flipped":
				mode = SEL_EDGE
				items = ModelChecks.flipped_edges(mesh)
			"inside_out":
				mode = SEL_FACE
				items = range(mesh.faces.size())
		out.append({"kind": k, "title": String(p["fix"]), "next": ("Repair fixes this" if p["auto"] else "by hand"), "mode": mode, "items": items, "count": items.size(), "pts": 0.0})
	return out


## the mesh-space points of a spot
static func points(mesh: KMesh, f: Dictionary) -> PackedVector3Array:
	return ModelChecks.points_of(mesh, f, Transform3D.IDENTITY)


## red crosses (3 lines each) at every point of the spot, in the mesh's space; unshaded, no depth test, drawn on top
static func marker_mesh(mesh: KMesh, f: Dictionary) -> ArrayMesh:
	var pts := points(mesh, f)
	var verts := PackedVector3Array()
	for p in pts:
		for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			verts.append(p - ax * CROSS)
			verts.append(p + ax * CROSS)
	var am := ArrayMesh.new()
	if verts.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.1)
	mat.no_depth_test = true
	mat.render_priority = 100
	am.surface_set_material(0, mat)
	return am


## the translucent surface of a KMeshView on / off
static func see_through(view: KMeshView, on: bool) -> void:
	var s = view.get("_surf")
	if s != null:
		(s as GeometryInstance3D).transparency = SEE_THROUGH if on else 0.0
