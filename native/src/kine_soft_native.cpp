#include "kine_soft_native.h"

#include <cmath>
#include <vector>

using namespace godot;

namespace {

// F = Ds Dm^-1 of tet (row-major 3x3). The operation order is the one of SoftBody._f_gd.
inline void deform(const double *x, const int *t, const double *m, double F[3][3]) {
	const int i0 = t[0] * 3, i1 = t[1] * 3, i2 = t[2] * 3, i3 = t[3] * 3;
	for (int r = 0; r < 3; r++) {
		const double c1 = x[i1 + r] - x[i0 + r];
		const double c2 = x[i2 + r] - x[i0 + r];
		const double c3 = x[i3 + r] - x[i0 + r];
		for (int q = 0; q < 3; q++) F[r][q] = c1 * m[0 * 3 + q] + c2 * m[1 * 3 + q] + c3 * m[2 * 3 + q];
	}
}

// the gradient of C w.r.t. the four nodes from G = dC/dF: g[k+1][r] = sum_c G[r][c] m[k][c]; g[0] = -(g1 + g2 + g3)
inline void node_grads(const double G[3][3], const double *m, double g[4][3]) {
	for (int kk = 0; kk < 3; kk++)
		for (int r = 0; r < 3; r++) g[kk + 1][r] = G[r][0] * m[kk * 3 + 0] + G[r][1] * m[kk * 3 + 1] + G[r][2] * m[kk * 3 + 2];
	for (int r = 0; r < 3; r++) g[0][r] = -(g[1][r] + g[2][r] + g[3][r]);
}

// Polar rotation R of F by Higham's Newton iteration R <- (R + R^-T) / 2, up to 12 rounds, stopping when no entry moves by 1e-13 (quadratic; the operation order is the
// one of SoftBody._polar_gd). A (near-)singular R is left as it is.
inline void polar(const double F[3][3], double R[3][3]) {
	for (int r = 0; r < 3; r++)
		for (int q = 0; q < 3; q++) R[r][q] = F[r][q];
	for (int it = 0; it < 12; it++) {
		const double c00 = R[1][1] * R[2][2] - R[1][2] * R[2][1];
		const double c01 = R[1][2] * R[2][0] - R[1][0] * R[2][2];
		const double c02 = R[1][0] * R[2][1] - R[1][1] * R[2][0];
		const double c10 = R[0][2] * R[2][1] - R[0][1] * R[2][2];
		const double c11 = R[0][0] * R[2][2] - R[0][2] * R[2][0];
		const double c12 = R[0][1] * R[2][0] - R[0][0] * R[2][1];
		const double c20 = R[0][1] * R[1][2] - R[0][2] * R[1][1];
		const double c21 = R[0][2] * R[1][0] - R[0][0] * R[1][2];
		const double c22 = R[0][0] * R[1][1] - R[0][1] * R[1][0];
		const double det = R[0][0] * c00 + R[0][1] * c01 + R[0][2] * c02;
		if (std::fabs(det) < 1e-18) break;
		const double idet = 1.0 / det;
		const double n00 = 0.5 * (R[0][0] + c00 * idet), n01 = 0.5 * (R[0][1] + c01 / det), n02 = 0.5 * (R[0][2] + c02 / det);
		const double n10 = 0.5 * (R[1][0] + c10 * idet), n11 = 0.5 * (R[1][1] + c11 / det), n12 = 0.5 * (R[1][2] + c12 / det);
		const double n20 = 0.5 * (R[2][0] + c20 * idet), n21 = 0.5 * (R[2][1] + c21 / det), n22 = 0.5 * (R[2][2] + c22 / det);
		double dmax = std::fabs(n00 - R[0][0]);
		dmax = std::fmax(dmax, std::fabs(n01 - R[0][1])); dmax = std::fmax(dmax, std::fabs(n02 - R[0][2]));
		dmax = std::fmax(dmax, std::fabs(n10 - R[1][0])); dmax = std::fmax(dmax, std::fabs(n11 - R[1][1])); dmax = std::fmax(dmax, std::fabs(n12 - R[1][2]));
		dmax = std::fmax(dmax, std::fabs(n20 - R[2][0])); dmax = std::fmax(dmax, std::fabs(n21 - R[2][1])); dmax = std::fmax(dmax, std::fabs(n22 - R[2][2]));
		R[0][0] = n00; R[0][1] = n01; R[0][2] = n02;
		R[1][0] = n10; R[1][1] = n11; R[1][2] = n12;
		R[2][0] = n20; R[2][1] = n21; R[2][2] = n22;
		if (dmax < 1e-13) break;
	}
}

// The deviatoric (corotated) constraint of one tet: C = |F - R|, stiffness k = 2 mu, so (1/2) k V0 C^2 = mu V0 |F - R|^2.
inline void solve_dev(double *x, const double *w, const int *t, const double *m, double v0, double k, double dt, double &lam) {
	double F[3][3];
	deform(x, t, m, F);
	double R[3][3];
	polar(F, R);
	double s2 = 0.0;
	for (int r = 0; r < 3; r++)
		for (int q = 0; q < 3; q++) s2 += (F[r][q] - R[r][q]) * (F[r][q] - R[r][q]);
	const double C = std::sqrt(s2);
	if (C < 1e-12) return;
	double G[3][3];
	for (int r = 0; r < 3; r++)
		for (int q = 0; q < 3; q++) G[r][q] = (F[r][q] - R[r][q]) / C;
	double g[4][3];
	node_grads(G, m, g);
	double s = 0.0;
	for (int a = 0; a < 4; a++) {
		const double wa = w[t[a]];
		s += wa * (g[a][0] * g[a][0] + g[a][1] * g[a][1] + g[a][2] * g[a][2]);
	}
	const double at = (1.0 / (k * v0)) / (dt * dt);
	const double den = s + at;
	if (den < 1e-30) return;
	const double dl = (-C - at * lam) / den;
	lam += dl;
	for (int a = 0; a < 4; a++) {
		const double f = w[t[a]] * dl;
		const int ia = t[a] * 3;
		x[ia] += f * g[a][0];
		x[ia + 1] += f * g[a][1];
		x[ia + 2] += f * g[a][2];
	}
}

// The hydrostatic constraint of one CELL (six tets): C = sum(V0 det F) / sum(V0) - gamma, compliance 1 / (lambda V0cell).
// Grouping the tets of a cell is the cure for volumetric locking: one det F = const per tet over-constrains a tet mesh
// (the soft_test bar 1c measured 2.6 % volume lost at nu 0.495 per tet, against 0.4 % expected from the continuum).
inline void solve_cell(double *x, const double *w, const int *tets, const double *dm, const double *v0, int cell, double k, double gamma,
		double dt, double &lam) {
	if (k <= 0.0) return; // lambda = 0 (nu = 0): no volume term
	int ids[24];
	int ng = 0;
	double gs[24][3];
	double jsum = 0.0, vc = 0.0;
	for (int tt = 0; tt < 6; tt++) {
		const int t = cell * 6 + tt;
		const int *tn = &tets[t * 4];
		const double *m = &dm[t * 9];
		double F[3][3];
		deform(x, tn, m, F);
		const double f0x = F[0][0], f0y = F[1][0], f0z = F[2][0];
		const double f1x = F[0][1], f1y = F[1][1], f1z = F[2][1];
		const double f2x = F[0][2], f2y = F[1][2], f2z = F[2][2];
		const double a0 = f1y * f2z - f1z * f2y, a1 = f1z * f2x - f1x * f2z, a2 = f1x * f2y - f1y * f2x;
		const double b0 = f2y * f0z - f2z * f0y, b1 = f2z * f0x - f2x * f0z, b2 = f2x * f0y - f2y * f0x;
		const double d0 = f0y * f1z - f0z * f1y, d1 = f0z * f1x - f0x * f1z, d2 = f0x * f1y - f0y * f1x;
		double G[3][3];
		G[0][0] = a0; G[1][0] = a1; G[2][0] = a2;
		G[0][1] = b0; G[1][1] = b1; G[2][1] = b2;
		G[0][2] = d0; G[1][2] = d1; G[2][2] = d2;
		const double J = f0x * a0 + f0y * a1 + f0z * a2;
		jsum += v0[t] * J;
		vc += v0[t];
		double g[4][3];
		node_grads(G, m, g);
		for (int a = 0; a < 4; a++) {
			int li = -1;
			for (int q = 0; q < ng; q++)
				if (ids[q] == tn[a]) { li = q; break; }
			if (li < 0) {
				li = ng++;
				ids[li] = tn[a];
				gs[li][0] = 0.0; gs[li][1] = 0.0; gs[li][2] = 0.0;
			}
			gs[li][0] += v0[t] * g[a][0];
			gs[li][1] += v0[t] * g[a][1];
			gs[li][2] += v0[t] * g[a][2];
		}
	}
	const double C = jsum / vc - gamma;
	double s = 0.0;
	for (int q = 0; q < ng; q++) {
		for (int r = 0; r < 3; r++) gs[q][r] = gs[q][r] / vc;
		s += w[ids[q]] * (gs[q][0] * gs[q][0] + gs[q][1] * gs[q][1] + gs[q][2] * gs[q][2]);
	}
	const double at = (1.0 / (k * vc)) / (dt * dt);
	const double den = s + at;
	if (den < 1e-30) return;
	const double dl = (-C - at * lam) / den;
	lam += dl;
	for (int q = 0; q < ng; q++) {
		const double f = w[ids[q]] * dl;
		const int ia = ids[q] * 3;
		x[ia] += f * gs[q][0];
		x[ia + 1] += f * gs[q][1];
		x[ia + 2] += f * gs[q][2];
	}
}

} // namespace

