shader_type canvas_item;
// L31 screen-space fluid, step 2: smoothing of the depth image. Texel layout: r = high part of the depth (normalised, see water_ssf_depth), g = 0 off water, 1 + low part on water, b = optical thickness (m): depth = r + (g - 1) / 1024.
// (A half float cannot hold a depth that is later differentiated into a normal: its steps on a glass are 0.03 mm against a 0.2 mm pixel, which showed as a comb on every
// refracted edge. The depth is therefore split in two halves and decoded to full float inside the filter.)
// mode 0: pack the depth pass and the thickness pass. mode 1: one pass of a SEPARABLE NARROW-RANGE BILATERAL filter along dir (Green 2010, "Screen Space Fluid
// Rendering for Games", GDC; the bilateral of Tomasi and Manduchi 1998). The spatial sigma is a WORLD length turned into pixels at the pixel's own depth, so a drop
// far away is smoothed over as many millimetres as a near one. The range sigma (metres of depth) stops it at silhouettes and at real steps in the surface.
// Only water texels are averaged; the thickness is smoothed with the same weights, so the two stay consistent.
render_mode blend_disabled;

uniform sampler2D src : filter_nearest, repeat_disable;
uniform sampler2D thick_tex : filter_nearest, repeat_disable;
uniform int mode = 1;
uniform vec2 dir = vec2(1.0, 0.0);
uniform float z0 = 0.0;
uniform float zr = 1.0;
uniform float pix_per_m = 1000.0;   // pixels per metre at 1 m distance = height / (2 tan(fov / 2))
uniform float sigma_w = 0.006;      // spatial sigma, metres
uniform float sigma_r = 0.008;      // range sigma, metres of depth
uniform float tmax = 0.2;           // a thickness outside 0..tmax is a ray through a crack of the mesh, not water: it is left out of the average

const int MAXR = 40;

float dec(vec4 c) {
	return c.r + (c.g - 1.0) / 1024.0;
}

vec4 enc(float v, float t) {
	float hi = floor(v * 1024.0) / 1024.0;
	return vec4(hi, 1.0 + (v - hi) * 1024.0, t, 1.0);
}

void fragment() {
	vec4 c = textureLod(src, UV, 0.0);
	if (mode == 0) {
		vec2 px0 = 1.0 / vec2(textureSize(src, 0));
		vec4 tc = textureLod(thick_tex, UV, 0.0);
		if (c.g > 0.5) {
			COLOR = vec4(c.r, 1.0 + c.b, tc.r, 1.0);
		} else if (tc.g > 0.5) {
			// a crack in the surface mesh: the thickness pass covers the pixel, the front-face depth pass does not. Fill it from the 5x5 window when most of it is water.
			float n = 0.0;
			float dsum = 0.0;
			float tsum = 0.0;
			for (int j = -2; j <= 2; j++) {
				for (int i = -2; i <= 2; i++) {
					vec2 uv = UV + vec2(float(i), float(j)) * px0;
					vec4 s0 = textureLod(src, uv, 0.0);
					float t0 = textureLod(thick_tex, uv, 0.0).r;
					if (s0.g > 0.5 && t0 >= 0.0 && t0 <= tmax) {
						n += 1.0;
						dsum += s0.r + s0.b / 1024.0;
						tsum += t0;
					}
				}
			}
			if (n >= 14.0) {
				COLOR = enc(dsum / n, tsum / n);
			} else {
				COLOR = vec4(0.0, 0.0, 0.0, 1.0);
			}
		} else {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
	} else {
		if (c.g < 0.5) {
			COLOR = c;
		} else {
			vec2 px = 1.0 / vec2(textureSize(src, 0));
			float vc = dec(c);
			float dc = vc * zr + z0;
			float sp = max(sigma_w * pix_per_m / dc, 0.5);
			int R = min(int(ceil(2.5 * sp)), MAXR);
			bool cvalid = c.b >= 0.0 && c.b <= tmax;
			float ws = 1.0;
			float ds = 0.0;   // sum of w * (v - vc): the offsets stay small, so full float precision survives
			float wt = cvalid ? 1.0 : 0.0;
			float ts = cvalid ? c.b : 0.0;
			for (int i = -MAXR; i <= MAXR; i++) {
				if (i == 0 || abs(i) > R) {
					continue;
				}
				vec4 s = textureLod(src, UV + dir * float(i) * px, 0.0);
				if (s.g < 0.5) {
					continue;
				}
				float dd = (dec(s) - vc) * zr;
				float w = exp(-0.5 * float(i * i) / (sp * sp) - 0.5 * dd * dd / (sigma_r * sigma_r));
				ws += w;
				ds += w * (dec(s) - vc);
				if (s.b >= 0.0 && s.b <= tmax) {
					wt += w;
					ts += w * s.b;
				}
			}
			COLOR = enc(vc + ds / ws, wt > 0.0 ? ts / wt : 0.0);
		}
	}
}
