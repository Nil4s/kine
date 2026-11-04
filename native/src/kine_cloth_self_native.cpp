#include "kine_cloth_self_native.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>

using namespace godot;

namespace {

const double CELL = 0.05;
const double PAD = 0.004;

struct V3 {
	float x, y, z;
};
inline V3 sub(const V3 &a, const V3 &b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 add(const V3 &a, const V3 &b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 mul(const V3 &a, float s) { return { a.x * s, a.y * s, a.z * s }; }
inline float dot(const V3 &a, const V3 &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline float len(const V3 &a) { return std::sqrt(dot(a, a)); }
inline V3 cross(const V3 &a, const V3 &b) { return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x }; }
inline V3 vmin(const V3 &a, const V3 &b) { return { std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z) }; }
inline V3 vmax(const V3 &a, const V3 &b) { return { std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z) }; }
inline V3 lerp3(const V3 &a, const V3 &b, float w) { return { a.x + (w * (b.x - a.x)), a.y + (w * (b.y - a.y)), a.z + (w * (b.z - a.z)) }; }
inline V3 normalized(const V3 &a) {
	float l2 = dot(a, a);
	if (l2 == 0.0f) return { 0, 0, 0 };
	float l = std::sqrt(l2);
	return { a.x / l, a.y / l, a.z / l };
}
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

V3 tri_bary(const V3 &q, const V3 &a, const V3 &b, const V3 &c) {
	V3 ab = sub(b, a), ac = sub(c, a), ap = sub(q, a);
	float d1 = dot(ab, ap), d2 = dot(ac, ap);
	if (d1 <= 0.0f && d2 <= 0.0f) return { 1, 0, 0 };
	V3 bp = sub(q, b);
	float d3 = dot(ab, bp), d4 = dot(ac, bp);
	if (d3 >= 0.0f && d4 <= d3) return { 0, 1, 0 };
	float vc = d1 * d4 - d3 * d2;
	if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f) {
		float v = d1 / (d1 - d3);
		return { 1.0f - v, v, 0 };
	}
	V3 cq = sub(q, c);
	float d5 = dot(ab, cq), d6 = dot(ac, cq);
	if (d6 >= 0.0f && d5 <= d6) return { 0, 0, 1 };
	float vb = d5 * d2 - d1 * d6;
	if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f) {
		float w = d2 / (d2 - d6);
		return { 1.0f - w, 0, w };
	}
	float va = d3 * d6 - d5 * d4;
	if (va <= 0.0f && (d4 - d3) >= 0.0f && (d5 - d6) >= 0.0f) {
		float w2 = (d4 - d3) / ((d4 - d3) + (d5 - d6));
		return { 0, 1.0f - w2, w2 };
	}
	float den = 1.0f / (va + vb + vc);
	float v2 = vb * den, w3 = vc * den;
	return { 1.0f - v2 - w3, v2, w3 };
}

void closest_segs(const V3 &p1, const V3 &q1, const V3 &p2, const V3 &q2, float &s, float &t) {
	V3 d1 = sub(q1, p1), d2 = sub(q2, p2), r = sub(p1, p2);
	float a = dot(d1, d1), e = dot(d2, d2), f = dot(d2, r);
	s = 0.0f;
	t = 0.0f;
	if (a <= 1e-14f && e <= 1e-14f) return;
	if (a <= 1e-14f) {
		t = clampf(f / e, 0.0f, 1.0f);
	} else {
		float c = dot(d1, r);
		if (e <= 1e-14f) {
			s = clampf(-c / a, 0.0f, 1.0f);
		} else {
			float b = dot(d1, d2);
			float den = a * e - b * b;
			if (den > 1e-14f) s = clampf((b * f - c * e) / den, 0.0f, 1.0f);
			t = (b * s + f) / e;
			if (t < 0.0f) {
				t = 0.0f;
				s = clampf(-c / a, 0.0f, 1.0f);
			} else if (t > 1.0f) {
				t = 1.0f;
				s = clampf((b - c) / a, 0.0f, 1.0f);
			}
		}
	}
}

inline long long cell_key(long long ix, long long iy, long long iz) {
	return (ix & 0x1FFFFF) | ((iy & 0x1FFFFF) << 21) | ((iz & 0x1FFFFF) << 42);
}

inline bool share(const std::vector<int> &T, int ta, int tb) {
	for (int i = 0; i < 3; i++) {
		int v = T[3 * ta + i];
		if (v == T[3 * tb] || v == T[3 * tb + 1] || v == T[3 * tb + 2]) return true;
	}
	return false;
}

