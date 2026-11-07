## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/strength_test.gd
## INNOVATIONS N037 (real sway in holds: scripts/sway.gd + Scene.sway), N038 (stance strength map: scripts/stance_map.gd + stance_map_ui.gd),
## N039 (strength curves: scripts/strength_curves.gd + ForceView.dynamics(cap, true)). Agent tools: sway_trace, stance_map, strength_curve (strength_serve.gd).
## BARS WRITTEN AND COMMITTED BEFORE THE CODE. Sources are quoted FROM MEMORY (the numbers below are the registration; not re-read this session;
## a web search could not reach the tables either), so they are flagged UNVERIFIED in the report.
## REGISTERED NUMBERS
##  SWAY  quiet standing, eyes open, firm floor, young adults: RMS of the sway about its mean, anteroposterior (AP) 3.5 mm, mediolateral (ML) 2.5 mm
##        (Prieto, Myklebust, Hoffmann, Lovett & Myklebust 1996, IEEE Trans Biomed Eng 43:956, "Measures of postural steadiness: young vs elderly";
##        Raymakers, Samson & Verhaar 2005, Gait Posture 21:48, PMID 15536033: young group n=10, age 21-45, 60 s trials, 10 Hz; the 3.5 / 2.5 mm values themselves: UNVERIFIED (from memory), the abstracts give no RMS). These are COP values; the COM moves a little less,
##        so the model is the upper bound (stated). The band: nearly all the sway power is 0.1-1 Hz (Winter 1995, Gait Posture 3:193; Prieto 1996
##        mean frequency 0.2-0.6 Hz; band and both cites UNVERIFIED (from memory)). Dominant frequency must lie in 0.1-1.0 Hz.
##  CURVES  knee extension torque by knee flexion angle, men, isokinetic ~60 deg/s: peak at 71 deg of flexion from full extension (UNVERIFIED (from memory); the earlier Kooistra 2007 cite was
##        REMOVED: that paper tested only 30/60/90 deg and does not give a 71 deg peak); 77.9 % of peak at
##        100 deg in men (Marginson & Eston 2001, J Sports Sci 19:875, doi 10.1080/026404101753113822; the number is UNVERIFIED (from memory), not read in the paper); ~40 % of peak at full extension (0 deg) (UNVERIFIED (from memory): Kulig, Andrews & Hay 1984, Exerc Sport Sci Rev 12:417; MY ROUND NUMBER from the usual
##        figure of 35-45 %). Elbow flexion: peak at 90 deg of elbow flexion (UNVERIFIED (from memory); Kulig 1984; Knapik et al. 1983 says the peak angle is highly variable; Knapik, Wright, Mawdsley & Braun 1983, Phys Ther 63:938),
##        ~55 % of peak at full extension (0 deg) (round number from the same figures). The PEAK VALUE is the existing ForceView.LIMIT_NM (calf 250,
##        lowerarm 80 N m at 75 kg): the curve scales it, so the cap at the peak angle is that number.
##  MAP   the impulse a stance takes before a step is needed: J = M * omega0 * d, d = distance from the COM's floor point to the support polygon's edge
##        along the push direction, omega0 = sqrt(g / l) (Hof, Gazendam & Sinke 2005, J Biomech 38:1 = Recovery.read's capture point xi = x + v / omega0,
##        left the base when v = omega0 d). The "push force" is J over PUSH_T = 0.1 s (taste, stated). Direction 0 = forward, 90 = his left (Recovery.DIRS).
## BARS
##  N037 SWAY   S1 trace RMS (about the mean, 120 s at 50 Hz, seeds 1..3): AP within 20 % of 3.5 mm and ML within 20 % of 2.5 mm.
##              S2 the spectrum's dominant frequency of every trace is inside 0.1-1.0 Hz. C: a planted 5 Hz trace is NOT inside (the check can fail).
##              S3 the same seed gives byte-identical traces (var_to_bytes) and byte-identical Scene samples; another seed differs.
##              S4 opt-out: sway off (the default) gives a sample byte-equal to the moving-holds drift (_drift) and a to_dict with no sway keys; with sway on
##                 the move samples (outside the holds) are byte-identical to sway off; a round trip through to_dict/from_dict keeps sway and seed.
##              S5 the posed body: the COM of the applied pose in a 60 s hold, std about the mean, AP and ML together within 35 % of sqrt(3.5^2+2.5^2) mm
##                 (this bar is looser than S1 because the lean is a spine bend and the COM gain is a fixed 0.24 m: stated before measuring), and the feet
##                 do not move (sole shift < 0.1 mm).
##  N038 MAP    M1 a wide stance takes more lateral push than a narrow one, and the ratio of the lateral impulses is within 10 % of the ratio of the
##                 support widths (polygon extent across the body).
##              M2 forward + back impulse over (M omega0) equals the polygon's front-to-back extent within 5 %, and that extent is within 15 % of one
##                 foot's own heel-to-toe footprint length (parallel stance: the asymmetry is the foot).
##              M3 CONTROL: a single-leg stance (left thigh raised) has a smaller mean impulse than the two-foot stance, and its smallest is not larger.
##              M4 the numbers agree with the I39 judge: for directions 0, 90 and 180 Recovery.read at 0.98 J / M holds and at 1.02 J / M steps.
##              M5 the polar picture (PolarView.points) lies inside its control and its longest spoke reaches the picture radius.
##  N039 CURVES C1 the cap at the cited peak angle equals the cited peak within 2 % (knee 71 deg: 250 N m; elbow 90 deg: 80 N m, at 75 kg).
##              C2 at full extension the cap equals the cited fraction within 5 % (knee 0.40, elbow 0.55).
##              C3 a push that passes with the constant cap (tau/cap_const < 1) is flagged at a weak angle: synthetic knee at 10 deg flexion, tau 0.8 of
##                 the constant cap, frames 10..20: the first weak frame is 10, the flag reports the angle and both caps. CONTROL: the same tau at 71
##                 deg raises no flag.
##              C4 the judges read the curve: on scenes/combo3.json ForceView.dynamics(cap, true) ratio for calf_l equals tau / curve cap at the knee angle
##                 the test recomputes from the joint positions (1e-6), and the ratio differs from the constant one where the angle is off the peak.
##              C5 curves off: ForceView.dynamics(cap) and dynamics(cap, false) are byte-identical (var_to_bytes) and have no "weak" key.
##  UNDO       U1 each edit (_set_strength sway on, seed change, curves on) is exactly one undo step; Ctrl+Z puts the setting back; the three reads
##                 (sway_trace, stance_map, strength_curve via StrengthServe) add no step and leave the scene JSON byte-identical.
extends SceneTree

