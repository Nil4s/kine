// scripts/kmesh_boolean.gd (class _Run) in C++, statement for statement, without the attribute carry (the GDScript twin keeps that).
// Dictionaries that the GDScript iterates keep their insertion order here (pts, dir, nxt); the others are lookups only.
#pragma GCC optimize("fp-contract=off")
#include "kine_kmesh_native.h"
#include "kine_kmesh_common.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace godot;
using namespace kmesh;

namespace {

const double INF = std::numeric_limits<double>::infinity();
const double TAU_ = 6.283185307179586;

struct CellKey {
	int32_t x, y, z;
	bool operator==(const CellKey &o) const { return x == o.x && y == o.y && z == o.z; }
};
struct CellHash {
	size_t operator()(const CellKey &k) const {
		uint64_t h = (uint64_t)(uint32_t)k.x * 73856093ULL ^ (uint64_t)(uint32_t)k.y * 19349663ULL ^ (uint64_t)(uint32_t)k.z * 83492791ULL;
		h ^= h >> 29;
		return (size_t)h;
	}
};

typedef std::vector<int32_t> IVec;

struct Run {
	double eps = 1e-6;
	double cellsz = 2e-6;
	std::vector<double> px, py, pz;
	IVec uf;
	std::unordered_map<CellKey, int32_t, CellHash> head;
	IVec chain;
	double ob[6] = { 0, 0, 0, 0, 0, 0 };
	int na = 0;
	IVec tv, tface;
	std::vector<double> tn, td;
	IVec tax;
	std::vector<IVec> pts, segs, copl;
	std::vector<int32_t> pts_order;
	std::unordered_map<int64_t, IVec> epts;
	IVec cut_list;
	std::vector<uint8_t> face_cut[2];
	IVec face_ntri[2];
	IVec vg[2];
	IVec pv, ptri;
	// stats
	int64_t st_pairs = 0, st_segments = 0, st_coplanar = 0, st_split = 0, st_pieces = 0, st_patches = 0, st_unresolved = 0, st_clamped = 0, st_aliased = 0, st_ngons = 0, st_as_were = 0, st_tri_faces = 0;
	// the local triangulation
	double _u = 0.0, _v = 0.0;
	IVec l_ids;
	std::vector<double> l_u, l_v;
	IVec l_al, l_tris;
	std::unordered_set<int64_t> l_cons;

	static int64_t ekey(int64_t a, int64_t b) { return (std::min(a, b) << 32) | std::max(a, b); }

	int find(int i) {
		while (uf[i] != i) {
			uf[i] = uf[uf[i]];
			i = uf[i];
		}
		return i;
	}
	void join(int a, int b) {
		int ra = find(a);
		int rb = find(b);
		if (ra != rb) {
			uf[std::max(ra, rb)] = std::min(ra, rb);
			st_aliased++;
		}
	}
	bool in_ob(double x, double y, double z) const {
		return x >= ob[0] && y >= ob[1] && z >= ob[2] && x <= ob[3] && y <= ob[4] && z <= ob[5];
	}
	int add_point(double x, double y, double z) {
		bool hashed = in_ob(x, y, z);
		CellKey c{ 0, 0, 0 };
		if (hashed) {
			c = CellKey{ (int32_t)(int64_t)std::floor(x / cellsz), (int32_t)(int64_t)std::floor(y / cellsz), (int32_t)(int64_t)std::floor(z / cellsz) };
			double e2 = eps * eps;
			for (int dx = -1; dx < 2; dx++) {
				for (int dy = -1; dy < 2; dy++) {
					for (int dz = -1; dz < 2; dz++) {
						auto it = head.find(CellKey{ c.x + dx, c.y + dy, c.z + dz });
						int q = it == head.end() ? -1 : it->second;
						while (q != -1) {
							double ddx = px[q] - x;
							double ddy = py[q] - y;
							double ddz = pz[q] - z;
							if (ddx * ddx + ddy * ddy + ddz * ddz <= e2) {
								return find(q);
							}
							q = chain[q];
						}
					}
				}
			}
		}
		int id = (int)px.size();
		px.push_back(x);
		py.push_back(y);
		pz.push_back(z);
		uf.push_back(id);
		chain.push_back(-1);
		if (hashed) {
			auto it = head.find(c);
			chain[id] = it == head.end() ? -1 : it->second;
			head[c] = id;
		}
		return id;
	}

	void add_tri(int a, int b, int c, int fi) {
		tv.push_back(a);
		tv.push_back(b);
		tv.push_back(c);
		tface.push_back(fi);
		double ux = px[b] - px[a];
		double uy = py[b] - py[a];
		double uz = pz[b] - pz[a];
		double vx = px[c] - px[a];
		double vy = py[c] - py[a];
		double vz = pz[c] - pz[a];
		double nx = uy * vz - uz * vy;
		double ny = uz * vx - ux * vz;
		double nz = ux * vy - uy * vx;
		double l = std::sqrt(nx * nx + ny * ny + nz * nz);
		if (l > 1e-300) {
			nx /= l;
			ny /= l;
			nz /= l;
		} else {
			nx = 0.0;
			ny = 0.0;
			nz = 0.0;
		}
		tn.push_back(nx);
		tn.push_back(ny);
		tn.push_back(nz);
		td.push_back(nx * px[a] + ny * py[a] + nz * pz[a]);
		double ax = std::fabs(nx);
		double ay = std::fabs(ny);
		double az = std::fabs(nz);
		int k = 0;
		double comp = nx;
		if (ay > ax && ay >= az) {
			k = 1;
			comp = ny;
		} else if (az > ax && az > ay) {
			k = 2;
			comp = nz;
		}
		tax.push_back(k * 2 + (comp < 0.0 ? 1 : 0));
	}

	bool degen(int t) const { return tn[3 * t] == 0.0 && tn[3 * t + 1] == 0.0 && tn[3 * t + 2] == 0.0; }

