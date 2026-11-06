## L19 USD-WIRE: the character dictionary of UsdExport.text_skinned / write_skinned (PR #232), built from the app's real state.
##   character(S, B, main, opts)   what the viewport shows: the imported CharImport character when one stands on the fighter, else
##                                 the mannequin (the visible skinned pieces of main.man_root, with the scene's proportions), plus the
##                                 face geometry (mask, two eyeballs, the 6 AU shapes as BlendShapes) when main.face_geo_on.
##   standalone(S, B, face_on, opts)  the same without a running app (tools/export_usd.gd --skinned): a fresh mannequin.
## VERTEX ORDER of the file: the visible skinned MeshInstance3D in tree order, surfaces in order; then, with the face on, the mask
## and the two eyeballs. Space: Kine's rest space (Body.p0), so the weights, rest and the SkelAnimation of UsdExport line up.
## WEIGHTS: each bone's weight goes to the nearest ancestor that is a Kine joint (Body.ORDER); the root and the extra bones follow the
## pelvis; a vertex with no weight is bound to the pelvis. All influences are kept (no truncation), normalised to 1.
## IMPORTED: the character is posed to Kine's REST pose (CharImport.pose with a zero-angle body of the scene's proportions) and its
## mesh is written in that pose, carried into Kine's frame by ratio * C * base; the Kine skeleton then drives it with Kine's G / P,
## which is what CharImport.pose does to the imported skeleton on screen (a bone with no Kine joint follows its mapped parent).
## Blend shapes of the import are written aligned the same way (a delta = skin(v + d) - skin(v) at that pose), weights 0 unless
## opts["shape_w"] (Callable(t) -> {name: weight}) says otherwise: nothing in the app drives an import's shapes.
## FACE: the AU weights per frame are main._face_geo_draw's map (AU1 / AU4 from the mean brow, AU6 squint, AU45 blink) + the extra AU
## (face_geo_au) + AU26 = the jaw channel / 27.5 deg. The jaw is a bone on screen (a rotation) and a LINEAR shape here, so a half-open
## jaw is off by a chord (about 0.7 mm at 14 deg); the eyeballs are written still (their yaw / pitch are not exported).
class_name UsdWire
extends RefCounted


## a body with the scene's proportions at its zero pose (main's B is never touched)
static func scratch(B: Body, S: Scene) -> Body:
	var b := Body.new()
	b.load_files(B._files[0], B._files[1])
	if b.body != S.body:
		b.set_proportions(S.body)
	b.fk()
	return b


## the face AU weights for a Face.pose result P and the extra AU
static func au_weights(P: Dictionary, extra: Dictionary) -> Dictionary:
	var bv := (float(P["brow_l"]) + float(P["brow_r"])) * 0.5
	var au := {"AU1": maxf(bv, 0.0), "AU4": maxf(-bv, 0.0), "AU6": float(P["squint"]), "AU45": float(P["blink"]),
		"AU26": float(P["jaw_deg"]) / FaceGeo.JAW_MAX_DEG}
	for k in extra:
		au[k] = float(au.get(k, 0.0)) + float(extra[k])
	return au


## the dictionary of what main shows now ({} when there is nothing to export)
static func character(S: Scene, B: Body, m: Node, opts := {}) -> Dictionary:
	if CharImportApp.active(m):
		return imported_character(S, B, m, opts)
	if m.get("man_root") == null:
		return {}
	var face := {}
	if bool(m.get("face_geo_on")) and not (m.get("face_geo_data") as Dictionary).is_empty():
		face = {"data": m.get("face_geo_data"), "extra": m.get("face_geo_au")}
	return body_character(S, B, m.get("man_root"), face, opts)


