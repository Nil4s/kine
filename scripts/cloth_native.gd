extends RefCounted
## The only script that names KineClothNative (native/, a GDExtension DLL). Cloth load()s THIS file by path, and only when
## ClassDB.class_exists("KineClothNative"): with no DLL it is never compiled. Arithmetic mirrors Cloth._substep
## (native/src/kine_cloth_native.cpp); tests/n04_test.gd holds the two together.


static func version() -> int:
	return KineClothNative.version()


static func run(x: PackedVector3Array, v: PackedVector3Array, A: Array, C: Array, rads: PackedFloat64Array, E: PackedInt32Array,
		rest: PackedFloat64Array, pinned: PackedByteArray, nsub: int, pre: int, m_from: int, m_to: int, dt: float, iter: int,
		grav: float, drag: float, margin: float, cand_pad: float) -> Array:
	return KineClothNative.run(x, v, A, C, rads, E, rest, pinned, nsub, pre, m_from, m_to, dt, iter, grav, drag, margin, cand_pad)
