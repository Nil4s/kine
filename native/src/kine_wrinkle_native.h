#pragma once
// KineWrinkleNative (L62, I09 wrinkles): per-vertex skin COMPRESSION of a posed mesh against its rest shape.
//   blend()   rest + sum(weight_k * delta_k) over the mask (the linear AU blendshapes).
//   wrinkle() strain() + the zone amplitude / phase of face_wrinkle.gd in one call.
//   strain()  for each vertex a 2x2 Green strain in the tangent plane (frame from the rest normal), least-squares fitted from the
//             incident edges (mm units inside); returns 4 floats per vertex: the wrinkle line direction (the principal direction
//             of the LEAST compressive axis, i.e. perpendicular to the most compressive one), and the compression (>= 0, unitless).
// Static, stateless. scripts/face_wrinkle.gd FaceWrinkle.strain_gd is the same arithmetic in GDScript (fallback and equality twin).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineWrinkleNative : public Object {
	GDCLASS(KineWrinkleNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	static PackedVector3Array blend(const PackedVector3Array &p_rest, const Array &p_deltas, const PackedFloat32Array &p_weights);
	// prep(): once per mesh: for the vertices with zone != 0 (active), their frames, incident rest edges and inverse Gram matrices
	static Dictionary prep(const PackedVector3Array &p_rest, const PackedVector3Array &p_normals, const PackedInt32Array &p_tris, const PackedByteArray &p_zt);
	// wrinkle(): per frame, the compression of the active vertices + the zone amplitude / phase: {dir, comp, amp, c0 (dir.xyz, amp)} (the phase is static: FaceWrinkle.zones), zero outside the zones; p_par = [wavelength m, C0, C1, gate of zone 1..5, purse weight]; p_purse x weight is added to p_posed for the strain only
	static Dictionary wrinkle(const Dictionary &p_prep, const PackedVector3Array &p_posed, const PackedVector3Array &p_purse, const PackedByteArray &p_zt, const PackedFloat32Array &p_zw, const PackedFloat64Array &p_par);
};

} // namespace godot
