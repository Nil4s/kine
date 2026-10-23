class_name KMeshShapes
extends RefCounted
## A13 (docs/ROADMAP_400.md): SHAPE KEYS on a KMesh, relative and absolute, each value drivable by anything.
## The set lives on the mesh as KMesh.shapes (so save/load and KMeshUndo carry it):
##   {"basis": PackedVector3Array (the rest positions), "relative": true, "eval_time": 0.0,
##    "keys": [{"name", "delta": PackedVector3Array, "rel": "Basis" or another key's name, "value", "min", "max",
##              "mute", "group": "" or a vert-domain float attribute (A09) used as a 0..1 mask, "frame"}],
##    "drivers": [driver, ...]}
## A key stores DELTAS from its reference key ("rel"), so its own shape is shape(rel) + delta and shape("Basis") = basis.
## (Blender keeps each key's positions and subtracts the reference at evaluation; the blend below is the same number.)
##
## RELATIVE (Blender's default "Relative"):
##     p(v) = basis(v) + sum over keys k not muted of  clamp(value_k, min_k, max_k) * mask_k(v) * delta_k(v)
## ABSOLUTE (Blender's "Relative" off, the Evaluation Time slider): the basis sits at frame 0 and each unmuted key at its
## "frame" (10, 20, 30... by default, as Blender places them); the time picks the two keys around it and blends their
## shapes linearly:  p = shape(a) + (shape(b) - shape(a)) * (t - frame_a) / (frame_b - frame_a), t clamped to the ends.
## Masks and values are not used in absolute mode (only the time is).
##
## DRIVERS ("driven by anything"): a driver sets one key's value from named inputs, every evaluation, in list order:
##     {"key": "smile", "expr": "clamp(upperarm_r_bend / 90.0, 0.0, 1.0)"}     a Godot Expression over the inputs
##     {"key": "smile", "source": "upperarm_r_bend", "factor": 0.01, "offset": 0, "from": 0}   Drivers.value's linear form
## Inputs are any {name: float}: body_inputs(B) gives every joint as <joint>_bend / _side / _twist (degrees); add
## "frame", "time", a slider, anything. The keys' own current values are inputs too (by name, when the name is an
## identifier), so one key can drive another. The written value is clamped to the key's min / max.
##
## Edits: shapes are evaluated from the basis, so an edit made to m.verts while a key is on is captured with
## add_from_current (the mesh's current positions minus the reference shape), not kept in the basis.

const BASIS := "Basis"
const FRAME_STEP := 10.0   # Blender places absolute keys 10 frames apart

## message of the last failed call (empty after a success); each names a next step
static var last_error := ""


## the shape set, made on first use with the mesh's current positions as the basis
static func ensure(m: KMesh) -> Dictionary:
	if m.shapes.is_empty():
		m.shapes = {"basis": m.verts.duplicate(), "relative": true, "eval_time": 0.0, "keys": [], "drivers": []}
	return m.shapes


static func keys(m: KMesh) -> Array:
	return m.shapes.get("keys", [])


static func find(m: KMesh, key_name: String) -> int:
	var ks := keys(m)
	for i in ks.size():
		if String(ks[i]["name"]) == key_name:
			return i
	return -1


## a new key (delta empty = all zero). Returns its index, -1 with last_error set
static func add_key(m: KMesh, key_name: String, delta := PackedVector3Array(), rel := BASIS, value := 0.0) -> int:
	last_error = ""
	var sh := ensure(m)
	var n := (sh["basis"] as PackedVector3Array).size()
	if key_name == "" or key_name == BASIS or find(m, key_name) >= 0:
		last_error = "shape key '%s' %s. Pick a new name." % [key_name, "has no name" if key_name == "" else "already exists"]
		return -1
	if rel != BASIS and find(m, rel) < 0:
		last_error = "the reference key '%s' does not exist. Use Basis or an existing key." % rel
		return -1
	if delta.is_empty():
		delta.resize(n)
	if delta.size() != n:
		last_error = "the key has %d offsets but the mesh has %d vertices. Pass one per vertex." % [delta.size(), n]
		return -1
	var ks: Array = sh["keys"]
	ks.append({"name": key_name, "delta": delta.duplicate(), "rel": rel, "value": value, "min": 0.0, "max": 1.0,
		"mute": false, "group": "", "frame": FRAME_STEP * (ks.size() + 1)})
	return ks.size() - 1