	// ---------------------------------------------------------------- broad phase
	void box(int t, double *out) const {
		int a = tv[3 * t];
		int b = tv[3 * t + 1];
		int c = tv[3 * t + 2];
		out[0] = std::min(px[a], std::min(px[b], px[c]));
		out[1] = std::min(py[a], std::min(py[b], py[c]));
		out[2] = std::min(pz[a], std::min(pz[b], pz[c]));
		out[3] = std::max(px[a], std::max(px[b], px[c]));
		out[4] = std::max(py[a], std::max(py[b], py[c]));
		out[5] = std::max(pz[a], std::max(pz[b], pz[c]));
	}

	static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

	void cells(const std::vector<double> &bx, int t, const double *csz, int res, int *rng) const {
		for (int k = 0; k < 3; k++) {
			rng[k] = clampi((int)(int64_t)std::floor((std::max(bx[t * 6 + k], ob[k]) - ob[k]) / csz[k]), 0, res - 1);
			rng[3 + k] = clampi((int)(int64_t)std::floor((std::min(bx[t * 6 + 3 + k], ob[3 + k]) - ob[k]) / csz[k]), 0, res - 1);
		}
	}

	void broad() {
		int nt = (int)tface.size();
		std::vector<double> bx((size_t)nt * 6);
		double tmp[6];
		IVec ins, ina;
		for (int t = 0; t < nt; t++) {
			box(t, tmp);
			for (int k = 0; k < 6; k++) {
				bx[(size_t)t * 6 + k] = tmp[k];
			}
			if (tmp[3] < ob[0] || tmp[4] < ob[1] || tmp[5] < ob[2] || tmp[0] > ob[3] || tmp[1] > ob[4] || tmp[2] > ob[5]) {
				continue;
			}
			if (t < na) {
				ina.push_back(t);
			} else {
				ins.push_back(t);
			}
		}
		if (ins.empty() || ina.empty()) {
			return;
		}
		int res = clampi((int)std::ceil(std::pow((double)ins.size(), 1.0 / 3.0) * 1.5), 1, 48);
		double csz[3] = { std::max((ob[3] - ob[0]) / res, 1e-12), std::max((ob[4] - ob[1]) / res, 1e-12), std::max((ob[5] - ob[2]) / res, 1e-12) };
		int ncell = res * res * res;
		IVec start(ncell + 1, 0);
		int rng[6];
		IVec lst;
		IVec fill;
		for (int pass_i = 0; pass_i < 2; pass_i++) {
			if (pass_i == 1) {
				int acc = 0;
				for (int ci = 0; ci < ncell; ci++) {
					int n = start[ci];
					start[ci] = acc;
					acc += n;
				}
				start[ncell] = acc;
				fill = start;
				lst.assign(start[ncell], 0);
			}
			for (int t : ins) {
				cells(bx, t, csz, res, rng);
				for (int ix = rng[0]; ix <= rng[3]; ix++) {
					for (int iy = rng[1]; iy <= rng[4]; iy++) {
						for (int iz = rng[2]; iz <= rng[5]; iz++) {
							int ci = (ix * res + iy) * res + iz;
							if (pass_i == 0) {
								start[ci] += 1;
							} else {
								lst[fill[ci]] = t;
								fill[ci] += 1;
							}
						}
					}
				}
			}
		}
		// query
		IVec stamp(tface.size(), -1);
		for (int ta : ina) {
			cells(bx, ta, csz, res, rng);
			for (int ix = rng[0]; ix <= rng[3]; ix++) {
				for (int iy = rng[1]; iy <= rng[4]; iy++) {
					for (int iz = rng[2]; iz <= rng[5]; iz++) {
						int ci = (ix * res + iy) * res + iz;
						for (int j = start[ci]; j < start[ci + 1]; j++) {
							int tb = lst[j];
							if (stamp[tb] == ta) {
								continue;
							}
							stamp[tb] = ta;
							if (bx[ta * 6 + 3] < bx[tb * 6] - eps || bx[tb * 6 + 3] < bx[ta * 6] - eps || bx[ta * 6 + 4] < bx[tb * 6 + 1] - eps ||
									bx[tb * 6 + 4] < bx[ta * 6 + 1] - eps || bx[ta * 6 + 5] < bx[tb * 6 + 2] - eps || bx[tb * 6 + 5] < bx[ta * 6 + 2] - eps) {
								continue;
							}
							pair(ta, tb);
						}
					}
				}
			}
		}
	}

	// ---------------------------------------------------------------- triangle / triangle
	double sd(int t, int p) const {
		double d = tn[3 * t] * px[p] + tn[3 * t + 1] * py[p] + tn[3 * t + 2] * pz[p] - td[t];
		return std::fabs(d) < eps ? 0.0 : d;
	}

	void push_pts(int t, int v) {
		if (pts[t].empty()) {
			pts_order.push_back(t);
		}
		pts[t].push_back(v);
	}

	void add_seg(int t, int p, int q) {
		if (find(p) == find(q)) {
			return;
		}
		segs[t].push_back(p);
		segs[t].push_back(q);
		push_pts(t, p);
		push_pts(t, q);
	}

	int cross_pt(int u, int v, double su, double sv) {
		if (u > v) {
			std::swap(u, v);
			std::swap(su, sv);
		}
		double f = su / (su - sv);
		return add_point(px[u] + (px[v] - px[u]) * f, py[u] + (py[v] - py[u]) * f, pz[u] + (pz[v] - pz[u]) * f);
	}

	int cut(int t, double r0, double r1, double r2, int *out) {
		int n = 0;
		int c[3] = { tv[3 * t], tv[3 * t + 1], tv[3 * t + 2] };
		double s[3] = { r0, r1, r2 };
		for (int i = 0; i < 3; i++) {
			if (s[i] == 0.0) {
				out[n++] = c[i];
			}
		}
		for (int i = 0; i < 3; i++) {
			int j = (i + 1) % 3;
			if ((s[i] > 0.0 && s[j] < 0.0) || (s[i] < 0.0 && s[j] > 0.0)) {
				out[n++] = cross_pt(c[i], c[j], s[i], s[j]);
			}
		}
		return n;
	}

