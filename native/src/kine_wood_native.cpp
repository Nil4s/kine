#include "kine_wood_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

using namespace godot;

namespace {

const double PI2 = 6.283185307179586476925286766559;
const double EWR = 0.804, EWG = 0.635, EWB = 0.486, LATE_K = 0.77;
const double PORE_CELL = 0.42, PORE_STRETCH = 8.0;
const int RAY_SLOTS = 240;

inline double hash3(int64_t x, int64_t y, int64_t z, int64_t s) {
	uint32_t h = ((uint32_t)x * 0x8da6b343u) ^ ((uint32_t)y * 0xd8163841u) ^ ((uint32_t)z * 0xcb1ab31fu) ^ ((uint32_t)s * 0x165667b1u);
	h ^= h >> 15;
	h *= 0x2c1b3c6du;
	h ^= h >> 12;
	h *= 0x297a2d39u;
	h ^= h >> 15;
	return (double)h / 4294967296.0;
}
inline double vnoise(double x, double y, double z, int s) {
	int64_t ix = (int64_t)std::floor(x), iy = (int64_t)std::floor(y), iz = (int64_t)std::floor(z);
	double fx = x - ix, fy = y - iy, fz = z - iz;
	fx = fx * fx * (3.0 - 2.0 * fx);
	fy = fy * fy * (3.0 - 2.0 * fy);
	fz = fz * fz * (3.0 - 2.0 * fz);
	double c000 = hash3(ix, iy, iz, s), c100 = hash3(ix + 1, iy, iz, s), c010 = hash3(ix, iy + 1, iz, s), c110 = hash3(ix + 1, iy + 1, iz, s);
	double c001 = hash3(ix, iy, iz + 1, s), c101 = hash3(ix + 1, iy, iz + 1, s), c011 = hash3(ix, iy + 1, iz + 1, s), c111 = hash3(ix + 1, iy + 1, iz + 1, s);
	double x00 = c000 + (c100 - c000) * fx, x10 = c010 + (c110 - c010) * fx, x01 = c001 + (c101 - c001) * fx, x11 = c011 + (c111 - c011) * fx;
	double y0 = x00 + (x10 - x00) * fy, y1 = x01 + (x11 - x01) * fy;
	return y0 + (y1 - y0) * fz;
}
inline double sstep(double e0, double e1, double x) {
	double t = std::min(std::max((x - e0) / (e1 - e0), 0.0), 1.0);
	return t * t * (3.0 - 2.0 * t);
}
inline double dot3(const Vector3 &a, double x, double y, double z) { return (double)a.x * x + (double)a.y * y + (double)a.z * z; }

} // namespace

void KineWoodNative::_bind_methods() {
	ClassDB::bind_static_method("KineWoodNative", D_METHOD("version"), &KineWoodNative::version);
	ClassDB::bind_static_method("KineWoodNative", D_METHOD("sample", "pts", "pith", "w", "u", "v", "seed", "ring", "ring_var", "oval", "oval_ang", "pore_p", "ray_dens"), &KineWoodNative::sample);
}

int KineWoodNative::version() { return 1; }

