extends RefCounted
## The only script that names KineMeshOpsNative (native/src/kine_meshops_native.cpp, a GDExtension DLL). MeshOpsDoor load()s THIS
## file by path, and only when the class exists: with no DLL it is never compiled, so the app runs on the GDScript path alone.
## No class_name on purpose (a global class would be compiled at project scan).


static func version() -> int:
	return KineMeshOpsNative.version()


static func decimate(verts: PackedVector3Array, faces: Array, ccls: PackedInt32Array, twin: PackedInt32Array, nxt: PackedInt32Array, target: int, lock: bool) -> Dictionary:
	return KineMeshOpsNative.decimate(verts, faces, ccls, twin, nxt, target, lock)


static func voxel_remesh(verts: PackedVector3Array, faces: Array, voxel: float) -> Dictionary:
	return KineMeshOpsNative.voxel_remesh(verts, faces, voxel)


static func stl_records(v: PackedVector3Array, t: PackedInt32Array) -> PackedByteArray:
	return KineMeshOpsNative.stl_records(v, t)


static func xml_vertices(v: PackedVector3Array) -> String:
	return KineMeshOpsNative.xml_vertices(v)


static func xml_triangles(t: PackedInt32Array) -> String:
	return KineMeshOpsNative.xml_triangles(t)


static func obj_vertices(v: PackedVector3Array, xf: Transform3D) -> String:
	return KineMeshOpsNative.obj_vertices(v, xf)


static func obj_normals(n: PackedVector3Array, nb: Basis) -> String:
	return KineMeshOpsNative.obj_normals(n, nb)


static func obj_faces(ix: PackedInt32Array, count: int, off_v: int, off_t: int, off_n: int, has_t: bool, has_n: bool) -> String:
	return KineMeshOpsNative.obj_faces(ix, count, off_v, off_t, off_n, has_t, has_n)
