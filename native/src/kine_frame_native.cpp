#include "kine_frame_native.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <numeric>
#include <queue>
#include <vector>

using namespace godot;

namespace {

typedef std::vector<double> Vd;

// symmetric band matrix, lower part: a[i * ld + (bw - (i - j))] = A(i, j) for 0 <= i - j <= bw
struct Band {
	int n = 0, bw = 0, ld = 1;
	Vd a;
	void init(int n_, int bw_) { n = n_; bw = bw_; ld = bw_ + 1; a.assign((size_t)n * ld, 0.0); }
	inline double &at(int i, int j) { return a[(size_t)i * ld + (bw - (i - j))]; } // i >= j
	inline double get(int i, int j) const { return a[(size_t)i * ld + (bw - (i - j))]; }
};

struct Model {
	int nn = 0;
	Vd xyz;
	std::vector<std::array<double, 12>> beams;
	struct Spr { int a, b; double k; };
	std::vector<Spr> sprs;
	std::vector<char> fixedDof;
	Vd addMass;
	std::vector<std::pair<int, double>> dash; // CH12: lateral viscous dampers, (global dof, c) added to the damping matrix diagonal
	std::vector<int> map; // global dof -> free index, or -1
	int nf = 0, bw = 0;
};

void cross3(const double *a, const double *b, double *c) {
	c[0] = a[1] * b[2] - a[2] * b[1];
	c[1] = a[2] * b[0] - a[0] * b[2];
	c[2] = a[0] * b[1] - a[1] * b[0];
}

// element stiffness K and consistent mass M in global coordinates (12x12, row major)
bool elem_matrices(const Model &m, const std::array<double, 12> &e, double *K, double *M, int &n1, int &n2) {
	n1 = (int)e[0];
	n2 = (int)e[1];
	const double *p1 = &m.xyz[n1 * 3], *p2 = &m.xyz[n2 * 3];
	double d[3] = { p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2] };
	double L = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
	if (L < 1e-9) return false;
	double e1[3] = { d[0] / L, d[1] / L, d[2] / L };
	double r[3] = { e[9], e[10], e[11] };
	double dp = r[0] * e1[0] + r[1] * e1[1] + r[2] * e1[2];
	double e2[3] = { r[0] - dp * e1[0], r[1] - dp * e1[1], r[2] - dp * e1[2] };
	double l2 = std::sqrt(e2[0] * e2[0] + e2[1] * e2[1] + e2[2] * e2[2]);
	if (l2 < 1e-9) return false;
	for (int i = 0; i < 3; i++) e2[i] /= l2;
	double e3[3];
	cross3(e1, e2, e3);
	double A = e[2], Iz = e[3], Iy = e[4], J = e[5], E = e[6], G = e[7], rho = e[8];
	double kl[144], ml[144];
	std::memset(kl, 0, sizeof(kl));
	std::memset(ml, 0, sizeof(ml));
	double L2 = L * L, L3 = L2 * L;
	double ea = E * A / L;
	kl[0 * 12 + 0] += ea; kl[6 * 12 + 6] += ea; kl[0 * 12 + 6] -= ea; kl[6 * 12 + 0] -= ea;
	double ma = rho * A * L / 6.0;
	ml[0 * 12 + 0] += 2 * ma; ml[6 * 12 + 6] += 2 * ma; ml[0 * 12 + 6] += ma; ml[6 * 12 + 0] += ma;
	double gj = G * J / L;
	kl[3 * 12 + 3] += gj; kl[9 * 12 + 9] += gj; kl[3 * 12 + 9] -= gj; kl[9 * 12 + 3] -= gj;
	double mt = rho * (Iz + Iy) * L / 6.0;
	ml[3 * 12 + 3] += 2 * mt; ml[9 * 12 + 9] += 2 * mt; ml[3 * 12 + 9] += mt; ml[9 * 12 + 3] += mt;
	{
		int ix[4] = { 1, 5, 7, 11 };
		double c = E * Iz / L3;
		double kb[4][4] = { { 12, 6 * L, -12, 6 * L }, { 6 * L, 4 * L2, -6 * L, 2 * L2 }, { -12, -6 * L, 12, -6 * L }, { 6 * L, 2 * L2, -6 * L, 4 * L2 } };
		double cm = rho * A * L / 420.0;
		double mb[4][4] = { { 156, 22 * L, 54, -13 * L }, { 22 * L, 4 * L2, 13 * L, -3 * L2 }, { 54, 13 * L, 156, -22 * L }, { -13 * L, -3 * L2, -22 * L, 4 * L2 } };
		for (int i = 0; i < 4; i++)
			for (int j = 0; j < 4; j++) {
				kl[ix[i] * 12 + ix[j]] += c * kb[i][j];
				ml[ix[i] * 12 + ix[j]] += cm * mb[i][j];
			}
	}
	{
		int ix[4] = { 2, 4, 8, 10 };
		double c = E * Iy / L3;
		double kb[4][4] = { { 12, -6 * L, -12, -6 * L }, { -6 * L, 4 * L2, 6 * L, 2 * L2 }, { -12, 6 * L, 12, 6 * L }, { -6 * L, 2 * L2, 6 * L, 4 * L2 } };
		double cm = rho * A * L / 420.0;
		double mb[4][4] = { { 156, -22 * L, 54, 13 * L }, { -22 * L, 4 * L2, -13 * L, -3 * L2 }, { 54, -13 * L, 156, 22 * L }, { 13 * L, -3 * L2, 22 * L, 4 * L2 } };
		for (int i = 0; i < 4; i++)
			for (int j = 0; j < 4; j++) {
				kl[ix[i] * 12 + ix[j]] += c * kb[i][j];
				ml[ix[i] * 12 + ix[j]] += cm * mb[i][j];
			}
	}
	double R[9] = { e1[0], e1[1], e1[2], e2[0], e2[1], e2[2], e3[0], e3[1], e3[2] };
	double T[144];
	std::memset(T, 0, sizeof(T));
	for (int b = 0; b < 4; b++)
		for (int i = 0; i < 3; i++)
			for (int j = 0; j < 3; j++) T[(b * 3 + i) * 12 + b * 3 + j] = R[i * 3 + j];
	double tmp[144];
	for (int pass = 0; pass < 2; pass++) {
		double *src = pass == 0 ? kl : ml;
		double *dst = pass == 0 ? K : M;
		for (int i = 0; i < 12; i++)
			for (int j = 0; j < 12; j++) {
				double s = 0;
				for (int k = 0; k < 12; k++) s += src[i * 12 + k] * T[k * 12 + j];
				tmp[i * 12 + j] = s;
			}
		for (int i = 0; i < 12; i++)
			for (int j = 0; j < 12; j++) {
				double s = 0;
				for (int k = 0; k < 12; k++) s += T[k * 12 + i] * tmp[k * 12 + j];
				dst[i * 12 + j] = s;
			}
	}
	return true;
}