var fails := 0
var m: Node
const AP_MM := 3.5
const ML_MM := 2.5
const BAND_LO := 0.1
const BAND_HI := 1.0
const PUSH_T := 0.1


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func rms(a: Array) -> float:
	var mu := 0.0
	for v in a:
		mu += float(v)
	mu /= maxf(a.size(), 1)
	var s := 0.0
	for v in a:
		s += (float(v) - mu) * (float(v) - mu)
	return sqrt(s / maxf(a.size(), 1))


## the frequency of the largest spectral line between 0.02 and 3 Hz (plain DFT on a grid)
func dominant(x: Array, hz: float) -> float:
	var n := x.size()
	var mu := 0.0
	for v in x:
		mu += float(v)
	mu /= n
	var best := 0.0
	var bp := -1.0
	var f := 0.02
	while f <= 3.0:
		var re := 0.0
		var im := 0.0
		for i in n:
			var a := TAU * f * float(i) / hz
			re += (float(x[i]) - mu) * cos(a)
			im += (float(x[i]) - mu) * sin(a)
		var pw := re * re + im * im
		if pw > bp:
			bp = pw
			best = f
		f += 0.02
	return best


func stand_body(abduct := 0.0, up_left := 0.0) -> Body:
	var B := DistanceKeeper.new_body()
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	if abduct != 0.0:
		B.ang["thigh_l"] = Vector3(0, abduct, 0)
		B.ang["thigh_r"] = Vector3(0, -abduct, 0)
	if up_left != 0.0:
		B.ang["thigh_l"] = Vector3(up_left, 0, 0)
	B.fk()
	B.ground()
	B.fk()
	return B


