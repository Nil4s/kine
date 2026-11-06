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

// fraction of a triangle (corner values a, b, c of a linear field) where the field is negative (= solid)
inline double tri_neg(double a, double b, double c) {
	int n = (a < 0 ? 1 : 0) + (b < 0 ? 1 : 0) + (c < 0 ? 1 : 0);
	if (n == 0) return 0.0;
	if (n == 3) return 1.0;
	if (n == 1) {
		double s, p, q;
		if (a < 0) { s = a; p = b; q = c; } else if (b < 0) { s = b; p = a; q = c; } else { s = c; p = a; q = b; }
		return (s / (s - p)) * (s / (s - q));
	}
	double x, y, z; // x >= 0, y and z < 0
	if (a >= 0) { x = a; y = b; z = c; } else if (b >= 0) { x = b; y = a; z = c; } else { x = c; y = a; z = b; }
	return 1.0 - (x / (x - y)) * (x / (x - z));
}

// open (fluid side, phi >= 0) area fraction of a square face with corner values p00, p10, p11, p01 (in order around the square): four triangles around
// the corner mean, so the answer does not depend on a diagonal choice
inline double face_open(double p00, double p10, double p11, double p01) {
	double m = 0.25 * (p00 + p10 + p11 + p01);
	double neg = tri_neg(p00, p10, m) + tri_neg(p10, p11, m) + tri_neg(p11, p01, m) + tri_neg(p01, p00, m);
	return 1.0 - 0.25 * neg;
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
	ClassDB::bind_method(D_METHOD("set_wall_law", "mask", "nu"), &KineFluidNative::set_wall_law);
	ClassDB::bind_method(D_METHOD("set_release_delay", "t"), &KineFluidNative::set_release_delay);
	ClassDB::bind_method(D_METHOD("set_density_mode", "mode"), &KineFluidNative::set_density_mode);
	ClassDB::bind_method(D_METHOD("set_surface_taubin", "on"), &KineFluidNative::set_surface_taubin);
	ClassDB::bind_method(D_METHOD("set_extrapolation", "on"), &KineFluidNative::set_extrapolation);
	ClassDB::bind_method(D_METHOD("surface_aniso", "iso", "ndiv"), &KineFluidNative::surface_aniso);
	ClassDB::bind_method(D_METHOD("add_cut_box", "min", "max"), &KineFluidNative::add_cut_box);
	ClassDB::bind_method(D_METHOD("clear_cut"), &KineFluidNative::clear_cut);
	ClassDB::bind_method(D_METHOD("add_cut_halfspace", "point", "normal"), &KineFluidNative::add_cut_halfspace);
	ClassDB::bind_method(D_METHOD("add_cut_mesh", "verts", "tris"), &KineFluidNative::add_cut_mesh);
	ClassDB::bind_method(D_METHOD("set_cut_wmin", "w"), &KineFluidNative::set_cut_wmin);
	ClassDB::bind_method(D_METHOD("rebuild_weights"), &KineFluidNative::rebuild_weights);
	ClassDB::bind_method(D_METHOD("face_weights"), &KineFluidNative::face_weights);
	ClassDB::bind_method(D_METHOD("open_volume"), &KineFluidNative::open_volume);
}

void KineFluidNative::setup(int p_nx, int p_ny, int p_nz, double p_h, Vector3 p_origin) {
	nx = p_nx; ny = p_ny; nz = p_nz; h = p_h;
	ox = p_origin.x; oy = p_origin.y; oz = p_origin.z;
	size_t nc = (size_t)nx * ny * nz;
	mtri.clear(); mbucket_start.clear(); mbucket_items.clear(); mesh_flip = false;
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
	cut = false; wdirty = true;
	phi.clear(); wxp.clear(); wyp.clear(); wzp.clear();
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
	wdirty = true;
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				double cx = ox + (i + 0.5) * h, cy = oy + (j + 0.5) * h, cz = oz + (k + 0.5) * h;
				if (cx >= mn.x && cx <= mx.x && cy >= mn.y && cy <= mx.y && cz >= mn.z && cz <= mx.z) solid[cid(i, j, k)] = 1;
			}
}

