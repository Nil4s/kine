extends RefCounted
## KineCAD calls newer than the first DLL (solid_from_mesh = version 4, offset = version 5). They live in their own script because naming a
## method the loaded DLL lacks is a PARSE error: in kcad_native.gd it would stop the whole kernel loading on an older DLL.
## scripts/kcad.gd loads this file only after ClassDB.class_has_method says the DLL has the call.


static func solid_from_mesh(verts: PackedVector3Array, tris: PackedInt32Array, tol: float) -> int:
	return KineCAD.solid_from_mesh(verts, tris, tol)


static func offset(id: int, distance_m: float) -> int:
	return KineCAD.offset(id, distance_m)


static func union_many(base: int, tools: PackedInt32Array) -> int:   # C70
	return KineCAD.union_many(base, tools)


static func overlap_volume(a: int, b: int) -> float:   # C70
	return KineCAD.overlap_volume(a, b)