bool near_tris(const std::vector<V3> &p, const std::vector<int> &T, int ta, int tb, float lim) {
	if (share(T, ta, tb)) return false;
	int a[3] = { T[3 * ta], T[3 * ta + 1], T[3 * ta + 2] };
	int b[3] = { T[3 * tb], T[3 * tb + 1], T[3 * tb + 2] };
	for (int i = 0; i < 3; i++) {
		V3 w = tri_bary(p[a[i]], p[b[0]], p[b[1]], p[b[2]]);
		V3 cp = add(add(mul(p[b[0]], w.x), mul(p[b[1]], w.y)), mul(p[b[2]], w.z));
		if (len(sub(p[a[i]], cp)) < lim) return true;
		w = tri_bary(p[b[i]], p[a[0]], p[a[1]], p[a[2]]);
		cp = add(add(mul(p[a[0]], w.x), mul(p[a[1]], w.y)), mul(p[a[2]], w.z));
		if (len(sub(p[b[i]], cp)) < lim) return true;
	}
	for (int i = 0; i < 3; i++)
		for (int j = 0; j < 3; j++) {
			V3 p1 = p[a[i]], q1 = p[a[(i + 1) % 3]], p2 = p[b[j]], q2 = p[b[(j + 1) % 3]];
			float s, t;
			closest_segs(p1, q1, p2, q2, s, t);
			if (len(sub(lerp3(p1, q1, s), lerp3(p2, q2, t))) < lim) return true;
		}
	return false;
}

int vert_tri(std::vector<V3> &p, const uint8_t *pinned, float thick, int v, int t0, int t1, int t2) {
	V3 q = p[v];
	V3 bary = tri_bary(q, p[t0], p[t1], p[t2]);
	V3 cp = add(add(mul(p[t0], bary.x), mul(p[t1], bary.y)), mul(p[t2], bary.z));
	V3 d = sub(q, cp);
	float dist = len(d);
	if (dist >= thick) return 0;
	V3 nrm;
	if (dist > 1e-9f) {
		nrm = { d.x / dist, d.y / dist, d.z / dist };
	} else {
		nrm = normalized(cross(sub(p[t1], p[t0]), sub(p[t2], p[t0])));
		if (nrm.x == 0 && nrm.y == 0 && nrm.z == 0) nrm = { 0, 1, 0 };
	}
	float wv = pinned[v] == 1 ? 0.0f : 1.0f;
	float w0 = pinned[t0] == 1 ? 0.0f : 1.0f;
	float w1 = pinned[t1] == 1 ? 0.0f : 1.0f;
	float w2 = pinned[t2] == 1 ? 0.0f : 1.0f;
	double den = wv + w0 * bary.x * bary.x + w1 * bary.y * bary.y + w2 * bary.z * bary.z;
	if (den < 1e-12) return 0;
	float s = (float)((thick - dist) / den);
	p[v] = add(p[v], mul(nrm, s * wv));
	p[t0] = sub(p[t0], mul(nrm, s * w0 * bary.x));
	p[t1] = sub(p[t1], mul(nrm, s * w1 * bary.y));
	p[t2] = sub(p[t2], mul(nrm, s * w2 * bary.z));
	return 1;
}

int edge_edge(std::vector<V3> &p, const uint8_t *pinned, float thick, int a, int b, int c, int d) {
	float s, t;
	closest_segs(p[a], p[b], p[c], p[d], s, t);
	V3 dv = sub(lerp3(p[a], p[b], s), lerp3(p[c], p[d], t));
	float dist = len(dv);
	if (dist >= thick) return 0;
	V3 nrm;
	if (dist > 1e-9f) {
		nrm = { dv.x / dist, dv.y / dist, dv.z / dist };
	} else {
		nrm = normalized(cross(sub(p[b], p[a]), sub(p[d], p[c])));
		if (nrm.x == 0 && nrm.y == 0 && nrm.z == 0) nrm = { 0, 1, 0 };
	}
	float wa = pinned[a] == 1 ? 0.0f : 1.0f, wb = pinned[b] == 1 ? 0.0f : 1.0f;
	float wc = pinned[c] == 1 ? 0.0f : 1.0f, wd = pinned[d] == 1 ? 0.0f : 1.0f;
	double den = wa * (1 - s) * (1 - s) + wb * s * s + wc * (1 - t) * (1 - t) + wd * t * t;
	if (den < 1e-12) return 0;
	float m = (float)((thick - dist) / den);
	p[a] = add(p[a], mul(nrm, m * wa * (1 - s)));
	p[b] = add(p[b], mul(nrm, m * wb * s));
	p[c] = sub(p[c], mul(nrm, m * wc * (1 - t)));
	p[d] = sub(p[d], mul(nrm, m * wd * t));
	return 1;
}

