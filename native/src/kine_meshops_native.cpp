#include "kine_meshops_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

namespace {

// ====================================================================================================================
// DECIMATE: scripts/kmesh_decimate.gd (KMeshDecimate.collapse), line for line. Vector3 is float32, scalars double.
// ====================================================================================================================

const double FEATURE_W = 100.0;
const double FLIP_DOT = 0.2;

struct Collapser {
	std::vector<Vector3> P;
	std::vector<int32_t> tv, tc;
	std::vector<uint8_t> talive, valive;
	std::vector<std::vector<int32_t>> vf;
	std::vector<int32_t> ver;
	std::vector<double> Q;
	std::vector<int32_t> ccls;
	bool has_cls = false;
	bool lock = false;
	std::vector<int32_t> fcache;
	// _try findings
	std::vector<int32_t> last_sh;
	std::vector<std::pair<int32_t, int32_t>> last_cmap; // class -> source corner
	// scratch for neighbour/fan walks
	std::vector<int32_t> mark_a, mark_b, f1v, f2v;
	int32_t stamp_a = 0, stamp_b = 0;
	std::vector<int32_t> nbu_list; // u's neighbours in fan order (the GDScript f1 dictionary order)
	// heap
	std::vector<double> hc;
	std::vector<int64_t> hk, hs;
	int64_t n_heap = 0;
	double top_c = 0.0;
	int64_t top_k = 0, top_s = 0;

	void tris_of(int v, std::vector<int32_t> &out) {
		std::vector<int32_t> &l = vf[v];
		out.clear();
		for (int32_t t : l) {
			if (talive[t] == 1) {
				out.push_back(t);
			}
		}
		if (out.size() != l.size()) {
			l = out;
		}
	}

	int slot(int t, int v) const {
		int b = 3 * t;
		return tv[b] == v ? 0 : (tv[b + 1] == v ? 1 : 2);
	}

	bool has_v(int t, int v) const {
		int b = 3 * t;
		return tv[b] == v || tv[b + 1] == v || tv[b + 2] == v;
	}

	// distinct neighbours of v, in the order the GDScript dictionary would hold them
	void neighbours(int v, std::vector<int32_t> &out) {
		out.clear();
		stamp_a++;
		std::vector<int32_t> tl;
		tris_of(v, tl);
		for (int32_t t : tl) {
			int b = 3 * t;
			for (int k = 0; k < 3; k++) {
				int w = tv[b + k];
				if (w != v && mark_a[w] != stamp_a) {
					mark_a[w] = stamp_a;
					out.push_back(w);
				}
			}
		}
	}

	bool feat2(int a, int b, int t1, int t2) const {
		if (t1 < 0 || t2 < 0) {
			return true;
		}
		if (has_cls) {
			if (ccls[tc[3 * t1 + slot(t1, a)]] != ccls[tc[3 * t2 + slot(t2, a)]]) {
				return true;
			}
			if (ccls[tc[3 * t1 + slot(t1, b)]] != ccls[tc[3 * t2 + slot(t2, b)]]) {
				return true;
			}
		}
		return false;
	}

	double cost(int u, int v) const {
		const Vector3 &p = P[v];
		double x = p.x, y = p.y, z = p.z;
		const double *qa = &Q[10 * (size_t)u];
		const double *qb = &Q[10 * (size_t)v];
		double q0 = qa[0] + qb[0];
		double q1 = qa[1] + qb[1];
		double q2 = qa[2] + qb[2];
		double q3 = qa[3] + qb[3];
		double q4 = qa[4] + qb[4];
		double q5 = qa[5] + qb[5];
		double q6 = qa[6] + qb[6];
		double q7 = qa[7] + qb[7];
		double q8 = qa[8] + qb[8];
		double q9 = qa[9] + qb[9];
		double r = q0 * x * x + 2.0 * q1 * x * y + 2.0 * q2 * x * z + 2.0 * q3 * x + q4 * y * y + 2.0 * q5 * y * z + 2.0 * q6 * y + q7 * z * z + 2.0 * q8 * z + q9;
		return std::max(0.0, r);
	}

	void add_plane(int v, const Vector3 &n, double d, double w) {
		double *q = &Q[10 * (size_t)v];
		double nx = n.x, ny = n.y, nz = n.z;
		q[0] += w * nx * nx;
		q[1] += w * nx * ny;
		q[2] += w * nx * nz;
		q[3] += w * nx * d;
		q[4] += w * ny * ny;
		q[5] += w * ny * nz;
		q[6] += w * ny * d;
		q[7] += w * nz * nz;
		q[8] += w * nz * d;
		q[9] += w * d * d;
	}

