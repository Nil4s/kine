#include "kine_ik_native.h"

#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <chrono>
#include <cmath>

using namespace godot;

void KineIKNative::_bind_methods() {
	ClassDB::bind_static_method("KineIKNative", D_METHOD("version"), &KineIKNative::version);
	ClassDB::bind_static_method("KineIKNative", D_METHOD("math_probe", "kind", "xs"), &KineIKNative::math_probe);
	ClassDB::bind_static_method("KineIKNative", D_METHOD("plant_leg", "static_data", "dyn", "ball_at", "head", "flat", "knee"), &KineIKNative::plant_leg);
}

int KineIKNative::version() {
	return 1;
}

namespace {

const double PI_D = 3.1415926535897932384626433833;
const double TAU_D = 6.2831853071795864769252867666;
const double IK_EPS = 1e-5;

// The engine's own math. The DLL is built with mingw, whose libm is not the engine's: measured (tests/i16probe_test.gd) sin 3.1 %, cos 3.0 %,
// atan2 0.06 % and Quaternion(axis, angle) 0.25 % of random inputs differ in the last bit, and one last-bit difference inside the IK
// bisections is enough to move a pose by 1e-5. So everything that goes through sin / cos / atan2 is called in the engine (the
// Variant constructor / method pointers, UtilityFunctions), never through this DLL's libm.
GDExtensionPtrConstructor g_quat_axis_angle = nullptr;
GDExtensionPtrBuiltInMethod g_angle_to = nullptr;

inline Quaternion qaa(const Vector3 &axis, double angle) {
	if (!g_quat_axis_angle) {
		g_quat_axis_angle = ::godot::gdextension_interface::variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_QUATERNION, 3);
	}
	Vector3 ax = axis;
	double a = angle;
	const void *args[2] = { &ax, &a };
	Quaternion q;
	g_quat_axis_angle(&q, args);
	return q;
}

inline double angle_to(const Vector3 &from, const Vector3 &to) {
	if (!g_angle_to) {
		g_angle_to = ::godot::internal::get_builtin_method(GDEXTENSION_VARIANT_TYPE_VECTOR3, "angle_to", 1047977935);
	}
	Vector3 base = from;
	Vector3 t = to;
	const void *args[1] = { &t };
	double r = 0.0;
	g_angle_to(&base, args, &r, 1);
	return r;
}

inline double d2r(double x) { return x * (PI_D / 180.0); }
inline double r2d(double x) { return x * (180.0 / PI_D); }
inline double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

// the chain: 0 thigh, 1 calf, 2 foot, 3 ball
struct Leg {
	Vector3 p0[4], e0[4], b[4], a[4], w[4], t[4];
	Vector3 pel_p0;
	bool bone[4];
	Vector3 ang[4];
	Quaternion G[4];
	Vector3 P[4], E[4];
	Quaternion pelG;
	Vector3 pelP;
	double lim[4][6];

	Quaternion compose(int j, const Vector3 &v) const {
		Vector3 rv = b[j] * (real_t)d2r(v.x) + a[j] * (real_t)d2r(v.y);
		double n = rv.length();
		Quaternion sw = n > 1e-9 ? qaa(rv / (real_t)n, n) : Quaternion();
		return sw * qaa(w[j], d2r(v.z));
	}

	Vector3 decompose_bone(int j, const Quaternion &q) const {
		Vector3 tt = t[j];
		Vector3 pr = tt * (real_t)Vector3(q.x, q.y, q.z).dot(tt);
		Quaternion qt(pr.x, pr.y, pr.z, q.w);
		qt = qt.length() > 1e-9 ? qt.normalized() : Quaternion();
		Quaternion qs = q * qt.inverse();
		if (qs.w < 0.0) {
			qs = Quaternion(-qs.x, -qs.y, -qs.z, -qs.w);
		}
		Vector3 v(qs.x, qs.y, qs.z);
		double vl = v.length();
		Vector3 rv;
		if (vl > 1e-12) {
			rv = v / (real_t)vl * (real_t)(2.0 * UtilityFunctions::atan2(vl, (double)qs.w));
		}
		double tw = 2.0 * UtilityFunctions::atan2((double)Vector3(qt.x, qt.y, qt.z).dot(tt), (double)qt.w);
		if (tw > PI_D) {
			tw -= TAU_D;
		} else if (tw < -PI_D) {
			tw += TAU_D;
		}
		return Vector3((real_t)r2d(rv.dot(b[j])), (real_t)r2d(rv.dot(a[j])), (real_t)r2d(tw));
	}

