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


func _maxspeed(d: PackedFloat64Array) -> float:
	var m := 0.0
	for p in d.size() / 6:
		m = maxf(m, Vector3(d[6 * p + 3], d[6 * p + 4], d[6 * p + 5]).length())
	return m


## (a) the settled tank; returns {vmax, p_bottom, p_expect}
func _tank(g: float) -> Dictionary:
	var F = Fluid.make()
	F.setup(14, 20, 14, 0.01, Vector3.ZERO)
	F.set_params(g, 0.2, 0.5, 0.004, 300, 1e-7)
	F.set_threads(4)
	var n: int = F.add_fluid_box(Vector3(0.01, 0.01, 0.01), Vector3(0.13, 0.11, 0.13), Vector3.ZERO, 3)
	F.advance(1.0)
	var d: PackedFloat64Array = F.particle_data()
	var sum := 0.0
	for k in range(1, 13):
		for i in range(1, 13):
			sum += F.get_pressure(i, 1, k)
	var H: float = (float(n) / 8.0) * pow(0.01, 3) / (12.0 * 12.0 * 0.0001)
	return {"vmax": _maxspeed(d), "p_bottom": sum / 144.0, "p_expect": RHO * G * H, "H": H}


func _a_hydro(control: bool) -> void:
	if control:
		var c := _tank(0.0)
		ok(absf(c["p_bottom"] - c["p_expect"]) > 0.02 * c["p_expect"], "(g) CONTROL gravity 0: bottom pressure %.1f Pa is NOT within 2 %% of rho g H = %.1f (the bar can fail)" % [c["p_bottom"], c["p_expect"]])
		return
	var r := _tank(G)
	ok(r["vmax"] < 1e-3, "(a) hydrostatic: max |v| = %.2e m/s after 1 s (bar < 1e-3)" % r["vmax"])
	var err := absf(r["p_bottom"] - r["p_expect"]) / r["p_expect"]
	ok(err <= 0.02, "(a) hydrostatic: bottom layer %.1f Pa vs rho g H = %.1f Pa (H = %.4f m): %.2f %% (bar 2 %%)" % [r["p_bottom"], r["p_expect"], r["H"], err * 100.0])


func _front(F: Object, h: float) -> float:
	var ps: PackedVector3Array = F.positions()
	var xf := 0.0
	for p in ps:
		if p.y < h + 0.15 * FluidScenes.MM_A:
			xf = maxf(xf, p.x)
	return (xf - h) / FluidScenes.MM_A


func _bc_dam() -> void:
	var F = Fluid.make()
	F.set_threads(4)
	var sc := FluidScenes.dam_break(F, 20)
	var a: float = sc["a"]
	var h: float = sc["h"]
	var tscale := sqrt(a / (2.0 * G))   # t = T * tscale
	var t := 0.0
	var worst_v := 1.0
	var zs := []
	var ritter_ok := true
	var rows := []
	# sample every table T, and every 0.25 T up to 5 for the volume and the Ritter bound
	var targets := []
	for T in MM_T:
		targets.append(T)
	var T2 := 0.25
	while T2 <= 5.0:
		targets.append(T2)
		T2 += 0.25
	targets.sort()
	for T in targets:
		F.advance(T * tscale - t)
		t = T * tscale
		var v: float = F.volume_ratio()
		worst_v = minf(worst_v, v)
		var z := _front(F, h)
		if z > 1.0 + 2.0 * T + 0.05:
			ritter_ok = false
		if MM_T.has(T):
			zs.append(z)
			rows.append("T %.2f  Z sim %.3f  M&M %.2f" % [T, z, MM_Z[MM_T.find(T)]])
	for r in rows:
		print("      ", r)
	ok(worst_v >= 0.98, "(b) volume: worst V/V0 = %.4f over the dam break to T = 5 (bar >= 0.98)" % worst_v)
	ok(ritter_ok, "(c) physics bound: Z <= 1 + 2T (Ritter) at every sampled T")
	var all_in := true
	var worst := 0.0
	for i in MM_T.size():
		var e := absf(zs[i] - MM_Z[i]) / MM_Z[i]
		worst = maxf(worst, e)
		if e > 0.10:
			all_in = false
	ok(all_in, "(c) dam break vs Martin & Moyce: worst surge-front error %.1f %% over %d points (bar 10 %%)" % [worst * 100.0, MM_T.size()])
	var planted := false
	for i in MM_T.size():
		if absf(zs[i] - 1.3 * MM_Z[i]) / (1.3 * MM_Z[i]) > 0.10:
			planted = true
	ok(planted, "(g) CONTROL a planted table (Z x 1.3) fails the 10 %% bar (the bar can fail)")
	print("      stats: ", F.stats())


