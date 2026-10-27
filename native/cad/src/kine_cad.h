#pragma once
// KineCAD: exact-solid kernel for the future BUILD mode (Open CASCADE Technology, LGPL 2.1 + OCCT exception; see native/CAD_BUILD.md).
// Static and handle based: a shape is an int id (0 = failure) into a table owned by this DLL. Units are the caller's.
// The only GDScript caller is scripts/kcad.gd ("the one door").
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class KineCAD : public Object {
	GDCLASS(KineCAD, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	static String occt_version();
	static String last_error();

	static int box(double p_dx, double p_dy, double p_dz); // centred on the origin
	static int cylinder(double p_r, double p_h); // axis Z, centred on the origin
	static int sphere(double p_r);
	static int translate(int p_id, const Vector3 &p_by); // a new shape
	static int rotate(int p_id, const Vector3 &p_axis, double p_radians);

	static int union_(int p_a, int p_b);
	static int cut(int p_a, int p_b);
	static int intersect(int p_a, int p_b);
	static int fillet_all(int p_id, double p_radius); // every edge
	// hollow it, walls p_thickness thick (inwards). p_open_dir != 0: also open the planar face whose normal points that way.
	static int shell(int p_id, double p_thickness, const Vector3 &p_open_dir);

	static double volume(int p_id);
	static double area(int p_id);
	static int face_count(int p_id);
	static int edge_count(int p_id);
	// one surface, vertices + normals + indices; not welded across B-rep faces (each face keeps its own vertices)
	static Ref<ArrayMesh> tessellate(int p_id, double p_deflection, double p_angle);

	static bool export_step(int p_id, const String &p_path);
	static int import_step(const String &p_path);

	// ---- phase 2: sketch -> solid (Fusion-style PART tools). A plane is (origin, x_dir, normal); sketch (u, v) = origin + u*x + v*(normal x x).
	// p_items: Array of Dictionary, in any order, forming ONE closed loop (open for a sweep path / loft rail):
	//   {t:"line", a:Vector2, b:Vector2}  {t:"arc", a, m (a point on the arc), b}  {t:"bspline", pts:PackedVector2Array, closed:bool}  {t:"circle", c, r}
	static int sketch_wire(const Array &p_items, const Vector3 &p_origin, const Vector3 &p_x, const Vector3 &p_normal);
	static int sketch_face(const Array &p_items, const Vector3 &p_origin, const Vector3 &p_x, const Vector3 &p_normal); // wire -> planar face
	static int path_wire(const PackedVector3Array &p_points); // 3D polyline wire (open)
	static int face_from_wire(int p_wire);
	// extrude a face along its normal. p_both: symmetric, p_dist is the total. p_taper (radians): >0 narrows as it goes.
	static int extrude(int p_face, double p_dist, bool p_both, double p_taper);
	static int revolve(int p_profile, const Vector3 &p_axis_origin, const Vector3 &p_axis_dir, double p_radians);
	static int sweep(int p_profile, int p_path); // profile face (solid) or wire (shell) along the path wire
	static int loft(const PackedInt32Array &p_profiles, bool p_ruled, bool p_solid); // wires or faces, in order
	// edge / face ids are 1-based positions in the shape's own map: stable for one shape id, NOT across derived shapes
	static Array edges(int p_id); // [{id, center, a, b, length, dir (tangent at the middle), faces: [face ids]}]
	static Array faces(int p_id); // [{id, center (of mass), normal (outward at the centre point), area, type, point (a point on the face)}]
	static int fillet_edges(int p_id, const PackedInt32Array &p_edge_ids, double p_radius);
	static int chamfer_edges(int p_id, const PackedInt32Array &p_edge_ids, double p_dist);
	// offset a face: a prism of it along its outward normal by p_dist (> 0 fused outside, < 0 cut inside). 0 on failure.
	static int offset_face(int p_id, int p_face_id, double p_dist);
	// draft faces (ids as in faces()) by p_angle (radians) about the neutral plane through p_neutral_origin with normal p_pull_dir
	static int draft_faces(int p_id, const PackedInt32Array &p_face_ids, double p_angle, const Vector3 &p_pull_dir, const Vector3 &p_neutral_origin);
	static int mirror(int p_id, const Vector3 &p_origin, const Vector3 &p_normal); // the reflected copy only
	static int pattern_linear(int p_id, const Vector3 &p_step, int p_count); // copies fused with the original
	static int pattern_circular(int p_id, const Vector3 &p_axis_origin, const Vector3 &p_axis_dir, int p_count, double p_total_radians);
	static Dictionary mass_properties(int p_id); // {volume, area, center, inertia (Basis about the centre, density 1)}

	static void release(int p_id);
	static void release_all();
	static int live_count();
};

} // namespace godot
