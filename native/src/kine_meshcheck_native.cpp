#include "kine_meshcheck_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

const double THIN_MM = 0.8;
const double OVERHANG_DEG = 45.0;
const double BED_TOL = 0.05;
const double TOUCH_TOL = 0.05;
const double CELL = 2.0;
const double SUPPORT_MM = 0.1;

inline int cell_of(double v) { return (int)std::floor(v / CELL); }

inline uint64_t ckey(int x, int y, int z) {
	const int64_t O = 1 << 20;
	return ((uint64_t)(x + O) << 42) | ((uint64_t)(y + O) << 21) | (uint64_t)(z + O);
}

struct Soup {
	std::vector<int> ia, ib, ic, body;
	std::vector<Vector3> pa, pb, pc, nn;
	std::vector<float> area;
	std::unordered_map<uint64_t, std::vector<int>> grid;
};

// Moller-Trumbore, mirrors PrintCheck._ray_tri (float32 vectors, double scalars)
inline double ray_tri(const Vector3 &o, const Vector3 &d, const Vector3 &a, const Vector3 &b, const Vector3 &c) {
	Vector3 e1 = b - a;
	Vector3 e2 = c - a;
	Vector3 p = d.cross(e2);
	double det = e1.dot(p);
	if (std::fabs(det) < 1e-12) {
		return -1.0;
	}
	double inv = 1.0 / det;
	Vector3 s = o - a;
	double u = (double)s.dot(p) * inv;
	if (u < -1e-6 || u > 1.0 + 1e-6) {
		return -1.0;
	}
	Vector3 q = s.cross(e1);
	double v = (double)d.dot(q) * inv;
	if (v < -1e-6 || u + v > 1.0 + 1e-6) {
		return -1.0;
	}
	double t = (double)e2.dot(q) * inv;
	return t >= 0.0 ? t : -1.0;
}

// PrintCheck._hit: nearest hit within maxd. mode 1: far side of a wall; mode 2: faces that look up
inline bool hit(const Soup &S, const Vector3 &o, const Vector3 &d, double maxd, int self_tri, int body_only, int mode, double &bt, int &bj) {
	Vector3 e = o + d * (real_t)maxd;
	const real_t pad = (real_t)0.01;
	int c0x = cell_of(std::min(o.x, e.x) - pad), c0y = cell_of(std::min(o.y, e.y) - pad), c0z = cell_of(std::min(o.z, e.z) - pad);
	int c1x = cell_of(std::max(o.x, e.x) + pad), c1y = cell_of(std::max(o.y, e.y) + pad), c1z = cell_of(std::max(o.z, e.z) + pad);
	double best = INFINITY;
	int b = -1;
	for (int x = c0x; x <= c1x; x++) {
		for (int y = c0y; y <= c1y; y++) {
			for (int z = c0z; z <= c1z; z++) {
				auto it = S.grid.find(ckey(x, y, z));
				if (it == S.grid.end()) {
					continue;
				}
				for (int j : it->second) {
					if (j == self_tri || (body_only >= 0 && S.body[j] != body_only)) {
						continue;
					}
					if (mode == 1 && S.nn[j].dot(d) < 0.0f) {
						continue;
					}
					if (mode == 2 && S.nn[j].z <= 0.3f) {
						continue;
					}
					double t = ray_tri(o, d, S.pa[j], S.pb[j], S.pc[j]);
					if (t >= 0.0 && t <= maxd && t < best) {
						best = t;
						b = j;
					}
				}
			}
		}
	}
	bt = best;
	bj = b;
	return b >= 0;
}

inline int uf_find(std::unordered_map<int, int> &parent, int i) {
	int r = i;
	while (parent[r] != r) {
		r = parent[r];
	}
	int c = i;
	while (parent[c] != r) {
		int nx = parent[c];
		parent[c] = r;
		c = nx;
	}
	return r;
}

inline void uf_union(std::unordered_map<int, int> &parent, int a, int b) {
	int ra = uf_find(parent, a), rb = uf_find(parent, b);
	if (ra != rb) {
		parent[ra] = rb;
	}
}

