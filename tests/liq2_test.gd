extends SceneTree
## L5 LIQUIDS (11-05): cut-cell solid walls for the CH8 APIC liquid, then the render. godot --headless --path . -s tests/liq2_test.gd
## Method: Batty, Bertails and Bridson 2007, "A fast variational framework for accurate solid-fluid coupling", SIGGRAPH: a solid signed distance field on the
## cell corners gives every face an open area fraction; the pressure matrix, the divergence and the pressure gradient are weighted by it (native + GDScript twin).
## Bars written and committed BEFORE the first run of this suite. No CH8 bar is edited here; the CH8 bars keep running in tests/ch8_test.gd.
##   (A1) FACE FRACTIONS are analytic: a tilted half-space cuts a 12^3 grid (h = 0.1); every u/v/w face weight equals the area fraction found by 400 x 400
##        sub-sampling of that face, within 0.005 (weights below wmin = 0.02 read 0). CONTROL: the same sampling against a half-space with the normal flipped
##        in x must differ by more than 0.005 somewhere.
##   (A2) C++ == GDScript with cut solids active: 12^3, h = 0.05, a cut box off the grid planes + a tilted cut half-space + a free fluid block, 20 steps:
##        every face weight and every particle position and velocity within 1e-6 (threads = 1). CONTROL: wmin = 0.3 in one arm differs by more than 1e-6.
##   (B1) HYDROSTATIC REST on a floor tilted 15 degrees (not on the grid): a flat water level settles 1.5 s. Max particle speed < 1e-3 m/s; the pressure of the
##        bottom layer over the flat part of the floor is rho g H within 2 %; the level (99th percentile of particle y) moves by at most 0.5 h; 0 particles are
##        on the wrong side of the TRUE (analytic) floor by more than 0.05 h.
##   (B2) CONTROL staircase floor (cells whose centre is under the plane are solid, the old way): the same count of particles through the true floor must be > 0
##        (the wall-penetration check can fail). Its speed and level are printed as information.
##   (B3) WALL VOLUME: the volume the fluid can occupy (open_volume) equals the analytic volume above the tilted floor within 1 %. CONTROL: the conservative
##        voxel staircase of the same plane (any touched cell is solid, as add_solid_mesh does) is off by more than 1 %.
##   (E1..E5) MUG with the real Part "mug" mesh as a CUT solid (add_cut_mesh): the CH8 (e) bars on it: 0 particles inside the mesh by ray parity; no water
##        outside the cup below the rim while under 0.9 of its volume is poured; it FILLS (>= 85 % of the interior holds water at the end of the pour);
##        it SPILLS (>= 2 % ends on the table). CONTROL: the same scene with the voxel mesh (add_solid_mesh) must read below 85 % on the fill bar.
##   (M) Martin and Moyce dam break, verified Table 2, n^2 = 2: the SAME 14 points as CH8 (h), worst error <= 10 %, run on the scene configuration named in
##        FluidScenes.dam_break_mm. CONTROL: the CH8 configuration (free slip, voxel walls) must fail the same 10 % bar.
var fails := 0
const G := 9.81
const RHO := 1000.0
const MMV_T := [0.41, 0.84, 1.19, 1.43, 1.63, 1.83, 1.98, 2.20, 2.32, 2.51, 2.65, 2.83, 2.97, 3.11]
const MMV_Z := [1.11, 1.22, 1.44, 1.67, 1.89, 2.11, 2.33, 2.56, 2.78, 3.00, 3.22, 3.44, 3.67, 3.89]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var native := Fluid.native()
	ok(native, "KineFluidNative is registered (build native/ first)")
	if native:
		_a1_fractions()
		_a2_equal()
		_b_rest()
		_m_dam()
		await _e_mug()
	print("liq2: %d fail  (%.0f s)" % [fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if fails > 0 else 0)


## ---------------------------------------------------------------- A1
func _sample_face(plane_p: Vector3, plane_n: Vector3, org: Vector3, h: float, axis: int, i: int, j: int, k: int) -> float:
	# the face of axis `axis` at lower-corner index (i, j, k): spans the two other axes over one cell
	var n := 400
	var open := 0
	var t1 := (axis + 1) % 3
	var t2 := (axis + 2) % 3
	var base := org + Vector3(i, j, k) * h
	for a in n:
		for b in n:
			var p := base
			p[t1] += (a + 0.5) / n * h
			p[t2] += (b + 0.5) / n * h
			if (p - plane_p).dot(plane_n.normalized()) >= 0.0:
				open += 1
	return float(open) / float(n * n)


func _a1_fractions() -> void:
	var pp := Vector3(0.43, 0.37, 0.52)
	var pn := Vector3(1.0, 0.5, 0.2)
	var F = Fluid.make()
	F.setup(12, 12, 12, 0.1, Vector3.ZERO)
	F.add_cut_halfspace(pp, pn)
	F.rebuild_weights()
	var w: PackedFloat64Array = F.face_weights()
	var nc := 12 * 12 * 12
	var worst := 0.0
	var worst_flip := 0.0
	var checked := 0
	var flipn := Vector3(-1.0, 0.5, 0.2)
	for k in range(2, 10):
		for j in range(2, 10):
			for i in range(2, 10):
				var c := i + 12 * (j + 12 * k)
				# face of cell c towards +x is the u face at index i + 1 (between cells i and i + 1), etc.
				var sx := _sample_face(pp, pn, Vector3.ZERO, 0.1, 0, i + 1, j, k)
				var sy := _sample_face(pp, pn, Vector3.ZERO, 0.1, 1, i, j + 1, k)
				var sz := _sample_face(pp, pn, Vector3.ZERO, 0.1, 2, i, j, k + 1)
				var ex := [0.0 if sx < 0.02 else sx, 0.0 if sy < 0.02 else sy, 0.0 if sz < 0.02 else sz]
				var got := [w[c], w[nc + c], w[2 * nc + c]]
				var fx := _sample_face(pp, flipn, Vector3.ZERO, 0.1, 0, i + 1, j, k)
				for a in 3:
					worst = maxf(worst, absf(got[a] - ex[a]))
				worst_flip = maxf(worst_flip, absf(got[0] - (0.0 if fx < 0.02 else fx)))
				checked += 3
	ok(worst <= 0.005, "(A1) %d face weights from the corner field equal the sub-sampled areas: worst |dw| = %.5f (bar 0.005)" % [checked, worst])
	ok(worst_flip > 0.005, "(g) CONTROL a half-space with the x normal flipped differs from the weights by %.3f (> 0.005: the comparison can fail)" % worst_flip)


## ---------------------------------------------------------------- A2
func _a2_run(gd: bool, wmin: float) -> Array:
	var F = Fluid.make(gd)
	F.setup(12, 12, 12, 0.05, Vector3.ZERO)
	F.set_params(9.81, 0.2, 0.5, 0.01, 300, 1e-6)
	F.set_threads(1)
	F.add_cut_box(Vector3(0.21, 0.07, 0.07), Vector3(0.38, 0.19, 0.5))
	F.add_cut_halfspace(Vector3(0.3, 0.12, 0.0), Vector3(0.5, 1.0, 0.1))
	F.set_cut_wmin(wmin)
	F.add_fluid_box(Vector3(0.08, 0.28, 0.1), Vector3(0.45, 0.45, 0.4), Vector3(0.2, 0.0, 0.1), 7)
	for s in 20:
		F.step(0.01)
	return [F.face_weights(), F.particle_data()]


func _a2_equal() -> void:
	var a: Array = _a2_run(false, 0.02)
	var b: Array = _a2_run(true, 0.02)
	var md := 0.0
	var mw := 0.0
	var wa: PackedFloat64Array = a[0]
	var wb: PackedFloat64Array = b[0]
	for i in mini(wa.size(), wb.size()):
		mw = maxf(mw, absf(wa[i] - wb[i]))
	var pa: PackedFloat64Array = a[1]
	var pb: PackedFloat64Array = b[1]
	for i in mini(pa.size(), pb.size()):
		md = maxf(md, absf(pa[i] - pb[i]))
	ok(wa.size() == wb.size() and wa.size() > 0 and pa.size() == pb.size() and pa.size() > 0 and mw <= 1e-6 and md <= 1e-6,
		"(A2) C++ == GDScript with cut solids: %d weights max |dw| = %s, %d values max |dp| = %s (bar 1e-6)" % [wa.size(), String.num_scientific(mw), pa.size(), String.num_scientific(md)])
	var c: Array = _a2_run(false, 0.3)
	var pc: PackedFloat64Array = c[1]
	var cd := 0.0
	for i in mini(pc.size(), pa.size()):
		cd = maxf(cd, absf(pc[i] - pa[i]))
	ok(cd > 1e-6, "(g) CONTROL wmin = 0.3 in one arm differs by %s (> 1e-6: the comparison can fail)" % String.num_scientific(cd))


## ---------------------------------------------------------------- B
const B_H := 0.01
const B_ANG := 15.0
const B_X0 := 0.1
const B_Y0 := 0.05


## the floor y at x for the tilted plane through (B_X0, B_Y0), normal (sin a, cos a, 0)
func _floor_y(x: float) -> float:
	return B_Y0 - tan(deg_to_rad(B_ANG)) * (x - B_X0)


func _basin(mode: String) -> Object:
	var F = Fluid.make()
	F.set_threads(4)
	var nx := 40
	var ny := 30
	var nz := 12
	F.setup(nx, ny, nz, B_H, Vector3.ZERO)
	F.set_params(G, 0.2, 0.5, 0.004, 300, 1e-7)
	var a := deg_to_rad(B_ANG)
	if mode == "cut":
		F.add_cut_halfspace(Vector3(B_X0, B_Y0, 0.0), Vector3(sin(a), cos(a), 0.0))
	else:
		for i in nx:
			var xl := i * B_H
			var top := _floor_y(xl + 0.5 * B_H) if mode == "centre" else _floor_y(xl) + 0.5 * B_H   # centre sampled / conservative (any touched cell)
			if top > B_H:
				F.add_solid_box(Vector3(xl, 0.0, 0.0), Vector3(xl + B_H, top, 1.0))
	return F


func _through_floor(F: Object) -> int:
	var n := 0
	var a := deg_to_rad(B_ANG)
	for p in F.positions():
		var d := sin(a) * (p.x - B_X0) + cos(a) * (p.y - B_Y0)
		if d < -0.05 * B_H and p.y > 1.5 * B_H:   # the domain floor is a straight wall; only the tilted plane is judged
			n += 1
	return n


func _level(F: Object) -> float:
	var ys := []
	for p in F.positions():
		ys.append(p.y)
	ys.sort()
	return ys[int(0.99 * (ys.size() - 1))]


func _b_run(mode: String) -> Dictionary:
	var F = _basin(mode)
	F.add_fluid_box(Vector3(B_H, B_H, B_H), Vector3(0.39, 0.12, 0.11), Vector3.ZERO, 3)
	var l0 := _level(F)
	F.advance(1.5)
	var vmax := 0.0
	var d: PackedFloat64Array = F.particle_data()
	for p in d.size() / 6:
		vmax = maxf(vmax, Vector3(d[6 * p + 3], d[6 * p + 4], d[6 * p + 5]).length())
	# bottom layer over the flat part of the floor: x cells 30..37 (x > 0.3: the plane is at y < 0.0 there), z cells 3..8
	var s := 0.0
	var m := 0
	for k in range(3, 9):
		for i in range(30, 38):
			s += F.get_pressure(i, 1, k)
			m += 1
	return {"vmax": vmax, "p": s / m, "dlevel": absf(_level(F) - l0), "through": _through_floor(F), "F": F}


func _b_rest() -> void:
	var r := _b_run("cut")
	var pe := RHO * G * 0.11   # 11 cells of water (y 0.01 .. 0.12) over the flat floor
	var err: float = absf(r["p"] - pe) / pe
	print("      B1 cut floor: vmax %s m/s, bottom p %.1f Pa (expect %.1f), level moved %.4f m, through-floor %d" % [String.num_scientific(r["vmax"]), r["p"], pe, r["dlevel"], r["through"]])
	ok(r["vmax"] < 1e-3, "(B1) tilted-floor tank at rest: max |v| = %s m/s after 1.5 s (bar < 1e-3)" % String.num_scientific(r["vmax"]))
	ok(err <= 0.02, "(B1) bottom pressure over the flat part %.1f Pa vs rho g H = %.1f Pa: %.2f %% (bar 2 %%)" % [r["p"], pe, err * 100.0])
	ok(r["dlevel"] <= 0.5 * B_H, "(B1) the level (99th percentile of y) moved %.4f m (bar <= 0.5 h = %.4f)" % [r["dlevel"], 0.5 * B_H])
	ok(r["through"] == 0, "(B1) 0 particles through the true (analytic) tilted floor by more than 0.05 h (found %d)" % r["through"])
	var c := _b_run("centre")
	print("      B2 centre-sampled staircase floor: vmax %s m/s, level moved %.4f m, through-floor %d (information: speed and level)" % [String.num_scientific(c["vmax"]), c["dlevel"], c["through"]])
	ok(c["through"] > 0, "(g) CONTROL (B2) staircase floor: %d particles sit through the true floor (> 0: the wall check can fail)" % c["through"])
	# B3 wall volume
	var Fv = _basin("cut")
	var vol_cut: float = Fv.open_volume()
	# analytic: interior box x 0.01..0.39, y 0.01..0.29, z 0.01..0.11 minus the part under the plane
	var vol := 0.0
	var nxs := 4000
	for q in nxs:
		var x := 0.01 + (q + 0.5) / nxs * 0.38
		var yf := clampf(_floor_y(x), 0.01, 0.29)
		vol += (0.29 - yf) * (0.38 / nxs) * 0.10
	var ec: float = absf(vol_cut - vol) / vol
	ok(ec <= 0.01, "(B3) open volume of the cut tank %.6f m3 vs analytic %.6f m3: %.2f %% (bar 1 %%)" % [vol_cut, vol, ec * 100.0])
	var Fc = _basin("conservative")
	var ev: float = absf(float(Fc.open_volume()) - vol) / vol
	ok(ev > 0.01, "(g) CONTROL (B3) the conservative voxel staircase is off by %.2f %% (> 1 %%: the bar can fail)" % [ev * 100.0])


## ---------------------------------------------------------------- M
func _front(F: Object, h: float, a: float) -> float:
	var xf := 0.0
	for p in F.positions():
		if p.y < h + 0.15 * a:
			xf = maxf(xf, p.x)
	return (xf - h) / a


func _mm_worst(cfg: String) -> float:
	var F = Fluid.make()
	F.set_threads(4)
	var sc: Dictionary = FluidScenes.dam_break_mm(F, 20, cfg)
	var a: float = sc["a"]
	var h: float = sc["h"]
	var tscale := sqrt(a / (2.0 * G))
	var t := 0.0
	var worst := 0.0
	var line := []
	for i in MMV_T.size():
		F.advance(MMV_T[i] * tscale - t)
		t = MMV_T[i] * tscale
		var z := _front(F, h, a)
		var e: float = absf(z - MMV_Z[i]) / MMV_Z[i]
		worst = maxf(worst, e)
		line.append("%.2f:%.2f" % [MMV_T[i], z])
	print("      M %s: Z(T) %s" % [cfg, " ".join(line)])
	return worst


func _m_dam() -> void:
	var w := _mm_worst("mm")
	ok(w <= 0.10, "(M) dam break vs Martin & Moyce verified Table 2, configuration 'mm': worst surge-front error %.1f %% over %d points (bar 10 %%)" % [w * 100.0, MMV_T.size()])
	var w0 := _mm_worst("ch8")
	ok(w0 > 0.10, "(g) CONTROL (M) the CH8 configuration (free slip, voxel walls) reads %.1f %% and fails the same 10 %% bar (the bar can fail)" % [w0 * 100.0])


## ---------------------------------------------------------------- E
func _pour(F: Object, m: Dictionary) -> Dictionary:
	var h: float = m["h"]
	var cx: float = m["cx"]
	var cz: float = m["cz"]
	var rim: float = m["rim"]
	var cap: float = m["cap"]
	var step_t := 0.003
	var half := 0.014
	var poured := 0.0
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
		if nsteps % 10 == 0 and poured < 0.9 * cap:
			for p in F.positions():
				if p.y < rim - 3.0 * h and Vector2(p.x - cx, p.z - cz).length() > m["R_out"] + 2.0 * h:
					leak += 1
		if (not pouring and t_end > 0.0 and t >= t_end) or t > 4.0:
			break
	var ps2: PackedVector3Array = F.positions()
	var inside := 0
	var spilled := 0
	for p in ps2:
		var r := Vector2(p.x - cx, p.z - cz).length()
		if r < m["R_in"] and p.y < rim:
			inside += 1
		if r > m["R_out"] + 2.0 * h and p.y < 4.0 * h + 0.003:
			spilled += 1
	return {"held": float(inside) / 8.0 * h * h * h, "cap": cap, "spilled": float(spilled) / ps2.size(), "leak": leak, "n": ps2.size(), "t": t}


func _e_mug() -> void:
	if not Part.available():
		ok(false, "(E) the CAD DLL is needed for the mug part")
		return
	var F = Fluid.make()
	F.set_threads(8)
	var m := FluidScenes.mug_cut(F, 0.003)
	if m.is_empty():
		ok(false, "(E) the mug part built no mesh")
		return
	var r := _pour(F, m)
	var in_mesh: int = F.particles_in_mesh(m["verts"], m["tris"])
	var frac: float = r["held"] / r["cap"]
	print("      mug (cut): %d particles, %.1f s, held %.3f of %.3f L, spilled %.1f %%, open volume %.3f L" % [r["n"], r["t"], r["held"] * 1000.0, r["cap"] * 1000.0, r["spilled"] * 100.0, F.open_volume() * 1000.0])
	ok(in_mesh == 0, "(E1) 0 particles inside the mesh by ray parity (found %d)" % in_mesh)
	ok(r["leak"] == 0, "(E2) no water outside the cup below the rim while under 0.9 of its volume was poured (%d)" % r["leak"])
	ok(frac >= 0.85, "(E3) it fills: %.3f L held inside of %.3f L (%.0f %%, bar 85 %%)" % [r["held"] * 1000.0, r["cap"] * 1000.0, frac * 100.0])
	ok(r["spilled"] >= 0.02, "(E4) it spills: %.1f %% of the water ended outside the cup on the table (bar 2 %%)" % [r["spilled"] * 100.0])
	# control: the voxel mesh
	var F2 = Fluid.make()
	F2.set_threads(8)
	var m2 := FluidScenes.mug(F2, 0.003)
	var r2 := _pour(F2, m2)
	var f2: float = r2["held"] / r2["cap"]
	ok(f2 < 0.85, "(g) CONTROL (E3) the voxel mesh (add_solid_mesh) holds %.0f %% and fails the same 85 %% bar (the bar can fail)" % [f2 * 100.0])
