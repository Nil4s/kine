extends RefCounted
## C38 BOOLEANS YOU CAN TRUST (complaints #85 coincident faces, #289 a slow boolean). Units are metres (KCad's).
## 1. polish(): run Join / Cut / Intersect; when the kernel hands back a solid with OPEN edges (the tool's face or a tangent surface sat exactly on the
##    target's), retry with the tool moved 0.01 mm on every axis at once (8 sign combinations); keep the first result that is watertight, within
##    0.5 % of the first answer's volume and no more lumps. The nudge is reported in words (result "words").
## 2. run_job(): many tools against one target, one tool per frame, a progress callback, a Cancel flag. KCad calls are NOT run on a worker thread: the
##    kernel keeps one global solid table with no lock, so a call from two threads is unsafe. One kernel call cannot be interrupted, so Cancel and
##    progress act BETWEEN steps; a cancelled job releases every temp and returns the target id it was given, untouched.
const KCad := preload("res://scripts/kcad.gd")
const JOINH := preload("res://scripts/build/join_helper.gd")
const NUDGE := 0.00001          # 0.01 mm
const VOL_TOL := 0.005          # a nudged answer may differ by 0.5 % of the first answer
const GRID := 1.0e5             # vertex quantum for the edge count: 0.01 mm


## --- the mesh of a solid, checked ---------------------------------------------------------------------------------------------------
## {"open": edges not owned by exactly two triangles (degenerate triangles ignored), "lumps": edge-connected pieces, "tris": count}
static func inspect(id: int) -> Dictionary:
	return inspect_mesh(KCad.tessellate(id, 0.001) if id != 0 else null)


static func inspect_mesh(m: Mesh) -> Dictionary:
	var out := {"open": -1, "lumps": 0, "tris": 0}
	if m == null or m.get_surface_count() == 0:
		return out
	var own := {}
	var par := {}
	var tris := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		var n: int = (ix as PackedInt32Array).size() if ix != null else v.size()
		var i := 0
		while i + 2 < n:
			var k: Array = []
			for j in 3:
				var p: Vector3 = v[ix[i + j]] if ix != null else v[i + j]
				k.append(Vector3i((p * GRID).round()))
			i += 3
			if k[0] == k[1] or k[1] == k[2] or k[0] == k[2]:
				continue
			tris += 1
			for j in 3:
				var a: Vector3i = k[j]
				var b: Vector3i = k[(j + 1) % 3]
				var lo := a if _less(a, b) else b
				var hi := b if _less(a, b) else a
				var key := "%d,%d,%d|%d,%d,%d" % [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]
				own[key] = int(own.get(key, 0)) + 1
				_union(par, "%d,%d,%d" % [a.x, a.y, a.z], "%d,%d,%d" % [b.x, b.y, b.z])
	var open := 0
	for key in own:
		if int(own[key]) != 2:
			open += 1
	var roots := {}
	for k in par:
		roots[_find(par, k)] = true
	out["open"] = open
	out["lumps"] = roots.size()
	out["tris"] = tris
	return out


static func _less(a: Vector3i, b: Vector3i) -> bool:
	return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))


static func _find(par: Dictionary, k: String) -> String:
	while par.get(k, k) != k:
		par[k] = par.get(par[k], par[k])
		k = par[k]
	return k


static func _union(par: Dictionary, a: String, b: String) -> void:
	if not par.has(a):
		par[a] = a
	if not par.has(b):
		par[b] = b
	var ra := _find(par, a)
	var rb := _find(par, b)
	if ra != rb:
		par[ra] = rb


static func _op(a: int, b: int, op: String) -> int:
	match op:
		"join":
			return KCad.union(a, b)
		"cut":
			return KCad.cut(a, b)
	return KCad.intersect(a, b)


