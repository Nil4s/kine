shader_type spatial;
// L5 water. Own lighting, no thin shell: the colour of the water is a function of how much water the view ray crosses (thickness pass, water_thick.gdshader).
//   colour = mix( behind * exp(-sigma * t)  +  scatter * (1 - exp(-k t)),  sky(reflect),  F )  then foam over it
// F: Schlick (1994) with n = 1.333 (F0 = 0.0201).
// sigma: absorption of pure water, Pope & Fry, Appl. Opt. 36, 8710 (1997), table at https://omlc.org/spectra/water/data/pope97.txt:
//   630 nm 0.2916 /m (red), 550 nm 0.0565 /m (green), 450 nm 0.00922 /m (blue).
// Refraction: the refracted ray (Snell, 1/1.333) is followed for the thickness t and the screen is sampled where it ends.
render_mode unshaded, cull_back, depth_draw_always, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D thick_tex : filter_nearest, repeat_disable;
uniform vec3 sigma = vec3(0.2916, 0.0565, 0.00922);
uniform float absorb_scale = 1.0;      // 1 = physical pure water. 0 switches the absorption off (test control)
uniform float fresnel_on = 1.0;        // 0 = constant F0 (test control)
uniform float ior = 1.333;
uniform vec3 sky_top : source_color = vec3(0.50, 0.68, 0.95);
uniform vec3 sky_horizon : source_color = vec3(0.92, 0.95, 1.0);
uniform vec3 scatter_col : source_color = vec3(0.03, 0.22, 0.30);
uniform float scatter_k = 6.0;         // per metre of path; an art term for the blue-green body colour of deep water
uniform float scatter_on = 1.0;
uniform vec3 sun_dir = vec3(0.45, 0.75, 0.35);
uniform float sun_power = 160.0;
uniform float sun_strength = 1.0;
uniform vec3 foam_col : source_color = vec3(0.96, 0.98, 1.0);
uniform float foam_gain = 1.0;
uniform float min_path = 0.0;

varying float v_foam;

void vertex() {
	v_foam = COLOR.r;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 P = VERTEX;
	vec3 I = normalize(P);                       // view space, from the eye to the surface
	float ndv = clamp(dot(n, -I), 0.0, 1.0);
	float f0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
	float F = fresnel_on > 0.5 ? f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0) : f0;
	float t = max(textureLod(thick_tex, SCREEN_UV, 0.0).r, min_path);
	vec3 T = refract(I, n, 1.0 / ior);
	vec3 Q = P + T * t;                          // where the refracted ray leaves the water (the thing behind is about there)
	vec4 qc = PROJECTION_MATRIX * vec4(Q, 1.0);
	vec2 uv = clamp(qc.xy / qc.w * 0.5 + 0.5, vec2(0.002), vec2(0.998));
	vec3 behind = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 trans = behind * exp(-sigma * absorb_scale * t);
	vec3 body = scatter_on * scatter_col * (1.0 - exp(-scatter_k * t));
	// reflection of the sky dome (world up = +y); the view-space reflection vector goes to world with the inverse view matrix
	vec3 R = reflect(I, n);
	vec3 Rw = normalize((INV_VIEW_MATRIX * vec4(R, 0.0)).xyz);
	vec3 sky = mix(sky_horizon, sky_top, clamp(Rw.y, 0.0, 1.0));
	vec3 L = normalize(sun_dir);
	float spec = pow(max(dot(Rw, L), 0.0), sun_power) * sun_strength;
	vec3 refl = sky + vec3(spec);
	vec3 col = mix(trans + body, refl, F);
	float foam = clamp(v_foam * foam_gain, 0.0, 1.0);
	col = mix(col, foam_col, foam * 0.85);
	ALBEDO = col;
	ALPHA = 1.0;
}
