#include "kine_spline_native.h"

#include <cmath>
#include <vector>

using namespace godot;

namespace {

const int TABLE = 200;
const double SCAN = 0.01;
typedef std::vector<double> Vd;

void pt(const Vd &c, int k, bool bez, double u, double *o) {
	const double top = double(k - 1);
	if (u >= top) {
		double s = u - top;
		for (int a = 0; a < 3; a++) {
			o[a] = c[(k - 1) * 3 + a] + s * (c[(k - 1) * 3 + a] - c[(k - 2) * 3 + a]);
		}
		return;
	}
	if (u < 0.0) {
		u = 0.0;
	}
	if (bez) {
		double t = u / top;
		Vd w(c.begin(), c.begin() + k * 3);
		for (int lvl = k - 1; lvl > 0; lvl--) {
			for (int i = 0; i < lvl * 3; i++) {
				w[i] = w[i] + (w[i + 3] - w[i]) * t;
			}
		}
		for (int a = 0; a < 3; a++) {
			o[a] = w[a];
		}
		return;
	}
	int sp = int(std::floor(u));
	if (sp > k - 2) {
		sp = k - 2;
	}
	double t2 = u - double(sp);
	double t3 = t2 * t2 * t2;
	double tq = t2 * t2;
	double h00 = 2.0 * t3 - 3.0 * tq + 1.0;
	double h10 = t3 - 2.0 * tq + t2;
	double h01 = -2.0 * t3 + 3.0 * tq;
	double h11 = t3 - tq;
	for (int a = 0; a < 3; a++) {
		double p0 = c[sp * 3 + a];
		double p1 = c[(sp + 1) * 3 + a];
		double m0 = (sp == 0) ? c[3 + a] - c[a] : (c[(sp + 1) * 3 + a] - c[(sp - 1) * 3 + a]) * 0.5;
		double m1 = (sp == k - 2) ? c[(k - 1) * 3 + a] - c[(k - 2) * 3 + a] : (c[(sp + 2) * 3 + a] - c[sp * 3 + a]) * 0.5;
		o[a] = p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11;
	}
}

double dist(const double *a, const double *b) {
	double dx = a[0] - b[0];
	double dy = a[1] - b[1];
	double dz = a[2] - b[2];
	return std::sqrt(dx * dx + dy * dy + dz * dz);
}

void rot(const double *v, double ax, double ay, double az, double cs, double sn, double *o) {
	double d = ax * v[0] + ay * v[1] + az * v[2];
	double cx = ay * v[2] - az * v[1];
	double cy = az * v[0] - ax * v[2];
	double cz = ax * v[1] - ay * v[0];
	o[0] = v[0] * cs + cx * sn + ax * d * (1.0 - cs);
	o[1] = v[1] * cs + cy * sn + ay * d * (1.0 - cs);
	o[2] = v[2] * cs + cz * sn + az * d * (1.0 - cs);
}

} // namespace

void KineSplineNative::_bind_methods() {
	ClassDB::bind_static_method("KineSplineNative", D_METHOD("version"), &KineSplineNative::version);
	ClassDB::bind_static_method("KineSplineNative", D_METHOD("solve", "root", "lens", "ctrl", "kind", "mode", "tw0", "tw1", "rest_y", "rest_x", "volume"), &KineSplineNative::solve);
}

int KineSplineNative::version() { return 1; }

