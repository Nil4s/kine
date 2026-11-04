#include "kine_fluid_native.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <thread>

using namespace godot;

namespace {

typedef std::chrono::steady_clock Clk;
inline double ms_since(Clk::time_point t) { return std::chrono::duration<double, std::milli>(Clk::now() - t).count(); }

template <class F>
void pfor(int n, int nt, F f) { // f(begin, end)
	if (nt <= 1 || n < 2 * nt) {
		f(0, n);
		return;
	}
	std::vector<std::thread> th;
	int chunk = (n + nt - 1) / nt;
	for (int t = 1; t < nt; t++) {
		int b = t * chunk, e = std::min(n, b + chunk);
		if (b < e) th.emplace_back([=]() { f(b, e); });
	}
	f(0, std::min(n, chunk));
	for (auto &t : th) t.join();
}

inline uint32_t hash32(uint32_t x) {
	x ^= x >> 16;
	x *= 0x7feb352du;
	x ^= x >> 15;
	x *= 0x846ca68bu;
	x ^= x >> 16;
	return x;
}

// quadratic B-spline: base = floor(q - 0.5), nodes base..base+2, f = q - base in [0.5, 1.5)
inline void w3(double q, int &base, double &f, double w[3]) {
	base = (int)std::floor(q - 0.5);
	f = q - base;
	double a = 1.5 - f;
	w[0] = 0.5 * a * a;
	double b = f - 1.0;
	w[1] = 0.75 - b * b;
	double c = f - 0.5;
	w[2] = 0.5 * c * c;
}

// triangle - axis aligned box overlap (separating axis theorem, 13 axes). Box centred at the origin, half size e.
bool tri_box(const double v0[3], const double v1[3], const double v2[3], double e) {
	const double *v[3] = { v0, v1, v2 };
	for (int a = 0; a < 3; a++) {
		double mn = std::min(v0[a], std::min(v1[a], v2[a])), mx = std::max(v0[a], std::max(v1[a], v2[a]));
		if (mn > e || mx < -e) return false;
	}
	double f[3][3];
	for (int i = 0; i < 3; i++)
		for (int a = 0; a < 3; a++) f[i][a] = v[(i + 1) % 3][a] - v[i][a];
	double n[3] = { f[0][1] * f[1][2] - f[0][2] * f[1][1], f[0][2] * f[1][0] - f[0][0] * f[1][2], f[0][0] * f[1][1] - f[0][1] * f[1][0] };
	double d = n[0] * v0[0] + n[1] * v0[1] + n[2] * v0[2];
	double r = e * (std::fabs(n[0]) + std::fabs(n[1]) + std::fabs(n[2]));
	if (std::fabs(d) > r) return false;
	for (int i = 0; i < 3; i++) {
		for (int a = 0; a < 3; a++) {
			double u[3] = { 0, 0, 0 };
			u[a] = 1;
			double ax[3] = { u[1] * f[i][2] - u[2] * f[i][1], u[2] * f[i][0] - u[0] * f[i][2], u[0] * f[i][1] - u[1] * f[i][0] };
			double p0 = ax[0] * v0[0] + ax[1] * v0[1] + ax[2] * v0[2];
			double p1 = ax[0] * v1[0] + ax[1] * v1[1] + ax[2] * v1[2];
			double p2 = ax[0] * v2[0] + ax[1] * v2[1] + ax[2] * v2[2];
			double rr = e * (std::fabs(ax[0]) + std::fabs(ax[1]) + std::fabs(ax[2]));
			if (std::min(p0, std::min(p1, p2)) > rr || std::max(p0, std::max(p1, p2)) < -rr) return false;
		}
	}
	return true;
}

} // namespace

void KineFluidNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "nx", "ny", "nz", "h", "origin"), &KineFluidNative::setup);
	ClassDB::bind_method(D_METHOD("set_threads", "n"), &KineFluidNative::set_threads);
	ClassDB::bind_method(D_METHOD("set_params", "gravity", "drift", "cfl", "dt_max", "max_iters", "tol"), &KineFluidNative::set_params);
	ClassDB::bind_method(D_METHOD("add_solid_box", "min", "max"), &KineFluidNative::add_solid_box);
	ClassDB::bind_method(D_METHOD("add_solid_mesh", "verts", "tris"), &KineFluidNative::add_solid_mesh);
	ClassDB::bind_method(D_METHOD("add_fluid_box", "min", "max", "vel", "seed"), &KineFluidNative::add_fluid_box);
	ClassDB::bind_method(D_METHOD("step", "dt"), &KineFluidNative::step);
	ClassDB::bind_method(D_METHOD("advance", "t"), &KineFluidNative::advance);
	ClassDB::bind_method(D_METHOD("particle_count"), &KineFluidNative::particle_count);
	ClassDB::bind_method(D_METHOD("particle_data"), &KineFluidNative::particle_data);
	ClassDB::bind_method(D_METHOD("positions"), &KineFluidNative::positions);
	ClassDB::bind_method(D_METHOD("stats"), &KineFluidNative::stats);
	ClassDB::bind_method(D_METHOD("get_pressure", "i", "j", "k"), &KineFluidNative::get_pressure);
	ClassDB::bind_method(D_METHOD("solid_count"), &KineFluidNative::solid_count);
	ClassDB::bind_method(D_METHOD("particles_in_solid"), &KineFluidNative::particles_in_solid);
	ClassDB::bind_method(D_METHOD("particles_in_mesh", "verts", "tris"), &KineFluidNative::particles_in_mesh);
	ClassDB::bind_method(D_METHOD("volume_ratio"), &KineFluidNative::volume_ratio);
	ClassDB::bind_method(D_METHOD("surface", "smooth", "iso"), &KineFluidNative::surface);
	ClassDB::bind_method(D_METHOD("clear_particles"), &KineFluidNative::clear_particles);
	ClassDB::bind_method(D_METHOD("set_wall_friction", "f"), &KineFluidNative::set_wall_friction);
}