	void pair(int ta, int tb) {
		st_pairs++;
		if (degen(ta) || degen(tb)) {
			return;
		}
		double s0 = sd(ta, tv[3 * tb]);
		double s1 = sd(ta, tv[3 * tb + 1]);
		double s2 = sd(ta, tv[3 * tb + 2]);
		if ((s0 > 0.0 && s1 > 0.0 && s2 > 0.0) || (s0 < 0.0 && s1 < 0.0 && s2 < 0.0)) {
			return;
		}
		double r0 = sd(tb, tv[3 * ta]);
		double r1 = sd(tb, tv[3 * ta + 1]);
		double r2 = sd(tb, tv[3 * ta + 2]);
		if ((r0 > 0.0 && r1 > 0.0 && r2 > 0.0) || (r0 < 0.0 && r1 < 0.0 && r2 < 0.0)) {
			return;
		}
		if ((s0 == 0.0 && s1 == 0.0 && s2 == 0.0) || (r0 == 0.0 && r1 == 0.0 && r2 == 0.0)) {
			coplanar(ta, tb);
			return;
		}
		int ia[8], ib[8];
		int na_ = cut(ta, r0, r1, r2, ia);
		int nb_ = cut(tb, s0, s1, s2, ib);
		if (na_ < 2 || nb_ < 2) {
			return;
		}
		double ax = tn[3 * ta];
		double ay = tn[3 * ta + 1];
		double az = tn[3 * ta + 2];
		double bxn = tn[3 * tb];
		double byn = tn[3 * tb + 1];
		double bzn = tn[3 * tb + 2];
		double dx = ay * bzn - az * byn;
		double dy = az * bxn - ax * bzn;
		double dz = ax * byn - ay * bxn;
		double dl = std::sqrt(dx * dx + dy * dy + dz * dz);
		double fa0 = dx * px[ia[0]] + dy * py[ia[0]] + dz * pz[ia[0]];
		double fa1 = dx * px[ia[1]] + dy * py[ia[1]] + dz * pz[ia[1]];
		double fb0 = dx * px[ib[0]] + dy * py[ib[0]] + dz * pz[ib[0]];
		double fb1 = dx * px[ib[1]] + dy * py[ib[1]] + dz * pz[ib[1]];
		int alo = ia[0];
		int ahi = ia[1];
		if (fa0 > fa1) {
			alo = ia[1];
			ahi = ia[0];
			std::swap(fa0, fa1);
		}
		int blo = ib[0];
		int bhi = ib[1];
		if (fb0 > fb1) {
			blo = ib[1];
			bhi = ib[0];
			std::swap(fb0, fb1);
		}
		double lo = fa0;
		int lo_id = alo;
		if (fb0 > fa0) {
			lo = fb0;
			lo_id = blo;
		}
		double hi = fa1;
		int hi_id = ahi;
		if (fb1 < fa1) {
			hi = fb1;
			hi_id = bhi;
		}
		if (hi - lo <= eps * dl) {
			return;
		}
		st_segments++;
		add_seg(ta, lo_id, hi_id);
		add_seg(tb, lo_id, hi_id);
	}

	void coplanar(int ta, int tb) {
		st_coplanar++;
		copl[ta].push_back(tb);
		copl[tb].push_back(ta);
		for (int pair_i = 0; pair_i < 2; pair_i++) {
			int into = pair_i == 0 ? ta : tb;
			int from = pair_i == 0 ? tb : ta;
			for (int e = 0; e < 3; e++) {
				int s[2];
				if (!clip(into, tv[3 * from + e], tv[3 * from + (e + 1) % 3], s)) {
					continue;
				}
				add_seg(into, s[0], s[1]);
				push_pts(from, s[0]);
				push_pts(from, s[1]);
			}
		}
	}

	bool clip(int t, int u, int v, int *res) {
		if (u > v) {
			std::swap(u, v);
		}
		int k = tax[t];
		double t0 = 0.0;
		double t1 = 1.0;
		for (int e = 0; e < 3; e++) {
			int a = tv[3 * t + e];
			int b = tv[3 * t + (e + 1) % 3];
			double du = d2(k, a, b, u);
			double dv = d2(k, a, b, v);
			if (du < -eps && dv < -eps) {
				return false;
			}
			if (du < -eps) {
				t0 = std::max(t0, du / (du - dv));
			} else if (dv < -eps) {
				t1 = std::min(t1, du / (du - dv));
			}
		}
		double lx = px[v] - px[u];
		double ly = py[v] - py[u];
		double lz = pz[v] - pz[u];
		double ln = std::sqrt(lx * lx + ly * ly + lz * lz);
		if ((t1 - t0) * ln <= eps) {
			return false;
		}
		int p = t0 * ln <= eps ? u : add_point(px[u] + lx * t0, py[u] + ly * t0, pz[u] + lz * t0);
		int q = (1.0 - t1) * ln <= eps ? v : add_point(px[u] + lx * t1, py[u] + ly * t1, pz[u] + lz * t1);
		if (find(p) == find(q)) {
			return false;
		}
		res[0] = p;
		res[1] = q;
		return true;
	}

	void pr(int k, double x, double y, double z) {
		switch (k) {
			case 0: _u = y; _v = z; break;
			case 1: _u = z; _v = y; break;
			case 2: _u = z; _v = x; break;
			case 3: _u = x; _v = z; break;
			case 4: _u = x; _v = y; break;
			default: _u = y; _v = x; break;
		}
	}

	double d2(int k, int a, int b, int p) { return d2xyz(k, a, b, px[p], py[p], pz[p]); }

