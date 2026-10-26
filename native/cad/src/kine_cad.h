#pragma once
// KineCAD: exact-solid kernel for the future BUILD mode (Open CASCADE Technology, LGPL 2.1 + OCCT exception; see native/CAD_BUILD.md).
// Static and handle based: a shape is an int id (0 = failure) into a table owned by this DLL. Units are the caller's.
// The only GDScript caller is scripts/kcad.gd ("the one door").
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
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

	static void release(int p_id);
	static void release_all();
	static int live_count();
};

} // namespace godot
