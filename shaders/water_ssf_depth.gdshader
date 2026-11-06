shader_type spatial;
// cull_disabled: a folded triangle of the mesh must not leave a see-through pixel (the nearest face is the surface, whatever its winding)
// L31 screen-space fluid, step 1: the depth of the nearest water surface, as the view-space distance along the camera axis, normalised to [0, 1] over zr from z0
// (a half float target: the span is the scene's own, so the 11 bit mantissa resolves a fraction of a millimetre on a glass). g = 1 marks the water, and b carries the low bits of the depth (see below).
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, fog_disabled;

uniform float z0 = 0.0;
uniform float zr = 1.0;

void fragment() {
	float d = -VERTEX.z;
	float v = clamp((d - z0) / zr, 0.0, 1.0);
	float hi = floor(v * 1024.0) / 1024.0;   // hi is exact in a half float; the remainder rides in b, scaled to [0, 1): ~21 bits in all
	ALBEDO = vec3(hi, 1.0, (v - hi) * 1024.0);
	ALPHA = 1.0;
}
