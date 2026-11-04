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
## Bars 10-13 (added when the lane was resumed, committed before their first run):
## 10 PARTS    all 14 part records build (>= 1 body, volume > 0); the printed pin hole is drawn at 4 + 0.15 + 0.30 = 4.45 mm and its worst print (- 0.30 undersize - 0.10 scatter)
##             still clears the 4 mm dowel; the six printed parts write as binary STL (84 + 50 n bytes, n > 0) whose box equals the part's box to 0.01 mm. PLANTED: a hole drawn
##             at the nominal 4.0 prints at 3.60 worst and does not clear.
## 11 BUILD    the whole build sequence sampled every 0.05 s: no sample without an IK solution inside the limits, arm + gripper never touch a placed can (clearance > 0),
##             the carried can never touches a placed can in transit (> 0), the base stays inside -90..+90, all six cans end up placed, and every master plunger stays
##             inside its own stroke (the thumb can actually push it there). PLANTED: arriving 40 mm BELOW the target height after the turn drives the carried can into the stack.
## 12 SHEET    (skipped headless) 12 frames over the job: each differs from the one before; the last shows more can red than the first; the syringe-pair section shows water
##             blue. PLANTED: the red counter on an empty background is 0.
## 13 COST     the BOM lines add up to its total (hand sum); the cheapest design over boom material x tube x syringe sizes that passes bars 2b, 4, 5 and 6 is found and costs no
##             more than the current one. PLANTED: the current design with soft PVC tube (the cheapest tube) fails the working bars.
var fails := 0
const A := preload("res://scripts/build/ch14_arm.gd")
const N := preload("res://scripts/build/ch14_anim.gd")
const PT := preload("res://scripts/build/ch14_parts.gd")
const SC := preload("res://scripts/build/ch14_scene.gd")
const BOM := preload("res://scripts/build/ch14_bom.gd")
const ME := preload("res://scripts/build/mesh_export.gd")
const OUT := "C:/Temp/claude/ch14"


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
		var f := A.fk_c(d, q["th1"], q["th2"])
		worst_close = maxf(worst_close, sqrt(pow(f[0] - float(p["r"]), 2) + pow(f[1] - float(p["z"]), 2)))
		print("     pose %-10s r %6.1f z %6.1f -> shoulder %6.2f elbow %7.2f wrist %6.2f deg" % [p["name"], p["r"], p["z"], q["th1"], q["th2"], q["psi"]])
	ok(worst_close < 1e-9, "1 FK(IK) closes: worst %s mm" % str(worst_close))
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
	# 2b (added after the first run, a check the first design should have had): every lever joint's stroke chain fits its slave syringe (<= 95 pct), is monotone and keeps an arm >= 20 mm
	for j in ["sh", "el", "wr"]:
		var ch := A.chain(d, j)
		ok(ch["monotone"] and ch["use"] <= 0.95 and ch["min_arm"] >= 20.0, "2b lever %s: stroke %.1f of %.1f mm (%.0f pct), monotone %s, smallest arm %.1f mm over %.0f deg" % [j, ch["stroke"], ch["avail"], 100.0 * ch["use"], ch["monotone"], ch["min_arm"], ch["sweep"]])
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
	ok(rel(sec["I"], 24510.94186666666) < 1e-9, "9 PLA+ boom I = 24510.941867 mm4")
	ok(rel(A.cantilever(250.0, 2300.0 * 13730.995199999998, 2.0, 0.0, 0.0), 0.3298366535913127) < 1e-9, "9 cantilever F L3 / 3EI = 0.3298366536 mm")
	var cf := A.cantilever(250.0, 3.1e7, 1.7, 0.0004, 120.0)
	var ce := A.cantilever_energy(250.0, 3.1e7, 1.7, 0.0004, 120.0)
	ok(rel(cf, ce) < 1e-9, "9 closed form %.12f equals the Simpson unit-load integral %.12f" % [cf, ce])
	ok(rel(PI * A.R_PINION, 62.83185307179586) < 1e-9, "9 rack travel for 180 deg = pi r = 62.831853 mm")
	ok(rel(A.hose_k(50.0), 0.122) < 1e-9, "9 Lame: 2 (13/5 + 0.45)/50 = 0.122 per MPa")
	var dva: float = A.circuit_dv(d, "sh", 0.2, 0.5)["air"]
	ok(rel(dva, 0.33186758483365136) < 1e-9, "9 bubble 0.5 mL at 0.2 MPa loses %.9f mL" % dva)
	ok(rel((A.P0 + 0.2) * (0.5 - dva), A.P0 * 0.5) < 1e-9, "9 isothermal identity (p0 + p)(V - dV) = p0 V")
	ok(rel(tol["x"], 16.9) < 1e-9 and rel(tol["y"], 37.92347557911853) < 1e-9, "9 stack tolerances 16.9 mm and 37.923476 mm")
	ok(rel(A.grip(d, A.CAN_M1, 1.5, A.F_HAND)["need"], 7.079175468749999) < 1e-9, "9 jaw N needed for the full can = 7.0791755 N")
	DirAccess.make_dir_recursive_absolute(OUT + "/stl")
	var vols := bars_parts()
	bars_build(d)
	await bars_sheet()
	bars_cost(d, vols)
	print("ch14: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ------------------------------------------------ 10
const PRINTED := ["turntable", "pinion", "rack", "gripper_body", "jaw", "jaw"]


func records() -> Dictionary:
	return {"syringe_barrel_20": PT.syringe_barrel(20), "syringe_plunger_20": PT.syringe_plunger(20, 80.0), "baseboard": PT.baseboard(), "console": PT.console(),
		"turntable": PT.turntable(), "pinion": PT.pinion(), "rack": PT.rack(), "upper_arm": PT.upper_arm(), "forearm": PT.forearm(), "gripper_body": PT.gripper_body(),
		"jaw": PT.jaw(), "can": PT.can_rec(), "stand": PT.stand(), "pair_section": PT.pair_section()}


## the part's triangles in mm, Z up (STL convention; Kine is Y up), every surface
func stl_body(rec: Dictionary) -> Dictionary:
	var m: ArrayMesh = Assembly.built(rec)["mesh"]
	var v := PackedVector3Array()
	var t := PackedInt32Array()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var base := v.size()
		for p in sv:
			v.append(Vector3(p.x, -p.z, p.y) * 1000.0)
		var si = arr[Mesh.ARRAY_INDEX]
		if si == null or (si as PackedInt32Array).is_empty():
			for i in sv.size():
				t.append(base + i)
		else:
			for i in (si as PackedInt32Array):
				t.append(base + i)
	return {"v": v, "t": t}


func bars_parts() -> Dictionary:
	var recs := records()
	var built_ok := true
	var bad := []
	for k in recs:
		var b := Assembly.built(recs[k])
		if int(b["bodies"]) < 1 or float(b["volume"]) <= 0.0:
			built_ok = false
			bad.append(k)
	ok(built_ok and recs.size() == 14, "10 all %d part records build: %s" % [recs.size(), "ok" if bad.is_empty() else str(bad)])
	var hd := A.hole_design(PT.PIN_D)
	var worst := hd - A.FDM_UNDERSIZE - 0.10
	ok(rel(hd, 4.45) < 1e-9 and worst > PT.PIN_D, "10 pin hole drawn %.2f mm, worst print %.2f mm > the 4 mm dowel" % [hd, worst])
	var nom_worst := PT.PIN_D - A.FDM_UNDERSIZE - 0.10
	ok(nom_worst < PT.PIN_D, "10 PLANTED a hole drawn at the nominal 4.00 prints %.2f worst: no clearance (caught)" % nom_worst)
	var stl_ok := true
	var vols := {}
	var seen := {}
	for nm in PRINTED:
		var rec: Dictionary = recs[nm]
		var key: String = nm if not seen.has(nm) else nm + "_2"
		seen[nm] = true
		vols[key] = float(Assembly.built(rec)["volume"]) * 1e9
		var body := stl_body(rec)
		var path := "%s/stl/ch14_%s.stl" % [OUT, key]
		ME.write_stl(path, [body])
		var n := (body["t"] as PackedInt32Array).size() / 3
		var sz := FileAccess.get_file_as_bytes(path).size()
		var bb := AABB((body["v"] as PackedVector3Array)[0], Vector3.ZERO)
		for p in (body["v"] as PackedVector3Array):
			bb = bb.expand(p)
		var pb: AABB = Assembly.built(rec)["aabb"]
		var want := Vector3(pb.size.x, pb.size.z, pb.size.y) * 1000.0
		var good := n > 0 and sz == 84 + 50 * n and (bb.size - want).length() < 0.01
		stl_ok = stl_ok and good
		print("     STL %-14s %6d triangles %8d bytes box %s mm" % [key, n, sz, bb.size])
	ok(stl_ok, "10 six printed parts written as binary STL, sizes and boxes match (%s/stl)" % OUT)
	return vols


# ------------------------------------------------ 11
func bars_build(d: Dictionary) -> void:
	var wp := N.waypoints(d)
	var sw := N.sweep(d, wp, 0.05)
	print("     build: %.1f s, %d waypoints, arm clearance min %.2f mm (%s), carried can min %.2f mm (%s), yaw %.1f..%.1f" % [sw["t_end"], wp.size(), sw["min"], sw["at"], sw["held_min"], sw["held_at"], sw["yaw"][0], sw["yaw"][1]])
	ok(int(sw["lost_ik"]) == 0, "11 every sample has an IK solution inside the joint limits (%d lost)" % sw["lost_ik"])
	ok(float(sw["min"]) > 0.0, "11 arm and gripper never touch a placed can (min %.2f mm)" % sw["min"])
	ok(float(sw["held_min"]) > 0.0, "11 the carried can never touches a placed can in transit (min %.2f mm)" % sw["held_min"])
	ok(float(sw["yaw"][0]) >= -90.0 - 1e-9 and float(sw["yaw"][1]) <= 90.0 + 1e-9, "11 base yaw stays inside -90..+90")
	ok(N.placed_at(d, wp, float(sw["t_end"]) + 1.0).size() == 6, "11 all six cans are placed at the end")
	var t := 0.0
	var worst_out := 0.0
	var worst_axis := ""
	while t <= float(sw["t_end"]):
		var st := N.state(d, wp, t)
		if st.has("th1"):
			var sk := N.strokes(d, st)
			for j in sk["master_out"]:
				var full := A.stroke(int(d["cyl"][j][0]))
				var m: float = sk["master_out"][j]
				var over := maxf(-m, m - full)
				if over > worst_out:
					worst_out = over
					worst_axis = "%s %.2f of %.1f mm at t %.1f" % [j, m, full, t]
		t += 0.05
	ok(worst_out <= 0.01, "11 every master plunger stays inside its stroke (worst overrun %.3f mm %s)" % [worst_out, worst_axis])
	# 11b (added with the slave syringes in the animation, committed before its run): the DRAWN horn pin and pivot (the parts and the scene) give the lever maths'
	# length at every joint angle, so what the animation shows is the mechanism the torque and stroke bars computed. PLANTED: the horn drawn 10 deg off fails.
	var worst_geo := 0.0
	var worst_off := 0.0
	for j in ["sh", "el", "wr"]:
		var lim: Array = d["lim"][j]
		var lv: Array = d["lever"][j]
		for i in 41:
			var th: float = lerpf(lim[0], lim[1], i / 40.0)
			var sl := A.slave_line(d, j, th)
			var want := A.lc_len(lv[0], lv[1], A.phi_of(d, j, th))
			worst_geo = maxf(worst_geo, absf(((sl["Q"] as Vector2) - (sl["P"] as Vector2)).length() - want))
			var off := A.slave_line(d, j, th + 10.0)
			worst_off = maxf(worst_off, absf(((off["Q"] as Vector2) - (off["P"] as Vector2)).length() - want))
	ok(worst_geo < 1e-9, "11b drawn horn + pivot = lever length at every angle of sh, el, wr (worst %s mm)" % str(worst_geo))
	ok(worst_off > 1.0, "11b PLANTED a horn drawn 10 deg off is %.2f mm out (caught)" % worst_off)
	var low := N.sweep(d, N.waypoints(d, N.CLEAR, -40.0), 0.05)
	ok(float(low["held_min"]) < 0.0, "11 PLANTED arriving 40 mm below the target height drives the carried can into the stack (%.2f mm at %s)" % [low["held_min"], low["held_at"]])


# ------------------------------------------------ 12
func grab() -> Image:
	for i in 4:
		await process_frame
	var im: Image = root.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func diff(a: Image, b: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var c := a.get_pixel(x, y)
			var e := b.get_pixel(x, y)
			s += absf(c.r - e.r) + absf(c.g - e.g) + absf(c.b - e.b)
			n += 3
	return s / maxf(n, 1)


func count_px(img: Image, want: Color, tol: float) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > want.r - tol and absf(c.g - want.g) < tol and absf(c.b - want.b) < tol and (want.r < 0.5 or c.r > c.g + 0.25):
				n += 1
	return n


func red_px(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.45 and c.g < 0.25 and c.b < 0.25:
				n += 1
	return n


func blue_px(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.b > 0.55 and c.r < 0.4 and c.b > c.g + 0.15:
				n += 1
	return n


func bars_sheet() -> void:
	if DisplayServer.get_name() == "headless":
		print("skip 12 (headless: no pixels)")
		return
	var blank: Image = await grab()
	var sc: Dictionary = SC.build(root)
	var te := SC.t_end(sc)
	var frames := []
	var labels := []
	for k in 12:
		var t := te * float(k) / 11.0
		var st := SC.pose(sc, t)
		var im: Image = await grab()
		frames.append(im)
		labels.append("%.0f s %s" % [t, st["label"]])
		im.save_png("%s/frame_%02d.png" % [OUT, k])
	var moves := true
	var low := 1e9
	for k in range(1, 12):
		var dd := diff(frames[k - 1], frames[k])
		low = minf(low, dd)
		moves = moves and dd > 0.001
	ok(moves, "12 each of 12 frames differs from the one before (smallest mean diff %.4f)" % low)
	var r0 := red_px(frames[0])
	var r1 := red_px(frames[11])
	ok(r1 > 3 * r0 and r0 > 0, "12 can red: first frame %d px, last %d px (six cans stacked)" % [r0, r1])
	ok(red_px(blank) == 0, "12 PLANTED the red counter on an empty background gives %d" % red_px(blank))
	var w: int = (frames[0] as Image).get_width() / 4
	var h: int = (frames[0] as Image).get_height() / 4
	var sheet := Image.create(4 * w, 3 * h, false, Image.FORMAT_RGBA8)
	for k in 12:
		var im: Image = (frames[k] as Image).duplicate()
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((k % 4) * w, (k / 4) * h))
	sheet.save_png(OUT + "/sheet_build.png")
	print("     frames: " + " | ".join(labels))
	(sc["root"] as Node).queue_free()
	await process_frame
	var sec: Dictionary = SC.build_section(root)
	var simg: Image = await grab()
	simg.save_png(OUT + "/section_pair.png")
	var bp := blue_px(simg)
	ok(bp > 500, "12 the syringe-pair section shows water blue (%d px)" % bp)
	(sec["root"] as Node).queue_free()
	print("     sheet: %s/sheet_build.png  section: %s/section_pair.png" % [OUT, OUT])


# ------------------------------------------------ 13
func bars_cost(d: Dictionary, vols: Dictionary) -> void:
	var b := BOM.bom(d, vols)
	var hand := 0.0
	for l in b["lines"]:
		hand += float(l["qty"]) * float(l["each"])
		print("     BOM %-72s %8.3f %-4s x %6.2f = %6.2f USD" % [l["item"], l["qty"], l["unit"], l["each"], l["cost"]])
	print("     BOM total %.2f USD" % b["total"])
	ok(rel(b["total"], hand) < 1e-9, "13 BOM lines add up: %.4f = %.4f USD" % [b["total"], hand])
	var w := BOM.works(d)
	ok(w["ok"], "13 the current design passes the working bars (%s)" % w["why"])
	var ch := BOM.cheapest(vols)
	var best: Dictionary = ch["best"]
	var n_ok := 0
	for r in ch["rows"]:
		if r["ok"]:
			n_ok += 1
	for r in (ch["rows"] as Array).slice(0, 10):
		print("     option %-9s %-5s big %-8s small %-7s %6.2f USD in-plane %5.2f mm %s" % [r["mat"], r["hose"], str(r["big"]), str(r["small"]), r["cost"], r["in"], "WORKS" if r["ok"] else "fails: " + String(r["why"])])
	ok(not best.is_empty() and float(best["cost"]) <= float(b["total"]) + 1e-9, "13 cheapest working design of %d (%d work): %s boom, %s tube, joints %s, wrist/gripper %s: %.2f USD vs current %.2f USD" % [(ch["rows"] as Array).size(), n_ok, best.get("mat", "?"), best.get("hose", "?"), str(best.get("big", [])), str(best.get("small", [])), float(best.get("cost", -1.0)), b["total"]])
	var pvc := A.design()
	pvc["hose"] = "pvc"
	var wp := BOM.works(pvc)
	ok(not wp["ok"], "13 PLANTED the current design with soft PVC tube fails the working bars (%s)" % wp["why"])
