#include "kine_skin_native.h"

#include <cmath>

using namespace godot;

namespace {
struct V3 {
	double x = 0, y = 0, z = 0;
};
inline V3 mk(const Vector3 &v) { return { v.x, v.y, v.z }; }
inline V3 operator+(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 operator-(V3 a, V3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 operator*(V3 a, double s) { return { a.x * s, a.y * s, a.z * s }; }
inline double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(V3 a, V3 b) { return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x }; }
inline V3 nrm(V3 a) {
	double l = std::sqrt(dot(a, a));
	return l > 0.0 ? a * (1.0 / l) : V3();
}
inline V3 lerp(V3 a, V3 b, double t) { return a + (b - a) * t; }

// a 3x3 matrix stored as its three columns
struct B3 {
	V3 c[3];
	V3 mul(V3 v) const { return c[0] * v.x + c[1] * v.y + c[2] * v.z; }
	double det() const { return dot(c[0], cross(c[1], c[2])); }
	B3 inverse() const {
		double id = 1.0 / det();
		V3 r0 = cross(c[1], c[2]) * id;
		V3 r1 = cross(c[2], c[0]) * id;
		V3 r2 = cross(c[0], c[1]) * id;
		B3 o;
		o.c[0] = { r0.x, r1.x, r2.x };
		o.c[1] = { r0.y, r1.y, r2.y };
		o.c[2] = { r0.z, r1.z, r2.z };
		return o;
	}
	B3 transposed() const {
		B3 o;
		o.c[0] = { c[0].x, c[1].x, c[2].x };
		o.c[1] = { c[0].y, c[1].y, c[2].y };
		o.c[2] = { c[0].z, c[1].z, c[2].z };
		return o;
	}
};

struct Q {
	double x, y, z, w;
};
inline Q qmul(Q a, Q b) {
	return { a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
		a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x, a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z };
}
inline Q qinv(Q a) {
	double l2 = a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w;
	return { -a.x / l2, -a.y / l2, -a.z / l2, a.w / l2 };
}
inline V3 qrot(Q q, V3 v) {
	V3 u = { q.x, q.y, q.z };
	V3 uv = cross(u, v);
	return v + ((uv * q.w) + cross(u, uv)) * 2.0;
}
} // namespace

void KineSkinNative::_bind_methods() {
	ClassDB::bind_static_method("KineSkinNative", D_METHOD("version"), &KineSkinNative::version);
	ClassDB::bind_static_method("KineSkinNative", D_METHOD("skin_points", "rest", "bo", "w", "per", "mats"), &KineSkinNative::skin_points);
	ClassDB::bind_static_method("KineSkinNative", D_METHOD("points_aabb", "pos", "vix"), &KineSkinNative::points_aabb);
	ClassDB::bind_static_method("KineSkinNative", D_METHOD("correct", "vs", "nn", "nt", "bo", "w", "fr", "k", "multi", "msk"), &KineSkinNative::correct);
}

int KineSkinNative::version() { return 2; }

PackedVector3Array KineSkinNative::skin_points(const PackedVector3Array &p_rest, const PackedInt32Array &p_bo, const PackedFloat32Array &p_w,
		int per, const PackedVector3Array &p_mats) {
	PackedVector3Array out;
	int64_t n = p_rest.size();
	out.resize(n);
	int64_t nm = p_mats.size() / 4;
	if (per < 1 || p_bo.size() < n * per || p_w.size() < n * per) {
		return out;
	}
	const Vector3 *rest = p_rest.ptr();
	const int32_t *bo = p_bo.ptr();
	const float *w = p_w.ptr();
	const Vector3 *mt = p_mats.ptr();
	Vector3 *o = out.ptrw();
	for (int64_t i = 0; i < n; i++) {
		V3 v = mk(rest[i]);
		V3 p;
		for (int q = 0; q < per; q++) {
			double x = w[i * per + q];
			if (x > 0.0) {
				int64_t b = bo[i * per + q];
				if (b < 0 || b >= nm) {
					continue;
				}
				const Vector3 *m = mt + b * 4;
				V3 t = mk(m[0]) * v.x + mk(m[1]) * v.y + mk(m[2]) * v.z + mk(m[3]);
				p = p + t * x;
			}
		}
		o[i] = Vector3((real_t)p.x, (real_t)p.y, (real_t)p.z);
	}
	return out;
}

AABB KineSkinNative::points_aabb(const PackedVector3Array &p_pos, const PackedInt32Array &p_vix) {
	if (p_vix.size() == 0) {
		return AABB();
	}
	const Vector3 *pos = p_pos.ptr();
	const int32_t *vix = p_vix.ptr();
	Vector3 lo = pos[vix[0]], hi = lo;
	for (int64_t i = 1; i < p_vix.size(); i++) {
		const Vector3 &p = pos[vix[i]];
		lo = Vector3(std::fmin(lo.x, p.x), std::fmin(lo.y, p.y), std::fmin(lo.z, p.z));
		hi = Vector3(std::fmax(hi.x, p.x), std::fmax(hi.y, p.y), std::fmax(hi.z, p.z));
	}
	return AABB(lo, hi - lo);
}

Dictionary KineSkinNative::correct(const PackedVector3Array &p_vs, const PackedVector3Array &p_nn, const PackedFloat32Array &p_nt,
		const PackedInt32Array &p_bo, const PackedFloat32Array &p_w, const Dictionary &fr, double k,
		const PackedInt32Array &p_multi, const PackedFloat32Array &p_msk) {
	const double EPS = 1e-6, DET_MIN = 1e-6;
	const int nvert = p_vs.size();
	const int per = nvert > 0 ? p_bo.size() / nvert : 0;
	const bool has_n = p_nn.size() == nvert && nvert > 0;
	const bool has_t = p_nt.size() == nvert * 4 && nvert > 0;
	const bool use_m = p_msk.size() == nvert;
	PackedVector3Array nv = p_vs;
	PackedVector3Array nn = p_nn;
	PackedFloat32Array nt = p_nt;
	int cnt = 0, sing = 0;
	PackedVector3Array FX = fr["bx"], FY = fr["by"], FZ = fr["bz"], FO = fr["bo"], SX = fr["sx"], SY = fr["sy"], SZ = fr["sz"];
	PackedFloat32Array R = fr["r"], D = fr["d"];
	PackedByteArray RIG = fr["rig"];
	const Vector3 *vs = p_vs.ptr();
	const int32_t *bo = p_bo.ptr();
	const float *w = p_w.ptr();
	const float *R_ = R.ptr();
	const float *D_ = D.ptr();
	const Vector3 *fx = FX.ptr(), *fy = FY.ptr(), *fz = FZ.ptr(), *fo = FO.ptr(), *sx_ = SX.ptr(), *sy_ = SY.ptr(), *sz_ = SZ.ptr();
	const uint8_t *rig = RIG.ptr();
	if (nvert > 0 && per > 0) {
		Vector3 *wv = nv.ptrw();
		Vector3 *wn = has_n ? nn.ptrw() : nullptr;
		float *wt = has_t ? nt.ptrw() : nullptr;
		const Vector3 *on = p_nn.ptr();
		const float *ot = p_nt.ptr();
		const int32_t *mp = p_multi.ptr();
		for (int mi = 0; mi < p_multi.size(); mi++) {
			const int i = mp[mi];
			double kk = k * (use_m ? (double)p_msk[i] : 1.0);
			if (kk <= 0.0) {
				continue;
			}
			const int o = i * per;
			int piv = bo[o];
			double pw = w[o];
			for (int q = 1; q < per; q++) {
				if (w[o + q] > pw) {
					pw = w[o + q];
					piv = bo[o + q];
				}
			}
			const int p4 = piv * 4;
			V3 cx, cy, cz, co, sx, sy, sz;
			double rx = 0, ry = 0, rz = 0, rw = 0, dx = 0, dy = 0, dz = 0, dw = 0, ws = 0;
			bool rigid = true;
			for (int q = 0; q < per; q++) {
				double x = w[o + q];
				if (x <= 0.0) {
					continue;
				}
				const int b = bo[o + q];
				ws += x;
				cx = cx + mk(fx[b]) * x;
				cy = cy + mk(fy[b]) * x;
				cz = cz + mk(fz[b]) * x;
				co = co + mk(fo[b]) * x;
				const int b4 = b * 4;
				double s = ((double)R_[b4] * (double)R_[p4] + (double)R_[b4 + 1] * (double)R_[p4 + 1] + (double)R_[b4 + 2] * (double)R_[p4 + 2] + (double)R_[b4 + 3] * (double)R_[p4 + 3] >= 0.0) ? x : -x;
				rx += R_[b4] * s;
				ry += R_[b4 + 1] * s;
				rz += R_[b4 + 2] * s;
				rw += R_[b4 + 3] * s;
				dx += D_[b4] * s;
				dy += D_[b4 + 1] * s;
				dz += D_[b4 + 2] * s;
				dw += D_[b4 + 3] * s;
				if (rig[b] == 0) {
					rigid = false;
					sx = sx + mk(sx_[b]) * x;
					sy = sy + mk(sy_[b]) * x;
					sz = sz + mk(sz_[b]) * x;
				} else {
					sx = sx + V3{ 1, 0, 0 } * x;
					sy = sy + V3{ 0, 1, 0 } * x;
					sz = sz + V3{ 0, 0, 1 } * x;
				}
			}
			B3 ML;
			ML.c[0] = cx;
			ML.c[1] = cy;
			ML.c[2] = cz;
			const double ln = std::sqrt(rx * rx + ry * ry + rz * rz + rw * rw);
			if (std::fabs(ML.det()) < DET_MIN || ln < 1e-9) {
				sing++;
				continue;
			}
			Q br = { rx / ln, ry / ln, rz / ln, rw / ln };
			Q bd = { dx / ln, dy / ln, dz / ln, dw / ln };
			const V3 v0 = mk(vs[i]);
			V3 v = v0;
			B3 SB;
			SB.c[0] = { 1, 0, 0 };
			SB.c[1] = { 0, 1, 0 };
			SB.c[2] = { 0, 0, 1 };
			if (!rigid) {
				SB.c[0] = sx * (1.0 / ws);
				SB.c[1] = sy * (1.0 / ws);
				SB.c[2] = sz * (1.0 / ws);
				v = SB.mul(v);
			}
			Q tq = qmul(bd, qinv(br));
			V3 p = (qrot(br, v) + V3{ tq.x, tq.y, tq.z } * 2.0) * ws;
			if (kk < 1.0) {
				p = lerp(ML.mul(v0) + co, p, kk);
			}
			B3 bi = ML.inverse();
			V3 v2 = bi.mul(p - co);
			V3 dv = v2 - v0;
			if (dot(dv, dv) < EPS * EPS) {
				continue;
			}
			wv[i] = Vector3((real_t)v2.x, (real_t)v2.y, (real_t)v2.z);
			cnt++;
			if (has_n) {
				V3 n0 = mk(on[i]);
				V3 nd = qrot(br, rigid ? n0 : SB.inverse().transposed().mul(n0));
				V3 r = nrm(bi.mul(lerp(nrm(ML.mul(n0)), nrm(nd), kk)));
				wn[i] = Vector3((real_t)r.x, (real_t)r.y, (real_t)r.z);
			}
			if (has_t) {
				V3 t0 = { ot[i * 4], ot[i * 4 + 1], ot[i * 4 + 2] };
				V3 td = qrot(br, SB.mul(t0));
				V3 t2 = nrm(bi.mul(lerp(nrm(ML.mul(t0)), nrm(td), kk)));
				wt[i * 4] = (float)t2.x;
				wt[i * 4 + 1] = (float)t2.y;
				wt[i * 4 + 2] = (float)t2.z;
			}
		}
	}
	Dictionary out;
	out["v"] = nv;
	out["n"] = nn;
	out["t"] = nt;
	out["cnt"] = cnt;
	out["sing"] = sing;
	return out;
}
