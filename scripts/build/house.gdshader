shader_type spatial;
render_mode unshaded;
// the BUILD page's house: floor slab (world y <= 0) dark, walls light, a soft top-and-side light; see build_ui.gd HOUSE_SHADER
varying vec3 wpos;
varying vec3 wnor;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = normalize(wnor);
	if (!FRONT_FACING) { n = -n; }
	bool floor_part = wpos.y < 0.004;
	vec3 base = floor_part ? vec3(0.2, 0.22, 0.28) : vec3(0.8, 0.82, 0.86);
	float l = 0.52 + 0.28 * max(n.y, 0.0) + 0.2 * max(dot(n, normalize(vec3(-0.5, 0.2, -0.85))), 0.0) + 0.12 * max(dot(n, normalize(vec3(0.8, 0.1, 0.5))), 0.0);
	ALBEDO = base * l;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
