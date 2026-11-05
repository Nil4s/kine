## parkour_native.gd - the one line that names KineParkourNative (C++, native/src/kine_parkour_native.cpp). Parkour.deepest load()s
## THIS file by path and only when ClassDB.class_exists("KineParkourNative"): with no DLL it is never compiled, so the app runs without it.
extends RefCounted


static func deepest(a: PackedVector3Array, b: PackedVector3Array, r: PackedFloat32Array, base: PackedFloat32Array, c: PackedVector3Array, h: PackedVector3Array) -> Array:
	return KineParkourNative.deepest(a, b, r, base, c, h)
