#include "kine_tpaint_native.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <thread>

using namespace godot;

int KineTPaintNative::version() { return 2; }

static inline int wrapi(int a, int n) {
	int r = a % n;
	return r < 0 ? r + n : r;
}

// barycentrics of a texel centre in the uv triangle (inv_den precomputed in setup)
static inline void bary3(const double uv[3][2], double inv, double px, double py, double *b) {
	double b1 = ((px - uv[0][0]) * (uv[2][1] - uv[0][1]) - (uv[2][0] - uv[0][0]) * (py - uv[0][1])) * inv;
	double b2 = ((uv[1][0] - uv[0][0]) * (py - uv[0][1]) - (px - uv[0][0]) * (uv[1][1] - uv[0][1])) * inv;
	b[0] = 1.0 - b1 - b2;
	b[1] = b1;
	b[2] = b2;
}

void KineTPaintNative::setup(const PackedVector3Array &p_pos, const PackedVector2Array &p_uv, int p_size) {
	size = p_size;
	int nt = p_pos.size() / 3;
	tris.assign(nt, Tri());
	for (int t = 0; t < nt; t++) {
		Tri &T = tris[t];
		for (int j = 0; j < 3; j++) {
			Vector3 v = p_pos[t * 3 + j];
			T.p[j][0] = v.x;
			T.p[j][1] = v.y;
			T.p[j][2] = v.z;
			Vector2 u = p_uv[t * 3 + j];
			T.uv[j][0] = (double)u.x * size;
			T.uv[j][1] = (double)u.y * size;
		}
		double den = (T.uv[1][0] - T.uv[0][0]) * (T.uv[2][1] - T.uv[0][1]) - (T.uv[2][0] - T.uv[0][0]) * (T.uv[1][1] - T.uv[0][1]);
		T.ok = std::fabs(den) >= 1e-12;
		if (T.ok) {
			T.inv_den = 1.0 / den;
			for (int i = 0; i < 3; i++) {
				int j = (i + 1) % 3, k = (i + 2) % 3;
				double L = std::sqrt((T.uv[k][0] - T.uv[j][0]) * (T.uv[k][0] - T.uv[j][0]) + (T.uv[k][1] - T.uv[j][1]) * (T.uv[k][1] - T.uv[j][1]));
				T.h[i] = std::fabs(den) / std::max(L, 1e-12);
			}
		}
	}
	size_t n = (size_t)size * size;
	tex.assign(n * 4, 255);
	cov.assign(n, 0);
	stamped.assign(n, 0);
	smark.assign(n, 0);
	undo_s.clear();
	redo_s.clear();
	cur.clear();
	in_stroke = false;
	for (const Tri &T : tris) {
		if (!T.ok) {
			continue;
		}
		double mnx = 1e300, mny = 1e300, mxx = -1e300, mxy = -1e300;
		for (int j = 0; j < 3; j++) {
			mnx = std::min(mnx, T.uv[j][0]);
			mxx = std::max(mxx, T.uv[j][0]);
			mny = std::min(mny, T.uv[j][1]);
			mxy = std::max(mxy, T.uv[j][1]);
		}
		for (int iy = (int)std::floor(mny); iy <= (int)std::ceil(mxy); iy++) {
			for (int ix = (int)std::floor(mnx); ix <= (int)std::ceil(mxx); ix++) {
				double b[3];
				bary3(T.uv, T.inv_den, ix + 0.5, iy + 0.5, b);
				if (b[0] >= -1e-9 && b[1] >= -1e-9 && b[2] >= -1e-9) {
					cov[(size_t)wrapi(iy, size) * size + wrapi(ix, size)] = 1;
				}
			}
		}
	}
}

struct SV {
	double x, y, w; // screen px, clip w
	double cx, cy; // clip x, y
};

struct TCand {
	int32_t idx;
	double w;
};