inline Vector3 closest_on_segment(const Vector3 &pt, const Vector3 &s0, const Vector3 &s1) {
	Vector3 p = pt - s0;
	Vector3 n = s1 - s0;
	real_t l2 = n.length_squared();
	if (l2 < (real_t)1e-8) {
		return s0;
	}
	real_t d = n.dot(p) / l2;
	if (d <= 0.0f) {
		return s0;
	} else if (d >= 1.0f) {
		return s1;
	}
	return s0 + n * d;
}

// PrintCheck._point_tri_dist
inline double point_tri_dist(const Vector3 &p, const Vector3 &a, const Vector3 &b, const Vector3 &c, const Vector3 &n) {
	double dist = (p - a).dot(n);
	Vector3 proj = p - n * (real_t)dist;
	Vector3 v0 = c - a, v1 = b - a, v2 = proj - a;
	double d00 = v0.dot(v0), d01 = v0.dot(v1), d02 = v0.dot(v2), d11 = v1.dot(v1), d12 = v1.dot(v2);
	double den = d00 * d11 - d01 * d01;
	if (std::fabs(den) > 1e-12) {
		double u = (d11 * d02 - d01 * d12) / den;
		double w = (d00 * d12 - d01 * d02) / den;
		if (u >= 0.0 && w >= 0.0 && u + w <= 1.0) {
			return std::fabs(dist);
		}
	}
	double m = std::min((double)p.distance_to(closest_on_segment(p, a, b)), (double)p.distance_to(closest_on_segment(p, b, c)));
	return std::min(m, (double)p.distance_to(closest_on_segment(p, c, a)));
}

// Geometry3D.segment_intersects_triangle (engine algorithm)
inline bool seg_tri(const Vector3 &from, const Vector3 &to, const Vector3 &v0, const Vector3 &v1, const Vector3 &v2) {
	Vector3 rel = to - from;
	Vector3 e1 = v1 - v0;
	Vector3 e2 = v2 - v0;
	Vector3 h = rel.cross(e2);
	real_t a = e1.dot(h);
	if (std::fabs(a) < (real_t)0.00001) {
		return false;
	}
	real_t f = 1.0f / a;
	Vector3 s = from - v0;
	real_t u = f * s.dot(h);
	if (u < 0.0f || u > 1.0f) {
		return false;
	}
	Vector3 q = s.cross(e1);
	real_t v = f * rel.dot(q);
	if (v < 0.0f || u + v > 1.0f) {
		return false;
	}
	real_t t = f * e2.dot(q);
	return t > (real_t)0.00001 && t <= 1.0f;
}

struct TriBox {
	Vector3 lo, hi;
};

