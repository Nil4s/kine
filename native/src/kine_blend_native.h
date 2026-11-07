#pragma once
// KineBlendNative (L41 N084): the blend matrix heavy loop, in C++.
//   matrix()  scripts/blend_matrix.gd BlendMatrix._cells_gd (the GDScript twin): every clip-to-clip crossfade of a moveset. Per cell the most any joint is
//   past its limit, the deepest capsule clash, the planted-foot slide and the pose distance at the seam.
// rig (Dictionary): J, parent (int32), p0 e0 bax aax wax (float64, 3 per joint), lim (6 per joint: bend lo hi, side lo hi, twist lo hi), stretch, mass.
// caps (Dictionary): joint (int32 per part), c0 c1 rj (float64 x3 per part), rad, pairs (int32 x2), allow, feet (foot_l, ball_l, foot_r, ball_r), rest
//   (float64 x6: per side the foot p0.y, ball p0.y, ball e0.y).
// clips (Array of Dictionary): ang (PackedVector3Array, n x J), off (PackedVector3Array, n), fps, n.
// returns n x n Dictionaries (row major): limit_deg, limit_j (-1 none), limit_ax, clash_mm, clash_p (-1 none), skate_mm, skate_foot (0 none, 1 left, 2 right), seam.
// Double arithmetic throughout; the twin runs the Body float32 FK, so the two agree to about 1e-4 mm (tests/n084_test.gd bars 0.1).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class KineBlendNative : public Object {
	GDCLASS(KineBlendNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	static Array matrix(const Dictionary &p_rig, const Dictionary &p_caps, const Array &p_clips, double p_blend_s);
};

} // namespace godot
