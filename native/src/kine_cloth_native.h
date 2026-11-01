#pragma once
// KineClothNative: the cape sim of scripts/cloth.gd (Cloth.simulate: lerp of pins/capsules, near/candidate culling, the PBD substep).
// Static, stateless: x and v come in, go out. It mirrors the GDScript arithmetic (float32 Vector3, double scalars, same loop order).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineClothNative : public Object {
	GDCLASS(KineClothNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();

	// Runs substeps m_from+1 .. m_to (the sim clock of Cloth.simulate, m in 1..m_end) on x / v.
	// A, C: Array of PackedVector3Array per frame (pins, capsule end points). Returns [x, v, frames] where frames holds a
	// copy of x for every m % nsub == 0 with m / nsub - pre >= 0 inside the range.
	static Array run(const PackedVector3Array &p_x, const PackedVector3Array &p_v, const Array &p_A, const Array &p_C,
			const PackedFloat64Array &p_rads, const PackedInt32Array &p_E, const PackedFloat64Array &p_rest, const PackedByteArray &p_pinned,
			int p_nsub, int p_pre, int p_m_from, int p_m_to, double p_dt, int p_iter, double p_grav, double p_drag, double p_margin,
			double p_cand_pad);
};

} // namespace godot
