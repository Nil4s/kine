extends RefCounted
## The only script that names KineDyntopoNative (native/src/kine_dyntopo_native.cpp). KMeshDyntopo loads it by path only when the class exists.


static func refine(verts: PackedVector3Array, tris: PackedInt32Array, c: Vector3, r: float, lmax: float, passes: int) -> Dictionary:
	return KineDyntopoNative.refine(verts, tris, c, r, lmax, passes)