## Blender's "New Shape from Mix" for one mesh edit: the key is the current positions minus the reference shape
static func add_from_current(m: KMesh, key_name: String, rel := BASIS, value := 0.0) -> int:
	var sh := ensure(m)
	if m.verts.size() != (sh["basis"] as PackedVector3Array).size():
		last_error = "the mesh has %d vertices but its shape keys %d. The topology changed: remove the keys first." % [m.verts.size(), (sh["basis"] as PackedVector3Array).size()]
		return -1
	if rel != BASIS and find(m, rel) < 0:
		last_error = "the reference key '%s' does not exist. Use Basis or an existing key." % rel
		return -1
	var ref := shape_of(m, rel)
	var d := PackedVector3Array()
	d.resize(ref.size())
	for i in ref.size():
		d[i] = m.verts[i] - ref[i]
	return add_key(m, key_name, d, rel, value)


## a key's own full shape: its reference's shape plus its delta (Basis = the basis)
static func shape_of(m: KMesh, key_name: String) -> PackedVector3Array:
	var sh := ensure(m)
	var out: PackedVector3Array = (sh["basis"] as PackedVector3Array).duplicate()
	var chain := []
	var k := key_name
	while k != BASIS:
		var i := find(m, k)
		if i < 0 or chain.has(i):
			break
		chain.append(i)
		k = String(keys(m)[i]["rel"])
	for c in range(chain.size() - 1, -1, -1):
		var d: PackedVector3Array = keys(m)[chain[c]]["delta"]
		for v in out.size():
			out[v] += d[v]
	return out


## sets a key's value, clamped to its min / max; returns the value kept (NAN = no such key)
static func set_value(m: KMesh, key_name: String, v: float) -> float:
	var i := find(m, key_name)
	if i < 0:
		return NAN
	var k: Dictionary = keys(m)[i]
	k["value"] = clampf(v, float(k["min"]), float(k["max"]))
	return k["value"]


## takes a key off; keys that referenced it keep their full shape (their delta gains its delta, their rel becomes its rel)
static func remove_key(m: KMesh, key_name: String) -> bool:
	var i := find(m, key_name)
	if i < 0:
		return false
	var ks := keys(m)
	var gone: Dictionary = ks[i]
	for k in ks:
		if String(k["rel"]) == key_name:
			var d: PackedVector3Array = k["delta"]
			var g: PackedVector3Array = gone["delta"]
			for v in d.size():
				d[v] += g[v]
			k["delta"] = d
			k["rel"] = gone["rel"]
	ks.remove_at(i)
	var drv: Array = m.shapes.get("drivers", [])
	for j in range(drv.size() - 1, -1, -1):
		if String(drv[j]["key"]) == key_name:
			drv.remove_at(j)
	return true


## the 0..1 mask a key's group gives (empty = no mask: every vertex weight 1)
static func _mask(m: KMesh, group: String, n: int) -> PackedFloat32Array:
	if group == "" or not m.attrs.has(group):
		return PackedFloat32Array()
	var r: Dictionary = m.attrs[group]
	if r["domain"] != KMesh.AD_VERT or r["type"] != TYPE_FLOAT or (r["data"] as PackedFloat32Array).size() != n:
		return PackedFloat32Array()
	return r["data"]


## THE BLEND: the positions the keys give. values (optional) overrides key values by name; time (absolute mode)
## overrides the stored eval_time. The mesh is not changed (apply() writes the result).
static func evaluate(m: KMesh, values := {}, time := NAN) -> PackedVector3Array:
	if m.shapes.is_empty():
		return m.verts.duplicate()
	var sh: Dictionary = m.shapes
	var basis: PackedVector3Array = sh["basis"]
	var n := basis.size()
	if not bool(sh.get("relative", true)):
		return _absolute(m, float(sh.get("eval_time", 0.0)) if is_nan(time) else time)
	var out := basis.duplicate()
	for k in sh["keys"]:
		if bool(k["mute"]):
			continue
		var w := clampf(float(values.get(k["name"], k["value"])), float(k["min"]), float(k["max"]))
		if w == 0.0:
			continue
		var d: PackedVector3Array = k["delta"]
		var mk := _mask(m, String(k["group"]), n)
		if mk.is_empty():
			for v in n:
				out[v] += d[v] * w
		else:
			for v in n:
				if mk[v] != 0.0:
					out[v] += d[v] * (w * mk[v])
	return out


