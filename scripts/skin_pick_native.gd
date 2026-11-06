extends RefCounted
## The only script that names KineSkinNative's pick helpers (native/src/kine_skin_native.cpp). SkinPick load()s THIS file by
## path, and only when the class and the methods exist: with no DLL (or an older one) it is never compiled. No class_name on purpose.


static func skin_points(rest: PackedVector3Array, bo: PackedInt32Array, w: PackedFloat32Array, per: int, mats: PackedVector3Array) -> PackedVector3Array:
	return KineSkinNative.skin_points(rest, bo, w, per, mats)


static func points_aabb(pos: PackedVector3Array, vix: PackedInt32Array) -> AABB:
	return KineSkinNative.points_aabb(pos, vix)
