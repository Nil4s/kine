#pragma once
// KineDyntopoNative (L52): dynamic topology under the brush, the C++ twin of scripts/kmesh_dyntopo.gd (KMeshDyntopo.refine_gd).
// refine(verts, tris, c, r, lmax, passes) -> {verts, tris, splits, collapses}. Same edge order, same tests, double maths on float32 data.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineDyntopoNative : public Object {
	GDCLASS(KineDyntopoNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	static Dictionary refine(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris, const Vector3 &p_c, double p_r, double p_lmax, int p_passes);
};

} // namespace godot
