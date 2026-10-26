#pragma once
// KineSculptNative: the sculpt hot path of scripts/kmesh_sculpt.gd (verts_in, one dab's displacements, _apply, _renormal).
// Static, stateless: every call takes and returns packed arrays; per-mesh topology lives in a Dictionary made once per stroke.
// It mirrors the GDScript arithmetic (same loop and sum order) so native and GDScript agree to ~1e-6 per vertex.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class KineSculptNative : public Object {
	GDCLASS(KineSculptNative, Object)

protected:
	static void _bind_methods();

public:
	// bump when the arithmetic changes (tests print it)
	static int version();

	// per-stroke topology + spatial hash: {fstart, fidx, vf_start, vf_list, nb_start, nb_list, hkeys, hverts, cell}
	static Dictionary make_ctx(const PackedVector3Array &p_verts, const Array &p_faces, double p_cell);
	// vertex ids within r of c, in the same order as KMeshSculpt.verts_in (cell loop x,y,z; newest vert of a cell first)
	static PackedInt32Array verts_in(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const Vector3 &p_c, double p_r);
	// one dab's per-vert displacement for brushes draw..snake (not grab / mask / face set)
	static PackedVector3Array displacements(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const PackedVector3Array &p_vnorm,
			const PackedInt32Array &p_ids, int p_brush, int p_falloff, const Vector3 &p_hit, const Vector3 &p_n, double p_r,
			double p_a, double p_strength, double p_sgn, bool p_has_last, const Vector3 &p_last);
	// add displacements (+ mirror partners, mask, lock), refresh normals: returns [verts, face_normals, vert_normals, moved]
	static Array apply(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const PackedVector3Array &p_fnorm, const PackedVector3Array &p_vnorm,
			const PackedInt32Array &p_ids, const PackedVector3Array &p_d, const PackedInt32Array &p_sym, int p_sax, const PackedFloat32Array &p_mask,
			const PackedByteArray &p_lock);
	// refresh the normals of the faces touching `moved` (verts already written): returns [face_normals, vert_normals]
	static Array renormal(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const PackedVector3Array &p_fnorm, const PackedVector3Array &p_vnorm,
			const PackedInt32Array &p_moved);
};

} // namespace godot