Dictionary KineSplineNative::solve(const PackedFloat64Array &p_root, const PackedFloat64Array &p_lens, const PackedFloat64Array &p_ctrl, int kind, int mode,
		double tw0, double tw1, const PackedFloat64Array &rest_y, const PackedFloat64Array &rest_x, bool volume) {
	const int n = int(p_lens.size());
	const int k = int(p_ctrl.size()) / 3;
	Vd c(p_ctrl.size());
	for (int i = 0; i < (int)p_ctrl.size(); i++) {
		c[i] = p_ctrl[i];
	}
	for (int a = 0; a < 3; a++) {
		c[a] = p_root[a];
	}
	Vd lens(n);
	for (int i = 0; i < n; i++) {
		lens[i] = p_lens[i];
	}
	const bool bez = kind == 1;
	const double top = double(k - 1);
	Vd joints((n + 1) * 3);
	double tmp[3] = { 0, 0, 0 };
	double tot = 0.0;
	Vd cum(n + 1);
	cum[0] = 0.0;
	for (int i = 0; i < n; i++) {
		tot += lens[i];
		cum[i + 1] = tot;
	}
	const int cells = TABLE * (k - 1);
	Vd tab(cells + 1);
	tab[0] = 0.0;
	double prev[3] = { c[0], c[1], c[2] };
	for (int i = 1; i <= cells; i++) {
		pt(c, k, bez, top * double(i) / double(cells), tmp);
		tab[i] = tab[i - 1] + dist(prev, tmp);
		prev[0] = tmp[0];
		prev[1] = tmp[1];
		prev[2] = tmp[2];
	}
	const double curve_len = tab[cells];
	joints[0] = c[0];
	joints[1] = c[1];
	joints[2] = c[2];
	if (mode == 1) {
		for (int i = 1; i <= n; i++) {
			double want = curve_len * (tot > 0.0 ? cum[i] / tot : 0.0);
			double u = top;
			if (i < n) {
				int lo = 0;
				int hi = cells;
				while (hi - lo > 1) {
					int mid = (lo + hi) / 2;
					if (tab[mid] <= want) {
						lo = mid;
					} else {
						hi = mid;
					}
				}
				double span = tab[lo + 1] - tab[lo];
				double f = span > 0.0 ? (want - tab[lo]) / span : 0.0;
				u = top * (double(lo) + f) / double(cells);
			}
			pt(c, k, bez, u, tmp);
			joints[i * 3] = tmp[0];
			joints[i * 3 + 1] = tmp[1];
			joints[i * 3 + 2] = tmp[2];
		}
	} else {
		double u_cur = 0.0;
		double J[3] = { c[0], c[1], c[2] };
		for (int i = 0; i < n; i++) {
			double L = lens[i];
			bool found = false;
			if (u_cur < top) {
				double u_lo = u_cur;
				double u_hi = u_cur;
				while (u_hi < top) {
					u_lo = u_hi;
					u_hi = std::fmin(u_hi + SCAN, top);
					pt(c, k, bez, u_hi, tmp);
					if (dist(J, tmp) >= L) {
						found = true;
						break;
					}
				}
				if (found) {
					for (int it = 0; it < 60; it++) {
						double um = (u_lo + u_hi) * 0.5;
						pt(c, k, bez, um, tmp);
						if (dist(J, tmp) >= L) {
							u_hi = um;
						} else {
							u_lo = um;
						}
					}
					u_cur = (u_lo + u_hi) * 0.5;
					pt(c, k, bez, u_cur, tmp);
				}
			}
			if (!found) {
				double ex = c[(k - 1) * 3];
				double ey = c[(k - 1) * 3 + 1];
				double ez = c[(k - 1) * 3 + 2];
				double tx = ex - c[(k - 2) * 3];
				double ty = ey - c[(k - 2) * 3 + 1];
				double tz = ez - c[(k - 2) * 3 + 2];
				double dx = ex - J[0];
				double dy = ey - J[1];
				double dz = ez - J[2];
				double a2 = tx * tx + ty * ty + tz * tz;
				if (a2 > 1e-18) {
					double b2 = 2.0 * (tx * dx + ty * dy + tz * dz);
					double c2 = dx * dx + dy * dy + dz * dz - L * L;
					double disc = std::fmax(b2 * b2 - 4.0 * a2 * c2, 0.0);
					double s = std::fmax((-b2 + std::sqrt(disc)) / (2.0 * a2), 0.0);
					if (u_cur > top) {
						s = std::fmax(s, u_cur - top);
					}
					u_cur = top + s;
					tmp[0] = ex + s * tx;
					tmp[1] = ey + s * ty;
					tmp[2] = ez + s * tz;
				} else {
					tmp[0] = J[0];
					tmp[1] = J[1] + L;
					tmp[2] = J[2];
				}
			}
			joints[(i + 1) * 3] = tmp[0];
			joints[(i + 1) * 3 + 1] = tmp[1];
			joints[(i + 1) * 3 + 2] = tmp[2];
			J[0] = tmp[0];
			J[1] = tmp[1];
			J[2] = tmp[2];
		}
	}
	PackedFloat64Array axes;
	axes.resize(n * 9);
	PackedFloat64Array scl;
	scl.resize(n);
	PackedFloat64Array crs;
	crs.resize(n);
	PackedFloat64Array twd;
	twd.resize(n);
	double ry_l = std::sqrt(rest_y[0] * rest_y[0] + rest_y[1] * rest_y[1] + rest_y[2] * rest_y[2]);
	double yp[3] = { rest_y[0] / ry_l, rest_y[1] / ry_l, rest_y[2] / ry_l };
	double ref[3] = { rest_x[0], rest_x[1], rest_x[2] };
	double dd = ref[0] * yp[0] + ref[1] * yp[1] + ref[2] * yp[2];
	ref[0] -= yp[0] * dd;
	ref[1] -= yp[1] * dd;
	ref[2] -= yp[2] * dd;
	double rl = std::sqrt(ref[0] * ref[0] + ref[1] * ref[1] + ref[2] * ref[2]);
	ref[0] /= rl;
	ref[1] /= rl;
	ref[2] /= rl;
	double y[3] = { yp[0], yp[1], yp[2] };
	double chain_len = 0.0;
	double o3[3] = { 0, 0, 0 };
	for (int i = 0; i < n; i++) {
		double dx = joints[(i + 1) * 3] - joints[i * 3];
		double dy = joints[(i + 1) * 3 + 1] - joints[i * 3 + 1];
		double dz = joints[(i + 1) * 3 + 2] - joints[i * 3 + 2];
		double bl = std::sqrt(dx * dx + dy * dy + dz * dz);
		chain_len += bl;
		if (bl > 1e-12) {
			y[0] = dx / bl;
			y[1] = dy / bl;
			y[2] = dz / bl;
		}
		double cs = yp[0] * y[0] + yp[1] * y[1] + yp[2] * y[2];
		double kx = yp[1] * y[2] - yp[2] * y[1];
		double ky = yp[2] * y[0] - yp[0] * y[2];
		double kz = yp[0] * y[1] - yp[1] * y[0];
		double kl = std::sqrt(kx * kx + ky * ky + kz * kz);
		if (kl > 1e-12) {
			rot(ref, kx / kl, ky / kl, kz / kl, cs, kl, o3);
			ref[0] = o3[0];
			ref[1] = o3[1];
			ref[2] = o3[2];
		} else if (cs < 0.0) {
			double px = 0.0, py = 0.0, pz = 0.0;
			if (std::fabs(y[0]) < 0.9) {
				px = 1.0;
			} else {
				py = 1.0;
			}
			double d2 = px * y[0] + py * y[1] + pz * y[2];
			px -= y[0] * d2;
			py -= y[1] * d2;
			pz -= y[2] * d2;
			double pl = std::sqrt(px * px + py * py + pz * pz);
			rot(ref, px / pl, py / pl, pz / pl, -1.0, 0.0, o3);
			ref[0] = o3[0];
			ref[1] = o3[1];
			ref[2] = o3[2];
		}
		double d3 = ref[0] * y[0] + ref[1] * y[1] + ref[2] * y[2];
		ref[0] -= y[0] * d3;
		ref[1] -= y[1] * d3;
		ref[2] -= y[2] * d3;
		double rl2 = std::sqrt(ref[0] * ref[0] + ref[1] * ref[1] + ref[2] * ref[2]);
		ref[0] /= rl2;
		ref[1] /= rl2;
		ref[2] /= rl2;
		yp[0] = y[0];
		yp[1] = y[1];
		yp[2] = y[2];
		double f_far = tot > 0.0 ? cum[i + 1] / tot : 0.0;
		double tw = tw0 + (tw1 - tw0) * f_far;
		twd[i] = tw;
		double trad = tw * (3.14159265358979323846 / 180.0);
		rot(ref, y[0], y[1], y[2], std::cos(trad), std::sin(trad), o3);
		double xx = o3[0], xy = o3[1], xz = o3[2];
		axes[i * 9] = xx;
		axes[i * 9 + 1] = xy;
		axes[i * 9 + 2] = xz;
		axes[i * 9 + 3] = y[0];
		axes[i * 9 + 4] = y[1];
		axes[i * 9 + 5] = y[2];
		axes[i * 9 + 6] = xy * y[2] - xz * y[1];
		axes[i * 9 + 7] = xz * y[0] - xx * y[2];
		axes[i * 9 + 8] = xx * y[1] - xy * y[0];
		double sc = 1.0;
		if (mode == 1 && lens[i] > 0.0) {
			sc = bl / lens[i];
		}
		scl[i] = sc;
		crs[i] = (volume && sc > 0.0) ? 1.0 / std::sqrt(sc) : 1.0;
	}
	PackedFloat64Array jo;
	jo.resize((n + 1) * 3);
	for (int i = 0; i < (n + 1) * 3; i++) {
		jo[i] = joints[i];
	}
	Dictionary out;
	out["joints"] = jo;
	out["axes"] = axes;
	out["scale"] = scl;
	out["cross"] = crs;
	out["twist"] = twd;
	out["curve_len"] = curve_len;
	out["chain_len"] = chain_len;
	return out;
}
