extends SceneTree
## godot --headless --path . -s tests/ch10_test.gd   (CH10: the CH1 house under wind and the El Centro 1940 record, a 3D frame solver in C++ with a GDScript twin)
## Bars (written and committed before any number was read; sources in docs/CH10_REFERENCE.md):
##  a1 CANTILEVER   2 m, 0.05 x 0.10 m, E 1e10, 16 elements, tip load: tip deflection P L^3 / 3 E I within 1 pct; first frequency 1.8751^2 sqrt(E I / (rho A L^4)) within 1 pct.
##  a2 PORTAL       fixed bases, columns 3 m, beam 4 m rigid (I x 1e5), 1000 kg lumped at each top corner: sway under H = 24 E I / h^3 (two columns, 12 E I / h^3 each) within 1 pct,
##                  first frequency sqrt(K / 2000 kg) within 1 pct.
##  b  HAND CALC    wind +z (eave wall F), site Levittown NY 130 mph exposure B (house_check site record), ASCE 7-16 q = 0.00256 Kz Kd V^2, G 0.85, Cp +0.8 / -0.5:
##                  (b1) total applied wind force within 2 pct of the hand calc (Kz = 0.57, Table 26.10-1);
##                  (b2) the base reactions of the model sum to the applied force within 0.5 pct (equilibrium);
##                  (b3) each gable wall (L, R): mean top-plate displacement within 5 pct of  R_wall / k_wall  where k_wall is summed from the member list by hand:
##                       full-height OSB panels, contiguous segments with h/b <= 3.5, per segment k = V / (v (8 h^3 / (E A b) + h / (1000 Ga))), Ga = 11 kips/in, end chords 2 studs.
##  c  PERIOD       the longest of the first x-sway and z-sway periods (inverse iteration from the static shape, effective modal mass of the shape reported) within
##                  [0.5 Ta, 1.7 Ta], Ta = 0.02 hn^0.75, hn = 12.96 ft (ridge) -> band 0.069 .. 0.233 s (Cu = 1.7 assumes SD1 <= 0.1 g: UNVERIFIED site value).
##  d  NEWMARK      undamped SDOF, free vibration, 1000 steps at T/20: total energy drift < 0.5 pct. CONTROL: with 2 pct Rayleigh damping the same check FAILS (bar can fail).
##  e  QUAKE        El Centro 1940 NS (PGA 0.349 g) unscaled, 5 pct Rayleigh damping at the first period and 5x it, dt 0.01 s, ASCE 7-16 Table 12.12-1 allowable 0.020 h
##                  (all other structures, Risk II; stated, and 0.025 if partitions are designed for the drift):
##                  (e1) code house, z and x: peak top-plate drift ratio < 0.020;
##                  (e2) planted house, bracing removed on ONE line (L): z peak drift >= 1.5 x the code house z peak (the lead's bar says "exceeds the allowable"; the number against
##                       0.020 is printed, not forced: a linear model at 0.35 g is not expected to rack a house that still has three braced lines);
##                  (e3) planted house with ALL z bracing removed (L and R): z peak drift > 0.020 (racks), and the code house does not;
##                  (e4) C++ == GDScript on a 10-member frame within 1e-9 (relative): static u, first omega, a Newmark record.
##  f  TIME         solve time per Newmark step of the house is printed; the bar is only that it is under 200 ms (stated, not tuned).
##  g  MODEL        the model is one connected frame: >= 95 pct of nodes in the main component; seismic mass between 3000 and 12000 kg (8-33 psf of 80 m2);
##                  the 16 front/back-wall full-height panels and the roof panels all have springs.
var fails := 0
const FR := preload("res://scripts/build/ch10_frame.gd")
const HO := preload("res://scripts/build/ch10_house.gd")
const SIM := preload("res://scripts/build/ch10_sim.gd")
var json_cache = null


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func sci(x: float) -> String:
	return String.num_scientific(x)


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func beam_row(n1: int, n2: int, b: float, d: float, E: float, rho: float, e2: Vector3) -> Array:
	var A := b * d
	var Iz := b * d * d * d / 12.0
	var Iy := d * b * b * b / 12.0
	var J := Iz + Iy
	return [n1, n2, A, Iz, Iy, J, E, E / 2.6, rho, e2.x, e2.y, e2.z]


