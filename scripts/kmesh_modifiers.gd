class_name KMeshModifiers
extends RefCounted
## A11 (docs/ROADMAP_400.md): the NON-DESTRUCTIVE MODIFIER STACK. The stack lives on the mesh as KMesh.modifiers (so
## .kmesh save / load and KMeshUndo carry it): an Array of plain dictionaries, top first,
##   {"type": "mirror" | "subdiv" | "solidify" | "array" | "displace", "on": bool, <that type's params (PARAMS)>}
## evaluate(base) runs the enabled ones in order on a COPY and returns the evaluated KMesh; the base is never touched.
## The model preview (kmesh_modifiers_ui.gd) draws the evaluated surface while selection, pick and every edit stay on the
## base cage. apply_mod(mesh, i) bakes one modifier into the base (the caller brackets it as ONE KMeshUndo step).
##
##   mirror    axis (X / Y / Z) through `plane` (m on that axis). Every vertex is reflected and every face copied with its
##             winding reversed (so it still faces out). merge on: a vertex within merge_dist of the plane is shared by
##             both halves and snapped onto the plane, so a half mesh open at the plane comes back closed and manifold.
##             A face whose corners all lie on the plane is not copied (it would be its own reversed twin).
##   subdiv    `levels` of Catmull-Clark: KMeshSubdiv.subdivide (A12; the mesh's "crease" edge channel is honoured).
##   solidify  a shell of `thickness`: every vertex gets a twin along its vertex normal, the original surface sits at
##             offset +1 (outside) .. -1 (inside, the default, as Blender) of the shell; the twins' faces are reversed;
##             rim on: a quad wall on every boundary edge. even on: the step is divided by the mean cosine between the
##             vertex normal and its faces' normals, so a flat face stays exactly `thickness` from its twin even at a
##             corner (off: a cube's corner gets t / sqrt(3)). The factor is capped at EVEN_CAP.
##   array     `count` copies, copy k moved by k * (rel_x/y/z * the bounding box size + off_x/y/z m) (Blender's relative
##             and constant offsets, summed). No merging between copies.
##   displace  every vertex moved by strength (m) along its normal or X / Y / Z, times the texture: "none" = 1 for every
##             vertex (Blender would give 0.5 with its 0.5 midlevel; here the strength is the distance), "noise" =
##             FastNoiseLite simplex in -1..1 at (vertex position / noise_size), seeded (same seed = same result).
## Attributes (A09): subdiv carries them (KMeshSubdiv), displace keeps them (same topology); mirror, solidify and array
## drop them (the evaluated mesh is for the viewport; apply_mod on those leaves the base without channels).

const TYPES := ["mirror", "subdiv", "solidify", "array", "displace"]
const NAMES := {"mirror": "Mirror", "subdiv": "Subdivide", "solidify": "Solidify", "array": "Array", "displace": "Displace"}
const EVEN_CAP := 4.0
## [name, default, min, max, step, kind]: kind "m" a length in metres (the panel shows cm), "f" a float, "i" an int,
## "b" a bool, "e:a,b,c" a choice (stored as its index)
const PARAMS := {
	"mirror": [["axis", 0, 0, 2, 1, "e:X,Y,Z"], ["merge", true, 0, 1, 1, "b"], ["merge_dist", 0.001, 0.0, 0.1, 0.0001, "m"], ["plane", 0.0, -10.0, 10.0, 0.001, "m"]],
	"subdiv": [["levels", 1, 1, 4, 1, "i"]],
	"solidify": [["thickness", 0.02, 0.0, 1.0, 0.0005, "m"], ["offset", -1.0, -1.0, 1.0, 0.1, "f"], ["even", false, 0, 1, 1, "b"], ["rim", true, 0, 1, 1, "b"]],
	"array": [["count", 2, 1, 100, 1, "i"], ["rel_x", 1.0, -10.0, 10.0, 0.05, "f"], ["rel_y", 0.0, -10.0, 10.0, 0.05, "f"], ["rel_z", 0.0, -10.0, 10.0, 0.05, "f"],
		["off_x", 0.0, -10.0, 10.0, 0.001, "m"], ["off_y", 0.0, -10.0, 10.0, 0.001, "m"], ["off_z", 0.0, -10.0, 10.0, 0.001, "m"]],
	"displace": [["strength", 0.05, -1.0, 1.0, 0.001, "m"], ["direction", 0, 0, 3, 1, "e:normal,X,Y,Z"], ["texture", 1, 0, 1, 1, "e:none,noise"],
		["noise_size", 0.25, 0.01, 10.0, 0.01, "m"], ["seed", 0, 0, 9999, 1, "i"]],
}