int KineTPaintNative::stamp(const PackedFloat64Array &p_mvp, const Vector3 &p_cam, int p_w, int p_h, double cx, double cy, double R, const Color &p_col, double strength, double hardness, int pad, bool cull, bool occ) {
	if (size <= 0 || p_mvp.size() < 16 || R <= 0.0) {
		return 0;
	}
	const double *M = p_mvp.ptr();
	const double cam[3] = { p_cam.x, p_cam.y, p_cam.z };
	const int nt = (int)tris.size();
	std::vector<SV> sv((size_t)nt * 3);
	std::vector<uint8_t> okv(nt, 0), front(nt, 0);
	const double rx0 = cx - R - 4.0, rx1 = cx + R + 4.0, ry0 = cy - R - 4.0, ry1 = cy + R + 4.0;
	for (int t = 0; t < nt; t++) {
		const Tri &T = tris[t];
		bool all = true;
		double mnx = 1e300, mny = 1e300, mxx = -1e300, mxy = -1e300;
		for (int j = 0; j < 3; j++) {
			SV &s = sv[t * 3 + j];
			const double *P = T.p[j];
			s.cx = M[0] * P[0] + M[4] * P[1] + M[8] * P[2] + M[12];
			s.cy = M[1] * P[0] + M[5] * P[1] + M[9] * P[2] + M[13];
			s.w = M[3] * P[0] + M[7] * P[1] + M[11] * P[2] + M[15];
			if (s.w <= 1e-6) {
				all = false;
				break;
			}
			s.x = (s.cx / s.w * 0.5 + 0.5) * p_w;
			s.y = (0.5 - s.cy / s.w * 0.5) * p_h;
			mnx = std::min(mnx, s.x);
			mxx = std::max(mxx, s.x);
			mny = std::min(mny, s.y);
			mxy = std::max(mxy, s.y);
		}
		if (!all || !T.ok) {
			continue;
		}
		double e1[3], e2[3];
		for (int k = 0; k < 3; k++) {
			e1[k] = T.p[1][k] - T.p[0][k];
			e2[k] = T.p[2][k] - T.p[0][k];
		}
		double n0 = e1[1] * e2[2] - e1[2] * e2[1], n1 = e1[2] * e2[0] - e1[0] * e2[2], n2 = e1[0] * e2[1] - e1[1] * e2[0];
		front[t] = (n0 * (cam[0] - T.p[0][0]) + n1 * (cam[1] - T.p[0][1]) + n2 * (cam[2] - T.p[0][2])) > 0.0;
		okv[t] = (mxx >= rx0 && mnx <= rx1 && mxy >= ry0 && mny <= ry1);
	}
	// depth buffer of the front faces over the disk's pixel box
	int dx0 = std::max(0, (int)std::floor(cx - R) - 1), dx1 = std::min(p_w - 1, (int)std::ceil(cx + R) + 1);
	int dy0 = std::max(0, (int)std::floor(cy - R) - 1), dy1 = std::min(p_h - 1, (int)std::ceil(cy + R) + 1);
	int dw = std::max(0, dx1 - dx0 + 1), dh = std::max(0, dy1 - dy0 + 1);
	const double INF = 1e300;
	if (occ && dw > 0 && dh > 0) {
		depth.assign((size_t)dw * dh, INF);
		for (int t = 0; t < nt; t++) {
			if (!okv[t] || !front[t]) {
				continue;
			}
			const SV *s = &sv[t * 3];
			double area = (s[1].x - s[0].x) * (s[2].y - s[0].y) - (s[2].x - s[0].x) * (s[1].y - s[0].y);
			if (std::fabs(area) < 1e-12) {
				continue;
			}
			double ia = 1.0 / area;
			double mnx = std::min(s[0].x, std::min(s[1].x, s[2].x)), mxx = std::max(s[0].x, std::max(s[1].x, s[2].x));
			double mny = std::min(s[0].y, std::min(s[1].y, s[2].y)), mxy = std::max(s[0].y, std::max(s[1].y, s[2].y));
			int x0 = std::max(dx0, (int)std::floor(mnx)), x1 = std::min(dx1, (int)std::ceil(mxx));
			int y0 = std::max(dy0, (int)std::floor(mny)), y1 = std::min(dy1, (int)std::ceil(mxy));
			for (int y = y0; y <= y1; y++) {
				for (int x = x0; x <= x1; x++) {
					double px = x + 0.5, py = y + 0.5;
					double l0 = ((s[1].x - px) * (s[2].y - py) - (s[2].x - px) * (s[1].y - py)) * ia;
					double l1 = ((s[2].x - px) * (s[0].y - py) - (s[0].x - px) * (s[2].y - py)) * ia;
					double l2 = 1.0 - l0 - l1;
					if (l0 < -1e-9 || l1 < -1e-9 || l2 < -1e-9) {
						continue;
					}
					double w = 1.0 / (l0 / s[0].w + l1 / s[1].w + l2 / s[2].w);
					double &d = depth[(size_t)(y - dy0) * dw + (x - dx0)];
					if (w < d) {
						d = w;
					}
				}
			}
		}
	}
	const double col[4] = { p_col.r * 255.0, p_col.g * 255.0, p_col.b * 255.0, p_col.a * 255.0 };
	const double R2 = R * R;
	std::vector<int> cand;
	for (int t = 0; t < nt; t++) {
		if (okv[t] && (!cull || front[t])) {
			cand.push_back(t);
		}
	}
	struct Local {
		std::vector<Entry> jr;
		std::vector<TCand> gut;
		std::vector<int32_t> touched;
		int written = 0;
	};
	int nth = cand.size() < 48 ? 1 : (int)std::min(8u, std::max(1u, std::thread::hardware_concurrency()));
	std::vector<Local> loc(nth);
	const bool jr_on = in_stroke;
	auto work = [&](int ti) {
		Local &L = loc[ti];
		size_t a = cand.size() * ti / nth, b = cand.size() * (ti + 1) / nth;
		for (size_t ci = a; ci < b; ci++) {
			const Tri &T = tris[cand[ci]];
			const SV *s = &sv[cand[ci] * 3];
			double mnx = std::min(T.uv[0][0], std::min(T.uv[1][0], T.uv[2][0])), mxx = std::max(T.uv[0][0], std::max(T.uv[1][0], T.uv[2][0]));
			double mny = std::min(T.uv[0][1], std::min(T.uv[1][1], T.uv[2][1])), mxy = std::max(T.uv[0][1], std::max(T.uv[1][1], T.uv[2][1]));
			for (int iy = (int)std::floor(mny) - pad; iy <= (int)std::ceil(mxy) + pad; iy++) {
				for (int ix = (int)std::floor(mnx) - pad; ix <= (int)std::ceil(mxx) + pad; ix++) {
					double bb[3];
					bary3(T.uv, T.inv_den, ix + 0.5, iy + 0.5, bb);
					bool inside = bb[0] >= -1e-9 && bb[1] >= -1e-9 && bb[2] >= -1e-9;
					size_t idx = (size_t)wrapi(iy, size) * size + wrapi(ix, size);
					if (!inside) {
						if (pad <= 0 || cov[idx]) {
							continue;
						}
						if (std::min(bb[0] * T.h[0], std::min(bb[1] * T.h[1], bb[2] * T.h[2])) <= -(double)pad) {
							continue;
						}
					} else if (stamped[idx]) {
						continue;
					}
					double cw = bb[0] * s[0].w + bb[1] * s[1].w + bb[2] * s[2].w;
					if (cw <= 1e-6) {
						continue;
					}
					double ccx = bb[0] * s[0].cx + bb[1] * s[1].cx + bb[2] * s[2].cx;
					double ccy = bb[0] * s[0].cy + bb[1] * s[1].cy + bb[2] * s[2].cy;
					double sx = (ccx / cw * 0.5 + 0.5) * p_w;
					double sy = (0.5 - ccy / cw * 0.5) * p_h;
					double dxx = sx - cx, dyy = sy - cy;
					double d2 = dxx * dxx + dyy * dyy;
					if (d2 >= R2) {
						continue;
					}
					double tt = std::sqrt(d2) / R, f;
					if (tt <= hardness) {
						f = 1.0;
					} else {
						double u = (tt - hardness) / (1.0 - hardness);
						f = 1.0 - (3.0 * u * u - 2.0 * u * u * u);
					}
					double w = strength * f;
					if (w <= 0.0) {
						continue;
					}
					if (occ && dw > 0) {
						int px = std::min(std::max((int)std::floor(sx), dx0), dx1), py = std::min(std::max((int)std::floor(sy), dy0), dy1);
						double dv = depth[(size_t)(py - dy0) * dw + (px - dx0)];
						if (dv < INF && cw > dv * (1.0 + (inside ? 0.02 : 0.05)) + 1e-9) {
							continue;
						}
					}
					if (!inside) {
						L.gut.push_back({ (int32_t)idx, w });
						continue;
					}
					stamped[idx] = 1;
					L.touched.push_back((int32_t)idx);
					uint8_t *o = &tex[idx * 4];
					if (jr_on) {
						Entry e;
						e.idx = (int32_t)idx;
						std::memcpy(e.o, o, 4);
						L.jr.push_back(e);
					}
					for (int c = 0; c < 4; c++) {
						double v = o[c] * (1.0 - w) + col[c] * w;
						int iv = (int)std::floor(v + 0.5);
						o[c] = (uint8_t)std::min(255, std::max(0, iv));
					}
					L.written++;
				}
			}
		}
	};
	if (nth == 1) {
		work(0);
	} else {
		std::vector<std::thread> th;
		for (int i = 1; i < nth; i++) {
			th.emplace_back(work, i);
		}
		work(0);
		for (auto &x : th) {
			x.join();
		}
	}
	// seam bleed texels (outside every island): serial, in triangle order, the first one wins
	int written = 0;
	for (Local &L : loc) {
		written += L.written;
		for (const TCand &g : L.gut) {
			if (stamped[g.idx]) {
				continue;
			}
			stamped[g.idx] = 1;
			L.touched.push_back(g.idx);
			uint8_t *o = &tex[(size_t)g.idx * 4];
			if (jr_on) {
				Entry e;
				e.idx = g.idx;
				std::memcpy(e.o, o, 4);
				L.jr.push_back(e);
			}
			for (int c = 0; c < 4; c++) {
				double v = o[c] * (1.0 - g.w) + col[c] * g.w;
				int iv = (int)std::floor(v + 0.5);
				o[c] = (uint8_t)std::min(255, std::max(0, iv));
			}
			written++;
		}
		for (int32_t i : L.touched) {
			stamped[i] = 0;
		}
		for (const Entry &e : L.jr) {
			if (!smark[e.idx]) {
				smark[e.idx] = 1;
				touched.push_back(e.idx);
				cur.push_back(e);
			}
		}
	}
	return written;
}

