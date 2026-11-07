extends RefCounted
## The only script that names KineKMeshNative (native/src/kine_kmesh_native.cpp). KMeshNatDoor load()s THIS file by path, and only
## when the class exists: with no DLL it is never compiled. No class_name on purpose.


static func version() -> int:
	return KineKMeshNative.version()


static func topology(verts: PackedVector3Array, faces: Array) -> Dictionary:
	return KineKMeshNative.topology(verts, faces)


static func from_tris(pos: PackedVector3Array, idx: PackedInt32Array, tol: float) -> Dictionary:
	return KineKMeshNative.from_tris(pos, idx, tol)


static func edge_map(nv: int, he_vert: PackedInt32Array, he_next: PackedInt32Array) -> Dictionary:
	return KineKMeshNative.edge_map(nv, he_vert, he_next)


static func subdivide(verts: PackedVector3Array, faces: Array, levels: int, crease: float) -> Dictionary:
	return KineKMeshNative.subdivide(verts, faces, levels, crease)


static func boolean(va: PackedVector3Array, fa: Array, tac: PackedInt32Array, taf: PackedInt32Array, vb: PackedVector3Array, fb: Array, tbc: PackedInt32Array, tbf: PackedInt32Array, op: int, snap_min: float) -> Dictionary:
	return KineKMeshNative.boolean(va, fa, tac, taf, vb, fb, tbc, tbf, op, snap_min)