void rcm_and_number(Model &m) {
	int n = m.nn;
	std::vector<std::vector<int>> adj(n);
	auto link = [&](int a, int b) { if (a != b) { adj[a].push_back(b); adj[b].push_back(a); } };
	for (auto &e : m.beams) link((int)e[0], (int)e[1]);
	for (auto &s : m.sprs) link(s.a, s.b);
	for (auto &v : adj) { std::sort(v.begin(), v.end()); v.erase(std::unique(v.begin(), v.end()), v.end()); }
	std::vector<int> order;
	order.reserve(n);
	std::vector<char> seen(n, 0);
	std::vector<int> byDeg(n);
	std::iota(byDeg.begin(), byDeg.end(), 0);
	std::stable_sort(byDeg.begin(), byDeg.end(), [&](int a, int b) { return adj[a].size() < adj[b].size(); });
	for (int s : byDeg) {
		if (seen[s]) continue;
		std::queue<int> q;
		q.push(s);
		seen[s] = 1;
		while (!q.empty()) {
			int u = q.front();
			q.pop();
			order.push_back(u);
			std::vector<int> nb;
			for (int v : adj[u]) if (!seen[v]) { seen[v] = 1; nb.push_back(v); }
			std::stable_sort(nb.begin(), nb.end(), [&](int a, int b) { return adj[a].size() < adj[b].size(); });
			for (int v : nb) q.push(v);
		}
	}
	std::reverse(order.begin(), order.end());
	m.map.assign((size_t)n * 6, -1);
	int c = 0;
	for (int u : order)
		for (int d = 0; d < 6; d++) if (!m.fixedDof[u * 6 + d]) m.map[u * 6 + d] = c++;
	m.nf = c;
	int bw = 0;
	auto upd = [&](const int *gd, int k) {
		int lo = 1 << 30, hi = -1;
		for (int i = 0; i < k; i++) {
			int f = m.map[gd[i]];
			if (f < 0) continue;
			lo = std::min(lo, f);
			hi = std::max(hi, f);
		}
		if (hi >= 0) bw = std::max(bw, hi - lo);
	};
	for (auto &e : m.beams) { int gd[12]; for (int i = 0; i < 6; i++) { gd[i] = (int)e[0] * 6 + i; gd[6 + i] = (int)e[1] * 6 + i; } upd(gd, 12); }
	for (auto &s : m.sprs) { int gd[6]; for (int i = 0; i < 3; i++) { gd[i] = s.a * 6 + i; gd[3 + i] = s.b * 6 + i; } upd(gd, 6); }
	m.bw = bw;
}

