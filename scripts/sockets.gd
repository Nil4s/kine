## sockets.gd - ENGINE SOCKETS FROM ANATOMY (N089). weapon_r, weapon_l, back_sheath, hip_holster_r, head_fx: each a parent bone and a
## local transform in that bone's REST frame, placed from the anatomy tags (KMeshAnatomy) of the proportioned, girth-baked mannequin skin and
## the skeleton, so they follow stature, segment lengths and girth. No fixed offsets: every number below is a fraction of a measured length.
##   weapon_r / weapon_l : parent hand_*. On the hand axis (wrist -> middle knuckle) at the along-axis centroid of the palm-tagged skin (grip centre).
##   back_sheath         : parent spine_03. On the middle line, half way up the scapula-tagged skin, 1.5 cm proud of the rearmost skin there.
##   hip_holster_r       : parent pelvis. At the right hip joint's z, 0.08 thigh lengths above the joint (greater trochanter), 5 mm outside the
##                         outermost skin at that height.
##   head_fx             : parent head. Above the highest skull-tagged skin point by 0.4 of the head-bone-to-vertex length.
## Written into the engine export by patch_glb (EngineExport.export): a node "socket_<name>" under the parent bone's joint node.
class_name Sockets
extends RefCounted

const NAMES := ["weapon_r", "weapon_l", "back_sheath", "hip_holster_r", "head_fx"]
const PARENT := {"weapon_r": "hand_r", "weapon_l": "hand_l", "back_sheath": "spine_03", "hip_holster_r": "pelvis", "head_fx": "head"}


## the bone index for a name, any case ("Head" in the mannequin's glb); -1 when absent
static func bone(sk: Skeleton3D, nm: String) -> int:
	var i := sk.find_bone(nm)
	if i >= 0:
		return i
	var low := nm.to_lower()
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).to_lower() == low:
			return b
	return -1


