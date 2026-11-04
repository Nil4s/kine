extends RefCounted
## The only script that names KineSolveNative (native/src/kine_solve_native.cpp). KMeshAutoWeights load()s THIS file by path, and
## only when the class exists: with no DLL it is never compiled. No class_name on purpose.


static func version() -> int:
	return KineSolveNative.version()


static func cg(n: int, rp: PackedInt32Array, ci: PackedInt32Array, cv: PackedFloat64Array, dg: PackedFloat64Array, b: PackedFloat64Array, x: PackedFloat64Array, tol: float, max_iter: int) -> Dictionary:
	return KineSolveNative.cg(n, rp, ci, cv, dg, b, x, tol, max_iter)