	double d2xyz(int k, int a, int b, double x, double y, double z) {
		pr(k, px[a], py[a], pz[a]);
		double au = _u;
		double av = _v;
		pr(k, px[b], py[b], pz[b]);
		double bu = _u - au;
		double bv = _v - av;
		pr(k, x, y, z);
		double l = std::sqrt(bu * bu + bv * bv);
		if (l <= 1e-300) {
			return 0.0;
		}
		return (bu * (_v - av) - bv * (_u - au)) / l;
	}

	// ---------------------------------------------------------------- splitting
	bool on_edge(int p, int a, int b) const {
		double ex = px[b] - px[a];
		double ey = py[b] - py[a];
		double ez = pz[b] - pz[a];
		double l2 = ex * ex + ey * ey + ez * ez;
		if (l2 <= 0.0) {
			return false;
		}
		double wx = px[p] - px[a];
		double wy = py[p] - py[a];
		double wz = pz[p] - pz[a];
		double t = (wx * ex + wy * ey + wz * ez) / l2;
		double l = std::sqrt(l2);
		if (t * l <= eps || (1.0 - t) * l <= eps) {
			return false;
		}
		double cx = wx - ex * t;
		double cy = wy - ey * t;
		double cz = wz - ez * t;
		return cx * cx + cy * cy + cz * cz <= eps * eps;
	}

	void split_all() {
		for (int t : pts_order) {
			std::unordered_set<int> seen;
			for (int p0 : pts[t]) {
				int p = find(p0);
				if (seen.count(p)) {
					continue;
				}
				seen.insert(p);
				for (int e = 0; e < 3; e++) {
					int a = find(tv[3 * t + e]);
					int b = find(tv[3 * t + (e + 1) % 3]);
					if (p != a && p != b && on_edge(p, a, b)) {
						epts[ekey(a, b)].push_back(p);
					}
				}
			}
		}
		int nt = (int)tface.size();
		for (int t = 0; t < nt; t++) {
			IVec extra;
			if (!pts[t].empty()) {
				extra.insert(extra.end(), pts[t].begin(), pts[t].end());
			}
			if (!epts.empty()) {
				for (int e = 0; e < 3; e++) {
					int64_t k = ekey(find(tv[3 * t + e]), find(tv[3 * t + (e + 1) % 3]));
					auto it = epts.find(k);
					if (it != epts.end()) {
						extra.insert(extra.end(), it->second.begin(), it->second.end());
					}
				}
			}
			if (extra.empty() || degen(t)) {
				pv.push_back(tv[3 * t]);
				pv.push_back(tv[3 * t + 1]);
				pv.push_back(tv[3 * t + 2]);
				ptri.push_back(t);
				continue;
			}
			st_split++;
			face_cut[t < na ? 0 : 1][tface[t]] = 1;
			split(t, extra, segs[t]);
		}
		st_pieces = (int64_t)ptri.size();
	}

	double ld(int a, int b, int p) const {
		double bu = l_u[b] - l_u[a];
		double bv = l_v[b] - l_v[a];
		double l = std::sqrt(bu * bu + bv * bv);
		if (l <= 1e-300) {
			return 0.0;
		}
		return (bu * (l_v[p] - l_v[a]) - bv * (l_u[p] - l_u[a])) / l;
	}

	int lres(int i) const {
		while (l_al[i] != i) {
			i = l_al[i];
		}
		return i;
	}

	void split(int t, const IVec &extra, const IVec &sg) {
		int k = tax[t];
		l_ids.clear();
		l_u.clear();
		l_v.clear();
		std::unordered_map<int, int> loc;
		for (int i = 0; i < 3; i++) {
			int g = find(tv[3 * t + i]);
			auto it = loc.find(g);
			loc[g] = it == loc.end() ? (int)l_ids.size() : it->second;
			l_ids.push_back(g);
			pr(k, px[g], py[g], pz[g]);
			l_u.push_back(_u);
			l_v.push_back(_v);
		}
		for (int p0 : extra) {
			int g = find(p0);
			if (loc.count(g)) {
				continue;
			}
			loc[g] = (int)l_ids.size();
			l_ids.push_back(g);
			pr(k, px[g], py[g], pz[g]);
			l_u.push_back(_u);
			l_v.push_back(_v);
		}
		l_al.clear();
		for (int i = 0; i < (int)l_ids.size(); i++) {
			l_al.push_back(i);
		}
		l_tris.assign({ 0, 1, 2 });
		l_cons.clear();
		for (int i = 3; i < (int)l_ids.size(); i++) {
			ins(i);
		}
		for (int j = 0; j + 1 < (int)sg.size(); j += 2) {
			auto ip = loc.find(find(sg[j]));
			auto iq = loc.find(find(sg[j + 1]));
			int p = ip == loc.end() ? -1 : ip->second;
			int q = iq == loc.end() ? -1 : iq->second;
			if (p < 0 || q < 0) {
				continue;
			}
			force(lres(p), lres(q));
		}
		for (int j = 0; j < (int)l_tris.size(); j += 3) {
			int a = l_ids[lres(l_tris[j])];
			int b = l_ids[lres(l_tris[j + 1])];
			int c = l_ids[lres(l_tris[j + 2])];
			if (a == b || b == c || c == a) {
				continue;
			}
			pv.push_back(a);
			pv.push_back(b);
			pv.push_back(c);
			ptri.push_back(t);
		}
		for (int64_t key : l_cons) {
			cut_list.push_back(l_ids[key >> 32]);
			cut_list.push_back(l_ids[key & 0xFFFFFFFF]);
		}
	}

