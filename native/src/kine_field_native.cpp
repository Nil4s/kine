#include "kine_field_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace godot;

namespace {

struct V {
	float x, y, z;
};
inline V sub(const V &a, const V &b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline V add(const V &a, const V &b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline V mul(const V &a, double s) { float f = (float)s; return {a.x * f, a.y * f, a.z * f}; }
inline float dot(const V &a, const V &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V cross(const V &a, const V &b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline float len(const V &a) { return std::sqrt(a.x * a.x + a.y * a.y + a.z * a.z); }

// AnyGrip.MeshField.closest (Ericson 5.1.5), the same branch order
V closest(const V &p, const V &a, const V &b, const V &c) {
	V ab = sub(b, a), ac = sub(c, a), ap = sub(p, a);
	double d1 = dot(ab, ap), d2 = dot(ac, ap);
	if (d1 <= 0.0 && d2 <= 0.0) return a;
	V bp = sub(p, b);
	double d3 = dot(ab, bp), d4 = dot(ac, bp);
	if (d3 >= 0.0 && d4 <= d3) return b;
	double vc = d1 * d4 - d3 * d2;
	if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) return add(a, mul(ab, d1 / (d1 - d3)));
	V cp = sub(p, c);
	double d5 = dot(ab, cp), d6 = dot(ac, cp);
	if (d6 >= 0.0 && d5 <= d6) return c;
	double vb = d5 * d2 - d1 * d6;
	if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) return add(a, mul(ac, d2 / (d2 - d6)));
	double va = d3 * d6 - d5 * d4;
	if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) return add(b, mul(sub(c, b), (d4 - d3) / ((d4 - d3) + (d5 - d6))));
	double denom = 1.0 / (va + vb + vc);
	return add(add(a, mul(ab, vb * denom)), mul(ac, vc * denom));
}

inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

} // namespace

void KineFieldNative::_bind_methods() {
	ClassDB::bind_static_method("KineFieldNative", D_METHOD("version"), &KineFieldNative::version);
	ClassDB::bind_static_method("KineFieldNative", D_METHOD("banded", "tris", "gmin", "nx", "ny", "nz", "cell", "flip", "band", "on_surface"), &KineFieldNative::banded);
}

int KineFieldNative::version() { return 1; }

PackedFloat32Array KineFieldNative::banded(const PackedVector3Array &p_tris, const Vector3 &p_gmin, int nx, int ny, int nz,
		double cell, double flip, double band, double on_surface) {
	PackedFloat32Array out;
	if (nx <= 0 || ny <= 0 || nz <= 0) return out;
	int64_t n = (int64_t)nx * ny * nz;
	out.resize(n);
	float *d = out.ptrw();
	std::vector<float> dist((size_t)n, INFINITY);
	std::vector<uint8_t> touched((size_t)n, 0);
	const V gmin{p_gmin.x, p_gmin.y, p_gmin.z};
	const double reach = band * cell;
	const float reachf = (float)reach;
	const int64_t ntri = p_tris.size() / 3;
	const Vector3 *tp = p_tris.ptr();
	for (int64_t t = 0; t < ntri; t++) {
		V a{tp[3 * t].x, tp[3 * t].y, tp[3 * t].z};
		V b{tp[3 * t + 1].x, tp[3 * t + 1].y, tp[3 * t + 1].z};
		V c{tp[3 * t + 2].x, tp[3 * t + 2].y, tp[3 * t + 2].z};
		V nrm = cross(sub(b, a), sub(c, a));
		V nt;
		float nl = len(nrm);
		if ((double)nl > 1e-12) {
			nt = {nrm.x / nl, nrm.y / nl, nrm.z / nl};
			nt = mul(nt, flip);
		} else {
			nt = {0, 1, 0};
		}
		V amin{std::min(std::min(a.x, b.x), c.x) - reachf, std::min(std::min(a.y, b.y), c.y) - reachf, std::min(std::min(a.z, b.z), c.z) - reachf};
		V amax{std::max(std::max(a.x, b.x), c.x) + reachf, std::max(std::max(a.y, b.y), c.y) + reachf, std::max(std::max(a.z, b.z), c.z) + reachf};
		int i0 = clampi((int)std::floor(((double)amin.x - gmin.x) / cell), 0, nx - 1);
		int j0 = clampi((int)std::floor(((double)amin.y - gmin.y) / cell), 0, ny - 1);
		int k0 = clampi((int)std::floor(((double)amin.z - gmin.z) / cell), 0, nz - 1);
		int i1 = clampi((int)std::ceil(((double)amax.x - gmin.x) / cell), 0, nx - 1);
		int j1 = clampi((int)std::ceil(((double)amax.y - gmin.y) / cell), 0, ny - 1);
		int k1 = clampi((int)std::ceil(((double)amax.z - gmin.z) / cell), 0, nz - 1);
		const float cf = (float)cell;
		for (int k = k0; k <= k1; k++) {
			for (int j = j0; j <= j1; j++) {
				for (int i = i0; i <= i1; i++) {
					int64_t idx = i + (int64_t)nx * (j + (int64_t)ny * k);
					V p{gmin.x + (float)i * cf, gmin.y + (float)j * cf, gmin.z + (float)k * cf};
					V q = closest(p, a, b, c);
					V pq = sub(p, q);
					double dd = len(pq);
					if (dd < (double)dist[idx]) {
						dist[idx] = (float)dd;
						d[idx] = (float)(dd * ((dd < on_surface || (double)dot(pq, nt) >= 0.0) ? 1.0 : -1.0));
						touched[idx] = 1;
					}
				}
			}
		}
	}
	// the untouched voxels: outside if reachable from the grid's edge through untouched voxels, else inside
	std::vector<uint8_t> outside((size_t)n, 0);
	std::vector<int32_t> queue;
	queue.reserve(1024);
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				if (i > 0 && j > 0 && k > 0 && i < nx - 1 && j < ny - 1 && k < nz - 1) continue;
				int64_t idx = i + (int64_t)nx * (j + (int64_t)ny * k);
				if (!touched[idx]) {
					outside[idx] = 1;
					queue.push_back((int32_t)idx);
				}
			}
	const int64_t slab = (int64_t)nx * ny;
	static const int st[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
	for (size_t head = 0; head < queue.size(); head++) {
		int64_t c = queue[head];
		int i = (int)(c % nx), j = (int)((c / nx) % ny), k = (int)(c / slab);
		for (auto &s : st) {
			int ni = i + s[0], nj = j + s[1], nk = k + s[2];
			if (ni < 0 || nj < 0 || nk < 0 || ni >= nx || nj >= ny || nk >= nz) continue;
			int64_t nidx = ni + (int64_t)nx * (nj + (int64_t)ny * nk);
			if (!touched[nidx] && !outside[nidx]) {
				outside[nidx] = 1;
				queue.push_back((int32_t)nidx);
			}
		}
	}
	const float reachv = (float)reach;
	for (int64_t idx = 0; idx < n; idx++)
		if (!touched[idx]) d[idx] = outside[idx] ? reachv : -reachv;
	return out;
}
