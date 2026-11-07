// Results must equal the GDScript twin exactly: no fused multiply-add, same rounding points.
#pragma GCC optimize("fp-contract=off")
#include "kine_kmesh_native.h"
#include "kine_kmesh_common.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;

void KineKMeshNative::_bind_methods() {
	ClassDB::bind_static_method("KineKMeshNative", D_METHOD("version"), &KineKMeshNative::version);
	ClassDB::bind_static_method("KineKMeshNative", D_METHOD("topology", "verts", "faces"), &KineKMeshNative::topology);
	ClassDB::bind_static_method("KineKMeshNative", D_METHOD("from_tris", "pos", "idx", "tol"), &KineKMeshNative::from_tris);
	ClassDB::bind_static_method("KineKMeshNative", D_METHOD("edge_map", "nv", "he_vert", "he_next"), &KineKMeshNative::edge_map);
	ClassDB::bind_static_method("KineKMeshNative", D_METHOD("subdivide", "verts", "faces", "levels", "crease"), &KineKMeshNative::subdivide);
	ClassDB::bind_static_method("KineKMeshNative", D_METHOD("boolean", "va", "fa", "ta_corner", "ta_face", "vb", "fb", "tb_corner", "tb_face", "op", "snap_min"), &KineKMeshNative::boolean);
}

int KineKMeshNative::version() {
	return 1;
}

namespace kmesh {

Faces read_faces(const Array &p_faces) {
	Faces F;
	int nf = p_faces.size();
	F.fs.resize(nf + 1);
	int total = 0;
	std::vector<PackedInt32Array> hold(nf);
	for (int i = 0; i < nf; i++) {
		hold[i] = p_faces[i];
		F.fs[i] = total;
		total += hold[i].size();
	}
	F.fs[nf] = total;
	F.fv.resize(total);
	for (int i = 0; i < nf; i++) {
		int n = hold[i].size();
		if (n) {
			memcpy(F.fv.data() + F.fs[i], hold[i].ptr(), sizeof(int32_t) * n);
		}
	}
	return F;
}

Array make_faces(const std::vector<int32_t> &fs, const std::vector<int32_t> &fv) {
	Array out;
	int nf = (int)fs.size() - 1;
	out.resize(nf);
	for (int f = 0; f < nf; f++) {
		int n = fs[f + 1] - fs[f];
		PackedInt32Array p;
		p.resize(n);
		if (n) {
			memcpy(p.ptrw(), fv.data() + fs[f], sizeof(int32_t) * n);
		}
		out[f] = p;
	}
	return out;
}

std::vector<Vector3> read_verts(const PackedVector3Array &p) {
	std::vector<Vector3> V((size_t)p.size());
	for (int64_t i = 0; i < p.size(); i++) {
		V[(size_t)i] = p[i];
	}
	return V;
}

PackedVector3Array write_verts(const std::vector<Vector3> &V) {
	PackedVector3Array p;
	p.resize((int64_t)V.size());
	for (size_t i = 0; i < V.size(); i++) {
		p[(int64_t)i] = V[i];
	}
	return p;
}

} // namespace kmesh

