#pragma once
// KineMeshOpsNative: native ports of Kine's mesh hot paths (n03).
//  - decimate: the quadric edge-collapse loop of scripts/kmesh_decimate.gd (KMeshDecimate.collapse), same heap, same tie order
//  - voxel_remesh: AnyGrip.MeshField.build_banded + KMeshVoxelRemesh.surface_nets (the Sculpt page's Remesh slider)
//  - stl_records / xml_vertices / xml_triangles / obj_faces: the per-triangle packing of MeshExport and ObjIO
// Static, stateless: arrays in, arrays out. Vector3 maths is float32 (godot-cpp's own Vector3), scalar maths double, as in GDScript.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {

class KineMeshOpsNative : public Object {
	GDCLASS(KineMeshOpsNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();

	// verts/faces (triangles) of a KMesh after triangulate; ccls = corner classes ([] when none); he_twin/he_next of the KMesh.
	// Returns {tv, tc, talive, collapses, refused_flip, refused_link, refused_side, refused_lock, max_cost}
	static Dictionary decimate(const PackedVector3Array &p_verts, const Array &p_faces, const PackedInt32Array &p_ccls,
			const PackedInt32Array &p_twin, const PackedInt32Array &p_next, int p_target, bool p_lock);

	// closed mesh -> surface-net quads at `voxel` metres: {verts, faces (Array of 4-index PackedInt32Array), voxels, cell}
	static Dictionary voxel_remesh(const PackedVector3Array &p_verts, const Array &p_faces, double p_voxel);

	// 50-byte binary STL records of one indexed body (normal from the winding, 3 vertices, attribute 0)
	static PackedByteArray stl_records(const PackedVector3Array &p_v, const PackedInt32Array &p_t);
	// the 3MF <vertex .../> lines and <triangle .../> lines, joined by "\n" (no trailing newline)
	static String xml_vertices(const PackedVector3Array &p_v);
	static String xml_triangles(const PackedInt32Array &p_t);
	// OBJ "v x y z" lines of xf * p, and "vn" lines of (nb * n).normalized(), "%.6f", joined by newline
	static String obj_vertices(const PackedVector3Array &p_v, const Transform3D &p_xf);
	static String obj_normals(const PackedVector3Array &p_n, const Basis &p_nb);
	// OBJ "f a b c" lines for `count` triangles (ix empty: unindexed), corners 0,2,1; refs "v", "v/t", "v//n" or "v/t/n"
	static String obj_faces(const PackedInt32Array &p_ix, int p_count, int p_off_v, int p_off_t, int p_off_n, bool p_has_t, bool p_has_n);
};

} // namespace godot
