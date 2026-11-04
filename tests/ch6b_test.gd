## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/ch6b_test.gd     (CH6b: rope self contact that holds, and the tie phase by phase)
## NEW BARS, written and committed BEFORE the first run of this file. They sit beside tests/ch6_test.gd (whose bars are untouched).
## Reference for the phases: docs/CH6_REFERENCE.md (Ashley, The Ashley Book of Knots, #1010 Bowline; rabbit-hole-tree sequence).
##
##  Step 1: the rope may not pass through itself (capsule-capsule contact, thickness 2r, kinematic particles of inverse mass 0,
##          substeps that grow with the fastest mover so nothing travels more than r/2 per substep)
##   K1 KIN     a driven particle sits on its target to 0.01 mm after every frame while the rope presses on it (C++)
##   S2 SAME    C++ and GDScript ropes, kin + adaptive substeps, end driven fast over the rope: every particle within 1 mm
##   S3 ADAPT   that scenario really used more substeps than the base count (the new path ran)
##   N1 NOPASS  the end driven over the rope at 0.36 m/s, kin + adapt: rope self-penetration <= 0.1 r on EVERY frame
##   N2 CONTROL the same with the rope-on-rope contact OFF: self-penetration > 0.1 r (the bar can fail)
##   C3 CONTROL the tie (Ch6Tie, tying frames) with the rope-on-rope contact OFF: self-penetration > 0.1 r somewhere (T1 can fail)
##  Step 2: the tie in named phases, the crossing code (view-minimised Gauss code, Reidemeister I/II reduced, up to the mirror)
##          checked at the end of each phase, expected codes hand-checked against the tying sequence below
##   phases (tying path waypoints, Ch6Knot.tip_waypoints):  hole = the rope laid out with the hole made (frame 0)
##     UP    the working end rises through the hole from behind           ends at waypoint 3  (z = +0.045, in front)   expect  1U 2O 1O 2U     (a clasp: end and hole interlocked)
##     DOWN  down in front of the hole's bottom strand, to below it       ends at waypoint 6                           expect  1U 2O 3U 1O 2U 3O
##     ROUND behind the standing part and back over it (the collar turn)  ends at waypoint 12                          expect  1U 2O 3U 4O 2U 3O 4U 1O
##     BACK  up in front of the bottom strand and down through the hole   ends at waypoint 18 (the keyed end)          expect  1U 2O 3O 4U 5O 6O 3U 4O 5U 1O 2U 6U   (the bowline)
##     hole  frame 0                                                                                                  expect  (empty: a single curl reduces away)
##   P0..P4 the simulated rope's code at the end of hole / UP / DOWN / ROUND / BACK equals the expected code (up to the mirror)
##   P5 REF  the expected codes above are the codes of the reference polyline (layout + keyed path) at the same waypoints
##   PS0..PS3 self-penetration <= 0.1 r on every frame of the phase UP / DOWN / ROUND / BACK
extends SceneTree

var fails := 0

const EXPECT := {
	"hole": "",
	"UP": "1U 2O 1O 2U",
	"DOWN": "1U 2O 3U 1O 2U 3O",
	"ROUND": "1U 2O 3U 4O 2U 3O 4U 1O",
	"BACK": "1U 2O 3O 4U 5O 6O 3U 4O 5U 1O 2U 6U",
}
const WP := {"UP": 3, "DOWN": 6, "ROUND": 12, "BACK": 18}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func same_as(code: Array, lit: String) -> bool:
	return Ch6Knot.code_str(code) == lit or Ch6Knot.code_str(Ch6Knot.mirror(code)) == lit


# ---- step 1: the rope scenario ---------------------------------------------------------------------

## 40 particles, end driven over the body (the ch6 SAME scenario) at `speedup` x its 0.36 m/s
func scenario(gd: bool, kin: float, adapt: float, selfcol: float, frames := 60) -> Dictionary:
	RopeSim.force_gdscript = gd
	var pts := PackedVector3Array()
	for i in 40:
		pts.append(Vector3(0.008 * i, 0, 0))
	var rp := RopeSim.new()
	rp.setup(pts, 0.008, 0.004, {"mass": 0.05, "mu": 0.4, "kb": 0.003, "iters": 10, "subs": 6, "damp": 0.98, "kin": kin, "adapt": adapt, "selfcol": selfcol})
	rp.drive(0, pts[0], pts[0])
	var keys := [Vector3(0.312, 0, 0), Vector3(0.20, 0.07, 0.0), Vector3(0.08, 0.0, 0.009), Vector3(0.08, -0.05, 0.009), Vector3(0.14, -0.05, 0.009)]
	var path := Ch6Knot.resample(Ch6Knot.spline(keys, 12), 0.012)
	var cur: Vector3 = pts[39]
	var worst_pen := 0.0
	var max_subs := 0
	var kin_err := 0.0
	for f in mini(frames, path.size()):
		rp.drive(39, cur, path[f])
		cur = path[f]
		rp.step(1.0 / 30.0)
		var xs := rp.positions()
		kin_err = maxf(kin_err, xs[39].distance_to(path[f]))
		kin_err = maxf(kin_err, xs[0].distance_to(pts[0]))
		worst_pen = maxf(worst_pen, rp.max_self_pen())
		max_subs = maxi(max_subs, rp.get_used_subs())
	RopeSim.force_gdscript = false
	return {"x": rp.positions(), "pen": worst_pen, "subs": max_subs, "kin_err": kin_err}