int KineFluidNative::add_solid_mesh(const PackedVector3Array &vs, const PackedInt32Array &tr) {
	wdirty = true;
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

// ---------------------------------------------------------------- cut-cell walls (L5 liquids)
// drops every cut solid (a moving wall is rebuilt each step: clear_cut, then add_cut_box at the new place)
void KineFluidNative::clear_cut() {
	cut = false; wdirty = true;
	phi.clear(); vfrac.clear(); wxp.clear(); wyp.clear(); wzp.clear();
	mtri.clear(); mbucket_start.clear(); mbucket_items.clear(); mesh_flip = false;
}

void KineFluidNative::add_cut_box(Vector3 mn, Vector3 mx) {
	cut = true; wdirty = true;
	if (phi.empty()) phi.assign((size_t)(nx + 1) * (ny + 1) * (nz + 1), 1e9);
	double c[3] = { 0.5 * (mn.x + mx.x), 0.5 * (mn.y + mx.y), 0.5 * (mn.z + mx.z) };
	double hf[3] = { 0.5 * (mx.x - mn.x), 0.5 * (mx.y - mn.y), 0.5 * (mx.z - mn.z) };
	for (int k = 0; k <= nz; k++)
		for (int j = 0; j <= ny; j++)
			for (int i = 0; i <= nx; i++) {
				double p[3] = { ox + i * h, oy + j * h, oz + k * h };
				double q[3], out2 = 0, mq = -1e30;
				for (int a = 0; a < 3; a++) {
					q[a] = std::fabs(p[a] - c[a]) - hf[a];
					if (q[a] > 0) out2 += q[a] * q[a];
					mq = std::max(mq, q[a]);
				}
				double d = std::sqrt(out2) + std::min(mq, 0.0);
				double &ph = phi[nid(i, j, k)];
				ph = std::min(ph, d);
			}
}

// solid on the side opposite to the normal: phi = dot(p - point, normal)
void KineFluidNative::add_cut_halfspace(Vector3 pt, Vector3 nrm) {
	cut = true; wdirty = true;
	if (phi.empty()) phi.assign((size_t)(nx + 1) * (ny + 1) * (nz + 1), 1e9);
	double l = std::sqrt(nrm.x * nrm.x + nrm.y * nrm.y + nrm.z * nrm.z);
	double n[3] = { nrm.x / l, nrm.y / l, nrm.z / l };
	for (int k = 0; k <= nz; k++)
		for (int j = 0; j <= ny; j++)
			for (int i = 0; i <= nx; i++) {
				double d = (ox + i * h - pt.x) * n[0] + (oy + j * h - pt.y) * n[1] + (oz + k * h - pt.z) * n[2];
				double &ph = phi[nid(i, j, k)];
				ph = std::min(ph, d);
			}
}

namespace {
// squared distance from point p to triangle abc (Ericson, Real-Time Collision Detection, 5.1.5)
double pt_tri_d2(const double p[3], const double a[3], const double b[3], const double c[3]) {
	auto sub = [](const double *x, const double *y, double *o) { o[0] = x[0] - y[0]; o[1] = x[1] - y[1]; o[2] = x[2] - y[2]; };
	auto dot = [](const double *x, const double *y) { return x[0] * y[0] + x[1] * y[1] + x[2] * y[2]; };
	double ab[3], ac[3], ap[3];
	sub(b, a, ab); sub(c, a, ac); sub(p, a, ap);
	double d1 = dot(ab, ap), d2 = dot(ac, ap);
	auto fin = [&](double x, double y, double z) { double e[3] = { p[0] - x, p[1] - y, p[2] - z }; return dot(e, e); };
	if (d1 <= 0 && d2 <= 0) return fin(a[0], a[1], a[2]);
	double bp[3]; sub(p, b, bp);
	double d3 = dot(ab, bp), d4 = dot(ac, bp);
	if (d3 >= 0 && d4 <= d3) return fin(b[0], b[1], b[2]);
	double vc = d1 * d4 - d3 * d2;
	if (vc <= 0 && d1 >= 0 && d3 <= 0) { double v = d1 / (d1 - d3); return fin(a[0] + v * ab[0], a[1] + v * ab[1], a[2] + v * ab[2]); }
	double cp[3]; sub(p, c, cp);
	double d5 = dot(ab, cp), d6 = dot(ac, cp);
	if (d6 >= 0 && d5 <= d6) return fin(c[0], c[1], c[2]);
	double vb = d5 * d2 - d1 * d6;
	if (vb <= 0 && d2 >= 0 && d6 <= 0) { double w = d2 / (d2 - d6); return fin(a[0] + w * ac[0], a[1] + w * ac[1], a[2] + w * ac[2]); }
	double va = d3 * d6 - d5 * d4;
	if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) { double w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return fin(b[0] + w * (c[0] - b[0]), b[1] + w * (c[1] - b[1]), b[2] + w * (c[2] - b[2])); }
	double den = 1.0 / (va + vb + vc), v = vb * den, w = vc * den;
	return fin(a[0] + ab[0] * v + ac[0] * w, a[1] + ab[1] * v + ac[1] * w, a[2] + ab[2] * v + ac[2] * w);
}
// closest point on triangle abc to p (same case analysis as above)
void pt_tri_cp(const double p[3], const double a[3], const double b[3], const double c[3], double q[3]) {
	auto sub = [](const double *x, const double *y, double *o) { o[0] = x[0] - y[0]; o[1] = x[1] - y[1]; o[2] = x[2] - y[2]; };
	auto dot = [](const double *x, const double *y) { return x[0] * y[0] + x[1] * y[1] + x[2] * y[2]; };
	double ab[3], ac[3], ap[3];
	sub(b, a, ab); sub(c, a, ac); sub(p, a, ap);
	auto set = [&](double x, double y, double z) { q[0] = x; q[1] = y; q[2] = z; };
	double d1 = dot(ab, ap), d2 = dot(ac, ap);
	if (d1 <= 0 && d2 <= 0) { set(a[0], a[1], a[2]); return; }
	double bp[3]; sub(p, b, bp);
	double d3 = dot(ab, bp), d4 = dot(ac, bp);
	if (d3 >= 0 && d4 <= d3) { set(b[0], b[1], b[2]); return; }
	double vc = d1 * d4 - d3 * d2;
	if (vc <= 0 && d1 >= 0 && d3 <= 0) { double v = d1 / (d1 - d3); set(a[0] + v * ab[0], a[1] + v * ab[1], a[2] + v * ab[2]); return; }
	double cp[3]; sub(p, c, cp);
	double d5 = dot(ab, cp), d6 = dot(ac, cp);
	if (d6 >= 0 && d5 <= d6) { set(c[0], c[1], c[2]); return; }
	double vb = d5 * d2 - d1 * d6;
	if (vb <= 0 && d2 >= 0 && d6 <= 0) { double w = d2 / (d2 - d6); set(a[0] + w * ac[0], a[1] + w * ac[1], a[2] + w * ac[2]); return; }
	double va = d3 * d6 - d5 * d4;
	if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) { double w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); set(b[0] + w * (c[0] - b[0]), b[1] + w * (c[1] - b[1]), b[2] + w * (c[2] - b[2])); return; }
	double den = 1.0 / (va + vb + vc), v = vb * den, w = vc * den;
	set(a[0] + ab[0] * v + ac[0] * w, a[1] + ab[1] * v + ac[1] * w, a[2] + ab[2] * v + ac[2] * w);
}
} // namespace

