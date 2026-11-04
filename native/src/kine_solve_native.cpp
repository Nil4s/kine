#include "kine_solve_native.h"

#include <vector>

using namespace godot;

void KineSolveNative::_bind_methods() {
	ClassDB::bind_static_method("KineSolveNative", D_METHOD("version"), &KineSolveNative::version);
	ClassDB::bind_static_method("KineSolveNative", D_METHOD("cg", "n", "rp", "ci", "cv", "dg", "b", "x", "tol", "max_iter"), &KineSolveNative::cg);
}

int KineSolveNative::version() { return 1; }

Dictionary KineSolveNative::cg(int n, const PackedInt32Array &p_rp, const PackedInt32Array &p_ci, const PackedFloat64Array &p_cv,
		const PackedFloat64Array &p_dg, const PackedFloat64Array &p_b, const PackedFloat64Array &p_x, double tol, int max_iter) {
	const int32_t *rp = p_rp.ptr();
	const int32_t *ci = p_ci.ptr();
	const double *cv = p_cv.ptr();
	const double *dg = p_dg.ptr();
	const double *b = p_b.ptr();
	PackedFloat64Array xo = p_x;
	Dictionary out;
	if (n <= 0) {
		out["it"] = 0;
		out["x"] = xo;
		return out;
	}
	double *x = xo.ptrw();
	std::vector<double> r(n), z(n), p(n), q(n);
	double bn = 0.0;
	for (int i = 0; i < n; i++) {
		double s = dg[i] * x[i];
		for (int e = rp[i]; e < rp[i + 1]; e++) {
			s += cv[e] * x[ci[e]];
		}
		r[i] = b[i] - s;
		bn += b[i] * b[i];
	}
	if (bn <= 0.0) {
		bn = 1.0;
	}
	double tol2 = tol * tol * bn;
	double rz = 0.0, rr = 0.0;
	for (int i = 0; i < n; i++) {
		z[i] = r[i] / dg[i];
		p[i] = z[i];
		rz += r[i] * z[i];
		rr += r[i] * r[i];
	}
	int it = 0;
	while (it < max_iter && rr > tol2) {
		double pq = 0.0;
		for (int i = 0; i < n; i++) {
			double s = dg[i] * p[i];
			for (int e = rp[i]; e < rp[i + 1]; e++) {
				s += cv[e] * p[ci[e]];
			}
			q[i] = s;
			pq += p[i] * s;
		}
		if (pq <= 0.0) {
			break;
		}
		double al = rz / pq;
		double rz2 = 0.0;
		rr = 0.0;
		for (int i = 0; i < n; i++) {
			x[i] += al * p[i];
			r[i] -= al * q[i];
			z[i] = r[i] / dg[i];
			rz2 += r[i] * z[i];
			rr += r[i] * r[i];
		}
		double be = rz2 / rz;
		rz = rz2;
		for (int i = 0; i < n; i++) {
			p[i] = z[i] + be * p[i];
		}
		it++;
	}
	out["it"] = it;
	out["x"] = xo;
	return out;
}
