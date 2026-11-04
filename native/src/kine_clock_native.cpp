#include "kine_clock_native.h"

#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <cmath>
#include <vector>

using namespace godot;

namespace {
struct P { double x, y; };
struct Tri { P a, b, c; double x0, x1, y0, y1; };

double cross(const P &o, const P &a, const P &b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); }

bool in_tri(const P &p, const P &a, const P &b, const P &c) {
	return cross(a, b, p) >= -1e-12 && cross(b, c, p) >= -1e-12 && cross(c, a, p) >= -1e-12;
}

// ear clipping of a simple polygon (any winding); triangles come out counter-clockwise
void ear_clip(std::vector<P> v, std::vector<Tri> &out) {
	double area = 0;
	for (size_t i = 0; i < v.size(); i++) {
		const P &a = v[i];
		const P &b = v[(i + 1) % v.size()];
		area += a.x * b.y - b.x * a.y;
	}
	if (area < 0) {
		std::vector<P> r(v.rbegin(), v.rend());
		v = r;
	}
	std::vector<int> idx(v.size());
	for (size_t i = 0; i < v.size(); i++) idx[i] = (int)i;
	int guard = 0;
	while (idx.size() > 3 && guard++ < 100000) {
		bool clipped = false;
		size_t n = idx.size();
		for (size_t i = 0; i < n; i++) {
			const P &a = v[idx[(i + n - 1) % n]];
			const P &b = v[idx[i]];
			const P &c = v[idx[(i + 1) % n]];
			if (cross(a, b, c) <= 1e-12) continue;
			bool empty = true;
			for (size_t j = 0; j < n && empty; j++) {
				if (j == i || j == (i + n - 1) % n || j == (i + 1) % n) continue;
				const P &p = v[idx[j]];
				if ((p.x == a.x && p.y == a.y) || (p.x == b.x && p.y == b.y) || (p.x == c.x && p.y == c.y)) continue;
				if (in_tri(p, a, b, c)) empty = false;
			}
			if (!empty) continue;
			out.push_back({ a, b, c, 0, 0, 0, 0 });
			idx.erase(idx.begin() + i);
			clipped = true;
			break;
		}
		if (!clipped) break;
	}
	if (idx.size() == 3) out.push_back({ v[idx[0]], v[idx[1]], v[idx[2]], 0, 0, 0, 0 });
}

void fill_box(Tri &t) {
	t.x0 = std::fmin(t.a.x, std::fmin(t.b.x, t.c.x));
	t.x1 = std::fmax(t.a.x, std::fmax(t.b.x, t.c.x));
	t.y0 = std::fmin(t.a.y, std::fmin(t.b.y, t.c.y));
	t.y1 = std::fmax(t.a.y, std::fmax(t.b.y, t.c.y));
}

// area of (convex ccw triangle s) clipped by (convex ccw triangle c)
double clip_area(const Tri &s, const Tri &c) {
	std::vector<P> poly = { s.a, s.b, s.c };
	P cp[3] = { c.a, c.b, c.c };
	for (int e = 0; e < 3 && !poly.empty(); e++) {
		const P &a = cp[e];
		const P &b = cp[(e + 1) % 3];
		std::vector<P> in = poly;
		poly.clear();
		for (size_t i = 0; i < in.size(); i++) {
			const P &p = in[i];
			const P &q = in[(i + 1) % in.size()];
			double dp = cross(a, b, p), dq = cross(a, b, q);
			if (dp >= 0) poly.push_back(p);
			if ((dp > 0 && dq < 0) || (dp < 0 && dq > 0)) {
				double t = dp / (dp - dq);
				poly.push_back({ p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t });
			}
		}
	}
	double A = 0;
	for (size_t i = 0; i < poly.size(); i++) {
		const P &a = poly[i];
		const P &b = poly[(i + 1) % poly.size()];
		A += a.x * b.y - b.x * a.y;
	}
	return std::fabs(A) * 0.5;
}

std::vector<Tri> posed(const PackedVector2Array &poly, double x, double y, double ang) {
	double cs = std::cos(ang), sn = std::sin(ang);
	std::vector<P> v;
	for (int i = 0; i < poly.size(); i++) {
		Vector2 q = poly[i];
		v.push_back({ x + q.x * cs - q.y * sn, y + q.x * sn + q.y * cs });
	}
	std::vector<Tri> t;
	ear_clip(v, t);
	for (auto &k : t) fill_box(k);
	return t;
}
} // namespace

int KineClockNative::version() { return 1; }

PackedFloat64Array KineClockNative::pair_overlaps(const Array &p_polys, const PackedFloat64Array &p_pose, const PackedInt32Array &p_pairs) {
	PackedFloat64Array res;
	int n = p_polys.size();
	std::vector<std::vector<Tri>> tris((size_t)n);
	std::vector<bool> done((size_t)n, false);
	for (int k = 0; k + 1 < p_pairs.size(); k += 2) {
		int ia = p_pairs[k], ib = p_pairs[k + 1];
		double sum = 0;
		if (ia >= 0 && ib >= 0 && ia < n && ib < n && p_pose.size() >= 3 * n) {
			for (int w : { ia, ib }) {
				if (!done[(size_t)w]) {
					tris[(size_t)w] = posed(p_polys[w], p_pose[3 * w], p_pose[3 * w + 1], p_pose[3 * w + 2]);
					done[(size_t)w] = true;
				}
			}
			for (const Tri &a : tris[(size_t)ia])
				for (const Tri &b : tris[(size_t)ib]) {
					if (a.x1 <= b.x0 || b.x1 <= a.x0 || a.y1 <= b.y0 || b.y1 <= a.y0) continue;
					sum += clip_area(a, b);
				}
		}
		res.push_back(sum);
	}
	return res;
}

void KineClockNative::_bind_methods() {
	ClassDB::bind_static_method("KineClockNative", D_METHOD("version"), &KineClockNative::version);
	ClassDB::bind_static_method("KineClockNative", D_METHOD("pair_overlaps", "polys", "pose", "pairs"), &KineClockNative::pair_overlaps);
}