	void set_tri(int k, int a, int b, int c) {
		l_tris[3 * k] = a;
		l_tris[3 * k + 1] = b;
		l_tris[3 * k + 2] = c;
	}
	void add_ltri(int a, int b, int c) {
		l_tris.push_back(a);
		l_tris.push_back(b);
		l_tris.push_back(c);
	}
	int find_ltri(int a, int b) const {
		int n = (int)l_tris.size() / 3;
		for (int k = 0; k < n; k++) {
			for (int e = 0; e < 3; e++) {
				if (l_tris[3 * k + e] == a && l_tris[3 * k + (e + 1) % 3] == b) {
					return k;
				}
			}
		}
		return -1;
	}
	int third(int k, int a, int b) const {
		for (int e = 0; e < 3; e++) {
			int x = l_tris[3 * k + e];
			if (x != a && x != b) {
				return x;
			}
		}
		return -1;
	}

	void ins(int i) {
		int nt = (int)l_tris.size() / 3;
		int best = 0;
		double bm = -INF;
		double b0 = 0.0, b1 = 0.0, b2 = 0.0;
		for (int k = 0; k < nt; k++) {
			int a = l_tris[3 * k];
			int b = l_tris[3 * k + 1];
			int c = l_tris[3 * k + 2];
			double d0 = ld(a, b, i);
			double d1 = ld(b, c, i);
			double d2_ = ld(c, a, i);
			double m = std::min(d0, std::min(d1, d2_));
			if (m > bm) {
				bm = m;
				best = k;
				b0 = d0;
				b1 = d1;
				b2 = d2_;
			}
			if (m > eps) {
				break;
			}
		}
		int a = l_tris[3 * best];
		int b = l_tris[3 * best + 1];
		int c = l_tris[3 * best + 2];
		bool n0 = b0 <= eps;
		bool n1 = b1 <= eps;
		bool n2 = b2 <= eps;
		if (bm < -eps) {
			st_clamped++;
			n0 = b0 == bm;
			n1 = (!n0) && b1 == bm;
			n2 = (!n0) && (!n1);
		}
		int cnt = (int)n0 + (int)n1 + (int)n2;
		if (cnt >= 2) {
			int v = (n0 && n1) ? b : ((n1 && n2) ? c : a);
			if (cnt == 3) {
				double dv = INF;
				int ws[3] = { a, b, c };
				for (int w : ws) {
					double dd = std::pow(l_u[w] - l_u[i], 2.0) + std::pow(l_v[w] - l_v[i], 2.0);
					if (dd < dv) {
						dv = dd;
						v = w;
					}
				}
			}
			l_al[i] = v;
			join(l_ids[i], l_ids[v]);
			return;
		}
		if (cnt == 1) {
			int u = a;
			int w = b;
			int o = c;
			if (n1) {
				u = b;
				w = c;
				o = a;
			} else if (n2) {
				u = c;
				w = a;
				o = b;
			}
			set_tri(best, u, i, o);
			add_ltri(i, w, o);
			int j = find_ltri(w, u);
			if (j >= 0) {
				int z = third(j, w, u);
				set_tri(j, w, i, z);
				add_ltri(i, u, z);
			}
			return;
		}
		set_tri(best, a, b, i);
		add_ltri(b, c, i);
		add_ltri(c, a, i);
	}

	void force(int p, int q) {
		IVec stack = { p, q };
		while (stack.size() >= 2) {
			int b = stack[stack.size() - 1];
			int a = stack[stack.size() - 2];
			stack.resize(stack.size() - 2);
			if (a == b) {
				continue;
			}
			double lu = l_u[b] - l_u[a];
			double lv = l_v[b] - l_v[a];
			double l2 = lu * lu + lv * lv;
			double l = std::sqrt(l2);
			int mid = -1;
			for (int v = 0; v < (int)l_ids.size(); v++) {
				if (v == a || v == b || l_al[v] != v) {
					continue;
				}
				if (std::fabs(ld(a, b, v)) > eps) {
					continue;
				}
				double tt = ((l_u[v] - l_u[a]) * lu + (l_v[v] - l_v[a]) * lv) / std::max(l2, 1e-300);
				if (tt * l > eps && (1.0 - tt) * l > eps) {
					mid = v;
					break;
				}
			}
			if (mid >= 0) {
				stack.push_back(a);
				stack.push_back(mid);
				stack.push_back(mid);
				stack.push_back(b);
				continue;
			}
			if (find_ltri(a, b) < 0 && find_ltri(b, a) < 0) {
				flip_to(a, b);
				if (find_ltri(a, b) < 0 && find_ltri(b, a) < 0) {
					st_unresolved++;
					continue;
				}
			}
			l_cons.insert(((int64_t)std::min(a, b) << 32) | (int64_t)std::max(a, b));
		}
	}

	bool xing(int p, int q, int u, int v) const {
		double du = ld(p, q, u);
		double dv = ld(p, q, v);
		if (!((du > 0.0 && dv < 0.0) || (du < 0.0 && dv > 0.0))) {
			return false;
		}
		double dp = ld(u, v, p);
		double dq = ld(u, v, q);
		return (dp > 0.0 && dq < 0.0) || (dp < 0.0 && dq > 0.0);
	}

	void flip_to(int p, int q) {
		int nt = (int)l_tris.size() / 3;
		int64_t cap = 64 + 4 * (int64_t)nt * nt;
		for (int64_t guard = 0; guard < cap; guard++) {
			bool crossing = false;
			bool done = false;
			for (int k = 0; k < nt; k++) {
				for (int e = 0; e < 3; e++) {
					int u = l_tris[3 * k + e];
					int v = l_tris[3 * k + (e + 1) % 3];
					int w = l_tris[3 * k + (e + 2) % 3];
					if (u == p || u == q || v == p || v == q || !xing(p, q, u, v)) {
						continue;
					}
					crossing = true;
					if (l_cons.count(((int64_t)std::min(u, v) << 32) | (int64_t)std::max(u, v))) {
						continue;
					}
					int j = find_ltri(v, u);
					if (j < 0) {
						continue;
					}
					int z = third(j, v, u);
					if (ld(u, z, w) <= 0.0 || ld(z, v, w) <= 0.0) {
						continue;
					}
					set_tri(k, u, z, w);
					set_tri(j, z, v, w);
					done = true;
					break;
				}
				if (done) {
					break;
				}
			}
			if (!crossing || !done) {
				return;
			}
		}
	}

