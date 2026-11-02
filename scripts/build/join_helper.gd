extends RefCounted
## W10 JOIN HELPER: two solids, four plain modes (Join / Cut / Overlap / New part), a plain-words reason when the kernel result is not
## what was meant ("these only touch along a line"), a one-click 0.01 mm nudge, and a body count after. Units are metres (KCad's).
## Nothing here releases the inputs: the caller owns a and b; every id in a result's "bodies" is a new solid the caller owns.
## result: {"ok", "mode", "bodies": [ids], "count": bodies after (counted, not assumed), "contact": {"kind","where"}, "message", "nudge": bool, "nudge_by": Vector3}

const KCad := preload("res://scripts/kcad.gd")
const MODES := ["join", "cut", "overlap", "new"]
const MODE_NAMES := {"join": "Join", "cut": "Cut", "overlap": "Overlap", "new": "New part"}
const NUDGE := 0.00001          # 0.01 mm
const TOL := 1e-7               # 0.1 micron: what "touching" means
const VOL_EPS := 1e-13          # m3: below this a shared volume is a skin
const NUDGE_ASK := "Nudge 0.01 mm and try again?"


## --- bodies, counted ----------------------------------------------------------------------------------------------------------------
## The kernel hands a line-touching union back as ONE id holding two lumps, so the id count lies. Count the lumps: triangles that share
## an edge that exactly two triangles own are one lump (an edge four triangles own is non-manifold: two solids meeting along a line).
static func lumps(id: int) -> int:
	var m := KCad.tessellate(id, 0.001)
	if m == null or m.get_surface_count() == 0:
		return 0
	var key := {}
	var tris: Array = []
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		var n: int = (ix as PackedInt32Array).size() if ix != null else v.size()
		var i := 0
		while i + 2 < n:
			var t := []
			for k in 3:
				var p: Vector3 = v[ix[i + k]] if ix != null else v[i + k]
				var q := Vector3i(roundi(p.x / TOL), roundi(p.y / TOL), roundi(p.z / TOL))
				if not key.has(q):
					key[q] = key.size()
				t.append(key[q])
			tris.append(t)
			i += 3
	var edge_tris := {}
	for ti in tris.size():
		var t: Array = tris[ti]
		for k in 3:
			var a: int = t[k]
			var b: int = t[(k + 1) % 3]
			var e := Vector2i(mini(a, b), maxi(a, b))
			if not edge_tris.has(e):
				edge_tris[e] = []
			(edge_tris[e] as Array).append(ti)
	var par := PackedInt32Array()
	par.resize(tris.size())
	for i in par.size():
		par[i] = i
	for e in edge_tris:
		var l: Array = edge_tris[e]
		if l.size() == 2:
			var ra := _root(par, l[0])
			var rb := _root(par, l[1])
			if ra != rb:
				par[ra] = rb
	var roots := {}
	for i in par.size():
		roots[_root(par, i)] = true
	return roots.size()


static func _root(par: PackedInt32Array, i: int) -> int:
	while par[i] != i:
		par[i] = par[par[i]]
		i = par[i]
	return i


static func _aabb(id: int) -> AABB:
	var m := KCad.tessellate(id, 0.001)
	if m == null:
		return AABB()
	return m.get_aabb()


## --- how two solids touch -----------------------------------------------------------------------------------------------------------
## {"kind": "overlap"|"face"|"line"|"point"|"apart", "where": words}. Judged on the shared box of the two: its zero-width sides say face/line/point.
static func contact(a: int, b: int) -> Dictionary:
	var x := KCad.intersect(a, b)
	var vol := KCad.volume(x) if x != 0 else 0.0
	if x != 0:
		KCad.release(x)
	if vol > VOL_EPS:
		return {"kind": "overlap", "where": "they share volume"}
	var A := _aabb(a)
	var B := _aabb(b)
	var lo := Vector3(maxf(A.position.x, B.position.x), maxf(A.position.y, B.position.y), maxf(A.position.z, B.position.z))
	var hi := Vector3(minf(A.end.x, B.end.x), minf(A.end.y, B.end.y), minf(A.end.z, B.end.z))
	var ext := hi - lo
	if ext.x < -TOL or ext.y < -TOL or ext.z < -TOL:
		return {"kind": "apart", "where": "they do not meet"}
	var zero := 0
	var names := PackedStringArray()
	for k in 3:
		if ext[k] <= TOL:
			zero += 1
			names.append("xyz".substr(k, 1) + " = %s mm" % String.num((lo[k] + hi[k]) * 500.0, 3))
	if zero == 0:
		return {"kind": "apart", "where": "their boxes cross but the shapes do not meet"}
	var kind := "face" if zero == 1 else ("line" if zero == 2 else "point")
	return {"kind": kind, "where": ", ".join(names)}


