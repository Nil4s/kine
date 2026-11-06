extends RefCounted
## The only script that names KinePropsNative (native/src/kine_props_native.cpp). Props.settle load()s THIS file by path, and only
## when the class exists. No class_name on purpose.


static func settle(xf: PackedFloat64Array, start: PackedInt32Array, sup: PackedFloat64Array, skp: PackedByteArray) -> PackedFloat64Array:
	return KinePropsNative.settle(xf, start, sup, skp)
