#include "kine_fluid_native.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <thread>
#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>

using namespace godot;

namespace {

typedef std::chrono::steady_clock Clk;
inline double ms_since(Clk::time_point t) { return std::chrono::duration<double, std::milli>(Clk::now() - t).count(); }

// A persistent pool: the conjugate-gradient loops run for tens of microseconds each, so spawning std::threads per call (the first version) cost more
// than the work. Workers spin briefly for the next job, then sleep on a condition variable.
struct Pool {
	std::vector<std::thread> th;
	std::atomic<uint64_t> gen{ 0 };
	std::atomic<int> pending{ 0 };
	std::atomic<bool> stop{ false };
	std::atomic<int> sleepers{ 0 };
	const std::function<void(int)> *job = nullptr;
	int active = 0;
	std::mutex m, run_m;
	std::condition_variable cv;
	void worker(int tid) {
		uint64_t seen = 0;
		while (true) {
			int spins = 0;
			while (gen.load(std::memory_order_acquire) == seen && !stop.load()) {
				if (++spins < 4000) continue;
				if (spins < 6000) { std::this_thread::yield(); continue; }
				std::unique_lock<std::mutex> lk(m);
				sleepers++;
				cv.wait_for(lk, std::chrono::milliseconds(2), [&] { return gen.load() != seen || stop.load(); });
				sleepers--;
				spins = 4000;
			}
			if (stop.load()) return;
			seen = gen.load(std::memory_order_acquire);
			if (tid < active) (*job)(tid);
			pending.fetch_sub(1, std::memory_order_acq_rel); // every worker reports every generation: run() is a full barrier, so none can lag a generation
		}
	}
	void ensure(int n) {
		while ((int)th.size() < n - 1) {
			int tid = (int)th.size() + 1;
			th.emplace_back([this, tid] { worker(tid); });
		}
	}
	void run(int n, const std::function<void(int)> &f) {
		std::lock_guard<std::mutex> g(run_m);
		ensure(n);
		job = &f;
		active = n;
		pending.store((int)th.size());
		gen.fetch_add(1, std::memory_order_release);
		if (sleepers.load() > 0) { std::lock_guard<std::mutex> lk(m); cv.notify_all(); }
		f(0);
		for (int spins = 0; pending.load(std::memory_order_acquire) > 0; spins++) if (spins > 2000) std::this_thread::yield(); // a preempted worker (other jobs on the box) must not make this spin for a whole time slice
	}
	~Pool() {
		stop = true;
		{ std::lock_guard<std::mutex> lk(m); cv.notify_all(); }
		for (auto &t : th) if (t.joinable()) t.detach(); // process exit: the workers see stop and return
	}
};
Pool &pool() { static Pool *p = new Pool(); return *p; } // leaked on purpose: no join at DLL unload

template <class F>
void pfor(int n, int nt, F f) { // f(begin, end), nt chunks of ceil(n/nt) run on the pool
	if (nt <= 1 || n < 2) {
		f(0, n);
		return;
	}
	int chunk = (n + nt - 1) / nt;
	int used = (n + chunk - 1) / chunk;
	if (used <= 1) { f(0, n); return; }
	pool().run(used, [&](int t) {
		int b = t * chunk, e = std::min(n, b + chunk);
		if (b < e) f(b, e);
	});
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
	ClassDB::bind_method(D_METHOD("volume_smooth"), &KineFluidNative::volume_smooth);
	ClassDB::bind_method(D_METHOD("surface", "smooth", "iso"), &KineFluidNative::surface);
	ClassDB::bind_method(D_METHOD("clear_particles"), &KineFluidNative::clear_particles);
	ClassDB::bind_method(D_METHOD("remove_every", "k"), &KineFluidNative::remove_every);
	ClassDB::bind_method(D_METHOD("set_wall_friction", "f"), &KineFluidNative::set_wall_friction);
	ClassDB::bind_method(D_METHOD("set_density_mode", "mode"), &KineFluidNative::set_density_mode);
	ClassDB::bind_method(D_METHOD("set_surface_taubin", "on"), &KineFluidNative::set_surface_taubin);
	ClassDB::bind_method(D_METHOD("set_extrapolation", "on"), &KineFluidNative::set_extrapolation);
	ClassDB::bind_method(D_METHOD("surface_aniso", "iso", "ndiv"), &KineFluidNative::surface_aniso);
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
	pr.assign(nc, 0); rhs = pr; rr = pr; zz = pr; ss = pr; qq = pr; pre = pr; adiag = pr; dq = pr; db = pr; pre_ok = false;
	P.clear(); V.clear(); C.clear();
}

void KineFluidNative::set_params(double p_g, double p_drift, double p_cfl, double p_dtmax, int p_iters, double p_tol) {
	grav = p_g; drift = p_drift; cfl = p_cfl; dtmax = p_dtmax; max_iter = p_iters; tol = p_tol;
}

void KineFluidNative::clear_particles() { P.clear(); V.clear(); C.clear(); }

// removes every k-th particle (index % k == k - 1); a planted-control helper for the volume bar (returns the number removed)
int KineFluidNative::remove_every(int k) {
	if (k < 1) return 0;
	int N = particle_count(), w = 0;
	for (int p = 0; p < N; p++) {
		if (p % k == k - 1) continue;
		for (int a = 0; a < 3; a++) { P[3 * w + a] = P[3 * p + a]; V[3 * w + a] = V[3 * p + a]; }
		for (int a = 0; a < 9; a++) C[9 * w + a] = C[9 * p + a];
		w++;
	}
	P.resize(3 * (size_t)w); V.resize(3 * (size_t)w); C.resize(9 * (size_t)w);
	return N - w;
}

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
	pre_ok = false;
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
	if (nte <= 1) {
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
			pfor((int)slabs.size(), nte, [&](int b, int e) {
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

// The solve is split in T tasks that each own a contiguous run of the ascending fluid-cell list (T = 1 for small systems and for threads = 1,
// which is then exactly the serial MIC(0) PCG of Bridson's notes). The incomplete-Cholesky factor is built per task: the coupling between two
// tasks is dropped in the PRECONDITIONER only (block-Jacobi / additive-Schwarz with MIC(0) sub-solves, which stays symmetric positive definite,
// so it is a valid CG preconditioner); the matrix-vector product is the full operator. All work is on the persistent pool.
int KineFluidNative::solve_tasks() const { return (nte > 1 && (int)fl.size() >= 4096) ? nte : 1; }

void KineFluidNative::build_precond() {
	int n = (int)fl.size();
	pre_ok = true;
	if (n == 0) return;
	const int sx = 1, sy = nx, sz = nx * ny;
	int T = solve_tasks();
	int chunk = (n + T - 1) / T;
	blo.assign(T, 0);
	bhi.assign(T, -1);
	for (int t = 0; t < T; t++) {
		int q0 = t * chunk, q1 = std::min(n, q0 + chunk);
		if (q0 < q1) { blo[t] = fl[q0]; bhi[t] = fl[q1 - 1]; }
	}
	auto task = [&](int t) {
		int q0 = t * chunk, q1 = std::min(n, q0 + chunk);
		if (q0 >= q1) return;
		const int lo = blo[t], hi = bhi[t];
		auto inb = [&](int c) { return c >= lo && c <= hi && type[c] == 1; };
		auto ap = [&](int c, int off) { return (inb(c) && inb(c + off)) ? -1.0 : 0.0; };
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			double d = 0;
			for (int off : { -sx, sx, -sy, sy, -sz, sz }) if (type[c + off] != 2) d += 1;
			adiag[c] = d;
		}
		const double tau = 0.97, sigma = 0.25;
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			double e = adiag[c];
			if (inb(c - sx)) {
				int m = c - sx; double p = pre[m];
				e -= (ap(m, sx) * p) * (ap(m, sx) * p) + tau * (ap(m, sx) * (ap(m, sy) + ap(m, sz)) * p * p);
			}
			if (inb(c - sy)) {
				int m = c - sy; double p = pre[m];
				e -= (ap(m, sy) * p) * (ap(m, sy) * p) + tau * (ap(m, sy) * (ap(m, sx) + ap(m, sz)) * p * p);
			}
			if (inb(c - sz)) {
				int m = c - sz; double p = pre[m];
				e -= (ap(m, sz) * p) * (ap(m, sz) * p) + tau * (ap(m, sz) * (ap(m, sx) + ap(m, sy)) * p * p);
			}
			if (e < sigma * adiag[c]) e = adiag[c];
			pre[c] = 1.0 / std::sqrt(e);
		}
	};
	if (T <= 1) task(0); else pool().run(T, [&](int t) { task(t); });
	// diagonal entries of the matrix are needed by every task before the matvec: they were written above (each task wrote its own cells)
}

// z = M^-1 r for the block factor; part[t] receives sum over the task of z*r (the next CG dot) when part != nullptr
void KineFluidNative::precond_apply(const std::vector<double> &r, std::vector<double> &z, std::vector<double> *part) {
	int n = (int)fl.size();
	const int sx = 1, sy = nx, sz = nx * ny;
	int T = (int)blo.size();
	int chunk = (n + T - 1) / T;
	auto task = [&](int t) {
		int q0 = t * chunk, q1 = std::min(n, q0 + chunk);
		if (q0 >= q1) { if (part) (*part)[t] = 0; return; }
		const int lo = blo[t], hi = bhi[t];
		auto inb = [&](int c) { return c >= lo && c <= hi && type[c] == 1; };
		auto ap = [&](int c, int off) { return (inb(c) && inb(c + off)) ? -1.0 : 0.0; };
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			double tt = r[c];
			if (inb(c - sx)) tt -= ap(c - sx, sx) * pre[c - sx] * qq[c - sx];
			if (inb(c - sy)) tt -= ap(c - sy, sy) * pre[c - sy] * qq[c - sy];
			if (inb(c - sz)) tt -= ap(c - sz, sz) * pre[c - sz] * qq[c - sz];
			qq[c] = tt * pre[c];
		}
		for (int q = q1 - 1; q >= q0; q--) {
			int c = fl[q];
			double tt = qq[c];
			if (inb(c + sx)) tt -= ap(c, sx) * pre[c] * z[c + sx];
			if (inb(c + sy)) tt -= ap(c, sy) * pre[c] * z[c + sy];
			if (inb(c + sz)) tt -= ap(c, sz) * pre[c] * z[c + sz];
			z[c] = tt * pre[c];
		}
		if (part) { double sacc = 0; for (int q = q0; q < q1; q++) sacc += z[fl[q]] * r[fl[q]]; (*part)[t] = sacc; }
	};
	if (T <= 1) task(0); else pool().run(T, [&](int t) { task(t); });
}

// solves A x = b on the fluid cells (A = the 7-point Laplacian with p = 0 in air and no flux through solids: Bridson's pressure matrix),
// to max-norm residual tl * max|b|, at most maxit iterations. warm = start from x (already zero outside the fluid), else from 0.
void KineFluidNative::pcg(std::vector<double> &x, const std::vector<double> &b, double tl, int maxit, bool warm) {
	int n = (int)fl.size();
	last_iters = 0;
	if (n == 0) return;
	if (!pre_ok) build_precond();
	const int sx = 1, sy = nx, sz = nx * ny;
	int T = (int)blo.size();
	int chunk = (n + T - 1) / T;
	std::vector<double> part(T, 0.0);
	auto par = [&](auto &&f) {
		if (T <= 1) f(0, 0, n);
		else pool().run(T, [&](int t) { int q0 = t * chunk, q1 = std::min(n, q0 + chunk); if (q0 < q1) f(t, q0, q1); });
	};
	auto reduce_sum = [&]() { double s = 0; for (double v : part) s += v; return s; };
	auto reduce_max = [&]() { double s = 0; for (double v : part) s = std::max(s, v); return s; };
	auto isf = [&](int c) { return type[c] == 1; };
	std::fill(part.begin(), part.end(), 0.0);
	par([&](int t, int q0, int q1) { double m = 0; for (int q = q0; q < q1; q++) m = std::max(m, std::fabs(b[fl[q]])); part[t] = m; });
	double bmax = reduce_max();
	last_res = bmax;
	if (bmax == 0) { for (int q = 0; q < n; q++) x[fl[q]] = 0; return; }
	if (!warm) par([&](int, int q0, int q1) { for (int q = q0; q < q1; q++) x[fl[q]] = 0.0; });
	// r = b - A x
	std::fill(part.begin(), part.end(), 0.0);
	par([&](int t, int q0, int q1) {
		double m = 0;
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			double tt = adiag[c] * x[c];
			if (isf(c - sx)) tt -= x[c - sx];
			if (isf(c + sx)) tt -= x[c + sx];
			if (isf(c - sy)) tt -= x[c - sy];
			if (isf(c + sy)) tt -= x[c + sy];
			if (isf(c - sz)) tt -= x[c - sz];
			if (isf(c + sz)) tt -= x[c + sz];
			rr[c] = b[c] - tt;
			m = std::max(m, std::fabs(rr[c]));
		}
		part[t] = m;
	});
	double r0 = reduce_max();
	if (r0 < tl * bmax) return;
	precond_apply(rr, zz, &part);
	double sig = reduce_sum();
	par([&](int, int q0, int q1) { for (int q = q0; q < q1; q++) ss[fl[q]] = zz[fl[q]]; });
	for (int it = 0; it < maxit; it++) {
		par([&](int t, int q0, int q1) {
			double dsum = 0;
			for (int q = q0; q < q1; q++) {
				int c = fl[q];
				double tt = adiag[c] * ss[c];
				if (isf(c - sx)) tt -= ss[c - sx];
				if (isf(c + sx)) tt -= ss[c + sx];
				if (isf(c - sy)) tt -= ss[c - sy];
				if (isf(c + sy)) tt -= ss[c + sy];
				if (isf(c - sz)) tt -= ss[c - sz];
				if (isf(c + sz)) tt -= ss[c + sz];
				zz[c] = tt;
				dsum += ss[c] * tt;
			}
			part[t] = dsum;
		});
		double den = reduce_sum();
		if (den == 0) break;
		double al = sig / den;
		par([&](int t, int q0, int q1) {
			double m = 0;
			for (int q = q0; q < q1; q++) { int c = fl[q]; x[c] += al * ss[c]; rr[c] -= al * zz[c]; m = std::max(m, std::fabs(rr[c])); }
			part[t] = m;
		});
		double rmax = reduce_max();
		last_iters = it + 1;
		last_res = rmax;
		if (rmax < tl * bmax) break;
		precond_apply(rr, zz, &part);
		double sig2 = reduce_sum();
		double be = sig2 / sig;
		sig = sig2;
		par([&](int, int q0, int q1) { for (int q = q0; q < q1; q++) { int c = fl[q]; ss[c] = zz[c] + be * ss[c]; } });
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

// Velocity extrapolation into the air (Bridson, Fluid Simulation for Computer Graphics, 2nd ed., sec. on extrapolating velocity): the pressure update only
// reaches faces next to a fluid cell, so a free-surface particle interpolating the grid (the B-spline reaches 1.5 cells) read zeros from the air faces and
// was slowed and given a wrong affine matrix. Two layers of faces beyond the fluid get the mean of their already-valid face neighbours (valid = touching
// a fluid cell, or filled by the previous layer). Faces on solid walls and the domain boundary stay as they are (normal velocity 0).
void KineFluidNative::extrapolate() {
	for (int c = 0; c < 3; c++) {
		std::vector<double> &g = c == 0 ? U : (c == 1 ? Vg : W);
		int d[3] = { nx, ny, nz };
		d[c] += 1;
		const int st[3] = { 1, d[0], d[0] * d[1] };
		const int cs[3] = { 1, nx, nx * ny };
		size_t tot = g.size();
		std::vector<uint8_t> &vf = vflag[c];
		std::vector<uint8_t> &nf = vflag2[c];
		vf.assign(tot, 0);
		nf.assign(tot, 0);
		pfor(d[2], nte, [&](int k0, int k1) {
			for (int k = k0; k < k1; k++)
				for (int j = 0; j < d[1]; j++)
					for (int i = 0; i < d[0]; i++) {
						size_t f = (size_t)i + (size_t)d[0] * ((size_t)j + (size_t)d[1] * k);
						int ij[3] = { i, j, k };
						bool bnd = ij[c] == 0 || ij[c] == d[c] - 1;
						if (bnd) { vf[f] = 2; continue; } // fixed: the domain wall
						int b = i + nx * (j + ny * k); // cell on the + side of the face along c; the - side is b - cs[c]
						int a = b - cs[c];
						// fixed: a face with solid on exactly one side carries the wall's normal velocity (0). A face with solid on BOTH sides lies inside
						// the wall: it is extrapolated like air, so a particle next to a wall interpolates its own tangential velocity there (free slip).
						// Leaving those faces at 0 made the B-spline read zeros 1 cell into every wall: a numerical no-slip that held a sheet of particles
						// on the tank's front and back walls at about 0.14 m/s in free fall (CH8b, 11-04).
						if ((type[a] == 2) != (type[b] == 2)) vf[f] = 2;
						else if (type[a] == 1 || type[b] == 1) vf[f] = 1;
					}
		});
		for (int layer = 0; layer < 2; layer++) {
			pfor(d[2], nte, [&](int k0, int k1) {
				for (int k = k0; k < k1; k++)
					for (int j = 0; j < d[1]; j++)
						for (int i = 0; i < d[0]; i++) {
							size_t f = (size_t)i + (size_t)d[0] * ((size_t)j + (size_t)d[1] * k);
							if (vf[f] != 0) continue;
							double sum = 0;
							int n = 0;
							if (i > 0 && vf[f - st[0]] == 1) { sum += g[f - st[0]]; n++; }
							if (i < d[0] - 1 && vf[f + st[0]] == 1) { sum += g[f + st[0]]; n++; }
							if (j > 0 && vf[f - st[1]] == 1) { sum += g[f - st[1]]; n++; }
							if (j < d[1] - 1 && vf[f + st[1]] == 1) { sum += g[f + st[1]]; n++; }
							if (k > 0 && vf[f - st[2]] == 1) { sum += g[f - st[2]]; n++; }
							if (k < d[2] - 1 && vf[f + st[2]] == 1) { sum += g[f + st[2]]; n++; }
							if (n > 0) { g[f] = sum / n; nf[f] = 1; }
						}
			});
			for (size_t f = 0; f < tot; f++) if (nf[f]) { vf[f] = 1; nf[f] = 0; }
		}
	}
}

void KineFluidNative::project(double dt) {
	const size_t NV = Vg.size();
	pfor((int)NV, nte, [&](int b0, int e0) { for (int n = b0; n < e0; n++) Vg[n] -= grav * dt; });
	apply_wall_friction();
	pfor(nz, nte, [&](int k0, int k1) {
		for (int k = k0; k < k1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i <= nx; i++) {
					bool s = (i == 0 || i == nx) || solid[cid(i - 1, j, k)] || solid[cid(i, j, k)];
					if (s) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] = 0;
				}
		for (int k = k0; k < k1; k++)
			for (int j = 0; j <= ny; j++)
				for (int i = 0; i < nx; i++) {
					bool s = (j == 0 || j == ny) || solid[cid(i, j - 1, k)] || solid[cid(i, j, k)];
					if (s) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] = 0;
				}
	});
	pfor(nz + 1, nte, [&](int k0, int k1) {
		for (int k = k0; k < k1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					bool s = (k == 0 || k == nz) || solid[cid(i, j, k - 1)] || solid[cid(i, j, k)];
					if (s) W[i + (size_t)nx * (j + (size_t)ny * k)] = 0;
				}
	});
	pfor((int)pr.size(), nte, [&](int b0, int e0) { for (int c = b0; c < e0; c++) if (type[c] != 1) pr[c] = 0.0; });
	double sc = h / dt;
	const bool legacy = dmode == 0;
	pfor((int)fl.size(), solve_tasks(), [&](int q0, int q1) {
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			int i = c % nx, j = (c / nx) % ny, k = c / (nx * ny);
			double div = U[(i + 1) + (size_t)(nx + 1) * (j + (size_t)ny * k)] - U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)]
					+ Vg[i + (size_t)nx * ((j + 1) + (size_t)(ny + 1) * k)] - Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)]
					+ W[i + (size_t)nx * (j + (size_t)ny * (k + 1))] - W[i + (size_t)nx * (j + (size_t)ny * k)];
			double eps = 0.0;
			if (legacy) { // the first-version density drift: a pressure source in the velocity solve (dmode 0). dmode 1 does it on positions instead (density_project)
				eps = std::min(1.0, std::max(0.0, (double)cnt[c] / ppc - 1.0));
				// voids: an under-dense cell whose six neighbours are all fluid is pulled back toward rest density (pressure source < 0). Free-surface cells are left alone.
				if (eps == 0.0 && cnt[c] < ppc && type[c - 1] == 1 && type[c + 1] == 1 && type[c - nx] == 1 && type[c + nx] == 1 && type[c - nx * ny] == 1 && type[c + nx * ny] == 1)
					eps = std::max(-0.5, (double)cnt[c] / ppc - 1.0);
			}
			rhs[c] = -sc * div + sc * (h / std::max(dt, dtmax)) * drift * eps;
		}
	});
	if (!pre_ok) build_precond();
	pcg(pr, rhs, tol, max_iter, true);
	double f = dt / h;
	pfor(nz, nte, [&](int k0, int k1) {
		for (int k = k0; k < k1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 1; i < nx; i++) {
					int a = cid(i - 1, j, k), b = cid(i, j, k);
					if (type[a] == 2 || type[b] == 2) continue;
					if (type[a] == 1 || type[b] == 1) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] -= f * (pr[b] - pr[a]);
				}
		for (int k = k0; k < k1; k++)
			for (int j = 1; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j - 1, k), b = cid(i, j, k);
					if (type[a] == 2 || type[b] == 2) continue;
					if (type[a] == 1 || type[b] == 1) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] -= f * (pr[b] - pr[a]);
				}
	});
	pfor(nz - 1, nte, [&](int k0, int k1) {
		for (int k = k0 + 1; k < k1 + 1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j, k - 1), b = cid(i, j, k);
					if (type[a] == 2 || type[b] == 2) continue;
					if (type[a] == 1 || type[b] == 1) W[i + (size_t)nx * (j + (size_t)ny * k)] -= f * (pr[b] - pr[a]);
				}
	});
	if (extrap) extrapolate();
}

