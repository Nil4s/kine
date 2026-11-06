#include "kine_dyntopo_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace godot;

void KineDyntopoNative::_bind_methods() {
	ClassDB::bind_static_method("KineDyntopoNative", D_METHOD("version"), &KineDyntopoNative::version);
	ClassDB::bind_static_method("KineDyntopoNative", D_METHOD("refine", "verts", "tris", "c", "r", "lmax", "passes"), &KineDyntopoNative::refine);
}

int KineDyntopoNative::version() {
	return 1;
}

namespace {

struct P3 {
	float x = 0, y = 0, z = 0;
};

inline uint64_t ekey(int a, int b) {
	return a < b ? (((uint64_t)a << 32) | (uint32_t)b) : (((uint64_t)b << 32) | (uint32_t)a);
}

struct Work {
	std::vector<P3> P;
	std::vector<int> T; // 3 per local tri
	std::vector<char> alive;
	std::vector<int> tsrc, vsrc;
	std::unordered_map<uint64_t, std::vector<int>> emap;
	std::unordered_map<int, std::vector<int>> vt;
	std::unordered_set<int> vdead;
	double cx = 0, cy = 0, cz = 0;
	double r2 = 0, l2 = 0, s2 = 0;
	int splits = 0, collapses = 0, flips = 0;

	double d2(const P3 &a, const P3 &b) const {
		double x = (double)a.x - (double)b.x, y = (double)a.y - (double)b.y, z = (double)a.z - (double)b.z;
		return x * x + y * y + z * z;
	}
	double d2c(const P3 &a) const {
		double x = (double)a.x - cx, y = (double)a.y - cy, z = (double)a.z - cz;
		return x * x + y * y + z * z;
	}
	static void cross(const P3 &a, const P3 &b, const P3 &d, double o[3]) {
		double ux = (double)b.x - a.x, uy = (double)b.y - a.y, uz = (double)b.z - a.z;
		double vx = (double)d.x - a.x, vy = (double)d.y - a.y, vz = (double)d.z - a.z;
		o[0] = uy * vz - uz * vy;
		o[1] = uz * vx - ux * vz;
		o[2] = ux * vy - uy * vx;
	}
	void add(int t) {
		for (int e = 0; e < 3; e++) {
			int a = T[3 * t + e], b = T[3 * t + (e + 1) % 3];
			emap[ekey(a, b)].push_back(t);
			vt[a].push_back(t);
		}
	}
	static void erase1(std::vector<int> &l, int t) {
		auto it = std::find(l.begin(), l.end(), t);
		if (it != l.end()) {
			l.erase(it);
		}
	}
	void rem(int t) {
		for (int e = 0; e < 3; e++) {
			int a = T[3 * t + e], b = T[3 * t + (e + 1) % 3];
			uint64_t k = ekey(a, b);
			auto it = emap.find(k);
			erase1(it->second, t);
			if (it->second.empty()) {
				emap.erase(it);
			}
			erase1(vt[a], t);
		}
	}
	std::vector<uint64_t> sorted_keys() const {
		std::vector<uint64_t> ks;
		ks.reserve(emap.size());
		for (auto &kv : emap) {
			ks.push_back(kv.first);
		}
		std::sort(ks.begin(), ks.end());
		return ks;
	}
	bool split_phase() {
		bool any = false;
		for (uint64_t k : sorted_keys()) {
			auto it = emap.find(k);
			if (it == emap.end() || it->second.size() > 2) {
				continue;
			}
			int a = (int)(k >> 32), b = (int)(k & 0xFFFFFFFFu);
			if (d2(P[a], P[b]) <= l2) {
				continue;
			}
			P3 m;
			m.x = (float)(((double)P[a].x + (double)P[b].x) * 0.5);
			m.y = (float)(((double)P[a].y + (double)P[b].y) * 0.5);
			m.z = (float)(((double)P[a].z + (double)P[b].z) * 0.5);
			if (d2c(m) > r2) {
				continue;
			}
			int mi = (int)P.size();
			P.push_back(m);
			vsrc.push_back(vsrc[a]);
			std::vector<int> tl = it->second;
			for (int t : tl) {
				int i0 = -1;
				for (int i = 0; i < 3; i++) {
					int p = T[3 * t + i], q = T[3 * t + (i + 1) % 3];
					if ((p == a && q == b) || (p == b && q == a)) {
						i0 = i;
					}
				}
				int p = T[3 * t + i0], q = T[3 * t + (i0 + 1) % 3], z = T[3 * t + (i0 + 2) % 3];
				rem(t);
				T[3 * t] = p;
				T[3 * t + 1] = mi;
				T[3 * t + 2] = z;
				add(t);
				int t2 = (int)alive.size();
				T.push_back(mi);
				T.push_back(q);
				T.push_back(z);
				alive.push_back(1);
				tsrc.push_back(tsrc[t]);
				add(t2);
			}
			splits++;
			any = true;
		}
		return any;
	}