	double sub_part(const Quaternion &q, const Vector3 &ww, const Vector3 &tt, double th) const {
		Quaternion S = q * qaa(ww, -th);
		return Vector3(S.x, S.y, S.z).dot(tt);
	}

	Vector3 decompose(int j, const Quaternion &q) const {
		if (bone[j]) {
			return decompose_bone(j, q);
		}
		Vector3 ww = w[j];
		Vector3 tt = t[j];
		Vector3 qv(q.x, q.y, q.z);
		if (std::fabs((double)qv.dot(tt)) < 1e-5) {
			return decompose_bone(j, q);
		}
		double fa = sub_part(q, ww, tt, 0.0);
		double fb = sub_part(q, ww, tt, PI_D);
		double th = 2.0 * UtilityFunctions::atan2(-fa, fb);
		if (th > PI_D) {
			th -= TAU_D;
		} else if (th < -PI_D) {
			th += TAU_D;
		}
		Quaternion S = q * qaa(ww, -th);
		if (S.w < 0.0) {
			S = -S;
		}
		Vector3 sv(S.x, S.y, S.z);
		double vl = sv.length();
		Vector3 rv;
		if (vl > 1e-12) {
			rv = sv / (real_t)vl * (real_t)(2.0 * UtilityFunctions::atan2(vl, (double)S.w));
		}
		return Vector3((real_t)r2d(rv.dot(b[j])), (real_t)r2d(rv.dot(a[j])), (real_t)r2d(th));
	}

	Vector3 clamp_ang(int j, const Vector3 &v) const {
		const double *L = lim[j];
		return Vector3((real_t)clampd(v.x, L[0], L[1]), (real_t)clampd(v.y, L[2], L[3]), (real_t)clampd(v.z, L[4], L[5]));
	}

	// Body.fk_sub in playback: j and every joint under it
	void fk_sub(int j) {
		for (int k = j; k < 4; k++) {
			Quaternion A = compose(k, ang[k]);
			Quaternion gpk = k == 0 ? pelG : G[k - 1];
			Vector3 ppk = k == 0 ? pelP : P[k - 1];
			Vector3 p0pk = k == 0 ? pel_p0 : p0[k - 1];
			G[k] = gpk * A;
			P[k] = ppk + gpk.xform(p0[k] - p0pk);
			E[k] = P[k] + G[k].xform(e0[k] - p0[k]);
		}
	}

	void set_ang(int j, const Vector3 &v) {
		ang[j] = clamp_ang(j, v);
		fk_sub(j);
	}

	void turn_world(int j, const Quaternion &R) {
		Quaternion gp = j == 0 ? pelG : G[j - 1];
		Quaternion a_new = gp.inverse() * R * gp * compose(j, ang[j]);
		Vector3 v = decompose(j, a_new.normalized());
		Vector3 old = ang[j];
		while ((double)v.z - (double)old.z > 180.0) {
			v.z = (real_t)((double)v.z - 360.0);
		}
		while ((double)v.z - (double)old.z < -180.0) {
			v.z = (real_t)((double)v.z + 360.0);
		}
		set_ang(j, v);
	}

	void flat_foot() {
		double want = (double)p0[3].y - (double)p0[2].y;
		double lo = lim[2][0];
		double hi = lim[2][1];
		Vector3 v = ang[2];
		Quaternion gp = G[1];
		Vector3 pfoot = P[1] + gp.xform(p0[2] - p0[1]);
		Vector3 ba = b[2];
		Vector3 side_part = a[2] * (real_t)d2r(v.y);
		Quaternion twist_q = qaa(w[2], d2r(v.z));
		Vector3 db = p0[3] - p0[2];
		for (int k = 0; k < 16; k++) {
			double m = (lo + hi) * 0.5;
			Vector3 rv = ba * (real_t)d2r(m) + side_part;
			double n = rv.length();
			Quaternion sw = n > 1e-9 ? qaa(rv / (real_t)n, n) : Quaternion();
			Quaternion gf = gp * (sw * twist_q);
			if ((double)(pfoot + gf.xform(db)).y - (double)pfoot.y > want) {
				hi = m;
			} else {
				lo = m;
			}
		}
		ang[2] = Vector3((real_t)((lo + hi) * 0.5), v.y, v.z);
		fk_sub(2);
	}