namespace kmesh {

void build_topo(const std::vector<Vector3> &V, const Faces &F, Topo &T) {
	int nv = (int)V.size();
	int nf = (int)F.fs.size() - 1;
	int total = (int)F.fv.size();
	T.he_vert.resize(total);
	T.he_next.resize(total);
	T.he_face.resize(total);
	T.face_he0.resize(nf);
	T.he_twin.assign(total, -1);
	std::vector<int32_t> counts(nv, 0);
	HMap em((size_t)total);
	std::vector<int32_t> firsts; // half-edges that own a directed edge, in creation order
	firsts.reserve(total);
	for (int fi = 0; fi < nf; fi++) {
		int h = F.fs[fi];
		int n = F.fs[fi + 1] - h;
		T.face_he0[fi] = h;
		for (int i = 0; i < n; i++) {
			int a = F.fv[h + i];
			int b = F.fv[h + (i + 1) % n];
			T.he_vert[h + i] = a;
			T.he_next[h + i] = h + (i + 1) % n;
			T.he_face[h + i] = fi;
			counts[a] += 1;
			if (a != b) {
				int64_t key = (int64_t)a * nv + b;
				if (em.put_first(key, h + i) == -1) {
					firsts.push_back(h + i);
				}
			}
		}
	}
	for (int32_t h : firsts) {
		int a = T.he_vert[h];
		int b = T.he_vert[T.he_next[h]];
		T.he_twin[h] = em.get((int64_t)b * nv + a);
	}
	T.vf_start.resize(nv + 1);
	int acc = 0;
	for (int v = 0; v < nv; v++) {
		T.vf_start[v] = acc;
		acc += counts[v];
	}
	T.vf_start[nv] = acc;
	T.vf_list.resize(acc);
	std::vector<int32_t> fill(nv, 0);
	for (int fi = 0; fi < nf; fi++) {
		for (int c = F.fs[fi]; c < F.fs[fi + 1]; c++) {
			int v = F.fv[c];
			T.vf_list[T.vf_start[v] + fill[v]] = fi;
			fill[v] += 1;
		}
	}
	// normals: Newell per face, accumulated float32 as GDScript does
	T.fn.resize(nf);
	T.vn.assign(nv, Vector3());
	for (int fi = 0; fi < nf; fi++) {
		int s0 = F.fs[fi];
		int n = F.fs[fi + 1] - s0;
		Vector3 s;
		for (int i = 0; i < n; i++) {
			Vector3 a = V[F.fv[s0 + i]];
			Vector3 b = V[F.fv[s0 + (i + 1) % n]];
			s.x = (float)((double)s.x + ((double)a.y - (double)b.y) * ((double)a.z + (double)b.z));
			s.y = (float)((double)s.y + ((double)a.z - (double)b.z) * ((double)a.x + (double)b.x));
			s.z = (float)((double)s.z + ((double)a.x - (double)b.x) * ((double)a.y + (double)b.y));
		}
		T.fn[fi] = s.normalized();
		for (int i = 0; i < n; i++) {
			T.vn[F.fv[s0 + i]] += s;
		}
	}
	for (int v = 0; v < nv; v++) {
		T.vn[v] = T.vn[v].normalized();
	}
	for (int h = 0; h < total; h++) {
		if (T.he_twin[h] == -1 && T.he_vert[h] != T.he_vert[T.he_next[h]]) {
			T.bnd++;
		}
	}
	// is_manifold, as KMesh.is_manifold
	T.manifold = 1;
	for (int h = 0; h < total && T.manifold; h++) {
		int a = T.he_vert[h];
		int b = T.he_vert[T.he_next[h]];
		if (a == b || em.get((int64_t)a * nv + b) != h) {
			T.manifold = 0;
		}
	}
	std::vector<int32_t> out_he;
	for (int v = 0; v < nv && T.manifold; v++) {
		out_he.clear();
		for (int k = T.vf_start[v]; k < T.vf_start[v + 1]; k++) {
			int fi = T.vf_list[k];
			int s0 = F.fs[fi];
			int n = F.fs[fi + 1] - s0;
			for (int i = 0; i < n; i++) {
				if (F.fv[s0 + i] == v) {
					out_he.push_back(T.face_he0[fi] + i);
				}
			}
		}
		if (out_he.empty()) {
			continue;
		}
		int start = -1;
		int bstarts = 0;
		for (int h : out_he) {
			if (T.he_twin[h] == -1) {
				bstarts++;
				start = h;
			}
		}
		if (bstarts > 1) {
			T.manifold = 0;
			break;
		}
		if (start == -1) {
			start = out_he[0];
		}
		int count = 0;
		int h2 = start;
		while (count <= (int)out_he.size()) {
			count++;
			int f = T.he_face[h2];
			int n = F.fs[f + 1] - F.fs[f];
			int i = h2 - T.face_he0[f];
			int prev = T.face_he0[f] + (i + n - 1) % n;
			int nxt = T.he_twin[prev];
			if (nxt == -1 || nxt == start) {
				break;
			}
			h2 = nxt;
		}
		if (count != (int)out_he.size()) {
			T.manifold = 0;
		}
	}
}

template <class P, class T>
P to_packed(const std::vector<T> &v) {
	P p;
	p.resize((int64_t)v.size());
	if (!v.empty()) {
		memcpy(p.ptrw(), v.data(), sizeof(T) * v.size());
	}
	return p;
}

void put_topo(Dictionary &d, const Topo &T) {
	d["he_vert"] = to_packed<PackedInt32Array>(T.he_vert);
	d["he_next"] = to_packed<PackedInt32Array>(T.he_next);
	d["he_twin"] = to_packed<PackedInt32Array>(T.he_twin);
	d["he_face"] = to_packed<PackedInt32Array>(T.he_face);
	d["face_he0"] = to_packed<PackedInt32Array>(T.face_he0);
	d["vf_start"] = to_packed<PackedInt32Array>(T.vf_start);
	d["vf_list"] = to_packed<PackedInt32Array>(T.vf_list);
	d["face_normals"] = write_verts(T.fn);
	d["vert_normals"] = write_verts(T.vn);
	d["manifold"] = T.manifold;
	d["bnd"] = T.bnd;
}

} // namespace kmesh