func _d_equal() -> void:
	var out := []
	for gd in [false, true]:
		var F = Fluid.make(gd)
		F.setup(16, 16, 16, 0.05, Vector3.ZERO)
		F.set_params(9.81, 0.2, 0.5, 0.01, 300, 1e-6)
		F.set_threads(1)
		F.add_solid_box(Vector3(0.25, 0.05, 0.05), Vector3(0.55, 0.2, 0.5))
		F.add_fluid_box(Vector3(0.1, 0.3, 0.1), Vector3(0.4, 0.5, 0.35), Vector3(0.2, 0, 0.1), 7)
		var t0 := Time.get_ticks_msec()
		for s in 20:
			F.step(0.01)
		print("      %s: %d particles, 20 steps, %d ms" % ["GDScript" if gd else "C++", F.particle_count(), Time.get_ticks_msec() - t0])
		out.append(F.particle_data())
	var a: PackedFloat64Array = out[0]
	var b: PackedFloat64Array = out[1]
	var md := 0.0
	for i in mini(a.size(), b.size()):
		md = maxf(md, absf(a[i] - b[i]))
	ok(a.size() == b.size() and a.size() > 0 and md <= 1e-6, "(d) C++ == GDScript, 16^3, 20 steps: %d values, max |diff| = %.2e (bar 1e-6)" % [a.size(), md])
	# control: a different seed must differ by far more than the bar
	var F3 = Fluid.make(true)
	F3.setup(16, 16, 16, 0.05, Vector3.ZERO)
	F3.add_fluid_box(Vector3(0.1, 0.3, 0.1), Vector3(0.4, 0.5, 0.35), Vector3(0.2, 0, 0.1), 8)
	var c: PackedFloat64Array = F3.particle_data()
	var cd := 0.0
	for i in mini(c.size(), a.size()):
		cd = maxf(cd, absf(c[i] - a[i]))
	ok(cd > 1e-6, "(g) CONTROL a different seed differs by %.2e (> 1e-6: the comparison can fail)" % cd)


