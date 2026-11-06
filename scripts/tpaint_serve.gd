## tpaint_serve.gd - SERVE `texture_paint` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (L53).
##   {shape?: "sphere"|"cylinder", x?, y?, radius?, size?, color?, strength?, hardness?, pad?, w?, h?}: one brush stamp in SCREEN px onto a built-in
##   UV-mapped shape (camera 3 m back, fov 50) and the numbers: texels written, the stamp's screen coverage %, engine (native / gdscript), ms, the
##   texture hash. A stamp over a UV seam writes both islands (scripts/kmesh_tpaint.gd). The live model preview paints through Texture mode.
class_name TPaintServe
extends RefCounted


static func serve(_m, p: Dictionary) -> Dictionary:
	var shape := String(p.get("shape", "sphere"))
	if shape != "sphere" and shape != "cylinder":
		return {"ok": false, "error": "texture_paint: shape is \"sphere\" or \"cylinder\""}
	var size := int(p.get("size", 512))
	var w := int(p.get("w", 512))
	var h := int(p.get("h", 512))
	var r := float(p.get("radius", 60.0))
	if size < 64 or size > 4096 or w < 16 or h < 16 or w > 4096 or h > 4096:
		return {"ok": false, "error": "texture_paint: size is 64..4096 and w, h are 16..4096"}
	if r <= 0.0 or r > 4000.0:
		return {"ok": false, "error": "texture_paint: radius is the brush radius in screen px, more than 0 (e.g. 60)"}
	var strength := clampf(float(p.get("strength", 1.0)), 0.0, 1.0)
	var hardness := clampf(float(p.get("hardness", 0.5)), 0.0, 1.0)
	var pad := clampi(int(p.get("pad", 2)), 0, 16)
	var col := Color.from_string(String(p.get("color", "#e61a1a")), Color(-1, 0, 0))
	if col.r < 0.0:
		return {"ok": false, "error": "texture_paint: color is an HTML colour such as \"#e61a1a\""}
	var k: KMesh = KMeshPrims.uv_sphere(1.0, 32, 16) if shape == "sphere" else KMeshPrims.cylinder(0.7, 2.0, 32, 4)
	if shape == "sphere":
		KMeshUV.project_sphere(k)
	else:
		KMeshUV.project_cylinder(k)
	var tp := KMeshTPaint.new(k, size)
	var cp := Vector3(0, 0, 3)
	var mvp := Projection.create_perspective(50.0, float(w) / float(h), 0.05, 50.0) * Projection(Transform3D(Basis(), cp).affine_inverse())
	var t0 := Time.get_ticks_usec()
	var n := tp.stamp(mvp, cp, Vector2i(w, h), Vector2(float(p.get("x", w * 0.5)), float(p.get("y", h * 0.5))), r, col, strength, hardness, pad)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	return {"ok": true, "shape": shape, "texels": n, "islands": 1, "screen_pct": snappedf(100.0 * PI * r * r / float(w * h), 0.01),
		"engine": tp.engine, "ms": snappedf(ms, 0.01), "tex_hash": tp.hash().left(16)}
