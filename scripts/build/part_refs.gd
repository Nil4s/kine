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


## the hinge's pivot in mm for the body (a kept kernel id) it turns: "oq" inside the body's box now, else the stored "o"
static func pivot_mm(f: Dictionary, body: int) -> Vector3:
	if f.get("oq") is Array and (f["oq"] as Array).size() >= 3:
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
