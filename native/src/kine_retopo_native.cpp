#include "kine_retopo_native.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

using namespace godot;

namespace {

typedef std::vector<int> VI;
const int DIGON_SMOOTH = 100;   // = KMeshRetopoFill.DIGON_SMOOTH: Laplacian steps on a 2-sided patch's interior

// ------------------------------------------------------------------------------------------------ the plan (integer system)
struct Plan {
	bool ok = false;
	std::string reason, kind;
	int n = 0;
	VI d, f;
	int p = 0, alpha = 0, beta = 0;
};

Plan make_plan(const VI &d) {
	Plan pl;
	pl.n = (int)d.size();
	pl.d = d;
	int n = pl.n;
	for (int x : d) {
		if (x < 1) {
			pl.reason = "a side has no edges";
			return pl;
		}
	}
	if (n == 4) {
		pl.kind = "quad";
		if (d[0] != d[2] || d[1] != d[3]) {
			pl.reason = "opposite sides of a 4-sided patch need equal counts";
			return pl;
		}
		pl.ok = true;
		return pl;
	}
	if (n == 3 || n == 5 || n == 6) {
		pl.kind = n == 3 ? "tri" : (n == 5 ? "pent" : "hex");
		int m = (n % 2 == 1) ? n : n / 2;
		pl.f.assign(n, 0);
		for (int i = 0; i < n; i++) {
			int s = 0, sign = 1;
			for (int k = 0; k < m; k++) {
				s += sign * d[(i + 2 * k) % n];
				sign = -sign;
			}
			if ((s & 1) != 0) {
				pl.reason = "the side counts need an even parity (the sum of alternate sides is odd)";
				return pl;
			}
			int fi = s / 2;
			if (fi < 1 || fi > d[i] - 1) {
				pl.reason = "one side is too long for the others (the triangle inequality of the counts fails)";
				return pl;
			}
			pl.f[i] = fi;
		}
		pl.ok = true;
		return pl;
	}
	if (n == 2) {
		pl.kind = "digon";
		int a = d[0], b = d[1];
		if (((a + b) & 1) != 0) {
			pl.reason = "the two sides of a 2-sided patch need counts of the same parity";
			return pl;
		}
		if (a < 3 || b < 3) {
			pl.reason = "a 2-sided patch needs at least 3 edges on each side";
			return pl;
		}
		int mn = a < b ? a : b;
		int best = -1, bscore = 1 << 30;
		for (int p = mn - 2; p >= 1; p--) {
			if (((p - a) & 1) != 0) {
				continue;
			}
			int al = (a - p) / 2, be = (b - p) / 2;
			if (al < 1 || be < 1) {
				continue;
			}
			int sc = al > be ? al - be : be - al;
			if (sc < bscore) {
				bscore = sc;
				best = p;
			}
		}
		if (best < 0) {
			pl.reason = "no 2-sided topology fits these counts";
			return pl;
		}
		pl.p = best;
		pl.alpha = (a - best) / 2;
		pl.beta = (b - best) / 2;
		pl.ok = true;
		return pl;
	}
	pl.kind = "none";
	pl.reason = "only 2 to 6 sided patches are filled";
	return pl;
}

// ------------------------------------------------------------------------------------------------ the patch builder
struct Builder {
	int n = 0;
	VI d, off;
	int B = 0;
	std::vector<double> P;
	VI Q;
	VI special;

