## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/ch6_test.gd     (CH6: a bowline tied by a hand, then loaded)
## BARS, written and committed before the first number of the full run was read (the rope solver itself had been tried in a
## stand-alone C++ harness on 11-03; the Godot driver, the hand and these bars had not run). Reference: docs/CH6_REFERENCE.md.
##  A  CAPSTAN  a rope over a fixed cylinder (radius 3 cm, mu 0.4), tails loaded F1 = 5 N and F2 = ratio x F1, 1.5 s: the ratio at
##     which the far end first slips more than 5 cm (bisection) divided by exp(mu theta) lies in [0.95, 1.05]
##   A1 theta = pi/2   A2 theta = 3 pi/4   A3 theta = pi
##   A4 CONTROL (a bar must be able to fail): mu = 0 measured against the mu = 0.4 prediction at theta = pi is outside the band
##  S  SAME  (needs the DLL, else prints SKIP): the C++ rope and the GDScript rope (RopeSim.force_gdscript) on a 40-particle rope
##     whose end is driven over itself for 60 frames, self contact and friction on: every particle within 1 mm
##  T  THE TIE  a Kine hand (Body.reach + the pinch pose) ties the bowline over keyed time (Ch6Tie.run):
##   T0 REACH   the pinch point is within 3 mm of the keyed path on every tying frame
##   T1 SELF    rope self-penetration <= 0.1 of the rope radius (0.4 mm) on EVERY frame of the whole run (tie, loads)
##   T2 FINGER  rope penetration of any finger / palm / forearm / peg capsule <= 0.1 of the rope radius on EVERY frame
##   T3 CODE    the shortest Reidemeister I/II-reduced Gauss code of the rope over 46 view directions, at the end of the tying, equals
##              the code of the reference polyline (docs/CH6_REFERENCE.md: the rope laid out + the keyed path as a curve), up to the mirror
##   T4 WINDING the loop's winding about the peg is +-1 turn at the end of the tying
##  H  THE HOLD  seat the knot (S0 pulled 0 -> 120 N, held), unload to 20 N, then re-load 20 -> 120 N (the judged window):
##   H1 NO SLIP  S0 moves <= 1.5 cm along the pull over the judged window
##   H2 LOOP     loop circumference (Ch6Knot.loop_len) changes < 5 % over the judged window
##   H3 TIGHTENS the knot core (Ch6Knot.core_len) is shorter at the end of the seating hold than at the end of the tying, by >= 10 %
##   H4 CELL     the solver's tension readout is within 5 % of the applied 120 N at the end
##   H5 SELF     T1 holds through the loads (reported with T1)
##  C  CONTROLS the bars can fail (full runs)
##   C1 mu = 0: H1 fails (S0 moves > 1.5 cm)
##   C2 slip knot (the end passes OVER the standing part both times, no turn round it): H1 fails or T3 fails
extends SceneTree

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


# ---- capstan ---------------------------------------------------------------

func capstan_run(f1: float, ratio: float, mu: float, theta: float) -> float:
	var Rc := 0.03
	var r := 0.004
	var ds := 0.008
	var Rr := Rc + r
	var pts := PackedVector3Array()
	var y := -0.15
	while y < 0.0:
		pts.append(Vector3(-Rr, y, 0))
		y += ds
	var na := int(theta * Rr / ds)
	for k in na + 1:
		var a := PI - theta * float(k) / na
		pts.append(Vector3(Rr * cos(a), Rr * sin(a), 0))
	var last: Vector3 = pts[pts.size() - 1]
	var tan := Vector3(Rr * sin(PI - theta), -Rr * cos(PI - theta), 0).normalized()
	var d := ds
	while d < 0.15:
		pts.append(last + tan * d)
		d += ds
	var rp := RopeSim.new()
	rp.setup(pts, ds, r, {"mass": 0.01, "mu": mu, "kb": 0.0, "iters": 20, "subs": 8, "damp": 0.999})
	rp.set_colliders(PackedVector3Array([Vector3(0, 0, -0.1)]), PackedVector3Array([Vector3(0, 0, 0.1)]), PackedVector3Array([Vector3(0, 0, -0.1)]),
		PackedVector3Array([Vector3(0, 0, 0.1)]), PackedFloat32Array([Rc]), PackedFloat32Array([mu]))
	var n := pts.size()
	rp.set_force(0, Vector3(0, -f1, 0))
	rp.set_force(n - 1, tan * (f1 * ratio))
	var e0: Vector3 = rp.positions()[n - 1]
	for f in 90:
		rp.step(1.0 / 60.0)
	return (rp.positions()[n - 1] - e0).dot(tan)


