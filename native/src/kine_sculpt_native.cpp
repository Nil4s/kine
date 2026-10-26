#include "kine_sculpt_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace godot;

namespace {

enum Brush { B_DRAW = 0, B_CLAY, B_INFLATE, B_SMOOTH, B_FLATTEN, B_PINCH, B_CREASE, B_GRAB, B_SNAKE };

// GDScript's Vector3 is float32 and its scalars double: scalar math below is double, stored back to float32 where it is a Vector3.
inline Vector3 normalized_gd(const Vector3 &v) {
	float l2 = v.x * v.x + v.y * v.y + v.z * v.z;
	if (l2 == 0.0f) {
		return Vector3(0, 0, 0);
	}
	float l = std::sqrt(l2);
	return Vector3(v.x / l, v.y / l, v.z / l);
}

inline float len_gd(const Vector3 &v) {
	return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

inline float dot_gd(const Vector3 &a, const Vector3 &b) {
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

inline Vector3 mul(const Vector3 &v, double s) {
	float f = (float)s;
	return Vector3(v.x * f, v.y * f, v.z * f);
}

inline Vector3 divd(const Vector3 &v, double c) {
	float f = (float)c;   // Vector3 / scalar divides by the float32
	return Vector3(v.x / f, v.y / f, v.z / f);
}

inline Vector3 sub(const Vector3 &a, const Vector3 &b) {
	return Vector3(a.x - b.x, a.y - b.y, a.z - b.z);
}

inline Vector3 add(const Vector3 &a, const Vector3 &b) {
	return Vector3(a.x + b.x, a.y + b.y, a.z + b.z);
}

double falloff(int kind, double t) {
	if (t >= 1.0) {
		return 0.0;
	}
	t = std::max(t, 0.0);
	switch (kind) {
		case 1:
			return std::sqrt(1.0 - t * t);
		case 2:
			return (1.0 - t) * (1.0 - t);
		case 3:
			return 1.0 - t;
	}
	return 1.0 - t * t * (3.0 - 2.0 * t);
}

Vector3 toward(const Vector3 &q, const Vector3 &target, double s) {
	Vector3 dv = sub(target, q);
	double l = len_gd(dv);
	if (l <= s || l < 1e-12) {
		return dv;
	}
	return mul(dv, s / l);
}

// Newell's vector of a face (KMesh._newell): terms in double, the running sum stored as float32 per step
Vector3 newell(const int32_t *fidx, int32_t a, int32_t b, const Vector3 *vp) {
	int32_t n = b - a;
	Vector3 s(0, 0, 0);
	for (int32_t i = 0; i < n; i++) {
		const Vector3 &p = vp[fidx[a + i]];
		const Vector3 &q = vp[fidx[a + (i + 1) % n]];
		const double py = p.y, pz = p.z, px = p.x, qy = q.y, qz = q.z, qx = q.x;   // GDScript reads components as doubles
		s.x = (float)((double)s.x + (py - qy) * (pz + qz));
		s.y = (float)((double)s.y + (pz - qz) * (px + qx));
		s.z = (float)((double)s.z + (px - qx) * (py + qy));
	}
	return s;
}

inline int64_t cell_key(int64_t x, int64_t y, int64_t z) {
	return ((x & 0x1FFFFF) << 42) | ((y & 0x1FFFFF) << 21) | (z & 0x1FFFFF);
}

// scratch shared by apply / renormal (GDScript calls from the main thread only)
struct Scratch {
	std::vector<Vector3> acc;
	std::vector<uint8_t> vtouched;
	std::vector<int32_t> touched;
	std::vector<uint8_t> fmark;
	std::vector<Vector3> nw;
	std::vector<int32_t> flist;
	std::vector<uint8_t> vmark;
	std::vector<int32_t> vlist;
};
Scratch S;

void ensure(size_t nv, size_t nf) {
	if (S.acc.size() < nv) {
		S.acc.assign(nv, Vector3());
		S.vtouched.assign(nv, 0);
		S.vmark.assign(nv, 0);
	}
	if (S.fmark.size() < nf) {
		S.fmark.assign(nf, 0);
		S.nw.assign(nf, Vector3());
	}
}

// refresh the normals of the faces touching `moved` and of all their verts; verts already written in vp
void renormal_core(const int32_t *fstart, const int32_t *fidx, const int32_t *vfs, const int32_t *vfl, const Vector3 *vp,
		Vector3 *fn, Vector3 *vn, const int32_t *moved, size_t nmoved) {
	S.flist.clear();
	S.vlist.clear();
	for (size_t i = 0; i < nmoved; i++) {
		int32_t v = moved[i];
		for (int32_t k = vfs[v]; k < vfs[v + 1]; k++) {
			int32_t fi = vfl[k];
			if (!S.fmark[fi]) {
				S.fmark[fi] = 1;
				S.flist.push_back(fi);
			}
		}
	}
	for (int32_t fi : S.flist) {
		Vector3 a = newell(fidx, fstart[fi], fstart[fi + 1], vp);
		S.nw[fi] = a;
		fn[fi] = normalized_gd(a);
		for (int32_t k = fstart[fi]; k < fstart[fi + 1]; k++) {
			int32_t v = fidx[k];
			if (!S.vmark[v]) {
				S.vmark[v] = 1;
				S.vlist.push_back(v);
			}
		}
	}
	for (int32_t v : S.vlist) {
		Vector3 s(0, 0, 0);
		for (int32_t k = vfs[v]; k < vfs[v + 1]; k++) {
			int32_t fi = vfl[k];
			s = add(s, S.fmark[fi] ? S.nw[fi] : newell(fidx, fstart[fi], fstart[fi + 1], vp));
		}
		vn[v] = normalized_gd(s);
		S.vmark[v] = 0;
	}
	for (int32_t fi : S.flist) {
		S.fmark[fi] = 0;
	}
}

} // namespace

void KineSculptNative::_bind_methods() {
	ClassDB::bind_static_method("KineSculptNative", D_METHOD("version"), &KineSculptNative::version);
	ClassDB::bind_static_method("KineSculptNative", D_METHOD("make_ctx", "verts", "faces", "cell"), &KineSculptNative::make_ctx);
	ClassDB::bind_static_method("KineSculptNative", D_METHOD("verts_in", "ctx", "verts", "c", "r"), &KineSculptNative::verts_in);
	ClassDB::bind_static_method("KineSculptNative",
			D_METHOD("displacements", "ctx", "verts", "vnorm", "ids", "brush", "falloff", "hit", "n", "r", "a", "strength", "sgn", "has_last", "last"),
			&KineSculptNative::displacements);
	ClassDB::bind_static_method("KineSculptNative",
			D_METHOD("apply", "ctx", "verts", "fnorm", "vnorm", "ids", "d", "sym", "sax", "mask", "lock"), &KineSculptNative::apply);
	ClassDB::bind_static_method("KineSculptNative", D_METHOD("renormal", "ctx", "verts", "fnorm", "vnorm", "moved"), &KineSculptNative::renormal);
}

int KineSculptNative::version() {
	return 1;
}

Dictionary KineSculptNative::make_ctx(const PackedVector3Array &p_verts, const Array &p_faces, double p_cell) {
	const int64_t nv = p_verts.size();
	const int64_t nf = p_faces.size();
	std::vector<int32_t> fs(nf + 1);
	std::vector<int32_t> fl;
	fl.reserve(nf * 4);
	for (int64_t fi = 0; fi < nf; fi++) {
		fs[fi] = (int32_t)fl.size();
		PackedInt32Array f = p_faces[fi];
		const int32_t *fp = f.ptr();
		for (int64_t i = 0; i < f.size(); i++) {
			fl.push_back(fp[i]);
		}
	}
	fs[nf] = (int32_t)fl.size();
	// vertex -> faces (CSR, faces ascending: KMesh._fresh)
	std::vector<int32_t> vfs(nv + 1, 0);
	for (int32_t v : fl) {
		vfs[v + 1]++;
	}
	for (int64_t v = 0; v < nv; v++) {
		vfs[v + 1] += vfs[v];
	}
	std::vector<int32_t> vfl(fl.size());
	std::vector<int32_t> fill(nv, 0);
	for (int64_t fi = 0; fi < nf; fi++) {
		for (int32_t k = fs[fi]; k < fs[fi + 1]; k++) {
			int32_t v = fl[k];
			vfl[vfs[v] + fill[v]++] = (int32_t)fi;
		}
	}
	// distinct neighbours, in KMesh.vert_neighbors order
	std::vector<int32_t> nbs(nv + 1);
	std::vector<int32_t> nbl;
	nbl.reserve(nv * 6);
	for (int64_t v = 0; v < nv; v++) {
		nbs[v] = (int32_t)nbl.size();
		size_t from = nbl.size();
		for (int32_t k = vfs[v]; k < vfs[v + 1]; k++) {
			int32_t fi = vfl[k];
			int32_t a = fs[fi], n = fs[fi + 1] - a;
			for (int32_t i = 0; i < n; i++) {
				if (fl[a + i] == v) {
					int32_t cand[2] = { fl[a + (i + 1) % n], fl[a + (i + n - 1) % n] };
					for (int32_t w : cand) {
						if (w != v && std::find(nbl.begin() + from, nbl.end(), w) == nbl.end()) {
							nbl.push_back(w);
						}
					}
				}
			}
		}
	}
	nbs[nv] = (int32_t)nbl.size();
	// spatial hash: sorted (cell key asc, vert desc) = the GDScript chain order (the newest vert of a cell is the head)
	const Vector3 *vp = p_verts.ptr();
	std::vector<std::pair<int64_t, int32_t>> cells(nv);
	for (int64_t v = 0; v < nv; v++) {
		cells[v] = { cell_key((int64_t)std::floor((double)vp[v].x / p_cell), (int64_t)std::floor((double)vp[v].y / p_cell),
							 (int64_t)std::floor((double)vp[v].z / p_cell)),
			(int32_t)v };
	}
	std::sort(cells.begin(), cells.end(), [](const std::pair<int64_t, int32_t> &a, const std::pair<int64_t, int32_t> &b) {
		return a.first != b.first ? a.first < b.first : a.second > b.second;
	});
	PackedInt64Array hkeys;
	hkeys.resize(nv);
	PackedInt32Array hverts;
	hverts.resize(nv);
	for (int64_t i = 0; i < nv; i++) {
		hkeys.set(i, cells[i].first);
		hverts.set(i, cells[i].second);
	}
	auto pack = [](const std::vector<int32_t> &s) {
		PackedInt32Array a;
		a.resize(s.size());
		if (!s.empty()) {
			memcpy(a.ptrw(), s.data(), s.size() * sizeof(int32_t));
		}
		return a;
	};
	Dictionary d;
	d["fstart"] = pack(fs);
	d["fidx"] = pack(fl);
	d["vf_start"] = pack(vfs);
	d["vf_list"] = pack(vfl);
	d["nb_start"] = pack(nbs);
	d["nb_list"] = pack(nbl);
	d["hkeys"] = hkeys;
	d["hverts"] = hverts;
	d["cell"] = p_cell;
	return d;
}

PackedInt32Array KineSculptNative::verts_in(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const Vector3 &p_c, double p_r) {
	const double cell = p_ctx["cell"];
	PackedInt64Array hkeys = p_ctx["hkeys"];
	PackedInt32Array hverts = p_ctx["hverts"];
	const int64_t *hk = hkeys.ptr();
	const int32_t *hv = hverts.ptr();
	const int64_t nh = hkeys.size();
	const Vector3 *vp = p_verts.ptr();
	const int64_t kx = (int64_t)std::floor((double)p_c.x / cell);
	const int64_t ky = (int64_t)std::floor((double)p_c.y / cell);
	const int64_t kz = (int64_t)std::floor((double)p_c.z / cell);
	const int64_t n = (int64_t)std::ceil(p_r / cell);
	const double r2 = p_r * p_r;
	std::vector<int32_t> tmp;
	for (int64_t x = kx - n; x <= kx + n; x++) {
		for (int64_t y = ky - n; y <= ky + n; y++) {
			for (int64_t z = kz - n; z <= kz + n; z++) {
				int64_t key = cell_key(x, y, z);
				const int64_t *lo = std::lower_bound(hk, hk + nh, key);
				for (int64_t i = lo - hk; i < nh && hk[i] == key; i++) {
					int32_t u = hv[i];
					const Vector3 &q = vp[u];
					float dx = q.x - p_c.x, dy = q.y - p_c.y, dz = q.z - p_c.z;
					float d2 = dx * dx + dy * dy + dz * dz;
					if ((double)d2 <= r2) {
						tmp.push_back(u);
					}
				}
			}
		}
	}
	PackedInt32Array out;
	out.resize(tmp.size());
	if (!tmp.empty()) {
		memcpy(out.ptrw(), tmp.data(), tmp.size() * sizeof(int32_t));
	}
	return out;
}

PackedVector3Array KineSculptNative::displacements(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const PackedVector3Array &p_vnorm,
		const PackedInt32Array &p_ids, int p_brush, int p_falloff, const Vector3 &p_hit, const Vector3 &p_n, double p_r,
		double p_a, double p_strength, double p_sgn, bool p_has_last, const Vector3 &p_last) {
	const int64_t ni = p_ids.size();
	PackedVector3Array dout;
	dout.resize(ni);
	if (ni == 0) {
		return dout;
	}
	PackedInt32Array nbs = p_ctx["nb_start"];
	PackedInt32Array nbl = p_ctx["nb_list"];
	const int32_t *nbs_p = nbs.ptr();
	const int32_t *nbl_p = nbl.ptr();
	const Vector3 *vp = p_verts.ptr();
	const Vector3 *vn = p_vnorm.ptr();
	const int32_t *ids = p_ids.ptr();
	Vector3 *d = dout.ptrw();
	std::vector<float> w(ni);
	for (int64_t i = 0; i < ni; i++) {
		double t = (double)len_gd(sub(vp[ids[i]], p_hit)) / p_r;
		w[i] = (float)falloff(p_falloff, t);
	}
	const Vector3 n = p_n;
	Vector3 ac = p_hit;
	Vector3 an = n;
	if (p_brush == B_FLATTEN || p_brush == B_CLAY) {
		double sw = 0.0;
		Vector3 sc(0, 0, 0), sn(0, 0, 0);
		for (int64_t i = 0; i < ni; i++) {
			sc = add(sc, mul(vp[ids[i]], w[i]));
			sn = add(sn, mul(vn[ids[i]], w[i]));
			sw += w[i];
		}
		if (sw > 0.0) {
			ac = divd(sc, sw);
		}
		if (dot_gd(sn, sn) > 1e-12f) {
			an = normalized_gd(sn);
		}
	}
	for (int64_t i = 0; i < ni; i++) {
		const int32_t v = ids[i];
		const Vector3 q = vp[v];
		const double s = p_a * (double)w[i];
		Vector3 out(0, 0, 0);
		switch (p_brush) {
			case B_DRAW:
				out = mul(mul(n, s), p_sgn);
				break;
			case B_INFLATE:
				out = mul(mul(vn[v], s), p_sgn);
				break;
			case B_SMOOTH: {
				int32_t a = nbs_p[v], b = nbs_p[v + 1];
				if (b == a) {
					break;
				}
				Vector3 mean(0, 0, 0);
				for (int32_t k = a; k < b; k++) {
					mean = add(mean, vp[nbl_p[k]]);
				}
				out = toward(q, divd(mean, (double)(b - a)), s);
				break;
			}
			case B_FLATTEN:
				out = toward(q, sub(q, mul(an, (double)dot_gd(an, sub(q, ac)))), s);
				break;
			case B_CLAY: {
				Vector3 pc = add(ac, mul(mul(an, p_strength), p_sgn));
				double h = (double)dot_gd(an, sub(q, pc));
				if (h * p_sgn < 0.0) {
					out = toward(q, sub(q, mul(an, h)), s);
				}
				break;
			}
			case B_PINCH: {
				Vector3 off = sub(q, p_hit);
				Vector3 tg = sub(off, mul(n, (double)dot_gd(n, off)));
				out = p_sgn > 0.0 ? toward(q, sub(q, tg), s) : mul(normalized_gd(tg), s);
				break;
			}
			case B_CREASE: {
				Vector3 off2 = sub(q, p_hit);
				Vector3 tang = sub(off2, mul(n, (double)dot_gd(n, off2)));
				out = add(mul(mul(Vector3(-n.x, -n.y, -n.z), s), p_sgn), toward(q, sub(q, tang), s * 0.5));
				break;
			}
			case B_SNAKE:
				if (p_has_last) {
					out = mul(sub(p_hit, p_last), (double)w[i]);
				}
				break;
		}
		d[i] = out;
	}
	return dout;
}

Array KineSculptNative::apply(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const PackedVector3Array &p_fnorm, const PackedVector3Array &p_vnorm,
		const PackedInt32Array &p_ids, const PackedVector3Array &p_d, const PackedInt32Array &p_sym, int p_sax, const PackedFloat32Array &p_mask,
		const PackedByteArray &p_lock) {
	PackedInt32Array fstart = p_ctx["fstart"], fidx = p_ctx["fidx"], vfs = p_ctx["vf_start"], vfl = p_ctx["vf_list"];
	PackedVector3Array verts = p_verts, fnorm = p_fnorm, vnorm = p_vnorm;
	ensure(verts.size(), fnorm.size());
	const bool has_sym = !p_sym.is_empty();
	const bool has_mask = !p_mask.is_empty();
	const bool has_lock = !p_lock.is_empty();
	const int32_t *ids = p_ids.ptr();
	const Vector3 *d = p_d.ptr();
	const int32_t *sym = p_sym.ptr();
	S.touched.clear();
	auto touch = [&](int32_t v, const Vector3 &dv) {
		if (!S.vtouched[v]) {
			S.vtouched[v] = 1;
			S.acc[v] = Vector3(0, 0, 0);
			S.touched.push_back(v);
		}
		S.acc[v] = add(S.acc[v], dv);
	};
	for (int64_t i = 0; i < p_ids.size(); i++) {
		if (d[i].x == 0.0f && d[i].y == 0.0f && d[i].z == 0.0f) {
			continue;
		}
		int32_t v = ids[i];
		touch(v, d[i]);
		if (has_sym) {
			int32_t u = sym[v];
			if (u >= 0) {
				Vector3 mv = d[i];
				mv[p_sax] = -mv[p_sax];
				touch(u, mv);
			}
		}
	}
	Vector3 *vp = verts.ptrw();
	for (int32_t v : S.touched) {
		double keep = 1.0;
		if (has_lock && p_lock[v]) {
			keep = 0.0;
		} else if (has_mask) {
			keep = 1.0 - std::min(std::max((double)p_mask[v], 0.0), 1.0);
		}
		Vector3 dv = mul(S.acc[v], keep);
		if (has_sym && sym[v] == v) {
			dv[p_sax] = 0.0f;
		}
		vp[v] = add(vp[v], dv);
		S.vtouched[v] = 0;
	}
	if (!S.touched.empty()) {
		renormal_core(fstart.ptr(), fidx.ptr(), vfs.ptr(), vfl.ptr(), verts.ptr(), fnorm.ptrw(), vnorm.ptrw(), S.touched.data(), S.touched.size());
	}
	Array res;
	res.push_back(verts);
	res.push_back(fnorm);
	res.push_back(vnorm);
	res.push_back((int64_t)S.touched.size());
	return res;
}

Array KineSculptNative::renormal(const Dictionary &p_ctx, const PackedVector3Array &p_verts, const PackedVector3Array &p_fnorm, const PackedVector3Array &p_vnorm,
		const PackedInt32Array &p_moved) {
	PackedInt32Array fstart = p_ctx["fstart"], fidx = p_ctx["fidx"], vfs = p_ctx["vf_start"], vfl = p_ctx["vf_list"];
	PackedVector3Array fnorm = p_fnorm, vnorm = p_vnorm;
	ensure(p_verts.size(), fnorm.size());
	if (!p_moved.is_empty()) {
		renormal_core(fstart.ptr(), fidx.ptr(), vfs.ptr(), vfl.ptr(), p_verts.ptr(), fnorm.ptrw(), vnorm.ptrw(), p_moved.ptr(), p_moved.size());
	}
	Array res;
	res.push_back(fnorm);
	res.push_back(vnorm);
	return res;
}