std::vector<V3> read_points(const PackedVector3Array &a) {
	int n = a.size();
	std::vector<V3> p(n);
	const Vector3 *src = a.ptr();
	for (int i = 0; i < n; i++) p[i] = { src[i].x, src[i].y, src[i].z };
	return p;
}

} // namespace

int KineClothSelfNative::version() { return 1; }

void KineClothSelfNative::_bind_methods() {
	ClassDB::bind_static_method("KineClothSelfNative", D_METHOD("version"), &KineClothSelfNative::version);
	ClassDB::bind_method(D_METHOD("setup", "faces", "thick"), &KineClothSelfNative::setup);
	ClassDB::bind_method(D_METHOD("begin", "p"), &KineClothSelfNative::begin);
	ClassDB::bind_method(D_METHOD("solve", "p", "pinned", "first"), &KineClothSelfNative::solve);
	ClassDB::bind_method(D_METHOD("get_contacts"), &KineClothSelfNative::get_contacts);
	ClassDB::bind_method(D_METHOD("get_npairs"), &KineClothSelfNative::get_npairs);
	ClassDB::bind_method(D_METHOD("get_pairs"), &KineClothSelfNative::get_pairs);
}

PackedInt32Array KineClothSelfNative::get_pairs() const {
	PackedInt32Array o;
	o.resize((int64_t)pairs.size());
	for (size_t i = 0; i < pairs.size(); i++) o[(int64_t)i] = pairs[i];
	return o;
}

void KineClothSelfNative::setup(const PackedInt32Array &p_faces, double p_thick) {
	thick = p_thick;
	int n = p_faces.size();
	tris.assign(n, 0);
	for (int i = 0; i < n; i++) tris[i] = p_faces[i];
	int nt = n / 3;
	std::unordered_map<int, std::vector<int>> by_vert;
	for (int t = 0; t < nt; t++)
		for (int i = 0; i < 3; i++) by_vert[tris[3 * t + i]].push_back(t);
	std::vector<std::vector<int>> sharing(nt);
	for (int t = 0; t < nt; t++) {
		std::unordered_set<int> s;
		for (int i = 0; i < 3; i++)
			for (int u : by_vert[tris[3 * t + i]]) s.insert(u);
		sharing[t].assign(s.begin(), s.end());
	}
	ring.clear();
	for (int t = 0; t < nt; t++) {
		std::unordered_set<int> two;
		for (int u : sharing[t])
			for (int w : sharing[u]) two.insert(w);
		for (int u : two)
			for (int w : sharing[u]) ring.insert((long long)t * nt + w);
	}
	pairs.clear();
	active.clear();
}

