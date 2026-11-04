extends SceneTree
## godot --headless --path . -s tests/ch14_test.gd   (CH14: a water-syringe arm that builds a 3-2-1 pyramid of six cola cans; docs/CH14_REFERENCE.md)
## Bars (written and committed before any number was read; each has a PLANTED control that must fail):
##  1 REACH    inverse kinematics reaches the pickup and the six placements (and a 25 mm hover over each) inside the joint limits, and FK(IK(p)) closes to 1e-9.
##             PLANTED: a boom of L1 = L2 = 110 mm fails.
##  2 BASE     the base turns the full 180 deg from ONE monotone stroke chain with no dead point: rack and pinion (pitch radius 20 mm) on a 20 mL slave: sweep >= 180 deg,
##             rack travel pi r <= the syringe stroke. PLANTED: a lever-crank swept -90..+90 (non-monotone, arm 0 at the dead point) fails.
##  3 COUNT    syringes <= 10. PLANTED: a design with a sixth axis (12 syringes) fails.
##  4 TORQUE   margin >= 1.5 at every joint with an EMPTY can (15 g), thumb force 30 N, at the worst of the 7 poses (+ hovers): capacity (F_hand - seal friction) x A_slave/A_master
##             against torque / moment arm + seal friction. PLANTED: a 5 mL slave on the shoulder fails.
##  5 GRIP     friction force 2 mu N of the gripper (N from its syringe pair x 0.85 rack-pinion) >= 1.5 x can weight (empty and full). PLANTED: a slick pad (mu 0.02) fails.
##  6 PLACE    placement error at the can centre = water + hose (Lame) + barrel compliance and seal-friction band at the slave, divided by the moment arm, times the distance from the
##             joint to the can, plus pin slop plus boom deflection; 2 x in-plane error <= the stack tolerance tau_x and 2 x sideways error <= tau_y (own error + half of each
##             support's error). Reported with and without a 0.5 mL air bubble per circuit (the with-air number is REPORTED, not barred; the air that the budget survives is solved).
##             PLANTED: soft PVC hose (E 10 MPa) fails.
##  7 STACK    the nominal pyramid and the worst sign combination of the bar-6 errors keep every upper can's centre of mass over its support polygon AND touching both supports.
##             PLANTED: an upper can 70 mm off its gap fails.
##  8 STRETCH  full can (385 g), thumb 50 N: torque margin >= 1.5 at every joint, boom tip deflection <= 3 mm, bending stress <= strength / 2; per material (cardboard, pine,
##             plywood, PLA+); the bar passes if at least one material meets all three, the passing ones are named. PLANTED: a 25 mm boom of foam-soft E = 20 MPa fails.
##  9 HAND     Pascal ratio, beam formula (closed form and Simpson unit-load), rack travel, Lame, bubble, stack tolerances, jaw force each equal the hand-arithmetic value to 1e-9.
##             PLANTED: the diameter ratio used as the force ratio fails the check.
var fails := 0
const A := preload("res://scripts/build/ch14_arm.gd")


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func _init() -> void:
	var d := A.design()
	# ------------------------------------------------ 1
	var rc := A.reach_check(d)
	ok(rc["ok"], "1 reach: pickup + 6 placements + hovers inside the limits %s" % str(rc["bad"]))
	var worst_close := 0.0
	for p in A.poses(d):
		var q := A.ik(d, p["r"], p["z"])
		var f := A.fk(d, q["th1"], q["th2"])
		worst_close = maxf(worst_close, (f["c"] as Vector2).distance_to(Vector2(p["r"], p["z"])))
		print("     pose %-10s r %6.1f z %6.1f -> shoulder %6.2f elbow %7.2f wrist %6.2f deg" % [p["name"], p["r"], p["z"], q["th1"], q["th2"], q["psi"]])
	ok(worst_close < 1e-9, "1 FK(IK) closes: worst %.2e mm" % worst_close)
	var short := A.design()
	short["L1"] = 110.0
	short["L2"] = 110.0
	var rs := A.reach_check(short)
	ok(not rs["ok"], "1 PLANTED short boom 110+110 fails: %d poses out" % (rs["bad"] as Array).size())
	# ------------------------------------------------ 2
	var br := A.base_chain("rack", d["cyl"]["ba"][1], d["rp_pinion"])
	ok(br["ok"], "2 base rack and pinion: sweep %.1f deg from a %.1f mm stroke of %.1f mm available (%.0f pct), monotone, arm %.1f mm" % [br["sweep"], br["need"], br["avail"], 100.0 * br["need"] / br["avail"], br["min_arm"]])
	ok(br["sweep"] >= 180.0, "2 base sweeps >= 180 deg")
	var bc := A.base_chain("crank", 20)
	ok(not bc["ok"], "2 PLANTED lever-crank -90..+90 fails: monotone %s, min arm %.3f mm" % [bc["monotone"], bc["min_arm"]])
	# ------------------------------------------------ 3
	var n := A.count_syringes(d)
	ok(n <= 10, "3 syringe count %d <= 10" % n)
	var six := A.design()
	six["cyl"]["x6"] = [5, 5]
	ok(A.count_syringes(six) > 10, "3 PLANTED six axes = %d syringes fails" % A.count_syringes(six))
	# ------------------------------------------------ 4
	var wm := A.worst_margins(d, "pla", A.CAN_M0, A.F_HAND)
	var minm := 1e9
	for j in wm:
		minm = minf(minm, wm[j]["margin"])
		print("     axis %s worst at %-12s: capacity %.1f N, load %.2f N, need %.2f N, margin %.2f" % [j, wm[j]["pose"], wm[j]["cap"], wm[j]["load"], wm[j]["need"], wm[j]["margin"]])
	ok(minm >= 1.5, "4 empty-can torque margin >= 1.5 at every joint (min %.2f)" % minm)
	var under := A.design()
	under["cyl"]["sh"] = [20, 5]
	var wu := A.worst_margins(under, "pla", A.CAN_M0, A.F_HAND)
	ok(float(wu["sh"]["margin"]) < 1.5, "4 PLANTED 5 mL slave on the shoulder fails (margin %.2f)" % wu["sh"]["margin"])
	# ------------------------------------------------ 5
	var g0 := A.grip(d, A.CAN_M0, 1.5, A.F_HAND)
	var g1 := A.grip(d, A.CAN_M1, 1.5, A.F_HAND)
	ok(g0["ratio"] >= 1.5, "5 grip empty: friction %.2f N vs weight %.3f N (ratio %.1f)" % [g0["friction"], g0["weight"], g0["ratio"]])
	ok(g1["ratio"] >= 1.5, "5 grip full: friction %.2f N vs weight %.3f N (ratio %.1f); jaw N %.2f have, %.2f needed" % [g1["friction"], g1["weight"], g1["ratio"], g1["have"], g1["need"]])
	var slick := A.design()
	slick["mu_jaw"] = 0.02
	ok(A.grip(slick, A.CAN_M1, 1.5, A.F_HAND)["ratio"] < 1.5, "5 PLANTED slick pad mu 0.02 fails")
	# ------------------------------------------------ 6
	var tol := A.stack_tolerance(d["pitch"])
	var e0 := A.placement_error(d, 0.0)
	var e1 := A.placement_error(d, 0.5)
	print("     tolerance tau_x %.2f mm tau_y %.2f mm; error without air: in-plane %.2f (sh %.2f el %.2f wr %.2f boom %.2f) at %s, sideways %.2f" % [tol["x"], tol["y"], e0["in"], e0["parts"]["sh"], e0["parts"]["el"], e0["parts"]["wr"], e0["parts"]["boom"], e0["pose"], e0["y"]])
	print("     with 0.5 mL air per circuit: in-plane %.2f (sh %.2f el %.2f wr %.2f) sideways %.2f" % [e1["in"], e1["parts"]["sh"], e1["parts"]["el"], e1["parts"]["wr"], e1["y"]])
	for j in e0["bands"]:
		print("     axis %s lost slave stroke: %.4f mm without air, %.4f mm with 0.5 mL air; master travel to build the load pressure %.3f mm" % [j, e0["bands"][j]["mm"], e1["bands"][j]["mm"], e0["bands"][j]["master_mm"]])
	ok(2.0 * e0["in"] <= tol["x"], "6 in-plane: 2 x %.2f = %.2f <= tau_x %.2f (no air)" % [e0["in"], 2.0 * e0["in"], tol["x"]])
	ok(2.0 * e0["y"] <= tol["y"], "6 sideways: 2 x %.2f = %.2f <= tau_y %.2f (no air)" % [e0["y"], 2.0 * e0["y"], tol["y"]])
	ok(e1["in"] > e0["in"], "6 air makes it worse: %.2f > %.2f" % [e1["in"], e0["in"]])
	var air_ok := A.air_tolerance(d, tol["x"] / 2.0)
	print("     REPORT: with 0.5 mL air per circuit, 2 x in-plane = %.2f mm vs tau_x %.2f -> %s; the budget survives at most %.4f mL per circuit" % [2.0 * e1["in"], tol["x"], "within" if 2.0 * e1["in"] <= tol["x"] else "OUTSIDE", air_ok])
	var soft := A.design()
	soft["hose"] = "pvc"
	var es := A.placement_error(soft, 0.0)
	ok(2.0 * es["in"] > tol["x"], "6 PLANTED soft PVC hose fails: 2 x %.2f = %.2f > %.2f" % [es["in"], 2.0 * es["in"], tol["x"]])
	# ------------------------------------------------ 7
	var s: float = d["pitch"]
	var rp: float = d["rp"]
	var nom := [Vector2(rp + s, 0), Vector2(rp, 0), Vector2(rp - s, 0), Vector2(rp + s / 2, 0), Vector2(rp - s / 2, 0), Vector2(rp, 0)]
	var chk := A.pyramid_check(nom)
	var allok := true
	for c in chk:
		allok = allok and c["c"]["margin"] > 0.0 and c["c"]["both"]
		print("     nominal %-9s margin %.2f mm both lids %s" % [c["name"], c["c"]["margin"], c["c"]["both"]])
	ok(allok, "7 nominal pyramid: every upper can's centre over its support polygon and on both supports")
	var worstm := 1e9
	var allboth := true
	for mask in 64:
		for ys in [-1.0, 1.0]:
			var pos := []
			for k in 6:
				var sg := 1.0 if (mask >> k) & 1 else -1.0
				pos.append(Vector2((nom[k] as Vector2).x + sg * e0["in"], ys * e0["y"] * (1.0 if k % 2 == 0 else -1.0)))
			for c in A.pyramid_check(pos):
				worstm = minf(worstm, c["c"]["margin"])
				allboth = allboth and c["c"]["both"]
	ok(worstm > 0.0 and allboth, "7 worst error combination (128 of them): minimum margin %.2f mm, both lids touched %s" % [worstm, allboth])
	var off := nom.duplicate()
	off[5] = Vector2(rp, 70.0)
	var cp := A.pyramid_check(off)
	ok(not (cp[2]["c"]["margin"] > 0.0 and cp[2]["c"]["both"]), "7 PLANTED top can 70 mm off its gap fails (margin %.2f)" % cp[2]["c"]["margin"])
	# ------------------------------------------------ 8
	var passing := []
	for mat in ["cardboard", "pine", "plywood", "pla"]:
		var dd := A.design()
		dd["mat"] = mat
		var w8 := A.worst_margins(dd, mat, A.CAN_M1, A.F_HAND_MAX)
		var mm := 1e9
		for j in w8:
			mm = minf(mm, w8[j]["margin"])
		var bm := A.boom(dd, mat, A.CAN_M1)
		var good: bool = mm >= 1.5 and bm["tip"] <= 3.0 and bm["sigma"] <= A.MAT[mat]["sigma"] / 2.0
		print("     %-9s min margin %.2f (sh %.2f el %.2f wr %.2f ba %.2f), boom tip %.2f mm, stress %.2f MPa of %.0f, boom mass %.0f g -> %s" % [mat, mm, w8["sh"]["margin"], w8["el"]["margin"], w8["wr"]["margin"], w8["ba"]["margin"], bm["tip"], bm["sigma"], A.MAT[mat]["sigma"], 1000.0 * bm["mass"], "MEETS" if good else "fails"])
		if good:
			passing.append(mat)
	ok(not passing.is_empty(), "8 full-can stretch: at least one material meets it: %s" % str(passing))
	A.MAT["foam"] = {"E": 20.0, "rho": 100.0, "sigma": 0.5, "wall": 0.0}
	var df := A.design()
	df["mat"] = "foam"
	var bf := A.boom(df, "foam", A.CAN_M1)
	ok(not (bf["tip"] <= 3.0), "8 PLANTED foam boom fails (tip %.1f mm)" % bf["tip"])
	# ------------------------------------------------ 9
	var hand_ratio := 1.7405797859690846     # (19.13 / 14.5)^2
	ok(rel(A.area(20) / A.area(10), hand_ratio) < 1e-9, "9 Pascal area ratio 20 mL / 10 mL = %.12f vs hand %.12f" % [A.area(20) / A.area(10), hand_ratio])
	ok(rel(A.pascal_slave_force(30.0, 10, 20), 52.217393579072535) < 1e-9, "9 30 N on a 10 mL gives %.9f N on a 20 mL (hand 52.217393579)" % A.pascal_slave_force(30.0, 10, 20))
	ok(rel(A.area(10), 165.1299638543135) < 1e-9, "9 10 mL bore area 165.13 mm2")
	var p_hand := 30.0 / 165.1299638543135
	ok(rel(A.pascal_slave_force(30.0, 10, 20), p_hand * A.area(20)) < 1e-9, "9 pressure route p A equals the ratio route")
	var wrong := A.pascal_slave_force(30.0, 10, 10) * (19.13 / 14.5)
	ok(rel(wrong, 52.217393579072535) > 1e-3, "9 PLANTED diameter ratio as force ratio is %.3f N, %.1f pct off" % [wrong, 100.0 * rel(wrong, 52.217393579072535)])
	var sec := A.section("pla")
	ok(rel(sec["I"], 13730.995199999998) < 1e-9, "9 PLA+ boom I = 13730.9952 mm4")
	ok(rel(A.cantilever(250.0, 2300.0 * 13730.995199999998, 2.0, 0.0, 0.0), 0.3298366535913127) < 1e-9, "9 cantilever F L3 / 3EI = 0.3298366536 mm")
	var cf := A.cantilever(250.0, 3.1e7, 1.7, 0.0004, 120.0)
	var ce := A.cantilever_energy(250.0, 3.1e7, 1.7, 0.0004, 120.0)
	ok(rel(cf, ce) < 1e-9, "9 closed form %.12f equals the Simpson unit-load integral %.12f" % [cf, ce])
	ok(rel(PI * A.R_PINION, 62.83185307179586) < 1e-9, "9 rack travel for 180 deg = pi r = 62.831853 mm")
	ok(rel(A.hose_k(50.0), 0.122) < 1e-9, "9 Lame: 2 (13/5 + 0.45)/50 = 0.122 per MPa")
	var dva := A.circuit_dv(d, "sh", 0.2, 0.5)["air"]
	ok(rel(dva, 0.33186758483365136) < 1e-9, "9 bubble 0.5 mL at 0.2 MPa loses %.9f mL" % dva)
	ok(rel((A.P0 + 0.2) * (0.5 - dva), A.P0 * 0.5) < 1e-9, "9 isothermal identity (p0 + p)(V - dV) = p0 V")
	ok(rel(tol["x"], 16.9) < 1e-9 and rel(tol["y"], 37.92347557911853) < 1e-9, "9 stack tolerances 16.9 mm and 37.923476 mm")
	ok(rel(A.grip(d, A.CAN_M1, 1.5, A.F_HAND)["need"], 7.079175468749999) < 1e-9, "9 jaw N needed for the full can = 7.0791755 N")
	print("ch14: %d fail" % fails)
	quit(1 if fails > 0 else 0)
