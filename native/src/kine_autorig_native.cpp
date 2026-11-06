#include "kine_autorig_native.h"

#include <algorithm>
#include <cmath>
#include <queue>
#include <vector>

using namespace godot;

void KineAutoRigNative::_bind_methods() {
	ClassDB::bind_static_method("KineAutoRigNative", D_METHOD("version"), &KineAutoRigNative::version);
	ClassDB::bind_static_method("KineAutoRigNative", D_METHOD("voxelize", "verts", "tris", "comp", "origin", "vs", "nx", "ny", "nz"), &KineAutoRigNative::voxelize);
	ClassDB::bind_static_method("KineAutoRigNative", D_METHOD("edt", "mask", "vs", "nx", "ny", "nz"), &KineAutoRigNative::edt);
	ClassDB::bind_static_method("KineAutoRigNative", D_METHOD("bind", "mask", "vs", "nx", "ny", "nz", "origin", "sa", "sb", "sbone", "nb", "r", "smooth"), &KineAutoRigNative::bind);
}

int KineAutoRigNative::version() { return 1; }

static const double JX = 0.000123, JY = 0.000217; // the column centre is nudged off the grid so no vertex or edge sits on a ray

PackedByteArray KineAutoRigNative::voxelize(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris, const PackedInt32Array &p_comp,
		const Vector3 &p_origin, double vs, int nx, int ny, int nz) {
	PackedByteArray out;
	out.resize((int64_t)nx * ny * nz);
	out.fill(0);
	uint8_t *m = out.ptrw();
	const Vector3 *V = p_verts.ptr();
	const int32_t *T = p_tris.ptr();
	int nt = p_tris.size() / 3;
	int ncomp = 0;
	for (int i = 0; i < p_comp.size(); i++) ncomp = std::max(ncomp, p_comp[i] + 1);
	double ox = p_origin.x, oy = p_origin.y, oz = p_origin.z;
	// surface: points over each triangle at most vs/2 apart
	for (int t = 0; t < nt; t++) {
		Vector3 a = V[T[t * 3]], b = V[T[t * 3 + 1]], c = V[T[t * 3 + 2]];
		auto len3 = [](const Vector3 &u, const Vector3 &v) {
			double dx = (double)v.x - u.x, dy = (double)v.y - u.y, dz = (double)v.z - u.z;
			return std::sqrt(dx * dx + dy * dy + dz * dz);
		};
		double l = std::max(len3(a, b), std::max(len3(b, c), len3(c, a)));
		int n = std::max(1, (int)std::ceil(l / (0.5 * vs)));
		for (int i = 0; i <= n; i++) {
			for (int j = 0; j <= n - i; j++) {
				double u = (double)i / n, v = (double)j / n, w = 1.0 - u - v;
				double px = a.x * w + b.x * u + c.x * v, py = a.y * w + b.y * u + c.y * v, pz = a.z * w + b.z * u + c.z * v;
				int ix = (int)std::floor((px - ox) / vs), iy = (int)std::floor((py - oy) / vs), iz = (int)std::floor((pz - oz) / vs);
				if (ix >= 0 && iy >= 0 && iz >= 0 && ix < nx && iy < ny && iz < nz) m[ix + (int64_t)nx * (iy + (int64_t)ny * iz)] |= 2;
			}
		}
	}
	// parity: per component, per column
	std::vector<std::vector<int>> by(ncomp);
	for (int t = 0; t < nt; t++) by[p_comp[t]].push_back(t);
	std::vector<double> zs;
	for (int c = 0; c < ncomp; c++) {
		if (by[c].empty()) continue;
		for (int iy = 0; iy < ny; iy++) {
			for (int ix = 0; ix < nx; ix++) {
				double cx = ox + (ix + 0.5 + JX) * vs, cy = oy + (iy + 0.5 + JY) * vs;
				zs.clear();
				for (int t : by[c]) {
					Vector3 a = V[T[t * 3]], b = V[T[t * 3 + 1]], d = V[T[t * 3 + 2]];
					double det = ((double)b.y - d.y) * (a.x - d.x) + ((double)d.x - b.x) * (a.y - d.y);
					if (std::fabs(det) < 1e-18) continue;
					double l0 = (((double)b.y - d.y) * (cx - d.x) + ((double)d.x - b.x) * (cy - d.y)) / det;
					double l1 = (((double)d.y - a.y) * (cx - d.x) + ((double)a.x - d.x) * (cy - d.y)) / det;
					double l2 = 1.0 - l0 - l1;
					if (l0 < 0.0 || l1 < 0.0 || l2 < 0.0) continue;
					zs.push_back(l0 * a.z + l1 * b.z + l2 * d.z);
				}
				if (zs.size() < 2) continue;
				std::sort(zs.begin(), zs.end());
				for (size_t k = 0; k + 1 < zs.size(); k += 2) {
					int k0 = (int)std::ceil((zs[k] - oz) / vs - 0.5), k1 = (int)std::ceil((zs[k + 1] - oz) / vs - 0.5) - 1;
					k0 = std::max(k0, 0);
					k1 = std::min(k1, nz - 1);
					for (int iz = k0; iz <= k1; iz++) m[ix + (int64_t)nx * (iy + (int64_t)ny * iz)] |= 1;
				}
			}
		}
	}
	return out;
}

