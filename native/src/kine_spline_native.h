#pragma once
// KineSplineNative: L28. The spline-IK solve of scripts/spline_chain.gd (SplineChain._core_gd): a bone chain marched down (keep length) or
// stretched along (stretch to fit) a Catmull-Rom / Bezier curve of 3-5 handles, with twist and volume. Same double arithmetic in the same
// order as the GDScript, so the two agree to ~1e-12 (tests/splineik_test.gd bar 7 holds them within 1e-9).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

namespace godot {

class KineSplineNative : public Object {
	GDCLASS(KineSplineNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	static Dictionary solve(const PackedFloat64Array &p_root, const PackedFloat64Array &p_lens, const PackedFloat64Array &p_ctrl, int p_kind, int p_mode,
			double p_tw0, double p_tw1, const PackedFloat64Array &p_rest_y, const PackedFloat64Array &p_rest_x, bool p_volume);
};

} // namespace godot