	double reach(const Vector3 &target) {
		double prev = INFINITY;
		for (int it = 0; it < 6; it++) {
			double want = (target - P[0]).length();
			double lo = lim[1][0];
			double hi = lim[1][1];
			Vector3 v = ang[1];
			Quaternion gr = G[0];
			Vector3 pr = P[0];
			Vector3 pmid = pr + gr.xform(p0[1] - p0[0]);
			Vector3 ba = b[1];
			Vector3 side_part = a[1] * (real_t)d2r(v.y);
			Quaternion twist_q = qaa(w[1], d2r(v.z));
			Vector3 dt = p0[2] - p0[1];
			for (int k = 0; k < 14; k++) {
				double m = (lo + hi) * 0.5;
				Vector3 rv = ba * (real_t)d2r(m) + side_part;
				double n = rv.length();
				Quaternion sw = n > 1e-9 ? qaa(rv / (real_t)n, n) : Quaternion();
				Quaternion gm = gr * (sw * twist_q);
				if ((double)((pmid + gm.xform(dt)) - pr).length() > want) {
					lo = m;
				} else {
					hi = m;
				}
			}
			ang[1] = v;
			fk_sub(1);
			set_ang(1, Vector3((real_t)((lo + hi) * 0.5), v.y, v.z));
			Vector3 r1 = P[2] - P[0];
			Vector3 r2 = target - P[0];
			Vector3 ax = r1.cross(r2);
			if (ax.length() > 1e-9) {
				turn_world(0, qaa(ax.normalized(), angle_to(r1, r2)));
			}
			double miss = (P[2] - target).length();
			if (miss < IK_EPS) {
				break;
			}
			if (miss > prev - 1e-6) {
				break;
			}
			prev = miss;
		}
		return (P[2] - target).length();
	}

	void knee_over_toes(double head) {
		Vector3 H = P[0];
		Vector3 u = (P[2] - H).normalized();
		Vector3 k = P[1] - H;
		k -= u * (real_t)u.dot(k);
		Vector3 w2((real_t)UtilityFunctions::sin(head), 0.0f, (real_t)UtilityFunctions::cos(head));
		w2 -= u * (real_t)u.dot(w2);
		if (k.length() < 0.01 || w2.length() < 0.01) {
			return;
		}
		k = k.normalized();
		w2 = w2.normalized();
		double a2 = UtilityFunctions::atan2((double)u.dot(k.cross(w2)), (double)k.dot(w2));
		turn_world(0, qaa(u, a2));
	}

	double plant(const Vector3 &ball_at, double head, bool flat, double knee) {
		for (int it = 0; it < 5; it++) {
			if (flat) {
				flat_foot();
			}
			Vector3 d = P[3] - P[2];
			reach(ball_at - d);
			Vector3 hf = pelG.xform(Vector3(0, 0, 1));
			double kh = !std::isnan(knee) ? knee : (flat ? head : UtilityFunctions::atan2((double)hf.x, (double)hf.z));
			knee_over_toes(kh);
			if ((double)(P[3] - ball_at).length() < IK_EPS) {
				break;
			}
		}
		return (P[3] - ball_at).length();
	}
};

inline Vector3 v3(const float *p) { return Vector3(p[0], p[1], p[2]); }
inline Quaternion q4(const float *p) { return Quaternion(p[0], p[1], p[2], p[3]); }

} // namespace

