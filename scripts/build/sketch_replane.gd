## MOVE A SKETCH TO ANOTHER PLANE, WITH A PREVIEW (C15, complaint #206: "moving a sketch to another plane shifts it unexpectedly").
## Engine only. The sketch keeps its plane coordinates (mm); only its plane changes. preview() answers where the outline WOULD land (world corners and
## the shift in mm, in plain words) WITHOUT touching the record; apply() makes the change. A plane that is the sketch's own, or comes later in the timeline, is not offered.
class_name SketchReplane
extends RefCounted


static func ent_points(e: Dictionary) -> Array:
	var pts := []
	match String(e.get("k", "")):
		"circle":
			var c := Part.v2(e["c"])
			var r := float(e["r"])
			pts = [c + Vector2(r, r), c - Vector2(r, r)]
		"rect":
			pts = [Part.v2(e["a"]), Part.v2(e["b"])]
		"bspline":
			for p in e.get("pts", []):
				pts.append(Part.v2(p))
		_:
			for key in ["a", "m", "b", "c"]:
				if e.has(key) and e[key] is Array and (e[key] as Array).size() >= 2:
					pts.append(Part.v2(e[key]))
	return pts


## the sketch's box in its plane coordinates: Rect2 (mm); size zero and has_ents false when empty
static func box2(sk: Dictionary) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var n := 0
	for e in sk.get("ents", []):
		for p in ent_points(e):
			lo = lo.min(p)
			hi = hi.max(p)
			n += 1
	if n == 0:
		return {"has": false, "rect": Rect2()}
	return {"has": true, "rect": Rect2(lo, hi - lo)}


## planes the sketch may move to: [{"name": id or base name, "words": "Top plane"}]
static func targets(rec: Dictionary, sk_id: String) -> Array:
	var out := []
	for pn in Part.PLANES:
		out.append({"name": pn, "words": Part.plane_words(rec, pn)})
	var si := Part.index_of(rec, sk_id)
	for i in (rec["features"] as Array).size():
		var f: Dictionary = rec["features"][i]
		if String(f.get("t", "")) == "plane" and i < si:
			out.append({"name": String(f["id"]), "words": Part.plane_words(rec, String(f["id"]))})
	return out


static func _world_corners(pl: Dictionary, r: Rect2) -> Array:
	return [Part.to_world(pl, r.position), Part.to_world(pl, Vector2(r.end.x, r.position.y)), Part.to_world(pl, r.end), Part.to_world(pl, Vector2(r.position.x, r.end.y))]


## {"ok", "why", "from": plane words, "to": plane words, "corners_from", "corners_to": [Vector3 m], "centre_from", "centre_to": Vector3 (mm), "shift_mm": Vector3, "words"}
static func preview(rec: Dictionary, sk_id: String, plane_name: String) -> Dictionary:
	var f := Part.feature(rec, sk_id)
	var out := {"ok": false, "why": "", "words": ""}
	if String(f.get("t", "")) != "sketch":
		out["why"] = "That is not a sketch."
		return out
	var ok_target := false
	for t in targets(rec, sk_id):
		if String(t["name"]) == plane_name:
			ok_target = true
	if not ok_target:
		out["why"] = "A sketch can only go on Front, Top, Right or a plane made before it."
		return out
	var b := box2(f)
	var rect: Rect2 = b["rect"]
	var pf := Part.resolve_plane(rec, String(f.get("plane", "front")))
	var pt := Part.resolve_plane(rec, plane_name)
	var cf := _world_corners(pf, rect)
	var ct := _world_corners(pt, rect)
	var c2 := rect.get_center()
	var wf := Part.to_world(pf, c2) / Part.MM
	var wt := Part.to_world(pt, c2) / Part.MM
	var sh := wt - wf
	out["ok"] = true
	out["from"] = Part.plane_words(rec, String(f.get("plane", "front")))
	out["to"] = Part.plane_words(rec, plane_name)
	out["corners_from"] = cf
	out["corners_to"] = ct
	out["centre_from"] = wf
	out["centre_to"] = wt
	out["shift_mm"] = sh
	out["has_ents"] = bool(b["has"])
	if plane_name == String(f.get("plane", "front")):
		out["words"] = "Already on the %s: nothing moves." % out["to"]
	else:
		out["words"] = "%s to %s: the centre goes from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f) mm, a move of (%.1f, %.1f, %.1f) mm. Its own numbers stay." % [
			out["from"], out["to"], wf.x, wf.y, wf.z, wt.x, wt.y, wt.z, sh.x, sh.y, sh.z]
	return out


## makes the move (the caller takes the undo step first); answers true when the plane changed
static func apply(rec: Dictionary, sk_id: String, plane_name: String) -> bool:
	var pv := preview(rec, sk_id, plane_name)
	if not bool(pv["ok"]):
		return false
	var f := Part.feature(rec, sk_id)
	if String(f.get("plane", "")) == plane_name:
		return false
	f["plane"] = plane_name
	return true