static func _rel(n: Node3D, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != stop and c is Node3D:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


## the mannequin's skin as one KMesh in the skeleton's space
static func skin(man: Node3D, sk: Skeleton3D) -> KMesh:
	var vs := PackedVector3Array()
	var fs := []
	var sx := _rel(sk, man)
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		if am == null:
			continue
		var xf := sx.affine_inverse() * _rel(mi as Node3D, man)
		for si in am.get_surface_count():
			var k := KMesh.new().from_array_mesh(am, si)
			var o := vs.size()
			for p in k.verts:
				vs.append(xf * p)
			for f in k.faces:
				var g := PackedInt32Array(f)
				for i in g.size():
					g[i] += o
				fs.append(g)
	return KMesh.new().from_arrays(vs, fs)


static func _pts(skin_m: KMesh, tags: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in skin_m.verts.size():
		if tags.has(KMeshAnatomy.tag_of(skin_m, v)):
			out.append(skin_m.verts[v])
	return out


## name -> {"parent": bone name, "local": Transform3D in the parent's rest frame}
static func compute(man: Node3D, sk: Skeleton3D) -> Dictionary:
	var k := skin(man, sk)
	KMeshAnatomy.seed_tags(k, sk)
	return compute_from(k, sk)


static func compute_from(k: KMesh, sk: Skeleton3D) -> Dictionary:
	var at := func(nm: String) -> Vector3: return sk.get_bone_global_rest(bone(sk, nm)).origin
	var W := {}
	for side in ["_r", "_l"]:
		var a: Vector3 = at.call("hand" + side)
		var ab: Vector3 = (at.call("middle_01" + side) as Vector3) - a
		var palm := _pts(k, ["palm" + side])
		var t := 0.5
		if not palm.is_empty():
			var s := 0.0
			for p in palm:
				s += (p - a).dot(ab) / ab.length_squared()
			t = s / palm.size()
		W["weapon" + side] = a + ab * t
	# back_sheath: between the scapulae
	var y0 := INF
	var y1 := -INF
	for p in _pts(k, ["scapula_l", "scapula_r"]):
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var by := (y0 + y1) * 0.5
	var zb := INF
	for p in k.verts:
		if absf(p.y - by) < 0.02 and absf(p.x) < 0.02:
			zb = minf(zb, p.z)
	W["back_sheath"] = Vector3(0.0, by, zb - 0.015)
	# hip_holster_r: greater trochanter, on the hip surface
	var hj: Vector3 = at.call("thigh_r")
	var knee: Vector3 = at.call("calf_r")
	var hy := hj.y + 0.08 * hj.distance_to(knee)
	var xmin := INF
	for p in k.verts:
		if absf(p.y - hy) < 0.02 and p.x < 0.0 and absf(p.z - hj.z) < 0.08:
			xmin = minf(xmin, p.x)
	W["hip_holster_r"] = Vector3(xmin - 0.005, hy, hj.z)
	# head_fx: above the vertex
	var tv := Vector3(0, -INF, 0)
	var sp := _pts(k, ["skull"])
	for p in (sp if not sp.is_empty() else k.verts):
		if p.y > tv.y:
			tv = p
	var hd: Vector3 = at.call("head")
	W["head_fx"] = Vector3(tv.x, tv.y + 0.4 * (tv.y - hd.y), tv.z)
	var out := {}
	for n in NAMES:
		var pn: String = PARENT[n]
		var rest := sk.get_bone_global_rest(bone(sk, pn))
		out[n] = {"parent": pn, "local": rest.affine_inverse() * Transform3D(Basis.IDENTITY, W[n])}
	return out


## a socket's position in skeleton space
static func world(sk: Skeleton3D, e: Dictionary) -> Vector3:
	return sk.get_bone_global_rest(bone(sk, String(e["parent"]))) * (e["local"] as Transform3D).origin


## the sockets of a built mannequin tree (finds its skeleton)
static func compute_root(man: Node3D) -> Dictionary:
	var sks := man.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return {}
	return compute(man, sks[0])


## rewrite the .glb's JSON chunk: a node "socket_<name>" (translation + rotation of the local transform) child of the parent
## bone's joint node. Returns OK or an error.
static func patch_glb(path: String, socks: Dictionary) -> Error:
	if socks.is_empty():
		return OK
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 20 or b.slice(0, 4).get_string_from_ascii() != "glTF" or b.slice(16, 20).get_string_from_ascii() != "JSON":
		return ERR_FILE_CORRUPT
	var jlen := b.decode_u32(12)
	var doc: Variant = JSON.parse_string(b.slice(20, 20 + jlen).get_string_from_utf8())
	if not doc is Dictionary:
		return ERR_FILE_CORRUPT
	var nodes: Array = (doc as Dictionary).get("nodes", [])
	var by_name := {}
	for i in nodes.size():
		var nm := String((nodes[i] as Dictionary).get("name", "")).to_lower()
		if not by_name.has(nm):
			by_name[nm] = i
	for n in NAMES:
		if not socks.has(n) or not by_name.has(String(socks[n]["parent"]).to_lower()):
			continue
		var tr: Transform3D = socks[n]["local"]
		var q := tr.basis.get_rotation_quaternion()
		var o := tr.origin
		nodes.append({"name": "socket_" + n, "translation": [o.x, o.y, o.z], "rotation": [q.x, q.y, q.z, q.w],
			"extras": {"kine_socket": n, "parent": String(socks[n]["parent"])}})
		var pn: Dictionary = nodes[by_name[String(socks[n]["parent"]).to_lower()]]
		var ch: Array = pn.get("children", [])
		ch.append(nodes.size() - 1)
		pn["children"] = ch
	(doc as Dictionary)["nodes"] = nodes
	var jb := JSON.stringify(doc, "", false).to_utf8_buffer()
	while jb.size() % 4 != 0:
		jb.append(0x20)
	var rest := b.slice(20 + jlen)
	var outb := PackedByteArray()
	outb.append_array("glTF".to_ascii_buffer())
	outb.append_array(CustomAttr._u32(2))
	outb.append_array(CustomAttr._u32(12 + 8 + jb.size() + rest.size()))
	outb.append_array(CustomAttr._u32(jb.size()))
	outb.append_array("JSON".to_ascii_buffer())
	outb.append_array(jb)
	outb.append_array(rest)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(outb)
	f.close()
	return OK