	void push(int u, int v, bool only_dir = false) {
		double c = cost(u, v);
		if (!only_dir) {
			double c2 = cost(v, u);
			if (c2 < c) {
				c = c2;
				int x = u;
				u = v;
				v = x;
			}
		}
		int64_t key = ((int64_t)u << 32) | ((int64_t)v << 1) | (only_dir ? 1 : 0);
		int64_t st = ((int64_t)ver[u] << 32) | (int64_t)ver[v];
		int64_t i = n_heap;
		n_heap++;
		if ((int64_t)hc.size() < n_heap) {
			size_t cap = std::max<int64_t>(64, n_heap * 2);
			hc.resize(cap);
			hk.resize(cap);
			hs.resize(cap);
		}
		while (i > 0) {
			int64_t p = (i - 1) >> 1;
			if (hc[p] <= c) {
				break;
			}
			hc[i] = hc[p];
			hk[i] = hk[p];
			hs[i] = hs[p];
			i = p;
		}
		hc[i] = c;
		hk[i] = key;
		hs[i] = st;
	}

	void pop() {
		top_c = hc[0];
		top_k = hk[0];
		top_s = hs[0];
		n_heap--;
		if (n_heap > 0) {
			double c = hc[n_heap];
			int64_t lk = hk[n_heap];
			int64_t ls = hs[n_heap];
			int64_t i = 0;
			int64_t n = n_heap;
			while (true) {
				int64_t l = 2 * i + 1;
				if (l >= n) {
					break;
				}
				int64_t r = l + 1;
				int64_t s = (r < n && hc[r] < hc[l]) ? r : l;
				if (hc[s] >= c) {
					break;
				}
				hc[i] = hc[s];
				hk[i] = hk[s];
				hs[i] = hs[s];
				i = s;
			}
			hc[i] = c;
			hk[i] = lk;
			hs[i] = ls;
		}
	}

	// 0: may go; 1 flip; 2 link; 3 side; 4 lock
	int try_collapse(int u, int v) {
		std::vector<int32_t> tu;
		tris_of(u, tu);
		nbu_list.clear();
		for (int32_t t : tu) {
			int b = 3 * t;
			for (int k = 0; k < 3; k++) {
				int w = tv[b + k];
				if (w == u) {
					continue;
				}
				if (f1v[w] < 0) {
					f1v[w] = t;
					nbu_list.push_back(w);
				} else if (f2v[w] == -1) {
					f2v[w] = t;
				} else {
					f2v[w] = -2;
				}
			}
		}
		struct Reset {
			Collapser *c;
			~Reset() {
				for (int32_t w : c->nbu_list) {
					c->f1v[w] = -1;
					c->f2v[w] = -1;
				}
			}
		} reset{ this };

		if (f1v[v] < 0) {
			return 2;
		}
		if (fcache[u] < 0) {
			int n = 0;
			for (int32_t w : nbu_list) {
				if (feat2(u, w, f1v[w], f2v[w])) {
					n++;
				}
			}
			fcache[u] = n;
		}
		int fd = fcache[u];
		if (fd > 0 && (lock || fd != 2 || !feat2(u, v, f1v[v], f2v[v]))) {
			return 4;
		}
		int sh[2];
		int nsh = 1;
		sh[0] = f1v[v];
		int t2 = f2v[v];
		if (t2 == -2) {
			return 2;
		}
		if (t2 >= 0) {
			sh[1] = t2;
			nsh = 2;
		}
		// link condition
		std::vector<int32_t> nbv;
		neighbours(v, nbv);
		stamp_b++;
		for (int32_t x : nbv) {
			mark_b[x] = stamp_b;
		}
		int opp[6];
		int nopp = 0;
		for (int i = 0; i < nsh; i++) {
			int t = sh[i];
			for (int k = 0; k < 3; k++) {
				int x = tv[3 * t + k];
				if (x != u && x != v) {
					bool dup = false;
					for (int j = 0; j < nopp; j++) {
						if (opp[j] == x) {
							dup = true;
						}
					}
					if (!dup) {
						opp[nopp++] = x;
					}
				}
			}
		}
		int common = 0;
		for (int32_t x : nbu_list) {
			if (mark_b[x] == stamp_b) {
				bool in_opp = false;
				for (int j = 0; j < nopp; j++) {
					if (opp[j] == x) {
						in_opp = true;
					}
				}
				if (!in_opp) {
					return 2;
				}
				common++;
			}
		}
		if (common != nopp) {
			return 2;
		}
		if ((int)nbu_list.size() + (int)nbv.size() - 2 - common <= 2 && nsh == 2) {
			return 2;
		}
		// side map
		std::vector<std::pair<int32_t, int32_t>> cmap;
		if (!has_cls) {
			cmap.push_back({ 0, -1 });
		} else {
			std::vector<std::pair<int32_t, int32_t>> ccv; // cu -> cv
			std::vector<int32_t> used;
			for (int i = 0; i < nsh; i++) {
				int t = sh[i];
				int cu = ccls[tc[3 * t + slot(t, u)]];
				int srcv = tc[3 * t + slot(t, v)];
				int cv = ccls[srcv];
				bool found = false;
				for (auto &pr : ccv) {
					if (pr.first == cu) {
						if (pr.second != cv) {
							return 3;
						}
						found = true;
						break;
					}
				}
				if (found) {
					continue;
				}
				if (std::find(used.begin(), used.end(), cv) != used.end()) {
					return 3;
				}
				ccv.push_back({ cu, cv });
				used.push_back(cv);
				cmap.push_back({ cu, srcv });
			}
			for (int32_t t : tu) {
				int cu = ccls[tc[3 * t + slot(t, u)]];
				bool has = false;
				for (auto &pr : cmap) {
					if (pr.first == cu) {
						has = true;
						break;
					}
				}
				if (!has) {
					return 3;
				}
			}
		}
		// no flip, no lost area
		Vector3 pv = P[v];
		for (int32_t t : tu) {
			int b = 3 * t;
			int i0 = tv[b], i1 = tv[b + 1], i2 = tv[b + 2];
			if (i0 == v || i1 == v || i2 == v) {
				continue;
			}
			Vector3 a0 = P[i0], a1 = P[i1], a2 = P[i2];
			Vector3 n0 = (a1 - a0).cross(a2 - a0);
			if (i0 == u) {
				a0 = pv;
			} else if (i1 == u) {
				a1 = pv;
			} else {
				a2 = pv;
			}
			Vector3 n1 = (a1 - a0).cross(a2 - a0);
			double l0 = n0.length();
			double l1 = n1.length();
			if (l1 <= l0 * 1e-6 || (double)n0.dot(n1) < FLIP_DOT * l0 * l1) {
				return 1;
			}
		}
		last_sh.assign(sh, sh + nsh);
		last_cmap = cmap;
		return 0;
	}
};

} // namespace