bool touching(const Soup &S, const std::vector<int> &ta, const std::vector<int> &tb, const Vector3 &amin0, const Vector3 &amax0, const Vector3 &bmn, const Vector3 &bmx) {
	const real_t tol = (real_t)TOUCH_TOL;
	Vector3 amin = amin0 - Vector3(tol, tol, tol);
	Vector3 amax = amax0 + Vector3(tol, tol, tol);
	if (amax.x < bmn.x || bmx.x < amin.x || amax.y < bmn.y || bmx.y < amin.y || amax.z < bmn.z || bmx.z < amin.z) {
		return false;
	}
	if (ta.empty() || tb.empty()) {
		return false;
	}
	auto boxes = [&](const std::vector<int> &l) {
		std::vector<TriBox> bx(l.size());
		for (size_t k = 0; k < l.size(); k++) {
			int j = l[k];
			const Vector3 &a = S.pa[j], &b = S.pb[j], &c = S.pc[j];
			bx[k].lo = Vector3(std::min(a.x, std::min(b.x, c.x)), std::min(a.y, std::min(b.y, c.y)), std::min(a.z, std::min(b.z, c.z)));
			bx[k].hi = Vector3(std::max(a.x, std::max(b.x, c.x)), std::max(a.y, std::max(b.y, c.y)), std::max(a.z, std::max(b.z, c.z)));
		}
		return bx;
	};
	std::vector<TriBox> bxa = boxes(ta), bxb = boxes(tb);
	const std::vector<int> *src_l[2] = { &ta, &tb };
	const std::vector<int> *dst_l[2] = { &tb, &ta };
	const std::vector<TriBox> *dst_b[2] = { &bxb, &bxa };
	const real_t M = (real_t)0.06; // TOUCH_TOL plus margin: a point further from the box than this cannot be within the tolerance
	int64_t checks = 0;
	for (int pr = 0; pr < 2; pr++) {
		const std::vector<int> &src = *src_l[pr];
		const std::vector<int> &dst = *dst_l[pr];
		const std::vector<TriBox> &db = *dst_b[pr];
		for (int i : src) {
			const Vector3 pts[3] = { S.pa[i], S.pb[i], S.pc[i] };
			for (int k = 0; k < 3; k++) {
				const Vector3 &p = pts[k];
				for (size_t jj = 0; jj < dst.size(); jj++) {
					checks++;
					if (checks > 3000000) {
						return true;
					}
					const TriBox &bb = db[jj];
					if (p.x < bb.lo.x - M || p.x > bb.hi.x + M || p.y < bb.lo.y - M || p.y > bb.hi.y + M || p.z < bb.lo.z - M || p.z > bb.hi.z + M) {
						continue;
					}
					int j = dst[jj];
					if (point_tri_dist(p, S.pa[j], S.pb[j], S.pc[j], S.nn[j]) <= TOUCH_TOL) {
						return true;
					}
				}
			}
		}
	}
	int64_t ed = 0;
	for (int i : ta) {
		const Vector3 sg[3][2] = { { S.pa[i], S.pb[i] }, { S.pb[i], S.pc[i] }, { S.pc[i], S.pa[i] } };
		for (int k = 0; k < 3; k++) {
			Vector3 slo(std::min(sg[k][0].x, sg[k][1].x), std::min(sg[k][0].y, sg[k][1].y), std::min(sg[k][0].z, sg[k][1].z));
			Vector3 shi(std::max(sg[k][0].x, sg[k][1].x), std::max(sg[k][0].y, sg[k][1].y), std::max(sg[k][0].z, sg[k][1].z));
			for (size_t jj = 0; jj < tb.size(); jj++) {
				ed++;
				if (ed > 3000000) {
					return true;
				}
				const TriBox &bb = bxb[jj];
				const real_t m2 = (real_t)0.01;
				if (shi.x < bb.lo.x - m2 || slo.x > bb.hi.x + m2 || shi.y < bb.lo.y - m2 || slo.y > bb.hi.y + m2 || shi.z < bb.lo.z - m2 || slo.z > bb.hi.z + m2) {
					continue;
				}
				int j = tb[jj];
				if (seg_tri(sg[k][0], sg[k][1], S.pa[j], S.pb[j], S.pc[j])) {
					return true;
				}
			}
		}
	}
	const Vector3 dir = Vector3(0.6f, 0.64f, 0.48f).normalized();
	for (int pr = 0; pr < 2; pr++) {
		const std::vector<int> &a = *src_l[pr];
		const std::vector<int> &b = *dst_l[pr];
		int i0 = a[0];
		int inside = 0;
		for (int j : b) {
			if (ray_tri(S.pa[i0], dir, S.pa[j], S.pb[j], S.pc[j]) >= 0.0) {
				inside++;
			}
		}
		if (inside % 2 == 1) {
			return true;
		}
	}
	return false;
}

} // namespace

void KineMeshCheckNative::_bind_methods() {
	ClassDB::bind_static_method("KineMeshCheckNative", D_METHOD("version"), &KineMeshCheckNative::version);
	ClassDB::bind_static_method("KineMeshCheckNative", D_METHOD("scan", "bodies"), &KineMeshCheckNative::scan);
	ClassDB::bind_static_method("KineMeshCheckNative", D_METHOD("edge_check", "t"), &KineMeshCheckNative::edge_check);
	ClassDB::bind_static_method("KineMeshCheckNative", D_METHOD("signed_volume", "v", "t"), &KineMeshCheckNative::signed_volume);
	ClassDB::bind_static_method("KineMeshCheckNative", D_METHOD("bounds", "v"), &KineMeshCheckNative::bounds);
	ClassDB::bind_static_method("KineMeshCheckNative", D_METHOD("feet_hull", "verts", "foot"), &KineMeshCheckNative::feet_hull);
}

