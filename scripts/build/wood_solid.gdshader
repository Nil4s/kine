shader_type spatial;
render_mode cull_disabled;
// CH4 solid wood: the same field as scripts/build/wood_solid.gd (field()), evaluated at the fragment's position in the mesh's own space (mm).
// Held equal to the GDScript and C++ versions by tests/ch4_test.gd. mode 0 lit, 1 albedo unshaded, 2 ring phase (sin, cos) unshaded.
uniform vec3 pith = vec3(0.0);
uniform vec3 ax_w = vec3(0.0, 0.0, 1.0);
uniform vec3 ax_u = vec3(1.0, 0.0, 0.0);
uniform vec3 ax_v = vec3(0.0, 1.0, 0.0);
uniform int seed = 1;
uniform float ring = 2.0;
uniform float ring_var = 0.35;
uniform float oval = 0.07;
uniform float oval_ang = 0.0;
uniform float pore_p = 0.55;
uniform float ray_dens = 0.35;
uniform int mode = 0;
uniform float bump = 1.0;
varying vec3 lp;
varying vec3 ln;

const vec3 EW = vec3(0.804, 0.635, 0.486);
const float LATE_K = 0.77;
const float PORE_CELL = 0.32;
const float PORE_STRETCH = 8.0;
const int RAY_SLOTS = 240;

