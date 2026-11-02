class_name LumpTouch
extends RefCounted
## W10b: do two shells meet on a face patch? True when at least three NON-COLLINEAR points of pts lie on triangles of tri_pts
## (flat, three per triangle) inside bb. One point (a corner) or points all on one line (an edge touch) are not a face contact.

static func patch(pts: PackedVector3Array, tri_pts: PackedVector3Array, bb: AABB) -> bool:
	var gbb := bb.grow(1e-4)
	var hit := PackedVector3Array()
	for p in pts:
		if not gbb.has_point(p):
			continue
		if _on_tri(p, tri_pts):
			hit.append(p)
	if hit.size() < 3:
		return false
	var p0: Vector3 = hit[0]
	var d1 := Vector3.ZERO
	for q in hit:
		if (q - p0).length() > 1e-5:
			d1 = (q - p0)
			break
	if d1 == Vector3.ZERO:
		return false
	for q in hit:
		if (q - p0).cross(d1).length() > 1e-9:
			return true
	return false


static func _on_tri(p: Vector3, tri_pts: PackedVector3Array) -> bool:
	for t in range(0, tri_pts.size() - 2, 3):
		var a: Vector3 = tri_pts[t]
		var b: Vector3 = tri_pts[t + 1]
		var c: Vector3 = tri_pts[t + 2]
		var nrm := (b - a).cross(c - a)
		var ln := nrm.length()
		if ln < 1e-12:
			continue
		nrm /= ln
		if absf((p - a).dot(nrm)) > 2e-5:
			continue
		if (b - a).cross(p - a).dot(nrm) >= -1e-9 and (c - b).cross(p - b).dot(nrm) >= -1e-9 and (a - c).cross(p - c).dot(nrm) >= -1e-9:
			return true
	return false
