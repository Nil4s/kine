#pragma once
// KineClothSelfNative: the pair list (spatial hash broad phase) and the pair-solve passes of scripts/cloth_self.gd (C54 cloth
// self-collision). One instance per cloth topology (faces + thickness); begin(p) once a substep, solve(p, pinned, first) per pass.
// It mirrors the GDScript arithmetic (float32 Vector3, same loop and pair order), so the positions agree to float rounding.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <unordered_set>
#include <vector>

namespace godot {

class KineClothSelfNative : public RefCounted {
	GDCLASS(KineClothSelfNative, RefCounted)

	std::vector<int> tris;
	double thick = 0.006;
	std::unordered_set<long long> ring;
	std::vector<int> pairs;
	std::vector<int> active;
	int contacts = 0;

protected:
	static void _bind_methods();

public:
	static int version();
	void setup(const PackedInt32Array &p_faces, double p_thick);
	int begin(const PackedVector3Array &p_p);
	// one projection pass; returns the new positions (the input is untouched). get_contacts() is the count it pushed.
	PackedVector3Array solve(const PackedVector3Array &p_p, const PackedByteArray &p_pinned, bool p_first);
	int get_contacts() const { return contacts; }
	int get_npairs() const { return (int)(pairs.size() / 2); }
	PackedInt32Array get_pairs() const;
};

} // namespace godot
