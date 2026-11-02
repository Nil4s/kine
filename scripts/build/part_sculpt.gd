class_name PartSculpt
extends RefCounted
## s227 "SCULPT THIS INTO THE PART": the one-step road between a Part and the sculpt mesh engine.
## open(): the sculpt page opens on a KMesh made from the part: the newest ornament / meshsolid step (its mesh is kept in the record, so a sculpt
## can be reopened again and again), else the picked body (its shown triangles), else a ball of clay. finish(): the sculpt comes back as ONE
## meshsolid step, ONE undo step: it takes the place of the step it was opened from (same id and name, "sculpt": true), or the place of the body
## ("replace": N), or is a new body. The solid keeps its place (keep_origin): the sculpt was drawn where the body stands.

const META := "s227_road"
const MM := 0.001


## the mesh a feature stands for, in metres where it stands in the part (one piece: the first); null when it is not a mesh step
static func feature_mesh(f: Dictionary) -> KMesh:
	match String(f.get("t", "")):
		"meshsolid":
			var vb := Marshalls.base64_to_raw(String(f.get("v", ""))).to_float32_array()
			var ib := Marshalls.base64_to_raw(String(f.get("f", ""))).to_int32_array()
			var vs := PackedVector3Array()
			for i in range(0, vb.size() - 2, 3):
				vs.append(Vector3(vb[i], vb[i + 1], vb[i + 2]) * MM)
			var fs: Array = []
			for i in range(0, ib.size() - 2, 3):
				fs.append(PackedInt32Array([ib[i], ib[i + 1], ib[i + 2]]))
			return KMesh.new().from_arrays(vs, fs)
		"ornament":
			var pcs := PartOrnament.pieces(f)
			if pcs.is_empty():
				return null
			var pc: Dictionary = pcs[0]
			var d := PartOrnament.mesh_dict(String(pc["kind"]), int(f.get("seed", 1)), pc["size"])
			if d.is_empty():
				return null
			var src: KMesh = d["km"]
			var bs := PartOrnament.basis_for(pc["dir"])
			var vs2 := PackedVector3Array()
			for p in src.verts:
				vs2.append(bs * p + (pc["at"] as Vector3) * MM)
			var fs2: Array = []
			for fc in src.faces:
				fs2.append((fc as PackedInt32Array).duplicate())
			return KMesh.new().from_arrays(vs2, fs2)
	return null


static func _pieces_of(f: Dictionary) -> int:
	return PartOrnament.pieces(f).size() if String(f.get("t", "")) == "ornament" else 1


## what the road would start from: {"mode": "feature" | "body" | "new", "fid", "body", "mesh": KMesh, "name"}
static func source(m: Node, fid := "") -> Dictionary:
	var rec: Dictionary = m.S.part
	var feats: Array = rec.get("features", [])
	var pick := -1
	if fid != "":
		pick = Part.index_of(rec, fid)
	else:
		for i in range(feats.size() - 1, -1, -1):
			if String((feats[i] as Dictionary).get("t", "")) in ["ornament", "meshsolid"] and not bool((feats[i] as Dictionary).get("off", false)):
				pick = i
				break
	if pick >= 0:
		var km := feature_mesh(feats[pick])
		if km != null and km.vert_count() > 3:
			return {"mode": "feature", "fid": String((feats[pick] as Dictionary)["id"]), "mesh": km, "name": String((feats[pick] as Dictionary).get("name", ""))}
	if not feats.is_empty():
		var res := Part.replay(rec)
		var nb := int(res["bodies"])
		if nb > 0 and res["mesh"] != null:
			var want := -1
			var pu = m.bld.part if m.get("bld") != null else null
			if pu != null and int(pu.sel_body) >= 0 and int(pu.sel_body) < nb:
				want = int(pu.sel_body)
			if want < 0:
				want = nb - 1
			var sb: Array = res["surf_body"]
			for s in sb.size():
				if int(sb[s]) == want:
					var km2 := KMesh.new().from_array_mesh(res["mesh"], s)
					if km2 != null and km2.vert_count() > 3:
						return {"mode": "body", "body": want, "mesh": km2, "name": "Body %d" % (want + 1)}
	var ball := KMeshSculptUI.make_sphere(0.06, 14)
	for i in ball.verts.size():
		ball.verts[i] += Vector3(0.0, 0.06, 0.0)
	ball.rebuild()
	return {"mode": "new", "mesh": ball, "name": "a ball of clay"}


## the Easy chip / the Sculpt ribbon button: open the sculpt on the part. Returns the sentence said
static func open(m: Node, fid := "") -> String:
	var say := _open(m, fid)
	m._say(say)
	return say


