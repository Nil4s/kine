class_name MeshQuality
extends RefCounted
## W05: the mesh quality choice of the 3D printing export (STL / 3MF): Coarse / Normal / Fine / Custom, with a live triangle count and an
## estimate of the file's size. A quality is a deflection (the most the mesh may sit off the true surface, mm) and a facet angle (radians),
## the two numbers KCad.tessellate takes. Normal is what the export always wrote (0.1 mm, 0.2 rad), so nothing changes unless it is chosen.
## Pure: no nodes. The estimate counts the triangles of the real tessellation (MeshExport.bodies_of) and sizes the file the writer would write:
## an STL is 84 + 50 bytes a triangle (exact); a 3MF is the deflated model text plus the zip's headers.

const NAMES := ["Coarse", "Normal", "Fine", "Custom"]
const PRESETS := {
	"Coarse": {"defl_mm": 0.5, "angle": 0.6},
	"Normal": {"defl_mm": 0.1, "angle": 0.2},
	"Fine": {"defl_mm": 0.01, "angle": 0.05},
}
const MIN_DEFL_MM := 0.005
const MAX_DEFL_MM := 5.0


## the quality for a name (Custom takes custom_mm); an unknown name is Normal. {"name", "defl_mm", "angle"}
static func of(qname: String, custom_mm := 0.1) -> Dictionary:
	if qname == "Custom":
		var d := clampf(custom_mm, MIN_DEFL_MM, MAX_DEFL_MM)
		return {"name": "Custom", "defl_mm": d, "angle": clampf(d * 2.0 + 0.1, 0.1, 0.6)}
	var p: Dictionary = PRESETS.get(qname, PRESETS["Normal"])
	return {"name": qname if PRESETS.has(qname) else "Normal", "defl_mm": float(p["defl_mm"]), "angle": float(p["angle"])}


## an estimate for bodies (MeshExport.bodies_of's) written as fmt "stl" | "3mf": {"tris", "bytes", "text"}
static func estimate(bodies: Array, fmt: String, title := "Part") -> Dictionary:
	var n := 0
	for b in bodies:
		n += (b["t"] as PackedInt32Array).size() / 3
	var bytes := 0
	if fmt == "stl":
		bytes = 84 + 50 * n
	else:
		bytes = 22
		for en in [["[Content_Types].xml", MeshExport.CONTENT_TYPES], ["_rels/.rels", MeshExport.RELS], ["3D/3dmodel.model", MeshExport.model_xml(bodies, title)]]:
			var raw := String(en[1]).to_utf8_buffer()
			var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
			bytes += (z.size() - 6) + 30 + 46 + 58 + 2 * String(en[0]).length()   # a zlib stream is a raw deflate + 6 bytes; local + central header; 58 = the zip packer's extra field, measured
	return {"tris": n, "bytes": bytes, "text": words(n, bytes)}


static func words(tris: int, bytes: int) -> String:
	var sz := "%d bytes" % bytes if bytes < 1024 else ("%.1f KB" % (bytes / 1024.0) if bytes < 1048576 else "%.2f MB" % (bytes / 1048576.0))
	return "about %s triangles, file about %s" % [_grp(tris), sz]


static func _grp(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += " "
		out += s[i]
	return out