func _e_mug() -> void:
	if not Part.available():
		ok(false, "(e) the CAD DLL is needed for the mug part")
		return
	var F = Fluid.make()
	F.set_threads(8)
	var m := FluidScenes.mug(F, 0.003)
	if m.is_empty():
		ok(false, "(e) the mug part built no mesh")
		return
	print("      mug box ", m["bb"], " solid voxels ", F.solid_count(), " (added by the mesh ", m["solid_added"], ")")
	var h: float = m["h"]
	var cx: float = m["cx"]
	var cz: float = m["cz"]
	var rim: float = m["rim"]
	var cap: float = m["cap"]
	var step_t := 0.003
	var half := 0.014
	var poured := 0.0
	var max_in_solid := 0
	var leak := 0
	var t := 0.0
	var seed_i := 100
	var pouring := true
	var t_end := 0.0
	var nsteps := 0
	while true:
		F.advance(step_t)
		t += step_t
		nsteps += 1
		if pouring:
			var n: int = F.add_fluid_box(Vector3(cx - half, rim + 0.03, cz - half), Vector3(cx + half, rim + 0.03 + h, cz + half), Vector3(0, -1.0, 0), seed_i)
			seed_i += 1
			poured += float(n) / 8.0 * h * h * h
			if poured >= 1.5 * cap:
				pouring = false
				t_end = t + 0.8
		if nsteps % 10 == 0:
			max_in_solid = maxi(max_in_solid, F.particles_in_solid())
			if poured < 0.9 * cap:
				var ps: PackedVector3Array = F.positions()
				for p in ps:
					if p.y < rim - 3.0 * h and Vector2(p.x - cx, p.z - cz).length() > m["R_out"] + 2.0 * h:
						leak += 1
		if (not pouring and t >= t_end) or t > 4.0:
			break
	var ps2: PackedVector3Array = F.positions()
	var n_all := ps2.size()
	var inside := 0
	var spilled := 0
	for p in ps2:
		var r := Vector2(p.x - cx, p.z - cz).length()
		if r < m["R_in"] and p.y < rim:
			inside += 1
		if r > m["R_out"] + 2.0 * h and p.y < 4.0 * h + 0.003:
			spilled += 1
	var held := float(inside) / 8.0 * h * h * h
	var mesh_n: int = F.particles_in_mesh(m["verts"], m["tris"])
	print("      pour: %.1f s simulated, %d particles, poured %.3f L (cup holds %.3f L), %d steps" % [t, n_all, poured * 1000.0, cap * 1000.0, nsteps])
	ok(max_in_solid == 0 and F.particles_in_solid() == 0, "(e) 0 particles in wall voxels at every check (max %d)" % max_in_solid)
	ok(mesh_n == 0, "(e) 0 particles inside the mesh by ray parity (found %d)" % mesh_n)
	ok(leak == 0, "(e) no water outside the cup below the rim while under 0.9 of its volume was poured (%d)" % leak)
	ok(held >= 0.85 * cap, "(e) it fills: %.3f L held inside of %.3f L (%.0f %%, bar 85 %%)" % [held * 1000.0, cap * 1000.0, held / cap * 100.0])
	ok(float(spilled) / n_all >= 0.02, "(e) it spills: %.1f %% of the water ended outside the cup on the table (bar 2 %%)" % [100.0 * spilled / n_all])
	# control: the same mesh, NOT voxelised: water placed in the walls is counted inside the mesh
	var F2 = Fluid.make()
	var m2 := FluidScenes.mug(F2, 0.003, false)
	F2.add_fluid_box(Vector3(m2["cx"] - 0.045, m2["h"] * 2.0, m2["cz"] - 0.045), Vector3(m2["cx"] + 0.045, m2["h"] * 12.0, m2["cz"] + 0.045), Vector3.ZERO, 1)
	var c_in: int = F2.particles_in_mesh(m2["verts"], m2["tris"])
	ok(c_in > 0 and F2.solid_count() < F.solid_count(), "(g) CONTROL the mesh without its voxels: %d particles sit inside the walls (the counter can fail)" % c_in)


func _f_bench() -> void:
	var best := 0
	for target in [50000, 100000, 200000, 400000, 800000, 1200000]:
		var s := int(round(pow(float(target) / 2.0, 1.0 / 3.0)))
		var F = Fluid.make()
		F.set_threads(8)
		F.setup(s + 2, s + 2, s + 2, 0.01, Vector3.ZERO)
		F.set_params(9.81, 0.2, 0.5, 0.002, 200, 1e-6)
		var half := s / 2
		var n: int = F.add_fluid_box(Vector3(0.01, 0.01, 0.01), Vector3((1 + half) * 0.01, (1 + half) * 0.01, (1 + s) * 0.01), Vector3.ZERO, 5)
		for i in 10:
			F.step(0.002)
		var t0 := Time.get_ticks_usec()
		for i in 5:
			F.step(0.002)
		var per := (Time.get_ticks_usec() - t0) / 5.0 / 1e6
		var sps := 1.0 / per
		print("      %8d particles  %7.1f ms/step  %6.2f steps/s  %.2f M particles/s   %s" % [n, per * 1000.0, sps, n * sps / 1e6, F.stats()])
		if sps >= 10.0:
			best = maxi(best, n)
		if sps < 3.0:
			break
	ok(best >= 200000, "(f) the largest count at >= 10 sim steps/s here: %d particles (bar >= 200000; the 1M goal is reported by the table above)" % best)
