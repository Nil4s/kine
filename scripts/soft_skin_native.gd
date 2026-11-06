extends RefCounted
## The only script that names KineSoftSkinNative (native/src/kine_softskin_native.cpp). SoftLive load()s THIS file by path, and only when
## ClassDB.class_exists("KineSoftSkinNative"): with no DLL it is never compiled (the GDScript path of soft_live.gd draws instead).


static func topo(idx: PackedInt32Array, nv: int, cand: PackedInt32Array) -> Dictionary:
	return KineSoftSkinNative.topo(idx, nv, cand)


static func encode_nt(nrm: PackedVector3Array, tan: PackedFloat32Array) -> PackedByteArray:
	return KineSoftSkinNative.encode_nt(nrm, tan)


static func deform(verts: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, cand: PackedInt32Array, mats: Array,
		gt: Transform3D, regs: PackedFloat64Array, disps: PackedVector3Array, strength: float, idx: PackedInt32Array, nrm: PackedVector3Array,
		tan: PackedFloat32Array, nt0: PackedByteArray, v1: PackedInt32Array, t2: PackedInt32Array, do_nrm: bool) -> Dictionary:
	return KineSoftSkinNative.deform(verts, bones, weights, per, cand, mats, gt, regs, disps, strength, idx, nrm, tan, nt0, v1, t2, do_nrm)