// A mesh as a cut solid: signed distance at the cell corners. Unsigned distance is exact (point - triangle) inside a band of 3 cells, the sign is ray parity
// along +x per corner column (the line is skewed by a fixed fraction of a cell so it never runs along an edge). Returns the number of corners inside.
int KineFluidNative::add_cut_mesh(const PackedVector3Array &vs, const PackedInt32Array &tr) {
	cut = true; wdirty = true;
	size_t nn = (size_t)(nx + 1) * (ny + 1) * (nz + 1);
	if (phi.empty()) phi.assign(nn, 1e9);
	const double band = 3.0 * h;
	std::vector<double> ud(nn, band * band);
	int nt3 = tr.size() / 3;
	{   // keep the triangles and bucket them per cell for the exact particle projection
		double vol6 = 0;
		for (int t = 0; t < nt3; t++) {
			for (int c = 0; c < 3; c++) { const Vector3 &v = vs[tr[3 * t + c]]; mtri.push_back(v.x); mtri.push_back(v.y); mtri.push_back(v.z); }
		}
		size_t ntot = mtri.size() / 9;
		for (size_t t = 0; t < ntot; t++) {
			const double *a = &mtri[9 * t], *b = a + 3, *c = a + 6;
			vol6 += a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0]);
		}
		mesh_flip = vol6 < 0;
		size_t nc = (size_t)nx * ny * nz;
		std::vector<std::vector<int>> bk(nc);
		for (size_t t = 0; t < ntot; t++) {
			const double *a = &mtri[9 * t], *b = a + 3, *c = a + 6;
			int i0[3], i1[3];
			int dim[3] = { nx, ny, nz };
			double org[3] = { ox, oy, oz };
			for (int ax = 0; ax < 3; ax++) {
				double lo = std::min(a[ax], std::min(b[ax], c[ax])), hi = std::max(a[ax], std::max(b[ax], c[ax]));
				i0[ax] = std::max(0, (int)std::floor((lo - org[ax]) / h) - 1);
				i1[ax] = std::min(dim[ax] - 1, (int)std::floor((hi - org[ax]) / h) + 1);
			}
			for (int k = i0[2]; k <= i1[2]; k++)
				for (int j = i0[1]; j <= i1[1]; j++)
					for (int i = i0[0]; i <= i1[0]; i++) bk[cid(i, j, k)].push_back((int)t);
		}
		mbucket_start.assign(nc + 1, 0);
		for (size_t c = 0; c < nc; c++) mbucket_start[c + 1] = mbucket_start[c] + (int)bk[c].size();
		mbucket_items.resize(mbucket_start[nc]);
		for (size_t c = 0; c < nc; c++) std::copy(bk[c].begin(), bk[c].end(), mbucket_items.begin() + mbucket_start[c]);
	}
	std::vector<std::vector<double>> xs((size_t)(ny + 1) * (nz + 1));
	const double sy = 0.0137 * h, sz = 0.0071 * h;
	for (int t = 0; t < nt3; t++) {
		double a[3] = { vs[tr[3 * t]].x, vs[tr[3 * t]].y, vs[tr[3 * t]].z };
		double b[3] = { vs[tr[3 * t + 1]].x, vs[tr[3 * t + 1]].y, vs[tr[3 * t + 1]].z };
		double c[3] = { vs[tr[3 * t + 2]].x, vs[tr[3 * t + 2]].y, vs[tr[3 * t + 2]].z };
		double org[3] = { ox, oy, oz };
		int dim[3] = { nx + 1, ny + 1, nz + 1 };
		int i0[3], i1[3];
		for (int ax = 0; ax < 3; ax++) {
			double lo = std::min(a[ax], std::min(b[ax], c[ax])) - band, hi = std::max(a[ax], std::max(b[ax], c[ax])) + band;
			i0[ax] = std::max(0, (int)std::ceil((lo - org[ax]) / h));
			i1[ax] = std::min(dim[ax] - 1, (int)std::floor((hi - org[ax]) / h));
		}
		for (int k = i0[2]; k <= i1[2]; k++)
			for (int j = i0[1]; j <= i1[1]; j++)
				for (int i = i0[0]; i <= i1[0]; i++) {
					double p[3] = { ox + i * h, oy + j * h, oz + k * h };
					double d2 = pt_tri_d2(p, a, b, c);
					double &u = ud[nid(i, j, k)];
					if (d2 < u) u = d2;
				}
		double ylo = std::min(a[1], std::min(b[1], c[1])), yhi = std::max(a[1], std::max(b[1], c[1]));
		double zlo = std::min(a[2], std::min(b[2], c[2])), zhi = std::max(a[2], std::max(b[2], c[2]));
		int j0 = std::max(0, (int)std::ceil((ylo - sy - oy) / h)), j1 = std::min(ny, (int)std::floor((yhi - sy - oy) / h));
		int k0 = std::max(0, (int)std::ceil((zlo - sz - oz) / h)), k1 = std::min(nz, (int)std::floor((zhi - sz - oz) / h));
		double det = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]);
		if (std::fabs(det) < 1e-18) continue;
		for (int k = k0; k <= k1; k++)
			for (int j = j0; j <= j1; j++) {
				double py = oy + j * h + sy, pz = oz + k * h + sz;
				double u = ((py - a[1]) * (c[2] - a[2]) - (pz - a[2]) * (c[1] - a[1])) / det;
				double v = ((b[1] - a[1]) * (pz - a[2]) - (b[2] - a[2]) * (py - a[1])) / det;
				if (u < 0 || v < 0 || u + v > 1) continue;
				xs[j + (size_t)(ny + 1) * k].push_back(a[0] + u * (b[0] - a[0]) + v * (c[0] - a[0]));
			}
	}
	int inside = 0;
	for (int k = 0; k <= nz; k++)
		for (int j = 0; j <= ny; j++) {
			std::vector<double> &col = xs[j + (size_t)(ny + 1) * k];
			std::sort(col.begin(), col.end());
			for (int i = 0; i <= nx; i++) {
				double x = ox + i * h;
				size_t nl = std::lower_bound(col.begin(), col.end(), x) - col.begin();
				bool in = (nl & 1) != 0;
				double d = std::sqrt(ud[nid(i, j, k)]);
				double sd = in ? -d : d;
				if (in) inside++;
				double &ph = phi[nid(i, j, k)];
				ph = std::min(ph, sd);
			}
		}
	return inside;
}

