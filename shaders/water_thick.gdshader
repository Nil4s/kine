shader_type spatial;
// L5: optical thickness pass. Every water triangle adds its signed ray distance: back faces +|P|, front faces -|P| (P = view-space position), so after the
// additive blend the pixel holds the length of the view ray INSIDE the water, summed over every entry/exit pair (needs a closed, consistently wound mesh).
// Rendered into a float SubViewport (use_hdr_2d) with a linear environment; the red channel is the thickness in metres.
render_mode unshaded, cull_disabled, depth_test_disabled, blend_add, shadows_disabled, fog_disabled;

void fragment() {
	float d = length(VERTEX);
	float s = FRONT_FACING ? -1.0 : 1.0;
	ALBEDO = vec3(s * d, 1.0, 0.0);   // r: signed ray length, g: number of faces crossed (odd = unmatched entry or exit)
	ALPHA = 1.0;
}
