#pragma once
// KineSolveNative: C64. The Jacobi-preconditioned conjugate gradient of KMeshAutoWeights._cg (the heat-weights solve, 2/3 of
// its time). Same loops, same order, double arithmetic: the result is bit-equal to the GDScript solver.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class KineSolveNative : public Object {
	GDCLASS(KineSolveNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// x holds the start; returns {"it": iterations, "x": answer}. rp/ci/cv: the off-diagonal CSR, dg: the diagonal.
	static Dictionary cg(int p_n, const PackedInt32Array &p_rp, const PackedInt32Array &p_ci, const PackedFloat64Array &p_cv,
			const PackedFloat64Array &p_dg, const PackedFloat64Array &p_b, const PackedFloat64Array &p_x, double p_tol, int p_max);
};

} // namespace godot
