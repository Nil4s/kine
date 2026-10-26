## godot --headless --path . -s tests/walk_people_test.gd     (round 44, GATES ZZ0 + ZZ1)
## WALK_BAT AGAINST REAL WALKERS. The steady steps (the three 0.70 m steps; the half step and the stop are not steady)
## measured against people, at the walk's own speed (0.70 m / 0.57 s = 1.23 m/s, 4.42 km/h):
##   ZZ0 1 the pelvis's rise and fall: people's centre of mass 2.74 +- 0.52 cm at 0.7 m/s, 4.83 +- 0.92 at 1.6
##         (Orendurff et al. 2004, PMID 15685471, 10 adults), interpolated at the walk's speed; bar: within 2 SD
##       2 the knees (Fukuchi 2018 band, refs/gait_band.json): each knee's share outside 2 SD at most 25 % (half the 51 %
##         before), and 40-52 % of the cycle (late stance, people 4-8 deg) inside 2 SD at every point
##   ZZ1 3 every steady landing is HEEL FIRST: the heel (the point under the ankle) is down before the ball, by at least
##         one 120 Hz frame
##       4 the foot-ground angle at heel strike: people 22.7 +- 3.7 deg at 4.5 km/h, 17.1 +- 3.7 at 3 (Eckelt et al. 2026,
##         PMID 41583941, 49 adults), interpolated at the walk's speed; bar: within 2 SD
##       5 the ankle at initial contact (the band's 0 %) within people's 2 SD (1.5 +- 3.1 deg; it was -20, the foot flat)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var ts := S.times()
	# the steady steps: cards 2, 3, 4 (each 0.70 m); the walk's speed from their marks and times
	var t0: float = ts[2][0]
	var t1: float = ts[4][1]
	var step := 0.70
	var v := step / (float(ts[3][1]) - float(ts[3][0]))
	var kmh := v * 3.6
	# 1 the pelvis's rise and fall over the steady steps (120 Hz)
	var lo := INF
	var hi := -INF
	for k in int((t1 - t0) * 120.0) + 1:
		S.apply(B, t0 + k / 120.0)
		var y: float = (B.P["pelvis"] as Vector3).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var f := clampf((v - 0.7) / 0.9, 0.0, 1.0)
	var m := lerpf(2.74, 4.83, f)
	var sd := lerpf(0.52, 0.92, f)
	var ex := (hi - lo) * 100.0
	ok(absf(ex - m) <= 2.0 * sd, "1 the pelvis rises and falls %.2f cm over the steady steps at %.2f m/s (people %.2f +- %.2f, Orendurff 2004; bar within 2 SD; it was 6.2)" % [ex, v, m, sd])
	# 2 the knees against the band
	var knees := []
	var late_ok := true
	for part in ["calf_r", "calf_l"]:
		var b := GaitBand.for_part(S, part)
		if not b["ok"]:
			late_ok = false
			knees.append("%s: %s" % [part, b.get("why", "?")])
			continue
		for i in range(40, 53):
			late_ok = late_ok and absf(float(b["you"][i]) - float(b["mean"][i])) <= 2.0 * float(b["sd"][i])
		knees.append(b["out"])
	ok(knees.size() == 2 and knees[0] is float and knees[1] is float and knees[0] <= 0.25 and knees[1] <= 0.25 and late_ok,
		"2 knees outside people's 2 SD: right %s, left %s of the cycle (bar <= 0.25; right was 0.51); 40-52 %% inside at every point %s" % [knees[0] if knees.size() > 0 else "?", knees[1] if knees.size() > 1 else "?", late_ok])
	# 3-5 the steady landings: cards 2, 3, 4, the stepping foot of each
	var d0: Vector3 = B.p0["ball_l"] - B.p0["foot_l"]
	var flat := rad_to_deg(atan2(-d0.y, Vector2(d0.x, d0.z).length()))
	var heel_first := true
	var fga := []
	var ank := []
	var lead := []
	var fm := lerpf(17.1, 22.7, clampf((kmh - 3.0) / 1.5, 0.0, 1.0))
	for i in [2, 3, 4]:
		var side: String = "_l" if (S.cards[i].get("steps", {}) as Dictionary).has("_l") else "_r"
		var heel_t := -1.0
		var ball_t := -1.0
		var a := 0.0
		var k := 0
		var ta: float = ts[i][0]
		while ta + k / 120.0 <= float(ts[i][1]) + 0.05:
			var t := ta + k / 120.0
			S.apply(B, t)
			var hy: float = (B.P["foot" + side] as Vector3).y - (B.p0["foot" + side] as Vector3).y
			var by: float = (B.P["ball" + side] as Vector3).y - (B.p0["ball" + side] as Vector3).y
			if heel_t < 0.0 and t > ta + 0.3 and hy <= GaitBand.HEEL_DOWN:
				heel_t = t
				var w: Vector3 = (B.P["ball" + side] as Vector3) - (B.P["foot" + side] as Vector3)
				a = flat - rad_to_deg(atan2(-w.y, Vector2(w.x, w.z).length()))   # toes up = positive
			if ball_t < 0.0 and t > ta + 0.3 and by <= GaitBand.HEEL_DOWN:
				ball_t = t
			k += 1
		heel_first = heel_first and heel_t > 0.0 and ball_t > 0.0 and ball_t - heel_t >= 1.0 / 120.0 - 1e-6
		lead.append("%s heel %.3f ball %.3f" % [side, heel_t, ball_t])
		fga.append(snappedf(a, 0.1))
		S.apply(B, heel_t)
		ank.append(snappedf(GaitBand.flex(B, side).z, 0.1))
	ok(heel_first, "3 every steady landing heel first: %s" % ", ".join(lead))
	ok(fga.all(func(x): return absf(x - fm) <= 2.0 * 3.7), "4 foot-ground angle at heel strike %s deg (people %.1f +- 3.7 at %.2f km/h, Eckelt 2026; bar within 2 SD)" % [fga, fm, kmh])
	var am: float = GaitBand.table()["joints"]["ankle"]["mean"][0]
	var asd: float = GaitBand.table()["joints"]["ankle"]["sd"][0]
	ok(ank.all(func(x): return absf(x - am) <= 2.0 * asd), "5 the ankle at initial contact %s deg (people %.1f +- %.1f; bar within 2 SD; it was -20, the foot landing flat)" % [ank, am, asd])
	print("WALK PEOPLE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
