extends RefCounted
## The only script that names KineAutoRigNative (native/src/kine_autorig_native.cpp). AutoRig load()s THIS file by path, and only when
## the class exists: with no DLL it is never compiled. No class_name on purpose.


static func version() -> int:
	return KineAutoRigNative.version()


static func voxelize(verts: PackedVector3Array, tris: PackedInt32Array, comp: PackedInt32Array, origin: Vector3, vs: float, nx: int, ny: int, nz: int) -> PackedByteArray:
	return KineAutoRigNative.voxelize(verts, tris, comp, origin, vs, nx, ny, nz)


static func edt(mask: PackedByteArray, vs: float, nx: int, ny: int, nz: int) -> PackedFloat32Array:
	return KineAutoRigNative.edt(mask, vs, nx, ny, nz)


static func bind(mask: PackedByteArray, vs: float, nx: int, ny: int, nz: int, origin: Vector3, sa: PackedVector3Array, sb: PackedVector3Array, sbone: PackedInt32Array, nb: int, r: float, smooth: int) -> Dictionary:
	return KineAutoRigNative.bind(mask, vs, nx, ny, nz, origin, sa, sb, sbone, nb, r, smooth)