func capstan_threshold(mu: float, theta: float, mu_pred: float) -> float:
	var pred := exp(mu_pred * theta)
	var lo := 0.5
	var hi := 1.5
	for k in 10:
		var m := (lo + hi) * 0.5
		if capstan_run(5.0, pred * m, mu, theta) > 0.05:
			hi = m
		else:
			lo = m
	return lo


# ---- C++ vs GDScript ---------------------------------------------------------

func same_scenario(gd: bool) -> PackedVector3Array:
	RopeSim.force_gdscript = gd
	var pts := PackedVector3Array()
	for i in 40:
		pts.append(Vector3(0.008 * i, 0, 0))
	var rp := RopeSim.new()
	rp.setup(pts, 0.008, 0.004, {"mass": 0.05, "mu": 0.4, "kb": 0.003, "iters": 10, "subs": 6, "damp": 0.98})
	rp.drive(0, pts[0], pts[0])
	var keys := [Vector3(0.312, 0, 0), Vector3(0.20, 0.07, 0.0), Vector3(0.08, 0.0, 0.009), Vector3(0.08, -0.05, 0.009), Vector3(0.14, -0.05, 0.009)]
	var path := Ch6Knot.resample(Ch6Knot.spline(keys, 12), 0.012)
	var cur: Vector3 = pts[39]
	for f in mini(60, path.size()):
		rp.drive(39, cur, path[f])
		cur = path[f]
		rp.step(1.0 / 30.0)
	RopeSim.force_gdscript = false
	return rp.positions()


