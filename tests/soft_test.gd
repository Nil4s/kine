## godot --headless --path . -s tests/soft_test.gd     (L17 SOFT-BODY, GAP_AUDIT_1106 #9; scripts/soft_body.gd, native/src/kine_soft_native.cpp)
## A picture of a jump landing (contact sheet, side view): SOFT_SHOT=<dir> with a window
##   godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/soft_test.gd
##
## THE MODEL, and why: an XPBD tetrahedral volume (Macklin, Mueller, Chentanez 2016 "XPBD", and the Neo-Hookean constraint pair of
## Macklin and Mueller 2021: a deviatoric constraint C = sqrt(tr(F^T F)) with compliance 1/(mu V0) and a hydrostatic constraint
## C = det F - gamma with compliance 1/(lambda V0)). Tets, not a spring lattice, because a spring lattice has no Poisson ratio: the
## bars below quote E and nu and compare with LINEAR ELASTICITY, which a mass-spring net cannot meet at nu != 0.25 and cannot
## preserve volume with. A tet knows mu and lambda, so E and nu go in and the physics comes out. Unconditionally stable (XPBD).
##
## Every bar was written BEFORE the implementation (this file's first commit has no soft_body.gd). Each has a PLANTED CONTROL: the
## same measurement on a deliberately wrong system, which the bar must REJECT. A bar that cannot fail is not a bar.
##
## PHYSICS TRUTH (blocks of tets; tolerances stated here, not tuned after):
##   1a STATIC SAG. A column 4 cm x 24 cm x 4 cm, E 50 kPa, nu 0.30, rho 1000, top face fixed, hangs under gravity. A slender bar
##      under its own weight stretches delta = rho g L^2 / (2 E) (the mean drop of the bottom face; 5.65 mm). Within 10 %.
##      CONTROL: the same column built with 2 E must NOT pass against the quoted E (it is 50 % off).
##   1b FREQUENCY. The same column, no gravity, a tip mass M = 10 x the bar's mass on the bottom face. The stiffness k is MEASURED
##      (a 1.67 N static push, k = F / drop). After release the tip oscillates at f = sqrt(k / (M + m/3)) / 2 pi (the Rayleigh
##      equivalent mass of the bar). Within 4 %. CONTROL: the prediction with k x 1.5 must NOT pass.
##   1c VOLUME. A 6 cm cube, nu 0.495 (soft tissue is nearly incompressible: 0.45 to 0.5), top and bottom faces held, the top pushed
##      down 30 % and settled. The summed tet volume stays within 1 % of the start, no tet inverted.
##      CONTROL: the same with nu 0.0 loses more than 5 % (the detector sees a volume that is not preserved).
##   1d DAMPING. The tip-mass system with damping configured for zeta 0.10 (rate = 2 zeta omega), the ratio read back from the
##      log decrement of four peaks: within 15 % of 0.10 (0.085 to 0.115). CONTROL: configured damping 0 reads under 0.02, so a
##      claim of 0.10 fails.
## FLESH PLAUSIBILITY (thigh region, a real landing of the mannequin: dip, flight, a stiff landing in 0.08 s; body-driven):
##   Literature (the two papers exist, checked on PubMed 11-06; THE NUMBERS BELOW ARE FROM MY MEMORY OF THE FIELD, I did not read the
##   full texts, and the abstracts carry no numbers; treat the windows as wide, not as citations of a value):
##   - Wakeling JM, Nigg BM (2001) J Biomech 34(4):539-43, PMID 11266679, DOI 10.1016/s0021-9290(00)00203-7: quadriceps soft-tissue
##     free vibration after impact is an under-damped sinusoid; frequencies of the order of 10 to 35 Hz, damping ratio of the order
##     of 0.1 to 0.3 (muscle activation raises both).
##   - Pain MTG, Challis JH (2005) J Biomech 39(1):119-24, PMID 16271595, DOI 10.1016/j.jbiomech.2004.10.036: wobbling-mass model of a
##     43 cm drop landing; the first 100 ms of the ground reaction force is carried by the soft tissue moving on the bone.
##   - Skin-marker soft-tissue artefact on the thigh in running / landing, a few mm to about 30 to 40 mm (Cappozzo 1996, Leardini
##     2005 review; from memory). Real flesh-on-bone travel at the thigh in a landing: ~ a few mm to ~ 3 cm.
##   2a peak displacement of the free flesh against the bone-driven position: 2 to 40 mm.
##   2b the ring-down frequency (zero crossings of the dominant node, 0.5 s after the peak): 8 to 40 Hz.
##   2c settle time (the envelope under 10 % of the peak): 0.04 to 0.60 s.
##   CONTROL: the same landing with the thigh region's damping x 30 must leave the frequency/settle windows (it is over-damped).
## STABILITY: all six regions, 1000 frames at 60 Hz of a jog-like drive: no NaN, no inverted tet, kinetic and elastic energy bounded
##   (under 5 x the first 200 frames' peak, and kinetic energy under 1e-3 of its peak 2 s after the drive stops).
##   CONTROL: negative damping (-8 /s) blows past the bound or goes non-finite; one node flipped by hand is counted as inverted.
## COST: the native step of all six regions (N particles printed) for one 60 Hz frame (8 substeps, SoftBody.DEFAULT_ITERS iterations; the 2-iteration figure is printed too): the measured ms is
##   printed; bar 2.0 ms. CONTROL: the same with 400 substeps must exceed the bar (the timer sees time).
## EQUALITY: the GDScript fallback and the native step, 120 frames of the same landing drive: every particle within 1e-9 m.
##   CONTROL: one particle nudged 1e-6 m in the native copy is seen (> 1e-9).
## OPT-IN: a Scene has no "soft" key by default and S.soft is empty; every scene file in scenes/ round-trips with no "soft" key and
##   the bytes of its dict unchanged; baking with no region touches nothing (Body.state unchanged). CONTROL: with a region on the key
##   appears and active() is true.
## PLACEMENT: for each region: the nodes that move (peak > 1 mm) are on the host part: the moving nodes' rest centroid is within
##   0.5 r .. 2.2 r of the host capsule axis, on the declared side of it (dot with the side direction > 0), the host capsule is the
##   NEAREST body capsule to that centroid, and the jiggle of the mannequin's own skin vertices (vertex_offsets) is zero for every
##   vertex outside the region's box and non-zero on at least 5 vertices inside it (the mannequin is a low-poly skin: 9 to 64 vertices per box). CONTROL: a region moved 0.5 m sideways fails.
## Numbers print next to each bar. FAIL lines count into the final verdict.
extends SceneTree

