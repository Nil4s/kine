## dyntopo_serve.gd - SERVE `dyntopo` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (L52).
##   {radius?: m (0.12), detail?: L_max / radius (0.25), levels?: test sphere subdivisions 2..5 (4)}. Runs one dynamic-topology step of the brush on a
##   test sphere (r 0.5 m, brush at +x) and replies with the numbers: tris_before, tris_after, splits, collapses, band_n / band_bad (edges in the brush
##   outside [0.4, 1.0] * L_max +-10 %), edge_min_mm / edge_max_mm, manifold, native, ms. Maths: scripts/kmesh_dyntopo.gd.
class_name DyntopoServe
extends RefCounted


static func serve(_m: Node, p: Dictionary) -> Dictionary:
	var radius := float(p.get("radius", 0.12))
	var detail := float(p.get("detail", 0.25))
	var levels := int(p.get("levels", 4))
	if radius < 0.01 or radius > 0.5:
		return {"ok": false, "error": "radius is the brush radius in metres on a 0.5 m sphere, 0.01 to 0.5"}
	if detail < 0.05 or detail > 3.0:
		return {"ok": false, "error": "detail is the longest edge as a fraction of the radius, 0.05 to 3"}
	if levels < 2 or levels > 5:
		return {"ok": false, "error": "levels is the test sphere's subdivisions, 2 to 5"}
	var mesh := KMeshSubdiv.subdivide(KMeshPrims.cube(Vector3.ONE, 1), levels)
	for i in mesh.verts.size():
		mesh.verts[i] = mesh.verts[i].normalized() * 0.5
	mesh.rebuild()
	var c := Vector3(0.5, 0.0, 0.0)
	var tb := mesh.triangle_count()
	var t0 := Time.get_ticks_usec()
	var st := KMeshDyntopo.step_mesh(mesh, c, radius, detail)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var tris := PackedInt32Array()
	for f in mesh.faces:
		for q in 3:
			tris.append((f as PackedInt32Array)[q])
	var b := KMeshDyntopo.band_report(mesh.verts, tris, c, radius, detail * radius)
	return {"ok": true, "result": {"tris_before": tb, "tris_after": mesh.faces.size(), "splits": st["splits"], "collapses": st["collapses"],
		"band_n": b["n"], "band_bad": b["bad"], "edge_min_mm": snappedf(float(b["min"]) * 1000.0, 0.01), "edge_max_mm": snappedf(float(b["max"]) * 1000.0, 0.01),
		"l_max_mm": snappedf(detail * radius * 1000.0, 0.01), "manifold": mesh.is_manifold(), "native": st.get("native", false), "ms": snappedf(ms, 0.01)}}
