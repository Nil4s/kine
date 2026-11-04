extends SceneTree
## godot --path . -s tests/ch13_test.gd   (CH13: a single-cylinder engine, Honda C50 class; tolerances, thermal fit, stack-up, slider-crank torque, FDM compensation; docs/CH13_REFERENCE.md)
## Bars (written and committed before the first run). Every bar's hand arithmetic / closed form is in this file as literals; every bar has a PLANTED CONTROL that must fail (a "ctl" line).
##  a1 IT TABLE      every table IT value (IT5..IT10, 6 to 180 mm) is within 1.5 um of the ISO formula (k x i). CONTROL: a table with IT7 swapped for IT6 is caught (> 1 um).
##  a2 FUND DEVS     g, f, e, d, k within 1.5 um of the ISO formulas, m = IT7 - IT6, p in [IT7, IT7+5], in every size range. CONTROL: shaft letter f given g's value is caught.
##  a3 PUBLISHED     Grgic 2023 Table 4, 35 mm: H9 +62/0, h9 0/-62, g9 -9/-71, f9 -25/-87. CONTROL: H8 is not 62.
##  a4 FITS          hand-computed min / max clearance and kind for G6/h5, JS6/h5, H7/f7 (20), H7/e7 (39), H7/f7 (18). CONTROL: the transition fit is not allowed to pass as clearance-only; H6/p5 is an interference.
##  b  THERMAL       piston 39 H7/e7 in an iron bore: closure 42.90 um by hand, hot min 7.10 / max 57.10; boss JS6/h5 opens by 16.055. The code picks H7/e7; CONTROL: the textbook H7/f7 goes to -17.9 hot (seizure flagged); equal CTE gives no closure.
##  c  STACK-UP      end-float and deck clearance: worst = sum |t|, RSS = sqrt(sum t^2), by hand; all 2^n corners equal the worst case. CONTROL: an algebraic (signed) sum is not the worst case; RSS is not the worst case.
##  d  KINEMATICS    x(0), x(90), x(180) closed forms; torque = -F dx/dtheta (central difference, 1e-6); T = 0 at both dead centres. CONTROL: F r sin(th) (no rod obliquity) is 13 pct off at 60 deg.
##  e  CYCLE         Otto cycle: integral of slider-crank torque = p1 Vc (tau-1)(rc^n - rc)/(n-1) (0.5 pct); Wiebe curve: pdV IMEP = torque IMEP (0.5 pct); inertia has zero mean and
##                   peak m r w^2 (1+lambda) at TDC; P = T w; brake power at 7000 rpm and brake torque at 5000 rpm each 0.5x to 1.5x of the Honda C50 spec (2.5 kW, 3.8 N m). CONTROL: motored (tau = 1) is rejected.
##  f  PRINT         Grgic rule: CAD at mid-zone (13.0275 / 12.9785 for G9/h9 at 13), HHE 0.13 per side lands the printed hole on the mid; uncompensated lands outside the zone. IT6 is flagged not demonstrated, IT9 is.
##                   CONTROL: uncompensated printed hole outside the hole limits.
##  g  PARTS         seven Parts build (one body each); volumes vs closed form (piston with the pin hole by quadrature, pin, cylinder, head, crankcase), rod bore volume by hand. CONTROL: a part with a 13.5 pin bore fails the volume bar.
##  h  ASSEMBLY      the posed parts: crank pin = rod big end, rod small end = piston pin, pin height = x(theta) (1e-6 mm), over 2 revolutions; periodic at +360; piston stroke 41.4. CONTROL: a rod left unturned is > 1 mm off.
##  i  SHEET         12 frames over 2 revolutions rendered: each differs from the last, frame(theta) == frame(theta + 360), frame(0) != frame(180); the section view shows cap colours (>= 800 px), the whole view none. Skipped when headless.
##  j  INTERFERENCE  (added at the lead's review, committed before its first run) KCad.overlap_volume on the posed exact solids. At 36 crank angles (every 10 deg, TDC and BDC included) every pair
##                   that is not a fit pair overlaps 0, and the 5 fit pairs overlap 0 too (the joints stay coaxial). Each fit pair at 40 deg, nominal (mid-zone) sizes: a gauge of the shaft grown to the
##                   fit's minimum clearance overlaps 0 (the geometry carries at least the fit's clearance) and a gauge 2 um bigger than the hole overlaps (the check can see a few um). The piston
##                   crown to head gap at TDC, measured on the solids (bisection on a lift of the piston), equals the deck clearance nominal within 5 um.
##                   CONTROLS: a rod 2 mm longer puts the piston into the head at TDC; a pin 1 mm oversize overlaps the rod's small end.
var fails := 0
var nok := 0
const E := preload("res://scripts/build/ch13_engine.gd")
const P := preload("res://scripts/build/ch13_parts.gd")
const S := preload("res://scripts/build/ch13_scene.gd")
const KCad := preload("res://scripts/kcad.gd")
const OUT := "C:/Temp/claude/ch13"
## AMENDED after the first run (documented): Transform3D is single precision, so a pose measured through it is good to ~2e-6 mm at 100 mm, not 1e-6; the bar is 1e-4 mm (0.1 um), still 100x finer than the smallest fit band (5.5 um)
const TOL_MM := 1e-4


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
	nok += 1 if c else 0