// open (fluid side) area fraction of every face from the corner field; then the cells whose six faces are all closed become solid
void KineFluidNative::rebuild_weights() {
	wdirty = false;
	size_t nc = (size_t)nx * ny * nz;
	wxp.assign(nc, 0.0); wyp.assign(nc, 0.0); wzp.assign(nc, 0.0);
	for (int k = 0; k < nz; k++)
		for (int j = 0; j < ny; j++)
			for (int i = 0; i < nx; i++) {
				int c = cid(i, j, k);
				if (solid[c]) continue;
				if (i < nx - 1 && !solid[c + 1]) {
					double f = 1.0;
					if (cut) f = face_open(phi[nid(i + 1, j, k)], phi[nid(i + 1, j + 1, k)], phi[nid(i + 1, j + 1, k + 1)], phi[nid(i + 1, j, k + 1)]);
					wxp[c] = f < wmin ? 0.0 : f;
				}
				if (j < ny - 1 && !solid[c + nx]) {
					double f = 1.0;
					if (cut) f = face_open(phi[nid(i, j + 1, k)], phi[nid(i + 1, j + 1, k)], phi[nid(i + 1, j + 1, k + 1)], phi[nid(i, j + 1, k + 1)]);
					wyp[c] = f < wmin ? 0.0 : f;
				}
				if (k < nz - 1 && !solid[c + nx * ny]) {
					double f = 1.0;
					if (cut) f = face_open(phi[nid(i, j, k + 1)], phi[nid(i + 1, j, k + 1)], phi[nid(i + 1, j + 1, k + 1)], phi[nid(i, j + 1, k + 1)]);
					wzp[c] = f < wmin ? 0.0 : f;
				}
			}
	if (cut) {
		for (int k = 1; k < nz - 1; k++)
			for (int j = 1; j < ny - 1; j++)
				for (int i = 1; i < nx - 1; i++) {
					int c = cid(i, j, k);
					if (solid[c]) continue;
					if (wxp[c] == 0 && wxp[c - 1] == 0 && wyp[c] == 0 && wyp[c - nx] == 0 && wzp[c] == 0 && wzp[c - nx * ny] == 0) solid[c] = 1;
				}
	}
	// open volume fraction of every cell (rest particle count scale): 1 when all eight corners are open, 0 when all are solid, else 4^3 sub-samples
	vfrac.assign(nc, 1.0);
	if (cut) {
		for (int k = 0; k < nz; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int neg = 0;
					for (int q = 0; q < 8; q++) if (phi[nid(i + (q & 1), j + ((q >> 1) & 1), k + (q >> 2))] < 0) neg++;
					double f = 1.0;
					if (neg == 8) f = 0.0;
					else if (neg > 0) {
						int n = 0;
						for (int c = 0; c < 64; c++) {
							double x = ox + (i + ((c & 3) + 0.5) / 4.0) * h, y = oy + (j + (((c >> 2) & 3) + 0.5) / 4.0) * h, z = oz + (k + ((c >> 4) + 0.5) / 4.0) * h;
							if (phi_at(x, y, z, nullptr) >= 0) n++;
						}
						f = n / 64.0;
					}
					vfrac[cid(i, j, k)] = std::max(0.05, f);
				}
	}
	pre_ok = false;
}

