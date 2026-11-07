#pragma once
// KinePropsNative (L58): Props.settle for big sets. Each prop, lowest first, comes to rest on the highest support of an
// already-placed prop that its origin is over. A uniform grid over the placed supports replaces the O(n^2) scan.
// Same arithmetic as scripts/props.gd Props.settle_gd (float32 inverse transform, the same tests), the twin and the fallback.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class KinePropsNative : public Object {
	GDCLASS(KinePropsNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// p_xf: 12 doubles per prop (basis columns x, y, z, then origin; values are float32-exact);
	// p_start: n+1 ints, the supports of prop i are p_start[i] .. p_start[i+1]-1;
	// p_sup: 5 doubles per support (dy = height above the prop's origin, centre x, centre z, half x, half z);
	// p_skip: n bytes (non-zero = stays where it is and holds nothing up).
	// Returns n+1 doubles: the settled origin.y of every prop, then the number of props moved.
	static PackedFloat64Array settle(const PackedFloat64Array &p_xf, const PackedInt32Array &p_start, const PackedFloat64Array &p_sup, const PackedByteArray &p_skip);
};

} // namespace godot
