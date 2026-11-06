extends RefCounted
## The only script that names KineRenderNative (native/src/kine_render_native.cpp). FinalHQ load()s THIS file by path, and only when
## the class exists: with no DLL it is never compiled. No class_name on purpose. tests/render2_test.gd holds it to the GDScript twins.


static func accumulate(datas: Array) -> PackedFloat32Array:
	return KineRenderNative.accumulate(datas)


static func denoise(rgb: PackedFloat32Array, guide: PackedFloat32Array, w: int, h: int, iters: int, sc: float, sg: float) -> PackedFloat32Array:
	return KineRenderNative.denoise(rgb, guide, w, h, iters, sc, sg)