void KineTPaintNative::begin_stroke() {
	cur.clear();
	touched.clear();
	in_stroke = true;
}

int KineTPaintNative::end_stroke() {
	in_stroke = false;
	for (int32_t i : touched) {
		smark[i] = 0;
	}
	touched.clear();
	for (Entry &e : cur) {
		std::memcpy(e.n, &tex[(size_t)e.idx * 4], 4);
	}
	int n = (int)cur.size();
	if (n > 0) {
		undo_s.push_back(cur);
		redo_s.clear();
	}
	cur.clear();
	return n;
}

bool KineTPaintNative::undo() {
	if (undo_s.empty()) {
		return false;
	}
	std::vector<Entry> e = undo_s.back();
	undo_s.pop_back();
	for (const Entry &x : e) {
		std::memcpy(&tex[(size_t)x.idx * 4], x.o, 4);
	}
	redo_s.push_back(e);
	return true;
}

bool KineTPaintNative::redo() {
	if (redo_s.empty()) {
		return false;
	}
	std::vector<Entry> e = redo_s.back();
	redo_s.pop_back();
	for (const Entry &x : e) {
		std::memcpy(&tex[(size_t)x.idx * 4], x.n, 4);
	}
	undo_s.push_back(e);
	return true;
}

PackedByteArray KineTPaintNative::get_data() const {
	PackedByteArray b;
	b.resize((int64_t)tex.size());
	if (!tex.empty()) {
		std::memcpy(b.ptrw(), tex.data(), tex.size());
	}
	return b;
}

