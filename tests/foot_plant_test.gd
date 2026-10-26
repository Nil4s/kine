## godot --headless --path . -s tests/foot_plant_test.gd     (ROADMAP 8, docs/COMPLAINTS.md: foot sliding; scripts/foot_plant.gd)
## Bars, written before measuring:
##   the scene: a standing body (knees bent) whose pelvis moves 20 cm forward and back again over 5 s, the feet on the floor,
##   no pins: unplanted, both feet slide with it (ANTI-VACUITY: the rule FOOT SLIDE must fire on it).
##   1 PLANTED: both feet planted over [0.4, 5.9] s. On EVERY frame at 120 Hz in the range: the ankle, the heel, the ball
##     point each within 1 mm of where it was at t0 (the unplanted scene at t0), the foot's and the ball's world turn
##     within 0.1 deg of their t0 turn.
##   2 THE FOOT SLIDE RULE (Rulebook.rule_feet) does not fire on the planted scene; it fires on the unplanted one.
##   3 EDGES: the sole's largest per-frame step (120 Hz, ball point) in the 3-frame blend at each range edge is <= the
##     largest per-frame step of either sole in the unplanted scene (the scene's own largest step).
##   4 THE PELVIS IS NOT TOUCHED: the hips' offset is bit for bit the unplanted scene's on every frame.
##   5 REACH: no frame in the range misses its pin by more than FootPlant.MISS_BAR (1 mm); the reported worst miss prints.
##   6 MIRROR: the planted file mirrored has foot_r (and foot_l) with the same times; mirrored twice = the original file.
##   7 FILE ROUND TRIP: to_dict -> JSON -> from_dict keeps the plants (times to 0.1 ms) and plays the same frames (0.1 mm).
##   8 NO PLANTS: a scene without plants writes no "plants" key and plays the same frames as before the feature
##     (the same scene with the list cleared and re-read from its file).
##   9 ONE PLANT PER FOOT: FootPlant.add over an overlapping range takes the older plant off.
##  11 MOVING RELEASE (ROADMAP 8 fix): released at 2.0 s while the body is moving, the sole's largest step in the release
##     ramp (120 Hz) is <= the scene's own largest step; the ramp is FootPlant.out_frames (BLEND to OUT_MAX frames). The
##     numbers print; a release whose distance needs more than OUT_MAX frames cannot meet it and says so.
extends SceneTree

var fails := 0
## ankle pitched 25 deg: the ball of each foot is under the rule's 5 cm "down" bar (ball 4 cm, the toes on the floor)
const STANCE := {"thigh_l": Vector3(-6, 0, 0), "calf_l": Vector3(38, 0, 0), "foot_l": Vector3(25, 0, 0), "thigh_r": Vector3(-6, 0, 0), "calf_r": Vector3(38, 0, 0), "foot_r": Vector3(25, 0, 0)}
const HZ := 120
const T0 := 0.4
const T1 := 5.9


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(B: Body, angs: Dictionary, off: Vector3) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = off
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


## the slide scene: stand (rest 0.4 s), forward 20 cm (move 2.5 s, hold 0.2), back (move 2.5 s, hold 0.4): a slow creep
## (under the rule's 0.3 m/s settled bar) that adds up to 20 cm
func slide(B: Body) -> Scene:
	var S := Scene.new()
	S.fps = 30
	S.pin = false   # the feet are NOT pinned by the scene: the body's motion slides them
	S.on_floor = true
	S.add("stand", pose(B, STANCE, Vector3.ZERO))
	S.add("forward", pose(B, STANCE, Vector3(0.2, 0, 0)))
	S.add("back", pose(B, STANCE, Vector3.ZERO))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.4
	S.cards[1]["move"] = 2.5
	S.cards[1]["hold"] = 0.2
	S.cards[2]["move"] = 2.5
	S.cards[2]["hold"] = 0.4
	return S


func plants_both() -> Array:
	return [{"foot": "foot_l", "t0": T0, "t1": T1}, {"foot": "foot_r", "t0": T0, "t1": T1}]