using namespace kmesh;

Dictionary KineKMeshNative::topology(const PackedVector3Array &p_verts, const Array &p_faces) {
	std::vector<Vector3> V = read_verts(p_verts);
	Faces F = read_faces(p_faces);
	Topo T;
	build_topo(V, F, T);
	Dictionary d;
	put_topo(d, T);
	return d;
}

Dictionary KineKMeshNative::from_tris(const PackedVector3Array &p_pos, const PackedInt32Array &p_idx, double p_tol) {
	int64_t np = p_pos.size();
	std::vector<int32_t> idx;
	if (p_idx.is_empty()) {
		idx.resize((size_t)np);
		for (int64_t i = 0; i < np; i++) {
			idx[(size_t)i] = (int32_t)i;
		}
	} else {
		idx.assign(p_idx.ptr(), p_idx.ptr() + p_idx.size());
	}
	double inv = 1.0 / p_tol;
	struct Cell {
		int32_t x, y, z, id;
		int32_t next;
	};
	size_t cap = 16;
	while (cap < (size_t)np * 2 + 2) {
		cap <<= 1;
	}
	std::vector<int32_t> head(cap, -1);
	std::vector<Cell> cells;
	cells.reserve((size_t)np);
	std::vector<int32_t> remap((size_t)np);
	std::vector<Vector3> out;
	out.reserve((size_t)np);
	for (int64_t i = 0; i < np; i++) {
		Vector3 p = p_pos[i];
		int32_t kx = (int32_t)(int64_t)std::round((double)p.x * inv);
		int32_t ky = (int32_t)(int64_t)std::round((double)p.y * inv);
		int32_t kz = (int32_t)(int64_t)std::round((double)p.z * inv);
		uint64_t h = (uint64_t)(uint32_t)kx * 73856093ULL ^ (uint64_t)(uint32_t)ky * 19349663ULL ^ (uint64_t)(uint32_t)kz * 83492791ULL;
		h ^= h >> 29;
		size_t slot = (size_t)(h & (cap - 1));
		int32_t got = -1;
		for (int32_t c = head[slot]; c != -1; c = cells[(size_t)c].next) {
			if (cells[(size_t)c].x == kx && cells[(size_t)c].y == ky && cells[(size_t)c].z == kz) {
				got = cells[(size_t)c].id;
				break;
			}
		}
		if (got == -1) {
			got = (int32_t)out.size();
			cells.push_back({ kx, ky, kz, got, head[slot] });
			head[slot] = (int32_t)cells.size() - 1;
			out.push_back(p);
		}
		remap[(size_t)i] = got;
	}
	Faces F;
	int nt = (int)(idx.size() / 3);
	F.fs.resize(nt + 1);
	F.fv.resize((size_t)nt * 3);
	for (int t = 0; t < nt; t++) {
		F.fs[t] = t * 3;
		for (int k = 0; k < 3; k++) {
			F.fv[(size_t)t * 3 + k] = remap[(size_t)idx[(size_t)t * 3 + k]];
		}
	}
	F.fs[nt] = nt * 3;
	Topo T;
	build_topo(out, F, T);
	Dictionary d;
	put_topo(d, T);
	d["verts"] = write_verts(out);
	d["faces"] = make_faces(F.fs, F.fv);
	return d;
}

