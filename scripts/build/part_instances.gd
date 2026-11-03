extends RefCounted
## s261 INSTANCES: one body placed N times on a face, drawn as ONE MultiMesh (one draw call), baked into real geometry at export.
## The existing pattern makes one kernel solid per copy (PATTERN_MAX 64); this makes none: the body is tessellated once and each copy is a transform.
## Feature {"t": "instances", "id", "body": N, "count": 1..MAX, "mode": "scatter" | "grid", "seed": int, "gap": mm (clear space between copies),
##   "face": {"c": [x, y, z] mm (face centre), "n": "x" | "y" | "z" (its normal, default "y"), "w": mm, "h": mm (u and v extent, u/v = the two other axes in x,y,z order)},
##   "looks": optional ["#rrggbb", ...] palette: each copy takes one by the seeded draw (a copy with its own look; none = the body's look)}.
## The body must fit the face, sits with its base on the face plane, and is taken out of the body list (the copies replace it).
## Scatter rejects any copy whose box would touch another box (gap mm clear) and fails in words when the count does not fit.
## The same seed gives the same places (RandomNumberGenerator is seeded; nothing else is drawn).
const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const MAX := 20000
const KEY := "__inst"   # where replay keeps the placed copies (in the sketches dict, so the incremental cache carries them)


## the places (metres, the translation of the source body) for a feature, given the body's box (metres). {"pos": PackedVector3Array, "err": String}
static func places(box: AABB, f: Dictionary) -> Dictionary:
	var n := int(f.get("count", 0))
	if n < 1 or n > MAX:
		return {"err": "instances needs 1 to %d copies" % MAX}
	var fc: Dictionary = f.get("face", {})
	var ax := String(fc.get("n", "y"))
	if not ["x", "y", "z"].has(ax):
		return {"err": "the face normal must be x, y or z"}
	var ci: int = {"x": 0, "y": 1, "z": 2}[ax]
	var ui := (ci + 1) % 3
	var vi := (ci + 2) % 3
	var cc: Array = fc.get("c", [0, 0, 0])
	var c := Vector3(float(cc[0]), float(cc[1]), float(cc[2])) * MM
	var fw := float(fc.get("w", 100.0)) * MM
	var fh := float(fc.get("h", 100.0)) * MM
	var gap := float(f.get("gap", 0.0)) * MM
	var bu: float = box.size[ui]
	var bv: float = box.size[vi]
	if bu > fw or bv > fh:
		return {"err": "the body is bigger than the face"}
	var pu := bu + gap   # pitch: footprint + gap
	var pv := bv + gap
	var short := ""   # set when scatter could not place them all; the places it did find are still returned in "partial"
	var spots: Array = []   # [u, v] of each footprint centre, relative to the face centre
	var mode := String(f.get("mode", "scatter"))
	if mode == "grid":
		var cols := maxi(int(floor((fw + gap) / pu)), 1)
		var rows := maxi(int(floor((fh + gap) / pv)), 1)
		if cols * rows < n:
			return {"err": "%d copies do not fit in a %d x %d grid on this face" % [n, cols, rows]}
		for k in n:
			spots.append([-fw * 0.5 + bu * 0.5 + (k % cols) * pu, -fh * 0.5 + bv * 0.5 + (k / cols) * pv])
	elif mode == "scatter":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(f.get("seed", 0))
		var cell_u := maxf(pu, 1e-9)
		var cell_v := maxf(pv, 1e-9)
		var cells := {}
		var tries := 0
		var cap := n * 400
		var ru := fw - bu
		var rv := fh - bv
		while spots.size() < n and tries < cap:
			tries += 1
			var u := rng.randf() * ru
			var v := rng.randf() * rv
			var cu := int(floor(u / cell_u))
			var cv := int(floor(v / cell_v))
			var hit := false
			for du in range(-1, 2):
				for dv in range(-1, 2):
					for q in cells.get(Vector2i(cu + du, cv + dv), []):
						if absf(q[0] - u) < pu and absf(q[1] - v) < pv:
							hit = true
							break
					if hit:
						break
				if hit:
					break
			if hit:
				continue
			var key := Vector2i(cu, cv)
			if not cells.has(key):
				cells[key] = []
			cells[key].append([u, v])
			spots.append([-fw * 0.5 + bu * 0.5 + u, -fh * 0.5 + bv * 0.5 + v])
		if spots.size() < n:
			short = "only %d of %d fit without overlapping: use fewer, a smaller gap or a bigger face" % [spots.size(), n]
	else:
		return {"err": "mode must be scatter or grid"}
	var pos := PackedVector3Array()
	var bc := box.get_center()
	var base: float = box.position[ci]
	for s in spots:
		var p := Vector3.ZERO
		p[ui] = c[ui] + float(s[0]) - bc[ui]
		p[vi] = c[vi] + float(s[1]) - bc[vi]
		p[ci] = c[ci] - base
		pos.append(p)
	if short != "":
		return {"err": short, "partial": pos}
	return {"pos": pos, "err": ""}


