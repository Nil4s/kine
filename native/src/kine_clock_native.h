#pragma once
// KineClockNative (CH2, the mechanical clock): the per-frame contact test of many moving flat parts.
//   pair_overlaps()  for polygons (mm, any simple outline) posed as (x, y, angle rad) and a list of index pairs: the overlap AREA (mm2) of each pair.
//                    Each outline is ear-clipped to triangles; the area is the sum over triangle pairs of the convex clip (Sutherland-Hodgman).
// Static, stateless. scripts/build/clock_ch2.gd ClockCH2.pair_overlaps_gd is the same algorithm in GDScript (the fallback and the test's twin).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class KineClockNative : public Object {
	GDCLASS(KineClockNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// p_polys: Array of PackedVector2Array; p_pose: 3 doubles per polygon (x, y, angle); p_pairs: 2 ints per pair. Returns one area per pair.
	static PackedFloat64Array pair_overlaps(const Array &p_polys, const PackedFloat64Array &p_pose, const PackedInt32Array &p_pairs);
};

} // namespace godot