// ====================================================================================================================

Dictionary KineMeshOpsNative::decimate(const PackedVector3Array &p_verts, const Array &p_faces, const PackedInt32Array &p_ccls,
		const PackedInt32Array &p_twin, const PackedInt32Array &p_next, int p_target, bool p_lock) {
	Collapser s;
	s.lock = p_lock;
	int nv = p_verts.size();
	int nt = p_faces.size();
	s.P.assign(p_verts.ptr(), p_verts.ptr() + nv);
	s.tv.resize(3 * (size_t)nt);
	s.tc.resize(3 * (size_t)nt);
	s.talive.assign(nt, 1);
	s.valive.assign(nv, 1);
	s.ver.assign(nv, 0);
	s.Q.assign(10 * (size_t)nv, 0.0);
	s.fcache.assign(nv, -1);
	s.mark_a.assign(nv, 0);
	s.mark_b.assign(nv, 0);
	s.f1v.assign(nv, -1);
	s.f2v.assign(nv, -1);
	s.vf.resize(nv);
	for (int t = 0; t < nt; t++) {
		PackedInt32Array f = p_faces[t];
		for (int k = 0; k < 3; k++) {
			s.tv[3 * t + k] = f[k];
			s.tc[3 * t + k] = 3 * t + k;
			s.vf[f[k]].push_back(t);
		}
	}
	s.ccls.assign(p_ccls.ptr(), p_ccls.ptr() + p_ccls.size());
	s.has_cls = !s.ccls.empty();
	// quadrics: the planes of the triangles, area weighted
	for (int t = 0; t < nt; t++) {
		Vector3 a = s.P[s.tv[3 * t]];
		Vector3 b = s.P[s.tv[3 * t + 1]];
		Vector3 c = s.P[s.tv[3 * t + 2]];
		Vector3 cr = (b - a).cross(c - a);
		double ln = cr.length();
		if (ln < 1e-20) {
			continue;
		}
		float lnf = (float)ln;
		Vector3 n(cr.x / lnf, cr.y / lnf, cr.z / lnf);
		double d = -n.dot(a);
		for (int k = 0; k < 3; k++) {
			s.add_plane(s.tv[3 * t + k], n, d, ln * 0.5);
		}
	}
	// feature edges: constraint planes through them
	const int32_t *he_t = p_twin.ptr();
	const int32_t *he_n = p_next.ptr();
	for (int h = 0; h < 3 * nt; h++) {
		int a = s.tv[h];
		int b = s.tv[3 * (h / 3) + (h + 1) % 3];
		int g = he_t[h];
		bool feat = g < 0;
		if (!feat && s.has_cls) {
			feat = s.ccls[h] != s.ccls[he_n[g]] || s.ccls[he_n[h]] != s.ccls[g];
		}
		if (!feat) {
			continue;
		}
		int t = h / 3;
		Vector3 ed = s.P[b] - s.P[a];
		Vector3 fn = (s.P[s.tv[3 * t + 1]] - s.P[s.tv[3 * t]]).cross(s.P[s.tv[3 * t + 2]] - s.P[s.tv[3 * t]]);
		Vector3 pn = ed.cross(fn);
		if ((double)pn.length_squared() < 1e-30) {
			continue;
		}
		pn = pn.normalized();
		double d = -pn.dot(s.P[a]);
		double w = FEATURE_W * (double)ed.length_squared();
		s.add_plane(a, pn, d, w);
		s.add_plane(b, pn, d, w);
	}
	for (int h = 0; h < 3 * nt; h++) {
		int g = he_t[h];
		if (g < 0 || h < g) {
			s.push(s.tv[h], s.tv[3 * (h / 3) + (h + 1) % 3]);
		}
	}
	int64_t counts[5] = { 0, 0, 0, 0, 0 };
	int64_t collapses = 0;
	double max_cost = 0.0;
	int64_t alive = nt;
	std::vector<int32_t> lv, nbw;
	while (alive > p_target && s.n_heap > 0) {
		s.pop();
		int u = (int)(s.top_k >> 32);
		int v = (int)((s.top_k & 0xFFFFFFFFLL) >> 1);
		if (s.valive[u] == 0 || s.valive[v] == 0 || s.top_s != (((int64_t)s.ver[u] << 32) | (int64_t)s.ver[v])) {
			continue;
		}
		int why = s.try_collapse(u, v);
		if (why != 0) {
			counts[why]++;
			if (why != 2 && (s.top_k & 1) == 0) {
				s.push(v, u, true);
			}
			continue;
		}
		std::vector<int32_t> sh = s.last_sh;
		std::vector<std::pair<int32_t, int32_t>> cmap = s.last_cmap;
		for (int32_t t : sh) {
			s.talive[t] = 0;
			alive--;
		}
		s.tris_of(v, lv);
		std::vector<int32_t> tu;
		s.tris_of(u, tu);
		for (int32_t t : tu) {
			int k = s.slot(t, u);
			s.tv[3 * t + k] = v;
			if (s.has_cls) {
				int cl = s.ccls[s.tc[3 * t + k]];
				int to = -1;
				for (auto &pr : cmap) {
					if (pr.first == cl) {
						to = pr.second;
						break;
					}
				}
				s.tc[3 * t + k] = to;
			}
			lv.push_back(t);
		}
		s.vf[v] = lv;
		s.vf[u].clear();
		for (int i = 0; i < 10; i++) {
			s.Q[10 * (size_t)v + i] += s.Q[10 * (size_t)u + i];
		}
		s.valive[u] = 0;
		s.fcache[v] = -1;
		for (int32_t w : s.nbu_list) {
			s.fcache[w] = -1;
		}
		s.ver[u] += 1;
		s.ver[v] += 1;
		max_cost = std::max(max_cost, s.top_c);
		collapses++;
		s.neighbours(v, nbw);
		for (int32_t w : nbw) {
			s.push(v, w);
		}
	}
	Dictionary res;
	PackedInt32Array otv, otc;
	otv.resize(s.tv.size());
	otc.resize(s.tc.size());
	if (!s.tv.empty()) {
		memcpy(otv.ptrw(), s.tv.data(), s.tv.size() * sizeof(int32_t));
		memcpy(otc.ptrw(), s.tc.data(), s.tc.size() * sizeof(int32_t));
	}
	PackedByteArray oal;
	oal.resize(nt);
	if (nt > 0) {
		memcpy(oal.ptrw(), s.talive.data(), nt);
	}
	res["tv"] = otv;
	res["tc"] = otc;
	res["talive"] = oal;
	res["collapses"] = (int64_t)collapses;
	res["refused_flip"] = counts[1];
	res["refused_link"] = counts[2];
	res["refused_side"] = counts[3];
	res["refused_lock"] = counts[4];
	res["max_cost"] = max_cost;
	return res;
}

