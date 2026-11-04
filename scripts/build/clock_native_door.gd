extends RefCounted
## The only script that names KineClockNative (native/src/kine_clock_native.cpp). ClockCH2 load()s THIS file by path, and only when the class
## exists: with no DLL it is never compiled and the clock runs on the GDScript path alone. No class_name on purpose.


static func pair_overlaps(polys: Array, pose: PackedFloat64Array, pairs: PackedInt32Array) -> PackedFloat64Array:
	return KineClockNative.pair_overlaps(polys, pose, pairs)
