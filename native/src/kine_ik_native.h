#pragma once
// KineIKNative (L21 I16-SPEED): Body.plant for one leg, in C++.
//   plant_leg()  scripts/body.gd Body.plant (+ flat_foot, reach, knee_over_toes, turn_world, set_ang, fk_sub for the leg), playback mode only
// The GDScript twin stays in scripts/body.gd (the fallback, and what tests/i16fast_test.gd compares this against). Same arithmetic, in the same
// order, with the same float32 vector maths and double scalars as GDScript, so the answers are meant to be equal to the last bit.
// static data (PackedFloat32Array, 79): per joint thigh, calf, foot, ball: p0 e0 b_ax a_ax w_ax t_ax (18 each), then the pelvis p0 (3),
//   then 4 flags (1 = the bone-axis split, w_ax == t_ax).
// dyn (PackedFloat32Array, 71): ang x4 (12), G x4 as xyzw (16), P x4 (12), pelvis G xyzw (4), pelvis P (3), lim x4 as bend, side, twist (min, max) (24).
// returns 53 floats: per joint ang(3) G(4) P(3) E(3), then the miss (m).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class KineIKNative : public Object {
	GDCLASS(KineIKNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// math_probe: kind 0 sin, 1 cos, 2 atan2(xs[2i], xs[2i+1]) (double); 3 Quaternion((0.6, 0, 0.8), (real_t)x) as xyzw; 4 Vector3((x, 0.3, -0.5)).normalized() as xyz
	static PackedFloat64Array math_probe(int p_kind, const PackedFloat64Array &p_xs);
	static PackedFloat32Array plant_leg(const PackedFloat32Array &p_static, const PackedFloat32Array &p_dyn, const Vector3 &p_ball_at, double p_head, bool p_flat, double p_knee);
};

} // namespace godot
