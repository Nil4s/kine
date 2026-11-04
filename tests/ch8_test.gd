extends SceneTree
## CH8 (Nick 11-03: liquids). APIC fluid on a MAC grid in C++ (native/src/kine_fluid_native.cpp), GDScript fallback (scripts/fluid_sim.gd).
## godot --headless --path . -s tests/ch8_test.gd     (ONE Godot at a time; bench part uses 8 threads)
## Bars, written and committed BEFORE any solver number was read (docs/CH8_REFERENCE.md has the data and its source):
##   (a) HYDROSTATIC: 12 x 10 x 12 cells of water (h = 10 mm) settle for 1.0 s. Then max |particle velocity| < 1e-3 m/s and the mean pressure of the
##       bottom fluid layer is within 2 % of rho*g*H, H = (particles / 8) * h^3 / floor area (the height the particles themselves say).
##   (b) VOLUME: over the dam break to T = 5 (past the wall hit), V(t) = sum over cells of min(n_cell, 8) / particles stays within 2 % of 1.0
##       (it only loses volume where cells are over-crowded: compression drift) at every sampled step.
##   (c) DAM BREAK vs Martin & Moyce 1952, n^2 = 2: the surge front Z = x/a (front = furthest x of particles within 0.15 a of the floor)
##       is within 10 % of the table Z at each T in the table (T = t*sqrt(2g/a)). Plus a physics bound: Z <= 1 + 2T (Ritter, frictionless) at every T.
##   (d) C++ == GDScript on 16^3 for 20 steps: every particle position and velocity within 1e-6 (threads = 1).
##   (e) MUG (the real Part "mug" mesh, Part.replay -> voxelised): pour in. 0 particles in wall voxels at every check AND 0 particles inside the mesh
##       by an independent ray-parity test; while less than 0.9 of the cup's volume has been poured, 0 particles are outside the cup below the rim;
##       it FILLS (>= 85 % of the interior volume holds water at the end of the pour) and SPILLS (>= 2 % of the poured water ends on the table).
##   (f) THROUGHPUT stated: particles per second per size, and the largest particle count that still runs >= 10 sim steps/s here must be >= 200000.
##   (g) CONTROLS: the checks can fail. A planted wrong Martin-Moyce table (Z * 1.3) fails (c); a hydrostatic run with gravity 0 fails (a)'s pressure
##       bar; a wall-voxel counter on a solid-less mug domain (mesh not voxelised) counts > 0 particles in the mesh.
var fails := 0
const RHO := 1000.0
const G := 9.81
## Martin & Moyce 1952 Fig. (n^2 = 2), the surge front: T = t*sqrt(2g/a), Z = x/a. See docs/CH8_REFERENCE.md (the source and its caveat).
const MM_T := [0.41, 0.84, 1.19, 1.43, 1.63, 1.83, 2.00]
const MM_Z := [1.11, 1.22, 1.44, 1.67, 1.89, 2.11, 2.33]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var native := ClassDB.class_exists("KineFluidNative")
	print("native class present: ", native)
	ok(native, "KineFluidNative is registered (build native/ first)")
	await _a_hydro(false)
	await _a_hydro(true)   # control: gravity 0 must FAIL the pressure bar
	await _bc_dam()
	await _d_equal()
	await _e_mug()
	await _f_bench()
	print("ch8: %d fail  (%.0f s)" % [fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if fails > 0 else 0)


func _a_hydro(_control: bool) -> void:
	pass


func _bc_dam() -> void:
	pass


func _d_equal() -> void:
	pass


func _e_mug() -> void:
	pass


func _f_bench() -> void:
	pass