func nframes(S: Scene) -> int:
	return int(ceilf(S.length() * HZ - 1e-6)) + 1


func tf(k: int) -> float:
	return float(k) / float(HZ)


## every frame at 120 Hz: the feet's points and turns, the hips' offset, the reports
func play(S: Scene, B: Body) -> Array:
	var out := []
	for k in nframes(S):
		var t := tf(k)
		S.apply(B, t)
		var row := {"t": t, "off": B.offset, "miss": 0.0}
		for sd in ["_l", "_r"]:
			row["ankle" + sd] = (B.P["foot" + sd] as Vector3)
			row["ball" + sd] = (B.P["ball" + sd] as Vector3)
			row["heel" + sd] = FootRoll.heel_point(B, sd)
			row["gf" + sd] = (B.G["foot" + sd] as Quaternion)
			row["gb" + sd] = (B.G["ball" + sd] as Quaternion)
		if not S.plant_last.is_empty():
			var worst := 0.0
			for i in S.plant_last:
				worst = maxf(worst, float(S.plant_last[i]["miss"]))
			row["miss"] = worst
		out.append(row)
	return out


func frame_of(rows: Array, t: float) -> Dictionary:
	return rows[int(roundf(t * HZ))]


func turn_deg(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg((a.inverse() * b).normalized().get_angle())


func largest_step(rows: Array, key: String) -> float:
	var m := 0.0
	for k in range(1, rows.size()):
		m = maxf(m, ((rows[k][key] as Vector3) - (rows[k - 1][key] as Vector3)).length())
	return m


func _init() -> void:
	var B := body()
	var B2 := body()
	var S0 := slide(B)
	var free := play(S0, B)
	var step_free := maxf(largest_step(free, "ball_l"), largest_step(free, "ball_r"))
	var excursion := 0.0   # the slide goes out and comes back: the largest distance from where it starts
	for row in free:
		excursion = maxf(excursion, ((row["ball_l"] as Vector3) - (free[0]["ball_l"] as Vector3)).length())
	print("unplanted: the left ball goes %.3f m from where it starts (out and back); its largest step %.2f mm per 120 Hz frame" % [excursion, step_free * 1000.0])

	var S1 := slide(B)
	S1.plants = FootPlant.from_file(plants_both())
	var rows := play(S1, B)

	# the references: where each sole was at t0 in the unplanted scene (frame HZ * T0)
	var r0 := frame_of(free, T0)
	var worst_p := {"ankle": 0.0, "heel": 0.0, "ball": 0.0, "turn": 0.0, "ball_turn": 0.0}
	var worst_at := ""
	for k in nframes(S1):
		var t := tf(k)
		if t < T0 - 1e-9 or t > T1 + 1e-9:
			continue
		var row: Dictionary = rows[k]
		for sd in ["_l", "_r"]:
			var e_a := ((row["ankle" + sd] as Vector3) - (r0["ankle" + sd] as Vector3)).length()
			var e_h := ((row["heel" + sd] as Vector3) - (r0["heel" + sd] as Vector3)).length()
			var e_b := ((row["ball" + sd] as Vector3) - (r0["ball" + sd] as Vector3)).length()
			var e_t := turn_deg(row["gf" + sd], r0["gf" + sd])
			var e_bt := turn_deg(row["gb" + sd], r0["gb" + sd])
			if e_a > worst_p["ankle"]:
				worst_at = "t=%.4f %s" % [t, sd]
			worst_p["ankle"] = maxf(worst_p["ankle"], e_a)
			worst_p["heel"] = maxf(worst_p["heel"], e_h)
			worst_p["ball"] = maxf(worst_p["ball"], e_b)
			worst_p["turn"] = maxf(worst_p["turn"], e_t)
			worst_p["ball_turn"] = maxf(worst_p["ball_turn"], e_bt)
	print("planted %.2f-%.2f s at 120 Hz, worst vs t0: ankle %.4f mm, heel %.4f mm, ball %.4f mm, foot turn %.4f deg, ball turn %.4f deg (ankle worst at %s)" % [T0, T1, worst_p["ankle"] * 1000.0, worst_p["heel"] * 1000.0, worst_p["ball"] * 1000.0, worst_p["turn"], worst_p["ball_turn"], worst_at])
	ok(worst_p["ankle"] <= 0.001 and worst_p["heel"] <= 0.001 and worst_p["ball"] <= 0.001, "1a the ankle, heel and ball within 1 mm of their t0 places on every frame of the range (worst %.4f mm)" % (maxf(worst_p["ankle"], maxf(worst_p["heel"], worst_p["ball"])) * 1000.0))
	ok(worst_p["turn"] <= 0.1 and worst_p["ball_turn"] <= 0.1, "1b the foot's and the ball's turn within 0.1 deg of t0 on every frame (worst %.4f, %.4f deg)" % [worst_p["turn"], worst_p["ball_turn"]])

	# 2 the rule
	var sm_p := Rulebook.sample(S1, B)
	var fire_p := Rulebook.rule_feet(sm_p)
	var fire_u := Rulebook.rule_feet(Rulebook.sample(S0, B))
	ok(fire_p.is_empty(), "2a FOOT SLIDE does not fire on the planted scene (%d findings)" % fire_p.size())
	ok(not fire_u.is_empty(), "2b ANTI-VACUITY: FOOT SLIDE fires on the unplanted scene (%d findings)" % fire_u.size())

	# 3 edges: the blend window at each edge, the sole's largest step there, against the scene's own largest step
	var blend := float(maxi(int(S1.plants[0].get("out", FootPlant.BLEND)), int(S1.plants[1].get("out", FootPlant.BLEND)))) / S1.fps
	var edge_step := 0.0
	for k in range(1, rows.size()):
		var t := tf(k)
		var near := (t >= T0 - blend - 1e-9 and t <= T0 + blend + 1e-9) or (t >= T1 - blend - 1e-9 and t <= T1 + blend + 1e-9)
		if not near:
			continue
		for sd in ["_l", "_r"]:
			edge_step = maxf(edge_step, ((rows[k]["ball" + sd] as Vector3) - (rows[k - 1]["ball" + sd] as Vector3)).length())
	print("edges: largest sole step in the release and entry ramps %.3f mm per frame; the scene's own largest step %.3f mm" % [edge_step * 1000.0, step_free * 1000.0])
	ok(edge_step <= step_free + 1e-9, "3 the edges move no more than the scene's own largest step (%.3f <= %.3f mm)" % [edge_step * 1000.0, step_free * 1000.0])

	# the release mid-slide (not barred): the plant ends while the body is still moving, so the foot must jump back to
	# where the free leg is. Its largest 3-frame step is what the animator sees at that release
	var S4 := slide(B)
	S4.plants = FootPlant.from_file([{"foot": "foot_l", "t0": T0, "t1": 2.0}, {"foot": "foot_r", "t0": T0, "t1": 2.0}])
	var rows4 := play(S4, B)
	var mid_step := 0.0
	var out4 := int(S4.plants[0].get("out", FootPlant.BLEND))
	var blend4 := float(out4) / S4.fps
	for k in range(1, rows4.size()):
		var t := tf(k)
		if t >= 2.0 - blend4 - 1e-9 and t <= 2.0 + blend4 + 1e-9:
			mid_step = maxf(mid_step, ((rows4[k]["ball_l"] as Vector3) - (rows4[k - 1]["ball_l"] as Vector3)).length())
	print("release MID-SLIDE at 2.0 s: the release ramp is %d frames (BLEND %d, cap %d); the left sole's largest step in it %.2f mm per 120 Hz frame, against the scene's own largest %.2f mm" % [out4, FootPlant.BLEND, FootPlant.OUT_MAX, mid_step * 1000.0, step_free * 1000.0])
	ok(mid_step <= step_free + 1e-9, "11 MOVING RELEASE at 2.0 s: the sole steps no more than the scene's own largest step in the ramp (%.2f <= %.2f mm, ramp %d frames%s)" % [mid_step * 1000.0, step_free * 1000.0, out4, ", CAPPED" if out4 >= FootPlant.OUT_MAX else ""])

	# 4 the pelvis
	var off_bad := 0.0
	for k in nframes(S1):
		off_bad = maxf(off_bad, ((rows[k]["off"] as Vector3) - (free[k]["off"] as Vector3)).length())
	ok(off_bad == 0.0, "4 the hips' offset is bit for bit the unplanted scene's on every frame (largest difference %f m)" % off_bad)

	# 5 reach
	var worst_miss := 0.0
	for k in nframes(S1):
		worst_miss = maxf(worst_miss, float(rows[k]["miss"]))
	print("reach: the worst ankle miss on any frame %.4f mm" % (worst_miss * 1000.0))
	ok(worst_miss <= FootPlant.MISS_BAR, "5 every planted frame reaches its pin within 1 mm (worst %.4f mm)" % (worst_miss * 1000.0))

	# 6 mirror
	var d := S1.to_dict(B)
	var md := Scene.mirror_file(d, B2)
	var mp: Array = md.get("plants", [])
	var ok_m: bool = mp.size() == 2 and mp[0]["foot"] == "foot_r" and mp[1]["foot"] == "foot_l" and absf(float(mp[0]["t0"]) - T0) < 1e-6
	var mmd := Scene.mirror_file(md, B2)
	ok(ok_m and JSON.stringify(mmd.get("plants", [])) == JSON.stringify(d.get("plants", [])), "6 mirror: foot_l <-> foot_r with the same times, mirrored twice = the file as it was (%s)" % JSON.stringify(mp))

	# 7 file round trip
	var js := JSON.stringify(d)
	var back := Scene.new()
	back.from_dict(JSON.parse_string(js))
	var same_list := JSON.stringify(FootPlant.to_file(back.plants)) == JSON.stringify(FootPlant.to_file(S1.plants))
	var rows_b := play(back, B2)
	var dev := 0.0
	for k in rows.size():
		dev = maxf(dev, ((rows_b[k]["ankle_l"] as Vector3) - (rows[k]["ankle_l"] as Vector3)).length())
		dev = maxf(dev, ((rows_b[k]["ankle_r"] as Vector3) - (rows[k]["ankle_r"] as Vector3)).length())
	ok(same_list and dev <= 0.0001, "7 file round trip: the plants come back (%d) and the feet play within 0.1 mm (largest %.4f mm)" % [back.plants.size(), dev * 1000.0])

	# 8 no plants: the key is not written and the frames are the unplanted ones
	var d0 := S0.to_dict(B)
	var none_key := not d0.has("plants")
	var S2 := slide(B)
	S2.plants = []
	var rows_n := play(S2, B)
	var same_n := true
	for k in rows_n.size():
		if (rows_n[k]["ankle_l"] as Vector3) != (free[k]["ankle_l"] as Vector3) or (rows_n[k]["off"] as Vector3) != (free[k]["off"] as Vector3):
			same_n = false
	ok(none_key and same_n, "8 a scene without plants writes no \"plants\" key and plays the unplanted frames bit for bit")

	# 9 one plant per foot
	var lst := FootPlant.add([{"foot": "foot_l", "t0": 0.5, "t1": 1.0}, {"foot": "foot_r", "t0": 0.5, "t1": 1.0}], {"foot": "foot_l", "t0": 0.8, "t1": 1.5})
	ok(lst.size() == 2 and float(lst[0]["t1"]) == 1.0 and float(lst[-1]["t1"]) == 1.5, "9 a new plant takes the overlapping plant of the same foot off and keeps the other foot's")

	# the unplanted-right-foot control: only the left foot planted, the right still slides
	var S3 := slide(B)
	S3.plants = FootPlant.from_file([{"foot": "foot_l", "t0": T0, "t1": T1}])
	var fire_1 := Rulebook.rule_feet(Rulebook.sample(S3, B))
	var only_r := true
	for f in fire_1:
		if String(f.get("foot", "")) != "_r":
			only_r = false
	ok(not fire_1.is_empty() and only_r, "10 with only the left foot planted, FOOT SLIDE fires on the right foot alone (%d findings)" % fire_1.size())

	print("FOOT PLANT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