	// ---------------------------------------------------------------- classification
	double area(int pc) const {
		int a = pv[3 * pc];
		int b = pv[3 * pc + 1];
		int c = pv[3 * pc + 2];
		double ux = px[b] - px[a];
		double uy = py[b] - py[a];
		double uz = pz[b] - pz[a];
		double vx = px[c] - px[a];
		double vy = py[c] - py[a];
		double vz = pz[c] - pz[a];
		double nx = uy * vz - uz * vy;
		double ny = uz * vx - ux * vz;
		double nz = ux * vy - uy * vx;
		return std::sqrt(nx * nx + ny * ny + nz * nz) * 0.5;
	}

	double winding(double x, double y, double z, int side) const {
		int t0 = side == 0 ? 0 : na;
		int t1 = side == 0 ? na : (int)tface.size();
		double w = 0.0;
		for (int t = t0; t < t1; t++) {
			int a = tv[3 * t];
			int b = tv[3 * t + 1];
			int c = tv[3 * t + 2];
			double ax = px[a] - x;
			double ay = py[a] - y;
			double az = pz[a] - z;
			double bx = px[b] - x;
			double by = py[b] - y;
			double bz = pz[b] - z;
			double cx = px[c] - x;
			double cy = py[c] - y;
			double cz = pz[c] - z;
			double la = std::sqrt(ax * ax + ay * ay + az * az);
			double lb = std::sqrt(bx * bx + by * by + bz * bz);
			double lc = std::sqrt(cx * cx + cy * cy + cz * cz);
			double det = ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx);
			double dv = la * lb * lc + (ax * bx + ay * by + az * bz) * lc + (bx * cx + by * cy + bz * cz) * la + (cx * ax + cy * ay + cz * az) * lb;
			w += std::atan2(det, dv);
		}
		return w / TAU_;
	}

	// op: 0 union, 1 difference, 2 intersect. keep: 0 drop, 1 keep, 2 keep flipped
	std::vector<uint8_t> classify(int op) {
		int np = (int)ptri.size();
		for (size_t i = 0; i < pv.size(); i++) {
			pv[i] = find(pv[i]);
		}
		std::unordered_set<int64_t> cuts;
		for (size_t i = 0; i + 1 < cut_list.size(); i += 2) {
			cuts.insert(ekey(find(cut_list[i]), find(cut_list[i + 1])));
		}
		IVec state(np, -1);
		std::unordered_map<int64_t, int32_t> e1, e2;
		e1.reserve((size_t)np * 2);
		for (int pc = 0; pc < np; pc++) {
			int a = pv[3 * pc];
			int b = pv[3 * pc + 1];
			int c = pv[3 * pc + 2];
			if (a == b || b == c || c == a) {
				state[pc] = 9;
				continue;
			}
			int side = ptri[pc] < na ? 0 : 1;
			for (int e = 0; e < 3; e++) {
				int64_t k = ekey(pv[3 * pc + e], pv[3 * pc + (e + 1) % 3]) * 2 + side;
				if (e1.count(k)) {
					e2[k] = pc;
				} else {
					e1[k] = pc;
				}
			}
			int t = ptri[pc];
			if (!copl[t].empty()) {
				double cx = (px[a] + px[b] + px[c]) / 3.0;
				double cy = (py[a] + py[b] + py[c]) / 3.0;
				double cz = (pz[a] + pz[b] + pz[c]) / 3.0;
				for (int o : copl[t]) {
					int ko = tax[o];
					bool inside = true;
					for (int e = 0; e < 3; e++) {
						if (d2xyz(ko, tv[3 * o + e], tv[3 * o + (e + 1) % 3], cx, cy, cz) <= eps) {
							inside = false;
							break;
						}
					}
					if (inside) {
						double dot = tn[3 * t] * tn[3 * o] + tn[3 * t + 1] * tn[3 * o + 1] + tn[3 * t + 2] * tn[3 * o + 2];
						state[pc] = dot > 0.0 ? 2 : 3;
						break;
					}
				}
			}
		}
		IVec queue;
		for (int s = 0; s < np; s++) {
			if (state[s] != -1) {
				continue;
			}
			int side = ptri[s] < na ? 0 : 1;
			queue.clear();
			queue.push_back(s);
			state[s] = -2;
			size_t qi = 0;
			int best = s;
			double barea = -1.0;
			while (qi < queue.size()) {
				int pc = queue[qi];
				qi++;
				double ar = area(pc);
				if (ar > barea) {
					barea = ar;
					best = pc;
				}
				for (int e = 0; e < 3; e++) {
					int a = pv[3 * pc + e];
					int b = pv[3 * pc + (e + 1) % 3];
					int64_t ek = ekey(a, b);
					if (cuts.count(ek)) {
						continue;
					}
					int64_t k = ek * 2 + side;
					auto i1 = e1.find(k);
					auto i2 = e2.find(k);
					int nbs[2] = { i1 == e1.end() ? -1 : i1->second, i2 == e2.end() ? -1 : i2->second };
					for (int nb : nbs) {
						if (nb >= 0 && nb != pc && state[nb] == -1) {
							state[nb] = -2;
							queue.push_back(nb);
						}
					}
				}
			}
			st_patches++;
			int a0 = pv[3 * best];
			int b0 = pv[3 * best + 1];
			int c0 = pv[3 * best + 2];
			double w = winding((px[a0] + px[b0] + px[c0]) / 3.0, (py[a0] + py[b0] + py[c0]) / 3.0, (pz[a0] + pz[b0] + pz[c0]) / 3.0, 1 - side);
			int stv = w > 0.5 ? 1 : 0;
			for (int pc : queue) {
				state[pc] = stv;
			}
		}
		std::vector<uint8_t> keep(np, 0);
		for (int pc = 0; pc < np; pc++) {
			int st = state[pc];
			int side = ptri[pc] < na ? 0 : 1;
			int k = 0;
			if (st == 9) {
				k = 0;
			} else if (st >= 2) {
				if (side == 0) {
					bool same = st == 2;
					k = (op != 1 ? same : !same) ? 1 : 0;
				}
			} else if (op == 0) {
				k = st == 0 ? 1 : 0;
			} else if (op == 2) {
				k = st == 1 ? 1 : 0;
			} else {
				k = side == 0 ? (st == 0 ? 1 : 0) : (st == 1 ? 2 : 0);
			}
			keep[pc] = (uint8_t)k;
		}
		return keep;
	}

