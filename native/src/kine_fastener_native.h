#pragma once
// KineFastenerNative (CH1e): the heavy loops of placing and checking thousands of fasteners on the CH1 house.
//  contacts    every pair of axis-aligned boxes that touch face to face (gap <= tol, overlap > minov on the other two axes)
//  first_hits  per point, the lowest-index solid (box + optional polygon extruded along x) that contains it
//  validate    per fastener, the shank walked in 0.5 mm steps: head gap to its first member, mm inside the first and second member, tip tail, uncovered holes
// Static and stateless. The GDScript twin is scripts/build/ch1e_fast.gd (same arithmetic); tests/ch1e_test.gd bars C++ == GDScript.
// Solids: boxes = 6 doubles each (x0 y0 z0 x1 y1 z1, mm); polyoff = n+1 ints into polypts (2 doubles per vertex: z, y); a solid with no polygon is its box.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class KineFastenerNative : public Object {
	GDCLASS(KineFastenerNative, Object)

protected:
	static void _bind_methods();

public:
	static PackedInt32Array contacts(const PackedFloat64Array &p_boxes, const PackedInt32Array &p_mask, double p_tol, double p_minov);
	static PackedInt32Array first_hits(const PackedFloat64Array &p_boxes, const PackedInt32Array &p_polyoff, const PackedFloat64Array &p_polypts, const PackedInt32Array &p_mask, const PackedFloat64Array &p_pts, double p_tol);
	// heads/dirs: 3 per fastener (dir unit), lens: mm, a/b: solid index; cover: mask of solids that count as lumber. Returns 5 per fastener: head_gap, len_a, len_b, tail, holes
	static PackedFloat64Array validate(const PackedFloat64Array &p_boxes, const PackedInt32Array &p_polyoff, const PackedFloat64Array &p_polypts, const PackedInt32Array &p_cover, const PackedFloat64Array &p_heads, const PackedFloat64Array &p_dirs, const PackedFloat64Array &p_lens, const PackedInt32Array &p_a, const PackedInt32Array &p_b);
};

} // namespace godot
