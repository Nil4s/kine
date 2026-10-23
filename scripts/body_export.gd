class_name BodyExport
extends RefCounted
## G12 (docs/ROADMAP_400.md): THE BODY AS A .glb WITH ITS SKIN WEIGHTS. The fighter's body (G01's KMesh, or a .kbody's) on
## the mannequin's own skeleton (assets/mannequin.glb, the UE5 bone names; "Head" written "head" by GltfExport._write), in
## its rest pose, no animation. Written by Godot's own GLTFDocument through GltfExport._write, so the skeleton, the names
## and the rest are the scene export's (GltfExport.build) to the bit.
## THE MESH: BaseBody.build, the same writer "Model: apply the body mesh to the fighter" uses: per surface one vertex per
##   distinct (KMesh vertex, UV) (a vertex on a UV seam is written once per side; normals are smooth per vertex, so they
##   never split one), the 4 heaviest bones per vertex in whole 1/65535 steps adding up to 1 (BaseBody.canon), a vertex
##   with no weight given its nearest bone. Bind poses are the file's own skin (the fighter's binds by name).
## PROPORTIONS: the scene's (B.set_proportions) are baked into the rest skeleton and the mesh as the scene export does
##   (Proportions.bake_mannequin); the mannequin as shipped (the default) leaves both as they are.
## FBX: not written. scripts/fbx_export.gd writes a skeleton and its curves only (no Geometry, no Skin / Cluster deformers,
##   no bind Pose for a mesh); a skinned mesh there is a new Geometry + Deformer + one Cluster per bone + connections, not a
##   small change. The .glb is read by Blender, Unreal 5, Godot and Unity (glTFast).
## WRITES: res://exports/<scene>_body.glb (the export folder, replaced per run; never a scene, pose, body or data file).

const DIR := "res://exports"


## the body as a node tree ready for GLTFDocument: the mannequin (no animation player) with its mesh replaced by k's.
## B (optional) bakes the proportions. -> [root, info {"verts", "tris", "unweighted"}]
static func build(k: KMesh, B: Body = null) -> Array:
	var man := GltfExport._mannequin(true)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var mis := man.find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = null
	for n in mis:
		if mi == null and (n as MeshInstance3D).skin != null:
			mi = n
		elif n != mi:
			n.get_parent().remove_child(n)
			n.free()
	var srcs := []
	var old := mi.mesh as ArrayMesh
	for si in old.get_surface_count():
		srcs.append({"mat": old.surface_get_material(si)})
	var b := BaseBody.build(k, mi.skin, sk, srcs)
	var am := ArrayMesh.new()
	var nv := 0
	var nt := 0
	for s in b["surfs"]:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s["arr"])
		am.surface_set_material(am.get_surface_count() - 1, s["mat"])
		nv += (s["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		nt += (s["arr"][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	mi.mesh = am
	mi.name = "body"
	if B != null:
		Proportions.bake_mannequin(man, sk, B)
	return [man, {"verts": nv, "tris": nt, "unweighted": b["unweighted"]}]


## write k as a .glb at path (res://, user:// or absolute). -> {"err", "path", "verts", "tris", "unweighted"}
static func write(k: KMesh, path: String, B: Body = null) -> Dictionary:
	var r := build(k, B)
	var err := GltfExport._write(r[0], path, true)
	var out: Dictionary = r[1]
	out["err"] = err
	out["path"] = path
	return out


## "Model: export the body as glb (skin weights)": the fighter's body as it is drawn now
static func export_cmd(m: Node, dir := DIR) -> String:
	if m.pieces.is_empty() or BaseBody.skin_of(m) == null:
		m._say("Model: the fighter has no skinned body to export")
		return ""
	var S: Scene = m._hero_scene()
	var path := "%s/%s_body.glb" % [dir, BodyFile._safe(S.name if S.name != "" else "scene")]
	var keep: Dictionary = m.B.state()
	var r := write(BaseBody.read(m), path, m.B)
	m.B.set_state(keep)
	m._refresh()
	if r["err"] != OK:
		m._say("Model: NOT EXPORTED: the .glb could not be written (%s)" % error_string(r["err"]))
		return ""
	m._say("Model: exported %s: the body (%d verts, %d triangles) skinned to the UE5-named skeleton, 4 weights per vertex, rest pose. Opens in Blender, Unreal 5, Godot; Unity via glTFast (no .fbx for the mesh yet)" % [path.get_file(), r["verts"], r["tris"]])
	return path
