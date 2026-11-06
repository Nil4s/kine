#pragma once
// KineKMeshNative (L60 kmeshnat): the KMesh topology and the two heavy modelling ops in C++, with the GDScript code left as the twin.
//  - topology / from_tris / edge_map: scripts/kmesh.gd rebuild(), from_array_mesh() (weld) and is_manifold()
//  - subdivide: scripts/kmesh_subdiv.gd (Catmull-Clark, uniform or no creases, no attribute channels)
//  - boolean: scripts/kmesh_boolean.gd (no attribute channels)
// Static, stateless. Vector3 maths is float32 (godot-cpp's Vector3) and scalar maths double, as in GDScript, so results are identical.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class KineKMeshNative : public Object {
	GDCLASS(KineKMeshNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// half-edge arrays, normals, vertex->face CSR and the manifold verdict of verts + faces
	// {he_vert, he_next, he_twin, he_face, face_he0, face_normals, vert_normals, vf_start, vf_list, manifold (0/1), corners}
	static Dictionary topology(const PackedVector3Array &p_verts, const Array &p_faces);
	// weld the triangle soup (grid tol 1e-6), then topology: {verts, faces, + topology()}
	static Dictionary from_tris(const PackedVector3Array &p_pos, const PackedInt32Array &p_idx, double p_tol);
	// directed edge a * nv + b -> first half-edge
	static Dictionary edge_map(int p_nv, const PackedInt32Array &p_he_vert, const PackedInt32Array &p_he_next);
	// Catmull-Clark: {verts, faces}. crease < 0: none; else that sharpness on every edge
	static Dictionary subdivide(const PackedVector3Array &p_verts, const Array &p_faces, int p_levels, double p_crease);
	// boolean of two closed meshes; tri tables are built by the caller for n-gons (see scripts/kmesh_native.gd)
	static Dictionary boolean(const PackedVector3Array &p_va, const Array &p_fa, const PackedInt32Array &p_ta_corner, const PackedInt32Array &p_ta_face,
			const PackedVector3Array &p_vb, const Array &p_fb, const PackedInt32Array &p_tb_corner, const PackedInt32Array &p_tb_face, int p_op, double p_snap_min);
};

} // namespace godot