## message of the last failed call (empty after a success); each names a next step
static var last_error := ""


# ---------------------------------------------------------------- the stack (data)

## one modifier with every param of its type in range and of its kind's type (missing = the default). {} for an unknown type
static func clean(mod: Dictionary) -> Dictionary:
	var t := String(mod.get("type", ""))
	if not PARAMS.has(t):
		return {}
	var d := {"type": t, "on": bool(mod.get("on", true))}
	for p in PARAMS[t]:
		var v = mod.get(p[0], p[1])
		var kind := String(p[5])
		if kind == "b":
			d[p[0]] = bool(v)
		elif kind == "i" or kind.begins_with("e:"):
			d[p[0]] = clampi(int(v), int(p[2]), int(p[3]))
		else:
			d[p[0]] = clampf(float(v), float(p[2]), float(p[3]))
	return d


## the stack as it goes into the .kmesh ("modifiers"): plain JSON values
static func to_file(stack: Array) -> Array:
	var out := []
	for mod in stack:
		out.append(clean(mod))
	return out


## the stack read back from a file. Not an array, or a modifier of an unknown type: [] with last_error set
static func from_file(d) -> Array:
	last_error = ""
	if d == null:
		return []
	if not (d is Array):
		last_error = "the modifier stack is damaged (not a list). Re-save the mesh from the app, or restore a backup."
		return []
	var out := []
	for i in d.size():
		var c := clean(d[i]) if d[i] is Dictionary else {}
		if c.is_empty():
			last_error = "modifier %d has an unknown type '%s'. Update Kine, or restore a backup." % [i + 1, str(d[i].get("type", "?")) if d[i] is Dictionary else "?"]
			return []
		out.append(c)
	return out


## add a modifier of `type` at the bottom of the mesh's stack. Returns its index, -1 with last_error set
static func add(mesh: KMesh, type: String, params := {}) -> int:
	last_error = ""
	if not PARAMS.has(type):
		last_error = "no modifier called '%s'. Pick one of %s." % [type, ", ".join(TYPES)]
		return -1
	var p := params.duplicate()
	p["type"] = type
	mesh.modifiers.append(clean(p))
	return mesh.modifiers.size() - 1


static func remove(mesh: KMesh, i: int) -> bool:
	if i < 0 or i >= mesh.modifiers.size():
		return false
	mesh.modifiers.remove_at(i)
	return true


## move modifier i to index `to` (clamped). Returns the new index, -1 when i is not in the stack
static func move(mesh: KMesh, i: int, to: int) -> int:
	if i < 0 or i >= mesh.modifiers.size():
		return -1
	to = clampi(to, 0, mesh.modifiers.size() - 1)
	var mod = mesh.modifiers[i]
	mesh.modifiers.remove_at(i)
	mesh.modifiers.insert(to, mod)
	return to


static func toggle(mesh: KMesh, i: int) -> bool:
	if i < 0 or i >= mesh.modifiers.size():
		return false
	mesh.modifiers[i]["on"] = not bool(mesh.modifiers[i]["on"])
	return mesh.modifiers[i]["on"]


## set one param (clamped to its range). Returns the value it got, null when there is no such modifier / param
static func set_param(mesh: KMesh, i: int, key: String, value):
	if i < 0 or i >= mesh.modifiers.size() or not (key == "on" or mesh.modifiers[i].has(key)):
		return null
	var d: Dictionary = mesh.modifiers[i].duplicate()
	d[key] = value
	mesh.modifiers[i] = clean(d)
	return mesh.modifiers[i][key]


static func any_on(stack: Array) -> bool:
	for mod in stack:
		if bool(mod.get("on", true)):
			return true
	return false