float hash3(int x, int y, int z, int s) {
	uint h = (uint(x) * 0x8da6b343u) ^ (uint(y) * 0xd8163841u) ^ (uint(z) * 0xcb1ab31fu) ^ (uint(s) * 0x165667b1u);
	h ^= h >> 15u; h *= 0x2c1b3c6du; h ^= h >> 12u; h *= 0x297a2d39u; h ^= h >> 15u;
	return float(h) / 4294967296.0;
}
float vnoise(float x, float y, float z, int s) {
	int ix = int(floor(x)); int iy = int(floor(y)); int iz = int(floor(z));
	float fx = x - float(ix); float fy = y - float(iy); float fz = z - float(iz);
	fx = fx * fx * (3.0 - 2.0 * fx); fy = fy * fy * (3.0 - 2.0 * fy); fz = fz * fz * (3.0 - 2.0 * fz);
	float x00 = mix(hash3(ix, iy, iz, s), hash3(ix + 1, iy, iz, s), fx);
	float x10 = mix(hash3(ix, iy + 1, iz, s), hash3(ix + 1, iy + 1, iz, s), fx);
	float x01 = mix(hash3(ix, iy, iz + 1, s), hash3(ix + 1, iy, iz + 1, s), fx);
	float x11 = mix(hash3(ix, iy + 1, iz + 1, s), hash3(ix + 1, iy + 1, iz + 1, s), fx);
	return mix(mix(x00, x10, fy), mix(x01, x11, fy), fz);
}
float sst(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

// returns rgb tone in xyz, growth coordinate in w; pore / ray via out
vec4 wood(vec3 p, out float pore, out float ray, out float bl) {
	vec3 q = p - pith;
	float t = dot(q, ax_w); float a = dot(q, ax_u); float b = dot(q, ax_v);
	float ca = cos(oval_ang); float sa = sin(oval_ang);
	float a2 = a * ca + b * sa; float b2 = -a * sa + b * ca;
	float ov = 1.0 + oval;
	float rho0 = sqrt(a2 * a2 * ov * ov + b2 * b2);
	float n1 = vnoise(a / 30.0, b / 30.0, t / 120.0, seed + 11);
	float n2 = vnoise(a / 9.0, b / 9.0, t / 45.0, seed + 23);
	float wob = ring_var * (2.0 * n1 - 1.0) * 1.5 + 0.15 * (2.0 * n2 - 1.0);
	float g = rho0 / ring + wob;
	int gi = int(floor(g)); float f = g - float(gi);
	float h1 = hash3(gi, 5, 5, seed + 3);
	float lw = sst(0.45, 0.93, f) * (0.8 + 0.4 * h1);
	// band limit (lit mode only): once a ring is under ~2 px on screen, or the pores / rays under ~1 px, fade that contrast to its mean so the field does not alias
	bl = 1.0;
	float blp = 1.0;
	if (mode == 0) {
		bl = 1.0 - smoothstep(0.2, 0.5, fwidth(g));
		blp = 1.0 - smoothstep(0.25, 0.6, fwidth(a2 / PORE_CELL) + fwidth(b2 / PORE_CELL));
	}
	float lw_eff = mix(0.31, min(lw, 1.0), bl);
	float tone = 1.0 + (LATE_K - 1.0) * lw_eff;
	float ewz = 1.0 - sst(0.1, 0.7, f);
	float pa = a2 / PORE_CELL; float pb = b2 / PORE_CELL; float pt = t / (PORE_CELL * PORE_STRETCH);
	int ci = int(floor(pa)); int cj = int(floor(pb)); int ck = int(floor(pt));
	float cx = 0.5 + 0.12 * (2.0 * hash3(ci, cj, ck, seed + 31) - 1.0);
	float cy = 0.5 + 0.12 * (2.0 * hash3(ci, cj, ck, seed + 32) - 1.0);
	float dx = (pa - float(ci)) - cx; float dy = (pb - float(cj)) - cy;
	float e = sqrt(dx * dx + dy * dy);
	float present = hash3(ci, cj, ck, seed + 34) < pore_p * ewz ? 1.0 : 0.0;
	pore = mix(0.09, present * (1.0 - sst(0.2, 0.32, e)), blp);
	tone *= 1.0 - 0.45 * pore;
	ray = 0.0;
	if (rho0 > 4.0) {
		float th = atan(b2, a2);
		float dth = 6.283185307179586 / float(RAY_SLOTS);
		int k0 = int(floor(th / dth));
		for (int dk = -2; dk <= 2; dk++) {
			int k = k0 + dk;
			if (hash3(k, 0, 0, seed + 41) >= ray_dens) { continue; }
			float cth = (float(k) + 0.5 + 0.8 * (hash3(k, 1, 0, seed + 43) - 0.5)) * dth;
			float dd = th - cth;
			if (cos(dd) <= 0.0) { continue; }
			float wk = 0.12 + 0.45 * hash3(k, 2, 0, seed + 44);
			float lat = abs(rho0 * sin(dd));
			if (lat >= 0.5 * wk) { continue; }
			float hk = 14.0 + 40.0 * hash3(k, 3, 0, seed + 45);
			int zi = int(floor((t + hash3(k, 4, 0, seed + 46) * hk) / hk));
			if (hash3(k, zi, 7, seed + 47) >= 0.6) { continue; }
			float lr = 22.0;
			int ri = int(floor((rho0 + hash3(k, 5, 0, seed + 48) * lr) / lr));
			if (hash3(k, ri, 9, seed + 53) >= 0.7) { continue; }
			ray = max(ray, 1.0 - sst(0.3 * wk, 0.5 * wk, lat));
		}
	}
	ray = mix(0.04, ray, blp);
	tone *= 1.0 + 0.2 * ray;
	tone *= mix(1.0, 0.94 + 0.12 * vnoise(a / 0.45, b / 0.45, t / 18.0, seed + 61), blp);
	tone *= 0.93 + 0.14 * vnoise(q.x / 40.0, q.y / 40.0, q.z / 40.0, seed + 67);
	return vec4(clamp(EW * tone, 0.0, 1.0), g);
}

vec3 s2l(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }

void vertex() { lp = VERTEX * 1000.0; ln = NORMAL; }

void fragment() {
	float pore; float ray; float bl;
	vec4 w = wood(lp, pore, ray, bl);
	if (mode == 0) {
		// end grain (the face normal along the board's own axis) is darker and thirstier than side grain: keyed from the field's axis, not a face id
		float endness = smoothstep(0.55, 0.85, abs(dot(normalize(ln), normalize(ax_w))));
		ALBEDO = s2l(w.xyz) * mix(1.0, 0.68, endness);
		// the grain catches light: pores are dimples, the latewood a faint ridge (a bump from the field's own derivatives), an oiled finish on top
		float lwv = mix(0.31, smoothstep(0.45, 0.93, fract(w.w)), bl);
		float hh = -(pore * 0.06 + lwv * 0.03) * 0.001;
		vec3 dpx = dFdx(VERTEX); vec3 dpy = dFdy(VERTEX);
		float dhx = dFdx(hh); float dhy = dFdy(hh);
		vec3 r1 = cross(dpy, NORMAL); vec3 r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		NORMAL = normalize(abs(det) * NORMAL - bump * grad);
		ROUGHNESS = 0.38 + 0.3 * pore + 0.12 * lwv + 0.2 * endness;
		SPECULAR = 0.55;
		CLEARCOAT = 0.35;
		CLEARCOAT_ROUGHNESS = 0.28;
	} else {
		vec3 c = w.xyz;
		if (mode == 2) {
			float ph = 6.283185307179586 * w.w;
			c = vec3(0.5 + 0.5 * sin(ph), 0.5 + 0.5 * cos(ph), 0.0);
		}
		ALBEDO = vec3(0.0);
		EMISSION = s2l(c);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
}
