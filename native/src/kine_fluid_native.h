#pragma once
// KineFluidNative (CH8): an APIC liquid solver on a MAC grid. Own code. Papers: Zhu & Bridson 2005 (sand/FLIP particle-grid method),
// Jiang et al. 2015 (APIC: affine particle-in-cell, quadratic B-spline, D = h^2/4), Bridson "Fluid Simulation for Computer Graphics"
// (MAC grid, pressure projection, PCG with modified incomplete Cholesky MIC(0)). Doubles throughout so the GDScript twin
// (scripts/fluid_sim.gd) matches to ~1e-12 with threads = 1.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cstdint>
#include <vector>

namespace godot {

class KineFluidNative : public RefCounted {
	GDCLASS(KineFluidNative, RefCounted)

protected:
	static void _bind_methods();

public:
	int nx = 0, ny = 0, nz = 0;
	double h = 0.01, ox = 0, oy = 0, oz = 0;
	double grav = 9.81, drift = 0.2, cfl = 0.5, dtmax = 0.01, tol = 1e-6;
	int max_iter = 300, nt = 1, nte = 1;
	std::vector<uint8_t> solid, type;
	std::vector<int32_t> cnt;
	std::vector<double> P, V, C; // 3N, 3N, 9N
	std::vector<double> U, Vg, W, mU, mV, mW; // grid momentum / velocity / weight sums
	std::vector<double> pr, rhs, rr, zz, ss, qq, pre, adiag, dq, db; // dq, db: the density-projection solve
	std::vector<int> blo, bhi; // per solve task: lowest / highest cell index it owns
	bool pre_ok = false;
	int dmode = 1; // 0 = density drift as a pressure source in the velocity solve (first version), 1 = implicit density projection on positions
	double idp_tol = 1e-3;
	int idp_max = 60, idp_iters_last = 0;
	double tm_idp = 0;
	void set_density_mode(int m) { dmode = m; }
	int sm_taubin = 1; // surface_aniso: Taubin lambda|mu smoothing of the kernel centres (0 = the lambda step only, Yu & Turk 2013 as first written)
	void set_surface_taubin(int p_on) { sm_taubin = p_on; }
	int extrap = 1; // velocity extrapolation into the air after the projection (1 = on)
	void set_extrapolation(int on) { extrap = on; }
	std::vector<uint8_t> vflag[3], vflag2[3];
	std::vector<int32_t> fl, order, cstart;
	double vmax = 0, tm_p2g = 0, tm_proj = 0, tm_g2p = 0, tm_adv = 0, tm_sort = 0;
	int last_iters = 0;
	double last_res = 0;
	int ppc = 8;
	double wfr = 0.0; // wall friction: 0 = free slip, 1 = no slip
	void set_wall_friction(double f) { wfr = f < 0 ? 0 : (f > 1 ? 1 : f); }

	void setup(int p_nx, int p_ny, int p_nz, double p_h, Vector3 p_origin);
	void set_threads(int p_n) { nt = p_n < 1 ? 1 : p_n; }
	void set_params(double p_g, double p_drift, double p_cfl, double p_dtmax, int p_iters, double p_tol);
	void add_solid_box(Vector3 p_min, Vector3 p_max);
	int add_solid_mesh(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris);
	int add_fluid_box(Vector3 p_min, Vector3 p_max, Vector3 p_vel, int p_seed);
	void step(double p_dt);
	int advance(double p_t);
	int particle_count() const { return (int)(P.size() / 3); }
	PackedFloat64Array particle_data() const;
	PackedVector3Array positions() const;
	Dictionary stats();
	double get_pressure(int i, int j, int k) const;
	int solid_count() const;
	int particles_in_solid() const;
	int particles_in_mesh(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris) const;
	double volume_ratio() const;
	double volume_smooth() const;
	Dictionary surface(int p_smooth, double p_iso);
	Dictionary surface_aniso(double p_iso, int p_ndiv);
	void clear_particles();
	int remove_every(int p_k);

private:
	inline int cid(int i, int j, int k) const { return i + nx * (j + ny * k); }
	void sort_particles();
	void mark_cells();
	void p2g();
	void apply_wall_friction();
	void project(double dt);
	void g2p();
	void advect(double dt);
	void pcg(std::vector<double> &x, const std::vector<double> &b, double tl, int maxit, bool warm);
	void build_precond();
	void precond_apply(const std::vector<double> &r, std::vector<double> &z, std::vector<double> *part);
	int solve_tasks() const;
	void density_project();
	void extrapolate();
};

} // namespace godot
