class_name PartRefs
extends RefCounted
const KCad := preload("res://scripts/kcad.gd")
## W03 STABLE REFERENCES. A later step must land on the same intended spot when an early step changes.
## Three ways a later feature loses its target (measured in tests/w03_test.gd, 7-step fixture, step-1 width 40 -> 60):
##   1 HINGE PIVOT  hinge "o" is an absolute point: after the box grows to 60 the pivot stays at x = 40, 20 mm inside the part. FIXED here:
##                  pin_hinge stores "oq" (the pivot as 0..1 inside the hinged body's box at that step, same idea as a fillet edge's "q"); pivot() reads it.
##   2 FILLET EDGE  part.gd match_edge keys on the edge centre as 0..1 of the whole edge-box plus direction. It survives a resize, but a feature that
##                  keeps its own absolute place (a hole at x = 10) moves in 0..1 terms and the nearest edge can be a different one. Plan in the report.
##   3 BODY INDEX   pattern / hinge / combine / bname / appear store "body": N (an index). 241's keys (<feature id>#<k>) are stable, indexes are not;
##                  a step that adds or drops a body earlier shifts every later N. Plan in the report.
## A pinned pivot with no "oq" (older files) is "o" as before.


## the body's box (mm) from its kernel edges; AABB() when it has none
static func body_box_mm(body: int) -> AABB:
	var bb := Part._bbox(KCad.edges(body))
	return AABB(bb.position / Part.MM, bb.size / Part.MM)


## stores "oq" on hinge `hinge_id` from its current "o" (mm), relative to the hinged body's box as it is just before the hinge. "" or the words of why not
static func pin_hinge(rec: Dictionary, hinge_id: String) -> String:
	var i := Part.index_of(rec, hinge_id)
	if i < 0 or String(rec["features"][i]["t"]) != "hinge":
		return "there is no hinge %s" % hinge_id
	var f: Dictionary = rec["features"][i]
	var ids: Array = Part.replay(rec, i - 1, {"keep": true}).get("ids", [])
	var bi := int(f.get("body", -1))
	var why := ""
	if bi < 0 or bi >= ids.size():
		why = "step %d (%s): there is no body %d to hinge" % [i + 1, String(f.get("name", hinge_id)), bi]
	else:
		var bb := body_box_mm(int(ids[bi]))
		var o := Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2]))
		var q := Vector3(_n(o.x, bb.position.x, bb.size.x), _n(o.y, bb.position.y, bb.size.y), _n(o.z, bb.position.z, bb.size.z))
		f["oq"] = [q.x, q.y, q.z]
	Part.release_kept(ids)
	return why


static func _n(v: float, lo: float, size: float) -> float:
	return 0.5 if size < 1e-6 else (v - lo) / size


## replay calls this for every hinge: no "oq" yet, or "o" was edited since it was pinned ("oq_o" is the "o" it was made from) -> pin now.
## Every way of making or editing a hinge (Expert dialog, Easy swing / hinge-by-click, hinge words, agent feature / insert_step / edit_step) ends in a replay.
static func auto_pin(f: Dictionary, body: int) -> void:
	if f.get("oq") is Array and f.get("oq_o") == f.get("o"):
		return
	var bb := body_box_mm(body)
	if bb.size == Vector3.ZERO or not (f.get("o") is Array):
		return
	var o := Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2]))
	f["oq"] = [_n(o.x, bb.position.x, bb.size.x), _n(o.y, bb.position.y, bb.size.y), _n(o.z, bb.position.z, bb.size.z)]
	f["oq_o"] = (f["o"] as Array).duplicate()


## the hinge's pivot in mm for the body (a kept kernel id) it turns: "oq" inside the body's box now, else the stored "o"
static func pivot_mm(f: Dictionary, body: int) -> Vector3:
	if f.get("oq") is Array and (f["oq"] as Array).size() >= 3 and f.get("oq_o") == f.get("o"):
		var bb := body_box_mm(body)
		if bb.size != Vector3.ZERO:
			var q: Array = f["oq"]
			return bb.position + Vector3(float(q[0]), float(q[1]), float(q[2])) * bb.size
	return Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2]))


