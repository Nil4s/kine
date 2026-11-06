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
		await _r_render()
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


## ================================================================ RENDER bars (R), written and committed before their first run
## The water shader (shaders/water_v2.gdshader) and the thickness pass (shaders/water_thick.gdshader), measured on analytic meshes so that the
## prediction does not come from the renderer. Pixels are decoded from sRGB to linear light before any number is taken.
##   (R0) THICKNESS PASS: a closed box 0.20 m deep seen head on reads 0.20 m within 3 % in the thickness map.
##   (R1) FRESNEL: a water slab with a white sky and a black floor, seen at 80 and at 10 degrees from the surface normal: the reflected fraction F (pixel
##        in linear light) is within 10 % (relative) of Schlick, F = F0 + (1 - F0)(1 - cos)^5, F0 = ((n-1)/(n+1))^2, n = 1.333, at both angles; so the edge
##        brightening ratio F(80)/F(10) matches (about 19). CONTROL: the Fresnel term switched off (constant F0) must fail the ratio (reads about 1).
##   (R2) BEER-LAMBERT: a water wedge over a white floor, seen from above. Its colour shift B - R at the path lengths 0.10, 0.20, 0.30 m equals the prediction
##        (1 - F0)(exp(-sigma_B t) - exp(-sigma_R t)) within 25 % (sigma = pure water, Pope and Fry 1997: R 0.2916, G 0.0565, B 0.00922 per m), and
##        grows with t. CONTROL: absorption switched off must fail.
##   (R3) NO VISIBLE SHELL: the reconstructed surface of the dam break at T = 2 is a closed mesh (fraction of welded edges not shared by exactly two
##        triangles <= 2 %), and in its thickness map at most 0.5 % of the covered pixels are incoherent (an odd number of faces crossed, or a negative
##        thickness: the signature of a hole through which the shell shows). CONTROL: the same mesh with 8 % of its triangles removed must exceed both.
func _slab_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var v := [Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)]
	# outward winding (counter-clockwise seen from outside)
	var f := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for q in f:
		for t in [[0, 1, 2], [0, 2, 3]]:
			for i in t:
				st.add_vertex(v[q[i]])
	st.generate_normals()
	return st.commit()


