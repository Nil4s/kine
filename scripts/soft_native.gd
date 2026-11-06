extends RefCounted
## The only script that names KineSoftNative (native/src/kine_soft_native.cpp). SoftBody load()s THIS file by path, and only when
## ClassDB.class_exists("KineSoftNative"): with no DLL it is never compiled. Arithmetic mirrors SoftBody._dev_gd / _cell_gd (tests/soft_test.gd bar 5).


static func version() -> int:
	return KineSoftNative.version()


static func run(x: PackedFloat64Array, v: PackedFloat64Array, w: PackedFloat64Array, tets: PackedInt32Array, dm: PackedFloat64Array,
		v0: PackedFloat64Array, pin_idx: PackedInt32Array, pin_to: PackedFloat64Array, fext: PackedFloat64Array, vref: PackedFloat64Array, nsub: int, iters: int,
		dt: float, mu: float, lam: float, gamma: float, gx: float, gy: float, gz: float, damp: float) -> Array:
	return KineSoftNative.run(x, v, w, tets, dm, v0, pin_idx, pin_to, fext, vref, nsub, iters, dt, mu, lam, gamma, gx, gy, gz, damp)
