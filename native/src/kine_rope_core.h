#pragma once
// kine_rope_core.h: CH6 rope. A particle chain (radius r, spacing ds) solved by position-based dynamics:
// stretch + weak bend constraints, capsule-capsule self contact and rope-vs-capsule contact (pegs, a capstan cylinder, finger
// capsules) with accumulated Coulomb friction (the friction correction is capped by mu times the normal correction accumulated
// in the substep, so a rope on a fixed cylinder holds T2/T1 = exp(mu theta)). Plain C++ (no Godot types) so a standalone
// harness can drive it; scripts/rope_sim.gd mirrors the arithmetic in float32 order for the C++-vs-GDScript bar.
#include <algorithm>
#include <cmath>
#include <vector>

namespace kr {

struct V {
	float x = 0, y = 0, z = 0;
};
inline V operator+(V a, V b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V operator-(V a, V b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V operator*(V a, float s) { return { a.x * s, a.y * s, a.z * s }; }
inline float dot(V a, V b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline float len(V a) { return std::sqrt(dot(a, a)); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

// closest points of segments p1q1 and p2q2: parameters s, t in [0,1]
inline void closest_segs(V p1, V q1, V p2, V q2, float &s, float &t) {
	V d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
	float a = dot(d1, d1), e = dot(d2, d2), f = dot(d2, r);
	s = 0.0f;
	t = 0.0f;
	if (a <= 1e-14f && e <= 1e-14f) return;
	if (a <= 1e-14f) {
		t = clampf(f / e, 0.0f, 1.0f);
	} else {
		float c = dot(d1, r);
		if (e <= 1e-14f) {
			s = clampf(-c / a, 0.0f, 1.0f);
		} else {
			float b = dot(d1, d2);
			float den = a * e - b * b;
			if (den > 1e-14f) s = clampf((b * f - c * e) / den, 0.0f, 1.0f);
			t = (b * s + f) / e;
			if (t < 0.0f) {
				t = 0.0f;
				s = clampf(-c / a, 0.0f, 1.0f);
			} else if (t > 1.0f) {
				t = 1.0f;
				s = clampf((b - c) / a, 0.0f, 1.0f);
			}
		}
	}
}

struct Col {
	V a0, b0, a1, b1; // capsule axis at the start and the end of the frame
	float r = 0.01f;
	float mu = 0.4f;
};

struct Pair {
	int i, j;
	float s, t;
	float lam; // accumulated normal correction (m)
	V fric; // accumulated friction correction (m)
	V da0, db0; // unused
};
struct CPair {
	int i, k;
	float s, u;
	float lam;
	V fric;
};

struct Rope {
	int n = 0;
	float ds = 0.008f, r = 0.004f;
	float mu = 0.4f; // rope on rope
	float kb = 0.01f; // bend stiffness (0..1 per iteration)
	float grav = 0.0f; // m/s^2 downward (-y)
	float damp = 0.995f; // velocity factor per substep
	float alpha = 0.0f; // stretch compliance (m/N); 0 = hard
	int iters = 12, subs = 8;
	int skip = 3; // self contact skips |i-j| < skip
	std::vector<V> x, xo, v, p, tg0, tg1, ext;
	std::vector<float> w;
	std::vector<char> drv;
	std::vector<Col> cols;
	std::vector<float> lam_s; // stretch multipliers (XPBD) -> tension
	std::vector<Pair> pairs;
	std::vector<CPair> cpairs;
	float mass = 0.0004f; // per particle (kg)
	int contacts_self = 0;
	float max_tension = 0.0f;

	void init(const std::vector<V> &pts, float ds_, float r_) {
		n = (int)pts.size();
		ds = ds_;
		r = r_;
		x = pts;
		xo = pts;
		p = pts;
		v.assign(n, V());
		tg0 = pts;
		tg1 = pts;
		ext.assign(n, V());
		w.assign(n, 1.0f / mass);
		drv.assign(n, 0);
		lam_s.assign(n, 0.0f);
	}

	void drive(int i, V a, V b) {
		drv[i] = 1;
		tg0[i] = a;
		tg1[i] = b;
	}
	void undrive(int i) { drv[i] = 0; }

	void collect(float margin) {
		pairs.clear();
		float lim = ds + 2.0f * r + margin;
		float lim2 = lim * lim;
		for (int i = 0; i < n - 1; i++) {
			V mi = (p[i] + p[i + 1]) * 0.5f;
			for (int j = i + skip; j < n - 1; j++) {
				V d = mi - (p[j] + p[j + 1]) * 0.5f;
				if (dot(d, d) > lim2) continue;
				Pair q;
				q.i = i;
				q.j = j;
				closest_segs(p[i], p[i + 1], p[j], p[j + 1], q.s, q.t);
				q.lam = 0;
				pairs.push_back(q);
			}
		}
		cpairs.clear();
		for (int k = 0; k < (int)cols.size(); k++) {
			const Col &c = cols[k];
			for (int i = 0; i < n - 1; i++) {
				float s, u;
				closest_segs(p[i], p[i + 1], c.a1, c.b1, s, u);
				V cs = p[i] + (p[i + 1] - p[i]) * s;
				V cc = c.a1 + (c.b1 - c.a1) * u;
				if (len(cs - cc) > r + c.r + margin) continue;
				CPair q;
				q.i = i;
				q.k = k;
				q.s = s;
				q.u = u;
				q.lam = 0;
				cpairs.push_back(q);
			}
		}
	}

	void step(float dt) {
		float h = dt / (float)subs;
		float al = alpha / (h * h);
		for (int sb = 0; sb < subs; sb++) {
			float f0 = (float)sb / (float)subs, f1 = (float)(sb + 1) / (float)subs;
			for (int i = 0; i < n; i++) {
				xo[i] = x[i];
				if (drv[i]) {
					p[i] = tg0[i] + (tg1[i] - tg0[i]) * f1;
					v[i] = V();
					continue;
				}
				V a = ext[i] * w[i];
				a.y -= grav;
				v[i] = (v[i] + a * h) * damp;
				p[i] = x[i] + v[i] * h;
			}
			for (int i = 0; i < n; i++) lam_s[i] = 0;
			// collider poses of this substep
			std::vector<Col> save;
			if (!cols.empty()) {
				save = cols;
				for (auto &c : cols) {
					V da = c.a1 - c.a0, db = c.b1 - c.b0;
					c.a0 = c.a0 + da * f0;
					c.b0 = c.b0 + db * f0;
					c.a1 = save[&c - &cols[0]].a0 + da * f1;
					c.b1 = save[&c - &cols[0]].b0 + db * f1;
				}
			}
			collect(0.004f);
			for (int it = 0; it < iters; it++) {
				// stretch (alternate sweep direction)
				for (int q = 0; q < n - 1; q++) {
					int i = (it & 1) ? n - 2 - q : q;
					V d = p[i + 1] - p[i];
					float l = len(d);
					if (l < 1e-9f) continue;
					float wsum = w[i] + w[i + 1];
					if (wsum == 0) continue;
					float C = l - ds;
					float dl = (-C - al * lam_s[i]) / (wsum + al);
					lam_s[i] += dl;
					V g = d * (1.0f / l);
					p[i] = p[i] - g * (dl * w[i]);
					p[i + 1] = p[i + 1] + g * (dl * w[i + 1]);
				}
				// bend: ends of every 3 particles pulled toward 2 ds
				if (kb > 0) {
					for (int i = 0; i < n - 2; i++) {
						V d = p[i + 2] - p[i];
						float l = len(d);
						if (l < 1e-9f) continue;
						float wsum = w[i] + w[i + 2];
						if (wsum == 0) continue;
						float C = l - 2.0f * ds;
						float c = -C * kb / wsum;
						V g = d * (1.0f / l);
						p[i] = p[i] - g * (c * w[i]);
						p[i + 2] = p[i + 2] + g * (c * w[i + 2]);
					}
				}
				solve_self(h);
				solve_cols(h);
			}
			for (int i = 0; i < n; i++) {
				if (drv[i]) { x[i] = p[i]; continue; }
				v[i] = (p[i] - xo[i]) * (1.0f / h);
				x[i] = p[i];
			}
			if (!save.empty()) cols = save;
			contacts_self = 0;
			for (auto &q : pairs) if (q.lam > 0) contacts_self++;
			(void)f0;
		}
		// tension readout of the last substep: lambda / h^2 (N) of the first stretch constraint
		max_tension = 0;
		float hh = dt / (float)subs;
		for (int i = 0; i < n - 1; i++) max_tension = std::max(max_tension, std::fabs(lam_s[i]) / (hh * hh));
	}

	void solve_self(float h) {
		(void)h;
		for (auto &q : pairs) {
			int i = q.i, j = q.j;
			float s, t;
			closest_segs(p[i], p[i + 1], p[j], p[j + 1], s, t);
			V ca = p[i] + (p[i + 1] - p[i]) * s;
			V cb = p[j] + (p[j + 1] - p[j]) * t;
			V d = ca - cb;
			float dl = len(d);
			float W = w[i] * (1 - s) * (1 - s) + w[i + 1] * s * s + w[j] * (1 - t) * (1 - t) + w[j + 1] * t * t;
			if (W == 0) continue;
			V nrm;
			if (dl < 1e-9f) {
				V ax = p[i + 1] - p[i];
				nrm = V{ -ax.y, ax.x, 0.0f };
				float nl = len(nrm);
				nrm = nl > 1e-9f ? nrm * (1.0f / nl) : V{ 0, 0, 1 };
			} else nrm = d * (1.0f / dl);
			float pen = 2.0f * r - dl;
			if (pen > 0) {
				q.lam += pen;
				apply(i, j, s, t, nrm * (pen / W), W);
			}
			if (q.lam > 0 && mu > 0) {
				// relative displacement of the contact material points since the substep start
				V dA = (p[i] - xo[i]) * (1 - q.s) + (p[i + 1] - xo[i + 1]) * q.s;
				V dB = (p[j] - xo[j]) * (1 - q.t) + (p[j + 1] - xo[j + 1]) * q.t;
				V rel = dA - dB;
				V ut = rel - nrm * dot(rel, nrm);
				V want = q.fric - ut; // accumulated friction that would stop the slide
				float wl = len(want), cap = mu * q.lam;
				if (wl > cap) want = want * (cap / wl);
				V dF = want - q.fric;
				q.fric = want;
				// friction moves the contact points at fixed (q.s, q.t)
				float Wf = w[i] * (1 - q.s) * (1 - q.s) + w[i + 1] * q.s * q.s + w[j] * (1 - q.t) * (1 - q.t) + w[j + 1] * q.t * q.t;
				if (Wf > 0) apply(i, j, q.s, q.t, dF * (1.0f / Wf), Wf);
			}
		}
	}
	// move contact point A by +corr*..., B by -corr (weights of this contact)
	void apply(int i, int j, float s, float t, V c, float) {
		p[i] = p[i] + c * (w[i] * (1 - s));
		p[i + 1] = p[i + 1] + c * (w[i + 1] * s);
		p[j] = p[j] - c * (w[j] * (1 - t));
		p[j + 1] = p[j + 1] - c * (w[j + 1] * t);
	}

	void solve_cols(float h) {
		(void)h;
		for (auto &q : cpairs) {
			const Col &c = cols[q.k];
			int i = q.i;
			float s, u;
			closest_segs(p[i], p[i + 1], c.a1, c.b1, s, u);
			V ca = p[i] + (p[i + 1] - p[i]) * s;
			V cc = c.a1 + (c.b1 - c.a1) * u;
			V d = ca - cc;
			float dl = len(d);
			float W = w[i] * (1 - s) * (1 - s) + w[i + 1] * s * s;
			if (W == 0) continue;
			float R = r + c.r;
			V nrm = dl < 1e-9f ? V{ 0, 0, 1 } : d * (1.0f / dl);
			float pen = R - dl;
			if (pen > 0) {
				q.lam += pen;
				V corr = nrm * (pen / W);
				p[i] = p[i] + corr * (w[i] * (1 - s));
				p[i + 1] = p[i + 1] + corr * (w[i + 1] * s);
			}
			float mu_c = std::min(mu, c.mu);
			if (q.lam > 0 && mu_c > 0) {
				// collider contact point moves with the axis (fixed parameter u)
				V cm0 = c.a0 + (c.b0 - c.a0) * q.u; // not used: the pose is already interpolated per substep
				(void)cm0;
				V dA = (p[i] - xo[i]) * (1 - q.s) + (p[i + 1] - xo[i + 1]) * q.s;
				V colmove = (c.a1 - c.a0) * (1 - q.u) + (c.b1 - c.b0) * q.u;
				V rel = dA - colmove;
				V ut = rel - nrm * dot(rel, nrm);
				V want = q.fric - ut;
				float wl = len(want), cap = mu_c * q.lam;
				if (wl > cap) want = want * (cap / wl);
				V dF = want - q.fric;
				q.fric = want;
				float Wf = w[i] * (1 - q.s) * (1 - q.s) + w[i + 1] * q.s * q.s;
				if (Wf > 0) {
					V corr = dF * (1.0f / Wf);
					p[i] = p[i] + corr * (w[i] * (1 - q.s));
					p[i + 1] = p[i + 1] + corr * (w[i + 1] * q.s);
				}
			}
		}
	}

	// brute-force clearance: largest penetration (m) between non-adjacent segments (|i-j| >= skip) and against each collider
	float max_self_pen() const {
		float m = 0;
		for (int i = 0; i < n - 1; i++)
			for (int j = i + skip; j < n - 1; j++) {
				float s, t;
				closest_segs(x[i], x[i + 1], x[j], x[j + 1], s, t);
				V a = x[i] + (x[i + 1] - x[i]) * s, b = x[j] + (x[j + 1] - x[j]) * t;
				m = std::max(m, 2.0f * r - len(a - b));
			}
		return m;
	}
	float max_col_pen(const std::vector<Col> &cs, const std::vector<char> *skipmask = nullptr) const {
		float m = 0;
		for (auto &c : cs)
			for (int i = 0; i < n - 1; i++) {
				if (skipmask && (*skipmask)[i]) continue;
				float s, u;
				closest_segs(x[i], x[i + 1], c.a1, c.b1, s, u);
				V a = x[i] + (x[i + 1] - x[i]) * s, b = c.a1 + (c.b1 - c.a1) * u;
				m = std::max(m, r + c.r - len(a - b));
			}
		return m;
	}
};

} // namespace kr