void KineFluidNative::setup(int p_nx, int p_ny, int p_nz, double p_h, Vector3 p_origin) {
	nx = p_nx; ny = p_ny; nz = p_nz; h = p_h;
	ox = p_origin.x; oy = p_origin.y; oz = p_origin.z;
	size_t nc = (size_t)nx * ny * nz;
	solid.assign(nc, 0);
	type.assign(nc, 0);
	cnt.assign(nc, 0);
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++)
				if (i == 0 || j == 0 || k == 0 || i == nx - 1 || j == ny - 1 || k == nz - 1) solid[cid(i, j, k)] = 1;
	U.assign((size_t)(nx + 1) * ny * nz, 0); mU = U;
	Vg.assign((size_t)nx * (ny + 1) * nz, 0); mV = Vg;
	W.assign((size_t)nx * ny * (nz + 1), 0); mW = W;
	pr.assign(nc, 0); rhs = pr; rr = pr; zz = pr; ss = pr; qq = pr; pre = pr; adiag = pr;
	P.clear(); V.clear(); C.clear();
}

void KineFluidNative::set_params(double p_g, double p_drift, double p_cfl, double p_dtmax, int p_iters, double p_tol) {
	grav = p_g; drift = p_drift; cfl = p_cfl; dtmax = p_dtmax; max_iter = p_iters; tol = p_tol;
}

void KineFluidNative::clear_particles() { P.clear(); V.clear(); C.clear(); }

void KineFluidNative::add_solid_box(Vector3 mn, Vector3 mx) {
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				double cx = ox + (i + 0.5) * h, cy = oy + (j + 0.5) * h, cz = oz + (k + 0.5) * h;
				if (cx >= mn.x && cx <= mx.x && cy >= mn.y && cy <= mx.y && cz >= mn.z && cz <= mx.z) solid[cid(i, j, k)] = 1;
			}
}

int KineFluidNative::add_solid_mesh(const PackedVector3Array &vs, const PackedInt32Array &tr) {
	int added = 0;
	int nt3 = tr.size() / 3;
	double e = h * 0.5;
	for (int t = 0; t < nt3; t++) {
		Vector3 a = vs[tr[3 * t]], b = vs[tr[3 * t + 1]], c = vs[tr[3 * t + 2]];
		double lo[3] = { std::min({ a.x, b.x, c.x }), std::min({ a.y, b.y, c.y }), std::min({ a.z, b.z, c.z }) };
		double hi[3] = { std::max({ a.x, b.x, c.x }), std::max({ a.y, b.y, c.y }), std::max({ a.z, b.z, c.z }) };
		double org[3] = { ox, oy, oz };
		int i0[3], i1[3], dim[3] = { nx, ny, nz };
		for (int ax = 0; ax < 3; ax++) {
			i0[ax] = std::max(0, (int)std::floor((lo[ax] - org[ax]) / h));
			i1[ax] = std::min(dim[ax] - 1, (int)std::floor((hi[ax] - org[ax]) / h));
		}
		for (int k = i0[2]; k <= i1[2]; k++)
			for (int j = i0[1]; j <= i1[1]; j++)
				for (int i = i0[0]; i <= i1[0]; i++) {
					if (solid[cid(i, j, k)]) continue;
					double c0[3] = { ox + (i + 0.5) * h, oy + (j + 0.5) * h, oz + (k + 0.5) * h };
					double v0[3] = { a.x - c0[0], a.y - c0[1], a.z - c0[2] };
					double v1[3] = { b.x - c0[0], b.y - c0[1], b.z - c0[2] };
					double v2[3] = { c.x - c0[0], c.y - c0[1], c.z - c0[2] };
					if (tri_box(v0, v1, v2, e)) {
						solid[cid(i, j, k)] = 1;
						added++;
					}
				}
	}
	return added;
}