int KineMeshCheckNative::version() {
	return 1;
}

Dictionary KineMeshCheckNative::scan(const Array &p_bodies) {
	Soup S;
	const int nb = p_bodies.size();
	std::vector<Vector3> bmin(nb), bmax(nb);
	std::vector<std::vector<int>> bverts(nb);
	int off = 0;
	for (int bi = 0; bi < nb; bi++) {
		Dictionary bd = p_bodies[bi];
		PackedVector3Array v = bd["v"];
		PackedInt32Array t = bd["t"];
		const Vector3 *vp = v.ptr();
		const int32_t *tp = t.ptr();
		Vector3 lo(INFINITY, INFINITY, INFINITY), hi(-INFINITY, -INFINITY, -INFINITY);
		for (int i = 0; i < v.size(); i++) {
			lo = Vector3(std::min(lo.x, vp[i].x), std::min(lo.y, vp[i].y), std::min(lo.z, vp[i].z));
			hi = Vector3(std::max(hi.x, vp[i].x), std::max(hi.y, vp[i].y), std::max(hi.z, vp[i].z));
		}
		bmin[bi] = lo;
		bmax[bi] = hi;
		for (int i = 0; i + 2 < t.size(); i += 3) {
			Vector3 a = vp[tp[i]], b = vp[tp[i + 1]], c = vp[tp[i + 2]];
			Vector3 cr = (b - a).cross(c - a);
			double ar = (double)cr.length() * 0.5;
			if (ar < 1e-9) {
				continue;
			}
			bverts[bi].push_back((int)S.pa.size());
			S.ia.push_back(off + tp[i]);
			S.ib.push_back(off + tp[i + 1]);
			S.ic.push_back(off + tp[i + 2]);
			S.pa.push_back(a);
			S.pb.push_back(b);
			S.pc.push_back(c);
			S.nn.push_back(cr.normalized());
			S.body.push_back(bi);
			S.area.push_back((float)ar);
		}
		off += v.size();
	}
	const int nt = (int)S.pa.size();
	for (int i = 0; i < nt; i++) {
		const Vector3 &a = S.pa[i], &b = S.pb[i], &c = S.pc[i];
		int c0x = cell_of(std::min(a.x, std::min(b.x, c.x))), c0y = cell_of(std::min(a.y, std::min(b.y, c.y))), c0z = cell_of(std::min(a.z, std::min(b.z, c.z)));
		int c1x = cell_of(std::max(a.x, std::max(b.x, c.x))), c1y = cell_of(std::max(a.y, std::max(b.y, c.y))), c1z = cell_of(std::max(a.z, std::max(b.z, c.z)));
		for (int x = c0x; x <= c1x; x++) {
			for (int y = c0y; y <= c1y; y++) {
				for (int z = c0z; z <= c1z; z++) {
					S.grid[ckey(x, y, z)].push_back(i);
				}
			}
		}
	}

	// ---- thin walls
	std::unordered_map<int, int> parent;
	std::vector<std::pair<int, int>> thin_pairs; // (triangle, partner)
	double thinnest = INFINITY;
	for (int i = 0; i < nt; i++) {
		double best = INFINITY;
		int bj = -1;
		for (int s = 0; s < 4; s++) {
			Vector3 q;
			switch (s) {
				case 0:
					q = (S.pa[i] + S.pb[i] + S.pc[i]) / (real_t)3.0;
					break;
				case 1:
					q = (S.pa[i] * (real_t)2.0 + S.pb[i] + S.pc[i]) * (real_t)0.25;
					break;
				case 2:
					q = (S.pa[i] + S.pb[i] * (real_t)2.0 + S.pc[i]) * (real_t)0.25;
					break;
				default:
					q = (S.pa[i] + S.pb[i] + S.pc[i] * (real_t)2.0) * (real_t)0.25;
			}
			Vector3 o = q - S.nn[i] * (real_t)0.001;
			double bt;
			int hj;
			if (hit(S, o, -S.nn[i], THIN_MM + 0.002, i, S.body[i], 1, bt, hj)) {
				if (bt + 0.001 < best) {
					best = bt + 0.001;
					bj = hj;
				}
			}
		}
		if (best < THIN_MM - 0.0005) {
			thin_pairs.push_back({ i, bj });
			parent[i] = i;
			thinnest = std::min(thinnest, best);
		}
	}
	for (auto &pr : thin_pairs) {
		if (!parent.count(pr.second)) {
			parent[pr.second] = pr.second;
		}
	}
	for (auto &pr : thin_pairs) {
		uf_union(parent, pr.first, pr.second);
	}
	std::unordered_map<uint64_t, std::vector<int>> edge_tris;
	for (auto &kv : parent) {
		int i = kv.first;
		int e[3][2] = { { S.ia[i], S.ib[i] }, { S.ib[i], S.ic[i] }, { S.ic[i], S.ia[i] } };
		for (int k = 0; k < 3; k++) {
			uint64_t key = ((uint64_t)std::min(e[k][0], e[k][1]) << 32) | (uint64_t)std::max(e[k][0], e[k][1]);
			edge_tris[key].push_back(i);
		}
	}
	for (auto &kv : edge_tris) {
		const std::vector<int> &l = kv.second;
		for (size_t x = 0; x < l.size(); x++) {
			for (size_t y = x + 1; y < l.size(); y++) {
				if (S.nn[l[x]].dot(S.nn[l[y]]) > 0.966) {
					uf_union(parent, l[x], l[y]);
				}
			}
		}
	}
	std::unordered_map<int, bool> roots;
	std::vector<int> keys;
	for (auto &kv : parent) {
		keys.push_back(kv.first);
	}
	for (int i : keys) {
		roots[uf_find(parent, i)] = true;
	}
	int walls = (int)roots.size();

	// ---- overhangs
	const double down_z = -std::sin(OVERHANG_DEG * 3.14159265358979323846 / 180.0) - 1e-4;
	double over_mm2 = 0.0;
	for (int i = 0; i < nt; i++) {
		if (S.nn[i].z >= down_z) {
			continue;
		}
		if (std::max(S.pa[i].z, std::max(S.pb[i].z, S.pc[i].z)) <= BED_TOL) {
			continue;
		}
		Vector3 cen = (S.pa[i] + S.pb[i] + S.pc[i]) / (real_t)3.0;
		double bt;
		int hj;
		if (hit(S, cen + Vector3(0, 0, (real_t)0.001), Vector3(0, 0, -1), SUPPORT_MM + 0.002, i, -1, 2, bt, hj)) {
			continue;
		}
		over_mm2 += (double)S.area[i];
	}

	// ---- floating pieces
	std::vector<char> reach(nb);
	for (int bi = 0; bi < nb; bi++) {
		reach[bi] = nb > 0 && bmin[bi].z <= BED_TOL && !std::isinf(bmin[bi].z);
	}
	std::unordered_map<int, bool> touch;
	bool changed = true;
	while (changed) {
		changed = false;
		for (int a = 0; a < nb; a++) {
			for (int b = 0; b < nb; b++) {
				if (a == b || !reach[a] || reach[b]) {
					continue;
				}
				int k = a * 1000 + b;
				auto it = touch.find(k);
				if (it == touch.end()) {
					bool r = touching(S, bverts[a], bverts[b], bmin[a], bmax[a], bmin[b], bmax[b]);
					touch[k] = r;
					touch[b * 1000 + a] = r;
					it = touch.find(k);
				}
				if (it->second) {
					reach[b] = 1;
					changed = true;
				}
			}
		}
	}
	int floating = 0;
	double lowest = INFINITY;
	for (int bi = 0; bi < nb; bi++) {
		if (!reach[bi]) {
			floating++;
			lowest = std::min(lowest, (double)bmin[bi].z);
		}
	}
	Dictionary out;
	out["walls"] = walls;
	out["thinnest"] = thinnest;
	out["over_mm2"] = over_mm2;
	out["floating"] = floating;
	out["lowest"] = lowest;
	out["tris"] = nt;
	return out;
}

