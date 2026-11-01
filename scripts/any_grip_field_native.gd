extends RefCounted
## The only script that names KineFieldNative (native/src/kine_field_native.cpp, a GDExtension DLL). AnyGrip.MeshField
## load()s THIS file by path, and only when ClassDB.class_exists("KineFieldNative"): with no DLL it is never compiled.
## No class_name on purpose. tests/n05_test.gd holds it to the GDScript field.

static func version() -> int:
	return KineFieldNative.version()


static func banded(tris: PackedVector3Array, gmin: Vector3, nx: int, ny: int, nz: int, cell: float, flip: float, band: float, on_surface: float) -> PackedFloat32Array:
	return KineFieldNative.banded(tris, gmin, nx, ny, nz, cell, flip, band, on_surface)