	int ring(int i, int k) const { return k == d[i] ? off[(i + 1) % n] : off[i] + k; }
	int addv(double x, double y, double z) {
		P.push_back(x);
		P.push_back(y);
		P.push_back(z);
		return (int)P.size() / 3 - 1;
	}
	VI line(int a, int b, int m) {
		VI out;
		out.push_back(a);
		for (int t = 1; t < m; t++) {
			double w = double(t) / double(m);
			double x = P[a * 3] + (P[b * 3] - P[a * 3]) * w;
			double y = P[a * 3 + 1] + (P[b * 3 + 1] - P[a * 3 + 1]) * w;
			double z = P[a * 3 + 2] + (P[b * 3 + 2] - P[a * 3 + 2]) * w;
			out.push_back(addv(x, y, z));
		}
		out.push_back(b);
		return out;
	}
	// Gauss-Seidel steps of the uniform Laplacian on the non-ring verts, neighbours ascending (= KMeshRetopoFill._B.smooth)
	void smooth(int steps) {
		int nv = (int)P.size() / 3;
		std::vector<VI> nb(nv);
		for (size_t q = 0; q < Q.size() / 4; q++) {
			for (int k = 0; k < 4; k++) {
				int a = Q[q * 4 + k], c = Q[q * 4 + (k + 1) % 4];
				nb[a].push_back(c);
				nb[c].push_back(a);
			}
		}
		for (int v = 0; v < nv; v++) {
			std::sort(nb[v].begin(), nb[v].end());
			nb[v].erase(std::unique(nb[v].begin(), nb[v].end()), nb[v].end());
		}
		for (int it = 0; it < steps; it++) {
			for (int v = B; v < nv; v++) {
				if (nb[v].empty()) continue;
				double sx = 0.0, sy = 0.0, sz = 0.0;
				for (int w : nb[v]) {
					sx += P[w * 3];
					sy += P[w * 3 + 1];
					sz += P[w * 3 + 2];
				}
				P[v * 3] = sx / double(nb[v].size());
				P[v * 3 + 1] = sy / double(nb[v].size());
				P[v * 3 + 2] = sz / double(nb[v].size());
			}
		}
	}
	void grid(const VI &bottom, const VI &right, const VI &top, const VI &left) {
		int A = (int)bottom.size() - 1, Bn = (int)left.size() - 1;
		std::vector<VI> g(A + 1, VI(Bn + 1, -1));
		for (int i = 0; i <= A; i++) {
			g[i][0] = bottom[i];
			g[i][Bn] = top[i];
		}
		for (int j = 0; j <= Bn; j++) {
			g[0][j] = left[j];
			g[A][j] = right[j];
		}
		const double *p00 = &P[bottom[0] * 3];
		const double *p10 = &P[bottom[A] * 3];
		const double *p01 = &P[top[0] * 3];
		const double *p11 = &P[top[A] * 3];
		double c00[3] = { p00[0], p00[1], p00[2] }, c10[3] = { p10[0], p10[1], p10[2] };
		double c01[3] = { p01[0], p01[1], p01[2] }, c11[3] = { p11[0], p11[1], p11[2] };
		for (int j = 1; j < Bn; j++) {
			for (int i = 1; i < A; i++) {
				double u = double(i) / double(A), v = double(j) / double(Bn);
				double r[3];
				for (int c = 0; c < 3; c++) {
					double val = (1.0 - v) * P[bottom[i] * 3 + c] + v * P[top[i] * 3 + c] + (1.0 - u) * P[left[j] * 3 + c] + u * P[right[j] * 3 + c]
							- ((1.0 - u) * (1.0 - v) * c00[c] + u * (1.0 - v) * c10[c] + (1.0 - u) * v * c01[c] + u * v * c11[c]);
					r[c] = val;
				}
				g[i][j] = addv(r[0], r[1], r[2]);
			}
		}
		for (int j = 0; j < Bn; j++) {
			for (int i = 0; i < A; i++) {
				Q.push_back(g[i][j]);
				Q.push_back(g[i + 1][j]);
				Q.push_back(g[i + 1][j + 1]);
				Q.push_back(g[i][j + 1]);
			}
		}
	}
};

bool build(const Plan &pl, const std::vector<std::vector<double>> &sides, Builder &b) {
	int n = pl.n;
	b.n = n;
	b.d = pl.d;
	b.off.assign(n, 0);
	int o = 0;
	for (int i = 0; i < n; i++) {
		b.off[i] = o;
		o += pl.d[i];
	}
	b.B = o;
	for (int i = 0; i < n; i++) {
		for (int k = 0; k < pl.d[i]; k++) {
			b.addv(sides[i][k * 3], sides[i][k * 3 + 1], sides[i][k * 3 + 2]);
		}
	}
	if (n == 4) {
		int a = pl.d[0], bb = pl.d[1];
		VI bottom, right, top, left;
		for (int k = 0; k <= a; k++) bottom.push_back(b.ring(0, k));
		for (int k = 0; k <= bb; k++) right.push_back(b.ring(1, k));
		for (int i = 0; i <= a; i++) top.push_back(b.ring(2, a - i));
		for (int j = 0; j <= bb; j++) left.push_back(b.ring(3, bb - j));
		b.grid(bottom, right, top, left);
		return true;
	}
	if (n == 3 || n == 5 || n == 6) {
		double sx = 0, sy = 0, sz = 0;
		for (int r = 0; r < b.B; r++) {
			sx += b.P[r * 3];
			sy += b.P[r * 3 + 1];
			sz += b.P[r * 3 + 2];
		}
		int C = b.addv(sx / b.B, sy / b.B, sz / b.B);
		b.special.push_back(C);
		std::vector<VI> spoke(n);
		for (int k = 0; k < n; k++) {
			int s = pl.f[(k + 1) % n];
			spoke[k] = b.line(C, b.ring(k, pl.f[k]), s);
		}
		for (int i = 0; i < n; i++) {
			int A = pl.f[(i + 1) % n];
			int Bg = pl.d[i] - pl.f[i];
			VI bottom = spoke[i], right, top, left;
			for (int j = 0; j <= Bg; j++) right.push_back(b.ring(i, pl.f[i] + j));
			for (int iu = 0; iu <= A; iu++) top.push_back(b.ring((i + 1) % n, A - iu));
			const VI &sp = spoke[(i + 1) % n];
			for (int j = 0; j <= Bg; j++) left.push_back(sp[j]);
			b.grid(bottom, right, top, left);
		}
		return true;
	}
	// n == 2
	int a = pl.d[0], bb = pl.d[1], p = pl.p, al = pl.alpha, be = pl.beta;
	auto A_ = [&](int k) { return b.ring(0, k); };
	auto B_ = [&](int k) { return b.ring(1, k); };
	int Pp = A_(0), Qq = A_(a);
	int a1 = A_(al), b1 = B_(bb - be);
	int X = b.addv(b.P[a1 * 3] + b.P[b1 * 3] - b.P[Pp * 3], b.P[a1 * 3 + 1] + b.P[b1 * 3 + 1] - b.P[Pp * 3 + 1], b.P[a1 * 3 + 2] + b.P[b1 * 3 + 2] - b.P[Pp * 3 + 2]);
	int a2 = A_(a - al), b2 = B_(be);
	int Y = b.addv(b.P[a2 * 3] + b.P[b2 * 3] - b.P[Qq * 3], b.P[a2 * 3 + 1] + b.P[b2 * 3 + 1] - b.P[Qq * 3 + 1], b.P[a2 * 3 + 2] + b.P[b2 * 3 + 2] - b.P[Qq * 3 + 2]);
	b.special.push_back(X);
	b.special.push_back(Y);
	VI sXA = b.line(a1, X, be);
	VI sXB = b.line(X, b1, al);
	VI path = b.line(X, Y, p);
	VI sYA = b.line(a2, Y, be);
	VI sYB = b.line(Y, b2, al);
	{   // R_P
		VI bottom, top, left;
		for (int k = 0; k <= al; k++) bottom.push_back(A_(k));
		for (int i = 0; i <= al; i++) top.push_back(sXB[al - i]);
		for (int j = 0; j <= be; j++) left.push_back(B_(bb - j));
		b.grid(bottom, sXA, top, left);
	}
	{   // L
		VI bottom;
		for (int k = 0; k <= p; k++) bottom.push_back(A_(al + k));
		b.grid(bottom, sYA, path, sXA);
	}
	{   // U
		VI top;
		for (int i = 0; i <= p; i++) top.push_back(B_(bb - be - i));
		b.grid(path, sYB, top, sXB);
	}
	{   // R_Q
		VI bottom, right;
		for (int k = 0; k <= al; k++) bottom.push_back(A_(a - al + k));
		for (int k = 0; k <= be; k++) right.push_back(B_(k));
		b.grid(bottom, right, sYB, sYA);
	}
	b.smooth(DIGON_SMOOTH);
	return true;
}

VI to_vi(const PackedInt32Array &a) {
	VI v(a.size());
	for (int i = 0; i < a.size(); i++) v[i] = a[i];
	return v;
}

Dictionary plan_dict(const Plan &pl) {
	Dictionary d;
	d["ok"] = pl.ok;
	d["kind"] = String(pl.kind.c_str());
	d["reason"] = String(pl.reason.c_str());
	d["n"] = pl.n;
	PackedInt32Array f;
	for (int x : pl.f) f.push_back(x);
	d["f"] = f;
	d["p"] = pl.p;
	d["alpha"] = pl.alpha;
	d["beta"] = pl.beta;
	PackedInt32Array sing;
	if (pl.ok) {
		if (pl.kind == "digon") {
			sing.push_back(3);
			sing.push_back(3);
		} else if (pl.kind == "tri" || pl.kind == "pent" || pl.kind == "hex") {
			sing.push_back(pl.n);
		}
	}
	d["singular"] = sing;
	return d;
}

bool read_sides(const Array &p_sides, std::vector<std::vector<double>> &sides, VI &counts, std::string &err) {
	int n = p_sides.size();
	sides.resize(n);
	counts.resize(n);
	for (int i = 0; i < n; i++) {
		PackedFloat64Array s = p_sides[i];
		if (s.size() < 6 || s.size() % 3 != 0) {
			err = "a side needs at least 2 points";
			return false;
		}
		sides[i].resize(s.size());
		for (int k = 0; k < s.size(); k++) sides[i][k] = s[k];
		counts[i] = s.size() / 3 - 1;
	}
	return true;
}

Dictionary fill_impl(const Array &p_sides) {
	Dictionary out;
	std::vector<std::vector<double>> sides;
	VI counts;
	std::string err;
	if (!read_sides(p_sides, sides, counts, err)) {
		out["ok"] = false;
		out["reason"] = String(err.c_str());
		return out;
	}
	Plan pl = make_plan(counts);
	out["kind"] = String(pl.kind.c_str());
	if (!pl.ok) {
		out["ok"] = false;
		out["reason"] = String(pl.reason.c_str());
		return out;
	}
	Builder b;
	build(pl, sides, b);
	PackedFloat64Array pv;
	pv.resize((int64_t)b.P.size());
	for (size_t i = 0; i < b.P.size(); i++) pv.set((int64_t)i, b.P[i]);
	PackedInt32Array qv;
	qv.resize((int64_t)b.Q.size());
	for (size_t i = 0; i < b.Q.size(); i++) qv.set((int64_t)i, b.Q[i]);
	PackedInt32Array sp;
	for (int s : b.special) sp.push_back(s);
	out["ok"] = true;
	out["reason"] = "";
	out["verts"] = pv;
	out["quads"] = qv;
	out["nring"] = b.B;
	out["singular"] = sp;
	return out;
}

// ------------------------------------------------------------------------------------------------ geometry helpers
inline double dot3(const double *a, const double *b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

// Ericson, Real-Time Collision Detection 5.1.5, with the barycentric coordinates of the result
void tri_closest(const double *p, const double *a, const double *b, const double *c, double *q, double *bary) {
	double ab[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] };
	double ac[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
	double ap[3] = { p[0] - a[0], p[1] - a[1], p[2] - a[2] };
	double d1 = dot3(ab, ap), d2 = dot3(ac, ap);
	auto set = [&](double u, double v, double w) {
		bary[0] = u;
		bary[1] = v;
		bary[2] = w;
		for (int k = 0; k < 3; k++) q[k] = a[k] * u + b[k] * v + c[k] * w;
	};
	if (d1 <= 0 && d2 <= 0) return set(1, 0, 0);
	double bp[3] = { p[0] - b[0], p[1] - b[1], p[2] - b[2] };
	double d3 = dot3(ab, bp), d4 = dot3(ac, bp);
	if (d3 >= 0 && d4 <= d3) return set(0, 1, 0);
	double vc = d1 * d4 - d3 * d2;
	if (vc <= 0 && d1 >= 0 && d3 <= 0) {
		double v = d1 / (d1 - d3);
		return set(1 - v, v, 0);
	}
	double cp[3] = { p[0] - c[0], p[1] - c[1], p[2] - c[2] };
	double d5 = dot3(ab, cp), d6 = dot3(ac, cp);
	if (d6 >= 0 && d5 <= d6) return set(0, 0, 1);
	double vb = d5 * d2 - d1 * d6;
	if (vb <= 0 && d2 >= 0 && d6 <= 0) {
		double w = d2 / (d2 - d6);
		return set(1 - w, 0, w);
	}
	double va = d3 * d6 - d5 * d4;
	if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
		double w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
		return set(0, 1 - w, w);
	}
	double den = 1.0 / (va + vb + vc);
	double v = vb * den, w = vc * den;
	set(1 - v - w, v, w);
}

inline double box_d2(const double *lo, const double *hi, const double *p) {
	double s = 0;
	for (int k = 0; k < 3; k++) {
		double e = 0;
		if (p[k] < lo[k]) e = lo[k] - p[k];
		else if (p[k] > hi[k]) e = p[k] - hi[k];
		s += e * e;
	}
	return s;
}

} // namespace