Dictionary KineMeshCheckNative::edge_check(const PackedInt32Array &p_t) {
	const int32_t *t = p_t.ptr();
	const int n = p_t.size();
	std::vector<std::pair<uint64_t, int>> ev;
	ev.reserve((size_t)n);
	for (int i = 0; i + 2 < n; i += 3) {
		for (int k = 0; k < 3; k++) {
			int a = t[i + k], c = t[i + (k + 1) % 3];
			ev.push_back({ ((uint64_t)std::min(a, c) << 32) | (uint64_t)std::max(a, c), a < c ? 1 : -1 });
		}
	}
	std::sort(ev.begin(), ev.end());
	int open = 0, bad = 0;
	for (size_t i = 0; i < ev.size();) {
		size_t j = i;
		int dirs = 0;
		while (j < ev.size() && ev[j].first == ev[i].first) {
			dirs += ev[j].second;
			j++;
		}
		int cnt = (int)(j - i);
		if (cnt == 1) {
			open++;
		} else if (cnt > 2 || dirs != 0) {
			bad++;
		}
		i = j;
	}
	Dictionary d;
	d["tris"] = n / 3;
	d["open"] = open;
	d["bad"] = bad;
	return d;
}

double KineMeshCheckNative::signed_volume(const PackedVector3Array &p_v, const PackedInt32Array &p_t) {
	const Vector3 *v = p_v.ptr();
	const int32_t *t = p_t.ptr();
	double s = 0.0;
	for (int i = 0; i + 2 < p_t.size(); i += 3) {
		s += (double)v[t[i]].dot(v[t[i + 1]].cross(v[t[i + 2]]));
	}
	return s / 6.0;
}