PackedFloat32Array KineWoodNative::sample(const PackedVector3Array &p_pts, const Vector3 &p_pith, const Vector3 &p_w, const Vector3 &p_u, const Vector3 &p_v,
		int seed, double ring, double ring_var, double oval, double oval_ang, double pore_p, double ray_dens) {
	PackedFloat32Array out;
	int n = p_pts.size();
	out.resize((int64_t)n * 6);
	float *o = out.ptrw();
	const Vector3 *pp = p_pts.ptr();
	double ca = std::cos(oval_ang), sa = std::sin(oval_ang), ov = 1.0 + oval;
	for (int i = 0; i < n; i++) {
		double qx = (double)pp[i].x - p_pith.x, qy = (double)pp[i].y - p_pith.y, qz = (double)pp[i].z - p_pith.z;
		double t = dot3(p_w, qx, qy, qz), a = dot3(p_u, qx, qy, qz), b = dot3(p_v, qx, qy, qz);
		double a2 = a * ca + b * sa, b2 = -a * sa + b * ca;
		double rho0 = std::sqrt(a2 * a2 * ov * ov + b2 * b2);
		double n1 = vnoise(a / 30.0, b / 30.0, t / 120.0, seed + 11);
		double n2 = vnoise(a / 9.0, b / 9.0, t / 45.0, seed + 23);
		double wob = ring_var * (2.0 * n1 - 1.0) * 1.5 + 0.15 * (2.0 * n2 - 1.0);
		double g = rho0 / ring + wob;
		int64_t gi = (int64_t)std::floor(g);
		double f = g - gi;
		double h1 = hash3(gi, 5, 5, seed + 3);
		double lw = sstep(0.45, 0.93, f) * (0.8 + 0.4 * h1);
		double tone = 1.0 + (LATE_K - 1.0) * std::min(lw, 1.0);
		double ewz = 1.0 - sstep(0.0, 0.3, f);
		double pa = a2 / PORE_CELL, pb = b2 / PORE_CELL, pt = t / (PORE_CELL * PORE_STRETCH);
		int64_t ci = (int64_t)std::floor(pa), cj = (int64_t)std::floor(pb), ck = (int64_t)std::floor(pt);
		double cx = 0.5 + 0.3 * (2.0 * hash3(ci, cj, ck, seed + 31) - 1.0);
		double cy = 0.5 + 0.3 * (2.0 * hash3(ci, cj, ck, seed + 32) - 1.0);
		double dx = (pa - ci) - cx, dy = (pb - cj) - cy;
		double e = std::sqrt(dx * dx + dy * dy);
		double present = hash3(ci, cj, ck, seed + 34) < pore_p * ewz ? 1.0 : 0.0;
		double pore = present * (1.0 - sstep(0.17, 0.26, e));
		tone *= 1.0 - 0.45 * pore;
		double ray = 0.0;
		if (rho0 > 4.0) {
			double th = std::atan2(b2, a2);
			double dth = PI2 / RAY_SLOTS;
			int64_t k0 = (int64_t)std::floor(th / dth);
			for (int dk = -2; dk <= 2; dk++) {
				int64_t k = k0 + dk;
				if (hash3(k, 0, 0, seed + 41) >= ray_dens) continue;
				double cth = (k + 0.5 + 0.8 * (hash3(k, 1, 0, seed + 43) - 0.5)) * dth;
				double dd = th - cth;
				if (std::cos(dd) <= 0.0) continue;
				double wk = 0.12 + 0.45 * hash3(k, 2, 0, seed + 44);
				double lat = std::fabs(rho0 * std::sin(dd));
				if (lat >= 0.5 * wk) continue;
				double hk = 14.0 + 40.0 * hash3(k, 3, 0, seed + 45);
				int64_t zi = (int64_t)std::floor((t + hash3(k, 4, 0, seed + 46) * hk) / hk);
				if (hash3(k, zi, 7, seed + 47) >= 0.6) continue;
				double lr = 22.0;
				int64_t ri = (int64_t)std::floor((rho0 + hash3(k, 5, 0, seed + 48) * lr) / lr);
				if (hash3(k, ri, 9, seed + 53) >= 0.7) continue;
				ray = std::max(ray, 1.0 - sstep(0.3 * wk, 0.5 * wk, lat));
			}
		}
		tone *= 1.0 + 0.2 * ray;
		tone *= 0.94 + 0.12 * vnoise(a / 0.45, b / 0.45, t / 18.0, seed + 61);
		tone *= 0.93 + 0.14 * vnoise(qx / 40.0, qy / 40.0, qz / 40.0, seed + 67);
		o[i * 6 + 0] = (float)std::min(std::max(EWR * tone, 0.0), 1.0);
		o[i * 6 + 1] = (float)std::min(std::max(EWG * tone, 0.0), 1.0);
		o[i * 6 + 2] = (float)std::min(std::max(EWB * tone, 0.0), 1.0);
		o[i * 6 + 3] = (float)g;
		o[i * 6 + 4] = (float)pore;
		o[i * 6 + 5] = (float)ray;
	}
	return out;
}