int KineClothSelfNative::begin(const PackedVector3Array &p_p) {
	int nt = (int)tris.size() / 3;
	std::vector<V3> p = read_points(p_p);
	std::vector<V3> lo(nt), hi(nt), cen(nt);
	std::vector<float> rad(nt);
	// cells in first-touch order (the GDScript Dictionary iterates in insertion order): the pair order is the same
	std::unordered_map<long long, int> index;
	std::vector<std::vector<int>> cells;
	std::vector<long long> keys;
	float padv = (float)(thick * 0.5 + PAD);
	V3 pad = { padv, padv, padv };
	double inv = 1.0 / CELL;
	for (int t = 0; t < nt; t++) {
		V3 a = p[tris[3 * t]], b = p[tris[3 * t + 1]], c = p[tris[3 * t + 2]];
		V3 l = sub(vmin(vmin(a, b), c), pad);
		V3 h = add(vmax(vmax(a, b), c), pad);
		lo[t] = l;
		hi[t] = h;
		V3 s3 = add(add(a, b), c);
		V3 ce = { s3.x / 3.0f, s3.y / 3.0f, s3.z / 3.0f };
		cen[t] = ce;
		auto d2 = [&](const V3 &q) { V3 d = sub(q, ce); return dot(d, d); };
		rad[t] = (float)std::sqrt(std::max(std::max(d2(a), d2(b)), d2(c)));
		long long x0 = (long long)std::floor(l.x * inv), x1 = (long long)std::floor(h.x * inv);
		long long y0 = (long long)std::floor(l.y * inv), y1 = (long long)std::floor(h.y * inv);
		long long z0 = (long long)std::floor(l.z * inv), z1 = (long long)std::floor(h.z * inv);
		for (long long ix = x0; ix <= x1; ix++)
			for (long long iy = y0; iy <= y1; iy++)
				for (long long iz = z0; iz <= z1; iz++) {
					long long key = cell_key(ix, iy, iz);
					auto it = index.find(key);
					if (it == index.end()) {
						index[key] = (int)cells.size();
						cells.push_back(std::vector<int>(1, t));
						keys.push_back(key);
					} else {
						cells[it->second].push_back(t);
					}
				}
	}
	pairs.clear();
	float reach = (float)(thick + 2.0 * PAD);
	for (size_t ci = 0; ci < cells.size(); ci++) {
		const std::vector<int> &lst = cells[ci];
		long long key = keys[ci];
		int n = (int)lst.size();
		if (n < 2) continue;
		for (int i = 0; i < n; i++) {
			int ta = lst[i];
			for (int j = i + 1; j < n; j++) {
				int tb = lst[j];
				const V3 &l1 = lo[ta], &h1 = hi[ta], &l2 = lo[tb], &h2 = hi[tb];
				if (l1.x > h2.x || l2.x > h1.x || l1.y > h2.y || l2.y > h1.y || l1.z > h2.z || l2.z > h1.z) continue;
				long long ox = (long long)std::floor(std::max(l1.x, l2.x) * inv);
				long long oy = (long long)std::floor(std::max(l1.y, l2.y) * inv);
				long long oz = (long long)std::floor(std::max(l1.z, l2.z) * inv);
				if (key != cell_key(ox, oy, oz)) continue;
				if (share(tris, ta, tb)) continue;
				if (len(sub(cen[ta], cen[tb])) > rad[ta] + rad[tb] + reach) continue;
				if (ring.count((long long)ta * nt + tb) && !near_tris(p, tris, ta, tb, reach)) continue;
				pairs.push_back(ta);
				pairs.push_back(tb);
			}
		}
	}
	active.clear();
	return (int)(pairs.size() / 2);
}

PackedVector3Array KineClothSelfNative::solve(const PackedVector3Array &p_p, const PackedByteArray &p_pinned, bool p_first) {
	int nv = p_p.size();
	std::vector<V3> p = read_points(p_p);
	const uint8_t *pinned = p_pinned.ptr();
	float th = (float)thick;
	int n = 0;
	std::vector<int> live;
	int cnt = p_first ? (int)(pairs.size() / 2) : (int)active.size();
	for (int kk = 0; kk < cnt; kk++) {
		int k = p_first ? kk : active[kk];
		int ta = pairs[2 * k], tb = pairs[2 * k + 1];
		int n0 = n;
		int a0 = tris[3 * ta], a1 = tris[3 * ta + 1], a2 = tris[3 * ta + 2];
		int b0 = tris[3 * tb], b1 = tris[3 * tb + 1], b2 = tris[3 * tb + 2];
		n += vert_tri(p, pinned, th, a0, b0, b1, b2);
		n += vert_tri(p, pinned, th, a1, b0, b1, b2);
		n += vert_tri(p, pinned, th, a2, b0, b1, b2);
		n += vert_tri(p, pinned, th, b0, a0, a1, a2);
		n += vert_tri(p, pinned, th, b1, a0, a1, a2);
		n += vert_tri(p, pinned, th, b2, a0, a1, a2);
		n += edge_edge(p, pinned, th, a0, a1, b0, b1);
		n += edge_edge(p, pinned, th, a0, a1, b1, b2);
		n += edge_edge(p, pinned, th, a0, a1, b2, b0);
		n += edge_edge(p, pinned, th, a1, a2, b0, b1);
		n += edge_edge(p, pinned, th, a1, a2, b1, b2);
		n += edge_edge(p, pinned, th, a1, a2, b2, b0);
		n += edge_edge(p, pinned, th, a2, a0, b0, b1);
		n += edge_edge(p, pinned, th, a2, a0, b1, b2);
		n += edge_edge(p, pinned, th, a2, a0, b2, b0);
		if (p_first && n > n0) live.push_back(k);
	}
	if (p_first) active = live;
	contacts = n;
	PackedVector3Array out;
	out.resize(nv);
	Vector3 *dst = out.ptrw();
	for (int i = 0; i < nv; i++) dst[i] = Vector3(p[i].x, p[i].y, p[i].z);
	return out;
}
