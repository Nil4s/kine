shader_type spatial;
render_mode unshaded, cull_back;
// CH5 wet street ground: one flat quad; height, albedo and roughness come from baked textures (scripts/wet_street.gd).
// Water exists where the baked height < level. The lamp is lit HERE: inverse-square irradiance, Lambert diffuse + GGX specular
// with the wet roughness on every stone top (the stone domes give each stone its own highlight). Water = the planar mirror image,
// blurred along an ellipse (vertical : horizontal = 1 / sin(grazing)), with fine ripple slope noise.
uniform sampler2D tex_h : filter_linear_mipmap, repeat_disable;
uniform sampler2D tex_m : filter_linear_mipmap, repeat_disable;
uniform sampler2D tex_w : filter_linear_mipmap, repeat_disable;
uniform sampler2D refl : filter_linear, repeat_disable;
uniform float level = -0.016;
uniform vec2 origin = vec2(-3.2, -13.6);
uniform vec2 span = vec2(6.4, 14.4);
uniform float texel = 0.003;
uniform float streak_px = 10.0;
uniform float refl_gain = 60.0;
uniform float plane_y = -0.016;
// CH5b: a row of lamps (position, colour x intensity), analytic soft shadows of vertical-cylinder occluders (x, z, radius, height) from a
// spherical bulb of radius light_r, a sodium sky haze and a warm bounce from the lit alley walls.
uniform vec3 lamps[8];
uniform vec3 lamp_cols[8];
uniform int n_lamps = 1;
uniform vec4 occ[16];
uniform int n_occ = 0;
uniform float light_r = 0.3;
uniform int probe_lamp = -1;
uniform vec3 amb_sky = vec3(0.015, 0.018, 0.03);
uniform vec3 wall_col = vec3(0.0);
uniform float wall_x = 3.2;
uniform float spec_gain = 1.0;
uniform float wide_gain = 0.0;
uniform float diff_gain = 1.0;
uniform float asphalt_x = 0.85;
uniform float dry = 0.0;
uniform float ripple_px = 150.0;
varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec2 ripple_slope(vec2 p) {
	vec2 q = p * 30.0;
	float e = 0.05;
	vec2 g1 = vec2(vnoise(q + vec2(e, 0.0)) - vnoise(q - vec2(e, 0.0)), vnoise(q + vec2(0.0, e)) - vnoise(q - vec2(0.0, e))) / (2.0 * e);
	vec2 q2 = p * 75.0 + 17.0;
	vec2 g2 = vec2(vnoise(q2 + vec2(e, 0.0)) - vnoise(q2 - vec2(e, 0.0)), vnoise(q2 + vec2(0.0, e)) - vnoise(q2 - vec2(0.0, e))) / (2.0 * e);
	return (g1 * 30.0 * 0.0004 + g2 * 75.0 * 0.00015);
}