// Density correction on POSITIONS, not on velocity (dmode 1). After Kugelstadt et al., "Implicit Density Projection for Volume Conserving Liquids",
// IEEE TVCG 2019, and the particle-shifting idea of Xu, Stansby, Laurence, J. Comput. Phys. 228 (2009) 6703 and Lind et al., J. Comput. Phys. 231 (2012)
// 1499. A cell that holds more particles than the rest density asks for its volume to grow by the excess (a cell short of particles, with all six
// neighbours fluid, asks to shrink): the displacement field d is the gradient of q, with  A q = h * excess  (the same Poisson matrix as the pressure,
// q = 0 in air, no flux through solids), so the divergence of d in every fluid cell equals the strain asked for. Each particle moves by the B-spline
// interpolated d; velocities are untouched, so the correction injects no kinetic energy. There is no tuned coefficient: the full strain is asked for.
void KineFluidNative::density_project() {
	auto t0 = Clk::now();
	int n = (int)fl.size();
	idp_iters_last = 0;
	if (n == 0) return;
	const int sx = 1, sy = nx, sz = nx * ny;
	pfor(n, solve_tasks(), [&](int q0, int q1) {
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			double ex = 0.0;
			if (cnt[c] > ppc) ex = (double)cnt[c] / ppc - 1.0;
			else if (cnt[c] < ppc && type[c - sx] == 1 && type[c + sx] == 1 && type[c - sy] == 1 && type[c + sy] == 1 && type[c - sz] == 1 && type[c + sz] == 1)
				ex = std::max(-0.5, (double)cnt[c] / ppc - 1.0);
			db[c] = h * ex;
		}
	});
	pfor((int)dq.size(), nte, [&](int b0, int e0) { for (int c = b0; c < e0; c++) if (type[c] != 1) dq[c] = 0.0; }); // air and solid: q = 0
	if (!pre_ok) build_precond();
	int saved = last_iters;
	double saved_res = last_res;
	pcg(dq, db, idp_tol, idp_max, false);
	idp_iters_last = last_iters;
	last_iters = saved;
	last_res = saved_res;
	// face displacements into U, Vg, W (the grid velocities are rebuilt by p2g right after, so they are free here)
	std::fill(U.begin(), U.end(), 0.0);
	std::fill(Vg.begin(), Vg.end(), 0.0);
	std::fill(W.begin(), W.end(), 0.0);
	pfor(nz, nte, [&](int k0, int k1) {
		for (int k = k0; k < k1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 1; i < nx; i++) {
					int a = cid(i - 1, j, k), b = cid(i, j, k);
					if (type[a] == 2 || type[b] == 2) continue;
					if (type[a] == 1 || type[b] == 1) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] = -(dq[b] - dq[a]);
				}
		for (int k = k0; k < k1; k++)
			for (int j = 1; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j - 1, k), b = cid(i, j, k);
					if (type[a] == 2 || type[b] == 2) continue;
					if (type[a] == 1 || type[b] == 1) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] = -(dq[b] - dq[a]);
				}
	});
	pfor(nz - 1, nte, [&](int k0, int k1) {
		for (int k = k0 + 1; k < k1 + 1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j, k - 1), b = cid(i, j, k);
					if (type[a] == 2 || type[b] == 2) continue;
					if (type[a] == 1 || type[b] == 1) W[i + (size_t)nx * (j + (size_t)ny * k)] = -(dq[b] - dq[a]);
				}
	});
	int N = particle_count();
	pfor(N, nte, [&](int b0, int e0) {
		for (int p = b0; p < e0; p++) {
			double *x = &P[3 * p];
			double dsp[3];
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
				double vs = 0;
				for (int kk = 0; kk < 3; kk++) {
					int nk = bz + kk;
					if (nk < 0 || nk >= dim[2]) continue;
					for (int jj = 0; jj < 3; jj++) {
						int nj = by + jj;
						if (nj < 0 || nj >= dim[1]) continue;
						for (int ii = 0; ii < 3; ii++) {
							int ni = bx + ii;
							if (ni < 0 || ni >= dim[0]) continue;
							vs += wx[ii] * wy[jj] * wz[kk] * g[ni + (size_t)dim[0] * (nj + (size_t)dim[1] * nk)];
						}
					}
				}
				dsp[c] = vs;
			}
			double org[3] = { ox, oy, oz };
			int dimc[3] = { nx, ny, nz };
			for (int a = 0; a < 3; a++) {
				double m = 0.5 * h; // a particle never moves more than half a cell in one correction
				double dd = std::max(-m, std::min(m, dsp[a]));
				double nxp[3] = { x[0], x[1], x[2] };
				nxp[a] += dd;
				int cc[3];
				for (int q = 0; q < 3; q++) cc[q] = (int)std::floor((nxp[q] - org[q]) / h);
				bool bad = false;
				for (int q = 0; q < 3; q++) if (cc[q] < 0 || cc[q] >= dimc[q]) bad = true;
				if (!bad && solid[cid(cc[0], cc[1], cc[2])]) bad = true;
				if (!bad) x[a] = nxp[a];
			}
		}
	});
	tm_idp = ms_since(t0);
}

