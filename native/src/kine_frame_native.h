#pragma once
// KineFrameNative (CH10): 3D Euler-Bernoulli frame solver for the house under load in time.
// Stiffness assembly, reverse Cuthill-McKee ordering, banded Cholesky, static solve, inverse iteration, Newmark-beta (average acceleration).
// Static and stateless: one call takes the model and a job, returns a Dictionary. The GDScript twin is scripts/build/ch10_frame.gd (same maths, dense);
// tests/ch10_test.gd bars C++ == GDScript on a small frame.
// Units are the caller's (the house uses N, m, kg, s). 6 DOF per node: ux uy uz rx ry rz. DOF index = node * 6 + d.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class KineFrameNative : public Object {
	GDCLASS(KineFrameNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();

	// model: xyz PackedFloat64Array (3 per node);
	//   beams PackedFloat64Array, 12 per element: n1 n2 A Iz Iy J E G rho e2x e2y e2z   (Iz: bending with displacement along e2, Iy: along e3 = e1 x e2; Ip = Iz + Iy for the torsional inertia)
	//   springs PackedFloat64Array, 3 per spring: n1 n2 k (axial, along the line n1-n2)
	//   fixed PackedInt32Array of global dofs; mass PackedFloat64Array (n) lumped extra mass added to ux uy uz of each node
	// job: type = "static" (loads 6n) | "modal" (start 6n, iters) | "newmark" (see the .cpp)
	static Dictionary solve(const Dictionary &p_model, const Dictionary &p_job);
};

} // namespace godot
