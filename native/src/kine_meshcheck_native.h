#pragma once
// KineMeshCheckNative: the triangle-mesh scans of the Export dialog and the size line.
//   scan()        scripts/build/print_check.gd PrintCheck.analyse (thin walls, overhangs, floating pieces: the numbers, not the words)
//   edge_check()  scripts/build/mesh_export.gd MeshExport.check (the "closed: every edge joins exactly two faces" edge count)
//   signed_volume()/bounds()  MeshExport.signed_volume / the box loop of MeshExport.report
//   feet_hull()   scripts/build/part_stand.gd PartStand.check (the feet within 0.5 mm of the lowest height, and their convex hull)
// Static, stateless; it mirrors the GDScript arithmetic (float32 vector maths, double scalars, same loop order and the same
// tie-breaks), so counts are identical and floats agree to ~1e-6.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class KineMeshCheckNative : public Object {
	GDCLASS(KineMeshCheckNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();

	// bodies = [{"v": PackedVector3Array, "t": PackedInt32Array}, ...] (MeshExport.bodies_of). Returns
	// {"walls": int, "thinnest": float (INF when none), "over_mm2": float, "floating": int, "lowest": float (INF when none), "tris": int}
	static Dictionary scan(const Array &p_bodies);
	// {"tris": int, "open": int, "bad": int}
	static Dictionary edge_check(const PackedInt32Array &p_t);
	static double signed_volume(const PackedVector3Array &p_v, const PackedInt32Array &p_t);
	// [min corner, max corner] of the vertices (empty array for no vertices)
	static PackedVector3Array bounds(const PackedVector3Array &p_v);
	// the convex hull (counter-clockwise, PartStand._hull) of the (x, z) of every vertex with y <= lowest y + foot
	static PackedVector2Array feet_hull(const PackedVector3Array &p_verts, double p_foot);
};

} // namespace godot