int KineFluidNative::add_fluid_box(Vector3 mn, Vector3 mx, Vector3 vel, int seed) {
	int i0 = (int)std::floor((mn.x - ox) / h + 1e-9), i1 = (int)std::ceil((mx.x - ox) / h - 1e-9) - 1;
	int j0 = (int)std::floor((mn.y - oy) / h + 1e-9), j1 = (int)std::ceil((mx.y - oy) / h - 1e-9) - 1;
	int k0 = (int)std::floor((mn.z - oz) / h + 1e-9), k1 = (int)std::ceil((mx.z - oz) / h - 1e-9) - 1;
	int added = 0;
	for (int k = k0; k <= k1; k++)
		for (int j = j0; j <= j1; j++)
			for (int i = i0; i <= i1; i++) {
				if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz || solid[cid(i, j, k)]) continue;
				int c = cid(i, j, k);
				for (int s = 0; s < 8; s++) {
					double pos[3];
					int sub[3] = { s & 1, (s >> 1) & 1, (s >> 2) & 1 };
					int cell[3] = { i, j, k };
					for (int a = 0; a < 3; a++) {
						uint32_t key = (uint32_t)((int64_t)c * 24 + s * 3 + a) + (uint32_t)seed * 1000003u;
						double u = hash32(key) / 4294967296.0;
						pos[a] = (cell[a] + 0.5 * sub[a] + 0.5 * (0.1 + 0.8 * u)) * h;
					}
					P.push_back(ox + pos[0]); P.push_back(oy + pos[1]); P.push_back(oz + pos[2]);
					V.push_back(vel.x); V.push_back(vel.y); V.push_back(vel.z);
					for (int q = 0; q < 9; q++) C.push_back(0.0);
					added++;
				}
			}
	return added;
}

void KineFluidNative::sort_particles() {
	size_t nc = (size_t)nx * ny * nz;
	int N = particle_count();
	cstart.assign(nc + 1, 0);
	std::vector<int32_t> pc(N);
	for (int p = 0; p < N; p++) {
		int i = std::clamp((int)std::floor((P[3 * p] - ox) / h), 0, nx - 1);
		int j = std::clamp((int)std::floor((P[3 * p + 1] - oy) / h), 0, ny - 1);
		int k = std::clamp((int)std::floor((P[3 * p + 2] - oz) / h), 0, nz - 1);
		pc[p] = cid(i, j, k);
		cstart[pc[p] + 1]++;
	}
	for (size_t c = 0; c < nc; c++) cstart[c + 1] += cstart[c];
	std::vector<int32_t> fillp(cstart.begin(), cstart.end() - 1);
	order.resize(N);
	for (int p = 0; p < N; p++) order[fillp[pc[p]]++] = p;
}

void KineFluidNative::mark_cells() {
	std::fill(cnt.begin(), cnt.end(), 0);
	int N = particle_count();
	for (int p = 0; p < N; p++) {
		int i = (int)std::floor((P[3 * p] - ox) / h), j = (int)std::floor((P[3 * p + 1] - oy) / h), k = (int)std::floor((P[3 * p + 2] - oz) / h);
		if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) continue;
		cnt[cid(i, j, k)]++;
	}
	fl.clear();
	size_t nc = (size_t)nx * ny * nz;
	for (size_t c = 0; c < nc; c++) {
		if (solid[c]) type[c] = 2;
		else if (cnt[c] > 0) { type[c] = 1; fl.push_back((int32_t)c); }
		else type[c] = 0;
	}
}

void KineFluidNative::p2g() {
	std::fill(U.begin(), U.end(), 0.0); std::fill(mU.begin(), mU.end(), 0.0);
	std::fill(Vg.begin(), Vg.end(), 0.0); std::fill(mV.begin(), mV.end(), 0.0);
	std::fill(W.begin(), W.end(), 0.0); std::fill(mW.begin(), mW.end(), 0.0);
	auto one = [&](int p) {
		const double *x = &P[3 * p], *v = &V[3 * p], *Cp = &C[9 * p];
		for (int c = 0; c < 3; c++) {
			double off[3] = { 0.5, 0.5, 0.5 };
			off[c] = 0.0;
			int dim[3] = { nx, ny, nz };
			dim[c] += 1;
			std::vector<double> &mom = c == 0 ? U : (c == 1 ? Vg : W);
			std::vector<double> &ws = c == 0 ? mU : (c == 1 ? mV : mW);
			int bx, by, bz;
			double fx, fy, fz, wx[3], wy[3], wz[3];
			w3((x[0] - ox) / h - off[0], bx, fx, wx);
			w3((x[1] - oy) / h - off[1], by, fy, wy);
			w3((x[2] - oz) / h - off[2], bz, fz, wz);
			for (int kk = 0; kk < 3; kk++) {
				int nk = bz + kk;
				if (nk < 0 || nk >= dim[2]) continue;
				double dz = (kk - fz) * h;
				for (int jj = 0; jj < 3; jj++) {
					int nj = by + jj;
					if (nj < 0 || nj >= dim[1]) continue;
					double dy = (jj - fy) * h;
					for (int ii = 0; ii < 3; ii++) {
						int ni = bx + ii;
						if (ni < 0 || ni >= dim[0]) continue;
						double dx = (ii - fx) * h;
						double Wt = wx[ii] * wy[jj] * wz[kk];
						size_t idx = ni + (size_t)dim[0] * (nj + (size_t)dim[1] * nk);
						mom[idx] += Wt * (v[c] + Cp[3 * c] * dx + Cp[3 * c + 1] * dy + Cp[3 * c + 2] * dz);
						ws[idx] += Wt;
					}
				}
			}
		}
	};
	int N = particle_count();
	if (nt <= 1) {
		for (int p = 0; p < N; p++) one(p);
	} else {
		auto t0 = Clk::now();
		sort_particles();
		tm_sort = ms_since(t0);
		const int T = 4;
		int ns = (nz + T - 1) / T;
		for (int par = 0; par < 2; par++) {
			std::vector<int> slabs;
			for (int s = par; s < ns; s += 2) slabs.push_back(s);
			pfor((int)slabs.size(), nt, [&](int b, int e) {
				for (int q = b; q < e; q++) {
					int s = slabs[q];
					int c0 = cid(0, 0, s * T), c1 = cid(0, 0, std::min(nz, s * T + T));
					for (int a = cstart[c0]; a < cstart[c1]; a++) one(order[a]);
				}
			});
		}
	}
	for (size_t n = 0; n < U.size(); n++) U[n] = mU[n] > 0 ? U[n] / mU[n] : 0.0;
	for (size_t n = 0; n < Vg.size(); n++) Vg[n] = mV[n] > 0 ? Vg[n] / mV[n] : 0.0;
	for (size_t n = 0; n < W.size(); n++) W[n] = mW[n] > 0 ? W[n] / mW[n] : 0.0;
}

