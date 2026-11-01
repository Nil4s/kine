extends RefCounted
## PINCH / BULGE a face (Friday plan 23). A record step {"t": "bulge", "id", "name", "body": N, "face": {descriptor as offset_face's}, "k": -1..1}.
## The picked flat face keeps its outline (the rim stays where it was) and its middle moves out (k > 0, a dome added on) or in (k < 0, a dish cut
## out) by |k| x FRAC of the face's smaller side: 20 % at k = +-1, so +0.5 on a 40 mm face lifts the middle 4 mm. The dome is a REAL solid made by the
## kernel: a smooth loft through scaled copies of the face's own outline, each one lifted to h x (1 - s^2) (a paraboloid), ending in a 4 % copy; it is
## joined to (or cut from) the body, so the result is one closed solid. k = 0 changes nothing at all (no kernel call). Straight-edged faces (box
## tops, prisms) and round ones (a cylinder's end) work; any other outline says so.
const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const FRAC := 0.2   # the middle moves by up to this share of the face's smaller side at k = +-1
const SCALES := [1.0, 0.8, 0.6, 0.45, 0.3, 0.15, 0.04]   # the outline's size at each section; the dome height there is h x (1 - s^2)


## how far (mm) the middle moves for k on a face of this smaller side (mm): the number the bars expect
static func rise_mm(k: float, side_mm: float) -> float:
	return k * FRAC * side_mm


## replay's step: moves the middle of the face; "" or the plain reason it could not
static func apply(bodies: Array, f: Dictionary, match_face: Callable, bbox_of: Callable) -> String:
	var k := clampf(float(f.get("k", 0.0)), -1.0, 1.0)
	if bodies.is_empty():
		return "there is no body to pinch or bulge"
	if absf(k) < 1e-6:
		return ""
	var bi := clampi(int(f.get("body", 0)), 0, bodies.size() - 1)
	var fs := KCad.faces(bodies[bi])
	var j: int = match_face.call(fs, bbox_of.call(fs), f.get("face", {}))
	if j < 0:
		return "the face it pinches or bulges is not there any more"
	var face: Dictionary = fs[j]
	var n: Vector3 = (face["normal"] as Vector3).normalized()
	var c: Vector3 = face["center"]
	var x := n.cross(Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var y := n.cross(x)
	var outline := _outline(bodies[bi], int(face["id"]), c, x, y)
	if not outline.has("pts") and not outline.has("r"):
		return String(outline.get("err", "that face has no outline to bend"))
	var side: float = float(outline["side"])
	var h := rise_mm(k, side / MM) * MM
	var profs := PackedInt32Array()
	for s in SCALES:
		var items: Array
		if outline.has("r"):
			items = [KCad.circle(Vector2.ZERO, float(outline["r"]) * s)]
		else:
			var sp := PackedVector2Array()
			for p in outline["pts"]:
				sp.append((p as Vector2) * s)
			items = KCad.polygon(sp)
		var pf := KCad.sketch_face(items, c + n * (h * (1.0 - s * s)), x, n)
		if pf == 0:
			for q in profs:
				KCad.release(q)
			return "the face outline cannot be copied: " + KCad.last_error()
		profs.append(pf)
	var tool_id := KCad.loft(profs, false, true)
	for q in profs:
		KCad.release(q)
	if tool_id == 0:
		return "the kernel cannot bend this face: " + KCad.last_error()
	var r := KCad.union(bodies[bi], tool_id) if h > 0.0 else KCad.cut(bodies[bi], tool_id)
	KCad.release(tool_id)
	if r == 0:
		return KCad.last_error()
	KCad.release(bodies[bi])
	bodies[bi] = r
	return ""


## the face's outline in its own plane (centre c, axes x and y): {"pts": polygon (m), "side"} or {"r": radius, "side"} or {"err"}
static func _outline(body: int, face_id: int, c: Vector3, x: Vector3, y: Vector3) -> Dictionary:
	var es: Array = []
	for e in KCad.edges(body):
		if (e["faces"] as Array).has(face_id):
			es.append(e)
	if es.is_empty():
		return {"err": "that face has no edges"}
	if es.size() == 1:
		var e: Dictionary = es[0]
		if (e["a"] as Vector3).distance_to(e["b"]) < 1e-6 and float(e["length"]) > 1e-6:
			var r := float(e["length"]) / TAU
			return {"r": r, "side": 2.0 * r}
		return {"err": "that face is not a flat shape with straight sides or a round one"}
	for e in es:
		if absf(float(e["length"]) - (e["a"] as Vector3).distance_to(e["b"])) > 1e-6:
			return {"err": "that face has a curved side: pinch and bulge work on straight-sided and round faces"}
	var pts3: Array = [(es[0]["a"] as Vector3), (es[0]["b"] as Vector3)]
	var used := {0: true}
	while used.size() < es.size():
		var tip: Vector3 = pts3[-1]
		var found := false
		for i in es.size():
			if used.has(i):
				continue
			var a: Vector3 = es[i]["a"]
			var b: Vector3 = es[i]["b"]
			if a.distance_to(tip) < 1e-6:
				pts3.append(b)
			elif b.distance_to(tip) < 1e-6:
				pts3.append(a)
			else:
				continue
			used[i] = true
			found = true
			break
		if not found:
			return {"err": "that face's outline is not one closed loop"}
	pts3.pop_back()   # the last point is the first again
	var pts := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts3:
		var q := Vector2(((p as Vector3) - c).dot(x), ((p as Vector3) - c).dot(y))
		pts.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	if pts.size() < 3:
		return {"err": "that face has fewer than three corners"}
	return {"pts": pts, "side": minf(hi.x - lo.x, hi.y - lo.y)}