// ------------------------------------------------------------------------------------------------ BVH
int KineRetopoNative::build_node(int lo, int hi) {
	BNode nd;
	for (int k = 0; k < 3; k++) {
		nd.lo[k] = 1e300;
		nd.hi[k] = -1e300;
	}
	double clo[3] = { 1e300, 1e300, 1e300 }, chi[3] = { -1e300, -1e300, -1e300 };
	for (int i = lo; i < hi; i++) {
		int t = order[i];
		double cen[3] = { 0, 0, 0 };
		for (int c = 0; c < 3; c++) {
			const double *v = &sv[st[t * 3 + c] * 3];
			for (int k = 0; k < 3; k++) {
				nd.lo[k] = std::min(nd.lo[k], v[k]);
				nd.hi[k] = std::max(nd.hi[k], v[k]);
				cen[k] += v[k] / 3.0;
			}
		}
		for (int k = 0; k < 3; k++) {
			clo[k] = std::min(clo[k], cen[k]);
			chi[k] = std::max(chi[k], cen[k]);
		}
	}
	int idx = (int)bvh.size();
	bvh.push_back(nd);
	if (hi - lo <= 4) {
		bvh[idx].start = lo;
		bvh[idx].count = hi - lo;
		return idx;
	}
	int ax = 0;
	double ext = chi[0] - clo[0];
	for (int k = 1; k < 3; k++) {
		if (chi[k] - clo[k] > ext) {
			ext = chi[k] - clo[k];
			ax = k;
		}
	}
	auto cen_ax = [&](int t) {
		double s = 0;
		for (int c = 0; c < 3; c++) s += sv[st[t * 3 + c] * 3 + ax];
		return s / 3.0;
	};
	int mid = (lo + hi) / 2;
	std::nth_element(order.begin() + lo, order.begin() + mid, order.begin() + hi, [&](int a, int b) { return cen_ax(a) < cen_ax(b); });
	int l = build_node(lo, mid);
	int r = build_node(mid, hi);
	bvh[idx].l = l;
	bvh[idx].r = r;
	bvh[idx].count = 0;
	return idx;
}