void KineFluidNative::pcg() {
	int n = (int)fl.size();
	last_iters = 0;
	if (n == 0) return;
	const int sx = 1, sy = nx, sz = nx * ny;
	auto isf = [&](int c) { return type[c] == 1; };
	for (int q = 0; q < n; q++) {
		int c = fl[q];
		double d = 0;
		for (int off : { -sx, sx, -sy, sy, -sz, sz }) if (type[c + off] != 2) d += 1;
		adiag[c] = d;
	}
	auto ap = [&](int c, int off) { return (isf(c) && isf(c + off)) ? -1.0 : 0.0; };
	const double tau = 0.97, sigma = 0.25;
	for (int q = 0; q < n; q++) {
		int c = fl[q];
		double e = adiag[c];
		if (isf(c - sx)) {
			int m = c - sx; double p = pre[m];
			e -= (ap(m, sx) * p) * (ap(m, sx) * p) + tau * (ap(m, sx) * (ap(m, sy) + ap(m, sz)) * p * p);
		}
		if (isf(c - sy)) {
			int m = c - sy; double p = pre[m];
			e -= (ap(m, sy) * p) * (ap(m, sy) * p) + tau * (ap(m, sy) * (ap(m, sx) + ap(m, sz)) * p * p);
		}
		if (isf(c - sz)) {
			int m = c - sz; double p = pre[m];
			e -= (ap(m, sz) * p) * (ap(m, sz) * p) + tau * (ap(m, sz) * (ap(m, sx) + ap(m, sy)) * p * p);
		}
		if (e < sigma * adiag[c]) e = adiag[c];
		pre[c] = 1.0 / std::sqrt(e);
	}
	auto precond = [&](const std::vector<double> &r, std::vector<double> &z) {
		for (int q = 0; q < n; q++) {
			int c = fl[q];
			double t = r[c];
			if (isf(c - sx)) t -= ap(c - sx, sx) * pre[c - sx] * qq[c - sx];
			if (isf(c - sy)) t -= ap(c - sy, sy) * pre[c - sy] * qq[c - sy];
			if (isf(c - sz)) t -= ap(c - sz, sz) * pre[c - sz] * qq[c - sz];
			qq[c] = t * pre[c];
		}
		for (int q = n - 1; q >= 0; q--) {
			int c = fl[q];
			double t = qq[c];
			if (isf(c + sx)) t -= ap(c, sx) * pre[c] * z[c + sx];
			if (isf(c + sy)) t -= ap(c, sy) * pre[c] * z[c + sy];
			if (isf(c + sz)) t -= ap(c, sz) * pre[c] * z[c + sz];
			z[c] = t * pre[c];
		}
	};
	auto dot = [&](const std::vector<double> &a, const std::vector<double> &b) {
		if (nt <= 1 || n < 20000) { double s = 0; for (int q = 0; q < n; q++) s += a[fl[q]] * b[fl[q]]; return s; }
		std::vector<double> part(nt, 0.0);
		int chunk = (n + nt - 1) / nt;
		pfor(nt, nt, [&](int b0, int e0) {
			for (int t = b0; t < e0; t++) { double s = 0; for (int q = t * chunk; q < std::min(n, (t + 1) * chunk); q++) s += a[fl[q]] * b[fl[q]]; part[t] = s; }
		});
		double s = 0; for (double v : part) s += v; return s;
	};
	auto matvec = [&](const std::vector<double> &s, std::vector<double> &out) {
		pfor(n, n < 20000 ? 1 : nt, [&](int b, int e) {
			for (int q = b; q < e; q++) {
				int c = fl[q];
				double t = adiag[c] * s[c];
				if (isf(c - sx)) t -= s[c - sx];
				if (isf(c + sx)) t -= s[c + sx];
				if (isf(c - sy)) t -= s[c - sy];
				if (isf(c + sy)) t -= s[c + sy];
				if (isf(c - sz)) t -= s[c - sz];
				if (isf(c + sz)) t -= s[c + sz];
				out[c] = t;
			}
		});
	};
	double bmax = 0;
	for (int q = 0; q < n; q++) { bmax = std::max(bmax, std::fabs(rhs[fl[q]])); pr[fl[q]] = 0; rr[fl[q]] = rhs[fl[q]]; }
	last_res = bmax;
	if (bmax == 0) return;
	precond(rr, zz);
	for (int q = 0; q < n; q++) ss[fl[q]] = zz[fl[q]];
	double sig = dot(zz, rr);
	for (int it = 0; it < max_iter; it++) {
		matvec(ss, zz);
		double den = dot(ss, zz);
		if (den == 0) break;
		double al = sig / den;
		double rmax = 0;
		for (int q = 0; q < n; q++) { int c = fl[q]; pr[c] += al * ss[c]; rr[c] -= al * zz[c]; rmax = std::max(rmax, std::fabs(rr[c])); }
		last_iters = it + 1;
		last_res = rmax;
		if (rmax < tol * bmax) break;
		precond(rr, zz);
		double sig2 = dot(zz, rr);
		double be = sig2 / sig;
		sig = sig2;
		for (int q = 0; q < n; q++) { int c = fl[q]; ss[c] = zz[c] + be * ss[c]; }
	}
}

