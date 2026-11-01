#pragma once
// KineFieldNative: the hot loop of AnyGrip.MeshField.build_banded (scripts/any_grip.gd): per triangle, the closest-point
// distance of the voxels within BAND cells of its box, then the flood fill of the untouched voxels. Static, stateless.
// Mirrors the GDScript arithmetic (Vector3 float32, scalars double) so the field matches to ~1e-6.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class KineFieldNative : public Object {
	GDCLASS(KineFieldNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// the d array (nx*ny*nz float32) of build_banded, given the grid (gmin, nx, ny, nz, cell), the volume sign and the constants
	static PackedFloat32Array banded(const PackedVector3Array &p_tris, const Vector3 &p_gmin, int p_nx, int p_ny, int p_nz,
			double p_cell, double p_flip, double p_band, double p_on_surface);
};

} // namespace godot