void KineRetopoNative::set_source(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris) {
	int nv = p_verts.size(), nt = p_tris.size() / 3;
	sv.assign((size_t)nv * 3, 0.0);
	for (int i = 0; i < nv; i++) {
		sv[i * 3] = p_verts[i].x;
		sv[i * 3 + 1] = p_verts[i].y;
		sv[i * 3 + 2] = p_verts[i].z;
	}
	st.assign((size_t)nt * 3, 0);
	for (int i = 0; i < nt * 3; i++) st[i] = p_tris[i];
	svn.assign((size_t)nv * 3, 0.0);
	for (int t = 0; t < nt; t++) {
		const double *a = &sv[st[t * 3] * 3];
		const double *b = &sv[st[t * 3 + 1] * 3];
		const double *c = &sv[st[t * 3 + 2] * 3];
		double e1[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] }, e2[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
		double n[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
		for (int k = 0; k < 3; k++) {
			for (int c2 = 0; c2 < 3; c2++) svn[st[t * 3 + c2] * 3 + k] += n[k];
		}
	}
	for (int i = 0; i < nv; i++) {
		double *n = &svn[i * 3];
		double l = std::sqrt(dot3(n, n));
		if (l > 1e-300) {
			n[0] /= l;
			n[1] /= l;
			n[2] /= l;
		}
	}
	order.resize(nt);
	for (int i = 0; i < nt; i++) order[i] = i;
	bvh.clear();
	if (nt > 0) {
		bvh.reserve((size_t)nt);
		build_node(0, nt);
	}
}

bool KineRetopoNative::has_source() const {
	return !bvh.empty();
}

double KineRetopoNative::closest(const double *p, int hint, int &tri, double *q, double *bary) const {
	double best = 1e300;
	tri = -1;
	auto test = [&](int t) {
		double qq[3], bb[3];
		tri_closest(p, &sv[st[t * 3] * 3], &sv[st[t * 3 + 1] * 3], &sv[st[t * 3 + 2] * 3], qq, bb);
		double d[3] = { p[0] - qq[0], p[1] - qq[1], p[2] - qq[2] };
		double d2 = dot3(d, d);
		if (d2 < best) {
			best = d2;
			tri = t;
			q[0] = qq[0];
			q[1] = qq[1];
			q[2] = qq[2];
			bary[0] = bb[0];
			bary[1] = bb[1];
			bary[2] = bb[2];
		}
	};
	if (hint >= 0) test(hint);
	int stack[128];
	int sp = 0;
	stack[sp++] = 0;
	while (sp > 0) {
		const BNode &nd = bvh[stack[--sp]];
		if (box_d2(nd.lo, nd.hi, p) >= best) continue;
		if (nd.l < 0) {
			for (int i = nd.start; i < nd.start + nd.count; i++) test(order[i]);
		} else {
			double dl = box_d2(bvh[nd.l].lo, bvh[nd.l].hi, p), dr = box_d2(bvh[nd.r].lo, bvh[nd.r].hi, p);
			if (dl < dr) {
				stack[sp++] = nd.r;
				stack[sp++] = nd.l;
			} else {
				stack[sp++] = nd.l;
				stack[sp++] = nd.r;
			}
		}
	}
	return std::sqrt(best);
}

void KineRetopoNative::normal_at(int tri, const double *bary, double *n) const {
	for (int k = 0; k < 3; k++) {
		n[k] = svn[st[tri * 3] * 3 + k] * bary[0] + svn[st[tri * 3 + 1] * 3 + k] * bary[1] + svn[st[tri * 3 + 2] * 3 + k] * bary[2];
	}
	double l = std::sqrt(dot3(n, n));
	if (l > 1e-300) {
		n[0] /= l;
		n[1] /= l;
		n[2] /= l;
	}
}

// ------------------------------------------------------------------------------------------------ API
int KineRetopoNative::version() {
	return 1;
}

Dictionary KineRetopoNative::plan(const PackedInt32Array &p_counts) {
	return plan_dict(make_plan(to_vi(p_counts)));
}

Dictionary KineRetopoNative::fill(const Array &p_sides) {
	return fill_impl(p_sides);
}

Dictionary KineRetopoNative::project(const PackedFloat64Array &p_pts) const {
	Dictionary out;
	int n = p_pts.size() / 3;
	PackedFloat64Array pts, nor, dist;
	PackedInt32Array tris;
	pts.resize(n * 3);
	nor.resize(n * 3);
	dist.resize(n);
	tris.resize(n);
	if (!has_source()) {
		out["pts"] = p_pts;
		return out;
	}
	int hint = -1;
	for (int i = 0; i < n; i++) {
		double p[3] = { p_pts[i * 3], p_pts[i * 3 + 1], p_pts[i * 3 + 2] }, q[3], bary[3], nn[3];
		int t;
		double d = closest(p, hint, t, q, bary);
		hint = t;
		normal_at(t, bary, nn);
		for (int k = 0; k < 3; k++) {
			pts.set(i * 3 + k, q[k]);
			nor.set(i * 3 + k, nn[k]);
		}
		dist.set(i, d);
		tris.set(i, t);
	}
	out["pts"] = pts;
	out["normals"] = nor;
	out["dist"] = dist;
	out["tris"] = tris;
	return out;
}

Dictionary KineRetopoNative::solve_patch(const Array &p_sides, int p_iters) const {
	auto t0 = std::chrono::steady_clock::now();
	Dictionary out = fill_impl(p_sides);
	if (!(bool)out["ok"] || !has_source()) {
		return out;
	}
	PackedFloat64Array pv = out["verts"];
	PackedInt32Array qv = out["quads"];
	int nring = out["nring"];
	int nv = pv.size() / 3;
	std::vector<double> P(pv.size());
	for (int i = 0; i < pv.size(); i++) P[i] = pv[i];
	std::vector<double> N((size_t)nv * 3, 0.0);
	VI hint(nv, -1);
	for (int v = nring; v < nv; v++) {
		double q[3], bary[3], nn[3];
		int t;
		closest(&P[v * 3], -1, t, q, bary);
		normal_at(t, bary, nn);
		hint[v] = t;
		for (int k = 0; k < 3; k++) {
			P[v * 3 + k] = q[k];
			N[v * 3 + k] = nn[k];
		}
	}
	// neighbours (each edge of each quad once per vertex)
	std::vector<VI> nb(nv);
	for (int f = 0; f < qv.size() / 4; f++) {
		for (int k = 0; k < 4; k++) {
			int a = qv[f * 4 + k], b = qv[f * 4 + (k + 1) % 4];
			nb[a].push_back(b);
			nb[b].push_back(a);
		}
	}
	for (int v = 0; v < nv; v++) {
		std::sort(nb[v].begin(), nb[v].end());
		nb[v].erase(std::unique(nb[v].begin(), nb[v].end()), nb[v].end());
	}
	for (int it = 0; it < p_iters; it++) {
		for (int v = nring; v < nv; v++) {
			if (nb[v].empty()) continue;
			double avg[3] = { 0, 0, 0 };
			for (int w : nb[v]) {
				for (int k = 0; k < 3; k++) avg[k] += P[w * 3 + k];
			}
			double inv = 1.0 / double(nb[v].size());
			double dd[3];
			for (int k = 0; k < 3; k++) dd[k] = avg[k] * inv - P[v * 3 + k];
			double dn = dot3(dd, &N[v * 3]);
			double np[3];
			for (int k = 0; k < 3; k++) np[k] = P[v * 3 + k] + dd[k] - N[v * 3 + k] * dn;
			double q[3], bary[3], nn[3];
			int t;
			closest(np, hint[v], t, q, bary);
			normal_at(t, bary, nn);
			hint[v] = t;
			for (int k = 0; k < 3; k++) {
				P[v * 3 + k] = q[k];
				N[v * 3 + k] = nn[k];
			}
		}
	}
	for (int i = 0; i < pv.size(); i++) pv.set(i, P[i]);
	out["verts"] = pv;
	out["ms"] = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	return out;
}

Dictionary KineRetopoNative::solve_patches(const Array &p_patches, int p_iters) const {
	auto t0 = std::chrono::steady_clock::now();
	Array res;
	for (int i = 0; i < p_patches.size(); i++) {
		res.push_back(solve_patch(p_patches[i], p_iters));
	}
	Dictionary out;
	out["patches"] = res;
	out["ms"] = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	return out;
}

void KineRetopoNative::_bind_methods() {
	ClassDB::bind_static_method("KineRetopoNative", D_METHOD("version"), &KineRetopoNative::version);
	ClassDB::bind_static_method("KineRetopoNative", D_METHOD("plan", "counts"), &KineRetopoNative::plan);
	ClassDB::bind_static_method("KineRetopoNative", D_METHOD("fill", "sides"), &KineRetopoNative::fill);
	ClassDB::bind_method(D_METHOD("set_source", "verts", "tris"), &KineRetopoNative::set_source);
	ClassDB::bind_method(D_METHOD("has_source"), &KineRetopoNative::has_source);
	ClassDB::bind_method(D_METHOD("project", "pts"), &KineRetopoNative::project);
	ClassDB::bind_method(D_METHOD("solve_patch", "sides", "iters"), &KineRetopoNative::solve_patch);
	ClassDB::bind_method(D_METHOD("solve_patches", "patches", "iters"), &KineRetopoNative::solve_patches);
}