	void nrm(int t, double o[3]) const {
		cross(P[T[3 * t]], P[T[3 * t + 1]], P[T[3 * t + 2]], o);
	}
	static bool tri_ok(const P3 &q0, const P3 &q1, const P3 &q2, const double n0[3]) {
		double n1[3];
		cross(q0, q1, q2, n1);
		double co2 = n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2];
		double cn2 = n1[0] * n1[0] + n1[1] * n1[1] + n1[2] * n1[2];
		double dt = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2];
		return !(cn2 <= 0.04 * co2 || dt < 0.35 * std::sqrt(co2) * std::sqrt(cn2));
	}
	bool flip_phase() {
		bool any = false;
		for (uint64_t k : sorted_keys()) {
			auto it = emap.find(k);
			if (it == emap.end() || it->second.size() != 2) {
				continue;
			}
			int a = (int)(k >> 32), b = (int)(k & 0xFFFFFFFFu);
			if (d2c(P[a]) > r2 || d2c(P[b]) > r2) {
				continue;
			}
			int t1 = it->second[0], t2 = it->second[1];
			int i0 = -1;
			for (int i = 0; i < 3; i++) {
				int pp = T[3 * t1 + i], qq = T[3 * t1 + (i + 1) % 3];
				if ((pp == a && qq == b) || (pp == b && qq == a)) {
					i0 = i;
				}
			}
			int p = T[3 * t1 + i0], q = T[3 * t1 + (i0 + 1) % 3], z = T[3 * t1 + (i0 + 2) % 3];
			int w = -1;
			for (int i = 0; i < 3; i++) {
				int u = T[3 * t2 + i];
				if (u != p && u != q) {
					w = u;
				}
			}
			if (w < 0 || w == z || emap.count(ekey(z, w))) {
				continue;
			}
			if (d2c(P[z]) > r2 || d2c(P[w]) > r2) {
				continue;
			}
			double lzw = d2(P[z], P[w]);
			if (lzw > l2 || lzw < s2) {
				continue;
			}
			int vp = (int)vt[p].size(), vq = (int)vt[q].size(), vz = (int)vt[z].size(), vw = (int)vt[w].size();
			if (vp <= 3 || vq <= 3) {
				continue;
			}
			int before = (vp - 6) * (vp - 6) + (vq - 6) * (vq - 6) + (vz - 6) * (vz - 6) + (vw - 6) * (vw - 6);
			int after = (vp - 7) * (vp - 7) + (vq - 7) * (vq - 7) + (vz - 5) * (vz - 5) + (vw - 5) * (vw - 5);
			if (after >= before) {
				continue;
			}
			double n1[3], n2[3];
			nrm(t1, n1);
			nrm(t2, n2);
			if (!(tri_ok(P[p], P[w], P[z], n1) && tri_ok(P[p], P[w], P[z], n2) && tri_ok(P[w], P[q], P[z], n1) && tri_ok(P[w], P[q], P[z], n2))) {
				continue;
			}
			double m1[3], m2[3];
			cross(P[p], P[w], P[z], m1);
			cross(P[w], P[q], P[z], m2);
			if (m1[0] * m2[0] + m1[1] * m2[1] + m1[2] * m2[2] < 0.35 * std::sqrt(m1[0] * m1[0] + m1[1] * m1[1] + m1[2] * m1[2]) * std::sqrt(m2[0] * m2[0] + m2[1] * m2[1] + m2[2] * m2[2])) {
				continue;
			}
			rem(t1);
			rem(t2);
			T[3 * t1] = p;
			T[3 * t1 + 1] = w;
			T[3 * t1 + 2] = z;
			T[3 * t2] = w;
			T[3 * t2 + 1] = q;
			T[3 * t2 + 2] = z;
			add(t1);
			add(t2);
			flips++;
			any = true;
		}
		return any;
	}
	void relax_phase() {
		std::vector<int> vs;
		vs.reserve(vt.size());
		for (auto &kv : vt) {
			vs.push_back(kv.first);
		}
		std::sort(vs.begin(), vs.end());
		for (int sweep = 0; sweep < 2; sweep++) {
			for (int v : vs) {
				P3 pv = P[v];
				if (d2c(pv) > r2) {
					continue;
				}
				std::vector<int> ts = vt[v];
				if (ts.empty()) {
					continue;
				}
				std::vector<int> nb;
				double nx = 0, ny = 0, nz = 0;
				for (int t : ts) {
					double nn[3];
					nrm(t, nn);
					nx += nn[0];
					ny += nn[1];
					nz += nn[2];
					for (int k = 0; k < 3; k++) {
						int u = T[3 * t + k];
						if (u != v && std::find(nb.begin(), nb.end(), u) == nb.end()) {
							nb.push_back(u);
						}
					}
				}
				double nl = std::sqrt(nx * nx + ny * ny + nz * nz);
				if (nl <= 0.0 || nb.size() < 3) {
					continue;
				}
				nx /= nl;
				ny /= nl;
				nz /= nl;
				double qx = 0, qy = 0, qz = 0;
				for (int u : nb) {
					qx += P[u].x;
					qy += P[u].y;
					qz += P[u].z;
				}
				qx /= nb.size();
				qy /= nb.size();
				qz /= nb.size();
				double mx = qx - pv.x, my = qy - pv.y, mz = qz - pv.z;
				double md = mx * nx + my * ny + mz * nz;
				mx -= md * nx;
				my -= md * ny;
				mz -= md * nz;
				P3 np;
				np.x = (float)(pv.x + 0.5 * mx);
				np.y = (float)(pv.y + 0.5 * my);
				np.z = (float)(pv.z + 0.5 * mz);
				if (d2c(np) > r2) {
					continue;
				}
				bool good = true;
				for (int u : nb) {
					double o = d2(pv, P[u]), n = d2(np, P[u]);
					if ((n > l2 && n > o) || (n < s2 && n < o)) {
						good = false;
						break;
					}
				}
				if (!good) {
					continue;
				}
				for (int t : ts) {
					double n0[3];
					nrm(t, n0);
					const P3 &q0 = T[3 * t] == v ? np : P[T[3 * t]];
					const P3 &q1 = T[3 * t + 1] == v ? np : P[T[3 * t + 1]];
					const P3 &q2 = T[3 * t + 2] == v ? np : P[T[3 * t + 2]];
					if (!tri_ok(q0, q1, q2, n0)) {
						good = false;
						break;
					}
				}
				if (good) {
					P[v] = np;
				}
			}
		}
	}
	std::unordered_set<int> nbrs(int v) {
		std::unordered_set<int> d;
		auto it = vt.find(v);
		if (it == vt.end()) {
			return d;
		}
		for (int t : it->second) {
			for (int k = 0; k < 3; k++) {
				int u = T[3 * t + k];
				if (u != v) {
					d.insert(u);
				}
			}
		}
		return d;
	}
	bool try_collapse(int a, int b, const std::vector<int> &tl) {
		std::unordered_set<int> na = nbrs(a), nb = nbrs(b);
		int common = 0;
		for (int u : na) {
			if (nb.count(u)) {
				common++;
			}
		}
		if (common != 2) {
			return false;
		}
		P3 pa = P[a], pb = P[b], mid;
		mid.x = (float)(((double)pa.x + (double)pb.x) * 0.5);
		mid.y = (float)(((double)pa.y + (double)pb.y) * 0.5);
		mid.z = (float)(((double)pa.z + (double)pb.z) * 0.5);
		struct Cand {
			int s, rm;
			P3 p;
		};
		Cand cands[3] = { { a, b, mid }, { a, b, pa }, { b, a, pb } };
		std::unordered_set<int> star;
		for (int t : vt[a]) {
			star.insert(t);
		}
		for (int t : vt[b]) {
			star.insert(t);
		}
		for (auto &cd : cands) {
			bool good = true;
			for (int t : star) {
				bool ha = false, hb = false;
				for (int k = 0; k < 3; k++) {
					if (T[3 * t + k] == a) {
						ha = true;
					}
					if (T[3 * t + k] == b) {
						hb = true;
					}
				}
				if (ha && hb) {
					continue;
				}
				double n0[3], n1[3];
				cross(P[T[3 * t]], P[T[3 * t + 1]], P[T[3 * t + 2]], n0);
				int i0 = T[3 * t], i1 = T[3 * t + 1], i2 = T[3 * t + 2];
				if (i0 == cd.rm) {
					i0 = cd.s;
				}
				if (i1 == cd.rm) {
					i1 = cd.s;
				}
				if (i2 == cd.rm) {
					i2 = cd.s;
				}
				const P3 &r0 = i0 == cd.s ? cd.p : P[i0];
				const P3 &r1 = i1 == cd.s ? cd.p : P[i1];
				const P3 &r2v = i2 == cd.s ? cd.p : P[i2];
				cross(r0, r1, r2v, n1);
				double co2 = n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2];
				double cn2 = n1[0] * n1[0] + n1[1] * n1[1] + n1[2] * n1[2];
				double dt = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2];
				if (cn2 <= 0.04 * co2 || dt < 0.35 * std::sqrt(co2) * std::sqrt(cn2)) {
					good = false;
					break;
				}
			}
			if (!good) {
				continue;
			}
			for (int u : na) {
				if (u != b && d2(cd.p, P[u]) > l2) {
					good = false;
					break;
				}
			}
			if (!good) {
				continue;
			}
			for (int u : nb) {
				if (u != a && d2(cd.p, P[u]) > l2) {
					good = false;
					break;
				}
			}
			if (!good) {
				continue;
			}
			for (int t : tl) {
				rem(t);
				alive[t] = 0;
			}
			std::vector<int> around = vt[cd.rm];
			for (int t : around) {
				rem(t);
				for (int k = 0; k < 3; k++) {
					if (T[3 * t + k] == cd.rm) {
						T[3 * t + k] = cd.s;
					}
				}
				add(t);
			}
			vt.erase(cd.rm);
			P[cd.s] = cd.p;
			vdead.insert(cd.rm);
			return true;
		}
		return false;
	}
	bool collapse_phase() {
		bool any = false;
		for (uint64_t k : sorted_keys()) {
			auto it = emap.find(k);
			if (it == emap.end() || it->second.size() != 2) {
				continue;
			}
			int a = (int)(k >> 32), b = (int)(k & 0xFFFFFFFFu);
			if (d2c(P[a]) > r2 || d2c(P[b]) > r2) {
				continue;
			}
			if (d2(P[a], P[b]) >= s2) {
				continue;
			}
			std::vector<int> tl = it->second;
			if (try_collapse(a, b, tl)) {
				collapses++;
				any = true;
			}
		}
		return any;
	}
};

} // namespace

