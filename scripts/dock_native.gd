extends RefCounted
## The only script that names KineDockNative (native/src/kine_dock_native.cpp). HandsDock and Corrective load() THIS file by path, and only
## when the class exists: with no DLL it is never compiled. No class_name on purpose.


static func version() -> int:
	return KineDockNative.version()


static func first_free(spots: PackedFloat64Array, w: float, h: float, body: Rect2, avoid: bool, pts: PackedVector2Array, pad: float) -> int:
	return KineDockNative.first_free(spots, w, h, body, avoid, pts, pad)


static func push(vs: PackedVector3Array, dv: PackedVector3Array, ai: PackedInt32Array, amp: float) -> PackedVector3Array:
	return KineDockNative.push(vs, dv, ai, amp)
