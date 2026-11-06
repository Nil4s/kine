extends RefCounted
## The only script that names KineSplineNative (native/src/kine_spline_native.cpp). SplineChain load()s THIS file by path, and only when
## NativeExt.ensure("kine_native", "KineSplineNative") says the class exists: with no DLL it is never compiled. Same arithmetic as
## SplineChain._core_gd (tests/splineik_test.gd bar 7).


static func solve(root: PackedFloat64Array, lens: PackedFloat64Array, ctrl: PackedFloat64Array, kind: int, mode: int, tw0: float, tw1: float,
		rest_y: PackedFloat64Array, rest_x: PackedFloat64Array, volume: bool) -> Dictionary:
	return KineSplineNative.solve(root, lens, ctrl, kind, mode, tw0, tw1, rest_y, rest_x, volume)