PackedFloat32Array KineIKNative::plant_leg(const PackedFloat32Array &p_static, const PackedFloat32Array &p_dyn, const Vector3 &p_ball_at, double p_head, bool p_flat, double p_knee) {
	PackedFloat32Array out;
	if (p_static.size() < 79 || p_dyn.size() < 71) {
		return out;
	}
	const float *s = p_static.ptr();
	const float *d = p_dyn.ptr();
	Leg L;
	for (int j = 0; j < 4; j++) {
		const float *q = s + j * 18;
		L.p0[j] = v3(q);
		L.e0[j] = v3(q + 3);
		L.b[j] = v3(q + 6);
		L.a[j] = v3(q + 9);
		L.w[j] = v3(q + 12);
		L.t[j] = v3(q + 15);
		L.bone[j] = s[75 + j] != 0.0f;
		L.ang[j] = v3(d + j * 3);
		L.G[j] = q4(d + 12 + j * 4);
		L.P[j] = v3(d + 28 + j * 3);
		for (int k = 0; k < 6; k++) {
			L.lim[j][k] = d[47 + j * 6 + k];
		}
	}
	L.pel_p0 = v3(s + 72);
	L.pelG = q4(d + 40);
	L.pelP = v3(d + 44);
	double miss = L.plant(p_ball_at, p_head, p_flat, p_knee);
	out.resize(53);
	float *o = out.ptrw();
	for (int j = 0; j < 4; j++) {
		float *w = o + j * 13;
		w[0] = L.ang[j].x;
		w[1] = L.ang[j].y;
		w[2] = L.ang[j].z;
		w[3] = L.G[j].x;
		w[4] = L.G[j].y;
		w[5] = L.G[j].z;
		w[6] = L.G[j].w;
		w[7] = L.P[j].x;
		w[8] = L.P[j].y;
		w[9] = L.P[j].z;
		w[10] = L.E[j].x;
		w[11] = L.E[j].y;
		w[12] = L.E[j].z;
	}
	o[52] = (float)miss;
	return out;
}

PackedFloat64Array KineIKNative::math_probe(int p_kind, const PackedFloat64Array &p_xs) {
	PackedFloat64Array out;
	const int n = p_xs.size();
	for (int i = 0; i < n; i++) {
		double x = p_xs[i];
		switch (p_kind) {
			case 0:
				out.push_back(std::sin(x));
				break;
			case 1:
				out.push_back(std::cos(x));
				break;
			case 2:
				if (i + 1 < n) {
					out.push_back(std::atan2(x, p_xs[i + 1]));
					i++;
				}
				break;
			case 3: {
				Quaternion q(Vector3(0.6f, 0.0f, 0.8f), (real_t)x);
				out.push_back(q.x);
				out.push_back(q.y);
				out.push_back(q.z);
				out.push_back(q.w);
			} break;
			case 5: {   // the engine's own Quaternion(axis, angle), through its constructor pointer
				Quaternion q = qaa(Vector3(0.6f, 0.0f, 0.8f), x);
				out.push_back(q.x);
				out.push_back(q.y);
				out.push_back(q.z);
				out.push_back(q.w);
			} break;
			case 6:
				out.push_back(UtilityFunctions::sin(x));
				break;
			case 7:
				out.push_back(UtilityFunctions::cos(x));
				break;
			case 8:
				if (i + 1 < n) {
					out.push_back(UtilityFunctions::atan2(x, p_xs[i + 1]));
					i++;
				}
				break;
			case 9: {   // timing: ns per call of the Variant constructor, then of UtilityFunctions::sin, over n calls
				auto t0 = std::chrono::steady_clock::now();
				double accq = 0.0;
				for (int k = 0; k < n; k++) {
					accq += qaa(Vector3(0.6f, 0.0f, 0.8f), p_xs[k]).w;
				}
				auto t1 = std::chrono::steady_clock::now();
				double acc = 0.0;
				for (int k = 0; k < n; k++) {
					acc += UtilityFunctions::sin(p_xs[k]);
				}
				auto t2 = std::chrono::steady_clock::now();
				out.push_back(std::chrono::duration<double, std::nano>(t1 - t0).count() / n);
				out.push_back(std::chrono::duration<double, std::nano>(t2 - t1).count() / n);
				out.push_back(acc + accq);
				return out;
			}
			default: {
				Vector3 v = Vector3((real_t)x, 0.3f, -0.5f).normalized();
				out.push_back(v.x);
				out.push_back(v.y);
				out.push_back(v.z);
			} break;
		}
	}
	return out;
}
