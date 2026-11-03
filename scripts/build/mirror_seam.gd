## MIRROR SEAM (C47, complaint #251: "the mirrored half does not join smoothly (no G1 continuity)"): the angle of the kink at a mirror seam.
## A surface that meets the mirror plane with its normal N off the plane makes a ridge of 2 * asin(|N . n|) degrees when its
## reflection joins it (0 = G1: the surface runs through the plane smoothly). Measured on the vertices of the body's own skin that
## lie ON the plane; a flat face lying in the plane (|N . n| > FLAT) is the cut face that vanishes in the join and is left out.
## Opt-in: a mirror step with "seam": true (threshold "seam_deg", default SEAM_DEG) gets the angle in its warning. The mirror itself is unchanged.
class_name MirrorSeam
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const SEAM_DEG := 5.0    # a kink above this is said
const ON_PLANE := 1e-4   # metres: a vertex this close to the plane is on the seam
const FLAT := 0.99       # |N . n| above this: the face lies in the plane


## the worst kink in degrees over a skin's seam vertices (-1 when none lie on the plane)
static func kink_of(mesh: ArrayMesh, origin: Vector3, n: Vector3) -> float:
	if mesh == null:
		return -1.0
	var nn := n.normalized()
	var worst := -1.0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		if ns.size() != vs.size():
			continue
		for i in vs.size():
			if absf((vs[i] - origin).dot(nn)) > ON_PLANE:
				continue
			var c := absf(ns[i].normalized().dot(nn))
			if c > FLAT:
				continue
			worst = maxf(worst, rad_to_deg(2.0 * asin(minf(c, 1.0))))
	return worst


## the warning words for the body about to be mirrored ("" = G1 or not asked)
static func warn(body: int, origin: Vector3, n: Vector3, thr := SEAM_DEG) -> String:
	var k := kink_of(KCad.tessellate(body, 0.002, 0.2), origin, n)
	if k <= thr:
		return ""
	return TranslationServer.translate("the mirrored halves meet at a ridge of %d degrees (over %d): the surface does not run smoothly through the mirror plane") % [roundi(k), roundi(thr)]