PackedFloat64Array KineFluidNative::face_weights() const {
	PackedFloat64Array out;
	size_t nc = wxp.size();
	out.resize(3 * nc);
	for (size_t c = 0; c < nc; c++) { out[c] = wxp[c]; out[nc + c] = wyp[c]; out[2 * nc + c] = wzp[c]; }
	return out;
}

// trilinear corner field and its gradient (g may be null); outside the grid the indices clamp
double KineFluidNative::phi_at(double x, double y, double z, double *g) const {
	double q[3] = { (x - ox) / h, (y - oy) / h, (z - oz) / h };
	int b[3];
	double f[3];
	int dim[3] = { nx, ny, nz };
	for (int a = 0; a < 3; a++) {
		b[a] = (int)std::floor(q[a]);
		if (b[a] < 0) b[a] = 0;
		if (b[a] > dim[a] - 1) b[a] = dim[a] - 1;
		f[a] = std::min(1.0, std::max(0.0, q[a] - b[a]));
	}
	double r = 0, gx = 0, gy = 0, gz = 0;
	for (int dz = 0; dz < 2; dz++)
		for (int dy = 0; dy < 2; dy++)
			for (int dx = 0; dx < 2; dx++) {
				double wx = dx ? f[0] : 1 - f[0], wy = dy ? f[1] : 1 - f[1], wz = dz ? f[2] : 1 - f[2];
				double val = phi[nid(b[0] + dx, b[1] + dy, b[2] + dz)];
				r += wx * wy * wz * val;
				gx += (dx ? 1.0 : -1.0) * wy * wz * val;
				gy += (dy ? 1.0 : -1.0) * wx * wz * val;
				gz += (dz ? 1.0 : -1.0) * wx * wy * val;
			}
	if (g) { g[0] = gx / h; g[1] = gy / h; g[2] = gz / h; }
	return r;
}