## a fresh mannequin (no app): face_on builds the face geometry on its head
static func standalone(S: Scene, B: Body, face_on := false, opts := {}) -> Dictionary:
	var holder := Node3D.new()
	var mq := Overlays.mannequin(holder, StandardMaterial3D.new())
	var man: Node3D = mq[0]
	var pieces := Overlays.split_parts(man, mq[1], mq[2])
	var face := {}
	if face_on and pieces.has("head"):
		var hp: MeshInstance3D = pieces["head"]
		var pts := PackedVector3Array()
		for si in hp.mesh.get_surface_count():
			var arr := hp.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
				pts.append(vs[i])
		var d := FaceGeo.build(pts)
		hp.mesh = FaceGeo.cut_head(hp.mesh as ArrayMesh, d)
		face = {"data": d, "extra": opts.get("au", {})}
	var ch := body_character(S, B, man, face, opts)
	holder.free()
	return ch


static func _new() -> Dictionary:
	return {"verts": PackedVector3Array(), "faces": [], "rows": [], "sh": {}}


## nearest-ancestor joint index per bone; of: bone index -> joint name
static func _joint_ids(sk: Skeleton3D, of: Dictionary) -> Dictionary:
	var out := {}
	for b in sk.get_bone_count():
		var c := b
		while c >= 0 and not of.has(c):
			c = sk.get_bone_parent(c)
		out[b] = Body.ORDER.find(of[c]) if c >= 0 else 0
	return out


## append one skinned mesh in its current pose: T carries the skeleton's space into Kine's rest space. The pieces split_parts makes
## each hold ALL the vertices of the body and only their own triangles: a surface whose vertex positions were seen before
## adds only its triangles (the first piece met supplies the weights), so the file holds the vertices once.
static func _add(acc: Dictionary, sk: Skeleton3D, mi: MeshInstance3D, T: Transform3D, jid: Dictionary, tri_from := []) -> void:
	var am := mi.mesh as ArrayMesh
	var base_pts := CharImport.skin_points(sk, mi)
	var shapes := CharImport.shapes_of(mi)
	var V: PackedVector3Array = acc["verts"]
	var seen: Dictionary = acc.get("seen", {})
	var sn := mi.skin
	var bind_bone := []
	for k in sn.get_bind_count():
		bind_bone.append(SkinPaint.bind_bone(sn, sk, k))
	for si in am.get_surface_count():
		var arr := am.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv := vs.size()
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var key := hash(vs)   # the vertices: the pieces share them (their weights may be carried per piece by the weight-paint and corrective passes)
		var off: int
		if seen.has(key):
			off = seen[key]
		else:
			off = V.size()
			seen[key] = off
			var per := bo.size() / maxi(nv, 1)
			for i in nv:
				V.append(T * (base_pts[si] as PackedVector3Array)[i])
				var d := {}
				for q in per:
					var wk := w[i * per + q]
					if wk > 0.0:
						var j: int = jid[bind_bone[bo[i * per + q]]]
						d[j] = float(d.get(j, 0.0)) + wk
				if d.is_empty():
					d[0] = 1.0
				var tot := 0.0
				for j in d:
					tot += float(d[j])
				var row := []
				for j in d:
					row.append([int(j), float(d[j]) / tot])
				(acc["rows"] as Array).append(row)
			for nm in shapes:
				var skin1: PackedVector3Array = CharImport.skin_points(sk, mi, {si: (shapes[nm] as Array)[si]})[si]
				var b0: PackedVector3Array = base_pts[si]
				var part := PackedVector3Array()
				for i in b0.size():
					part.append(T.basis * (skin1[i] - b0[i]))
				if not (acc["sh"] as Dictionary).has(nm):
					acc["sh"][nm] = {}
				acc["sh"][nm][off] = part
		var lists := []
		if tri_from.is_empty():
			lists.append(arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(nv)))
		else:
			for pc in tri_from:
				var pm := (pc as MeshInstance3D).mesh as ArrayMesh
				if si < pm.get_surface_count() and pm.surface_get_array_len(si) == nv:
					var pi = pm.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
					if pi != null:
						lists.append(pi)
		for ix in lists:
			for t in range(0, (ix as PackedInt32Array).size() - 2, 3):
				(acc["faces"] as Array).append(PackedInt32Array([off + ix[t], off + ix[t + 1], off + ix[t + 2]]))
	acc["verts"] = V
	acc["seen"] = seen