// ====================================================================================================================
// VOXEL REMESH: AnyGrip.MeshField.build_banded + KMeshVoxelRemesh.surface_nets
// ====================================================================================================================

namespace {

const double ON_SURFACE = 1e-7;
const double BAND = 3.0;
const double GRID_MARGIN = 0.01;

// AnyGrip.MeshField.closest: Vector3 float32, the scalar parameters double (a GDScript float)
Vector3 closest_pt(const Vector3 &p, const Vector3 &a, const Vector3 &b, const Vector3 &c) {
	Vector3 ab = b - a;
	Vector3 ac = c - a;
	Vector3 ap = p - a;
	double d1 = ab.dot(ap);
	double d2 = ac.dot(ap);
	if (d1 <= 0.0 && d2 <= 0.0) {
		return a;
	}
	Vector3 bp = p - b;
	double d3 = ab.dot(bp);
	double d4 = ac.dot(bp);
	if (d3 >= 0.0 && d4 <= d3) {
		return b;
	}
	double vc = d1 * d4 - d3 * d2;
	if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) {
		return a + ab * (float)(d1 / (d1 - d3));
	}
	Vector3 cp = p - c;
	double d5 = ab.dot(cp);
	double d6 = ac.dot(cp);
	if (d6 >= 0.0 && d5 <= d6) {
		return c;
	}
	double vb = d5 * d2 - d1 * d6;
	if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) {
		return a + ac * (float)(d2 / (d2 - d6));
	}
	double va = d3 * d6 - d5 * d4;
	if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) {
		return b + (c - b) * (float)((d4 - d3) / ((d4 - d3) + (d5 - d6)));
	}
	double denom = 1.0 / (va + vb + vc);
	return a + ab * (float)(vb * denom) + ac * (float)(vc * denom);
}

struct Field {
	Vector3 gmin, gmax;
	double h = 0.004;
	int nx = 2, ny = 2, nz = 2;
	std::vector<float> d;