// keeps every particle on the fluid side of the cut solid: phi >= push_margin * h. The inward part of the velocity is removed (free slip).
void KineFluidNative::push_out() {
	if (!cut || phi.empty()) return;
	int N = particle_count();
	double m = push_margin * h;
	pfor(N, nte, [&](int b0, int e0) {
		for (int p = b0; p < e0; p++) {
			double *x = &P[3 * p], *v = &V[3 * p];
			for (int it = 0; it < 3; it++) {
				double g[3];
				double d = phi_at(x[0], x[1], x[2], g);
				if (d >= m) break;
				double gl = std::sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
				if (gl < 0.25) break;
				double n[3] = { g[0] / gl, g[1] / gl, g[2] / gl };
				double s = (m - d) / gl;
				for (int a = 0; a < 3; a++) x[a] += s * n[a];
				double vn = v[0] * n[0] + v[1] * n[1] + v[2] * n[2];
				if (vn < 0) for (int a = 0; a < 3; a++) v[a] -= vn * n[a];
			}
			if (!mbucket_start.empty()) {   // exact point-triangle projection: walls thinner than the corner field resolves
				int ci = std::min(nx - 1, std::max(0, (int)std::floor((x[0] - ox) / h)));
				int cj = std::min(ny - 1, std::max(0, (int)std::floor((x[1] - oy) / h)));
				int ck = std::min(nz - 1, std::max(0, (int)std::floor((x[2] - oz) / h)));
				size_t cc = cid(ci, cj, ck);
				// the triangle that was crossed: among the triangles whose outer side held the particle BEFORE the move, the nearest; else the nearest of all
				double best = 1e30, bq[3] = { 0, 0, 0 }, bn[3] = { 0, 0, 0 };
				double bestA = 1e30, bqA[3] = { 0, 0, 0 }, bnA[3] = { 0, 0, 0 };
				const double *xo = Pold.size() == P.size() ? &Pold[3 * p] : x;
				for (int q = mbucket_start[cc]; q < mbucket_start[cc + 1]; q++) {
					const double *a = &mtri[9 * (size_t)mbucket_items[q]], *b = a + 3, *c = a + 6;
					double qp[3];
					pt_tri_cp(x, a, b, c, qp);
					double dd = (x[0] - qp[0]) * (x[0] - qp[0]) + (x[1] - qp[1]) * (x[1] - qp[1]) + (x[2] - qp[2]) * (x[2] - qp[2]);
					if (dd >= best && dd >= bestA) continue;
					double e1[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] }, e2[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
					double nn[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
					double l = std::sqrt(nn[0] * nn[0] + nn[1] * nn[1] + nn[2] * nn[2]);
					double sg = (mesh_flip ? -1.0 : 1.0) / std::max(l, 1e-30);
					for (int a2 = 0; a2 < 3; a2++) nn[a2] *= sg;
					double so = (xo[0] - a[0]) * nn[0] + (xo[1] - a[1]) * nn[1] + (xo[2] - a[2]) * nn[2];
					if (dd < best) { best = dd; for (int a2 = 0; a2 < 3; a2++) { bq[a2] = qp[a2]; bn[a2] = nn[a2]; } }
					if (so > 0 && dd < bestA) { bestA = dd; for (int a2 = 0; a2 < 3; a2++) { bqA[a2] = qp[a2]; bnA[a2] = nn[a2]; } }
				}
				if (bestA < 1e29) {   // a triangle the particle came from the outer side of: use it when the particle is now behind it or too close
					double sA = (x[0] - bqA[0]) * bnA[0] + (x[1] - bqA[1]) * bnA[1] + (x[2] - bqA[2]) * bnA[2];
					if (sA < 0 || std::sqrt(bestA) < m) { best = bestA; for (int a2 = 0; a2 < 3; a2++) { bq[a2] = bqA[a2]; bn[a2] = bnA[a2]; } }
				}
				if (best < 1e29) {
					double d = std::sqrt(best);
					double side = (x[0] - bq[0]) * bn[0] + (x[1] - bq[1]) * bn[1] + (x[2] - bq[2]) * bn[2];
					bool inside = side < 0;
					if (inside || d < m) {
						for (int a = 0; a < 3; a++) x[a] = bq[a] + bn[a] * m;
						double vn = v[0] * bn[0] + v[1] * bn[1] + v[2] * bn[2];
						if (vn < 0) for (int a = 0; a < 3; a++) v[a] -= vn * bn[a];
					}
				}
			}
		}
	});
}

// volume the fluid can occupy inside the domain walls: 4^3 sub-samples of the corner field in every interior cell
double KineFluidNative::open_volume() const {
	double tot = 0;
	for (int k = 1; k < nz - 1; k++)
		for (int j = 1; j < ny - 1; j++)
			for (int i = 1; i < nx - 1; i++) {
				if (!cut && solid[cid(i, j, k)]) continue;
				int n = 0;
				for (int c = 0; c < 64; c++) {
					double x = ox + (i + ((c & 3) + 0.5) / 4.0) * h, y = oy + (j + (((c >> 2) & 3) + 0.5) / 4.0) * h, z = oz + (k + ((c >> 4) + 0.5) / 4.0) * h;
					if (!cut || phi_at(x, y, z, nullptr) >= 0) n++;
				}
				tot += n / 64.0;
			}
	return tot * h * h * h;
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
					if (cut && !phi.empty() && phi_at(ox + pos[0], oy + pos[1], oz + pos[2], nullptr) < push_margin * h) continue;
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
	// A cut cell under water can be empty of particles (a sliver). Left as air it would be a p = 0 Dirichlet cell BELOW the water and the water would fall
	// into it. An empty cut cell whose upper neighbour is fluid is fluid too (gravity is -y), top to bottom so chains of slivers follow.
	if (cut && !vfrac.empty()) {
		std::vector<int32_t> add;
		for (int k = 1; k < nz - 1; k++)
			for (int j = ny - 2; j >= 1; j--)
				for (int i = 1; i < nx - 1; i++) {
					int c = cid(i, j, k);
					if (type[c] == 0 && vfrac[c] < 1.0 && type[c + nx] == 1) { type[c] = 1; add.push_back((int32_t)c); }
				}
		if (!add.empty()) {
			fl.insert(fl.end(), add.begin(), add.end());
			std::sort(fl.begin(), fl.end());
		}
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
		auto ap = [&](int c, int off) { return (inb(c) && inb(c + off)) ? -(off == sx ? wxp[c] : (off == sy ? wyp[c] : wzp[c])) : 0.0; };
		for (int q = q0; q < q1; q++) {
			int c = fl[q];
			double d = 0;
			d = wxp[c - sx] + wxp[c] + wyp[c - sy] + wyp[c] + wzp[c - sz] + wzp[c];
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
		auto ap = [&](int c, int off) { return (inb(c) && inb(c + off)) ? -(off == sx ? wxp[c] : (off == sy ? wyp[c] : wzp[c])) : 0.0; };
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
			if (isf(c - sx)) tt -= wxp[c - sx] * x[c - sx];
			if (isf(c + sx)) tt -= wxp[c] * x[c + sx];
			if (isf(c - sy)) tt -= wyp[c - sy] * x[c - sy];
			if (isf(c + sy)) tt -= wyp[c] * x[c + sy];
			if (isf(c - sz)) tt -= wzp[c - sz] * x[c - sz];
			if (isf(c + sz)) tt -= wzp[c] * x[c + sz];
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
				if (isf(c - sx)) tt -= wxp[c - sx] * ss[c - sx];
				if (isf(c + sx)) tt -= wxp[c] * ss[c + sx];
				if (isf(c - sy)) tt -= wyp[c - sy] * ss[c - sy];
				if (isf(c + sy)) tt -= wyp[c] * ss[c + sy];
				if (isf(c - sz)) tt -= wzp[c - sz] * ss[c - sz];
				if (isf(c + sz)) tt -= wzp[c] * ss[c + sz];
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

// Friction velocity of the smooth-wall log law for a tangential speed au at distance y from the wall (Prandtl / von Karman; Pope, Turbulent Flows, sec. 7.1):
// u/u_tau = ln(E y u_tau / nu) / kappa, E = exp(kappa B), kappa 0.41, B 5.2; in the viscous sublayer (y+ < 11.06) u+ = y+. Deterministic, same code in the twin.
static double wall_utau(double au, double y, double nu) {
	if (au <= 0.0) return 0.0;
	const double kappa = 0.41, E = std::exp(0.41 * 5.2);
	double uv = std::sqrt(nu * au / y);
	if (y * uv / nu < 11.06) return uv;
	double ut = 0.05 * au;
	for (int it = 0; it < 30; it++) ut = kappa * au / std::log(E * y * ut / nu);
	return ut;
}

void KineFluidNative::apply_wall_friction(double dt) {
	// A face that touches a solid wall sideways (a transverse neighbour of either of its two cells is solid) keeps (1 - wfr) of its speed.
	// L44: with the wall law on, the face loses the wall stress u_tau^2 over the cell height (du/dt = -u_tau^2 / h, u_tau from the log law at y = h/2).
	if (wfr <= 0.0 && wlaw == 0) return;
	const double s = 1.0 - wfr;
	const int off[3] = { 1, nx, nx * ny };
	for (int c : fl) {
		for (int ax = 0; ax < 3; ax++) {
			for (int side = 0; side < 2; side++) {
				int a = side == 0 ? c - off[ax] : c, b = side == 0 ? c : c + off[ax];
				if (side == 1 && type[b] == 1) continue;
				bool touch = false;
				int nw = 0;
				for (int t = 0; t < 3; t++) {
					if (t == ax) continue;
					bool lo = solid[a - off[t]] || solid[b - off[t]], hi = solid[a + off[t]] || solid[b + off[t]];
					if (lo || hi) touch = true;
					if ((wlaw >> t) & 1) nw += (lo ? 1 : 0) + (hi ? 1 : 0);
				}
				if (!touch) continue;
				int i = b % nx, j = (b / nx) % ny, k = b / (nx * ny);
				double *f;
				if (ax == 0) f = &U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)];
				else if (ax == 1) f = &Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)];
				else f = &W[i + (size_t)nx * (j + (size_t)ny * k)];
				if (wfr > 0.0) *f *= s;
				if (nw > 0) {
					double au = std::fabs(*f);
					if (au > 1e-12) {
						double ut = wall_utau(au, 0.5 * h, wnu);
						double fac = 1.0 - dt * nw * ut * ut / (h * au);
						*f *= fac > 0.0 ? fac : 0.0;
					}
				}
			}
		}
	}
}