bool assemble(Model &m, Band &K, Band &M) {
	K.init(m.nf, m.bw);
	M.init(m.nf, m.bw);
	double ke[144], me[144];
	for (auto &e : m.beams) {
		int n1, n2;
		if (!elem_matrices(m, e, ke, me, n1, n2)) return false;
		int gd[12];
		for (int i = 0; i < 6; i++) { gd[i] = n1 * 6 + i; gd[6 + i] = n2 * 6 + i; }
		for (int i = 0; i < 12; i++) {
			int fi = m.map[gd[i]];
			if (fi < 0) continue;
			for (int j = 0; j < 12; j++) {
				int fj = m.map[gd[j]];
				if (fj < 0 || fj > fi) continue;
				K.at(fi, fj) += ke[i * 12 + j];
				M.at(fi, fj) += me[i * 12 + j];
			}
		}
	}
	for (auto &s : m.sprs) {
		const double *p1 = &m.xyz[s.a * 3], *p2 = &m.xyz[s.b * 3];
		double d[3] = { p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2] };
		double L = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
		if (L < 1e-9) return false;
		double n[3] = { d[0] / L, d[1] / L, d[2] / L };
		int gd[6];
		double sg[6];
		for (int i = 0; i < 3; i++) { gd[i] = s.a * 6 + i; gd[3 + i] = s.b * 6 + i; sg[i] = -n[i]; sg[3 + i] = n[i]; }
		for (int i = 0; i < 6; i++) {
			int fi = m.map[gd[i]];
			if (fi < 0) continue;
			for (int j = 0; j < 6; j++) {
				int fj = m.map[gd[j]];
				if (fj < 0 || fj > fi) continue;
				K.at(fi, fj) += s.k * sg[i] * sg[j];
			}
		}
	}
	for (int nd = 0; nd < m.nn; nd++) {
		double am = m.addMass[nd];
		if (am == 0.0) continue;
		for (int d = 0; d < 3; d++) {
			int f = m.map[nd * 6 + d];
			if (f >= 0) M.at(f, f) += am;
		}
	}
	return true;
}

// in-place banded Cholesky A = L L^T. false if not positive definite
bool chol(Band &A) {
	int n = A.n, bw = A.bw;
	for (int j = 0; j < n; j++) {
		int k0 = std::max(0, j - bw);
		double s = A.at(j, j);
		for (int k = k0; k < j; k++) { double l = A.at(j, k); s -= l * l; }
		if (!(s > 1e-300)) return false;
		double dd = std::sqrt(s);
		A.at(j, j) = dd;
		int imax = std::min(n - 1, j + bw);
		for (int i = j + 1; i <= imax; i++) {
			int kk0 = std::max(std::max(0, i - bw), k0);
			double t = A.at(i, j);
			for (int k = kk0; k < j; k++) t -= A.at(i, k) * A.at(j, k);
			A.at(i, j) = t / dd;
		}
	}
	return true;
}