	double sd(const Vector3 &q) const {
		Vector3 cl = q.clamp(gmin, gmax);
		if (cl != q) {
			return (double)(q - cl).length() + GRID_MARGIN;
		}
		float hf = (float)h;
		Vector3 g((q.x - gmin.x) / hf, (q.y - gmin.y) / hf, (q.z - gmin.z) / hf);
		int ix = std::min((int)std::floor((double)g.x), nx - 2);
		int iy = std::min((int)std::floor((double)g.y), ny - 2);
		int iz = std::min((int)std::floor((double)g.z), nz - 2);
		double tx = (double)g.x - ix;
		double ty = (double)g.y - iy;
		double tz = (double)g.z - iz;
		double s = 0.0;
		for (int dz = 0; dz < 2; dz++) {
			for (int dy = 0; dy < 2; dy++) {
				for (int dx = 0; dx < 2; dx++) {
					double w = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty) * (dz == 1 ? tz : 1.0 - tz);
					s += w * (double)d[(size_t)(ix + dx) + (size_t)nx * ((size_t)(iy + dy) + (size_t)ny * (size_t)(iz + dz))];
				}
			}
		}
		return s;
	}
};

void build_banded(const std::vector<Vector3> &tris, double cell, Field &f) {
	size_t ntri = tris.size() / 3;
	Vector3 lo = tris[0], hi = tris[0];
	for (const Vector3 &p : tris) {
		lo = lo.min(p);
		hi = hi.max(p);
	}
	f.h = cell;
	float cellf = (float)cell;
	Vector3 pad = (Vector3(1, 1, 1) * (float)(BAND + 2.0)) * cellf;
	f.gmin = lo - pad + Vector3(0.3719, 0.2841, 0.4137) * cellf;
	Vector3 span = hi + pad - f.gmin;
	f.nx = (int)std::ceil((double)span.x / cell) + 1;
	f.ny = (int)std::ceil((double)span.y / cell) + 1;
	f.nz = (int)std::ceil((double)span.z / cell) + 1;
	f.gmax = f.gmin + Vector3(f.nx - 1, f.ny - 1, f.nz - 1) * cellf;
	size_t n = (size_t)f.nx * f.ny * f.nz;
	double vol = 0.0;
	for (size_t t = 0; t < ntri; t++) {
		vol += tris[3 * t].dot(tris[3 * t + 1].cross(tris[3 * t + 2]));
	}
	float flip = vol < 0.0 ? -1.0f : 1.0f;
	f.d.assign(n, 0.0f);
	std::vector<float> dist(n, INFINITY);
	std::vector<uint8_t> touched(n, 0);
	double reach = BAND * cell;
	float reachf = (float)reach;
	for (size_t t = 0; t < ntri; t++) {
		Vector3 a = tris[3 * t], b = tris[3 * t + 1], c = tris[3 * t + 2];
		Vector3 nrm = (b - a).cross(c - a);
		Vector3 nt = nrm.length() > 1e-12 ? nrm.normalized() * flip : Vector3(0, 1, 0);
		Vector3 rv(reachf, reachf, reachf);
		Vector3 amin = a.min(b).min(c) - rv;
		Vector3 amax = a.max(b).max(c) + rv;
		int i0 = std::clamp((int)std::floor(((double)amin.x - f.gmin.x) / cell), 0, f.nx - 1);
		int j0 = std::clamp((int)std::floor(((double)amin.y - f.gmin.y) / cell), 0, f.ny - 1);
		int k0 = std::clamp((int)std::floor(((double)amin.z - f.gmin.z) / cell), 0, f.nz - 1);
		int i1 = std::clamp((int)std::ceil(((double)amax.x - f.gmin.x) / cell), 0, f.nx - 1);
		int j1 = std::clamp((int)std::ceil(((double)amax.y - f.gmin.y) / cell), 0, f.ny - 1);
		int k1 = std::clamp((int)std::ceil(((double)amax.z - f.gmin.z) / cell), 0, f.nz - 1);
		// (amin.x - gmin.x) is a float32 subtraction in GDScript too (Vector3 members), then / cell in double
		for (int k = k0; k <= k1; k++) {
			for (int j = j0; j <= j1; j++) {
				for (int i = i0; i <= i1; i++) {
					size_t idx = (size_t)i + (size_t)f.nx * ((size_t)j + (size_t)f.ny * (size_t)k);
					Vector3 p = f.gmin + Vector3(i, j, k) * cellf;
					Vector3 q = closest_pt(p, a, b, c);
					double dd = (p - q).length();
					if (dd < (double)dist[idx]) {
						dist[idx] = (float)dd;
						f.d[idx] = (float)(dd * ((dd < ON_SURFACE || (double)(p - q).dot(nt) >= 0.0) ? 1.0 : -1.0));
						touched[idx] = 1;
					}
				}
			}
		}
	}
	std::vector<uint8_t> outside(n, 0);
	std::vector<int32_t> queue;
	for (int k = 0; k < f.nz; k++) {
		for (int j = 0; j < f.ny; j++) {
			for (int i = 0; i < f.nx; i++) {
				if (i > 0 && j > 0 && k > 0 && i < f.nx - 1 && j < f.ny - 1 && k < f.nz - 1) {
					continue;
				}
				size_t idx = (size_t)i + (size_t)f.nx * ((size_t)j + (size_t)f.ny * (size_t)k);
				if (touched[idx] == 0) {
					outside[idx] = 1;
					queue.push_back((int32_t)idx);
				}
			}
		}
	}
	size_t head = 0;
	size_t slab = (size_t)f.nx * f.ny;
	static const int steps[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
	while (head < queue.size()) {
		size_t c = queue[head++];
		int i = (int)(c % f.nx);
		int j = (int)((c / f.nx) % f.ny);
		int k = (int)(c / slab);
		for (auto &st : steps) {
			int ni = i + st[0], nj = j + st[1], nk = k + st[2];
			if (ni < 0 || nj < 0 || nk < 0 || ni >= f.nx || nj >= f.ny || nk >= f.nz) {
				continue;
			}
			size_t nidx = (size_t)ni + (size_t)f.nx * ((size_t)nj + (size_t)f.ny * (size_t)nk);
			if (touched[nidx] == 0 && outside[nidx] == 0) {
				outside[nidx] = 1;
				queue.push_back((int32_t)nidx);
			}
		}
	}
	for (size_t idx = 0; idx < n; idx++) {
		if (touched[idx] == 0) {
			f.d[idx] = outside[idx] == 1 ? (float)reach : (float)-reach;
		}
	}
}

Vector3 field_normal(const Field &f, const Vector3 &p) {
	double e = f.h * 0.25;
	float ef = (float)e;
	Vector3 g(
			(float)(f.sd(p + Vector3(ef, 0, 0)) - f.sd(p - Vector3(ef, 0, 0))),
			(float)(f.sd(p + Vector3(0, ef, 0)) - f.sd(p - Vector3(0, ef, 0))),
			(float)(f.sd(p + Vector3(0, 0, ef)) - f.sd(p - Vector3(0, 0, ef))));
	return (double)g.length() > 1e-9 ? g.normalized() : Vector3();
}

struct Crossing {
	Vector3 p, n;
};

Vector3 qef_vertex(const std::vector<Crossing> &pts, const Vector3 &mass, const Vector3 &lo, double h) {
	Basis ata;
	Vector3 atb;
	const double LAMBDA = 0.1;
	Vector3 c0, c1, c2;
	for (const Crossing &pn : pts) {
		const Vector3 &n = pn.n;
		const Vector3 &p = pn.p;
		if (n == Vector3()) {
			continue;
		}
		c0 += Vector3(n.x * n.x, n.x * n.y, n.x * n.z);
		c1 += Vector3(n.y * n.x, n.y * n.y, n.y * n.z);
		c2 += Vector3(n.z * n.x, n.z * n.y, n.z * n.z);
		atb += n * n.dot(p);
	}
	c0.x = (float)((double)c0.x + LAMBDA);
	c1.y = (float)((double)c1.y + LAMBDA);
	c2.z = (float)((double)c2.z + LAMBDA);
	ata = Basis(c0, c1, c2);
	atb += mass * (float)LAMBDA;
	Vector3 x = mass;
	if (std::fabs((double)ata.determinant()) > 1e-12) {
		x = ata.inverse().xform(atb);
	}
	float hf = (float)h;
	return x.clamp(lo, lo + Vector3(1, 1, 1) * hf);
}

} // namespace