static func _open(m: Node, fid: String) -> String:
	if not Part.available() or not PartMeshSolid.KCad.has_mesh_solid():
		return "Sculpting a part needs the part library, and it is not loaded: restart Kine first"
	if m.get("ksc") == null:
		m.ksc = load("res://scripts/kmesh_sculpt_ui.gd").new()
		m.add_child(m.ksc)
		m.ksc.setup(m)
	if m.ksc.on:
		return "The sculpt is already open: drag on it, then press Back into the part"
	var src := source(m, fid)
	var km: KMesh = src["mesh"]
	if km.boundary_edge_count() > 0 or not km.is_manifold():
		return "That body is not one closed skin, so it cannot be sculpted into a solid again. Use Voxel remesh on it first"
	var lo := km.verts[0]
	var hi := km.verts[0]
	for p in km.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	if m.easy != null and m.easy.on:
		m.easy.set_on(false)   # the Sculpt page is an Expert page: Easy hides it
	var at := Transform3D()
	var said := "Sculpt: %s is clay now. Drag on it with the brushes, then press Back into the part (Esc leaves: nothing is changed)" % String(src["name"])
	m.ksc.source = func(): return {"mesh": km, "at": at, "say": said}
	m._sculpt_start()
	m.ksc.source = Callable()
	m.ksc.left = func(): _left(m)
	m.set_meta(META, {"mode": src["mode"], "fid": src.get("fid", ""), "body": int(src.get("body", -1)), "name": src["name"]})
	m.target = (lo + hi) * 0.5
	m.dist = maxf(0.4, (hi - lo).length() * 2.2)
	m._cam()
	return said


static func _left(m: Node) -> void:
	if m.has_meta(META):
		m.remove_meta(META)
	if m.get("ksc") != null:
		m.ksc.left = Callable()


## Back into the part: the sculpt becomes ONE meshsolid step. Returns the sentence said (refusals change nothing)
static func finish(m: Node) -> String:
	var say := _finish(m)
	m._say(say)
	return say


static func _finish(m: Node) -> String:
	if not m.has_meta(META):
		return "Press Sculpt this into the part first (Easy Part > Parts > Ornaments, or the Sculpt page), then sculpt, then come back"
	var road: Dictionary = m.get_meta(META)
	var ksc = m.get("ksc")
	if ksc == null or not ksc.on or ksc.mesh == null:
		_left(m)
		return "The sculpt is closed: press Sculpt this into the part to open it again"
	var got := PartMeshSolid.from_mesh(ksc.mesh, Basis(), String(road["mode"]) != "new")
	if not bool(got["ok"]):
		return String(got["why"])
	var rec: Dictionary = (m.S.part if not m.S.part.is_empty() else Part.make("Part")).duplicate(true)
	var feats: Array = rec["features"]
	var fid := ""
	var nf := {}
	var fi := Part.index_of(rec, String(road["fid"])) if String(road["mode"]) == "feature" else -1
	if fi >= 0 and _pieces_of(feats[fi]) == 1:
		var old: Dictionary = feats[fi]
		nf = {"t": "meshsolid", "id": old["id"], "name": old.get("name", "Sculpt solid"), "sculpt": true}
		for k in (got["f"] as Dictionary):
			nf[k] = (got["f"] as Dictionary)[k]
		feats[fi] = nf
		fid = String(nf["id"])
	else:
		nf = Part.new_feature(rec, "meshsolid", {"name": "Sculpt solid", "sculpt": true})
		for k in (got["f"] as Dictionary):
			nf[k] = (got["f"] as Dictionary)[k]
		if String(road["mode"]) == "body":
			nf["replace"] = int(road["body"])
		feats.append(nf)
		fid = String(nf["id"])
	var res := Part.replay(rec)
	var errs: Dictionary = res["errors"]
	if errs.has(fid):
		return "The sculpt could not become a solid: " + String(errs[fid]) + ". Smooth the skin or remesh it, then try again"
	var want := float(got["vol_mm3"])
	var have := -1e30
	for v in (res["volumes"] as Array):
		var mm3 := float(v) / (MM * MM * MM)
		if absf(mm3 - want) < absf(have - want):
			have = mm3
	if absf(have - want) > 0.02 * want:
		return "The sculpt did not become a clean solid (its volume came out %.0f mm3, the sculpt is %.0f mm3). Remesh it, then try again" % [have, want]
	m._step_hint = "Sculpt this into the part"
	m._push_undo()
	m.S.part = rec
	_left(m)
	ksc.stop()
	m._page_set("BUILD")
	m.bld.part.open_easy()
	m._fit_top.call_deferred()
	var sz: Vector3 = got["size_mm"]
	return "Done: the sculpt is part of the part now (%.0f x %.0f x %.0f mm). Press Sculpt this into the part to change it again, or Undo to take it back" % [sz.x, sz.y, sz.z]
