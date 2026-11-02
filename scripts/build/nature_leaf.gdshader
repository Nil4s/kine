shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;
// FRIDAY 225: one leaf card, alpha-tested into a leaf shape. Per-instance colour from the MultiMesh. The light sees a ball-like normal
// (from the crown's middle out to the card), so a crown shades as one mass instead of a pile of flat cards.
uniform int shape = 0;
uniform float crown_h = 3.0;
uniform float soft = 0.55;
varying vec3 vcol;
void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ipos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 centre = NODE_POSITION_WORLD + vec3(0.0, crown_h, 0.0);
	vec3 n = normalize(ipos - centre + vec3(0.0, 0.25, 0.0));
	vec3 cardn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	n = normalize(mix(cardn * sign(dot(cardn, n) + 1e-4), n, soft));
	VERTEX = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vcol = COLOR.rgb;
}
float mask(vec2 uv) {
	float x = uv.x - 0.5;
	float v = uv.y;
	if (shape == 0) { // ginkgo fan with a notch
		float r = length(vec2(x, v));
		float a = abs(atan(x, v));
		float edge = 0.92 + 0.03 * sin(a * 18.0);
		float m = (r < edge && a < 0.95 && r > 0.12) ? 1.0 : 0.0;
		if (abs(x) < 0.035 && r > 0.62) m = 0.0;
		if (v < 0.14 && abs(x) < 0.025) m = 1.0;
		return m;
	} else if (shape == 1) { // lobed oak leaf
		vec2 p = vec2(x / 0.36, (v - 0.5) / 0.5);
		float ang = atan(p.y, p.x);
		float lobes = 1.0 + 0.17 * sin(ang * 7.0);
		return length(p) < lobes * 0.95 ? 1.0 : 0.0;
	} else if (shape == 2) { // a tuft of needles
		float m = 0.0;
		for (int i = 0; i < 7; i++) {
			float a = (float(i) - 3.0) * 0.2;
			vec2 d = vec2(sin(a), cos(a));
			float t = dot(vec2(x, v), d);
			float dist = abs(x * d.y - v * d.x);
			if (t > 0.0 && t < 1.0 && dist < 0.028 * (1.0 - 0.5 * t)) m = 1.0;
		}
		return m;
	} else if (shape == 3) { // a palm frond: rib and leaflets
		float w = 0.5 * (1.0 - pow(v, 3.0)) ;
		float lf = fract(v * 16.0 - abs(x) * 5.0);
		float m = (abs(x) < w && lf < 0.62) ? 1.0 : 0.0;
		if (abs(x) < 0.025) m = 1.0;
		return m;
	} else if (shape == 4) { // pointed ovate (birch)
		float w = 0.42 * pow(sin(3.14159 * pow(v, 0.8)), 0.9);
		return abs(x) < w ? 1.0 : 0.0;
	}
	// rounded small leaf (hedge, shrub)
	float w2 = 0.45 * sin(3.14159 * pow(v, 0.75));
	return abs(x) < w2 ? 1.0 : 0.0;
}
void fragment() {
	float m = mask(UV);
	ALPHA = m;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float shade = 0.72 + 0.4 * UV.y;
	float rib = shape == 3 ? 1.0 : 1.0 - 0.18 * smoothstep(0.05, 0.0, abs(UV.x - 0.5));
	ALBEDO = vcol * shade * rib;
	ROUGHNESS = 0.8;
	BACKLIGHT = vcol * 0.25;
}
