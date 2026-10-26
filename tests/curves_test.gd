## godot --headless --path . -s tests/curves_test.gd     (GATE WW2; headless is fine)
## CURVE TOOLS (#244 #245): Euler filter, Gaussian, Butterworth, Decimate, Clean on plain channels and on a real
## scene's right upper arm. Every line prints the measured number beside its bar.
extends SceneTree

var fails := 0
var n_ok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if c:
		n_ok += 1
	else:
		fails += 1


func max_step(ch: Array, k := -1) -> float:
	var w := 0.0
	for i in range(1, ch.size()):
		var d = ch[i][1] - ch[i - 1][1]
		w = maxf(w, absf(d[k]) if k >= 0 else absf(d))
	return w


func sine(f: float, fps := 60.0, n := 600) -> Array:
	var o := []
	for i in n:
		o.append([i / fps, 10.0 * sin(TAU * f * i / fps)])
	return o


## sine amplitude from the RMS of the middle half (sqrt 2 x rms), so sampling never misses the peak
func amp(ch: Array) -> float:
	var w := 0.0
	var n := 0
	for i in range(ch.size() / 4, ch.size() * 3 / 4):
		w += ch[i][1] * ch[i][1]
		n += 1
	return sqrt(2.0 * w / n)


func _init() -> void:
	# 1 a twist spin through +-180: 30 deg per key wraps to -180 at the crossing
	var spin := []
	for i in 30:
		spin.append([i * 0.1, Vector3(5.0, 0.0, wrapf(i * 30.0, -180.0, 180.0))])
	var before := max_step(spin, 2)
	var r := Curves.euler_filter(spin)
	var after := max_step(r["track"], 2)
	ok(before > 180.0, "1 wrapped spin jumps %.0f deg between keys (bar > 180)" % before)
	ok(after < 180.0 and absf(after - 30.0) < 1e-6, "1b filtered max step %.3f deg (bar < 180, expect 30)" % after)
	ok(absf(r["track"][-1][1].z - 29.0 * 30.0) < 1e-6, "2 last key is the true unwrapped angle %.1f (expect 870)" % r["track"][-1][1].z)
	ok(max_step(r["track"], 0) == 0.0, "3 the other axes are untouched (x step %.3f)" % max_step(r["track"], 0))
	var back := Curves.euler_filter(r["track"])
	ok(back["report"]["worst_err"] == 0.0, "4 filtering twice changes nothing (%.3f)" % back["report"]["worst_err"])
	# 2 Butterworth, 60 fps, 6 Hz cutoff
	var s1: Array = Curves.butterworth(sine(1.0), 6.0, 60.0)["track"]
	var s20: Array = Curves.butterworth(sine(20.0), 6.0, 60.0)["track"]
	var a1 := amp(s1) / 10.0
	var a20 := amp(s20) / 10.0
	ok(absf(a1 - 1.0) < 0.01, "5 1 Hz keeps amplitude %.4f (bar within 1%% of 1; theory 0.9992)" % a1)
	ok(a20 < 0.05, "6 20 Hz leaves %.4f of its amplitude (bar < 0.05; theory 0.0081)" % a20)
	var s6 := amp(Curves.butterworth(sine(6.0), 6.0, 60.0)["track"]) / 10.0
	ok(absf(s6 - 0.5) < 0.02, "7 6 Hz (the cutoff) keeps %.4f (zero-phase filtfilt: 1/(1+1) = 0.5)" % s6)
	var ph := 0.0
	for i in range(200, 400):
		ph = maxf(ph, absf(s1[i][1] - 10.0 * sin(TAU * 1.0 * i / 60.0)))
	ok(ph < 0.1, "8 zero phase: 1 Hz output differs from the input sine by %.4f (bar < 0.1)" % ph)
	# 3 Gaussian
	var cst := []
	for i in 50:
		cst.append([i / 30.0, 42.0])
	var gc := Curves.smooth_gaussian(cst, 0.1)
	ok(gc["report"]["worst_err"] < 1e-9, "9 a constant is kept (worst change %s, bar < 1e-9)" % String.num_scientific(gc["report"]["worst_err"]))
	var bump := []
	var m0 := 0.0
	for i in 120:
		var v := 20.0 * exp(-pow((i - 60) / 8.0, 2.0))
		bump.append([i / 30.0, v])
		m0 += v
	var gb := Curves.smooth_gaussian(bump, 0.2)
	var m1 := 0.0
	var pk1 := 0.0
	for p in gb["track"]:
		m1 += p[1]
		pk1 = maxf(pk1, p[1])
	ok(absf(m1 - m0) / m0 < 1e-3, "10 the mean is preserved: %.5f vs %.5f (bar rel 1e-3)" % [m1 / 120.0, m0 / 120.0])
	ok(pk1 < 19.9, "11 the peak is lowered 20 -> %.3f (bar < 19.9)" % pk1)
	# 4 a real scene: combo3, right upper arm
	var f := FileAccess.open("res://scenes/combo3.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var S := Scene.new()
	S.from_dict(d)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var ch := Curves.sample_scene_channel(S, B, "upperarm_r", 30.0)
	ok(ch.size() > 100, "12 sampled %d keys over %.2f s (bar > 100)" % [ch.size(), S.length()])
	var bar := 0.5
	var dr := Curves.decimate(ch, bar)
	var rp: Dictionary = dr["report"]
	print("     decimate %.1f deg: %d -> %d keys, worst %.4f deg" % [bar, rp["keys_before"], rp["keys_after"], rp["worst_err"]])
	ok(rp["worst_err"] <= bar + 1e-9, "13 decimate worst err %.4f <= bar %.1f" % [rp["worst_err"], bar])
	ok(rp["keys_after"] < rp["keys_before"] * 0.6, "14 decimate keeps under 60%% of the keys (%d of %d)" % [rp["keys_after"], rp["keys_before"]])
	var d0 := Curves.decimate(ch, 0.0)
	ok(d0["report"]["worst_err"] < 1e-9, "15 decimate at 0 keeps the curve (worst %s, %d keys)" % [String.num_scientific(d0["report"]["worst_err"]), d0["report"]["keys_after"]])
	var cl := Curves.clean(ch, bar)
	ok(cl["report"]["worst_err"] <= bar + 1e-9 and cl["report"]["keys_after"] < ch.size(), "16 clean %.1f: %d -> %d keys, worst %.4f" % [bar, ch.size(), cl["report"]["keys_after"], cl["report"]["worst_err"]])
	var sg := Curves.smooth_gaussian(ch, 0.1)
	var bw := Curves.butterworth(ch, 4.0, 30.0)
	ok(sg["report"]["worst_err"] > 0.0 and sg["track"].size() == ch.size(), "17 gaussian on the scene: worst change %.3f deg, same key count" % sg["report"]["worst_err"])
	ok(bw["report"]["worst_err"] > 0.0 and bw["track"].size() == ch.size(), "18 butterworth on the scene: worst change %.3f deg" % bw["report"]["worst_err"])
	# 5 clean on a straight line
	var line := []
	for i in 40:
		line.append([i / 30.0, Vector3(i * 2.0, 10.0 - i, 5.0)])
	var cr := Curves.clean(line, 0.001)
	ok(cr["report"]["keys_after"] == 2 and cr["report"]["worst_err"] < 1e-4, "19 a straight line cleans to %d keys (bar 2), worst %s" % [cr["report"]["keys_after"], String.num_scientific(cr["report"]["worst_err"])])
	var dl := Curves.decimate(line, 0.001)
	ok(dl["report"]["keys_after"] == 2, "20 and decimates to %d keys (bar 2)" % dl["report"]["keys_after"])
	var corner := [[0.0, 0.0], [1.0, 10.0], [2.0, 0.0]]
	ok(Curves.clean(corner, 0.1)["report"]["keys_after"] == 3 and Curves.decimate(corner, 0.1)["report"]["keys_after"] == 3, "21 a real corner is kept by both")
	print("CURVES TEST %s %d (ok %d)" % ["PASS" if fails == 0 else "FAIL", fails, n_ok])
	TestFiles.cleanup()
	quit(fails)