void KineTPaintNative::set_data(const PackedByteArray &p_d) {
	if ((size_t)p_d.size() == tex.size()) {
		std::memcpy(tex.data(), p_d.ptr(), tex.size());
	}
}

PackedByteArray KineTPaintNative::coverage() const {
	PackedByteArray b;
	b.resize((int64_t)cov.size());
	if (!cov.empty()) {
		std::memcpy(b.ptrw(), cov.data(), cov.size());
	}
	return b;
}

void KineTPaintNative::_bind_methods() {
	ClassDB::bind_static_method("KineTPaintNative", D_METHOD("version"), &KineTPaintNative::version);
	ClassDB::bind_method(D_METHOD("setup", "pos", "uv", "size"), &KineTPaintNative::setup);
	ClassDB::bind_method(D_METHOD("stamp", "mvp", "cam", "w", "h", "cx", "cy", "r", "color", "strength", "hardness", "pad", "cull", "occ"), &KineTPaintNative::stamp);
	ClassDB::bind_method(D_METHOD("begin_stroke"), &KineTPaintNative::begin_stroke);
	ClassDB::bind_method(D_METHOD("end_stroke"), &KineTPaintNative::end_stroke);
	ClassDB::bind_method(D_METHOD("undo"), &KineTPaintNative::undo);
	ClassDB::bind_method(D_METHOD("redo"), &KineTPaintNative::redo);
	ClassDB::bind_method(D_METHOD("get_data"), &KineTPaintNative::get_data);
	ClassDB::bind_method(D_METHOD("set_data", "d"), &KineTPaintNative::set_data);
	ClassDB::bind_method(D_METHOD("coverage"), &KineTPaintNative::coverage);
}