## the dict text_skinned wants, from the accumulator
static func _finish(acc: Dictionary, S: Scene, opts: Dictionary, extra_shapes := []) -> Dictionary:
	var verts: PackedVector3Array = acc["verts"]
	var nv := verts.size()
	var rows: Array = acc["rows"]
	var K := 1
	for r in rows:
		K = maxi(K, (r as Array).size())
	var ids := PackedInt32Array()
	var w := PackedFloat32Array()
	for r in rows:
		for q in K:
			if q < (r as Array).size():
				ids.append(int(r[q][0]))
				w.append(float(r[q][1]))
			else:
				ids.append(-1)
				w.append(0.0)
	var shapes := []
	var zero_w := {}
	for nm in acc["sh"]:
		var o := PackedVector3Array()
		o.resize(nv)
		for st in acc["sh"][nm]:
			var part: PackedVector3Array = acc["sh"][nm][st]
			for i in part.size():
				o[int(st) + i] = part[i]
		shapes.append({"name": nm, "offsets": o, "sparse": true})
		zero_w[nm] = 0.0
	shapes.append_array(extra_shapes)
	var swf: Callable = opts.get("shape_w", Callable())
	if not swf.is_valid():
		swf = func(_t: float) -> Dictionary: return zero_w
	return {"name": "Body", "verts": verts, "faces": acc["faces"], "k": K, "ids": ids, "w": w, "shapes": shapes, "shape_w": swf}


static func body_character(S: Scene, B: Body, man_root: Node3D, face := {}, opts := {}) -> Dictionary:
	var Bk := scratch(B, S)
	var dup: Node3D = man_root.duplicate()
	var sk: Skeleton3D = dup.find_children("*", "Skeleton3D", true, false)[0]
	sk.reset_bone_poses()
	Proportions.bake_mannequin(dup, sk, Bk)   # the scene's proportions in the rest skeleton and the skin (nothing for the default body)
	var of := {}
	for j in Body.ORDER:
		var bi := sk.find_bone("Head" if j == "head" else j)
		if bi >= 0:
			of[bi] = j
	var jid := _joint_ids(sk, of)
	var T := AnimImport._scene_xf(sk, dup)
	var acc := _new()
	var vis := []
	var orig := []
	for mi in dup.find_children("*", "MeshInstance3D", true, false):
		var x := mi as MeshInstance3D
		if x.skin == null or not (x.mesh is ArrayMesh):
			continue
		if x.visible:
			vis.append(x)
		elif not String(x.name).begins_with("piece_"):
			orig.append(x)
	# The live pieces are rebuilt each frame by the corrective pass (bulges, girth): their vertices are the POSED, corrected ones.
	# The hidden original mannequin mesh is the untouched rest mesh; the triangles are the visible pieces' (a hidden part is not in).
	if orig.size() == 1:
		_add(acc, sk, orig[0], T, jid, vis)
	else:
		for x in vis:
			_add(acc, sk, x, T, jid)
	var extra_shapes := []
	var swf_face := Callable()
	if not face.is_empty():
		extra_shapes = _add_face(acc, face["data"], Body.ORDER.find("head"))
		var fx: Dictionary = face.get("extra", {})
		swf_face = func(t: float) -> Dictionary:
			return au_weights(Face.at(S.face, S.lip, t, S.expr_at(t)), fx)
	dup.free()
	# the face shapes are sized now that the vertex count is known
	var nv := (acc["verts"] as PackedVector3Array).size()
	for sh in extra_shapes:
		var tab: PackedVector3Array = sh["offsets"]
		var o := PackedVector3Array()
		o.resize(nv)
		var at: int = sh["at"]
		for i in tab.size():
			o[at + i] = tab[i]
		sh["offsets"] = o
		sh.erase("at")
	var o2 := opts.duplicate()
	if swf_face.is_valid():
		o2["shape_w"] = swf_face
	return _finish(acc, S, o2, extra_shapes)


