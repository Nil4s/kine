extends RefCounted
## The only script that names KineFastenerNative (native/src/kine_fastener_native.cpp). Ch1eFast load()s it by path only when the class exists.


static func contacts(boxes: PackedFloat64Array, mask: PackedInt32Array, tol: float, minov: float) -> PackedInt32Array:
	return KineFastenerNative.contacts(boxes, mask, tol, minov)


static func first_hits(boxes: PackedFloat64Array, off: PackedInt32Array, pts: PackedFloat64Array, mask: PackedInt32Array, q: PackedFloat64Array, tol: float) -> PackedInt32Array:
	return KineFastenerNative.first_hits(boxes, off, pts, mask, q, tol)


static func validate(boxes: PackedFloat64Array, off: PackedInt32Array, pts: PackedFloat64Array, cover: PackedInt32Array, heads: PackedFloat64Array, dirs: PackedFloat64Array, lens: PackedFloat64Array, a: PackedInt32Array, b: PackedInt32Array) -> PackedFloat64Array:
	return KineFastenerNative.validate(boxes, off, pts, cover, heads, dirs, lens, a, b)
