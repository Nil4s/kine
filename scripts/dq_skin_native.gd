extends RefCounted
## The only script that names KineSkinNative (native/src/kine_skin_native.cpp). DqSkin load()s THIS file by path, and only
## when the class exists: with no DLL it is never compiled. No class_name on purpose.


static func version() -> int:
	return KineSkinNative.version()


static func correct(vs: PackedVector3Array, nn: PackedVector3Array, nt: PackedFloat32Array, bo: PackedInt32Array, w: PackedFloat32Array, fr: Dictionary, k: float, multi: PackedInt32Array, msk: PackedFloat32Array) -> Dictionary:
	return KineSkinNative.correct(vs, nn, nt, bo, w, fr, k, multi, msk)