// fraction of the bulb (a sphere of radius R at P) that a ground point G sees past the vertical cylinders; penumbra half-width at the
// occluder = R * (its distance from G / the distance to the bulb)
float occl(vec3 G, vec3 P, float R) {
	float vis = 1.0;
	vec2 pq = P.xz - G.xz;
	float L2 = max(dot(pq, pq), 1e-4);
	for (int k = 0; k < 16; k++) {
		if (k >= n_occ) break;
		vec4 o = occ[k];
		vec2 c = o.xy - G.xz;
		float t = clamp(dot(c, pq) / L2, 0.0, 1.0);
		float lat = length(c - pq * t) - o.z;
		float yr = G.y + t * (P.y - G.y);
		float w = max(R * t, 0.002);
		float s = smoothstep(-w, w, lat);
		float top = smoothstep(o.w - w, o.w + w, yr);
		vis *= 1.0 - (1.0 - s) * (1.0 - top);
	}
	return vis;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - origin) / span;
	float h = texture(tex_h, uv).r;
	vec4 m = texture(tex_m, uv);
	float wet = texture(tex_w, uv).r;
	bool water = dry < 0.5 && h < level;
	vec3 nw = vec3(0.0, 1.0, 0.0);
	vec2 rip = vec2(0.0);
	if (water) {
		rip = ripple_slope(wpos.xz);
		nw = normalize(vec3(-rip.x, 1.0, -rip.y));
	} else {
		// level-0 gradient: far stones must keep their tilt so they glint (averaging it away turns a glittering street flat)
		float hx = textureLod(tex_h, uv + vec2(texel / span.x, 0.0), 0.0).r - textureLod(tex_h, uv - vec2(texel / span.x, 0.0), 0.0).r;
		float hz = textureLod(tex_h, uv + vec2(0.0, texel / span.y), 0.0).r - textureLod(tex_h, uv - vec2(0.0, texel / span.y), 0.0).r;
		nw = normalize(vec3(-hx / (2.0 * texel), 1.0, -hz / (2.0 * texel)));
	}
	vec3 albedo = m.rgb;
	float rough = water ? 0.04 : m.a;
	if (dry > 0.5) {
		albedo = m.rgb / mix(1.0, 0.7, wet);
		rough = wpos.x > asphalt_x ? 0.92 : 0.85;
	}
	vec3 vw = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 v = -vw;
	float nv = max(dot(nw, v), 1e-3);
	float wb = exp(-(wpos.x + wall_x) / 2.2) + exp(-(wall_x - wpos.x) / 2.2);
	float win = 0.7 + 0.3 * sin(wpos.z * 2.9);
	vec3 col = albedo * (amb_sky + wall_col * wb * win);
	float probe_v = 1.0;
	for (int i = 0; i < 8; i++) {
		if (i >= n_lamps) break;
		vec3 L = lamps[i] - wpos;
		float d2 = dot(L, L);
		vec3 l = L * inversesqrt(d2);
		float vis = occl(vec3(wpos.x, 0.0, wpos.z), lamps[i], light_r);
		if (i == probe_lamp) probe_v = vis;
		float nl = max(dot(nw, l), 0.0);
		float cone = smoothstep(0.17, 0.57, dot(-l, vec3(0.0, -1.0, 0.0)));
		vec3 irr = lamp_cols[i] * cone * vis / d2;
		float sgl = i == 0 ? 1.0 : 0.15;   // the row's extra lamps light the stone mostly diffusely: their glints were saturating puddle masks (bar B)
		if (water) {
			col += albedo * 0.08 / 3.14159 * irr * nl * diff_gain;
		} else {
			col += albedo / 3.14159 * irr * nl * diff_gain;
			vec3 hv = normalize(l + v);
			float nh = max(dot(nw, hv), 0.0);
			float vh = max(dot(v, hv), 0.0);
			float a = rough * rough;
			float dd = a * a / (3.14159 * pow(nh * nh * (a * a - 1.0) + 1.0, 2.0));
			float k = (rough + 1.0) * (rough + 1.0) / 8.0;
			float g = (nl / (nl * (1.0 - k) + k)) * (nv / (nv * (1.0 - k) + k));
			float f = 0.03 + 0.97 * pow(1.0 - vh, 5.0);
			col += irr * (dd * f * g / (4.0 * nl * nv + 1e-4)) * nl * (dry > 0.5 ? 1.0 : spec_gain) * sgl;
			if (dry < 0.5 && wide_gain > 0.0 && wpos.x <= asphalt_x) {
				// the water film's wide lobe, anisotropic (ruts and joints run along the lane): narrow across the street (ax), long along the
				// view (ay), so the lamp's glitter on the stone tops becomes a band running toward the camera
				vec3 tt = normalize(vec3(1.0, 0.0, 0.0) - nw * nw.x);
				vec3 bb = cross(nw, tt);
				float hx = dot(hv, tt) / 0.18;
				float hy = dot(hv, bb) / 0.55;
				float q = hx * hx + hy * hy + nh * nh;
				float dw = 1.0 / (3.14159 * 0.18 * 0.55 * q * q);
				col += irr * wide_gain * (dw * f * nl / (4.0 * nl * nv + 1e-4)) * nl * wet * sgl;
			}
		}
	}
	// planar mirror: vertical sigma = streak_px, horizontal = streak_px * sin(grazing); ripples offset the lookup
	float sina = clamp(abs(vw.y), 0.05, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - sina, 5.0);
	float sv = streak_px * (water ? 1.0 : 1.0 + 3.0 * rough);
	float sh = max(sv * sina, 0.75);
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 roff = rip * ripple_px * px;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	const int N = 32;
	for (int i = 0; i < N; i++) {
		float r = sqrt((float(i) + 0.5) / float(N)) * 2.2;
		float an = float(i) * 2.39996;
		vec2 o = vec2(cos(an) * r * sh, sin(an) * r * sv) * px;
		float wgt = exp(-r * r * 0.5);
		vec2 s1 = vec2(SCREEN_UV.x + o.x + roff.x, 1.0 - (SCREEN_UV.y + o.y + roff.y));
		vec2 s2 = vec2(SCREEN_UV.x - o.x + roff.x, 1.0 - (SCREEN_UV.y - o.y + roff.y));
		acc += (texture(refl, clamp(s1, vec2(0.0), vec2(1.0))).rgb + texture(refl, clamp(s2, vec2(0.0), vec2(1.0))).rgb) * wgt;
		wsum += 2.0 * wgt;
	}
	vec3 rc = acc / wsum;
	float kk = dry > 0.5 ? 0.0 : (water ? 1.0 : (wpos.x > asphalt_x ? 0.05 : 0.15) * (1.0 - rough));
	col += rc * clamp(fres * refl_gain, 0.0, 1.0) * kk;
	ALBEDO = probe_lamp >= 0 ? vec3(probe_v) : col;
}
