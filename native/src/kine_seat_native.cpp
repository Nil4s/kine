#include "kine_seat_native.h"

#include <cmath>
#include <limits>
#include <vector>

using namespace godot;

void KineSeatNative::_bind_methods() {
	ClassDB::bind_static_method("KineSeatNative", D_METHOD("version"), &KineSeatNative::version);
	ClassDB::bind_static_method("KineSeatNative", D_METHOD("surface_under", "hosts", "pts", "top_y", "low_y"), &KineSeatNative::surface_under);
}

int KineSeatNative::version() {
	return 1;
}

namespace {
struct V3 {
	float x, y, z;
};
inline V3 sub(const V3 &a, const V3 &b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline float dot(const V3 &a, const V3 &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(const V3 &a, const V3 &b) {
	return { (a.y * b.z) - (a.z * b.y), (a.z * b.x) - (a.x * b.z), (a.x * b.y) - (a.y * b.x) };
}
const double EPS = 1e-3; // same slack as the GDScript grid: a ray the reference counts as a hit is never missed by the box test
} // namespace

PackedFloat64Array KineSeatNative::surface_under(const Array &p_hosts, const PackedVector3Array &p_pts, double p_top_y, double p_low_y) {
	const int np = p_pts.size();
	PackedFloat64Array out;
	out.resize(np);
	const double nan = std::numeric_limits<double>::quiet_NaN();
	const double inf = std::numeric_limits<double>::infinity();
	if (np == 0) {
		return out;
	}
	std::vector<V3> pt(np);
	std::vector<double> best(np, inf); // smallest distance down (= highest y), over every host triangle
	float minx = p_pts[0].x, maxx = minx, minz = p_pts[0].z, maxz = minz;
	for (int i = 0; i < np; i++) {
		Vector3 q = p_pts[i];
		pt[i] = { q.x, (float)p_top_y, q.z };
		minx = std::fmin(minx, q.x);
		maxx = std::fmax(maxx, q.x);
		minz = std::fmin(minz, q.z);
		maxz = std::fmax(maxz, q.z);
	}
	const V3 dn = { 0.0f, -1.0f, 0.0f };
	for (int h = 0; h < p_hosts.size(); h++) {
		PackedVector3Array t = p_hosts[h];
		const int nt = t.size() / 3;
		const Vector3 *P = t.ptr();
		for (int i = 0; i < nt; i++) {
			const Vector3 &A = P[i * 3], &B = P[i * 3 + 1], &C = P[i * 3 + 2];
			double lx = std::fmin(A.x, std::fmin(B.x, C.x)) - EPS, hx = std::fmax(A.x, std::fmax(B.x, C.x)) + EPS;
			double lz = std::fmin(A.z, std::fmin(B.z, C.z)) - EPS, hz = std::fmax(A.z, std::fmax(B.z, C.z)) + EPS;
			if (hx < minx || lx > maxx || hz < minz || lz > maxz) {
				continue;
			}
			const V3 p0 = { A.x, A.y, A.z };
			const V3 e1 = sub({ B.x, B.y, B.z }, p0);
			const V3 e2 = sub({ C.x, C.y, C.z }, p0);
			const V3 hv = cross(dn, e2);
			const double a = dot(e1, hv);
			if (std::fabs(a) < 1e-12) {
				continue;
			}
			const double f = 1.0 / a;
			for (int k = 0; k < np; k++) {
				const V3 &o = pt[k];
				if (o.x < lx || o.x > hx || o.z < lz || o.z > hz) {
					continue;
				}
				const V3 sv = sub(o, p0);
				const double u = f * dot(sv, hv);
				if (u < -1e-9 || u > 1.0 + 1e-9) {
					continue;
				}
				const V3 qv = cross(sv, e1);
				const double v = f * dot(dn, qv);
				if (v < -1e-9 || u + v > 1.0 + 1e-9) {
					continue;
				}
				const double tt = f * dot(e2, qv);
				if (tt >= -1e-9 && tt < best[k]) {
					best[k] = tt > 0.0 ? tt : 0.0;
				}
			}
		}
	}
	for (int k = 0; k < np; k++) {
		double y = nan;
		if (!std::isinf(best[k])) {
			double yy = p_top_y - best[k];
			if (yy >= p_low_y) {
				y = yy;
			}
		}
		out.set(k, y);
	}
	return out;
}
