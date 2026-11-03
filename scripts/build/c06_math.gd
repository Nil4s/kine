class_name C06Math
extends RefCounted
## C06 AGENT MATH FOR BUILDING: the extra fields part_facts answers (an agent that cannot see the screen reads them over MCP). All of them are ADDED keys;
## no old key changes. Same maths as the rest of part_facts (the kernel's solids, PartFacts.Model), so the numbers are the ones tests/fdesk_test.gd,
## fflat_test.gd and erepeat_test.gd judge (fdesk: Part.replay(part)["aabb"], which is the whole part's box).
##   box_mm          {min, max, size}: the box of ALL bodies in mm, same frame as the record (y up). A desk's top is box_mm.max[1].
##   bodies_math     per body: {n, name, volume_mm3, box_min, box_max, size_mm}
##   failed_steps    [{id, name, t, msg}]: the steps the replay could not run (empty = clean)
##   touching_pairs  [[a, b]] (1-based): bodies that touch (gap <= PartFacts.TOUCH_MM) and do not overlap
##   gap             only when the request has {gap: [a, b]} (1-based): {a, b, gap_mm, touching, overlap_mm3}
##   holes           [{feature, name, radius_mm, centre_mm: [x, y], plane}]: every circle of a sketch that a CUT extrude uses
##   fillets         [{feature, name, body, radius_mm, ok}]: every fillet step, ok = it ran


static func _name_of(rec: Dictionary, id: String) -> Dictionary:
	for f in (rec.get("features", []) as Array):
		if String(f.get("id", "")) == id:
			return f
	return {}


static func extra(M: PartFacts.Model, C: Dictionary, opts: Dictionary) -> Dictionary:
	var out := {}
	var bb := AABB()
	var bm := []
	for i in M.n:
		var b: AABB = M.box(i)
		bb = b if i == 0 else bb.merge(b)
		bm.append({"n": i + 1, "name": String(M.labels[i]), "volume_mm3": snappedf(M.vol_mm3[i], 0.01),
			"box_min": _a(b.position), "box_max": _a(b.end), "size_mm": _a(b.size)})
	out["box_mm"] = {"min": _a(bb.position), "max": _a(bb.end), "size": _a(bb.size)}
	out["bodies_math"] = bm
	var fails := []
	for id in M.errors:
		var f := _name_of(M.rec, String(id))
		fails.append({"id": String(id), "name": String(f.get("name", "")), "t": String(f.get("t", "")), "msg": String(M.errors[id])})
	out["failed_steps"] = fails
	out["touching_pairs"] = (C["touches"] as Array).map(func(p): return [int(p[0]) + 1, int(p[1]) + 1])
	var g: Variant = opts.get("gap", null)
	if g is Array and (g as Array).size() == 2:
		var a := int(g[0]) - 1
		var b2 := int(g[1]) - 1
		if a >= 0 and b2 >= 0 and a < M.n and b2 < M.n and a != b2:
			var ov := M.overlap(a, b2)
			var gp := M.gap(a, b2) if ov <= PartFacts.HIT_MM3 else 0.0
			out["gap"] = {"a": a + 1, "b": b2 + 1, "gap_mm": snappedf(gp, 0.001), "touching": ov <= PartFacts.HIT_MM3 and gp <= PartFacts.TOUCH_MM, "overlap_mm3": snappedf(ov, 0.01)}
		else:
			out["gap"] = {"error": "gap needs two different body numbers 1..%d" % M.n}
	var holes := []
	var fil := []
	var feats: Array = M.rec.get("features", [])
	for f in feats:
		var t := String(f.get("t", ""))
		if t == "extrude" and String(f.get("op", "")) == "cut":
			var sk := _name_of(M.rec, String(f.get("sketch", "")))
			for e in (sk.get("ents", []) as Array):
				if String(e.get("k", "")) == "circle":
					holes.append({"feature": String(f.get("id", "")), "name": String(f.get("name", "")), "radius_mm": snappedf(float(e.get("r", 0.0)), 0.0001),
						"centre_mm": [float(e["c"][0]), float(e["c"][1])], "plane": String(sk.get("plane", ""))})
		elif t == "fillet":
			fil.append({"feature": String(f.get("id", "")), "name": String(f.get("name", "")), "body": int(f.get("body", 0)) + 1,
				"radius_mm": snappedf(float(f.get("r", 0.0)), 0.0001), "ok": not M.errors.has(String(f.get("id", "")))})
	out["holes"] = holes
	out["fillets"] = fil
	return out


static func _a(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
