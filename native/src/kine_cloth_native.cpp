#include "kine_cloth_native.h"

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {

struct V3 {
	float x, y, z;
};

inline V3 sub(const V3 &a, const V3 &b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 add(const V3 &a, const V3 &b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 mul(const V3 &a, double s) { float f = (float)s; return { a.x * f, a.y * f, a.z * f }; }
inline V3 divd(const V3 &a, double s) { float f = (float)s; return { a.x / f, a.y / f, a.z / f }; }
inline float dot(const V3 &a, const V3 &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline float len(const V3 &a) { return std::sqrt(a.x * a.x + a.y * a.y + a.z * a.z); }
inline float len2(const V3 &a) { return a.x * a.x + a.y * a.y + a.z * a.z; }

// Vector3.lerp(to, w): x + (w * (to.x - x)) with w as float32
inline V3 lerp3(const V3 &a, const V3 &b, double w) {
	float f = (float)w;
	return { a.x + (f * (b.x - a.x)), a.y + (f * (b.y - a.y)), a.z + (f * (b.z - a.z)) };
}

inline V3 rd(const PackedVector3Array &a, int i) {
	Vector3 v = a[i];
	return { v.x, v.y, v.z };
}

void lerp_into(const Array &F, double u, std::vector<V3> &out) {
	int fs = F.size();
	double f = std::min(std::max(u, 0.0), (double)(fs - 1));
	int i0 = (int)std::floor(f);
	int i1 = std::min(i0 + 1, fs - 1);
	double a = f - (double)i0;
	PackedVector3Array A = F[i0];
	int n = (int)out.size();
	if (a <= 0.0 || i1 == i0) {
		for (int k = 0; k < n; k++) out[k] = rd(A, k);
		return;
	}
	PackedVector3Array B = F[i1];
	for (int k = 0; k < n; k++) out[k] = lerp3(rd(A, k), rd(B, k), a);
}

} // namespace

void KineClothNative::_bind_methods() {
	ClassDB::bind_static_method("KineClothNative", D_METHOD("version"), &KineClothNative::version);
	ClassDB::bind_static_method("KineClothNative",
			D_METHOD("run", "x", "v", "A", "C", "rads", "E", "rest", "pinned", "nsub", "pre", "m_from", "m_to", "dt", "iter", "grav", "drag", "margin", "cand_pad"),
			&KineClothNative::run);
}

int KineClothNative::version() {
	return 1;
}

Array KineClothNative::run(const PackedVector3Array &p_x, const PackedVector3Array &p_v, const Array &p_A, const Array &p_C,
		const PackedFloat64Array &p_rads, const PackedInt32Array &p_E, const PackedFloat64Array &p_rest, const PackedByteArray &p_pinned,
		int p_nsub, int p_pre, int p_m_from, int p_m_to, double p_dt, int p_iter, double p_grav, double p_drag, double p_margin,
		double p_cand_pad) {
	const int N = (int)p_x.size();
	const int nparts = (int)p_rads.size();
	const int ne = (int)(p_E.size() / 2);
	std::vector<V3> x(N), v(N), p(N);
	for (int i = 0; i < N; i++) {
		x[i] = rd(p_x, i);
		v[i] = rd(p_v, i);
		// GDScript's p is zero before the first substep and equals x after every substep
		p[i] = p_m_from > 0 ? x[i] : V3{ 0, 0, 0 };
	}
	std::vector<int> E(p_E.size());
	for (int i = 0; i < (int)E.size(); i++) E[i] = p_E[i];
	std::vector<double> rest(ne), rads(nparts);
	for (int i = 0; i < ne; i++) rest[i] = p_rest[i];
	for (int i = 0; i < nparts; i++) rads[i] = p_rads[i];
	std::vector<unsigned char> pinned(N);
	for (int i = 0; i < N; i++) pinned[i] = p_pinned[i];

	PackedVector3Array first = p_A.size() > 0 ? (PackedVector3Array)p_A[0] : PackedVector3Array();
	std::vector<V3> pins(first.size()), capn(2 * nparts);
	std::vector<int> nearv(std::max(nparts, 1));
	std::vector<int> cand;
	cand.reserve(2 * (size_t)N * (size_t)std::max(nparts, 1));

	Array frames;
	const double drag = 1.0 - p_drag * p_dt;
	const V3 gdt = { 0.0f, (float)(-p_grav * p_dt), 0.0f };

	for (int m = p_m_from + 1; m <= p_m_to; m++) {
		double u = (double)m / (double)p_nsub - (double)p_pre;
		lerp_into(p_A, u, pins);
		lerp_into(p_C, u, capn);

		// _near
		int nnear = 0;
		{
			float lox = INFINITY, loy = INFINITY, loz = INFINITY, hix = -INFINITY, hiy = -INFINITY, hiz = -INFINITY;
			for (int i = 0; i < N; i++) {
				lox = std::min(lox, p[i].x); loy = std::min(loy, p[i].y); loz = std::min(loz, p[i].z);
				hix = std::max(hix, p[i].x); hiy = std::max(hiy, p[i].y); hiz = std::max(hiz, p[i].z);
			}
			const float pad = (float)0.08;
			lox -= pad; loy -= pad; loz -= pad; hix += pad; hiy += pad; hiz += pad;
			for (int k = 0; k < nparts; k++) {
				const V3 &a = capn[2 * k];
				const V3 &b = capn[2 * k + 1];
				double r = rads[k] + p_margin;
				if (((double)std::min(a.x, b.x) - r) > (double)hix || ((double)std::max(a.x, b.x) + r) < (double)lox) continue;
				if (((double)std::min(a.y, b.y) - r) > (double)hiy || ((double)std::max(a.y, b.y) + r) < (double)loy) continue;
				if (((double)std::min(a.z, b.z) - r) > (double)hiz || ((double)std::max(a.z, b.z) + r) < (double)loz) continue;
				nearv[nnear++] = k;
			}
		}
		// _candidates (uses p from the previous substep, as the GDScript does)
		cand.clear();
		for (int i = 0; i < N; i++) {
			if (pinned[i] == 1) continue;
			const V3 q = p[i];
			for (int kk = 0; kk < nnear; kk++) {
				int c = nearv[kk];
				const V3 &a = capn[2 * c];
				const V3 &b = capn[2 * c + 1];
				double r = rads[c] + p_margin + p_cand_pad;
				if ((double)q.x < (double)std::min(a.x, b.x) - r || (double)q.x > (double)std::max(a.x, b.x) + r) continue;
				if ((double)q.y < (double)std::min(a.y, b.y) - r || (double)q.y > (double)std::max(a.y, b.y) + r) continue;
				if ((double)q.z < (double)std::min(a.z, b.z) - r || (double)q.z > (double)std::max(a.z, b.z) + r) continue;
				cand.push_back(i);
				cand.push_back(c);
			}
		}
		const int ncand = (int)(cand.size() / 2);

		// _substep
		for (int i = 0; i < N; i++) {
			if (pinned[i] == 1) {
				p[i] = pins[i];
				v[i] = { 0, 0, 0 };
			} else {
				v[i] = add(mul(v[i], drag), gdt);
				p[i] = add(x[i], mul(v[i], p_dt));
			}
		}
		for (int it = 0; it < p_iter; it++) {
			for (int kq = 0; kq < ne; kq++) {
				int k = (it % 2 == 0) ? kq : ne - 1 - kq;
				int i = E[2 * k];
				int j = E[2 * k + 1];
				double wi = pinned[i] == 1 ? 0.0 : 1.0;
				double wj = pinned[j] == 1 ? 0.0 : 1.0;
				double ws = wi + wj;
				if (ws <= 0.0) continue;
				V3 d = sub(p[j], p[i]);
				double L = (double)len(d);
				if (L < 1e-12) continue;
				V3 corr = mul(d, (L - rest[k]) / L);
				p[i] = add(p[i], mul(corr, wi / ws));
				p[j] = sub(p[j], mul(corr, wj / ws));
			}
			for (int kc = 0; kc < ncand; kc++) {
				int i = cand[2 * kc];
				int c = cand[2 * kc + 1];
				const V3 ka = capn[2 * c];
				const V3 ab = sub(capn[2 * c + 1], ka);
				double t = (double)dot(sub(p[i], ka), ab) / std::max((double)len2(ab), 1e-12);
				t = std::min(std::max(t, 0.0), 1.0);
				V3 cp = add(ka, mul(ab, t));
				V3 dv = sub(p[i], cp);
				double dist = (double)len(dv);
				double rr = rads[c] + p_margin;
				if (dist < rr) {
					V3 nrm = dist > 1e-9 ? divd(dv, dist) : V3{ 0.0f, 1.0f, 0.0f };
					p[i] = add(cp, mul(nrm, rr));
				}
			}
		}
		for (int i = 0; i < N; i++) {
			if (pinned[i] == 0) {
				v[i] = divd(sub(p[i], x[i]), p_dt);
			}
			x[i] = p[i];
		}

		if (m % p_nsub == 0) {
			int k = m / p_nsub - p_pre;
			if (k >= 0) {
				PackedVector3Array f;
				f.resize(N);
				for (int i = 0; i < N; i++) f[i] = Vector3(x[i].x, x[i].y, x[i].z);
				frames.push_back(f);
			}
		}
	}

	PackedVector3Array ox, ov;
	ox.resize(N);
	ov.resize(N);
	for (int i = 0; i < N; i++) {
		ox[i] = Vector3(x[i].x, x[i].y, x[i].z);
		ov[i] = Vector3(v[i].x, v[i].y, v[i].z);
	}
	Array out;
	out.push_back(ox);
	out.push_back(ov);
	out.push_back(frames);
	return out;
}
