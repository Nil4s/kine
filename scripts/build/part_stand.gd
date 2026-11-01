## part_stand.gd - P127 "DOES IT FALL OVER?" (Friday plan item 127: springs and gravity, light physics; Kine's own idea).
## No simulation: a built Part stands on its FEET (the mesh vertices within 0.5 mm of its lowest height) when its MIDDLE (the
## volume-weighted centre of its solid, the same centre the weight uses) lies over those feet, inside their convex hull.
## MARGIN = how far the middle sits inside the feet's edge (mm, positive); negative = how far it sits past them, and gravity
## tips it that way. The words name the side in plain words, from the default view (+X right, +Z front).
## Read-only: a press changes no step and makes no undo step.
class_name PartStand
extends RefCounted

const FOOT := 0.0005   # m: a vertex this close to the lowest height is a foot (0.5 mm)


## {"ok": bool, "margin_mm": float, "say": String}. A Part with no solid returns ok false and the next step in its words.
static func check(rec: Dictionary) -> Dictionary:
	if not Part.available():
		return {"ok": false, "margin_mm": 0.0, "say": Part.why_not()}
	var res := Part.replay_memo(rec, {"props": true, "inc": true})   # s168: from the cached steps
	var mesh: ArrayMesh = res["mesh"]
	var props: Array = res["props"]
	if mesh == null or props.is_empty() or float(res["volume"]) <= 0.0:
		return {"ok": false, "margin_mm": 0.0, "say": "No solid yet: Pull it up or Spin it round first, then press this"}
	var c := Vector3.ZERO
	var vsum := 0.0
	for p in props:
		c += (p["center"] as Vector3) * float(p["volume"])
		vsum += float(p["volume"])
	c /= vsum
	var verts := PackedVector3Array()
	for s in mesh.get_surface_count():
		verts.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	var hull := _feet_hull(verts)
	var mid := Vector2(c.x, c.z)
	var margin := _margin(mid, hull)   # metres: + inside the feet, - past them
	var mm := margin * 1000.0
	var near := _nearest(mid, hull)
	var side := (mid - near)   # the way gravity tips it: from the feet toward the middle
	var dir := ""
	if absf(side.x) >= absf(side.y):
		dir = "right" if side.x > 0.0 else "left"
	else:
		dir = "front" if side.y > 0.0 else "back"
	if margin >= 0.0:
		return {"ok": true, "margin_mm": mm, "say": "Yes, it stands. Its middle is %d mm inside its feet, so gravity keeps it up" % roundi(mm)}
	return {"ok": false, "margin_mm": mm, "say": "No, it falls over toward the %s. Its middle is %d mm past its feet. Widen the foot on the %s side, or move the weight in" % [dir, roundi(-mm), dir]}


## the convex hull of the feet of a vertex list (the vertices within FOOT of the lowest height, seen from above).
## KineMeshCheckNative.feet_hull when the DLL is there, else the GDScript lines.
static func _feet_hull(verts: PackedVector3Array) -> Array:
	var d = MeshCheckDoor.door()
	if d != null:
		return Array(d.feet_hull(verts, FOOT))
	var lo := INF
	for v in verts:
		lo = minf(lo, v.y)
	var feet := PackedVector2Array()
	for v in verts:
		if v.y <= lo + FOOT:
			feet.append(Vector2(v.x, v.z))
	return _hull(feet)


## the convex hull of the feet (monotone chain), counter-clockwise. One or two points stay as they are (a line or a point)
static func _hull(pts: PackedVector2Array) -> Array:
	var p := Array(pts)
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var uniq := []
	for q in p:
		if uniq.is_empty() or not (uniq[-1] as Vector2).is_equal_approx(q):
			uniq.append(q)
	if uniq.size() < 3:
		return uniq
	var lower := []
	for q in uniq:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], q) <= 0.0:
			lower.pop_back()
		lower.append(q)
	var upper := []
	for i in range(uniq.size() - 1, -1, -1):
		var q: Vector2 = uniq[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], q) <= 0.0:
			upper.pop_back()
		upper.append(q)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).cross(b - o)


## + distance inside the hull's nearest edge, - distance to the hull when outside (a segment or a point: always outside)
static func _margin(p: Vector2, h: Array) -> float:
	if h.size() < 3:
		return -_seg_dist_min(p, h)
	var inside := true
	var edge_min := INF
	for i in h.size():
		var a: Vector2 = h[i]
		var b: Vector2 = h[(i + 1) % h.size()]
		if _cross(a, b, p) < 0.0:
			inside = false
		edge_min = minf(edge_min, _seg_dist(p, a, b))
	return edge_min if inside else -_seg_dist_min(p, h)


## the hull's point nearest to p (the edge it tips over)
static func _nearest(p: Vector2, h: Array) -> Vector2:
	if h.is_empty():
		return p
	if h.size() == 1:
		return h[0]
	var best: Vector2 = h[0]
	var best_d := INF
	for i in h.size():
		var a: Vector2 = h[i]
		var b: Vector2 = h[(i + 1) % h.size()] if h.size() >= 3 or i == 0 else a
		var q := _seg_point(p, a, b)
		var d := p.distance_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


static func _seg_point(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0:
		return a
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(_seg_point(p, a, b))


static func _seg_dist_min(p: Vector2, h: Array) -> float:
	if h.is_empty():
		return INF
	if h.size() == 1:
		return p.distance_to(h[0])
	var d := INF
	for i in h.size():
		var a: Vector2 = h[i]
		var b: Vector2 = h[(i + 1) % h.size()] if h.size() >= 3 or i == 0 else a
		d = minf(d, _seg_dist(p, a, b))
	return d
