## s262b EXPLODED VIEW v2 (scripts/build/explode_view.gd is the planner): the pieces that the panel, the timeline and the film share.
##  1. BODIES OF ANY COUNT. A part mesh holds at most 256 surfaces (Part.pack_surfaces merges bodies of one look into a surface and records res.surf_ranges =
##     [[body, first vertex, vertex count]] per surface). body_verts / shifted_mesh / split_pieces read and move a body by its vertex range, so a 300-body
##     part explodes body by body, with no 256 limit.
##  2. THE TIMELINE. send() puts the part in the scene as ONE prop whose bodies are child nodes, each moving body under a SLIDE joint (PropJoints, s120) along its
##     signed axis, and keys every joint at the planner's out / in times (ExplodeView.keys). The scene's playback, Check and the video export read
##     those keys like any other: whatever the panel played is what the export films. The prop's kind carries the plan's inputs
##     ("part:<name>#<hash>~explode_<axis>_<gap mm>_<level>[_<anchor>]"), so a saved scene is made again from its record (BuildStage.restore_part).
class_name ExplodeKeys
extends RefCounted

const SUFFIX := "~explode_"


## distinct body ids of the mesh, ascending
static func body_ids(mesh: ArrayMesh, res: Dictionary) -> Array:
	var seen := {}
	var rngs: Array = res.get("surf_ranges", [])
	var sb: Array = res.get("surf_body", [])
	var ranged: bool = rngs.size() == mesh.get_surface_count()
	for s in mesh.get_surface_count():
		if ranged:
			for r in rngs[s]:
				seen[int(r[0])] = true
		else:
			seen[int(sb[s]) if s < sb.size() else 1000000 + s] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## [[body, first vertex, vertex count]] of surface s (a surface with no record is one body)
