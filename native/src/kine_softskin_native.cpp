#include "kine_softskin_native.h"

#include <cmath>
#include <cstring>
#include <vector>

using namespace godot;

namespace {

struct V3 {
	double x = 0, y = 0, z = 0;
};
inline V3 operator+(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 operator-(V3 a, V3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 operator*(V3 a, double s) { return { a.x * s, a.y * s, a.z * s }; }
inline double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(V3 a, V3 b) { return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x }; }
inline double len(V3 a) { return std::sqrt(dot(a, a)); }
inline V3 mk(const Vector3 &v) { return { v.x, v.y, v.z }; }

// the octahedral encoding of the engine's mesh data builder (Vector3::octahedron_encode, then uint16 of x 65535)
inline void oct(V3 n, double &ox, double &oy) {
	const double s = std::fabs(n.x) + std::fabs(n.y) + std::fabs(n.z);
	if (s > 0.0) {
		n.x /= s;
		n.y /= s;
		n.z /= s;
	}
	double a, b;
	if (n.z >= 0.0) {
		a = n.x;
		b = n.y;
	} else {
		a = (1.0 - std::fabs(n.y)) * (n.x >= 0.0 ? 1.0 : -1.0);
		b = (1.0 - std::fabs(n.x)) * (n.y >= 0.0 ? 1.0 : -1.0);
	}
	ox = a * 0.5 + 0.5;
	oy = b * 0.5 + 0.5;
}
inline uint16_t u16(double v) {
	v *= 65535.0;
	if (v < 0.0) v = 0.0;
	if (v > 65535.0) v = 65535.0;
	return (uint16_t)v;
}
inline void put_normal(uint8_t *dst, V3 n) {
	double a, b;
	oct(n, a, b);
	uint16_t w[2] = { u16(a), u16(b) };
	std::memcpy(dst, w, 4);
}
inline void put_tangent(uint8_t *dst, V3 t, double sign) {
	double a, b;
	oct(t, a, b);
	if (b < 1.0 / 32767.0) b = 1.0 / 32767.0;
	b = b * 0.5 + 0.5;
	b = sign >= 0.0 ? b : 1.0 - b;
	uint16_t w[2] = { u16(a), u16(b) };
	std::memcpy(dst, w, 4);
}
// v turned by the shortest arc from the unit a to the unit b
inline V3 arc(V3 v, V3 a, V3 b) {
	V3 k = cross(a, b);
	const double s = len(k);
	const double c = dot(a, b);
	if (s < 1e-12) return v;
	k = k * (1.0 / s);
	return v * c + cross(k, v) * s + k * (dot(k, v) * (1.0 - c));
}
inline double smooth(double a, double b, double x) {
	double t = (x - a) / (b - a);
	t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
	return t * t * (3.0 - 2.0 * t);
}
} // namespace

void KineSoftSkinNative::_bind_methods() {
	ClassDB::bind_static_method("KineSoftSkinNative", D_METHOD("version"), &KineSoftSkinNative::version);
	ClassDB::bind_static_method("KineSoftSkinNative", D_METHOD("topo", "idx", "nv", "cand"), &KineSoftSkinNative::topo);
	ClassDB::bind_static_method("KineSoftSkinNative", D_METHOD("encode_nt", "nrm", "tan"), &KineSoftSkinNative::encode_nt);
	ClassDB::bind_static_method("KineSoftSkinNative",
			D_METHOD("deform", "verts", "bones", "weights", "per", "cand", "mats", "gt", "regs", "disps", "strength", "idx", "nrm", "tan", "nt0", "v1", "t2", "do_nrm"),
			&KineSoftSkinNative::deform);
}

int KineSoftSkinNative::version() { return 1; }

Dictionary KineSoftSkinNative::topo(const PackedInt32Array &p_idx, int p_nv, const PackedInt32Array &p_cand) {
	std::vector<uint8_t> cf(p_nv > 0 ? p_nv : 1, 0), v1f(p_nv > 0 ? p_nv : 1, 0);
	for (int i = 0; i < p_cand.size(); i++) {
		if (p_cand[i] >= 0 && p_cand[i] < p_nv) cf[p_cand[i]] = 1;
	}
	const int nt = p_idx.size() / 3;
	for (int t = 0; t < nt; t++) {
		const int a = p_idx[t * 3], b = p_idx[t * 3 + 1], c = p_idx[t * 3 + 2];
		if (a >= p_nv || b >= p_nv || c >= p_nv) continue;
		if (cf[a] || cf[b] || cf[c]) v1f[a] = v1f[b] = v1f[c] = 1;
	}
	PackedInt32Array v1, t2;
	for (int i = 0; i < p_nv; i++) {
		if (v1f[i]) v1.append(i);
	}
	for (int t = 0; t < nt; t++) {
		const int a = p_idx[t * 3], b = p_idx[t * 3 + 1], c = p_idx[t * 3 + 2];
		if (a >= p_nv || b >= p_nv || c >= p_nv) continue;
		if (v1f[a] || v1f[b] || v1f[c]) t2.append(t);
	}
	Dictionary d;
	d["v1"] = v1;
	d["t2"] = t2;
	return d;
}

PackedByteArray KineSoftSkinNative::encode_nt(const PackedVector3Array &p_nrm, const PackedFloat32Array &p_tan) {
	const int n = p_nrm.size();
	const bool has_t = n > 0 && p_tan.size() >= n * 4;
	const int stride = has_t ? 8 : 4;
	PackedByteArray out;
	out.resize((int64_t)n * stride);
	uint8_t *o = out.ptrw();
	for (int i = 0; i < n; i++) {
		put_normal(o + (int64_t)i * stride, mk(p_nrm[i]));
		if (has_t) put_tangent(o + (int64_t)i * stride + 4, { p_tan[i * 4], p_tan[i * 4 + 1], p_tan[i * 4 + 2] }, p_tan[i * 4 + 3]);
	}
	return out;
}

Dictionary KineSoftSkinNative::deform(const PackedVector3Array &p_verts, const PackedInt32Array &p_bones, const PackedFloat32Array &p_weights, int p_per,
		const PackedInt32Array &p_cand, const Array &p_mats, const Transform3D &p_gt, const PackedFloat64Array &p_regs, const PackedVector3Array &p_disps,
		double p_strength, const PackedInt32Array &p_idx, const PackedVector3Array &p_nrm, const PackedFloat32Array &p_tan, const PackedByteArray &p_nt0,
		const PackedInt32Array &p_v1, const PackedInt32Array &p_t2, bool p_do_nrm) {
	Dictionary res;
	const int n = p_verts.size();
	const int nc = p_cand.size();
	const int nreg = p_regs.size() / 19;
	res["moved"] = 0;
	if (n == 0 || nc == 0 || nreg == 0 || p_per < 1 || p_bones.size() < n * p_per || p_weights.size() < n * p_per) return res;
	// the skinning matrices as columns x, y, z, origin
	const int nb = p_mats.size();
	std::vector<double> mm((size_t)nb * 12);
	for (int b = 0; b < nb; b++) {
		const Transform3D t = p_mats[b];
		for (int c = 0; c < 3; c++)
			for (int r = 0; r < 3; r++) mm[b * 12 + c * 3 + r] = t.basis.rows[r][c];
		mm[b * 12 + 9] = t.origin.x;
		mm[b * 12 + 10] = t.origin.y;
		mm[b * 12 + 11] = t.origin.z;
	}
	double g[3][3];
	for (int r = 0; r < 3; r++)
		for (int c = 0; c < 3; c++) g[r][c] = p_gt.basis.rows[r][c];
	const double go[3] = { p_gt.origin.x, p_gt.origin.y, p_gt.origin.z };
	double gi[3][3];
	{
		const double det = g[0][0] * (g[1][1] * g[2][2] - g[1][2] * g[2][1]) - g[0][1] * (g[1][0] * g[2][2] - g[1][2] * g[2][0]) + g[0][2] * (g[1][0] * g[2][1] - g[1][1] * g[2][0]);
		if (std::fabs(det) < 1e-18) return res;
		const double id = 1.0 / det;
		gi[0][0] = (g[1][1] * g[2][2] - g[1][2] * g[2][1]) * id;
		gi[0][1] = (g[0][2] * g[2][1] - g[0][1] * g[2][2]) * id;
		gi[0][2] = (g[0][1] * g[1][2] - g[0][2] * g[1][1]) * id;
		gi[1][0] = (g[1][2] * g[2][0] - g[1][0] * g[2][2]) * id;
		gi[1][1] = (g[0][0] * g[2][2] - g[0][2] * g[2][0]) * id;
		gi[1][2] = (g[0][2] * g[1][0] - g[0][0] * g[1][2]) * id;
		gi[2][0] = (g[1][0] * g[2][1] - g[1][1] * g[2][0]) * id;
		gi[2][1] = (g[0][1] * g[2][0] - g[0][0] * g[2][1]) * id;
		gi[2][2] = (g[0][0] * g[1][1] - g[0][1] * g[1][0]) * id;
	}
	const Vector3 *vv = p_verts.ptr();
	const int32_t *bo = p_bones.ptr();
	const float *wt = p_weights.ptr();
	const double *rg = p_regs.ptr();
	const Vector3 *dp = p_disps.ptr();
	const int nd = p_disps.size();
	std::vector<V3> newpos(nc);
	std::vector<uint8_t> mv(nc, 0);
	int moved = 0;
	for (int c = 0; c < nc; c++) {
		const int i = p_cand[c];
		if (i < 0 || i >= n) continue;
		double bx[3] = { 0, 0, 0 }, by[3] = { 0, 0, 0 }, bz[3] = { 0, 0, 0 }, bq[3] = { 0, 0, 0 };
		for (int q = 0; q < p_per; q++) {
			const double w = wt[i * p_per + q];
			if (w <= 0.0) continue;
			const int b = bo[i * p_per + q];
			if (b < 0 || b >= nb) continue;
			const double *m = &mm[b * 12];
			for (int r = 0; r < 3; r++) {
				bx[r] += m[r] * w;
				by[r] += m[3 + r] * w;
				bz[r] += m[6 + r] * w;
				bq[r] += m[9 + r] * w;
			}
		}
		const double vx = vv[i].x, vy = vv[i].y, vz = vv[i].z;
		double l[3], wp[3];
		for (int r = 0; r < 3; r++) l[r] = bx[r] * vx + by[r] * vy + bz[r] * vz + bq[r];
		for (int r = 0; r < 3; r++) wp[r] = g[r][0] * l[0] + g[r][1] * l[1] + g[r][2] * l[2] + go[r];
		V3 off;
		for (int ri = 0; ri < nreg; ri++) {
			const double *R = rg + ri * 19;
			const double ux = R[0] * wp[0] + R[1] * wp[1] + R[2] * wp[2] + R[3];
			const double uy = R[4] * wp[0] + R[5] * wp[1] + R[6] * wp[2] + R[7];
			const double uz = R[8] * wp[0] + R[9] * wp[1] + R[10] * wp[2] + R[11];
			const double sx = R[12], sy = R[13], sz = R[14];
			if (ux < 0.0 || uy < 0.0 || uz < 0.0 || ux > sx || uy > sy || uz > sz) continue;
			const int nx_ = (int)R[15], ny_ = (int)R[16], nz_ = (int)R[17];
			const int base = (int)R[18];
			const int nxp = nx_ + 1, nyp = ny_ + 1;
			const double fx = ux / sx * nx_, fy = uy / sy * ny_, fz = uz / sz * nz_;
			int cx = (int)std::floor(fx), cy = (int)std::floor(fy), cz = (int)std::floor(fz);
			if (cx > nx_ - 1) cx = nx_ - 1;
			if (cy > ny_ - 1) cy = ny_ - 1;
			if (cz > nz_ - 1) cz = nz_ - 1;
			const double tx = fx - cx, ty = fy - cy, tz = fz - cz;
			V3 d;
			for (int dz = 0; dz < 2; dz++)
				for (int dy = 0; dy < 2; dy++)
					for (int dx = 0; dx < 2; dx++) {
						const double wg = (dx ? tx : 1.0 - tx) * (dy ? ty : 1.0 - ty) * (dz ? tz : 1.0 - tz);
						const int k = base + ((cz + dz) * nyp + (cy + dy)) * nxp + (cx + dx);
						if (k < 0 || k >= nd) continue;
						d = d + mk(dp[k]) * wg;
					}
			const double fu = ux / sx, fv = uy / sy;
			const double fade = smooth(0.0, 0.25, std::fmin(fu, 1.0 - fu)) * smooth(0.0, 0.25, std::fmin(fv, 1.0 - fv));
			off = off + d * (fade * p_strength);
		}
		if (len(off) <= 1e-9) continue;
		// new = v + bas^-1 (gi off), bas = columns bx by bz
		const double det = bx[0] * (by[1] * bz[2] - by[2] * bz[1]) - by[0] * (bx[1] * bz[2] - bx[2] * bz[1]) + bz[0] * (bx[1] * by[2] - bx[2] * by[1]);
		if (std::fabs(det) <= 1e-12) continue;
		double o2[3];
		const double ov[3] = { off.x, off.y, off.z };
		for (int r = 0; r < 3; r++) o2[r] = gi[r][0] * ov[0] + gi[r][1] * ov[1] + gi[r][2] * ov[2];
		const double id = 1.0 / det;
		const double s0 = (o2[0] * (by[1] * bz[2] - by[2] * bz[1]) - by[0] * (o2[1] * bz[2] - o2[2] * bz[1]) + bz[0] * (o2[1] * by[2] - o2[2] * by[1])) * id;
		const double s1 = (bx[0] * (o2[1] * bz[2] - o2[2] * bz[1]) - o2[0] * (bx[1] * bz[2] - bx[2] * bz[1]) + bz[0] * (bx[1] * o2[2] - bx[2] * o2[1])) * id;
		const double s2 = (bx[0] * (by[1] * o2[2] - by[2] * o2[1]) - by[0] * (bx[1] * o2[2] - bx[2] * o2[1]) + o2[0] * (bx[1] * by[2] - bx[2] * by[1])) * id;
		newpos[c] = { vx + s0, vy + s1, vz + s2 };
		mv[c] = 1;
		moved++;
	}
	res["moved"] = moved;
	if (moved == 0) return res;
	const int stride = (p_nt0.size() > 0) ? (int)(p_nt0.size() / n) : 0;
	PackedByteArray buf;
	buf.resize((int64_t)n * 12 + p_nt0.size());
	uint8_t *ob = buf.ptrw();
	std::memcpy(ob, vv, (size_t)n * 12);
	if (p_nt0.size() > 0) std::memcpy(ob + (size_t)n * 12, p_nt0.ptr(), (size_t)p_nt0.size());
	float *pf = reinterpret_cast<float *>(ob);
	for (int c = 0; c < nc; c++) {
		if (!mv[c]) continue;
		const int i = p_cand[c];
		pf[i * 3] = (float)newpos[c].x;
		pf[i * 3 + 1] = (float)newpos[c].y;
		pf[i * 3 + 2] = (float)newpos[c].z;
	}
	int turned = 0;
	if (p_do_nrm && stride > 0 && p_nrm.size() == n && p_idx.size() >= 3 && p_v1.size() > 0 && p_t2.size() > 0) {
		thread_local std::vector<V3> sa, sb;
		thread_local std::vector<uint8_t> in1;
		if ((int)sa.size() < n) {
			sa.resize(n);
			sb.resize(n);
		}
		if ((int)in1.size() < n) in1.assign(n, 0);
		for (int k = 0; k < p_v1.size(); k++) {
			sa[p_v1[k]] = V3();
			sb[p_v1[k]] = V3();
			in1[p_v1[k]] = 1;
		}
		const int32_t *ix = p_idx.ptr();
		for (int k = 0; k < p_t2.size(); k++) {
			const int t = p_t2[k];
			const int a = ix[t * 3], b = ix[t * 3 + 1], c = ix[t * 3 + 2];
			const V3 va = mk(vv[a]), vb = mk(vv[b]), vc = mk(vv[c]);
			const V3 fo = cross(vb - va, vc - va);
			const V3 da = { pf[a * 3], pf[a * 3 + 1], pf[a * 3 + 2] }, db = { pf[b * 3], pf[b * 3 + 1], pf[b * 3 + 2] }, dc = { pf[c * 3], pf[c * 3 + 1], pf[c * 3 + 2] };
			const V3 fd = cross(db - da, dc - da);
			if (in1[a]) {
				sa[a] = sa[a] + fo;
				sb[a] = sb[a] + fd;
			}
			if (in1[b]) {
				sa[b] = sa[b] + fo;
				sb[b] = sb[b] + fd;
			}
			if (in1[c]) {
				sa[c] = sa[c] + fo;
				sb[c] = sb[c] + fd;
			}
		}
		const bool has_t = stride == 8 && p_tan.size() >= n * 4;
		for (int k = 0; k < p_v1.size(); k++) {
			const int v = p_v1[k];
			in1[v] = 0;
			const double la = len(sa[v]), lb = len(sb[v]);
			if (la < 1e-12 || lb < 1e-12) continue;
			const V3 na = sa[v] * (1.0 / la), nb2 = sb[v] * (1.0 / lb);
			if (len(nb2 - na) <= 1e-9) continue;
			V3 nn = arc(mk(p_nrm[v]), na, nb2);
			const double l = len(nn);
			if (l < 1e-12) continue;
			nn = nn * (1.0 / l);
			put_normal(ob + (size_t)n * 12 + (size_t)v * stride, nn);
			if (has_t) {
				V3 tt = arc({ p_tan[v * 4], p_tan[v * 4 + 1], p_tan[v * 4 + 2] }, na, nb2);
				const double lt = len(tt);
				if (lt > 1e-12) {
					tt = tt * (1.0 / lt);
					put_tangent(ob + (size_t)n * 12 + (size_t)v * stride + 4, tt, p_tan[v * 4 + 3]);
				}
			}
			turned++;
		}
	}
	res["buf"] = buf;
	res["turned"] = turned;
	return res;
}
