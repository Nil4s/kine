#include "kine_wrinkle_native.h"

#include <cmath>
#include <cstring>
#include <vector>

using namespace godot;

int KineWrinkleNative::version() { return 2; }

PackedVector3Array KineWrinkleNative::blend(const PackedVector3Array &p_rest, const Array &p_deltas, const PackedFloat32Array &p_weights) {
	const int n = p_rest.size();
	PackedVector3Array out;
	out.resize(n);
	std::vector<PackedVector3Array> keep;
	std::vector<const Vector3 *> dps;
	std::vector<float> ws;
	const int k = p_deltas.size();
	for (int a = 0; a < k && a < p_weights.size(); a++) {
		const float w = p_weights[a];
		if (w == 0.0f) continue;
		PackedVector3Array d = p_deltas[a];
		if (d.size() != n) continue;
		keep.push_back(d);
		ws.push_back(w);
	}
	for (size_t a = 0; a < keep.size(); a++) dps.push_back(keep[a].ptr());
	const Vector3 *rp = p_rest.ptr();
	Vector3 *o = out.ptrw();
	const size_t m = dps.size();
	for (int i = 0; i < n; i++) {
		Vector3 v = rp[i];
		for (size_t a = 0; a < m; a++) v += dps[a][i] * ws[a];
		o[i] = v;
	}
	return out;
}

// Each active vertex keeps its UNIQUE neighbours (first-seen order over the triangles) with the multiplicity m (an interior edge is in 2 triangles).
// entry layout (doubles): m*f0, m*f1, m*f2, |r|^2 (mm2)      frame layout: e1(3) e2(3) inv(6: 00 01 02 11 12 22)
Dictionary KineWrinkleNative::prep(const PackedVector3Array &p_rest, const PackedVector3Array &p_normals, const PackedInt32Array &p_tris, const PackedByteArray &p_zt) {
	const int n = p_rest.size();
	std::vector<int> slot((size_t)n, -1);
	PackedInt32Array act;
	for (int i = 0; i < n; i++)
		if (p_zt[i] != 0) {
			slot[(size_t)i] = act.size();
			act.push_back(i);
		}
	const int na = act.size();
	const int nt = p_tris.size() / 3;
	std::vector<std::vector<std::pair<int, int>>> lists((size_t)na);
	for (int t = 0; t < nt; t++) {
		int v[3] = { p_tris[t * 3], p_tris[t * 3 + 1], p_tris[t * 3 + 2] };
		for (int s = 0; s < 3; s++) {
			const int a = slot[(size_t)v[s]];
			if (a < 0) continue;
			for (int o = 1; o <= 2; o++) {
				const int j = v[(s + o) % 3];
				auto &L = lists[(size_t)a];
				bool found = false;
				for (auto &pr : L)
					if (pr.first == j) {
						pr.second++;
						found = true;
						break;
					}
				if (!found) L.push_back({ j, 1 });
			}
		}
	}
	PackedInt32Array off;
	off.resize(na + 1);
	int tot = 0;
	for (int a = 0; a < na; a++) {
		off[a] = tot;
		tot += (int)lists[(size_t)a].size();
	}
	off[na] = tot;
	PackedInt32Array nb;
	nb.resize(tot);
	PackedFloat64Array ent;
	ent.resize((int64_t)tot * 4);
	PackedFloat64Array fr;
	fr.resize((int64_t)na * 12);
	for (int a = 0; a < na; a++) {
		const int i = act[a];
		double nx = p_normals[i].x, ny = p_normals[i].y, nz = p_normals[i].z;
		double rx = 1, ry = 0, rz = 0;
		if (std::fabs(nx) >= 0.9) { rx = 0; ry = 1; }
		double ex = ry * nz - rz * ny, ey = rz * nx - rx * nz, ez = rx * ny - ry * nx;
		double l = std::sqrt(ex * ex + ey * ey + ez * ez);
		if (l < 1e-12) l = 1e-12;
		ex /= l; ey /= l; ez /= l;
		fr[a * 12 + 0] = ex; fr[a * 12 + 1] = ey; fr[a * 12 + 2] = ez;
		fr[a * 12 + 3] = ny * ez - nz * ey; fr[a * 12 + 4] = nz * ex - nx * ez; fr[a * 12 + 5] = nx * ey - ny * ex;
		double G[6] = { 0, 0, 0, 0, 0, 0 };
		int e = off[a];
		for (auto &pr : lists[(size_t)a]) {
			const int j = pr.first;
			const double m = (double)pr.second;
			double r0 = ((double)p_rest[j].x - (double)p_rest[i].x) * 1000.0, r1 = ((double)p_rest[j].y - (double)p_rest[i].y) * 1000.0, r2 = ((double)p_rest[j].z - (double)p_rest[i].z) * 1000.0;
			double x = r0 * fr[a * 12] + r1 * fr[a * 12 + 1] + r2 * fr[a * 12 + 2];
			double y = r0 * fr[a * 12 + 3] + r1 * fr[a * 12 + 4] + r2 * fr[a * 12 + 5];
			double f0 = x * x, f1 = 2.0 * x * y, f2 = y * y;
			nb[e] = j;
			double *E = ent.ptrw() + (int64_t)e * 4;
			E[0] = m * f0; E[1] = m * f1; E[2] = m * f2; E[3] = r0 * r0 + r1 * r1 + r2 * r2;
			G[0] += m * (f0 * f0); G[1] += m * (f0 * f1); G[2] += m * (f0 * f2); G[3] += m * (f1 * f1); G[4] += m * (f1 * f2); G[5] += m * (f2 * f2);
			e++;
		}
		const double reg = 1e-6;
		double a00 = G[0] + reg, a01 = G[1], a02 = G[2], a11 = G[3] + reg, a12 = G[4], a22 = G[5] + reg;
		double det = a00 * (a11 * a22 - a12 * a12) - a01 * (a01 * a22 - a12 * a02) + a02 * (a01 * a12 - a11 * a02);
		double *F = fr.ptrw() + (int64_t)a * 12;
		if (std::fabs(det) < 1e-18 || off[a + 1] == off[a]) {
			for (int k = 6; k < 12; k++) F[k] = 0.0;
			continue;
		}
		F[6] = (a11 * a22 - a12 * a12) / det;
		F[7] = (a02 * a12 - a01 * a22) / det;
		F[8] = (a01 * a12 - a02 * a11) / det;
		F[9] = (a00 * a22 - a02 * a02) / det;
		F[10] = (a01 * a02 - a00 * a12) / det;
		F[11] = (a00 * a11 - a01 * a01) / det;
	}
	Dictionary r;
	r["n"] = n;
	r["act"] = act;
	r["off"] = off;
	r["nb"] = nb;
	r["ent"] = ent;
	r["fr"] = fr;
	return r;
}