// Velocity extrapolation into the air (Bridson, Fluid Simulation for Computer Graphics, 2nd ed., sec. on extrapolating velocity): the pressure update only
// reaches faces next to a fluid cell, so a free-surface particle interpolating the grid (the B-spline reaches 1.5 cells) read zeros from the air faces and
// was slowed and given a wrong affine matrix. Two layers of faces beyond the fluid get the mean of their already-valid face neighbours (valid = touching
// a fluid cell, or filled by the previous layer). Faces on solid walls and the domain boundary stay as they are (normal velocity 0).
void KineFluidNative::extrapolate() {
	// is the face between cells a (lower side) and b closed (open fraction 0)? c = axis
	auto wcl = [&](int c, int a) { return (c == 0 ? wxp[a] : (c == 1 ? wyp[a] : wzp[a])) == 0.0; };
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
						if (wcl(c, a) && !(type[a] == 2 && type[b] == 2)) vf[f] = 2;
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
	apply_wall_friction(dt);
	pfor(nz, nte, [&](int k0, int k1) {
		for (int k = k0; k < k1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i <= nx; i++) {
					bool s = (i == 0 || i == nx) || wxp[cid(i - 1, j, k)] == 0.0;
					if (s) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] = 0;
				}
		for (int k = k0; k < k1; k++)
			for (int j = 0; j <= ny; j++)
				for (int i = 0; i < nx; i++) {
					bool s = (j == 0 || j == ny) || wyp[cid(i, j - 1, k)] == 0.0;
					if (s) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] = 0;
				}
	});
	pfor(nz + 1, nte, [&](int k0, int k1) {
		for (int k = k0; k < k1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					bool s = (k == 0 || k == nz) || wzp[cid(i, j, k - 1)] == 0.0;
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
			double div = wxp[c] * U[(i + 1) + (size_t)(nx + 1) * (j + (size_t)ny * k)] - wxp[c - 1] * U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)]
					+ wyp[c] * Vg[i + (size_t)nx * ((j + 1) + (size_t)(ny + 1) * k)] - wyp[c - nx] * Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)]
					+ wzp[c] * W[i + (size_t)nx * (j + (size_t)ny * (k + 1))] - wzp[c - nx * ny] * W[i + (size_t)nx * (j + (size_t)ny * k)];
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
					if (wxp[a] == 0.0) continue;
					if (type[a] == 1 || type[b] == 1) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] -= f * (pr[b] - pr[a]);
				}
		for (int k = k0; k < k1; k++)
			for (int j = 1; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j - 1, k), b = cid(i, j, k);
					if (wyp[a] == 0.0) continue;
					if (type[a] == 1 || type[b] == 1) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] -= f * (pr[b] - pr[a]);
				}
	});
	pfor(nz - 1, nte, [&](int k0, int k1) {
		for (int k = k0 + 1; k < k1 + 1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j, k - 1), b = cid(i, j, k);
					if (wzp[a] == 0.0) continue;
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
			// a cut cell holds fewer particles at rest density: the rest count is ppc times the open volume fraction (1 for a whole cell)
			const double rest = ppc * vfrac[c];
			if (vfrac[c] < 1.0) ex = 0.0; // a cut cell: no density correction (its particles sit against a wall that pushes them back; asking them to spread is a feedback loop)
			else if (cnt[c] > rest) ex = (double)cnt[c] / rest - 1.0;
			else if (cnt[c] < rest && type[c - sx] == 1 && type[c + sx] == 1 && type[c - sy] == 1 && type[c + sy] == 1 && type[c - sz] == 1 && type[c + sz] == 1)
				ex = std::max(-0.5, (double)cnt[c] / rest - 1.0);
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
					if (wxp[a] == 0.0) continue;
					if (type[a] == 1 || type[b] == 1) U[i + (size_t)(nx + 1) * (j + (size_t)ny * k)] = -(dq[b] - dq[a]);
				}
		for (int k = k0; k < k1; k++)
			for (int j = 1; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j - 1, k), b = cid(i, j, k);
					if (wyp[a] == 0.0) continue;
					if (type[a] == 1 || type[b] == 1) Vg[i + (size_t)nx * (j + (size_t)(ny + 1) * k)] = -(dq[b] - dq[a]);
				}
	});
	pfor(nz - 1, nte, [&](int k0, int k1) {
		for (int k = k0 + 1; k < k1 + 1; k++)
			for (int j = 0; j < ny; j++)
				for (int i = 0; i < nx; i++) {
					int a = cid(i, j, k - 1), b = cid(i, j, k);
					if (wzp[a] == 0.0) continue;
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
	push_out();
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
	push_out();
	vmax = 0;
	for (double m : vm) vmax = std::max(vmax, m);
}

void KineFluidNative::step(double dt) {
	auto t0 = Clk::now();
	// threads only pay on a big grid or many particles: the pool barriers cost more than a small loop (and much more when the machine is shared)
	nte = (nt > 1 && ((size_t)nx * ny * nz >= 40000 || particle_count() >= 16384)) ? nt : 1;
	if (wdirty || wxp.empty()) rebuild_weights();
	if (!mbucket_start.empty()) Pold = P;
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
	if (!mbucket_start.empty()) Pold = P;
	advect(dt);
	tm_adv = ms_since(t0);
}

int KineFluidNative::advance(double T) {
	if (release_delay > 0.0) {   // a held column is at rest and nothing acts on it: the hold costs no steps
		double hold = std::min(release_delay, T);
		release_delay -= hold;
		T -= hold;
	}
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
