#pragma once
// KineRetopoNative (I11): the solver of stroke-guided retopology (scripts/kmesh_retopo_*.gd).
//
// METHOD. Takayama, Panozzo, Sorkine-Hornung, Sorkine-Hornung ("Sketch-Based Generation and Editing of Quad Meshes",
// ACM Transactions on Graphics 32(4), SIGGRAPH 2013, art. 97): the user's strokes cut the surface into patches of 2 to 6
// sides, each side carries an edge count, and a patch is filled with a quad topology chosen from a small dictionary by the
// side counts (an integer system). This file is an independent implementation written from the paper's idea and from the
// Gauss-Bonnet count of a quad disk; no code was taken from QuadriFlow (MIT) or any AGPL project.
//
//  - plan / fill: the patch topology for sides of given counts, and the vertex positions (transfinite Coons interpolation
//    of the sub-grids). 4 sides: one grid (opposite counts equal, 0 singularities). 3, 5, 6 sides: n sub-grids round one
//    centre vertex of valence n joined to a vertex of every side (1 singularity). 2 sides: two valence-3 vertices
//    (2 singularities). Everything in double precision, in the exact operation order of scripts/kmesh_retopo_fill.gd, so the
//    two agree to 1e-9 (tests/sretopo_test.gd bar 7); a 2-sided patch's interior is then relaxed (DIGON_SMOOTH Laplacian steps).
//  - set_source / project: closest point on the source triangle mesh (BVH), with the interpolated vertex normal.
//  - solve_patch / solve_patches: fill, drop the interior vertices on the surface, then relax them (tangent-plane Gauss-Seidel
//    smoothing, each step projected back), the patch border held. Timed in C++ (std::chrono).
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <vector>

namespace godot {

class KineRetopoNative : public RefCounted {
	GDCLASS(KineRetopoNative, RefCounted)

	struct BNode {
		double lo[3], hi[3];
		int l = -1, r = -1, start = 0, count = 0;
	};
	std::vector<double> sv;   // source vertices, 3 per
	std::vector<int> st;      // source triangles, 3 per
	std::vector<double> svn;  // source vertex normals
	std::vector<BNode> bvh;
	std::vector<int> order;
	int build_node(int lo, int hi);
	// closest point to p: triangle id, point, barycentric; `hint` is a triangle tried first (tightens the search)
	double closest(const double *p, int hint, int &tri, double *q, double *bary) const;
	void normal_at(int tri, const double *bary, double *n) const;

protected:
	static void _bind_methods();

public:
	static int version();

	// plan for sides with `counts` edges: {ok, kind, reason, n, f (PackedInt32Array), p, alpha, beta, singular (valences of the interior singular verts)}
	static Dictionary plan(const PackedInt32Array &p_counts);
	// the patch for `sides` (Array of PackedFloat64Array, side i = counts[i] + 1 points xyz, ccw seen from outside): {ok, reason, kind,
	// verts (PackedFloat64Array), quads (PackedInt32Array), nring, singular (PackedInt32Array of vertex ids)}. The first nring verts are the ring.
	static Dictionary fill(const Array &p_sides);

	void set_source(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris);
	bool has_source() const;
	// pts: PackedFloat64Array xyz. -> {pts, normals, dist (PackedFloat64Array), tris (PackedInt32Array)}
	Dictionary project(const PackedFloat64Array &p_pts) const;
	// fill + project the interior + relax it `iters` times. -> fill's dictionary plus {ms}
	Dictionary solve_patch(const Array &p_sides, int p_iters) const;
	// patches: Array of Array(sides). -> {patches: Array of the above, ms: the whole loop timed from C++}
	Dictionary solve_patches(const Array &p_patches, int p_iters) const;
};

} // namespace godot
