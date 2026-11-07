extends RefCounted
## The only script that names KineWrinkleNative (native/src/kine_wrinkle_native.cpp). FaceWrinkle load()s THIS file by path, and only when
## the class exists: with no DLL it is never compiled and the wrinkles run on the GDScript path alone. No class_name on purpose.


static func blend(rest: PackedVector3Array, deltas: Array, weights: PackedFloat32Array) -> PackedVector3Array:
	return KineWrinkleNative.blend(rest, deltas, weights)


static func prep(rest: PackedVector3Array, nrm: PackedVector3Array, tris: PackedInt32Array, zt: PackedByteArray) -> Dictionary:
	return KineWrinkleNative.prep(rest, nrm, tris, zt)


static func wrinkle(pr: Dictionary, posed_v: PackedVector3Array, purse: PackedVector3Array, zt: PackedByteArray, zw: PackedFloat32Array, par: PackedFloat64Array) -> Dictionary:
	return KineWrinkleNative.wrinkle(pr, posed_v, purse, zt, zw, par)
