extends RefCounted
## s124 GEARS DRIVE EACH OTHER (Friday plan 124): the numbers behind Easy Part's "Turn it" on a Gear pair. Pure functions, no scene.
## Meshed gears turn in opposite directions and the speeds run in the ratio of the teeth: the driven gear turns -N1 / N2 times the driver's angle.
## The signed gap measures the TWO MESHES (a ring of boundary segments read from a built triangle soup): positive = the clearance between the
## teeth, negative = how far one gear's outline sits inside the other.


## the angle (degrees) the driven gear (n_out teeth) turns when the driver (n_in teeth) turns a_in degrees
static func out_angle(a_in: float, n_in: int, n_out: int) -> float:
	return -a_in * float(n_in) / float(n_out)


## a chain of gears side by side (teeth list, the first is turned a0 degrees): every gear's angle. Each neighbour turns -N_prev / N_next times
static func chain_angles(teeth: Array, a0: float) -> Array:
	var out: Array = []
	if teeth.is_empty():
		return out
	out.append(a0)
	for i in range(1, teeth.size()):
		out.append(out_angle(float(out[i - 1]), int(teeth[i - 1]), int(teeth[i])))
	return out


## the Gear pair of a record: {"n1", "n2", "md", "d"} (teeth of both, module, centre distance in mm), or {} when the record is not a Gear pair
static func pair_of(rec: Dictionary) -> Dictionary:
	var e: Dictionary = rec.get("easy", {})
	if String(e.get("t", "")) != "gearpair":
		return {}
	var p: Dictionary = e.get("p", {})
	if int(roundf(float(p.get("mode", 0.0)))) == 1:   # c52: Rack and pinion has no big gear to turn
		return {}
	if not (p.has("teeth") and p.has("ratio") and p.has("module")):
		return {}
	var n1 := int(roundf(float(p["teeth"])))
	var n2 := int(roundf(float(p["teeth"]) * float(p["ratio"])))
	var md := float(int(roundf(float(p["module"]))))
	return {"n1": n1, "n2": n2, "md": md, "d": md * float(n1 + n2) * 0.5}


## the outline of a triangle soup (metres) in mm: the segments of the lowest-z face that belong to one triangle only. Array of [Vector2, Vector2]
static func outline_of(tris: PackedVector3Array) -> Array:
	var zmin := INF
	for v in tris:
		zmin = minf(zmin, v.z)
	var count := {}
	var seg := {}
	for i in range(0, tris.size(), 3):
		var t := [tris[i], tris[i + 1], tris[i + 2]]
		if absf(t[0].z - zmin) > 1e-6 or absf(t[1].z - zmin) > 1e-6 or absf(t[2].z - zmin) > 1e-6:
			continue
		for k in 3:
			var a: Vector3 = t[k]
			var b: Vector3 = t[(k + 1) % 3]
			var ka := Vector2i(roundi(a.x * 1e5), roundi(a.y * 1e5))
			var kb := Vector2i(roundi(b.x * 1e5), roundi(b.y * 1e5))
			var key := [ka, kb] if (ka.x < kb.x or (ka.x == kb.x and ka.y < kb.y)) else [kb, ka]
			var ks := str(key)
			count[ks] = int(count.get(ks, 0)) + 1
			seg[ks] = [Vector2(a.x, a.y) * 1000.0, Vector2(b.x, b.y) * 1000.0]
	var out: Array = []
	for ks in count:
		if int(count[ks]) == 1:
			out.append(seg[ks])
	return out


static func _inside(p: Vector2, segs: Array) -> bool:
	var inside := false
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if (a.y > p.y) != (b.y > p.y):
			var x := a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if x > p.x:
				inside = not inside
	return inside


static func _dist(p: Vector2, segs: Array) -> float:
	var best := INF
	for s in segs:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])))
	return best


## the signed gap (mm) between two outlines: points every `step` mm along each boundary; the smallest distance to the other outline, negative
## for a point that sits inside the other gear's material (then the deepest one). The centre holes are in the outlines (even-odd inside).
static func signed_gap(a: Array, b: Array, step := 0.25) -> float:
	var best := INF
	for pair in [[a, b], [b, a]]:
		var from: Array = pair[0]
		var to: Array = pair[1]
		for s in from:
			var p0: Vector2 = s[0]
			var p1: Vector2 = s[1]
			var n := maxi(1, ceili(p0.distance_to(p1) / step))
			for i in n + 1:
				var p := p0.lerp(p1, float(i) / float(n))
				var d := _dist(p, to)
				best = minf(best, -d if _inside(p, to) else d)
	return best