Dictionary KineWrinkleNative::wrinkle(const Dictionary &p_prep, const PackedVector3Array &p_posed, const PackedVector3Array &p_purse, const PackedByteArray &p_zt, const PackedFloat32Array &p_zw, const PackedFloat64Array &p_par) {
	const int n = (int)p_prep["n"];
	const PackedInt32Array act = p_prep["act"], off = p_prep["off"], nb = p_prep["nb"];
	const PackedFloat64Array ent = p_prep["ent"], fr = p_prep["fr"];
	PackedVector3Array dir;
	PackedFloat32Array comp, amp, c0;
	dir.resize(n);
	comp.resize(n);
	amp.resize(n);
	c0.resize(n * 4);
	std::memset(dir.ptrw(), 0, (size_t)n * sizeof(Vector3));
	std::memset(comp.ptrw(), 0, (size_t)n * sizeof(float));
	std::memset(amp.ptrw(), 0, (size_t)n * sizeof(float));
	std::memset(c0.ptrw(), 0, (size_t)n * 4 * sizeof(float));
	Vector3 *dirp = dir.ptrw();
	float *compp = comp.ptrw(), *ampp = amp.ptrw(), *c0p = c0.ptrw();
	const Vector3 *pp = p_posed.ptr();
	const Vector3 *pu = p_purse.ptr();
	const bool use_purse = p_par.size() > 8 && p_par[8] != 0.0 && p_purse.size() == n;
	const float w6 = p_par.size() > 8 ? (float)p_par[8] : 0.0f;
	const int *nbp = nb.ptr();
	const double *entp = ent.ptr(), *frp = fr.ptr();
	const double lo = p_par[1], hi = p_par[2];
	const int na = act.size();
	const int *actp = act.ptr(), *offp = off.ptr();
	const float *zwp = p_zw.ptr();
	const uint8_t *ztp = p_zt.ptr();
	double gate[8];
	for (int k = 0; k < 8; k++) gate[k] = k < p_par.size() ? p_par[k] : 0.0;
	for (int a = 0; a < na; a++) {
		const int i = actp[a];
		const double *F = frp + (int64_t)a * 12;
		const int e0 = offp[a], e1 = offp[a + 1];
		if (e1 == e0) continue;
		double px = pp[i].x, py = pp[i].y, pz = pp[i].z;
		if (use_purse) {
			px = (double)(pp[i].x + pu[i].x * w6);
			py = (double)(pp[i].y + pu[i].y * w6);
			pz = (double)(pp[i].z + pu[i].z * w6);
		}
		double b0 = 0, b1 = 0, b2 = 0;
		for (int e = e0; e < e1; e++) {
			Vector3 pj = pp[nbp[e]];
			if (use_purse) pj += pu[nbp[e]] * w6;
			const double *E = entp + (int64_t)e * 4;
			double q0 = ((double)pj.x - px) * 1000.0, q1 = ((double)pj.y - py) * 1000.0, q2 = ((double)pj.z - pz) * 1000.0;
			double g = 0.5 * ((q0 * q0 + q1 * q1 + q2 * q2) - E[3]);
			b0 += g * E[0];
			b1 += g * E[1];
			b2 += g * E[2];
		}
		if (F[6] == 0.0 && F[9] == 0.0) continue;
		double ea = F[6] * b0 + F[7] * b1 + F[8] * b2;
		double eb = F[7] * b0 + F[9] * b1 + F[10] * b2;
		double ec = F[8] * b0 + F[10] * b1 + F[11] * b2;
		double mid = 0.5 * (ea + ec);
		double rad = std::sqrt(0.5 * (ea - ec) * 0.5 * (ea - ec) + eb * eb);
		double lmin = mid - rad;
		// the line runs along the eigenvector of the LARGEST eigenvalue (perpendicular to the most compressive axis), without trigonometry
		const double lmax = mid + rad;
		double v1x = eb, v1y = lmax - ea, v2x = lmax - ec, v2y = eb;
		double l1 = v1x * v1x + v1y * v1y, l2 = v2x * v2x + v2y * v2y;
		double vx, vy;
		if (l1 >= l2) { vx = v1x; vy = v1y; } else { vx = v2x; vy = v2y; }
		double ll = vx * vx + vy * vy;
		if (ll < 1e-30) {
			vx = ea >= ec ? 1.0 : 0.0;
			vy = ea >= ec ? 0.0 : 1.0;
		} else {
			ll = std::sqrt(ll);
			vx /= ll;
			vy /= ll;
		}
		if (vx < 0.0 || (vx == 0.0 && vy < 0.0)) { vx = -vx; vy = -vy; }
		float tx = (float)(vx * F[0] + vy * F[3]), ty = (float)(vx * F[1] + vy * F[4]), tz = (float)(vx * F[2] + vy * F[5]);
		float cp = (float)(lmin < 0.0 ? -lmin : 0.0);
		double t = (cp - lo) / (hi - lo);
		t = t < 0 ? 0 : (t > 1 ? 1 : t);
		float am = (float)(t * t * (3.0 - 2.0 * t) * zwp[i] * gate[2 + ztp[i]]);
		dirp[i] = Vector3(tx, ty, tz);
		compp[i] = cp;
		ampp[i] = am;
		c0p[i * 4] = tx;
		c0p[i * 4 + 1] = ty;
		c0p[i * 4 + 2] = tz;
		c0p[i * 4 + 3] = am;
	}
	Dictionary r;
	r["dir"] = dir;
	r["comp"] = comp;
	r["amp"] = amp;
	r["c0"] = c0;
	return r;
}

void KineWrinkleNative::_bind_methods() {
	ClassDB::bind_static_method("KineWrinkleNative", D_METHOD("version"), &KineWrinkleNative::version);
	ClassDB::bind_static_method("KineWrinkleNative", D_METHOD("blend", "rest", "deltas", "weights"), &KineWrinkleNative::blend);
	ClassDB::bind_static_method("KineWrinkleNative", D_METHOD("prep", "rest", "normals", "tris", "zt"), &KineWrinkleNative::prep);
	ClassDB::bind_static_method("KineWrinkleNative", D_METHOD("wrinkle", "prep", "posed", "purse", "zt", "zw", "par"), &KineWrinkleNative::wrinkle);
}
