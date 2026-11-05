#include "kine_parkour_native.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
const double STEP = 0.01; // Props.STEP

// Props._sd for an axis-aligned box (the course's Parts are never turned)
inline double box_sd(const Vector3 &pt, const Vector3 &c, const Vector3 &h) {
	Vector3 l = pt - c;
	Vector3 q(std::fabs(l.x) - h.x, std::fabs(l.y) - h.y, std::fabs(l.z) - h.z);
	Vector3 o(std::max(q.x, 0.0f), std::max(q.y, 0.0f), std::max(q.z, 0.0f));
	return o.length() + std::min(std::max(q.x, std::max(q.y, q.z)), 0.0f);
}
} // namespace

void KineParkourNative::_bind_methods() {
	ClassDB::bind_static_method("KineParkourNative", D_METHOD("version"), &KineParkourNative::version);
	ClassDB::bind_static_method("KineParkourNative", D_METHOD("deepest", "a", "b", "r", "base", "centre", "half"), &KineParkourNative::deepest);
}

int KineParkourNative::version() { return 1; }

Array KineParkourNative::deepest(const PackedVector3Array &p_a, const PackedVector3Array &p_b, const PackedFloat32Array &p_r,
		const PackedFloat32Array &p_base, const PackedVector3Array &p_centre, const PackedVector3Array &p_half) {
	double best = 0.0;
	int bi = -1, bj = -1;
	const int nc = p_a.size();
	const int nb = p_centre.size();
	for (int i = 0; i < nc; i++) {
		const Vector3 a = p_a[i];
		const Vector3 b = p_b[i];
		const double r = p_r[i];
		const double base = p_base[i];
		const int n = std::max(1, (int)std::ceil(a.distance_to(b) / STEP));
		for (int j = 0; j < nb; j++) {
			double worst = 0.0;
			for (int k = 0; k <= n; k++) {
				Vector3 pt = a.lerp(b, (float)k / (float)n);
				worst = std::max(worst, r - box_sd(pt, p_centre[j], p_half[j]));
			}
			double d = worst - base;
			if (d > best) {
				best = d;
				bi = i;
				bj = j;
			}
		}
	}
	Array out;
	out.push_back(best);
	out.push_back(bi);
	out.push_back(bj);
	return out;
}
