shader_type spatial;
// CH8: water over the particle surface. Refraction: the screen behind is sampled with the offset the surface normal gives (thin-lens style),
// tinted by a Beer-like absorption, with a Schlick Fresnel reflection of the sky colour on top.
render_mode cull_back, depth_draw_always, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.45, 0.72, 0.9, 1.0);
uniform vec4 sky : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform float strength = 0.06;
uniform float ior = 1.333;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	vec2 off = n.xy * strength * (1.0 - 0.5 * ndv);
	vec3 behind = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	float f0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
	float fres = f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0);
	vec3 absorbed = behind * mix(vec3(1.0), tint.rgb, 0.85);
	ALBEDO = mix(absorbed, sky.rgb, fres);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	METALLIC = 0.0;
	ALPHA = 0.995;
}