Dictionary KineKMeshNative::edge_map(int p_nv, const PackedInt32Array &p_he_vert, const PackedInt32Array &p_he_next) {
	Dictionary d;
	int total = p_he_vert.size();
	for (int h = 0; h < total; h++) {
		int a = p_he_vert[h];
		int b = p_he_vert[p_he_next[h]];
		if (a != b) {
			int64_t key = (int64_t)a * p_nv + b;
			if (!d.has(key)) {
				d[key] = h;
			}
		}
	}
	return d;
}

// ====================================================================================================================
// SUBDIVIDE: scripts/kmesh_subdiv.gd
// ====================================================================================================================
namespace {

struct STop {
	std::vector<int32_t> a, b, f0, f1, nf, ce;
};

void sub_edges(int nv, const Faces &F, STop &t) {
	int nf = (int)F.fs.size() - 1;
	t.ce.assign(F.fv.size(), 0);
	HMap key(F.fv.size());
	for (int f = 0; f < nf; f++) {
		int s = F.fs[f];
		int n = F.fs[f + 1] - s;
		for (int i = 0; i < n; i++) {
			int p = F.fv[s + i];
			int q = F.fv[s + (i + 1) % n];
			int lo = std::min(p, q);
			int hi = std::max(p, q);
			int64_t k = (int64_t)lo * nv + hi;
			int id = key.get(k);
			if (id == -1) {
				id = (int)t.a.size();
				key.put_first(k, id);
				t.a.push_back(lo);
				t.b.push_back(hi);
				t.f0.push_back(f);
				t.f1.push_back(-1);
				t.nf.push_back(1);
			} else {
				if (t.nf[id] == 1) {
					t.f1[id] = f;
				}
				t.nf[id] += 1;
			}
			t.ce[s + i] = id;
		}
	}
}

void sub_level(std::vector<Vector3> &V, Faces &F, STop &top, std::vector<float> &sharp) {
	const double INF = std::numeric_limits<double>::infinity();
	int nv = (int)V.size();
	int nf = (int)F.fs.size() - 1;
	int ne = (int)top.a.size();
	std::vector<Vector3> FP(nf);
	for (int f = 0; f < nf; f++) {
		Vector3 s;
		for (int c = F.fs[f]; c < F.fs[f + 1]; c++) {
			s += V[F.fv[c]];
		}
		FP[f] = s / (float)(double)(F.fs[f + 1] - F.fs[f]);
	}
	std::vector<Vector3> q_sum(nv), r_sum(nv), s_oth(nv);
	std::vector<int32_t> k_cnt(nv, 0), val(nv, 0), s_cnt(nv, 0), bnd(nv, 0);
	std::vector<float> s_sum(nv, 0.0f);
	for (int f = 0; f < nf; f++) {
		for (int c = F.fs[f]; c < F.fs[f + 1]; c++) {
			q_sum[F.fv[c]] += FP[f];
			k_cnt[F.fv[c]] += 1;
		}
	}
	std::vector<Vector3> EP(ne);
	for (int e = 0; e < ne; e++) {
		int a = top.a[e];
		int b = top.b[e];
		Vector3 mid = (V[a] + V[b]) * 0.5f;
		r_sum[a] += mid;
		r_sum[b] += mid;
		val[a] += 1;
		val[b] += 1;
		double s = top.nf[e] == 2 ? (double)sharp[e] : INF;
		if (top.nf[e] != 2) {
			bnd[a] += 1;
			bnd[b] += 1;
		}
		if (s > 0.0) {
			s_cnt[a] += 1;
			s_cnt[b] += 1;
			s_sum[a] = (float)((double)s_sum[a] + s);
			s_sum[b] = (float)((double)s_sum[b] + s);
			s_oth[a] += V[b];
			s_oth[b] += V[a];
		}
		if (top.nf[e] != 2 || s >= 1.0) {
			EP[e] = mid;
		} else {
			Vector3 sm = (V[a] + V[b] + FP[top.f0[e]] + FP[top.f1[e]]) * 0.25f;
			EP[e] = s > 0.0 ? sm.lerp(mid, (float)s) : sm;
		}
	}
	std::vector<Vector3> NV((size_t)nv + ne + nf);
	for (int v = 0; v < nv; v++) {
		Vector3 p = V[v];
		int k = k_cnt[v];
		if (k == 0) {
			NV[v] = p;
			continue;
		}
		int n = val[v];
		Vector3 sm = (q_sum[v] / (float)(double)k + ((float)2.0 * r_sum[v]) / (float)(double)n + (float)(double)(n - 3) * p) / (float)(double)n;
		int ns = s_cnt[v];
		if (ns < 2) {
			NV[v] = sm;
			continue;
		}
		Vector3 hard = p;
		if (ns == 2 && !(k == 1 && bnd[v] >= 2)) {
			hard = (s_oth[v] + (float)6.0 * p) / (float)8.0;
		}
		double vs = (double)s_sum[v] / (double)ns;
		NV[v] = vs >= 1.0 ? hard : sm.lerp(hard, (float)vs);
	}
	for (int e = 0; e < ne; e++) {
		NV[(size_t)nv + e] = EP[e];
	}
	for (int f = 0; f < nf; f++) {
		NV[(size_t)nv + ne + f] = FP[f];
	}
	int nc = (int)F.fv.size();
	std::vector<int32_t> nfs(nc + 1), nfv((size_t)nc * 4);
	for (int f = 0; f < nf; f++) {
		int s0 = F.fs[f];
		int n = F.fs[f + 1] - s0;
		for (int i = 0; i < n; i++) {
			int c = s0 + i;
			int o = c * 4;
			nfs[c] = o;
			nfv[o] = F.fv[c];
			nfv[o + 1] = nv + top.ce[c];
			nfv[o + 2] = nv + ne + f;
			nfv[o + 3] = nv + top.ce[s0 + (i + n - 1) % n];
		}
	}
	nfs[nc] = nc * 4;
	int nne = 2 * ne + nc;
	STop nt;
	nt.a.resize(nne);
	nt.b.resize(nne);
	std::vector<float> nsh(nne, 0.0f);
	for (int e = 0; e < ne; e++) {
		nt.a[2 * e] = top.a[e];
		nt.b[2 * e] = nv + e;
		nt.a[2 * e + 1] = top.b[e];
		nt.b[2 * e + 1] = nv + e;
		float cs = (float)std::max((double)sharp[e] - 1.0, 0.0);
		nsh[2 * e] = cs;
		nsh[2 * e + 1] = cs;
	}
	nt.ce.resize((size_t)nc * 4);
	for (int f = 0; f < nf; f++) {
		int s0 = F.fs[f];
		int n = F.fs[f + 1] - s0;
		for (int i = 0; i < n; i++) {
			int c = s0 + i;
			int pc = s0 + (i + n - 1) % n;
			int v = F.fv[c];
			nt.a[2 * ne + c] = nv + top.ce[c];
			nt.b[2 * ne + c] = nv + ne + f;
			int o = c * 4;
			nt.ce[o] = 2 * top.ce[c] + (top.a[top.ce[c]] == v ? 0 : 1);
			nt.ce[o + 1] = 2 * ne + c;
			nt.ce[o + 2] = 2 * ne + pc;
			nt.ce[o + 3] = 2 * top.ce[pc] + (top.a[top.ce[pc]] == v ? 0 : 1);
		}
	}
	nt.f0.assign(nne, -1);
	nt.f1.assign(nne, -1);
	nt.nf.assign(nne, 0);
	for (int o = 0; o < nc * 4; o++) {
		int e = nt.ce[o];
		int f = o >> 2;
		if (nt.nf[e] == 0) {
			nt.f0[e] = f;
		} else if (nt.nf[e] == 1) {
			nt.f1[e] = f;
		}
		nt.nf[e] += 1;
	}
	V = std::move(NV);
	F.fs = std::move(nfs);
	F.fv = std::move(nfv);
	top = std::move(nt);
	sharp = std::move(nsh);
}

} // namespace

Dictionary KineKMeshNative::subdivide(const PackedVector3Array &p_verts, const Array &p_faces, int p_levels, double p_crease) {
	std::vector<Vector3> V = read_verts(p_verts);
	Faces F = read_faces(p_faces);
	STop top;
	sub_edges((int)V.size(), F, top);
	std::vector<float> sharp(top.a.size(), p_crease < 0.0 ? 0.0f : (float)p_crease);
	for (int lv = 0; lv < p_levels; lv++) {
		sub_level(V, F, top, sharp);
	}
	Dictionary d;
	Topo T;
	build_topo(V, F, T);
	put_topo(d, T);
	d["verts"] = write_verts(V);
	d["faces"] = make_faces(F.fs, F.fv);
	return d;
}