func _wedge_mesh() -> ArrayMesh:
	# triangle (0,0), (0.6,0), (0.6,0.3) in x,y extruded over z in [-0.15, 0.15]; thickness (vertical) = 0.5 x
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(0, 0, -0.15)
	var b := Vector3(0.6, 0, -0.15)
	var c := Vector3(0.6, 0.3, -0.15)
	var d := Vector3(0, 0, 0.15)
	var e := Vector3(0.6, 0, 0.15)
	var f := Vector3(0.6, 0.3, 0.15)
	for t in [[a, c, b], [d, e, f], [a, b, e], [a, e, d], [b, c, f], [b, f, e], [a, d, f], [a, f, c]]:
		for p in t:
			st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func _unlit_box(p: Vector3, s: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = p
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	m.material_override = mat
	return m


func _patch_mean(img: Image, cx: int, cy: int, r: int) -> Color:
	var s := Vector3.ZERO
	var n := 0
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var c := img.get_pixel(x, y)
			s += Vector3(WaterRender.lin(c.r), WaterRender.lin(c.g), WaterRender.lin(c.b))
			n += 1
	s /= float(n)
	return Color(s.x, s.y, s.z)


func _schlick(cosv: float) -> float:
	var f0 := pow((1.0 - 1.333) / (1.0 + 1.333), 2.0)
	return f0 + (1.0 - f0) * pow(1.0 - cosv, 5.0)


func _r_params_flat() -> Dictionary:
	return {"sky_top": Vector3(1, 1, 1), "sky_horizon": Vector3(1, 1, 1), "scatter_on": 0.0, "sun_strength": 0.0}


## pixel of a world point for a camera at pos looking at tgt with up (the Camera3D conventions, vertical fov)
func _proj(pos: Vector3, tgt: Vector3, up: Vector3, fov_deg: float, size: Vector2i, wp: Vector3) -> Vector2i:
	var fwd := (tgt - pos).normalized()
	var right := fwd.cross(up).normalized()
	var u := right.cross(fwd).normalized()
	var d := wp - pos
	var z := d.dot(fwd)
	var tf := tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2i(roundi(size.x * 0.5 + d.dot(right) / z / tf * size.y * 0.5), roundi(size.y * 0.5 - d.dot(u) / z / tf * size.y * 0.5))


func _r_render() -> void:
	var size := Vector2i(640, 400)
	# ---- R0: thickness of a 0.2 m box head on
	var box := _slab_mesh(Vector3(0.3, 0.3, 0.2))
	var r0: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": Vector3(0, 0, 1.5), "cam_look": Vector3.ZERO, "fov": 20.0, "water": box, "params": _r_params_flat()})
	var ti: Image = r0["thick"]
	var t0 := ti.get_pixel(size.x / 2, size.y / 2).r
	ok(absf(t0 - 0.2) <= 0.006, "(R0) thickness pass reads %.4f m for a 0.200 m deep box (bar 3 %%)" % t0)
	ok(absf(0.3 * 1.3 - 0.2) / 0.2 > 0.03, "(g) CONTROL (R0) a planted reading of 0.39 m fails the 3 % bar")
	# ---- R1: Fresnel on a slab (black floor, white sky)
	var slab := _slab_mesh(Vector3(0.6, 0.1, 0.6))
	var res := {}
	for mode in ["on", "off"]:
		var vals := []
		for ang in [80.0, 10.0]:
			var a := deg_to_rad(ang)
			var tgt := Vector3(0, 0.05, 0)
			var pos := tgt + Vector3(sin(a), cos(a), 0.0) * 2.0
			var prm := _r_params_flat()
			prm["fresnel_on"] = 1.0 if mode == "on" else 0.0
			prm["absorb_scale"] = 0.0
			var rr: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": pos, "cam_look": tgt, "fov": 12.0, "water": slab, "props": [_unlit_box(Vector3(0, -0.5, 0), Vector3(3, 0.1, 3), Color(0, 0, 0))], "bg": Color(0, 0, 0), "params": prm})
			var img: Image = rr["color"]
			vals.append(_patch_mean(img, size.x / 2, size.y / 2, 4).g)
		res[mode] = vals
	var fp80 := _schlick(cos(deg_to_rad(80.0)))
	var fp10 := _schlick(cos(deg_to_rad(10.0)))
	var m80: float = res["on"][0]
	var m10: float = res["on"][1]
	print("      R1 Fresnel: measured F(80) %.4f F(10) %.4f ratio %.1f; Schlick %.4f %.4f ratio %.1f; Fresnel off: %.4f %.4f" % [m80, m10, m80 / maxf(m10, 1e-6), fp80, fp10, fp80 / fp10, res["off"][0], res["off"][1]])
	ok(absf(m80 - fp80) / fp80 <= 0.10 and absf(m10 - fp10) / fp10 <= 0.10, "(R1) F at 80 deg %.4f vs Schlick %.4f, at 10 deg %.4f vs %.4f (bar 10 %%); edge brightening ratio %.1f vs %.1f" % [m80, fp80, m10, fp10, m80 / maxf(m10, 1e-6), fp80 / fp10])
	var off_ratio: float = res["off"][0] / maxf(res["off"][1], 1e-6)
	ok(absf(off_ratio - fp80 / fp10) / (fp80 / fp10) > 0.5, "(g) CONTROL (R1) with the Fresnel term off the 80/10 ratio reads %.2f against %.1f and fails" % [off_ratio, fp80 / fp10])
	# ---- R2: Beer-Lambert on a wedge over a white floor, seen from above
	var wedge := _wedge_mesh()
	var sig := Vector3(0.2916, 0.0565, 0.00922)
	var f0 := _schlick(1.0)
	var shifts := {}
	for mode in ["on", "off"]:
		var pos2 := Vector3(0.3, 3.0, 0.0)
		var tgt2 := Vector3(0.3, 0.0, 0.0)
		var up2 := Vector3(0, 0, -1)
		var prm2 := _r_params_flat()
		prm2["absorb_scale"] = 1.0 if mode == "on" else 0.0
		var rr2: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": pos2, "cam_look": tgt2, "up": up2, "fov": 14.0, "water": wedge, "props": [_unlit_box(Vector3(0.3, -0.05, 0), Vector3(2, 0.1, 2), Color(1, 1, 1))], "bg": Color(1, 1, 1), "params": prm2})
		var img2: Image = rr2["color"]
		var row := []
		for tv in [0.10, 0.20, 0.30]:
			var x: float = tv / 0.5   # wedge: vertical thickness = 0.5 x
			var wp := Vector3(x, tv, 0.0)
			var px := _proj(pos2, tgt2, up2, 14.0, size, wp)
			var c := _patch_mean(img2, px.x, px.y, 2)
			var dirv := (wp - pos2).normalized()
			var path: float = tv / absf(dirv.y)
			var pred := (1.0 - f0) * (exp(-sig.z * path) - exp(-sig.x * path))
			row.append([c.b - c.r, pred, path])
		shifts[mode] = row
	var good := true
	var line := []
	for q in 3:
		var meas: float = shifts["on"][q][0]
		var pred: float = shifts["on"][q][1]
		line.append("t %.3f: B-R measured %.4f predicted %.4f" % [shifts["on"][q][2], meas, pred])
		if absf(meas - pred) > 0.25 * pred:
			good = false
	if not (shifts["on"][0][0] < shifts["on"][1][0] and shifts["on"][1][0] < shifts["on"][2][0]):
		good = false
	print("      R2 ", " | ".join(line))
	ok(good, "(R2) colour shift B - R with thickness follows Beer-Lambert for pure water within 25 %% at 3 path lengths and grows with t")
	var bad := true
	for q in 3:
		if absf(float(shifts["off"][q][0]) - float(shifts["off"][q][1])) <= 0.25 * float(shifts["off"][q][1]):
			bad = false
	ok(bad, "(g) CONTROL (R2) with the absorption off the colour shift is %.4f %.4f %.4f and fails the same bar" % [shifts["off"][0][0], shifts["off"][1][0], shifts["off"][2][0]])
	# ---- R3: the dam break surface
	var F = Fluid.make()
	F.set_threads(8)
	var sc := FluidScenes.dam_break(F, 20)
	F.advance(2.0 * sqrt(sc["a"] / (2.0 * G)))
	var bs := WaterSurface.build(F, 0.5, 4, 4, sc["h"], 1.0, false)
	if bs["mesh"] == null:
		ok(false, "(R3) the dam break produced no surface")
		return
	var pos3: PackedVector3Array = bs["pos"]
	var idx3: PackedInt32Array = bs["idx"]
	var open_f := _open_edge_fraction(idx3)
	var idx_cut := PackedInt32Array()
	for t in range(0, idx3.size() - 2, 3):
		if (t / 3) % 25 != 7 and (t / 3) % 25 != 19:   # 2 of every 25 triangles = 8 %
			idx_cut.append(idx3[t])
			idx_cut.append(idx3[t + 1])
			idx_cut.append(idx3[t + 2])
	var open_cut := _open_edge_fraction(idx_cut)
	var nrm3 := WaterSurface.normals(pos3, idx3)
	var mesh_ok: ArrayMesh = WaterSurface.make_mesh(pos3, idx3, nrm3, PackedFloat32Array())
	var mesh_cut: ArrayMesh = WaterSurface.make_mesh(pos3, idx_cut, nrm3, PackedFloat32Array())
	var cpos := Vector3(0.45, 0.35, 1.0)
	var ctgt := Vector3(0.3, 0.1, 0.05)
	var inc := {}
	for nm in ["ok", "cut"]:
		var rr3: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": cpos, "cam_look": ctgt, "fov": 40.0, "water": mesh_ok if nm == "ok" else mesh_cut, "params": _r_params_flat()})
		var ti3: Image = rr3["thick"]
		var covered := 0
		var incoh := 0
		for y in size.y:
			for x in size.x:
				var c := ti3.get_pixel(x, y)
				if c.g > 0.5:
					covered += 1
					if (roundi(c.g) % 2) == 1 or c.r < -1e-4:
						incoh += 1
		inc[nm] = float(incoh) / maxf(float(covered), 1.0)
		print("      R3 %s: covered %d px, incoherent %d (%.3f %%)" % [nm, covered, incoh, inc[nm] * 100.0])
	print("      R3 open-edge fraction: mesh %.4f, with 8 %% of the triangles removed %.4f; mesh %d triangles, enclosed volume %.5f m3" % [open_f, open_cut, idx3.size() / 3, bs["volume"]])
	ok(open_f <= 0.02, "(R3) the welded surface is closed: %.2f %% of its edges are not shared by two triangles (bar 2 %%)" % [open_f * 100.0])
	ok(inc["ok"] <= 0.005, "(R3) thickness map coherent: %.3f %% of the covered pixels are incoherent (bar 0.5 %%)" % [inc["ok"] * 100.0])
	ok(open_cut > 0.02 and inc["cut"] > 0.005, "(g) CONTROL (R3) the mesh with 8 %% of its triangles removed reads %.2f %% open edges and %.2f %% incoherent pixels and fails both" % [open_cut * 100.0, inc["cut"] * 100.0])


func _open_edge_fraction(idx: PackedInt32Array) -> float:
	var cnt := {}
	for t in range(0, idx.size() - 2, 3):
		for e in 3:
			var a := idx[t + e]
			var b := idx[t + (e + 1) % 3]
			var key := (mini(a, b) << 32) | maxi(a, b)
			cnt[key] = int(cnt.get(key, 0)) + 1
	var bad := 0
	for k in cnt:
		if cnt[k] != 2:
			bad += 1
	return float(bad) / maxf(float(cnt.size()), 1.0)