void chol_solve(const Band &L, Vd &x) {
	int n = L.n, bw = L.bw;
	for (int i = 0; i < n; i++) {
		double s = x[i];
		for (int k = std::max(0, i - bw); k < i; k++) s -= L.get(i, k) * x[k];
		x[i] = s / L.get(i, i);
	}
	for (int i = n - 1; i >= 0; i--) {
		double s = x[i];
		int kmax = std::min(n - 1, i + bw);
		for (int k = i + 1; k <= kmax; k++) s -= L.get(k, i) * x[k];
		x[i] = s / L.get(i, i);
	}
}

void band_mul(const Band &A, const Vd &x, Vd &y) {
	int n = A.n, bw = A.bw;
	y.assign(n, 0.0);
	for (int i = 0; i < n; i++) {
		const double *row = &A.a[(size_t)i * A.ld];
		int j0 = std::max(0, i - bw);
		double s = 0;
		for (int j = j0; j < i; j++) {
			double v = row[bw - (i - j)];
			s += v * x[j];
			y[j] += v * x[i];
		}
		y[i] += s + row[bw] * x[i];
	}
}

PackedFloat64Array to_pf(const Vd &v) {
	PackedFloat64Array p;
	p.resize((int64_t)v.size());
	for (size_t i = 0; i < v.size(); i++) p[(int64_t)i] = v[i];
	return p;
}

} // namespace

void KineFrameNative::_bind_methods() {
	ClassDB::bind_static_method("KineFrameNative", D_METHOD("version"), &KineFrameNative::version);
	ClassDB::bind_static_method("KineFrameNative", D_METHOD("solve", "model", "job"), &KineFrameNative::solve);
}

int KineFrameNative::version() { return 1; }

