## godot --headless --path . -s tests/key_reduce_test.gd     (ROADMAP 68: key reduction, scripts/key_reduce.gd)
## KEY REDUCTION: a dense joint (a sine of 40 deg, 0.8 Hz, sampled at 30 fps for 3 s: 91 keys) thinned by a tolerance.
## Bars, stated before measuring:
##   1 tolerance 0.5 deg: the worst error at the sampled frames (the reduced curve against the sine at each frame) <= 0.5 (bar)
##   2 tolerance 0.5 deg: at least 70 % of the keys are removed (bar); the first and last key stay (bar)
##   3 tolerance 0: nothing is removed (bar)
##   4 the readout's worst error (deg, at the time and joint it names) equals the error measured again at that time from the
##     two curves within 0.01 deg (bar)
##   5 the first key keeps its modifier stack (a limits modifier on it): the reduced joint still samples the limits (bar)
##   6 a second joint with 2 keys is left as it was (bar); the readout names the joint with the worst error
## Reported, not barred: the worst error BETWEEN frames (60 Hz grid) against the sine, and the kept count at 2 deg.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func sine(t: float) -> Vector3:
	return Vector3(40.0 * sin(TAU * 0.8 * t), 0.0, 0.0)


func dense(n_frames: int) -> Array:
	var keys := []
	for f in n_frames:
		var t := float(f) / 30.0
		keys.append({"t": t, "v": sine(t)})
	return keys


func _init() -> void:
	var keys := dense(91)
	var pk := {"upperarm_l": keys}
	var orig := pk.duplicate(true)

	# 1, 2, 4: tolerance 0.5 deg
	var r := KeyReduce.reduce(pk, 0.5)
	var red: Array = r["pk"]["upperarm_l"]
	var kept := red.size()
	print("reduce 0.5 deg: %d -> %d keys (%.0f %% removed)" % [keys.size(), kept, 100.0 * (1.0 - float(kept) / keys.size())])
	var wf := 0.0
	for f in 91:
		var t := float(f) / 30.0
		wf = maxf(wf, KeyReduce.channel_err(PartKeys.at(red, t), sine(t)))
	print("  worst error at the 91 frames: %.4f deg" % wf)
	ok(wf <= 0.5, "1 worst sampled error %.4f deg <= 0.5 at the frames (bar)" % wf)
	ok(float(kept) <= 0.3 * keys.size(), "2 %d of %d keys removed = %.0f %% >= 70 %% (bar)" % [keys.size() - kept, keys.size(), 100.0 * (1.0 - float(kept) / keys.size())])
	ok(is_equal_approx(float(red[0]["t"]), 0.0) and is_equal_approx(float(red[kept - 1]["t"]), 90.0 / 30.0), "2 the first (0 s) and last (3 s) keys stay (bar)")
	var wb := 0.0
	for s in 301:
		var t := float(s) / 100.0 * 0.3   # 300 steps over 0..3 s: between the frames too, reported only
		wb = maxf(wb, KeyReduce.channel_err(PartKeys.at(red, t), sine(t)))
	print("  reported, not barred: worst error on a 100 Hz grid (between frames too): %.4f deg" % wb)
	var jt := float(r["t"])
	var mine := KeyReduce.channel_err(PartKeys.at(red, jt), PartKeys.at(orig["upperarm_l"], jt))
	print("readout: worst %.4f deg at %.3f s (%s); measured again: %.4f deg" % [float(r["worst"]), jt, r["joint"], mine])
	ok(String(r["joint"]) == "upperarm_l" and absf(mine - float(r["worst"])) <= 0.01,
		"4 readout worst %.4f deg at %.3f s equals the measured %.4f within 0.01 (bar)" % [float(r["worst"]), jt, mine])
	ok(int(r["before"]) == 91 and int(r["after"]) == kept, "4 the readout counts 91 -> %d keys" % kept)

	# 3: tolerance 0 removes nothing
	var r0 := KeyReduce.reduce(pk, 0.0)
	ok(int(r0["after"]) == 91 and (r0["pk"]["upperarm_l"] as Array).size() == 91, "3 tolerance 0 removes nothing: 91 -> %d (bar)" % int(r0["after"]))

	# the 2 deg reading, reported
	var r2 := KeyReduce.reduce(pk, 2.0)
	print("reported, not barred: 2 deg keeps %d of 91 keys, worst %.3f deg" % [int(r2["after"]), float(r2["worst"])])

	# 5: a limits modifier on the first key survives and still limits the curve
	var pm := {"upperarm_l": dense(91)}
	(pm["upperarm_l"][0] as Dictionary)["mods"] = [{"type": "limits", "ch": 0, "min": -10.0, "max": 10.0, "mix": 1.0}]
	var rm := KeyReduce.reduce(pm, 0.5)
	var km: Array = rm["pk"]["upperarm_l"]
	var mods_kept: bool = km[0].has("mods") and (km[0]["mods"] as Array).size() == 1
	var clamped := PartKeys.value_at(km, 0.5)
	ok(mods_kept and clamped.x <= 10.0 + 1e-6 and clamped.x >= -10.0 - 1e-6, "5 the first key keeps its limits modifier, value_at at 0.5 s = %.3f (within -10..10) (bar)" % clamped.x)

	# 6: a second joint with two keys is left alone; the readout names the worst joint
	var two := [{"t": 0.0, "v": Vector3(5, 0, 0)}, {"t": 1.0, "v": Vector3(-5, 0, 0)}]
	var p2 := {"upperarm_l": dense(91), "lowerarm_r": two.duplicate(true)}
	var r6 := KeyReduce.reduce(p2, 0.5)
	ok((r6["pk"]["lowerarm_r"] as Array).size() == 2 and is_equal_approx((r6["pk"]["lowerarm_r"][1]["v"] as Vector3).x, -5.0),
		"6 a two-key joint is left as it was (bar)")
	ok(String(r6["joint"]) == "upperarm_l", "6 the readout names the joint with the worst error: %s" % String(r6["joint"]))

	print("")
	print("ALL PASS" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
