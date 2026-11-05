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
##   (c2) AVERAGE FRONT SPEED vs the CITED measurements (added 11-04, committed before its first run; the lead's decision on bar (c)).
##       n^2 = 1 square column (scene FluidScenes.dam_square), H = a. Definition as in the source: non-dimensional time tau = t*sqrt(g/H), average front
##       speed v/sqrt(gH) of the surge on the dry bed for tau > 1 (Table 1 of arXiv:1308.0115, Fig. 12; cross-check arXiv:2108.08769 sec 3.3.2).
##       The source gives no end of window; MINE: tau in [1, 2], v = (Z(2) - Z(1)) / 1 with Z = x/H as in bar (c). PASS if v lies in the published
##       experimental span 1.48 .. 1.74 (Martin & Moyce H = 57 mm 1.48, H = 114 mm 1.69; Dressler 1954 H = 55/110/220 mm 1.54/1.70/1.74).
##       CONTROL: the frictionless Ritter value 2.0 must FAIL the same band test.
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
	var native := Fluid.native()
	print("native class present: ", native)
	ok(native, "KineFluidNative is registered (build native/ first)")
	await _a_hydro(false)
	await _a_hydro(true)   # control: gravity 0 must FAIL the pressure bar
	await _bc_dam()
	await _c2_speed()
	await _d_equal()
	await _e_mug()
	await _h_verified()
	await _i_bars()
	await _f_bench()
	print("ch8: %d fail  (%.0f s)" % [fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if fails > 0 else 0)


## (c2) average surge-front speed over tau in [1, 2] for the square column, in units of sqrt(g H)
const C2_LO := 1.48
const C2_HI := 1.74


func _c2_speed() -> void:
	var F = Fluid.make()
	F.set_threads(4)
	var sc := FluidScenes.dam_square(F, 20)
	var a: float = sc["a"]
	var h: float = sc["h"]
	var t := 0.0
	var z := []
	for tau in [1.0, 2.0]:
		var tt: float = tau * sqrt(a / G)   # tau = t sqrt(g/H), H = a
		F.advance(tt - t)
		t = tt
		z.append(_front(F, h))
	var v: float = (z[1] - z[0]) / (2.0 - 1.0)
	print("      c2: Z(tau=1) = %.3f  Z(tau=2) = %.3f  average front speed = %.6f sqrt(gH)" % [z[0], z[1], v])
	ok(v >= C2_LO and v <= C2_HI, "(c2) average front speed %.6f sqrt(gH) over tau 1..2 is inside the published span %.2f .. %.2f (arXiv:1308.0115 Table 1)" % [v, C2_LO, C2_HI])
	ok(not (2.0 >= C2_LO and 2.0 <= C2_HI), "(g) CONTROL the frictionless Ritter value 2.0 fails the c2 span (the bar can fail)")


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
	ok(r["vmax"] < 1e-3, "(a) hydrostatic: max |v| = %s m/s after 1 s (bar < 1e-3)" % String.num_scientific(r["vmax"]))
	var err: float = absf(r["p_bottom"] - r["p_expect"]) / r["p_expect"]
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
		var e: float = absf(zs[i] - MM_Z[i]) / MM_Z[i]
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
	ok(a.size() == b.size() and a.size() > 0 and md <= 1e-6, "(d) C++ == GDScript, 16^3, 20 steps: %d values, max |diff| = %s (bar 1e-6)" % [a.size(), String.num_scientific(md)])
	# control: a different seed must differ by far more than the bar
	var F3 = Fluid.make(true)
	F3.setup(16, 16, 16, 0.05, Vector3.ZERO)
	F3.add_fluid_box(Vector3(0.1, 0.3, 0.1), Vector3(0.4, 0.5, 0.35), Vector3(0.2, 0, 0.1), 8)
	var c: PackedFloat64Array = F3.particle_data()
	var cd := 0.0
	for i in mini(c.size(), a.size()):
		cd = maxf(cd, absf(c[i] - a[i]))
	ok(cd > 1e-6, "(g) CONTROL a different seed differs by %s (> 1e-6: the comparison can fail)" % String.num_scientific(cd))


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


## ===== CH8b bars (added 11-04 by lane CH8b; bar text written and committed BEFORE its first run; no existing bar above was edited) =====
## Martin & Moyce 1952 Table 2 (rectangular section, plane symmetry, n^2 = 2), the "mean" column of the a = 2 1/4 in runs, read from the scan of the paper
## (Phil. Trans. R. Soc. A 244, p. 317; scan at www.math.ntu.edu.tw/~shyue/orch08/benchmarks/lowmach/broken-dam/91519.pdf). T = n t sqrt(g/a) = t sqrt(2g/a),
## Z = x/a from the axis of symmetry. Rows with Z > 4 are not used (the tank wall of the scene is at Z = 4).
const MMV_T := [0.41, 0.84, 1.19, 1.43, 1.63, 1.83, 1.98, 2.20, 2.32, 2.51, 2.65, 2.83, 2.97, 3.11]
const MMV_Z := [1.11, 1.22, 1.44, 1.67, 1.89, 2.11, 2.33, 2.56, 2.78, 3.00, 3.22, 3.44, 3.67, 3.89]


func _peak_count(F: Object) -> int:
	var h := 0.01   # the dam-break scene: a / 20
	var cnt := {}
	var peak := 0
	for p in F.positions():
		var key := int(floor(p.x / h)) + 1000 * int(floor(p.y / h)) + 1000000 * int(floor(p.z / h))
		var n: int = cnt.get(key, 0) + 1
		cnt[key] = n
		peak = maxi(peak, n)
	return peak


## (h) dam break against the VERIFIED table; (h2) the remembered table of bar (c) against the paper; (b2) peak cell count; (b3) the legacy drift as control
func _h_verified() -> void:
	var rows := []
	# compared in whole hundredths (both tables are printed to 2 decimals): in binary floats 2.00 - 1.98 = 0.020000000000000018 > 0.02, which failed
	# the row that the bar's own text accepts (|dT| <= 0.02). Same tolerance as written; only the float round-off is removed (CH8b, 11-04).
	for i in MM_T.size():
		var hit := false
		for j in MMV_T.size():
			if absi(roundi(MM_T[i] * 100.0) - roundi(MMV_T[j] * 100.0)) <= 2 and absi(roundi(MM_Z[i] * 100.0) - roundi(MMV_Z[j] * 100.0)) <= 1:
				hit = true
		rows.append(hit)
	ok(not rows.has(false), "(h2) the remembered table of bar (c) equals the paper's Table 2 mean column row by row (|dT| <= 0.02, |dZ| <= 0.01): %s" % str(rows))
	var bad_hit := false
	for j in MMV_T.size():
		if absf(MM_T[1] - MMV_T[j]) <= 0.02 and absf(1.3 * MM_Z[1] - MMV_Z[j]) <= 0.01:
			bad_hit = true
	ok(not bad_hit, "(g) CONTROL a planted row (Z x 1.3) does not match the paper's table (the table check can fail)")
	var F = Fluid.make()
	F.set_threads(4)
	var sc := FluidScenes.dam_break(F, 20)
	var a: float = sc["a"]
	var h: float = sc["h"]
	var tscale := sqrt(a / (2.0 * G))
	var t := 0.0
	var worst := 0.0
	var worst_planted := false
	var peak := 0
	var worst_v := 1.0
	var worst_vs := 1.0
	var lines := []
	for i in MMV_T.size():
		F.advance(MMV_T[i] * tscale - t)
		t = MMV_T[i] * tscale
		var z := _front(F, h)
		var e: float = absf(z - MMV_Z[i]) / MMV_Z[i]
		worst = maxf(worst, e)
		if absf(z - 1.3 * MMV_Z[i]) / (1.3 * MMV_Z[i]) > 0.10:
			worst_planted = true
		lines.append("T %.2f Z sim %.3f paper %.2f (%.1f %%)" % [MMV_T[i], z, MMV_Z[i], e * 100.0])
		peak = maxi(peak, _peak_count(F))
		worst_v = minf(worst_v, F.volume_ratio())
		worst_vs = minf(worst_vs, F.volume_smooth())
	for l in lines:
		print("      ", l)
	# the rest of bar (b)'s window, to T = 5 (past the wall hit), for the peak count and the smooth volume
	var T3 := 3.25
	while T3 <= 5.0 + 1e-9:
		F.advance(T3 * tscale - t)
		t = T3 * tscale
		peak = maxi(peak, _peak_count(F))
		worst_v = minf(worst_v, F.volume_ratio())
		worst_vs = minf(worst_vs, F.volume_smooth())
		T3 += 0.25
	ok(worst <= 0.10, "(h) dam break vs Martin & Moyce, VERIFIED table (paper Table 2, mean, a = 2 1/4 in): worst surge-front error %.1f %% over %d points (bar 10 %%)" % [worst * 100.0, MMV_T.size()])
	ok(worst_planted, "(g) CONTROL the planted verified table (Z x 1.3) fails the 10 %% bar (the bar can fail)")
	ok(peak <= 12, "(b2) peak cell count %d <= 12 (1.5 x rest density, 8 per cell) at every sampled T of the dam break to T = 5" % peak)
	print("      (b) statistic on this run: worst V/V0 = %.4f (min(count, 8) per cell, the lattice-phase sensitive one)" % worst_v)
	ok(worst_vs >= 0.98, "(b4) smooth volume (B-spline density at the cell centres, capped at rest density; a partition of unity, so lattice phase does not enter): worst %.4f over the dam break to T = 5 (bar >= 0.98)" % worst_vs)
	# controls for (b4): a block with DOUBLE the particles per cell (two overlapping seeds) reads about 0.5; and the lattice-phase demonstration:
	# a block translated rigidly (gravity 0, no deformation, nothing compressed) must read >= 0.98 by (b4) while the min(count, 8) statistic of (b) reads lower
	var Fd = Fluid.make()
	Fd.setup(30, 30, 30, 0.01, Vector3.ZERO)
	Fd.add_fluid_box(Vector3(0.08, 0.08, 0.08), Vector3(0.18, 0.18, 0.18), Vector3.ZERO, 3)
	Fd.add_fluid_box(Vector3(0.08, 0.08, 0.08), Vector3(0.18, 0.18, 0.18), Vector3.ZERO, 4)
	var vd: float = Fd.volume_smooth()
	ok(vd < 0.98, "(g) CONTROL a block with twice the rest density reads %.3f by (b4) (the bar can fail)" % vd)
	var Fs = Fluid.make()
	Fs.setup(30, 30, 30, 0.01, Vector3.ZERO)
	Fs.set_params(0.0, 0.2, 0.5, 0.004, 300, 1e-7)
	Fs.set_threads(1)
	Fs.add_fluid_box(Vector3(0.08, 0.08, 0.08), Vector3(0.18, 0.18, 0.18), Vector3(0.37, 0.21, 0.5), 3)
	Fs.advance(0.036)
	var v_old: float = Fs.volume_ratio()
	var v_new: float = Fs.volume_smooth()
	ok(v_new >= 0.98 and v_old < 0.98, "(b4) lattice-phase demonstration: a block translated rigidly with gravity 0 reads %.4f by the smooth volume and %.4f by bar (b)'s min(count, 8) statistic (nothing was compressed)" % [v_new, v_old])
	# control for (b2): the first-version density drift in the velocity solve (dmode 0) must break the same cap
	var F0 = Fluid.make()
	F0.set_threads(4)
	FluidScenes.dam_break(F0, 20)
	F0.set_density_mode(0)
	var t0 := 0.0
	var peak0 := 0
	for T in [1.0, 2.0, 3.0, 4.0, 5.0]:
		F0.advance(T * tscale - t0)
		t0 = T * tscale
		peak0 = maxi(peak0, _peak_count(F0))
	ok(peak0 > 12, "(g) CONTROL the first-version drift (density mode 0) breaks the same cap: peak %d > 12 (the cap bar can fail)" % peak0)


## (a2) settled tank speed 10x tighter than (a); (d2) C++ == GDScript with the density projection ACTIVE; (r) surface volume
func _i_bars() -> void:
	var r := _tank(G)
	ok(r["vmax"] < 1e-4, "(a2) hydrostatic: max |v| = %s m/s after 1 s (bar < 1e-4, ten times tighter than (a))" % String.num_scientific(r["vmax"]))
	# (d2): two overlapping boxes put 16 particles in the overlap cells, so the projection has real excess to push away
	var out := []
	for mode in [1, 1, 0]:
		var gd: bool = out.size() == 1
		var F = Fluid.make(gd)
		F.setup(16, 16, 16, 0.05, Vector3.ZERO)
		F.set_params(9.81, 0.2, 0.5, 0.01, 300, 1e-6)
		F.set_threads(1)
		F.set_density_mode(mode)
		F.add_solid_box(Vector3(0.25, 0.05, 0.05), Vector3(0.55, 0.2, 0.5))
		F.add_fluid_box(Vector3(0.1, 0.3, 0.1), Vector3(0.4, 0.5, 0.35), Vector3(0.2, 0, 0.1), 7)
		F.add_fluid_box(Vector3(0.2, 0.3, 0.1), Vector3(0.45, 0.45, 0.3), Vector3(0.2, 0, 0.1), 9)
		for s in 20:
			F.step(0.01)
		out.append(F.particle_data())
	var a1: PackedFloat64Array = out[0]
	var a2: PackedFloat64Array = out[1]
	var a3: PackedFloat64Array = out[2]
	var md := 0.0
	var mc := 0.0
	for i in mini(a1.size(), a2.size()):
		md = maxf(md, absf(a1[i] - a2[i]))
	for i in mini(a1.size(), a3.size()):
		mc = maxf(mc, absf(a1[i] - a3[i]))
	ok(a1.size() == a2.size() and a1.size() > 0 and md <= 1e-6, "(d2) C++ == GDScript with density projection active (16^3, 20 steps, overlapping boxes): max |diff| = %s (bar 1e-6)" % String.num_scientific(md))
	ok(mc > 1e-6, "(g) CONTROL density mode 0 differs from mode 1 by %s (> 1e-6: the projection is really active in that scene)" % String.num_scientific(mc))
	# (r) the reconstructed surface of the settled tank encloses the particles' volume within 10 %
	var F2 = Fluid.make()
	if not F2.has_method("surface_aniso"):
		ok(false, "(r) native surface_aniso is needed")
		return
	F2.setup(14, 20, 14, 0.01, Vector3.ZERO)
	F2.set_params(G, 0.2, 0.5, 0.004, 300, 1e-7)
	F2.set_threads(4)
	var n: int = F2.add_fluid_box(Vector3(0.01, 0.01, 0.01), Vector3(0.13, 0.11, 0.13), Vector3.ZERO, 3)
	F2.advance(1.0)
	var vol_p := float(n) / 8.0 * pow(0.01, 3)
	var sf: Dictionary = F2.surface_aniso(0.5, 4)
	var vs: PackedVector3Array = sf["verts"]
	var vol_m := 0.0
	for i in range(0, vs.size() - 2, 3):
		vol_m += vs[i].dot(vs[i + 1].cross(vs[i + 2])) / 6.0
	vol_m = absf(vol_m)
	print("      (r) mesh %d triangles, enclosed volume %.6f m3, particles %.6f m3" % [vs.size() / 3, vol_m, vol_p])
	ok(vs.size() >= 3 and absf(vol_m - vol_p) / vol_p <= 0.10, "(r) surface_aniso encloses %.1f %% of the particle volume (bar within 10 %%)" % [100.0 * vol_m / vol_p])
	ok(absf(vol_m - 1.3 * vol_p) / (1.3 * vol_p) > 0.10, "(g) CONTROL a planted volume (particles x 1.3) fails the same 10 %% bar (the bar can fail)")