## the pivot (mm) of hinge `hinge_id` after a fresh replay, or a Dictionary {"err": words naming the step}
static func hinge_pivot(rec: Dictionary, hinge_id: String) -> Variant:
	var i := Part.index_of(rec, hinge_id)
	if i < 0:
		return {"err": "there is no hinge %s" % hinge_id}
	var f: Dictionary = rec["features"][i]
	var ids: Array = Part.replay(rec, i - 1, {"keep": true}).get("ids", [])
	var bi := int(f.get("body", -1))
	var out: Variant
	if bi < 0 or bi >= ids.size():
		out = {"err": "step %d (%s): there is no body %d to hinge: an earlier step changed the bodies" % [i + 1, String(f.get("name", hinge_id)), bi]}
	else:
		out = pivot_mm(f, int(ids[bi]))
	Part.release_kept(ids)
	return out


## the pivot of hinge f (metres) as the current record puts it: "oq" inside its body's box after a replay up to the hinge
static func pivot_for_rec(rec: Dictionary, f: Dictionary) -> Vector3:
	var r = hinge_pivot(rec, String(f.get("id", "")))
	if r is Vector3:
		return (r as Vector3) * Part.MM
	return Part._pivot(f)


## W03b FILLET EDGE BY FACE PAIR. An edge descriptor also stores "fp": the two faces it joins, each {"n": outward normal, "c": centre as 0..1 of the body box}.
## Matching: the edges whose two face normals equal the stored two (either order) are the candidates; the best by box position "q", or by the
## stored absolute "p" (a hole rim keeps its place in mm while the box grows), wins. No "fp" (older files), or no candidate -> Part.match_edge as before.
static func face_pair(ef: Array, fnorm: Dictionary, fcen: Dictionary, bb: AABB) -> Array:
	var out := []
	if ef.size() != 2 or not fnorm.has(int(ef[0])) or not fnorm.has(int(ef[1])):
		return out
	for fi in ef:
		var n: Vector3 = fnorm[int(fi)]
		var c: Vector3 = Part._norm(fcen[int(fi)], bb)
		out.append({"n": [n.x, n.y, n.z], "c": [c.x, c.y, c.z]})
	return out


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## index in es of the edge `want` names (see above), or -1
static func pick_edge(body: int, es: Array, bb: AABB, want: Dictionary) -> int:
	var fp: Array = want.get("fp", [])
	if fp.size() == 2 and want.get("q") is Array and not want.get("nofp", false):
		var norm := {}
		for fc in KCad.faces(body):
			norm[int(fc["id"])] = fc["normal"]
		var n0 := _v(fp[0]["n"])
		var n1 := _v(fp[1]["n"])
		var q := _v(want["q"])
		var p := _v(want["p"]) * Part.MM if want.get("p") is Array else Vector3.INF
		var diag := maxf(bb.size.length(), 1e-6)
		var best := -1
		var bs := INF
		for i in es.size():
			var ef: Array = es[i].get("faces", [])
			if ef.size() != 2 or not norm.has(int(ef[0])) or not norm.has(int(ef[1])):
				continue
			var a: Vector3 = norm[int(ef[0])]
			var b: Vector3 = norm[int(ef[1])]
			if not ((a.dot(n0) > 0.98 and b.dot(n1) > 0.98) or (a.dot(n1) > 0.98 and b.dot(n0) > 0.98)):
				continue
			var s: float = Part._norm(es[i]["center"], bb).distance_to(q)
			if p.x != INF:
				s = minf(s, (es[i]["center"] as Vector3).distance_to(p) / diag)
			if s < bs:
				bs = s
				best = i
		if best >= 0:
			return best
	return Part.match_edge(es, bb, want)