PackedVector3Array KineMeshCheckNative::bounds(const PackedVector3Array &p_v) {
	PackedVector3Array out;
	if (p_v.size() == 0) {
		return out;
	}
	const Vector3 *v = p_v.ptr();
	Vector3 lo = v[0], hi = v[0];
	for (int i = 1; i < p_v.size(); i++) {
		lo = Vector3(std::min(lo.x, v[i].x), std::min(lo.y, v[i].y), std::min(lo.z, v[i].z));
		hi = Vector3(std::max(hi.x, v[i].x), std::max(hi.y, v[i].y), std::max(hi.z, v[i].z));
	}
	out.push_back(lo);
	out.push_back(hi);
	return out;
}

PackedVector2Array KineMeshCheckNative::feet_hull(const PackedVector3Array &p_verts, double p_foot) {
	const Vector3 *v = p_verts.ptr();
	const int n = p_verts.size();
	double lo = INFINITY;
	for (int i = 0; i < n; i++) {
		lo = std::min(lo, (double)v[i].y);
	}
	std::vector<Vector2> p;
	for (int i = 0; i < n; i++) {
		if (v[i].y <= lo + p_foot) {
			p.push_back(Vector2(v[i].x, v[i].z));
		}
	}
	std::stable_sort(p.begin(), p.end(), [](const Vector2 &a, const Vector2 &b) { return a.x < b.x || (a.x == b.x && a.y < b.y); });
	std::vector<Vector2> uniq;
	for (const Vector2 &q : p) {
		if (uniq.empty() || !uniq.back().is_equal_approx(q)) {
			uniq.push_back(q);
		}
	}
	PackedVector2Array out;
	if (uniq.size() < 3) {
		for (const Vector2 &q : uniq) {
			out.push_back(q);
		}
		return out;
	}
	auto cross = [](const Vector2 &o, const Vector2 &a, const Vector2 &b) { return (a - o).cross(b - o); };
	std::vector<Vector2> lower, upper;
	for (const Vector2 &q : uniq) {
		while (lower.size() >= 2 && cross(lower[lower.size() - 2], lower.back(), q) <= 0.0f) {
			lower.pop_back();
		}
		lower.push_back(q);
	}
	for (int i = (int)uniq.size() - 1; i >= 0; i--) {
		const Vector2 &q = uniq[i];
		while (upper.size() >= 2 && cross(upper[upper.size() - 2], upper.back(), q) <= 0.0f) {
			upper.pop_back();
		}
		upper.push_back(q);
	}
	lower.pop_back();
	upper.pop_back();
	for (const Vector2 &q : lower) {
		out.push_back(q);
	}
	for (const Vector2 &q : upper) {
		out.push_back(q);
	}
	return out;
}