Dictionary KineMeshOpsNative::voxel_remesh(const PackedVector3Array &p_verts, const Array &p_faces, double p_voxel) {
	Dictionary res;
	std::vector<Vector3> tris;
	for (int fi = 0; fi < p_faces.size(); fi++) {
		PackedInt32Array fa = p_faces[fi];
		for (int k = 1; k < fa.size() - 1; k++) {
			tris.push_back(p_verts[fa[0]]);
			tris.push_back(p_verts[fa[k]]);
			tris.push_back(p_verts[fa[k + 1]]);
		}
	}
	if (tris.empty()) {
		return res;
	}
	Field field;
	build_banded(tris, p_voxel, field);
	const int nx = field.nx, ny = field.ny, nz = field.nz;
	const int sx = nx - 1, sy = ny - 1;
	std::vector<int32_t> cell_vert((size_t)std::max(nx - 1, 0) * std::max(ny - 1, 0) * std::max(nz - 1, 0), -1);
	PackedVector3Array verts;
	static const int CORNERS[8][3] = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 } };
	static const int EDGES[12][2] = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 }, { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 } };
	float hf = (float)field.h;
	std::vector<Crossing> pts;
	for (int k = 0; k < nz - 1; k++) {
		for (int j = 0; j < ny - 1; j++) {
			for (int i = 0; i < nx - 1; i++) {
				float val[8];
				int inside = 0;
				for (int c = 0; c < 8; c++) {
					val[c] = field.d[(size_t)(i + CORNERS[c][0]) + (size_t)nx * ((size_t)(j + CORNERS[c][1]) + (size_t)ny * (size_t)(k + CORNERS[c][2]))];
					if (val[c] < 0.0f) {
						inside++;
					}
				}
				if (inside == 0 || inside == 8) {
					continue;
				}
				pts.clear();
				Vector3 mass;
				for (int e = 0; e < 12; e++) {
					int a = EDGES[e][0], b = EDGES[e][1];
					if ((val[a] < 0.0f) == (val[b] < 0.0f)) {
						continue;
					}
					double t = (double)val[a] / ((double)val[a] - (double)val[b]);
					Vector3 ca(CORNERS[a][0], CORNERS[a][1], CORNERS[a][2]);
					Vector3 cb(CORNERS[b][0], CORNERS[b][1], CORNERS[b][2]);
					Vector3 cc = Vector3(i, j, k) + ca.lerp(cb, (float)t);
					Vector3 pw = field.gmin + cc * hf;
					pts.push_back({ pw, field_normal(field, pw) });
					mass += pw;
				}
				float cnt = (float)pts.size();
				mass = Vector3(mass.x / cnt, mass.y / cnt, mass.z / cnt);
				Vector3 at = qef_vertex(pts, mass, field.gmin + Vector3(i, j, k) * hf, field.h);
				cell_vert[(size_t)i + (size_t)sx * ((size_t)j + (size_t)sy * (size_t)k)] = verts.size();
				verts.push_back(at);
			}
		}
	}
	Array faces;
	for (int k = 0; k < nz; k++) {
		for (int j = 0; j < ny; j++) {
			for (int i = 0; i < nx; i++) {
				size_t here = (size_t)i + (size_t)nx * ((size_t)j + (size_t)ny * (size_t)k);
				for (int axis = 0; axis < 3; axis++) {
					int ni = i + (axis == 0), nj = j + (axis == 1), nk = k + (axis == 2);
					if (ni >= nx || nj >= ny || nk >= nz) {
						continue;
					}
					size_t there = (size_t)ni + (size_t)nx * ((size_t)nj + (size_t)ny * (size_t)nk);
					if ((field.d[here] < 0.0f) == (field.d[there] < 0.0f)) {
						continue;
					}
					int u = (axis + 1) % 3;
					int w = (axis + 2) % 3;
					int ring[4];
					bool bad = false;
					static const int QS[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
					for (int qi = 0; qi < 4; qi++) {
						int cc[3] = { i, j, k };
						cc[u] += QS[qi][0] - 1;
						cc[w] += QS[qi][1] - 1;
						if (cc[0] < 0 || cc[1] < 0 || cc[2] < 0 || cc[0] >= sx || cc[1] >= sy || cc[2] >= nz - 1) {
							bad = true;
							break;
						}
						ring[qi] = cell_vert[(size_t)cc[0] + (size_t)sx * ((size_t)cc[1] + (size_t)sy * (size_t)cc[2])];
					}
					if (bad || ring[0] < 0 || ring[1] < 0 || ring[2] < 0 || ring[3] < 0) {
						continue;
					}
					Vector3 want;
					want[axis] = field.d[here] < 0.0f ? 1.0f : -1.0f;
					Vector3 nrm = (verts[ring[2]] - verts[ring[0]]).cross(verts[ring[3]] - verts[ring[1]]);
					PackedInt32Array q;
					q.resize(4);
					if (nrm.dot(want) < 0.0f) {
						q[0] = ring[0];
						q[1] = ring[3];
						q[2] = ring[2];
						q[3] = ring[1];
					} else {
						q[0] = ring[0];
						q[1] = ring[1];
						q[2] = ring[2];
						q[3] = ring[3];
					}
					faces.push_back(q);
				}
			}
		}
	}
	res["verts"] = verts;
	res["faces"] = faces;
	res["voxels"] = (int64_t)nx * ny * nz;
	res["cell"] = field.h;
	return res;
}

