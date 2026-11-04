#pragma once
// KineWoodNative (CH4): the solid-wood grain field of scripts/build/wood_solid.gd, evaluated at many points. Static, stateless.
// Same arithmetic as the GDScript (doubles, the same 32-bit integer hash) so the two agree to float32 rounding of the output.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class KineWoodNative : public Object {
	GDCLASS(KineWoodNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// 6 floats per point: r, g, b (sRGB), growth coordinate g, pore, ray
	static PackedFloat32Array sample(const PackedVector3Array &p_pts, const Vector3 &p_pith, const Vector3 &p_w, const Vector3 &p_u, const Vector3 &p_v,
			int p_seed, double p_ring, double p_ring_var, double p_oval, double p_oval_ang, double p_pore_p, double p_ray_dens);
};

} // namespace godot
