#pragma once
// KineSoftNative: the XPBD tetrahedral soft-body step of scripts/soft_body.gd (SoftBody._step_gd).
// Static, stateless: x and v come in, go out. Doubles throughout, the same operation order as the GDScript fallback, so the two
// agree to rounding (tests/soft_test.gd bar 5). corotated linear elasticity as two XPBD constraints (deviatoric |F - R| per tet, hydrostatic mean det F - 1 per cell).
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class KineSoftNative : public Object {
	GDCLASS(KineSoftNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();

	// nsub substeps of dt / nsub. w: inverse masses (0 = driven), pin_idx / pin_to: the driven particles and where they stand at the
	// end of the frame (moved linearly through the substeps), fext: external force per particle (N); vref: the velocity damping is relative to (empty = 0; the bone-carried velocity of a flesh node). Returns [x, v].
	static Array run(const PackedFloat64Array &p_x, const PackedFloat64Array &p_v, const PackedFloat64Array &p_w,
			const PackedInt32Array &p_tets, const PackedFloat64Array &p_dm, const PackedFloat64Array &p_v0,
			const PackedInt32Array &p_pin_idx, const PackedFloat64Array &p_pin_to, const PackedFloat64Array &p_fext,
			const PackedFloat64Array &p_vref, int p_nsub, int p_iters, double p_dt, double p_mu, double p_lam, double p_gamma, double p_gx, double p_gy, double p_gz,
			double p_damp);
};

} // namespace godot