// job "static":  loads (6n) -> u (6n), f (6n, K u incl. the constrained dofs; reaction = f - loads there)
// job "modal":   start (6n), iters -> rq (Rayleigh quotient of the start vector, then after each inverse iteration), omega, phi (6n)
// model "dashpots" (optional, CH12): pairs (global dof, c) of lateral viscous dampers; job "crowd" (optional, CH12): n1 n2 w omega theta0 (per pedestrian), F0, cp, dir
// job "newmark": dt, nsteps, ag (nsteps + 1 base accelerations, force = -M r ag, r = 1 on translational dir 0/1/2 of every free node),
//                u0 / v0 (6n, optional), alpha / beta (C = alpha M + beta K), record (global dofs), snap_every (0 = none)
//                -> rec_u rec_v rec_a (row k = record[k], nsteps + 1 columns), snaps (Array of 6n displacement vectors), ke_end, se_end
Dictionary KineFrameNative::solve(const Dictionary &p_model, const Dictionary &p_job) {
	Dictionary out;
	Model m;
	PackedFloat64Array xyz = p_model["xyz"];
	m.nn = (int)(xyz.size() / 3);
	m.xyz.assign(xyz.ptr(), xyz.ptr() + xyz.size());
	PackedFloat64Array bm = p_model["beams"];
	for (int64_t i = 0; i + 11 < bm.size(); i += 12) {
		std::array<double, 12> e;
		for (int k = 0; k < 12; k++) e[k] = bm[i + k];
		m.beams.push_back(e);
	}
	PackedFloat64Array sp = p_model.get("springs", PackedFloat64Array());
	for (int64_t i = 0; i + 2 < sp.size(); i += 3) m.sprs.push_back({ (int)sp[i], (int)sp[i + 1], sp[i + 2] });
	m.fixedDof.assign((size_t)m.nn * 6, 0);
	PackedInt32Array fx = p_model.get("fixed", PackedInt32Array());
	for (int64_t i = 0; i < fx.size(); i++) m.fixedDof[fx[i]] = 1;
	PackedFloat64Array am = p_model.get("mass", PackedFloat64Array());
	m.addMass.assign(am.ptr(), am.ptr() + am.size());
	if (m.addMass.size() != (size_t)m.nn) m.addMass.assign(m.nn, 0.0);
	PackedFloat64Array dp = p_model.get("dashpots", PackedFloat64Array());
	for (int64_t i = 0; i + 1 < dp.size(); i += 2) m.dash.push_back({ (int)dp[i], dp[i + 1] });
	rcm_and_number(m);
	Band K, M;
	if (!assemble(m, K, M)) { out["error"] = "degenerate element"; return out; }
	int nf = m.nf;
	out["bw"] = m.bw;
	out["nfree"] = nf;
	String type = p_job["type"];
	auto gather = [&](const PackedFloat64Array &g) {
		Vd f(nf, 0.0);
		for (int i = 0; i < m.nn * 6; i++) if (m.map[i] >= 0) f[m.map[i]] = g[i];
		return f;
	};
	auto scatter = [&](const Vd &f) {
		Vd g((size_t)m.nn * 6, 0.0);
		for (int i = 0; i < m.nn * 6; i++) if (m.map[i] >= 0) g[i] = f[m.map[i]];
		return g;
	};
	auto internal = [&](const Vd &ug) {
		Vd f((size_t)m.nn * 6, 0.0);
		double ke[144], me[144];
		for (auto &e : m.beams) {
			int n1, n2;
			elem_matrices(m, e, ke, me, n1, n2);
			int gd[12];
			for (int i = 0; i < 6; i++) { gd[i] = n1 * 6 + i; gd[6 + i] = n2 * 6 + i; }
			for (int i = 0; i < 12; i++) {
				double s = 0;
				for (int j = 0; j < 12; j++) s += ke[i * 12 + j] * ug[gd[j]];
				f[gd[i]] += s;
			}
		}
		for (auto &s : m.sprs) {
			const double *p1 = &m.xyz[s.a * 3], *p2 = &m.xyz[s.b * 3];
			double d[3] = { p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2] };
			double L = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
			double n[3] = { d[0] / L, d[1] / L, d[2] / L };
			double ext = 0;
			for (int i = 0; i < 3; i++) ext += n[i] * (ug[s.b * 6 + i] - ug[s.a * 6 + i]);
			for (int i = 0; i < 3; i++) { f[s.a * 6 + i] -= s.k * ext * n[i]; f[s.b * 6 + i] += s.k * ext * n[i]; }
		}
		return f;
	};
	if (type == "static") {
		PackedFloat64Array loads = p_job["loads"];
		Vd rhs = gather(loads);
		Band Kf = K;
		if (!chol(Kf)) { out["error"] = "stiffness not positive definite (a floating member or a mechanism)"; return out; }
		chol_solve(Kf, rhs);
		Vd ug = scatter(rhs);
		out["u"] = to_pf(ug);
		out["f"] = to_pf(internal(ug));
		return out;
	}
	if (type == "modal") {
		PackedFloat64Array st = p_job["start"];
		int iters = p_job.get("iters", 3);
		Band Kf = K;
		if (!chol(Kf)) { out["error"] = "stiffness not positive definite"; return out; }
		Vd x = gather(st), rq;
		auto rayleigh = [&](const Vd &v) {
			Vd a, b;
			band_mul(K, v, a);
			band_mul(M, v, b);
			double nn = 0, dd = 0;
			for (int i = 0; i < nf; i++) { nn += v[i] * a[i]; dd += v[i] * b[i]; }
			return nn / dd;
		};
		rq.push_back(rayleigh(x));
		for (int it = 0; it < iters; it++) {
			Vd y;
			band_mul(M, x, y);
			chol_solve(Kf, y);
			double nrm = 0;
			for (int i = 0; i < nf; i++) nrm = std::max(nrm, std::fabs(y[i]));
			for (int i = 0; i < nf; i++) y[i] /= nrm;
			x = y;
			rq.push_back(rayleigh(x));
		}
		out["rq"] = to_pf(rq);
		out["omega"] = std::sqrt(rq.back());
		out["phi"] = to_pf(scatter(x));
		return out;
	}
	if (type == "newmark") {
		double dt = p_job["dt"];
		int ns = p_job["nsteps"];
		const double beta = 0.25, gam = 0.5;
		PackedFloat64Array ag = p_job.get("ag", PackedFloat64Array());
		int dir = p_job.get("dir", 0);
		double alpha = p_job.get("alpha", 0.0), bet = p_job.get("beta", 0.0);
		PackedFloat64Array u0g = p_job.get("u0", PackedFloat64Array());
		PackedFloat64Array v0g = p_job.get("v0", PackedFloat64Array());
		PackedInt32Array rec = p_job.get("record", PackedInt32Array());
		int snap_every = p_job.get("snap_every", 0);
		Vd u(nf, 0.0), v(nf, 0.0), a(nf, 0.0);
		if (u0g.size() == (int64_t)m.nn * 6) u = gather(u0g);
		if (v0g.size() == (int64_t)m.nn * 6) v = gather(v0g);
		Vd r(nf, 0.0);
		for (int nd = 0; nd < m.nn; nd++) { int f = m.map[nd * 6 + dir]; if (f >= 0) r[f] = 1.0; }
		Vd Mr;
		band_mul(M, r, Mr);
		auto force = [&](int step, Vd &P) {
			P.assign(nf, 0.0);
			if (ag.size() > step) { double g = ag[step]; for (int i = 0; i < nf; i++) P[i] = -Mr[i] * g; }
		};
		auto Cmul = [&](const Vd &x, Vd &y) {
			Vd a1, a2;
			band_mul(M, x, a1);
			band_mul(K, x, a2);
			y.resize(nf);
			for (int i = 0; i < nf; i++) y[i] = alpha * a1[i] + bet * a2[i];
		};
		{
			Vd P, Cv, Ku;
			force(0, P);
			Cmul(v, Cv);
			for (auto &d : m.dash) { int f = m.map[d.first]; if (f >= 0) Cv[f] += d.second * v[f]; }
			band_mul(K, u, Ku);
			Vd rhs(nf);
			for (int i = 0; i < nf; i++) rhs[i] = P[i] - Cv[i] - Ku[i];
			Band Mf = M;
			if (!chol(Mf)) { out["error"] = "mass not positive definite"; return out; }
			chol_solve(Mf, rhs);
			a = rhs;
		}
		Band Ke;
		Ke.init(nf, m.bw);
		double c1 = 1.0 / (beta * dt * dt), c2 = gam / (beta * dt);
		for (size_t i = 0; i < Ke.a.size(); i++) Ke.a[i] = K.a[i] * (1.0 + c2 * bet) + M.a[i] * (c1 + c2 * alpha);
		for (auto &d : m.dash) { int f = m.map[d.first]; if (f >= 0) Ke.at(f, f) += c2 * d.second; }
		if (!chol(Ke)) { out["error"] = "effective stiffness not positive definite"; return out; }
		// CH12 crowd: pedestrians whose lateral force F0 sin(theta) is phase-locked to the local deck velocity, theta' = omega + cp v cos(theta) (cp = 0: free-running random-phase control)
		Dictionary crowd = p_job.get("crowd", Dictionary());
		PackedInt32Array cn1, cn2;
		PackedFloat64Array cw, com, cth;
		double cF0 = 0, ccp = 0;
		int cdir = 2;
		if (!crowd.is_empty()) {
			cn1 = crowd["n1"]; cn2 = crowd["n2"]; cw = crowd["w"]; com = crowd["omega"]; cth = crowd["theta0"];
			cF0 = crowd["F0"]; ccp = crowd["cp"]; cdir = crowd.get("dir", 2);
		}
		int np = (int)cn1.size();
		Vd th(cth.ptr(), cth.ptr() + cth.size());
		Vd cpow((size_t)ns + 1, 0.0);
		std::vector<int> cf1(np), cf2(np);
		for (int i = 0; i < np; i++) { cf1[i] = m.map[cn1[i] * 6 + cdir]; cf2[i] = m.map[cn2[i] * 6 + cdir]; }
		int nr = (int)rec.size();
		Vd ru((size_t)nr * (ns + 1)), rv(ru.size()), ra(ru.size());
		Array snaps;
		auto store = [&](int step) {
			for (int k = 0; k < nr; k++) {
				int f = m.map[rec[k]];
				size_t ix = (size_t)k * (ns + 1) + step;
				ru[ix] = f >= 0 ? u[f] : 0.0;
				rv[ix] = f >= 0 ? v[f] : 0.0;
				ra[ix] = f >= 0 ? a[f] : 0.0;
			}
			if (snap_every > 0 && step % snap_every == 0) snaps.push_back(to_pf(scatter(u)));
		};
		store(0);
		Vd P, t1(nf), t2(nf), Mt, Ct, rhs(nf), dashadd;
		for (int s = 0; s < ns; s++) {
			force(s + 1, P);
			for (int i = 0; i < np; i++) {
				double w = cw[i];
				double vi = (1.0 - w) * (cf1[i] >= 0 ? v[cf1[i]] : 0.0) + w * (cf2[i] >= 0 ? v[cf2[i]] : 0.0);
				double g1 = com[i] + ccp * vi * std::cos(th[i]);
				double tm = th[i] + 0.5 * dt * g1;
				th[i] += dt * (com[i] + ccp * vi * std::cos(tm));
				double F = cF0 * std::sin(th[i]);
				if (cf1[i] >= 0) P[cf1[i]] += (1.0 - w) * F;
				if (cf2[i] >= 0) P[cf2[i]] += w * F;
				cpow[s + 1] += F * vi;
			}
			for (int i = 0; i < nf; i++) t1[i] = c1 * u[i] + (1.0 / (beta * dt)) * v[i] + (1.0 / (2 * beta) - 1.0) * a[i];
			for (int i = 0; i < nf; i++) t2[i] = c2 * u[i] + (gam / beta - 1.0) * v[i] + dt * (gam / (2 * beta) - 1.0) * a[i];
			// M t1 + (alpha M + bet K) t2 = M (t1 + alpha t2) + K (bet t2): two band products instead of three
			Ct.resize(nf);
			dashadd.resize(m.dash.size());
			for (size_t k = 0; k < m.dash.size(); k++) { int f = m.map[m.dash[k].first]; dashadd[k] = f >= 0 ? m.dash[k].second * t2[f] : 0.0; }
			for (int i = 0; i < nf; i++) { Ct[i] = bet * t2[i]; t2[i] = t1[i] + alpha * t2[i]; }
			band_mul(M, t2, Mt);
			Vd Kt;
			band_mul(K, Ct, Kt);
			for (int i = 0; i < nf; i++) rhs[i] = P[i] + Mt[i] + Kt[i];
			for (size_t k = 0; k < m.dash.size(); k++) { int f = m.map[m.dash[k].first]; if (f >= 0) rhs[f] += dashadd[k]; }
			chol_solve(Ke, rhs);
			for (int i = 0; i < nf; i++) {
				double an = c1 * (rhs[i] - u[i]) - (1.0 / (beta * dt)) * v[i] - (1.0 / (2 * beta) - 1.0) * a[i];
				v[i] += dt * ((1.0 - gam) * a[i] + gam * an);
				a[i] = an;
				u[i] = rhs[i];
			}
			store(s + 1);
		}
		out["rec_u"] = to_pf(ru);
		out["rec_v"] = to_pf(rv);
		out["rec_a"] = to_pf(ra);
		out["snaps"] = snaps;
		out["crowd_power"] = to_pf(cpow);
		out["crowd_theta"] = to_pf(th);
		{
			Vd Mv, Ku;
			band_mul(M, v, Mv);
			band_mul(K, u, Ku);
			double ke = 0, se = 0;
			for (int i = 0; i < nf; i++) { ke += 0.5 * v[i] * Mv[i]; se += 0.5 * u[i] * Ku[i]; }
			out["ke_end"] = ke;
			out["se_end"] = se;
		}
		return out;
	}
	out["error"] = "unknown job type";
	return out;
}
