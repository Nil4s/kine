#include "kine_rope_native.h"

using namespace godot;

int KineRopeNative::version() { return 1; }

void KineRopeNative::set_param(const String &key, double v) {
	if (key == "mu") rope.mu = (float)v;
	else if (key == "kb") rope.kb = (float)v;
	else if (key == "grav") rope.grav = (float)v;
	else if (key == "damp") rope.damp = (float)v;
	else if (key == "iters") rope.iters = (int)v;
	else if (key == "subs") rope.subs = (int)v;
	else if (key == "skip") rope.skip = (int)v;
	else if (key == "alpha") rope.alpha = (float)v;
}

void KineRopeNative::setup(const PackedVector3Array &p_pts, double p_ds, double p_r, const Dictionary &p_params) {
	std::vector<kr::V> pts((size_t)p_pts.size());
	for (int i = 0; i < p_pts.size(); i++) pts[i] = { p_pts[i].x, p_pts[i].y, p_pts[i].z };
	if (p_params.has("mass")) rope.mass = (float)(double)p_params["mass"];
	rope.init(pts, (float)p_ds, (float)p_r);
	Array keys = p_params.keys();
	for (int k = 0; k < keys.size(); k++) set_param(String(keys[k]), (double)p_params[keys[k]]);
}

void KineRopeNative::set_colliders(const PackedVector3Array &a0, const PackedVector3Array &b0, const PackedVector3Array &a1, const PackedVector3Array &b1, const PackedFloat32Array &radii, const PackedFloat32Array &mus) {
	rope.cols.clear();
	for (int i = 0; i < a0.size(); i++) {
		kr::Col c;
		c.a0 = { a0[i].x, a0[i].y, a0[i].z };
		c.b0 = { b0[i].x, b0[i].y, b0[i].z };
		c.a1 = { a1[i].x, a1[i].y, a1[i].z };
		c.b1 = { b1[i].x, b1[i].y, b1[i].z };
		c.r = radii[i];
		c.mu = i < mus.size() ? mus[i] : 0.4f;
		rope.cols.push_back(c);
	}
}

void KineRopeNative::drive(int i, const Vector3 &from, const Vector3 &to) {
	if (i < 0 || i >= rope.n) return;
	rope.drive(i, { from.x, from.y, from.z }, { to.x, to.y, to.z });
}
void KineRopeNative::undrive(int i) {
	if (i < 0 || i >= rope.n) return;
	rope.undrive(i);
}
void KineRopeNative::set_force(int i, const Vector3 &f) {
	if (i < 0 || i >= rope.n) return;
	rope.ext[i] = { f.x, f.y, f.z };
}
void KineRopeNative::step(double dt) { rope.step((float)dt); }

PackedVector3Array KineRopeNative::get_x() const {
	PackedVector3Array o;
	o.resize(rope.n);
	for (int i = 0; i < rope.n; i++) o.set(i, Vector3(rope.x[i].x, rope.x[i].y, rope.x[i].z));
	return o;
}

double KineRopeNative::max_col_pen(bool skip_driven) const {
	std::vector<char> mask((size_t)std::max(0, rope.n - 1), 0);
	if (skip_driven)
		for (int i = 0; i < rope.n - 1; i++) mask[i] = rope.drv[i] || rope.drv[i + 1];
	// colliders as last set (a1/b1 = pose at the end of the step)
	return rope.max_col_pen(rope.cols, &mask);
}

void KineRopeNative::_bind_methods() {
	ClassDB::bind_static_method("KineRopeNative", D_METHOD("version"), &KineRopeNative::version);
	ClassDB::bind_method(D_METHOD("setup", "pts", "ds", "r", "params"), &KineRopeNative::setup);
	ClassDB::bind_method(D_METHOD("set_param", "key", "v"), &KineRopeNative::set_param);
	ClassDB::bind_method(D_METHOD("set_colliders", "a0", "b0", "a1", "b1", "radii", "mus"), &KineRopeNative::set_colliders);
	ClassDB::bind_method(D_METHOD("drive", "i", "from", "to"), &KineRopeNative::drive);
	ClassDB::bind_method(D_METHOD("undrive", "i"), &KineRopeNative::undrive);
	ClassDB::bind_method(D_METHOD("set_force", "i", "f"), &KineRopeNative::set_force);
	ClassDB::bind_method(D_METHOD("step", "dt"), &KineRopeNative::step);
	ClassDB::bind_method(D_METHOD("get_x"), &KineRopeNative::get_x);
	ClassDB::bind_method(D_METHOD("get_n"), &KineRopeNative::get_n);
	ClassDB::bind_method(D_METHOD("max_self_pen"), &KineRopeNative::max_self_pen);
	ClassDB::bind_method(D_METHOD("max_col_pen", "skip_driven"), &KineRopeNative::max_col_pen);
	ClassDB::bind_method(D_METHOD("get_tension"), &KineRopeNative::get_tension);
	ClassDB::bind_method(D_METHOD("get_contacts"), &KineRopeNative::get_contacts);
}
