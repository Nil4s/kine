class_name KMeshPickStack
extends RefCounted
## C45 (M #233): click through to a face that is hidden behind another, without deleting anything.
## Alt+click on a face (face mode) walks the faces under the mouse, nearest first, one more each click at the same spot:
## 1st the front face, 2nd the one behind it, ... then round to the front. The plain click is unchanged.

const SAME_SPOT_PX := 3.0

var last_p := Vector2(-1.0e6, -1.0e6)
var last_stack: Array = []
var at := -1


## every face the ray crosses (back faces too), nearest first: [{"face", "t"}]
static func faces_along(view: KMeshView, cam: Camera3D, p: Vector2) -> Array:
	var r := view.ray_at(cam, p)
	var inv := view.global_transform.affine_inverse()
	var o: Vector3 = inv * (r[0] as Vector3)
	var d: Vector3 = inv.basis * (r[1] as Vector3)
	var out := []
	var mesh: KMesh = view.mesh
	for fi in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[fi]
		var best := INF
		for k in range(1, fp.size() - 1):
			var t: Variant = Geometry3D.ray_intersects_triangle(o, d, mesh.verts[fp[0]], mesh.verts[fp[k]], mesh.verts[fp[k + 1]])
			if t != null:
				best = minf(best, ((t as Vector3) - o).length())
		if best < INF:
			out.append({"face": fi, "t": best})
	out.sort_custom(func(a, b): return a["t"] < b["t"])
	return out


## the next face behind at p (the same spot again goes one deeper, wrapping round); {} on a miss
func next(view: KMeshView, cam: Camera3D, p: Vector2) -> Dictionary:
	if p.distance_to(last_p) > SAME_SPOT_PX or last_stack.is_empty():
		last_stack = faces_along(view, cam, p)
		at = -1
	last_p = p
	if last_stack.is_empty():
		return {}
	at = (at + 1) % last_stack.size()
	return {"face": int(last_stack[at]["face"]), "depth": at + 1, "of": last_stack.size()}