PackedFloat32Array KineAutoRigNative::edt(const PackedByteArray &p_mask, double vs, int nx, int ny, int nz) {
	int64_t N = (int64_t)nx * ny * nz;
	std::vector<double> d(N);
	const uint8_t *m = p_mask.ptr();
	for (int64_t i = 0; i < N; i++) d[i] = m[i] ? 1e30 : 0.0;
	const double w1 = vs, w2 = vs * std::sqrt(2.0), w3 = vs * std::sqrt(3.0);
	// forward half-neighbourhood then backward; a voxel beyond the grid counts as outside
	for (int pass = 0; pass < 2; pass++) {
		bool fwd = pass == 0;
		for (int zz = 0; zz < nz; zz++) {
			int z = fwd ? zz : nz - 1 - zz;
			for (int yy = 0; yy < ny; yy++) {
				int y = fwd ? yy : ny - 1 - yy;
				for (int xx = 0; xx < nx; xx++) {
					int x = fwd ? xx : nx - 1 - xx;
					int64_t i = x + (int64_t)nx * (y + (int64_t)ny * z);
					if (!m[i]) continue;
					double best = d[i];
					for (int dz = -1; dz <= 1; dz++) for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
						if (!dx && !dy && !dz) continue;
						int key = dz != 0 ? dz : (dy != 0 ? dy : dx);
						if (fwd ? key > 0 : key < 0) continue;
						int a = x + dx, b = y + dy, c = z + dz;
						int k = std::abs(dx) + std::abs(dy) + std::abs(dz);
						double w = k == 1 ? w1 : (k == 2 ? w2 : w3);
						double nd;
						if (a < 0 || b < 0 || c < 0 || a >= nx || b >= ny || c >= nz) nd = w;
						else nd = d[a + (int64_t)nx * (b + (int64_t)ny * c)] + w;
						if (nd < best) best = nd;
					}
					d[i] = best;
				}
			}
		}
	}
	PackedFloat32Array out;
	out.resize(N);
	float *o = out.ptrw();
	for (int64_t i = 0; i < N; i++) o[i] = (float)d[i];
	return out;
}

static double seg_dist(double pxx, double pyy, double pzz, const Vector3 &a, const Vector3 &b) {
	double abx = (double)b.x - a.x, aby = (double)b.y - a.y, abz = (double)b.z - a.z;
	double l2 = abx * abx + aby * aby + abz * abz;
	double px = pxx - a.x, py = pyy - a.y, pz = pzz - a.z;
	double t = l2 > 1e-18 ? std::min(1.0, std::max(0.0, (px * abx + py * aby + pz * abz) / l2)) : 0.0;
	double qx = px - abx * t, qy = py - aby * t, qz = pz - abz * t;
	return std::sqrt(qx * qx + qy * qy + qz * qz);
}