void KineSoftNative::_bind_methods() {
	ClassDB::bind_static_method("KineSoftNative", D_METHOD("version"), &KineSoftNative::version);
	ClassDB::bind_static_method("KineSoftNative",
			D_METHOD("run", "x", "v", "w", "tets", "dm", "v0", "pin_idx", "pin_to", "fext", "vref", "nsub", "iters", "dt", "mu", "lam", "gamma", "gx", "gy", "gz", "damp"),
			&KineSoftNative::run);
}

int KineSoftNative::version() {
	return 1;
}

Array KineSoftNative::run(const PackedFloat64Array &p_x, const PackedFloat64Array &p_v, const PackedFloat64Array &p_w,
		const PackedInt32Array &p_tets, const PackedFloat64Array &p_dm, const PackedFloat64Array &p_v0,
		const PackedInt32Array &p_pin_idx, const PackedFloat64Array &p_pin_to, const PackedFloat64Array &p_fext,
		const PackedFloat64Array &p_vref, int p_nsub, int p_iters, double p_dt, double p_mu, double p_lam, double p_gamma, double p_gx, double p_gy, double p_gz,
		double p_damp) {
	const int n3 = (int)p_x.size();
	const int N = n3 / 3;
	const int T = (int)(p_tets.size() / 4);
	std::vector<double> x(n3), v(n3), xp(n3), x0(n3), w(N), fext(n3, 0.0), vref(n3, 0.0), dm(p_dm.size()), v0(T);
	std::vector<int> tets(p_tets.size()), pin(p_pin_idx.size());
	std::vector<double> pto(p_pin_to.size());
	for (int i = 0; i < n3; i++) { x[i] = p_x[i]; v[i] = p_v[i]; }
	for (int i = 0; i < N; i++) w[i] = p_w[i];
	if ((int)p_fext.size() == n3) for (int i = 0; i < n3; i++) fext[i] = p_fext[i];
	if ((int)p_vref.size() == n3) for (int i = 0; i < n3; i++) vref[i] = p_vref[i];
	for (int i = 0; i < (int)dm.size(); i++) dm[i] = p_dm[i];
	for (int i = 0; i < T; i++) v0[i] = p_v0[i];
	for (int i = 0; i < (int)tets.size(); i++) tets[i] = p_tets[i];
	for (int i = 0; i < (int)pin.size(); i++) pin[i] = p_pin_idx[i];
	for (int i = 0; i < (int)pto.size(); i++) pto[i] = p_pin_to[i];
	x0 = x;
	const int NC = T / 6; // the hydrostatic constraint is per cell (six tets)
	std::vector<double> lamD(T), lamH(NC);
	const double dt = p_dt / (double)p_nsub;
	const double damp = std::exp(-p_damp * dt);
	const double g[3] = { p_gx, p_gy, p_gz };
	for (int s = 1; s <= p_nsub; s++) {
		const double u = (double)s / (double)p_nsub;
		xp = x;
		for (int i = 0; i < N; i++) {
			if (w[i] > 0.0) {
				for (int r = 0; r < 3; r++) {
					v[i * 3 + r] += dt * (g[r] + w[i] * fext[i * 3 + r]);
					x[i * 3 + r] += dt * v[i * 3 + r];
				}
			}
		}
		for (int j = 0; j < (int)pin.size(); j++) {
			const int i = pin[j];
			for (int r = 0; r < 3; r++) x[i * 3 + r] = x0[i * 3 + r] + u * (pto[j * 3 + r] - x0[i * 3 + r]);
		}
		for (int i = 0; i < T; i++) lamD[i] = 0.0;
		for (int i = 0; i < NC; i++) lamH[i] = 0.0;
		for (int it = 0; it < p_iters; it++) {
			for (int i = 0; i < T; i++) solve_dev(x.data(), w.data(), &tets[i * 4], &dm[i * 9], v0[i], 2.0 * p_mu, dt, lamD[i]);
			for (int c = 0; c < NC; c++) solve_cell(x.data(), w.data(), tets.data(), dm.data(), v0.data(), c, p_lam, p_gamma, dt, lamH[c]);
		}
		for (int i = 0; i < n3; i++) v[i] = vref[i] + (((x[i] - xp[i]) / dt) - vref[i]) * damp;
	}
	PackedFloat64Array ox, ov;
	ox.resize(n3);
	ov.resize(n3);
	for (int i = 0; i < n3; i++) { ox[i] = x[i]; ov[i] = v[i]; }
	Array out;
	out.append(ox);
	out.append(ov);
	return out;
}
