extends SceneTree
## BODY: SMOOTH (second body option; the mannequin stays the default). Builds assets/body_smooth.glb:
## the shipped mannequin scene (its skeleton, rest pose, Skin and node names untouched) whose mesh is Quaternius
## Universal Base Characters "Superhero_Male" (CC0) fitted onto the mannequin's 65 joints, with
##   - the mannequin's EGG HEAD put on the Head bone in place of the sculpted head (the drawn face, face.gd, sits on the
##     egg: same triangles, same rest coordinates, so Face.anchors reads the same numbers), and
##   - the soles lifted to the mannequin's own floor line (the fit leaves them 1 cm under y = 0).
## STEPS (the Blender one is kept next to this file, tools/smoothbody_fit.py):
##   1. blender -b --python tools/smoothbody_fit.py -- assets/mannequin.glb <Superhero_Male_FullBody.gltf> <fit.glb> 1.0 Eyebrows,Eyes
##   2. godot --headless --path . -s tools/smoothbody_build.gd -- <fit.glb> <abs path>/assets/body_smooth.glb
## Then reads the written file back: 65/65 bones, rest gap, triangles, lowest vertex, the head's triangle count.
## The source: https://quaternius.itch.io/universal-base-characters (Standard, free, CC0 1.0).

const SOLE := 0.00046   # Proportions.MESH_SOLE: where the mannequin's own soles are


static func bind_index(skin: Skin, sk: Skeleton3D) -> Dictionary:
	var out := {}
	for i in skin.get_bind_count():
		var n := String(skin.get_bind_name(i))
		if n == "":
			n = sk.get_bone_name(skin.get_bind_bone(i))
		out[n.to_lower()] = i
	return out


static func gen(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	return doc.generate_scene(st)


static func empty() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}


## the triangles in tris (corner indices) of surface arrays a: vertices re-numbered, 4 bone slots, weights summing to 1
static func pick(a: Array, tris: PackedInt32Array) -> Dictionary:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var bn: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var wt: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bn.size() / v.size()
	var map := {}
	var o := empty()
	for i in tris:
		if not map.has(i):
			map[i] = o["v"].size()
			o["v"].append(v[i])
			o["n"].append(nn[i])
			o["uv"].append(uv[i] if uv.size() == v.size() else Vector2.ZERO)
			var sum := 0.0
			for k in 4:
				sum += wt[i * per + k]
			for k in 4:
				o["b"].append(bn[i * per + k])
				o["w"].append(wt[i * per + k] / sum if sum > 0.0 else (1.0 if k == 0 else 0.0))
		o["i"].append(map[i])
	return o


static func append(into: Dictionary, part: Dictionary) -> void:
	var off: int = into["v"].size()
	for k in ["v", "n", "uv", "b", "w"]:
		into[k].append_array(part[k])
	for i in part["i"]:
		into["i"].append(i + off)


