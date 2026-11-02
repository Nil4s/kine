## s212 NAME BODIES, the export side. A Part's bodies can be named (Part "bname" step; Part.body_name). When the part on screen has a named body, the export
## objects (the .glb "What to export" list, the .obj groups) are one mesh object PER BODY, each called by its body's name, instead of one object for the whole
## part. A part with no named body is exported exactly as before (one object named by the part). Each per-body object carries "group": the part's name,
## so "Only the selected object" (the part) still picks all of them.
class_name PartNames
extends RefCounted


## fp = the one-object export of the free part ({"name", "mesh", "xf"}); pu = the PartUI that drew it. Returns the objects to export
static func objects(fp: Dictionary, pu: Object) -> Array:
	if fp.is_empty() or pu == null:
		return [fp]
	var res: Dictionary = pu.get("res")
	var names: Array = res.get("body_names", [])
	var named := false
	for i in names.size():
		if String(names[i]) != "Body%d" % (i + 1):
			named = true
	var pm: MeshInstance3D = pu.get("part_mesh")
	if not named or pm == null or pm.mesh == null:
		return [fp]
	var sb: Array = res.get("surf_body", [])
	var per := {}
	for s in pm.mesh.get_surface_count():
		if s >= sb.size():
			continue
		var bi := int(sb[s])
		if not per.has(bi):
			per[bi] = ArrayMesh.new()
		(per[bi] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm.mesh.surface_get_arrays(s))
	var out := []
	var keys: Array = per.keys()
	keys.sort()
	for bi in keys:
		out.append({"name": String(names[bi]) if bi < names.size() else "Body%d" % (bi + 1), "mesh": per[bi], "xf": fp.get("xf", Transform3D.IDENTITY), "group": String(fp["name"])})
	return out if not out.is_empty() else [fp]


## the file's stem for an export of these objects when one was picked: the part's name when the objects are its bodies
static func stem_of(o: Dictionary) -> String:
	return String(o.get("group", o["name"]))
