#pragma once
// KineSkinNative: C75. The per-vertex pass of DqSkin.correct_arrays (scripts/dq_skin.gd): the dual-quaternion / linear
// blend pre-correction of rest vertices, normals and tangents. Same algorithm, same order, double arithmetic.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
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
	// fr: DqSkin.frame_of(mats). nrm/tan may be empty. msk: per-vertex 0..1 or empty (size != vertex count = ignored).
	// -> {"v","n","t" corrected copies, "cnt" vertices moved, "sing" vertices left singular}
	static Dictionary correct(const PackedVector3Array &p_vs, const PackedVector3Array &p_nn, const PackedFloat32Array &p_nt,
			const PackedInt32Array &p_bo, const PackedFloat32Array &p_w, const Dictionary &p_fr, double p_k,
			const PackedInt32Array &p_multi, const PackedFloat32Array &p_msk);
};

} // namespace godot