void KineFluidNative::apply_wall_friction() {
	// A face that touches a solid wall sideways (a transverse neighbour of either of its two cells is solid) keeps (1 - wfr) of its speed.
	if (wfr <= 0.0) return;
	const double s = 1.0 - wfr;
	const int off[3] = { 1, nx, nx * ny };
	for (int c : fl) {
		for (int ax = 0; ax < 3; ax++) {
			for (int side = 0; side < 2; side++) {
				int a = side == 0 ? c - off[ax] : c, b = side == 0 ? c : c + off[ax];
				if (side == 1 && type[b] == 1) continue;
				bool touch = false;
				for (int t = 0; t < 3 && !touch; t++) {
					if (t == ax) continue;
					if (solid[a - off[t]] || solid[a + off[t]] || solid[b - off[t]] || solid[b + off[t]]) touch = true;
				}
				if (!touch) continue;
				int i = b % nx, j = (b / nx) % ny, k = b / (nx * ny);
				if (ax == 0) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] *= s;
				else if (ax == 1) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] *= s;
				else W[i + (size_t)nx * (j + (size_t)ny * k)] *= s;
			}
		}
	}
}

void KineFluidNative::project(double dt) {
	for (size_t n = 0; n < Vg.size(); n++) Vg[n] -= grav * dt;
	apply_wall_friction();
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i <= nx; i++) {
				bool s = (i == 0 || i == nx) || solid[cid(i - 1, j, k)] || solid[cid(i, j, k)];
				if (s) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] = 0;
			}
	for (int k = 0; k < nz; k++)
		for (int j = 0; j <= ny; j++)
			for (int i = 0; i < nx; i++) {
				bool s = (j == 0 || j == ny) || solid[cid(i, j - 1, k)] || solid[cid(i, j, k)];
				if (s) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] = 0;
			}
	for (int k = 0; k <= nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				bool s = (k == 0 || k == nz) || solid[cid(i, j, k - 1)] || solid[cid(i, j, k)];
				if (s) W[i + (size_t)nx * (j + (size_t)ny * k)] = 0;
			}
	std::fill(pr.begin(), pr.end(), 0.0);
	double sc = h / dt;
	for (int c : fl) {
		int i = c % nx, j = (c / nx) % ny, k = c / (nx * ny);
		double div = U[(i + 1) + (size_t)(nx + 1) * (j + (size_t)ny * k)] - U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)]
				+ Vg[i + (size_t)nx * ((j + 1) + (size_t)(ny + 1) * k)] - Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)]
				+ W[i + (size_t)nx * (j + (size_t)ny * (k + 1))] - W[i + (size_t)nx * (j + (size_t)ny * k)];
		double eps = std::min(1.0, std::max(0.0, (double)cnt[c] / ppc - 1.0));
		rhs[c] = -sc * div + sc * (h / std::max(dt, dtmax)) * drift * eps;
	}
	pcg();
	double f = dt / h;
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 1; i < nx; i++) {
				int a = cid(i - 1, j, k), b = cid(i, j, k);
				if (type[a] == 2 || type[b] == 2) continue;
				if (type[a] == 1 || type[b] == 1) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] -= f * (pr[b] - pr[a]);
			}
	for (int k = 0; k < nz; k++)
		for (int j = 1; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				int a = cid(i, j - 1, k), b = cid(i, j, k);
				if (type[a] == 2 || type[b] == 2) continue;
				if (type[a] == 1 || type[b] == 1) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] -= f * (pr[b] - pr[a]);
			}
	for (int k = 1; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				int a = cid(i, j, k - 1), b = cid(i, j, k);
				if (type[a] == 2 || type[b] == 2) continue;
				if (type[a] == 1 || type[b] == 1) W[i + (size_t)nx * (j + (size_t)ny * k)] -= f * (pr[b] - pr[a]);
			}
}

