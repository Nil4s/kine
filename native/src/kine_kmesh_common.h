#pragma once
// shared helpers of kine_kmesh_native.cpp and kine_kmesh_boolean.cpp
#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace kmesh {

// open-addressing table: int64 key -> int32 value (insert keeps the first)
struct HMap {
	std::vector<int64_t> keys;
	std::vector<int32_t> vals;
	uint64_t mask = 0;
	explicit HMap(size_t n) {
		size_t cap = 16;
		while (cap < n * 2 + 2) {
			cap <<= 1;
		}
		keys.assign(cap, INT64_MIN);
		vals.assign(cap, -1);
		mask = cap - 1;
	}
	static uint64_t mix(int64_t k) {
		uint64_t x = (uint64_t)k;
		x ^= x >> 33;
		x *= 0xff51afd7ed558ccdULL;
		x ^= x >> 33;
		x *= 0xc4ceb9fe1a85ec53ULL;
		x ^= x >> 33;
		return x;
	}
	int32_t get(int64_t k) const {
		uint64_t i = mix(k) & mask;
		while (keys[i] != INT64_MIN) {
			if (keys[i] == k) {
				return vals[i];
			}
			i = (i + 1) & mask;
		}
		return -1;
	}
	// returns the existing value, or -1 after inserting v
	int32_t put_first(int64_t k, int32_t v) {
		uint64_t i = mix(k) & mask;
		while (keys[i] != INT64_MIN) {
			if (keys[i] == k) {
				return vals[i];
			}
			i = (i + 1) & mask;
		}
		keys[i] = k;
		vals[i] = v;
		return -1;
	}
};

struct Faces {
	std::vector<int32_t> fs; // size nf + 1
	std::vector<int32_t> fv;
};

struct Topo {
	std::vector<int32_t> he_vert, he_next, he_twin, he_face, face_he0, vf_start, vf_list;
	std::vector<godot::Vector3> fn, vn;
	int manifold = 1;
	int bnd = 0;
};
void build_topo(const std::vector<godot::Vector3> &V, const Faces &F, Topo &T);
void put_topo(godot::Dictionary &d, const Topo &T);

Faces read_faces(const godot::Array &p_faces);
godot::Array make_faces(const std::vector<int32_t> &fs, const std::vector<int32_t> &fv);
std::vector<godot::Vector3> read_verts(const godot::PackedVector3Array &p);
godot::PackedVector3Array write_verts(const std::vector<godot::Vector3> &V);

} // namespace kmesh