Dictionary KineDyntopoNative::refine(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris, const Vector3 &p_c, double p_r, double p_lmax, int p_passes) {
	Work w;
	w.cx = p_c.x;
	w.cy = p_c.y;
	w.cz = p_c.z;
	w.r2 = p_r * p_r;
	w.l2 = p_lmax * p_lmax;
	w.s2 = 0.4 * p_lmax * (0.4 * p_lmax);
	const int nv = p_verts.size();
	const int nt = p_tris.size() / 3;
	const Vector3 *pv = p_verts.ptr();
	const int32_t *pt = p_tris.ptr();
	w.P.resize(nv);
	for (int i = 0; i < nv; i++) {
		w.P[i].x = pv[i].x;
		w.P[i].y = pv[i].y;
		w.P[i].z = pv[i].z;
	}
	double lo_x = w.cx - p_r, hi_x = w.cx + p_r, lo_y = w.cy - p_r, hi_y = w.cy + p_r, lo_z = w.cz - p_r, hi_z = w.cz + p_r;
	std::vector<char> act(nt, 0);
	for (int t = 0; t < nt; t++) {
		const Vector3 &a = pv[pt[3 * t]];
		const Vector3 &b = pv[pt[3 * t + 1]];
		const Vector3 &d = pv[pt[3 * t + 2]];
		if (std::max(std::max(a.x, b.x), d.x) < lo_x || std::min(std::min(a.x, b.x), d.x) > hi_x) {
			continue;
		}
		if (std::max(std::max(a.y, b.y), d.y) < lo_y || std::min(std::min(a.y, b.y), d.y) > hi_y) {
			continue;
		}
		if (std::max(std::max(a.z, b.z), d.z) < lo_z || std::min(std::min(a.z, b.z), d.z) > hi_z) {
			continue;
		}
		act[t] = 1;
		w.T.push_back(pt[3 * t]);
		w.T.push_back(pt[3 * t + 1]);
		w.T.push_back(pt[3 * t + 2]);
		w.alive.push_back(1);
		w.tsrc.push_back(t);
		w.add((int)w.alive.size() - 1);
	}
	w.vsrc.resize(nv);
	for (int i = 0; i < nv; i++) {
		w.vsrc[i] = i;
	}
	for (int p = 0; p < p_passes; p++) {
		bool ch = w.split_phase();
		bool ch2 = w.collapse_phase();
		if (w.splits + w.collapses > 0) {
			bool ch3 = w.flip_phase();
			bool ch4 = w.collapse_phase();
			w.relax_phase();
			ch2 = ch2 || ch3 || ch4;
		}
		if (!ch && !ch2) {
			break;
		}
	}
	if (w.splits + w.collapses == 0) {
		PackedInt32Array idv, idt;
		idv.resize(nv);
		idt.resize(nt);
		for (int i = 0; i < nv; i++) {
			idv.set(i, i);
		}
		for (int i = 0; i < nt; i++) {
			idt.set(i, i);
		}
		Dictionary z;
		z["verts"] = p_verts;
		z["tris"] = p_tris;
		z["splits"] = 0;
		z["collapses"] = 0;
		z["vsrc"] = idv;
		z["tsrc"] = idt;
		return z;
	}
	const int dead_n = (int)w.vdead.size();
	std::vector<int> remap;
	PackedVector3Array ov;
	PackedInt32Array ovs;
	if (dead_n > 0) {
		remap.assign(w.P.size(), -1);
		int n = 0;
		for (size_t i = 0; i < w.P.size(); i++) {
			if (!w.vdead.count((int)i)) {
				remap[i] = n++;
			}
		}
		ov.resize(n);
		ovs.resize(n);
		Vector3 *o = ov.ptrw();
		for (size_t i = 0; i < w.P.size(); i++) {
			if (remap[i] >= 0) {
				ovs.set(remap[i], w.vsrc[i]);
				o[remap[i]] = Vector3(w.P[i].x, w.P[i].y, w.P[i].z);
			}
		}
	} else {
		ov.resize((int)w.P.size());
		ovs.resize((int)w.P.size());
		Vector3 *o = ov.ptrw();
		for (size_t i = 0; i < w.P.size(); i++) {
			ovs.set((int)i, w.vsrc[i]);
			o[i] = Vector3(w.P[i].x, w.P[i].y, w.P[i].z);
		}
	}
	int n_act_alive = 0;
	for (char a : w.alive) {
		n_act_alive += a ? 1 : 0;
	}
	int n_keep = 0;
	for (int t = 0; t < nt; t++) {
		n_keep += act[t] ? 0 : 1;
	}
	PackedInt32Array ot;
	ot.resize((n_keep + n_act_alive) * 3);
	PackedInt32Array ots;
	ots.resize(n_keep + n_act_alive);
	int tk = 0;
	int32_t *o = ot.ptrw();
	int k = 0;
	for (int t = 0; t < nt; t++) {
		if (!act[t]) {
			ots.set(tk++, t);
			for (int j = 0; j < 3; j++) {
				o[k++] = dead_n > 0 ? remap[pt[3 * t + j]] : pt[3 * t + j];
			}
		}
	}
	for (size_t t = 0; t < w.alive.size(); t++) {
		if (w.alive[t]) {
			ots.set(tk++, w.tsrc[t]);
			for (int j = 0; j < 3; j++) {
				o[k++] = dead_n > 0 ? remap[w.T[3 * t + j]] : w.T[3 * t + j];
			}
		}
	}
	Dictionary d;
	d["verts"] = ov;
	d["tris"] = ot;
	d["splits"] = w.splits;
	d["collapses"] = w.collapses;
	d["flips"] = w.flips;
	d["vsrc"] = ovs;
	d["tsrc"] = ots;
	return d;
}
