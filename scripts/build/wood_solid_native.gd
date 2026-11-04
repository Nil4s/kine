extends RefCounted
## The only script that names KineWoodNative (native/src/kine_wood_native.cpp). WoodSolid load()s THIS file by path, and only when
## ClassDB.class_exists("KineWoodNative"): with no DLL it is never compiled. No class_name on purpose. tests/ch4_test.gd holds it to the GDScript field.

static func version() -> int:
	return KineWoodNative.version()


static func sample(pts: PackedVector3Array, sp: Dictionary) -> PackedFloat32Array:
	return KineWoodNative.sample(pts, sp["pith"], sp["w"], sp["u"], sp["v"], int(sp["seed"]), float(sp["ring"]), float(sp["ring_var"]),
		float(sp["oval"]), float(sp["oval_ang"]), float(sp["pore_p"]), float(sp["ray_dens"]))