// ====================================================================================================================
// WRITERS
// ====================================================================================================================

// "%.6f" as Godot's String formatting writes it: an exact tie (x.xxxxxx5 in binary) rounds away from zero, snprintf rounds it to even
static void fmt6(char *out, size_t n, double x) {
	char t[64];
	snprintf(t, sizeof(t), "%.12f", x);
	size_t L = strlen(t);
	if (L >= 6 && memcmp(t + L - 6, "500000", 6) == 0) {
		x += x < 0 ? -1e-10 : 1e-10;
	}
	snprintf(out, n, "%.6f", x);
}

PackedByteArray KineMeshOpsNative::stl_records(const PackedVector3Array &p_v, const PackedInt32Array &p_t) {
	int nt = p_t.size() / 3;
	PackedByteArray out;
	out.resize((int64_t)nt * 50);
	uint8_t *w = out.ptrw();
	const Vector3 *v = p_v.ptr();
	const int32_t *t = p_t.ptr();
	for (int i = 0; i < nt; i++) {
		const Vector3 &p0 = v[t[3 * i]];
		const Vector3 &p1 = v[t[3 * i + 1]];
		const Vector3 &p2 = v[t[3 * i + 2]];
		Vector3 nn = (p1 - p0).cross(p2 - p0).normalized();
		float f[12] = { nn.x, nn.y, nn.z, p0.x, p0.y, p0.z, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z };
		memcpy(w, f, 48); // little-endian host
		w[48] = 0;
		w[49] = 0;
		w += 50;
	}
	return out;
}

