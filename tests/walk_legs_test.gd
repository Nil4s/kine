## godot --headless --path . -s tests/walk_legs_test.gd     (round 42, Nick 10-17: "yes fix the steps too, make them real")
## walk_bat's steps were 0.30 m (0.176 of body height); people walk 0.415 +- 0.038 of it (PMID 19502061). At real length
## the legs broke: the swing knee snapped 1743 deg/s, the stance knee folded to 37 deg as the hips passed over the foot.
## Scene.gd's WALK playback (TOE-OFF, STANCE: the hips' height follows the stance leg, the feet BUILT on their marks) is
## measured here against PEOPLE on the full steps of walk_bat (cards 2-4), 120 fps:
##   mid-stance knee (stance foot under the hip)   people ~5-10 deg (Perry, Gait Analysis)          bar 3-12
##   swing knee peak                               people ~60-65 deg (Perry; Winter's normative)     bar 55-72
##   foot-ground angle at toe-off                  people 49.4 (3 km/h) - 68.5 (6 km/h), 60.3 +- 5.1 at 4.5
##                                                 (Eckelt et al. 2026, PMID 41583941)                bar >= 40
##   swing foot peak speed                         people ~4.4 m/s at 1.25 m/s walking               bar 3.5-5.5
##   fastest knee, every frame of the scene (30 fps)  people peak ~400-500 deg/s in swing           bar < 750
##   a standing foot (low and < 0.2 m/s) slides on its mark   bar < 5 mm (measured 3.1: the toe pivoting at lift-off;
##                                                 it was 51 before the WALK legs)
## CONTROL (anti-vacuity, every run): the same scene with its "walk" flags taken off must FAIL the stance-knee bar (it
## folds past 20 deg), so the bars are able to see the bug they guard.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func measure(S: Scene, B: Body) -> Dictionary:
	var ts := S.times()
	var t0: float = ts[2][0]
	var t1: float = ts[4][1]
	var fps := 120.0
	var d0: Vector3 = B.p0["ball_l"] - B.p0["foot_l"]
	var flat := rad_to_deg(atan2(-d0.y, Vector2(d0.x, d0.z).length()))
	var out := {"swing": 0.0, "mid": [], "toe_off": [], "vmax": 0.0, "slide": 0.0}
	var prev := {}
	var mark := {}
	var down0 := {}
	for k in int((t1 - t0) * fps) + 1:
		var t := t0 + k / fps
		S.apply(B, t)
		for sd in ["_l", "_r"]:
			var ball: Vector3 = B.P["ball" + sd]
			# on the floor: the toe base under 2.2 cm (the two marks sit at 1.6 and 2.0 cm)
			var down := ball.y < 0.022
			if down0.has(sd) and down0[sd] and not down:
				var v: Vector3 = ball - (B.P["foot" + sd] as Vector3)
				(out["toe_off"] as Array).append(rad_to_deg(atan2(-v.y, Vector2(v.x, v.z).length())) - flat)
			# standing = on the floor AND slow (mocap_clean's contact: < 0.2 m/s along the floor); the mark is where it stood
			# first, and a standing foot must stay within 3 mm of it
			var slow: bool = prev.has(sd) and Vector2(ball.x - prev[sd].x, ball.z - prev[sd].z).length() * fps < 0.2
			if down and slow:
				if not mark.has(sd):
					mark[sd] = ball
				out["slide"] = maxf(out["slide"], Vector2(ball.x - mark[sd].x, ball.z - mark[sd].z).length())
			elif not down:
				mark.erase(sd)
			if not down:
				out["swing"] = maxf(out["swing"], B.ang["calf" + sd].x)
				mark.erase(sd)
			down0[sd] = down
			if prev.has(sd):
				out["vmax"] = maxf(out["vmax"], ((ball - prev[sd]) as Vector3).length() * fps)
			prev[sd] = ball
			if down and absf((B.P["thigh" + sd] as Vector3).z - (B.P["foot" + sd] as Vector3).z) < 0.02:
				(out["mid"] as Array).append(B.ang["calf" + sd].x)
	# the fastest knee over the whole scene at 30 fps
	var kmax := 0.0
	var pk := {}
	for k in int(S.length() * 30.0) + 1:
		S.apply(B, k / 30.0)
		for sd in ["_l", "_r"]:
			var q: Quaternion = B.compose("calf" + sd, B.ang["calf" + sd])
			if pk.has(sd):
				kmax = maxf(kmax, rad_to_deg((pk[sd] as Quaternion).angle_to(q)) * 30.0)
			pk[sd] = q
	out["knee_rate"] = kmax
	return out


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json"))
	var S := Scene.new()
	S.from_dict(d)
	var n_walk := 0
	for c in S.cards:
		n_walk += 1 if bool(c.get("walk", false)) else 0
	ok(n_walk >= 5, "walk_bat has %d WALK cards (bar >= 5: the half step, three steps, the stop)" % n_walk)
	var m := measure(S, B)
	var mid: Array = m["mid"]
	var mmax: float = mid.max() if not mid.is_empty() else 99.0
	var mmin: float = mid.min() if not mid.is_empty() else -1.0
	ok(not mid.is_empty() and mmin >= 3.0 and mmax <= 12.0, "mid-stance knee %.1f..%.1f deg over %d frames (people ~5-10, Perry; bar 3-12)" % [mmin, mmax, mid.size()])
	ok(m["swing"] >= 55.0 and m["swing"] <= 72.0, "swing knee peak %.1f deg (people ~60-65; bar 55-72)" % m["swing"])
	var to: Array = m["toe_off"]
	ok(to.size() >= 3 and to.min() >= 40.0, "foot-ground angle at toe-off %s deg (people 49-68 by speed, 60.3 +- 5.1 at 4.5 km/h, PMID 41583941; bar >= 40)" % str(to.map(func(x): return snappedf(x, 0.1))))
	ok(m["vmax"] >= 3.5 and m["vmax"] <= 5.5, "swing foot peak %.2f m/s (people ~4.4 at 1.25 m/s; bar 3.5-5.5)" % m["vmax"])
	ok(m["knee_rate"] < 750.0, "fastest knee over the scene %.0f deg/s at 30 fps (people peak ~400-500 in swing; bar < 750; it was 1743)" % m["knee_rate"])
	ok(m["slide"] < 0.005, "a stance foot slides %.1f mm on its mark at most (bar < 5; it was 51)" % (m["slide"] * 1000.0))
	# CONTROL: the walk flags off -> the old playback; the stance-knee bar must see the fold
	var d2: Dictionary = d.duplicate(true)
	for c in d2["cards"]:
		(c as Dictionary).erase("walk")
	var S2 := Scene.new()
	S2.from_dict(d2)
	var m2 := measure(S2, B)
	var mid2: Array = m2["mid"]
	var m2max: float = mid2.max() if not mid2.is_empty() else 0.0
	ok(m2max > 20.0, "CONTROL: the same scene without its walk flags folds the stance knee to %.1f deg (bar > 20: the bars above can see the bug)" % m2max)
	print("WALK LEGS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