## the mask and the eyeballs, all on the head joint; returns the six AU shapes (offsets of the mask only, "at" = where it starts)
static func _add_face(acc: Dictionary, d: Dictionary, head: int) -> Array:
	var verts: PackedVector3Array = acc["verts"]
	var at := verts.size()
	var mv: PackedVector3Array = d["verts"]
	for v in mv:
		verts.append(v)
		(acc["rows"] as Array).append([[head, 1.0]])
	var tr: PackedInt32Array = d["tris"]
	for t in range(0, tr.size() - 2, 3):
		(acc["faces"] as Array).append(PackedInt32Array([at + tr[t], at + tr[t + 1], at + tr[t + 2]]))
	for e in d["eyes"]:
		var ea := FaceGeo.eye_arrays(float(e["r"]))
		var ev: PackedVector3Array = ea[Mesh.ARRAY_VERTEX]
		var off := verts.size()
		for v in ev:
			verts.append((e["c"] as Vector3) + v)
			(acc["rows"] as Array).append([[head, 1.0]])
		var ei: PackedInt32Array = ea[Mesh.ARRAY_INDEX]
		for t in range(0, ei.size() - 2, 3):
			(acc["faces"] as Array).append(PackedInt32Array([off + ei[t], off + ei[t + 1], off + ei[t + 2]]))
	acc["verts"] = verts
	var out := []
	for au in FaceGeo.AUS:
		out.append({"name": au, "offsets": (d["au"][au] as PackedVector3Array).duplicate(), "sparse": true, "at": at})
	return out


static func imported_character(S: Scene, B: Body, m: Node, opts := {}) -> Dictionary:
	var st := CharImportApp.state(m)
	var chd: Dictionary = st["ch"]
	var mapping: Dictionary = st["mapping"]
	var sk: Skeleton3D = chd["sk"]
	var R := scratch(B, S)
	var ft := CharImport.fit(chd["src"], mapping, R)
	if not ft["ok"]:
		return {}
	var keep := []
	for i in sk.get_bone_count():
		keep.append(sk.get_bone_pose(i))
	CharImport.pose(chd, mapping, ft, R)   # Kine's rest pose onto the character
	var of := {}
	for j in mapping["map"]:
		of[int(mapping["map"][j])] = j
	var jid := _joint_ids(sk, of)
	var base: Transform3D = (chd["src"] as Dictionary).get("base", Transform3D.IDENTITY)
	var T := Transform3D(Basis(ft["C"] as Quaternion).scaled(Vector3.ONE * float(ft["ratio"])), Vector3.ZERO) * base
	var acc := _new()
	for mi in chd["meshes"]:
		_add(acc, sk, mi, T, jid)
	# the character's own joint positions at that rest pose (its bone lengths, not Kine's): the app turns the mesh about THESE
	var g := []
	g.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		var pb := sk.get_bone_parent(b)
		g[b] = (g[pb] as Transform3D) * sk.get_bone_pose(b) if pb >= 0 else sk.get_bone_pose(b)
	var rest_p0 := {}
	for j in Body.ORDER:
		var par: String = B.parent[j]
		if of.values().has(j):
			var bi := -1
			for k in of:
				if of[k] == j:
					bi = int(k)
			rest_p0[j] = T * (g[bi] as Transform3D).origin
		elif par != "":
			rest_p0[j] = (rest_p0[par] as Vector3) + (B.p0[j] as Vector3) - (B.p0[par] as Vector3)
		else:
			rest_p0[j] = B.p0[j]
	for i in keep.size():
		sk.set_bone_pose(i, keep[i])
	var out := _finish(acc, S, opts)
	if not out.is_empty():
		out["rest_p0"] = rest_p0
	return out
