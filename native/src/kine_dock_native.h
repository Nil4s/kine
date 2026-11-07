#pragma once
// KineDockNative (L64 L-REFRESH): the hands card's spot scan, in C++.
//   first_free()  scripts/hands_dock.gd HandsDock._first_free_gd (the GDScript twin): the first spot, in scan order, of a list of grid spots
//   (x0, y0, x1, y1, ... float64) where a card of size (w, h) is not rejected by the body (when `avoid`) and covers no pick point grown by `pad`.
//   push()  scripts/corrective.gd Corrective._push_gd (the GDScript twin): vs[i] += dv[i] * amp for the vertices in `ai`, single-precision steps as GDScript
//   runs them (a multiply, then an add), so the result is the loop's, bit for bit.
//   Returns the spot's index (0, 1, ...) or -1. The arithmetic is the engine's Rect2 in single precision, step for step
//   (Rect2::intersects, Rect2::grow, Rect2::has_point), so the answer is the GDScript loop's answer, bit for bit.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

namespace godot {

class KineDockNative : public Object {
	GDCLASS(KineDockNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	static PackedVector3Array push(const PackedVector3Array &p_vs, const PackedVector3Array &p_dv, const PackedInt32Array &p_ai, double p_amp);
	static int first_free(const PackedFloat64Array &p_spots, double p_w, double p_h, const Rect2 &p_body, bool p_avoid, const PackedVector2Array &p_pts, double p_pad);
};

} // namespace godot