var fails := 0
const G := Vector3(0.0, -9.81, 0.0)
const E_COL := 5.0e4
const NU_COL := 0.30
const RHO := 1000.0
const COL_N := Vector3i(2, 10, 2)
const COL_SIZE := Vector3(0.04, 0.24, 0.04)
const SHOT_DIR_ENV := "SOFT_SHOT"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func nid(n: Vector3i, ix: int, iy: int, iz: int) -> int:
	return (iz * (n.y + 1) + iy) * (n.x + 1) + ix


## the node ids on one y level (iy) of a block
func level(n: Vector3i, iy: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for iz in n.z + 1:
		for ix in n.x + 1:
			out.append(nid(n, ix, iy, iz))
	return out


func column(E: float, nu: float) -> Dictionary:
	var st := SoftBody.block(COL_N, COL_SIZE, {"E": E, "nu": nu, "rho": RHO}, Vector3.ZERO)
	SoftBody.pin(st, level(COL_N, COL_N.y))   # the top face
	return st


func run(st: Dictionary, frames: int, damp: float, g: Vector3, hz := 60.0, nsub := 40) -> void:
	for f in frames:
		SoftBody.step(st, {"dt": 1.0 / hz, "nsub": nsub, "iters": 1, "g": g, "damp": damp})


func bottom_y(st: Dictionary) -> float:
	var s := 0.0
	var L := level(COL_N, 0)
	for i in L:
		s += SoftBody.node(st, i).y
	return s / float(L.size())


func total_mass(st: Dictionary) -> float:
	var m := 0.0
	for x in (st["mass"] as PackedFloat64Array):
		m += x
	return m


## add a tip mass M spread on the bottom face
func tip_mass(st: Dictionary, M: float) -> void:
	var L := level(COL_N, 0)
	for i in L:
		SoftBody.set_node_mass(st, i, (st["mass"] as PackedFloat64Array)[i] + M / float(L.size()))


func push(st: Dictionary, F: float) -> void:
	var fe := PackedFloat64Array()
	fe.resize(3 * int(st["n"]))
	var L := level(COL_N, 0)
	for i in L:
		fe[3 * i + 1] = -F / float(L.size())
	st["fext"] = fe


func release(st: Dictionary) -> void:
	var fe := PackedFloat64Array()
	fe.resize(3 * int(st["n"]))
	st["fext"] = fe


## the tip's y at every 1/240 s for `seconds`, after the push is released
func ring(st: Dictionary, seconds: float, damp: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in int(seconds * 240.0):
		SoftBody.step(st, {"dt": 1.0 / 240.0, "nsub": 10, "iters": 1, "g": Vector3.ZERO, "damp": damp})
		out.append(bottom_y(st))
	return out


## rising zero crossings (linear interpolation) of y - mean, in seconds
func crossings(y: PackedFloat64Array, base: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(1, y.size()):
		var a := y[i - 1] - base
		var b := y[i] - base
		if a < 0.0 and b >= 0.0:
			out.append((float(i - 1) + (-a) / (b - a)) / 240.0)
	return out


## successive maxima of (y - base), parabolic peak height
func peaks(y: PackedFloat64Array, base: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(1, y.size() - 1):
		var a := y[i - 1] - base
		var b := y[i] - base
		var c := y[i + 1] - base
		if b > a and b >= c and b > 0.0:
			var d := a - 2.0 * b + c
			out.append(b - (c - a) * (c - a) / (8.0 * d) if absf(d) > 1e-30 else b)
	return out


func zeta_of(pk: PackedFloat64Array) -> float:
	if pk.size() < 5:
		return -1.0
	var delta := log(pk[0] / pk[4]) / 4.0
	return delta / sqrt(4.0 * PI * PI + delta * delta)


## the tip-mass rig: stiffness measured, mass, omega
func rig() -> Dictionary:
	var st := column(E_COL, NU_COL)
	var m_bar := total_mass(st)
	var M := 10.0 * m_bar
	tip_mass(st, M)
	var y0 := bottom_y(st)
	var F := 1.67
	push(st, F)
	run(st, 960, 18.0, Vector3.ZERO, 240.0, 40)   # critically damped settle (4 s)
	var k := F / (y0 - bottom_y(st))
	release(st)
	return {"st": st, "k": k, "M": M, "m": m_bar, "y_push": bottom_y(st), "y0": y0}


## the thigh landing: dip, flight, stiff landing; the impact time
func landing_scene() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_soft_land"
	S.add("stand", B.to_dict())
	S.add("dip", pose(50, 90, 0))
	S.add("air", pose(10, 20, 100))
	S.add("land", pose(50, 90, 0))
	S.add("stand", B.to_dict())
	var mvs := [0.3, 0.3, 0.2855, 0.08, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mvs[i]
		S.cards[i]["hold"] = hd[i]
	S.cards[2]["air"] = true
	return S


func pose(thigh: float, calf: float, arm: float) -> Dictionary:
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(arm, 0, 0))
	B.fk()
	return B.to_dict()


func _init() -> void:
	var t_all := Time.get_ticks_msec()
	# ---------- 0. the door
	ok(SoftBody.native_on(), "0 the native door is open (KineSoftNative loaded from native/bin): GDScript is the fallback, the bars below run the fast path")

	# ---------- 1a STATIC SAG
	var st := column(E_COL, NU_COL)
	run(st, 90, 60.0, G)
	var sag := -bottom_y(st)   # the bottom face started at y = 0, the top (fixed) at 0.24: it hangs from y = 0.24
	var delta_an := RHO * 9.81 * COL_SIZE.y * COL_SIZE.y / (2.0 * E_COL)
	print("1a SAG: measured drop of the bottom face %.3f mm, analytic rho g L^2 / 2E = %.3f mm" % [sag * 1000.0, delta_an * 1000.0])
	ok(absf(sag - delta_an) / delta_an < 0.10, "1a static sag within 10 %% of the analytic value: %.3f vs %.3f mm (%.1f %%)" % [sag * 1000.0, delta_an * 1000.0, 100.0 * (sag - delta_an) / delta_an])
	var st2 := column(2.0 * E_COL, NU_COL)
	run(st2, 90, 60.0, G)
	var sag2 := -(bottom_y(st2))
	ok(absf(sag2 - delta_an) / delta_an >= 0.10, "1a CONTROL: a column of 2 E read against the quoted E is rejected (%.3f mm, %.0f %% off)" % [sag2 * 1000.0, 100.0 * absf(sag2 - delta_an) / delta_an])

	# ---------- 1b FREQUENCY
	var R := rig()
	var k: float = R["k"]
	var Meq: float = float(R["M"]) + float(R["m"]) / 3.0
	var f_pred := sqrt(k / Meq) / TAU
	var yy: PackedFloat64Array = ring(R["st"], 7.0, 0.0)
	var base := float(R["y0"])   # the unloaded tip (gravity off, the push released)
	var cr := crossings(yy, base)
	var f_meas := 0.0
	if cr.size() >= 4:
		f_meas = float(cr.size() - 1) / (cr[cr.size() - 1] - cr[0])
	var kk := 1.5 * k
	var f_ctl := sqrt(kk / Meq) / TAU
	print("1b FREQ: measured k %.1f N/m (EA/L = %.1f), M %.3f kg + m/3, predicted %.4f Hz, measured %.4f Hz (%d crossings)" % [k, E_COL * COL_SIZE.x * COL_SIZE.z / COL_SIZE.y, R["M"], f_pred, f_meas, cr.size()])
	ok(f_meas > 0.0 and absf(f_meas - f_pred) / f_pred < 0.04, "1b the ring-down frequency matches sqrt(k/m): %.4f vs %.4f Hz (%.2f %%)" % [f_meas, f_pred, 100.0 * (f_meas - f_pred) / f_pred])
	ok(absf(f_meas - f_ctl) / f_ctl >= 0.04, "1b CONTROL: the prediction with k x 1.5 (%.4f Hz) is rejected" % f_ctl)

	# ---------- 1c VOLUME
	var vcheck := func(nu: float) -> Array:
		var n := Vector3i(4, 4, 4)
		var b := SoftBody.block(n, Vector3(0.06, 0.06, 0.06), {"E": 3.0e4, "nu": nu, "rho": RHO}, Vector3.ZERO)
		SoftBody.pin(b, level(n, 0) + level(n, n.y))
		var v0 := SoftBody.volume(b)
		var steps := 120
		for s in steps:
			var drop := 0.30 * 0.06 * float(s + 1) / float(steps)
			var tgt := (b["pin_to"] as PackedFloat64Array).duplicate()
			var top := level(n, n.y)
			var pins: PackedInt32Array = b["pin_idx"]
			for j in pins.size():
				if pins[j] in top:
					tgt[3 * j + 1] = 0.06 - drop
			b["pin_to"] = tgt
			SoftBody.step(b, {"dt": 1.0 / 60.0, "nsub": 20, "iters": 4, "g": Vector3.ZERO, "damp": 30.0})
		for s in 60:
			SoftBody.step(b, {"dt": 1.0 / 60.0, "nsub": 20, "iters": 4, "g": Vector3.ZERO, "damp": 30.0})
		return [SoftBody.volume(b) / v0 - 1.0, SoftBody.inverted(b)]
	var vr: Array = vcheck.call(0.495)
	var vc: Array = vcheck.call(0.0)
	print("1c VOLUME: nu 0.495 dV/V %.3f %% inverted %d | control nu 0 dV/V %.2f %%" % [100.0 * vr[0], vr[1], 100.0 * vc[0]])
	ok(absf(vr[0]) < 0.01 and vr[1] == 0, "1c volume kept within 1 %% at 30 %% compression (%.3f %%), %d inverted tets" % [100.0 * vr[0], vr[1]])
	ok(absf(vc[0]) > 0.05, "1c CONTROL: nu 0 loses %.1f %% (> 5 %%): the detector sees volume that is not preserved" % [100.0 * absf(vc[0])])

	# ---------- 1d DAMPING
	var omega := sqrt(k / Meq)
	var zeta_cfg := 0.10
	var run_z := func(rate: float) -> float:
		var r2 := rig()
		var y := ring(r2["st"], 7.0, rate)
		return zeta_of(peaks(y, float(r2["y0"])))
	var z_meas: float = run_z.call(SoftBody.damp_for_zeta(zeta_cfg, omega))
	var z_zero: float = run_z.call(0.0)
	print("1d DAMPING: configured zeta %.3f (rate %.3f /s at omega %.3f), measured %.4f | damping 0 reads %.4f" % [zeta_cfg, SoftBody.damp_for_zeta(zeta_cfg, omega), omega, z_meas, z_zero])
	ok(z_meas > 0.085 and z_meas < 0.115, "1d the damping ratio is as configured: %.4f for 0.100 (bar 0.085 .. 0.115)" % z_meas)
	ok(z_zero >= 0.0 and z_zero < 0.02, "1d CONTROL: damping 0 reads %.4f (< 0.02): a claim of 0.10 against it fails" % z_zero)

	# ---------- 2 FLESH PLAUSIBILITY on a real landing
	var S := landing_scene()
	var fl := S.flights()
	ok(fl.size() == 1, "2 the landing scene has one flight")
	var t_imp: float = float(fl[0]["t1"]) if fl.size() == 1 else 1.0
	var B := body()
	var bk := SoftBody.bake_scene(S, B, ["thigh_l"], 240.0, {})
	var disp: Array = bk["regions"]["thigh_l"]["disp"]
	var i_imp := int(round(t_imp * 240.0))
	var peak := 0.0
	var i_peak := i_imp
	var node_best := 0
	for i in range(maxi(i_imp - 6, 0), mini(i_imp + 120, disp.size())):
		var d: PackedVector3Array = disp[i]
		for j in d.size():
			if d[j].length() > peak:
				peak = d[j].length()
				i_peak = i
				node_best = j
	# the signal of the dominant node: its displacement along the direction of its peak
	var dir_peak: Vector3 = (disp[i_peak] as PackedVector3Array)[node_best].normalized()
	var sig := PackedFloat64Array()
	for i in range(i_peak, mini(i_peak + 120, disp.size())):
		sig.append(((disp[i] as PackedVector3Array)[node_best]).dot(dir_peak))
	var zc := 0
	var tz := PackedFloat64Array()
	for i in range(1, sig.size()):
		if (sig[i - 1] < 0.0) != (sig[i] < 0.0):
			tz.append(float(i) / 240.0)
	var f_ring := 0.0
	if tz.size() >= 3:
		f_ring = 0.5 * float(tz.size() - 1) / (tz[tz.size() - 1] - tz[0])
	# settle: the first 40 ms window after the peak whose max |disp| (of that node) is under 10 % of the peak
	var settle := -1.0
	for i in range(i_peak, disp.size() - 10):
		var m := 0.0
		for q in 10:
			m = maxf(m, ((disp[i + q] as PackedVector3Array)[node_best]).length())
		if m < 0.10 * peak:
			settle = float(i - i_peak) / 240.0
			break
	print("2 LANDING (thigh_l): impact at %.3f s, peak flesh travel %.2f mm, ring-down %.1f Hz (%d crossings), settle to 10%% %.3f s" % [t_imp, peak * 1000.0, f_ring, tz.size(), settle])
	ok(peak > 0.002 and peak < 0.040, "2a peak flesh travel %.2f mm in the 2 .. 40 mm window (soft-tissue artefact / wobbling-mass range, from memory)" % (peak * 1000.0))
	ok(f_ring >= 8.0 and f_ring <= 40.0, "2b ring-down %.1f Hz in 8 .. 40 Hz (Wakeling and Nigg 2001, from memory)" % f_ring)
	ok(settle >= 0.04 and settle <= 0.60, "2c settle time %.3f s in 0.04 .. 0.60 s" % settle)
	var bk_od := SoftBody.bake_scene(S, B, ["thigh_l"], 240.0, {"damp_scale": 30.0})
	var peak_od := 0.0
	var disp_od: Array = bk_od["regions"]["thigh_l"]["disp"]
	for i in range(maxi(i_imp - 6, 0), mini(i_imp + 120, disp_od.size())):
		for d in (disp_od[i] as PackedVector3Array):
			peak_od = maxf(peak_od, d.length())
	ok(peak_od < 0.5 * peak, "2 CONTROL: damping x 30 cuts the travel to %.2f mm (< half of %.2f): over-damped flesh is out of the live window" % [peak_od * 1000.0, peak * 1000.0])

	# ---------- 3 STABILITY: 1000 frames at 60 Hz, all six regions
	var names: Array = SoftBody.REGIONS.keys()
	var stab := _stability(names, {})
	print("3 STABILITY: %d frames, regions %s: NaN %s, inverted tets %d, peak energy (first 200) %.4f J, later %.4f J, KE 2 s after stop / peak %s" % [stab["frames"], str(names), str(not stab["finite"]), stab["inverted"], stab["e_early"], stab["e_late"], String.num_scientific(stab["ke_after_ratio"])])
	ok(stab["frames"] == 1000 and stab["finite"], "3a 1000 frames, no NaN or inf")
	ok(stab["inverted"] == 0, "3b no inverted tet in any region at any 10th frame")
	ok(stab["e_late"] < 5.0 * stab["e_early"] and stab["ke_after_ratio"] < 1e-3, "3c energy bounded: later peak %.4f J < 5 x early %.4f J; KE 2 s after the drive stops is %s of its peak (bar 1e-3)" % [stab["e_late"], stab["e_early"], String.num_scientific(stab["ke_after_ratio"])])
	var bad := _stability(names, {"damp": -8.0})
	ok(not bad["finite"] or bad["e_late"] >= 5.0 * bad["e_early"] or bad["ke_after_ratio"] >= 1e-3, "3 CONTROL: damping -8 /s breaks the energy bound (finite %s, late %.4f vs early %.4f J, after-stop %s)" % [str(bad["finite"]), bad["e_late"], bad["e_early"], String.num_scientific(bad["ke_after_ratio"])])
	var fl_st := SoftBody.block(Vector3i(2, 2, 2), Vector3(0.04, 0.04, 0.04), {"E": 3.0e4, "nu": 0.45, "rho": RHO}, Vector3.ZERO)
	var xf := fl_st["x"] as PackedFloat64Array
	xf[3 * nid(Vector3i(2, 2, 2), 1, 1, 1) + 1] += 0.1   # the middle node pushed through the top
	fl_st["x"] = xf
	ok(SoftBody.inverted(fl_st) > 0, "3 CONTROL: a node pushed through its neighbours is counted as inverted (%d tets)" % SoftBody.inverted(fl_st))

	# ---------- 4 COST
	var cost := _cost(names, 8)
	var cost_big := _cost(names, 400)
	var cost_2it := _cost(names, 8, 2)
	print("4 COST: %d particles in %d tets (%d regions): %.3f ms per 60 Hz frame at 8 substeps x %d iteration (native %s); with 2 iterations %.3f ms; 400 substeps: %.2f ms" % [cost["n"], cost["tets"], names.size(), cost["ms"], SoftBody.DEFAULT_ITERS, str(cost["native"]), cost_2it["ms"], cost_big["ms"]])
	ok(cost["native"] and cost["ms"] < 2.0, "4 native step of %d particles: %.3f ms (bar 2.0 ms)" % [cost["n"], cost["ms"]])
	ok(cost_big["ms"] > 2.0, "4 CONTROL: 400 substeps take %.2f ms: the timer sees time (the bar can fail)" % cost_big["ms"])

	# ---------- 5 EQUALITY native vs GDScript
	var eq := _equality()
	print("5 EQUALITY: 120 frames of the landing drive, %d particles: largest difference native vs GDScript %s m; nudged control %s m" % [eq["n"], String.num_scientific(eq["diff"]), String.num_scientific(eq["ctl"])])
	ok(eq["diff"] < 1e-9, "5 the GDScript fallback equals the native step to %s m (bar 1e-9)" % [String.num_scientific(eq["diff"])])
	ok(eq["ctl"] > 1e-9, "5 CONTROL: a particle nudged 1e-6 m is seen (%s m)" % [String.num_scientific(eq["ctl"])])

	# ---------- 6 OPT-IN
	var S0 := Scene.new()
	ok(not S0.to_dict(B, false).has("soft") and S0.soft.is_empty() and not SoftBody.active(S0), "6a a new Scene has no 'soft' key and the system is not active")
	var same := 0
	var checked := 0
	for fn in DirAccess.get_files_at("res://scenes"):
		if not fn.ends_with(".json"):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn))
		if not raw is Dictionary or (raw as Dictionary).has("soft"):
			continue
		var sc := Scene.new()
		sc.from_dict(raw)
		var d1 := sc.to_dict(B, false)
		var sc2 := Scene.new()
		sc2.from_dict(d1)
		checked += 1
		if not d1.has("soft") and sc.soft.is_empty() and JSON.stringify(sc2.to_dict(B, false)) == JSON.stringify(d1) and not SoftBody.active(sc):
			same += 1
	print("6 OPT-IN: %d scene files, %d with no soft key, inactive, and a stable dict" % [checked, same])
	ok(checked > 0 and same == checked, "6b every scene file loads and saves with no 'soft' key and stays inactive (%d of %d)" % [same, checked])
	var Bk := body()
	var before := var_to_str(Bk.state())
	var none := SoftBody.bake_scene(S0, Bk, [], 60.0, {})
	ok(var_to_str(Bk.state()) == before and (none.get("regions", {}) as Dictionary).is_empty(), "6c baking with no region touches nothing: the Body is as it was")
	var S1 := Scene.new()
	S1.soft = {"regions": ["belly"]}
	ok(S1.to_dict(B, false).has("soft") and SoftBody.active(S1) and S1.clone().soft == S1.soft, "6 CONTROL: with a region on, the key is written, the system is active and clone() copies it")
	var BA := body()
	var before2 := var_to_str(BA.state())
	SoftBody.bake_scene(S, BA, ["thigh_l"], 60.0, {})
	ok(var_to_str(BA.state()) == before2, "6d even a real bake leaves the Body as it was")

	# ---------- 7 PLACEMENT
	_placement(S, t_imp)

	# ---------- LOOK
	print("soft: %d failures (%.1f s)" % [fails, float(Time.get_ticks_msec() - t_all) / 1000.0])
	var shot := OS.get_environment(SHOT_DIR_ENV)
	if shot != "":
		await _shot(shot, S, t_imp)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## a jog-like drive on a Body: pelvis bob, thigh and arm swing, some trunk twist
func jog_pose(B: Body, t: float, amp: float) -> void:
	B.offset = Vector3(0.0, 0.04 * amp * sin(TAU * 2.8 * t), 0.0)
	var s := sin(TAU * 1.4 * t)
	B.set_ang("thigh_l", Vector3(35.0 * amp * s, 0, 0))
	B.set_ang("thigh_r", Vector3(-35.0 * amp * s, 0, 0))
	B.set_ang("upperarm_l", Vector3(-30.0 * amp * s, 0, 0))
	B.set_ang("upperarm_r", Vector3(30.0 * amp * s, 0, 0))
	B.set_ang("spine_01", Vector3(0, 12.0 * amp * s, 0))
	B.fk()


func _stability(names: Array, extra: Dictionary) -> Dictionary:
	var B := body()
	var regs := []
	for n in names:
		regs.append(SoftBody.region_new(B, n, extra))
	var finite := true
	var inv := 0
	var e_early := 0.0
	var e_late := 0.0
	var ke_peak := 0.0
	var ke_after := 0.0
	var frames := 0
	for f in 1000:
		var amp := 1.0 if f < 600 else (0.5 + 0.5 * cos(PI * float(f - 600) / 100.0) if f < 700 else 0.0)   # the drive tapers off over frames 600-700 (a jump from a swing to rest in one frame is a teleport, not a motion); 300 frames (5 s) of rest
		jog_pose(B, float(f) / 60.0, amp)
		var ke := 0.0
		var el := 0.0
		for r in regs:
			SoftBody.region_step(r, B, {"dt": 1.0 / 60.0, "nsub": 8, "iters": SoftBody.DEFAULT_ITERS, "g": G})
			var en := SoftBody.energy(r["st"], G)
			ke += en["ke"]
			el += en["el"]
			if f % 10 == 0:
				inv += SoftBody.inverted(r["st"])
			if not SoftBody.finite(r["st"]):
				finite = false
		frames += 1
		if not finite:
			break
		var e := ke + el
		if f < 200:
			e_early = maxf(e_early, e)
		elif f < 700:
			e_late = maxf(e_late, e)
		if f < 700:
			ke_peak = maxf(ke_peak, ke)
		if f == 700 + 120 + 60:   # 2 s after the stop (the last 60 frames of a 3 s tail are read)
			ke_after = ke
	return {"frames": frames, "finite": finite, "inverted": inv, "e_early": e_early, "e_late": e_late, "ke_after_ratio": (ke_after / maxf(ke_peak, 1e-12)) if finite else INF}


func _cost(names: Array, nsub: int, iters := SoftBody.DEFAULT_ITERS) -> Dictionary:
	var B := body()
	var regs := []
	var n := 0
	var tets := 0
	for nm in names:
		var r := SoftBody.region_new(B, nm, {})
		regs.append(r)
		n += int(r["st"]["n"])
		tets += (r["st"]["tets"] as PackedInt32Array).size() / 4
	for f in 10:
		for r in regs:
			SoftBody.region_step(r, B, {"dt": 1.0 / 60.0, "nsub": nsub, "iters": iters, "g": G})
	var reps := 60 if nsub <= 8 else 3
	var us := 0.0   # only the region steps are timed (their GDScript marshalling included); the Body.fk of the pose is not the soft body's cost
	for f in reps:
		jog_pose(B, float(f) / 60.0, 1.0)
		var t0 := Time.get_ticks_usec()
		for r in regs:
			SoftBody.region_step(r, B, {"dt": 1.0 / 60.0, "nsub": nsub, "iters": iters, "g": G})
		us += float(Time.get_ticks_usec() - t0)
	return {"n": n, "tets": tets, "ms": us / 1000.0 / float(reps), "native": SoftBody.native_on()}


func _equality() -> Dictionary:
	var S := landing_scene()
	var B := body()
	var a := SoftBody.region_new(B, "thigh_l", {})
	var b := SoftBody.region_new(B, "thigh_l", {})
	var ctl := SoftBody.region_new(B, "thigh_l", {})
	var worst := 0.0
	var worst_ctl := 0.0
	var nudge := true
	for f in 120:
		S.apply(B, 0.6 + float(f) / 60.0)
		SoftBody.force_gdscript = true
		SoftBody.region_step(a, B, {"dt": 1.0 / 60.0, "nsub": 8, "iters": SoftBody.DEFAULT_ITERS, "g": G})
		SoftBody.force_gdscript = false
		SoftBody.region_step(b, B, {"dt": 1.0 / 60.0, "nsub": 8, "iters": SoftBody.DEFAULT_ITERS, "g": G})
		SoftBody.region_step(ctl, B, {"dt": 1.0 / 60.0, "nsub": 8, "iters": SoftBody.DEFAULT_ITERS, "g": G})
		if nudge:
			var xc := ctl["st"]["x"] as PackedFloat64Array
			xc[3 * 20] += 1e-6
			ctl["st"]["x"] = xc
			nudge = false
		var xa := a["st"]["x"] as PackedFloat64Array
		var xb := b["st"]["x"] as PackedFloat64Array
		var xcc := ctl["st"]["x"] as PackedFloat64Array
		for i in xa.size():
			worst = maxf(worst, absf(xa[i] - xb[i]))
			worst_ctl = maxf(worst_ctl, absf(xa[i] - xcc[i]))
	return {"n": int(a["st"]["n"]), "diff": worst, "ctl": worst_ctl}


## a node's transform up to (not including) the holder: the tree may not be live yet inside _init, so global_transform is not used
func xf_of(n: Node3D, stop: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != stop and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _placement(S: Scene, t_imp: float) -> void:
	var B := body()
	var hosts_ok := 0
	var tot := 0
	# the mannequin's own skin vertices at rest (world metres): the GLB's meshes through Overlays.mannequin
	var holder := Node3D.new()
	root.add_child(holder)
	var mq: Array = Overlays.mannequin(holder, StandardMaterial3D.new())
	var man: Node3D = mq[0]
	var verts := PackedVector3Array()
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var arr := m.mesh.surface_get_arrays(0)
		for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			verts.append(xf_of(m, holder) * v)
	for nm in SoftBody.REGIONS:
		var bk := SoftBody.bake_scene(S, B, [nm], 120.0, {})
		var reg: Dictionary = bk["regions"][nm]
		var info := SoftBody.region_new(B, nm, {})
		var pk := PackedFloat64Array()
		pk.resize((info["st"]["n"] as int))
		for fr in (reg["disp"] as Array):
			for j in (fr as PackedVector3Array).size():
				pk[j] = maxf(pk[j], (fr[j] as Vector3).length())
		var rest: PackedVector3Array = SoftBody.region_pose(info, B)   # B is at rest (fk) here: the rest place of every node
		var cen := Vector3.ZERO
		var wsum := 0.0
		for j in pk.size():
			if pk[j] > 0.001:
				cen += rest[j] * pk[j]
				wsum += pk[j]
		var n_move := 0
		for j in pk.size():
			if pk[j] > 0.001:
				n_move += 1
		var host: String = SoftBody.REGIONS[nm]["host"]
		var c: Array = B.cap(host)
		var a: Vector3 = c[0]
		var b2: Vector3 = c[1]
		var ok_place := wsum > 0.0
		var dist := -1.0
		var side := -1.0
		var nearest := ""
		if wsum > 0.0:
			cen /= wsum
			var ab := b2 - a
			var tt := clampf((cen - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
			var axp := a + ab * tt
			dist = (cen - axp).length()
			side = (cen - axp).normalized().dot((SoftBody.REGIONS[nm]["dir"] as Vector3).normalized())
			var rr := float(B.rad[host])
			var best := INF
			for cn in ["pelvis", "spine_01", "spine_02", "spine_03", "thigh_l", "thigh_r", "calf_l", "calf_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "clavicle_l", "clavicle_r"]:
				var cc: Array = B.cap(cn)
				var cab: Vector3 = (cc[1] as Vector3) - (cc[0] as Vector3)
				var tq := clampf((cen - (cc[0] as Vector3)).dot(cab) / maxf(cab.length_squared(), 1e-12), 0.0, 1.0)
				var dd := (cen - ((cc[0] as Vector3) + cab * tq)).length() - float(B.rad[cn])
				if dd < best:
					best = dd
					nearest = cn
			ok_place = dist >= 0.5 * rr and dist <= 2.2 * rr and side > 0.0 and (nearest == host or nm.begins_with("belly") or nm.begins_with("chest"))
		# the skin vertices: offsets from the region's last-impact displacement
		var frame: PackedVector3Array = (reg["disp"] as Array)[mini(int(round(t_imp * 120.0)) + 6, (reg["disp"] as Array).size() - 1)]
		var off := SoftBody.vertex_offsets(info, B, frame, verts)
		var inside := 0
		var outside_moved := 0
		for i in verts.size():
			var inbox := SoftBody.in_box(info, B, verts[i], 0.0)
			if off[i].length() > 1e-9:
				if inbox:
					inside += 1
				elif not SoftBody.in_box(info, B, verts[i], 0.02):
					outside_moved += 1
		print("7 PLACEMENT %s: %d moving nodes, centroid %.3f m from the %s axis (r %.3f), side dot %.2f, nearest capsule %s; skin vertices moved: %d inside the box, %d outside" % [nm, n_move, dist, host, float(B.rad[host]), side, nearest, inside, outside_moved])
		ok(ok_place and outside_moved == 0 and inside >= 5, "7 %s: jiggle sits on the %s (dist %.3f m, side %.2f, nearest %s), %d skin vertices move inside the box (bar >= 5), %d outside" % [nm, host, dist, side, nearest, inside, outside_moved])
		tot += 1
		if ok_place:
			hosts_ok += 1
	# CONTROL: a region moved 0.5 m sideways must fail the same test
	var moved := SoftBody.region_new(B, "thigh_l", {"shift": Vector3(0.5, 0.0, 0.0)})
	var rest2: PackedVector3Array = SoftBody.region_pose(moved, B)
	var cen2 := Vector3.ZERO
	for p in rest2:
		cen2 += p
	cen2 /= float(rest2.size())
	var c2: Array = B.cap("thigh_l")
	var ab2: Vector3 = (c2[1] as Vector3) - (c2[0] as Vector3)
	var t2 := clampf((cen2 - (c2[0] as Vector3)).dot(ab2) / maxf(ab2.length_squared(), 1e-12), 0.0, 1.0)
	var d2 := (cen2 - ((c2[0] as Vector3) + ab2 * t2)).length()
	ok(d2 > 2.2 * float(B.rad["thigh_l"]), "7 CONTROL: a thigh region shifted 0.5 m sideways is %.3f m off the thigh axis (bar 2.2 r = %.3f): the placement test rejects it" % [d2, 2.2 * float(B.rad["thigh_l"])])
	holder.queue_free()


## the picture: a before / after contact sheet of the landing, side view (SOFT_SHOT=<dir>): frames at -2, 0, +3, +8 around the
## impact (1/60 s apart). Row 1 the mannequin as it is, row 2 the same frame with the soft regions added to its skin, row 3 the
## difference of the two pictures (x8, grey) so a few millimetres can be seen at all. Nothing is exaggerated in rows 1 and 2.
func _shot(dir: String, S: Scene, t_imp: float) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.dummy_on = false
	var tmp := "user://soft_shot_scene.json"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	fa.store_string(JSON.stringify(S.to_dict(m.B)))
	fa.close()
	m._load_scene(tmp)
	m._rebuild_cards()
	m.playing = false
	var names: Array = SoftBody.REGIONS.keys()
	var bk := SoftBody.bake_scene(S, body(), names, 60.0, {})
	var rest := body()
	var regs := []
	for n in names:
		regs.append(SoftBody.region_new(rest, n, {}))
	var sv := SubViewport.new()
	sv.size = Vector2i(520, 760)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = false
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.current = true
	cam.fov = 28.0
	cam.global_position = Vector3(3.6, 1.0, 0.0)
	cam.look_at(Vector3(0.0, 0.93, 0.0), Vector3.UP)
	var k_imp := int(round(t_imp * 60.0))
	var offs := [-2, 0, 3, 8]
	var rows := [[], [], []]
	var peaks := []
	for off in offs:
		var k: int = k_imp + off
		var t := float(k) / 60.0
		m.playhead = t
		m._ps().apply(m.B, t)
		m._refresh()
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var before: Image = sv.get_texture().get_image()
		var disps := []
		var pk := 0.0
		for n in names:
			var d: PackedVector3Array = (bk["regions"][n]["disp"] as Array)[k]
			disps.append(d)
			for v in d:
				pk = maxf(pk, v.length())
		var clones := []
		var hidden := []
		for part in m.pieces:
			var piece: MeshInstance3D = m.pieces[part]
			var dm := SoftBody.skin_deform(piece, regs, m.B, disps)
			if dm != null:
				var c := MeshInstance3D.new()
				c.mesh = dm
				c.skin = piece.skin
				c.material_override = piece.material_override
				piece.get_parent().add_child(c)
				c.transform = piece.transform
				c.skeleton = c.get_path_to(piece.get_node(piece.skeleton))
				clones.append(c)
				hidden.append(piece)
				piece.visible = false
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var after: Image = sv.get_texture().get_image()
		for c in clones:
			c.queue_free()
		for h in hidden:
			h.visible = true
		var diff := Image.create(before.get_width(), before.get_height(), false, Image.FORMAT_RGB8)
		var nd := 0
		for y in before.get_height():
			for xx in before.get_width():
				var a := before.get_pixel(xx, y)
				var b2 := after.get_pixel(xx, y)
				var dv := maxf(absf(a.r - b2.r), maxf(absf(a.g - b2.g), absf(a.b - b2.b)))
				if dv > 0.02:
					nd += 1
				diff.set_pixel(xx, y, Color(clampf(dv * 8.0, 0.0, 1.0), clampf(dv * 8.0, 0.0, 1.0), clampf(dv * 8.0, 0.0, 1.0)))
		rows[0].append(before)
		rows[1].append(after)
		rows[2].append(diff)
		peaks.append([off, pk, nd, clones.size()])
		print("   frame %+d (k %d, t %.3f s): peak flesh travel %.2f mm, %d pieces deformed, %d pixels differ by more than 2 %%" % [off, k, t, pk * 1000.0, clones.size(), nd])
	var w := 520
	var h := 760
	var sheet := Image.create(w * 4, h * 3, false, Image.FORMAT_RGB8)
	for r in 3:
		for c in 4:
			sheet.blit_rect(rows[r][c], Rect2i(0, 0, w, h), Vector2i(c * w, r * h))
	sheet.save_png(dir.path_join("soft_landing_sheet.png"))
	for c in 4:
		(rows[0][c] as Image).save_png(dir.path_join("before_%d.png" % c))
		(rows[1][c] as Image).save_png(dir.path_join("after_%d.png" % c))
	print("   contact sheet -> %s" % dir.path_join("soft_landing_sheet.png"))
	sv.queue_free()
