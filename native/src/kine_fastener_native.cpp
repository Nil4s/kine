#include "kine_fastener_native.h"

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {

struct Solids {
	const double *bx;
	const int *po;
	const double *pp;
	int n;
	bool has_poly(int i) const { return po[i + 1] - po[i] >= 3; }
};

double seg_dist(double px, double py, double ax, double ay, double bx, double by) {
	double dx = bx - ax, dy = by - ay;
	double l2 = dx * dx + dy * dy;
	double t = l2 > 0.0 ? ((px - ax) * dx + (py - ay) * dy) / l2 : 0.0;
	t = std::max(0.0, std::min(1.0, t));
	double cx = ax + t * dx - px, cy = ay + t * dy - py;
	return std::sqrt(cx * cx + cy * cy);
}

bool pip(const Solids &S, int i, double z, double y) {
	int a = S.po[i], b = S.po[i + 1];
	bool in = false;
	int n = b - a;
	for (int k = 0, j = n - 1; k < n; j = k++) {
		double zk = S.pp[2 * (a + k)], yk = S.pp[2 * (a + k) + 1];
		double zj = S.pp[2 * (a + j)], yj = S.pp[2 * (a + j) + 1];
		if (((yk > y) != (yj > y)) && (z < (zj - zk) * (y - yk) / (yj - yk) + zk)) {
			in = !in;
		}
	}
	return in;
}

double poly_edge_dist(const Solids &S, int i, double z, double y) {
	int a = S.po[i], b = S.po[i + 1];
	int n = b - a;
	double d = 1e30;
	for (int k = 0, j = n - 1; k < n; j = k++) {
		d = std::min(d, seg_dist(z, y, S.pp[2 * (a + j)], S.pp[2 * (a + j) + 1], S.pp[2 * (a + k)], S.pp[2 * (a + k) + 1]));
	}
	return d;
}

bool inside(const Solids &S, int i, double x, double y, double z, double tol) {
	const double *b = S.bx + 6 * i;
	if (x < b[0] - tol || x > b[3] + tol || y < b[1] - tol || y > b[4] + tol || z < b[2] - tol || z > b[5] + tol) {
		return false;
	}
	if (!S.has_poly(i)) {
		return true;
	}
	if (pip(S, i, z, y)) {
		return true;
	}
	return poly_edge_dist(S, i, z, y) <= tol;
}

// distance from a point to the surface of solid i (0 on the surface; depth below it when inside)
double surf_dist(const Solids &S, int i, double x, double y, double z) {
	const double *b = S.bx + 6 * i;
	if (!S.has_poly(i)) {
		double dx = std::max(std::max(b[0] - x, x - b[3]), 0.0);
		double dy = std::max(std::max(b[1] - y, y - b[4]), 0.0);
		double dz = std::max(std::max(b[2] - z, z - b[5]), 0.0);
		if (dx > 0.0 || dy > 0.0 || dz > 0.0) {
			return std::sqrt(dx * dx + dy * dy + dz * dz);
		}
		return std::min(std::min(std::min(x - b[0], b[3] - x), std::min(y - b[1], b[4] - y)), std::min(z - b[2], b[5] - z));
	}
	double dx = std::max(std::max(b[0] - x, x - b[3]), 0.0);
	bool in = pip(S, i, z, y);
	double ed = poly_edge_dist(S, i, z, y);
	if (dx > 0.0 || !in) {
		double d2 = in ? 0.0 : ed;
		return std::sqrt(dx * dx + d2 * d2);
	}
	return std::min(std::min(x - b[0], b[3] - x), ed);
}

} // namespace

void KineFastenerNative::_bind_methods() {
	ClassDB::bind_static_method("KineFastenerNative", D_METHOD("contacts", "boxes", "mask", "tol", "minov"), &KineFastenerNative::contacts);
	ClassDB::bind_static_method("KineFastenerNative", D_METHOD("first_hits", "boxes", "polyoff", "polypts", "mask", "pts", "tol"), &KineFastenerNative::first_hits);
	ClassDB::bind_static_method("KineFastenerNative", D_METHOD("validate", "boxes", "polyoff", "polypts", "cover", "heads", "dirs", "lens", "a", "b"), &KineFastenerNative::validate);
}

PackedInt32Array KineFastenerNative::contacts(const PackedFloat64Array &p_boxes, const PackedInt32Array &p_mask, double p_tol, double p_minov) {
	PackedInt32Array out;
	int n = p_boxes.size() / 6;
	const double *B = p_boxes.ptr();
	const int *M = p_mask.ptr();
	for (int i = 0; i < n; i++) {
		if (!M[i]) continue;
		const double *bi = B + 6 * i;
		for (int j = i + 1; j < n; j++) {
			if (!M[j]) continue;
			const double *bj = B + 6 * j;
			for (int ax = 0; ax < 3; ax++) {
				int o1 = (ax + 1) % 3, o2 = (ax + 2) % 3;
				double ov1 = std::min(bi[o1 + 3], bj[o1 + 3]) - std::max(bi[o1], bj[o1]);
				double ov2 = std::min(bi[o2 + 3], bj[o2 + 3]) - std::max(bi[o2], bj[o2]);
				if (ov1 <= p_minov || ov2 <= p_minov) continue;
				if (std::fabs(bi[ax + 3] - bj[ax]) <= p_tol) {
					out.push_back(i); out.push_back(j); out.push_back(ax); out.push_back(1);
				}
				if (std::fabs(bj[ax + 3] - bi[ax]) <= p_tol) {
					out.push_back(i); out.push_back(j); out.push_back(ax); out.push_back(-1);
				}
			}
		}
	}
	return out;
}

