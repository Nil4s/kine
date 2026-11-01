extends RefCounted
## The only script that names KineMeshCheckNative (native/, a GDExtension DLL). MeshCheckDoor load()s THIS file by path, and only when
## the class exists: with no DLL this file is never compiled and the app runs on the GDScript path alone. No class_name on purpose.
## Arithmetic mirrors PrintCheck / MeshExport / PartStand (native/src/kine_meshcheck_native.cpp); tests/n02_test.gd holds the two together.


static func scan(bodies: Array) -> Dictionary:
	return KineMeshCheckNative.scan(bodies)


static func edge_check(t: PackedInt32Array) -> Dictionary:
	return KineMeshCheckNative.edge_check(t)


static func signed_volume(v: PackedVector3Array, t: PackedInt32Array) -> float:
	return KineMeshCheckNative.signed_volume(v, t)


static func bounds(v: PackedVector3Array) -> PackedVector3Array:
	return KineMeshCheckNative.bounds(v)


static func feet_hull(verts: PackedVector3Array, foot: float) -> PackedVector2Array:
	return KineMeshCheckNative.feet_hull(verts, foot)
