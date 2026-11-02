shader_type spatial;
render_mode cull_disabled;
// FRIDAY 225: a grass blade (or a flower, UV.x < 0 marks the stem) with its per-instance colour; dark at the root, light at the tip.
uniform float flower = 0.0;
varying vec3 vcol;
void vertex() { vcol = COLOR.rgb; }
void fragment() {
	if (flower > 0.5) {
		if (UV.x < 0.5) ALBEDO = vec3(0.16, 0.36, 0.1);
		else ALBEDO = vcol;
	} else {
		ALBEDO = mix(vcol * 0.45, vcol * 1.2, UV.y);
	}
	ROUGHNESS = 0.85;
	BACKLIGHT = ALBEDO * 0.2;
}