	// ---------------------------------------------------------------- rebuild
	// the kept pieces of one source face as one loop of points (CCW like the pieces), empty when not clean
	IVec merge(const IVec &g) {
		if (g.size() < 2) {
			return IVec();
		}
		std::unordered_map<int64_t, int32_t> dir;
		std::vector<int64_t> dir_order;
		std::unordered_set<int64_t> und;
		std::unordered_set<int64_t> verts;
		for (int pc : g) {
			for (int e = 0; e < 3; e++) {
				int64_t a = pv[3 * pc + e];
				int64_t b = pv[3 * pc + (e + 1) % 3];
				int64_t key = (a << 32) | b;
				if (!dir.count(key)) {
					dir_order.push_back(key);
				}
				dir[key] = pc;
				und.insert(ekey(a, b));
				verts.insert(a);
			}
		}
		if ((int64_t)verts.size() - (int64_t)und.size() + (int64_t)g.size() != 1) {
			return IVec();
		}
		std::unordered_map<int64_t, int64_t> nxt;
		std::unordered_map<int64_t, int32_t> via;
		int64_t first_a = -1;
		int nb = 0;
		for (int64_t k : dir_order) {
			int64_t a = k >> 32;
			int64_t b = k & 0xFFFFFFFF;
			if (dir.count((b << 32) | a)) {
				continue;
			}
			if (nxt.count(a)) {
				return IVec();
			}
			if (nb == 0) {
				first_a = a;
			}
			nxt[a] = b;
			via[a] = dir[k];
			nb++;
		}
		if (nb < 3) {
			return IVec();
		}
		int64_t start = first_a;
		IVec loop, tris;
		int64_t v = start;
		while (true) {
			loop.push_back((int32_t)v);
			tris.push_back(ptri[via[v]]);
			auto it = nxt.find(v);
			v = it == nxt.end() ? -1 : it->second;
			if (v == start || v == -1 || (int)loop.size() > nb) {
				break;
			}
		}
		if (v != start || (int)loop.size() != nb) {
			return IVec();
		}
		int k = tax[ptri[g[0]]];
		int n = (int)loop.size();
		std::vector<double> uu, vv;
		for (int p : loop) {
			pr(k, px[p], py[p], pz[p]);
			uu.push_back(_u);
			vv.push_back(_v);
		}
		int best = -1;
		double bscore = -INF;
		for (int s = 0; s < n; s++) {
			double worst = INF;
			for (int i = 1; i < n - 1; i++) {
				int a = s;
				int b = (s + i) % n;
				int c = (s + i + 1) % n;
				double bu = uu[b] - uu[a];
				double bv = vv[b] - vv[a];
				double cu = uu[c] - uu[a];
				double cv = vv[c] - vv[a];
				double cr = bu * cv - bv * cu;
				double lb = std::sqrt(cu * cu + cv * cv);
				worst = std::min(worst, cr / std::max(lb, 1e-300));
				if (worst < -eps) {
					break;
				}
			}
			if (worst > bscore) {
				bscore = worst;
				best = s;
			}
		}
		if (best < 0 || bscore < -eps) {
			return IVec();
		}
		IVec out;
		for (int i = 0; i < n; i++) {
			out.push_back(loop[(best + i) % n]);
		}
		return out;
	}

	int gid_of(int side, int v) { return find(vg[side][v]); }
};

} // namespace