## the triangles of surface arrays a whose corners weigh most on the binds in `heads` (head = true) or not (false)
static func split(a: Array, heads: Dictionary, head: bool) -> PackedInt32Array:
	var bn: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var wt: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bn.size() / (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out := PackedInt32Array()
	for t in range(0, ix.size(), 3):
		var hw := 0.0
		var tw := 0.0
		for k in 3:
			for q in per:
				tw += wt[ix[t + k] * per + q]
				if heads.get(bn[ix[t + k] * per + q], false):
					hw += wt[ix[t + k] * per + q]
		if (hw * 2.0 > tw) == head:
			out.append_array(ix.slice(t, t + 3))
	return out


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	root.add_child(man)
	var cand := gen(args[0])
	root.add_child(cand)
	await process_frame
	var msk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var mmi: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
	var mb := bind_index(mmi.skin, msk)
	var csk: Skeleton3D = cand.find_children("*", "Skeleton3D", true, false)[0]
	# the binds that belong to the head part (Overlays.split_parts' rule: the bone itself or its nearest body-joint ancestor)
	var ours := {}
	for j in Body.ORDER:
		ours[msk.find_bone("Head" if j == "head" else j)] = true
	var head_bone := msk.find_bone("Head")
	var heads := {}
	for i in mmi.skin.get_bind_count():
		var c: int = mmi.skin.get_bind_bone(i)
		if c < 0:
			c = msk.find_bone(mmi.skin.get_bind_name(i))
		while c >= 0 and not ours.has(c):
			c = msk.get_bone_parent(c)
		heads[i] = (c == head_bone)
	var body := empty()
	var low := 1000.0
	var cut := 0
	for cmi in cand.find_children("*", "MeshInstance3D", true, false):
		var src := cmi as MeshInstance3D
		var cb := bind_index(src.skin, csk)
		var remap := {}
		for n in cb:
			remap[cb[n]] = mb.get(n, mb.get("pelvis"))
		var xf := mmi.global_transform.affine_inverse() * src.global_transform
		for si in src.mesh.get_surface_count():
			var a: Array = src.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i] = xf * v[i]
				nn[i] = (xf.basis * nn[i]).normalized()
				low = minf(low, v[i].y)
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			for i in bones.size():
				bones[i] = remap.get(bones[i], 0)
			a[Mesh.ARRAY_VERTEX] = v
			a[Mesh.ARRAY_NORMAL] = nn
			a[Mesh.ARRAY_BONES] = bones
			cut += split(a, heads, true).size() / 3   # the sculpted head's triangles go
			append(body, pick(a, split(a, heads, false)))
	var lift := SOLE - low
	for i in body["v"].size():
		body["v"][i].y += lift
	# the mannequin's egg head, on the Head bone, where it always was
	var ma: Array = mmi.mesh.surface_get_arrays(0)
	var htri := split(ma, heads, true)
	append(body, pick(ma, htri))
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = body["v"]
	out[Mesh.ARRAY_NORMAL] = body["n"]
	out[Mesh.ARRAY_TEX_UV] = body["uv"]
	out[Mesh.ARRAY_BONES] = body["b"]
	out[Mesh.ARRAY_WEIGHTS] = body["w"]
	out[Mesh.ARRAY_INDEX] = body["i"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mmi.mesh = am
	cand.queue_free()
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap)
		ap.free()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var e := doc.append_from_scene(man, st)
	if e == OK:
		e = doc.write_to_filesystem(st, args[1])
	print("WRITE ", args[1], " err ", e, " verts ", body["v"].size(), " tris ", body["i"].size() / 3, " head tris ", htri.size() / 3, " sculpted-head tris cut ", cut, " lift ", lift)
	# read back: every bone's rest against the shipped file's, and the mesh's extent
	var back := gen(args[1])
	root.add_child(back)
	await process_frame
	var bsk: Skeleton3D = back.find_children("*", "Skeleton3D", true, false)[0]
	var worst_p := 0.0
	var worst_r := 0.0
	var missing := []
	for b in msk.get_bone_count():
		var n := msk.get_bone_name(b)
		var bb := bsk.find_bone(n)
		if bb < 0:
			missing.append(n)
			continue
		var r0 := msk.get_bone_rest(b)
		var r1 := bsk.get_bone_rest(bb)
		worst_p = maxf(worst_p, r0.origin.distance_to(r1.origin))
		worst_r = maxf(worst_r, rad_to_deg(r0.basis.get_rotation_quaternion().angle_to(r1.basis.get_rotation_quaternion())))
	var bm: MeshInstance3D = back.find_children("*", "MeshInstance3D", true, false)[0]
	var bv: PackedVector3Array = bm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := 1000.0
	var hi := -1000.0
	for p in bv:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	print("READBACK bones %d/%d missing %s worst rest gap %.6f m %.4f deg; verts %d, lowest y %.5f, highest y %.5f" % [bsk.get_bone_count(), msk.get_bone_count(), str(missing), worst_p, worst_r, bv.size(), lo, hi])
	quit()
