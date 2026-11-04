#pragma once
// KineSeatNative (s249n): the ornament SEAT step of the Part build, in C++.
//   surface_under()  scripts/build/part_fast.gd PartFast.surface_under / part_ornament.gd PartOrnament._surface_under
// Per sample point the highest host surface y in [low_y, top_y] (NAN for none): a ray straight down from (x, top_y, z) against every
// triangle of the candidate host bodies. Same arithmetic as PartFacts.ray_hit (float32 vector maths, double scalars), so the answers agree.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineSeatNative : public Object {
	GDCLASS(KineSeatNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// p_hosts = Array of PackedVector3Array (3 vertices per triangle, millimetres); p_pts = sample points (only x, z used)
	static PackedFloat64Array surface_under(const Array &p_hosts, const PackedVector3Array &p_pts, double p_top_y, double p_low_y);
};

} // namespace godot
