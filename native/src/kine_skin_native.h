#pragma once
// KineSkinNative: C75. The per-vertex pass of DqSkin.correct_arrays (scripts/dq_skin.gd): the dual-quaternion / linear
// blend pre-correction of rest vertices, normals and tangents. Same algorithm, same order, double arithmetic.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineSkinNative : public Object {
	GDCLASS(KineSkinNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// L12 PERF60: the posed world position of every vertex (scripts/skin_pick.gd refresh): sum over the `per` influences of
	// (mats[bone] * rest) * weight. mats: 4 Vector3 per bind (basis column x, y, z, origin). -> PackedVector3Array
	static PackedVector3Array skin_points(const PackedVector3Array &p_rest, const PackedInt32Array &p_bo, const PackedFloat32Array &p_w,
			int p_per, const PackedVector3Array &p_mats);
	// L12: the box of pos[vix[i]] over all i (no grow)
	static AABB points_aabb(const PackedVector3Array &p_pos, const PackedInt32Array &p_vix);
	// fr: DqSkin.frame_of(mats). nrm/tan may be empty. msk: per-vertex 0..1 or empty (size != vertex count = ignored).
	// -> {"v","n","t" corrected copies, "cnt" vertices moved, "sing" vertices left singular}
	static Dictionary correct(const PackedVector3Array &p_vs, const PackedVector3Array &p_nn, const PackedFloat32Array &p_nt,
			const PackedInt32Array &p_bo, const PackedFloat32Array &p_w, const Dictionary &p_fr, double p_k,
			const PackedInt32Array &p_multi, const PackedFloat32Array &p_msk);
};

} // namespace godot