## --- 1. coincident faces ------------------------------------------------------------------------------------------------------------
## {"id": a NEW solid (0 = the kernel refused), "nudged": bool, "by": Vector3, "words": "" when nothing was needed, "open_before", "open_after",
##  "vol_change": fraction}. Neither a nor b is released. `first` = an answer the caller already has (then polish owns it: it is released if replaced).
static func polish(a: int, b: int, op: String, first := 0) -> Dictionary:
	var nx := first if first != 0 else _op(a, b, op)
	var r := {"id": nx, "nudged": false, "by": Vector3.ZERO, "words": "", "open_before": 0, "open_after": 0, "vol_change": 0.0}
	if nx == 0:
		return r
	var q := inspect(nx)
	r["open_before"] = int(q["open"])
	r["open_after"] = int(q["open"])
	if int(q["open"]) <= 0:
		return r
	if JOINH.contact(a, b)["kind"] in ["line", "point"]:
		return r   # two solids that only touch along a line / at a point are W10's (JoinHelper.explain says so and offers the nudge); not changed here
	var v0 := KCad.volume(nx)
	for sg in [Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(1, -1, -1), Vector3(-1, -1, -1)]:
		var by: Vector3 = sg * NUDGE
		var t2 := KCad.translate(b, by)
		if t2 == 0:
			continue
		var n2 := _op(a, t2, op)
		KCad.release(t2)
		if n2 == 0:
			continue
		var q2 := inspect(n2)
		var dv := absf(KCad.volume(n2) - v0) / maxf(absf(v0), 1e-12)
		if int(q2["open"]) == 0 and dv <= VOL_TOL and int(q2["lumps"]) <= int(q["lumps"]):
			KCad.release(nx)
			r["id"] = n2
			r["nudged"] = true
			r["by"] = by
			r["open_after"] = 0
			r["vol_change"] = dv
			r["words"] = "Two surfaces sat exactly on each other (%d open edges in the first answer), so the tool was moved 0.01 mm to give one clean solid; the volume changed by %s %%." % [int(q["open"]), String.num(dv * 100.0, 3)]
			return r
		KCad.release(n2)
	r["words"] = "Two surfaces sit exactly on each other and a 0.01 mm nudge did not clean the result (%d open edges); move one of the bodies slightly." % int(q["open"])
	return r


## --- 2. a heavy boolean, in steps ---------------------------------------------------------------------------------------------------
## job = {"cancel": bool (set it from a button), "on_progress": Callable(done, total, text)}. Awaitable. Returns
## {"ok", "cancelled", "id" (the new solid, or `target` itself when cancelled/failed: then nothing was made), "done", "total", "nudged", "words"}.
static func run_job(tree: SceneTree, target: int, tools: Array, op: String, job: Dictionary) -> Dictionary:
	var res := {"ok": false, "cancelled": false, "id": target, "done": 0, "total": tools.size(), "nudged": 0, "words": ""}
	var cur := target
	var prog: Callable = job.get("on_progress", Callable())
	for i in tools.size():
		if prog.is_valid():
			prog.call(i, tools.size(), "%s %d of %d" % [op.capitalize(), i + 1, tools.size()])
		await tree.process_frame     # the UI paints and a Cancel click lands here, between kernel calls
		if bool(job.get("cancel", false)):
			if cur != target:
				KCad.release(cur)
			res["cancelled"] = true
			res["id"] = target
			res["words"] = "Cancelled after %d of %d; the part is unchanged." % [i, tools.size()]
			return res
		var p := polish(cur, tools[i], op)
		if cur != target:
			KCad.release(cur)
		if int(p["id"]) == 0:
			res["id"] = target
			res["words"] = "Step %d failed: %s" % [i + 1, KCad.last_error()]
			return res
		cur = int(p["id"])
		if bool(p["nudged"]):
			res["nudged"] = int(res["nudged"]) + 1
			res["words"] = String(p["words"])
		res["done"] = i + 1
	if prog.is_valid():
		prog.call(tools.size(), tools.size(), "Done")
	res["ok"] = true
	res["id"] = cur
	return res