func ctl(c: bool, w: String) -> void:   # a planted control: c is true when the control WAS caught (the bar can fail)
	ok(c, "ctl " + w)


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func relnear(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol * maxf(absf(b), 1e-300)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	bars_iso()
	bars_thermal()
	bars_stack()
	bars_kin()
	bars_cycle()
	bars_print()
	bars_parts()
	bars_assembly()
	bars_interference()
	await bars_sheet()
	print("ch13: %d ok, %d fail" % [nok, fails])
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------------------------------------ a
func bars_iso() -> void:
	var worst := 0.0
	for ri in E.RANGES.size():
		var d: float = sqrt(float(E.RANGES[ri][0]) * float(E.RANGES[ri][1]))
		for g in [5, 6, 7, 8, 9, 10]:
			worst = maxf(worst, absf(E.it(g, d) - E.it_formula(g, d)))
	ok(worst <= 1.5, "a1 every IT5..IT10 table value is within 1.5 um of k x i (worst %.2f um)" % worst)
	var bad: Dictionary = E.it_table().duplicate(true)
	bad[7] = (E.it_table()[6] as Array).duplicate()
	ctl(E.it_table_maxdiff(bad) > 1.5, "a1 an IT table with IT7 = IT6 is caught (max diff %.2f um)" % E.it_table_maxdiff(bad))
	ok(E.it_table_maxdiff(E.it_table()) <= 1.5, "a1 the real table passes the same checker (%.2f um)" % E.it_table_maxdiff(E.it_table()))

	var wf := 0.0
	var wm := 0.0
	var pin := true
	for ri in E.RANGES.size():
		var d2: float = sqrt(float(E.RANGES[ri][0]) * float(E.RANGES[ri][1]))
		for l in ["g", "f", "e", "d", "k"]:
			wf = maxf(wf, absf(E.fund(l, d2) - E.fund_formula(l, d2)))
		wm = maxf(wm, absf(E.fund("m", d2) - (E.it(7, d2) - E.it(6, d2))))
		var pv: float = E.fund("p", d2)
		pin = pin and pv >= E.it(7, d2) and pv <= E.it(7, d2) + 5.0
	ok(wf <= 1.5, "a2 g f e d k fundamental deviations within 1.5 um of the formulas, all ranges (worst %.2f um)" % wf)
	ok(wm == 0.0 and pin, "a2 m = IT7 - IT6 exactly and p in [IT7, IT7+5] in every range")
	ctl(absf(E.fund("f", 23.24) - E.fund_formula("g", 23.24)) > 1.5, "a2 f given g's formula value is caught (f %.0f vs g-formula %.2f)" % [E.fund("f", 23.24), E.fund_formula("g", 23.24)])

	var h9: Dictionary = E.hole("H", 9, 35.0)
	var s_h9: Dictionary = E.shaft("h", 9, 35.0)
	var s_g9: Dictionary = E.shaft("g", 9, 35.0)
	var s_f9: Dictionary = E.shaft("f", 9, 35.0)
	ok(h9["ES"] == 62.0 and h9["EI"] == 0.0 and s_h9["es"] == 0.0 and s_h9["ei"] == -62.0, "a3 35 H9 +62/0 and h9 0/-62 (Grgic Table 4)")
	ok(s_g9["es"] == -9.0 and s_g9["ei"] == -71.0 and s_f9["es"] == -25.0 and s_f9["ei"] == -87.0, "a3 35 g9 -9/-71 and f9 -25/-87 (Grgic Table 4)")
	ctl(E.hole("H", 8, 35.0)["ES"] != 62.0, "a3 a wrong grade (H8) is not 62 (is %.0f)" % E.hole("H", 8, 35.0)["ES"])

	var f1: Dictionary = E.fit(13.0, "G6", "h5")
	var f2: Dictionary = E.fit(13.0, "JS6", "h5")
	var f3: Dictionary = E.fit(20.0, "H7", "f7")
	var f4: Dictionary = E.fit(39.0, "H7", "e7")
	var f5: Dictionary = E.fit(18.0, "H7", "f7")
	ok(f1["cmin"] == 6.0 and f1["cmax"] == 25.0 and f1["kind"] == "clearance", "a4 pin in rod small end 13 G6/h5: hole +17/+6, shaft 0/-8 -> clearance 6..25 um")
	ok(f2["cmin"] == -5.5 and f2["cmax"] == 13.5 and f2["kind"] == "transition", "a4 pin in piston boss 13 JS6/h5: hole +5.5/-5.5 -> -5.5..+13.5 um, a transition fit")
	ok(f3["cmin"] == 20.0 and f3["cmax"] == 62.0 and f3["kind"] == "clearance", "a4 crank journal 20 H7/f7: hole +21/0, shaft -20/-41 -> 20..62 um")
	ok(f4["cmin"] == 50.0 and f4["cmax"] == 100.0 and f4["kind"] == "clearance", "a4 piston in bore 39 H7/e7: hole +25/0, shaft -50/-75 -> 50..100 um")
	ok(f5["cmin"] == 16.0 and f5["cmax"] == 52.0 and f5["kind"] == "clearance", "a4 crank pin in big end 18 H7/f7: hole +18/0, shaft -16/-34 -> 16..52 um")
	ctl(f2["kind"] != "clearance" and f2["cmin"] < 0.0, "a4 the JS6/h5 boss fit flagged clearance would be wrong: it is %s with min %.1f" % [f2["kind"], f2["cmin"]])
	var p5: Dictionary = E.fit(13.0, "H6", "p5")
	ctl(p5["kind"] == "interference" and p5["cmax"] < 0.0, "a4 13 H6/p5 is an interference (%.0f..%.0f um), never clearance" % [p5["cmin"], p5["cmax"]])


# ------------------------------------------------------------------------------------------------ b
func bars_thermal() -> void:
	var a_al: float = E.ALPHA["4032"]
	var a_fe: float = E.ALPHA["iron"]
	var a_st: float = E.ALPHA["steel"]
	ok(a_al == 19.4 and a_fe == 10.5 and a_st == 11.7, "b CTEs as cited: 4032 19.4, grey iron 10.5, steel 11.7 (e-6 /K)")
	# by hand: piston grows 19.4e-6 x 100 K x 39 mm = 75.66 um; iron bore grows 10.5e-6 x 80 K x 39 mm = 32.76 um; closure 42.90 um
	var hot: Dictionary = E.hot_clearance(39.0, 50.0, 100.0, a_fe, 100.0, a_al, 120.0)
	ok(near(hot["delta"], -42.90, 1e-6), "b piston in bore closes by 42.90 um (75.66 - 32.76), got %.4f" % hot["delta"])
	ok(near(hot["cmin_hot"], 7.10, 1e-6) and near(hot["cmax_hot"], 57.10, 1e-6) and hot["cmin_hot"] > 0.0, "b 39 H7/e7 hot clearance 7.10..57.10 um, positive (got %.4f..%.4f)" % [hot["cmin_hot"], hot["cmax_hot"]])
	var boss: Dictionary = E.hot_clearance(13.0, -5.5, 13.5, a_al, 150.0, a_st, 130.0)
	ok(near(boss["delta"], 16.055, 0.001) and near(boss["cmin_hot"], 10.555, 0.001), "b boss JS6/h5 hot: aluminium boss 32.786 um vs steel pin 16.731 um -> opens by 16.055, min +10.555 (got %.3f / %.3f)" % [boss["delta"], boss["cmin_hot"]])
	var sel: Dictionary = E.select_piston_fit(39.0, ["H7/h6", "H7/g6", "H7/f7", "H7/e7", "H7/d8"])
	ok(sel["fit"] == "H7/e7", "b the code picks the tightest fit with hot min >= 5 um: %s" % sel["fit"])
	var f7: Dictionary = E.fit(39.0, "H7", "f7")
	ok(f7["cmin"] == 25.0, "b 39 H7/f7 cold min 25 um (hand)")
	var hot_f7: Dictionary = E.hot_clearance(39.0, f7["cmin"], f7["cmax"], a_fe, 100.0, a_al, 120.0)
	ctl(near(hot_f7["cmin_hot"], -17.9, 1e-6) and hot_f7["cmin_hot"] < 0.0 and hot_f7["seizes"], "b the textbook H7/f7 goes to %.2f um hot and is flagged as seizing" % hot_f7["cmin_hot"])
	var same: Dictionary = E.hot_clearance(39.0, 50.0, 100.0, a_al, 100.0, a_al, 100.0)
	ctl(near(same["delta"], 0.0, 1e-12), "b same alloy, same temperature: no closure (the model has no free closure)")


# ------------------------------------------------------------------------------------------------ c
func bars_stack() -> void:
	var ch: Array = E.endfloat_chain()
	var st: Dictionary = E.stack(ch)
	# gap = 58.30 - 17.0 - 24.0 - 17.0 = 0.30 mm; tol: IT10 50-80 120 -> 60; IT8 10-18 27 -> 13.5; IT8 18-30 33 -> 16.5; 13.5
	var worst := 60.0 + 13.5 + 16.5 + 13.5
	var rss := sqrt(60.0 * 60.0 + 13.5 * 13.5 + 16.5 * 16.5 + 13.5 * 13.5)
	ok(near(st["nominal"], 0.300, 1e-9) and near(st["tol_worst"], worst, 1e-9) and near(st["tol_rss"], rss, 1e-9), "c end-float: nominal 0.300 mm, worst +-%.1f um, RSS +-%.3f um" % [st["tol_worst"], st["tol_rss"]])
	ok(near(st["min_worst"], 0.300 - worst / 1000.0, 1e-9) and near(st["max_rss"], 0.300 + rss / 1000.0, 1e-9) and st["min_worst"] > 0.0, "c end-float worst min %.4f mm stays positive; RSS max %.4f" % [st["min_worst"], st["max_rss"]])
	var cs: Dictionary = E.stack_corners(ch)
	ok(near(cs["min"], st["min_worst"], 1e-9) and near(cs["max"], st["max_worst"], 1e-9) and cs["n"] == 16, "c end-float: all 16 corners give the worst case %.4f..%.4f mm" % [cs["min"], cs["max"]])
	var dk: Dictionary = E.stack(E.deck_chain())
	# gap = 111.2 - 20.7 - 80.0 - 10.0 = 0.500; IT10 80-120 140 -> 70; IT8 18-30 33 -> 16.5; IT7 50-80 30 -> 15; IT9 6-10 36 -> 18
	var dw := 70.0 + 16.5 + 15.0 + 18.0
	var dr := sqrt(70.0 * 70.0 + 16.5 * 16.5 + 15.0 * 15.0 + 18.0 * 18.0)
	ok(near(dk["nominal"], 0.500, 1e-9) and near(dk["tol_worst"], dw, 1e-9) and near(dk["tol_rss"], dr, 1e-9), "c deck clearance: nominal 0.500 mm, worst +-%.1f um, RSS +-%.3f um" % [dk["tol_worst"], dk["tol_rss"]])
	var dc: Dictionary = E.stack_corners(E.deck_chain())
	ok(near(dc["min"], dk["min_worst"], 1e-9) and dk["min_worst"] > 0.0, "c deck: corners agree, worst min %.4f mm (piston never touches the head cold)" % dc["min"])
	var signed := 0.0
	for l in ch:
		signed += float(l["sign"]) * float(l["tol"])
	ctl(not near(signed, worst, 1e-6), "c an algebraic (signed) tolerance sum %.1f is not the worst case %.1f" % [signed, worst])
	ctl(not near(rss, worst, 1.0), "c RSS %.1f is not the worst case %.1f" % [rss, worst])


# ------------------------------------------------------------------------------------------------ d
func bars_kin() -> void:
	var r := 20.7
	var L := 80.0
	ok(near(E.piston_x(0.0, r, L), 100.7, 1e-12) and near(E.piston_x(PI, r, L), 59.3, 1e-12), "d x(0) = r + L = 100.7, x(180) = L - r = 59.3")
	ok(near(E.piston_x(PI / 2.0, r, L), sqrt(80.0 * 80.0 - 20.7 * 20.7), 1e-12), "d x(90) = sqrt(L^2 - r^2) = %.4f" % sqrt(80.0 * 80.0 - 20.7 * 20.7))
	var worst := 0.0
	for deg in [47.0, 130.0, 250.0, 311.0, 15.0, 95.0]:
		var th := deg_to_rad(deg)
		var h := 1e-6
		var vw: float = -(E.piston_x(th + h, r, L) - E.piston_x(th - h, r, L)) / (2.0 * h)   # -dx/dth: torque per unit force
		var fac: float = E.torque_per_force(th, r, L)
		worst = maxf(worst, absf(vw - fac) / maxf(absf(fac), 1e-9))
	ok(worst < 1e-6, "d torque per unit force = -dx/dtheta by central difference at 6 angles (worst rel %s)" % String.num_scientific(worst))
	ok(near(E.torque_per_force(0.0, r, L), 0.0, 1e-12) and near(E.torque_per_force(PI, r, L), 0.0, 1e-12), "d zero torque at both dead centres")
	var th60 := deg_to_rad(60.0)
	var exact: float = E.torque_per_force(th60, r, L)
	var simple := r * sin(th60)
	var by_hand := r * sin(th60) * (1.0 + r * cos(th60) / sqrt(L * L - r * r * sin(th60) * sin(th60)))
	ok(near(exact, by_hand, 1e-12), "d exact factor at 60 deg by hand: %.5f mm" % by_hand)
	ctl(absf(simple - exact) / exact > 0.1, "d F r sin(th) with no rod obliquity is %.1f pct off at 60 deg" % (100.0 * absf(simple - exact) / exact))


# ------------------------------------------------------------------------------------------------ e
func bars_cycle() -> void:
	var pr: Dictionary = E.params(7000.0, 4.0, P.m_recip())
	var Vd: float = PI / 4.0 * 0.039 * 0.039 * 0.0414
	ok(near(pr["Vd"], Vd, 1e-12) and relnear(Vd * 1e6, 49.46, 0.002), "e swept volume %.3f cc (spec 49.5)" % (Vd * 1e6))
	var rc := 10.0
	var n := 1.3
	var Vc := Vd / (rc - 1.0)
	var W: float = pr["p1"] * Vc * (4.0 - 1.0) * (pow(rc, n) - rc) / (n - 1.0)
	var Wn: float = E.otto_work_numeric(pr)
	ok(relnear(Wn, W, 0.005), "e Otto cycle: integral of slider-crank torque %.3f J vs closed form %.3f J (rel %s)" % [Wn, W, String.num_scientific(absf(Wn - W) / W)])
	var cyc: Dictionary = E.run_cycle(pr)
	ok(relnear(cyc["imep_T"], cyc["imep_pdv"], 0.005), "e Wiebe curve: IMEP from torque %.4f bar vs from pdV %.4f bar" % [cyc["imep_T"] / 1e5, cyc["imep_pdv"] / 1e5])
	var m: float = pr["m_rec"]
	var w: float = 7000.0 * TAU / 60.0
	var lam: float = 20.7 / 80.0
	ok(relnear(abs(E.inertia_force(0.0, pr)), m * 0.0207 * w * w * (1.0 + lam), 1e-9), "e primary+secondary inertia at TDC = m r w^2 (1 + lambda) = %.1f N" % (m * 0.0207 * w * w * (1.0 + lam)))
	ok(abs(cyc["mean_T_inertia"]) < 1e-3 * cyc["peak_T_inertia"], "e inertia torque has zero mean over the cycle (mean %s, peak %.2f N m)" % [String.num_scientific(cyc["mean_T_inertia"]), cyc["peak_T_inertia"]])
	ok(near(cyc["P_brake"], cyc["T_brake"] * w, 1e-9), "e P = T w (%.1f W = %.3f N m x %.1f rad/s)" % [cyc["P_brake"], cyc["T_brake"], w])
	var T5: float = E.run_cycle(E.params(5000.0, 4.0, P.m_recip()))["T_brake"]
	print("e  numbers: peak p %.1f bar at %.0f deg, IMEP_net %.2f bar, FMEP %.2f bar, BMEP %.2f bar; 7000 rpm: T %.3f N m, P %.3f kW; 5000 rpm: T %.3f N m" % [cyc["pmax"] / 1e5, cyc["th_pmax"], cyc["imep_net"] / 1e5, cyc["fmep"] / 1e5, cyc["bmep"] / 1e5, cyc["T_brake"], cyc["P_brake"] / 1000.0, T5])
	ok(cyc["P_brake"] / 1000.0 >= 1.25 and cyc["P_brake"] / 1000.0 <= 3.75, "e brake power at 7000 rpm %.3f kW within 0.5x..1.5x of the Honda C50 2.5 kW" % (cyc["P_brake"] / 1000.0))
	ok(T5 >= 1.9 and T5 <= 5.7, "e brake torque at 5000 rpm %.3f N m within 0.5x..1.5x of the Honda C50 3.8 N m" % T5)
	var mot: Dictionary = E.run_cycle(E.params(7000.0, 1.0, P.m_recip()))
	ctl(mot["P_brake"] / 1000.0 < 1.25, "e a motored curve (tau = 1) gives %.3f kW and is rejected by the power band" % (mot["P_brake"] / 1000.0))


# ------------------------------------------------------------------------------------------------ f
func bars_print() -> void:
	var plan: Dictionary = E.print_plan(13.0, "G", "h", 6, 5)
	ok(plan["demonstrated"] == false and plan["grade"] == 9, "f G6/h5 is finer than the IT9 the study demonstrated: flagged, prototype goes to IT9")
	# G9: EI +6, ES +6+43 = +49 -> 13.006..13.049, mid 13.0275; h9: 0/-43 -> 13.000..12.957, mid 12.9785; hole baked for HHE 0: +0.26
	ok(near(plan["hole_cad"], 13.0275, 1e-9) and near(plan["shaft_cad"], 12.9785, 1e-9), "f CAD at mid-zone: hole %.4f, shaft %.4f (hand 13.0275 / 12.9785)" % [plan["hole_cad"], plan["shaft_cad"]])
	ok(near(plan["hole_slicer0"], 13.2875, 1e-9) and plan["hhe"] == 0.13, "f for a slicer with HHE 0 the hole is drawn %.4f (mid + 0.26)" % plan["hole_slicer0"])
	var lo := 13.006
	var hi := 13.049
	var comp: float = E.printed_hole(plan["hole_cad"], 0.13)
	var unc: float = E.printed_hole(plan["hole_cad"], 0.0)
	var bake: float = E.printed_hole(plan["hole_slicer0"], 0.0)
	ok(near(comp, 13.0275, 1e-9) and comp >= lo and comp <= hi, "f printed hole with HHE 0.13: %.4f, inside %.3f..%.3f" % [comp, lo, hi])
	ok(near(bake, 13.0275, 1e-9), "f printed hole from the baked-up CAD with HHE 0: %.4f" % bake)
	ctl(unc < lo, "f uncompensated printed hole %.4f is outside the hole limits (< %.3f)" % [unc, lo])
	ok(E.print_plan(13.0, "G", "h", 9, 9)["demonstrated"] == true, "f an IT9 pair is inside the demonstrated range")


# ------------------------------------------------------------------------------------------------ g
func vol_mm3(rec: Dictionary) -> float:
	return float(preload("res://scripts/build/assembly.gd").built(rec)["volume"]) * 1e9


func bars_parts() -> void:
	var AS := preload("res://scripts/build/assembly.gd")
	if not Part.available():
		ok(false, "g the KineCAD DLL is missing")
		return
	for nm in P.NAMES:
		var b: Dictionary = AS.built(P.record(nm))
		ok(b["mesh"] != null and int(b["bodies"]) == 1, "g part %s builds, %d body, %.0f mm3" % [nm, int(b["bodies"]), float(b["volume"]) * 1e9])
	var d: Dictionary = P.dims()
	var dp := 38.9375   # 39 e7 mid: (-50 + -75)/2 = -62.5 um
	var rh := 13.0 / 2.0   # boss JS6 mid 13.000
	ok(near(d["skirt_d"], dp, 1e-9) and near(d["boss_d"], 13.0, 1e-9) and near(d["pin_d"], 12.996, 1e-9) and near(d["bore_d"], 39.0125, 1e-9), "g dims from the fits: skirt 38.9375, boss 13.000, pin 12.996, bore 39.0125")
	# piston: cylinder dp x 44, pocket 34 x 22 from the bottom, pin hole (axis perpendicular to the piston axis, wholly inside the solid crown block): quadrature of the chord
	var R := dp / 2.0
	var n := 20000
	var hv := 0.0
	for i in n:
		var x := -rh + (i + 0.5) * (2.0 * rh) / n
		hv += 2.0 * sqrt(R * R - x * x) * 2.0 * sqrt(rh * rh - x * x) * (2.0 * rh) / n
	var vp := PI / 4.0 * dp * dp * 44.0 - PI / 4.0 * 34.0 * 34.0 * 22.0 - hv
	var vk := vol_mm3(P.record("piston"))
	ok(relnear(vk, vp, 0.001), "g piston volume %.1f mm3 vs closed form %.1f (hole %.1f by quadrature), rel %s" % [vk, vp, hv, String.num_scientific(absf(vk - vp) / vp)])
	var bad := vol_mm3(P.record("piston", {"boss_override": 13.5}))
	ctl(not relnear(bad, vp, 0.001), "g a piston with a 13.5 pin bore is caught by the volume bar (%.1f vs %.1f)" % [bad, vp])
	var vpin := vol_mm3(P.record("pin"))
	var vpin_h := PI / 4.0 * 12.996 * 12.996 * 33.0
	ok(relnear(vpin, vpin_h, 0.001), "g pin volume %.1f mm3 vs pi/4 x 12.996^2 x 33 = %.1f" % [vpin, vpin_h])
	var vcyl := vol_mm3(P.record("cylinder"))
	var vcyl_h := PI / 4.0 * ((56.0 * 56.0 - 39.0125 * 39.0125) * 71.2 + 5.0 * (70.0 * 70.0 - 56.0 * 56.0) * 2.0)
	ok(relnear(vcyl, vcyl_h, 0.001), "g cylinder (bore 39.0125, 5 fins) %.1f mm3 vs %.1f" % [vcyl, vcyl_h])
	var vhd := vol_mm3(P.record("head"))
	var vhd_h := PI / 4.0 * (70.0 * 70.0 * 30.0 - 39.0 * 39.0 * 4.6 - 14.0 * 14.0 * 25.4)
	ok(relnear(vhd, vhd_h, 0.001), "g head (chamber 39 x 4.6, plug 14) %.1f mm3 vs %.1f" % [vhd, vhd_h])
	var vcc := vol_mm3(P.record("crankcase"))
	var vcc_h := 90.0 * 90.0 * 78.3 - 80.0 * 80.0 * 58.3 - 2.0 * PI / 4.0 * 20.0105 * 20.0105 * 10.0 - PI / 4.0 * 44.0 * 44.0 * 5.0
	ok(relnear(vcc, vcc_h, 0.001), "g crankcase %.1f mm3 vs %.1f" % [vcc, vcc_h])
	var vrod := vol_mm3(P.record("rod", {"no_bores": true})) - vol_mm3(P.record("rod"))
	var vrod_h := PI / 4.0 * (13.0115 * 13.0115 + 18.009 * 18.009) * 20.0
	ok(relnear(vrod, vrod_h, 0.001), "g rod bores remove %.2f mm3 vs pi/4 (13.0115^2 + 18.009^2) x 20 = %.2f" % [vrod, vrod_h])
	var vrod_bad := vol_mm3(P.record("rod", {"no_bores": true})) - vol_mm3(P.record("rod", {"small_override": 13.5}))
	ctl(not relnear(vrod_bad, vrod_h, 0.001), "g a rod with a 13.5 small end bore is caught (%.2f vs %.2f)" % [vrod_bad, vrod_h])
	var bb: AABB = AS.built(P.record("crankshaft"))["aabb"]
	ok(near(bb.size.z * 1000.0, 98.0, 0.01), "g crankshaft is 98 mm long (journals -20..78), got %.3f" % (bb.size.z * 1000.0))
	var m_rec: float = P.m_recip()
	ok(m_rec > 0.05 and m_rec < 0.25, "g reciprocating mass from the CAD volumes %.1f g" % (m_rec * 1000.0))
	# every fit pair: the as-built mid clearance is the middle of the fit's band, and the pair never overlaps (mid clearance > 0 except the transition boss)
	var pairs := [["bush_d", "pin_d", "G6/h5"], ["bore_d", "skirt_d", "H7/e7"], ["bearing_d", "journal_d", "H7/f7"], ["bigend_d", "crankpin_d", "H7/f7"]]
	var allok := true
	for pr in pairs:
		var c: float = (float(d[pr[0]]) - float(d[pr[1]])) * 1000.0
		allok = allok and c > 0.0
	ok(allok, "g all four clearance pairs have positive as-built mid clearance (bush-pin %.1f, bore-skirt %.1f, bearing-journal %.1f, bigend-crankpin %.1f um)" % [(d["bush_d"] - d["pin_d"]) * 1000.0, (d["bore_d"] - d["skirt_d"]) * 1000.0, (d["bearing_d"] - d["journal_d"]) * 1000.0, (d["bigend_d"] - d["crankpin_d"]) * 1000.0])
	ok(near((d["boss_d"] - d["pin_d"]) * 1000.0, 4.0, 1e-6), "g the boss mid clearance is +4.0 um (transition fit, centre of -5.5..+13.5)")


# ------------------------------------------------------------------------------------------------ h
func bars_assembly() -> void:
	var r := 20.7
	var L := 80.0
	var worst_cp := 0.0
	var worst_rod := 0.0
	var worst_pin := 0.0
	var worst_len := 0.0
	var ymin := 1e9
	var ymax := -1e9
	for k in 49:
		var th := 15.0 * k   # 0 .. 720 deg, two revolutions
		var q: Dictionary = P.points(th)
		var t := deg_to_rad(th)
		worst_cp = maxf(worst_cp, ((q["crankpin"] as Vector3) - Vector3(r * sin(t), r * cos(t), q["crankpin"].z)).length())
		worst_rod = maxf(worst_rod, ((q["rod_big"] as Vector3) - (q["crankpin"] as Vector3)).length())
		worst_pin = maxf(worst_pin, ((q["rod_small"] as Vector3) - (q["pin"] as Vector3)).length())
		worst_len = maxf(worst_len, absf(((q["rod_small"] as Vector3) - (q["rod_big"] as Vector3)).length() - L))
		var xf: float = E.piston_x(t, r, L)
		worst_pin = maxf(worst_pin, absf(q["pin"].y - xf))
		ymin = minf(ymin, q["pin"].y)
		ymax = maxf(ymax, q["pin"].y)
	ok(worst_cp < TOL_MM, "h crank pin sits at r (sin th, cos th) over 2 revolutions (worst %s mm)" % String.num_scientific(worst_cp))
	ok(worst_rod < TOL_MM, "h rod big end on the crank pin, 49 poses (worst %s mm)" % String.num_scientific(worst_rod))
	ok(worst_pin < TOL_MM and worst_len < TOL_MM, "h rod small end on the piston pin, pin height = x(theta), rod length 80 (worst %s / %s mm)" % [String.num_scientific(worst_pin), String.num_scientific(worst_len)])
	ok(near(ymax - ymin, 41.4, TOL_MM), "h piston stroke over the sweep %.6f mm (spec 41.4)" % (ymax - ymin))
	var a: Dictionary = P.points(100.0)
	var b: Dictionary = P.points(460.0)
	ok(((a["pin"] as Vector3) - (b["pin"] as Vector3)).length() < TOL_MM and ((a["crankpin"] as Vector3) - (b["crankpin"] as Vector3)).length() < TOL_MM, "h the pose repeats after 360 deg")
	var bad: Dictionary = P.points(90.0, {"skip_rod_turn": true})
	ctl(((bad["rod_small"] as Vector3) - (bad["pin"] as Vector3)).length() > 1.0, "h a rod left unturned is %.2f mm off the pin at 90 deg" % ((bad["rod_small"] as Vector3) - (bad["pin"] as Vector3)).length())


# ------------------------------------------------------------------------------------------------ j
const OV_EPS := 1e-12   # m3 = 0.001 mm3: below this two solids share no volume (the kernel's own early-out, KineCAD::overlap_volume)
const MOVING := ["crankshaft", "rod", "piston", "pin"]
const FITS := {"pin|rod": "G6/h5", "piston|pin": "JS6/h5", "cylinder|piston": "H7/e7", "crankcase|crankshaft": "H7/f7", "crankshaft|rod": "H7/f7"}
var _kcalls := 0


func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func ov(a: int, b: int) -> float:
	_kcalls += 1
	return KCad.overlap_volume(a, b)


## the overlap (m3) of the gauge record placed at p with the solid `other`
func gauge_ov(g: Dictionary, p: Dictionary, other: int) -> float:
	var s0: int = P.solid(g)
	var s: int = P.place(s0, p)
	var v := ov(s, other) if s != 0 else -1.0
	KCad.release(s)
	KCad.release(s0)
	return v


## the piston crown to head gap (mm) at crank angle th: the smallest lift of the posed piston that makes it overlap the head, by bisection to 1e-4 mm; -1 when it overlaps unlifted, 99 when 10 mm is not enough
func crown_gap(piston: int, head: int) -> float:
	if ov(piston, head) > OV_EPS:
		return -1.0
	var lo := 0.0
	var hi := 10.0
	var up: int = KCad.translate(piston, Vector3(0, hi, 0) * Assembly.MM)
	var hit := ov(up, head) > OV_EPS
	KCad.release(up)
	if not hit:
		return 99.0
	while hi - lo > 1e-4:
		var mid := (lo + hi) / 2.0
		var t: int = KCad.translate(piston, Vector3(0, mid, 0) * Assembly.MM)
		if ov(t, head) > OV_EPS:
			hi = mid
		else:
			lo = mid
		KCad.release(t)
	return (lo + hi) / 2.0


func bars_interference() -> void:
	if not Part.available() or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		ok(false, "j KineCAD with overlap_volume is missing")
		return
	var t0 := Time.get_ticks_msec()
	var local := {}
	var recs := {}
	for nm in P.NAMES:
		recs[nm] = P.record(nm)
		local[nm] = P.solid(recs[nm])
	var built_all := true
	for nm in P.NAMES:
		built_all = built_all and int(local[nm]) != 0
	ok(built_all, "j every part gives one exact solid to pose")
	if not built_all:
		return
	var po0: Dictionary = P.pose_of(0.0)
	var placed_static := {}
	for nm in P.NAMES:
		if not MOVING.has(nm):
			placed_static[nm] = P.place(int(local[nm]), po0[nm])
	var worst := {}     # pair -> [overlap mm3, angle]
	var clashes := PackedStringArray()
	var skipped := 0
	for k in 36:
		var th := 10.0 * k
		var po: Dictionary = P.pose_of(th)
		var placed := placed_static.duplicate()
		for nm in MOVING:
			placed[nm] = P.place(int(local[nm]), po[nm])
		for i in P.NAMES.size():
			for j in range(i + 1, P.NAMES.size()):
				var a: String = P.NAMES[i]
				var b: String = P.NAMES[j]
				if k > 0 and not MOVING.has(a) and not MOVING.has(b):
					continue   # two fixed parts: once is enough
				var ka := pair_key(a, b)
				var wa: AABB = Assembly.world_aabb({"rec": recs[a], "pos": po[a]["pos"], "rot": po[a]["rot"]}).grow(1e-4)
				var wb: AABB = Assembly.world_aabb({"rec": recs[b], "pos": po[b]["pos"], "rot": po[b]["rot"]}).grow(1e-4)
				var v := 0.0
				if wa.intersects(wb):
					v = ov(int(placed[a]), int(placed[b]))
				else:
					skipped += 1
				if not worst.has(ka) or v > float(worst[ka][0]):
					worst[ka] = [v, th]
				if v > OV_EPS or v < 0.0:
					clashes.append("%s %.0f deg %.3f mm3" % [ka, th, v * 1e9])
		for nm in MOVING:
			KCad.release(int(placed[nm]))
	var bad_free := PackedStringArray()
	var bad_fit := PackedStringArray()
	for ka in worst:
		var v: float = worst[ka][0]
		if v > OV_EPS or v < 0.0:
			var line := "%s %.3f mm3 at %.0f deg" % [ka, v * 1e9, worst[ka][1]]
			if FITS.has(ka):
				bad_fit.append(line)
			else:
				bad_free.append(line)
	print("j  sweep: %d pairs, %d kernel overlaps, %d skipped by box, %.1f s; clashes: %s" % [worst.size(), _kcalls, skipped, (Time.get_ticks_msec() - t0) / 1000.0, ", ".join(clashes.slice(0, 12)) if clashes.size() > 0 else "none"])
	ok(bad_free.is_empty() and worst.size() == 21, "j no two parts that are not a fit pair share volume at any of 36 crank angles (%d pairs): %s" % [worst.size() - FITS.size(), "none" if bad_free.is_empty() else "; ".join(bad_free)])
	ok(bad_fit.is_empty(), "j the 5 fit pairs share no volume at any of the 36 angles: %s" % ("none" if bad_fit.is_empty() else "; ".join(bad_fit)))

	# each fit pair at its nominal size: shaft gauge grown to the fit's min clearance -> 0; a gauge 2 um over the hole -> overlap
	var d: Dictionary = P.dims()
	var po40: Dictionary = P.pose_of(40.0)
	var at40 := {}
	for nm in P.NAMES:
		at40[nm] = P.place(int(local[nm]), po40[nm])
	var fe: Dictionary = {"G6/h5": E.fit(13.0, "G6", "h5"), "JS6/h5": E.fit(13.0, "JS6", "h5"), "H7/e7": E.fit(39.0, "H7", "e7"), "H7/f7_20": E.fit(20.0, "H7", "f7"), "H7/f7_18": E.fit(18.0, "H7", "f7")}
	# [label, fit, shaft dia, hole dia, gauge maker (dia -> record), gauge part (its pose), hole part]
	var rows := [
		["pin in rod small end", "G6/h5", d["pin_d"], d["bush_d"], func(g: float) -> Dictionary: return P.gauge(0, 0, g / 2.0, 0.0, 33.0), "pin", "rod"],
		["pin in piston boss", "JS6/h5", d["pin_d"], d["boss_d"], func(g: float) -> Dictionary: return P.gauge(0, 0, g / 2.0, 0.0, 33.0), "pin", "piston"],
		["piston in bore", "H7/e7", d["skirt_d"], d["bore_d"], func(g: float) -> Dictionary: return P.gauge(0, 0, g / 2.0, 0.0, P.PISTON_H), "piston", "cylinder"],
		["crank journal (drive side) in bearing", "H7/f7_20", d["journal_d"], d["bearing_d"], func(g: float) -> Dictionary: return P.gauge(0, 0, g / 2.0, -20.0, 29.0), "crankshaft", "crankcase"],
		["crank journal (far side) in bearing", "H7/f7_20", d["journal_d"], d["bearing_d"], func(g: float) -> Dictionary: return P.gauge(0, 0, g / 2.0, 49.0, 29.0), "crankshaft", "crankcase"],
		["crank pin in big end", "H7/f7_18", d["crankpin_d"], d["bigend_d"], func(g: float) -> Dictionary: return P.gauge(0, P.R, g / 2.0, 17.0, 24.0), "crankshaft", "rod"],
	]
	var fit_ok := true
	var sees_ok := true
	var lines := PackedStringArray()
	for r in rows:
		var f: Dictionary = fe[r[1]]
		var cmin_mm := maxf(float(f["cmin"]), 0.0) / 1000.0
		var mk: Callable = r[4]
		var v_min := gauge_ov(mk.call(float(r[2]) + cmin_mm), po40[r[5]], int(at40[r[6]]))
		var v_over := gauge_ov(mk.call(float(r[3]) + 0.002), po40[r[5]], int(at40[r[6]]))
		var c_um := (float(r[3]) - float(r[2])) * 1000.0
		fit_ok = fit_ok and v_min >= 0.0 and v_min <= OV_EPS and c_um >= float(f["cmin"])
		sees_ok = sees_ok and v_over > OV_EPS
		lines.append("%s %s: as built %.1f um (fit %.1f..%.1f), gauge at min %.4f mm3, gauge hole+2um %.4f mm3" % [r[0], String(r[1]).get_slice("_", 0), c_um, f["cmin"], f["cmax"], v_min * 1e9, v_over * 1e9])
	for l in lines:
		print("j  " + l)
	ok(fit_ok, "j every fit pair carries at least its minimum clearance in the geometry (shaft gauge grown to the fit's min overlaps 0, 6 bearings)")
	ok(sees_ok, "j a gauge 2 um bigger than each hole overlaps it (the check sees a few um)")
	for nm in P.NAMES:
		KCad.release(int(at40[nm]))

	# crown to head at TDC against the deck clearance
	var deck: float = float(E.stack(E.deck_chain())["nominal"])
	var pis_tdc: int = P.place(int(local["piston"]), po0["piston"])
	var gap := crown_gap(pis_tdc, int(placed_static["head"]))
	KCad.release(pis_tdc)
	print("j  crown to head at TDC: %.4f mm measured on the solids; deck clearance (stack-up nominal) %.4f mm" % [gap, deck])
	ok(near(gap, deck, 0.005), "j crown to head gap at TDC %.4f mm = deck clearance %.4f mm (5 um)" % [gap, deck])

	# controls
	var pl: Dictionary = P.pose_of(0.0, {"rod_len": P.L + 2.0})
	var pis_long: int = P.place(int(local["piston"]), pl["piston"])
	var v_long := ov(pis_long, int(placed_static["head"]))
	KCad.release(pis_long)
	ctl(v_long > OV_EPS, "j a rod 2 mm longer drives the piston into the head at TDC (overlap %.3f mm3)" % (v_long * 1e9))
	var rod40: int = P.place(int(local["rod"]), po40["rod"])
	var v_pin := gauge_ov(P.gauge(0, 0, (float(d["pin_d"]) + 1.0) / 2.0, 0.0, 33.0), po40["pin"], rod40)
	KCad.release(rod40)
	ctl(v_pin > OV_EPS, "j a pin 1 mm oversize overlaps the rod's small end (%.2f mm3)" % (v_pin * 1e9))
	for nm in placed_static:
		KCad.release(int(placed_static[nm]))
	for nm in local:
		KCad.release(int(local[nm]))
	print("j  %d kernel overlaps in %.1f s" % [_kcalls, (Time.get_ticks_msec() - t0) / 1000.0])


# ------------------------------------------------------------------------------------------------ i
func grab() -> Image:
	for i in 4:
		await process_frame
	var im: Image = root.get_texture().get_image()
	var w := im.get_width()
	var h := im.get_height()
	var crop: Image = im.get_region(Rect2i(int(w * 0.3), int(h * 0.04), int(w * 0.4), int(h * 0.92)))
	crop.convert(Image.FORMAT_RGBA8)
	return crop


func diff(a: Image, b: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var c := a.get_pixel(x, y)
			var d := b.get_pixel(x, y)
			s += absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b)
			n += 3
	return s / maxf(n, 1)


func cap_px(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			for k in SectionLook.CAPS:
				if absf(c.r - k.r) < 0.03 and absf(c.g - k.g) < 0.03 and absf(c.b - k.b) < 0.03:
					n += 1
					break
	return n


func bars_sheet() -> void:
	if DisplayServer.get_name() == "headless":
		print("skip i (headless: no pixels)")
		return
	var sc: Dictionary = S.build(root)
	var imgs := {}
	var order := []
	for k in 13:
		var th := 60.0 * k
		S.pose(sc, th)
		imgs[th] = await grab()
		order.append(th)
		(imgs[th] as Image).save_png("%s/frame_%03d.png" % [OUT, int(th)])
	var movers := true
	var low := 1e9
	for i in range(1, order.size()):
		var dd := diff(imgs[order[i - 1]], imgs[order[i]])
		low = minf(low, dd)
		movers = movers and dd > 0.002
	ok(movers, "i each of 12 frames differs from the one before (smallest mean diff %.4f)" % low)
	var p360 := diff(imgs[0.0], imgs[360.0])
	var p720 := diff(imgs[60.0], imgs[420.0])
	ok(p360 < 1e-4 and p720 < 1e-4, "i frame(theta) == frame(theta + 360): diffs %s, %s" % [String.num_scientific(p360), String.num_scientific(p720)])
	var half := diff(imgs[0.0], imgs[180.0])
	ctl(half > 0.002, "i frame(0) vs frame(180) differ (%.4f), so the periodicity bar can fail" % half)
	var sheet := Image.create(6 * 256, 2 * 460, false, Image.FORMAT_RGBA8)
	for i in 12:
		var im: Image = (imgs[order[i]] as Image).duplicate()
		im.resize(256, 460, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, 256, 460), Vector2i((i % 6) * 256, (i / 6) * 460))
	sheet.save_png(OUT + "/sheet_animation.png")
	S.pose(sc, 40.0)
	var whole: Image = await grab()
	S.set_cut(sc, true)
	var cut: Image = await grab()
	cut.save_png(OUT + "/section.png")
	whole.save_png(OUT + "/whole.png")
	var cp := cap_px(cut)
	var wp := cap_px(whole)
	ok(cp >= 800, "i section view shows %d cap-colour pixels (sampled every 2nd)" % cp)
	ctl(wp == 0, "i the uncut view has %d cap-colour pixels (the count can be zero, so it measures the cut)" % wp)
	print("sheet: %s/sheet_animation.png  section: %s/section.png" % [OUT, OUT])