## a short line for the panel / status: "Mirror X, merge 1 mm"
static func describe(mod: Dictionary) -> String:
	var t := String(mod["type"])
	match t:
		"mirror":
			return "Mirror %s%s" % ["XYZ"[int(mod["axis"])], ", merge %s" % Units.len(mod["merge_dist"]) if mod["merge"] else ""]
		"subdiv":
			return "Subdivide x%d" % int(mod["levels"])
		"solidify":
			return "Solidify %s%s" % [Units.len(mod["thickness"]), " even" if mod["even"] else ""]
		"array":
			return "Array x%d" % int(mod["count"])
		"displace":
			return "Displace %s %s" % [Units.len(mod["strength"]), ["normal", "X", "Y", "Z"][int(mod["direction"])]]
	return t


# ---------------------------------------------------------------- evaluation

## THE STACK: a new KMesh, the base with every enabled modifier of `stack` (null = base.modifiers) run top to bottom,
## stopping after index `upto` (-1 = all). The base is never changed; with nothing enabled the result is a copy.
static func evaluate(base: KMesh, stack = null, upto := -1) -> KMesh:
	var st: Array = base.modifiers if stack == null else stack
	var cur := base
	for i in st.size():
		if upto >= 0 and i > upto:
			break
		if not bool(st[i].get("on", true)):
			continue
		cur = run(cur, st[i])
	if cur == base:
		cur = _copy(base)
	return cur


## one modifier on `m` (not changed): a new KMesh
static func run(m: KMesh, mod: Dictionary) -> KMesh:
	var c := clean(mod)
	match String(c.get("type", "")):
		"mirror":
			return mirror(m, c["axis"], c["merge"], c["merge_dist"], c["plane"])
		"subdiv":
			return KMeshSubdiv.subdivide(m, c["levels"])
		"solidify":
			return solidify(m, c["thickness"], c["offset"], c["even"], c["rim"])
		"array":
			var lo := Vector3.INF
			var hi := -Vector3.INF
			for v in m.verts:
				lo = lo.min(v)
				hi = hi.max(v)
			var size := (hi - lo) if m.vert_count() > 0 else Vector3.ZERO
			var off := Vector3(c["rel_x"], c["rel_y"], c["rel_z"]) * size + Vector3(c["off_x"], c["off_y"], c["off_z"])
			return array(m, c["count"], off)
		"displace":
			return displace(m, c["strength"], c["direction"], c["texture"] == 1, c["noise_size"], c["seed"])
	return _copy(m)


static func _copy(m: KMesh) -> KMesh:
	var r := KMesh.new().from_arrays(m.verts, m.faces)
	r.attrs = m.attr_snapshot() if not m.attrs.is_empty() else {}
	return r


static func mirror(m: KMesh, axis := 0, merge := true, merge_dist := 0.001, plane := 0.0) -> KMesh:
	var nv := m.verts.size()
	var V := m.verts.duplicate()
	var map := PackedInt32Array()
	map.resize(nv)
	for v in nv:
		var p := V[v]
		if merge and absf(p[axis] - plane) <= merge_dist:
			p[axis] = plane
			V[v] = p
			map[v] = v
		else:
			p[axis] = 2.0 * plane - p[axis]
			map[v] = V.size()
			V.append(p)
	var F: Array = m.faces.duplicate()
	for f in m.faces:
		var fp: PackedInt32Array = f
		var n := fp.size()
		var g := PackedInt32Array()
		g.resize(n)
		var all_on := true
		for i in n:
			g[i] = map[fp[n - 1 - i]]
			all_on = all_on and map[fp[i]] == fp[i]
		if not all_on:
			F.append(g)
	return KMesh.new().from_arrays(V, F)