static func _absolute(m: KMesh, t: float) -> PackedVector3Array:
	var pts := [[0.0, BASIS]]
	for k in keys(m):
		if not bool(k["mute"]):
			pts.append([float(k["frame"]), String(k["name"])])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	if t <= pts[0][0]:
		return shape_of(m, pts[0][1])
	for i in range(1, pts.size()):
		if t <= pts[i][0]:
			var a := shape_of(m, pts[i - 1][1])
			var b := shape_of(m, pts[i][1])
			var span: float = pts[i][0] - pts[i - 1][0]
			var f: float = 1.0 if span <= 0.0 else (t - pts[i - 1][0]) / span
			for v in a.size():
				a[v] += (b[v] - a[v]) * f
			return a
	return shape_of(m, pts[pts.size() - 1][1])


## writes the blend into the mesh (positions + normals). Returns how many vertices moved
static func apply(m: KMesh, values := {}, time := NAN) -> int:
	var p := evaluate(m, values, time)
	if p.size() != m.verts.size():
		return 0
	var moved := 0
	for i in p.size():
		if p[i] != m.verts[i]:
			moved += 1
	if moved > 0:
		m.verts = p
		m._compute_normals()
	return moved


# ---------------------------------------------------------------- drivers

## every joint's angle as an input: <joint>_bend / _side / _twist in degrees (Body.ang)
static func body_inputs(B: Body) -> Dictionary:
	var out := {}
	for j in B.ang:
		var a: Vector3 = B.ang[j]
		out[j + "_bend"] = a.x
		out[j + "_side"] = a.y
		out[j + "_twist"] = a.z
	return out


## a driver for the same key replaces the old one (its place kept); else appended. Returns its index, -1 = no such key
static func put_driver(m: KMesh, d: Dictionary) -> int:
	if find(m, String(d.get("key", ""))) < 0:
		last_error = "the driver's key '%s' does not exist. Add the shape key first." % str(d.get("key", ""))
		return -1
	var drv: Array = ensure(m)["drivers"]
	for i in drv.size():
		if drv[i]["key"] == d["key"]:
			drv[i] = d
			return i
	drv.append(d)
	return drv.size() - 1


## one driver's value from the inputs; NAN with last_error set when it cannot be read
static func driver_value(d: Dictionary, inputs: Dictionary) -> float:
	if d.has("expr"):
		var names := PackedStringArray()
		var vals := []
		for k in inputs:
			if String(k).is_valid_identifier():
				names.append(String(k))
				vals.append(float(inputs[k]))
		var e := Expression.new()
		if e.parse(String(d["expr"]), names) != OK:
			last_error = "driver of '%s': %s. Fix the expression (inputs: %s)." % [d["key"], e.get_error_text(), ", ".join(names.slice(0, 6))]
			return NAN
		var r = e.execute(vals, null, false)
		if e.has_execute_failed() or not (r is float or r is int):
			last_error = "driver of '%s' did not give a number. Fix the expression." % d["key"]
			return NAN
		return float(r)
	var src := String(d.get("source", ""))
	if not inputs.has(src):
		last_error = "driver of '%s' reads '%s', which is not an input. Pick one of the inputs." % [d["key"], src]
		return NAN
	var lin := {"factor": d.get("factor", 1.0), "offset": d.get("offset", 0.0)}
	if d.has("from"):
		lin["from"] = d["from"]
	return Drivers.value(lin, float(inputs[src]))


