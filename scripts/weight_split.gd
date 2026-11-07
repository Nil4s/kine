## weight_split.gd - WEIGHT SPLIT (N069): a whole-number percent under each foot (60 / 40) from the centre of mass's floor point
## projected onto the line between the two feet's support points (the centroid of each foot's footprint, Balance.footprint).
## One foot on the floor = 100 / 0 on it; no foot down (airborne) = nothing shown. The two always sum to 100.
## This is a lever-rule reading (the weight shared in inverse proportion to the COM's distance to each foot), a simplification of
## a force-plate split: it ignores the feet's own size and the COM's sway off the line between them. Stated, not hidden.
class_name WeightSplit
extends RefCounted


## the percent on the left (x+) and right foot for a COM floor point and the two support points
static func from_points(com: Vector2, l: Vector2, r: Vector2) -> Dictionary:
	var d := r - l
	var t := 0.5
	if d.length_squared() > 1e-10:
		t = clampf((com - l).dot(d) / d.length_squared(), 0.0, 1.0)
	var rp := int(round(100.0 * t))
	return {"l": 100 - rp, "r": rp}


static func centre(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(1.0, float(pts.size()))


## {"shown": bool, "l": int, "r": int, "pl": Vector2, "pr": Vector2 (support points)}
static func read(B: Body) -> Dictionary:
	var fl := Balance.footprint(B, "_l")
	var fr := Balance.footprint(B, "_r")
	var c := Balance.com(B)
	var q := Vector2(c.x, c.z)
	var out := {"shown": false, "l": 0, "r": 0, "pl": Vector2.ZERO, "pr": Vector2.ZERO}
	if fl.is_empty() and fr.is_empty():
		return out
	out["shown"] = true
	if not fl.is_empty():
		out["pl"] = centre(fl)
	if not fr.is_empty():
		out["pr"] = centre(fr)
	if fr.is_empty():
		out["l"] = 100
	elif fl.is_empty():
		out["r"] = 100
	else:
		var s := from_points(q, out["pl"], out["pr"])
		out["l"] = s["l"]
		out["r"] = s["r"]
	return out