void KineFluidNative::g2p() {
	int N = particle_count();
	double k4 = 4.0 / (h * h);
	pfor(N, nt, [&](int b0, int e0) {
		for (int p = b0; p < e0; p++) {
			const double *x = &P[3 * p];
			double *v = &V[3 * p], *Cp = &C[9 * p];
			for (int c = 0; c < 3; c++) {
				double off[3] = { 0.5, 0.5, 0.5 };
				off[c] = 0.0;
				int dim[3] = { nx, ny, nz };
				dim[c] += 1;
				const std::vector<double> &g = c == 0 ? U : (c == 1 ? Vg : W);
				int bx, by, bz;
				double fx, fy, fz, wx[3], wy[3], wz[3];
				w3((x[0] - ox) / h - off[0], bx, fx, wx);
				w3((x[1] - oy) / h - off[1], by, fy, wy);
				w3((x[2] - oz) / h - off[2], bz, fz, wz);
				double vs = 0, c0 = 0, c1 = 0, c2 = 0;
				for (int kk = 0; kk < 3; kk++) {
					int nk = bz + kk;
					if (nk < 0 || nk >= dim[2]) continue;
					double dz = (kk - fz) * h;
					for (int jj = 0; jj < 3; jj++) {
						int nj = by + jj;
						if (nj < 0 || nj >= dim[1]) continue;
						double dy = (jj - fy) * h;
						for (int ii = 0; ii < 3; ii++) {
							int ni = bx + ii;
							if (ni < 0 || ni >= dim[0]) continue;
							double dx = (ii - fx) * h;
							double Wt = wx[ii] * wy[jj] * wz[kk];
							double u = g[ni + (size_t)dim[0] * (nj + (size_t)dim[1] * nk)];
							vs += Wt * u;
							c0 += Wt * u * dx; c1 += Wt * u * dy; c2 += Wt * u * dz;
						}
					}
				}
				v[c] = vs;
				Cp[3 * c] = k4 * c0; Cp[3 * c + 1] = k4 * c1; Cp[3 * c + 2] = k4 * c2;
			}
		}
	});
}

void KineFluidNative::advect(double dt) {
	int N = particle_count();
	std::vector<double> vm(nt, 0.0);
	int chunk = std::max(1, (N + nt - 1) / nt);
	pfor(nt, nt, [&](int t0, int t1) {
		for (int t = t0; t < t1; t++) {
			double m = 0;
			for (int p = t * chunk; p < std::min(N, (t + 1) * chunk); p++) {
				double *x = &P[3 * p], *v = &V[3 * p];
				double org[3] = { ox, oy, oz };
				int dim[3] = { nx, ny, nz };
				for (int a = 0; a < 3; a++) {
					double nxp[3] = { x[0], x[1], x[2] };
					nxp[a] += dt * v[a];
					int cc[3];
					for (int q = 0; q < 3; q++) cc[q] = (int)std::floor((nxp[q] - org[q]) / h);
					bool bad = false;
					for (int q = 0; q < 3; q++) if (cc[q] < 0 || cc[q] >= dim[q]) bad = true;
					if (!bad && solid[cid(cc[0], cc[1], cc[2])]) bad = true;
					if (bad) v[a] = 0.0; else x[a] = nxp[a];
				}
				m = std::max(m, std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]));
			}
			vm[t] = m;
		}
	});
	vmax = 0;
	for (double m : vm) vmax = std::max(vmax, m);
}

void KineFluidNative::step(double dt) {
	auto t0 = Clk::now();
	mark_cells();
	p2g();
	tm_p2g = ms_since(t0);
	t0 = Clk::now();
	project(dt);
	tm_proj = ms_since(t0);
	t0 = Clk::now();
	g2p();
	tm_g2p = ms_since(t0);
	t0 = Clk::now();
	advect(dt);
	tm_adv = ms_since(t0);
}

int KineFluidNative::advance(double T) {
	double t = 0;
	int n = 0;
	while (t < T - 1e-12) {
		double dt = dtmax;
		if (vmax > 1e-9) dt = std::min(dt, cfl * h / vmax);
		dt = std::max(dt, dtmax * 0.05);
		if (t + dt > T) dt = T - t;
		step(dt);
		t += dt;
		n++;
	}
	return n;
}

PackedFloat64Array KineFluidNative::particle_data() const {
	PackedFloat64Array out;
	int N = particle_count();
	out.resize(6 * N);
	for (int p = 0; p < N; p++)
		for (int a = 0; a < 3; a++) { out.set(6 * p + a, P[3 * p + a]); out.set(6 * p + 3 + a, V[3 * p + a]); }
	return out;
}

PackedVector3Array KineFluidNative::positions() const {
	PackedVector3Array out;
	int N = particle_count();
	out.resize(N);
	for (int p = 0; p < N; p++) out.set(p, Vector3((real_t)P[3 * p], (real_t)P[3 * p + 1], (real_t)P[3 * p + 2]));
	return out;
}

Dictionary KineFluidNative::stats() {
	Dictionary d;
	d["n"] = particle_count();
	d["fluid_cells"] = (int)fl.size();
	d["vmax"] = vmax;
	d["pcg_iters"] = last_iters;
	d["pcg_res"] = last_res;
	d["ms_p2g"] = tm_p2g; d["ms_project"] = tm_proj; d["ms_g2p"] = tm_g2p; d["ms_advect"] = tm_adv; d["ms_sort"] = tm_sort;
	return d;
}