## THE DRIVER PASS: each driver in list order sets its key's value (clamped). Key values are inputs by name, as the
## earlier drivers left them. Returns {key: value written}; a driver that fails leaves its key as it was.
static func drive(m: KMesh, inputs: Dictionary) -> Dictionary:
	last_error = ""
	var out := {}
	var inp := inputs.duplicate()
	for k in keys(m):
		if String(k["name"]).is_valid_identifier() and not inp.has(k["name"]):
			inp[k["name"]] = float(k["value"])
	var err := ""
	for d in m.shapes.get("drivers", []):
		var v := driver_value(d, inp)
		if is_nan(v):
			err = last_error
			continue
		var kept := set_value(m, String(d["key"]), v)
		if is_nan(kept):
			continue
		out[d["key"]] = kept
		if String(d["key"]).is_valid_identifier():
			inp[d["key"]] = kept
	last_error = err
	return out


# ---------------------------------------------------------------- file (KMesh.to_dict / from_dict "shapes")

static func to_file(sh: Dictionary) -> Dictionary:
	var ks := []
	for k in sh["keys"]:
		ks.append({"name": k["name"], "rel": k["rel"], "value": k["value"], "min": k["min"], "max": k["max"], "mute": k["mute"],
			"group": k["group"], "frame": k["frame"], "d": KMesh._pack((k["delta"] as PackedVector3Array).to_byte_array())})
	return {"basis": KMesh._pack((sh["basis"] as PackedVector3Array).to_byte_array()), "relative": sh.get("relative", true),
		"eval_time": sh.get("eval_time", 0.0), "keys": ks, "drivers": (sh.get("drivers", []) as Array).duplicate(true)}


## the live form from a file block for a mesh of nv vertices; {} with KMesh.last_error set when damaged (null = no block)
static func from_file(d, nv: int) -> Dictionary:
	if d == null:
		return {}
	if not (d is Dictionary and d.get("keys") is Array):
		KMesh.last_error = "the shape keys block is damaged. Re-save the mesh from the app, or restore a backup."
		return {}
	var braw := KMesh._unpack(d.get("basis"), "shape key basis")
	if KMesh.last_error != "":
		return {}
	if braw.size() != nv * 12:
		KMesh.last_error = "the shape key basis has %d bytes but the mesh %d vertices. The file is damaged: restore a backup." % [braw.size(), nv]
		return {}
	var ks := []
	var seen := {BASIS: true}
	for k in d["keys"]:
		if not (k is Dictionary and k.has("name")) or seen.has(String(k["name"])):
			KMesh.last_error = "a shape key is damaged or named twice. Re-save the mesh from the app, or restore a backup."
			return {}
		var raw := KMesh._unpack(k.get("d"), "shape key '%s'" % str(k["name"]))
		if KMesh.last_error != "":
			return {}
		if raw.size() != nv * 12:
			KMesh.last_error = "shape key '%s' does not match the %d vertices. The file is damaged: restore a backup." % [str(k["name"]), nv]
			return {}
		var rel := String(k.get("rel", BASIS))
		if not seen.has(rel):
			rel = BASIS   # a reference must come earlier in the list (no loops); an unknown one falls back to the basis
		seen[String(k["name"])] = true
		ks.append({"name": String(k["name"]), "delta": raw.to_vector3_array(), "rel": rel, "value": float(k.get("value", 0.0)),
			"min": float(k.get("min", 0.0)), "max": float(k.get("max", 1.0)), "mute": bool(k.get("mute", false)),
			"group": String(k.get("group", "")), "frame": float(k.get("frame", FRAME_STEP * (ks.size() + 1)))})
	var drv := []
	if d.get("drivers") is Array:
		for x in d["drivers"]:
			if x is Dictionary and seen.has(String(x.get("key", ""))) and (x.has("expr") or x.has("source")):
				drv.append(x.duplicate(true))
	return {"basis": braw.to_vector3_array(), "relative": bool(d.get("relative", true)), "eval_time": float(d.get("eval_time", 0.0)),
		"keys": ks, "drivers": drv}


## a deep copy (an undo snapshot)
static func snapshot(sh: Dictionary) -> Dictionary:
	return sh.duplicate(true)


static func bytes(sh: Dictionary) -> int:
	if sh.is_empty():
		return 0
	return (sh["basis"] as PackedVector3Array).size() * 12 * (1 + (sh["keys"] as Array).size())