Dictionary KineAutoRigNative::bind(const PackedByteArray &p_mask, double vs, int nx, int ny, int nz, const Vector3 &p_origin,
		const PackedVector3Array &p_sa, const PackedVector3Array &p_sb, const PackedInt32Array &p_sbone, int nb, double R, int smooth) {
	Dictionary res;
	int64_t N = (int64_t)nx * ny * nz;
	const uint8_t *m = p_mask.ptr();
	std::vector<int32_t> cid(N, -1);
	std::vector<int64_t> vox;
	for (int64_t i = 0; i < N; i++) {
		if (m[i]) {
			cid[i] = (int32_t)vox.size();
			vox.push_back(i);
		}
	}
	int n = (int)vox.size();
	std::vector<double> cx(n), cy(n), cz(n);
	for (int k = 0; k < n; k++) {
		int64_t i = vox[k];
		int x = (int)(i % nx), y = (int)((i / nx) % ny), z = (int)(i / ((int64_t)nx * ny));
		cx[k] = (double)p_origin.x + (x + 0.5) * vs;
		cy[k] = (double)p_origin.y + (y + 0.5) * vs;
		cz[k] = (double)p_origin.z + (z + 0.5) * vs;
	}
	const double INF = 1e30;
	std::vector<double> D((size_t)n * nb, INF);
	int off[26][3];
	double wl[26];
	int no = 0;
	for (int dz = -1; dz <= 1; dz++) for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
		if (!dx && !dy && !dz) continue;
		off[no][0] = dx; off[no][1] = dy; off[no][2] = dz;
		wl[no] = vs * std::sqrt((double)(dx * dx + dy * dy + dz * dz));
		no++;
	}
	typedef std::pair<double, int> QE;
	for (int b = 0; b < nb; b++) {
		std::vector<double> d(n, INF);
		std::priority_queue<QE, std::vector<QE>, std::greater<QE>> pq;
		bool any = false;
		for (int s = 0; s < p_sbone.size(); s++) {
			if (p_sbone[s] != b) continue;
			for (int k = 0; k < n; k++) {
				double sd = seg_dist(cx[k], cy[k], cz[k], p_sa[s], p_sb[s]);
				if (sd <= 1.5 * vs && sd < d[k]) {
					d[k] = sd;
					any = true;
				}
			}
		}
		if (!any) {
			double bd = INF;
			int bk = -1;
			for (int s = 0; s < p_sbone.size(); s++) {
				if (p_sbone[s] != b) continue;
				for (int k = 0; k < n; k++) {
					double sd = seg_dist(cx[k], cy[k], cz[k], p_sa[s], p_sb[s]);
					if (sd < bd) { bd = sd; bk = k; }
				}
			}
			if (bk >= 0) d[bk] = bd;
		}
		for (int k = 0; k < n; k++) if (d[k] < INF) pq.push(QE(d[k], k));
		while (!pq.empty()) {
			QE e = pq.top();
			pq.pop();
			int u = e.second;
			if (e.first > d[u]) continue;
			int64_t i = vox[u];
			int x = (int)(i % nx), y = (int)((i / nx) % ny), z = (int)(i / ((int64_t)nx * ny));
			for (int q = 0; q < no; q++) {
				int a = x + off[q][0], bb = y + off[q][1], c = z + off[q][2];
				if (a < 0 || bb < 0 || c < 0 || a >= nx || bb >= ny || c >= nz) continue;
				int v = cid[a + (int64_t)nx * (bb + (int64_t)ny * c)];
				if (v < 0) continue;
				double nd = d[u] + wl[q];
				if (nd < d[v]) {
					d[v] = nd;
					pq.push(QE(nd, v));
				}
			}
		}
		for (int k = 0; k < n; k++) D[(size_t)k * nb + b] = d[k];
	}
	std::vector<double> W((size_t)n * nb, 0.0);
	for (int k = 0; k < n; k++) {
		double dm = INF;
		for (int b = 0; b < nb; b++) dm = std::min(dm, D[(size_t)k * nb + b]);
		if (dm >= INF) {
			double bd = INF;
			int bb = 0;
			for (int s = 0; s < p_sbone.size(); s++) {
				double sd = seg_dist(cx[k], cy[k], cz[k], p_sa[s], p_sb[s]);
				if (sd < bd) { bd = sd; bb = p_sbone[s]; }
			}
			W[(size_t)k * nb + bb] = 1.0;
			continue;
		}
		double sum = 0.0;
		for (int b = 0; b < nb; b++) {
			double x = D[(size_t)k * nb + b];
			double t = x - dm;
			double r = x >= INF ? 0.0 : std::max(0.0, (R - t) / (R + t));
			W[(size_t)k * nb + b] = r;
			sum += r;
		}
		for (int b = 0; b < nb; b++) W[(size_t)k * nb + b] /= sum;
	}
	// diffusion: w <- 0.5 w + 0.5 mean(6-neighbours inside)
	std::vector<double> W2((size_t)n * nb);
	static const int six[6][3] = { { -1, 0, 0 }, { 1, 0, 0 }, { 0, -1, 0 }, { 0, 1, 0 }, { 0, 0, -1 }, { 0, 0, 1 } };
	for (int it = 0; it < smooth; it++) {
		for (int k = 0; k < n; k++) {
			int64_t i = vox[k];
			int x = (int)(i % nx), y = (int)((i / nx) % ny), z = (int)(i / ((int64_t)nx * ny));
			int nbr[6];
			int cnt = 0;
			for (int q = 0; q < 6; q++) {
				int a = x + six[q][0], bb = y + six[q][1], c = z + six[q][2];
				if (a < 0 || bb < 0 || c < 0 || a >= nx || bb >= ny || c >= nz) continue;
				int v = cid[a + (int64_t)nx * (bb + (int64_t)ny * c)];
				if (v >= 0) nbr[cnt++] = v;
			}
			for (int b = 0; b < nb; b++) {
				if (cnt == 0) { W2[(size_t)k * nb + b] = W[(size_t)k * nb + b]; continue; }
				double s = 0.0;
				for (int q = 0; q < cnt; q++) s += W[(size_t)nbr[q] * nb + b];
				W2[(size_t)k * nb + b] = 0.5 * W[(size_t)k * nb + b] + 0.5 * s / cnt;
			}
		}
		W.swap(W2);
	}
	PackedFloat32Array out;
	out.resize((int64_t)n * nb);
	float *o = out.ptrw();
	for (size_t i = 0; i < W.size(); i++) o[i] = (float)W[i];
	res["n"] = n;
	res["w"] = out;
	return res;
}
