extends RefCounted
## The only script that names KineIKNative (native/src/kine_ik_native.cpp). Body loads it by path only when the class exists.


static func plant_leg(stat: PackedFloat32Array, dyn: PackedFloat32Array, ball_at: Vector3, head: float, flat: bool, knee: float) -> PackedFloat32Array:
	return KineIKNative.plant_leg(stat, dyn, ball_at, head, flat, knee)


static func math_probe(kind: int, xs: PackedFloat64Array) -> PackedFloat64Array:
	return KineIKNative.math_probe(kind, xs)
