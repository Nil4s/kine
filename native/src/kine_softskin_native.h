#pragma once
// KineSoftSkinNative: L32 SOFT-2. The per-frame hot loop of scripts/soft_live.gd in C++: the skinning blend of the vertices near a flesh region, the
// region offsets (SoftBody.vertex_offsets: trilinear in the cell, faded toward the lateral edges, zero outside the box), the move of the vertex into the
// bind pose (inverse of the blended skinning matrix), and the NORMALS of the deformed region (area-weighted rest / deformed vertex normals; the file's
// normal is turned by the shortest arc between the two). The result is the byte image of the mesh's vertex buffer (positions, then the octahedral
// normal / tangent pairs) that ArrayMesh.surface_update_vertex_region takes, so the engine rebuilds nothing. Doubles inside; the GDScript path stays.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {

class KineSoftSkinNative : public Object {
	GDCLASS(KineSoftSkinNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// {"v1": vertices of the triangles that touch a candidate, "t2": the triangles that touch any of v1} (what a normal recompute needs)
	static Dictionary topo(const PackedInt32Array &p_idx, int p_nv, const PackedInt32Array &p_cand);
	// the byte image of a vertex buffer's normal region: per vertex octahedral normal (4 B) then, when p_tan is not empty (4 floats a vertex), tangent (4 B)
	static PackedByteArray encode_nt(const PackedVector3Array &p_nrm, const PackedFloat32Array &p_tan);
	// p_mats: Array of Transform3D (the skinning matrix of each bind). p_gt: the skeleton's global transform.
	// p_regs: 19 doubles per region: 12 (rows of the world -> box-coordinate affine), size xyz, cells xyz, offset of its displacements in p_disps.
	// p_nt0: encode_nt of the undeformed normals (stride 4 or 8 per vertex, empty = no normals region). p_do_nrm: recompute the normals.
	// -> {"moved": vertices moved, "buf": positions (12 B a vertex) + normal region, "turned": normals turned}; "buf" absent when moved == 0.
	static Dictionary deform(const PackedVector3Array &p_verts, const PackedInt32Array &p_bones, const PackedFloat32Array &p_weights, int p_per,
			const PackedInt32Array &p_cand, const Array &p_mats, const Transform3D &p_gt, const PackedFloat64Array &p_regs, const PackedVector3Array &p_disps,
			double p_strength, const PackedInt32Array &p_idx, const PackedVector3Array &p_nrm, const PackedFloat32Array &p_tan, const PackedByteArray &p_nt0,
			const PackedInt32Array &p_v1, const PackedInt32Array &p_t2, bool p_do_nrm);
};

} // namespace godot
