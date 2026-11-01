class_name PropJoints
extends RefCounted
## MOVING PARTS ON STAGE (s120, Friday plan 120, "Export to the animation side: the part becomes a prop with its pieces as moving parts").
## A Part with Easy hinges (Swing it, Hinge) goes to the scene as ONE prop; its bodies are separate child nodes of that prop. A body with a hinge
## hangs under a joint node placed at the hinge's REAL origin and turned about its REAL axis (the record's "o" and "axis"); a body with no hinge
## stays where it is. The joint is keyable on the STAGE timeline: a channel per joint (prop "jkeys": {joint name: [{"t", "v"}]}, played with
## PartKeys like any joint), clamped to the part's own joint limit (Part.hinge_limit: +-limit degrees, 90 by default), and the words say so.
## The kind is "part:<name>#<hash>~moving", registered from the record (Props.register_part for the whole, plus "pieces" and "pjoints"), and made
## again from the record on load (BuildStage.restore_part), so a saved scene keeps the joints; the prop's "jang" / "jkeys" are in its file entry.
## A joint is {"name", "id", "kind": "turn" (degrees about the axis) | "slide" (mm along the axis, 0..limit), "piece": body index,
## "o": Vector3 (metres, the part's frame; in a prop's kind the prop's frame), "axis": Vector3 (unit), "limit"}.

const SUFFIX := "~moving"
const SAME_T := 0.001


static func is_moving_kind(kind: String) -> bool:
	return kind.ends_with(SUFFIX)


## true when the record has a hinge step (cheap: no replay)
static func has_hinge(rec: Dictionary) -> bool:
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "hinge":
			return true
	return false


## the joints of a record for a part of n bodies: one per hinge step whose body exists (the first hinge on a body wins)
static func joints_of(rec: Dictionary, n: int) -> Array:
	var out := []
	var seen := {}
	for f in rec.get("features", []):
		if String(f.get("t", "")) != "hinge":
			continue
		var bi := int(f.get("body", -1))
		if bi < 0 or bi >= n or seen.has(bi) or not (f.get("o") is Array) or not (f.get("axis") is Array):
			continue
		var ax := Vector3(float(f["axis"][0]), float(f["axis"][1]), float(f["axis"][2]))
		if ax.length() < 1e-9:
			continue
		seen[bi] = true
		out.append({"name": String(f.get("name", "Hinge")), "id": String(f.get("id", "")), "kind": "turn", "piece": bi,
			"o": Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2])) * Part.MM, "axis": ax.normalized(), "limit": Part.hinge_limit(f)})
	return out


## register the moving kind from the record. false when there is no solid, fewer than two bodies, or no usable hinge (nothing registered)
static func register(kind: String, rec: Dictionary) -> bool:
	if not Part.available():
		return false
	var res := Part.replay(rec)
	var whole = res["mesh"]
	if whole == null or int(res["bodies"]) < 2:
		return false
	var js := joints_of(rec, int(res["bodies"]))
	if js.is_empty():
		return false
	Part.paint(whole, res["looks"])
	Props.register_part(kind, whole, true)
	var at: Vector3 = Props.EXTRA[kind]["mesh_at"]
	var pieces := []
	for b in int(res["bodies"]):
		var pm := ArrayMesh.new()
		for s in whole.get_surface_count():
			if int((res["surf_body"] as Array)[s]) == b:
				pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, whole.surface_get_arrays(s))
				pm.surface_set_material(pm.get_surface_count() - 1, whole.surface_get_material(s))
		pieces.append({"mesh": pm, "volume": float((res["volumes"] as Array)[b])})
	for j in js:
		j["o"] = (j["o"] as Vector3) + at
	var kd: Dictionary = Props.EXTRA[kind]
	kd["pieces"] = pieces
	kd["pjoints"] = js
	kd["label"] = "%s, %d moving pieces, %d joint%s" % [String(kd["label"]).trim_suffix(")"), pieces.size(), js.size(), "" if js.size() == 1 else "s"] + ")"
	return true


static func joints_of_kind(kind: String) -> Array:
	return Props.kind_of(kind).get("pjoints", []) if Props.has_kind(kind) else []


static func has_joints(p: Dictionary) -> bool:
	return Props.has_kind(String(p["kind"])) and not (Props.kind_of(String(p["kind"])).get("pjoints", []) as Array).is_empty()


## the joint's local transform at value v (degrees for a turn, mm for a slide), clamped to its limit
static func joint_xf(j: Dictionary, v: float) -> Transform3D:
	var c := clamp_value(j, v)
	if String(j["kind"]) == "slide":
		return Transform3D(Basis.IDENTITY, (j["o"] as Vector3) + (j["axis"] as Vector3) * c * 0.001)
	return Transform3D(Basis(j["axis"] as Vector3, deg_to_rad(c)), j["o"] as Vector3)


static func clamp_value(j: Dictionary, v: float) -> float:
	var lim := float(j["limit"])
	if String(j["kind"]) == "slide":
		return clampf(v, 0.0, lim)
	return clampf(v, -lim, lim)