PackedInt32Array KineFastenerNative::first_hits(const PackedFloat64Array &p_boxes, const PackedInt32Array &p_polyoff, const PackedFloat64Array &p_polypts, const PackedInt32Array &p_mask, const PackedFloat64Array &p_pts, double p_tol) {
	Solids S{ p_boxes.ptr(), p_polyoff.ptr(), p_polypts.ptr(), (int)(p_boxes.size() / 6) };
	const int *M = p_mask.ptr();
	int np = p_pts.size() / 3;
	PackedInt32Array out;
	out.resize(np);
	for (int k = 0; k < np; k++) {
		double x = p_pts[3 * k], y = p_pts[3 * k + 1], z = p_pts[3 * k + 2];
		int hit = -1;
		for (int i = 0; i < S.n; i++) {
			if (M[i] && inside(S, i, x, y, z, p_tol)) { hit = i; break; }
		}
		out.set(k, hit);
	}
	return out;
}

PackedFloat64Array KineFastenerNative::validate(const PackedFloat64Array &p_boxes, const PackedInt32Array &p_polyoff, const PackedFloat64Array &p_polypts, const PackedInt32Array &p_cover, const PackedFloat64Array &p_heads, const PackedFloat64Array &p_dirs, const PackedFloat64Array &p_lens, const PackedInt32Array &p_a, const PackedInt32Array &p_b) {
	Solids S{ p_boxes.ptr(), p_polyoff.ptr(), p_polypts.ptr(), (int)(p_boxes.size() / 6) };
	const int *cov = p_cover.ptr();
	int nn = p_lens.size();
	PackedFloat64Array out;
	out.resize(5 * nn);
	std::vector<int> cand;
	std::vector<char> covered;
	const double STEP = 0.5, TOL = 0.3;
	for (int k = 0; k < nn; k++) {
		double hx = p_heads[3 * k], hy = p_heads[3 * k + 1], hz = p_heads[3 * k + 2];
		double dx = p_dirs[3 * k], dy = p_dirs[3 * k + 1], dz = p_dirs[3 * k + 2];
		double L = p_lens[k];
		int a = p_a[k], b = p_b[k];
		double ex = hx + dx * L, ey = hy + dy * L, ez = hz + dz * L;
		double lo[3] = { std::min(hx, ex) - TOL, std::min(hy, ey) - TOL, std::min(hz, ez) - TOL };
		double hi[3] = { std::max(hx, ex) + TOL, std::max(hy, ey) + TOL, std::max(hz, ez) + TOL };
		cand.clear();
		for (int i = 0; i < S.n; i++) {
			if (!cov[i] && i != a && i != b) continue;
			const double *bb = S.bx + 6 * i;
			if (bb[0] > hi[0] || bb[3] < lo[0] || bb[1] > hi[1] || bb[4] < lo[1] || bb[2] > hi[2] || bb[5] < lo[2]) continue;
			cand.push_back(i);
		}
		int ns = (int)std::floor(L / STEP + 1e-9);
		covered.assign(ns + 1, 0);
		int n_a = 0, n_b = 0, last = -1;
		for (int s = 0; s <= ns; s++) {
			double t = s * STEP;
			double x = hx + dx * t, y = hy + dy * t, z = hz + dz * t;
			bool ina = a >= 0 && inside(S, a, x, y, z, TOL);
			bool inb = b >= 0 && inside(S, b, x, y, z, TOL);
			bool any = ina || inb;
			if (!any) {
				for (int c : cand) {
					if (cov[c] && inside(S, c, x, y, z, TOL)) { any = true; break; }
				}
			}
			if (ina) n_a++;
			if (inb) n_b++;
			if (any) { last = s; covered[s] = 1; }
		}
		int holes = 0;
		for (int s = 0; s <= last; s++) {
			if (!covered[s]) holes++;
		}
		double len_a = n_a * STEP;
		double len_b = n_b * STEP;
		if (a == b) len_b = std::max(0.0, len_a - 51.0);
		double tail = last < 0 ? L : std::max(0.0, L - last * STEP);
		double gap = a >= 0 ? surf_dist(S, a, hx, hy, hz) : 0.0;
		out.set(5 * k, gap);
		out.set(5 * k + 1, len_a);
		out.set(5 * k + 2, len_b);
		out.set(5 * k + 3, tail);
		out.set(5 * k + 4, holes * STEP);
	}
	return out;
}
