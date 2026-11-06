#pragma once
// KineRenderNative (L51 RENDER2): the heavy per-pixel loops of the Final HQ preset.
//   accumulate()  mean of N same-size RGB8 images -> float RGB (0..1); threaded over byte ranges.
//   denoise()     edge-avoiding a-trous wavelet filter (after Dammertz et al. 2010, written from the paper): B3-spline 5-tap kernel with holes
//                 (step 1, 2, 4 ...), each tap weighted by exp(-|dcolour|^2/sc_i^2) * exp(-|dguide|^2/sg^2); guide = a feature buffer (albedo /
//                 normal / depth, 3 floats per pixel) that carries the clean edges. scripts/final_hq.gd FinalHQ.denoise_gd is the same maths.
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class KineRenderNative : public Object {
	GDCLASS(KineRenderNative, Object)

protected:
	static void _bind_methods();

public:
	static int version();
	// p_imgs: Array of PackedByteArray (RGB8, equal sizes). Returns mean/255 per byte.
	static PackedFloat32Array accumulate(const Array &p_imgs);
	// p_rgb, p_guide: w*h*3 floats. Returns the filtered w*h*3 floats.
	static PackedFloat32Array denoise(const PackedFloat32Array &p_rgb, const PackedFloat32Array &p_guide, int p_w, int p_h, int p_iters, double p_sigma_c, double p_sigma_g);
};

} // namespace godot