## the node tree of a moving prop (Props.mesh): one child per piece; a hinged piece under a joint node at the hinge's origin
static func build(root: Node3D, p: Dictionary, kd: Dictionary, mat: Material) -> Node3D:
	var at: Vector3 = kd["mesh_at"]
	var of := {}
	for j in kd["pjoints"]:
		of[int(j["piece"])] = j
	var pieces: Array = kd["pieces"]
	for i in pieces.size():
		var mi := MeshInstance3D.new()
		mi.name = "piece_%d" % i
		mi.mesh = pieces[i]["mesh"]
		if p.has("mat"):
			mi.material_override = mat
		if of.has(i):
			var j: Dictionary = of[i]
			var jn := Node3D.new()
			jn.name = "joint_%d" % i
			jn.set_meta("pj", j)
			mi.position = at - (j["o"] as Vector3)
			jn.add_child(mi)
			root.add_child(jn)
		else:
			mi.position = at
			root.add_child(mi)
	pose(root, p)
	return root


## the joint nodes of a built prop turned (slid) to the prop's joint values (p["jang"]; a posed prop carries the values at its time)
static func pose(n: Node3D, p: Dictionary) -> void:
	var ang: Dictionary = p.get("jang", {})
	for c in n.get_children():
		if c is Node3D and c.has_meta("pj"):
			var j: Dictionary = c.get_meta("pj")
			(c as Node3D).transform = joint_xf(j, float(ang.get(String(j["name"]), 0.0)))


static func keyed(p: Dictionary) -> bool:
	return not (p.get("jkeys", {}) as Dictionary).is_empty()


## every joint's value of the prop at time t: its keys when it has some, else the value it was last set to
static func angles_at(p: Dictionary, t: float) -> Dictionary:
	var out := {}
	for j in joints_of_kind(String(p["kind"])):
		var nm := String(j["name"])
		var ks: Array = (p.get("jkeys", {}) as Dictionary).get(nm, [])
		var v := float((p.get("jang", {}) as Dictionary).get(nm, 0.0))
		if not ks.is_empty():
			v = PartKeys.at(ks.map(func(k): return {"t": float(k["t"]), "v": Vector3(float(k["v"]), 0, 0)}), t).x
		out[nm] = clamp_value(j, v)
	return out


## key joint `name` at time t to value v (clamped to the part's limit). A joint with no keys and t > 0 first gets a key at 0 at its current value,
## so the move PLAYS from it. Answers {"ok", "value" (what was keyed), "asked", "limited" (the limit cut the value), "limit", "why"}
static func key(p: Dictionary, name: String, t: float, v: float) -> Dictionary:
	var jd := {}
	for j in joints_of_kind(String(p["kind"])):
		if String(j["name"]) == name:
			jd = j
	if jd.is_empty():
		return {"ok": false, "why": "this prop has no joint called %s" % name}
	var c := clamp_value(jd, v)
	var jk: Dictionary = p.get("jkeys", {})
	var ks: Array = (jk.get(name, []) as Array).duplicate(true)
	if ks.is_empty() and t > SAME_T:
		ks.append({"t": 0.0, "v": clamp_value(jd, float((p.get("jang", {}) as Dictionary).get(name, 0.0)))})
	var done := false
	for i in ks.size():
		if absf(float(ks[i]["t"]) - t) < SAME_T:
			ks[i] = {"t": t, "v": c}
			done = true
	if not done:
		ks.append({"t": t, "v": c})
	ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	jk[name] = ks
	p["jkeys"] = jk
	var ja: Dictionary = p.get("jang", {})
	ja[name] = c
	p["jang"] = ja
	return {"ok": true, "value": c, "asked": v, "limited": absf(c - v) > 1e-9, "limit": float(jd["limit"]), "kind": String(jd["kind"])}


## the file entry's joint fields (Props.to_dict) and the other way (Props.from_dict)
static func to_file(p: Dictionary, d: Dictionary) -> void:
	if p.has("jang") and not (p["jang"] as Dictionary).is_empty():
		var ja := {}
		for k in p["jang"]:
			ja[k] = snappedf(float(p["jang"][k]), 0.0001)
		d["jang"] = ja
	if keyed(p):
		var jk := {}
		for k in p["jkeys"]:
			jk[k] = (p["jkeys"][k] as Array).map(func(e): return {"t": snappedf(float(e["t"]), 0.0001), "v": snappedf(float(e["v"]), 0.0001)})
		d["jkeys"] = jk


static func from_file(d: Dictionary, p: Dictionary) -> void:
	if d.get("jang") is Dictionary:
		var ja := {}
		for k in d["jang"]:
			ja[String(k)] = float(d["jang"][k])
		p["jang"] = ja
	if d.get("jkeys") is Dictionary and not (d["jkeys"] as Dictionary).is_empty():
		var jk := {}
		for k in d["jkeys"]:
			var ks := []
			for e in d["jkeys"][k]:
				ks.append({"t": float(e.get("t", 0.0)), "v": float(e.get("v", 0.0))})
			ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
			jk[String(k)] = ks
		p["jkeys"] = jk


## a piece's volume in cubic metres, from its triangles (the signed volume of the closed surface)
static func mesh_volume(m: Mesh) -> float:
	var v := 0.0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n: int = (idx as PackedInt32Array).size() if idx != null else vs.size()
		for k in range(0, n, 3):
			var a: Vector3 = vs[idx[k]] if idx != null else vs[k]
			var b: Vector3 = vs[idx[k + 1]] if idx != null else vs[k + 1]
			var c: Vector3 = vs[idx[k + 2]] if idx != null else vs[k + 2]
			v += a.dot(b.cross(c)) / 6.0
	return absf(v)
