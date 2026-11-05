#pragma once
// KineParkourNative (CH7): the set's penetration scan of scripts/parkour.gd (Parkour.deepest).
//   deepest()  every body capsule (a, b, r) against every axis-aligned box of the course (centre, half size): the deepest
//              point of any capsule inside any box, less the capsule's own standing allowance (a flat sole's capsule
//              reaches below the sole by design). It mirrors Props.depth + Props._sd exactly: the axis sampled at most
//              STEP = 1 cm apart, both ends included, the box's signed distance per sample, depth = r - sd.
// Static, stateless (float32 vector maths like the GDScript, double scalars).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineParkourNative : public Object {
	GDCLASS(KineParkourNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// returns [depth (m, 0 = clear), capsule index (-1 = none), box index (-1 = none)]
	static Array deepest(const PackedVector3Array &p_a, const PackedVector3Array &p_b, const PackedFloat32Array &p_r,
			const PackedFloat32Array &p_base, const PackedVector3Array &p_centre, const PackedVector3Array &p_half);
};

} // namespace godot