void KineFluidNative::g2p() {
	int N = particle_count();
	double k4 = 4.0 / (h * h);
	pfor(N, nte, [&](int b0, int e0) {
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
	std::vector<double> vm(nte, 0.0);
	int chunk = std::max(1, (N + nte - 1) / nte);
	pfor(nte, nte, [&](int t0, int t1) {
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
	// threads only pay on a big grid or many particles: the pool barriers cost more than a small loop (and much more when the machine is shared)
	nte = (nt > 1 && ((size_t)nx * ny * nz >= 40000 || particle_count() >= 16384)) ? nt : 1;
	mark_cells();
	if (dmode == 1) {
		density_project();
		mark_cells();   // the particles moved: the cell classes follow
	}
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
	d["idp_iters"] = idp_iters_last; d["ms_idp"] = tm_idp;
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

// Translation-invariant volume: the particles' kernel density at the cell centres (quadratic B-spline, a partition of unity, so the sum of the field over all
// cells is exactly N / ppc), capped at the rest density 1. The lattice-phase of the particles against the cells does not enter, unlike volume_ratio() whose
// min(count, 8) reads a rigidly shifted lattice as a loss. Only a smoothed density above 1 (a real compression) loses volume here.
double KineFluidNative::volume_smooth() const {
	int N = particle_count();
	if (N == 0) return 1.0;
	size_t nc = (size_t)nx * ny * nz;
	std::vector<double> F(nc, 0.0);
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
	double s = 0;
	for (double v : F) s += std::min(v, 1.0);
	return s / ((double)N / ppc);
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

namespace {
// symmetric 3x3 eigen-decomposition by cyclic Jacobi: A (row major) -> eigenvalues e[3], eigenvectors as COLUMNS of V
void eig3(const double A_in[9], double e[3], double V[9]) {
	double A[9];
	for (int i = 0; i < 9; i++) A[i] = A_in[i];
	for (int i = 0; i < 9; i++) V[i] = (i % 4 == 0) ? 1.0 : 0.0;
	for (int sweep = 0; sweep < 24; sweep++) {
		double off = A[1] * A[1] + A[2] * A[2] + A[5] * A[5];
		if (off < 1e-30) break;
		static const int PQ[3][2] = { { 0, 1 }, { 0, 2 }, { 1, 2 } };
		for (int pq = 0; pq < 3; pq++) {
			int p = PQ[pq][0], q = PQ[pq][1];
			double apq = A[3 * p + q];
			if (std::fabs(apq) < 1e-300) continue;
			double th = (A[3 * q + q] - A[3 * p + p]) / (2.0 * apq);
			double t = (th >= 0 ? 1.0 : -1.0) / (std::fabs(th) + std::sqrt(th * th + 1.0));
			double c = 1.0 / std::sqrt(t * t + 1.0), sn = t * c;
			for (int k = 0; k < 3; k++) {
				double akp = A[3 * k + p], akq = A[3 * k + q];
				A[3 * k + p] = c * akp - sn * akq;
				A[3 * k + q] = sn * akp + c * akq;
			}
			for (int k = 0; k < 3; k++) {
				double apk = A[3 * p + k], aqk = A[3 * q + k];
				A[3 * p + k] = c * apk - sn * aqk;
				A[3 * q + k] = sn * apk + c * aqk;
			}
			for (int k = 0; k < 3; k++) {
				double vkp = V[3 * k + p], vkq = V[3 * k + q];
				V[3 * k + p] = c * vkp - sn * vkq;
				V[3 * k + q] = sn * vkp + c * vkq;
			}
		}
	}
	e[0] = A[0]; e[1] = A[4]; e[2] = A[8];
}
} // namespace

// Anisotropic-kernel surface (Yu & Turk, "Reconstructing surfaces of particle-based fluids using anisotropic kernels", ACM Trans. Graph. 32(1), 2013).
// Per particle: the weighted mean x_bar and covariance C of the neighbours within rc (weight 1 - (d/rc)^3), eigen-decomposed (Jacobi). With at least
// N_eps = 25 neighbours the kernel is an ellipsoid whose axes follow the eigenvectors, longest axis = the kernel radius, the others scaled by
// sqrt(sigma_k / sigma_1) with sigma_k >= sigma_1 / k_r (k_r = 4): stretched along the surface, thin across it. Fewer neighbours: a sphere (a droplet),
// sized so that one particle's volume gives a field peak of 1. The position is smoothed toward x_bar by lambda = 0.9. The field is the VOLUME FRACTION,
// sum_j V_p * K_j(x) with K_j integrating to 1, so the interior is 1, a flat surface is exactly 0.5, and iso = 0.5 needs no tuning.
// (N_eps, k_r, lambda are the paper's published values, written from memory; the paper was not available offline.) Field grid: h / ndiv.
Dictionary KineFluidNative::surface_aniso(double iso, int ndiv) {
	Dictionary out;
	int N = particle_count();
	PackedVector3Array verts, norms;
	out["verts"] = verts;
	out["normals"] = norms;
	if (N == 0) return out;
	sort_particles();
	const double Vp = h * h * h / ppc;
	const double rc = 1.5 * h;
	const double Rk = h; // kernel support radius in the bulk (two particle spacings)
	const double K_INT = 64.0 * 3.14159265358979323846 / 315.0; // integral of (1 - |u|^2)^3 over the unit ball
	const double lambda = 0.9, kr = 4.0;
	const int n_eps = 25;
	std::vector<double> xs(3 * (size_t)N), ax(3 * (size_t)N), ev(9 * (size_t)N);
	int reach = (int)std::ceil(rc / h);
	pfor(N, nte, [&](int b0, int e0) {
		for (int p = b0; p < e0; p++) {
			const double *xp = &P[3 * p];
			int ci = std::clamp((int)std::floor((xp[0] - ox) / h), 0, nx - 1), cj = std::clamp((int)std::floor((xp[1] - oy) / h), 0, ny - 1), ck = std::clamp((int)std::floor((xp[2] - oz) / h), 0, nz - 1);
			double sw = 0, m[3] = { 0, 0, 0 };
			int nn = 0;
			double Cm[9] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 };
			for (int pass = 0; pass < 2; pass++) {
				// pass 0: weighted mean; pass 1: weighted covariance about it
				for (int dk = -reach; dk <= reach; dk++)
					for (int dj = -reach; dj <= reach; dj++)
						for (int di = -reach; di <= reach; di++) {
							int i = ci + di, j = cj + dj, k = ck + dk;
							if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) continue;
							int c = cid(i, j, k);
							for (int a = cstart[c]; a < cstart[c + 1]; a++) {
								const double *xq = &P[3 * order[a]];
								double d0 = xq[0] - xp[0], d1 = xq[1] - xp[1], d2 = xq[2] - xp[2];
								double d = std::sqrt(d0 * d0 + d1 * d1 + d2 * d2);
								if (d >= rc) continue;
								double q = d / rc, w = 1.0 - q * q * q;
								if (pass == 0) { sw += w; m[0] += w * xq[0]; m[1] += w * xq[1]; m[2] += w * xq[2]; nn++; }
								else {
									double r0 = xq[0] - m[0], r1 = xq[1] - m[1], r2 = xq[2] - m[2];
									Cm[0] += w * r0 * r0; Cm[1] += w * r0 * r1; Cm[2] += w * r0 * r2;
									Cm[4] += w * r1 * r1; Cm[5] += w * r1 * r2; Cm[8] += w * r2 * r2;
								}
							}
						}
				if (pass == 0) { m[0] /= sw; m[1] /= sw; m[2] /= sw; }
			}
			double *a3 = &ax[3 * p], *V = &ev[9 * p];
			if (nn >= n_eps) {
				Cm[3] = Cm[1]; Cm[6] = Cm[2]; Cm[7] = Cm[5];
				for (int q = 0; q < 9; q++) Cm[q] /= sw;
				double e[3];
				eig3(Cm, e, V);
				double s1 = std::max(e[0], std::max(e[1], e[2]));
				for (int q = 0; q < 3; q++) {
					double sg = std::max(e[q], s1 / kr);
					a3[q] = Rk * std::sqrt(sg / s1);
				}
				for (int q = 0; q < 3; q++) xs[3 * p + q] = (1.0 - lambda) * xp[q] + lambda * m[q];
			} else {
				// a droplet: a sphere whose peak of V_p * K is 1
				double rad = std::cbrt(Vp / K_INT);
				for (int q = 0; q < 3; q++) { a3[q] = rad; xs[3 * p + q] = xp[q]; }
				for (int q = 0; q < 9; q++) V[q] = (q % 4 == 0) ? 1.0 : 0.0;
			}
		}
	});
	// Taubin's lambda|mu step (Taubin, "A signal processing approach to fair surface design", SIGGRAPH 1995): the lambda step above is a Laplacian
	// low-pass that also shrinks (a surface particle's neighbour mean lies inside the liquid). The second step applies the SAME operator (same
	// neighbours and weights, taken on the original positions) with mu < -lambda, 1/lambda + 1/mu = k_PB = 0.1 (Taubin's pass-band value), which
	// cancels the shrink to first order while keeping the smoothing of the high frequencies.
	if (sm_taubin) {
		const double kpb = 0.1, mu = 1.0 / (kpb - 1.0 / lambda);
		std::vector<double> xs2(xs);
		pfor(N, nte, [&](int b0, int e0) {
			for (int p = b0; p < e0; p++) {
				const double *xp = &P[3 * p];
				int ci = std::clamp((int)std::floor((xp[0] - ox) / h), 0, nx - 1), cj = std::clamp((int)std::floor((xp[1] - oy) / h), 0, ny - 1), ck = std::clamp((int)std::floor((xp[2] - oz) / h), 0, nz - 1);
				double sw = 0, m[3] = { 0, 0, 0 };
				int nn = 0;
				for (int dk = -reach; dk <= reach; dk++)
					for (int dj = -reach; dj <= reach; dj++)
						for (int di = -reach; di <= reach; di++) {
							int i = ci + di, j = cj + dj, k = ck + dk;
							if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) continue;
							int c = cid(i, j, k);
							for (int a = cstart[c]; a < cstart[c + 1]; a++) {
								int qi = order[a];
								const double *xq = &P[3 * qi];
								double d0 = xq[0] - xp[0], d1 = xq[1] - xp[1], d2 = xq[2] - xp[2];
								double dd = std::sqrt(d0 * d0 + d1 * d1 + d2 * d2);
								if (dd >= rc) continue;
								double q = dd / rc, w = 1.0 - q * q * q;
								sw += w; m[0] += w * xs[3 * qi]; m[1] += w * xs[3 * qi + 1]; m[2] += w * xs[3 * qi + 2]; nn++;
							}
						}
				if (nn < n_eps) continue;
				for (int q = 0; q < 3; q++) xs2[3 * p + q] = xs[3 * p + q] + mu * (m[q] / sw - xs[3 * p + q]);
			}
		});
		xs.swap(xs2);
	}
	// the field grid over the particles' box
	double lo[3] = { 1e30, 1e30, 1e30 }, hi[3] = { -1e30, -1e30, -1e30 };
	for (int p = 0; p < N; p++)
		for (int q = 0; q < 3; q++) { lo[q] = std::min(lo[q], xs[3 * p + q]); hi[q] = std::max(hi[q], xs[3 * p + q]); }
	const double d = h / std::max(1, ndiv);
	double org[3];
	int dm[3];
	for (int q = 0; q < 3; q++) {
		org[q] = lo[q] - Rk - 2 * d;
		dm[q] = (int)std::ceil((hi[q] - lo[q] + 2 * Rk + 4 * d) / d) + 1;
	}
	size_t tot = (size_t)dm[0] * dm[1] * dm[2];
	std::vector<float> F(tot, 0.0f);
	auto fid = [&](int i, int j, int k) { return (size_t)i + (size_t)dm[0] * ((size_t)j + (size_t)dm[1] * k); };
	for (int p = 0; p < N; p++) {
		const double *a3 = &ax[3 * p], *V = &ev[9 * p];
		double detG = 1.0 / (a3[0] * a3[1] * a3[2]);
		double cst = Vp * detG / K_INT;
		// G = V diag(1/a) V^T (world -> kernel space); AABB of the ellipsoid
		double G[9];
		for (int r = 0; r < 3; r++)
			for (int c = 0; c < 3; c++) {
				double sacc = 0;
				for (int q = 0; q < 3; q++) sacc += V[3 * r + q] * V[3 * c + q] / a3[q];
				G[3 * r + c] = sacc;
			}
		int i0[3], i1[3];
		for (int q = 0; q < 3; q++) {
			double ext = 0;
			for (int k = 0; k < 3; k++) ext += V[3 * q + k] * V[3 * q + k] * a3[k] * a3[k];
			ext = std::sqrt(ext);
			i0[q] = std::max(0, (int)std::ceil((xs[3 * p + q] - ext - org[q]) / d));
			i1[q] = std::min(dm[q] - 1, (int)std::floor((xs[3 * p + q] + ext - org[q]) / d));
		}
		for (int k = i0[2]; k <= i1[2]; k++) {
			double rz = org[2] + k * d - xs[3 * p + 2];
			for (int j = i0[1]; j <= i1[1]; j++) {
				double ry = org[1] + j * d - xs[3 * p + 1];
				for (int i = i0[0]; i <= i1[0]; i++) {
					double rx = org[0] + i * d - xs[3 * p];
					double u0 = G[0] * rx + G[1] * ry + G[2] * rz, u1 = G[3] * rx + G[4] * ry + G[5] * rz, u2 = G[6] * rx + G[7] * ry + G[8] * rz;
					double u2s = u0 * u0 + u1 * u1 + u2 * u2;
					if (u2s >= 1.0) continue;
					double t = 1.0 - u2s;
					F[fid(i, j, k)] += (float)(cst * t * t * t);
				}
			}
		}
	}
	auto val = [&](int i, int j, int k) {
		i = std::clamp(i, 0, dm[0] - 1); j = std::clamp(j, 0, dm[1] - 1); k = std::clamp(k, 0, dm[2] - 1);
		return (double)F[fid(i, j, k)];
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
			verts.push_back(Vector3((real_t)(org[0] + pp[q].x * d), (real_t)(org[1] + pp[q].y * d), (real_t)(org[2] + pp[q].z * d)));
		}
	};
	for (int k = 0; k < dm[2] - 1; k++)
		for (int j = 0; j < dm[1] - 1; j++)
			for (int i = 0; i < dm[0] - 1; i++) {
				double fv[8];
				bool any_in = false, any_out = false;
				for (int c = 0; c < 8; c++) {
					fv[c] = F[fid(i + cv[c][0], j + cv[c][1], k + cv[c][2])];
					if (fv[c] >= iso) any_in = true; else any_out = true;
				}
				if (!(any_in && any_out)) continue;
				for (int t = 0; t < 6; t++) {
					int in[4], outv[4], ni = 0, no = 0;
					for (int q = 0; q < 4; q++) { int c = tets[t][q]; if (fv[c] >= iso) in[ni++] = c; else outv[no++] = c; }
					auto cut = [&](int a, int b) {
						double t0 = (iso - fv[a]) / (fv[b] - fv[a]);
						return Vector3((real_t)(i + cv[a][0] + t0 * (cv[b][0] - cv[a][0])), (real_t)(j + cv[a][1] + t0 * (cv[b][1] - cv[a][1])), (real_t)(k + cv[a][2] + t0 * (cv[b][2] - cv[a][2])));
					};
					if (ni == 1) emit(cut(in[0], outv[0]), cut(in[0], outv[1]), cut(in[0], outv[2]));
					else if (ni == 3) emit(cut(outv[0], in[0]), cut(outv[0], in[1]), cut(outv[0], in[2]));
					else if (ni == 2) {
						Vector3 a = cut(in[0], outv[0]), b = cut(in[0], outv[1]), c = cut(in[1], outv[1]), dd = cut(in[1], outv[0]);
						emit(a, b, c);
						emit(a, c, dd);
					}
				}
			}
	out["verts"] = verts;
	out["normals"] = norms;
	return out;
}