static func ranges_of(mesh: ArrayMesh, res: Dictionary, s: int) -> Array:
	var rngs: Array = res.get("surf_ranges", [])
	if rngs.size() == mesh.get_surface_count():
		return rngs[s]
	var sb: Array = res.get("surf_body", [])
	var nv := (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return [[int(sb[s]) if s < sb.size() else 1000000 + s, 0, nv]]


## body id -> its vertices (mesh-local)
static func body_verts(mesh: ArrayMesh, res: Dictionary) -> Dictionary:
	var out := {}
	for s in mesh.get_surface_count():
		var vs: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for r in ranges_of(mesh, res, s):
			var b := int(r[0])
			var acc: PackedVector3Array = out.get(b, PackedVector3Array())
			acc.append_array(vs.slice(int(r[1]), int(r[1]) + int(r[2])))
			out[b] = acc
	return out


static func box_of(vs: PackedVector3Array) -> AABB:
	if vs.is_empty():
		return AABB()
	var lo := vs[0]
	var hi := vs[0]
	for v in vs:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## the mesh with every body moved by offs[body] (mesh-local vectors; a body not named stays). Same surfaces, same order.
static func shifted_mesh(mesh: ArrayMesh, res: Dictionary, offs: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var mv := vs.duplicate()
		for r in ranges_of(mesh, res, s):
			var off: Vector3 = offs.get(int(r[0]), Vector3.ZERO)
			if off == Vector3.ZERO:
				continue
			for i in range(int(r[1]), int(r[1]) + int(r[2])):
				mv[i] = vs[i] + off
		arr[Mesh.ARRAY_VERTEX] = mv
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arr)
	return out


## one ArrayMesh per body: body id -> mesh (the surface's material kept). Slices every vertex-shaped array and re-bases the indices.
static func split_pieces(mesh: ArrayMesh, res: Dictionary) -> Dictionary:
	var out := {}
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var nvt: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var rs := ranges_of(mesh, res, s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var ip := 0
		for r in rs:
			var b := int(r[0])
			var v0 := int(r[1])
			var nv := int(r[2])
			var a2: Array = []
			a2.resize(Mesh.ARRAY_MAX)
			for slot in Mesh.ARRAY_MAX:
				if slot == Mesh.ARRAY_INDEX or arr[slot] == null:
					continue
				var full: Variant = arr[slot]
				var stride: int = int(full.size() / maxi(nvt, 1))
				if stride < 1 or stride * nvt != full.size():
					continue
				a2[slot] = full.slice(v0 * stride, (v0 + nv) * stride)
			if idx.size() > 0:
				var li := PackedInt32Array()
				while ip + 2 < idx.size() and int(idx[ip]) < v0 + nv:
					li.append(int(idx[ip]) - v0)
					li.append(int(idx[ip + 1]) - v0)
					li.append(int(idx[ip + 2]) - v0)
					ip += 3
				a2[Mesh.ARRAY_INDEX] = li
			var pm := ArrayMesh.new()
			pm.add_surface_from_arrays(mesh.surface_get_primitive_type(s), a2)
			pm.surface_set_material(0, mesh.surface_get_material(s))
			out[b] = pm
	return out


# ---------------------------------------------------------------- the prop

static func axis_letter(axis: Vector3) -> String:
	return "x" if absf(axis.x) > 0.5 else ("z" if absf(axis.z) > 0.5 else "y")


static func is_kind(kind: String) -> bool:
	return kind.find(SUFFIX) >= 0


## "<base>~explode_<axis>_<gap mm>_<level 0/1>_<anchor body name or ->"
static func kind_name(rec: Dictionary, axis: Vector3, gap_mm: float, by_level: bool, anchor := "") -> String:
	return "part:%s#%s%s%s_%s_%d_%s" % [String(rec.get("name", "Part")), str(hash(JSON.stringify(rec))), SUFFIX, axis_letter(axis), String.num(gap_mm, 3), 1 if by_level else 0, anchor.uri_encode() if anchor != "" else "-"]


static func opts_of(kind: String) -> Dictionary:
	var tail := kind.substr(kind.find(SUFFIX) + SUFFIX.length()).split("_")
	if tail.size() < 3:
		return {}
	return {"axis": ExplodeView.axis_vec(tail[0]), "gap_mm": float(tail[1]), "by_level": tail[2] == "1", "anchor": tail[3].uri_decode() if tail.size() > 3 and tail[3] != "-" else ""}


## the plan of a replayed part: {plan, ids, names, boxes}. Prop frame = the part's frame. anchor: a body name ("" = the biggest).
static func plan_of(res: Dictionary, opts: Dictionary) -> Dictionary:
	var mesh: ArrayMesh = res["mesh"]
	var bv := body_verts(mesh, res)
	var ids := body_ids(mesh, res)
	var bn: Array = res.get("body_names", [])
	var boxes: Array = []
	var names: Array = []
	for b in ids:
		boxes.append(box_of(bv[b]))
		names.append(String(bn[b]) if b < bn.size() and String(bn[b]) != "" else "Body%d" % (int(b) + 1))
	var axis: Vector3 = opts.get("axis", Vector3.UP)
	var layers: Array = ExplodeView.level_layers(boxes, axis) if bool(opts.get("by_level", false)) else ExplodeView.body_layers(boxes.size())
	var po := {}
	var an := String(opts.get("anchor", ""))
	if an != "":
		for u in layers.size():
			for bi in layers[u]:
				if names[int(bi)] == an:
					po["anchor"] = u
	var plan := ExplodeView.plan(boxes, layers, axis, float(opts.get("gap_mm", 10.0)) * Part.MM, po)
	return {"plan": plan, "ids": ids, "names": names, "boxes": boxes}


static func _joint_names(names: Array) -> Array:
	var seen := {}
	var out: Array = []
	for n in names:
		var k := String(n)
		seen[k] = int(seen.get(k, 0)) + 1
	var cnt := {}
	for n in names:
		var k := String(n)
		cnt[k] = int(cnt.get(k, 0)) + 1
		out.append(k if int(seen[k]) == 1 else "%s %d" % [k, int(cnt[k])])
	return out


## register the kind from the record: one piece per body, one slide joint per moving body. false when it has no solid or fewer than two bodies.
static func register(kind: String, rec: Dictionary) -> bool:
	if not Part.available():
		return false
	var res := Part.replay(rec)
	var whole = res["mesh"]
	if whole == null or int(res["bodies"]) < 2:
		return false
	var pl := plan_of(res, opts_of(kind))
	var plan: Dictionary = pl["plan"]
	if not bool(plan.get("ok", false)):
		return false
	Part.paint(whole, res["looks"])
	Props.register_part(kind, whole, true)
	var at: Vector3 = Props.EXTRA[kind]["mesh_at"]
	var split := split_pieces(whole, res)
	var ids: Array = pl["ids"]
	var pieces: Array = []
	for i in ids.size():
		pieces.append({"mesh": split.get(ids[i], ArrayMesh.new()), "volume": float((res["volumes"] as Array)[ids[i]]) if ids[i] < (res["volumes"] as Array).size() else 0.0})
	var jn := _joint_names(pl["names"])
	var joints: Array = []
	var ax: Vector3 = (plan["axis"] as Vector3).normalized()
	for u in (plan["units"] as Array).size():
		if float((plan["dist"] as Array)[u]) <= 0.0:
			continue
		var lim := float(plan["dist"][u]) * 1000.0 + 1e-6
		for bi in plan["units"][u]:
			joints.append({"name": jn[int(bi)], "id": "", "kind": "slide", "piece": int(bi), "o": at, "axis": ax * float(plan["sign"][u]), "limit": lim, "unit": u})
	var kd: Dictionary = Props.EXTRA[kind]
	kd["pieces"] = pieces
	kd["pjoints"] = joints
	kd["explode_plan"] = plan
	kd["label"] = "%s, exploded view, %d moving pieces)" % [String(kd["label"]).trim_suffix(")"), joints.size()]
	return true


static func restore(kind: String, rec: Dictionary) -> String:
	return kind if register(kind, rec) else ""


## key every joint of prop p (a scene prop of an explode kind) at the planner's times: the out run, the hold and the in run. sched: ExplodeView.schedule(plan).
## Returns {joints, keys, total}
static func write_keys(p: Dictionary, sched: Dictionary) -> Dictionary:
	var kd: Dictionary = Props.kind_of(String(p["kind"]))
	var plan: Dictionary = kd["explode_plan"]
	var tab: Array = ExplodeView.keys(plan, sched)
	var nk := 0
	var nj := 0
	p.erase("jkeys")
	for j in kd["pjoints"]:
		var u := int(j["unit"])
		nj += 1
		for k in tab[u]:
			var r := PropJoints.key(p, String(j["name"]), float(k["t"]), float(k["d"]) * 1000.0)
			nk += 1 if bool(r.get("ok", false)) else 0
	return {"joints": nj, "keys": nk, "total": float(sched["total"])}


## the scene gets the part as an explode prop, keyed. m: the app (main.gd). rec: the part record. One undo step. Answers {ok, why, prop, joints, keys, total, kind}
static func send(m: Node, rec: Dictionary, opts: Dictionary, dur := 1.0, stagger := 0.4, hold := 0.5) -> Dictionary:
	var kind := kind_name(rec, opts.get("axis", Vector3.UP), float(opts.get("gap_mm", 10.0)), bool(opts.get("by_level", false)), String(opts.get("anchor", "")))
	m._step_hint = "Exploded view on the timeline: %s" % String(rec.get("name", "part"))
	m._push_undo()
	if not register(kind, rec):
		m._drop_undo()
		return {"ok": false, "why": "Exploded view needs a part with two or more bodies"}
	var kd: Dictionary = Props.kind_of(kind)
	var sched := ExplodeView.schedule(kd["explode_plan"], dur, stagger, hold)
	var pp := Props.make(kind, Transform3D.IDENTITY)
	pp["part_rec"] = rec.duplicate(true)
	var r := write_keys(pp, sched)
	m.S.props.append(pp)
	fit_length(m, float(sched["total"]))
	m.sel_prop = m.S.props.size() - 1
	m._props_show()
	r.merge({"ok": true, "prop": m.S.props.size() - 1, "kind": kind})
	return r


## the scene is at least `total` seconds long, so playback and export reach the last key: two cards at least, the last one holding
static func fit_length(m: Node, total: float) -> void:
	while m.S.cards.size() < 2:
		m.S.add("hold", m.B.to_dict())
	var deficit: float = total - float(m.S.length())
	if deficit > 0.0:
		m.S.cards[-1]["hold"] = float(m.S.cards[-1].get("hold", 0.0)) + deficit + 0.001