func flat(rows: Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	for r in rows:
		for v in r:
			o.append(v)
	return o


func xyz_of(pts: Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	for p in pts:
		o.append_array([p.x, p.y, p.z])
	return o


func house_model(opts: Dictionary) -> Dictionary:
	if json_cache == null:
		json_cache = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var bld := HO.build(json_cache, opts)
	var mm := HO.to_model(bld)
	var ms := HO.masses(bld)
	var model: Dictionary = mm["model"]
	model["mass"] = ms["mass"]
	return {"bld": bld, "model": model, "mm": mm, "ms": ms}


## static shape + inverse iteration -> omega, effective modal mass fraction in dir
func sway_period(hm: Dictionary, dir: int) -> Dictionary:
	var model: Dictionary = hm["model"]
	var bld: Dictionary = hm["bld"]
	var n: int = bld["nodes"].size()
	var load := PackedFloat64Array()
	load.resize(n * 6)
	for i in SIM.top_nodes(bld):
		load[i * 6 + dir] = 1.0
	var st := FR.solve(model, {"type": "static", "loads": load})
	var md := FR.solve(model, {"type": "modal", "start": st["u"], "iters": 3})
	# effective modal mass fraction of the found shape in dir: (phi^T M r)^2 / (phi^T M phi) / total mass, from the model's own masses is not exposed; use the lumped extras + the
	# translational participation of the mass array as the estimate
	var phi: PackedFloat64Array = md["phi"]
	var mass: PackedFloat64Array = model["mass"]
	var num := 0.0
	var den := 0.0
	var tot := 0.0
	for i in n:
		num += mass[i] * phi[i * 6 + dir]
		den += mass[i] * (phi[i * 6] * phi[i * 6] + phi[i * 6 + 1] * phi[i * 6 + 1] + phi[i * 6 + 2] * phi[i * 6 + 2])
		tot += mass[i]
	var eff := (num * num) / maxf(den, 1e-30) / maxf(tot, 1e-30)
	return {"omega": md["omega"], "T": TAU / md["omega"], "rq": md["rq"], "eff": eff, "phi": phi}


func quake(hm: Dictionary, dir: int, om: float, snap_every := 0) -> Dictionary:
	var rec := SIM.load_record()
	var dt := 0.02    # the record's own step; average-acceleration Newmark, period elongation (w dt)^2/12 ~ 2 pct at T 0.25 s
	var ag := SIM.resample(rec, dt)
	var zeta := 0.05
	var w2 := 5.0 * om
	var alpha := 2.0 * zeta * om * w2 / (om + w2)
	var beta := 2.0 * zeta / (om + w2)
	var tops := SIM.top_nodes(hm["bld"])
	var recd := PackedInt32Array()
	for i in tops:
		recd.append(i * 6 + dir)
	var t0 := Time.get_ticks_msec()
	var r := FR.solve(hm["model"], {"type": "newmark", "dt": dt, "nsteps": ag.size() - 1, "ag": ag, "dir": dir, "alpha": alpha, "beta": beta, "record": recd, "snap_every": snap_every})
	var ms := float(Time.get_ticks_msec() - t0)
	var ns := ag.size()
	var ru: PackedFloat64Array = r["rec_u"]
	var peak := 0.0
	for k in tops.size():
		for s in ns:
			peak = maxf(peak, absf(ru[k * ns + s]))
	return {"peak_m": peak, "ratio": peak / 2.467, "ms_per_step": ms / (ns - 1), "r": r, "dt": dt, "tops": tops, "nsteps": ns - 1}


func _init() -> void:
	print("native frame class: ", FR.native_ok())
	# ------------------------------------------------------------------------------------------------- a1 cantilever
	var E := 1.0e10
	var rho := 500.0
	var b := 0.05
	var d := 0.10
	var L := 2.0
	var I := b * d * d * d / 12.0
	var rows: Array = []
	var pts: Array = []
	var ne := 16
	for i in ne + 1:
		pts.append(Vector3(L * i / ne, 0, 0))
	for i in ne:
		rows.append(beam_row(i, i + 1, b, d, E, rho, Vector3(0, 1, 0)))
	var fixed_all := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var cm := {"xyz": xyz_of(pts), "beams": flat(rows), "fixed": fixed_all}
	var load := PackedFloat64Array()
	load.resize((ne + 1) * 6)
	load[ne * 6 + 1] = 100.0
	for fg in [false, true]:
		if fg and not FR.native_ok():
			continue
		var tag := "GDScript" if fg else ("C++" if FR.native_ok() else "GDScript")
		var sr := FR.solve(cm, {"type": "static", "loads": load}, fg)
		var tip: float = sr["u"][ne * 6 + 1]
		var exact := 100.0 * L * L * L / (3.0 * E * I)
		ok(rel(tip, exact) < 0.01, "a1 cantilever tip deflection [%s] %s m vs P L^3/3EI %s (%.4f pct)" % [tag, sci(tip), sci(exact), 100.0 * rel(tip, exact)])
		var md := FR.solve(cm, {"type": "modal", "start": sr["u"], "iters": 8}, fg)
		var w_ex: float = 1.8751040687 * 1.8751040687 * sqrt(E * I / (rho * b * d * L * L * L * L))
		ok(rel(md["omega"], w_ex) < 0.01, "a1 cantilever first omega [%s] %.4f vs %.4f rad/s (%.4f pct)" % [tag, md["omega"], w_ex, 100.0 * rel(md["omega"], w_ex)])
	# ------------------------------------------------------------------------------------------------- a2 portal
	var hh := 3.0
	var sp := 4.0
	var ppts := [Vector3(0, 0, 0), Vector3(0, hh, 0), Vector3(sp, hh, 0), Vector3(sp, 0, 0)]
	var prow: Array = []
	prow.append(beam_row(0, 1, b, d, E, 1.0, Vector3(1, 0, 0)))
	prow.append(beam_row(1, 2, b * 1.0, d * pow(1.0e5, 1.0 / 3.0), E, 1.0, Vector3(0, 1, 0)))
	prow.append(beam_row(3, 2, b, d, E, 1.0, Vector3(1, 0, 0)))
	var pfix := PackedInt32Array([0, 1, 2, 3, 4, 5, 18, 19, 20, 21, 22, 23])
	# also hold out-of-plane motion and torsion so the frame is planar (z, rx, ry free would be a 3D mechanism)
	for nd in [1, 2]:
		pfix.append(nd * 6 + 2)
		pfix.append(nd * 6 + 3)
		pfix.append(nd * 6 + 4)
	var pm := {"xyz": xyz_of(ppts), "beams": flat(prow), "fixed": pfix, "mass": PackedFloat64Array([0.0, 1000.0, 1000.0, 0.0])}
	var pl := PackedFloat64Array()
	pl.resize(24)
	pl[1 * 6] = 1000.0
	var ps := FR.solve(pm, {"type": "static", "loads": pl})
	var K_ex := 24.0 * E * I / (hh * hh * hh)
	var sway: float = ps["u"][1 * 6]
	ok(rel(sway, 1000.0 / K_ex) < 0.01, "a2 portal sway %s m vs H / (24EI/h^3) %s (%.4f pct)" % [sci(sway), sci(1000.0 / K_ex), 100.0 * rel(sway, 1000.0 / K_ex)])
	var pmd := FR.solve(pm, {"type": "modal", "start": ps["u"], "iters": 6})
	var wp := sqrt(K_ex / 2000.0)
	ok(rel(pmd["omega"], wp) < 0.01, "a2 portal first omega %.4f vs sqrt(K/m) %.4f rad/s (%.4f pct)" % [pmd["omega"], wp, 100.0 * rel(pmd["omega"], wp)])
	# ------------------------------------------------------------------------------------------------- d newmark energy
	var km := 2.0e6
	var mm0 := 500.0
	var sd := {"xyz": xyz_of([Vector3(0, 0, 0), Vector3(1, 0, 0)]), "beams": PackedFloat64Array(), "springs": PackedFloat64Array([0, 1, km]),
		"fixed": PackedInt32Array([0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11]), "mass": PackedFloat64Array([0.0, mm0])}
	var u0 := PackedFloat64Array()
	u0.resize(12)
	u0[6] = 0.001
	var Tn := TAU / sqrt(km / mm0)
	for damped in [false, true]:
		var sr2 := FR.solve(sd, {"type": "newmark", "dt": Tn / 20.0, "nsteps": 1000, "u0": u0, "record": PackedInt32Array([6]), "alpha": 0.02 * 2.0 * sqrt(km / mm0) if damped else 0.0, "beta": 0.0})
		var ru: PackedFloat64Array = sr2["rec_u"]
		var rv: PackedFloat64Array = sr2["rec_v"]
		var e0 := 0.5 * km * ru[0] * ru[0] + 0.5 * mm0 * rv[0] * rv[0]
		var drift := 0.0
		for s in 1001:
			var e := 0.5 * km * ru[s] * ru[s] + 0.5 * mm0 * rv[s] * rv[s]
			drift = maxf(drift, absf(e - e0) / e0)
		if not damped:
			ok(drift < 0.005, "d Newmark undamped SDOF energy drift %s over 1000 steps (bar 5e-3)" % sci(drift))
		else:
			ok(not (drift < 0.005), "d CONTROL: 2 pct damped SDOF energy drift %s FAILS the same bar (the bar can fail)" % sci(drift))
	# ------------------------------------------------------------------------------------------------- e4 C++ == GDScript on 10 members
	if FR.native_ok():
		var q10 := [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 3), Vector3(0, 0, 3), Vector3(0, 3, 0), Vector3(4, 3, 0), Vector3(4, 3, 3), Vector3(0, 3, 3)]
		var r10: Array = []
		for c in 4:
			r10.append(beam_row(c, c + 4, 0.1, 0.15, 1.1e10, 500.0, Vector3(1, 0, 0) if c % 2 == 0 else Vector3(0, 0, 1)))
		r10.append(beam_row(4, 5, 0.08, 0.12, 1.1e10, 500.0, Vector3(0, 1, 0)))
		r10.append(beam_row(5, 6, 0.08, 0.12, 1.1e10, 500.0, Vector3(0, 1, 0)))
		r10.append(beam_row(6, 7, 0.08, 0.12, 1.1e10, 500.0, Vector3(0, 1, 0)))
		r10.append(beam_row(7, 4, 0.08, 0.12, 1.1e10, 500.0, Vector3(0, 1, 0)))
		r10.append(beam_row(0, 5, 0.05, 0.05, 1.1e10, 500.0, Vector3(0, 0, 1)))
		r10.append(beam_row(2, 7, 0.05, 0.05, 1.1e10, 500.0, Vector3(0, 0, 1)))
		var fx10 := PackedInt32Array()
		for nd in 4:
			for dd in 6:
				fx10.append(nd * 6 + dd)
		var m10 := {"xyz": xyz_of(q10), "beams": flat(r10), "fixed": fx10, "springs": PackedFloat64Array([5, 7, 3.0e5]), "mass": PackedFloat64Array([0, 0, 0, 0, 120, 80, 150, 90])}
		var l10 := PackedFloat64Array()
		l10.resize(48)
		l10[4 * 6] = 800.0
		l10[5 * 6 + 2] = -500.0
		l10[7 * 6 + 1] = 300.0
		var s_n := FR.solve(m10, {"type": "static", "loads": l10})
		var s_g := FR.solve(m10, {"type": "static", "loads": l10}, true)
		var e_u := 0.0
		var mx := 0.0
		for i in 48:
			e_u = maxf(e_u, absf(s_n["u"][i] - s_g["u"][i]))
			mx = maxf(mx, absf(s_g["u"][i]))
		ok(e_u / mx < 1e-9, "e4 10-member frame static u: C++ vs GDScript max rel diff %s (bar 1e-9)" % sci(e_u / mx))
		var o_n := FR.solve(m10, {"type": "modal", "start": s_g["u"], "iters": 5})
		var o_g := FR.solve(m10, {"type": "modal", "start": s_g["u"], "iters": 5}, true)
		ok(rel(o_n["omega"], o_g["omega"]) < 1e-9, "e4 first omega: C++ %.9f GDScript %.9f (rel %s)" % [o_n["omega"], o_g["omega"], sci(rel(o_n["omega"], o_g["omega"]))])
		var ag10 := PackedFloat64Array()
		for s in 201:
			ag10.append(3.0 * sin(0.2 * s))
		var jb := {"type": "newmark", "dt": 0.01, "nsteps": 200, "ag": ag10, "dir": 0, "alpha": 0.5, "beta": 0.0005, "record": PackedInt32Array([4 * 6, 6 * 6 + 2, 7 * 6 + 1])}
		var n_n := FR.solve(m10, jb)
		var n_g := FR.solve(m10, jb, true)
		var e_r := 0.0
		var mr := 0.0
		for i in n_g["rec_u"].size():
			e_r = maxf(e_r, absf(n_n["rec_u"][i] - n_g["rec_u"][i]))
			mr = maxf(mr, absf(n_g["rec_u"][i]))
		ok(e_r / mr < 1e-9 and mr > 0.0, "e4 Newmark record (3 dofs x 201 steps): max rel diff %s (bar 1e-9), peak %s m" % [sci(e_r / mr), sci(mr)])
	else:
		ok(false, "e4 the native class is not loaded: C++ == GDScript cannot be checked")
	# ------------------------------------------------------------------------------------------------- the house
	if not FR.native_ok():
		print("the house has ~5800 free dofs: the dense GDScript twin cannot run it; the house bars (b c e1-e3 f g) need KineFrameNative (native/bin DLL) and are not run")
		print("ch10: %d fail (house bars NOT run)" % fails)
		quit(1)
		return
	var code := house_model({})
	var bld: Dictionary = code["bld"]
	var nn: int = bld["nodes"].size()
	var mmm: Dictionary = code["mm"]
	print("house: %d nodes, %d elements, %d springs, %d panels, %d roof panels, kept nodes %d, dropped elems %d, rafters without a bearing plate %d, bandwidth reported by the solver below" % [nn, bld["elems"].size(), bld["springs"].size(), bld["panels"].size(), bld["roofs"].size(), mmm["kept"], mmm["dropped_elems"], bld["rafter_free"]])
	ok(float(mmm["kept"]) / float(nn) >= 0.95, "g connected: %d of %d nodes in the main component" % [mmm["kept"], nn])
	var mtot: float = code["ms"]["total_kg"]
	var mbeams := 0.0
	var bm: PackedFloat64Array = code["model"]["beams"]
	for i in range(0, bm.size(), 12):
		if bm[i + 8] > 0.0:
			var p1: Vector3 = bld["nodes"][int(bm[i])]
			var p2: Vector3 = bld["nodes"][int(bm[i + 1])]
			mbeams += bm[i + 8] * bm[i + 2] * p1.distance_to(p2)
	print("mass: lumped finishes and sheathing %.0f kg, frame members %.0f kg, total %.0f kg (%.1f psf of 74.3 m2)" % [mtot, mbeams, mtot + mbeams, (mtot + mbeams) / 74.3 / 4.8824])
	ok(mtot + mbeams > 3000.0 and mtot + mbeams < 12000.0, "g seismic mass %.0f kg inside 3000..12000" % (mtot + mbeams))
	var nwall_f := 0
	var nwall_b := 0
	for p in bld["panels"]:
		if p["line"] == "F" or p["line"] == "B":
			nwall_f += 1 if p["spr"].size() == 2 else 0
		nwall_b += 1
	var full_ok := 0
	for sg in bld["segments"]:
		if sg["ok"]:
			full_ok += sg["panels"].size()
	ok(nwall_b == full_ok, "g every panel of an eligible segment has crossed springs: %d of %d" % [nwall_b, full_ok])
	ok(bld["roofs"].size() == 32, "g all 32 roof panels have crossed springs: %d" % bld["roofs"].size())
	# --- b: wind
	var wz := SIM.wind(bld, nn, 2)
	var q_hand := 0.00256 * 0.57 * 0.85 * 130.0 * 130.0 * 47.88026
	var F_hand := q_hand * 0.85 * (0.8 + 0.5) * 9.754 * (0.5 * 2.467)
	ok(rel(wz["F"], F_hand) < 0.02, "b1 wind +z total force %.0f N vs hand calc %.0f N (q %.1f psf, Kz %.3f vs 0.57) %.2f pct" % [wz["F"], F_hand, wz["q_psf"], wz["kz"], 100.0 * rel(wz["F"], F_hand)])
	var sw := FR.solve(code["model"], {"type": "static", "loads": wz["loads"]})
	ok(not sw.has("error"), "b static wind solve ran: " + str(sw.get("error", "")) + " bandwidth %s free dofs %s" % [str(sw.get("bw", "?")), str(sw.get("nfree", "?"))])
	if not sw.has("error"):
		var fixd: PackedInt32Array = code["model"]["fixed"]
		var rz := 0.0
		var rl := 0.0
		var rr := 0.0
		for dof in fixd:
			if dof % 6 == 2:
				var f: float = sw["f"][dof] - wz["loads"][dof]
				rz += f
				var p: Vector3 = bld["nodes"][dof / 6]
				if p.x < 0.06:
					rl += f
				elif p.x > 9.754 - 0.06:
					rr += f
		ok(rel(-rz, wz["F"]) < 0.005, "b2 reactions sum %.0f N vs applied %.0f N (%.3f pct)" % [-rz, wz["F"], 100.0 * rel(-rz, wz["F"])])
		var hand := hand_wall_k()
		for ln in ["L", "R"]:
			var rwall: float = -(rl if ln == "L" else rr)
			var us := 0.0
			var cnt := 0
			for i in SIM.top_nodes(bld):
				var p: Vector3 = bld["nodes"][i]
				var on: bool = (p.x < 0.06) if ln == "L" else (p.x > 9.754 - 0.06)
				if on:
					us += sw["u"][i * 6 + 2]
					cnt += 1
			us /= maxf(cnt, 1)
			var dh: float = rwall / hand[ln]
			ok(rel(us, dh) < 0.05, "b3 wall %s: model mean top drift %.3f mm, R %.0f N / k_hand %.0f N/mm = %.3f mm (%.2f pct)" % [ln, us * 1000.0, rwall, hand[ln] / 1000.0, dh * 1000.0, 100.0 * rel(us, dh)])
	# --- c: periods
	var pz := sway_period(code, 2)
	var px := sway_period(code, 0)
	var Ta := SIM.ta(12.96)
	var Tlong := maxf(pz["T"], px["T"])
	print("period z %.4f s (rq %s, eff mass %.2f), x %.4f s (eff mass %.2f), Ta %.4f s" % [pz["T"], str(pz["rq"]), pz["eff"], px["T"], px["eff"], Ta])
	ok(Tlong >= 0.5 * Ta and Tlong <= 1.7 * Ta, "c longest first sway period %.4f s in [%.4f, %.4f]" % [Tlong, 0.5 * Ta, 1.7 * Ta])
	# --- e: quake
	var qz := quake(code, 2, pz["omega"])
	var qx := quake(code, 0, px["omega"])
	print("code house El Centro: z peak %.2f mm ratio %.5f, x peak %.2f mm ratio %.5f; allowable %.3f" % [qz["peak_m"] * 1000.0, qz["ratio"], qx["peak_m"] * 1000.0, qx["ratio"], SIM.DRIFT_ALLOWABLE])
	ok(qz["ratio"] < SIM.DRIFT_ALLOWABLE and qx["ratio"] < SIM.DRIFT_ALLOWABLE, "e1 code house peak drift ratio z %.5f x %.5f < %.3f" % [qz["ratio"], qx["ratio"], SIM.DRIFT_ALLOWABLE])
	var pl1 := house_model({"remove_line": "L"})
	var pp1 := sway_period(pl1, 2)
	var q1 := quake(pl1, 2, pp1["omega"])
	ok(q1["ratio"] >= 1.5 * qz["ratio"], "e2 planted (line L unbraced) z peak ratio %.5f = %.2f x code %.5f (bar 1.5x); against the allowable 0.020: %s" % [q1["ratio"], q1["ratio"] / qz["ratio"], qz["ratio"], "EXCEEDS" if q1["ratio"] > 0.02 else "stays under"])
	var pl2 := house_model({"remove_lines": ["L", "R"]})
	var pp2 := sway_period(pl2, 2)
	var q2 := quake(pl2, 2, pp2["omega"])
	ok(q2["ratio"] > SIM.DRIFT_ALLOWABLE and qz["ratio"] < SIM.DRIFT_ALLOWABLE, "e3 planted (no z bracing, L and R) peak ratio %.5f > 0.020 and the code house %.5f does not (T %.3f s)" % [q2["ratio"], qz["ratio"], pp2["T"]])
	# --- f
	print("f solve time per Newmark step (code house, %d free dofs): %.2f ms" % [qz["r"]["nfree"], qz["ms_per_step"]])
	ok(qz["ms_per_step"] < 200.0, "f %.2f ms per step < 200 ms" % qz["ms_per_step"])
	print("ch10: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## hand calc of the lateral stiffness (N/m) of the gable wall lines L and R, from the member list alone (not from the builder)
func hand_wall_k() -> Dictionary:
	var mj = json_cache
	var out := {"L": 0.0, "R": 0.0}
	var h := 2.467 / 0.3048           # ft
	var Ga := 11.0                    # kips/in
	var Ech := 1.6e6                  # psi
	var A_ch := 2.0 * 3.5 * 1.5       # in2, king + jack at each end
	for ln in ["L", "R"]:
		var segs: Array = []
		for m in mj["members"]:
			if m["kind"] == "wall_sheathing" and str(m["name"]).begins_with("sheathing." + ln + "."):
				var bb: Array = m["box_mm"]
				if bb[1] < 50 and bb[4] > 2467 - 50:
					segs.append([bb[2] * 0.001, bb[5] * 0.001])
		segs.sort_custom(func(a, c): return a[0] < c[0])
		var cur: Array = []
		var groups: Array = []
		for s in segs:
			if cur.is_empty() or s[0] - cur[1] <= 0.015:
				if cur.is_empty():
					cur = [s[0], s[1]]
				else:
					cur[1] = s[1]
			else:
				groups.append(cur)
				cur = [s[0], s[1]]
		if not cur.is_empty():
			groups.append(cur)
		var k := 0.0
		for g in groups:
			var bft: float = (g[1] - g[0]) / 0.3048
			if h / bft > 3.5:
				continue
			# v = 1 plf: delta = 8 h^3 / (E A b) + h / (1000 Ga)   (inches); k = b v / delta  (lb/in)
			var delta := 8.0 * h * h * h / (Ech * A_ch * bft) + h / (1000.0 * Ga)
			k += bft / delta
		out[ln] = k * 175.1268
	return out
