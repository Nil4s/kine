class_name PropInstances
extends RefCounted
## INSTANCING (M3, A15): the props of one kind that stay still are drawn as ONE MultiMeshInstance3D per mesh of the kind:
## the mesh is built once and each copy is one transform. Before, every prop was its own node, and a .glb prop parsed its
## file again (GLTFDocument.generate_scene per prop). Not shared: a keyed or hinged prop (it moves), a carried prop, the
## picked one (it keeps its tint and its own node), a box or an OBJ kind. Picking and Check are unchanged: they read the
## prop's solids (Props.solids), never the drawn nodes.
## CROWDS are not here: a crowd copy is a fighter posed every frame on its own skeleton (crowd.gd), and a MultiMesh draws
## one mesh at one transform per instance, so the copies cannot share a pose.
## ROW: "Copies in a row" puts n copies of the picked prop beside it, along its own x axis, a gap apart, each on the floor.

const MIN_COUNT := 2      # a kind is shared from two copies
const ROW_N := 10
const ROW_GAP := 0.1      # m between two copies of a row


## whether prop i of props may be drawn shared (see the header); sel is the picked prop, carried the props in a hand
static func shareable(props: Array, i: int, sel := -1, carried: Array = []) -> bool:
	var p: Dictionary = props[i]
	if i == sel or i in carried or Props.animated(p) or Props.hinged(p) or Props.model_missing(p):
		return false
	var kd := Props.kind_of(p["kind"])
	if kd.is_empty() or bool(kd.get("hidden", false)):
		return false
	var glb := String(kd.get("glb", ""))
	return glb != "" and glb.get_extension().to_lower() != "obj"


## the groups to draw shared: an Array of index Arrays, one per (kind, colour, photo material) with at least MIN_COUNT copies,
## in the order the props first appear
static func plan(props: Array, sel := -1, carried: Array = []) -> Array:
	var groups := {}
	var order := []
	for i in props.size():
		if not shareable(props, i, sel, carried):
			continue
		var p: Dictionary = props[i]
		var key := "%s|%s|%s" % [p["kind"], Props.colour_of(p), str(p.get("mat", ""))]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(i)
	var out := []
	for k in order:
		if (groups[k] as Array).size() >= MIN_COUNT:
			out.append(groups[k])
	return out


## the prop's place as Props.mesh sets its root: the placement with the prop's scale
static func root_xf(p: Dictionary) -> Transform3D:
	return (p["xf"] as Transform3D).scaled_local(Vector3.ONE * Props.scale_of(p))


## the meshes of the prop's built model, each with the transform it has under the root (the root itself not included) and
## its material per surface resolved into the mesh (the built model is ours alone, so the mesh may take them)
static func parts(p: Dictionary) -> Array:
	var root := Props.mesh(p)
	var out := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t: Transform3D = m.transform
		var q: Node = m.get_parent()
		while q != root and q is Node3D:
			t = (q as Node3D).transform * t
			q = q.get_parent()
		for s in m.mesh.get_surface_count():
			m.mesh.surface_set_material(s, m.get_active_material(s))
		out.append({"mesh": m.mesh, "xf": t})
	root.free()
	return out


## one MultiMeshInstance3D per mesh of the kind, with one instance per prop of idx (props[idx[k]] is copy k). idx: a group
## from plan(); all its props share the first one's model
static func build(props: Array, idx: Array) -> Array:
	var out := []
	for part in parts(props[idx[0]]):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part["mesh"]
		mm.instance_count = idx.size()
		for k in idx.size():
			mm.set_instance_transform(k, root_xf(props[idx[k]]) * (part["xf"] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		out.append(mmi)
	return out


## the width of the prop along its own x axis, in m, as drawn (the model's boxes, scaled)
static func width_x(p: Dictionary) -> float:
	var lo := INF
	var hi := -INF
	for part in parts(p):
		var bb: AABB = (part["xf"] as Transform3D) * (part["mesh"] as Mesh).get_aabb()
		lo = minf(lo, bb.position.x)
		hi = maxf(hi, bb.end.x)
	return maxf(0.0, hi - lo) * Props.scale_of(p) if hi > lo else 0.0


## n copies of props[i] beside it, along its own x axis (copy k is k steps of width + gap away), each on the floor on what it
## stands over. The new records are not in props yet: the caller appends them (one undo step)
static func row(props: Array, i: int, n := ROW_N, gap := ROW_GAP) -> Array:
	var p: Dictionary = props[i]
	var step := width_x(p) + gap
	var out := []
	for k in range(1, n + 1):
		var q := p.duplicate(true)
		var xf: Transform3D = p["xf"]
		xf.origin += xf.basis.x * step * float(k)
		q["xf"] = xf
		var o := xf.origin
		o.y = Props.snap_y(q, props)
		xf.origin = o
		q["xf"] = xf
		out.append(q)
	return out