func _init() -> void:
	# A
	var pi_pred := 0.4
	var a1 := capstan_threshold(0.4, PI / 2.0, pi_pred)
	var a2 := capstan_threshold(0.4, PI * 0.75, pi_pred)
	var a3 := capstan_threshold(0.4, PI, pi_pred)
	print("     capstan threshold / exp(mu theta): %.4f  %.4f  %.4f" % [a1, a2, a3])
	ok(a1 >= 0.95 and a1 <= 1.05, "A1 capstan theta = pi/2 within 5 %% (%.4f)" % a1)
	ok(a2 >= 0.95 and a2 <= 1.05, "A2 capstan theta = 3pi/4 within 5 %% (%.4f)" % a2)
	ok(a3 >= 0.95 and a3 <= 1.05, "A3 capstan theta = pi within 5 %% (%.4f)" % a3)
	var a4 := capstan_threshold(0.0, PI, 0.4)
	print("     control: mu = 0 measured against the mu = 0.4 prediction: %.4f" % a4)
	ok(a4 < 0.95 or a4 > 1.05, "A4 CONTROL mu = 0 fails the capstan band (%.4f)" % a4)
	# S
	if RopeSim.native_ok():
		var c := same_scenario(false)
		var g := same_scenario(true)
		var worst := 0.0
		for i in c.size():
			worst = maxf(worst, c[i].distance_to(g[i]))
		print("     C++ vs GDScript, worst particle %.3f mm" % (worst * 1000.0))
		ok(worst <= 0.001, "S1 C++ and GDScript ropes agree within 1 mm (%.3f mm)" % (worst * 1000.0))
	else:
		print("SKIP S1: no KineRopeNative in the DLL")
	# T, H
	var t0 := Time.get_ticks_msec()
	var tie := Ch6Tie.new()
	var R: Dictionary = tie.run({})
	print("     tie run: %d frames, native=%s, %d s" % [R["frames"].size(), str(R["native"]), (Time.get_ticks_msec() - t0) / 1000])
	judge(R, "main", true)
	# C
	var Rm: Dictionary = Ch6Tie.new().run({"mu": 0.0})
	var hm := hold_numbers(Rm)
	print("     control mu = 0: S0 moved %.1f cm" % (hm["s0"] * 100.0))
	ok(hm["s0"] > 0.015, "C1 CONTROL mu = 0 slips: S0 moves > 1.5 cm (%.1f cm)" % (hm["s0"] * 100.0))
	var Rw: Dictionary = Ch6Tie.new().run({"wrong": true})
	var hw := hold_numbers(Rw)
	var cw: Array = Ch6Knot.best_code(end_of_tie(Rw))
	var ref := reference_code()
	var code_ok := Ch6Knot.same_code(cw, ref)
	print("     control slip knot: S0 moved %.1f cm, code %s (reference %s)" % [hw["s0"] * 100.0, Ch6Knot.code_str(cw), Ch6Knot.code_str(ref)])
	ok(hw["s0"] > 0.015 or not code_ok, "C2 CONTROL the slip knot fails the hold bar or the code bar")
	print("ch6: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func reference_code() -> Array:
	var lay := Ch6Knot.layout()
	var path := Ch6Knot.tip_path(lay[lay.size() - 1], 0.08, false)
	var P := PackedVector3Array(lay)
	for i in range(1, path.size()):
		P.append(path[i])
	return Ch6Knot.best_code(P)


func end_of_tie(R: Dictionary) -> PackedVector3Array:
	return R["frames"][int(R["phase"]["tie_end"])]


func hold_numbers(R: Dictionary) -> Dictionary:
	var ph: Dictionary = R["phase"]
	var f0: int = ph["unload_end"]
	var f1: int = ph["end"] - 1
	var P0: PackedVector3Array = R["frames"][f0]
	var P1: PackedVector3Array = R["frames"][f1]
	var s0 := absf(P1[0].y - P0[0].y)
	return {"s0": s0, "P0": P0, "P1": P1}


func judge(R: Dictionary, tag: String, full: bool) -> void:
	var ph: Dictionary = R["phase"]
	var tie_end: int = ph["tie_end"]
	var rr := Ch6Knot.R_ROPE
	var wm := 0.0
	for f in tie_end:
		wm = maxf(wm, R["miss"][f])
	ok(wm <= 0.003, "T0 %s: the pinch stays within 3 mm of the keyed path (worst %.2f mm)" % [tag, wm * 1000.0])
	var sp := 0.0
	var cp := 0.0
	for f in R["selfpen"].size():
		sp = maxf(sp, R["selfpen"][f])
		cp = maxf(cp, R["colpen"][f])
	ok(sp <= 0.1 * rr, "T1 %s: rope self-penetration <= 0.1 r on every frame (worst %.3f of r)" % [tag, sp / rr])
	ok(cp <= 0.1 * rr, "T2 %s: rope-finger/palm/forearm/peg penetration <= 0.1 r on every frame (worst %.3f of r)" % [tag, cp / rr])
	var Pt := end_of_tie(R)
	var code: Array = Ch6Knot.best_code(Pt)
	var ref := reference_code()
	print("     code at the end of the tying: %s\n     reference:                    %s" % [Ch6Knot.code_str(code), Ch6Knot.code_str(ref)])
	ok(Ch6Knot.same_code(code, ref), "T3 %s: crossing code equals the bowline's (up to the mirror)" % tag)
	var wind := Ch6Knot.peg_winding(Pt)
	ok(absf(absf(wind) - 1.0) < 0.15, "T4 %s: the loop winds once about the peg (%.2f turns)" % [tag, wind])
	var h := hold_numbers(R)
	var c0 = Ch6Knot.knot_centre(h["P0"])
	var c1 = Ch6Knot.knot_centre(h["P1"])
	ok(h["s0"] <= 0.015, "H1 %s: no slip, S0 moves %.2f cm over the judged window (<= 1.5 cm)" % [tag, h["s0"] * 100.0])
	if c0 != null and c1 != null:
		var l0 := Ch6Knot.loop_len(h["P0"], c0)
		var l1 := Ch6Knot.loop_len(h["P1"], c1)
		ok(absf(l1 - l0) / l0 < 0.05, "H2 %s: loop circumference changes %.1f %% (< 5 %%; %.3f -> %.3f m)" % [tag, absf(l1 - l0) / l0 * 100.0, l0, l1])
	else:
		ok(false, "H2 %s: no knot found in the judged window" % tag)
	var Pe: PackedVector3Array = R["frames"][tie_end]
	var Ps: PackedVector3Array = R["frames"][int(ph["seat_end"])]
	var ce = Ch6Knot.knot_centre(Pe)
	var cs = Ch6Knot.knot_centre(Ps)
	if ce != null and cs != null:
		var k0 := Ch6Knot.core_len(Pe, ce)
		var k1 := Ch6Knot.core_len(Ps, cs)
		ok(k1 <= 0.9 * k0, "H3 %s: the knot tightens, core %.3f -> %.3f m (>= 10 %% shorter)" % [tag, k0, k1])
	else:
		ok(false, "H3 %s: no knot found" % tag)
	var tn: float = R["tension"][R["tension"].size() - 1]
	ok(absf(tn - 120.0) / 120.0 < 0.05, "H4 %s: tension readout %.1f N vs 120 N applied" % [tag, tn])