double KineFluidNative::get_pressure(int i, int j, int k) const {
	if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) return 0.0;
	return pr[cid(i, j, k)] * 1000.0; // rho = 1000 kg/m3; the solve runs at rho 1
}

int KineFluidNative::solid_count() const {
	int n = 0;
	for (uint8_t s : solid) n += s ? 1 : 0;
	return n;
}

int KineFluidNative::particles_in_solid() const {
	int n = 0, N = particle_count();
	for (int p = 0; p < N; p++) {
		int i = (int)std::floor((P[3 * p] - ox) / h), j = (int)std::floor((P[3 * p + 1] - oy) / h), k = (int)std::floor((P[3 * p + 2] - oz) / h);
		if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz || solid[cid(i, j, k)]) n++;
	}
	return n;
}

// independent of the voxels: ray parity (+x, skewed) against the triangles, Moller-Trumbore
int KineFluidNative::particles_in_mesh(const PackedVector3Array &vs, const PackedInt32Array &tr) const {
	int N = particle_count(), nt3 = tr.size() / 3;
	std::vector<double> tv(9 * nt3);
	for (int t = 0; t < nt3; t++)
		for (int c = 0; c < 3; c++) { Vector3 v = vs[tr[3 * t + c]]; tv[9 * t + 3 * c] = v.x; tv[9 * t + 3 * c + 1] = v.y; tv[9 * t + 3 * c + 2] = v.z; }
	int nth = std::max(1, nt);
	std::vector<int> hit(nth, 0);
	int chunk = std::max(1, (N + nth - 1) / nth);
	const double D[3] = { 1.0, 0.0123, 0.0071 };
	pfor(nth, nth, [&](int t0, int t1) {
		for (int th = t0; th < t1; th++) {
			int cntp = 0;
			for (int p = th * chunk; p < std::min(N, (th + 1) * chunk); p++) {
				const double *o = &P[3 * p];
				int cross = 0;
				for (int t = 0; t < nt3; t++) {
					const double *a = &tv[9 * t];
					double e1[3] = { a[3] - a[0], a[4] - a[1], a[5] - a[2] }, e2[3] = { a[6] - a[0], a[7] - a[1], a[8] - a[2] };
					double pv[3] = { D[1] * e2[2] - D[2] * e2[1], D[2] * e2[0] - D[0] * e2[2], D[0] * e2[1] - D[1] * e2[0] };
					double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
					if (std::fabs(det) < 1e-18) continue;
					double inv = 1.0 / det;
					double tt[3] = { o[0] - a[0], o[1] - a[1], o[2] - a[2] };
					double u = (tt[0] * pv[0] + tt[1] * pv[1] + tt[2] * pv[2]) * inv;
					if (u < 0 || u > 1) continue;
					double q[3] = { tt[1] * e1[2] - tt[2] * e1[1], tt[2] * e1[0] - tt[0] * e1[2], tt[0] * e1[1] - tt[1] * e1[0] };
					double v = (D[0] * q[0] + D[1] * q[1] + D[2] * q[2]) * inv;
					if (v < 0 || u + v > 1) continue;
					double s = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) * inv;
					if (s > 0) cross++;
				}
				if (cross & 1) cntp++;
			}
			hit[th] = cntp;
		}
	});
	int n = 0;
	for (int v : hit) n += v;
	return n;
}

double KineFluidNative::volume_ratio() const {
	int N = particle_count();
	if (N == 0) return 1.0;
	std::vector<int32_t> c2(cnt.size(), 0);
	for (int p = 0; p < N; p++) {
		int i = (int)std::floor((P[3 * p] - ox) / h), j = (int)std::floor((P[3 * p + 1] - oy) / h), k = (int)std::floor((P[3 * p + 2] - oz) / h);
		if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) continue;
		c2[cid(i, j, k)]++;
	}
	double s = 0;
	for (int32_t c : c2) s += std::min(c, ppc);
	return s / N;
}