## the move that makes b sink 0.01 mm into a on each axis where the two only meet (b's centre toward a's centre)
static func nudge_vector(a: int, b: int) -> Vector3:
	var A := _aabb(a)
	var B := _aabb(b)
	var lo := Vector3(maxf(A.position.x, B.position.x), maxf(A.position.y, B.position.y), maxf(A.position.z, B.position.z))
	var hi := Vector3(minf(A.end.x, B.end.x), minf(A.end.y, B.end.y), minf(A.end.z, B.end.z))
	var v := Vector3.ZERO
	for k in 3:
		if hi[k] - lo[k] <= TOL:
			v[k] = NUDGE if A.get_center()[k] > B.get_center()[k] else -NUDGE
	return v


## --- the four modes -----------------------------------------------------------------------------------------------------------------
static func run(a: int, b: int, mode: String) -> Dictionary:
	var r := {"ok": false, "mode": mode, "bodies": [], "count": 0, "contact": {}, "message": "", "nudge": false, "nudge_by": Vector3.ZERO}
	if not KCad.available() or a == 0 or b == 0:
		r["message"] = "the solid kernel is not available"
		return r
	var c := contact(a, b)
	r["contact"] = c
	var out := 0
	match mode:
		"new":
			r["bodies"] = [KCad.translate(a, Vector3.ZERO), KCad.translate(b, Vector3.ZERO)]
			r["ok"] = true
			r["count"] = 2
			r["message"] = "Kept as two separate parts (2 bodies)."
			return r
		"join":
			out = KCad.union(a, b)
		"cut":
			out = KCad.cut(a, b)
		"overlap":
			out = KCad.intersect(a, b)
		_:
			r["message"] = "%s is not Join, Cut, Overlap or New part" % mode
			return r
	var empty := out == 0 or KCad.volume(out) <= VOL_EPS
	if out != 0 and not empty:
		r["bodies"] = [out]
		r["count"] = lumps(out)
	elif out != 0:
		KCad.release(out)
	var touches: bool = c["kind"] in ["line", "point"]
	var why := ""
	if c["kind"] == "line":
		why = "these only touch along a line (%s)" % c["where"]
	elif c["kind"] == "point":
		why = "these only touch at a point (%s)" % c["where"]
	elif c["kind"] == "apart":
		why = "these do not touch: %s" % c["where"]
	if empty:
		r["message"] = "%s left nothing: %s" % [MODE_NAMES[mode], why if why != "" else "the two have no shared volume to work with"]
		r["nudge"] = touches
	elif mode == "join" and int(r["count"]) > 1:
		r["message"] = "Join did not make one part (%d bodies): %s" % [r["count"], why if why != "" else "they are not connected"]
		r["nudge"] = touches
		_drop(r)
	elif mode == "cut" and (touches or c["kind"] == "apart"):
		r["message"] = "Cut changed nothing: %s" % why
		r["nudge"] = touches
		_drop(r)
	elif mode == "overlap" and touches:
		r["message"] = "Overlap found no shared volume: %s" % why
		r["nudge"] = true
		_drop(r)
	else:
		r["ok"] = true
		r["message"] = "%s done: %d %s." % [MODE_NAMES[mode], r["count"], "body" if int(r["count"]) == 1 else "bodies"]
	if r["nudge"]:
		r["nudge_by"] = nudge_vector(a, b)
		r["message"] += " Nudge 0.01 mm and try again?"
	return r


static func _drop(r: Dictionary) -> void:
	for id in r["bodies"]:
		KCad.release(id)
	r["bodies"] = []


## the one-click retry: b moved 0.01 mm into a, then the same mode. {"b": the moved solid (caller owns it), "result": run()'s answer}
static func nudged_retry(a: int, b: int, mode: String) -> Dictionary:
	var by := nudge_vector(a, b)
	var b2 := KCad.translate(b, by)
	var res := run(a, b2, mode)
	res["nudged"] = true
	res["nudge_by"] = by
	return {"b": b2, "result": res}


## W10: what a combine step (Part._combine_step) should say about a kernel answer nx for cur (op) tool. "" = nothing to say.
## Join must leave one counted lump; Cut and Intersect must not be a no-op / empty because the two only touch along a line or at a point.
## The words end with "Nudge 0.01 mm and try again?" when the nudge could fix it (the dialog then shows its button).
static func explain(cur: int, tool: int, op: String, nx: int) -> String:
	var c := contact(cur, tool)
	var touches: bool = c["kind"] in ["line", "point"]
	if not touches:
		return ""
	var why := "these only touch %s (%s)" % ["along a line" if c["kind"] == "line" else "at a point", c["where"]]
	if op == "join":
		if nx != 0 and lumps(nx) > 1:
			return "Join did not make one part (%d bodies): %s. %s" % [lumps(nx), why, NUDGE_ASK]
		return ""
	if op == "cut" and nx != 0:
		return "Cut changed nothing: %s. %s" % [why, NUDGE_ASK]
	if op == "intersect" and (nx == 0 or KCad.volume(nx) <= VOL_EPS):
		return "Overlap found no shared volume: %s. %s" % [why, NUDGE_ASK]
	return ""
