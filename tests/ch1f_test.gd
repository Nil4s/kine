extends SceneTree
## godot --headless --path . -s tests/ch1f_test.gd    (CH1f: soil-structure interaction, three building systems, expansive clay and wind on the CH1 house)
## LABEL: physics model with cited typical values, NOT an NBR code check. Sources and UNVERIFIED flags: docs/CH1f_REFERENCE.md.
## Bars (written and committed before the test was run):
##  a  FIXED-BASE LIMIT  the SSI model with a huge Vs (VS_FIX m/s, P-delta off) gives the first x period of the CH10 fixed-base model within 1 pct, for the wood house, and for the masonry and
##                       light steel houses against their own fixed-base models.
##  a2 UNITS CONTROL     the same bar with Vs entered as ft/s but used as m/s... the number VS_FIX_FT is VS_FIX in ft/s; read as m/s it is 3.28 x stiffer (harmless), so the planted error is the other way:
##                       a Vs given in m/s and treated as ft/s (VS_FIX / 3.28084). It must FAIL the 1 pct bar for at least one system (the heavy masonry one), else the bar cannot detect a units slip.
##  b  SDOF ON FOOTING   one column + mass on a 3 x 3 m footing, stiff clay: the period lengthening T~/T from the solver equals Veletsos-Meek sqrt(1 + k/Kx + k h^2/Ktheta) with Gazetas Kx and Ktheta within 5 pct.
##  c  MONOTONIC         period rises strictly rock < dense < stiff clay < soft clay, for each of the three systems.
##  d  MASONRY vs WOOD   on the soft clay, the fractional period shift (T_soft - T_fixed)/T_fixed of the masonry house is larger than the wood house's. PREDICTION written before running:
##                       by Veletsos the shift is about (k/Kx + k h^2/Ktheta)/2 and does not depend on the mass but on the structure STIFFNESS k, so the ratio is about k_masonry/k_wood with
##                       k = M (2 pi/T_fixed)^2, expected of order 100 (masonry ~32 t at ~0.05 s against wood ~7 t at ~0.29 s). Bar: ratio > 1 and within a factor 3 of that k ratio.
##  e  EULER             P-delta: the axial load that makes K + Kg singular (bisection on positive definiteness) equals pi^2 E I/(K L)^2 within 2 pct, cantilever (K 2) and pinned-pinned (K 1).
##                       CONTROL: with no geometric stiffness the column never becomes singular below 3 x Pe.
##  f  MASS TAKEOFF      model mass of wood, masonry and light steel each within 5 pct of an independent hand takeoff from the member list and the stated unit masses.
##  g  P-DELTA SIGN      gravity P-delta lengthens each system's fixed-base period (T_pd > T_no_pd).
##  h  C++ == GDScript   10-node frame with soil springs, dashpots, penalty ties and P-delta: static u, modal omega and a Newmark record within 1e-9 relative.
##  i  HEAVE             free heave follows dh = H eps max(0, 1 - q/ps); heavier masonry heaves less than wood; pier distortion is linear in dh (doubling the swell strain doubles it within 1 pct).
##  j  WIND              NBR 6123-form wind pressure q = 0.613 Vk^2 equals a hand calc within 0.5 pct and the applied force equals p_net x area; the wind base shear is printed against the zone 0 seismic bound.
const FR := preload("res://scripts/build/ch10_frame.gd")
const SYS := preload("res://scripts/build/ch1f_systems.gd")
const SO := preload("res://scripts/build/ch1f_soil.gd")
const AN := preload("res://scripts/build/ch1f_analysis.gd")
const VS_FIX := 5000.0     # m/s, "very large"
const VS_REF := 1500.0     # m/s, the rock/hard-rock boundary used for the units control
var fails := 0
var mj: Dictionary


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func _init() -> void:
	print("CH1f: %s" % SO.LABEL)
	if not FR.native_ok():
		print("FAIL the native frame class is not loaded")
		quit(1)
		return
	mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var sysd := {}
	for n in ["wood", "masonry", "lsf"]:
		sysd[n] = SYS.build(n, mj)
	bar_a(sysd)
	bar_b()
	var tab := bar_cd(sysd)
	bar_e()
	bar_f(sysd)
	bar_g(sysd)
	bar_h()
	bar_i(sysd)
	bar_j(sysd)
	bar_j2()
	table(sysd)
	print("ch1f: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func fixed_T(sys: Dictionary, pd := false) -> float:
	var asm_opts := {"pdelta": pd}
	var r := AN.first_period(sys, null, asm_opts, 0)
	return r["T"] if not r.has("error") else -1.0


func ssi_T(sys: Dictionary, s: Dictionary, pd := false) -> float:
	var r := AN.first_period(sys, s, {"pdelta": pd}, 0)
	return r["T"] if not r.has("error") else -1.0


func bar_a(sysd: Dictionary) -> void:
	var worst_ctl := 0.0
	for n in sysd:
		var sys: Dictionary = sysd[n]
		var T0 := fixed_T(sys)
		var big := SO.soil("rock", VS_FIX)
		var T1 := ssi_T(sys, big)
		var d := rel(T1, T0)
		ok(T0 > 0.0 and d < 0.01, "a fixed-base limit %s: Vs %.0f m/s T %.5f s vs fixed %.5f s (%.3f pct)" % [n, VS_FIX, T1, T0, d * 100.0])
		# units control: a Vs of 1500 m/s entered in m/s but treated as ft/s -> 457 m/s; the right value is 1500
		var good := ssi_T(sys, SO.soil("rock", VS_REF))
		var bad := ssi_T(sys, SO.soil("rock", VS_REF / SO.FT_PER_M))
		var dg := rel(good, T0)
		var db := rel(bad, T0)
		print("     %s units control: Vs 1500 -> %.3f pct from fixed; as 457 m/s (ft/s slip) -> %.3f pct" % [n, dg * 100.0, db * 100.0])
		worst_ctl = maxf(worst_ctl, db)
	ok(worst_ctl > 0.01, "a2 planted control: the m/s -> ft/s slip fails the 1 pct fixed-base bar for at least one system (worst %.3f pct)" % (worst_ctl * 100.0))


func bar_b() -> void:
	# SDOF: column h 3.0 m, 0.8 x 0.8 m, E 30 GPa, mass 50 t at the top, footing 3 x 3 m, base node 0.05 m above the footing node
	var E := 30.0e9
	var b := 0.8
	var I := b * b * b * b / 12.0
	var h := 3.0
	var k := 3.0 * E * I / (h * h * h)
	var xyz := PackedFloat64Array([1.5, 0.05, 1.5, 1.5, 0.05 + h, 1.5])
	var beams := PackedFloat64Array([0, 1, b * b, I, I, 2.0 * I, E, E / 2.4, 0.0, 1, 0, 0])
	var fixed := PackedInt32Array([3, 4, 5])    # base rotations; the translations are fixed (fixed base) or tied to the footing
	var mass := PackedFloat64Array([0.0, 5.0e4])
	var sys := {"name": "sdof", "model": {"xyz": xyz, "beams": beams, "springs": PackedFloat64Array(), "fixed": fixed, "mass": mass},
		"base": PackedInt32Array([0]), "top": PackedInt32Array([1]), "base_mass": 0.0, "mass_total": 5.0e4, "panels": []}
	var s := SO.soil("stiff_clay")
	var o := {"lx": 3.0, "lz": 3.0, "foot_mass": 0.0, "tie_rot": true, "pdelta": false}
	var T0 := AN.first_period(sys, null, o, 0)["T"] as float
	var T1 := AN.first_period(sys, s, o, 0)["T"] as float
	var g := SO.gazetas(s, 3.0, 3.0)
	var rc := SO.veletsos_ratio(k, h + 0.05, g["kx"], g["rz"])
	var rn := T1 / T0
	print("     SDOF: k %s N/m, Kx %s, Krz %s, T fixed %.5f s, T SSI %.5f s, ratio %.4f, closed form %.4f" % [String.num_scientific(k), String.num_scientific(g["kx"]), String.num_scientific(g["rz"]), T0, T1, rn, rc])
	ok(rel(T0, TAU * sqrt(5.0e4 / k)) < 0.01, "b SDOF fixed period equals 2 pi sqrt(m/k) within 1 pct (%.5f s)" % T0)
	ok(rel(rn, rc) < 0.05, "b SDOF period lengthening %.4f vs Veletsos-Meek %.4f within 5 pct (%.2f pct)" % [rn, rc, rel(rn, rc) * 100.0])


func bar_cd(sysd: Dictionary) -> Dictionary:
	var out := {}
	for n in sysd:
		var sys: Dictionary = sysd[n]
		var Tf := fixed_T(sys, true)
		var ts: Array = []
		for id in SO.ORDER:
			ts.append(ssi_T(sys, SO.soil(id), true))
		out[n] = {"fixed": Tf, "T": ts}
		var mono := true
		for i in 3:
			if not (ts[i + 1] > ts[i]):
				mono = false
		ok(mono and ts[0] >= Tf * 0.999, "c %s period rises with softer soil: fixed %.5f, rock %.5f, dense %.5f, stiff clay %.5f, soft clay %.5f s" % [n, Tf, ts[0], ts[1], ts[2], ts[3]])
	var sh_w: float = (out["wood"]["T"][3] - out["wood"]["fixed"]) / out["wood"]["fixed"]
	var sh_m: float = (out["masonry"]["T"][3] - out["masonry"]["fixed"]) / out["masonry"]["fixed"]
	var kw: float = sysd["wood"]["mass_total"] * pow(TAU / out["wood"]["fixed"], 2)
	var km: float = sysd["masonry"]["mass_total"] * pow(TAU / out["masonry"]["fixed"], 2)
	var pred := km / kw
	var got := sh_m / sh_w
	print("     soft clay shift: wood %.4f pct, masonry %.4f pct, ratio %.1f; predicted k_m/k_w %.1f" % [sh_w * 100.0, sh_m * 100.0, got, pred])
	ok(sh_m > sh_w and got > 1.0, "d masonry shifts more than wood on soft clay (ratio %.1f)" % got)
	ok(got > pred / 3.0 and got < pred * 3.0, "d the ratio %.1f is within a factor 3 of the predicted k ratio %.1f" % [got, pred])
	return out


func column_model(n: int, L: float, E: float, b: float, support: String) -> Dictionary:
	var xyz := PackedFloat64Array()
	var beams := PackedFloat64Array()
	var I := b * b * b * b / 12.0
	for i in n + 1:
		xyz.append_array([0.0, L * i / n, 0.0])
	for i in n:
		beams.append_array([i, i + 1, b * b, I, I, 2.0 * I, E, E / 2.6, 0.0, 1, 0, 0])
	var fixed := PackedInt32Array()
	if support == "cantilever":
		fixed.append_array([0, 1, 2, 3, 4, 5])
	else:
		fixed.append_array([0, 1, 2, 4, n * 6, n * 6 + 2])
	return {"xyz": xyz, "beams": beams, "springs": PackedFloat64Array(), "fixed": fixed, "mass": PackedFloat64Array()}


func buckles(model: Dictionary, P: float, probe: int, use_kg: bool) -> bool:
	var m := model.duplicate()
	if use_kg:
		var ax := PackedFloat64Array()
		for i in (model["beams"] as PackedFloat64Array).size() / 12:
			ax.append(-P)
		m["axial"] = ax
	var n: int = (m["xyz"] as PackedFloat64Array).size() / 3
	var load := PackedFloat64Array()
	load.resize(n * 6)
	load[probe] = 1.0
	return FR.solve(m, {"type": "static", "loads": load}).has("error")


func critical(model: Dictionary, probe: int, hi: float, use_kg: bool) -> float:
	if not buckles(model, hi, probe, use_kg):
		return INF
	var lo := 0.0
	for it in 50:
		var mid := 0.5 * (lo + hi)
		if buckles(model, mid, probe, use_kg):
			hi = mid
		else:
			lo = mid
	return 0.5 * (lo + hi)


func bar_e() -> void:
	var E := 1.0e10
	var b := 0.1
	var L := 3.0
	var I := b * b * b * b / 12.0
	var pe_c := PI * PI * E * I / pow(2.0 * L, 2)
	var pe_p := PI * PI * E * I / (L * L)
	var mc := column_model(16, L, E, b, "cantilever")
	var mp := column_model(16, L, E, b, "pinned")
	var pc := critical(mc, 16 * 6, 3.0 * pe_c, true)
	var pp := critical(mp, 8 * 6, 3.0 * pe_p, true)
	ok(rel(pc, pe_c) < 0.02, "e cantilever buckling load %.2f N vs Euler %.2f N (%.3f pct)" % [pc, pe_c, rel(pc, pe_c) * 100.0])
	ok(rel(pp, pe_p) < 0.02, "e pinned-pinned buckling load %.2f N vs Euler %.2f N (%.3f pct)" % [pp, pe_p, rel(pp, pe_p) * 100.0])
	var pn := critical(mc, 16 * 6, 3.0 * pe_c, false)
	ok(pn == INF, "e control: without the geometric stiffness the column never buckles below 3 Pe")


func bar_f(sysd: Dictionary) -> void:
	var oa := SYS.opening_area(mj)
	var gross := 2.0 * (9.754 + 7.620) * 2.467
	var net: float = gross - oa["window"] - oa["door"]
	var glass: float = (oa["window"] + oa["door"]) * 30.0
	# partitions: all top_plate1 members that are not on the four outer lines, less the interior doors
	var part_len := 0.0
	var idoor := 0.0
	for m in mj["members"]:
		var bx: Array = m["box_mm"]
		if m["kind"] == "top_plate1" and not (str(m["name"]).split(".")[1] in ["F", "B", "L", "R"]):
			part_len += maxf(bx[3] - bx[0], bx[5] - bx[2]) * 0.001
		if m["kind"] == "idoor":
			idoor += (bx[5] - bx[2]) * (bx[4] - bx[1]) * 1e-6 if (bx[3] - bx[0]) < 200 else (bx[3] - bx[0]) * (bx[4] - bx[1]) * 1e-6
	var part := (part_len * 2.467 - idoor) * 30.0
	var slope := 9.754 * (7.620 + 0.812) * sqrt(10.0) / 3.0
	var gable := 2.0 * 0.5 * 7.620 * (3.95 - 2.467)
	var ceil_m := 9.754 * 7.620 * 10.7
	# masonry
	var nc := 0
	var ends := {}
	for ln in ["F", "B", "L", "R"]:
		var ops: Array = []
		for m in mj["members"]:
			if (m["kind"] == "window" or m["kind"] == "door") and str(m["name"]).split(".")[1] == ln:
				var bx2: Array = m["box_mm"]
				var al := 0 if (ln == "F" or ln == "B") else 2
				ops.append([bx2[al] * 0.001, bx2[al + 3] * 0.001])
		ops.sort_custom(func(p, q): return p[0] < q[0])
		var total := 9.754 if (ln == "F" or ln == "B") else 7.620
		var pts: Array = [0.07]
		for o in ops:
			pts.append(o[0])
			pts.append(o[1])
		pts.append(total - 0.07)
		for p in pts:
			var key := Vector2i(roundi((p if (ln == "F" or ln == "B") else (0.07 if ln == "L" else 9.684)) * 1000.0), roundi((0.07 if ln == "F" else (7.55 if ln == "B" else p)) * 1000.0))
			ends[key] = true
	nc = ends.size()
	var tie_len := 2.0 * (9.754 - 0.14) + 2.0 * (7.620 - 0.14)
	var mas: float = net * 255.0 + nc * 0.14 * 0.14 * 2.467 * 2500.0 + tie_len * 0.14 * (0.19 + 0.30) * 2500.0 + gable * 255.0 + glass + part + slope * 60.0 + ceil_m
	var mm: float = sysd["masonry"]["mass_total"]
	ok(rel(mm, mas) < 0.05, "f masonry mass %.0f kg vs hand takeoff %.0f kg (%.2f pct); %d tie columns" % [mm, mas, rel(mm, mas) * 100.0, nc])
	# light steel
	var cs := SYS.cee_section()
	var nst := 0
	var nop := 0
	for ln in ["F", "B", "L", "R"]:
		var len := (9.754 if (ln == "F" or ln == "B") else 7.620) - 0.14
		nst += int(ceil(len / 0.4)) + 1
		for m in mj["members"]:
			if (m["kind"] == "window" or m["kind"] == "door") and str(m["name"]).split(".")[1] == ln:
				nop += 1
	nst += 2 * nop
	var trk_a := (0.090 + 0.080) * 0.00095
	var steel: float = nst * cs["A"] * 2.467 * 7850.0 + 2.0 * 2.0 * (9.754 + 7.620 - 0.28) * trk_a * 7850.0
	var lsf: float = steel + net * (7.1 + 11.0 + 10.7) + gable * 25.0 + glass + part + slope * (8.0 + 7.1 + 9.8) + ceil_m
	var ml: float = sysd["lsf"]["mass_total"]
	ok(rel(ml, lsf) < 0.05, "f light steel mass %.0f kg vs hand takeoff %.0f kg (%.2f pct); %d studs" % [ml, lsf, rel(ml, lsf) * 100.0, nst])
	# wood: framing volumes from the member boxes, finishes from areas
	var vol := 0.0
	var fin := 0.0
	var gyp_len := 0.0
	var joist_gyp := 0.0
	for m in mj["members"]:
		var bx3: Array = m["box_mm"]
		var dx: float = (bx3[3] - bx3[0]) * 0.001
		var dy: float = (bx3[4] - bx3[1]) * 0.001
		var dz: float = (bx3[5] - bx3[2]) * 0.001
		var k: String = m["kind"]
		if k in ["stud", "king", "jack", "cripple", "corner", "nailer", "end", "bottom_plate", "top_plate1", "top_plate2", "sill", "header", "joist", "ridge", "gable_stud"]:
			vol += dx * dy * dz
		elif k in ["rafter", "rafter_pair", "gable_rafter"]:
			vol += dx * 0.235 * (dz * sqrt(10.0) / 3.0 - 0.235 * 0.316)
		var area := maxf(dx * dy, maxf(dy * dz, dx * dz))
		if k == "wall_sheathing":
			fin += area * 7.1
		elif k == "siding":
			fin += area * 9.5
		elif k == "window" or k == "door":
			fin += area * 30.0
		elif k == "roof_sheathing":
			fin += dx * Vector2(m["poly"][0][0], m["poly"][0][1]).distance_to(Vector2(m["poly"][1][0], m["poly"][1][1])) * 0.001 * 7.1
		elif k == "shingle":
			fin += dx * Vector2(m["poly"][0][0], m["poly"][0][1]).distance_to(Vector2(m["poly"][1][0], m["poly"][1][1])) * 0.001 * 9.8
		elif k == "gable_sheathing":
			var a2 := 0.0
			var poly: Array = m["poly"]
			for i in poly.size():
				var p := Vector2(poly[i][0], poly[i][1])
				var q := Vector2(poly[(i + 1) % poly.size()][0], poly[(i + 1) % poly.size()][1])
				a2 += p.x * q.y - q.x * p.y
			fin += absf(a2) * 0.5e-6 * 7.1
		elif k == "joist":
			joist_gyp += maxf(dx, maxf(dy, dz)) * 0.4064 * 10.7
		elif k == "top_plate1":
			var faces := 1.0 if (str(m["name"]).split(".")[1] in ["F", "B", "L", "R"]) else 2.0
			gyp_len += maxf(dx, dz) * faces
	var wood := vol * 530.0 + fin + joist_gyp + gyp_len * 2.467 * 10.7
	var mw: float = sysd["wood"]["mass_total"]
	ok(rel(mw, wood) < 0.05, "f wood mass %.0f kg vs hand takeoff %.0f kg (%.2f pct)" % [mw, wood, rel(mw, wood) * 100.0])


func bar_g(sysd: Dictionary) -> void:
	for n in sysd:
		var a := fixed_T(sysd[n], false)
		var b := fixed_T(sysd[n], true)
		ok(b > a, "g P-delta lengthens the %s fixed-base period: %.6f -> %.6f s (+%.4f pct)" % [n, a, b, (b / a - 1.0) * 100.0])


func bar_h() -> void:
	var E := 1.0e10
	var b := 0.1
	var m := column_model(8, 3.0, E, b, "cantilever")
	m["fixed"] = PackedInt32Array()
	# footing node 9 at the base, ties from the column foot (node 0) to node 10, soil springs and dashpots on node 9, link beam 9 -> 10
	var xyz: PackedFloat64Array = m["xyz"]
	xyz.append_array([0.5, 0.0, 0.0, 0.0, 0.0, 0.0])
	m["xyz"] = xyz
	var bm: PackedFloat64Array = m["beams"]
	bm.append_array([9, 10, 1.0, 1.0, 1.0, 2.0, 1e13, 1e13 / 2.6, 0.0, 0, 1, 0])
	m["beams"] = bm
	var I := b * b * b * b / 12.0
	m["ties"] = PackedFloat64Array([0, 60, 1e12, 1, 61, 1e12, 2, 62, 1e12, 3, 63, 1e12, 4, 64, 1e12, 5, 65, 1e12])
	m["dofk"] = PackedFloat64Array([54, 2e8, 55, 5e8, 56, 2e8, 57, 3e8, 58, 3e8, 59, 3e8])
	m["dofc"] = PackedFloat64Array([54, 1e5, 55, 2e5, 57, 5e4])
	var mass := PackedFloat64Array()
	mass.resize(11)
	for i in 9:
		mass[i] = 100.0
	mass[9] = 500.0
	m["mass"] = mass
	var ax := PackedFloat64Array()
	for i in 8:
		ax.append(-0.3 * PI * PI * E * I / 36.0)
	ax.append(0.0)
	m["axial"] = ax
	# the ties above address node 10 dofs 60.. but node 10 is index 10: dofs 60..65; fix the ones that name node 0 dofs against node 10
	var n := 11
	var ag := PackedFloat64Array()
	for i in 201:
		ag.append(3.0 * sin(0.2 * i) * exp(-0.01 * i))
	var load := PackedFloat64Array()
	load.resize(n * 6)
	load[8 * 6] = 1000.0
	load[8 * 6 + 1] = -500.0
	var worst := 0.0
	var js := [{"type": "static", "loads": load}, {"type": "modal", "start": load, "iters": 5},
		{"type": "newmark", "dt": 0.01, "nsteps": 200, "ag": ag, "dir": 0, "alpha": 0.5, "beta": 0.001, "record": PackedInt32Array([8 * 6, 9 * 6, 8 * 6 + 1])}]
	var names := ["static u", "modal omega", "newmark rec_u"]
	for j in 3:
		var c := FR.solve(m, js[j])
		var g := FR.solve(m, js[j], true)
		if c.has("error") or g.has("error"):
			ok(false, "h %s error: %s / %s" % [names[j], str(c.get("error", "")), str(g.get("error", ""))])
			continue
		var a: Variant
		var bb: Variant
		if j == 0:
			a = c["u"]
			bb = g["u"]
		elif j == 1:
			a = PackedFloat64Array([c["omega"]])
			bb = PackedFloat64Array([g["omega"]])
		else:
			a = c["rec_u"]
			bb = g["rec_u"]
		var mx := 0.0
		var sc := 0.0
		for i in a.size():
			mx = maxf(mx, absf(a[i] - bb[i]))
			sc = maxf(sc, absf(bb[i]))
		ok(mx / maxf(sc, 1e-300) < 1e-9, "h C++ == GDScript %s: max difference %s relative" % [names[j], String.num_scientific(mx / maxf(sc, 1e-300))])


func bar_i(sysd: Dictionary) -> void:
	var s := SO.soil("stiff_clay")
	var hw := AN.heave(sysd["wood"], s)
	var hm := AN.heave(sysd["masonry"], s)
	var hl := AN.heave(sysd["lsf"], s)
	for r in [["wood", hw], ["masonry", hm], ["lsf", hl]]:
		var d: Dictionary = r[1]
		if d.has("error"):
			ok(false, "i heave %s error %s" % [r[0], d["error"]])
			return
		print("     heave %s: q %.1f kPa, dh %.2f mm, peak pier distortion %s, unit shear %.2f kN/m (%.1f pct of capacity)" % [r[0], d["q"] / 1000.0, d["dh"] * 1000.0, String.num_scientific(d["gamma"]), d["v"] / 1000.0, d["ratio"] * 100.0])
		var expect := SO.heave_free(d["q"])
		ok(absf(d["dh"] - expect) < 1e-12, "i %s free heave equals H eps (1 - q/ps): %.3f mm" % [r[0], d["dh"] * 1000.0])
	ok(hm["q"] > hw["q"] and hm["dh"] <= hw["dh"], "i heavier masonry carries more pressure (%.1f > %.1f kPa) and heaves no more (%.2f <= %.2f mm)" % [hm["q"] / 1000.0, hw["q"] / 1000.0, hm["dh"] * 1000.0, hw["dh"] * 1000.0])
	var h2 := AN.heave(sysd["masonry"], s, {"eps": 2.0 * SO.EPS_FREE})
	var r2: float = h2["gamma"] / hm["gamma"]
	# eps doubles dh before the q relief, and dh = H eps (1 - q/ps) is linear in eps
	ok(absf(r2 - 2.0) < 0.02, "i pier distortion is linear in the swell strain: doubling eps gives x%.4f" % r2)


func bar_j(sysd: Dictionary) -> void:
	var wd := SO.wind(2.467 + 0.7)
	var s2 := 0.94 * pow((2.467 + 0.7) / 10.0, 0.105)
	var q_hand := 0.613 * pow(35.0 * s2, 2)
	ok(rel(wd["q"], q_hand) < 0.005, "j wind q %.1f Pa vs hand %.1f Pa" % [wd["q"], q_hand])
	var w := AN.wind(sysd["masonry"], SO.soil("dense"))
	ok(not w.has("error") and rel(w["Fz"], q_hand * 1.2 * 9.754 * 2.467) < 0.005, "j applied wind force %.0f N = p_net x area" % w.get("Fz", 0.0))


## j2 (added 2026-11-04 after bar j was found to disagree with a clamp that had crept into SO.wind; written before this run)
##  the optional 5 m S2 floor (NBR 6123 S2 table starts at 5 m, MEMORY/UNVERIFIED) gives q = 0.613 (35 x 0.94 (5/10)^0.105)^2 within 0.5 pct, does nothing at z >= 5 m,
##  and CONTROL: at z = 3.167 m the floored q exceeds the unfloored one by more than 5 pct (so bar j really tests the unfloored formula).
func bar_j2() -> void:
	var qf: float = SO.wind(3.167, SO.V0_CUIABA, 1.0, 1.0, true)["q"]
	var qh := 0.613 * pow(35.0 * 0.94 * pow(0.5, 0.105), 2)
	ok(rel(qf, qh) < 0.005, "j2 floored wind q %.1f Pa vs hand at 5 m %.1f Pa" % [qf, qh])
	ok(rel(SO.wind(8.0, SO.V0_CUIABA, 1.0, 1.0, true)["q"], SO.wind(8.0)["q"]) < 1e-12, "j2 floor does nothing at z = 8 m")
	ok(qf > SO.wind(3.167)["q"] * 1.05, "j2 control: floored q %.1f Pa exceeds unfloored %.1f Pa by more than 5 pct" % [qf, SO.wind(3.167)["q"]])


func table(sysd: Dictionary) -> void:
	print("")
	print("CH1f table (%s). El Centro NS unscaled (a unit-test input, NOT a Mato Grosso hazard), x direction, 30 s, P-delta on." % SO.LABEL)
	print("%-8s %-11s %5s %9s %11s %10s %9s %9s %11s" % ["system", "soil", "class", "T s", "V base kN", "roof drift", "heave dh", "unit shear", "shear/cap"])
	for n in ["wood", "masonry", "lsf"]:
		var sys: Dictionary = sysd[n]
		for id in SO.ORDER:
			var s := SO.soil(id)
			var q := AN.quake(sys, s, {})
			var h := AN.heave(sys, s)
			if q.has("error") or h.has("error"):
				print("%-8s %-11s error %s %s" % [n, id, str(q.get("error", "")), str(h.get("error", ""))])
				fails += 1
				continue
			print("%-8s %-11s %5s %9.4f %11.2f %10.5f %8.2f mm %7.2f kN/m %9.1f%%" % [n, id, s["asce"], q["T"], q["V"] / 1000.0, q["drift"], h["dh"] * 1000.0, h["v"] / 1000.0, h["ratio"] * 100.0])
	print("")
	print("Wind (NBR 6123 form, V0 35 m/s UNVERIFIED) vs the zone 0 bound (UNVERIFIED), dense soil, base shear kN / roof drift ratio / bound 2.5 ag Ca W (R = 1) kN")
	for n in ["wood", "masonry", "lsf"]:
		var w := AN.wind(sysd[n], SO.soil("dense"))
		var sb := AN.seismic0_shear(sysd[n]["mass_total"] + SYS.LX * SYS.LZ * SYS.SLAB_T * SYS.RHO_RC, "C")
		print("%-8s wind %7.2f kN  drift %.6f   seismic zone 0 bound %7.2f kN   mass %.0f kg" % [n, w["Fz"] / 1000.0, w["drift"], sb / 1000.0, sysd[n]["mass_total"]])
