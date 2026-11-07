#include "kine_blend_native.h"

#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <cmath>
#include <vector>

using namespace godot;

void KineBlendNative::_bind_methods() {
	ClassDB::bind_static_method("KineBlendNative", D_METHOD("version"), &KineBlendNative::version);
	ClassDB::bind_static_method("KineBlendNative", D_METHOD("matrix", "rig", "caps", "clips", "blend_s"), &KineBlendNative::matrix);
}

int KineBlendNative::version() {
	return 1;
}

namespace {

const double DT = 1.0 / 60.0;
const double SOLE_H = 0.025;
const double SOLE_V = 0.6;
const double CLASH_MIN = 0.001;
const double HEIGHT_W = 100.0;

struct V3 {
	double x = 0, y = 0, z = 0;
};
inline V3 operator+(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 operator-(V3 a, V3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 operator*(V3 a, double s) { return { a.x * s, a.y * s, a.z * s }; }
inline double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline double len(V3 a) { return std::sqrt(dot(a, a)); }

struct M3 {
	double m[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
};
inline M3 mul(const M3 &a, const M3 &b) {
	M3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i * 3 + j] = a.m[i * 3] * b.m[j] + a.m[i * 3 + 1] * b.m[3 + j] + a.m[i * 3 + 2] * b.m[6 + j];
		}
	}
	return r;
}
inline V3 apply(const M3 &a, V3 v) {
	return { a.m[0] * v.x + a.m[1] * v.y + a.m[2] * v.z, a.m[3] * v.x + a.m[4] * v.y + a.m[5] * v.z, a.m[6] * v.x + a.m[7] * v.y + a.m[8] * v.z };
}
// rotation about a unit axis
inline M3 rot(V3 k, double ang) {
	double c = std::cos(ang), s = std::sin(ang), t = 1.0 - c;
	M3 r;
	r.m[0] = t * k.x * k.x + c;
	r.m[1] = t * k.x * k.y - s * k.z;
	r.m[2] = t * k.x * k.z + s * k.y;
	r.m[3] = t * k.x * k.y + s * k.z;
	r.m[4] = t * k.y * k.y + c;
	r.m[5] = t * k.y * k.z - s * k.x;
	r.m[6] = t * k.x * k.z - s * k.y;
	r.m[7] = t * k.y * k.z + s * k.x;
	r.m[8] = t * k.z * k.z + c;
	return r;
}

inline double wrapf(double v, double lo, double hi) {
	double range = hi - lo;
	if (range == 0.0) {
		return lo;
	}
	return v - range * std::floor((v - lo) / range);
}
inline double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double smooth(double x) {
	double t = clampd(x, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

struct Rig {
	int J = 0;
	std::vector<int> parent;
	std::vector<double> p0, e0, bax, aax, wax, lim, stretch, mass;
	int pelvis = 0;
	int np = 0;
	std::vector<int> pjoint, pairs;
	std::vector<double> c0, c1, rj, rad, allow, rest;
	int feet[4] = { 0, 0, 0, 0 };
	int npairs = 0;
};

struct Clip {
	const Vector3 *ang;
	const Vector3 *off;
	double fps;
	int n;
};

struct Pose {
	std::vector<V3> ang;
	V3 off;
};

inline V3 v3(const Vector3 &v) { return { v.x, v.y, v.z }; }

inline V3 diff(const Rig &R, int j, V3 a, V3 b) {
	V3 d = b - a;
	if (j == R.pelvis) {
		d.z = wrapf(d.z, -180.0, 180.0);
	}
	return d;
}

void sample(const Rig &R, const Clip &c, double t, Pose &out) {
	double f = clampd(t * c.fps, 0.0, double(c.n - 1));
	int i0 = int(std::floor(f));
	int i1 = i0 + 1 < c.n - 1 ? i0 + 1 : c.n - 1;
	double u = f - double(i0);
	out.ang.resize(R.J);
	for (int j = 0; j < R.J; j++) {
		V3 a = v3(c.ang[i0 * R.J + j]);
		V3 b = v3(c.ang[i1 * R.J + j]);
		out.ang[j] = a + diff(R, j, a, b) * u;
	}
	V3 oa = v3(c.off[i0]), ob = v3(c.off[i1]);
	out.off = oa + (ob - oa) * u;
}

struct Skel {
	std::vector<M3> G;
	std::vector<V3> P, E;
};

void fk(const Rig &R, const std::vector<V3> &ang, V3 off, Skel &S) {
	S.G.resize(R.J);
	S.P.resize(R.J);
	S.E.resize(R.J);
	const double D2R = 3.14159265358979323846 / 180.0;
	for (int j = 0; j < R.J; j++) {
		V3 bx = { R.bax[j * 3], R.bax[j * 3 + 1], R.bax[j * 3 + 2] };
		V3 ax = { R.aax[j * 3], R.aax[j * 3 + 1], R.aax[j * 3 + 2] };
		V3 wx = { R.wax[j * 3], R.wax[j * 3 + 1], R.wax[j * 3 + 2] };
		V3 rv = bx * (ang[j].x * D2R) + ax * (ang[j].y * D2R);
		double n = len(rv);
		M3 sw = n > 1e-9 ? rot(rv * (1.0 / n), n) : M3();
		M3 A = mul(sw, rot(wx, ang[j].z * D2R));
		V3 pj = { R.p0[j * 3], R.p0[j * 3 + 1], R.p0[j * 3 + 2] };
		V3 ej = { R.e0[j * 3], R.e0[j * 3 + 1], R.e0[j * 3 + 2] };
		int p = R.parent[j];
		if (p < 0) {
			S.G[j] = A;
			S.P[j] = pj + off;
		} else {
			V3 pp = { R.p0[p * 3], R.p0[p * 3 + 1], R.p0[p * 3 + 2] };
			S.G[j] = mul(S.G[p], A);
			S.P[j] = S.P[p] + apply(S.G[p], (pj - pp) * R.stretch[j]);
		}
		S.E[j] = S.P[j] + apply(S.G[j], ej - pj);
	}
}

double seg_seg(V3 p1, V3 q1, V3 p2, V3 q2) {
	V3 d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
	double a = dot(d1, d1), e = dot(d2, d2), f = dot(d2, r);
	double s = 0.0, t = 0.0;
	if (a <= 1e-12 && e <= 1e-12) {
		return len(r);
	}
	if (a <= 1e-12) {
		t = clampd(f / e, 0.0, 1.0);
	} else {
		double c = dot(d1, r);
		if (e <= 1e-12) {
			s = clampd(-c / a, 0.0, 1.0);
		} else {
			double b = dot(d1, d2);
			double den = a * e - b * b;
			s = den > 1e-12 ? clampd((b * f - c * e) / den, 0.0, 1.0) : 0.0;
			t = (b * s + f) / e;
			if (t < 0.0) {
				t = 0.0;
				s = clampd(-c / a, 0.0, 1.0);
			} else if (t > 1.0) {
				t = 1.0;
				s = clampd((b - c) / a, 0.0, 1.0);
			}
		}
	}
	return len((p1 + d1 * s) - (p2 + d2 * t));
}

struct Feet {
	double low[2];
	double bx[2], bz[2];
};

void feet_of(const Rig &R, const Skel &S, Feet &F) {
	for (int s = 0; s < 2; s++) {
		int fj = R.feet[s * 2], bj = R.feet[s * 2 + 1];
		double a = S.P[fj].y - R.rest[s * 3];
		double b = S.E[bj].y - R.rest[s * 3 + 2];
		double c = S.P[bj].y - R.rest[s * 3 + 1];
		double l = a < b ? a : b;
		F.low[s] = l < c ? l : c;
		F.bx[s] = S.P[bj].x;
		F.bz[s] = S.P[bj].z;
	}
}

double speed(const Rig &R, const Clip &c, double t, double t2, double shx, double shz, int side) {
	if (std::fabs(t - t2) <= 1e-9) {
		return 0.0;
	}
	Pose p;
	Skel S;
	Feet F[2];
	double tt[2] = { t, t2 };
	for (int k = 0; k < 2; k++) {
		sample(R, c, tt[k], p);
		V3 o = { p.off.x + shx, p.off.y, p.off.z + shz };
		fk(R, p.ang, o, S);
		feet_of(R, S, F[k]);
	}
	double dx = F[0].bx[side] - F[1].bx[side], dz = F[0].bz[side] - F[1].bz[side];
	return std::sqrt(dx * dx + dz * dz) / DT;
}

Dictionary cell(const Rig &R, const Clip &ca, const Clip &cb, double blend_s) {
	int m = int(std::round(blend_s * 60.0));
	if (m < 2) {
		m = 2;
	}
	double T = double(m) * DT;
	double LA = double(ca.n - 1) / ca.fps;
	double LB = double(cb.n - 1) / cb.fps;
	double t0A = LA - T > 0.0 ? LA - T : 0.0;
	Pose pa0, pb0, sa, sb;
	sample(R, ca, t0A, pa0);
	sample(R, cb, 0.0, pb0);
	double shx = pa0.off.x - pb0.off.x, shz = pa0.off.z - pb0.off.z;

	double lim_x = 0.0;
	int lim_j = -1, lim_ax = 0;
	double clash = 0.0;
	int clash_p = -1;
	std::vector<Feet> fs(m + 1);
	Skel S;
	std::vector<V3> ang(R.J);
	std::vector<V3> capa(R.np), capb(R.np);
	for (int k = 0; k <= m; k++) {
		double tA = t0A + double(k) * DT;
		if (tA > LA) {
			tA = LA;
		}
		double tB = double(k) * DT;
		if (tB > LB) {
			tB = LB;
		}
		double w = smooth(double(k) / double(m));
		sample(R, ca, tA, sa);
		sample(R, cb, tB, sb);
		for (int j = 0; j < R.J; j++) {
			V3 r = sa.ang[j] + diff(R, j, sa.ang[j], sb.ang[j]) * w;
			if (j == R.pelvis) {
				r.z = wrapf(r.z, -180.0, 180.0);
			}
			ang[j] = r;
			double vv[3] = { r.x, r.y, r.z };
			for (int ai = 0; ai < 3; ai++) {
				double lo = R.lim[j * 6 + ai * 2], hi = R.lim[j * 6 + ai * 2 + 1];
				double x = lo - vv[ai];
				double y = vv[ai] - hi;
				x = x > y ? x : y;
				if (x < 0.0) {
					x = 0.0;
				}
				if (x > lim_x) {
					lim_x = x;
					lim_j = j;
					lim_ax = ai;
				}
			}
		}
		V3 obx = { sb.off.x + shx, sb.off.y, sb.off.z + shz };
		V3 off = sa.off + (obx - sa.off) * w;
		fk(R, ang, off, S);
		for (int q = 0; q < R.np; q++) {
			int j = R.pjoint[q];
			V3 pj = S.P[j];
			V3 rjv = { R.rj[q * 3], R.rj[q * 3 + 1], R.rj[q * 3 + 2] };
			V3 a = { R.c0[q * 3], R.c0[q * 3 + 1], R.c0[q * 3 + 2] };
			V3 b = { R.c1[q * 3], R.c1[q * 3 + 1], R.c1[q * 3 + 2] };
			capa[q] = pj + apply(S.G[j], a - rjv);
			capb[q] = pj + apply(S.G[j], b - rjv);
		}
		for (int p = 0; p < R.npairs; p++) {
			int x = R.pairs[p * 2], y = R.pairs[p * 2 + 1];
			double d = R.rad[x] + R.rad[y] - seg_seg(capa[x], capb[x], capa[y], capb[y]) - R.allow[p];
			if (d > CLASH_MIN && d > clash) {
				clash = d;
				clash_p = p;
			}
		}
		feet_of(R, S, fs[k]);
	}
	double tAo = t0A + DT <= LA ? t0A + DT : t0A - DT;
	double tBm = T < LB ? T : LB;
	double tBo = tBm + DT <= LB ? tBm + DT : tBm - DT;
	double skate = 0.0;
	int sk_foot = 0;
	for (int s = 0; s < 2; s++) {
		double spa = speed(R, ca, t0A, tAo, 0.0, 0.0, s);
		double spb = speed(R, cb, tBm, tBo, shx, shz, s);
		bool sp = spa < SOLE_V && fs[0].low[s] < SOLE_H;
		bool ep = spb < SOLE_V && fs[m].low[s] < SOLE_H;
		double sl = 0.0;
		auto dist = [&](int i, int j) {
			double dx = fs[i].bx[s] - fs[j].bx[s], dz = fs[i].bz[s] - fs[j].bz[s];
			return std::sqrt(dx * dx + dz * dz);
		};
		if (sp) {
			for (int k = 1; k <= m; k++) {
				if (fs[k].low[s] >= SOLE_H) {
					break;
				}
				double d = dist(k, 0);
				sl = d > sl ? d : sl;
			}
		}
		if (ep) {
			for (int k = m - 1; k >= 0; k--) {
				if (fs[k].low[s] >= SOLE_H) {
					break;
				}
				double d = dist(k, m);
				sl = d > sl ? d : sl;
			}
		}
		if (sp && ep) {
			double d = dist(m, 0);
			sl = d > sl ? d : sl;
		}
		if (sl > skate) {
			skate = sl;
			sk_foot = s + 1;
		}
	}
	Pose qa, qb;
	sample(R, ca, LA, qa);
	sample(R, cb, 0.0, qb);
	double tot = 0.0, sm = 0.0;
	for (int j = 0; j < R.J; j++) {
		V3 d = diff(R, j, qa.ang[j], qb.ang[j]);
		if (j == R.pelvis) {
			d.z = 0.0;
		}
		sm += R.mass[j] * len(d);
		tot += R.mass[j];
	}
	double seam = sm / tot + HEIGHT_W * std::fabs(qb.off.y - qa.off.y);
	Dictionary out;
	out["limit_deg"] = lim_x;
	out["limit_j"] = lim_j;
	out["limit_ax"] = lim_ax;
	out["clash_mm"] = clash * 1000.0;
	out["clash_p"] = clash_p;
	out["skate_mm"] = skate * 1000.0;
	out["skate_foot"] = sk_foot;
	out["seam"] = seam;
	return out;
}

std::vector<double> f64(const Variant &v) {
	PackedFloat64Array a = v;
	std::vector<double> o(a.size());
	for (int i = 0; i < a.size(); i++) {
		o[i] = a[i];
	}
	return o;
}
std::vector<int> i32(const Variant &v) {
	PackedInt32Array a = v;
	std::vector<int> o(a.size());
	for (int i = 0; i < a.size(); i++) {
		o[i] = a[i];
	}
	return o;
}

} // namespace

Array KineBlendNative::matrix(const Dictionary &p_rig, const Dictionary &p_caps, const Array &p_clips, double p_blend_s) {
	Rig R;
	R.J = int(p_rig["J"]);
	R.parent = i32(p_rig["parent"]);
	R.p0 = f64(p_rig["p0"]);
	R.e0 = f64(p_rig["e0"]);
	R.bax = f64(p_rig["bax"]);
	R.aax = f64(p_rig["aax"]);
	R.wax = f64(p_rig["wax"]);
	R.lim = f64(p_rig["lim"]);
	R.stretch = f64(p_rig["stretch"]);
	R.mass = f64(p_rig["mass"]);
	R.pelvis = 0;
	R.pjoint = i32(p_caps["joint"]);
	R.np = int(R.pjoint.size());
	R.c0 = f64(p_caps["c0"]);
	R.c1 = f64(p_caps["c1"]);
	R.rj = f64(p_caps["rj"]);
	R.rad = f64(p_caps["rad"]);
	R.pairs = i32(p_caps["pairs"]);
	R.npairs = int(R.pairs.size() / 2);
	R.allow = f64(p_caps["allow"]);
	R.rest = f64(p_caps["rest"]);
	std::vector<int> fe = i32(p_caps["feet"]);
	for (int i = 0; i < 4; i++) {
		R.feet[i] = fe[i];
	}
	int n = p_clips.size();
	std::vector<PackedVector3Array> angs(n), offs(n);
	std::vector<Clip> cl(n);
	for (int i = 0; i < n; i++) {
		Dictionary d = p_clips[i];
		angs[i] = d["ang"];
		offs[i] = d["off"];
		cl[i].ang = angs[i].ptr();
		cl[i].off = offs[i].ptr();
		cl[i].fps = double(d["fps"]);
		cl[i].n = int(d["n"]);
	}
	Array out;
	for (int i = 0; i < n; i++) {
		for (int j = 0; j < n; j++) {
			out.push_back(cell(R, cl[i], cl[j], p_blend_s));
		}
	}
	return out;
}