func width_of(B: Body) -> float:
	var r := Balance.read(B)
	var lo := INF
	var hi := -INF
	var h := Recovery.heading(B)
	var side := Vector2(cos(h), -sin(h))   # across the body (perpendicular to the facing d = (sin h, cos h))
	for p in r["poly"]:
		var s := (p as Vector2).dot(side)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return hi - lo


func length_of(B: Body) -> float:
	var r := Balance.read(B)
	var lo := INF
	var hi := -INF
	var h := Recovery.heading(B)
	var d := Vector2(sin(h), cos(h))
	for p in r["poly"]:
		var s := (p as Vector2).dot(d)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return hi - lo


func spot(mp: Dictionary, deg: float) -> float:
	return StanceMap.at(mp, deg)


func hold_scene(hold: float, holds: bool) -> Scene:
	var B := stand_body()
	var d := B.to_dict()
	var S := Scene.new()
	S.from_dict({"scene": "strength", "fps": 30, "on_floor": true, "moving_holds": holds, "cards": [
		{"name": "a", "pose": d, "move": -1.0, "hold": hold},
		{"name": "b", "pose": d, "move": 0.5, "hold": 1.0}]})
	return S


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false

	# ---------------------------------------------------------------- N037 SWAY
	ok(is_equal_approx(Sway.RMS_AP_MM, AP_MM) and is_equal_approx(Sway.RMS_ML_MM, ML_MM) and is_equal_approx(Sway.BAND_LO, BAND_LO) and is_equal_approx(Sway.BAND_HI, BAND_HI),
		"registered: the module carries 3.5 / 2.5 mm and the 0.1-1.0 Hz band")
	var all_rms_ok := true
	var all_dom_ok := true
	var line := ""
	for sd in [1, 2, 3]:
		var tr: Array = Sway.trace(sd, 120.0, 50.0)   # Vector2 (ml_mm, ap_mm)
		var ml := tr.map(func(v): return (v as Vector2).x)
		var ap := tr.map(func(v): return (v as Vector2).y)
		var ra := rms(ap)
		var rm := rms(ml)
		var da := dominant(ap, 50.0)
		var dm := dominant(ml, 50.0)
		line += "  seed %d: AP %.2f mm ML %.2f mm, dominant %.2f / %.2f Hz;" % [sd, ra, rm, da, dm]
		if absf(ra / AP_MM - 1.0) > 0.2 or absf(rm / ML_MM - 1.0) > 0.2:
			all_rms_ok = false
		if da < BAND_LO or da > BAND_HI or dm < BAND_LO or dm > BAND_HI:
			all_dom_ok = false
	print("    " + line)
	ok(all_rms_ok, "S1 trace RMS AP/ML within 20 % of 3.5 / 2.5 mm for seeds 1..3")
	ok(all_dom_ok, "S2 the dominant frequency of every trace is inside 0.1-1.0 Hz")
	var tremor := []
	for i in 6000:
		tremor.append(3.5 * sin(TAU * 5.0 * float(i) / 50.0))
	var dt := dominant(tremor, 50.0)
	control(dt >= BAND_LO and dt <= BAND_HI, "a 5 Hz tremor trace reads %.2f Hz and is not inside the quiet-standing band" % dt)
	var t1a := var_to_bytes(Sway.trace(7, 30.0, 30.0))
	var t1b := var_to_bytes(Sway.trace(7, 30.0, 30.0))
	var t2 := var_to_bytes(Sway.trace(8, 30.0, 30.0))
	var S := hold_scene(60.0, true)
	S.sway = true
	S.sway_seed = 5
	var sa := var_to_bytes(S._sample_cards(12.34))
	var sb := var_to_bytes(S._sample_cards(12.34))
	S.sway_seed = 6
	var sc := var_to_bytes(S._sample_cards(12.34))
	ok(t1a == t1b and t1a != t2 and sa == sb and sa != sc, "S3 the same seed is byte-identical (trace and scene sample), another seed differs")
	# opt-out
	var Soff := hold_scene(60.0, true)
	var drift_ref := var_to_bytes(Soff._drift(0, 12.34 / 60.0))
	var off_sample := var_to_bytes(Soff._sample_cards(12.34))
	var d_off := Soff.to_dict(stand_body(), false)
	var no_keys := not d_off.has("sway") and not d_off.has("sway_seed") and not d_off.has("strength_curves")
	var Son := hold_scene(60.0, true)
	Son.sway = true
	Son.sway_seed = 3
	var moves_same := true
	for tt in [0.0, 60.1, 60.25, 60.4]:   # the 0.5 s move into card b starts at 60.0 (card a's hold is 0..60)
		if var_to_bytes(Son._sample_cards(tt)) != var_to_bytes(Soff._sample_cards(tt)) and tt > 60.05:
			moves_same = false
	var Srt := Scene.new()
	Srt.from_dict(Son.to_dict(stand_body(), false))
	ok(drift_ref == off_sample and no_keys and moves_same and Srt.sway and Srt.sway_seed == 3,
		"S4 sway off = the moving-holds drift byte for byte, no sway keys in the saved scene; moves unchanged with sway on; to_dict/from_dict keep sway and seed")
	# the posed body
	var Bp := stand_body()
	var Sp := hold_scene(60.0, false)
	Sp.sway = true
	Sp.sway_seed = 11
	var ap_com := []
	var ml_com := []
	var sole0 := Vector3.ZERO
	var sole_max := 0.0
	var t := 1.0
	var first := true
	while t < 59.0:
		Sp.apply(Bp, t)
		var c := Balance.com(Bp)
		var h := Recovery.heading(Bp)
		var f := Vector2(sin(h), cos(h))
		var sd2 := Vector2(cos(h), -sin(h))
		ap_com.append(Vector2(c.x, c.z).dot(f) * 1000.0)
		ml_com.append(Vector2(c.x, c.z).dot(sd2) * 1000.0)
		if first:
			sole0 = Bp.P["foot_l"]
			first = false
		sole_max = maxf(sole_max, ((Bp.P["foot_l"] as Vector3) - sole0).length())
		t += 0.25
	var comr := sqrt(pow(rms(ap_com), 2.0) + pow(rms(ml_com), 2.0))
	var want := sqrt(AP_MM * AP_MM + ML_MM * ML_MM)
	print("    posed COM sway: AP %.2f ML %.2f mm, total %.2f mm (want %.2f), sole shift %.4f mm" % [rms(ap_com), rms(ml_com), comr, want, sole_max * 1000.0])
	ok(absf(comr / want - 1.0) <= 0.35 and sole_max < 0.0001, "S5 the applied pose's COM sway is within 35 % of %.2f mm and the feet stay" % want)

	# ---------------------------------------------------------------- N038 MAP
	var Bn := stand_body(0.0)
	# SETUP fixed after the first run (not a bar): the sign of the thigh side angle is not known, so both signs are tried and the one with both feet down and the wider base is the wide stance
	var Bw := stand_body(12.0)
	var Bw2 := stand_body(-12.0)
	var okw := (Balance.read(Bw)["down"] as Array).size() == 2
	var okw2 := (Balance.read(Bw2)["down"] as Array).size() == 2
	if (okw2 and not okw) or (okw2 == okw and width_of(Bw2) > width_of(Bw)):
		Bw = Bw2
	var wn := width_of(Bn)
	var ww := width_of(Bw)
	var mn := StanceMap.compute(Bn)
	var mw := StanceMap.compute(Bw)
	var latn := minf(spot(mn, 90.0), spot(mn, 270.0))
	var latw := minf(spot(mw, 90.0), spot(mw, 270.0))
	print("    narrow width %.1f cm lateral %.1f N s; wide width %.1f cm lateral %.1f N s; ratios J %.3f width %.3f" % [wn * 100.0, latn, ww * 100.0, latw, latw / latn, ww / wn])
	ok(ww > wn and latw > latn and absf((latw / latn) / (ww / wn) - 1.0) <= 0.10, "M1 wide stance takes more lateral push; the impulse ratio %.3f is within 10 %% of the width ratio %.3f" % [latw / latn, ww / wn])
	var fb := (spot(mn, 0.0) + spot(mn, 180.0)) / (float(mn["mass"]) * float(mn["w0"]))
	var ln := length_of(Bn)
	var fl := Balance.footprint(Bn, "_l")
	var flo := INF
	var fhi := -INF
	var hh := Recovery.heading(Bn)
	for p in fl:
		var s := (p as Vector2).dot(Vector2(sin(hh), cos(hh)))
		flo = minf(flo, s)
		fhi = maxf(fhi, s)
	var foot_len := fhi - flo
	print("    front+back extent from the map %.1f cm, polygon %.1f cm, one foot %.1f cm" % [fb * 100.0, ln * 100.0, foot_len * 100.0])
	ok(absf(fb / ln - 1.0) <= 0.05 and absf(ln / foot_len - 1.0) <= 0.15, "M2 front + back impulse gives the polygon's length (5 %) and that is the foot's length (15 %)")
	var B1 := stand_body(0.0, 70.0)
	var m1 := StanceMap.compute(B1)
	var mean_two := StanceMap.mean(mn)
	var mean_one := StanceMap.mean(m1)
	var min_two := StanceMap.lowest(mn)
	var min_one := StanceMap.lowest(m1)
	print("    two feet: mean %.1f min %.1f N s;  one foot: mean %.1f min %.1f N s (ok %s)" % [mean_two, min_two, mean_one, min_one, str(m1.get("ok", false))])
	ok(mean_one < mean_two and min_one <= min_two, "M3 CONTROL single-leg stance: the map shrinks")
	var agree := true
	var msg := ""
	for dg in [0.0, 90.0, 180.0]:
		var J := spot(mn, dg)
		var lo := Recovery.read(Bn, dg, 0.98 * J / float(mn["mass"]))
		var hi := Recovery.read(Bn, dg, 1.02 * J / float(mn["mass"]))
		msg += " %d deg J %.1f -> %s/%s;" % [int(dg), J, lo["verdict"], hi["verdict"]]
		if String(lo["verdict"]) != "hold" or String(hi["verdict"]) == "hold":
			agree = false
	print("    " + msg)
	ok(agree, "M4 the map's impulses are the I39 judge's hold/step threshold in 0, 90, 180 deg")
	m.sm_ui.compute()
	await idle(2)
	var pv: Control = m.sm_ui.polar
	var pts: PackedVector2Array = pv.points()
	var inside := pts.size() >= 8
	var rmax := 0.0
	var ctr := pv.size * 0.5
	for p in pts:
		if p.x < 0.0 or p.y < 0.0 or p.x > pv.size.x or p.y > pv.size.y:
			inside = false
		rmax = maxf(rmax, p.distance_to(ctr))
	var rad := minf(pv.size.x, pv.size.y) * 0.5
	print("    polar picture: %d points, control %.0fx%.0f, longest spoke %.1f px of radius %.1f" % [pts.size(), pv.size.x, pv.size.y, rmax, rad])
	ok(inside and rmax >= rad * 0.9 and rmax <= rad + 0.5, "M5 the polar picture is inside its control and its longest spoke reaches the radius")

	# ---------------------------------------------------------------- N039 CURVES
	var kn := StrengthCurves.cap_nm("calf_l", 75.0, 71.0)
	var el := StrengthCurves.cap_nm("lowerarm_r", 75.0, 90.0)
	ok(absf(kn / 250.0 - 1.0) <= 0.02 and absf(el / 80.0 - 1.0) <= 0.02, "C1 cap at the cited peak angle: knee 71 deg %.1f N m (250), elbow 90 deg %.1f N m (80)" % [kn, el])
	var k0 := StrengthCurves.cap_nm("calf_l", 75.0, 0.0)
	var e0 := StrengthCurves.cap_nm("lowerarm_r", 75.0, 0.0)
	ok(absf(k0 / (0.40 * 250.0) - 1.0) <= 0.05 and absf(e0 / (0.55 * 80.0) - 1.0) <= 0.05, "C2 cap at full extension: knee %.1f N m (100), elbow %.1f N m (44)" % [k0, e0])
	var tau := []
	var angs := []
	var angp := []
	for i in 30:
		tau.append(0.8 * 250.0 if i >= 10 and i <= 20 else 50.0)
		angs.append(10.0)
		angp.append(71.0)
	var weak: Dictionary = StrengthCurves.check({"calf_l": tau}, {"calf_l": angs}, 75.0)
	var weak_c: Dictionary = StrengthCurves.check({"calf_l": tau}, {"calf_l": angp}, 75.0)
	var wl: Array = weak["weak"]
	var w0: Dictionary = wl[0] if not wl.is_empty() else {}
	print("    weak flag: %s" % str(w0))
	ok(not wl.is_empty() and int(w0.get("frame", -1)) == 10 and absf(float(w0.get("angle", 0.0)) - 10.0) < 1e-6 and float(w0.get("cap_const", 0.0)) > float(w0.get("cap_curve", 9e9)),
		"C3 the 0.8-of-constant knee push at 10 deg is flagged at frame 10 with the angle and both caps")
	control(not (weak_c["weak"] as Array).is_empty(), "the same push at the peak angle 71 deg raises a weak-angle flag")
	var S3 := Scene.new()
	S3.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var B3 := DistanceKeeper.new_body()
	var cap := ForceView.capture(S3, B3)
	var d_const := ForceView.dynamics(cap)
	var d_false := ForceView.dynamics(cap, false)
	var d_curve := ForceView.dynamics(cap, true)
	ok(var_to_bytes(d_const) == var_to_bytes(d_false) and not d_const.has("weak"), "C5 curves off: dynamics(cap) and dynamics(cap, false) are byte-identical and carry no weak flags")
	var n: int = cap["n"]
	var maxdiff := 0.0
	var differs := 0
	var maxrel := 0.0
	for i in n:
		var pj: Dictionary = cap["ps"][i]
		var v1: Vector3 = (pj["thigh_l"] as Vector3) - (pj["calf_l"] as Vector3)
		var v2: Vector3 = (pj["foot_l"] as Vector3) - (pj["calf_l"] as Vector3)
		var flex := 180.0 - rad_to_deg(v1.angle_to(v2))
		var want_r := float(d_curve["tau"]["calf_l"][i]) / StrengthCurves.cap_nm("calf_l", float(cap["mass"]), flex)
		maxdiff = maxf(maxdiff, absf(want_r - float(d_curve["ratio"]["calf_l"][i])))
		var dr := absf(float(d_curve["ratio"]["calf_l"][i]) - float(d_const["ratio"]["calf_l"][i]))
		if dr > 1e-6:
			differs += 1
		maxrel = maxf(maxrel, dr)
	print("    combo3 calf_l: ratio vs recompute max diff %.2e, %d of %d frames differ from the constant cap (max %.3f)" % [maxdiff, differs, n, maxrel])
	ok(maxdiff < 1e-6 and differs > 0 and d_curve.has("weak"), "C4 the judge reads the curve: ratio = tau / cap at the knee angle (1e-6), and it differs from the constant cap")

	# ---------------------------------------------------------------- UNDO
	m.S.from_dict(hold_scene(10.0, false).to_dict(stand_body(), false))
	m._rebuild_cards()
	m.playing = false
	m.playhead = 0.0
	m._ps().apply(m.B, 0.0)
	m._refresh()
	await idle(3)
	var js0 := JSON.stringify(m.S.to_dict(m.B, false))
	var u0: int = m.undo.size()
	for rd in [{"op": "sway_trace", "seed": 4, "seconds": 5.0}, {"op": "stance_map"}, {"op": "strength_curve", "joint": "calf_l", "angle": 30.0}]:
		var r := StrengthServe.serve(String(rd["op"]), m, rd)
		if not bool(r.get("ok", false)):
			print("    serve %s: %s" % [rd["op"], str(r)])
	var js1 := JSON.stringify(m.S.to_dict(m.B, false))
	ok(m.undo.size() == u0 and js0 == js1, "U1 the three reads add no undo step and leave the scene JSON byte-identical")
	var steps := 0
	m._set_strength("sway", true, 5)
	steps += int(m.undo.size() == u0 + 1)
	m._set_strength("sway", true, 9)
	steps += int(m.undo.size() == u0 + 2)
	m._set_strength("curves", true, -1)
	steps += int(m.undo.size() == u0 + 3)
	var on_all: bool = m.S.sway and int(m.S.sway_seed) == 9 and m.S.strength_curves
	m._undo()
	m._undo()
	m._undo()
	var back: bool = (not m.S.sway) and (not m.S.strength_curves) and JSON.stringify(m.S.to_dict(m.B, false)) == js0
	ok(steps == 3 and on_all and back, "U1 each edit is one undo step (%d of 3); three Ctrl+Z put sway, seed and curves back and the scene JSON is byte-identical" % steps)

	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