func step1() -> void:
	var rr := 0.004
	var c: Dictionary = scenario(false, 1.0, 0.5, 1.0)
	ok(c["kin_err"] <= 0.00001, "K1 driven particles sit on their targets (worst %.5f mm)" % (c["kin_err"] * 1000.0))
	if RopeSim.native_ok():
		var g: Dictionary = scenario(true, 1.0, 0.5, 1.0)
		var worst := 0.0
		for i in 40:
			worst = maxf(worst, (c["x"][i] as Vector3).distance_to(g["x"][i]))
		ok(worst <= 0.001, "S2 C++ and GDScript ropes agree within 1 mm with kin + adaptive substeps (%.3f mm)" % (worst * 1000.0))
	else:
		print("SKIP S2: no KineRopeNative in the DLL")
	ok(c["subs"] > 6, "S3 adaptive substeps ran: up to %d substeps (base 6)" % c["subs"])
	ok(c["pen"] <= 0.1 * rr, "N1 rope self-penetration <= 0.1 r on every frame (worst %.3f of r)" % (c["pen"] / rr))
	var n: Dictionary = scenario(false, 1.0, 0.5, 0.0)
	ok(n["pen"] > 0.1 * rr, "N2 CONTROL rope-on-rope contact off: self-penetration > 0.1 r (%.3f of r)" % (n["pen"] / rr))


# ---- step 2: the tie in phases ----------------------------------------------------------------------

func phase_frames(lay: PackedVector3Array, path: PackedVector3Array) -> Dictionary:
	var wps := Ch6Knot.tip_waypoints(lay[lay.size() - 1])
	var out := {}
	var last := 0
	for wi in range(1, wps.size()):
		var bi := last
		var bd := 1e9
		for k in range(last, path.size()):
			var d := (path[k] - (wps[wi] as Vector3)).length()
			if d < bd:
				bd = d
				bi = k
		last = bi
		out[wi] = bi
	return out


func step2() -> void:
	var rr := Ch6Knot.R_ROPE
	var lay := Ch6Knot.layout()
	var path := Ch6Knot.tip_path(lay[lay.size() - 1], 0.08, false)
	var pf := phase_frames(lay, path)
	# P5: the literals are the reference polyline's codes at those waypoints
	var refok := true
	var order := ["UP", "DOWN", "ROUND", "BACK"]
	for ph in order:
		var P := PackedVector3Array(lay)
		for k in range(1, int(pf[WP[ph]]) + 1):
			P.append(path[k])
		var rc := Ch6Knot.best_code(P)
		var good := same_as(rc, EXPECT[ph])
		print("     reference %-5s idx %3d: %s %s" % [ph, int(pf[WP[ph]]), Ch6Knot.code_str(rc), "" if good else "  <-- differs from the expected literal"])
		refok = refok and good
	refok = refok and same_as(Ch6Knot.best_code(lay), EXPECT["hole"])
	ok(refok, "P5 the expected codes are the reference polyline's codes at the phase ends (hole, UP, DOWN, ROUND, BACK)")
	# the simulated tie (tying frames only)
	var t0 := Time.get_ticks_msec()
	var tie := Ch6Tie.new()
	var R: Dictionary = tie.run({"tie_only": true})
	print("     tie run: %d frames, native=%s, %d s" % [R["frames"].size(), str(R["native"]), (Time.get_ticks_msec() - t0) / 1000])
	var lk: Array = R["log"].keys()
	lk.sort()
	for k in lk:
		if not String(k).begins_with("trace_"):
			print("     LOG ", k, " ", R["log"][k])
	var fr: Array = R["frames"]
	var sp: PackedFloat32Array = R["selfpen"]
	var c0: Array = Ch6Knot.best_code(fr[0])
	ok(same_as(c0, EXPECT["hole"]), "P0 hole: code '%s' (expect '%s')" % [Ch6Knot.code_str(c0), EXPECT["hole"]])
	var start := 0
	for i in order.size():
		var ph: String = order[i]
		var f: int = mini(int(pf[WP[ph]]), fr.size() - 1)
		var code: Array = Ch6Knot.best_code(fr[f])
		ok(same_as(code, EXPECT[ph]), "P%d %s (frame %d): code '%s' (expect '%s')" % [i + 1, ph, f, Ch6Knot.code_str(code), EXPECT[ph]])
	for i in order.size():
		var ph: String = order[i]
		var f1: int = mini(int(pf[WP[ph]]), sp.size() - 1)
		var worst := 0.0
		for f in range(start, f1 + 1):
			worst = maxf(worst, sp[f])
		start = f1 + 1
		ok(worst <= 0.1 * rr, "PS%d %s: self-penetration <= 0.1 r on every frame of the phase (worst %.3f of r)" % [i, ph, worst / rr])
	# C3: the same tie with the rope-on-rope contact off
	var Rc: Dictionary = Ch6Tie.new().run({"tie_only": true, "selfcol": false})
	var wc := 0.0
	for f in Rc["selfpen"].size():
		wc = maxf(wc, Rc["selfpen"][f])
	ok(wc > 0.1 * rr, "C3 CONTROL tie with rope-on-rope contact off: self-penetration > 0.1 r (%.3f of r)" % (wc / rr))


func _init() -> void:
	step1()
	step2()
	print("ch6b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