## replay step: body N is tessellated once, taken out of the lists, and its copies are kept in sketches[KEY]. "" or the failure (nothing changes)
static func apply(bodies: Array, looks: Array, f: Dictionary, sketches: Dictionary) -> String:
	var bi := int(f.get("body", -1))
	if bi < 0 or bi >= bodies.size():
		return "there is no body to place copies of"
	var tm := KCad.tessellate(int(bodies[bi]), 0.0001, 0.2)
	if tm == null or tm.get_surface_count() == 0:
		return "the body has no shape to copy"
	var box := tm.get_aabb()
	var pl := places(box, f)
	if String(pl["err"]) != "":
		return String(pl["err"])
	var pos: PackedVector3Array = pl["pos"]
	var look = looks[bi] if bi < looks.size() else null
	var cols := PackedColorArray()
	var pal: Array = f.get("looks", [])
	if not pal.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(f.get("seed", 0)) + 7919
		for _i in pos.size():
			cols.append(Color.html(String(pal[rng.randi() % pal.size()])))
	var list: Array = sketches.get(KEY, [])
	list.append({"id": String(f.get("id", "")), "mesh": tm, "pos": pos, "cols": cols, "look": look})
	sketches[KEY] = list
	KCad.release(int(bodies[bi]))
	bodies.remove_at(bi)
	if bi < looks.size():
		looks.remove_at(bi)
	return ""


## the node tree for the view: one MultiMeshInstance3D per instanced body (one draw call each), under a parent; the old ones go
static func sync(parent: Node3D, res: Dictionary) -> void:
	for c in parent.get_children():
		if String(c.name).begins_with("Instances_"):
			parent.remove_child(c)
			c.queue_free()
	var list: Array = res.get("instances", [])
	for k in list.size():
		parent.add_child(build_node(list[k], "Instances_%d" % k))


static func build_node(inst: Dictionary, nm := "Instances") -> MultiMeshInstance3D:
	var pos: PackedVector3Array = inst["pos"]
	var cols: PackedColorArray = inst["cols"]
	var arrs := (inst["mesh"] as ArrayMesh).surface_get_arrays(0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	var mt := StandardMaterial3D.new()
	var look = inst.get("look")
	if look is Dictionary and look.has("c"):
		mt.albedo_color = look["c"]
		mt.roughness = float(look.get("rough", 0.6))
		mt.metallic = float(look.get("metal", 0.0))
	var use_cols := cols.size() == pos.size() and pos.size() > 0
	if use_cols:
		mt.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mt)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_cols
	mm.mesh = mesh
	mm.instance_count = pos.size()
	for i in pos.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos[i]))   # each copy keeps its own transform
		if use_cols:
			mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	return mi


## export: the instanced bodies as real geometry. One welded body per instanced step ("<base> instances") holding every copy's triangles.
static func bake_into(out: Array, instances: Array, base: String) -> void:
	if instances.is_empty():
		return
	var Mx = load("res://scripts/build/mesh_export.gd")
	for k in instances.size():
		var inst: Dictionary = instances[k]
		var tm: ArrayMesh = inst["mesh"]
		var soup := PackedVector3Array()
		for s in tm.get_surface_count():
			var arr := tm.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null:
				soup.append_array(vs)
			else:
				for q in (idx as PackedInt32Array):
					soup.append(vs[q])
		var one: Dictionary = Mx.weld(soup)
		var v1: PackedVector3Array = one["v"]
		var t1: PackedInt32Array = one["t"]
		var pos: PackedVector3Array = inst["pos"]
		var v := PackedVector3Array()
		var t := PackedInt32Array()
		v.resize(v1.size() * pos.size())
		t.resize(t1.size() * pos.size())
		for i in pos.size():
			var off: Vector3 = Mx.to_print(pos[i])
			var vo := i * v1.size()
			for j in v1.size():
				v[vo + j] = v1[j] + off
			var to := i * t1.size()
			for j in t1.size():
				t[to + j] = t1[j] + vo
		out.append({"name": "%s instances%s" % [base, "" if instances.size() == 1 else " %d" % (k + 1)], "v": v, "t": t, "color": null})
