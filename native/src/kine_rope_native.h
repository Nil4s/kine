#pragma once
// KineRopeNative (CH6): the rope of kine_rope_core.h as a Godot class. One instance per rope.
//   setup(points, ds, r, params)        points = PackedVector3Array of particle centres (spacing ds, radius r)
//   params keys (all optional): mu, kb, grav, damp, iters, subs, mass, skip, alpha
//   set_colliders(a0, b0, a1, b1, radii, mus)   capsules at the start / end of the coming step (frame)
//   drive(i, from, to) / undrive(i)     kinematic particle moving from -> to over the step (a hand's grasp, a pinned end)
//   set_force(i, f)                     external force (N) on particle i
//   step(dt)                            one frame: `subs` substeps of `iters` iterations
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include "kine_rope_core.h"

namespace godot {

class KineRopeNative : public RefCounted {
	GDCLASS(KineRopeNative, RefCounted)
	kr::Rope rope;

protected:
	static void _bind_methods();

public:
	static int version();
	void setup(const PackedVector3Array &p_pts, double p_ds, double p_r, const Dictionary &p_params);
	void set_colliders(const PackedVector3Array &a0, const PackedVector3Array &b0, const PackedVector3Array &a1, const PackedVector3Array &b1, const PackedFloat32Array &radii, const PackedFloat32Array &mus);
	void drive(int i, const Vector3 &from, const Vector3 &to);
	void undrive(int i);
	void set_force(int i, const Vector3 &f);
	void set_param(const String &key, double v);
	void step(double dt);
	PackedVector3Array get_x() const;
	int get_n() const { return rope.n; }
	double max_self_pen() const { return rope.max_self_pen(); }
	double max_col_pen(bool skip_driven) const;
	double get_tension() const { return rope.max_tension; }
	int get_contacts() const { return rope.contacts_self; }
};

} // namespace godot