Dictionary KineKMeshNative::boolean(const PackedVector3Array &p_va, const Array &p_fa, const PackedInt32Array &p_ta_corner, const PackedInt32Array &p_ta_face,
		const PackedVector3Array &p_vb, const Array &p_fb, const PackedInt32Array &p_tb_corner, const PackedInt32Array &p_tb_face, int p_op, double p_snap_min) {
	Dictionary res;
	std::vector<Vector3> VA = read_verts(p_va), VB = read_verts(p_vb);
	Faces FA = read_faces(p_fa), FB = read_faces(p_fb);
	const PackedInt32Array *tc[2] = { &p_ta_corner, &p_tb_corner };
	const PackedInt32Array *tf[2] = { &p_ta_face, &p_tb_face };
	const std::vector<Vector3> *VS[2] = { &VA, &VB };
	const Faces *FS[2] = { &FA, &FB };
	for (int s = 0; s < 2; s++) {
		if (tc[s]->is_empty()) {
			for (size_t f = 0; f + 1 < FS[s]->fs.size(); f++) {
				if (FS[s]->fs[f + 1] - FS[s]->fs[f] != 3) {
					res["need_tris"] = true;
					return res;
				}
			}
		}
	}
	Run r;
	double lo[6] = { INF, INF, INF, INF, INF, INF };
	double hi[6] = { -INF, -INF, -INF, -INF, -INF, -INF };
	for (int s = 0; s < 2; s++) {
		for (const Vector3 &p : *VS[s]) {
			double c[3] = { p.x, p.y, p.z };
			for (int k = 0; k < 3; k++) {
				lo[s * 3 + k] = std::min(lo[s * 3 + k], c[k]);
				hi[s * 3 + k] = std::max(hi[s * 3 + k], c[k]);
			}
		}
	}
	double diag = 0.0;
	for (int k = 0; k < 3; k++) {
		double d = std::max(hi[k], hi[3 + k]) - std::min(lo[k], lo[3 + k]);
		diag += d * d;
	}
	r.eps = std::max(p_snap_min, 1e-6 * std::sqrt(diag));
	r.cellsz = r.eps * 2.0;
	for (int k = 0; k < 3; k++) {
		r.ob[k] = std::max(lo[k], lo[3 + k]) - r.eps;
		r.ob[3 + k] = std::min(hi[k], hi[3 + k]) + r.eps;
	}
	// add both meshes
	for (int s = 0; s < 2; s++) {
		const std::vector<Vector3> &V = *VS[s];
		const Faces &F = *FS[s];
		int nv = (int)V.size();
		r.vg[s].resize(nv);
		for (int v = 0; v < nv; v++) {
			r.vg[s][v] = r.add_point(V[v].x, V[v].y, V[v].z);
		}
		int nf = (int)F.fs.size() - 1;
		r.face_ntri[s].assign(nf, 0);
		if (tc[s]->is_empty()) {
			for (int fi = 0; fi < nf; fi++) {
				r.face_ntri[s][fi] = 1;
				r.add_tri(r.vg[s][F.fv[F.fs[fi]]], r.vg[s][F.fv[F.fs[fi] + 1]], r.vg[s][F.fv[F.fs[fi] + 2]], fi);
			}
		} else {
			int nt = tf[s]->size();
			for (int t = 0; t < nt; t++) {
				int fi = (*tf[s])[t];
				int s0 = F.fs[fi];
				r.face_ntri[s][fi] += 1;
				r.add_tri(r.vg[s][F.fv[s0 + (*tc[s])[3 * t]]], r.vg[s][F.fv[s0 + (*tc[s])[3 * t + 1]]], r.vg[s][F.fv[s0 + (*tc[s])[3 * t + 2]]], fi);
			}
		}
		r.face_cut[s].assign(nf, 0);
		if (s == 0) {
			r.na = (int)r.tface.size();
		}
	}
	int nt_all = (int)r.tface.size();
	r.pts.assign(nt_all, IVec());
	r.segs.assign(nt_all, IVec());
	r.copl.assign(nt_all, IVec());
	if (r.ob[0] <= r.ob[3] && r.ob[1] <= r.ob[4] && r.ob[2] <= r.ob[5]) {
		r.broad();
	}
	r.split_all();
	std::vector<uint8_t> keep = r.classify(p_op);
	// build
	std::unordered_map<int64_t, IVec> groups;
	std::vector<int64_t> order;
	for (int pc = 0; pc < (int)r.ptri.size(); pc++) {
		if (keep[pc] == 0) {
			continue;
		}
		int t = r.ptri[pc];
		int side = t < r.na ? 0 : 1;
		int64_t gk = ((int64_t)side << 40) | r.tface[t];
		auto it = groups.find(gk);
		if (it == groups.end()) {
			order.push_back(gk);
			groups[gk].push_back(pc);
		} else {
			it->second.push_back(pc);
		}
	}
	std::vector<IVec> of_pts;
	for (int64_t gk : order) {
		const IVec &g = groups[gk];
		int side = (int)(gk >> 40);
		int fi = (int)(gk & 0xFFFFFFFFFFLL);
		bool flip = keep[g[0]] == 2;
		const Faces &F = *FS[side];
		int s0 = F.fs[fi];
		int fn = F.fs[fi + 1] - s0;
		if (!r.face_cut[side][fi] && (int)g.size() == r.face_ntri[side][fi]) {
			IVec fp;
			for (int i = 0; i < fn; i++) {
				int j = flip ? (fn - i) % fn : i;
				fp.push_back(r.gid_of(side, F.fv[s0 + j]));
			}
			of_pts.push_back(fp);
			r.st_as_were++;
			continue;
		}
		IVec loop = r.merge(g);
		if (loop.size() >= 3) {
			r.st_ngons++;
			int n = (int)loop.size();
			IVec fp;
			for (int i = 0; i < n; i++) {
				int j = flip ? (n - i) % n : i;
				fp.push_back(loop[j]);
			}
			of_pts.push_back(fp);
			continue;
		}
		for (int pc : g) {
			r.st_tri_faces++;
			IVec tri = flip ? IVec{ r.pv[3 * pc], r.pv[3 * pc + 2], r.pv[3 * pc + 1] } : IVec{ r.pv[3 * pc], r.pv[3 * pc + 1], r.pv[3 * pc + 2] };
			of_pts.push_back(tri);
		}
	}
	std::unordered_map<int, int> newid;
	std::vector<Vector3> V;
	Faces OF;
	OF.fs.push_back(0);
	for (const IVec &fp : of_pts) {
		for (int p : fp) {
			int g = r.find(p);
			auto it = newid.find(g);
			int id;
			if (it == newid.end()) {
				id = (int)V.size();
				newid[g] = id;
				V.push_back(Vector3((float)r.px[g], (float)r.py[g], (float)r.pz[g]));
			} else {
				id = it->second;
			}
			OF.fv.push_back(id);
		}
		OF.fs.push_back((int32_t)OF.fv.size());
	}
	Topo T;
	build_topo(V, OF, T);
	put_topo(res, T);
	res["verts"] = write_verts(V);
	res["faces"] = make_faces(OF.fs, OF.fv);
	res["pairs"] = r.st_pairs;
	res["segments"] = r.st_segments;
	res["coplanar_pairs"] = r.st_coplanar;
	res["split_tris"] = r.st_split;
	res["pieces"] = r.st_pieces;
	res["patches"] = r.st_patches;
	res["unresolved"] = r.st_unresolved;
	res["clamped"] = r.st_clamped;
	res["aliased"] = r.st_aliased;
	res["ngons"] = r.st_ngons;
	res["faces_as_were"] = r.st_as_were;
	res["tri_faces"] = r.st_tri_faces;
	return res;
}