String KineMeshOpsNative::xml_vertices(const PackedVector3Array &p_v) {
	std::string s;
	s.reserve((size_t)p_v.size() * 60);
	char buf[160];
	for (int i = 0; i < p_v.size(); i++) {
		const Vector3 &p = p_v[i];
		char a[48], b[48], c[48];
		fmt6(a, sizeof(a), (double)p.x);
		fmt6(b, sizeof(b), (double)p.y);
		fmt6(c, sizeof(c), (double)p.z);
		snprintf(buf, sizeof(buf), "<vertex x=\"%s\" y=\"%s\" z=\"%s\"/>", a, b, c);
		if (i > 0) {
			s += '\n';
		}
		s += buf;
	}
	return String::utf8(s.c_str(), (int64_t)s.size());
}

String KineMeshOpsNative::xml_triangles(const PackedInt32Array &p_t) {
	std::string s;
	int nt = p_t.size() / 3;
	s.reserve((size_t)nt * 48);
	char buf[96];
	for (int i = 0; i < p_t.size() - 2; i += 3) {
		snprintf(buf, sizeof(buf), "<triangle v1=\"%d\" v2=\"%d\" v3=\"%d\"/>", p_t[i], p_t[i + 1], p_t[i + 2]);
		if (i > 0) {
			s += '\n';
		}
		s += buf;
	}
	return String::utf8(s.c_str(), (int64_t)s.size());
}

String KineMeshOpsNative::obj_vertices(const PackedVector3Array &p_v, const Transform3D &p_xf) {
	std::string s;
	s.reserve((size_t)p_v.size() * 40);
	char buf[160];
	for (int i = 0; i < p_v.size(); i++) {
		Vector3 q = p_xf.xform(p_v[i]);
		char a[48], b[48], c[48];
		fmt6(a, sizeof(a), (double)q.x);
		fmt6(b, sizeof(b), (double)q.y);
		fmt6(c, sizeof(c), (double)q.z);
		snprintf(buf, sizeof(buf), "v %s %s %s", a, b, c);
		if (i > 0) {
			s += '\n';
		}
		s += buf;
	}
	return String::utf8(s.c_str(), (int64_t)s.size());
}

String KineMeshOpsNative::obj_normals(const PackedVector3Array &p_n, const Basis &p_nb) {
	std::string s;
	s.reserve((size_t)p_n.size() * 40);
	char buf[160];
	for (int i = 0; i < p_n.size(); i++) {
		Vector3 q = p_nb.xform(p_n[i]).normalized();
		char a[48], b[48], c[48];
		fmt6(a, sizeof(a), (double)q.x);
		fmt6(b, sizeof(b), (double)q.y);
		fmt6(c, sizeof(c), (double)q.z);
		snprintf(buf, sizeof(buf), "vn %s %s %s", a, b, c);
		if (i > 0) {
			s += '\n';
		}
		s += buf;
	}
	return String::utf8(s.c_str(), (int64_t)s.size());
}

String KineMeshOpsNative::obj_faces(const PackedInt32Array &p_ix, int p_count, int p_off_v, int p_off_t, int p_off_n, bool p_has_t, bool p_has_n) {
	std::string s;
	s.reserve((size_t)p_count * 40);
	bool indexed = p_ix.size() > 0;
	static const int order[3] = { 0, 2, 1 };
	char ref[3][64];
	for (int t = 0; t < p_count; t++) {
		for (int c = 0; c < 3; c++) {
			int i = indexed ? p_ix[t * 3 + order[c]] : t * 3 + order[c];
			if (p_has_t && p_has_n) {
				snprintf(ref[c], 64, "%d/%d/%d", p_off_v + i + 1, p_off_t + i + 1, p_off_n + i + 1);
			} else if (p_has_t) {
				snprintf(ref[c], 64, "%d/%d", p_off_v + i + 1, p_off_t + i + 1);
			} else if (p_has_n) {
				snprintf(ref[c], 64, "%d//%d", p_off_v + i + 1, p_off_n + i + 1);
			} else {
				snprintf(ref[c], 64, "%d", p_off_v + i + 1);
			}
		}
		if (t > 0) {
			s += '\n';
		}
		s += "f ";
		s += ref[0];
		s += ' ';
		s += ref[1];
		s += ' ';
		s += ref[2];
	}
	return String::utf8(s.c_str(), (int64_t)s.size());
}

int KineMeshOpsNative::version() {
	return 1;
}

void KineMeshOpsNative::_bind_methods() {
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("version"), &KineMeshOpsNative::version);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("decimate", "verts", "faces", "ccls", "he_twin", "he_next", "target", "lock"), &KineMeshOpsNative::decimate);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("voxel_remesh", "verts", "faces", "voxel"), &KineMeshOpsNative::voxel_remesh);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("stl_records", "v", "t"), &KineMeshOpsNative::stl_records);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("xml_vertices", "v"), &KineMeshOpsNative::xml_vertices);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("xml_triangles", "t"), &KineMeshOpsNative::xml_triangles);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("obj_vertices", "v", "xf"), &KineMeshOpsNative::obj_vertices);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("obj_normals", "n", "nb"), &KineMeshOpsNative::obj_normals);
	ClassDB::bind_static_method("KineMeshOpsNative", D_METHOD("obj_faces", "ix", "count", "off_v", "off_t", "off_n", "has_t", "has_n"), &KineMeshOpsNative::obj_faces);
}
