#pragma once
// KineAutoRigNative: L29 AUTORIG. The heavy passes of scripts/autorig.gd: voxelizing a mesh (per-component scanline parity + the
// voxels its triangles touch), a chamfer distance to the outside, and geodesic voxel binding (Dionne & de Lasa 2013, written from
// the paper): per bone a shortest-path distance through the voxels, weights from the distance excess over the nearest bone,
// then a few diffusion passes. Same loops and order as the GDScript fallback in scripts/autorig.gd, double arithmetic.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class KineAutoRigNative : public Object {
	GDCLASS(KineAutoRigNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// byte per voxel (x + nx*(y + ny*z)): bit 1 = inside by parity (any component), bit 2 = touched by a triangle
	static PackedByteArray voxelize(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris, const PackedInt32Array &p_comp,
			const Vector3 &p_origin, double p_vs, int p_nx, int p_ny, int p_nz);
	// distance (m) from every nonzero voxel to the nearest zero voxel, two-pass 3-D chamfer (vs, vs*sqrt2, vs*sqrt3)
	static PackedFloat32Array edt(const PackedByteArray &p_mask, double p_vs, int p_nx, int p_ny, int p_nz);
	// -> {"n": inside voxel count, "w": PackedFloat32Array n * nb (voxels in index order)}
	static Dictionary bind(const PackedByteArray &p_mask, double p_vs, int p_nx, int p_ny, int p_nz, const Vector3 &p_origin,
			const PackedVector3Array &p_sa, const PackedVector3Array &p_sb, const PackedInt32Array &p_sbone, int p_nb, double p_r, int p_smooth);
};

} // namespace godot
