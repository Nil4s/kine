extends RefCounted
## The only script that names KineSeatNative (native/src/kine_seat_native.cpp). PartFast load()s THIS file by path, and only when the class exists.
## No class_name on purpose: with no DLL this file is never compiled and the seat runs on the GDScript grid alone.


static func surface_under(hosts: Array, pts: PackedVector3Array, top_y: float, low_y: float) -> PackedFloat64Array:
	return KineSeatNative.surface_under(hosts, pts, top_y, low_y)