static func solidify(m: KMesh, thickness := 0.02, offset := -1.0, even := false, rim := true) -> KMesh:
	var nv := m.verts.size()
	var vn := m.vert_normals
	var fn := m.face_normals
	var k := PackedFloat32Array()   # the step factor per vertex (1, or 1 / mean cos for even)
	k.resize(nv)
	k.fill(1.0)
	if even:
		var sum := PackedFloat32Array()
		var cnt := PackedInt32Array()
		sum.resize(nv)
		cnt.resize(nv)
		for fi in m.faces.size():
			for v in (m.faces[fi] as PackedInt32Array):
				sum[v] += vn[v].dot(fn[fi])
				cnt[v] += 1
		for v in nv:
			if cnt[v] > 0 and sum[v] > 0.0:
				k[v] = minf(float(cnt[v]) / sum[v], EVEN_CAP)
	var hi := thickness * (offset + 1.0) * 0.5
	var lo := thickness * (offset - 1.0) * 0.5
	var V := PackedVector3Array()
	V.resize(nv * 2)
	for v in nv:
		V[v] = m.verts[v] + vn[v] * (hi * k[v])
		V[v + nv] = m.verts[v] + vn[v] * (lo * k[v])
	var F: Array = m.faces.duplicate()
	for f in m.faces:
		var fp: PackedInt32Array = f
		var n := fp.size()
		var g := PackedInt32Array()
		g.resize(n)
		for i in n:
			g[i] = fp[n - 1 - i] + nv
		F.append(g)
	if rim:
		var hv := m.he_vert
		var hn := m.he_next
		var ht := m.he_twin
		for h in hv.size():
			if ht[h] == -1:
				var a := hv[h]
				var b := hv[hn[h]]
				F.append(PackedInt32Array([b, a, a + nv, b + nv]))
	return KMesh.new().from_arrays(V, F)


static func array(m: KMesh, count := 2, off := Vector3(1, 0, 0)) -> KMesh:
	var nv := m.verts.size()
	var V := PackedVector3Array()
	V.resize(nv * count)
	var F: Array = []
	for c in count:
		var d := off * float(c)
		var o := nv * c
		for v in nv:
			V[o + v] = m.verts[v] + d
		for f in m.faces:
			var g := PackedInt32Array(f)
			if o != 0:
				for i in g.size():
					g[i] += o
			F.append(g)
	return KMesh.new().from_arrays(V, F)


## direction 0 = the vertex normal, 1 / 2 / 3 = X / Y / Z
static func displace(m: KMesh, strength := 0.05, direction := 0, noise := true, noise_size := 0.25, rseed := 0) -> KMesh:
	var nv := m.verts.size()
	var V := m.verts.duplicate()
	var vn := m.vert_normals
	var fnl: FastNoiseLite = null
	if noise:
		fnl = FastNoiseLite.new()
		fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fnl.seed = rseed
		fnl.frequency = 1.0
		fnl.fractal_type = FastNoiseLite.FRACTAL_NONE
	var axis: Vector3 = [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK][direction]
	var inv := 1.0 / maxf(noise_size, 1e-6)
	for v in nv:
		var w := 1.0
		if fnl != null:
			var p := m.verts[v] * inv
			w = fnl.get_noise_3d(p.x, p.y, p.z)
		V[v] += (vn[v] if direction == 0 else axis) * (strength * w)
	var r := KMesh.new().from_arrays(V, m.faces)
	r.attrs = m.attr_snapshot() if not m.attrs.is_empty() else {}
	return r


# ---------------------------------------------------------------- bake

## APPLY: modifier i run on the base alone (as Blender does: the ones above it are not baked in) and written into the base;
## it leaves the stack. "" on success, else why not (the mesh is unchanged). Bracket with KMeshUndo begin / commit.
static func apply_mod(mesh: KMesh, i: int) -> String:
	last_error = ""
	if i < 0 or i >= mesh.modifiers.size():
		last_error = "there is no modifier %d. Pick one from the list." % (i + 1)
		return last_error
	var mod: Dictionary = mesh.modifiers[i]
	if not bool(mod.get("on", true)):
		last_error = "%s is turned off. Turn it on first (its tick), then apply." % NAMES[mod["type"]]
		return last_error
	if not KMeshShapes.keys(mesh).is_empty():
		last_error = "the mesh has shape keys: applying would break them (as in Blender). Remove the keys first, or keep the modifier live."
		return last_error
	var r := run(mesh, mod)
	mesh.attrs = {}   # the new channels are sized for the new mesh: from_arrays must not fit the old ones
	mesh.from_arrays(r.verts, r.faces)
	mesh.attrs = r.attrs
	if not mesh.shapes.is_empty():   # no keys: the basis is the rest shape, which is now the baked one
		mesh.shapes["basis"] = mesh.verts.duplicate()
	mesh.modifiers.remove_at(i)
	return ""