// smoothed particle density field (quadratic kernel at cell centres), blurred, then marching tetrahedra at `iso` (fraction of rest density)
Dictionary KineFluidNative::surface(int smooth, double iso) {
	size_t nc = (size_t)nx * ny * nz;
	std::vector<double> F(nc, 0.0), T2(nc, 0.0);
	int N = particle_count();
	for (int p = 0; p < N; p++) {
		int bx, by, bz;
		double fx, fy, fz, wx[3], wy[3], wz[3];
		w3((P[3 * p] - ox) / h - 0.5, bx, fx, wx);
		w3((P[3 * p + 1] - oy) / h - 0.5, by, fy, wy);
		w3((P[3 * p + 2] - oz) / h - 0.5, bz, fz, wz);
		for (int kk = 0; kk < 3; kk++)
			for (int jj = 0; jj < 3; jj++)
				for (int ii = 0; ii < 3; ii++) {
					int i = bx + ii, j = by + jj, k = bz + kk;
					if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) continue;
					F[cid(i, j, k)] += wx[ii] * wy[jj] * wz[kk] / ppc;
				}
	}
	for (int s = 0; s < smooth; s++) {
		for (int ax = 0; ax < 3; ax++) {
			int st = ax == 0 ? 1 : (ax == 1 ? nx : nx * ny);
			int dm = ax == 0 ? nx : (ax == 1 ? ny : nz);
			for (int k = 0; k < nz; k++)
				for (int j = 0; j < ny; j++)
					for (int i = 0; i < nx; i++) {
						int c = cid(i, j, k);
						int q = ax == 0 ? i : (ax == 1 ? j : k);
						double a = q > 0 ? F[c - st] : F[c], b = q < dm - 1 ? F[c + st] : F[c];
						T2[c] = 0.25 * a + 0.5 * F[c] + 0.25 * b;
					}
			F.swap(T2);
		}
	}
	auto val = [&](int i, int j, int k) {
		i = std::clamp(i, 0, nx - 1); j = std::clamp(j, 0, ny - 1); k = std::clamp(k, 0, nz - 1);
		return F[cid(i, j, k)];
	};
	auto grad = [&](double gx, double gy, double gz) {
		int i = (int)std::floor(gx), j = (int)std::floor(gy), k = (int)std::floor(gz);
		double g[3] = { 0, 0, 0 };
		for (int dk = 0; dk < 2; dk++)
			for (int dj = 0; dj < 2; dj++)
				for (int di = 0; di < 2; di++) {
					double wgt = (di ? gx - i : 1 - (gx - i)) * (dj ? gy - j : 1 - (gy - j)) * (dk ? gz - k : 1 - (gz - k));
					int ii = i + di, jj = j + dj, kk = k + dk;
					g[0] += wgt * 0.5 * (val(ii + 1, jj, kk) - val(ii - 1, jj, kk));
					g[1] += wgt * 0.5 * (val(ii, jj + 1, kk) - val(ii, jj - 1, kk));
					g[2] += wgt * 0.5 * (val(ii, jj, kk + 1) - val(ii, jj, kk - 1));
				}
		return Vector3((real_t)g[0], (real_t)g[1], (real_t)g[2]);
	};
	static const int cv[8][3] = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } };
	static const int tets[6][4] = { { 0, 5, 1, 6 }, { 0, 1, 2, 6 }, { 0, 2, 3, 6 }, { 0, 3, 7, 6 }, { 0, 7, 4, 6 }, { 0, 4, 5, 6 } };
	PackedVector3Array verts, norms;
	auto emit = [&](Vector3 a, Vector3 b, Vector3 c) {
		Vector3 n = (b - a).cross(c - a);
		Vector3 cen = (a + b + c) / 3.0;
		Vector3 gr = grad(cen.x, cen.y, cen.z);
		if (n.dot(-gr) < 0) std::swap(b, c);
		Vector3 pp[3] = { a, b, c };
		for (int q = 0; q < 3; q++) {
			Vector3 nn = -grad(pp[q].x, pp[q].y, pp[q].z);
			if (nn.length_squared() > 1e-20) nn = nn.normalized(); else nn = Vector3(0, 1, 0);
			norms.push_back(nn);
			verts.push_back(Vector3((real_t)(ox + (pp[q].x + 0.5) * h), (real_t)(oy + (pp[q].y + 0.5) * h), (real_t)(oz + (pp[q].z + 0.5) * h)));
		}
	};
	for (int k = 1; k < nz - 2; k++)
		for (int j = 1; j < ny - 2; j++)
			for (int i = 1; i < nx - 2; i++) {
				double fv[8];
				bool any_in = false, any_out = false;
				for (int c = 0; c < 8; c++) {
					fv[c] = F[cid(i + cv[c][0], j + cv[c][1], k + cv[c][2])];
					if (fv[c] >= iso) any_in = true; else any_out = true;
				}
				if (!(any_in && any_out)) continue;
				for (int t = 0; t < 6; t++) {
					int in[4], out[4], ni = 0, no = 0;
					for (int q = 0; q < 4; q++) { int c = tets[t][q]; if (fv[c] >= iso) in[ni++] = c; else out[no++] = c; }
					auto cut = [&](int a, int b) {
						double t0 = (iso - fv[a]) / (fv[b] - fv[a]);
						return Vector3((real_t)(i + cv[a][0] + t0 * (cv[b][0] - cv[a][0])), (real_t)(j + cv[a][1] + t0 * (cv[b][1] - cv[a][1])), (real_t)(k + cv[a][2] + t0 * (cv[b][2] - cv[a][2])));
					};
					if (ni == 1) emit(cut(in[0], out[0]), cut(in[0], out[1]), cut(in[0], out[2]));
					else if (ni == 3) emit(cut(out[0], in[0]), cut(out[0], in[1]), cut(out[0], in[2]));
					else if (ni == 2) {
						Vector3 a = cut(in[0], out[0]), b = cut(in[0], out[1]), c = cut(in[1], out[1]), d = cut(in[1], out[0]);
						emit(a, b, c);
						emit(a, c, d);
					}
				}
			}
	Dictionary d;
	d["verts"] = verts;
	d["normals"] = norms;
	return d;
}
